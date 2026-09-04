-- recorder6.lua - Live capture for the 5.1 rewrite through the Potassium bridge.
-- Beyond recorder5 (health drops with the hazards near, spawns, candidates):
--   * a 10 Hz trace of what the bot intended and what the character did
--     (MoveDirection vs measured velocity, WalkSpeed, state, spot, danger
--     here, grace, nearest box, reflex, boost, stall), kept for 6 s and
--     dumped with every death;
--   * a verdict for every death: the box that contained the character and
--     whether the model called it live, not yet live (by how much), or over
--     (by how much) - or no box at all (undetected, or padding too small);
--   * per-kind verdict counts, movement effectiveness, blink and reflex logs.
-- Saves dq_rec6.json every 10 s.
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local lp = Players.LocalPlayer
local S = _G.DungeonAutofarmState
if _G.DQRec5 and _G.DQRec5.stop then pcall(_G.DQRec5.stop) end
local R = { started = os.clock(), hits = {}, samples = {}, states = {}, conns = {}, trace = {}, verdicts = {}, blinkLog = {}, reflexLog = {},
    move = { n = 0, effSum = 0, dotSum = 0, stuck = 0, idle = 0 } }
_G.DQRec5 = R
local function r1(v) return math.floor(v * 10 + 0.5) / 10 end
local function r2(v) return math.floor(v * 100 + 0.5) / 100 end
local function v3(v) return { r1(v.X), r1(v.Y), r1(v.Z) } end
local function now() return r1(os.clock() - R.started) end

-- Signed containment: inside > 0 (depth), outside < 0 (minus the distance).
local function boxDepth(b, p, t)
    if b.moving then
        local along = b.offset + b.speed * math.max(t - b.pathStart, 0)
        local cx, cz = b.ox + b.dx * along, b.oz + b.dz * along
        local qx, qz = p.X - cx, p.Z - cz
        local a = math.abs(qx * b.dx + qz * b.dz) - b.halfL
        local s = math.abs(-qx * b.dz + qz * b.dx) - b.halfW
        if a <= 0 and s <= 0 then return -math.max(a, s) end
        return -math.sqrt(math.max(a, 0) ^ 2 + math.max(s, 0) ^ 2)
    end
    if b.round then
        local c = b.cframe.Position
        return b.size.X * 0.5 - math.sqrt((p.X - c.X) ^ 2 + (p.Z - c.Z) ^ 2)
    end
    if b.r then return b.r - math.sqrt((p.X - b.cx) ^ 2 + (p.Z - b.cz) ^ 2) end   -- cylinders and rounds carry a radius (the object-space test below read a standing cylinder as a 1-stud slab)
    local lpos = b.cframe:PointToObjectSpace(p)
    local sx, sz = b.size.X * 0.5, b.size.Z * 0.5
    if b.cyl then
        -- A cylinder's axis is X; its round face spans Y/Z. Horizontal
        -- containment is what matters here.
        local ry = b.size.Y * 0.5
        local ax, az = math.abs(lpos.X) - sx, math.abs(lpos.Z) - ry
        if ax <= 0 and az <= 0 then return -math.max(ax, az) end
        return -math.sqrt(math.max(ax, 0) ^ 2 + math.max(az, 0) ^ 2)
    end
    local ax, az = math.abs(lpos.X) - sx, math.abs(lpos.Z) - sz
    if ax <= 0 and az <= 0 then return -math.max(ax, az) end
    return -math.sqrt(math.max(ax, 0) ^ 2 + math.max(az, 0) ^ 2)
end

-- Everything that appears in workspace, kept for a few seconds.
R.spawns = {}
R.conns[#R.conns + 1] = workspace.DescendantAdded:Connect(function(inst)
    if not (inst:IsA("BasePart") or inst:IsA("Model")) then return end
    local top = inst
    while top.Parent and top.Parent ~= workspace do top = top.Parent end
    if top.Name == "DungeonAutofarmVisuals" or (lp.Character and top == lp.Character) or top.Name == "dungeon" and inst.Parent and inst.Parent.Name == "enemyFolder" then return end
    local rt = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
    local p = inst:IsA("BasePart") and inst or (inst:IsA("Model") and (inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart")))
    local d = (p and rt) and r1((Vector3.new(p.Position.X, 0, p.Position.Z) - Vector3.new(rt.Position.X, 0, rt.Position.Z)).Magnitude) or nil
    R.spawns[#R.spawns + 1] = { at = os.clock(), name = (top ~= inst and (top.Name .. "/") or "") .. inst.Name, class = inst.ClassName, dist = d,
        pos = p and v3(p.Position) or nil, size = p and string.format("%.0fx%.0fx%.0f", p.Size.X, p.Size.Y, p.Size.Z) or nil }
    if #R.spawns > 400 then table.remove(R.spawns, 1) end
end)
pcall(function()
    local remotes = game:GetService("ReplicatedStorage"):FindFirstChild("remotes")
    for _, r in ipairs(remotes and remotes:GetChildren() or {}) do
        if r:IsA("RemoteEvent") and r.Name:lower():find("bossspecficevents") then
            R.conns[#R.conns + 1] = r.OnClientEvent:Connect(function(name, args)
                local rt = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
                local pos = typeof(args) == "Vector3" and args or (typeof(args) == "CFrame" and args.Position) or (type(args) == "table" and typeof(args[5]) == "CFrame" and args[5].Position) or nil
                local d = (pos and rt) and r1((Vector3.new(pos.X, 0, pos.Z) - Vector3.new(rt.Position.X, 0, rt.Position.Z)).Magnitude) or nil
                R.spawns[#R.spawns + 1] = { at = os.clock(), name = "EVENT " .. tostring(name), class = typeof(args), dist = d, pos = pos and v3(pos) or nil,
                    size = (type(args) == "table" and #args >= 4) and string.format("dist%.0f dur%.1f", tonumber(args[1]) or 0, tonumber(args[2]) or 0) or nil }
            end)
        end
    end
end)

local function recentSpawns(t, deathPos)
    local out = {}
    for i = #R.spawns, 1, -1 do
        local sp = R.spawns[i]
        if t - sp.at > 4 then break end
        local dd = (sp.pos and deathPos) and r1(math.sqrt((sp.pos[1] - deathPos.X) ^ 2 + (sp.pos[3] - deathPos.Z) ^ 2)) or nil
        if not sp.name:lower():find("passivebeam") or (sp.dist or 99) < 12 or (dd or 99) < 12 then
            out[#out + 1] = string.format("%.1fs %s(%s) d%s fromDeath%s %s", t - sp.at, sp.name, sp.class, tostring(sp.dist), tostring(dd), sp.size or "")
        end
    end
    return out
end

-- ------------------------------------------------------------ trace (10 Hz)
local lastPos, lastT = nil, nil
local lastBlinks, lastReflex = 0, nil
task.spawn(function()
    while _G.DQRec5 == R and not R.stopped do
        task.wait(0.1)
        local c = lp.Character
        local hum = c and c:FindFirstChildOfClass("Humanoid")
        local rt = c and c:FindFirstChild("HumanoidRootPart")
        local t = os.clock()
        if hum and rt and S then
            local p = rt.Position
            local vel = rt.AssemblyLinearVelocity
            local flatV = Vector3.new(vel.X, 0, vel.Z)
            local speed = flatV.Magnitude
            local md = hum.MoveDirection
            local mdMag = md.Magnitude
            local dot = (mdMag > 0.1 and speed > 1) and r2(flatV.Unit:Dot(Vector3.new(md.X, 0, md.Z).Unit)) or nil
            local eff = mdMag > 0.1 and r2(speed / math.max(hum.WalkSpeed, 1)) or nil
            if mdMag > 0.1 then
                R.move.n = R.move.n + 1
                R.move.effSum = R.move.effSum + (eff or 0)
                if dot then R.move.dotSum = R.move.dotSum + dot end
                if speed < 3 then R.move.stuck = R.move.stuck + 1 end
            else
                R.move.idle = R.move.idle + 1
            end
            local DG, RT, BR = S.DG, S.RT, S.BR
            local nearest, nd, nf = nil, math.huge, nil
            local boxes = DG.boxes or {}
            for _, b in ipairs(boxes) do
                local depth = boxDepth(b, p, t)
                if -depth < nd then nd = -depth nearest = b nf = r1(b.from - t) end
            end
            local tg = DG.target
            local e = BR.target
            local ch = DG.chosen
            local st = DG.evalStats
            local row = {
                t = now(), p = v3(p), v = r1(speed), eff = eff, dot = dot, md = r1(mdMag), ws = r1(hum.WalkSpeed),
                st = RT.movementState, rs = DG.reason,
                tg = tg and r1((Vector3.new(tg.X, 0, tg.Z) - Vector3.new(p.X, 0, p.Z)).Magnitude) or nil,
                h0 = r2(DG.here0 or 0), hd = r2(DG.dangerHere or 0), gr = (DG.grace and DG.grace < math.huge) and r2(DG.grace) or nil,
                nb = #boxes, near = nearest and string.format("%s %s d%.1f f%s", nearest.name or "?", nearest.kind or (nearest.moving and "path" or "zone"), nd == math.huge and 99 or nd, tostring(nf)) or nil,
                rf = RT.reflex and RT.reflex.name or nil, bo = RT.walkSpeedBefore ~= nil, stall = r1(RT.stalledFor or 0),
                bc = (c:FindFirstChild("busyCasting") and c.busyCasting.Value) and 1 or 0,
                tgt = e and string.format("%s d%.0f", e.model.Name, S.flatDistance(e.root.Position, p)) or nil,
                ch = ch and string.format("%.0fst dg%.2f end%.2f c%.2f", ch.dist, ch.danger, ch.endDanger or -1, ch.cost) or nil,
                ev = st and string.format("tot%d val%d floor%d walk%d end%d", st.total or 0, st.valid or 0, st.noFloor or 0, st.notWalkable or 0, st.lethalEnd or 0) or nil,
            }
            R.trace[#R.trace + 1] = row
            if #R.trace > 60 then table.remove(R.trace, 1) end
            if (RT.blinks or 0) ~= lastBlinks then
                lastBlinks = RT.blinks or 0
                local lb = RT.lastBlink
                R.blinkLog[#R.blinkLog + 1] = { t = now(), dist = lb and r1(lb.dist), grace = lb and r1(lb.grace), from = lb and v3(lb.from), to = lb and v3(lb.to), near = row.near }
            end
            local rfName = RT.reflex and RT.reflex.name or nil
            if rfName ~= lastReflex then
                R.reflexLog[#R.reflexLog + 1] = { t = now(), reflex = rfName or "end", pos = v3(p) }
                lastReflex = rfName
            end
        end
        lastPos, lastT = rt and rt.Position or nil, t
    end
end)

-- ------------------------------------------------------------ deaths
local function verdictFor(p, t)
    if not (S and S.hazards) then return { class = "no model" } end
    local best = nil
    local nearest, nd = nil, math.huge
    for _, b in ipairs(S.hazards(t)) do
        local depth = boxDepth(b, p, t)
        local name = b.name or "?"
        local kind = b.kind or (b.moving and "path" or "zone")
        -- A soft band (weighted) never kills; it only counts as "nearest".
        if depth >= 0 and not b.weight then
            local class, by
            if t >= b.from and t <= b.untilAt then class, by = "inside-live", 0
            elseif t < b.from then class, by = "inside-early", r1(b.from - t)
            else class, by = "inside-expired", r1(t - b.untilAt) end
            local rank = class == "inside-live" and 3 or (class == "inside-early" and 2 or 1)
            if not best or rank > best.rank or (rank == best.rank and by < best.by) then
                best = { class = class, by = by, name = name, kind = kind, depth = r1(depth), rank = rank, weight = b.weight }
            end
        elseif -depth < nd then
            nd = -depth
            nearest = { name = name, kind = kind, dist = r1(-depth), firesIn = r1(b.from - t), endsIn = b.untilAt < math.huge and r1(b.untilAt - t) or nil }
        end
    end
    if best then best.rank = nil return best end
    return { class = "outside-all", nearest = nearest }
end

local function hookHumanoid(c)
    local hum = c:WaitForChild("Humanoid", 10)
    if not hum then return end
    local last = hum.Health
    R.conns[#R.conns + 1] = hum.HealthChanged:Connect(function(h)
        if h < last - 1 then
            local rt = c:FindFirstChild("HumanoidRootPart")
            local t = os.clock()
            local near = {}
            local verdict = nil
            if rt and S and S.hazards then
                for _, b in ipairs(S.hazards(t)) do
                    local depth = boxDepth(b, rt.Position, t)
                    if -depth <= 20 then
                        near[#near + 1] = { name = b.name, kind = b.kind or (b.moving and "path" or "zone"), dist = r1(-depth),
                            firesIn = r1(b.from - t), endsIn = b.untilAt < math.huge and r1(b.untilAt - t) or nil, live = t >= b.from and t <= b.untilAt }
                    end
                end
                table.sort(near, function(a, b) return a.dist < b.dist end)
                verdict = verdictFor(rt.Position, t)
                local key = (verdict.name or (verdict.nearest and ("~" .. verdict.nearest.name)) or "none") .. " / " .. verdict.class
                local v = R.verdicts[key] or { n = 0, bySum = 0 }
                v.n = v.n + 1
                v.bySum = v.bySum + (verdict.by or 0)
                R.verdicts[key] = v
            end
            local trace = {}
            for i = math.max(1, #R.trace - 40), #R.trace do trace[#trace + 1] = R.trace[i] end
            R.hits[#R.hits + 1] = { t = now(), lost = math.floor(last - h), fatal = h <= 0, pos = rt and v3(rt.Position) or nil, near = near, verdict = verdict,
                spawns = recentSpawns(t, rt and rt.Position or nil), trace = trace,
                state = S and S.RT.movementState, reason = S and S.DG and S.DG.reason, dangerHere = S and S.DG and r1(S.DG.dangerHere or 0),
                grace = S and S.DG and S.DG.grace ~= math.huge and r1(S.DG.grace) or nil,
                target = S and S.BR and S.BR.target and S.BR.target.model.Name or nil,
                blinks = S and S.RT.blinks or 0, lastBlinkAgo = (S and S.RT.lastBlinkAt) and r1(t - S.RT.lastBlinkAt) or nil,
                beams = (function()   -- the Champion's beams: yaw and age of the last twelve, and our bearing from the hub (mod 180, like the yaws)
                    local bl = S and S.RD and S.RD.beams
                    if not bl or #bl == 0 or not rt then return nil end
                    local list = {}
                    for i = math.max(1, #bl - 11), #bl do local b = bl[i] list[#list + 1] = string.format("%.0f@-%.1f", b.yaw, t - b.t) end
                    local hub = bl[#bl].hub
                    local myYaw = math.deg(math.atan2(rt.Position.X - hub.X, rt.Position.Z - hub.Z)) % 180
                    return string.format("me %.0f at %.0f from hub | %s", myYaw, (Vector3.new(rt.Position.X - hub.X, 0, rt.Position.Z - hub.Z)).Magnitude, table.concat(list, " "))
                end)(),
                reflex = S and S.RT.reflex and S.RT.reflex.name or nil,
                cands = (function()
                    if not (S and S.DG and S.DG.cands) then return nil end
                    local list = {}
                    for i = 1, math.min(6, #S.DG.cands) do local cd = S.DG.cands[i]; list[i] = { dist = r1(cd.dist), danger = r1(cd.danger), endDanger = cd.endDanger and r1(cd.endDanger), cost = r1(cd.cost), valid = cd.valid == true } end
                    return list
                end)(),
                bossDist = (function()
                    local e = S and S.BR and S.BR.target
                    if e and rt then return r1(S.flatDistance(e.root.Position, rt.Position)) end
                end)() }
        end
        last = h
    end)
end
if lp.Character then hookHumanoid(lp.Character) end
R.conns[#R.conns + 1] = lp.CharacterAdded:Connect(function(c) R.states[#R.states + 1] = { t = now(), s = "respawn" } hookHumanoid(c) end)

task.spawn(function()
    while _G.DQRec5 == R and not R.stopped do
        task.wait(1)
        local e = S and S.BR and S.BR.target
        local rt = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
        R.samples[#R.samples + 1] = { t = now(), target = e and e.model.Name, hp = e and r1(e.humanoid.Health / math.max(e.humanoid.MaxHealth, 1) * 100),
            dist = (e and rt) and r1(S.flatDistance(e.root.Position, rt.Position)) or nil, state = S and S.RT.movementState, reason = S and S.DG and S.DG.reason,
            hazards = S and #S.hazards(os.clock()) or 0, tickMs = S and r1(S.RT.tickMs or 0) }
        if #R.samples > 1800 then table.remove(R.samples, 1) end
    end
end)
task.spawn(function()
    while _G.DQRec5 == R and not R.stopped do
        task.wait(10)
        pcall(writefile, "dq_rec6.json", HttpService:JSONEncode({ hits = R.hits, samples = R.samples, states = R.states, verdicts = R.verdicts, move = R.move, blinks = R.blinkLog, reflexes = R.reflexLog }))
    end
end)
function R.stop() for _, c in ipairs(R.conns) do pcall(function() c:Disconnect() end) end R.stopped = true end
return { ok = true, version = _G.DungeonAutofarmVersion, loaded = S ~= nil, recorder = 6 }
