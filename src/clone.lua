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
local getRaycastExclusions = S.getRaycastExclusions
local isPathSegmentClear = S.isPathSegmentClear
local releaseFacing = S.releaseFacing
local getThreatAt = S.getThreatAt
local refreshThreatSources = S.refreshThreatSources
local TH = S.TH

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
            standable = false, safe = false, holds = false, depth = 0, eta = 0,
            threat = math.huge, threatLater = math.huge,
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
                cell.threat = verdict.threat or math.huge
                cell.threatLater = verdict.threatLater or math.huge
            else
                cell.standable = false
                cell.safe = false
                cell.threat = math.huge
                cell.threatLater = math.huge
            end
        end
    end
    return true
end

-- The heat ramp: dark green through light green, light and dark yellow, orange,
-- to red. Seven stops rather than two, because with several hundred discs on
-- screen a two-stop blend cannot show the difference between "cool" and
-- "coolest", and that difference is exactly what you need to see when nothing
-- is truly safe.
--
-- Built from the three colours in the panel so the pickers still mean
-- something: the cool end is your safe colour darkened, the middle is your warm
-- colour lightened and plain, the hot end is your danger colour.
local RAMP = {}
local rampSignature = nil

local function rebuildRamp()
    local safe, warm, danger = CFG.colorCloneSafe, CFG.colorThreatWarm, CFG.colorCloneDanger
    local black, white = Color3.new(0, 0, 0), Color3.new(1, 1, 1)
    RAMP = {
        safe:Lerp(black, 0.55),      -- 0.00 darkest green: the coolest ground
        safe:Lerp(black, 0.25),      -- deep green
        safe,                        -- green
        safe:Lerp(warm, 0.5),        -- yellow-green
        warm:Lerp(white, 0.4),       -- light yellow
        warm,                        -- dark yellow
        warm:Lerp(danger, 0.5),      -- orange
        danger,                      -- red
        danger:Lerp(black, 0.3),     -- 1.00 deep red: standing in it
    }
    rampSignature = tostring(safe) .. tostring(warm) .. tostring(danger)
end

local function heatColor(t)
    if rampSignature ~= (tostring(CFG.colorCloneSafe) .. tostring(CFG.colorThreatWarm)
        .. tostring(CFG.colorCloneDanger)) then
        rebuildRamp()
    end
    -- Quantised into bands: adjacent cells with near-identical heat share a
    -- colour, so the boundaries between hotter and cooler ground are visible
    -- edges rather than an imperceptible drift.
    local bands = math.max(math.floor(CFG.threatColorBands), 2)
    local band = math.floor(math.clamp(t, 0, 1) * (bands - 1) + 0.5) / (bands - 1)
    local pos = band * (#RAMP - 1)
    local i = math.floor(pos)
    local frac = pos - i
    local a = RAMP[i + 1] or RAMP[#RAMP]
    local b = RAMP[i + 2] or RAMP[#RAMP]
    return a:Lerp(b, frac)
end

local function paintCells()
    local visible = CFG.showClones
    local safeColor, dangerColor, pathColor = CFG.colorCloneSafe, CFG.colorCloneDanger, CFG.colorClonePath
    local trailColor = pathColor:Lerp(Color3.new(1, 1, 1), 0.3)
    local lethal = math.max(CFG.threatLethal, 1)

    for _, cell in ipairs(CL.cells) do
        local pad, prism = cell.pad, cell.prism
        if not visible or not cell.standable then
            if pad.Transparency ~= 1 then pad.Transparency = 1 end
            if prism and prism.Transparency ~= 1 then prism.Transparency = 1 end
        else
            local color
            if cell.isGoal then
                color = pathColor
            elseif cell.onPath then
                color = trailColor
            elseif CFG.showThreatGradient then
                color = heatColor((cell.threat or 0) / lethal)
            elseif cell.threat >= lethal then
                color = dangerColor
            else
                color = safeColor
            end
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

-- Throttled. Floor, standability, and then the heat at the moment we would
-- actually be standing there.
local function evaluateCells(root)
    local now = os.clock()
    if now - CL.lastEvalTime < CFG.cloneEvalInterval then return false end
    CL.lastEvalTime = now
    refreshThreatSources()

    local rootY = root.Position.Y
    local rootPos = root.Position
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = getRaycastExclusions(nil)
    local budget = CFG.cloneFloorBudget
    local safeCount = 0

    local humanoid = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
    local speed = math.max((humanoid and humanoid.WalkSpeed) or 16, 4)
    local hottest = 1

    for _, cell in ipairs(CL.cells) do
        local y
        y, budget = floorFor(cell, rootY, params, budget)
        cell.y = y
        local standable = type(y) == "number"
            and (y - rootY) < CFG.cloneMaxClimb and (y - rootY) > -CFG.cloneMaxDrop
        cell.standable = standable
        if standable then
            local pos = Vector3.new(cell.x, y, cell.z)
            -- Judged at arrival, not now: that is what makes time the third
            -- dimension rather than decoration.
            local travel = Vector3.new(cell.x - rootPos.X, 0, cell.z - rootPos.Z).Magnitude / speed
            cell.eta = travel
            cell.threat = getThreatAt(pos, travel)
            -- And it has to still be tolerable a moment later, so the bot does
            -- not walk somewhere, stop, and be hit by what it already knew was
            -- coming.
            local later = getThreatAt(pos, travel + CFG.cloneSafeDwell)
            cell.threatLater = later
            cell.holds = math.max(cell.threat, later) < CFG.threatLethal
            cell.safe = cell.threat < CFG.threatLethal
            if cell.safe then safeCount = safeCount + 1 end
            hottest = math.max(hottest, cell.threat)
        else
            cell.threat = math.huge
            cell.threatLater = math.huge
            cell.safe = false
            cell.holds = false
        end
        CL.verdictCache[cell.key] = {
            standable = cell.standable, safe = cell.safe, holds = cell.holds,
            threat = cell.threat, threatLater = cell.threatLater,
        }
    end
    CL.safeCount = safeCount
    CL.hottest = hottest
    return true
end

-- =========================================================================
-- A* ACROSS THE HEAT FIELD
--
--     F = G + H + (threat * threatWeight)
--
-- G is distance travelled, H is the octile distance left to the goal, and the
-- threat term is what makes it prefer a longer cool route to a short hot one.
-- CFG.threatWeight is literally "how many studs of detour is one point of heat
-- worth", which is the survival-versus-speed dial in one number.
--
-- Cells at or above CFG.threatLethal are impassable. If that leaves no route
-- at all, the search is re-run with them merely expensive - being cornered is
-- not a reason to stand still and take it.
-- =========================================================================

-- Scratch buffers, reused. Allocating four tables of a few hundred entries
-- several times a second is exactly the kind of churn that shows up as stutter.
local gScore, fScore, cameFrom, closed, openHeap = {}, {}, {}, {}, {}

local function heuristic(ax, az, bx, bz, spacing)
    -- Octile: diagonals cost sqrt(2), so the admissible estimate is the
    -- straight runs plus the diagonal shortcut, never an overestimate.
    local dx, dz = math.abs(ax - bx), math.abs(az - bz)
    local lo, hi = math.min(dx, dz), math.max(dx, dz)
    return (hi - lo + lo * DIAG) * spacing
end

local function astar(goalK, allowLethal)
    local n, side = CL.reach, CL.side
    local spacing = math.max(CFG.cloneGridSpacing, 0.5)
    local total = side * side
    local startK = indexOf(0, 0)
    if not goalK then return nil end

    for k = 1, total do
        gScore[k] = math.huge
        fScore[k] = math.huge
        cameFrom[k] = nil
        closed[k] = false
    end
    local goalCell = CL.cells[goalK]

    gScore[startK] = 0
    fScore[startK] = heuristic(CL.cells[startK].x, CL.cells[startK].z,
        goalCell.x, goalCell.z, 1)
    local openCount = 1
    openHeap[1] = startK

    while openCount > 0 do
        -- Linear scan for the lowest F. A binary heap is asymptotically better
        -- but the window is a few hundred cells, and the scan avoids the
        -- per-push allocations a heap of tables would cost.
        local bestIdx, bestK, bestF = 1, openHeap[1], fScore[openHeap[1]]
        for i = 2, openCount do
            local k = openHeap[i]
            if fScore[k] < bestF then bestIdx, bestK, bestF = i, k, fScore[k] end
        end
        openHeap[bestIdx] = openHeap[openCount]
        openHeap[openCount] = nil
        openCount = openCount - 1

        if bestK == goalK then return cameFrom, startK end
        closed[bestK] = true

        local cell = CL.cells[bestK]
        local di, dj = (bestK - 1) % side - n, math.floor((bestK - 1) / side) - n
        for _, nb in ipairs(NEIGHBOURS) do
            local ni, nj = di + nb[1], dj + nb[2]
            local other = cellAt(ni, nj)
            if other and other.standable and not closed[indexOf(ni, nj)]
                and math.abs((other.y or 0) - (cell.y or 0)) <= CFG.cloneMaxClimb then
                local passable = allowLethal or other.threat < CFG.threatLethal
                if passable and nb[4] then
                    -- Diagonal: both orthogonal neighbours must be walkable, or
                    -- the corner of a hot cell gets clipped on the way past.
                    local a = cellAt(di + nb[4], dj + nb[5])
                    local b = cellAt(di + nb[6], dj + nb[7])
                    passable = a ~= nil and b ~= nil and a.standable and b.standable
                end
                if passable then
                    local nk = indexOf(ni, nj)
                    local step = spacing * nb[3]
                    -- Heat is paid per unit of exposure, so crossing a hot cell
                    -- quickly costs less than loitering in a warm one.
                    local heat = math.min(other.threat, TH.LETHAL * 2) * CFG.threatWeight * nb[3]
                    local tentative = gScore[bestK] + step + heat
                    if tentative < gScore[nk] then
                        cameFrom[nk] = bestK
                        gScore[nk] = tentative
                        fScore[nk] = tentative
                            + heuristic(other.x, other.z, goalCell.x, goalCell.z, 1)
                        openCount = openCount + 1
                        openHeap[openCount] = nk
                    end
                end
            end
        end
    end
    return nil, startK
end

-- Where to go: the coolest ground we can plausibly reach, preferring somewhere
-- that stays cool and is not right on the edge of the window. Survival first,
-- so distance is only a tie-break against heat, never the other way round.
local function bestGoal(root)
    local rootPos = root.Position
    local bestK, bestScore = nil, math.huge
    for k, cell in ipairs(CL.cells) do
        if cell.standable then
            local travel = Vector3.new(cell.x - rootPos.X, 0, cell.z - rootPos.Z).Magnitude
            -- Blend rather than max, biased to the future: standing on a cell
            -- that is cool now and hot in a moment is how you die on the spot.
            -- A cell whose heat is FALLING scores better than one merely cool.
            local bias = CFG.threatFutureBias
            local expected = cell.threat * (1 - bias) + cell.threatLater * bias
            local score = expected * CFG.threatWeight
                + travel * 0.35
                - cell.depth * CFG.cloneDepthBonus
            if score < bestScore then bestK, bestScore = k, score end
        end
    end
    return bestK
end

local function buildPath(parent, start, goalK)
    for _, cell in ipairs(CL.cells) do cell.onPath = false cell.isGoal = false end
    table.clear(CL.path)
    if not parent then return end
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
    local rootPos = root.Position

    -- Projectile steering first. The grid replans a few times a second, which
    -- is right for ground attacks that announce themselves and far too slow for
    -- something already in the air.
    local dodge = S.getProjectileDodge(rootPos, root.AssemblyLinearVelocity)
    if dodge then
        local target = rootPos + dodge * CFG.dodgeStrength
        releaseFacing(humanoid)
        humanoid:MoveTo(Vector3.new(target.X, rootPos.Y, target.Z))
        NAV.lastIssuedMove = target
        NAV.driving = true
        setMovementState("CLONE sidestep (projectile)")
        return true
    end

    -- The goal is held as a WORLD KEY, not an index into the window: the window
    -- is centred on the character and slides as it walks, so an index means a
    -- different place a moment later.
    local goalK = nil
    if CL.goalKey then
        for k, cell in ipairs(CL.cells) do
            if cell.key == CL.goalKey then goalK = k break end
        end
    end

    -- With attacks overlapping and nowhere actually safe, committing to a
    -- destination for a third of a second is the wrong shape of decision: the
    -- field is changing faster than that. Saturated, it re-picks every pass and
    -- simply flows downhill, which is what keeps you alive when there is no
    -- exit - you are never in the hottest place for long.
    local saturated = CL.safeCount == 0
    local commit = saturated and 0 or CFG.cloneCommitTime
    local stale = not goalK
        or (now - CL.goalAt) >= commit
        or CL.cells[goalK].threat >= CFG.threatLethal
    if stale then
        goalK = bestGoal(root)
        CL.goalKey = goalK and CL.cells[goalK].key or nil
        CL.goalAt = now
    end

    if not goalK then
        setMovementState("CLONE - nowhere to stand")
        buildPath(nil, nil, nil)
        paintCells()
        return false
    end

    -- Lethal cells are impassable; if that leaves no route, run it again with
    -- them merely expensive. Being cornered is not a reason to stand still.
    local parent, startK = astar(goalK, false)
    if not parent and CFG.threatDesperate then
        parent, startK = astar(goalK, true)
        heavyDebugThrottled("clone_desperate", 1.0, "Clone",
            "Every route out crosses something lethal; taking the coolest one rather than standing still.")
    end
    if not parent then
        setMovementState("CLONE - no route")
        buildPath(nil, nil, nil)
        paintCells()
        return false
    end

    buildPath(parent, startK, goalK)
    paintCells()

    local goal = CL.cells[goalK]
    if #CL.path == 0 or Vector3.new(goal.x - rootPos.X, 0, goal.z - rootPos.Z).Magnitude <= 1.0 then
        CL.goalKey = nil
        setMovementState(string.format("CLONE holding (heat %.0f)", goal.threat))
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
    setMovementState(string.format("CLONE moving, %d cell(s), heat %.0f -> %.0f",
        #CL.path, CL.cells[indexOf(0, 0)].threat or 0, goal.threat))
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
