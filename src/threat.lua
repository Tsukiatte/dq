-- threat.lua - The influence map: how dangerous is a point, at a moment in time.
-- Module contract: receives the shared table S. Everything this module needs from
-- earlier modules is pulled into locals below; everything later modules need is
-- assigned onto S at the bottom. Load order is fixed by main.lua / build.py.
return function(S)
local RT = S.RT
local CFG = S.CFG
local HZ = S.HZ
local PC = S.PC
local TH = S.TH
local Workspace = S.Workspace
local LocalPlayer = S.LocalPlayer
local getHazardMotion = S.getHazardMotion
local getPlayerHitboxMetrics = S.getPlayerHitboxMetrics

-- =========================================================================
-- THREAT MANAGER (3.1.0)
--
-- Replaces "is this square safe, yes or no" with "how hot is this square, at
-- the moment I would be standing in it". Binary safety cannot express the
-- situation in a fan of radial beams: every square is unsafe, so the search
-- has nothing to choose between and the character stands still and dies. A
-- scalar field always has a least-bad answer, and the gaps between the beams
-- fall out of it for free.
--
-- Time is the third dimension. Every query takes `atTime` - seconds from now -
-- and an attack contributes almost nothing until shortly before it lands. That
-- is what lets the bot walk through a marker that fires in a second and a half
-- on its way somewhere genuinely cool.
--
-- Scores are on a 0..THREAT_LETHAL scale, additive where threats overlap, so
-- two half-dangerous things stacked read as lethal. 0 is safe.
-- =========================================================================

local THREAT_LETHAL = 100

-- ------------------------------------------------------------------ shapes
-- Circle: trivial, but done flat. Height is handled separately because a
-- telegraph on the floor below a ledge should not heat the ledge.
local function circleDepth(position, center, radius)
    local dx, dz = position.X - center.X, position.Z - center.Z
    local d = math.sqrt(dx * dx + dz * dz)
    return d - radius
end

-- Box with optional Y rotation. Rotating the WORLD POINT into the box's own
-- frame turns an oriented-box test back into an axis-aligned one: once the
-- point is expressed in box space, the box is axis-aligned by definition, and
-- the test is two independent 1-D comparisons. Cheaper and exact, versus
-- trying to rotate the box itself.
local function boxDepth(position, cframe, halfX, halfZ)
    local localPos = cframe:PointToObjectSpace(position)
    -- Distance outside each axis, clamped at 0 so a point inside reads 0.
    local dx = math.abs(localPos.X) - halfX
    local dz = math.abs(localPos.Z) - halfZ
    if dx <= 0 and dz <= 0 then
        -- Inside: the negative number closest to zero is the nearest wall.
        return math.max(dx, dz), localPos.Y
    end
    dx, dz = math.max(dx, 0), math.max(dz, 0)
    return math.sqrt(dx * dx + dz * dz), localPos.Y
end

-- ------------------------------------------------------------ urgency curve
-- How much an announced attack matters, given how long until it lands.
--
--   already landing / just landed -> full
--   about to land                 -> most
--   a long way off                -> almost nothing
--
-- Squared so the ramp is gentle far out and steep near impact: this is the
-- shape that produces the green-to-orange-to-red gradient rather than a wall.
local function urgency(timeToImpact)
    if timeToImpact <= 0 then
        -- Landing now, or within the window where it still hurts.
        return timeToImpact > -CFG.precastLingerTime and 1 or 0
    end
    if timeToImpact >= CFG.threatHorizon then return 0 end
    local t = 1 - (timeToImpact / CFG.threatHorizon)
    return t * t
end

-- ------------------------------------------------------------------ queries
-- The whole field in one call: 0 is safe, THREAT_LETHAL and above is lethal.
-- `atTime` is how many seconds from now we would be standing there.
local function getThreatAt(position, atTime)
    atTime = atTime or 0
    local total = 0
    local _, playerRadius, totalHeight = getPlayerHitboxMetrics()
    local reach = playerRadius + CFG.threatMargin
    local halfHeight = (totalHeight * 0.5) + 2.0

    -- 1. Announced ground attacks. Exact geometry, exact timing.
    if CFG.usePrecast then
        local now = Workspace:GetServerTimeNow()
        for _, zone in ipairs(PC.zones) do
            local timeToImpact = (zone.impactAt - now) - atTime
            local weight = urgency(timeToImpact)
            if weight > 0 then
                local depth, vertical
                if zone.shape == "Circle" then
                    depth = circleDepth(position, zone.position, zone.radius)
                    vertical = math.abs(position.Y - zone.position.Y)
                else
                    depth, vertical = boxDepth(position, zone.cframe,
                        zone.size.X * 0.5, zone.size.Z * 0.5)
                end
                if CFG.hazardIgnoreVertical or math.abs(vertical) < halfHeight then
                    if depth <= reach then
                        total = total + THREAT_LETHAL * weight
                    elseif depth <= reach + CFG.threatFalloff then
                        -- Outside but close: a shoulder of heat, so the search
                        -- prefers the middle of a gap to its very edge.
                        local t = 1 - ((depth - reach) / CFG.threatFalloff)
                        total = total + THREAT_LETHAL * weight * t * t * 0.6
                    end
                end
            end
        end
    end

    -- 2. Physical hazards already in the world. These are live damage, so they
    -- carry full weight regardless of time - there is nothing to wait for.
    for _, volume in ipairs(HZ.volumes) do
        if not volume.part or volume.part.Parent then
            local closest = S.volumeClosestPoint(volume, position)
            local dx, dz = position.X - closest.X, position.Z - closest.Z
            local depth = math.sqrt(dx * dx + dz * dz) - reach
            if CFG.hazardIgnoreVertical or math.abs(position.Y - closest.Y) < halfHeight then
                if depth <= 0 then
                    total = total + THREAT_LETHAL
                elseif depth <= CFG.threatFalloff then
                    local t = 1 - (depth / CFG.threatFalloff)
                    total = total + THREAT_LETHAL * t * t
                end
            end
        end
    end

    -- 3. Enemies. Melee never telegraphs and never expires, so its heat is
    -- constant in time: being next to one simply is the attack.
    for _, epos in ipairs(TH.enemyPositions) do
        local dx, dz = position.X - epos.X, position.Z - epos.Z
        local d = math.sqrt(dx * dx + dz * dz)
        if d < CFG.cloneEnemyRadius then
            total = total + THREAT_LETHAL
        elseif d < CFG.cloneEnemySoftRadius then
            local t = 1 - ((d - CFG.cloneEnemyRadius)
                / math.max(CFG.cloneEnemySoftRadius - CFG.cloneEnemyRadius, 0.01))
            total = total + THREAT_LETHAL * t * t * 0.5
        end
    end

    -- 4. Safe-spot markers invert everything: some bosses mark the one circle
    -- you must stand in, and outside it is the danger.
    if CFG.safeZoneEnabled and #HZ.safeZones > 0 then
        local inside = false
        for _, part in ipairs(HZ.safeZones) do
            if part.Parent then
                local size = part.Size
                if circleDepth(position, part.Position, math.max(size.X, size.Z) * 0.5) < 0 then
                    inside = true
                    break
                end
            end
        end
        if not inside then total = total + THREAT_LETHAL end
    end

    return total
end

-- Refreshed once per evaluation pass rather than per query: walking the enemy
-- set inside the inner loop of a grid search would dominate the cost.
local function refreshThreatSources()
    table.clear(TH.enemyPositions)
    local character = LocalPlayer.Character
    for model in pairs(HZ.enemyModels) do
        if model ~= character and model.Parent and not S.Players:GetPlayerFromCharacter(model) then
            local part = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
                or model:FindFirstChildWhichIsA("BasePart")
            if part then TH.enemyPositions[#TH.enemyPositions + 1] = part.Position end
        end
    end

    -- Projectiles worth steering away from: moving fast, and moving at us.
    table.clear(TH.projectiles)
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if not root then return end
    for _, part in ipairs(HZ.detected) do
        if part.Parent then
            local velocity = getHazardMotion(part)
            if velocity and velocity.Magnitude >= CFG.dodgeMinProjectileSpeed then
                TH.projectiles[#TH.projectiles + 1] = { part = part, velocity = velocity }
            end
        end
    end
end

-- ========================================================================
-- PROJECTILE STEERING (3.1.0)
--
-- The grid replans a few times a second, which is right for ground attacks
-- that announce themselves a second ahead and wrong for something already in
-- the air. This is the reflex underneath it: a sideways shove out of the line
-- of a projectile, computed per frame, costing one dot product per threat.
-- ========================================================================

-- Closest approach of a moving point to a stationary one, then a perpendicular
-- push out of its path.
--
-- The geometry: in the projectile's frame of reference we are the thing that
-- moves, at relativeVelocity. The closest the two ever come is at
--     t = -dot(relativePosition, relativeVelocity) / dot(relativeVelocity, relativeVelocity)
-- which is just the projection of the offset onto the direction of travel,
-- normalised by speed. Negative t means the nearest approach is in the past,
-- i.e. it is already going away, so there is nothing to dodge.
--
-- The dodge direction is the component of our offset PERPENDICULAR to the
-- line of travel: offset minus its projection onto that line. Stepping along
-- it is the shortest way out of the path, where backing away along the line
-- would just be outrun.
local function calculateDodgeForce(position, velocity, projectilePosition, projectileVelocity, projectileRadius)
    local relativePosition = position - projectilePosition
    local relativeVelocity = (velocity or Vector3.zero) - projectileVelocity
    local speedSquared = relativeVelocity:Dot(relativeVelocity)
    if speedSquared < 1e-4 then return nil end

    local t = -relativePosition:Dot(relativeVelocity) / speedSquared
    if t <= 0 or t > CFG.dodgeLookahead then return nil end

    -- Where we would be, relative to it, at the closest approach.
    local closestOffset = relativePosition + relativeVelocity * t
    local _, playerRadius = getPlayerHitboxMetrics()
    local missDistance = Vector3.new(closestOffset.X, 0, closestOffset.Z).Magnitude
    local hitRadius = playerRadius + (projectileRadius or 2) + CFG.threatMargin
    if missDistance >= hitRadius then return nil end

    -- Perpendicular component of the offset: what is left after removing the
    -- part that lies along the direction of travel.
    local direction = relativeVelocity.Unit
    local along = relativePosition:Dot(direction)
    local perpendicular = relativePosition - direction * along
    perpendicular = Vector3.new(perpendicular.X, 0, perpendicular.Z)

    if perpendicular.Magnitude < 0.1 then
        -- Dead centre: no side is "away", so pick one deterministically rather
        -- than dithering between them frame to frame.
        perpendicular = Vector3.new(-direction.Z, 0, direction.X)
    end

    -- Urgency scales with how little room there is and how soon it arrives.
    local closeness = 1 - (missDistance / hitRadius)
    local imminence = 1 - (t / CFG.dodgeLookahead)
    return perpendicular.Unit * (closeness * imminence), t
end

-- The strongest single dodge among the tracked projectiles, or nil.
local function getProjectileDodge(position, velocity)
    if not CFG.dodgeProjectiles then return nil end
    local best, bestWeight = nil, 0
    for _, entry in ipairs(TH.projectiles) do
        local part = entry.part
        if part.Parent then
            local radius = math.max(part.Size.X, part.Size.Z) * 0.5
            local force = calculateDodgeForce(position, velocity, part.Position, entry.velocity, radius)
            if force then
                local weight = force.Magnitude
                if weight > bestWeight then best, bestWeight = force, weight end
            end
        end
    end
    return best, bestWeight
end

TH.LETHAL = THREAT_LETHAL
S.getThreatAt = getThreatAt
S.refreshThreatSources = refreshThreatSources
S.calculateDodgeForce = calculateDodgeForce
S.getProjectileDodge = getProjectileDodge
S.threatUrgency = urgency
end
