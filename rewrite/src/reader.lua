-- reader.lua - Everything that can hurt, as boxes with live windows.
-- Module contract: receives the shared table S; imports from core only.
--
-- Four sources, one shape. A hazard is an oriented box (cframe, size) that
-- hurts from `from` until `until` on os.clock(). A moving hazard also carries a
-- flat velocity and its box is swept along it. The field never asks what a
-- thing is; it asks where and when.
--
--   Model attacks   hitBox (invisible damage volume) + precast (visible
--                   warning), parented to workspace. Timing by name from the
--                   seeds; a precast that fades means "fired", and fade plus a
--                   linger means "over" unless the seed says it burns on.
--   Bare parts      criss cross, strike meshes, orbs: a moving part is the box
--                   it sweeps over the next second. Faded and still = spent.
--   Boss remotes    scripted attacks announced with distance, duration,
--                   start/end on the game clock and an origin CFrame.
--   precastHitbox   the game's own ground telegraphs, exact impact time.
return function(S)
local CFG = S.CFG
local RT = S.RT
local TIMING = S.TIMING
local PROJECTILE_HINTS = S.PROJECTILE_HINTS
local Workspace = S.Workspace
local ReplicatedStorage = S.ReplicatedStorage
local Players = S.Players
local LocalPlayer = S.LocalPlayer
local heavyDebug = S.heavyDebug
local heavyDebugThrottled = S.heavyDebugThrottled
local isOurs = S.isOurs

local RD = {
    models = {},        -- [Model] = record
    parts = {},         -- [BasePart] = record (bare projectiles)
    zones = {},         -- announced: { cframe, size, from, until, moving? }
    enemies = {},       -- { model, root, humanoid, isBoss, melee, extent, x, z, vx, vz }
    connections = {},
    lastSweep = -math.huge,
    lastEnemyScan = -math.huge,
    timeSync = nil,
    count = 0,
    beams = {},         -- recent passive-beam spawns: { t, yaw, hub, size }
    fanUntil = -math.huge, -- the beam fan is on until this os.clock()
}

local lower = string.lower
local huge = math.huge

-- ------------------------------------------------------------ clocks
local function gameClock()
    local ts = RD.timeSync
    if ts then
        local ok, t = pcall(function() return ts:GetTime() end)
        if ok and type(t) == "number" then return t end
    end
    return Workspace:GetServerTimeNow()
end
-- A game-clock or server-clock time, as os.clock().
local function fromGame(t) return os.clock() + (t - gameClock()) end
local function fromServer(t) return os.clock() + (t - Workspace:GetServerTimeNow()) end

-- ------------------------------------------------------------ names
local function isProjectileName(name)
    local n = lower(name)
    for _, hint in ipairs(PROJECTILE_HINTS) do
        if n:find(hint, 1, true) then return true end
    end
    return false
end

local function findPart(model, ...)
    for _, name in ipairs({ ... }) do
        local p = model:FindFirstChild(name)
        if p and p:IsA("BasePart") then return p end
    end
    for _, d in ipairs(model:GetChildren()) do
        if d:IsA("BasePart") then
            local n = lower(d.Name)
            for _, name in ipairs({ ... }) do
                if n:find(lower(name), 1, true) then return d end
            end
        end
    end
    return nil
end

local function ownedByPlayer(inst)
    local node = inst
    for _ = 1, 4 do
        node = node and node.Parent
        if not node then break end
        if node:IsA("Model") and Players:GetPlayerFromCharacter(node) then return true end
    end
    return false
end

-- ------------------------------------------------------------ model attacks
local noteBeam
local function trackModel(model)
    if RD.models[model] or isOurs(model) or ownedByPlayer(model) then return end
    if model:FindFirstChildOfClass("Humanoid") then return end
    local hb = findPart(model, "hitBox", "hitbox")
    local pc = findPart(model, "precast", "preCast")
    if not hb and not pc then return end
    local name = lower(model.Name)
    local seed = TIMING[name]
    local now = os.clock()
    local first = seed and seed.first or (pc and CFG.defaultFire or 0)
    local last = seed and seed.last or (first + CFG.defaultLive)
    RD.models[model] = {
        model = model, hb = hb, pc = pc, name = name, spawn = now,
        from = now + first, untilAt = now + last, long = seed ~= nil and seed.long == true, holdFull = seed ~= nil and seed.holdFull == true,
        minT = pc and pc.Transparency or 1, fired = false,
    }
    RD.count = RD.count + 1
    if hb and name:find("passivebeam", 1, true) then noteBeam(hb, now) end
end

local function trackPart(part)
    if RD.parts[part] or RD.models[part.Parent] or isOurs(part) or ownedByPlayer(part) then return end
    if not part:IsA("BasePart") then return end
    if not isProjectileName(part.Name) then return end
    local p = part.Position
    RD.parts[part] = { part = part, x = p.X, z = p.Z, vx = 0, vz = 0, at = os.clock(), spawn = os.clock() }
end

local function consider(inst)
    if inst:IsA("Model") then
        trackModel(inst)
    elseif inst:IsA("BasePart") then
        if inst.Parent == Workspace then
            trackPart(inst)
        else
            local model = inst:FindFirstAncestorOfClass("Model")
            if model and (inst.Name:lower():find("hitbox", 1, true) or inst.Name:lower():find("precast", 1, true)) then
                trackModel(model)
            end
        end
    end
end

-- ------------------------------------------------------------ boss remotes
local function addZone(z)
    RD.zones[#RD.zones + 1] = z
    if #RD.zones > 96 then table.remove(RD.zones, 1) end
end

-- The Champion's passive beams (8 x 250 through the hub, lethal from the
-- moment they appear) come in two rhythms. Slow: one every half second,
-- each 20 degrees on from the last - a sweep, so the next two lanes are
-- known and go in as zones. Fast: eighteen a second for seven seconds with
-- shifting offsets - a fan nothing inside 125 studs survives; the brain backs
-- out past the beams' reach while RD.fanUntil holds.
local function wrap180(a) a = a % 180 if a > 90 then a = a - 180 end return a end
noteBeam = function(hb, now)
    local look = hb.CFrame.LookVector
    local yaw = math.deg(math.atan2(look.X, look.Z)) % 180
    local beams = RD.beams
    beams[#beams + 1] = { t = now, yaw = yaw, hub = hb.Position, size = hb.Size }
    if #beams > 24 then table.remove(beams, 1) end
    local recent = 0
    for i = #beams, 1, -1 do if now - beams[i].t <= 0.5 then recent = recent + 1 else break end end
    if recent >= 4 then RD.fanUntil = now + 1.5 end
    -- Predictions older than half a second are stale, whatever came of them.
    for i = #RD.zones, 1, -1 do
        local z = RD.zones[i]
        if z.name == "beam next" and z.madeAt < now - 0.5 then table.remove(RD.zones, i) end
    end
    -- Several sweeps run at once, interleaved: each new beam is matched to any
    -- recent beam 20 degrees away, and that chain's next two lanes are zones.
    local b = beams[#beams]
    local chains = 0
    for i = #beams - 1, 1, -1 do
        local a = beams[i]
        local dt = b.t - a.t
        if dt > 0.8 then break end
        local step = wrap180(b.yaw - a.yaw)
        if dt >= 0.08 and math.abs(step) >= 15 and math.abs(step) <= 25 then
            chains = chains + 1
            for k = 1, 2 do
                local yawK = math.rad(b.yaw + step * k)
                local at = now + dt * k
                local cf = CFrame.lookAt(b.hub, b.hub + Vector3.new(math.sin(yawK), 0, math.cos(yawK)))
                addZone({ name = "beam next", cframe = cf, size = b.size, from = at, untilAt = at + 2.0, telegraphed = true, madeAt = now })
            end
            if chains >= 2 then break end
        end
    end
end
-- A body rolling along a line: origin, direction, distance over duration from
-- t0 to t1 (game clock). Half sizes across / along / up. Boxed at the moment
-- asked for by the field.
local function addPath(name, cframe, distance, duration, t0, t1, halfW, halfL, halfH, offset)
    local look = cframe.LookVector
    local flat = Vector3.new(look.X, 0, look.Z)
    if flat.Magnitude < 0.01 then flat = Vector3.new(0, 0, -1) end
    flat = flat.Unit
    local speed = distance / math.max(duration, 0.01)
    addZone({
        name = name, moving = true,
        ox = cframe.Position.X, oy = cframe.Position.Y, oz = cframe.Position.Z,
        dx = flat.X, dz = flat.Z, speed = speed, offset = offset or 0,
        halfW = halfW, halfL = halfL, halfH = math.max(halfH, 6), ground = true,
        from = fromGame(t0), untilAt = fromGame(t1), pathStart = fromGame(t0),
    })
end
local function cubeZone(name, cframe, size, fireGame, holdFor)
    addZone({ name = name, cframe = cframe, size = size, from = fromGame(fireGame), untilAt = fromGame(fireGame) + holdFor, telegraphed = true })
end
local function circleZone(name, position, radius, fireGame, holdFor)
    addZone({ name = name, cframe = CFrame.new(position), size = Vector3.new(radius * 2, 12, radius * 2), round = true,
        from = fromGame(fireGame), untilAt = fromGame(fireGame) + holdFor, telegraphed = true })
end

local SPIKE_RADIUS = { small = 15, medium = 25, large = 40 }
local function args(a, n) return type(a) == "table" and #a >= n end
local HANDLERS = {
    -- The jump's target is where the 67-stud slam lands about 2.5 s later; the
    -- slam Model itself appears only at landing.
    ["First Boss Jump Down"] = function(a) if typeof(a) == "Vector3" then circleZone("slam soon", a, 33.5, gameClock() + 2.5, 1.5) end end,
    ["First Boss Criss Cross Projectile"] = function(a) if args(a, 5) then addPath("criss cross", a[5], a[1], a[2], a[3], a[4], 7.5, 7.5, 8) end end,
    ["First Boss Seeking Spike"] = function(a) if args(a, 5) then addPath("seeking spike", a[5], a[1], a[2], a[3], a[4], 10, 10, 4) end end,
    ["First Boss Big Spike"] = function(a) if args(a, 5) then addPath("big spike", a[5], a[1], a[2], a[3], a[4], 20, 20, 6) end end,
    ["Second Boss Big Hitting Ground Spikes"] = function(a)
        if args(a, 3) and typeof(a[2]) == "CFrame" then circleZone("ground spikes", a[2].Position, SPIKE_RADIUS[a[1]] or 25, a[3], 0.7) end
    end,
    ["Second Boss Moving Beam"] = function(a) if args(a, 5) then addPath("moving beam", a[5], a[1], a[2], a[3], a[4], 29, 4, 6) end end,
    ["Third Boss Bouncing Orb Beam"] = function(a) if typeof(a) == "CFrame" then circleZone("orb beam", a.Position, 12, gameClock(), 6) end end,
    ["Third Boss Sideways Missile"] = function(a) if args(a, 5) then addPath("sideways missile", a[5], a[1], a[2], a[3], a[4], 5, 15, 6, -10) end end,
}
local function lineStrike(cframe, name)
    if typeof(cframe) ~= "CFrame" then return end
    -- The strike mesh grows to 31 long and slides 65 studs behind the cframe.
    cubeZone(name, cframe - cframe.LookVector * 50, Vector3.new(11, 6, 100), gameClock(), 0.6)
end
HANDLERS["Spearman Strike"] = function(a) lineStrike(a, "spearman strike") end
HANDLERS["Warrior Line Strike"] = function(a) lineStrike(a, "warrior strike") end

local function connectRemotes()
    local folder = ReplicatedStorage:FindFirstChild("remotes")
    if not folder then return end
    for _, r in ipairs(folder:GetChildren()) do
        if r:IsA("RemoteEvent") and r.Name:find("BossSpecficEvents", 1, true) then
            RD.connections[#RD.connections + 1] = r.OnClientEvent:Connect(function(name, a)
                local h = HANDLERS[name]
                if h then
                    local ok, err = pcall(h, a)
                    if not ok then heavyDebugThrottled("evt_err", 2, "Reader", tostring(name) .. ": " .. tostring(err)) end
                end
            end)
        end
    end
end

-- The game's own ground telegraphs: exact shape, exact impact time.
local function connectPrecastBridge()
    pcall(function()
        local util = ReplicatedStorage:WaitForChild("Utility", 5)
        local BN = require(util:WaitForChild("BridgeNet2", 5))
        local bridge = BN.ReferenceBridge("precastHitbox")
        local id = BN.ReferenceIdentifier("action")
        RD.connections[#RD.connections + 1] = bridge:Connect(function(p)
            if type(p) ~= "table" then return end
            local eta = (p.delayUntilAttack or 0) - (Workspace:GetServerTimeNow() - (p.startTime or Workspace:GetServerTimeNow()))
            local fire = os.clock() + eta
            if p[id] == "Circle" and p.position then
                addZone({ name = "circle", cframe = CFrame.new(p.position), size = Vector3.new((p.radius or 5) * 2, 12, (p.radius or 5) * 2), round = true, from = fire, untilAt = fire + 0.45, telegraphed = true })
            elseif p.cframe and p.size then
                addZone({ name = "cube", cframe = p.cframe, size = Vector3.new(p.size.X, math.max(p.size.Y, 12), p.size.Z), from = fire, untilAt = fire + 0.45, telegraphed = true })
            end
        end)
    end)
end

-- ------------------------------------------------------------ enemies
local function scanEnemies(now)
    local list = {}
    local me = LocalPlayer.Character
    local function visit(folder)
        for _, m in ipairs(folder:GetChildren()) do
            if m:IsA("Model") and m ~= me then
                local hum = m:FindFirstChildOfClass("Humanoid")
                if hum and hum.Health > 0 and not Players:GetPlayerFromCharacter(m) then
                    local root = m:FindFirstChild("HumanoidRootPart") or m.PrimaryPart
                    if root then
                        local style = m:FindFirstChild("enemyStyle")
                        local melee = m:FindFirstChild("meleeDistance")
                        local prev = RD.enemyPrev and RD.enemyPrev[m]
                        local p = root.Position
                        local vx, vz = 0, 0
                        if prev and now > prev.at then
                            vx, vz = (p.X - prev.x) / (now - prev.at), (p.Z - prev.z) / (now - prev.at)
                        end
                        local extent = math.max(root.Size.X, root.Size.Z) * 0.5
                        list[#list + 1] = {
                            model = m, root = root, humanoid = hum,
                            isBoss = style and type(style.Value) == "string" and lower(style.Value):find("boss", 1, true) ~= nil or false,
                            melee = melee and type(melee.Value) == "number" and melee.Value <= CFG.meleeMobMaxReach or false,
                            meleeDistance = melee and type(melee.Value) == "number" and melee.Value or 4,
                            extent = extent, x = p.X, y = p.Y, z = p.Z, vx = vx, vz = vz,
                        }
                    end
                end
            elseif m:IsA("Folder") or (m:IsA("Model") and m.Name:find("room", 1, true)) then
                visit(m)
            end
        end
    end
    local dungeon = Workspace:FindFirstChild("dungeon")
    if dungeon then visit(dungeon) end
    local enemies = Workspace:FindFirstChild("enemies")
    if enemies then visit(enemies) end
    RD.enemyPrev = RD.enemyPrev or setmetatable({}, { __mode = "k" })
    for _, e in ipairs(list) do RD.enemyPrev[e.model] = { x = e.x, z = e.z, at = now } end
    RD.enemies = list
    -- The Champion's arena kills past about 128 studs from him: every death
    -- out there had nothing near it, and the respawn point is 131-137 out.
    -- The leash arms once the character has been inside the arena (within
    -- 110 studs) and stays armed for that boss; the walk in from room 2 must
    -- not see the band as a wall. Hopping at its outer edge cost a whole run.
    RD.leash = nil
    local rt = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    for _, e in ipairs(list) do
        if e.isBoss and e.model.Name == "Midgardian Champion" then
            if RD.leashBoss ~= e.model then RD.leashBoss = e.model RD.leashArmed = false end
            if rt and not RD.leashArmed then
                local dx, dz = rt.Position.X - e.x, rt.Position.Z - e.z
                if dx * dx + dz * dz < 110 * 110 then RD.leashArmed = true end
            end
            if RD.leashArmed then RD.leash = { enemy = e, radius = CFG.leashRadius } end
            break
        end
    end
end

-- ------------------------------------------------------------ tick
local function readerTick(now)
    -- New instances arrive through DescendantAdded; a cheap sweep every quarter
    -- second catches anything that was renamed or moved in afterwards.
    if now - RD.lastSweep > 0.25 then
        RD.lastSweep = now
        for _, c in ipairs(Workspace:GetChildren()) do
            if c:IsA("Model") or c:IsA("BasePart") then consider(c) end
        end
    end
    -- Model attacks: fade means fired; fade + linger means over.
    for model, r in pairs(RD.models) do
        if not model.Parent or (r.hb and not r.hb.Parent and r.pc and not r.pc.Parent) then
            RD.models[model] = nil
        else
            local pc = r.pc
            if pc and pc.Parent then
                local tr = pc.Transparency
                if tr < r.minT then r.minT = tr end
                if not r.fired and r.minT < 0.9 and tr > r.minT + 0.08 and tr >= 0.9 then
                    r.fired = true
                    if now < r.from then r.from = now end
                    if not r.long and not r.holdFull then r.untilAt = math.min(r.untilAt, math.max(now + CFG.fadeLinger, r.from + 0.2)) end
                end
            end
            if now > r.untilAt + 0.5 then RD.models[model] = nil end
        end
    end
    -- Bare projectiles: velocity from position; spent when faded and still.
    for part, r in pairs(RD.parts) do
        if not part.Parent then
            RD.parts[part] = nil
        else
            local p = part.Position
            local dt = now - r.at
            if dt > 0.08 then
                r.vx, r.vz = (p.X - r.x) / dt, (p.Z - r.z) / dt
                r.x, r.z, r.at = p.X, p.Z, now
            end
            local speed = math.sqrt(r.vx * r.vx + r.vz * r.vz)
            if part.Transparency >= CFG.spentTransparency and speed < 1 and now - r.spawn > 0.5 then
                RD.parts[part] = nil
            end
        end
    end
    -- Announced zones: gone half a second after they end.
    for i = #RD.zones, 1, -1 do
        if now > RD.zones[i].untilAt + 0.5 then table.remove(RD.zones, i) end
    end
    if now - RD.lastEnemyScan > 0.5 then
        RD.lastEnemyScan = now
        pcall(scanEnemies, now)
    end
end

-- Every hazard as a box the field can test. Static boxes carry cframe/size and
-- a window; moving ones carry an origin, a direction, a speed and half sizes.
local function hazards(now)
    local out = {}
    for _, r in pairs(RD.models) do
        local anchor = (r.hb and r.hb.Parent) and r.hb or ((r.pc and r.pc.Parent) and r.pc or nil)
        if anchor then
            local size = anchor.Size
            if anchor == r.pc and r.hb == nil then size = Vector3.new(size.X, math.max(size.Y, 10), size.Z) end
            local isCyl = anchor:IsA("Part") and anchor.Shape == Enum.PartType.Cylinder
            out[#out + 1] = { cframe = anchor.CFrame, size = size, round = isCyl and anchor.Size.Y == anchor.Size.Z, cyl = isCyl,
                from = r.from, untilAt = r.long and huge or r.untilAt, name = r.name, kind = "model" }
        end
    end
    for part, r in pairs(RD.parts) do
        local speed = math.sqrt(r.vx * r.vx + r.vz * r.vz)
        local size = part.Size
        local half = math.max(size.X, size.Z) * 0.5
        if speed > 2 then
            out[#out + 1] = { moving = true, ox = part.Position.X, oy = part.Position.Y, oz = part.Position.Z,
                dx = r.vx / speed, dz = r.vz / speed, speed = speed, offset = 0, halfW = half, halfL = half, halfH = math.max(size.Y * 0.5, 6),
                from = now, untilAt = now + CFG.projectileLookahead, pathStart = now, name = part.Name, kind = "part" }
        else
            out[#out + 1] = { cframe = part.CFrame, size = Vector3.new(size.X, math.max(size.Y, 8), size.Z), from = now, untilAt = huge, name = part.Name, kind = "part" }
        end
    end
    for _, z in ipairs(RD.zones) do out[#out + 1] = z end
    return out
end

local function start()
    pcall(function()
        local ts = ReplicatedStorage:FindFirstChild("timeSync")
        if ts then RD.timeSync = require(ts) end
    end)
    RD.connections[#RD.connections + 1] = Workspace.DescendantAdded:Connect(function(d)
        task.defer(function() if d.Parent then pcall(consider, d) end end)
    end)
    connectRemotes()
    connectPrecastBridge()
    heavyDebug("Reader", "listening")
end

local function stop()
    for _, c in ipairs(RD.connections) do pcall(function() c:Disconnect() end) end
    RD.connections = {}
end

S.RD = RD
S.readerTick = readerTick
S.hazards = hazards
S.readerStart = start
S.readerStop = stop
S.gameClock = gameClock
end
