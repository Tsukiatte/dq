-- mover.lua - How the character is actually made to go somewhere.
-- Module contract: receives the shared table S. Everything this module needs from
-- earlier modules is pulled into locals below; everything later modules need is
-- assigned onto S at the bottom. Load order is fixed by main.lua / build.py.
return function(S)
local RT = S.RT
local CFG = S.CFG
local NAV = S.NAV
local heavyDebug = S.heavyDebug

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
    elseif CFG.moveMode ~= "walk" and now - RT.moverProgressAt > 1.0 then
        heavyDebug("Mover", "'" .. tostring(CFG.moveMode)
            .. "' produced no movement for a second; falling back to walk.")
        CFG.moveMode = "walk"
        RT.moverProgressAt = now
    end

    local mode = CFG.moveMode
    local direction = flat.Unit
    local speed = humanoid.WalkSpeed

    if mode == "walk" then
        humanoid:MoveTo(target)
        return false
    end

    if mode == "steer" then
        humanoid:Move(direction, false)
        return false
    end

    if mode == "tween" then
        -- Step no further than the character could actually have walked, so it
        -- moves at a believable speed rather than blinking across the arena.
        local step = math.min(speed * RT.frameDelta, distance)
        local goal = root.Position + direction * step
        root.CFrame = CFrame.new(goal, goal + direction)
        local v = root.AssemblyLinearVelocity
        root.AssemblyLinearVelocity = Vector3.new(0, v.Y, 0)
        return false
    end

    -- velocity: instant direction changes without the acceleration ramp.
    --
    -- The Humanoid must be told to move in the SAME direction, not told to
    -- stop. It re-asserts its own idea of velocity every physics step, so
    -- calling Move(zero) here - which is what 3.6.0 did - is an instruction to
    -- brake, applied every frame, cancelling the velocity written on the line
    -- above it. The character stood still in the middle of attacks because the
    -- mover and the Humanoid were fighting and the Humanoid always wins.
    --
    -- Told the same thing, they agree: the Humanoid handles animation, footing
    -- and slopes, and the direct write removes the quarter-second ramp.
    humanoid:Move(direction, false)
    local vertical = root.AssemblyLinearVelocity.Y
    root.AssemblyLinearVelocity = Vector3.new(direction.X * speed, vertical, direction.Z * speed)
    return false
end

local function releaseMover(humanoid, root)
    if root and (CFG.moveMode == "velocity" or CFG.moveMode == "tween") then
        local v = root.AssemblyLinearVelocity
        root.AssemblyLinearVelocity = Vector3.new(0, v.Y, 0)
    end
    if humanoid then humanoid:Move(Vector3.zero, false) end
    NAV.driving = false
end

S.driveTo = driveTo
S.releaseMover = releaseMover
end
