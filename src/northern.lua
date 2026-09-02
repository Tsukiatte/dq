-- northern.lua - Northern Lands: the bosses announce themselves, exactly.
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
-- NORTHERN LANDS (4.6.0)
--
-- Read from the game's own client script (mapSpecificLocals, the handler for
-- ReplicatedStorage.remotes.northernBossSpecficEvents) and the models in
-- ReplicatedStorage.enemyProjectiles, live in Studio. Every timed attack of
-- the three bosses and the bonus boss is sent to the client BEFORE it happens
-- with the numbers the client uses to animate it - and those numbers are the
-- attack:
--
--   projectiles   { distance, duration, startTime, endTime, startCFrame }
--                 position(t) = start + look * clamp((t - startTime) / duration) * distance
--   ground spikes { "small"|"medium"|"large", cframe, fireTime }
--   orb beams     cframe; a pillar that lives six seconds
--   tall swirly   { colour, fireTime }; the arena explodes, the matching
--                 colour safe spot is the only place to be
--
-- Times are on the game's timeSync clock (ReplicatedStorage.timeSync, a
-- MasterClock/SlaveClock pair synced to the server's tick()). We require the
-- same module, so we read the same clock.
--
-- Scripted projectiles go into PC.paths: the dodge asks where each one WILL
-- be at the moment it would be somewhere, which beats extrapolating a mesh
-- from two frames of motion. Timed ground attacks become precast zones with
-- exact impact times, and pillars are zones held open for their lifetime.
-- The bonus boss's colour spots become timed safe windows - outside them is
-- the danger, but only around the explosion.
-- =========================================================================

local NL = {
    connection = nil,
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
        halfWidth = halfWidth, halfLength = halfLength, halfHeight = halfHeight,
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
    heavyDebugThrottled("nl_event", 0.5, "Northern", text)
end

local function isArgs(args, n)
    return type(args) == "table" and #args >= n
end

-- ------------------------------------------------------------ handlers
local HANDLERS = {}

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
    addSafeWindow(spots, fireAt - CFG.northernSafeLead, fireAt + 0.8, "swirly " .. tostring(colour))
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

-- ------------------------------------------------------------ per-frame
local function step()
    if not NL.connection then return end
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
                    circleZone("bonus flame", root.Position, 17.5, nowG + CFG.northernFlameDelay, 1.0)
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
local function startNorthernListener()
    if NL.connection or not CFG.useNorthern then return NL.connection ~= nil end
    local ok, err = pcall(function()
        local ts = ReplicatedStorage:FindFirstChild("timeSync")
        if ts then NL.timeSync = require(ts) end
        local remotes = ReplicatedStorage:WaitForChild("remotes", 5)
        local remote = remotes and remotes:FindFirstChild("northernBossSpecficEvents")
        if not remote then error("northernBossSpecficEvents not found") end
        NL.connection = remote.OnClientEvent:Connect(function(name, args)
            local handler = HANDLERS[name]
            if not handler then return end
            local hok, herr = pcall(handler, args)
            if not hok then
                heavyDebugThrottled("nl_handler", 2.0, "Northern", "Handler for '" .. tostring(name) .. "' threw: " .. tostring(herr))
            end
        end)
    end)
    if ok then
        heavyDebug("Northern", "Listening to the Northern Lands bosses" .. (NL.timeSync and " on the game's clock." or " (no timeSync; using local time)."))
        return true
    end
    heavyDebug("Northern", "Could not hook the boss events: " .. tostring(err))
    return false
end

local function stopNorthernListener()
    if NL.connection then NL.connection:Disconnect() NL.connection = nil end
    table.clear(PC.paths)
    table.clear(PC.safeWindows)
    table.clear(NL.flameTracks)
end

S.NL = NL
S.startNorthernListener = startNorthernListener
S.stopNorthernListener = stopNorthernListener
S.northernStep = step
end
