-- mover.lua - The character goes where it is told, on its own legs.
-- Module contract: receives the shared table S; imports from core.
--
-- Every move is a Humanoid walk (hum:Move), so the server sees a body that
-- walks: legal speed, real collisions, real falls. The 4.12 tween and the
-- 5.1.0 per-frame CFrame write both ended in anti-cheat kicks (an instant hop,
-- a lag-spike jump, a ledge snapped down in one frame). Leaving danger raises
-- WalkSpeed to CFG.tweenEscape for the burst - the client checker only resets
-- values above 45, and 4.12.14 ran the boss approach at 22 for whole runs -
-- and puts it back the moment the burst ends.
return function(S)
local CFG = S.CFG
local RT = S.RT
local LocalPlayer = S.LocalPlayer

local MV = { driving = false, controlsOff = false, lastTarget = nil, facedAt = -math.huge, stallSince = nil, lastPos = nil,
    counts = { arrive = 0, walked = 0, jump = 0, boost = 0 } }
local function count(k) MV.counts[k] = (MV.counts[k] or 0) + 1 end

local function setControls(enabled)
    if MV.controlsOff == (not enabled) then return end
    local ok = pcall(function()
        local scripts = LocalPlayer:FindFirstChild("PlayerScripts")
        local module = scripts and scripts:FindFirstChild("PlayerModule")
        if not module then return end
        local controls = require(module):GetControls()
        if enabled then controls:Enable() else controls:Disable() end
    end)
    if ok then MV.controlsOff = not enabled end
end

-- The burst: WalkSpeed raised while leaving danger, restored after. The value
-- it had is remembered once per burst, so the game's own changes survive.
local function setBoost(hum, on)
    if on then
        if not RT.walkSpeedBefore then
            RT.walkSpeedBefore = hum.WalkSpeed
            count("boost")
        end
        if hum.WalkSpeed ~= CFG.tweenEscape then hum.WalkSpeed = CFG.tweenEscape end
    elseif RT.walkSpeedBefore then
        pcall(function() hum.WalkSpeed = RT.walkSpeedBefore end)
        RT.walkSpeedBefore = nil
    end
end

-- Walk toward `target`. A `speed` above the Humanoid's own WalkSpeed is a
-- burst; one below it walks proportionally slower. Returns true within `arrive`.
local function driveTo(hum, root, target, speed, arrive)
    if not hum or not root then return false end
    arrive = arrive or 1.0
    local pos = root.Position
    local flat = Vector3.new(target.X - pos.X, 0, target.Z - pos.Z)
    local distance = flat.Magnitude
    MV.driving = true
    MV.lastTarget = target
    setControls(false)
    local walk = RT.walkSpeedBefore or hum.WalkSpeed
    if not RT.walkSpeedBefore then RT.walkSpeed = walk end
    setBoost(hum, speed > walk + 0.5)
    if distance <= arrive then
        count("arrive")
        hum:Move(Vector3.zero, false)
        MV.stallSince = nil
        return true
    end
    count("walked")
    -- Face where we go unless the brain aimed us this frame.
    local aimed = os.clock() - MV.facedAt < 0.25
    if hum.AutoRotate == aimed then hum.AutoRotate = not aimed end
    local scale = math.clamp(speed / math.max(hum.WalkSpeed, 1), 0.15, 1)
    hum:Move(flat.Unit * scale, false)
    -- Standing against something for half a second: a hop.
    local now = os.clock()
    if MV.lastPos and (pos - MV.lastPos).Magnitude < 0.05 then
        MV.stallSince = MV.stallSince or now
        if now - MV.stallSince > 0.5 then
            count("jump")
            hum.Jump = true
            MV.stallSince = now
        end
    else
        MV.stallSince = nil
    end
    MV.lastPos = pos
    return false
end

local function face(root, hum, point)
    if not root then return end
    local p = root.Position
    local look = Vector3.new(point.X - p.X, 0, point.Z - p.Z)
    if look.Magnitude < 0.5 then return end
    MV.facedAt = os.clock()
    if hum and hum.AutoRotate then hum.AutoRotate = false end
    root.CFrame = CFrame.lookAt(p, p + look.Unit)
end

local function release(hum, root)
    if MV.driving then
        MV.driving = false
        if hum then hum:Move(Vector3.zero, false) end
    end
    if hum then
        setBoost(hum, false)
        if not hum.AutoRotate then hum.AutoRotate = true end
    end
    MV.stallSince, MV.lastPos = nil, nil
    setControls(true)
end

local function restoreWalkSpeed(hum)
    if hum then setBoost(hum, false) end
end

S.MV = MV
S.driveTo = driveTo
S.faceToward = face
S.releaseMover = release
S.restoreWalkSpeed = restoreWalkSpeed
S.setMoveControls = setControls
end
