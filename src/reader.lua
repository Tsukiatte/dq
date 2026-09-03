-- reader.lua - Reads the game's attacks. Every Model with a hitBox or precast
-- under workspace is tracked from the moment it appears and its precast is
-- read every frame; every BasePart parented straight to workspace is tracked
-- as a projectile, with the boss remote event that made it when one matches;
-- the enemies are scanned from the dungeon's enemy folders; every hit is
-- written down with what enclosed the character. Nothing here learns timing
-- from being hit: the timing comes from the precast and from bosses.lua.
--
-- What the real Northern Lands capture (2026-09-02, 6 deaths, 422 attacks)
-- showed, and what this module is built on: the precast is visible from the
-- moment the Model appears, flashes to transparency 0.17 at the instant the
-- hit lands, and fades to 1.0 about 0.2 s later. The invisible hitBox stays
-- for seven seconds afterwards and never hurts again.
return function(S)
local CFG = S.CFG
local RT = S.RT
local HZ = S.HZ
local PC = S.PC
local Workspace = S.Workspace
local ReplicatedStorage = S.ReplicatedStorage
local Players = S.Players
local LocalPlayer = S.LocalPlayer
local heavyDebug = S.heavyDebug
local isKnownOwnEffect = S.isKnownOwnEffect

local V3 = Vector3.new
local clock = os.clock
local INF = math.huge
local fmt = string.format

local byInst = {}          -- [instance] = record
local candidates = {}      -- [Model] = os.clock() it appeared
local events = {}          -- recent boss projectile events, newest last
local recent = {}          -- records that ended within the last second (hit blame)
local connections = {}
local timeSync
local gameOffset = 0       -- game clock = os.clock() + gameOffset
HZ.finished = {}           -- ended records kept while a capture is recording

-- ------------------------------------------------------------------ clocks
local function syncClock()
    local ok, t = pcall(function()
        if timeSync then return timeSync:GetTime() end
        return Workspace:GetServerTimeNow()
    end)
    if ok and type(t) == "number" then gameOffset = t - clock() end
end
local function gameTime(t) return t + gameOffset end

-- ------------------------------------------------------------------ helpers
local function sz(v) return fmt("%.0fx%.0fx%.0f", v.X, v.Y, v.Z) end
local function statFor(key)
    local st = HZ.stats[key]
    if not st then
        st = { n = 0, flashN = 0, flashSum = 0, inside = {}, hits = {} }
        HZ.stats[key] = st
    end
    return st
end
local function bucket(age)
    if age > 12 then age = 12 end
    return math.floor(age / 0.25)
end
local function trace(rec, now, tr)
    if not CFG.diagnoseAttacks then return end
    rec.trace = rec.trace or {}
    local n = #rec.trace
    if n < 60 then rec.trace[n + 1] = fmt("%.2f:%.2f", now - rec.spawn, tr) end
end
local function closeSpan(rec, now)
    rec.inside = false
    rec.spans = rec.spans or {}
    if #rec.spans < 40 then rec.spans[#rec.spans + 1] = fmt("%.2f-%.2f", rec.insideAt - rec.spawn, now - rec.spawn) end
end

-- The shape a record is scored against. Cylinders and balls are discs (the
-- circle strike's precast, the jump slam's hitBox); mesh parts are discs of
-- their widest extent (the projectiles); everything else is a box.
local function shapeOf(part)
    local ok, shape = pcall(function() return part.Shape end)
    if ok and shape == Enum.PartType.Cylinder then return "disc", part.Size.Y * 0.5 end
    if ok and shape == Enum.PartType.Ball then return "disc", part.Size.X * 0.5 end
    if not ok then
        local s = part.Size
        return "disc", math.max(s.X, s.Z) * 0.5
    end
    return "box", 0
end

-- ------------------------------------------------------------------ the book
-- Every attack name the reader meets goes into this map's Attack Book, where
-- the Attacks panel shows its measured timing and lets it be switched off.
local function bookSeen(rec)
    local r = HZ.bookByName[rec.key]
    if not r then
        r = { name = rec.name, enabled = true, hits = 0, damage = 0 }
        HZ.attackBook[#HZ.attackBook + 1] = r
        HZ.bookByName[rec.key] = r
        if S.refreshAttackBookPanel then pcall(S.refreshAttackBookPanel) end
    end
    rec.disabled = r.enabled == false
end
local function invalidateAttackBook()
    HZ.bookByName = {}
    for _, r in ipairs(HZ.attackBook) do
        if type(r.name) == "string" then HZ.bookByName[string.lower(r.name)] = r end
    end
    for _, rec in ipairs(HZ.attacks) do
        local r = HZ.bookByName[rec.key]
        rec.disabled = r ~= nil and r.enabled == false
    end
end

-- ------------------------------------------------------------------ records
local function addRecord(rec)
    HZ.attacks[#HZ.attacks + 1] = rec
    if rec.inst then byInst[rec.inst] = rec end
    PC.received = PC.received + 1
    local st = statFor(rec.key)
    st.n = st.n + 1
    if rec.kind == "model" then bookSeen(rec) end
    return rec
end
local function removeRecord(rec, now)
    if rec.inside then closeSpan(rec, now) end
    rec.removed = now
    if rec.inst then byInst[rec.inst] = nil end
    for i = #HZ.attacks, 1, -1 do
        if HZ.attacks[i] == rec then table.remove(HZ.attacks, i) break end
    end
    recent[#recent + 1] = rec
    if CFG.diagnoseAttacks and rec.kind ~= "pred" then
        HZ.finished[#HZ.finished + 1] = rec
        if #HZ.finished > CFG.diagnoseMax then table.remove(HZ.finished, 1) end
    end
end

local function newModelRecord(model, spawn)
    return addRecord({
        kind = "model", inst = model, name = model.Name, key = string.lower(model.Name),
        spawn = spawn or clock(), tr = 1, visible = false,
    })
end

-- ------------------------------------------------------------------ geometry
-- Where a projectile is at time t: on its scripted path when the boss event
-- gave one, else along its measured velocity for at most the lookahead.
local function projPos(rec, t)
    local ev = rec.ev
    if ev then
        local k = (gameTime(t) - ev.start) / ev.dur
        if k < 0 then k = 0 elseif k > 1 then k = 1 end
        return ev.origin + ev.look * (k * ev.dist)
    end
    local dt = t - rec.sampledAt
    if dt > CFG.projectileLookahead then dt = CFG.projectileLookahead end
    if dt < 0 then dt = 0 end
    if not rec.vel then return rec.pos end
    return rec.pos + rec.vel * dt
end

-- Planar distance from (x, z) to the record's shape at time t; 0 or less inside.
local function attackDistance(rec, x, z, t)
    if rec.kind == "part" then
        local p = projPos(rec, t)
        local dx, dz = p.X - x, p.Z - z
        return math.sqrt(dx * dx + dz * dz) - rec.radius
    end
    local part = rec.part
    if rec.shape == "disc" then
        local c = rec.center or part.Position
        local dx, dz = c.X - x, c.Z - z
        return math.sqrt(dx * dx + dz * dz) - rec.radius
    end
    local cf = rec.cframe or part.CFrame
    local size = rec.size or part.Size
    local l = cf:PointToObjectSpace(V3(x, cf.Position.Y, z))
    local dx = math.max(math.abs(l.X) - size.X * 0.5, 0)
    local dz = math.max(math.abs(l.Z) - size.Z * 0.5, 0)
    return math.sqrt(dx * dx + dz * dz)
end

-- The interval (in os.clock seconds) during which the record can hurt, or
-- nil when it cannot. Unknown timing means the whole visible life plus a
-- linger; known timing (bosses.lua, or the flash once it is seen) means a
-- short window around the flash and floor before and after.
local function window(rec)
    local kind = rec.kind
    if kind ~= "model" then return rec.open, rec.close end
    if rec.disabled then return nil end
    local lead, after = CFG.dodgeLead, CFG.hitAfter
    if rec.flashAt then return rec.flashAt - lead, rec.flashAt + after end
    local T = rec.flashTime
    if T and not rec.pre then
        local close = rec.spawn + T + after
        if clock() > close and rec.visible then
            -- Overdue and still showing: the table is wrong for this one, so it
            -- stays live until it fires or fades.
            close = (rec.fadeAt or INF) + CFG.fadeLinger
        end
        return rec.spawn + T - lead, close
    end
    if rec.visAt then return rec.visAt, (rec.fadeAt or INF) + CFG.fadeLinger end
    return nil
end
local function attackLive(rec, t)
    local open, close = window(rec)
    return open ~= nil and t >= open and t <= close
end

-- ------------------------------------------------------------------ sampling
local function adopt(rec)
    local m = rec.inst
    if not rec.hb then
        local hb = m:FindFirstChild("hitBox")
        if hb and hb:IsA("BasePart") then rec.hb = hb end
    end
    if not rec.pc then
        local pc = m:FindFirstChild("precast")
        if pc and pc:IsA("BasePart") then rec.pc = pc end
    end
    local part = rec.hb or rec.pc
    if part and rec.part ~= part then
        rec.part = part
        rec.shape, rec.radius = shapeOf(part)
        rec.sizeText = sz(part.Size)
        rec.flashTime = S.flashTimeFor and S.flashTimeFor(rec) or nil
        if rec.flashTime then PC.total = PC.total + 1 end
        if S.onAttackShape then S.onAttackShape(rec) end
    end
end

local function sampleInside(rec, now, step, rx, rz)
    if rx == nil then return end
    local inside = attackDistance(rec, rx, rz, now) <= 0
    if inside and not rec.inside then
        rec.inside, rec.insideAt = true, now
    elseif rec.inside and not inside then
        closeSpan(rec, now)
    end
    if inside then
        local st = statFor(rec.key)
        local b = bucket(now - rec.spawn)
        st.inside[b] = (st.inside[b] or 0) + step
    end
end

local function sampleModel(rec, now, step, rx, rz)
    local m = rec.inst
    if not m.Parent then removeRecord(rec, now) return end
    adopt(rec)
    local pc = rec.pc
    if pc then
        local tr = pc.Transparency
        rec.tr = tr
        local visible = tr < 0.97
        rec.visible = visible
        if visible and not rec.visAt then rec.visAt = now end
        if visible and tr <= 0.2 and not rec.flashAt then
            rec.flashAt = now
            local st = statFor(rec.key)
            st.flashN = st.flashN + 1
            st.flashSum = st.flashSum + (now - rec.spawn)
        end
        if rec.visAt and not rec.fadeAt and not visible then rec.fadeAt = now end
        if rec.lastT == nil or math.abs(tr - rec.lastT) >= 0.02 then
            rec.lastT = tr
            trace(rec, now, tr)
        end
    end
    if CFG.diagnoseAttacks and rec.part then sampleInside(rec, now, step, rx, rz) end
    -- Over: past its window, or a plain Model that never showed anything for
    -- fifteen seconds. Parked pool Models (present before the reader) stay.
    local _, close = window(rec)
    if close and now > close + 0.5 then rec.done = true end
    if rec.done and not rec.pre then removeRecord(rec, now) end
end

local function samplePart(rec, now, step, rx, rz)
    local p = rec.inst
    if not p.Parent then removeRecord(rec, now) return end
    local pos = p.Position
    local dt = now - rec.sampledAt
    if dt > 0.05 then
        local v = (pos - rec.pos) / dt
        rec.vel = rec.vel and (rec.vel * 0.5 + v * 0.5) or v
        rec.pos, rec.sampledAt = pos, now
    end
    local tr = p.Transparency
    if rec.lastT == nil or math.abs(tr - rec.lastT) >= 0.02 then
        rec.lastT = tr
        trace(rec, now, tr)
    end
    rec.tr = tr
    if tr < 0.97 and not rec.visAt then rec.visAt = now end
    if rec.visAt and tr >= 0.97 and not rec.fadeAt then rec.fadeAt = now end
    -- Live from the event or from the moment it shows; over when the event
    -- says so or when it fades.
    if rec.ev then
        rec.open = rec.spawn
        rec.close = rec.ev.stop - gameOffset
    elseif rec.vel and rec.vel.Magnitude > CFG.projectileMaxSpeed then
        -- Faster than any projectile here: a tweened visual (the spearman's
        -- strike part crosses 65 studs in a quarter second). Floor.
        rec.open = nil
    else
        rec.open = rec.visAt
        rec.close = rec.fadeAt and (rec.fadeAt + 0.1) or INF
    end
    if CFG.diagnoseAttacks then sampleInside(rec, now, step, rx, rz) end
    if now > (rec.close or INF) + 0.5 or (not rec.visAt and now - rec.spawn > 12) then
        removeRecord(rec, now)
    end
end

local function sampleZone(rec, now)
    if not rec.part.Parent then removeRecord(rec, now) end
end

-- ------------------------------------------------------------------ workspace
local function isOwn(part)
    if HZ.ownNames[string.lower(part.Name)] then return true end
    local ok, own = pcall(isKnownOwnEffect, part)
    return ok and own == true
end

local function linkEvent(rec)
    local now = clock()
    for i = #events, 1, -1 do
        local ev = events[i]
        if now - ev.at > 0.5 then break end
        if (ev.origin - rec.pos).Magnitude <= 3 then rec.ev = ev return end
    end
end

local function onChildAdded(child)
    if RT.destroyed then return end
    if child:IsA("Model") then
        if child:FindFirstChildOfClass("Humanoid") then return end
        candidates[child] = clock()
    elseif child:IsA("BasePart") then
        if child == RT.visualRoot then return end
        local s = child.Size
        local radius = math.max(s.X, s.Y, s.Z) * 0.5
        local key = string.lower(child.Name)
        if (radius < 1.5 and not HZ.learnedNames[key]) or isOwn(child) then return end
        local now = clock()
        local rec = addRecord({
            kind = "part", inst = child, name = child.Name, key = key, spawn = now,
            pos = child.Position, sampledAt = now, radius = math.max(radius, 1), tr = child.Transparency,
            sizeText = sz(s), open = nil, close = INF,
        })
        linkEvent(rec)
    end
end

local function promoteCandidates(now)
    for model, since in pairs(candidates) do
        if not model.Parent then
            candidates[model] = nil
        elseif model:FindFirstChild("hitBox") or model:FindFirstChild("precast") then
            candidates[model] = nil
            newModelRecord(model, since)
        elseif now - since > 2 then
            candidates[model] = nil
        end
    end
end

-- ------------------------------------------------------------------ events
local function onEvent(remoteName, name, args)
    if type(args) == "table" and typeof(args[5]) == "CFrame" and type(args[1]) == "number" and type(args[3]) == "number" then
        events[#events + 1] = {
            name = tostring(name), dist = args[1], dur = args[2], start = args[3], stop = args[4],
            origin = args[5].Position, look = args[5].LookVector, at = clock(),
        }
        if #events > 64 then table.remove(events, 1) end
    end
    if S.onBossEvent then pcall(S.onBossEvent, remoteName, name, args) end
end

-- ------------------------------------------------------------------ enemies
local function scanEnemies()
    local list = {}
    local mine = LocalPlayer.Character
    local function consider(m)
        if not m:IsA("Model") or m == mine or Players:GetPlayerFromCharacter(m) then return end
        local hum = m:FindFirstChildOfClass("Humanoid")
        local root = m:FindFirstChild("HumanoidRootPart") or m.PrimaryPart
        if not hum or not root or hum.Health <= 0 then return end
        local md, st = m:FindFirstChild("meleeDistance"), m:FindFirstChild("enemyStyle")
        local style = st and tostring(st.Value) or ""
        local s = root.Size
        list[#list + 1] = {
            model = m, root = root, humanoid = hum, name = m.Name,
            melee = (md and tonumber(md.Value)) or CFG.enemyMeleeReach,
            style = style, boss = string.find(string.lower(style), "boss") ~= nil,
            extent = math.max(s.X, s.Z) * 0.5,
        }
    end
    local dungeon = Workspace:FindFirstChild("dungeon")
    if dungeon then
        for _, room in ipairs(dungeon:GetChildren()) do
            local ef = room:FindFirstChild("enemyFolder")
            if ef then for _, m in ipairs(ef:GetChildren()) do consider(m) end end
        end
    end
    local en = Workspace:FindFirstChild("enemies")
    if en then for _, m in ipairs(en:GetChildren()) do consider(m) end end
    if #list == 0 then for _, m in ipairs(Workspace:GetChildren()) do consider(m) end end
    HZ.enemies = list
    return list
end

-- ------------------------------------------------------------------ hits
local function recordHit(damage)
    local now = clock()
    local char = LocalPlayer.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local p = root and root.Position
    HZ.lastHitAt = now
    local best, bestScore = nil, INF
    local near = {}
    local function consider(rec)
        if not p or rec.kind == "pred" then return end
        local ok, d = pcall(attackDistance, rec, p.X, p.Z, now)
        if not ok or d > 4 then return end
        local open, close = window(rec)
        local live = open ~= nil and now >= open - 0.3 and now <= close + 0.3
        local score = (live and 0 or 10) + math.max(d, 0)
        near[#near + 1] = fmt("%s age=%.2f tr=%.2f dist=%.1f%s", rec.name, now - rec.spawn, rec.tr or 1, d, live and " LIVE" or "")
        if score < bestScore then best, bestScore = rec, score end
    end
    for _, rec in ipairs(HZ.attacks) do consider(rec) end
    for _, rec in ipairs(recent) do consider(rec) end
    local culprit = best and best.name or nil
    HZ.lastHitName = culprit
    if best then
        local st = statFor(best.key)
        local b = bucket(now - best.spawn)
        st.hits[b] = (st.hits[b] or 0) + 1
        local r = HZ.bookByName[best.key]
        if r then r.hits = (r.hits or 0) + 1 r.damage = (r.damage or 0) + (damage or 0) end
    end
    local enemies = {}
    for _, e in ipairs(HZ.enemies) do
        if p and e.root.Parent then
            local d = (e.root.Position - p).Magnitude
            if d <= 25 then enemies[#enemies + 1] = fmt("%s %.0f", e.name, d) end
        end
    end
    local stun = Workspace:FindFirstChild("stunParts")
    local stunned = stun ~= nil and stun:FindFirstChild(LocalPlayer.Name) ~= nil
    HZ.hitLog[#HZ.hitLog + 1] = fmt("HIT %s dmg=%.0f pos=%s%s culprit=%s | near: %s | enemies: %s",
        os.date("%H:%M:%S"), damage or 0, p and fmt("(%.0f,%.0f,%.0f)", p.X, p.Y, p.Z) or "?",
        stunned and " STUNNED" or "", tostring(culprit), table.concat(near, "; "), table.concat(enemies, ", "))
    if #HZ.hitLog > 80 then table.remove(HZ.hitLog, 1) end
    heavyDebug("Hit", HZ.hitLog[#HZ.hitLog])
    if S.refreshHitPanel then pcall(S.refreshHitPanel) end
end

-- ------------------------------------------------------------------ zones and predictions
local function addZoneRecord(part, shape, radius, name)
    local rec = {
        kind = "zone", inst = part, part = part, name = name or part.Name, key = string.lower(name or part.Name),
        spawn = clock(), shape = shape == "circle" and "disc" or "box", radius = radius,
        cframe = shape ~= "circle" and part.CFrame or nil,
        size = shape ~= "circle" and V3(radius * 2, part.Size.Y, radius * 2) or nil,
        open = clock(), close = INF, tr = 0,
    }
    return addRecord(rec)
end
local function removeZoneRecords()
    for i = #HZ.attacks, 1, -1 do
        local rec = HZ.attacks[i]
        if rec.kind == "zone" then removeRecord(rec, clock()) end
    end
end
local function addVirtualAttack(name, cframe, size, open, close)
    local rec = {
        kind = "pred", name = name, key = string.lower(name), spawn = clock(),
        shape = "box", cframe = cframe, size = size, open = open, close = close, tr = 0.5,
    }
    HZ.attacks[#HZ.attacks + 1] = rec
    return rec
end

-- ------------------------------------------------------------------ the step
local lastSync = -INF
local function readerStep(now, step)
    if now - lastSync > 10 then lastSync = now syncClock() end
    promoteCandidates(now)
    local char = LocalPlayer.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local rx, rz
    if root then local p = root.Position rx, rz = p.X, p.Z end
    for i = #HZ.attacks, 1, -1 do
        local rec = HZ.attacks[i]
        local kind = rec.kind
        if kind == "model" then sampleModel(rec, now, step, rx, rz)
        elseif kind == "part" then samplePart(rec, now, step, rx, rz)
        elseif kind == "zone" then sampleZone(rec, now)
        elseif kind == "pred" then
            if now > rec.close + 0.3 or rec.dropped then removeRecord(rec, now) end
        end
    end
    for i = #recent, 1, -1 do
        if now - recent[i].removed > 1.0 then table.remove(recent, i) end
    end
    -- What can hurt now or within a second, within detection range: the HUD's
    -- count, the live feed and the highlights.
    local detected = {}
    local range = CFG.damageBrickDetectionRange
    for _, rec in ipairs(HZ.attacks) do
        local open, close = window(rec)
        if open and now <= close and now >= open - 1.0 and (rec.kind ~= "model" or CFG.usePrecast) then
            if rx == nil or rec.kind == "pred" then
                detected[#detected + 1] = rec
            else
                local ok, d = pcall(attackDistance, rec, rx, rz, now)
                if ok and d <= range then detected[#detected + 1] = rec end
            end
        end
    end
    HZ.detected = detected
    PC.zones = #detected
end

-- ------------------------------------------------------------------ start / stop
local function stopReader()
    for _, c in ipairs(connections) do pcall(function() c:Disconnect() end) end
    connections = {}
end
local function startReader()
    stopReader()
    pcall(function()
        local m = ReplicatedStorage:FindFirstChild("timeSync")
        if m then timeSync = require(m) end
    end)
    syncClock()
    connections[#connections + 1] = Workspace.ChildAdded:Connect(function(child)
        local ok, err = pcall(onChildAdded, child)
        if not ok then heavyDebug("Reader", "ChildAdded threw: " .. tostring(err)) end
    end)
    local pre = 0
    for _, c in ipairs(Workspace:GetChildren()) do
        if c:IsA("Model") and not c:FindFirstChildOfClass("Humanoid") and (c:FindFirstChild("hitBox") or c:FindFirstChild("precast")) then
            local rec = newModelRecord(c, clock() - 30)
            rec.pre = true
            pre = pre + 1
        end
    end
    local hooked = {}
    local remotes = ReplicatedStorage:FindFirstChild("remotes")
    if remotes then
        for _, r in ipairs(remotes:GetChildren()) do
            local n = r.Name
            if r:IsA("RemoteEvent") and (string.find(n, "BossSpecficEvents") or n == "mapSpecificEvent" or n == "bossSpecficEvents") then
                connections[#connections + 1] = r.OnClientEvent:Connect(function(name, args)
                    local ok, err = pcall(onEvent, n, name, args)
                    if not ok then heavyDebug("Reader", "event threw: " .. tostring(err)) end
                end)
                hooked[#hooked + 1] = n
            end
        end
    end
    PC.failed = false
    heavyDebug("Reader", fmt("Watching workspace (%d attack Models already present), %d boss remote(s), timeSync=%s.",
        pre, #hooked, tostring(timeSync ~= nil)))
end

S.readerStep = readerStep
S.startReader = startReader
S.stopReader = stopReader
S.scanEnemies = scanEnemies
S.recordHit = recordHit
S.attackDistance = attackDistance
S.attackWindow = window
S.attackLive = attackLive
S.gameTime = gameTime
S.addZoneRecord = addZoneRecord
S.removeZoneRecords = removeZoneRecords
S.addVirtualAttack = addVirtualAttack
S.invalidateAttackBook = invalidateAttackBook
S.readerEvents = events
-- Names the UI imports from the old modules, kept so ui.lua stays as it is.
S.stopWorldIndex = stopReader
S.stopBossEventListeners = stopReader
S.startPrecastListener = function() CFG.usePrecast = true end
S.clearPrecastZones = function() end
end
