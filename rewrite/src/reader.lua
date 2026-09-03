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
    walls = {},         -- [Model] = record for Bob's sweeping wall
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
local noteBeam, noteVolley, noteCircle
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
        minT = pc and pc.Transparency or 1, fired = false, pad = seed and seed.pad or 0, slim = seed and seed.slim or nil,
    }
    RD.count = RD.count + 1
    if hb and name:find("passivebeam", 1, true) then noteBeam(hb, now) end
    if hb and name:find("mageshot", 1, true) then noteVolley(hb, now) end
    if pc and name:find("cricle", 1, true) then noteCircle(pc, now) end
end

-- Bob's wall: a Model with two balls and a beam between them, sweeping
-- sideways at ~19 studs/s. Measured, not announced: the announcement's
-- path was a hundred studs from where the wall actually is.
local function trackWall(model)
    if RD.walls[model] then return end
    RD.walls[model] = { model = model, x = nil, z = nil, at = os.clock(), vx = 0, vz = 0 }
end

local function trackPart(part)
    if RD.parts[part] or RD.models[part.Parent] or isOurs(part) or ownedByPlayer(part) then return end
    if not part:IsA("BasePart") then return end
    if not isProjectileName(part.Name) then return end
    local p = part.Position
    RD.parts[part] = { part = part, x = p.X, z = p.Z, vx = 0, vz = 0, at = os.clock(), spawn = os.clock() }
end

-- Our own ability. The Geyser is placed on the target, or at the range cap
-- along the aim when the target is further: a geyser that lands short of a
-- far target measures the range (Chris: read the range, stand at it).
local function noteGeyser(model)
    task.defer(function()
        local castAt = RT.lastCastAt or -math.huge
        if os.clock() - castAt > 0.8 then return end
        local castPos, targetPos = RT.lastCastPos, RT.lastCastTargetPos
        local ring = model:FindFirstChild("geyserRing") or model:FindFirstChildWhichIsA("BasePart")
        if not castPos or not targetPos or not ring then return end
        local g = Vector3.new(ring.Position.X, 0, ring.Position.Z)
        local d = (g - Vector3.new(castPos.X, 0, castPos.Z)).Magnitude
        local toTarget = (g - Vector3.new(targetPos.X, 0, targetPos.Z)).Magnitude
        local targetD = (Vector3.new(targetPos.X, 0, targetPos.Z) - Vector3.new(castPos.X, 0, castPos.Z)).Magnitude
        if toTarget <= 8 then
            -- On the target: the range is at least this.
            if d > (RD.abilityReach or 0) then RD.abilityReach = math.floor(d + 0.5) end
        elseif targetD > d + 3 then
            -- Short of the target, along the aim: the cap.
            local cap = math.floor(d + 0.5)
            if cap >= 15 and cap <= 80 and cap > (RD.abilityRange or 0) then RD.abilityRange = cap end
        end
        -- A reach beyond the supposed cap means the cap was misread.
        if RD.abilityRange and RD.abilityReach and RD.abilityReach > RD.abilityRange + 2 then RD.abilityRange = nil end
    end)
end

local function consider(inst)
    if inst:IsA("Model") and inst.Name == "Geyser" then noteGeyser(inst) return end
    if inst:IsA("Model") and lower(inst.Name):find("movingbeam", 1, true) then trackWall(inst) return end
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

-- Bob's circles come as a chain marching outward from him along the line
-- through the player: one every 0.27 s, 22 studs further, 6 studs wider,
-- lethal about 0.6 s after each appears. The first circle fixes the whole
-- chain, so the rest of it becomes zones at once (Chris: run before it comes).
noteCircle = function(pc, now)
    local pos = pc.Position
    local size = math.max(pc.Size.Y, pc.Size.Z)
    local prev = RD.lastCircle
    RD.lastCircle = { t = now, pos = pos, size = size }
    local bob = nil
    for _, e in ipairs(RD.enemies) do if e.isBoss then bob = e break end end
    local dir, spacing, growth, dt, measured
    if prev and now - prev.t < 0.6 then
        local step = Vector3.new(pos.X - prev.pos.X, 0, pos.Z - prev.pos.Z)
        if step.Magnitude >= 8 and step.Magnitude <= 45 then
            dir, spacing, growth, dt, measured = step.Unit, step.Magnitude, size - prev.size, math.max(now - prev.t, 0.15), true
        end
    end
    if not dir and bob then
        -- First circle: the chain runs along the line through Bob, inward or
        -- outward; the line itself is the zone until the second circle says which.
        local out = Vector3.new(pos.X - bob.x, 0, pos.Z - bob.z)
        if out.Magnitude >= 5 then dir = out.Unit end
    end
    if not dir then return end
    for i = #RD.zones, 1, -1 do
        local z = RD.zones[i]
        if (z.name == "circle next" or z.name == "circle line") and z.madeAt < now - 0.2 then table.remove(RD.zones, i) end
    end
    -- The whole line is the attack: every circle of the chain lands on it, so
    -- the way out is sideways, never along it (Chris: left or right, not
    -- toward the smaller circle). The line is a soft band (never a spot to
    -- pick, but crossable: a hard line made every escape path read lethal and
    -- the choice arbitrary); the circles themselves carry the timing.
    local width = size + 6
    if measured and growth > 0 then width = size + growth * 9 + 6 end
    addZone({ name = "circle line", cframe = CFrame.lookAt(pos, pos + dir), size = Vector3.new(width, 12, 400), from = now, untilAt = now + 3.0, telegraphed = true, madeAt = now, weight = 0.5 })
    local function chain(d, sp, gr, step)
        for k = 1, 9 do
            local c = pos + d * (sp * k)
            local diam = size + gr * k + 6
            if diam < 16 then break end
            local at = now + step * k + 0.6
            addZone({ name = "circle next", cframe = CFrame.new(c.X, pos.Y, c.Z), size = Vector3.new(diam, 12, diam), round = true, from = at, untilAt = at + 1.0, telegraphed = true, madeAt = now })
        end
    end
    if measured then
        chain(dir, spacing, growth, dt)
    else
        -- Direction unknown until the second circle: both ways, circles wider
        -- away from Bob and narrower toward him (the wrong half is removed
        -- 0.27 s later).
        chain(dir, 22, 6, 0.27)
        chain(-dir, 22, -6, 0.27)
    end
end

-- A mage volley is a chain of shots marching from the mage toward the player,
-- one every tenth of a second, the last landing on the player. Two aligned
-- shots reveal the line; the rest of it becomes one zone at once, so the
-- field steps off the line instead of standing on it as the shots arrive.
noteVolley = function(hb, now)
    local prev = RD.lastShot
    local pos = hb.Position
    local look = hb.CFrame.LookVector
    RD.lastShot = { t = now, pos = pos, look = look }
    if not prev or now - prev.t > 0.4 then return end
    local step = pos - prev.pos
    local flat = Vector3.new(step.X, 0, step.Z)
    if flat.Magnitude < 6 or flat.Magnitude > 40 then return end
    local dir = flat.Unit
    for i = #RD.zones, 1, -1 do
        local z = RD.zones[i]
        if z.name == "volley next" and z.madeAt < now - 0.3 then table.remove(RD.zones, i) end
    end
    local length = 70
    local centre = Vector3.new(pos.X, pos.Y, pos.Z) + dir * (length * 0.5)
    local cf = CFrame.lookAt(centre, centre + dir)
    addZone({ name = "volley next", cframe = cf, size = Vector3.new(hb.Size.X, math.max(hb.Size.Y, 12), length), from = now + 0.3, untilAt = now + 2.2, telegraphed = true, madeAt = now })
end
noteBeam = function(hb, now)
    local look = hb.CFrame.LookVector
    local yaw = math.deg(math.atan2(look.X, look.Z)) % 180
    local beams = RD.beams
    beams[#beams + 1] = { t = now, yaw = yaw, hub = hb.Position, size = hb.Size }
    if #beams > 24 then table.remove(beams, 1) end
    local recent = 0
    for i = #beams, 1, -1 do if now - beams[i].t <= 0.5 then recent = recent + 1 else break end end
    if recent >= 4 then
        RD.fanUntil = now + 1.5
        -- Out to the edge: the lanes are 38 studs apart at 110 from the hub and
        -- 14 at 40. The reflex runs until the character is 100 studs out.
        RT.reflex = { name = "fan", from = hb.Position, radius = CFG.fanRadius, untilAt = now + 2.5 }
    end
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
    -- The slam is an instadeath 67 studs wide landing where announced: a zone
    -- for the field, and a reflex for the brain - straight out from the
    -- landing point at escape speed until clear (Chris: it HAS to get away).
    ["First Boss Jump Down"] = function(a)
        if typeof(a) == "Vector3" then
            circleZone("slam soon", a, 38, gameClock() + 2.5, 1.5)
            RT.reflex = { name = "slam", from = a, radius = 44, untilAt = os.clock() + 3.2 }
        end
    end,
    ["First Boss Criss Cross Projectile"] = function(a) if args(a, 5) then addPath("criss cross", a[5], a[1], a[2], a[3], a[4], 7.5, 7.5, 8) end end,
    ["First Boss Seeking Spike"] = function(a) if args(a, 5) then addPath("seeking spike", a[5], a[1], a[2], a[3], a[4], 10, 10, 4) end end,
    ["First Boss Big Spike"] = function(a) if args(a, 5) then addPath("big spike", a[5], a[1], a[2], a[3], a[4], 28, 28, 6) end end,
    ["Second Boss Big Hitting Ground Spikes"] = function(a)
        if args(a, 3) and typeof(a[2]) == "CFrame" then circleZone("ground spikes", a[2].Position, SPIKE_RADIUS[a[1]] or 25, a[3], 0.7) end
    end,
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
            if RD.leashBoss ~= e.model then RD.leashBoss = e.model RD.leashArmed = (_G.DungeonAutofarmLeashArmed == e.model) end
            if rt and not RD.leashArmed then
                local dx, dz = rt.Position.X - e.x, rt.Position.Z - e.z
                if dx * dx + dz * dz < 110 * 110 then RD.leashArmed = true _G.DungeonAutofarmLeashArmed = e.model end
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
    -- Bob's walls: centre from the balls, velocity from position.
    for model, w in pairs(RD.walls) do
        if not model.Parent then
            RD.walls[model] = nil
        else
            local b1 = model:FindFirstChild("ball1")
            local b2 = model:FindFirstChild("ball2")
            local p1 = b1 and b1:FindFirstChildWhichIsA("BasePart")
            local p2 = b2 and b2:FindFirstChildWhichIsA("BasePart")
            if p1 and p2 then
                local c = (p1.Position + p2.Position) * 0.5
                local dt = now - w.at
                if w.x and dt > 0.08 then
                    w.vx, w.vz = (c.X - w.x) / dt, (c.Z - w.z) / dt
                    w.x, w.z, w.at = c.X, c.Z, now
                elseif not w.x then
                    w.x, w.z, w.at = c.X, c.Z, now
                end
                w.cx, w.cz, w.cy = c.X, c.Z, c.Y
                local axis = p1.Position - p2.Position
                w.halfLen = axis.Magnitude * 0.5 + 4
            end
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
            if speed < 1 then r.stillSince = r.stillSince or now else r.stillSince = nil end
            -- Spent when faded and still, or simply still for a while: a thrown
            -- spear lying in the ground blocked the field for five seconds.
            if (part.Transparency >= CFG.spentTransparency and speed < 1 and now - r.spawn > 0.5)
                or (r.stillSince and now - r.stillSince > 0.6 and now - r.spawn > 0.8) then
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
            local isCyl = anchor:IsA("Part") and anchor.Shape == Enum.PartType.Cylinder
            if anchor == r.pc and r.hb == nil and not isCyl then size = Vector3.new(size.X, math.max(size.Y, 10), size.Z) end
            if r.pad > 0 then
                if isCyl then size = Vector3.new(size.X, size.Y + r.pad * 2, size.Z + r.pad * 2)
                else size = Vector3.new(size.X + r.pad * 2, size.Y, size.Z + r.pad * 2) end
            end
            out[#out + 1] = { cframe = anchor.CFrame, size = size, round = isCyl and anchor.Size.Y == anchor.Size.Z, cyl = isCyl,
                from = r.from, untilAt = r.long and huge or r.untilAt, name = r.name, kind = "model", slim = r.slim }
        end
    end
    for part, r in pairs(RD.parts) do
        local speed = math.sqrt(r.vx * r.vx + r.vz * r.vz)
        local size = part.Size
        local half = math.max(size.X, size.Z) * 0.5
        if lower(part.Name):find("bigspike", 1, true) then half = half + 8 end   -- kills 4-7 studs outside its mesh
        if speed > 2 then
            r.stillSince = nil
            out[#out + 1] = { moving = true, ox = part.Position.X, oy = part.Position.Y, oz = part.Position.Z,
                dx = r.vx / speed, dz = r.vz / speed, speed = speed, offset = 0, halfW = half, halfL = half, halfH = math.max(size.Y * 0.5, 6),
                from = now, untilAt = now + CFG.projectileLookahead, pathStart = now, name = part.Name, kind = "part" }
        else
            -- A projectile that has stopped is a hazard for one more second, not
            -- for as long as it lies in the ground (a spear blocked a lane for 5 s).
            r.stillSince = r.stillSince or now
            if now - r.stillSince < 1.0 then
                out[#out + 1] = { cframe = part.CFrame, size = Vector3.new(size.X, math.max(size.Y, 8), size.Z), from = now, untilAt = now + 1.0, name = part.Name, kind = "part" }
            end
        end
    end
    for _, w in pairs(RD.walls) do
        if w.cx then
            local speed = math.sqrt(w.vx * w.vx + w.vz * w.vz)
            if speed > 2 then
                out[#out + 1] = { moving = true, ox = w.cx, oy = w.cy, oz = w.cz, dx = w.vx / speed, dz = w.vz / speed, speed = speed, offset = 0,
                    halfW = w.halfLen or 30, halfL = 6, halfH = 10, ground = true, from = now, untilAt = now + 20, pathStart = now, name = "wall", kind = "wall" }
            else
                out[#out + 1] = { cframe = CFrame.new(w.cx, w.cy, w.cz), size = Vector3.new((w.halfLen or 30) * 2, 12, 12), from = now, untilAt = now + 1, name = "wall", kind = "wall" }
            end
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
