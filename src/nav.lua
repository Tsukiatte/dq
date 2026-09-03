-- nav.lua - Pursuit routing, obstacle steering, blacklists, escape routing, facing rig, point walking.
-- Module contract: receives the shared table S. Everything this module needs from
-- earlier modules is pulled into locals below; everything later modules need is
-- assigned onto S at the bottom. Load order is fixed by main.lua / build.py.
return function(S)
local RT = S.RT
local NAV = S.NAV
local CFG = S.CFG
local LocalPlayer = S.LocalPlayer
local HZ = S.HZ
local getPlayerHitboxMetrics = S.getPlayerHitboxMetrics
local getEnemyStandoff = S.getEnemyStandoff
local heavyDebug = S.heavyDebug
local evaluateHazardPenaltyAtPoint = S.evaluateHazardPenaltyAtPoint
local isPositionSafeFromDamageBricks = S.isPositionSafeFromDamageBricks
local heavyDebugThrottled = S.heavyDebugThrottled
local PathfindingService = S.PathfindingService
local setMovementState = S.setMovementState
local debugThrottleClocks = S.debugThrottleClocks
local Workspace = S.Workspace
local DEBUG_VERBOSE = S.DEBUG_VERBOSE
local STEER_PROBE_HEIGHTS = S.STEER_PROBE_HEIGHTS
local STEER_FAN_ANGLES = S.STEER_FAN_ANGLES
local DEBUG_NORMAL = S.DEBUG_NORMAL
local getVisualRoot = S.getVisualRoot
local getHazardMotion = S.getHazardMotion

local function clearRenderedPath()
    if NAV.nodesFolder then
        NAV.nodesFolder:Destroy()
        NAV.nodesFolder = nil
    end
end

-- Render High-Visibility Path
-- Node pool. Parts are reused in place rather than destroyed and rebuilt.
-- A 48-waypoint path with a marker every 1.5 studs is about 166 Parts, and the
-- old renderer recreated all of them on every recompute - several times a second
-- while stuck. That churn, not the drawing, was the stutter.
local NODE_MAIN_SIZE = Vector3.new(0.45, 0.45, 0.45)
local NODE_SUB_SIZE = Vector3.new(0.18, 0.18, 0.18)
local NODE_LIFT = Vector3.new(0, 0.2, 0)

local function applyNodePool(folder, entries)
    local children = folder:GetChildren()

    for i, entry in ipairs(entries) do
        local node = children[i]
        if not node then
            node = Instance.new("Part")
            node.Name = "PathNode"
            node.Anchored = true
            node.CanCollide = false
            node.CanQuery = false
            node.CanTouch = false
            node.CastShadow = false
            node.Material = Enum.Material.Neon
            node.Parent = folder
        end
        -- Only write what changed: a property write on an anchored part is a
        -- physics/replication touch, and most of a re-rendered route is the same.
        if node.Position ~= entry.position then node.Position = entry.position end
        if node.Size ~= entry.size then node.Size = entry.size end
        if node.Color ~= entry.color then node.Color = entry.color end
    end

    for i = #entries + 1, #children do
        children[i]:Destroy()
    end
end

local function renderCurrentPath()
    if not RT.renderPathEnabled or #NAV.waypoints == 0 then
        clearRenderedPath()
        return
    end

    if not NAV.nodesFolder or not NAV.nodesFolder.Parent then
        NAV.nodesFolder = Instance.new("Folder")
        NAV.nodesFolder.Name = "PursuitPathNodes"
        NAV.nodesFolder.Parent = getVisualRoot()
    end

    local entries = {}

    for index, waypoint in ipairs(NAV.waypoints) do
        table.insert(entries, {
            position = waypoint.Position + NODE_LIFT,
            size = NODE_MAIN_SIZE,
            color = CFG.colorPursuit,
        })
    end

    -- Fill the remaining budget with connecting dots, spaced to span the whole
    -- path. A long route now draws a sparser line instead of an unbounded one.
    local budget = CFG.pathNodeBudget - #entries
    if budget > 0 then
        local segments = {}
        local totalLength = 0
        for index = 1, #NAV.waypoints - 1 do
            local from = NAV.waypoints[index].Position
            local to = NAV.waypoints[index + 1].Position
            local length = (to - from).Magnitude
            if length > 0.01 then
                table.insert(segments, { from = from, to = to, length = length })
                totalLength = totalLength + length
            end
        end

        if totalLength > 0 then
            local spacing = math.max(1.5, totalLength / budget)
            for _, segment in ipairs(segments) do
                local count = math.floor(segment.length / spacing)
                for i = 1, count do
                    table.insert(entries, {
                        position = segment.from:Lerp(segment.to, i / (count + 1)) + NODE_LIFT,
                        size = NODE_SUB_SIZE,
                        color = Color3.fromRGB(255, 255, 255),
                    })
                end
            end
        end
    end

    applyNodePool(NAV.nodesFolder, entries)
end

local function resetPursuitPath()
    if NAV.blockedConnection then
        NAV.blockedConnection:Disconnect()
        NAV.blockedConnection = nil
    end
    NAV.waypoints = {}
    NAV.index = 1
    NAV.enemy = nil
    NAV.lastTarget = nil
    NAV.lastComputeTime = -math.huge
    NAV.needsRecompute = false
    NAV.computing = false
    NAV.progressPosition = nil
    NAV.progressTime = os.clock()
    NAV.lastIssuedMove = nil
    NAV.routeIsDirect = false
    NAV.directProgressPosition = nil
    NAV.directProgressTime = os.clock()
    NAV.stallAnchor = nil
    NAV.stallTime = os.clock()
    NAV.steerAngle = nil
    -- Blacklisted headings are intentionally kept across a reset: the walls that
    -- caused them are still there. They expire on their own timer.
    clearRenderedPath()
end

-- Every instance this script spawns into the world must be invisible to its own
-- raycasts, or the visualisers block the paths they are drawn to illustrate.
local function getRaycastExclusions(enemy)
    local exclusions = {}
    if LocalPlayer.Character then table.insert(exclusions, LocalPlayer.Character) end
    if enemy then table.insert(exclusions, enemy) end
    -- Every marker this script draws lives under one folder (2.1.0).
    if RT.visualRoot then table.insert(exclusions, RT.visualRoot) end
    return exclusions
end

local function projectToGround(position, enemy)
    local exclusions = getRaycastExclusions(enemy)

    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = exclusions
    params.IgnoreWater = false

    local result = Workspace:Raycast(
        Vector3.new(position.X, position.Y + 6, position.Z),
        Vector3.new(0, -40, 0),
        params
    )
    return result and (result.Position + Vector3.new(0, 0.1, 0)) or position
end

-- Reused across calls so the clearance test allocates nothing per candidate.
local SEGMENT_PROBE_HEIGHT = Vector3.new(0, 2.8, 0)
local SHIN_PROBE_HEIGHT = Vector3.new(0, -1.5, 0)   -- about a stud and a half above the floor
local SEGMENT_SIDE_OFFSETS = { 0, 0, 0 }
-- Defined further down (it needs castSolid); declared here because the
-- segment test below is the first thing that asks it.
local hitBlocksWalking

local function isPathSegmentClear(fromPosition, toPosition, enemy)
    local flatDelta = Vector3.new(toPosition.X - fromPosition.X, 0, toPosition.Z - fromPosition.Z)
    local distance = flatDelta.Magnitude
    if distance < 0.1 then return true end

    local exclusions = getRaycastExclusions(enemy)

    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = exclusions
    params.IgnoreWater = true

    local direction = flatDelta.Unit
    local side = Vector3.new(-direction.Z, 0, direction.X)
    local _, playerRadius = getPlayerHitboxMetrics()
    local clearanceOffset = math.max(CFG.wallPadding, playerRadius + 0.6)

    -- Was a 3x3 sweep, 9 casts per candidate, with both loop tables reallocated
    -- on every call. One chest-height pass across three lateral offsets is enough
    -- of a prefilter now that the navmesh makes the final reachability call.
    local sideOffsets = SEGMENT_SIDE_OFFSETS
    sideOffsets[2] = clearanceOffset
    sideOffsets[3] = -clearanceOffset

    -- A hit is a wall only if it is wall-like. A staircase rises a stud a
    -- step, and a horizontal ray at any height meets a riser within a few
    -- studs on the way up; treating that as a wall is what walked the
    -- character diagonally up every flight, steering round steps it could
    -- simply climb. The same test the direct steerer uses decides.
    local feetY = fromPosition.Y - 3.0
    for i = 1, 3 do
        local origin = fromPosition + SEGMENT_PROBE_HEIGHT + (side * sideOffsets[i])
        local destination = toPosition + SEGMENT_PROBE_HEIGHT + (side * sideOffsets[i])
        local hit = Workspace:Raycast(origin, destination - origin, params)
        if hit and hit.Instance and hit.Instance.CanCollide
            and hitBlocksWalking(hit, direction, feetY, exclusions) then
            return false
        end
    end
    -- And one at shin height down the middle. The plinth of a pillar sits
    -- below the chest ray; the character walked into it and stayed there.
    do
        local origin = fromPosition + SHIN_PROBE_HEIGHT
        local destination = toPosition + SHIN_PROBE_HEIGHT
        local hit = Workspace:Raycast(origin, destination - origin, params)
        if hit and hit.Instance and hit.Instance.CanCollide
            and hitBlocksWalking(hit, direction, feetY, exclusions) then
            return false
        end
    end

    local groundCheck = Workspace:Raycast(
        toPosition + Vector3.new(0, 3.0, 0),
        Vector3.new(0, -12, 0),
        params
    )
    if not groundCheck then
        return false
    end

    return true
end

local function pruneBlockedAreas(now)
    for i = #NAV.blockedAreas, 1, -1 do
        if now >= NAV.blockedAreas[i].expires then
            table.remove(NAV.blockedAreas, i)
        end
    end
end

-- Planar, like the rest of the avoidance maths.
local function isInsideBlockedArea(position)
    local now = os.clock()
    for _, area in ipairs(NAV.blockedAreas) do
        if now < area.expires then
            local offset = Vector2.new(position.X - area.position.X, position.Z - area.position.Z)
            if offset.Magnitude <= area.radius then
                return true
            end
        end
    end
    return false
end

-- Re-trapping in the same place grows the area rather than stacking overlapping
-- entries, so a wide dead-end is eventually covered by one region.
local function blockArea(position, now)
    for _, area in ipairs(NAV.blockedAreas) do
        local offset = Vector2.new(position.X - area.position.X, position.Z - area.position.Z)
        if offset.Magnitude <= area.radius then
            area.expires = now + CFG.stuckAreaLife
            area.radius = math.min(area.radius + 2.0, CFG.stuckAreaRadius * 2.5)
            heavyDebug("Stuck", string.format(
                "Trapped again in a known bad area; radius grown to %.1f.", area.radius))
            return
        end
    end

    table.insert(NAV.blockedAreas, {
        position = position,
        radius = CFG.stuckAreaRadius,
        expires = now + CFG.stuckAreaLife,
    })
    heavyDebug("Stuck", string.format(
        "Stood still %.1fs without dodging at (%.0f, %.0f). Area blacklisted for %.0fs.",
        CFG.stuckAreaTime, position.X, position.Z, CFG.stuckAreaLife))
end

local function buildEscapeCandidates(rootPos, targetPos, enemy)
    local candidates = {}
    local _, playerRadius = getPlayerHitboxMetrics()

    for _, part in ipairs(HZ.detected) do
        if part.Parent then
            local localPos = part.CFrame:PointToObjectSpace(rootPos)
            local size = part.Size
            local halfSize = size * 0.5
            local pushDist = CFG.damageBrickClearance + playerRadius + 1.0

            local escapeLocal
            if halfSize.X < halfSize.Z then
                local xDir = localPos.X >= 0 and 1 or -1
                escapeLocal = Vector3.new(xDir * (halfSize.X + pushDist), 0, math.clamp(localPos.Z, -halfSize.Z, halfSize.Z))
            else
                local zDir = localPos.Z >= 0 and 1 or -1
                escapeLocal = Vector3.new(math.clamp(localPos.X, -halfSize.X, halfSize.X), 0, zDir * (halfSize.Z + pushDist))
            end

            local edgeWorld = projectToGround(part.CFrame:PointToWorldSpace(escapeLocal), enemy)

            if isPathSegmentClear(rootPos, edgeWorld, enemy) then
                local penalty = evaluateHazardPenaltyAtPoint(edgeWorld)
                local isSafe = isPositionSafeFromDamageBricks(edgeWorld, 0.5)
                local distToTarget = Vector2.new(edgeWorld.X - targetPos.X, edgeWorld.Z - targetPos.Z).Magnitude
                table.insert(candidates, {
                    Position = edgeWorld,
                    Distance = (edgeWorld - rootPos).Magnitude,
                    DistToTarget = distToTarget,
                    Penalty = penalty,
                    IsSafe = isSafe
                })
            end
        end
    end

    -- Moving hazards (2.3.0): the best dodge from a projectile is sideways out
    -- of its line, so each one contributes two candidates perpendicular to its
    -- travel. The penalty and safety tests already see the swept strip, so these
    -- rank themselves.
    for _, part in ipairs(HZ.detected) do
        local velocity = part.Parent and getHazardMotion(part)
        if velocity then
            local flat = Vector3.new(velocity.X, 0, velocity.Z)
            if flat.Magnitude > 0.1 then
                local side = Vector3.new(-flat.Unit.Z, 0, flat.Unit.X)
                local reach = CFG.preemptiveClearance + playerRadius + 4.0
                for sign = -1, 1, 2 do
                    local candidate = projectToGround(rootPos + side * (sign * reach), enemy)
                    if isPathSegmentClear(rootPos, candidate, enemy) then
                        table.insert(candidates, {
                            Position = candidate,
                            Distance = (candidate - rootPos).Magnitude,
                            DistToTarget = Vector2.new(candidate.X - targetPos.X, candidate.Z - targetPos.Z).Magnitude,
                            Penalty = evaluateHazardPenaltyAtPoint(candidate),
                            IsSafe = isPositionSafeFromDamageBricks(candidate, 0.5),
                        })
                    end
                end
            end
        end
    end

    -- Coarser fan: 4x10 instead of 6x16. The old grid produced 96 candidates and
    -- each ran a 9-ray clearance test, roughly 900 raycasts per escape. Navmesh
    -- validation now decides reachability, so this only has to rank plausibly.
    local distances = {3, 6, 11, 18}
    local angles = {0, 25, -25, 55, -55, 90, -90, 135, -135, 180}

    for _, dist in ipairs(distances) do
        for _, angle in ipairs(angles) do
            local rad = math.rad(angle)
            local offset = Vector3.new(math.sin(rad) * dist, 0, math.cos(rad) * dist)
            local candidate = projectToGround(Vector3.new(rootPos.X + offset.X, rootPos.Y, rootPos.Z + offset.Z), enemy)

            if isPathSegmentClear(rootPos, candidate, enemy) then
                local penalty = evaluateHazardPenaltyAtPoint(candidate)
                local isSafe = isPositionSafeFromDamageBricks(candidate, 0.5)
                local distToTarget = Vector2.new(candidate.X - targetPos.X, candidate.Z - targetPos.Z).Magnitude
                table.insert(candidates, {
                    Position = candidate,
                    Distance = dist,
                    DistToTarget = distToTarget,
                    Penalty = penalty,
                    IsSafe = isSafe
                })
            end
        end
    end

    for _, candidate in ipairs(candidates) do
        candidate.InBadArea = isInsideBlockedArea(candidate.Position)
    end

    table.sort(candidates, function(a, b)
        if a.IsSafe ~= b.IsSafe then
            return a.IsSafe
        end
        -- A spot that already trapped us is a poor place to flee to, but still
        -- better than staying in the damage, so it sorts last rather than out.
        if a.InBadArea ~= b.InBadArea then
            return b.InBadArea
        end
        if math.abs(a.Distance - b.Distance) > 1.0 then
            return a.Distance < b.Distance
        end
        return a.DistToTarget < b.DistToTarget
    end)

    return candidates
end

local function findStagingSafePoint(rootPos, targetPos, enemy)
    local candidates = buildEscapeCandidates(rootPos, targetPos, enemy)
    return candidates[1] and candidates[1].Position or nil
end

local function clearEscapeNodes()
    if NAV.escapeNodesFolder then
        NAV.escapeNodesFolder:Destroy()
        NAV.escapeNodesFolder = nil
    end
end

local function clearEscapeRoute()
    NAV.escapeWaypoints = {}
    NAV.escapeIndex = 1
    NAV.escapeTarget = nil
    NAV.lastEscapeTime = -math.huge
    clearEscapeNodes()
end

local function renderEscapeRoute()
    if not RT.renderPathEnabled or #NAV.escapeWaypoints == 0 then
        clearEscapeNodes()
        return
    end

    if not NAV.escapeNodesFolder or not NAV.escapeNodesFolder.Parent then
        NAV.escapeNodesFolder = Instance.new("Folder")
        NAV.escapeNodesFolder.Name = "EscapeNodes"
        NAV.escapeNodesFolder.Parent = getVisualRoot()
    end

    local entries = {}
    for _, waypoint in ipairs(NAV.escapeWaypoints) do
        table.insert(entries, {
            position = waypoint.Position + Vector3.new(0, 0.25, 0),
            size = Vector3.new(0.5, 0.5, 0.5),
            color = CFG.colorEscape,
        })
    end

    applyNodePool(NAV.escapeNodesFolder, entries)
end

-- Picks an escape point the character can actually walk to. Ranked candidates are
-- checked against the real navmesh in order, because a raycast-clear straight line
-- still walks into concave geometry, which is what was getting the bot stuck.
-- Runs off the Heartbeat because ComputeAsync yields.
local function resolveEscapeRoute(rootPos, targetPos, enemy)
    if NAV.computingEscape then return end
    NAV.computingEscape = true

    local ok, err = xpcall(function()
        local candidates = buildEscapeCandidates(rootPos, targetPos, enemy)
        if #candidates == 0 then
            heavyDebugThrottled("escape_none", 1.0, "Escape", "No escape candidates produced.")
            return
        end

        -- No point validating against a navmesh that cannot answer.
        if os.clock() < NAV.navmeshDeadUntil then
            NAV.escapeWaypoints = {
                { Position = candidates[1].Position, Action = Enum.PathWaypointAction.Walk }
            }
            NAV.escapeIndex = 1
            NAV.escapeTarget = candidates[1].Position
            heavyDebugThrottled("escape_direct", 3.0, "Escape",
                "Navmesh unusable here; stepping straight to the best-ranked safe point.")
            renderEscapeRoute()
            return
        end

        local budget = math.min(#candidates, CFG.escapeValidationBudget)
        for i = 1, budget do
            local candidate = candidates[i]
            local path = PathfindingService:CreatePath({
                AgentRadius = CFG.wallPadding,
                AgentHeight = 4.5,
                AgentCanJump = true,
                AgentCanClimb = false,
                WaypointSpacing = 4
            })

            local computed = pcall(function()
                path:ComputeAsync(rootPos, candidate.Position)
            end)

            if computed and path.Status == Enum.PathStatus.Success then
                local waypoints = path:GetWaypoints()
                if #waypoints > 1 then
                    NAV.escapeWaypoints = waypoints
                    NAV.escapeIndex = 2
                    NAV.escapeTarget = candidate.Position
                    heavyDebug("Escape", string.format(
                        "Reachable escape found: candidate %d/%d, %.1f studs out, %d waypoints.",
                        i, budget, candidate.Distance, #waypoints))
                    renderEscapeRoute()
                    return
                end
            end

            heavyDebug("Escape", string.format(
                "Candidate %d/%d unreachable (status %s). Trying next.",
                i, budget, tostring(path.Status)), DEBUG_VERBOSE)
        end

        -- Nothing validated. Walk at the best-ranked point directly rather than
        -- standing in the damage, but say so; this is the case that can snag.
        NAV.escapeWaypoints = {
            { Position = candidates[1].Position, Action = Enum.PathWaypointAction.Walk }
        }
        NAV.escapeIndex = 1
        NAV.escapeTarget = candidates[1].Position
        heavyDebugThrottled("escape_unvalidated", 1.0, "Escape", string.format(
            "No candidate of %d passed navmesh validation. Falling back to straight-line escape.", budget))
        renderEscapeRoute()
    end, debug.traceback)

    NAV.computingEscape = false

    if not ok then
        heavyDebugThrottled("escape_error", 1.0, "FATAL", "Escape resolver threw:\n" .. tostring(err))
    end
end

-- Advances along the validated escape path. Returns false when the route is spent.
local function followEscapeRoute(humanoid, root)
    while NAV.escapeIndex <= #NAV.escapeWaypoints do
        local waypoint = NAV.escapeWaypoints[NAV.escapeIndex]
        local delta = root.Position - waypoint.Position
        local horizontal = Vector3.new(delta.X, 0, delta.Z).Magnitude
        if horizontal > CFG.escapeWaypointAdvanceDistance then
            break
        end
        NAV.escapeIndex = NAV.escapeIndex + 1
    end

    local waypoint = NAV.escapeWaypoints[NAV.escapeIndex]
    if not waypoint then
        return false
    end

    if waypoint.Action == Enum.PathWaypointAction.Jump then
        humanoid.Jump = true
    end
    humanoid:MoveTo(waypoint.Position)
    setMovementState(string.format("ESCAPE wp %d/%d", NAV.escapeIndex, #NAV.escapeWaypoints))
    return true
end

-- Yaw-only orientation. Position is preserved and pitch/roll are left flat, so
-- this sets which way the character looks without moving or tipping it, and does
-- not fight Humanoid:MoveTo, which drives velocity rather than facing.
-- One Attachment + AlignOrientation, built once per character and reused. Rigid
-- so it snaps rather than easing, matching the previous behaviour.
local function ensureFacingRig(root)
    if NAV.faceAligner and NAV.faceAligner.Parent == root
        and NAV.faceAttachment and NAV.faceAttachment.Parent == root then
        return NAV.faceAligner
    end

    if NAV.faceAligner then NAV.faceAligner:Destroy() end
    if NAV.faceAttachment then NAV.faceAttachment:Destroy() end
    NAV.faceAligner, NAV.faceAttachment = nil, nil

    local built = pcall(function()
        local attachment = Instance.new("Attachment")
        attachment.Name = "DungeonFaceAttachment"
        attachment.Parent = root

        local aligner = Instance.new("AlignOrientation")
        aligner.Name = "DungeonFaceAligner"
        aligner.Mode = Enum.OrientationAlignmentMode.OneAttachment
        aligner.Attachment0 = attachment
        -- Not rigid. A rigid constraint snaps the body to the exact bearing every
        -- frame, and against a close, moving enemy that bearing swings several
        -- degrees per frame, so the character whipped back and forth - the
        -- stutter that survived the 1.16.0 facing rewrite. Easing with a high
        -- responsiveness still turns fast, but smoothly, without the whip.
        aligner.RigidityEnabled = false
        pcall(function()
            aligner.MaxTorque = CFG.faceMaxTorque
            aligner.Responsiveness = CFG.faceResponsiveness
        end)
        aligner.Enabled = false
        aligner.Parent = root

        NAV.faceAttachment = attachment
        NAV.faceAligner = aligner
    end)

    return built and NAV.faceAligner or nil
end

local function faceTowards(root, humanoid, targetPosition)
    local flat = Vector3.new(
        targetPosition.X - root.Position.X, 0, targetPosition.Z - root.Position.Z)
    if flat.Magnitude < 0.05 then return end

    local desired = flat.Unit
    local look = root.CFrame.LookVector

    -- Skip while already pointed close enough, roughly six degrees. Writing the
    -- CFrame is not free and there is no reason to do it every frame.
    if (look.X * desired.X) + (look.Z * desired.Z) > 0.995 then
        humanoid.AutoRotate = false
        return
    end

    humanoid.AutoRotate = false

    -- Prefer an AlignOrientation constraint. Writing CFrame moves the assembly,
    -- which forces a physics resolve and a replication update every time; even
    -- with the velocity carried across it showed up as stutter. The constraint
    -- only ever has a property set on it and never touches position at all.
    local aligner = ensureFacingRig(root)
    if aligner then
        aligner.CFrame = CFrame.new(Vector3.zero, desired)
        aligner.Enabled = true
        return
    end

    -- Fallback for clients without the constraint. Assigning CFrame resets the
    -- assembly's velocity, which pinned the character in place, so it is carried
    -- across the write and only the orientation changes.
    local linearVelocity = root.AssemblyLinearVelocity
    local angularVelocity = root.AssemblyAngularVelocity

    root.CFrame = CFrame.new(root.Position, root.Position + desired)

    root.AssemblyLinearVelocity = linearVelocity
    root.AssemblyAngularVelocity = angularVelocity
end

local function releaseFacing(humanoid)
    if NAV.faceAligner and NAV.faceAligner.Parent then
        NAV.faceAligner.Enabled = false
    end
    if humanoid then
        humanoid.AutoRotate = true
    end
end

local function destroyFacingRig()
    if NAV.faceAligner then NAV.faceAligner:Destroy() end
    if NAV.faceAttachment then NAV.faceAttachment:Destroy() end
    NAV.faceAligner, NAV.faceAttachment = nil, nil
end

local function getStandOffPosition(root, enemyRoot)
    local enemyPosition = enemyRoot.Position
    local offset = root.Position - enemyPosition
    local flatOffset = Vector3.new(offset.X, 0, offset.Z)
    local directionAway

    if flatOffset.Magnitude > 0.001 then
        directionAway = flatOffset.Unit
    else
        local look = enemyRoot.CFrame.LookVector
        local flatLook = Vector3.new(-look.X, 0, -look.Z)
        directionAway = flatLook.Magnitude > 0.001 and flatLook.Unit or Vector3.new(0, 0, 1)
    end

    -- The enemy is the distance: its body plus a swing, capped by our own
    -- reach. The dodge draws its enemy circle from the same number, so the
    -- chase and the dodge agree on where to stand.
    local model = enemyRoot:FindFirstAncestorOfClass("Model") or enemyRoot.Parent
    local standoff = model and getEnemyStandoff(model) or math.max(CFG.attackRange - 1.5, 2)
    return enemyPosition + (directionAway * standoff)
end

-- Primary Wall-Aware Pathfinding Router with Debug Output
-- Walks a straight line to the target in short hops, each dropped onto the floor.
-- Short hops rather than one long MoveTo so the humanoid can follow stairs and
-- ramps, and so the stuck detector has intermediate progress to measure against.
local function buildDirectWalkRoute(fromPosition, toPosition, enemy)
    local flat = Vector3.new(toPosition.X - fromPosition.X, 0, toPosition.Z - fromPosition.Z)
    local distance = flat.Magnitude
    local waypoints = {}

    local steps = math.clamp(math.floor(distance / CFG.directWalkStepLength), 1, 24)
    for i = 1, steps do
        local alpha = i / steps
        local point = fromPosition:Lerp(toPosition, alpha)
        table.insert(waypoints, {
            Position = projectToGround(point, enemy),
            Action = Enum.PathWaypointAction.Walk,
        })
    end

    return waypoints
end

-- Rotates a flat direction around Y.
local function rotateFlatDirection(direction, degrees)
    local radians = math.rad(degrees)
    local cosine, sine = math.cos(radians), math.sin(radians)
    return Vector3.new(
        direction.X * cosine - direction.Z * sine,
        0,
        direction.X * sine + direction.Z * cosine
    )
end

-- Direct walking has no navmesh to route around geometry, so it steers itself:
-- probe straight at the goal, and if that is blocked, fan outwards until a clear
-- heading is found. Preferring the smallest deviation keeps it hugging the
-- intended direction rather than wandering off.
-- Returns the first SOLID hit along a ray.
--
-- Raycast reports whichever part it meets first, collidable or not. The steering
-- probe used to accept a heading whenever that first hit was non-collidable,
-- which silently ignored any wall standing behind a decoration or an effect
-- part. Dungeons are full of both, so the bot walked into walls occasionally and
-- for no visible reason. Non-collidable hits are now skipped through.
local function castSolid(origin, displacement, exclusions)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = exclusions
    params.IgnoreWater = true

    -- Newer clients can filter non-collidable geometry natively. Support is
    -- tested once at startup (core.lua); this used to be a pcall plus a closure
    -- on every single cast, dozens of times a frame while steering.
    if RT.respectCanCollide then
        params.RespectCanCollide = true
        return Workspace:Raycast(origin, displacement, params)
    end

    local ignored = table.clone(exclusions)
    for _ = 1, 8 do
        params.FilterDescendantsInstances = ignored
        local hit = Workspace:Raycast(origin, displacement, params)
        if not hit then return nil end
        if hit.Instance.CanCollide then return hit end
        table.insert(ignored, hit.Instance)
    end
    return nil
end

-- A single centre ray also missed anything the character's shoulders clip, and
-- anything below chest height such as a railing, so clearance is tested as a
-- crude capsule: two heights across the character's own width.
--
-- Returns how far the capsule stays clear along `heading`, capped at `length`,
-- and `length` when nothing is hit. The steerer used to ask only the yes/no
-- question "clear at the probe distance?" and take the first heading that passed;
-- measuring the distance instead lets it prefer the roomiest heading, so it runs
-- into open space rather than committing to whichever near-blocked direction
-- happened to clear the probe by a hair.
-- Feet height of the character: the root part sits HipHeight above the floor.
local function getFeetY(root)
    local humanoid = root.Parent and root.Parent:FindFirstChildWhichIsA("Humanoid")
    local hip = humanoid and humanoid.HipHeight or 2.0
    return root.Position.Y - root.Size.Y * 0.5 - hip
end

-- Does a probe hit actually block walking? (2.2.0)
--
-- This is why the bot stuck on "semi rough terrain": the shin-height probe sits
-- about 1.4 studs above the feet, so on any upward slope it hit the ramp itself
-- within a few studs and reported the heading blocked. Straight ahead was then
-- never "clear the whole way", the fan swung to whichever sideways heading was
-- roomier, and the bot ground along the foot of every incline. A hit only
-- counts now if it is wall-like: a surface facing up is floor or ramp, and a
-- lip no taller than a step (checked by looking DOWN from head height just past
-- the hit) is something the humanoid steps onto. Tall walls are still caught -
-- by the head-height probe, which is unaffected.
hitBlocksWalking = function(hit, heading, feetY, exclusions)
    if hit.Normal.Y >= CFG.walkableNormalY then return false end
    if hit.Position.Y - feetY > CFG.maxStepHeight then return true end
    local past = hit.Position + heading * 0.75
    local top = castSolid(Vector3.new(past.X, feetY + 4.6, past.Z), Vector3.new(0, -5.1, 0), exclusions)
    if not top then return false end           -- a lip with a drop behind it; falling is allowed
    return (top.Position.Y - feetY) > CFG.maxStepHeight
end

-- Reused across calls so the fan allocates nothing per heading.
local HEADING_LATERALS = { 0, 0, 0 }

local function headingClearDistance(root, heading, length, enemy, radius)
    local exclusions = getRaycastExclusions(enemy)
    local side = Vector3.new(-heading.Z, 0, heading.X)
    local displacement = heading * length
    local nearest = length
    local feetY = getFeetY(root)
    HEADING_LATERALS[2] = radius
    HEADING_LATERALS[3] = -radius

    for _, height in ipairs(STEER_PROBE_HEIGHTS) do
        for i = 1, 3 do
            local origin = root.Position + Vector3.new(0, height, 0) + (side * HEADING_LATERALS[i])
            local hit = castSolid(origin, displacement, exclusions)
            if hit and hitBlocksWalking(hit, heading, feetY, exclusions) then
                local d = (hit.Position - origin).Magnitude
                if d < nearest then nearest = d end
            end
        end
    end

    return nearest
end


local function pruneBlockedHeadings(now)
    for i = #NAV.blockedHeadings, 1, -1 do
        if now >= NAV.blockedHeadings[i].expires then
            table.remove(NAV.blockedHeadings, i)
        end
    end
end

-- Angle between two flat unit vectors, in degrees.
local function flatAngleBetween(a, b)
    return math.deg(math.acos(math.clamp(a:Dot(b), -1, 1)))
end

local function isHeadingBlocked(heading, now)
    for _, entry in ipairs(NAV.blockedHeadings) do
        if now < entry.expires and flatAngleBetween(heading, entry.direction) <= entry.arc then
            return true
        end
    end
    return false
end

-- Records a heading that produced no movement. Re-blocking the same direction
-- widens its arc and extends it, because a repeat offender is usually a wall
-- being clipped at a shallow angle rather than a one-off snag.
local function blockHeading(direction, now)
    local flat = Vector3.new(direction.X, 0, direction.Z)
    if flat.Magnitude < 0.01 then return end
    flat = flat.Unit

    for _, entry in ipairs(NAV.blockedHeadings) do
        if flatAngleBetween(flat, entry.direction) <= entry.arc then
            entry.expires = now + CFG.headingBlacklistTime
            entry.arc = math.min(entry.arc + CFG.headingBlacklistArcGrowth, CFG.headingBlacklistMaxArc)
            heavyDebug("Steering", string.format(
                "Heading still blocked; arc widened to %.0f degrees.", entry.arc))
            return
        end
    end

    table.insert(NAV.blockedHeadings, {
        direction = flat,
        arc = CFG.headingBlacklistArc,
        expires = now + CFG.headingBlacklistTime,
    })
    heavyDebug("Steering", string.format(
        "Blacklisted heading (%.2f, %.2f) for %.0fs after no movement.",
        flat.X, flat.Z, CFG.headingBlacklistTime))
end

local function steerTowards(root, goalPosition, enemy)
    local flat = Vector3.new(
        goalPosition.X - root.Position.X, 0, goalPosition.Z - root.Position.Z)
    local distance = flat.Magnitude
    if distance < 0.5 then return goalPosition end

    local direction = flat.Unit
    local probeLength = math.min(distance, CFG.steerProbeDistance)
    local _, playerRadius = getPlayerHitboxMetrics()
    local now = os.clock()

    -- Reuse the last decision for a moment. The fan is six rays per heading
    -- across up to eleven headings, and running all of it every frame was the
    -- second largest cost in direct mode. The answer changes slowly, and the
    -- stall detector is what catches a heading that has gone bad.
    if NAV.steerCache
        and (now - NAV.steerCacheTime) < CFG.steerRefreshInterval
        and NAV.steerCacheGoal
        and (NAV.steerCacheGoal - goalPosition).Magnitude < 4.0 then
        return NAV.steerCache, NAV.steerCacheAngle
    end

    pruneBlockedHeadings(now)

    -- Minimum room worth stepping into: a couple of body-widths plus a margin.
    -- Below this a heading is treated as blocked rather than "clear by a hair".
    local minClear = math.min(probeLength, playerRadius * 2 + CFG.steerOpennessMargin)

    local function commit(angle, grounded)
        if angle ~= NAV.steerAngle then
            NAV.steerAngle = angle
            NAV.steerTime = now
        end
        NAV.steerCache = grounded
        NAV.steerCacheAngle = angle
        NAV.steerCacheTime = now
        NAV.steerCacheGoal = goalPosition
    end

    -- Measures one heading. Returns the grounded destination and how open the
    -- heading is, or nil if it is blocked, blacklisted, off a ledge or inside a
    -- known-bad area.
    local function evaluate(angle, respectBlacklist)
        local heading = rotateFlatDirection(direction, angle)
        if respectBlacklist and isHeadingBlocked(heading, now) then return nil end
        local clear = headingClearDistance(root, heading, probeLength, enemy, playerRadius)
        if clear < minClear then return nil end
        -- Require floor at the destination so it does not steer off a ledge.
        local candidate = root.Position + (heading * math.min(clear, probeLength))
        local grounded = projectToGround(candidate, enemy)
        -- Asymmetric (2.2.0): a drop is fine - there is no fall damage to speak
        -- of and the drop is usually the way forward - but a climb has to be
        -- within a jump. The old symmetric 12-stud gate refused ledges down.
        local rise = grounded.Y - getFeetY(root)
        if rise >= CFG.maxClimbHeight or rise <= -CFG.maxDropHeight then return nil end
        if respectBlacklist and isInsideBlockedArea(grounded) then return nil end
        return grounded, clear
    end

    local openThreshold = probeLength - 0.5

    local function pick(respectBlacklist)
        -- Stay on the committed deviation while it is still genuinely roomy, so
        -- the steerer does not oscillate between two equally open headings and
        -- grind into the corner between them. It is dropped the moment it stops
        -- being open, which is what lets it peel away from a wall it is scraping.
        if NAV.steerAngle and (now - NAV.steerTime) < CFG.steerCommitTime then
            local grounded, clear = evaluate(NAV.steerAngle, respectBlacklist)
            if grounded and clear >= probeLength * 0.85 then
                commit(NAV.steerAngle, grounded)
                return grounded, NAV.steerAngle
            end
        end

        -- Walk the fan in increasing deviation and take the FIRST heading that is
        -- clear the whole way. In the open that is straight ahead on the first
        -- probe, so the common case is six rays and cheap - evaluating every
        -- heading each frame to rank openness was a real frame cost. Only when
        -- nothing is clear the whole way (a genuinely tight spot) do we fall back
        -- to the roomiest partial heading, which is what turns the bot into the
        -- open direction along a wall instead of grinding straight into it.
        local bestGrounded, bestAngle, bestClear
        for _, angle in ipairs(STEER_FAN_ANGLES) do
            local grounded, clear = evaluate(angle, respectBlacklist)
            if grounded then
                if clear >= openThreshold
                    and math.abs(angle) <= CFG.steerOpennessDeviationBudget then
                    commit(angle, grounded)
                    return grounded, angle
                end
                if not bestClear or clear > bestClear then
                    bestClear, bestGrounded, bestAngle = clear, grounded, angle
                end
            end
        end

        if bestGrounded then
            commit(bestAngle, bestGrounded)
            return bestGrounded, bestAngle
        end
        return nil
    end

    local target, angle = pick(true)
    if target then return target, angle end

    -- Nothing survived the blacklist. Retry ignoring it, since standing still is
    -- never better than trying a direction that failed a while ago. Skipped when
    -- the blacklist is empty, because that second sweep would be identical.
    if #NAV.blockedHeadings > 0 then
        heavyDebugThrottled("steer_allblocked", 3.0, "Steering",
            "No unblocked heading available; retrying without the blacklist.")
        target, angle = pick(false)
        if target then return target, angle end
    end

    NAV.steerAngle = nil
    return goalPosition, nil
end

-- Confirms whether the navmesh works *at all* from here, by pathing a few studs
-- forward. If even that fails the problem is the place, not the target, and
-- benching every enemy on the map would be the wrong conclusion.
local function probeNavmeshUsable(fromPosition, enemy)
    local probeTarget = projectToGround(
        fromPosition + Vector3.new(CFG.navmeshProbeDistance, 0, 0), enemy)

    local path = PathfindingService:CreatePath({
        AgentRadius = 1.0,
        AgentHeight = 4.5,
        AgentCanJump = true,
        AgentCanClimb = false,
        WaypointSpacing = 4
    })

    local ok = pcall(function()
        path:ComputeAsync(fromPosition, probeTarget)
    end)

    return ok and path.Status == Enum.PathStatus.Success
end


-- Commits a set of waypoints as the active pursuit route.
local function adoptPursuitRoute(waypoints, enemy, targetPosition, startIndex)
    NAV.waypoints = waypoints
    NAV.index = startIndex
    NAV.enemy = enemy
    NAV.lastTarget = targetPosition
    NAV.lastComputeTime = os.clock()
    NAV.lastIssuedMove = nil
    NAV.needsRecompute = false
    NAV.computing = false
    renderCurrentPath()
end

local function computePursuitPath(root, enemy, targetPosition)
    if NAV.computing then
        heavyDebug("Pathfinding", "Skipped: Already computing path in another thread.")
        return false
    end
    NAV.computing = true

    if NAV.blockedConnection then
        NAV.blockedConnection:Disconnect()
        NAV.blockedConnection = nil
    end

    local groundedStart = projectToGround(root.Position, enemy)
    local groundedTarget = projectToGround(targetPosition, enemy)
    local distanceToTarget = (groundedStart - groundedTarget).Magnitude
    heavyDebug("Pathfinding", string.format("Attempting path to %s. Distance: %.1f studs", enemy.Name, distanceToTarget))

    local inHazard = not isPositionSafeFromDamageBricks(groundedStart, 0.5)

    if inHazard then
        local stagingPointB = findStagingSafePoint(groundedStart, groundedTarget, enemy)
        if stagingPointB then
            heavyDebug("Pathfinding", "Phase 1: Executing Staging Escape Point B via Side-Escape.")
            local waypointsCombined = {
                {Position = groundedStart, Action = Enum.PathWaypointAction.Walk},
                {Position = stagingPointB, Action = Enum.PathWaypointAction.Walk}
            }

            local pathBC = PathfindingService:CreatePath({
                AgentRadius = CFG.wallPadding,
                AgentHeight = 4.5,
                AgentCanJump = true,
                AgentCanClimb = false,
                WaypointSpacing = 4
            })
            local successBC, _ = pcall(function()
                pathBC:ComputeAsync(stagingPointB, groundedTarget)
            end)

            if successBC and pathBC.Status == Enum.PathStatus.Success then
                local rawBC = pathBC:GetWaypoints()
                for i = 2, #rawBC do
                    table.insert(waypointsCombined, rawBC[i])
                end
            end

            NAV.waypoints = waypointsCombined
            NAV.index = 2
            NAV.enemy = enemy
            NAV.lastTarget = targetPosition
            NAV.lastComputeTime = os.clock()
            NAV.lastIssuedMove = nil
            NAV.needsRecompute = false
            NAV.computing = false
            renderCurrentPath()
            return true
        end
    end

    -- Navmesh already established as unusable here: skip the ladder entirely.
    -- Running four yielding ComputeAsync calls per attempt against a navmesh
    -- that cannot answer is what produced the log flood.
    if os.clock() < NAV.navmeshDeadUntil then
        heavyDebugThrottled("navmesh_direct", 3.0, "Pathfinding", string.format(
            "Navmesh unusable here; walking directly to %s (%.1f studs).",
            enemy.Name, distanceToTarget))
        adoptPursuitRoute(buildDirectWalkRoute(groundedStart, groundedTarget, enemy),
            enemy, targetPosition, 1)
        NAV.routeIsDirect = true
        return true
    end

    -- NoPath usually means one of three things: the agent is modelled too wide
    -- for a doorway, the standoff point landed off the navmesh, or the enemy is
    -- genuinely sealed off. The ladder below distinguishes them: shrink the
    -- agent first, then aim progressively shorter of the target so the bot at
    -- least closes distance and can re-path from somewhere better connected.
    local attempts = {
        { radius = CFG.wallPadding, fraction = 1.0, note = "full target, configured radius" },
        { radius = 1.0,             fraction = 1.0, note = "full target, slim radius" },
        { radius = 1.0,             fraction = 0.66, note = "two thirds of the way" },
        { radius = 1.0,             fraction = 0.33, note = "one third of the way" },
    }

    local path, rawWaypoints, lastStatus
    for index, attempt in ipairs(attempts) do
        local aimPoint = groundedTarget
        if attempt.fraction < 1.0 then
            aimPoint = projectToGround(groundedStart:Lerp(groundedTarget, attempt.fraction), enemy)
        end

        local candidatePath = PathfindingService:CreatePath({
            AgentRadius = attempt.radius,
            AgentHeight = 4.5,
            AgentCanJump = true,
            AgentCanClimb = false,
            WaypointSpacing = 4
        })

        local computed = pcall(function()
            candidatePath:ComputeAsync(groundedStart, aimPoint)
        end)

        lastStatus = candidatePath.Status

        if computed and candidatePath.Status == Enum.PathStatus.Success then
            local waypoints = candidatePath:GetWaypoints()
            if #waypoints > 1 then
                path = candidatePath
                rawWaypoints = waypoints
                if index > 1 then
                    heavyDebug("Pathfinding", string.format(
                        "Recovered on attempt %d/%d (%s).", index, #attempts, attempt.note))
                end
                break
            end
        end

        heavyDebug("Pathfinding", string.format("Attempt %d/%d failed (%s): %s",
            index, #attempts, attempt.note, tostring(candidatePath.Status)), DEBUG_VERBOSE)
    end

    if path then
        NAV.failureStreak = 0
        NAV.navmeshDeadUntil = -math.huge
        NAV.benched[enemy] = nil
        NAV.routeIsDirect = false
        adoptPursuitRoute(rawWaypoints, enemy, targetPosition, 2)

        NAV.blockedConnection = path.Blocked:Connect(function()
            heavyDebug("Pathfinding", "Path blocked event triggered. Forcing recompute.")
            NAV.needsRecompute = true
        end)

        return true
    end

    NAV.failureStreak = NAV.failureStreak + 1

    -- After repeated total failures, confirm the navmesh is dead here so future
    -- attempts can skip ComputeAsync entirely. This is now only an optimisation
    -- and a diagnostic; the fallback below no longer depends on its verdict.
    if NAV.failureStreak >= CFG.navmeshFailureThreshold then
        NAV.failureStreak = 0
        if not probeNavmeshUsable(groundedStart, enemy) then
            NAV.navmeshDeadUntil = os.clock() + CFG.navmeshRetestInterval
            table.clear(NAV.benched)
            heavyDebug("Pathfinding", string.format(
                "Navmesh cannot route even %.0f studs from here. Skipping ComputeAsync for %.0fs.",
                CFG.navmeshProbeDistance, CFG.navmeshRetestInterval))
        end
    end

    -- Always walk at the target. Benching here was the mistake: with no route to
    -- anything, every enemy got benched in turn and the bot cycled the whole map
    -- doing nothing. Heading in the right direction is strictly better than
    -- standing still, and often opens a route once the gap closes.
    -- An enemy is only benched later, by the stuck detector, if walking at it
    -- genuinely makes no progress.
    heavyDebugThrottled("path_direct", 2.0, "Pathfinding", string.format(
        "No navmesh route to %s (%s) at %.1f studs. Walking directly instead.",
        enemy.Name, tostring(lastStatus), distanceToTarget))

    adoptPursuitRoute(buildDirectWalkRoute(groundedStart, groundedTarget, enemy),
        enemy, targetPosition, 1)
    NAV.routeIsDirect = true
    return true
end

-- Navmesh waypoints can run within a stud of a wall, and the character is
-- wider than that: it walks into the wall and slides, or stops. Two rays at
-- hip height to either side of the direction of travel; a wall closer than
-- the character's clearance pushes the goal off it by the deficit, so the
-- next MoveTo angles away from the wall instead of along it.
local wallParams = RaycastParams.new()
wallParams.FilterType = Enum.RaycastFilterType.Exclude
wallParams.IgnoreWater = true
local function keepOffWalls(root, goal, enemy)
    local to = Vector3.new(goal.X - root.Position.X, 0, goal.Z - root.Position.Z)
    if to.Magnitude < 0.5 then return goal end
    local dir = to.Unit
    local side = Vector3.new(-dir.Z, 0, dir.X)
    local _, playerRadius = getPlayerHitboxMetrics()
    local clearance = math.max(CFG.wallPadding, playerRadius + 0.6)
    wallParams.FilterDescendantsInstances = getRaycastExclusions(enemy)
    local shift = 0
    for _, s in ipairs({ 1, -1 }) do
        -- Hip and shin: a plinth or a step is below the hip ray.
        local room = clearance
        for _, h in ipairs({ 0.5, -1.5 }) do
            local origin = root.Position + Vector3.new(0, h, 0)
            local hit = Workspace:Raycast(origin, side * (s * clearance), wallParams)
            if hit and hit.Instance and hit.Instance.CanCollide then
                local r = (hit.Position - origin).Magnitude
                if r < room then room = r end
            end
        end
        if room < clearance then shift = shift - s * (clearance - room) end
    end
    if shift == 0 then return goal end
    return goal + side * shift
end

-- Closing on a boss from far out is the walk that gets you shot: after a
-- death the respawn is 130 studs from the Champion and its aimed shot comes
-- every few seconds. WalkSpeed goes up for that walk and back on arrival.
-- The client's own checker resets WalkSpeed above 45; this stays well under.
local function applyApproachSpeed(humanoid, enemy, root, enemyRoot)
    if not humanoid or not enemyRoot then return end
    local boost = CFG.approachWalkSpeed or 0
    local far = (root.Position - enemyRoot.Position).Magnitude > CFG.approachBoostDistance
    local isBoss = S.isBossModel and S.isBossModel(enemy)
    if boost > 0 and isBoss and far then
        if humanoid.WalkSpeed ~= boost then RT.walkSpeedBefore = RT.walkSpeedBefore or humanoid.WalkSpeed humanoid.WalkSpeed = math.min(boost, 40) end
    elseif RT.walkSpeedBefore then
        humanoid.WalkSpeed = RT.walkSpeedBefore
        RT.walkSpeedBefore = nil
    end
end

local function updatePursuitMovement(enemy, humanoid, root, enemyRoot)
    applyApproachSpeed(humanoid, enemy, root, enemyRoot)
    local benchedUntil = NAV.benched[enemy]
    if benchedUntil and os.clock() < benchedUntil then
        setMovementState("target unreachable, reselecting")
        return
    end

    local targetPosition = getStandOffPosition(root, enemyRoot)
    local now = os.clock()

    local targetChanged = NAV.enemy ~= enemy
    local targetMoved = not NAV.lastTarget or (targetPosition - NAV.lastTarget).Magnitude >= CFG.pathTargetMoveThreshold
    local inHazard = not isPositionSafeFromDamageBricks(root.Position, 0.5)
    local retryDelay = #NAV.waypoints == 0 and CFG.pathFailureRetryInterval or CFG.pathRecomputeInterval
    local canRecompute = (now - NAV.lastComputeTime >= retryDelay) or inHazard

    if not NAV.progressPosition then
        NAV.progressPosition = root.Position
        NAV.progressTime = now
    elseif (root.Position - NAV.progressPosition).Magnitude >= CFG.stuckProgressDistance then
        NAV.progressPosition = root.Position
        NAV.progressTime = now
    elseif NAV.index <= #NAV.waypoints
        and (root.Position - targetPosition).Magnitude > CFG.waypointAdvanceDistance
        and now - NAV.progressTime >= CFG.stuckTimeout then
        heavyDebug("Stuck", "Stuck timeout reached. Forcing path recompute.")
        -- A stall is usually a lip, a step or an invisible wall the route did not
        -- know about. Hopping costs nothing and clears most of them, on navmesh
        -- routes too - the mesh is baked without the game's invisible walls.
        humanoid.Jump = true
        NAV.needsRecompute = true
        NAV.progressPosition = root.Position
        NAV.progressTime = now
    end

    local wantsRecompute = targetChanged or ((targetMoved or NAV.needsRecompute or #NAV.waypoints == 0) and canRecompute)

    -- Throttle is tested before the string is built; formatting this every frame
    -- only to discard it was pure garbage generation.
    if RT.debugLevel >= DEBUG_NORMAL and (now - (debugThrottleClocks["move_state"] or -math.huge)) >= 1.0 then
        heavyDebugThrottled("move_state", 1.0, "Movement", string.format(
            "target=%s dist=%.1f | waypoints=%d idx=%d | changed=%s moved=%s needs=%s canRecompute=%s computing=%s | sinceCompute=%.2fs",
            enemy.Name,
            (root.Position - enemyRoot.Position).Magnitude,
            #NAV.waypoints, NAV.index,
            tostring(targetChanged), tostring(targetMoved), tostring(NAV.needsRecompute),
            tostring(canRecompute), tostring(NAV.computing),
            now - NAV.lastComputeTime))
    end

    if wantsRecompute then
        if not NAV.computing then
            heavyDebug("Movement", "Triggering path recompute for " .. enemy.Name)
            task.spawn(function()
                computePursuitPath(root, enemy, targetPosition)
            end)
        else
            heavyDebugThrottled("move_blocked", 2.0, "Movement", "Recompute wanted but a compute is already in flight.")
        end
    end

    while NAV.index <= #NAV.waypoints do
        local waypoint = NAV.waypoints[NAV.index]
        local waypointDelta = root.Position - waypoint.Position
        local horizontalDistance = Vector3.new(waypointDelta.X, 0, waypointDelta.Z).Magnitude

        if horizontalDistance > CFG.waypointAdvanceDistance or math.abs(waypointDelta.Y) > 4.5 then
            break
        end
        -- Near enough to pass it - but on a turn, passing it early aims the
        -- next MoveTo through the inside wall of the corner. With waypoints
        -- four studs apart and a four-stud advance radius that was every
        -- corner, and a staircase that turns ninety degrees is a corner with
        -- a wall on the inside and a drop on the outside. A waypoint is only
        -- passed once the one after it is in clear sight, or once we are
        -- practically on it.
        local following = NAV.waypoints[NAV.index + 1]
        if following and horizontalDistance > 1.5
            and not isPathSegmentClear(root.Position, following.Position, enemy) then
            break
        end
        NAV.index = NAV.index + 1
    end

    local waypoint = NAV.waypoints[NAV.index]
    if waypoint then
        -- Actively moving toward something: the recovery detector is armed.
        NAV.driving = true
        if not CFG.faceTarget then
            humanoid.AutoRotate = true
        end

        local moveTarget = waypoint.Position
        local steerAngle = nil

        if NAV.routeIsDirect then
            -- Steer each frame rather than caching: obstacles are only known by
            -- probing, so the heading has to be re-evaluated as the bot moves.
            moveTarget, steerAngle = steerTowards(root, waypoint.Position, enemy)
            moveTarget = keepOffWalls(root, moveTarget, enemy)
            -- Only re-send the goal when the carrot has actually shifted. The
            -- steer result is a fixed world point held for a beat, so hammering
            -- MoveTo with it every frame just restarts the humanoid's approach
            -- and micro-stutters; the carrot still moves forward as the character
            -- advances, so MoveTo refreshes often enough not to time out.
            if not NAV.lastIssuedMove
                or (NAV.lastIssuedMove - moveTarget).Magnitude > CFG.moveReissueThreshold then
                humanoid:MoveTo(moveTarget)
                NAV.lastIssuedMove = moveTarget
            end

            -- World-space stall check, separate from progress-toward-enemy.
            -- Standing still while walking means the heading is into geometry
            -- the probes did not see, so retire that direction rather than
            -- re-picking it the moment the commitment window lapses.
            if not NAV.stallAnchor
                or (root.Position - NAV.stallAnchor).Magnitude >= CFG.headingStallDistance then
                NAV.stallAnchor = root.Position
                NAV.stallTime = now
            elseif now - NAV.stallTime >= CFG.headingStallTime then
                blockHeading(moveTarget - root.Position, now)
                NAV.stallAnchor = root.Position
                NAV.stallTime = now
                NAV.steerAngle = nil
                -- Drop the cache too, or the next frame would serve the very
                -- heading that was just blacklisted.
                NAV.steerCache = nil
                humanoid.Jump = true
            end

            -- Progress is measured against the enemy, not the steering target,
            -- so circling an obstacle does not read as success.
            local distanceNow = (root.Position - enemyRoot.Position).Magnitude
            if not NAV.directProgressPosition
                or (NAV.directProgressPosition - enemyRoot.Position).Magnitude - distanceNow > 2.0 then
                NAV.directProgressPosition = root.Position
                NAV.directProgressTime = now
            elseif now - NAV.directProgressTime >= CFG.directWalkGiveUpTime then
                NAV.benched[enemy] = now + CFG.unreachableCooldown
                NAV.directProgressPosition = nil
                NAV.directProgressTime = now
                NAV.forceRescan = true
                heavyDebug("Pathfinding", string.format(
                    "Walking at %s gained no ground in %.0fs. Benched for %.0fs; taking the next target.",
                    enemy.Name, CFG.directWalkGiveUpTime, CFG.unreachableCooldown))
                return
            end

            setMovementState(string.format("DIRECT %.0f studs%s%s",
                (root.Position - enemyRoot.Position).Magnitude,
                steerAngle and steerAngle ~= 0 and string.format(" (steer %d)", steerAngle) or "",
                (#NAV.blockedHeadings > 0 or #NAV.blockedAreas > 0)
                    and string.format(" [%dh %da blocked]", #NAV.blockedHeadings, #NAV.blockedAreas)
                    or ""))
            return
        end

        -- The navmesh is baked without the game's invisible walls, so a valid
        -- navmesh path can still run the character straight into one. Probe the
        -- short step to the next waypoint; if a solid is actually in the way,
        -- steer around it and ask for a fresh path rather than grinding on it.
        local moveGoal = waypoint.Position
        local toWp = Vector3.new(waypoint.Position.X - root.Position.X, 0,
            waypoint.Position.Z - root.Position.Z)
        local wpDist = toWp.Magnitude
        if wpDist > 1.5 then
            local probe = math.min(wpDist, CFG.wallProbeDistance)
            local excl = getRaycastExclusions(enemy)
            local dir = toWp.Unit
            local feetY = getFeetY(root)
            -- Chest and shin. The plinth of a pillar is below the chest ray;
            -- a stair riser is below it too, and is a step, not a wall.
            local high = castSolid(root.Position + Vector3.new(0, 1.5, 0), dir * probe, excl)
            local low = castSolid(root.Position - Vector3.new(0, 1.5, 0), dir * probe, excl)
            if (high and hitBlocksWalking(high, dir, feetY, excl))
                or (low and hitBlocksWalking(low, dir, feetY, excl)) then
                moveGoal = steerTowards(root, waypoint.Position, enemy)
                NAV.needsRecompute = true
            end
        end
        moveGoal = keepOffWalls(root, moveGoal, enemy)

        -- Pressed against something no probe saw: after a moment without
        -- moving, sidestep - alternating sides - and hop, then let the path
        -- recompute from the new spot. This is the wall the character was
        -- found standing into.
        -- The anchor is only meaningful while this branch runs every tick.
        -- Left over from a walk that ended a while ago it fired a sidestep
        -- and a hop on the first tick of the next path.
        local stale = not NAV.wpStallTick or now - NAV.wpStallTick > 0.3
        NAV.wpStallTick = now
        if stale or not NAV.wpStallAnchor or (root.Position - NAV.wpStallAnchor).Magnitude >= 1.0 then
            NAV.wpStallAnchor = root.Position
            NAV.wpStallTime = now
        elseif now - NAV.wpStallTime >= CFG.wallStallTime then
            local dir = Vector3.new(moveGoal.X - root.Position.X, 0, moveGoal.Z - root.Position.Z)
            if dir.Magnitude > 0.1 then
                dir = dir.Unit
                local side = Vector3.new(-dir.Z, 0, dir.X)
                -- Which way round the wall? It used to ALTERNATE sides every
                -- stall, which against a long wall is a left-right shuffle on
                -- the spot. Measure the room to each side and take the roomier
                -- one; keep taking it for a few seconds so successive stalls
                -- walk along the wall instead of undoing each other.
                local _, playerRadius = getPlayerHitboxMetrics()
                local roomRight = headingClearDistance(root, side, 8, enemy, playerRadius)
                local roomLeft = headingClearDistance(root, -side, 8, enemy, playerRadius)
                local s = NAV.wpStallSide
                if not s or not NAV.wpStallSideAt or now - NAV.wpStallSideAt > 4.0 then
                    s = roomRight >= roomLeft and 1 or -1
                end
                if (s == 1 and roomRight < 2.0 and roomLeft > roomRight)
                    or (s == -1 and roomLeft < 2.0 and roomRight > roomLeft) then
                    s = -s
                end
                NAV.wpStallSide, NAV.wpStallSideAt = s, now
                local along = math.min(6, math.max(2, (s == 1 and roomRight or roomLeft) - 1))
                moveGoal = root.Position + side * (along * s) + dir * 1.0
                humanoid.Jump = true
                NAV.lastIssuedMove = nil
                NAV.needsRecompute = true
                heavyDebugThrottled("wp_stall", 1.0, "Pathfinding", string.format(
                    "Stopped against something; going round to the %s (%.0f studs of room).",
                    s == 1 and "right" or "left", along))
            end
            NAV.wpStallAnchor = root.Position
            NAV.wpStallTime = now
        end

        if not NAV.lastIssuedMove
            or (NAV.lastIssuedMove - moveGoal).Magnitude > CFG.moveReissueThreshold then
            if waypoint.Action == Enum.PathWaypointAction.Jump then
                humanoid.Jump = true
            end
            humanoid:MoveTo(moveGoal)
            NAV.lastIssuedMove = moveGoal
            heavyDebug("Movement", string.format("MoveTo waypoint %d/%d", NAV.index, #NAV.waypoints), DEBUG_VERBOSE)
        end
        setMovementState(string.format("PURSUE wp %d/%d", NAV.index, #NAV.waypoints))
    elseif (root.Position - targetPosition).Magnitude > CFG.directHopDistance then
        NAV.driving = true
        NAV.needsRecompute = true
        NAV.lastIssuedMove = nil
        heavyDebugThrottled("move_nopath", 1.0, "Movement", string.format(
            "NO PATH but target is %.1f studs away. Flagged for recompute.",
            (root.Position - targetPosition).Magnitude))
        setMovementState("NO PATH - retrying")
    elseif (root.Position - targetPosition).Magnitude > CFG.inRangeDeadband then
        if not NAV.lastIssuedMove
            or (NAV.lastIssuedMove - targetPosition).Magnitude > CFG.moveReissueThreshold then
            humanoid:MoveTo(targetPosition)
            NAV.lastIssuedMove = targetPosition
        end
        setMovementState("IN RANGE")
    else
        -- Inside the deadband: hold position and let facing and the attack run.
        -- The standoff point orbits the enemy as we move, so chasing it exactly
        -- made the character shuffle in place the whole time it was attacking.
        if NAV.lastIssuedMove and (NAV.lastIssuedMove - root.Position).Magnitude > 0.5 then
            humanoid:MoveTo(root.Position)
            NAV.lastIssuedMove = root.Position
        end
        setMovementState("IN RANGE")
    end
end

-- =========================================================================
-- ROUTED POINT WALKING (2.2.0)
--
-- walkTowardPoint used to be a straight steer at the point: fine on open floor,
-- useless across a drop, up a ramp with a lip, or around anything the navmesh
-- knows how to route past - which is exactly the terrain the manual path exists
-- for. It now asks the navmesh for a route to the point (slim agent, jumping
-- allowed) and follows it the way the pursuit follower does, steering directly
-- only when the navmesh has no answer. It also measures progress toward the
-- point itself, so a caller can tell "arrived" from "walked into a wall for six
-- seconds" and skip the point instead of parking on it forever.
-- =========================================================================

local function clearPointRoute()
    NAV.pointRoute = nil
    NAV.pointProgressDistance = nil
    NAV.pointProgressTime = 0
    NAV.walkAnchor = nil
    NAV.lastIssuedMove = nil
end

-- Off the Heartbeat: ComputeAsync yields.
local function computePointRoute(fromPosition, point)
    if NAV.computingPoint then return end
    NAV.computingPoint = true

    local ok, err = xpcall(function()
        local route = {
            target = point, waypoints = {}, index = 1, direct = true,
            computedAt = os.clock(), stalls = 0, needsRecompute = false,
        }
        if os.clock() >= NAV.navmeshDeadUntil then
            local path = PathfindingService:CreatePath({
                AgentRadius = CFG.pointRouteAgentRadius,
                AgentHeight = 4.5,
                AgentCanJump = true,
                AgentCanClimb = false,
                WaypointSpacing = 4,
            })
            local computed = pcall(function()
                path:ComputeAsync(fromPosition, point)
            end)
            if computed and path.Status == Enum.PathStatus.Success then
                local waypoints = path:GetWaypoints()
                if #waypoints > 1 then
                    route.waypoints = waypoints
                    route.index = 2
                    route.direct = false
                end
            end
            if route.direct then
                heavyDebugThrottled("point_nopath", 2.0, "PointWalk", string.format(
                    "No navmesh route to (%.0f, %.0f, %.0f) [%s]; steering directly.",
                    point.X, point.Y, point.Z, tostring(path.Status)))
            end
        end
        route.computedAt = os.clock()
        NAV.pointRoute = route
    end, debug.traceback)

    NAV.computingPoint = false
    if not ok then
        heavyDebugThrottled("point_err", 1.0, "FATAL", "Point route threw:\n" .. tostring(err))
    end
end

-- Walks toward `point`. Returns the planar distance remaining and a `stuck`
-- flag: true once the distance has not improved for CFG.pointGiveUpTime.
local function walkTowardPoint(humanoid, root, point)
    -- Facing goes back to the Humanoid so it looks where it is walking.
    releaseFacing(humanoid)
    NAV.driving = true

    local now = os.clock()
    local rootPos = root.Position
    local distance = Vector3.new(point.X - rootPos.X, 0, point.Z - rootPos.Z).Magnitude

    local route = NAV.pointRoute
    local sameTarget = route ~= nil
        and (route.target - point).Magnitude <= CFG.pointRouteTargetMoveThreshold

    -- Progress toward the point itself, not toward the current carrot, so
    -- circling an obstacle does not read as success.
    if not sameTarget or not NAV.pointProgressDistance then
        NAV.pointProgressDistance = distance
        NAV.pointProgressTime = now
    elseif distance < NAV.pointProgressDistance - 1.5 then
        NAV.pointProgressDistance = distance
        NAV.pointProgressTime = now
    end
    local stuck = sameTarget and (now - NAV.pointProgressTime) >= CFG.pointGiveUpTime

    -- (Re)route when the target changed, the route asked for one, or a navmesh
    -- route has gone stale. The old route keeps being followed while the new
    -- one computes, unless it was for a different point.
    if distance > 6 and not NAV.computingPoint
        and (not sameTarget or route.needsRecompute
            or (not route.direct and now - route.computedAt >= CFG.pointRouteRecomputeInterval)) then
        if not sameTarget then
            NAV.pointRoute = nil
            route = nil
        else
            route.needsRecompute = false
        end
        local from = rootPos
        task.spawn(function()
            computePointRoute(from, point)
        end)
    end

    local moveGoal = nil
    local usingRoute = false
    if route and sameTarget and not route.direct then
        local waypoints = route.waypoints
        while route.index <= #waypoints do
            local delta = rootPos - waypoints[route.index].Position
            local hd = Vector3.new(delta.X, 0, delta.Z).Magnitude
            if hd > CFG.waypointAdvanceDistance or math.abs(delta.Y) > 4.5 then
                break
            end
            -- Pass a waypoint only when the next is in clear sight (see the
            -- pursuit follower): passing it early cuts the corner.
            local following = waypoints[route.index + 1]
            if following and hd > 1.5
                and not isPathSegmentClear(rootPos, following.Position, nil) then
                break
            end
            route.index = route.index + 1
        end
        local waypoint = waypoints[route.index]
        if waypoint then
            usingRoute = true
            moveGoal = waypoint.Position
            if waypoint.Action == Enum.PathWaypointAction.Jump then
                humanoid.Jump = true
            end
            -- The navmesh is baked without the game's invisible walls: probe the
            -- short step to the waypoint and steer around a solid in the way.
            local toWp = Vector3.new(moveGoal.X - rootPos.X, 0, moveGoal.Z - rootPos.Z)
            local wpDist = toWp.Magnitude
            if wpDist > 1.5 then
                local probe = math.min(wpDist, CFG.wallProbeDistance)
                local excl = getRaycastExclusions(nil)
                local hit = castSolid(rootPos + Vector3.new(0, 1.5, 0), toWp.Unit * probe, excl)
                if hit and hitBlocksWalking(hit, toWp.Unit, getFeetY(root), excl) then
                    moveGoal = steerTowards(root, moveGoal, nil)
                    route.needsRecompute = true
                end
            end
        end
    end
    if not moveGoal then
        moveGoal = steerTowards(root, point, nil)
    end

    if not NAV.lastIssuedMove
        or (NAV.lastIssuedMove - moveGoal).Magnitude > CFG.moveReissueThreshold then
        humanoid:MoveTo(moveGoal)
        NAV.lastIssuedMove = moveGoal
    end

    -- Stall: standing still while walking. Hop it and drop the steer
    -- commitment. A navmesh hop that stalls repeatedly is abandoned for direct
    -- steering (the mesh did not know about whatever we are stuck on); a direct
    -- heading that stalls is blacklisted like it is in pursuit.
    if not NAV.walkAnchor
        or (rootPos - NAV.walkAnchor).Magnitude >= CFG.headingStallDistance then
        NAV.walkAnchor = rootPos
        NAV.walkAnchorTime = now
    elseif now - NAV.walkAnchorTime >= CFG.headingStallTime then
        humanoid.Jump = true
        NAV.steerAngle = nil
        NAV.steerCache = nil
        NAV.walkAnchor = rootPos
        NAV.walkAnchorTime = now
        if usingRoute then
            route.stalls = route.stalls + 1
            if route.stalls >= CFG.pointRouteStallLimit then
                route.direct = true
                heavyDebug("PointWalk", string.format(
                    "Navmesh hop stalled %d times; steering directly for this point.", route.stalls))
            end
        else
            blockHeading(moveGoal - rootPos, now)
        end
    end

    return distance, stuck
end

-- Walk the hardcoded path. progressPath (run every frame) advances pathIndex as
-- waypoints are passed, so this just walks toward the current one. When the
-- path is used up it holds. Returns false if no path is set OR it is already
-- finished, so the caller can fall back to plain idle. A waypoint that cannot
-- be closed on for CFG.pointGiveUpTime is skipped rather than parked on.
local function followPath(humanoid, root)
    local count = #NAV.waypath
    if count == 0 or NAV.pathIndex > count then return false end

    local target = NAV.waypath[NAV.pathIndex]
    local distance, stuck = walkTowardPoint(humanoid, root, target)
    if stuck then
        heavyDebug("Path", string.format(
            "Waypoint #%d not getting closer for %.0fs; skipping to the next.",
            NAV.pathIndex, CFG.pointGiveUpTime))
        NAV.pathIndex = NAV.pathIndex + 1
        if NAV.pathIndex > count and CFG.loopPath then NAV.pathIndex = 1 end
        clearPointRoute()
        if S.refreshPathMarkers then S.refreshPathMarkers() end
    end
    setMovementState(string.format("PATH wp %d/%d (%.0f studs%s)",
        NAV.pathIndex, count, distance,
        (NAV.pointRoute and not NAV.pointRoute.direct) and ", routed" or ", direct"))
    return true
end

S.blockArea = blockArea
S.clearEscapeNodes = clearEscapeNodes
S.clearEscapeRoute = clearEscapeRoute
S.clearRenderedPath = clearRenderedPath
S.destroyFacingRig = destroyFacingRig
S.faceTowards = faceTowards
S.followEscapeRoute = followEscapeRoute
S.followPath = followPath
S.pruneBlockedAreas = pruneBlockedAreas
S.releaseFacing = releaseFacing
S.renderCurrentPath = renderCurrentPath
S.renderEscapeRoute = renderEscapeRoute
S.resetPursuitPath = resetPursuitPath
S.resolveEscapeRoute = resolveEscapeRoute
S.updatePursuitMovement = updatePursuitMovement
S.walkTowardPoint = walkTowardPoint
S.clearPointRoute = clearPointRoute
S.castSolid = castSolid
S.getRaycastExclusions = getRaycastExclusions
S.steerTowards = steerTowards
S.projectToGround = projectToGround
S.isPathSegmentClear = isPathSegmentClear
S.hitBlocksWalking = hitBlocksWalking
S.headingClearDistance = headingClearDistance
S.getFeetY = getFeetY
end
