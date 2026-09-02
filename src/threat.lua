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

-- Locals for everything used inside the per-cell loops. Each `math.sqrt` in
-- Lua is a hash lookup on the global table followed by one on `math`; at the
-- call counts below that is not a rounding error.
local sqrt, max, min, abs, clamp = math.sqrt, math.max, math.min, math.abs, math.clamp
local huge = math.huge

-- Per-pass constants, computed ONCE for the whole grid instead of once per
-- query. getPlayerHitboxMetrics walks the character and does two Instance
-- lookups; at 900 cells x 2 time samples that was 3,600 Instance lookups per
-- evaluation, twelve times a second, purely to re-derive numbers that had not
-- changed.
local ctxReach, ctxHalfHeight, ctxNow = 2.0, 5.0, 0

local function prepareThreatPass()
    local _, playerRadius, totalHeight = getPlayerHitboxMetrics()
    -- The probe is deliberately NOT the drawn disc. The disc is how big you
    -- look; the probe is how big the game thinks you are when it decides
    -- whether something hit you, and probing with the wider of the two makes
    -- the grid blind to any pocket narrower than your shoulders.
    local probe = CFG.threatProbeRadius
    ctxReach = (probe > 0 and probe or playerRadius) + CFG.threatMargin
    ctxHalfHeight = (totalHeight * 0.5) + 2.0
    ctxNow = Workspace:GetServerTimeNow()
end

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
-- The exponent (CFG.threatCurve) sets how long it stays cool before turning.
-- This matters more than it looks. A delayed attack genuinely is harmless until
-- shortly before it lands, so it should read green for most of its wind-up and
-- then redden hard. At squared it went lethal a full second early, which turned
-- every marker into a wall - and when several attacks overlap and no square is
-- ever truly safe, walls everywhere means no route, while a gradient always
-- leaves somewhere to flow to.
local function urgency(timeToImpact)
    if timeToImpact <= 0 then
        -- Landing now, or within the window where it still hurts.
        return timeToImpact > -CFG.precastLingerTime and 1 or 0
    end
    if timeToImpact >= CFG.threatHorizon then return 0 end
    local t = 1 - (timeToImpact / CFG.threatHorizon)
    return t ^ CFG.threatCurve
end

-- How dangerous a point is at a given moment, given a projectile passes it at
-- `delta` seconds from that moment. Positive delta means it has not arrived
-- yet; negative means it has already gone by.
--
-- This is a window, not a ramp, and the difference matters twice over. A ramp
-- says a corridor a shot reaches in two seconds is nearly cool, so the bot
-- strolls in - and worse, it says the ground BEHIND a projectile is still
-- lethal, when behind it is the safest place on the map. The bot was fleeing
-- the one spot that could not hurt it.
--
-- The core of the window is geometric: how long the thing physically occupies
-- the point, which is its own width plus yours, over its speed. A shot at a
-- hundred studs a second is there for a twentieth of a second; a tornado
-- ambling at five owns the ground for the best part of two. Around that sits
-- the lead (generous - being early is how you get hit) and the wake (short,
-- because gone is gone).
local function passHeat(delta, halfWindow)
    if delta >= -halfWindow and delta <= halfWindow then return 1 end
    if delta > halfWindow then
        local over = (delta - halfWindow) / CFG.threatProjectileLead
        if over >= 1 then return 0 end
        local t = 1 - over
        return t * t
    end
    local over = (-delta - halfWindow) / CFG.threatProjectileWake
    if over >= 1 then return 0 end
    local t = 1 - over
    return t * t
end

-- ------------------------------------------------------------------ queries
-- Heat at a point, at TWO moments, in a single walk over the threat sources.
--
-- The grid needs both "how hot when I arrive" and "how hot once I have stood
-- here a moment", and asking twice meant walking every zone, volume,
-- projectile and safe marker twice over. The sources are the same; only the
-- time sample differs, so one pass computes both. Halves the dominant cost of
-- the whole system.
local function getThreatPair(position, timeA, timeB)
    local totalA, totalB = 0, 0
    local px, py, pz = position.X, position.Y, position.Z
    local reach, halfHeight, now = ctxReach, ctxHalfHeight, ctxNow
    local ignoreVertical = CFG.hazardIgnoreVertical
    local falloff = CFG.threatFalloff

    -- 1. Announced ground attacks. Exact geometry, exact timing.
    if CFG.usePrecast then
        for _, zone in ipairs(PC.zones) do
            local eta = zone.impactAt - now
            local wA = urgency(eta - timeA)
            local wB = urgency(eta - timeB)
            if wA > 0 or wB > 0 then
                local depth, vertical
                if zone.shape == "Circle" then
                    local c = zone.position
                    local dx, dz = px - c.X, pz - c.Z
                    depth = sqrt(dx * dx + dz * dz) - zone.radius
                    vertical = abs(py - c.Y)
                else
                    depth, vertical = boxDepth(position, zone.cframe,
                        zone.size.X * 0.5, zone.size.Z * 0.5)
                    vertical = abs(vertical)
                end
                if ignoreVertical or vertical < halfHeight then
                    local share
                    if depth <= reach then
                        share = 1
                    elseif depth <= reach + falloff then
                        local t = 1 - ((depth - reach) / falloff)
                        share = t * t * 0.6
                    end
                    if share then
                        totalA = totalA + THREAT_LETHAL * wA * share
                        totalB = totalB + THREAT_LETHAL * wB * share
                    end
                end
            end
        end
    end

    -- 2. Live hazards. Full weight at both times: nothing to wait for.
    for _, volume in ipairs(HZ.volumes) do
        if not volume.part or volume.part.Parent then
            local closest = S.volumeClosestPoint(volume, position)
            local dx, dz = px - closest.X, pz - closest.Z
            local depth = sqrt(dx * dx + dz * dz) - reach
            if ignoreVertical or abs(py - closest.Y) < halfHeight then
                local share
                if depth <= 0 then
                    share = 1
                elseif depth <= falloff then
                    local t = 1 - (depth / falloff)
                    share = t * t
                end
                if share then
                    local heat = THREAT_LETHAL * share
                    totalA = totalA + heat
                    totalB = totalB + heat
                end
            end
        end
    end

    -- 3. Moving hazards heat the corridor they are ABOUT to sweep. A
    -- projectile is not a place, it is a line through space and time.
    if CFG.threatSweepEnabled then
        local sweepTime = CFG.threatSweepTime
        for _, entry in ipairs(TH.projectiles) do
            local part = entry.part
            if part.Parent then
                local velocity = entry.velocity
                local speed = entry.speed
                if speed > 0.01 then
                    local origin = part.Position
                    local dx, dy, dz = px - origin.X, py - origin.Y, pz - origin.Z
                    local ux, uy, uz = entry.ux, entry.uy, entry.uz
                    -- Distance along the line of travel. Negative is behind it,
                    -- which is the one safe place to be.
                    local along = dx * ux + dy * uy + dz * uz
                    if along > 0 and along < speed * sweepTime then
                        local ox, oy, oz = dx - ux * along, dy - uy * along, dz - uz * along
                        local sideways = sqrt(ox * ox + oz * oz)
                        local width = reach + entry.radius
                        if sideways <= width + falloff and (ignoreVertical or abs(oy) < halfHeight) then
                            local edge = sideways <= width and 1
                                or (1 - (sideways - width) / falloff) ^ 2
                            local arrive = along / speed
                            -- How long it actually sits on this point: its own
                            -- width plus ours, over its speed.
                            local halfWindow = max(width / speed, 0.05)
                            totalA = totalA + THREAT_LETHAL * passHeat(arrive - timeA, halfWindow) * edge
                            totalB = totalB + THREAT_LETHAL * passHeat(arrive - timeB, halfWindow) * edge
                        end
                    end
                end
            end
        end
    end

    -- 4. Enemies. Constant in time: melee never telegraphs and never expires.
    local hard, soft = CFG.cloneEnemyRadius, CFG.cloneEnemySoftRadius
    local softSpan = max(soft - hard, 0.01)
    for _, epos in ipairs(TH.enemyPositions) do
        local dx, dz = px - epos.X, pz - epos.Z
        local dSquared = dx * dx + dz * dz
        -- Squared comparison first: most cells are nowhere near an enemy, and
        -- this skips the square root entirely for those.
        if dSquared < soft * soft then
            local d = sqrt(dSquared)
            local heat
            if d < hard then
                heat = THREAT_LETHAL
            else
                local t = 1 - ((d - hard) / softSpan)
                heat = THREAT_LETHAL * t * t * 0.5
            end
            totalA = totalA + heat
            totalB = totalB + heat
        end
    end

    -- 5. Safe-spot markers invert everything: outside the circle is the danger.
    if CFG.safeZoneEnabled and #HZ.safeZones > 0 then
        local inside = false
        for _, part in ipairs(HZ.safeZones) do
            if part.Parent then
                local size = part.Size
                local r = max(size.X, size.Z) * 0.5
                local dx, dz = px - part.Position.X, pz - part.Position.Z
                if dx * dx + dz * dz < r * r then inside = true break end
            end
        end
        if not inside then
            totalA = totalA + THREAT_LETHAL
            totalB = totalB + THREAT_LETHAL
        end
    end

    return totalA, totalB
end

-- Single-time query, for callers that only need one sample.
local function getThreatAt(position, atTime)
    prepareThreatPass()
    local a = getThreatPair(position, atTime or 0, atTime or 0)
    return a
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
            -- A low bar on purpose: a slow drifting tornado still owns the
            -- ground in front of it. The sidestep reflex applies its own,
            -- higher threshold separately.
            if velocity and velocity.Magnitude >= CFG.threatSweepMinSpeed then
                -- Unit vector and radius precomputed here rather than per
                -- cell: this is once per projectile, that was 900 times.
                local speed = velocity.Magnitude
                local size = part.Size
                TH.projectiles[#TH.projectiles + 1] = {
                    part = part, velocity = velocity, speed = speed,
                    ux = velocity.X / speed, uy = velocity.Y / speed, uz = velocity.Z / speed,
                    radius = max(size.X, size.Z) * 0.5,
                    fast = speed >= CFG.dodgeMinProjectileSpeed,
                }
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
        if part.Parent and entry.fast then
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
S.getThreatPair = getThreatPair
S.prepareThreatPass = prepareThreatPass
S.refreshThreatSources = refreshThreatSources
S.calculateDodgeForce = calculateDodgeForce
S.getProjectileDodge = getProjectileDodge
S.threatUrgency = urgency
end
