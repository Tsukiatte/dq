--[[
    probe.lua - standalone attack probe for the Dungeon Autofarm rewrite
    (HANDOFF.md section 4). It is NOT the bot: it moves nothing and presses
    nothing. Load it, play the room yourself (or with any bot), and it writes
    a text file every five seconds and on every hit.

    What it records
      ATTACK MODELS  every Model under workspace with a hitBox and/or precast
                     child, tracked from workspace.ChildAdded for its whole
                     life at 20 Hz: sizes, precast transparency at spawn, every
                     change of that transparency with its age, the ages during
                     which the character's root was INSIDE the hitBox, removal.
      PARTS          every BasePart parented straight to workspace (the boss
                     projectiles are MeshParts: firstBossCrissCross,
                     firstBossSeekingSpikes, firstBossBigSpike): transparency
                     trace, first movement, ages within its radius, and the
                     remote event that made it when one matches.
      HITS           every drop of Humanoid.Health: age, damage, what enclosed
                     the root at that instant, what was within 15 studs, the
                     live projectiles with their scripted position, the enemies
                     within 25 studs, whether a stun marker was on you.
      EVENTS         every boss remote event with its arguments; timestamps are
                     shown relative to the game's clock at the event (t+0.50
                     means it fires half a second after the event arrived).

    Load (Potassium):
      loadstring(game:HttpGet("https://raw.githubusercontent.com/Tsukiatte/dq/main/probe.lua?t=" .. tick()))()
    Stop:   getgenv().DQProbe.stop()      Force a write: getgenv().DQProbe.save()
    File:   <executor workspace>/DQProbe_<map>_<MMDD_HHMMSS>.txt
    Without writefile (Studio) the report stays in memory: _G.DQProbe.report().
]]

local PROBE_VERSION = "0.1"
local SAMPLE_DT = 0.05        -- 20 Hz sampling
local WRITE_EVERY = 5         -- seconds between file writes
local NEAR = 15               -- studs: an attack this close to a hit is listed as "near"
local ENEMY_NEAR = 25         -- studs: enemies this close to a hit are listed
local MAX_TRACE = 60          -- transparency changes kept per record
local MAX_SPANS = 40          -- inside spans kept per record
local MAX_RECORDS = 900       -- records kept; the oldest quiet ones go first
local CANDIDATE_GRACE = 2     -- s a new Model may wait for its hitBox/precast
local BUCKET = 0.25           -- s: age buckets of the per-name summary
local MAX_BUCKET_AGE = 12     -- s: ages beyond this lump into the last bucket

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer

local G = (type(getgenv) == "function" and getgenv()) or _G
if type(G.DQProbe) == "table" and type(G.DQProbe.stop) == "function" then pcall(G.DQProbe.stop) end

local fmt = string.format
local t0 = os.clock()
local function age() return os.clock() - t0 end
local function v3(v) return fmt("(%.0f,%.0f,%.0f)", v.X, v.Y, v.Z) end
local function sz(v) return fmt("%.1fx%.1fx%.1f", v.X, v.Y, v.Z) end
local function num(x, d) return x and fmt("%." .. (d or 2) .. "f", x) or "-" end

-- The game's clock: ReplicatedStorage.timeSync (a SlaveClock; GetTime() is the
-- server's tick()). Boss events carry their times on it.
local timeSync
pcall(function()
    local m = ReplicatedStorage:FindFirstChild("timeSync")
    if m then timeSync = require(m) end
end)
local function gameTime()
    if timeSync then
        local ok, t = pcall(function() return timeSync:GetTime() end)
        if ok and type(t) == "number" then return t end
    end
    return workspace:GetServerTimeNow()
end

local mapName = "nomap"
pcall(function()
    local v = workspace:FindFirstChild("dungeonName")
    if v and v.Value ~= "" then mapName = v.Value end
end)
local fileName = fmt("DQProbe_%s_%s.txt", (mapName:gsub("[^%w]", "")), os.date("%m%d_%H%M%S"))
local canWrite = type(writefile) == "function"

-- ------------------------------------------------------------------ state
local attacks, parts, candidates = {}, {}, {}   -- live records by instance
local order = {}                                 -- every record, spawn order
local hits, events, log = {}, {}, {}
local enemies = {}
local deaths = 0
local root, humanoid, lastHealth
local connections = {}
local dirty, stopped = false, false

-- Per-name summary: seconds the root spent inside at each age (no hit) and
-- hits at each age. The hurt window of an attack is where the hits are; ages
-- with lots of inside time and no hits are floor.
local stats = {}
local function statFor(name, kind)
    local st = stats[name]
    if not st then
        st = { n = 0, inside = {}, hits = {}, kind = kind }
        stats[name] = st
    end
    return st
end
local function bucketOf(a)
    if a > MAX_BUCKET_AGE then a = MAX_BUCKET_AGE end
    return math.floor(a / BUCKET)
end
local function insideTime(rec, a, step)
    local st = statFor(rec.name, rec.kind)
    local b = bucketOf(a)
    st.inside[b] = (st.inside[b] or 0) + step
end
local function hitAt(rec, a)
    local st = statFor(rec.name, rec.kind)
    local b = bucketOf(a)
    st.hits[b] = (st.hits[b] or 0) + 1
    rec.hitAges[#rec.hitAges + 1] = fmt("%.2f", a)
end

local function note(s)
    log[#log + 1] = fmt("%8.2f  %s", age(), s)
    dirty = true
end

-- ------------------------------------------------------------------ geometry
-- Distance from a point to an oriented box; 0 when the point is inside.
local function boxDistance(part, p)
    local l = part.CFrame:PointToObjectSpace(p)
    local s = part.Size
    local dx = math.max(math.abs(l.X) - s.X * 0.5, 0)
    local dy = math.max(math.abs(l.Y) - s.Y * 0.5, 0)
    local dz = math.max(math.abs(l.Z) - s.Z * 0.5, 0)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end
local function partRadius(part)
    local s = part.Size
    return math.max(s.X, s.Y, s.Z) * 0.5
end

-- ------------------------------------------------------------------ records
local function prune()
    if #order <= MAX_RECORDS then return end
    local kept, dropped = {}, 0
    for _, rec in ipairs(order) do
        if dropped < 100 and rec.removed and #rec.hitAges == 0 and #rec.spans == 0 then
            dropped = dropped + 1
        else
            kept[#kept + 1] = rec
        end
    end
    order = kept
end

local function newRecord(kind, inst, pre, spawn)
    local rec = {
        kind = kind, inst = inst, name = inst.Name, spawn = spawn or age(), pre = pre,
        trace = {}, spans = {}, hitAges = {}, minT = 2, inside = false,
    }
    order[#order + 1] = rec
    local st = statFor(rec.name, kind)
    st.n = st.n + 1
    prune()
    return rec
end

local function pushTrace(rec, a, t)
    local n = #rec.trace
    if n < MAX_TRACE then rec.trace[n + 1] = fmt("%.2f:%.2f", a, t)
    elseif n == MAX_TRACE then rec.trace[n + 1] = "..." end
end
local function sampleTransparency(rec, part, a)
    local t = part.Transparency
    if rec.lastT == nil or math.abs(t - rec.lastT) >= 0.02 then
        pushTrace(rec, a, t)
        rec.lastT = t
    end
    if t < rec.minT then rec.minT = t end
    if not rec.visAt and t < 0.97 then rec.visAt = a end
    if rec.visAt and not rec.fadeAt and t >= 0.97 then rec.fadeAt = a end
end
local function sampleInside(rec, inside, a)
    if inside and not rec.inside then
        rec.inside, rec.insideAt = true, a
    elseif rec.inside and not inside then
        rec.inside, rec.leftAt = false, a
        if #rec.spans < MAX_SPANS then rec.spans[#rec.spans + 1] = fmt("%.2f-%.2f", rec.insideAt, a) end
    end
end
local function closeRecord(rec, a)
    if rec.inside then sampleInside(rec, false, a) end
    rec.removed = a
end

local function adoptParts(rec, model)
    if not rec.hb then
        local hb = model:FindFirstChild("hitBox")
        if hb and hb:IsA("BasePart") then
            rec.hb = hb
            rec.hbInfo = fmt("%s tr%.2f touch=%s", sz(hb.Size), hb.Transparency, tostring(hb.CanTouch))
        end
    end
    if not rec.pc then
        local pc = model:FindFirstChild("precast")
        if pc and pc:IsA("BasePart") then
            rec.pc = pc
            local shape = ""
            pcall(function() if pc:IsA("Part") then shape = " " .. pc.Shape.Name end end)
            rec.pcSize = sz(pc.Size) .. shape
            rec.pcT0 = pc.Transparency
        end
    end
end

local function sampleModel(model, rec, now, p, step)
    local a = now - rec.spawn
    if not model.Parent then
        closeRecord(rec, a)
        attacks[model] = nil
        return
    end
    adoptParts(rec, model)
    if rec.pc then sampleTransparency(rec, rec.pc, a) end
    local box = rec.hb or rec.pc
    if box and p then
        if not rec.at then
            rec.at = box.Position
            rec.distAt = boxDistance(box, p)
        end
        local inside = boxDistance(box, p) <= 0
        sampleInside(rec, inside, a)
        if inside then insideTime(rec, a, step) end
    end
end

local function samplePart(part, rec, now, p, step)
    local a = now - rec.spawn
    if not part.Parent then
        closeRecord(rec, a)
        parts[part] = nil
        return
    end
    sampleTransparency(rec, part, a)
    local pos = part.Position
    if not rec.movedAt and (pos - rec.at).Magnitude > 1 then rec.movedAt = a end
    if p then
        local inside = (pos - p).Magnitude <= rec.radius
        sampleInside(rec, inside, a)
        if inside then insideTime(rec, a, step) end
    end
end

-- ------------------------------------------------------------------ events
local function describe(v, gnow)
    local ty = typeof(v)
    if ty == "CFrame" then
        local l = v.LookVector
        return fmt("cf%s look(%.2f,%.2f,%.2f)", v3(v.Position), l.X, l.Y, l.Z)
    elseif ty == "Vector3" then return "v" .. v3(v)
    elseif ty == "number" then
        if v > 1e8 then return fmt("t%+.2f", v - gnow) end
        return fmt("%.2f", v)
    elseif ty == "Instance" then return v.ClassName .. ":" .. v.Name
    elseif ty == "table" then
        local out = {}
        for _, x in ipairs(v) do out[#out + 1] = describe(x, gnow) end
        for k, x in pairs(v) do
            if type(k) ~= "number" then out[#out + 1] = tostring(k) .. "=" .. describe(x, gnow) end
        end
        return "{" .. table.concat(out, ", ") .. "}"
    end
    return tostring(v)
end

local function onEvent(remoteName, ...)
    local n = select("#", ...)
    local args = { ... }
    local gnow = gameTime()
    local ev = { age = age(), remote = remoteName, name = tostring(args[1]), gnow = gnow, text = "" }
    local rest = {}
    for i = 2, n do rest[#rest + 1] = describe(args[i], gnow) end
    ev.text = table.concat(rest, " ")
    -- Timed projectile shape: {distance, duration, startTime, endTime, cframe}.
    local a = args[2]
    if type(a) == "table" and typeof(a[5]) == "CFrame" and type(a[1]) == "number" and type(a[3]) == "number" then
        ev.dist, ev.dur, ev.start, ev.stop, ev.cf = a[1], a[2], a[3], a[4], a[5]
        if root and root.Parent then ev.originDist = (a[5].Position - root.Position).Magnitude end
    end
    events[#events + 1] = ev
    dirty = true
end

local function linkEvent(rec)
    local now = age()
    for i = #events, math.max(1, #events - 12), -1 do
        local ev = events[i]
        if now - ev.age > 0.5 then break end
        if ev.cf and (ev.cf.Position - rec.at).Magnitude <= 3 then
            rec.ev = ev
            return
        end
    end
end

local function projPredict(ev, gnow)
    local k = (gnow - ev.start) / ev.dur
    if k < 0 then k = 0 elseif k > 1 then k = 1 end
    return ev.cf.Position + ev.cf.LookVector * (k * ev.dist), k
end

-- ------------------------------------------------------------------ workspace watch
local function onChildAdded(child)
    if stopped then return end
    if child:IsA("Model") then
        if child:FindFirstChildOfClass("Humanoid") then return end
        candidates[child] = age()
    elseif child:IsA("BasePart") then
        if partRadius(child) < 1.5 then return end
        local rec = newRecord("part", child, false)
        rec.at = child.Position
        rec.radius = partRadius(child)
        rec.distAt = (root and root.Parent) and (child.Position - root.Position).Magnitude or -1
        rec.hbInfo = fmt("%s %s", child.ClassName, sz(child.Size))
        rec.pcT0 = child.Transparency
        linkEvent(rec)
        parts[child] = rec
    end
end

local function promoteCandidates(now)
    for model, since in pairs(candidates) do
        if not model.Parent then
            candidates[model] = nil
        elseif model:FindFirstChild("hitBox") or model:FindFirstChild("precast") then
            candidates[model] = nil
            attacks[model] = newRecord("model", model, false, since)
        elseif now - since > CANDIDATE_GRACE then
            candidates[model] = nil
        end
    end
end

local function scanEnemies()
    local list, folders = {}, {}
    local dungeon = workspace:FindFirstChild("dungeon")
    if dungeon then
        for _, room in ipairs(dungeon:GetChildren()) do
            local ef = room:FindFirstChild("enemyFolder")
            if ef then folders[#folders + 1] = ef end
        end
    end
    local en = workspace:FindFirstChild("enemies")
    if en then folders[#folders + 1] = en end
    for _, f in ipairs(folders) do
        for _, m in ipairs(f:GetChildren()) do
            if m:IsA("Model") then
                local hum = m:FindFirstChildOfClass("Humanoid")
                local r = m:FindFirstChild("HumanoidRootPart")
                if hum and r and hum.Health > 0 then
                    local md, st = m:FindFirstChild("meleeDistance"), m:FindFirstChild("enemyStyle")
                    list[#list + 1] = { root = r, name = m.Name, melee = md and md.Value or "?", style = st and st.Value or "?" }
                end
            end
        end
    end
    enemies = list
end

-- ------------------------------------------------------------------ hits
local function onHealthChanged(h)
    local last = lastHealth
    lastHealth = h
    if not last or h >= last then return end
    local now = age()
    local p = (root and root.Parent) and root.Position or nil
    local hit = { age = now, dmg = last - h, hp = h, pos = p, enclosing = {}, near = {}, proj = {}, enemies = {} }
    local stun = workspace:FindFirstChild("stunParts")
    hit.stun = stun ~= nil and stun:FindFirstChild(player.Name) ~= nil
    if p then
        for _, rec in pairs(attacks) do
            local box = rec.hb or rec.pc
            if box then
                local d = boxDistance(box, p)
                local a = now - rec.spawn
                local left = (not rec.inside and rec.leftAt and (a - rec.leftAt) < 0.5) and fmt(" (left %.2fs ago)", a - rec.leftAt) or ""
                local line = fmt("%s age=%.2f tr=%s dist=%.1f via %s%s", rec.name, a,
                    rec.pc and fmt("%.2f", rec.pc.Transparency) or "-", d, rec.hb and "hitBox" or "precast", left)
                if d <= 0 then
                    hit.enclosing[#hit.enclosing + 1] = line
                    hitAt(rec, a)
                elseif d <= NEAR then
                    hit.near[#hit.near + 1] = line
                end
            end
        end
        local gnow = gameTime()
        for part, rec in pairs(parts) do
            local d = (part.Position - p).Magnitude
            if d <= NEAR + rec.radius then
                local a = now - rec.spawn
                local extra = ""
                if rec.ev then
                    local pp, k = projPredict(rec.ev, gnow)
                    extra = fmt(" path k=%.2f predDist=%.1f start%+.2f end%+.2f", k, (pp - p).Magnitude, rec.ev.start - gnow, rec.ev.stop - gnow)
                end
                hit.proj[#hit.proj + 1] = fmt("%s age=%.2f dist=%.1f r=%.1f tr=%.2f%s%s", rec.name, a, d, rec.radius, part.Transparency,
                    d <= rec.radius and " INSIDE" or "", extra)
                if d <= rec.radius then hitAt(rec, a) end
            end
        end
        for _, e in ipairs(enemies) do
            if e.root.Parent then
                local d = (e.root.Position - p).Magnitude
                if d <= ENEMY_NEAR then
                    hit.enemies[#hit.enemies + 1] = fmt("%s dist=%.1f melee=%s style=%s", e.name, d, tostring(e.melee), tostring(e.style))
                end
            end
        end
    end
    hits[#hits + 1] = hit
    dirty = true
end

local function bindCharacter(char)
    task.spawn(function()
        local r = char:WaitForChild("HumanoidRootPart", 10)
        local hum = char:WaitForChild("Humanoid", 10)
        if not r or not hum or stopped then return end
        root, humanoid = r, hum
        lastHealth = hum.Health
        connections[#connections + 1] = hum.HealthChanged:Connect(onHealthChanged)
        connections[#connections + 1] = hum.Died:Connect(function()
            deaths = deaths + 1
            note(fmt("DIED #%d at %s", deaths, root and root.Parent and v3(root.Position) or "?"))
        end)
        note(fmt("character bound  hp=%.0f/%.0f  pos=%s", hum.Health, hum.MaxHealth, v3(r.Position)))
    end)
end

-- ------------------------------------------------------------------ report
local function modelLine(rec)
    local spans = table.concat(rec.spans, " ")
    if rec.inside then spans = spans .. (spans ~= "" and " " or "") .. fmt("%.2f-now", rec.insideAt) end
    return fmt("%-26s @%7.2f%s dist=%5.1f  hb=%s  pc=%s tr0=%s vis@%s fade@%s rm@%s  trace=[%s]  inside=[%s]  HIT@[%s]",
        rec.name, rec.spawn, rec.pre and "*" or " ", rec.distAt or -1, rec.hbInfo or "none", rec.pcSize or "none",
        num(rec.pcT0), num(rec.visAt), num(rec.fadeAt), rec.removed and num(rec.removed) or "live",
        table.concat(rec.trace, " "), spans, table.concat(rec.hitAges, " "))
end

local function partLine(rec)
    local spans = table.concat(rec.spans, " ")
    if rec.inside then spans = spans .. (spans ~= "" and " " or "") .. fmt("%.2f-now", rec.insideAt) end
    local ev = ""
    if rec.ev then
        ev = fmt("  event=%s dist=%.0f dur=%.2f start%+.2f end%+.2f", rec.ev.name, rec.ev.dist, rec.ev.dur,
            rec.ev.start - rec.ev.gnow, rec.ev.stop - rec.ev.gnow)
    end
    return fmt("%-26s @%7.2f  %s r=%.1f at%s dist=%5.1f tr0=%s moved@%s rm@%s  trace=[%s]  within=[%s]  HIT@[%s]%s",
        rec.name, rec.spawn, rec.hbInfo, rec.radius, v3(rec.at), rec.distAt or -1, num(rec.pcT0), num(rec.movedAt),
        rec.removed and num(rec.removed) or "live", table.concat(rec.trace, " "), spans, table.concat(rec.hitAges, " "), ev)
end

local function report()
    local out = {}
    local function w(s) out[#out + 1] = s end
    local live, models, partCount = 0, 0, 0
    for _ in pairs(attacks) do live = live + 1 end
    for _, rec in ipairs(order) do if rec.kind == "model" then models = models + 1 else partCount = partCount + 1 end end
    local synced = "absent"
    if timeSync then
        local ok, s = pcall(function() return timeSync:IsSynced() end)
        synced = ok and tostring(s) or "?"
    end
    w(fmt("DQ attack probe v%s  map=%s  player=%s  started %s  age %.1fs  file=%s", PROBE_VERSION, mapName, player.Name,
        os.date("%Y-%m-%d %H:%M:%S", os.time() - math.floor(age())), age(), canWrite and fileName or "(memory)"))
    w(fmt("clocks: timeSync %s, timeSync-serverNow=%+.3f s   hits=%d deaths=%d  attack models=%d (live %d)  parts=%d  events=%d",
        synced, gameTime() - workspace:GetServerTimeNow(), #hits, deaths, models, live, partCount, #events))
    w("Ages are seconds since the probe started (spawn) or since the record appeared (age). A hit's age is when HealthChanged reached this client;")
    w("the server judged it a network delay (~0.05-0.15 s) earlier. * after a spawn age = the Model existed before the probe started.")
    w("")
    w("SUMMARY by name - n records; precast first visible / fades / Model removed (min..max age over records);")
    w("  inside@age=s: seconds the root spent inside at that age (0.25 s buckets); HIT@age=n: hits while inside at that age.")
    w("  The hurt window is where the HITs are; ages with inside time and no HITs are floor.")
    local names = {}
    for name in pairs(stats) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do
        local st = stats[name]
        local visMin, visMax, fadeMin, fadeMax, rmMin, rmMax
        for _, rec in ipairs(order) do
            if rec.name == name then
                if rec.visAt then visMin = math.min(visMin or rec.visAt, rec.visAt) visMax = math.max(visMax or rec.visAt, rec.visAt) end
                if rec.fadeAt then fadeMin = math.min(fadeMin or rec.fadeAt, rec.fadeAt) fadeMax = math.max(fadeMax or rec.fadeAt, rec.fadeAt) end
                if rec.removed then rmMin = math.min(rmMin or rec.removed, rec.removed) rmMax = math.max(rmMax or rec.removed, rec.removed) end
            end
        end
        local function range(lo, hi) return lo and fmt("%.2f..%.2f", lo, hi) or "-" end
        local ins, hs, totalIn, totalHits = {}, {}, 0, 0
        for b = 0, bucketOf(MAX_BUCKET_AGE) do
            if st.inside[b] then ins[#ins + 1] = fmt("%.2f=%.1f", b * BUCKET, st.inside[b]) totalIn = totalIn + st.inside[b] end
            if st.hits[b] then hs[#hs + 1] = fmt("%.2f=%d", b * BUCKET, st.hits[b]) totalHits = totalHits + st.hits[b] end
        end
        w(fmt("%-26s n=%-3d vis@%s fade@%s rm@%s  inside %.1fs [%s]  HITS %d [%s]", name, st.n, range(visMin, visMax), range(fadeMin, fadeMax), range(rmMin, rmMax),
            totalIn, table.concat(ins, " "), totalHits, table.concat(hs, " ")))
    end
    w("")
    w("HITS - what enclosed the root when health dropped")
    for i, h in ipairs(hits) do
        w(fmt("HIT #%d  age=%.2f  dmg=%.0f  hp=%.0f  pos=%s%s", i, h.age, h.dmg, h.hp, h.pos and v3(h.pos) or "?", h.stun and "  STUNNED" or ""))
        for _, s in ipairs(h.enclosing) do w("    ENCLOSING " .. s) end
        for _, s in ipairs(h.proj) do w("    PART " .. s) end
        for _, s in ipairs(h.near) do w("    near " .. s) end
        for _, s in ipairs(h.enemies) do w("    enemy " .. s) end
        if #h.enclosing == 0 and #h.proj == 0 then w("    (nothing enclosing; see near/enemy lines - or an attack this probe does not track)") end
    end
    w("")
    w("ATTACK MODELS - spawn age, distance at spawn, hitBox, precast (size, transparency at spawn, first visible age, fade age), removal age,")
    w("  trace=[age:transparency on every change], inside=[age spans the root was inside the hitBox], HIT@[ages of hits while inside]")
    for _, rec in ipairs(order) do if rec.kind == "model" then w(modelLine(rec)) end end
    w("")
    w("PARTS - BaseParts parented straight to workspace: class+size, radius, spawn pos, first moved age, trace, within=[age spans inside the radius], linked event")
    for _, rec in ipairs(order) do if rec.kind == "part" then w(partLine(rec)) end end
    w("")
    w("EVENTS - boss remote events; t+1.20 = a time 1.2 s after the event on the game's clock; originDist = root to the event's cframe")
    for _, ev in ipairs(events) do
        w(fmt("@%7.2f  %s  %s  %s%s", ev.age, ev.remote, ev.name, ev.text, ev.originDist and fmt("  originDist=%.1f", ev.originDist) or ""))
    end
    w("")
    w("LOG")
    for _, s in ipairs(log) do w(s) end
    return table.concat(out, "\n")
end

local lastWriteErr
local function save()
    dirty = false
    if not canWrite then return end
    local ok, err = pcall(function() writefile(fileName, report()) end)
    if not ok and tostring(err) ~= lastWriteErr then
        lastWriteErr = tostring(err)
        log[#log + 1] = fmt("%8.2f  writefile failed: %s", age(), lastWriteErr)
    end
end

-- ------------------------------------------------------------------ HUD
local gui, label
local function buildHud()
    pcall(function()
        gui = Instance.new("ScreenGui")
        gui.Name = "DQProbeGui"
        gui.ResetOnSpawn = false
        gui.IgnoreGuiInset = true
        label = Instance.new("TextLabel")
        label.BackgroundColor3 = Color3.new(0, 0, 0)
        label.BackgroundTransparency = 0.35
        label.TextColor3 = Color3.new(1, 1, 1)
        label.Font = Enum.Font.Code
        label.TextSize = 14
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.Size = UDim2.new(0, 640, 0, 22)
        label.Position = UDim2.new(0, 8, 0, 44)
        label.Parent = gui
        local parent
        pcall(function() if type(gethui) == "function" then parent = gethui() end end)
        if not parent then pcall(function() parent = game:GetService("CoreGui") end) end
        local ok = parent and pcall(function() gui.Parent = parent end)
        if not ok then gui.Parent = player:WaitForChild("PlayerGui") end
    end)
end
local function updateHud()
    if not gui or not gui.Parent then buildHud() end
    if not label then return end
    local live, partsLive = 0, 0
    for _ in pairs(attacks) do live = live + 1 end
    for _ in pairs(parts) do partsLive = partsLive + 1 end
    label.Text = fmt(" DQ probe %s | %s | attacks %d (live %d) | parts %d | hits %d | deaths %d | events %d | %s",
        PROBE_VERSION, mapName, #order, live, partsLive, #hits, deaths, #events,
        canWrite and fileName or "no writefile: report in memory")
end

-- ------------------------------------------------------------------ wiring
connections[#connections + 1] = workspace.ChildAdded:Connect(onChildAdded)
for _, c in ipairs(workspace:GetChildren()) do
    if c:IsA("Model") and not c:FindFirstChildOfClass("Humanoid") and (c:FindFirstChild("hitBox") or c:FindFirstChild("precast")) then
        attacks[c] = newRecord("model", c, true)
    end
end

pcall(function()
    local remotes = ReplicatedStorage:FindFirstChild("remotes")
    if not remotes then note("ReplicatedStorage.remotes not found; no events") return end
    local hooked = {}
    for _, r in ipairs(remotes:GetChildren()) do
        local n = r.Name
        if r:IsA("RemoteEvent") and (n:find("BossSpecficEvents") or n == "mapSpecificEvent" or n == "bossSpecficEvents") then
            connections[#connections + 1] = r.OnClientEvent:Connect(function(...) onEvent(n, ...) end)
            hooked[#hooked + 1] = n
        end
    end
    note("hooked remotes: " .. table.concat(hooked, ", "))
end)

if player.Character then bindCharacter(player.Character) end
connections[#connections + 1] = player.CharacterAdded:Connect(function(char)
    note("respawn")
    bindCharacter(char)
end)

local acc, hudAcc, enemyAcc, writeAcc = 0, 0, 0, 0
local lastLoopErr
connections[#connections + 1] = RunService.Heartbeat:Connect(function(dt)
    if stopped then return end
    acc = acc + dt
    if acc < SAMPLE_DT then return end
    local step = acc
    acc = 0
    local ok, err = pcall(function()
        local now = age()
        local p = (root and root.Parent) and root.Position or nil
        promoteCandidates(now)
        for model, rec in pairs(attacks) do sampleModel(model, rec, now, p, step) end
        for part, rec in pairs(parts) do samplePart(part, rec, now, p, step) end
        enemyAcc = enemyAcc + step
        if enemyAcc >= 1 then enemyAcc = 0 scanEnemies() end
        hudAcc = hudAcc + step
        if hudAcc >= 0.5 then hudAcc = 0 updateHud() end
        writeAcc = writeAcc + step
        if writeAcc >= WRITE_EVERY or (dirty and writeAcc >= 1) then writeAcc = 0 save() end
    end)
    if not ok and tostring(err) ~= lastLoopErr then
        lastLoopErr = tostring(err)
        note("loop error: " .. lastLoopErr)
        warn("[DQProbe] " .. lastLoopErr)
    end
end)

local function stop()
    if stopped then return end
    stopped = true
    for _, c in ipairs(connections) do pcall(function() c:Disconnect() end) end
    local a = age()
    for model, rec in pairs(attacks) do closeRecord(rec, a - rec.spawn) attacks[model] = nil end
    for part, rec in pairs(parts) do closeRecord(rec, a - rec.spawn) parts[part] = nil end
    save()
    if gui then pcall(function() gui:Destroy() end) end
    print(fmt("[DQProbe] stopped after %.0fs; %d hits, %d records; %s", a, #hits, #order, canWrite and ("wrote " .. fileName) or "no writefile here"))
end

G.DQProbe = { version = PROBE_VERSION, file = fileName, stop = stop, save = save, report = report }
scanEnemies()
buildHud()
note(fmt("probe v%s started  map=%s  timeSync=%s  writefile=%s", PROBE_VERSION, mapName, tostring(timeSync ~= nil), tostring(canWrite)))
print(fmt("[DQProbe] v%s watching %s; %s", PROBE_VERSION, mapName, canWrite and ("writing " .. fileName .. " every " .. WRITE_EVERY .. " s and on every hit") or "no writefile: use DQProbe.report()"))
