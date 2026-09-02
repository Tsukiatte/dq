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

-- Hoisted for the inner loops: each `math.floor` is two hash lookups, and
-- these run hundreds of thousands of times a second at a large radius.
local floor, ceil, sqrt, max, min, abs, clamp = math.floor, math.ceil, math.sqrt,
    math.max, math.min, math.abs, math.clamp
local huge = math.huge

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
    CL.goalI, CL.goalJ = nil, nil
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

    table.clear(CL.activeCells)
    local limit = n * n

    for k = 1, CL.side * CL.side do
        local zeroed = k - 1
        local di, dj = zeroed % CL.side - n, floor(zeroed / CL.side) - n
        local inRange = (di * di + dj * dj) <= limit
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

        if inRange then CL.activeCells[#CL.activeCells + 1] = k end
        CL.cells[k] = {
            inRange = inRange,
            i = 0, j = 0, key = "", x = 0, z = 0, y = nil,
            standable = false, safe = false, holds = false, depth = 0, eta = 0,
            threat = huge, threatLater = huge, wallHeat = 0, blocked = false,
            baseThreat = huge, baseThreatLater = huge, measured = false,
            onPath = false, isGoal = false,
            pad = pad, prism = prism, halfHeight = totalHeight * 0.5,
        }
    end
    CL.nodes = CL.cells
    CL.signature = gridSignature()
    heavyDebug("Clone", string.format(
        "Grid built: %d discs of %.1f studs in a circle %.0f studs across, %.1f apart.",
        #CL.activeCells, diameter, n * spacing * 2, spacing))
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
-- Floor height AND whether anything is standing in the way, cached together.
--
-- The grid used to ask only "is there a floor within reach", which says nothing
-- about whether you can actually get there. A wall has a floor. A ledge you
-- would have to jump onto has a floor. Both were being treated as open ground,
-- and the bot only discovered otherwise by walking into them.
--
-- `blocked` is a second, upward cast through the space the character would
-- occupy. RespectCanCollide keeps it from tripping over decorations and
-- non-solid effects, which are everywhere in this game; where the engine is too
-- old for that property, the hit is checked by hand.
local function probeCell(cell, rootY, params, budget)
    local entry = CL.floorCache[cell.key]
    local now = os.clock()
    if entry and (now - entry.t) < CFG.cloneFloorRefresh then
        return entry.y, entry.blocked, budget
    end
    if budget <= 0 then
        if entry then return entry.y, entry.blocked, budget end
        return nil, false, budget
    end

    local hit = Workspace:Raycast(
        Vector3.new(cell.x, rootY + 6, cell.z),
        Vector3.new(0, -(6 + CFG.cloneMaxDrop + 4), 0),
        params)
    local y = hit and (hit.Position.Y + 0.1) or false

    local blocked = false
    if y then
        local _, _, standHeight = getPlayerHitboxMetrics()
        local up = Workspace:Raycast(
            Vector3.new(cell.x, y + 0.6, cell.z),
            Vector3.new(0, max(standHeight - 0.8, 1), 0),
            params)
        if up then
            local part = up.Instance
            blocked = part == nil or part.CanCollide ~= false
        end
    end

    CL.floorCache[cell.key] = { y = y, blocked = blocked, t = now }
    return y, blocked, budget - 1
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
            cell.drawnY, cell.drawnColor = nil, nil
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
            cell.measured = cell.inRange and verdict ~= nil
            if verdict then
                cell.standable = verdict.standable
                cell.safe = verdict.safe
                cell.holds = verdict.holds
                cell.threat = verdict.threat or huge
                cell.threatLater = verdict.threatLater or huge
                cell.wallHeat = verdict.wallHeat or 0
                cell.blocked = verdict.blocked or false
                cell.baseThreat = verdict.baseThreat or huge
                cell.baseThreatLater = verdict.baseThreatLater or huge
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
        if not visible or not cell.inRange or not cell.standable then
            if pad.Transparency ~= 1 then
                pad.Transparency = 1
                cell.drawnColor = nil
            end
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
            -- Every property write here crosses into the engine, and there are
            -- three per disc. Writing 2,700 of them unconditionally twelve
            -- times a second was most of the drawing cost; almost none of them
            -- were changing anything.
            local y = cell.y or 0
            if cell.drawnY ~= y then
                cell.drawnY = y
                pad.CFrame = CFrame.new(cell.x, y + 0.1, cell.z) * DISC_UPRIGHT
                if prism then
                    prism.CFrame = CFrame.new(cell.x, y + cell.halfHeight, cell.z)
                end
            end
            if cell.drawnColor ~= color then
                cell.drawnColor = color
                pad.Color = color
                if prism then prism.Color = color end
            end
            local alpha = (cell.isGoal or cell.onPath) and 0.05 or 0.55
            if pad.Transparency ~= alpha then
                pad.Transparency = alpha
                if prism then prism.Transparency = 0.88 end
            end
        end
    end
end

-- Throttled AND sliced. Floor, standability, then the heat at the moment we
-- would actually be standing there.
--
-- The whole grid used to be judged in one go, which meant a 900-cell radius
-- did 900 floor checks and 1,800 threat queries inside a single frame and
-- visibly hitched. Verdicts persist in the cache between passes, so the grid
-- is refreshed in slices instead: each pass judges CFG.cloneEvalBudget cells
-- and picks up where it left off. A cell's answer can be up to a couple of
-- passes old, which is a far better trade than dropping frames - and the cell
-- the character is actually standing in is re-queried every frame anyway, by
-- the main loop.
local function evaluateCells(root)
    local now = os.clock()
    if now - CL.lastEvalTime < CFG.cloneEvalInterval then return false end
    CL.lastEvalTime = now
    refreshThreatSources()
    S.prepareThreatPass()

    local rootY = root.Position.Y
    local rootPos = root.Position
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = getRaycastExclusions(nil)
    -- Newer engines can skip non-solid parts inside the cast itself, which
    -- matters here: this game fills the floor with decorative, walk-through
    -- geometry that would otherwise read as wall after wall.
    pcall(function() params.RespectCanCollide = true end)
    local budget = CFG.cloneFloorBudget

    local humanoid = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
    local speed = max((humanoid and humanoid.WalkSpeed) or 16, 4)

    -- Heights are compared against the floor the character is STANDING on, not
    -- the root part's centre, which sits about three studs above it. Measuring
    -- from the root meant "step height 2.5" actually described a rise of five
    -- and a half, so the slider said one thing and the grid did another.
    local baseY = rootY
    do
        local hit = Workspace:Raycast(rootPos, Vector3.new(0, -12, 0), params)
        if hit then baseY = hit.Position.Y end
    end

    local dwell = CFG.cloneSafeDwell
    local lethal = CFG.threatLethal
    local getThreatPair = S.getThreatPair

    local cells = CL.cells
    local active = CL.activeCells
    local count = #active
    local slice = min(max(floor(CFG.cloneEvalBudget), 32), count)
    local cursor = CL.evalCursor
    local rx, rz = rootPos.X, rootPos.Z

    for _ = 1, slice do
        if cursor > count then cursor = 1 end
        local cell = cells[active[cursor]]
        cursor = cursor + 1

        local y, blocked
        y, blocked, budget = probeCell(cell, rootY, params, budget)
        cell.y = y
        local rise = type(y) == "number" and (y - baseY) or nil
        local standable = rise ~= nil
            and rise < CFG.cloneMaxClimb and rise > -CFG.cloneMaxDrop
            and not blocked
        cell.standable = standable
        cell.measured = true

        -- Ground you cannot simply walk onto is a threat, not a wall. A ledge
        -- within jump range is reachable, just expensive: a jump mid-fight is a
        -- moment spent not dodging, and the search should only spend it when
        -- the alternative is worse.
        local wallHeat = 0
        if standable and rise > CFG.cloneStepHeight then
            local span = max(CFG.cloneMaxClimb - CFG.cloneStepHeight, 0.01)
            wallHeat = CFG.threatWallWeight * min((rise - CFG.cloneStepHeight) / span, 1)
        end
        cell.wallHeat = wallHeat
        cell.blocked = blocked and true or false

        if standable then
            local dx, dz = cell.x - rx, cell.z - rz
            local travel = sqrt(dx * dx + dz * dz) / speed
            cell.eta = travel
            -- Both time samples in one walk over the threat sources.
            local nowHeat, laterHeat = getThreatPair(
                Vector3.new(cell.x, y, cell.z), travel, travel + dwell)
            -- Kept without the wall-edge term so the spread pass below can be
            -- recomputed from scratch each time. It runs over every cell while
            -- only a slice is re-evaluated, so anything it ADDS would pile up
            -- pass after pass on the cells it did not just measure.
            cell.baseThreat = nowHeat + wallHeat
            cell.baseThreatLater = laterHeat + wallHeat
            cell.threat = cell.baseThreat
            cell.threatLater = cell.baseThreatLater
            cell.holds = max(nowHeat, laterHeat) < lethal
            cell.safe = nowHeat < lethal
        else
            cell.baseThreat = huge
            cell.baseThreatLater = huge
            cell.threat = huge
            cell.threatLater = huge
            cell.safe = false
            cell.holds = false
        end
        CL.verdictCache[cell.key] = {
            standable = cell.standable, safe = cell.safe, holds = cell.holds,
            threat = cell.threat, threatLater = cell.threatLater,
            baseThreat = cell.baseThreat, baseThreatLater = cell.baseThreatLater,
            wallHeat = cell.wallHeat, blocked = cell.blocked,
        }
    end
    CL.evalCursor = cursor

    -- ENCLOSURE PASS
    --
    -- A cell inherits a share of the heat around it, sampled both immediately
    -- and at a distance. Two things fall out of one rule:
    --
    --   * A green pocket ringed by red gains heat, because it is a trap - you
    --     can stand in it now and have nowhere to go the moment it closes.
    --   * A corner gains heat, because walls count as maximum heat here. That
    --     is the same "do not scrape along walls" the previous edge pass did,
    --     as a special case rather than a separate rule.
    --
    -- The result is that open ground beats an enclosed pocket of equal local
    -- safety, so the bot strafes into the open instead of backing into a
    -- corner and waiting to be cornered.
    --
    -- ASSIGNED from baseThreat, never accumulated, and unmeasured neighbours
    -- are skipped rather than counted as walls. This pass runs over the whole
    -- grid while only a slice is re-measured, and both of those rules have
    -- already been learned the hard way here.
    if CFG.threatWallSpread then
        local n, side = CL.reach, CL.side
        local spacing = max(CFG.cloneGridSpacing, 0.5)
        local ring = max(2, floor(CFG.threatEnclosureRange / spacing))
        local weight = CFG.threatEnclosureWeight
        local lethal = CFG.threatLethal
        local blockedHeat = TH.LETHAL

        for idx = 1, count do
            local k = active[idx]
            local cell = cells[k]
            if cell.standable and cell.measured then
                local zeroed = k - 1
                local di, dj = zeroed % side - n, floor(zeroed / side) - n
                local sum, samples = 0, 0

                for _, nb in ipairs(NEIGHBOURS) do
                    -- Two distances per direction: the cell beside us catches
                    -- walls we are touching, the one further out catches a way
                    -- through that is not immediately obvious.
                    for _, reach in ipairs({ 1, ring }) do
                        local ni, nj = di + nb[1] * reach, dj + nb[2] * reach
                        if ni >= -n and ni <= n and nj >= -n and nj <= n then
                            local other = cells[(nj + n) * side + (ni + n) + 1]
                            if other.inRange and other.measured then
                                if not other.standable then
                                    sum = sum + blockedHeat
                                else
                                    sum = sum + min(other.baseThreat or 0, blockedHeat)
                                end
                                samples = samples + 1
                            end
                        end
                    end
                end

                local enclosure = samples > 0 and (sum / samples) * weight or 0
                cell.threat = (cell.baseThreat or huge) + enclosure
                cell.threatLater = (cell.baseThreatLater or huge) + enclosure
                cell.safe = cell.threat < lethal
                cell.holds = max(cell.threat, cell.threatLater) < lethal
            end
        end
    end

    -- Counted over the whole grid, not just the slice, so the saturated test
    -- stays honest.
    local safeCount = 0
    for i = 1, count do
        local c = cells[active[i]]
        if c.standable and c.safe then safeCount = safeCount + 1 end
    end
    CL.safeCount = safeCount
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

-- Scratch buffers, reused across calls and never cleared.
--
-- Clearing four arrays of side^2 entries per call was 3,600 table writes at a
-- 900-cell grid, and A* runs EVERY FRAME while dodging - a quarter of a
-- million writes a second doing nothing but zeroing. A generation stamp gets
-- the same guarantee for free: an entry whose stamp is not the current
-- generation is simply treated as unset.
local gScore, fScore, cameFrom, stamp = {}, {}, {}, {}
-- Binary min-heap over two parallel NUMERIC arrays. A heap of {k, f} tables
-- would allocate per push, which is exactly the churn this is avoiding; two
-- number arrays allocate nothing after they have grown once.
local heapK, heapF = {}, {}

local function heapPush(count, k, f)
    count = count + 1
    heapK[count], heapF[count] = k, f
    local i = count
    while i > 1 do
        local parent = floor(i / 2)
        if heapF[parent] <= heapF[i] then break end
        heapK[i], heapK[parent] = heapK[parent], heapK[i]
        heapF[i], heapF[parent] = heapF[parent], heapF[i]
        i = parent
    end
    return count
end

local function heapPop(count)
    local topK = heapK[1]
    heapK[1], heapF[1] = heapK[count], heapF[count]
    count = count - 1
    local i = 1
    while true do
        local left, right = i * 2, i * 2 + 1
        local smallest = i
        if left <= count and heapF[left] < heapF[smallest] then smallest = left end
        if right <= count and heapF[right] < heapF[smallest] then smallest = right end
        if smallest == i then break end
        heapK[i], heapK[smallest] = heapK[smallest], heapK[i]
        heapF[i], heapF[smallest] = heapF[smallest], heapF[i]
        i = smallest
    end
    return count, topK
end

local function heuristic(ax, az, bx, bz)
    -- Octile: diagonals cost sqrt(2), so the straight runs plus the diagonal
    -- shortcut is admissible - it never overestimates, which is what keeps A*
    -- optimal.
    local dx, dz = abs(ax - bx), abs(az - bz)
    local lo, hi = min(dx, dz), max(dx, dz)
    return (hi - lo) + lo * DIAG
end

local function astar(goalK, allowLethal)
    if not goalK then return nil end
    local n, side = CL.reach, CL.side
    local spacing = max(CFG.cloneGridSpacing, 0.5)
    local startK = (0 + n) * side + (0 + n) + 1
    local cells = CL.cells
    local goalCell = cells[goalK]
    local gx, gz = goalCell.x, goalCell.z
    local lethal = CFG.threatLethal
    local weight = CFG.threatWeight
    local maxClimb = CFG.cloneMaxClimb

    CL.searchGen = CL.searchGen + 1
    local gen = CL.searchGen

    stamp[startK] = gen
    gScore[startK] = 0
    cameFrom[startK] = nil
    local count = heapPush(0, startK, heuristic(cells[startK].x, cells[startK].z, gx, gz))

    while count > 0 do
        local topK
        count, topK = heapPop(count)
        if topK == goalK then return cameFrom, startK end

        local cell = cells[topK]
        local base = gScore[topK]
        local zeroed = topK - 1
        local di, dj = zeroed % side - n, floor(zeroed / side) - n
        local cellY = cell.y or 0

        for _, nb in ipairs(NEIGHBOURS) do
            local ni, nj = di + nb[1], dj + nb[2]
            if ni >= -n and ni <= n and nj >= -n and nj <= n then
                local nk = (nj + n) * side + (ni + n) + 1
                local other = cells[nk]
                if other.inRange and other.standable
                    and abs((other.y or 0) - cellY) <= maxClimb then
                    local passable = allowLethal or other.threat < lethal
                    if passable and nb[4] then
                        -- Diagonal: both orthogonal neighbours must be walkable,
                        -- or the corner of a hot cell gets clipped on the way.
                        local ak = (dj + nb[5] + n) * side + (di + nb[4] + n) + 1
                        local bk = (dj + nb[7] + n) * side + (di + nb[6] + n) + 1
                        local a, b = cells[ak], cells[bk]
                        passable = a ~= nil and b ~= nil and a.standable and b.standable
                    end
                    if passable then
                        local step = nb[3]
                        -- Heat paid per unit of exposure, so crossing something
                        -- hot quickly costs less than loitering in something warm.
                        local heat = min(other.threat, 200) * weight * step
                        local tentative = base + spacing * step + heat
                        if stamp[nk] ~= gen or tentative < gScore[nk] then
                            stamp[nk] = gen
                            gScore[nk] = tentative
                            cameFrom[nk] = topK
                            count = heapPush(count, nk,
                                tentative + heuristic(other.x, other.z, gx, gz) * spacing)
                        end
                    end
                end
            end
        end
    end
    return nil, startK
end

-- The cell nearest a world point, or nil if it is outside the window.
local function cellNearest(x, z)
    local spacing = max(CFG.cloneGridSpacing, 0.5)
    local n = CL.reach
    local di = clamp(floor((x / spacing) + 0.5) - CL.centerI, -n, n)
    local dj = clamp(floor((z / spacing) + 0.5) - CL.centerJ, -n, n)
    return (dj + n) * CL.side + (di + n) + 1
end

-- Look PAST the edge of the grid.
--
-- The window reaches about twenty studs. Cornered, with attacks filling all of
-- it, the clear ground is outside and bestGoal cannot see it - so the bot
-- settles for the least bad cell nearby, which when you are cornered is the
-- corner. This samples a ring of directions well beyond the grid and returns
-- the bearing of the coolest one, so the search has somewhere real to head for
-- instead of shuffling on the spot.
--
-- Only the DIRECTION comes from out here. The A* still does the local routing,
-- because out there is exactly where the grid has no idea what the floor does.
local function findEscapeBearing(root, localBest)
    if not CFG.escapeScanEnabled then return nil end
    local now = os.clock()
    -- Held briefly, or the bot would pick a new compass heading every frame and
    -- pace on the spot - the very thing this exists to stop.
    if CL.escapeDir and (now - CL.escapeAt) < CFG.cloneCommitTime * 2 then
        return CL.escapeDir
    end

    local rootPos = root.Position
    local spacing = max(CFG.cloneGridSpacing, 0.5)
    local near = CL.reach * spacing * 1.15
    local far = CL.reach * spacing * CFG.escapeScanFar
    local rays = max(floor(CFG.escapeScanRays), 4)
    local getThreatPair = S.getThreatPair
    S.prepareThreatPass()

    local bestDir, bestHeat = nil, huge
    for i = 0, rays - 1 do
        local angle = (i / rays) * math.pi * 2
        local dx, dz = math.cos(angle), math.sin(angle)
        -- Two samples along each bearing: a direction is only worth taking if
        -- it stays cool, not merely if it starts cool.
        local a = getThreatPair(Vector3.new(rootPos.X + dx * near, rootPos.Y, rootPos.Z + dz * near), 0, 0)
        local b = getThreatPair(Vector3.new(rootPos.X + dx * far, rootPos.Y, rootPos.Z + dz * far), 0, 0)
        local heat = max(a, b)
        if heat < bestHeat then
            bestHeat = heat
            bestDir = Vector3.new(dx, 0, dz)
        end
    end

    -- Only worth abandoning the local plan for something clearly better.
    if bestDir and bestHeat + CFG.escapeMargin < (localBest or huge) then
        CL.escapeDir, CL.escapeAt = bestDir, now
        heavyDebugThrottled("clone_escape", 1.5, "Clone", string.format(
            "Boxed in - everything within the grid is hot. Heading out on a bearing that reads %.0f against %.0f here.",
            bestHeat, localBest or 0))
        return bestDir
    end
    CL.escapeDir = nil
    return nil
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
    -- The goal is a world cell; its index in the window is arithmetic, not a
    -- search. This used to scan all 900 cells every frame to find it again.
    local goalK = nil
    if CL.goalI then
        local di, dj = CL.goalI - CL.centerI, CL.goalJ - CL.centerJ
        local n = CL.reach
        if di >= -n and di <= n and dj >= -n and dj <= n then
            goalK = (dj + n) * CL.side + (di + n) + 1
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
        -- If the whole window is hot, the least bad cell in it is usually the
        -- corner we are already stuck in. Look further out and aim at the rim.
        if saturated and goalK then
            local localBest = max(CL.cells[goalK].threat, CL.cells[goalK].threatLater)
            local bearing = findEscapeBearing(root, localBest)
            if bearing then
                local spacing = max(CFG.cloneGridSpacing, 0.5)
                local reachOut = CL.reach * spacing * 0.9
                local rimK = cellNearest(rootPos.X + bearing.X * reachOut,
                    rootPos.Z + bearing.Z * reachOut)
                local rim = CL.cells[rimK]
                if rim and rim.standable then goalK = rimK end
            end
        end
        if goalK then
            CL.goalI, CL.goalJ = CL.cells[goalK].i, CL.cells[goalK].j
        else
            CL.goalI, CL.goalJ = nil, nil
        end
        CL.goalAt = now
    end

    if not goalK then
        CL.goalI, CL.goalJ = nil, nil
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
        CL.goalI, CL.goalJ = nil, nil
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
        CL.goalI, CL.goalJ = nil, nil
        heavyDebugThrottled("clone_wall", 1.0, "Clone",
            string.format("Cell %s is walled off; marked impassable, re-routing.", target.key))
        setMovementState("CLONE - re-routing")
        return true
    end

    -- Progress check. The ordinary stuck detector is deliberately switched off
    -- while dodging - holding position inside a telegraph's clearance is
    -- sometimes correct - which left nothing at all watching for the character
    -- being wedged between a wall and an enemy. It would push into the corner
    -- indefinitely.
    local progress = CL.progressPos
    if not progress or (rootPos - progress).Magnitude >= CFG.cloneStuckDistance then
        CL.progressPos, CL.progressAt = rootPos, now
    elseif now - CL.progressAt >= CFG.cloneStuckTime then
        CL.progressPos, CL.progressAt = rootPos, now
        -- A hop clears most lips and steps, the goal is abandoned so the next
        -- pass picks somewhere else, and the cell we were pushing at is marked
        -- impassable so the search stops choosing the same wall.
        humanoid.Jump = true
        CL.floorCache[target.key] = { y = false, blocked = true, t = now }
        target.standable = false
        CL.goalI, CL.goalJ = nil, nil
        CL.escapeDir = nil
        heavyDebugThrottled("clone_pinned", 1.0, "Clone",
            "Pinned against something for " .. string.format("%.1fs", CFG.cloneStuckTime)
            .. " - hopping, dropping this goal and routing round it.")
        setMovementState("CLONE - pinned, re-routing")
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
