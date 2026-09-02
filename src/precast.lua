-- precast.lua - Listening to the game announce its own attacks.
-- Module contract: receives the shared table S. Everything this module needs from
-- earlier modules is pulled into locals below; everything later modules need is
-- assigned onto S at the bottom. Load order is fixed by main.lua / build.py.
return function(S)
local RT = S.RT
local CFG = S.CFG
local PC = S.PC
local Workspace = S.Workspace
local ReplicatedStorage = S.ReplicatedStorage
local heavyDebug = S.heavyDebug
local heavyDebugThrottled = S.heavyDebugThrottled
local getVisualRoot = S.getVisualRoot

-- =========================================================================
-- PRECAST HITBOX LISTENER (3.0.0)
--
-- The game hands the client every ground attack before it lands. See
-- game/GAME_NOTES.md; the short version is that
-- ReplicatedStorage.modules.PrecastHitbox listens on a BridgeNet2 bridge
-- called "precastHitbox" and builds the telegraph locally from a payload:
--
--   action            "Cube" | "Circle"
--   cframe, size      the cube, already oriented and placed
--   position, radius  the circle
--   startTime         workspace:GetServerTimeNow() when the server cast it
--   delayUntilAttack  seconds from startTime until it hits
--
-- So time-to-impact is arithmetic, not something to learn from being hit:
--     eta = delayUntilAttack - (GetServerTimeNow() - startTime)
--
-- This matters more than it sounds. The part the game builds starts at
-- Transparency 1 - fully invisible - with CanQuery false, parented straight to
-- workspace with no distinguishing parent, and only fades in over 0.15s. It is
-- close to the worst case for an appearance scorer and trivial for a listener.
--
-- BridgeNet2 is an ordinary ModuleScript in ReplicatedStorage, so we require
-- the same module the game does and connect to the same bridge. No packet
-- parsing, no namecall hook, and it costs nothing per frame.
--
-- Everything here is wrapped in pcall and degrades to "no zones" if the game
-- changes: the appearance scorer stays underneath as the fallback.
-- =========================================================================

local function clearZones()
    table.clear(PC.zones)
    if PC.folder then PC.folder:Destroy() end
    PC.folder = nil
    table.clear(PC.parts)
end

local function zoneFolder()
    if PC.folder and PC.folder.Parent then return PC.folder end
    local folder = Instance.new("Folder")
    folder.Name = "PrecastZones"
    folder.Parent = getVisualRoot()
    PC.folder = folder
    return folder
end

-- Our own drawing of a zone. The game's part is invisible for the first
-- fraction of a second, which is exactly the window that matters, so we draw
-- our own and colour it by how long is left.
local function drawZone(zone)
    if not CFG.showPrecast then return end
    local part = Instance.new("Part")
    part.Anchored = true
    part.CanCollide = false
    part.CanQuery = false
    part.CanTouch = false
    part.CastShadow = false
    part.Material = Enum.Material.Neon
    part.Transparency = 0.72
    part.Color = CFG.colorPrecastEarly
    if zone.shape == "Circle" then
        part.Shape = Enum.PartType.Cylinder
        part.Size = Vector3.new(0.4, zone.radius * 2, zone.radius * 2)
        part.CFrame = CFrame.new(zone.position) * CFrame.Angles(0, 0, math.rad(90))
    else
        part.Shape = Enum.PartType.Block
        part.Size = Vector3.new(zone.size.X, 0.4, zone.size.Z)
        part.CFrame = zone.cframe
    end
    part.Parent = zoneFolder()
    zone.part = part
    PC.parts[#PC.parts + 1] = part
end

-- Distance from a point to the zone's footprint, flat. Negative-ish inside.
local function distanceToZone(zone, position)
    if zone.shape == "Circle" then
        local d = Vector3.new(position.X - zone.position.X, 0, position.Z - zone.position.Z)
        return d.Magnitude - zone.radius, math.abs(position.Y - zone.position.Y)
    end
    -- Cube: measure in the zone's own frame so rotation is respected.
    local localPos = zone.cframe:PointToObjectSpace(position)
    local hx, hz = zone.size.X * 0.5, zone.size.Z * 0.5
    local dx = math.max(math.abs(localPos.X) - hx, 0)
    local dz = math.max(math.abs(localPos.Z) - hz, 0)
    return Vector2.new(dx, dz).Magnitude, math.abs(localPos.Y)
end

-- Is `position` clear of every announced attack, `atTime` seconds from now?
--
-- A zone that will already have resolved by then is not a threat, and one that
-- has not started yet still is - you have to be out of it when it lands, not
-- when it was announced. That is the whole value of the ETA: the bot can walk
-- across a marker that fires in 1.2 seconds to reach real safety, instead of
-- treating every marker as an equal wall and getting cornered.
-- `dwell` asks the question over an interval: "would I be safe there from the
-- moment I arrive until `dwell` seconds later?" Asking about a single instant
-- is what let the bot walk somewhere, stop, and be killed by an attack that
-- was already announced - at the instant it arrived, the cell really was safe.
local function isPositionSafeFromPrecast(position, clearance, atTime, dwell)
    atTime = atTime or 0
    local from, to = atTime, atTime + (dwell or 0)
    local now = Workspace:GetServerTimeNow()
    for _, zone in ipairs(PC.zones) do
        local eta = zone.impactAt - now
        -- The zone hurts during [eta, eta + linger]; we are there during
        -- [from, to]. Danger is the two intervals overlapping.
        if eta <= to and (eta + CFG.precastLingerTime) >= from
            and eta < CFG.precastHorizon + to then
            local flat, vertical = distanceToZone(zone, position)
            if flat < clearance and (CFG.hazardIgnoreVertical or vertical < 14) then
                return false, zone, eta
            end
        end
    end
    return true
end

-- Soonest impact among the zones covering this point, or nil.
local function precastTimeToImpact(position, clearance)
    local now = Workspace:GetServerTimeNow()
    local soonest = nil
    for _, zone in ipairs(PC.zones) do
        local eta = zone.impactAt - now
        if eta > -CFG.precastLingerTime and eta < CFG.precastHorizon then
            local flat, vertical = distanceToZone(zone, position)
            if flat < clearance and (CFG.hazardIgnoreVertical or vertical < 14) then
                if not soonest or eta < soonest then soonest = eta end
            end
        end
    end
    return soonest
end

-- Drops zones whose attack has resolved, and recolours the rest by urgency.
local function precastStep()
    -- Northern Lands housekeeping rides on the same clock. Late-bound: that
    -- module loads after this one.
    if S.northernStep then S.northernStep() end
    -- Keep the Attacks panel honest. It used to be rendered once at build and
    -- never again, so it read zero however many attacks had gone past.
    if #PC.zones ~= PC.lastShown or PC.total ~= PC.lastTotal then
        PC.lastShown, PC.lastTotal = #PC.zones, PC.total
        if S.refreshPrecastPanel then S.refreshPrecastPanel() end
    end
    if #PC.zones == 0 then return end
    local now = Workspace:GetServerTimeNow()
    for i = #PC.zones, 1, -1 do
        local zone = PC.zones[i]
        local eta = zone.impactAt - now
        if eta < -(CFG.precastLingerTime + (zone.holdFor or 0)) then
            if zone.part then zone.part:Destroy() end
            table.remove(PC.zones, i)
        elseif zone.part and zone.part.Parent then
            -- Warm as it approaches, so an imminent zone reads at a glance.
            local t = math.clamp(1 - (eta / math.max(zone.delay, 0.01)), 0, 1)
            zone.part.Color = CFG.colorPrecastEarly:Lerp(CFG.colorPrecastImminent, t)
        end
    end
end

local function addZone(zone)
    zone.impactAt = zone.startTime + zone.delay
    -- One zone per identical footprint and time: a boss firing a ring of them
    -- sends many, and they are all real, but an exact duplicate is a resend.
    table.insert(PC.zones, zone)
    if #PC.zones > CFG.precastMaxZones then
        local dropped = table.remove(PC.zones, 1)
        if dropped.part then dropped.part:Destroy() end
    end
    drawZone(zone)
    PC.total = PC.total + 1
end

-- Connects to the game's own bridge. Safe to call repeatedly; only the first
-- successful connection sticks.
local function startPrecastListener()
    if PC.connection or PC.failed then return PC.connection ~= nil end

    local ok, err = pcall(function()
        local utility = ReplicatedStorage:FindFirstChild("Utility")
        local moduleScript = utility and utility:FindFirstChild("BridgeNet2")
        if not moduleScript then error("BridgeNet2 not found", 0) end

        local BridgeNet2 = require(moduleScript)
        local bridge = BridgeNet2.ReferenceBridge("precastHitbox")
        -- BridgeNet2 compresses string keys, so the action key on the wire is
        -- not the literal string.
        local actionKey = BridgeNet2.ReferenceIdentifier("action")
        PC.bridge = bridge

        PC.connection = bridge:Connect(function(data)
            PC.received = PC.received + 1
            if type(data) ~= "table" then
                heavyDebugThrottled("precast_type", 5.0, "Precast",
                    "Payload was a " .. typeof(data) .. ", not a table.")
                return
            end

            -- The first few payloads get printed key by key. If the wire format
            -- is not what was read out of the decompiled module, this is where
            -- it shows, instead of the handler silently dropping everything.
            if PC.received <= 3 then
                local keys = {}
                for k, v in pairs(data) do
                    keys[#keys + 1] = tostring(k) .. "=" .. (typeof(v) == "table" and "table" or tostring(v))
                end
                heavyDebug("Precast", string.format("Payload #%d: %s",
                    PC.received, table.concat(keys, "  ")))
            end

            local action = data[actionKey] or data.action
            -- BridgeNet2 compresses string keys, and the identifier we ask for
            -- may not be the one the server used. The shape name is distinctive
            -- enough to find on its own.
            if action ~= "Cube" and action ~= "Circle" then
                for _, v in pairs(data) do
                    if v == "Cube" or v == "Circle" then action = v break end
                end
            end
            local delay = tonumber(data.delayUntilAttack)
            local startTime = tonumber(data.startTime)
            if not action or not delay or not startTime then
                heavyDebugThrottled("precast_shape", 5.0, "Precast", string.format(
                    "Payload not understood (action=%s delay=%s startTime=%s). The wire format has changed; see game/GAME_NOTES.md.",
                    tostring(action), tostring(delay), tostring(startTime)))
                return
            end

            if action == "Circle" and typeof(data.position) == "Vector3" then
                addZone({ shape = "Circle", position = data.position,
                          radius = tonumber(data.radius) or 8,
                          delay = delay, startTime = startTime })
            elseif action == "Cube" and typeof(data.cframe) == "CFrame" then
                addZone({ shape = "Cube", cframe = data.cframe,
                          size = typeof(data.size) == "Vector3" and data.size or Vector3.new(8, 8, 8),
                          delay = delay, startTime = startTime })
            end
        end)
    end)

    if ok and PC.connection then
        PC.failed = false
        heavyDebug("Precast", "Listening to the game's own attack broadcast. "
            .. "Every ground attack now arrives with its exact shape and time to impact.")
        return true
    end

    PC.failed = true
    heavyDebug("Precast", "Could not attach to the precastHitbox bridge ("
        .. tostring(err) .. "). Falling back to appearance scoring.")
    return false
end

local function stopPrecastListener()
    if PC.connection then
        pcall(function() PC.connection:Disconnect() end)
    end
    PC.connection = nil
    PC.bridge = nil
    PC.failed = false
    clearZones()
end

S.startPrecastListener = startPrecastListener
S.stopPrecastListener = stopPrecastListener
S.precastStep = precastStep
S.isPositionSafeFromPrecast = isPositionSafeFromPrecast
S.precastTimeToImpact = precastTimeToImpact
S.clearPrecastZones = clearZones
S.addPrecastZone = addZone
end
