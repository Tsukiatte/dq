-- pursuit.lua - Which enemy, where to stand off it, and how to get there:
-- straight at the standoff point when the way is clear, PathfindingService
-- once when a wall says otherwise, re-planned on block. Every step is asked
-- of the danger field first; a step that would cross something live is
-- refused and the dodge takes the approach one safe spot at a time.
return function(S)
local CFG = S.CFG
local RT = S.RT
local NAV = S.NAV
local HZ = S.HZ
local DG = S.DG
local Workspace = S.Workspace
local PathfindingService = S.PathfindingService
local LocalPlayer = S.LocalPlayer
local heavyDebug = S.heavyDebug
local heavyDebugThrottled = S.heavyDebugThrottled
local setMovementState = S.setMovementState
local dangerAlong = S.dangerAlong
local moveTo = S.moveTo
local moverStop = S.moverStop
local wallBetween = S.wallBetween
local MV = S.MV

local V3 = Vector3.new
local INF = math.huge
local clock = os.clock
local fmt = string.format

NAV.route = nil            -- { target, waypoints, index, computedAt, failed }
NAV.computing = false
NAV.blockedSince = nil
NAV.pointRoute = nil
NAV.pointProgressDistance = nil
NAV.pointProgressTime = 0

local function planar(a, b)
    local dx, dz = a.X - b.X, a.Z - b.Z
    return math.sqrt(dx * dx + dz * dz)
end

-- ------------------------------------------------------------------ target
local function pickTarget(root)
    local best, bestScore, count = nil, INF, 0
    local now = clock()
    local p = root.Position
    for _, e in ipairs(HZ.enemies) do
        if e.root.Parent and e.humanoid.Health > 0 then
            local bench = NAV.benched[e.model]
            if bench and now < bench then
                count = count + 1
            else
                if bench then NAV.benched[e.model] = nil end
                count = count + 1
                local d = planar(p, e.root.Position)
                local score
                if CFG.targetMode == "lowest HP" then
                    score = d <= CFG.targetHpRange and e.humanoid.Health or (1e9 + d)
                elseif CFG.targetMode == "highest HP" then
                    score = d <= CFG.targetHpRange and -e.humanoid.Health or (1e9 + d)
                else
                    score = d
                end
                if score < bestScore then best, bestScore = e, score end
            end
        end
    end
    NAV.cachedEntry = best
    NAV.cachedEnemy = best and best.model or nil
    NAV.cachedEnemyCount = count
    if S.updateEnemyDisplay then pcall(S.updateEnemyDisplay, NAV.cachedEnemy, count) end
    return best
end

-- ------------------------------------------------------------------ routes
local function computeRoute(slot, from, to)
    NAV.computing = true
    local ok, err = pcall(function()
        local path = PathfindingService:CreatePath({ AgentRadius = CFG.wallPadding, AgentHeight = 5, AgentCanJump = true })
        path:ComputeAsync(from, to)
        if path.Status == Enum.PathStatus.Success then
            slot.waypoints = path:GetWaypoints()
            slot.index = 2
            slot.failed = false
        else
            slot.waypoints = nil
            slot.failed = true
        end
    end)
    if not ok then slot.waypoints = nil slot.failed = true heavyDebug("Pursuit", "path threw: " .. tostring(err)) end
    slot.computedAt = clock()
    NAV.computing = false
end

-- The next point to walk to on the way to `goal`: the goal itself when the
-- straight line is clear, else the route's next waypoint (computing one if
-- there is none). Returns point, jump.
local function nextPoint(root, goal, slot)
    local p = root.Position
    local d = planar(p, goal)
    local direct = d < 8 or not wallBetween(p, V3(goal.X, p.Y, goal.Z))
    if direct then
        NAV.blockedSince = nil
        return goal, false
    end
    local now = clock()
    local stale = slot.target == nil or planar(slot.target, goal) > 4
        or (slot.computedAt and now - slot.computedAt > CFG.pathRecomputeInterval * (slot.failed and 3 or 8))
    if (stale or slot.needsRecompute) and not NAV.computing then
        slot.target = goal
        slot.needsRecompute = false
        local from = p
        task.spawn(function() computeRoute(slot, from, goal) end)
    end
    local wps = slot.waypoints
    if wps then
        while slot.index <= #wps do
            local wp = wps[slot.index]
            if planar(p, wp.Position) > 3.5 then break end
            slot.index = slot.index + 1
        end
        local wp = wps[slot.index]
        if wp then return wp.Position, wp.Action == Enum.PathWaypointAction.Jump end
    end
    return goal, false
end

-- Walk a step toward `point` unless the danger field says the next few studs
-- are not safe. Returns true when moving.
local function safeStep(root, point, speed, face, jump, owner)
    local p = root.Position
    local d = planar(p, point)
    if d < 0.3 then return false end
    local probe = math.min(d, CFG.dodgeStepProbe)
    local ux, uz = (point.X - p.X) / d, (point.Z - p.Z) / d
    local worst = dangerAlong(p.X, p.Z, p.X + ux * probe, p.Z + uz * probe, clock(), speed, nil)
    if worst >= CFG.dodgeMoveAt then
        DG.pursuitBlocked = true
        return false
    end
    DG.pursuitBlocked = false
    moveTo(point, speed, owner, face, jump)
    return true
end

-- ------------------------------------------------------------------ pursuit
local function resetPursuitPath()
    NAV.route = nil
    NAV.blockedSince = nil
    DG.goal = nil
end

local function pursuitStep(root, hum, now)
    local e = NAV.cachedEntry
    if not e or not e.root.Parent then resetPursuitPath() return end
    local ep, p = e.root.Position, root.Position
    local dist = planar(p, ep)
    local standoff = S.standoffFor(e, now)
    local ux, uz = 1, 0
    if dist > 0.1 then ux, uz = (p.X - ep.X) / dist, (p.Z - ep.Z) / dist end
    local goal = V3(ep.X + ux * standoff, p.Y, ep.Z + uz * standoff)
    DG.goal = goal
    local face = CFG.faceTarget and ep or nil
    local off = dist - standoff
    NAV.driving = false
    if math.abs(off) <= CFG.inRangeDeadband then
        moverStop()
        DG.pursuitBlocked = false
        setMovementState(fmt("HOLD %s at %.0f", e.name, dist))
        return
    end
    if off < 0 then
        -- Too close: back off to the standoff, straight away from it.
        if safeStep(root, goal, CFG.moveSpeed, face, false, "back") then
            NAV.driving = true
            setMovementState(fmt("BACK OFF %s (%.0f -> %.0f)", e.name, dist, standoff))
        else
            moverStop()
            setMovementState(fmt("too close to %s, way blocked", e.name))
        end
        return
    end
    NAV.route = NAV.route or {}
    local point, jump = nextPoint(root, goal, NAV.route)
    if safeStep(root, point, CFG.moveSpeed, face, jump, "pursuit") then
        NAV.driving = true
        setMovementState(fmt("PURSUE %s (%.0f -> %.0f)%s", e.name, dist, standoff, NAV.route.waypoints and " [path]" or ""))
        if MV.blocked then
            NAV.blockedSince = NAV.blockedSince or now
            if now - NAV.blockedSince > 0.6 then
                NAV.route.needsRecompute = true
                NAV.blockedSince = now
                if NAV.route.failed then
                    NAV.benched[e.model] = now + 10
                    heavyDebug("Pursuit", "No route to " .. e.name .. "; benched for ten seconds.")
                end
            end
        else
            NAV.blockedSince = nil
        end
    else
        moverStop()
        setMovementState(fmt("HOLD for a gap (%s at %.0f)", e.name, dist))
    end
end

-- ------------------------------------------------------------------ points (path.lua)
local function clearPointRoute()
    NAV.pointRoute = nil
    NAV.pointProgressDistance = nil
    NAV.pointProgressTime = 0
    NAV.walkAnchor = nil
end

-- Walk toward a static point (the manual waypath). Returns distance, stuck.
local function walkTowardPoint(hum, root, point)
    NAV.driving = true
    local now = clock()
    local p = root.Position
    local distance = planar(p, point)
    if not NAV.pointRoute or planar(NAV.pointRoute.goal, point) > 3 then
        NAV.pointRoute = { goal = point }
        NAV.pointProgressDistance = distance
        NAV.pointProgressTime = now
    elseif distance < NAV.pointProgressDistance - 1.5 then
        NAV.pointProgressDistance = distance
        NAV.pointProgressTime = now
    end
    local stuck = now - NAV.pointProgressTime >= CFG.pointGiveUpTime
    local slot = NAV.pointRoute
    local next, jump = nextPoint(root, point, slot)
    if safeStep(root, next, CFG.moveSpeed, nil, jump, "path") then
        if MV.blocked then slot.needsRecompute = true end
    else
        moverStop()
    end
    return distance, stuck
end

local function followPath(hum, root)
    local wp = NAV.waypath[NAV.pathIndex]
    if not wp then
        if CFG.loopPath and #NAV.waypath > 0 then NAV.pathIndex = 1 wp = NAV.waypath[1] else return false end
    end
    local distance, stuck = walkTowardPoint(hum, root, wp)
    setMovementState(fmt("PATH waypoint %d/%d (%.0f)", NAV.pathIndex, #NAV.waypath, distance))
    if stuck then
        heavyDebugThrottled("path_stuck", 5, "Path", "No progress toward the waypoint; skipping it.")
        NAV.pathIndex = NAV.pathIndex + 1
        clearPointRoute()
    end
    return true
end

S.pickTarget = pickTarget
S.pursuitStep = pursuitStep
S.resetPursuitPath = resetPursuitPath
S.walkTowardPoint = walkTowardPoint
S.clearPointRoute = clearPointRoute
S.followPath = followPath
end
