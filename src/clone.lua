-- clone.lua - Clone evasion: a world-anchored grid of candidate positions, and the dodge that paths across it.
-- Module contract: receives the shared table S. Everything this module needs from
-- earlier modules is pulled into locals below; everything later modules need is
-- assigned onto S at the bottom. Load order is fixed by main.lua / build.py.
return function(S)
local RT = S.RT
local LocalPlayer = S.LocalPlayer
local Workspace = S.Workspace
local CFG = S.CFG
local CL = S.CL
local NAV = S.NAV
local HZ = S.HZ
local heavyDebug = S.heavyDebug
local heavyDebugThrottled = S.heavyDebugThrottled
local setMovementState = S.setMovementState
local getVisualRoot = S.getVisualRoot
local getPlayerHitboxMetrics = S.getPlayerHitboxMetrics
local isPositionSafeFromDamageBricks = S.isPositionSafeFromDamageBricks
local Players = S.Players
local evaluateHazardPenaltyAtPoint = S.evaluateHazardPenaltyAtPoint
local getRaycastExclusions = S.getRaycastExclusions
local isPathSegmentClear = S.isPathSegmentClear
local releaseFacing = S.releaseFacing

-- =========================================================================
-- CLONE EVASION (2.9.0), ON A GRID (2.15.0)
--
-- A field of positions around the character. Each one is a standing offer:
-- "if you were here instead, would anything be hitting you?" They are
-- re-tested continuously and shown as discs - green safe, red not - and when
-- something is about to hit the character, the bot paths to the best green
-- one.
--
-- 2.15 changed the field from a ring that moved with the character to a grid
-- anchored to the world, and made it dense. Four things follow from that:
--
--   * A cell has an identity. Its floor height is raycast once and cached,
--     and its verdict stays valid while you walk toward it, instead of the
--     whole field sliding under you and being re-derived every frame.
--   * A cell has neighbours. So the dodge is a search across cells, not a
--     straight dash to a point: red cells cost a great deal to cross, walls
--     and pits cannot be crossed at all, and the path found never runs
--     through danger it could have gone around. The old ring tested the
--     straight line for walls only, and would choose a green node behind a
--     red strip.
--   * A cell has depth. A pass from every red cell outward tells each green
--     one how far it is from trouble, and the chooser can prefer the interior
--     of a safe region to a single green cell about to close.
--   * The discs are the size of the character's own hitbox and overlap, so a
--     safe pocket a few studs wide between two boss attacks still shows up,
--     and green means the whole body fits there untouched - the safety test
--     uses the hitbox radius plus the margin, not the centre point.
--
-- Projectiles come free, as before: safety goes through
-- isPositionSafeFromDamageBricks, which measures against the swept path of a
-- moving hazard, so a cell in the line of fire is red before the shot arrives.
-- =========================================================================

local DIAG = 1.41421356
-- 8 neighbours: dx, dz, step cost multiplier, and for diagonals the two
-- orthogonal offsets that must both be clear so a red corner is never cut.
local NEIGHBOURS = {
    { 1, 0, 1 }, { -1, 0, 1 }, { 0, 1, 1 }, { 0, -1, 1 },
    { 1, 1, DIAG, 1, 0, 0, 1 }, { 1, -1, DIAG, 1, 0, 0, -1 },
    { -1, 1, DIAG, -1, 0, 0, 1 }, { -1, -1, DIAG, -1, 0, 0, -1 },
}
local DISC_UPRIGHT = CFrame.Angles(0, 0, math.rad(90))

-- The character's real footprint, measured from the BODY.
--
-- This used to be character:GetExtentsSize(), which includes accessories and
-- the held weapon - so a big cosmetic sword or a pair of wings made the bot
-- believe it needed several extra studs to fit through a gap, and it was
-- sampled once at build. Now only the BaseParts directly under the character
-- count (limbs and torso; an Accessory holds its Handle one level down), it is
-- measured in the root's own frame so turning does not change it, and it is
-- re-measured on a timer so equipping something is picked up without dying.
local function measureFootprint()
    local _, rootRadius = getPlayerHitboxMetrics()
    local character = LocalPlayer.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if not root then return rootRadius, rootRadius end

    local rootCF = root.CFrame
    local reach = rootRadius
    for _, child in ipairs(character:GetChildren()) do
        if child:IsA("BasePart") then
            local ok, localPos = pcall(function() return rootCF:PointToObjectSpace(child.Position) end)
            if ok then
                local size = child.Size
                reach = math.max(reach,
                    math.abs(localPos.X) + size.X * 0.5,
                    math.abs(localPos.Z) + size.Z * 0.5)
            end
        end
    end
    return math.clamp(reach, rootRadius, CFG.cloneMaxFootprint), rootRadius
end

-- Cached; re-measured on its own clock rather than every frame, because it
-- walks the character's children.
local function footprintRadius()
    local now = os.clock()
    if now - CL.footprintCheckedAt >= CFG.cloneFootprintRefresh then
        CL.footprintCheckedAt = now
        CL.footprintRadius = (measureFootprint())
    end
    local _, rootRadius = getPlayerHitboxMetrics()
    return CL.footprintRadius * CFG.cloneDiscScale, rootRadius
end

local function gridSignature()
    -- The footprint is in here so that equipping a weapon, or the character
    -- finishing loading after the script started, resizes the discs. It used
    -- to be sampled once at build, so the only thing that ever corrected it
    -- was dying.
    return string.format("%.2f/%.1f/%d/%s/%.1f", CFG.cloneGridSpacing, CFG.cloneRadius,
        CFG.cloneMaxCells, tostring(CFG.showClonePrisms), (footprintRadius()))
end

-- How many cells out from the centre the window reaches, capped by the cell
-- budget: the cap is the promise, the radius is the request.
local function windowReach()
    local spacing = math.max(CFG.cloneGridSpacing, 0.5)
    local n = math.floor(CFG.cloneRadius / spacing)
    while n > 1 and (2 * n + 1) * (2 * n + 1) > CFG.cloneMaxCells do n = n - 1 end
    return math.max(n, 1)
end

local function destroyClones()
    if CL.folder then CL.folder:Destroy() end
    CL.folder = nil
    table.clear(CL.cells)
    CL.nodes = CL.cells
    table.clear(CL.path)
    CL.goalKey = nil
    CL.centerI, CL.centerJ = nil, nil
    CL.safeCount = 0
end

-- Builds the pool. A cell is a disc the size of the character's footprint,
-- and a tall prism on top when those are on; both are world-fixed and only
-- moved when the window shifts by a whole cell.
-- Both caches are keyed by world position, so they grow as you cross the map.
-- Dropping them wholesale is fine: a floor height costs one raycast and a
-- verdict is refreshed on the next pass anyway.
local function pruneCaches()
    local n = 0
    for _ in pairs(CL.floorCache) do n = n + 1 end
    if n > 6000 then
        table.clear(CL.floorCache)
        table.clear(CL.verdictCache)
    end
end

local function buildClones()
    destroyClones()
    table.clear(CL.floorCache)
    table.clear(CL.verdictCache)

    local folder = Instance.new("Folder")
    folder.Name = "CloneGrid"
    folder.Parent = getVisualRoot()
    CL.folder = folder

    local _, _, totalHeight = getPlayerHitboxMetrics()
    local radius = footprintRadius()
    local diameter = radius * 2
    CL.footprintRadius = radius
    local spacing = math.max(CFG.cloneGridSpacing, 0.5)
    local n = windowReach()
    CL.reach = n
    CL.side = 2 * n + 1

    for k = 1, CL.side * CL.side do
        -- A cylinder's length runs along X; laid on its side it is a disc.
        local pad = Instance.new("Part")
        pad.Name = "Disc_" .. k
        pad.Shape = Enum.PartType.Cylinder
        pad.Size = Vector3.new(0.2, diameter, diameter)
        pad.Anchored = true
        pad.CanCollide = false
        pad.CanQuery = false
        pad.CanTouch = false
        pad.CastShadow = false
        pad.Material = Enum.Material.Neon
        pad.Color = CFG.colorCloneSafe
        pad.Transparency = 1
        pad.Parent = folder

        local prism
        if CFG.showClonePrisms then
            prism = Instance.new("Part")
            prism.Name = "Clone_" .. k
            prism.Size = Vector3.new(diameter, totalHeight, diameter)
            prism.Anchored = true
            prism.CanCollide = false
            prism.CanQuery = false
            prism.CanTouch = false
            prism.CastShadow = false
            prism.Material = Enum.Material.ForceField
            prism.Color = CFG.colorCloneSafe
            prism.Transparency = 1
            prism.Parent = folder
        end

        CL.cells[k] = {
            i = 0, j = 0, key = "", x = 0, z = 0, y = nil,
            standable = false, safe = false, holds = false, penalty = math.huge, depth = 0, eta = 0,
            onPath = false, isGoal = false,
            pad = pad, prism = prism, halfHeight = totalHeight * 0.5,
        }
    end
    CL.nodes = CL.cells
    CL.signature = gridSignature()
    heavyDebug("Clone", string.format(
        "Grid built: %dx%d discs of %.1f studs, %.1f apart, reaching %.0f studs.",
        CL.side, CL.side, diameter, spacing, n * spacing))
end

local function setCloneActive(active)
    CL.active = active
    if active then
        buildClones()
    else
        destroyClones()
        heavyDebug("Clone", "Clone evasion off; grid removed.")
    end
end

-- Cell lookup by offset from the centre; (di, dj) in [-reach, reach].
local function cellAt(di, dj)
    local n = CL.reach
    if di < -n or di > n or dj < -n or dj > n then return nil end
    return CL.cells[(dj + n) * CL.side + (di + n) + 1]
end

local function indexOf(di, dj)
    local n = CL.reach
    return (dj + n) * CL.side + (di + n) + 1
end

-- Floor height for a world cell, cached. `false` means no floor (a pit, or a
-- wall we walked into); nil means not measured yet.
local function floorFor(cell, rootY, params, budget)
    local entry = CL.floorCache[cell.key]
    local now = os.clock()
    if entry and (now - entry.t) < CFG.cloneFloorRefresh then
        return entry.y, budget
    end
    if budget <= 0 then
        return entry and entry.y or nil, budget
    end
    local hit = Workspace:Raycast(
        Vector3.new(cell.x, rootY + 6, cell.z),
        Vector3.new(0, -(6 + CFG.cloneMaxDrop + 4), 0),
        params)
    local y = hit and (hit.Position.Y + 0.1) or false
    CL.floorCache[cell.key] = { y = y, t = now }
    return y, budget - 1
end

-- Re-anchors the window on the character's cell when it crosses a cell
-- boundary. World-fixed discs only need moving then.
local function positionCells(root)
    local spacing = math.max(CFG.cloneGridSpacing, 0.5)
    local rootPos = root.Position
    local ci = math.floor(rootPos.X / spacing + 0.5)
    local cj = math.floor(rootPos.Z / spacing + 0.5)
    if ci == CL.centerI and cj == CL.centerJ then return false end
    CL.centerI, CL.centerJ = ci, cj

    local n = CL.reach
    for dj = -n, n do
        for di = -n, n do
            local cell = cellAt(di, dj)
            cell.i, cell.j = ci + di, cj + dj
            cell.key = cell.i .. "," .. cell.j
            cell.x, cell.z = cell.i * spacing, cell.j * spacing
            local cachedFloor = CL.floorCache[cell.key]
            cell.y = cachedFloor and cachedFloor.y or nil
            -- Carry the last verdict for this world position across the shift.
            -- Blanking it made every disc vanish and come back each time you
            -- crossed a cell boundary - and at 1.5 studs apart you cross one
            -- about every 0.075s while running, against an evaluation interval
            -- of 0.08s, so it blanked on very nearly every frame you moved.
            -- The cell is at the same world position it was before; the answer
            -- from a moment ago is a far better guess than nothing.
            local verdict = CL.verdictCache[cell.key]
            if verdict then
                cell.standable = verdict.standable
                cell.safe = verdict.safe
                cell.holds = verdict.holds
                cell.penalty = verdict.penalty
            else
                cell.standable = false
                cell.safe = false
                cell.penalty = math.huge
            end
        end
    end
    return true
end

local function paintCells()
    local visible = CFG.showClones
    local safeColor, dangerColor, pathColor = CFG.colorCloneSafe, CFG.colorCloneDanger, CFG.colorClonePath
    local edgeColor = safeColor:Lerp(Color3.new(0, 0, 0), 0.4)
    local trailColor = pathColor:Lerp(Color3.new(1, 1, 1), 0.3)
    for _, cell in ipairs(CL.cells) do
        local pad, prism = cell.pad, cell.prism
        if not visible or not cell.standable then
            if pad.Transparency ~= 1 then pad.Transparency = 1 end
            if prism and prism.Transparency ~= 1 then prism.Transparency = 1 end
        else
            local color
            if cell.isGoal then color = pathColor
            elseif cell.onPath then color = trailColor
            elseif not cell.safe then color = dangerColor
            -- Safe this instant but something lands on it shortly: passable,
            -- but not somewhere to stop. Drawn dim so the difference is visible.
            elseif not cell.holds then color = edgeColor
            elseif cell.depth == 0 then color = edgeColor
            else color = safeColor end
            local y = cell.y or 0
            pad.CFrame = CFrame.new(cell.x, y + 0.1, cell.z) * DISC_UPRIGHT
            pad.Color = color
            pad.Transparency = (cell.isGoal or cell.onPath) and 0.05 or 0.55
            if prism then
                prism.CFrame = CFrame.new(cell.x, y + cell.halfHeight, cell.z)
                prism.Color = color
                prism.Transparency = 0.88
            end
        end
    end
end

-- Throttled. Floor, standability, safety, penalty, then depth.
local function evaluateCells(root)
    local now = os.clock()
    if now - CL.lastEvalTime < CFG.cloneEvalInterval then return false end
    CL.lastEvalTime = now

    local rootY = root.Position.Y
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = getRaycastExclusions(nil)
    local budget = CFG.cloneFloorBudget
    local safeCount = 0
    -- The test measures from the root radius; add the difference so it is
    -- measuring the disc, and the disc's promise holds.
    local footprint = footprintRadius()
    local exactClearance = footprint + CFG.cloneSafetyMargin

    -- Melee enemies do not announce anything: being next to one is the attack.
    -- Collected once per pass rather than per cell.
    local enemies = {}
    local character = LocalPlayer.Character
    for model in pairs(HZ.enemyModels) do
        if model ~= character and model.Parent and not Players:GetPlayerFromCharacter(model) then
            local part = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
                or model:FindFirstChildWhichIsA("BasePart")
            if part then enemies[#enemies + 1] = part.Position end
        end
    end
    local hardR = CFG.cloneEnemyRadius + footprint
    local softR = math.max(CFG.cloneEnemySoftRadius + footprint, hardR)
    -- How long it would take to walk to a cell, so each one is judged at the
    -- moment we would actually be standing in it rather than right now. The
    -- announced attacks carry real impact times, so this is the difference
    -- between crossing a marker that fires in a second and being cornered by
    -- treating it as a wall.
    local humanoid = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
    local speed = math.max((humanoid and humanoid.WalkSpeed) or 16, 4)
    local rootPos = root.Position

    for _, cell in ipairs(CL.cells) do
        local y
        y, budget = floorFor(cell, rootY, params, budget)
        cell.y = y
        local standable = type(y) == "number"
            and (y - rootY) < CFG.cloneMaxClimb and (y - rootY) > -CFG.cloneMaxDrop
        cell.standable = standable
        if standable then
            local pos = Vector3.new(cell.x, y, cell.z)
            -- The test takes the hitbox radius plus the margin: green means the
            -- whole body fits, not just the centre point.
            local travel = Vector3.new(cell.x - rootPos.X, 0, cell.z - rootPos.Z).Magnitude / speed
            cell.eta = travel

            -- Enemy personal space. Inside the hard circle is simply unsafe;
            -- between hard and soft it is allowed but expensive, so the bot
            -- will pass through to reach somewhere better and will not choose
            -- to stand there.
            local enemyPenalty, tooClose = 0, false
            for _, epos in ipairs(enemies) do
                local d = Vector3.new(pos.X - epos.X, 0, pos.Z - epos.Z).Magnitude
                if d < hardR then
                    tooClose = true
                    break
                elseif d < softR then
                    local t = (softR - d) / (softR - hardR)
                    enemyPenalty = enemyPenalty + t * t * CFG.safeZonePull * 0.5
                end
            end

            -- Exact: the disc's own radius plus whatever margin you dial in,
            -- and nothing else. Red means "my body would be in this", not
            -- "my body plus three and a half studs of hedge".
            local safeOnArrival = not tooClose
                and isPositionSafeFromDamageBricks(pos, nil, travel, exactClearance)
            -- And it must STAY safe. A cell judged only at the instant of
            -- arrival reads as green even when something already announced
            -- lands on it a moment later - which is precisely how the bot
            -- walked somewhere, stopped, and died there.
            local holds = safeOnArrival
                and isPositionSafeFromDamageBricks(pos, nil, travel, exactClearance, CFG.cloneSafeDwell)
            cell.safe = safeOnArrival and true or false
            cell.holds = holds and true or false
            cell.penalty = cell.safe and (evaluateHazardPenaltyAtPoint(pos) + enemyPenalty) or math.huge
            if cell.safe then safeCount = safeCount + 1 end
        else
            cell.safe = false
            cell.holds = false
            cell.penalty = math.huge
        end
        CL.verdictCache[cell.key] = {
            standable = cell.standable, safe = cell.safe, holds = cell.holds, penalty = cell.penalty,
        }
    end
    CL.safeCount = safeCount

    -- Depth: a breadth-first wave from every red or impassable cell outward
    -- across the green ones. The window rim counts as unknown, so a green
    -- cell on the rim is edge-depth too.
    local n, side = CL.reach, CL.side
    local maxDepth = 6
    local queue, head = {}, 1
    for k, cell in ipairs(CL.cells) do
        local di, dj = (k - 1) % side - n, math.floor((k - 1) / side) - n
        local onRim = math.abs(di) == n or math.abs(dj) == n
        if cell.standable and cell.safe and not onRim then
            cell.depth = maxDepth
        else
            cell.depth = 0
            queue[#queue + 1] = k
        end
    end
    while head <= #queue do
        local k = queue[head]; head = head + 1
        local cell = CL.cells[k]
        local di, dj = (k - 1) % side - n, math.floor((k - 1) / side) - n
        for _, nb in ipairs(NEIGHBOURS) do
            local ni, nj = di + nb[1], dj + nb[2]
            local other = cellAt(ni, nj)
            if other and other.depth > cell.depth + 1 then
                other.depth = cell.depth + 1
                queue[#queue + 1] = indexOf(ni, nj)
            end
        end
    end
    return true
end

-- The search. Dijkstra from the character's cell across the window. Green
-- cells cost their distance; red cells cost cloneDangerCost times that, so
-- they are crossed only when there is no way around; pits and walls are not
-- crossed at all. Returns costs and parent links for every reached cell.
local function search()
    local n, side = CL.reach, CL.side
    local spacing = math.max(CFG.cloneGridSpacing, 0.5)
    local total = side * side
    local dist, parent, closed = {}, {}, {}
    for k = 1, total do dist[k] = math.huge end
    local start = indexOf(0, 0)
    dist[start] = 0
    local open = { start }

    while #open > 0 do
        -- Smallest-cost pop by scan; the window is at most a few hundred cells.
        local bi, bk, bd = 1, open[1], dist[open[1]]
        for idx = 2, #open do
            local k = open[idx]
            if dist[k] < bd then bi, bk, bd = idx, k, dist[k] end
        end
        open[bi] = open[#open]; open[#open] = nil
        if not closed[bk] then
            closed[bk] = true
            local cell = CL.cells[bk]
            local di, dj = (bk - 1) % side - n, math.floor((bk - 1) / side) - n
            for _, nb in ipairs(NEIGHBOURS) do
                local ni, nj = di + nb[1], dj + nb[2]
                local other = cellAt(ni, nj)
                if other and other.standable
                    and math.abs((other.y or 0) - (cell.y or 0)) <= CFG.cloneMaxClimb then
                    local passable = true
                    if nb[4] then
                        -- Diagonal: both orthogonal cells must be walkable, and
                        -- green unless the target is red anyway - otherwise the
                        -- corner of a red cell gets clipped on the way past.
                        local a = cellAt(di + nb[4], dj + nb[5])
                        local b = cellAt(di + nb[6], dj + nb[7])
                        passable = a ~= nil and b ~= nil and a.standable and b.standable
                            and ((a.safe and b.safe) or not other.safe)
                    end
                    if passable then
                        local nk = indexOf(ni, nj)
                        local nd = bd + spacing * (other.safe and 1 or CFG.cloneDangerCost) * nb[3]
                        if nd < dist[nk] then
                            dist[nk] = nd
                            parent[nk] = bk
                            open[#open + 1] = nk
                        end
                    end
                end
            end
        end
    end
    return dist, parent, start
end

-- Cheapest to reach, then least hazardous, then deepest into safety.
-- Two passes: somewhere that stays safe, and failing that somewhere that is
-- at least safe on arrival. Without the fallback, a moment where every cell has
-- something inbound would return nothing and the bot would stand still through
-- it - the worst possible answer.
local function bestGoal(dist)
    local function pick(requireHolds)
        local bestK, bestScore = nil, math.huge
        for k, cell in ipairs(CL.cells) do
            if cell.standable and cell.safe and dist[k] < math.huge
                and (not requireHolds or cell.holds) then
                local score = dist[k]
                    + (cell.penalty < math.huge and cell.penalty * CFG.clonePenaltyWeight or 0)
                    - cell.depth * CFG.cloneDepthBonus
                if score < bestScore then bestK, bestScore = k, score end
            end
        end
        return bestK
    end
    return pick(true) or pick(false)
end

local function buildPath(parent, start, goalK)
    for _, cell in ipairs(CL.cells) do cell.onPath = false cell.isGoal = false end
    table.clear(CL.path)
    local k = goalK
    while k and k ~= start do
        table.insert(CL.path, 1, k)
        CL.cells[k].onPath = true
        k = parent[k]
    end
    if goalK then CL.cells[goalK].isGoal = true end
end

-- The dodge. Called from the hazard branch of the main loop while clone mode
-- is on. Returns true if it is driving the character.
local function runCloneEvasion(humanoid, root)
    if not CL.active or #CL.cells == 0 then return false end
    local now = os.clock()

    -- Hold the goal briefly: re-picking every frame under a moving hazard makes
    -- the character stutter between two equally good regions. The PATH to it
    -- is re-planned every call, on whatever the field currently says.
    --
    -- The goal is held as a WORLD KEY, not as an index into the window. The
    -- window is centred on the character and slides as it walks, so index k
    -- means a different place a moment later - the committed goal silently
    -- moved every time you crossed a cell boundary, which is why it would set
    -- off, take a few steps, and then decide it had arrived somewhere it had
    -- never been going.
    local dist, parent, start = search()
    local goalK = nil
    if CL.goalKey then
        for k, cell in ipairs(CL.cells) do
            if cell.key == CL.goalKey then goalK = k break end
        end
    end

    local stale = not goalK
        or (now - CL.goalAt) >= CFG.cloneCommitTime
        or not CL.cells[goalK].safe
        or dist[goalK] == math.huge
    if stale then
        goalK = bestGoal(dist)
        CL.goalKey = goalK and CL.cells[goalK].key or nil
        CL.goalAt = now
    end
    if not goalK then
        CL.goalKey = nil
        heavyDebugThrottled("clone_none", 1.0, "Clone",
            "No green cell reachable - the attack is bigger than the grid, or every way out is walled. Widen Radius.")
        setMovementState("CLONE - no safe cell")
        buildPath(parent, start, nil)
        paintCells()
        return false
    end
    buildPath(parent, start, goalK)
    paintCells()

    -- Arrived: drop the goal so the next call picks again rather than sitting
    -- on a cell that may have gone red behind us.
    local goal = CL.cells[goalK]
    local rootPos = root.Position
    if #CL.path == 0 or Vector3.new(goal.x - rootPos.X, 0, goal.z - rootPos.Z).Magnitude <= 1.0 then
        CL.goalKey = nil
        setMovementState(string.format("CLONE arrived (%d/%d safe)", CL.safeCount, #CL.cells))
        return true
    end

    -- Aim at the first path cell we are not already standing on.
    local spacing = math.max(CFG.cloneGridSpacing, 0.5)
    local target = CL.cells[CL.path[1]]
    if #CL.path > 1 and Vector3.new(target.x - rootPos.X, 0, target.z - rootPos.Z).Magnitude < spacing * 0.5 then
        target = CL.cells[CL.path[2]]
    end
    local targetPos = Vector3.new(target.x, target.y or rootPos.Y, target.z)

    -- Walls are learned by trying: a blocked first step marks that cell as no
    -- floor until its next refresh, and the next search routes around it.
    if not isPathSegmentClear(rootPos, targetPos, nil) then
        CL.floorCache[target.key] = { y = false, t = os.clock() }
        target.standable = false
        target.safe = false
        CL.goalKey = nil
        heavyDebugThrottled("clone_wall", 1.0, "Clone",
            string.format("Cell %s is walled off; marked impassable, re-routing.", target.key))
        setMovementState("CLONE - re-routing")
        return true
    end

    releaseFacing(humanoid)
    humanoid:MoveTo(targetPos)
    NAV.lastIssuedMove = targetPos
    NAV.driving = true
    setMovementState(string.format("CLONE dodge, %d cell(s) to go (%d/%d safe)",
        #CL.path, CL.safeCount, #CL.cells))
    return true
end

-- One entry point for the main loop: keep the grid under the character and in
-- step with the settings, whether or not anything is currently threatening.
local function cloneStep(root)
    if not CL.active then return end
    if gridSignature() ~= CL.signature then buildClones() end
    pruneCaches()
    local shifted = positionCells(root)
    if shifted then CL.lastEvalTime = -math.huge end
    local evaluated = evaluateCells(root)
    if shifted or evaluated then paintCells() end
end

S.setCloneActive = setCloneActive
S.destroyClones = destroyClones
S.buildClones = buildClones
S.cloneStep = cloneStep
S.runCloneEvasion = runCloneEvasion
end
