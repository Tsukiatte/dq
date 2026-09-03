-- recorder_live.lua - Continuous capture through the Potassium bridge.
-- Run once when the run begins (execute_luau_file). It records, until the
-- client leaves the place:
--   parts   every attack-like BasePart that appears (not map, not us), with the
--           reader's verdict at spawn, 0.6 s and 2 s later, and when it vanished
--   events  every northernBossSpecficEvents fire and every precastHitbox
--           broadcast, with their arguments
--   hits    every health drop with the attack-like parts near the character
-- The log is written to dq_rec.json in Potassium's workspace every 10 s and
-- summarised by tools/recorder_dump.lua.
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local S = _G.DungeonAutofarmState
local lp = Players.LocalPlayer

if _G.DQRec and _G.DQRec.stop then pcall(_G.DQRec.stop) end
local R = { started = os.clock(), serverStart = workspace:GetServerTimeNow(), parts = {}, events = {}, hits = {}, bossHp = {}, states = {},
            byPart = setmetatable({}, { __mode = "k" }), conns = {}, partCount = 0 }
_G.DQRec = R

local function r1(v) return math.floor(v * 10 + 0.5) / 10 end
local function v3(v) return { r1(v.X), r1(v.Y), r1(v.Z) } end
local function now() return r1(os.clock() - R.started) end
local function char() return lp.Character end
local function root() local c = char() return c and c:FindFirstChild("HumanoidRootPart") end

local function verdict(p)
    if not (S and S.isDamageBrick) then return nil end
    local ok, v = pcall(S.isDamageBrick, p)
    if not ok then return "err" end
    local st = S.HZ and S.HZ.armState and S.HZ.armState[p]
    local arm = nil
    if st then
        arm = { name = st.name, armedBy = st.armedBy, armed = st.armedAt ~= nil,
                impactIn = st.impactAt and r1(st.impactAt - os.clock()) or nil,
                done = st.doneAt ~= nil and (st.doneBy or true) or nil,
                liveFor = st.liveUntil and r1(st.liveUntil - os.clock()) or nil }
    end
    return { danger = v and true or false, arm = arm }
end

local ATTACKY = { hitbox = true, precast = true, precasthitbox = true }
local function attackLike(p)
    if not p:IsA("BasePart") then return false end
    local c = char()
    if c and p:IsDescendantOf(c) then return false end
    local map = workspace:FindFirstChild("Map")
    if map and p:IsDescendantOf(map) then return false end
    local n = p.Name:lower()
    if ATTACKY[n] or n:find("precast") or n:find("hitbox") or n:find("strike") or n:find("spike")
        or n:find("beam") or n:find("orb") or n:find("shot") or n:find("neon") or n:find("freeze")
        or n:find("indicator") or n:find("aoe") or n:find("explosion") or n:find("crisscross") or n:find("missile") then
        return true
    end
    local m = p:FindFirstAncestorOfClass("Model")
    if m and not m:FindFirstChildOfClass("Humanoid") and (m:FindFirstChild("hitBox") or m:FindFirstChild("hitbox")) then
        return true
    end
    -- A bare Neon part parented straight to workspace is what the precast bridge builds.
    if p.Parent == workspace and p.Material == Enum.Material.Neon and not p.CanCollide then return true end
    return false
end

local function distToMe(p)
    local rt = root()
    return rt and r1((p.Position - rt.Position).Magnitude) or nil
end

local function recordPart(p)
    if R.byPart[p] or R.partCount >= 8000 then return end
    -- Anchor parts are never the danger and a boss spawns one every half second.
    local ln = p.Name:lower()
    if ln == "primarypart" then return end
    local m = p:FindFirstAncestorOfClass("Model")
    local e = { t = now(), name = p.Name, class = p.ClassName, model = m and m.Name or nil,
                parent = p.Parent and p.Parent.Name or nil, size = v3(p.Size), t0 = r1(p.Transparency),
                pos = v3(p.Position), dist = distToMe(p), neon = p.Material == Enum.Material.Neon,
                cc = p.CanCollide, v0 = verdict(p) }
    R.byPart[p] = e
    R.partCount = R.partCount + 1
    R.parts[#R.parts + 1] = e
    task.delay(0.6, function()
        if p.Parent then e.t1 = r1(p.Transparency); e.v1 = verdict(p); e.dist1 = distToMe(p); e.size1 = v3(p.Size) end
    end)
    task.delay(2.0, function()
        if p.Parent then e.t2 = r1(p.Transparency); e.v2 = verdict(p) end
    end)
    R.conns[#R.conns + 1] = p.AncestryChanged:Connect(function(_, parent)
        if parent == nil then e.gone = now() end
    end)
end

-- The enemies' own numbers, once, for the standoff rules.
task.spawn(function()
    task.wait(3)
    local list = {}
    for _, m in ipairs(Workspace:GetDescendants()) do
        if m:IsA("Model") and m:FindFirstChildOfClass("Humanoid") and m:FindFirstChild("enemyStyle") then
            local e = { name = m.Name }
            for _, k in ipairs({ "enemyStyle", "meleeDistance", "aggroRange", "moveSpeed", "attackSpeed", "level", "damage" }) do
                local v = m:FindFirstChild(k)
                if v and v:IsA("ValueBase") then e[k] = v.Value end
            end
            list[#list + 1] = e
        end
    end
    R.enemies = list
    pcall(writefile, "dq_enemies.json", HttpService:JSONEncode(list))
end)

-- Sweep what is already there, then watch.
for _, d in ipairs(workspace:GetDescendants()) do if attackLike(d) then recordPart(d) end end
R.conns[#R.conns + 1] = workspace.DescendantAdded:Connect(function(d)
    -- Parts arrive before their children are named/sized; look again next frame.
    task.defer(function() if d.Parent and attackLike(d) then recordPart(d) end end)
end)

-- Boss events and precast broadcasts, verbatim.
local function ser(v, depth)
    depth = depth or 0
    local ty = typeof(v)
    if ty == "CFrame" then return { cf = v3(v.Position), look = v3(v.LookVector) } end
    if ty == "Vector3" then return v3(v) end
    if ty == "Instance" then return "<" .. v.ClassName .. " " .. v.Name .. ">" end
    if ty == "Color3" then return v:ToHex() end
    if ty == "table" and depth < 3 then
        local o = {}
        for k, x in pairs(v) do o[tostring(k)] = ser(x, depth + 1) end
        return o
    end
    if ty == "number" then return r1(v) end
    return tostring(v)
end
local remote = RS.remotes:FindFirstChild("northernBossSpecficEvents")
if remote then
    R.conns[#R.conns + 1] = remote.OnClientEvent:Connect(function(name, args)
        R.events[#R.events + 1] = { t = now(), src = "northern", name = name, args = ser(args),
            serverNow = r1(workspace:GetServerTimeNow() - R.serverStart) }
    end)
end
pcall(function()
    local BN = require(RS.Utility.BridgeNet2)
    local bridge = BN.ReferenceBridge("precastHitbox")
    local id = BN.ReferenceIdentifier("action")
    R.conns[#R.conns + 1] = bridge:Connect(function(p)
        R.events[#R.events + 1] = { t = now(), src = "precast", name = p[id], args = ser({
            cframe = p.cframe, position = p.position, size = p.size, radius = p.radius,
            delayUntilAttack = p.delayUntilAttack, startTime = p.startTime,
            eta = p.delayUntilAttack and p.startTime and (p.delayUntilAttack - (workspace:GetServerTimeNow() - p.startTime)) or nil }) }
    end)
end)

-- Hits, with what was around us. Re-hooked on respawn.
local function hookHumanoid(c)
    local hum = c:WaitForChild("Humanoid", 10)
    if not hum then return end
    local last = hum.Health
    R.conns[#R.conns + 1] = hum.HealthChanged:Connect(function(h)
        if h < last - 1 then
            local rt = c:FindFirstChild("HumanoidRootPart")
            local near = {}
            if rt then
                for p, e in pairs(R.byPart) do
                    if p.Parent and not e.gone then
                        -- Distance to the part's BODY, not its centre: a 250-stud
                        -- beam's centre is far away while its body is on top of us.
                        local lpos = p.CFrame:PointToObjectSpace(rt.Position)
                        local hx, hy, hz = p.Size.X * 0.5, p.Size.Y * 0.5, p.Size.Z * 0.5
                        local ex = math.max(0, math.abs(lpos.X) - hx)
                        local ey = math.max(0, math.abs(lpos.Y) - hy)
                        local ez = math.max(0, math.abs(lpos.Z) - hz)
                        local d = math.sqrt(ex * ex + ey * ey + ez * ez)
                        if d <= 25 then near[#near + 1] = { name = e.name, model = e.model, dist = r1(d), inside = d == 0,
                            centre = r1((p.Position - rt.Position).Magnitude), t = r1(p.Transparency),
                            age = r1(now() - e.t), v = verdict(p) } end
                    end
                end
            end
            table.sort(near, function(a, b) return a.dist < b.dist end)
            R.hits[#R.hits + 1] = { t = now(), lost = math.floor(last - h), left = math.floor(h), fatal = h <= 0,
                enemy = S and S.NAV and S.NAV.cachedEnemy and S.NAV.cachedEnemy.Name or nil,
                state = S and S.RT and S.RT.movementState or nil, boost = S and S.RT and S.RT.moveBoost or nil,
                pos = rt and v3(rt.Position) or nil, near = near,
                dodge = S and S.DG and { target = S.DG.target and v3(S.DG.target) or nil, reason = S.DG.targetReason,
                    dangerHere = S.DG.dangerHere and r1(S.DG.dangerHere) or nil } or nil,
                readerLastHit = S and S.HZ and S.HZ.lastHitName or nil,
                -- The dodge's view at the instant: the cheapest candidates it had.
                cands = (function()
                    if not (S and S.DG and S.DG.cands and S.DG.order) then return nil end
                    local list = {}
                    for i = 1, math.min(#S.DG.order, 8) do
                        local c = S.DG.cands[S.DG.order[i]]
                        if c then list[#list + 1] = { dist = r1(c.dist or 0), danger = r1(c.danger or 0), cost = r1(c.cost or 0), valid = c.valid == true,
                            dx = rt and r1(c.x - rt.Position.X) or nil, dz = rt and r1(c.z - rt.Position.Z) or nil } end
                    end
                    return list
                end)(),
                -- How much of the field was open: candidates by danger band, and the safest few.
                field = (function()
                    if not (S and S.DG and S.DG.cands) then return nil end
                    local bands, safest = { safe = 0, warm = 0, hot = 0, invalid = 0 }, {}
                    for _, c in ipairs(S.DG.cands) do
                        if c.danger then
                            if c.valid == false or c.valid == nil then bands.invalid = bands.invalid + 1 end
                            if c.danger < 0.15 then bands.safe = bands.safe + 1 elseif c.danger < 0.6 then bands.warm = bands.warm + 1 else bands.hot = bands.hot + 1 end
                            safest[#safest + 1] = c
                        end
                    end
                    table.sort(safest, function(a, b) return (a.danger or 1) < (b.danger or 1) end)
                    local top = {}
                    for i = 1, math.min(4, #safest) do local c = safest[i]; top[i] = { dist = r1(c.dist or 0), danger = r1(c.danger or 0), valid = c.valid == true, dx = rt and r1(c.x - rt.Position.X) or nil, dz = rt and r1(c.z - rt.Position.Z) or nil } end
                    return { bands = bands, safest = top }
                end)(),
                dangerHere = S and S.DG and S.DG.dangerHere and r1(S.DG.dangerHere) or nil,
                bossDist = (function()
                    local e = S and S.NAV and S.NAV.cachedEnemy
                    local er = e and (e:FindFirstChild("HumanoidRootPart") or e.PrimaryPart)
                    if er and rt then local d = er.Position - rt.Position return r1(math.sqrt(d.X * d.X + d.Z * d.Z)) end
                end)() }
        end
        last = h
    end)
end
if char() then hookHumanoid(char()) end
R.conns[#R.conns + 1] = lp.CharacterAdded:Connect(function(c)
    R.events[#R.events + 1] = { t = now(), src = "respawn", name = "CharacterAdded" }
    hookHumanoid(c)
end)

function R.stop()
    for _, c in ipairs(R.conns) do pcall(function() c:Disconnect() end) end
    R.conns = {}
    R.stopped = now()
end

-- Progress against the target: its health once a second, and the bot's
-- movement state, so damage dealt and time spent can be read afterwards.
task.spawn(function()
    while _G.DQRec == R and not R.stopped do
        task.wait(1)
        local e = S and S.NAV and S.NAV.cachedEnemy
        local hum = e and e:FindFirstChildOfClass("Humanoid")
        if hum then
            local style = e:FindFirstChild("enemyStyle")
            local er = e:FindFirstChild("HumanoidRootPart") or e.PrimaryPart
            local rt = root()
            local bd = (er and rt) and (function() local d = er.Position - rt.Position return r1(math.sqrt(d.X * d.X + d.Z * d.Z)) end)() or nil
            R.bossHp[#R.bossHp + 1] = { t = now(), name = e.Name, hp = hum.Health, max = hum.MaxHealth, dist = bd,
                boss = style and type(style.Value) == "string" and style.Value:lower():find("boss") ~= nil or nil }
            if #R.bossHp > 2000 then table.remove(R.bossHp, 1) end
        end
        local st = S and ((S.RT and S.RT.movementState) or (S.UI and S.UI.movementStateLabel and S.UI.movementStateLabel.Text))
        if S and S.NAV then
            local N = S.NAV
            R.nav = R.nav or {}
            R.nav[#R.nav + 1] = { t = now(), wps = N.waypoints and #N.waypoints or 0, idx = N.index, direct = N.routeIsDirect, fails = N.failureStreak,
                dead = N.navmeshDeadUntil and N.navmeshDeadUntil > os.clock() or false, computing = N.computing, recompute = N.needsRecompute, driving = N.driving,
                blocked = S.DG and S.DG.pursuitBlocked, gap = S.DG and S.DG.gapWait, hub = S.DG and S.DG.hubHold, reason = S.DG and S.DG.targetReason, state = st }
            if #R.nav > 1200 then table.remove(R.nav, 1) end
        end
        local lastState = R.states[#R.states]
        if st and (not lastState or lastState.s ~= st) then
            R.states[#R.states + 1] = { t = now(), s = st }
            if #R.states > 600 then table.remove(R.states, 1) end
        end
    end
end)

-- Periodic save.
task.spawn(function()
    while _G.DQRec == R and not R.stopped do
        task.wait(10)
        pcall(function()
            writefile("dq_rec.json", HttpService:JSONEncode({ started = R.started, parts = R.parts, events = R.events, hits = R.hits, bossHp = R.bossHp, states = R.states, enemies = R.enemies, nav = R.nav }))
        end)
    end
end)

return { ok = true, loaded = S ~= nil, version = _G.DungeonAutofarmVersion, existingParts = #R.parts,
         northernRemote = remote ~= nil, dungeon = workspace:FindFirstChild("dungeonName") and workspace.dungeonName.Value or nil }
