-- clone.lua - Clone evasion: a visible ring of candidate positions, and the dodge that uses it.
-- Module contract: receives the shared table S. Everything this module needs from
-- earlier modules is pulled into locals below; everything later modules need is
-- assigned onto S at the bottom. Load order is fixed by main.lua / build.py.
return function(S)
local RT = S.RT
local CFG = S.CFG
local CL = S.CL
local NAV = S.NAV
local HZ = S.HZ
local LocalPlayer = S.LocalPlayer
local heavyDebug = S.heavyDebug
local heavyDebugThrottled = S.heavyDebugThrottled
local setMovementState = S.setMovementState
local getVisualRoot = S.getVisualRoot
local getPlayerHitboxMetrics = S.getPlayerHitboxMetrics
local isPositionSafeFromDamageBricks = S.isPositionSafeFromDamageBricks
local evaluateHazardPenaltyAtPoint = S.evaluateHazardPenaltyAtPoint
local projectToGround = S.projectToGround
local isPathSegmentClear = S.isPathSegmentClear
local releaseFacing = S.releaseFacing

-- =========================================================================
-- CLONE EVASION (2.9.0)
--
-- A ring of player-sized volumes around the character. Each one is a standing
-- offer: "if you were here instead, would anything be hitting you?" They are
-- re-tested continuously and their pads show the answer - green safe, red not.
-- When something is about to hit the character, the bot steps into the best
-- green one.
--
-- This is the same question the Legacy escape search asks, with two
-- differences. The candidates are FIXED relative to the character rather than
-- generated per escape, so the answer is stable frame to frame instead of
-- being re-derived under pressure. And they are on screen, so a dodge that
-- goes wrong can be watched rather than reasoned about from a log.
--
-- Projectiles are handled for free: safety goes through
-- isPositionSafeFromDamageBricks, which measures against hazardClosestPoint,
-- which already sweeps a moving hazard along the strip it will cross in the
-- next CFG.projectileLookahead seconds. A clone standing in the path of an
-- incoming projectile is therefore red before the projectile arrives, which is
-- the entire point of testing positions rather than testing contact.
-- =========================================================================

-- Where the ring sits, as flat offsets from the character. Rebuilt only when
-- the count, ring or radius settings change.
local function buildOffsets()
    local offsets = {}
    local rings = math.clamp(math.floor(CFG.cloneRings), 1, CFG.cloneMaxRings)
    local total = math.clamp(math.floor(CFG.cloneCount), 4, CFG.cloneMaxVolumes)
    local perRing = math.max(3, math.floor(total / rings))

    for ring = 1, rings do
        -- Inner rings sit proportionally closer; a single ring sits at the
        -- full radius.
        local scale = rings == 1 and 1 or (0.55 + 0.45 * ((ring - 1) / (rings - 1)))
        local radius = CFG.cloneRadius * scale
        -- Offset alternate rings by half a step so they interleave rather than
        -- lining up into spokes with gaps between them.
        local phase = (ring % 2 == 0) and (math.pi / perRing) or 0
        for i = 1, perRing do
            local angle = phase + (i - 1) * (2 * math.pi / perRing)
            table.insert(offsets, Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius))
        end
    end
    return offsets
end

local function destroyClones()
    if CL.folder then CL.folder:Destroy() end
    CL.folder = nil
    table.clear(CL.nodes)
    CL.chosen = nil
    CL.safeCount = 0
end

-- Builds the pool. Every clone is two parts: a tall prism the size of the
-- character, and a flat pad under it that carries the safe/danger colour.
local function buildClones()
    destroyClones()

    local folder = Instance.new("Folder")
    folder.Name = "CloneRing"
    folder.Parent = getVisualRoot()
    CL.folder = folder

    local _, radius, totalHeight = getPlayerHitboxMetrics()
    local width = math.max(radius * 2, 2)
    local offsets = buildOffsets()

    for i, offset in ipairs(offsets) do
        local prism = Instance.new("Part")
        prism.Name = "Clone_" .. i
        prism.Size = Vector3.new(width, totalHeight, width)
        prism.Anchored = true
        prism.CanCollide = false
        prism.CanQuery = false      -- invisible to our own raycasts
        prism.CanTouch = false
        prism.CastShadow = false
        prism.Material = Enum.Material.ForceField
        prism.Color = CFG.colorCloneSafe
        prism.Transparency = 0.82
        prism.Parent = folder

        local pad = Instance.new("Part")
        pad.Name = "Pad_" .. i
        pad.Size = Vector3.new(width, 0.25, width)
        pad.Anchored = true
        pad.CanCollide = false
        pad.CanQuery = false
        pad.CanTouch = false
        pad.CastShadow = false
        pad.Material = Enum.Material.Neon
        pad.Color = CFG.colorCloneSafe
        pad.Transparency = 0.25
        pad.Parent = folder

        table.insert(CL.nodes, {
            prism = prism, pad = pad, offset = offset,
            position = Vector3.zero, safe = false, penalty = math.huge, reachable = true,
        })
    end

    CL.signature = string.format("%d/%d/%.1f", CFG.cloneCount, CFG.cloneRings, CFG.cloneRadius)
    heavyDebug("Clone", string.format("Ring built: %d volumes across %d ring(s) at %.0f studs.",
        #CL.nodes, CFG.cloneRings, CFG.cloneRadius))
end

local function setCloneActive(active)
    CL.active = active
    if active then
        buildClones()
    else
        destroyClones()
        heavyDebug("Clone", "Clone evasion off; ring removed.")
    end
end

-- Per frame. Cheap: it only writes CFrames, and only when the mode is on.
-- Safety is a separate, throttled pass because it costs raycasts.
local function positionClones(root)
    local visible = CFG.showClones
    local _, _, totalHeight = getPlayerHitboxMetrics()
    local rootPos = root.Position
    -- Prisms take the character's yaw so they read as copies of it; the ring
    -- offsets stay in world space, so a safe spot does not move when you turn.
    local _, yaw = root.CFrame:ToOrientation()
    local rotation = CFrame.Angles(0, yaw, 0)
    local half = totalHeight * 0.5

    for _, node in ipairs(CL.nodes) do
        local target = rootPos + node.offset
        node.position = target
        local prism, pad = node.prism, node.pad
        if prism.Parent then
            prism.CFrame = CFrame.new(target) * rotation
            pad.CFrame = CFrame.new(target - Vector3.new(0, half, 0)) * rotation
            if prism.Transparency ~= (visible and 0.82 or 1) then
                prism.Transparency = visible and 0.82 or 1
                pad.Transparency = visible and 0.25 or 1
            end
        end
    end
end

-- Throttled. Marks each clone safe or not and recolours its pad.
local function evaluateClones(root)
    local now = os.clock()
    if now - CL.lastEvalTime < CFG.cloneEvalInterval then return end
    CL.lastEvalTime = now

    local rootPos = root.Position
    local safeColor, dangerColor = CFG.colorCloneSafe, CFG.colorCloneDanger
    local safeCount = 0

    for _, node in ipairs(CL.nodes) do
        -- Drop the candidate onto the floor: a clone hanging in the air over a
        -- pit is not somewhere the character can stand.
        local grounded = projectToGround(node.position, nil)
        local rise = grounded.Y - rootPos.Y
        local standable = rise < CFG.cloneMaxClimb and rise > -CFG.cloneMaxDrop
        node.position = Vector3.new(node.position.X, grounded.Y, node.position.Z)

        -- Safety, including anything moving: isPositionSafeFromDamageBricks
        -- measures against the swept path of a projectile, not its current
        -- position, so a clone in the line of fire is already unsafe.
        local clear = standable
            and isPositionSafeFromDamageBricks(node.position, CFG.cloneSafetyMargin)
        node.safe = clear and true or false
        node.penalty = clear and evaluateHazardPenaltyAtPoint(node.position) or math.huge
        node.reachable = standable

        local color = node.safe and safeColor or dangerColor
        if node.pad.Parent and node.pad.Color ~= color then
            node.pad.Color = color
            node.prism.Color = color
        end
        if node.safe then safeCount = safeCount + 1 end
    end

    CL.safeCount = safeCount
end

-- Picks the clone to run to. Lowest hazard penalty wins; distance breaks ties,
-- because a shorter dash is a dash you finish. The reachability raycast is
-- only paid for the handful of best candidates, not all of them.
local function chooseClone(root)
    local rootPos = root.Position
    local ranked = {}
    for _, node in ipairs(CL.nodes) do
        if node.safe then table.insert(ranked, node) end
    end
    if #ranked == 0 then return nil end

    table.sort(ranked, function(a, b)
        if math.abs(a.penalty - b.penalty) > 1.0 then return a.penalty < b.penalty end
        return (a.position - rootPos).Magnitude < (b.position - rootPos).Magnitude
    end)

    for i = 1, math.min(#ranked, 5) do
        if isPathSegmentClear(rootPos, ranked[i].position, nil) then
            return ranked[i]
        end
    end
    -- Nothing verified walkable: take the best-ranked anyway rather than stand
    -- in the damage, exactly as the Legacy escape does when validation fails.
    return ranked[1]
end

-- The dodge. Called from the hazard branch of the main loop while clone mode
-- is on. Returns true if it is driving the character.
local function runCloneEvasion(humanoid, root)
    if not CL.active or #CL.nodes == 0 then return false end
    local now = os.clock()

    -- Hold a chosen clone briefly: re-picking every frame under a moving
    -- hazard makes the character stutter between two equally good options.
    local chosen = CL.chosen
    local stale = not chosen
        or (now - CL.chosenAt) >= CFG.cloneCommitTime
        or not chosen.safe
    if stale then
        chosen = chooseClone(root)
        CL.chosen = chosen
        CL.chosenAt = now
    end

    if not chosen then
        heavyDebugThrottled("clone_none", 1.0, "Clone",
            "Every clone is red - nowhere in the ring is safe. Widen it (Clone radius) or the attack is bigger than the ring.")
        setMovementState("CLONE - no safe node")
        return false
    end

    releaseFacing(humanoid)
    humanoid:MoveTo(chosen.position)
    NAV.lastIssuedMove = chosen.position
    NAV.driving = true

    -- Arrived: let the next frame pick again rather than sitting on a node
    -- that may have gone red behind us.
    if (root.Position - chosen.position).Magnitude <= 2.5 then
        CL.chosen = nil
    end

    setMovementState(string.format("CLONE dodge (%d/%d safe)", CL.safeCount, #CL.nodes))
    return true
end

-- One entry point for the main loop: keep the ring in step with the character
-- and with the settings, whether or not anything is currently threatening.
local function cloneStep(root)
    if not CL.active then return end
    -- A settings change (count, rings, radius) rebuilds the pool rather than
    -- trying to reshape it in place.
    local signature = string.format("%d/%d/%.1f", CFG.cloneCount, CFG.cloneRings, CFG.cloneRadius)
    if signature ~= CL.signature then buildClones() end
    positionClones(root)
    evaluateClones(root)
end

S.setCloneActive = setCloneActive
S.destroyClones = destroyClones
S.buildClones = buildClones
S.cloneStep = cloneStep
S.runCloneEvasion = runCloneEvasion
end
