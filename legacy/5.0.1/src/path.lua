-- path.lua - Manual waypoint path: markers, editing, free-fly editor, progression, recovery.
-- Module contract: receives the shared table S. Everything this module needs from
-- earlier modules is pulled into locals below; everything later modules need is
-- assigned onto S at the bottom. Load order is fixed by main.lua / build.py.
return function(S)
local RT = S.RT
local NAV = S.NAV
local CFG = S.CFG
local heavyDebug = S.heavyDebug
local heavyDebugThrottled = S.heavyDebugThrottled
local UserInputService = S.UserInputService
local setMovementState = S.setMovementState
local LocalPlayer = S.LocalPlayer
local RunService = S.RunService
local Workspace = S.Workspace
local getVisualRoot = S.getVisualRoot
local walkTowardPoint = S.walkTowardPoint
local clearPointRoute = S.clearPointRoute
local resetPursuitPath = S.resetPursuitPath

-- =========================================================================
-- PATH EDITOR: fly the camera, click the map to drop ordered waypoints, and
-- reorder them in a small panel. Waypoints are plain world coordinates saved to
-- the config; the bot walks them (followPath) whenever it has nothing to fight,
-- and walks the nearest stretch of them to get out when it is wedged (recovery).
-- =========================================================================

-- In-world markers, one record per waypoint index: { orb, link, sphere }.
-- Built once per edit; passing a waypoint destroys just that record (2.1.0).
-- The old renderer destroyed and rebuilt every marker on the path each time a
-- single waypoint was passed - with Show Radius on that was a hundred-plus
-- Instances per crossing.

local function ensurePathFolder()
    if NAV.pathFolder and NAV.pathFolder.Parent then return NAV.pathFolder end
    local folder = Instance.new("Folder")
    folder.Name = "PathWaypoints"
    folder.Parent = getVisualRoot()
    NAV.pathFolder = folder
    table.clear(NAV.pathMarkers)
    return folder
end

local function destroyMarker(i)
    local marker = NAV.pathMarkers[i]
    if not marker then return end
    if marker.orb then marker.orb:Destroy() end
    if marker.link then marker.link:Destroy() end
    if marker.sphere then marker.sphere:Destroy() end
    NAV.pathMarkers[i] = nil
end

local function buildMarker(folder, i, withLink)
    local pos = NAV.waypath[i]
    local marker = {}

    if NAV.showRadius then
        local sphere = Instance.new("Part")
        sphere.Name = "Radius_" .. i
        sphere.Shape = Enum.PartType.Ball
        sphere.Size = Vector3.new(CFG.waypointClearRadius * 2, CFG.waypointClearRadius * 2,
            CFG.waypointClearRadius * 2)
        sphere.Position = pos
        sphere.Anchored = true
        sphere.CanCollide = false
        sphere.CanQuery = false
        sphere.CanTouch = false
        sphere.CastShadow = false
        sphere.Material = Enum.Material.ForceField
        sphere.Color = Color3.fromRGB(90, 190, 255)
        sphere.Transparency = 0.7
        sphere.Parent = folder
        marker.sphere = sphere
    end

    local orb = Instance.new("Part")
    orb.Name = "Waypoint_" .. i
    orb.Shape = Enum.PartType.Ball
    orb.Size = Vector3.new(1.6, 1.6, 1.6)
    orb.Position = pos
    orb.Anchored = true
    orb.CanCollide = false
    orb.CanQuery = false          -- invisible to our own raycasts
    orb.CanTouch = false
    orb.CastShadow = false
    orb.Material = Enum.Material.Neon
    orb.Color = CFG.colorWaypoint
    orb.Transparency = 0.25
    orb.Parent = folder
    marker.orb = orb

    local billboard = Instance.new("BillboardGui")
    billboard.Name = "Label"
    billboard.Size = UDim2.fromOffset(46, 26)
    billboard.StudsOffsetWorldSpace = Vector3.new(0, 2.4, 0)
    billboard.AlwaysOnTop = true
    billboard.Adornee = orb
    billboard.Parent = orb

    local label = Instance.new("TextLabel")
    label.Size = UDim2.fromScale(1, 1)
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.GothamBold
    label.Text = "#" .. i
    label.TextColor3 = CFG.colorWaypoint
    label.TextStrokeTransparency = 0.2
    label.TextScaled = true
    label.Parent = billboard

    -- A faint line to the previous waypoint (only if it is also still live).
    if withLink and NAV.waypath[i - 1] then
        local prev = NAV.waypath[i - 1]
        local mid = prev:Lerp(pos, 0.5)
        local link = Instance.new("Part")
        link.Name = "Link_" .. i
        link.Anchored = true
        link.CanCollide = false
        link.CanQuery = false
        link.CanTouch = false
        link.CastShadow = false
        link.Material = Enum.Material.Neon
        link.Color = CFG.colorWaypoint
        link.Transparency = 0.6
        link.Size = Vector3.new(0.15, 0.15, (pos - prev).Magnitude)
        link.CFrame = CFrame.lookAt(mid, pos)
        link.Parent = folder
        marker.link = link
    end

    NAV.pathMarkers[i] = marker
end

-- Full rebuild: every live waypoint (index >= pathIndex) gets a marker. Used
-- when the list itself changes, on load, on a loop wrap, and when the radius
-- overlay is toggled or resized - never per frame and never on progression.
local function renderPathMarkers()
    if NAV.pathFolder then NAV.pathFolder:Destroy() end
    NAV.pathFolder = nil
    table.clear(NAV.pathMarkers)
    if #NAV.waypath == 0 then return end

    local folder = ensurePathFolder()
    for i = 1, #NAV.waypath do
        if i >= NAV.pathIndex then
            buildMarker(folder, i, i > NAV.pathIndex)
        end
    end
end

-- Incremental: drop the markers of waypoints now behind pathIndex, and the link
-- leading into the first live one. Touches only what changed.
local function refreshPathMarkers()
    local first = NAV.pathIndex
    local stale = nil
    for i in pairs(NAV.pathMarkers) do
        if i < first then
            stale = stale or {}
            stale[#stale + 1] = i
        end
    end
    if stale then
        for _, i in ipairs(stale) do destroyMarker(i) end
    end
    local marker = NAV.pathMarkers[first]
    if marker and marker.link then
        marker.link:Destroy()
        marker.link = nil
    end
end

-- refreshPathPanel is late-bound: the UI module assigns S.refreshPathPanel.

local function addWaypoint(pos)
    table.insert(NAV.waypath, pos)
    renderPathMarkers()
    if S.refreshPathPanel then S.refreshPathPanel() end
    heavyDebug("Path", string.format("Added waypoint #%d at (%.0f, %.0f, %.0f).",
        #NAV.waypath, pos.X, pos.Y, pos.Z))
end

local function removeWaypoint(index)
    if not NAV.waypath[index] then return end
    table.remove(NAV.waypath, index)
    if NAV.pathIndex > #NAV.waypath then NAV.pathIndex = 1 end
    renderPathMarkers()
    if S.refreshPathPanel then S.refreshPathPanel() end
end

local function moveWaypoint(index, delta)
    local target = index + delta
    if not NAV.waypath[index] or not NAV.waypath[target] then return end
    NAV.waypath[index], NAV.waypath[target] = NAV.waypath[target], NAV.waypath[index]
    renderPathMarkers()
    if S.refreshPathPanel then S.refreshPathPanel() end
end

local function clearWaypath()
    table.clear(NAV.waypath)
    NAV.pathIndex = 1
    renderPathMarkers()
    if S.refreshPathPanel then S.refreshPathPanel() end
end

-- Called every frame: as the player passes within the clear radius of the NEXT
-- waypoint in order, that waypoint is marked passed and its marker clears. Only
-- the next one in sequence is ever consumed (chronological), and NAV.waypath -
-- the saved list - is never touched, so the config stays permanent.
local function progressPath(rootPos)
    -- Recovery drives pathIndex itself while it is walking the path.
    if NAV.recovery then return end
    local count = #NAV.waypath
    if count == 0 or NAV.pathIndex > count then return end
    if NAV.pathIndex < 1 then NAV.pathIndex = 1 end

    local passed = false
    while NAV.pathIndex <= count
        and (rootPos - NAV.waypath[NAV.pathIndex]).Magnitude <= CFG.waypointClearRadius do
        NAV.pathIndex = NAV.pathIndex + 1
        passed = true
    end

    if passed then
        clearPointRoute()
        if NAV.pathIndex > count and CFG.loopPath then
            NAV.pathIndex = 1
            renderPathMarkers()
        else
            refreshPathMarkers()
        end
    end
end

-- =========================================================================
-- RECOVERY (2.2.0): the manual path as the last resort.
--
-- Normal navigation - navmesh, the retry ladder, direct steering, the heading
-- and area blacklists - is what gets the bot to enemies. When all of it has
-- still left the character loitering in one spot, the one thing that is known
-- to be walkable is the path the user laid down by hand. Recovery walks to the
-- nearest waypoint (routed, see walkTowardPoint) and on along the path for a
-- couple of points, then hands back to pursuit with a clean slate. Re-sticking
-- soon after continues further along the path instead of returning to the
-- same nearest point, and each repeat walks a longer stretch.
-- =========================================================================

local function nearestWaypointIndex(position)
    local best, bestScore = nil, math.huge
    for i, p in ipairs(NAV.waypath) do
        local score = Vector3.new(p.X - position.X, 0, p.Z - position.Z).Magnitude
        -- A waypoint well above us (a ledge overhead) is not a way out from here.
        if p.Y - position.Y > CFG.maxClimbHeight then score = score + 40 end
        if score < bestScore then best, bestScore = i, score end
    end
    return best
end

local function exitRecovery(reason)
    local recovery = NAV.recovery
    if not recovery then return end
    NAV.recovery = nil
    NAV.lastRecoveryEnd = os.clock()
    NAV.lastRecoveryIndex = recovery.index
    NAV.stuckAnchor = nil
    clearPointRoute()
    resetPursuitPath()
    -- The wedge is behind us: let pursuit retry everything it had given up on.
    table.clear(NAV.benched)
    NAV.forceRescan = true
    heavyDebug("Recovery", string.format(
        "Recovery over (%s) after %.1fs; back to normal navigation at path #%d.",
        reason, os.clock() - recovery.startedAt, recovery.index))
end

local function enterRecovery(root, reason)
    if not CFG.recoveryEnabled or NAV.recovery then return false end
    if #NAV.waypath == 0 then
        heavyDebugThrottled("recovery_nopath", 10.0, "Recovery",
            "Stuck (" .. reason .. ") but no manual path is set, so there is nothing to recover along. Lay one down in Edit Path.")
        return false
    end

    local now = os.clock()
    local remaining = CFG.recoveryWaypoints
    local index
    if NAV.lastRecoveryIndex and NAV.waypath[NAV.lastRecoveryIndex]
        and now - NAV.lastRecoveryEnd <= CFG.recoveryRepeatWindow then
        -- Stuck again right after a recovery: the nearest waypoint is probably
        -- the one we just walked back from. Continue along the path instead,
        -- and further this time.
        index = NAV.lastRecoveryIndex
        remaining = remaining + CFG.recoveryEscalation
    else
        index = nearestWaypointIndex(root.Position)
    end
    -- Walking to a waypoint we are already standing on achieves nothing.
    if (NAV.waypath[index] - root.Position).Magnitude <= CFG.recoveryArriveRadius then
        index = index + 1
        if index > #NAV.waypath then
            index = CFG.loopPath and 1 or #NAV.waypath
        end
    end

    NAV.recovery = {
        index = index,
        remaining = remaining,
        deadline = now + CFG.recoveryMaxTime,
        startedAt = now,
        stuckAt = root.Position,
    }
    NAV.pathIndex = index
    renderPathMarkers()
    clearPointRoute()
    resetPursuitPath()
    NAV.stuckAnchor = nil
    heavyDebug("Recovery", string.format(
        "STUCK (%s) at (%.0f, %.0f, %.0f). Walking the manual path from #%d for %d waypoint(s).",
        reason, root.Position.X, root.Position.Y, root.Position.Z, index, remaining))
    setMovementState(string.format("RECOVERY: to path #%d", index))
    return true
end

-- The recovery branch of the main loop. Returns false once recovery has ended.
local function runRecovery(humanoid, root)
    local recovery = NAV.recovery
    if not recovery then return false end
    local now = os.clock()

    local target = NAV.waypath[recovery.index]
    if not target then
        exitRecovery("ran out of path")
        return false
    end
    if now > recovery.deadline then
        exitRecovery("time limit")
        return false
    end

    -- A mob in our face is not a wedge; fight it.
    local enemy = NAV.cachedEnemy
    if enemy then
        local enemyRoot = enemy:FindFirstChild("HumanoidRootPart") or enemy.PrimaryPart
        if enemyRoot and (enemyRoot.Position - root.Position).Magnitude <= CFG.attackRange then
            exitRecovery("enemy in reach")
            return false
        end
    end

    local distance, stuck = walkTowardPoint(humanoid, root, target)
    if distance <= CFG.recoveryArriveRadius or stuck then
        if stuck then
            heavyDebug("Recovery", string.format(
                "Path #%d not getting closer for %.0fs; skipping it.", recovery.index, CFG.pointGiveUpTime))
        end
        recovery.index = recovery.index + 1
        if recovery.index > #NAV.waypath then
            if CFG.loopPath then
                recovery.index = 1
            else
                exitRecovery("end of path")
                return false
            end
        end
        recovery.remaining = recovery.remaining - 1
        NAV.pathIndex = recovery.index
        refreshPathMarkers()
        clearPointRoute()
        if recovery.remaining <= 0 then
            exitRecovery("walked the segment")
            return false
        end
    end

    setMovementState(string.format("RECOVERY wp #%d (%.0f studs, %d to go)",
        recovery.index, distance, recovery.remaining))
    return true
end

-- Stuck detector, called once per frame by the main loop AFTER the branch ran,
-- so `driving` reflects this frame. Loitering inside recoveryStuckRadius for
-- recoveryStuckTime while actively trying to move means the normal navigation
-- has wedged itself. Not armed while dodging (holding still inside a
-- telegraph's clearance is the escape logic working) or while standing in
-- range attacking (that is not moving on purpose).
local function updateStuckDetector(root, driving, inHazard, now)
    if NAV.recovery or not driving or inHazard then
        NAV.stuckAnchor = nil
        return false
    end
    if not NAV.stuckAnchor
        or (root.Position - NAV.stuckAnchor).Magnitude > CFG.recoveryStuckRadius then
        NAV.stuckAnchor = root.Position
        NAV.stuckAnchorTime = now
        return false
    end
    if now - NAV.stuckAnchorTime >= CFG.recoveryStuckTime then
        NAV.stuckAnchor = nil
        return enterRecovery(root, string.format(
            "within %.0f studs for %.1fs", CFG.recoveryStuckRadius, CFG.recoveryStuckTime))
    end
    return false
end

-- Free-fly camera + click-to-place. While armed: hold RIGHT mouse to look, WASD
-- to fly (E/Q up/down), and LEFT-click a spot on the map to drop a waypoint there.
local function setPathEditEnabled(enabled)
    for _, connection in ipairs(NAV.pathEditConnections) do
        connection:Disconnect()
    end
    table.clear(NAV.pathEditConnections)
    NAV.pathEditEnabled = enabled

    local camera = Workspace.CurrentCamera
    if not enabled then
        if camera and NAV.savedCameraType then
            camera.CameraType = NAV.savedCameraType
        elseif camera then
            camera.CameraType = Enum.CameraType.Custom
        end
        table.clear(NAV.freecamKeys)
        NAV.freecamLooking = false
        pcall(function() UserInputService.MouseBehavior = Enum.MouseBehavior.Default end)
        setMovementState("path editor off")
        return
    end

    if not camera then return end
    NAV.savedCameraType = camera.CameraType
    camera.CameraType = Enum.CameraType.Scriptable
    NAV.freecamCFrame = camera.CFrame
    local _, y, _ = camera.CFrame:ToOrientation()
    NAV.freecamYaw = y
    NAV.freecamPitch = 0
    table.clear(NAV.freecamKeys)
    NAV.freecamLooking = false

    local KEY_VECTORS = {
        [Enum.KeyCode.W] = Vector3.new(0, 0, -1),
        [Enum.KeyCode.S] = Vector3.new(0, 0, 1),
        [Enum.KeyCode.A] = Vector3.new(-1, 0, 0),
        [Enum.KeyCode.D] = Vector3.new(1, 0, 0),
        [Enum.KeyCode.E] = Vector3.new(0, 1, 0),
        [Enum.KeyCode.Q] = Vector3.new(0, -1, 0),
    }

    table.insert(NAV.pathEditConnections, UserInputService.InputBegan:Connect(function(input, processed)
        if processed then return end
        if KEY_VECTORS[input.KeyCode] then
            NAV.freecamKeys[input.KeyCode] = true
        elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
            NAV.freecamLooking = true
            -- Pin the cursor so the look delta keeps coming instead of stopping
            -- dead the moment the pointer reaches a screen edge.
            pcall(function()
                UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
            end)
        elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
            -- Drop a waypoint where the cursor is pointing on the map.
            local mouse = LocalPlayer:GetMouse()
            local hit = mouse.Hit
            if hit then addWaypoint(hit.Position) end
        end
    end))

    table.insert(NAV.pathEditConnections, UserInputService.InputEnded:Connect(function(input)
        if KEY_VECTORS[input.KeyCode] then
            NAV.freecamKeys[input.KeyCode] = nil
        elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
            NAV.freecamLooking = false
            pcall(function()
                UserInputService.MouseBehavior = Enum.MouseBehavior.Default
            end)
        end
    end))

    table.insert(NAV.pathEditConnections, UserInputService.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement and NAV.freecamLooking then
            local s = math.rad(CFG.freecamLookSensitivity)
            NAV.freecamYaw = NAV.freecamYaw - input.Delta.X * s
            NAV.freecamPitch = math.clamp(NAV.freecamPitch - input.Delta.Y * s,
                math.rad(-89), math.rad(89))
        end
    end))

    table.insert(NAV.pathEditConnections, RunService.RenderStepped:Connect(function(dt)
        local cam = Workspace.CurrentCamera
        if not cam or not NAV.pathEditEnabled then return end
        local rot = CFrame.Angles(0, NAV.freecamYaw, 0) * CFrame.Angles(NAV.freecamPitch, 0, 0)
        local move = Vector3.zero
        for key, vec in pairs(KEY_VECTORS) do
            if NAV.freecamKeys[key] then move = move + vec end
        end
        local pos = NAV.freecamCFrame.Position
        if move.Magnitude > 0 then
            pos = pos + (rot:VectorToWorldSpace(move.Unit) * CFG.freecamSpeed * dt)
        end
        NAV.freecamCFrame = CFrame.new(pos) * rot
        cam.CFrame = NAV.freecamCFrame
    end))

    setMovementState("path editor: fly (WASD/EQ), right-drag look, left-click to place")
    heavyDebug("Path", "Path editor armed. WASD+EQ fly, hold right mouse to look, left-click places a waypoint.")
end

S.clearWaypath = clearWaypath
S.moveWaypoint = moveWaypoint
S.progressPath = progressPath
S.removeWaypoint = removeWaypoint
S.renderPathMarkers = renderPathMarkers
S.refreshPathMarkers = refreshPathMarkers
S.setPathEditEnabled = setPathEditEnabled
S.enterRecovery = enterRecovery
S.exitRecovery = exitRecovery
S.runRecovery = runRecovery
S.updateStuckDetector = updateStuckDetector
end
