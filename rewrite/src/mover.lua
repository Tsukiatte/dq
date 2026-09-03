-- mover.lua - The character goes where it is told: a tween along the floor.
-- Module contract: receives the shared table S; imports from core.
--
-- Writes the root's CFrame each frame, never further than `speed * dt`, along
-- the floor (a raycast under the next point), stopping short of anything
-- solid at knee or chest height. The Humanoid's WalkSpeed is untouched; the
-- default control module is disabled while we drive and handed back after.
return function(S)
local CFG = S.CFG
local RT = S.RT
local Workspace = S.Workspace
local LocalPlayer = S.LocalPlayer
local raycastParams = S.raycastParams
local heavyDebug = S.heavyDebug

local MV = { driving = false, controlsOff = false, lastTarget = nil }
local PROBE_HEIGHTS = { 1.2, 2.6 }

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

-- Step toward `target` at `speed` studs/s. Returns true when within `arrive`.
local function driveTo(hum, root, target, speed, arrive)
    if not hum or not root then return false end
    arrive = arrive or 1.0
    local pos = root.Position
    local flat = Vector3.new(target.X - pos.X, 0, target.Z - pos.Z)
    local distance = flat.Magnitude
    MV.driving = true
    MV.lastTarget = target
    if distance <= arrive then
        root.AssemblyLinearVelocity = Vector3.new(0, root.AssemblyLinearVelocity.Y, 0)
        return true
    end
    setControls(false)
    local direction = flat.Unit
    -- A lag spike must never become a jump: the step is capped at what a 30 fps
    -- frame allows, and a spike frame writes nothing at all. A kick followed
    -- exactly this shape once - lag, a fall through the floor, a jump.
    local dt = RT.frameDelta
    if dt > 0.12 then return false end
    local step = math.min(speed * math.min(dt, 1 / 30), distance)
    local params = raycastParams(nil)

    -- The root rides above the floor by a measured amount, not an assumed one.
    local above = hum.HipHeight + root.Size.Y * 0.5
    local under = Workspace:Raycast(pos, Vector3.new(0, -(above + 4), 0), params)
    if not under then
        -- Nothing under us: falling, or the floor did not answer. Hold; never
        -- write a position while airborne.
        return false
    end
    above = pos.Y - under.Position.Y
    local feetY = pos.Y - above

    -- Anything wall-like across the step, at knee and at chest.
    for _, h in ipairs(PROBE_HEIGHTS) do
        local hit = Workspace:Raycast(Vector3.new(pos.X, feetY + h, pos.Z), direction * (step + 0.6), params)
        if hit then
            local rise = hit.Position.Y - feetY
            local wall = h > 2.0 or rise > CFG.maxStepHeight or hit.Normal.Y < 0.5
            if wall then
                local room = Vector3.new(hit.Position.X - pos.X, 0, hit.Position.Z - pos.Z).Magnitude - 0.6
                if room <= 0.05 then
                    -- Flat against it: the Humanoid knows how to slide along a wall.
                    hum:MoveTo(target)
                    return false
                end
                step = math.min(step, room)
            end
        end
    end

    local nx, nz = pos.X + direction.X * step, pos.Z + direction.Z * step
    local floorHit = Workspace:Raycast(Vector3.new(nx, feetY + CFG.maxStepHeight + 0.5, nz),
        Vector3.new(0, -(CFG.maxStepHeight + 0.5 + CFG.maxDropHeight), 0), params)
    if not floorHit then
        -- No floor there: hold rather than step off. The Humanoid is not asked
        -- to walk either; a ledge is a decision for the field, not the mover.
        return false
    end
    local rise = floorHit.Position.Y - feetY
    if rise > CFG.maxStepHeight then
        hum.Jump = true
        hum:MoveTo(target)
        return false
    end
    root.CFrame = CFrame.new(Vector3.new(nx, floorHit.Position.Y + above, nz)) * (root.CFrame - root.CFrame.Position)
    root.AssemblyLinearVelocity = Vector3.zero
    return false
end

local function face(root, hum, point)
    if not root then return end
    local p = root.Position
    local look = Vector3.new(point.X - p.X, 0, point.Z - p.Z)
    if look.Magnitude < 0.5 then return end
    root.CFrame = CFrame.lookAt(p, p + look.Unit)
end

local function release(hum, root)
    if MV.driving then
        MV.driving = false
        if root then root.AssemblyLinearVelocity = Vector3.new(0, root.AssemblyLinearVelocity.Y, 0) end
    end
    if hum then hum:Move(Vector3.zero, false) end
    setControls(true)
end

local function restoreWalkSpeed(hum)
    if RT.walkSpeedBefore and hum then
        pcall(function() hum.WalkSpeed = RT.walkSpeedBefore end)
        RT.walkSpeedBefore = nil
    end
end

S.MV = MV
S.driveTo = driveTo
S.faceToward = face
S.releaseMover = release
S.restoreWalkSpeed = restoreWalkSpeed
S.setMoveControls = setControls
end
