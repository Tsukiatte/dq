-- bossevents.lua - The bosses announce themselves, exactly: one listener per map remote.
-- Module contract: receives the shared table S. Everything this module needs from
-- earlier modules is pulled into locals below; everything later modules need is
-- assigned onto S at the bottom. Load order is fixed by main.lua / build.py.
return function(S)
local RT = S.RT
local CFG = S.CFG
local PC = S.PC
local HZ = S.HZ
local Workspace = S.Workspace
local ReplicatedStorage = S.ReplicatedStorage
local LocalPlayer = S.LocalPlayer
local heavyDebug = S.heavyDebug
local heavyDebugThrottled = S.heavyDebugThrottled
local addPrecastZone = S.addPrecastZone

local max, min, abs = math.max, math.min, math.abs

-- =========================================================================
-- BOSS EVENTS (4.6.0 Northern Lands, 4.7.0 every map)
--
-- Read from the game's own client script (mapSpecificLocals) and the models in
-- ReplicatedStorage.enemyProjectiles, live in Studio. Each map's bosses talk to
-- the client over their own RemoteEvent in ReplicatedStorage.remotes -
-- northernBossSpecficEvents, steampunkBossSpecficEvents, and so on - plus a
-- shared mapSpecificEvent. Every timed attack is sent BEFORE it happens with
-- the numbers the client animates it with, and those numbers are the attack:
--
--   projectiles   { distance, duration, startTime, endTime, startCFrame }
--                 position(t) = start + look * clamp((t - startTime) / duration) * distance
--   ground spikes { "small"|"medium"|"large", cframe, fireTime }
--   orb beams     cframe; a pillar that lives six seconds
--   tall swirly   { colour, fireTime }; the arena explodes, the matching
--                 colour safe spot is the only place to be
--   drop cogs     a container of cog models, each tweened down 100 studs in 0.75s
--   back flames   a model of flameParts, lit 0.5s after the event for 1s
--
-- Times are on the game's timeSync clock (ReplicatedStorage.timeSync, a
-- MasterClock/SlaveClock pair synced to the server's tick()). We require the
-- same module, so we read the same clock.
--
-- Scripted projectiles go into PC.paths: the dodge asks where each one WILL
-- be at the moment it would be somewhere. Timed ground attacks become precast
-- zones with exact impact times, pillars are zones held open for their
-- lifetime, and colour spots become timed safe windows. Attacks the server
-- spawns as Models (precast + hitBox) need none of this: the arming pass in
-- hazards.lua reads their precast. A few of those get their arming delay
-- seeded here from measurement so even the first cast is time-aware.
-- =========================================================================

local NL = {
    connections = {},       -- [remote name] = RBXScriptConnection
    timeSync = nil,
    total = 0,
    flameTracks = {},       -- { player, endsAt (game clock) }
    lastLog = -math.huge,
}

local function gameClock()
    local ts = NL.timeSync
    if ts then
        local ok, t = pcall(function() return ts:GetTime() end)
        if ok and type(t) == "number" then return t end
    end
    return tick()
end

-- A game-clock timestamp, as an offset from now on the server clock the
-- precast zones use.
local function serverAt(gameTime)
    return Workspace:GetServerTimeNow() + (gameTime - gameClock())
end

local function circleZone(name, position, radius, fireGame, holdFor)
    local now = gameClock()
    addPrecastZone({
        shape = "Circle", position = position, radius = radius,
        startTime = Workspace:GetServerTimeNow(), delay = fireGame - now,
        holdFor = holdFor, source = name,
    })
end

local function cubeZone(name, cframe, size, fireGame, holdFor)
    local now = gameClock()
    addPrecastZone({
        shape = "Cube", cframe = cframe, size = size,
        startTime = Workspace:GetServerTimeNow(), delay = fireGame - now,
        holdFor = holdFor, source = name,
    })
end

-- A thing that moves along a line on a schedule. halfWidth is across the
-- direction of travel, halfLength along it; offset shifts it along the line.
local function addPath(name, cframe, distance, duration, t0, t1, halfWidth, halfLength, halfHeight, offset)
    local look = cframe.LookVector
    local flat = Vector3.new(look.X, 0, look.Z)
    if flat.Magnitude < 0.01 then flat = Vector3.new(0, 0, -1) end
    flat = flat.Unit
    PC.paths[#PC.paths + 1] = {
        name = name,
        ox = cframe.Position.X, oy = cframe.Position.Y, oz = cframe.Position.Z,
        dx = flat.X, dz = flat.Z,
        dist = distance, dur = max(duration, 0.01),
        t0 = serverAt(t0), t1 = serverAt(t1),
        spawn = Workspace:GetServerTimeNow(),
        -- A rolling body's centre rides its radius above the floor; the
        -- vertical test must reach down to the feet from there.
        halfWidth = halfWidth, halfLength = halfLength, halfHeight = max(halfHeight, halfWidth, halfLength),
        offset = offset or 0,
    }
    if #PC.paths > 64 then table.remove(PC.paths, 1) end
end

local SWIRLY_COLOURS = {
    red = Color3.fromRGB(255, 78, 78),
    yellow = Color3.fromRGB(255, 250, 94),
    green = Color3.fromRGB(78, 255, 69),
}

local function colourDistance(a, b)
    return abs(a.R - b.R) + abs(a.G - b.G) + abs(a.B - b.B)
end

-- The bonus boss's colour spots: whichever of them are nearest the named
-- colour are the safe ones for this explosion.
local function safeSpotsFor(colourName)
    local want = SWIRLY_COLOURS[colourName]
    local folder = Workspace:FindFirstChild("bonusBossColorSafeSpots")
    if not want or not folder then return {} end
    local parts = {}
    for _, child in ipairs(folder:GetDescendants()) do
        if child:IsA("BasePart") and child.Size.X >= 6 and colourDistance(child.Color, want) < 0.35 then
            parts[#parts + 1] = child
        end
    end
    return parts
end

local function addSafeWindow(parts, fromGame, untilGame, name)
    if #parts == 0 then return end
    PC.safeWindows[#PC.safeWindows + 1] = {
        parts = parts, from = serverAt(fromGame), untilAt = serverAt(untilGame), name = name,
    }
end

local function log(text)
    NL.total = NL.total + 1
    heavyDebugThrottled("boss_event", 0.5, "Bosses", text)
end

local function isArgs(args, n)
    return type(args) == "table" and #args >= n
end

-- ------------------------------------------------------------ handlers
-- [remote name] = { [event name] = function(args) }
local REMOTES = {}
local HANDLERS = {}
REMOTES["northernBossSpecficEvents"] = HANDLERS

-- First boss: rolling projectiles down a line.
HANDLERS["First Boss Criss Cross Projectile"] = function(a)
    if not isArgs(a, 5) then return end
    addPath("criss cross", a[5], a[1], a[2], a[3], a[4], 7.5, 7.5, 8)
    log("Criss cross projectile: " .. tostring(math.floor(a[1])) .. " studs over " .. string.format("%.1fs", a[2]))
end
HANDLERS["First Boss Seeking Spike"] = function(a)
    if not isArgs(a, 5) then return end
    addPath("seeking spike", a[5], a[1], a[2], a[3], a[4], 10, 10, 4)
    log("Seeking spike along its beam")
end
HANDLERS["First Boss Big Spike"] = function(a)
    if not isArgs(a, 5) then return end
    -- Invisible until startTime, then rolls. Live from startTime.
    addPath("big spike", a[5], a[1], a[2], a[3], a[4], 20, 20, 6)
    log("Big spike: rolling from " .. string.format("%.1fs", a[3] - gameClock()))
end

-- Second boss: ice.
local SPIKE_RADIUS = { small = 15, medium = 25, large = 40 }
HANDLERS["Second Boss Big Hitting Ground Spikes"] = function(a)
    if not isArgs(a, 3) or typeof(a[2]) ~= "CFrame" then return end
    local radius = SPIKE_RADIUS[a[1]] or 25
    -- Spikes rise over 0.1s, hold 0.25s, fade 0.3s.
    circleZone("ground spikes " .. tostring(a[1]), a[2].Position, radius, a[3], 0.7)
    log(string.format("Ground spikes (%s, r=%d) in %.1fs", tostring(a[1]), radius, a[3] - gameClock()))
end
HANDLERS["Second Boss Moving Beam"] = function(a)
    if not isArgs(a, 5) then return end
    -- A bar 57 studs wide, sweeping along its look vector and rolling.
    addPath("moving beam", a[5], a[1], a[2], a[3], a[4], 29, 4, 6)
    log(string.format("Moving beam: %d studs over %.1fs", math.floor(a[1]), a[2]))
end

-- Third boss.
HANDLERS["Third Boss Bouncing Orb Beam"] = function(a)
    if typeof(a) ~= "CFrame" then return end
    circleZone("orb beam", a.Position, 12, gameClock(), 6)
    log("Bouncing orb beam pillar, 6s")
end
HANDLERS["Third Boss Sideways Missile"] = function(a)
    if not isArgs(a, 5) then return end
    -- 10 wide, 30 long, travelling along look with a ten stud head start.
    addPath("sideways missile", a[5], a[1], a[2], a[3], a[4], 5, 15, 6, -10)
    log(string.format("Sideways missile: %d studs over %.1fs", math.floor(a[1]), a[2]))
end

-- Mobs in the boss rooms.
local function lineStrike(cframe, name)
    if typeof(cframe) ~= "CFrame" then return end
    -- The strike part grows to 31 long and slides 65 studs behind the cframe.
    local centre = cframe - cframe.LookVector * 50
    cubeZone(name, centre, Vector3.new(11, 4, 100), gameClock(), 0.5)
end
HANDLERS["Spearman Strike"] = function(a) lineStrike(a, "spearman strike") end
HANDLERS["Warrior Line Strike"] = function(a) lineStrike(a, "warrior strike") end

-- Bonus boss.
HANDLERS["Bonus Boss Tall Swirly"] = function(a)
    if not isArgs(a, 2) then return end
    local colour, fireAt = a[1], a[2]
    local middle = Workspace:FindFirstChild("thirdBossMiddlePart")
    if middle and middle:IsA("BasePart") then
        circleZone("tall swirly", middle.Position, 130, fireAt, 0.8)
    end
    local spots = safeSpotsFor(colour)
    addSafeWindow(spots, fireAt - CFG.bossSafeLead, fireAt + 0.8, "swirly " .. tostring(colour))
    log(string.format("Tall swirly (%s) in %.1fs; %d safe spot(s)", tostring(colour), fireAt - gameClock(), #spots))
end
HANDLERS["Bonus Boss Flame Pre Target"] = function(a)
    if not isArgs(a, 2) then return end
    -- A marker follows a player until endTime; the flame lands where the
    -- marker is then. The marker itself is not the damage.
    NL.flameTracks[#NL.flameTracks + 1] = { player = a[1], endsAt = a[2] }
    log(string.format("Flame targeting %s for %.1fs", tostring(a[1] and a[1].Name), a[2] - gameClock()))
end
HANDLERS["Bonus Boss Freezing Orb Beam"] = function(a)
    if typeof(a) ~= "CFrame" then return end
    circleZone("freezing orb beam", a.Position, 12, gameClock(), 6)
    log("Freezing orb beam pillar, 6s")
end


-- ------------------------------------------------------------ Steampunk Sewers
-- The Evil Scientist's kit is mostly server-spawned Models - the six-beam
-- pulse wave (the lattice), the concentric outward blasts, the punch circle,
-- the zig-zag, the orb shot, the cannon and horizontal beams - and the arming
-- pass reads those. The remote adds the cogs and the flames, which have no
-- precast of their own, and the pulse ball.
local SP = {}
REMOTES["steampunkBossSpecficEvents"] = SP

SP["Drop Cogs"] = function(container)
    if typeof(container) ~= "Instance" then return end
    -- Every part of every cog is tweened 100 studs straight down over 0.75s.
    -- Where it will be is where it is now, minus a hundred.
    local count = 0
    local fire = gameClock() + 0.75
    for _, cog in ipairs(container:GetChildren()) do
        if cog:IsA("Model") then
            for _, part in ipairs(cog:GetChildren()) do
                if part:IsA("BasePart") then
                    local landing = part.CFrame - Vector3.new(0, 100, 0)
                    local size = part.Size
                    cubeZone("cog", landing, Vector3.new(size.X + 3, size.Y, size.Z + 3), fire, 0.6)
                    count = count + 1
                end
            end
        end
    end
    log(string.format("Cogs dropping: %d part(s) land in 0.75s", count))
end

SP["Second Boss Random Pulse"] = function(model)
    -- The ball. Its precast is brightened 0.2s after it appears, which the
    -- arming pass already reads as live; this just names it in the log.
    if typeof(model) == "Instance" then log("Pulse ball at " .. tostring(model:GetPivot().Position)) end
end

SP["Second Boss Pulse Wave"] = function()
    -- The client draws an expanding disc; the damage is the six beam Models
    -- the server spawns alongside, which arm through their precasts.
    log("Pulse wave (six beams follow)")
end

SP["Second Boss Aura"] = function()
    log("Aura for 4.8s")
end

-- Shared by every map.
local SHARED = {}
-- ------------------------------------------------------------ Aquatic Temple
-- From the place file's client handler (2026-09-02). The boss's attack
-- Models are renamed "Model" on the client, so their timing has to come from
-- the events, not the names.
local AQ = {}
REMOTES["aquaticBossSpecficEvents"] = AQ

local function osAt(gameTime)
    return os.clock() + (gameTime - gameClock())
end

-- Laser: {startTime, endTime, cframe, distance, boss, topIndex}. A precast
-- line Model (renamed "Model") is placed at the cframe; the beam runs along
-- it from startTime to endTime. Stamp that window on the Model, and keep a
-- zone as the belt to its braces.
AQ["first boss laser shot"] = function(a)
    if not isArgs(a, 4) or typeof(a[3]) ~= "CFrame" then return end
    local startT, endT, cf, distance = a[1], a[2], a[3], a[4]
    local stamped = S.stampAttackWindow and S.stampAttackWindow(cf.Position, 24, osAt(startT), osAt(endT))
    -- The line itself, as the event describes it: from the cframe, along
    -- its look, for the distance, for the whole of the sweep.
    local centre = cf + cf.LookVector * (distance * 0.5)
    cubeZone("laser", centre, Vector3.new(4.4, 8, math.max(distance, 4)), startT, math.max(endT - startT, 0.2))
    log(string.format("Laser: %d studs, %.1fs to %.1fs from now (%s)", math.floor(distance), startT - gameClock(), endT - gameClock(), stamped and "Model stamped" or "stamp held"))
end
-- Orbs: {cframe, startTime, endTime, distance, duration}: a Part renamed
-- "Model" (no hitBox, so the index never sees it) rolling along the look
-- vector. The path is the whole of the hazard.
local function movingOrb(name)
    return function(a)
        if not isArgs(a, 5) or typeof(a[1]) ~= "CFrame" then return end
        local r = CFG.aquaticOrbRadius
        addPath(name, a[1], a[4], a[5], a[2], a[3], r, r, r)
        log(string.format("%s: %d studs over %.1fs", name, math.floor(a[4]), a[5]))
    end
end
AQ["first boss moving orb"] = movingOrb("moving orb")
AQ["last boss moving orb"] = movingOrb("last boss orb")
-- Smite: a position; particles and a beam for 0.3 s.
AQ["third boss smite"] = function(a)
    local pos = typeof(a) == "CFrame" and a.Position or (typeof(a) == "Instance" and a:IsA("BasePart") and a.Position) or (typeof(a) == "Vector3" and a) or nil
    if not pos then return end
    circleZone("smite", pos, CFG.aquaticSmiteRadius, gameClock() + 0.1, 0.6)
    log("Smite")
end
-- The second boss shows workspace.secondBossDamageParts: each becomes a
-- zone for a few seconds.
AQ["second boss show damage parts"] = function()
    local folder = Workspace:FindFirstChild("secondBossDamageParts")
    if not folder then return end
    local n = 0
    for _, part in ipairs(folder:GetChildren()) do
        if part:IsA("BasePart") then
            cubeZone("damage part", part.CFrame, part.Size, gameClock() + 0.2, CFG.aquaticDamagePartHold)
            n = n + 1
        end
    end
    log(string.format("Second boss damage parts: %d zones", n))
end
AQ["last boss mark character"] = function(character)
    if typeof(character) == "Instance" and character == LocalPlayer.Character then
        log("Marked by the last boss")
    end
end

REMOTES["mapSpecificEvent"] = SHARED

SHARED["Steampunk Back Flames"] = function(model)
    if typeof(model) ~= "Instance" then return end
    -- flamePart children are lit 0.5s after the event and burn for 1s.
    local fire = gameClock() + 0.5
    local count = 0
    for _, part in ipairs(model:GetChildren()) do
        if part.Name == "flamePart" and part:IsA("BasePart") then
            local size = part.Size
            cubeZone("back flame", part.CFrame, Vector3.new(size.X + 4, size.Y, size.Z + 4), fire, 1.1)
            count = count + 1
        end
    end
    log(string.format("Back flames: %d jet(s) light in 0.5s", count))
end

-- ------------------------------------------------------------ per-frame
local function step()
    if next(NL.connections) == nil then return end
    local nowS = Workspace:GetServerTimeNow()
    for i = #PC.paths, 1, -1 do
        if nowS > PC.paths[i].t1 + 0.5 then table.remove(PC.paths, i) end
    end
    for i = #PC.safeWindows, 1, -1 do
        if nowS > PC.safeWindows[i].untilAt + 0.5 then table.remove(PC.safeWindows, i) end
    end
    if #NL.flameTracks > 0 then
        local nowG = gameClock()
        for i = #NL.flameTracks, 1, -1 do
            local track = NL.flameTracks[i]
            if nowG >= track.endsAt then
                -- Where the marker stops is where it lands, a moment later.
                local character = track.player and track.player.Character
                local root = character and character:FindFirstChild("HumanoidRootPart")
                if root then
                    circleZone("bonus flame", root.Position, 17.5, nowG + CFG.bossFlameDelay, 1.0)
                end
                table.remove(NL.flameTracks, i)
            end
        end
        -- The following marker is a marker: never a hazard in its own right.
        for _, part in ipairs(Workspace:GetChildren()) do
            if part.Name == "bonusBossFlamePreCast" and part:IsA("BasePart") then
                HZ.ownParts[part] = true
            end
        end
    end
end

-- ------------------------------------------------------------ hook
local function startBossEventListeners()
    if next(NL.connections) ~= nil or not CFG.useBossEvents then return next(NL.connections) ~= nil end
    local ok, err = pcall(function()
        local ts = ReplicatedStorage:FindFirstChild("timeSync")
        if ts then NL.timeSync = require(ts) end
        local remotes = ReplicatedStorage:WaitForChild("remotes", 5)
        if not remotes then error("ReplicatedStorage.remotes not found") end
        for remoteName, handlers in pairs(REMOTES) do
            local remote = remotes:FindFirstChild(remoteName)
            if remote and remote:IsA("RemoteEvent") then
                NL.connections[remoteName] = remote.OnClientEvent:Connect(function(name, args)
                    local handler = handlers[name]
                    if not handler then return end
                    local hok, herr = pcall(handler, args)
                    if not hok then
                        heavyDebugThrottled("boss_handler", 2.0, "Bosses", "Handler for '" .. tostring(name) .. "' threw: " .. tostring(herr))
                    end
                end)
            end
        end
    end)
    local hooked = {}
    for name in pairs(NL.connections) do hooked[#hooked + 1] = name end
    table.sort(hooked)
    if ok and #hooked > 0 then
        heavyDebug("Bosses", "Listening to " .. table.concat(hooked, ", ")
            .. (NL.timeSync and " on the game's clock." or " (no timeSync; using local time)."))
        return true
    end
    heavyDebug("Bosses", "Could not hook the boss events: " .. tostring(err or "no known remotes present"))
    return false
end

local function stopBossEventListeners()
    for name, connection in pairs(NL.connections) do
        connection:Disconnect()
        NL.connections[name] = nil
    end
    table.clear(PC.paths)
    table.clear(PC.safeWindows)
    table.clear(NL.flameTracks)
end

S.BE = NL
S.startBossEventListeners = startBossEventListeners
S.stopBossEventListeners = stopBossEventListeners
S.bossEventsStep = step
end
