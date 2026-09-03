-- mover.lua - How the character is actually made to go somewhere.
-- Module contract: receives the shared table S. Everything this module needs from
-- earlier modules is pulled into locals below; everything later modules need is
-- assigned onto S at the bottom. Load order is fixed by main.lua / build.py.
return function(S)
local RT = S.RT
local Workspace = S.Workspace
local CFG = S.CFG
local NAV = S.NAV
local heavyDebug = S.heavyDebug
local getRaycastExclusions = S.getRaycastExclusions
local hitBlocksWalking = S.hitBlocksWalking

-- Knee and chest, above the feet. A riser sits under the knee ray and reads
-- as a step; a plinth or a wall reaches the chest ray and reads as a wall.
local TWEEN_PROBE_HEIGHTS = { 1.2, 2.6 }

-- =========================================================================
-- THE ACTUATOR (3.6.0)
--
-- Every dodge in this script was issued as Humanoid:MoveTo, and that turns out
-- to be most of why the dodging looks broken regardless of how good the
-- decision was.
--
-- MoveTo is pathing-and-walking built for getting somewhere eventually. It:
--
--   * accelerates from a standstill, taking roughly a quarter of a second to
--     reach WalkSpeed - in a fight where telegraphs land in 0.7s, a quarter of
--     that budget is gone before the character has really started moving;
--   * arrives only within about two studs, which in a three-stud gap between
--     two beams means standing on the edge of one;
--   * re-plans internally each time it is called, so re-issuing it every frame
--     restarts the acceleration;
--   * slides along geometry rather than routing, so a wall turns a dodge into
--     a scrape.
--
-- "Stands in the middle of attacks", "goes to the edge of an attack instead of
-- around it", "barely keeps its distance from walls" are all descriptions of
-- an ACTUATOR failing, not of a decision failing. The grid can pick the
-- perfect cell and MoveTo will still put you a couple of studs off it, a
-- quarter of a second late.
--
-- So the mover is now a choice:
--
--   walk      Humanoid:MoveTo. What it always did. Safest, least precise.
--   steer     Humanoid:Move each frame, which is the DEFAULT. No arrival
--             tolerance and no re-planning - most of what was wrong with
--             MoveTo - and it cannot stall, because it is the Humanoid driving
--             itself through its own API.
--   velocity  Humanoid:Move plus a direct write of the assembly's horizontal
--             velocity, so direction changes land the same frame with no
--             acceleration ramp. Both must be told the SAME direction; telling
--             the Humanoid to stop while writing a velocity is an instruction
--             to brake, re-applied every physics step, and the Humanoid wins.
--   tween     Moves the root's CFrame straight toward the target. Exact to the
--             stud and instantaneous, and it ignores collision entirely, which
--             is both why it is precise and why it is conspicuous. It is the
--             closest thing to what a script that "tweens to a marker" is
--             doing.
-- =========================================================================

-- Roblox's own control module drives the Humanoid every frame from input, so
-- the Move-based modes need it out of the way or they are simply overruled.
-- Only touched when one of those modes is actually in use, and always handed
-- back, because taking the player's controls away permanently would be a
-- nasty thing to leave behind.
local function setControlsEnabled(enabled)
    if RT.controlsDisabled == (not enabled) then return end
    local ok = pcall(function()
        local scripts = S.LocalPlayer:FindFirstChild("PlayerScripts")
        local module = scripts and scripts:FindFirstChild("PlayerModule")
        if not module then return end
        local controls = require(module):GetControls()
        if enabled then controls:Enable() else controls:Disable() end
    end)
    if ok then
        RT.controlsDisabled = not enabled
        heavyDebug("Mover", enabled and "Player controls handed back."
            or "Player controls taken over: the default control module calls Move(zero) every frame and would overrule us.")
    end
end

-- How fast the mover actually goes, for whoever estimates travel times.
local function moverSpeed(humanoid)
    local walk = humanoid and humanoid.WalkSpeed or 16
    if CFG.moveMode == "tween" and (CFG.tweenSpeed or 0) > 0 then
        return math.min(CFG.tweenSpeed, CFG.tweenSpeedMax or 40)
    end
    return walk
end

local function flatTo(root, target)
    local delta = target - root.Position
    return Vector3.new(delta.X, 0, delta.Z)
end

-- Only ever called once the target is reached: telling the Humanoid to stop
-- while it is still meant to be going somewhere is what broke 3.6.0.
local function halt(root, humanoid)
    if CFG.moveMode == "velocity" or CFG.moveMode == "tween" then
        local v = root.AssemblyLinearVelocity
        root.AssemblyLinearVelocity = Vector3.new(0, v.Y, 0)
    end
    if humanoid then humanoid:Move(Vector3.zero, false) end
end

-- Returns true once the character is within `arrive` studs of the target.
local function driveTo(humanoid, root, target, arrive)
    if not humanoid or not root then return false end
    arrive = arrive or CFG.moveArriveRadius

    local flat = flatTo(root, target)
    local distance = flat.Magnitude
    NAV.lastIssuedMove = target
    NAV.driving = true

    if distance <= arrive then
        halt(root, humanoid)
        RT.moverProgressAt = nil
        return true
    end

    -- Watchdog. If a mode is asked to move and the character does not, fall back
    -- to the one that always works rather than standing in an attack insisting.
    local now = os.clock()
    if not RT.moverProgressAt or not RT.moverProgressPos
        or (root.Position - RT.moverProgressPos).Magnitude > 1.5 then
        RT.moverProgressPos, RT.moverProgressAt = root.Position, now
    elseif CFG.moveMode ~= "walk" and now - RT.moverProgressAt > 1.0
        and not (RT.moverFallbackUntil and now < RT.moverFallbackUntil) then
        -- Borrow walk for a few seconds, then go back to the chosen mode. This
        -- used to REWRITE the setting: one second against a wall - a cornered
        -- character is against a wall - and the tween the user picked was
        -- silently walk for the rest of the session.
        heavyDebug("Mover", "'" .. tostring(CFG.moveMode)
            .. "' produced no movement for a second; walking for the next three.")
        RT.moverFallbackUntil = now + 3.0
        RT.moverProgressAt = now
    end

    local mode = CFG.moveMode
    if RT.moverFallbackUntil then
        if now < RT.moverFallbackUntil then mode = "walk" else RT.moverFallbackUntil = nil end
    end
    local direction = flat.Unit
    local speed = mode == "tween" and moverSpeed(humanoid) or humanoid.WalkSpeed

    if mode == "walk" then
        humanoid:MoveTo(target)
        return false
    end

    if mode == "steer" or mode == "velocity" then
        -- Both go through the Humanoid, so the control module has to be out of
        -- the way first or it wins.
        if CFG.moveTakeControls then setControlsEnabled(false) end
    else
        setControlsEnabled(true)
    end

    if mode == "steer" then
        humanoid:Move(direction, false)
        return false
    end

    if mode == "tween" then
        -- Writes the root's position directly, which is the ONLY one of these
        -- that the default control module cannot argue with (Move() and a
        -- velocity write both go through the Humanoid, and Roblox's own control
        -- script calls Move(zero) every frame on RenderStepped, before physics).
        --
        -- It FOLLOWS THE FLOOR. The 3.6.2 tween stepped horizontally and never
        -- re-sampled the floor, and its one wall ray left the root centre -
        -- about three studs up - so it missed every riser under that. Up a
        -- staircase it drove the legs into each step and physics fought back:
        -- that was "cannot go up stairs", and a staircase that turns ninety
        -- degrees was hopeless. Each frame the floor under the NEXT point is
        -- raycast and the root placed at its own height above it; a rise
        -- within the step height is simply climbed. Walls are read at knee
        -- and chest height with the same step-versus-wall classifier the
        -- steerer uses, so a riser reads as a step and a plinth as a wall.
        --
        -- Never further than the character could have walked this frame, so
        -- what a server sees is walking pace, and never through anything.
        local step = math.min(speed * RT.frameDelta, distance)
        local exclusions = getRaycastExclusions(nil)
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = exclusions
        params.IgnoreWater = true
        pcall(function() params.RespectCanCollide = true end)

        local pos = root.Position
        -- How far the root rides above the floor, measured rather than assumed:
        -- HipHeight + half the root is right for R15 and wrong for R6, and a
        -- slope puts the answer somewhere between anyway.
        local above = humanoid.HipHeight + root.Size.Y * 0.5
        local under = Workspace:Raycast(pos, Vector3.new(0, -(above + 4), 0), params)
        if under then above = pos.Y - under.Position.Y end
        local feetY = pos.Y - above

        -- Anything wall-like across the step, at knee and at chest.
        for _, h in ipairs(TWEEN_PROBE_HEIGHTS) do
            local origin = Vector3.new(pos.X, feetY + h, pos.Z)
            local hit = Workspace:Raycast(origin, direction * (step + 0.6), params)
            if hit and hitBlocksWalking(hit, direction, feetY, exclusions) then
                local room = Vector3.new(hit.Position.X - pos.X, 0, hit.Position.Z - pos.Z).Magnitude - 0.6
                if room <= 0.05 then
                    -- Flat against something: the Humanoid knows how to slide
                    -- along a wall and hop a lip; let it, for this frame.
                    humanoid:MoveTo(target)
                    return false
                end
                step = math.min(step, room)
            end
        end

        local nx, nz = pos.X + direction.X * step, pos.Z + direction.Z * step
        -- The floor under the next point: from a step above the feet down
        -- through the drop limit, so a kerb up is seen and a ledge down is too.
        local floorHit = Workspace:Raycast(
            Vector3.new(nx, feetY + CFG.maxStepHeight + 0.5, nz),
            Vector3.new(0, -(CFG.maxStepHeight + 0.5 + CFG.maxDropHeight), 0), params)
        if not floorHit then
            -- Nothing to stand on there: the Humanoid, not a CFrame write,
            -- decides what happens at an edge.
            humanoid:MoveTo(target)
            return false
        end
        local rise = floorHit.Position.Y - feetY
        if rise > CFG.maxStepHeight then
            -- Taller than a step: that is a jump, and the Humanoid does jumps.
            humanoid.Jump = true
            humanoid:MoveTo(target)
            return false
        end

        local goal = Vector3.new(nx, floorHit.Position.Y + above, nz)
        -- Position only: the rotation is left as it was so AutoRotate keeps
        -- turning the character normally.
        root.CFrame = CFrame.new(goal) * (root.CFrame - root.CFrame.Position)
        -- On the floor every frame, so the Humanoid never reads as hovering.
        root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
        return false
    end

    -- velocity: the Humanoid told the same direction, plus a direct write of
    -- the horizontal velocity so the change lands this frame with no
    -- acceleration ramp. Both must agree - telling it to stop while writing a
    -- velocity is an instruction to brake that the Humanoid re-applies every
    -- physics step, and the Humanoid wins.
    humanoid:Move(direction, false)
    local vertical = root.AssemblyLinearVelocity.Y
    root.AssemblyLinearVelocity = Vector3.new(direction.X * speed, vertical, direction.Z * speed)
    return false
end

local function releaseMover(humanoid, root)
    setControlsEnabled(true)
    if root and (CFG.moveMode == "velocity" or CFG.moveMode == "tween") then
        local v = root.AssemblyLinearVelocity
        root.AssemblyLinearVelocity = Vector3.new(0, v.Y, 0)
    end
    if humanoid then humanoid:Move(Vector3.zero, false) end
    NAV.driving = false
end

S.setMoveControlsEnabled = setControlsEnabled
S.moverSpeed = moverSpeed
S.driveTo = driveTo
S.releaseMover = releaseMover
end
