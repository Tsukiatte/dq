-- dodge.lua - A box that is never in danger, and a character that follows it.
-- Module contract: receives the shared table S. Everything this module needs from
-- earlier modules is pulled into locals below; everything later modules need is
-- assigned onto S at the bottom. Load order is fixed by main.lua / build.py.
return function(S)
local RT = S.RT
local CFG = S.CFG
local HZ = S.HZ
local PC = S.PC
local DG = S.DG
local NAV = S.NAV
local Workspace = S.Workspace
local LocalPlayer = S.LocalPlayer
local Players = S.Players
local heavyDebug = S.heavyDebug
local heavyDebugThrottled = S.heavyDebugThrottled
local setMovementState = S.setMovementState
local getVisualRoot = S.getVisualRoot
local getPlayerHitboxMetrics = S.getPlayerHitboxMetrics
local getEnemyStandoff = S.getEnemyStandoff
local getEnemyMeleeReach = S.getEnemyMeleeReach
local getEnemyExtent = S.getEnemyExtent
local getHazardMotion = S.getHazardMotion
local volumeClosestPoint = S.volumeClosestPoint
local getRaycastExclusions = S.getRaycastExclusions
local releaseFacing = S.releaseFacing
local driveTo = S.driveTo
local releaseMover = S.releaseMover

local sqrt, max, min, abs, floor = math.sqrt, math.max, math.min, math.abs, math.floor
local cos, sin, pi = math.cos, math.sin, math.pi

-- =========================================================================
-- DODGE (4.0.0)
--
-- This replaces the grid, the heat field, the A*, and the twenty-odd
-- heuristics that grew around them. What is left is the shape of the thing
-- that actually works in a few hundred lines:
--
--   1. Know where danger is, now and in the next second or two. Exact
--      geometry and exact timing for announced attacks, footprint for the
--      physical ones, a swept segment for anything moving, a circle for
--      every enemy.
--   2. Look at a few dozen points around the character. For each, ask what
--      would hit you on the way there and what would hit you once you
--      stopped - at the moments those things would actually happen.
--   3. Put a box on the best one. Move the character straight at the box.
--      Do it again next frame.
--
-- There is no path. A path is what you need when you decide rarely and move
-- imprecisely. Deciding every frame and moving exactly, the straight line to
-- the current best point IS the path, and the check on step 2 is what stops
-- that line crossing something that lands while you are on it.
--
-- The box is the whole idea. It only ever sits on ground that will be clear
-- when you get there and stays clear once you have. The character just
-- follows it.
-- =========================================================================

-- ------------------------------------------------------------ sources
-- Gathered once per decision so the per-point test below is pure arithmetic.
local function refreshSources()
    local _, rootRadius, totalHeight = getPlayerHitboxMetrics()
    -- What counts as "touching": the root part is what the game damages
    -- against, plus a little margin. The visible body is wider, and probing
    -- with the body makes every narrow gap read as closed.
    DG.reach = (CFG.dodgeProbe > 0 and CFG.dodgeProbe or rootRadius) + CFG.dodgeMargin
    DG.halfHeight = totalHeight * 0.5 + 2.5
    DG.now = Workspace:GetServerTimeNow()
    DG.clock = os.clock()

    table.clear(DG.enemies)
    local character = LocalPlayer.Character
    local clock = os.clock()
    for model in pairs(HZ.enemyModels) do
        if model ~= character and model.Parent and not Players:GetPlayerFromCharacter(model) then
            local part = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
                or model:FindFirstChildWhichIsA("BasePart")
            if part then
                local pos = part.Position

                -- Velocity from where it was last decision. Enemies close on
                -- you: a spot thirteen studs from one now is eight a second
                -- later. Judging them where they WILL be is what makes the
                -- character back away from an advance instead of sidestepping
                -- into whatever happens to be beside it.
                local prev = DG.enemyPrev[model]
                local vx, vz = 0, 0
                if prev then
                    local dt = clock - prev.t
                    if dt > 0.01 and dt < 1 then
                        vx, vz = (pos.X - prev.x) / dt, (pos.Z - prev.z) / dt
                        -- A jump this large is a teleport or a respawn, not motion.
                        if vx * vx + vz * vz > 60 * 60 then vx, vz = 0, 0 end
                    end
                end
                DG.enemyPrev[model] = { x = pos.X, z = pos.Z, t = clock }

                -- The hard circle is the BODY and nothing more. Its swing is
                -- an attack, and the game spawns a hitBox for it that is
                -- detected like any other; pricing the swing's reach as
                -- danger in its own right made the character kite two idle
                -- melee bots backward into a wall two rooms away, because a
                -- mob walking at you is never further than its reach. Past
                -- the body a soft ring out to the standoff is a preference,
                -- below the move threshold, so it fights from there.
                local hard = getEnemyExtent(model) + 1
                local hub = DG.hubs[model]
                if not hub then
                    hub = { times = {}, lastSpawn = -math.huge, period = nil, rate = 0, fire = nil, angles = {}, pred = {} }
                    DG.hubs[model] = hub
                end
                DG.enemies[#DG.enemies + 1] = {
                    x = pos.X, y = pos.Y, z = pos.Z, vx = vx, vz = vz,
                    hard = hard, soft = getEnemyMeleeReach(model) + CFG.dodgeEnemySoftWidth,
                    model = model, hub = hub,
                }
            end
        end
    end

    -- Anything moving is a line through space and time, not a place. The
    -- square in front of a shot is the dangerous one; the square it just left
    -- is the safest on the map.
    table.clear(DG.movers)
    table.clear(DG.moverSet)
    for _, part in ipairs(HZ.detected) do
        if part.Parent then
            local velocity = getHazardMotion(part)
            if velocity and velocity.Magnitude >= CFG.dodgeMoverMinSpeed then
                local size = part.Size
                DG.movers[#DG.movers + 1] = {
                    pos = part.Position, vel = velocity,
                    radius = max(size.X, size.Z) * 0.5,
                }
                DG.moverSet[part] = true
            end
        end
    end

    -- Hubs (4.10.0): an enemy that long line attacks pass through. The
    -- Midgardian Champion fires beams two at a time through its own
    -- position; at melee standoff the character stands where they all
    -- cross, and two crossing beams cannot be cleared in the telegraph. Each
    -- new line part whose axis passes near an enemy is counted once. The
    -- rate over the last ten seconds and the interval between volleys give
    -- decide() a radial cost and an approach gate.
    for _, part in ipairs(HZ.detected) do
        if not DG.hubSeen[part] then
            local size = part.Size
            local L = max(size.X, size.Z)
            if L >= CFG.dodgeHubLineLength then
                DG.hubSeen[part] = true
                local cf = part.CFrame
                local axis = size.X >= size.Z and cf.RightVector or cf.LookVector
                axis = Vector3.new(axis.X, 0, axis.Z)
                if axis.Magnitude > 0.01 then
                    axis = axis.Unit
                    local p = part.Position
                    local t = HZ.spawnTimes[part] or clock
                    local model = part:FindFirstAncestorOfClass("Model")
                    local fire = model and RT.armDelays[string.lower(model.Name)] or nil
                    for i = 1, #DG.enemies do
                        local e = DG.enemies[i]
                        local rel = Vector3.new(e.x - p.X, 0, e.z - p.Z)
                        local along = rel:Dot(axis)
                        local perp = (rel - axis * along).Magnitude
                        -- Centred on the enemy, not merely passing it: a mage
                        -- shot that happens to cross the boss was being counted
                        -- as one of its lines, and took over the hub's name,
                        -- arming delay and headings.
                        if perp <= CFG.dodgeHubTolerance and abs(along) <= CFG.dodgeHubTolerance then
                            local hub = e.hub
                            -- Lines within a third of a second are one volley.
                            if t - hub.lastSpawn > 0.3 then
                                if hub.lastSpawn > -math.huge then
                                    local interval = t - hub.lastSpawn
                                    -- The interval between lines of one burst is the
                                    -- period; the gap between bursts is not. Folding
                                    -- the ten-second gap in put the period at two
                                    -- seconds for the first half of every burst, and
                                    -- every predicted line came late.
                                    if interval < CFG.dodgeHubBurstGap then
                                        hub.period = hub.period and (hub.period * 0.7 + interval * 0.3) or interval
                                    elseif interval < 30 then
                                        hub.gap = hub.gap and (hub.gap * 0.7 + interval * 0.3) or interval
                                    end
                                end
                                hub.lastSpawn = t
                                -- The line's heading, folded to [0, pi): a line
                                -- has no front. The Midgardian Champion's beams
                                -- come 20 degrees apart every half second - a
                                -- hand sweeping round the boss - and from two of
                                -- them the third is known before it exists.
                                local ang = math.atan2(axis.Z, axis.X)
                                if ang < 0 then ang = ang + pi end
                                local angles = hub.angles
                                angles[#angles + 1] = { t = t, a = ang, x = p.X, z = p.Z, y = p.Y, w = min(size.X, size.Z), L = L }
                                while #angles > 6 do table.remove(angles, 1) end
                            end
                            hub.times[#hub.times + 1] = t
                            if fire and fire > 0 then hub.fire = fire end
                            if model then hub.name = string.lower(model.Name) end
                        end
                    end
                end
            end
        end
    end
    for _, hub in pairs(DG.hubs) do
        local times = hub.times
        local cutoff = clock - 10
        local n = 0
        for i = #times, 1, -1 do
            if times[i] < cutoff then table.remove(times, i) else n = n + 1 end
        end
        hub.rate = n / 10
        -- Active: lines are coming now. Imminent: the gap between bursts is
        -- nearly used up. Either way the ring is the place to be.
        local since = clock - hub.lastSpawn
        hub.active = since <= max((hub.period or 0.5) * 3, 1.5)
        hub.imminent = hub.gap ~= nil and since >= hub.gap - CFG.dodgeHubLeave and since < hub.gap + 5

        -- Prediction: when the last two steps of heading agree, the next
        -- lines are the same step further round, one period apart.
        local pred = hub.pred
        table.clear(pred)
        local angles = hub.angles
        local na = #angles
        if na >= 3 and hub.period and hub.period < 5 and clock - angles[na].t < hub.period * 3 then
            local function wrap(d)
                while d > pi * 0.5 do d = d - pi end
                while d <= -pi * 0.5 do d = d + pi end
                return d
            end
            local d1 = wrap(angles[na].a - angles[na - 1].a)
            local d0 = wrap(angles[na - 1].a - angles[na - 2].a)
            if abs(d1) > math.rad(3) and abs(d1 - d0) < math.rad(6) then
                hub.step = d1
                local last = angles[na]
                local span = hub.name and RT.armSpans[hub.name]
                local fire = hub.fire or (span and span.first) or 0
                local hurt = span and max(span.last - span.first, 0.3) or CFG.dodgePredictedLive
                for k = 1, CFG.dodgePredictSteps do
                    local at = last.t + hub.period * k
                    pred[#pred + 1] = {
                        a = last.a + d1 * k, x = last.x, z = last.z, y = last.y, w = last.w, L = last.L,
                        from = at + fire, untilAt = at + fire + hurt + CFG.dodgeLinger,
                    }
                end
            else
                hub.step = nil
            end
        else
            hub.step = nil
        end
    end
end

-- Flat distance from (px, pz) to the segment a-b, in the XZ plane.
local function segmentDistance(px, pz, ax, az, bx, bz)
    local dx, dz = bx - ax, bz - az
    local lenSq = dx * dx + dz * dz
    local t = 0
    if lenSq > 1e-6 then
        t = ((px - ax) * dx + (pz - az) * dz) / lenSq
        if t < 0 then t = 0 elseif t > 1 then t = 1 end
    end
    local cx, cz = ax + dx * t, az + dz * t
    local ex, ez = px - cx, pz - cz
    return sqrt(ex * ex + ez * ez)
end

-- Danger 0..1 at a point, `t` seconds from now. Max over sources, not sum:
-- the question is "does something hit me here", and two half-hits are not a
-- whole one.
local function dangerAt(px, py, pz, t)
    local reach, halfHeight = DG.reach, DG.halfHeight
    local shoulder = CFG.dodgeShoulder
    local worst = 0

    -- 0. Enemies, at time t - where an advancing one will be, not where it is.
    -- Melee never telegraphs: being next to one is the attack. They read 1.5
    -- against an attack's 1.0, so a line through an enemy loses to a line
    -- through an attack and is taken only when every other line is worse -
    -- backed into a corner with the mob as the only way out, it goes through
    -- the mob, because dying in the corner is the alternative.
    -- Extrapolated only a short way: a mob chasing you is predicted onto
    -- every spot near you if you look a second ahead, and then the only
    -- safe ground is always further back.
    local tt = t < CFG.dodgeEnemyLookahead and t or CFG.dodgeEnemyLookahead
    for i = 1, #DG.enemies do
        local e = DG.enemies[i]
        local dx, dz = px - (e.x + e.vx * tt), pz - (e.z + e.vz * tt)
        local d2 = dx * dx + dz * dz
        if d2 < e.soft * e.soft then
            local d = sqrt(d2)
            if d < e.hard then return 1.5 end
            worst = max(worst, CFG.dodgeEnemySoftWeight * (1 - (d - e.hard) / (e.soft - e.hard)))
        end
    end

    -- 1. Announced ground attacks: exact shape, exact time. A zone hurts from
    -- `lead` seconds before it lands until `linger` after. Before that it is
    -- floor you may cross; that is the entire value of knowing the timing.
    local now = DG.now
    for i = 1, #PC.zones do
        local zone = PC.zones[i]
        local eta = zone.impactAt - now
        if t >= eta - CFG.dodgeLead and t <= eta + CFG.dodgeLinger + (zone.holdFor or 0) then
            local depth, vertical
            if zone.shape == "Circle" then
                local c = zone.position
                local dx, dz = px - c.X, pz - c.Z
                depth = sqrt(dx * dx + dz * dz) - zone.radius
                vertical = abs(py - c.Y)
            else
                -- Oriented box: rotate the point into the box's frame and it
                -- becomes an axis-aligned test.
                local lp = zone.cframe:PointToObjectSpace(Vector3.new(px, py, pz))
                local ox = abs(lp.X) - zone.size.X * 0.5
                local oz = abs(lp.Z) - zone.size.Z * 0.5
                if ox <= 0 and oz <= 0 then
                    depth = max(ox, oz)
                else
                    ox, oz = max(ox, 0), max(oz, 0)
                    depth = sqrt(ox * ox + oz * oz)
                end
                vertical = abs(lp.Y)
            end
            if vertical < halfHeight then
                if depth <= reach then return 1 end
                if depth <= reach + shoulder then
                    worst = max(worst, 0.6 * (1 - (depth - reach) / shoulder))
                end
            end
        end
    end

    -- 1b. Scripted projectiles (Northern Lands): where each one WILL be at
    -- time t, from the numbers the game sent - no extrapolation. A box in the
    -- projectile's own frame: halfLength along its travel, halfWidth across.
    for i = 1, #PC.paths do
        local p = PC.paths[i]
        local at = now + t
        -- From the moment it exists, not from the moment it starts moving:
        -- the game places the body at its origin on the event and it sits
        -- there until its start time - and it hurts while it sits. The real
        -- criss cross spawns ON the player; five of Chris's seven deaths were
        -- that, at 0% along its path, with the dodge reading zero danger.
        if at >= (p.spawn or p.t0) - 0.05 and at <= p.t1 + 0.1 and abs(py - p.oy) < halfHeight + p.halfHeight then
            local k = (at - p.t0) / p.dur
            if k < 0 then k = 0 elseif k > 1 then k = 1 end
            local s = k * p.dist + p.offset
            local cx, cz = p.ox + p.dx * s, p.oz + p.dz * s
            local qx, qz = px - cx, pz - cz
            local along = abs(qx * p.dx + qz * p.dz) - p.halfLength
            local side = abs(-qx * p.dz + qz * p.dx) - p.halfWidth
            local depth
            if along <= 0 and side <= 0 then
                depth = max(along, side)
            else
                along, side = max(along, 0), max(side, 0)
                depth = sqrt(along * along + side * side)
            end
            if depth <= reach then return 1 end
            if depth <= reach + shoulder then
                worst = max(worst, 1 - (depth - reach) / shoulder)
            end
        end
    end

    -- 1c. Predicted lines (4.10.2): where a sweeping hub's NEXT lines will
    -- be, from the step between the last ones. Floor until their time, a
    -- line for as long as such lines have been seen to hurt.
    local atc = DG.clock + t
    for _, hub in pairs(DG.hubs) do
        local pred = hub.pred
        if pred then
            for i = 1, #pred do
                local L = pred[i]
                if atc >= L.from - CFG.dodgeLead and atc <= L.untilAt and abs(py - L.y) < halfHeight + 40 then
                    local dx, dz = math.cos(L.a), math.sin(L.a)
                    local qx, qz = px - L.x, pz - L.z
                    local along = abs(qx * dx + qz * dz) - L.L * 0.5
                    local side = abs(-qx * dz + qz * dx) - L.w * 0.5
                    local depth
                    if along <= 0 and side <= 0 then
                        depth = max(along, side)
                    else
                        along, side = max(along, 0), max(side, 0)
                        depth = sqrt(along * along + side * side)
                    end
                    if depth <= reach then return 1 end
                    if depth <= reach + shoulder then
                        worst = max(worst, 1 - (depth - reach) / shoulder)
                    end
                end
            end
        end
    end

    -- 2. Physical hazards already in the world. They are live now, so time
    -- does not enter into it - except that the moving ones are handled below
    -- as the line they sweep rather than the point they occupy.
    local point = Vector3.new(px, py, pz)
    local lead = CFG.dodgeLead
    for i = 1, #HZ.volumes do
        local volume = HZ.volumes[i]
        local part = volume.part
        local live = true
        if part then
            -- Announced and not yet armed: floor, until its learned impact is
            -- within the lead. Unknown timing stays live - the first cast of
            -- anything is dodged as if it were, and the second is not.
            local st = HZ.armState[part]
            if st then
                if st.doneAt or st.dormant then
                    live = false
                elseif not st.armedAt and st.impactAt then
                    live = t >= (st.impactAt - DG.clock) - lead
                end
            end
        end
        if live and (not part or part.Parent) and not (part and DG.moverSet[part]) then
            local closest = volumeClosestPoint(volume, point)
            if abs(py - closest.Y) < halfHeight then
                local dx, dz = px - closest.X, pz - closest.Z
                local depth = sqrt(dx * dx + dz * dz) - reach
                if depth <= 0 then return 1 end
                if depth <= shoulder then
                    worst = max(worst, 1 - depth / shoulder)
                end
            end
        end
    end

    -- 3. Moving hazards: where it will be around time t, as a short segment so
    -- a fast shot cannot fall between two samples.
    local h = CFG.dodgeMoverWindow
    for i = 1, #DG.movers do
        local m = DG.movers[i]
        local ax, az = m.pos.X + m.vel.X * (t - h), m.pos.Z + m.vel.Z * (t - h)
        local bx, bz = m.pos.X + m.vel.X * (t + h), m.pos.Z + m.vel.Z * (t + h)
        local py2 = m.pos.Y + m.vel.Y * t
        if abs(py - py2) < halfHeight then
            local depth = segmentDistance(px, pz, ax, az, bx, bz) - (m.radius + reach)
            if depth <= 0 then return 1 end
            if depth <= shoulder then
                worst = max(worst, 1 - depth / shoulder)
            end
        end
    end

    -- 5a. Timed safe windows (Northern Lands bonus boss): around the
    -- explosion, outside the colour spot is the danger; before and after,
    -- the floor is floor.
    for i = 1, #PC.safeWindows do
        local w = PC.safeWindows[i]
        local at = now + t
        if at >= w.from and at <= w.untilAt then
            local inside = false
            for j = 1, #w.parts do
                local part = w.parts[j]
                if part.Parent then
                    local size = part.Size
                    local r = max(size.X, size.Z) * 0.5
                    local dx, dz = px - part.Position.X, pz - part.Position.Z
                    if dx * dx + dz * dz < r * r then inside = true break end
                end
            end
            if not inside then return 1 end
        end
    end

    -- 5. Safe-spot bosses invert the rule: outside the marked circle is the
    -- danger.
    if CFG.safeZoneEnabled and #HZ.safeZones > 0 then
        local inside = false
        for i = 1, #HZ.safeZones do
            local part = HZ.safeZones[i]
            if part.Parent then
                local size = part.Size
                local r = max(size.X, size.Z) * 0.5
                local dx, dz = px - part.Position.X, pz - part.Position.Z
                if dx * dx + dz * dz < r * r then inside = true break end
            end
        end
        if not inside then return 1 end
    end

    return worst
end

-- ------------------------------------------------------------ candidates
-- Fixed offsets around the character: a few rings of a few directions. Rebuilt
-- only when the settings change.
local function buildOffsets()
    table.clear(DG.offsets)
    local rings = max(floor(CFG.dodgeRings), 1)
    local rays = max(floor(CFG.dodgeRays), 6)
    for ring = 1, rings do
        local r = CFG.dodgeReach * (ring / rings)
        -- Alternate rings are rotated half a step so the points interleave
        -- instead of lining up into spokes.
        local phase = (ring % 2 == 0) and (pi / rays) or 0
        for i = 0, rays - 1 do
            local a = phase + (i / rays) * 2 * pi
            DG.offsets[#DG.offsets + 1] = { x = cos(a) * r, z = sin(a) * r, dist = r }
        end
    end
    DG.offsetsKey = string.format("%d/%d/%.1f", rings, rays, CFG.dodgeReach)
end

-- Floor under a point, or nil. Cached briefly by rounded position: the
-- candidates move with the character, but not far between decisions.
local function floorAt(x, z, rootY, params)
    local key = floor(x * 2) .. "," .. floor(z * 2)
    local hit = DG.floorCache[key]
    local now = os.clock()
    if hit and now - hit.t < 0.5 then return hit.y end
    -- From just above the root, not four studs above it: under the pipes and
    -- machinery of a boss room the higher origin hit the pipe, read its top as
    -- the floor, and rejected every spot - "waiting for a gap" with nothing
    -- wrong but the ceiling, in the corner the character then died in. A
    -- floor higher than the root is more than a climb anyway.
    local result = Workspace:Raycast(Vector3.new(x, rootY + 0.5, z), Vector3.new(0, -(3.5 + CFG.dodgeMaxDrop), 0), params)
    local y = result and result.Position.Y or false
    DG.floorCache[key] = { y = y, t = now }
    DG.floorCacheSize = DG.floorCacheSize + 1
    if DG.floorCacheSize > 3000 then table.clear(DG.floorCache) DG.floorCacheSize = 0 end
    return y
end

-- Is the straight walk from the character to (x, z) clear of solid geometry?
-- Swept as a slab the width of the character, not a line through its middle:
-- a single centre ray passed spots the body could not reach, and the tween
-- then stopped against the wall it had not seen.
-- `above` is how far the root rides above the floor here; the slab is swept
-- to the SAME height above the destination floor, so up a staircase it
-- climbs with the steps and clears the risers (a riser under the step height
-- never reaches a slab centred three studs up). It used to be swept from the
-- root to two studs above the destination floor, which on any upward run of
-- steps clipped the first riser and rejected every spot uphill.
local function walkable(rootPos, x, y, z, params, above)
    local from = Vector3.new(rootPos.X, rootPos.Y, rootPos.Z)
    local to = Vector3.new(x, y + (above or 2.0), z)
    local w = DG.reach * 2
    local ok, hit = pcall(function()
        return Workspace:Blockcast(CFrame.new(from), Vector3.new(w, 1.5, w), to - from, params)
    end)
    if not ok then hit = Workspace:Raycast(from, to - from, params) end
    return hit == nil
end

-- The decision. Fills DG.dangerHere and DG.target.
local function decide(root, humanoid)
    if DG.offsetsKey ~= string.format("%d/%d/%.1f", max(floor(CFG.dodgeRings), 1),
        max(floor(CFG.dodgeRays), 6), CFG.dodgeReach) then buildOffsets() end

    refreshSources()

    local rootPos = root.Position
    local rx, ry, rz = rootPos.X, rootPos.Y, rootPos.Z
    -- The mover's real speed, so a spot reachable in time is judged in time.
    local speed = max(S.moverSpeed and S.moverSpeed(humanoid) or humanoid.WalkSpeed, 4)
    local dwell = CFG.dodgeDwell
    -- Where the feet are. Heights below are judged from here, not from the
    -- root: the root rides about three studs up, and comparing a floor
    -- height against it with abs() rejected any spot even a fraction of a
    -- stud DOWNHILL while allowing six studs up - the dodge could not step off
    -- a kerb but would happily pick a ledge it had to jump onto.
    local aboveFloor = humanoid.HipHeight + root.Size.Y * 0.5
    do
        local under = Workspace:Raycast(rootPos, Vector3.new(0, -8, 0), DG.rayParams)
        if under then aboveFloor = ry - under.Position.Y end
    end
    local feetY = ry - aboveFloor

    -- Here: now, and a moment from now. Standing still is a decision too.
    local here0 = dangerAt(rx, ry, rz, 0)
    DG.dangerHere = max(here0, dangerAt(rx, ry, rz, dwell * 0.5), dangerAt(rx, ry, rz, dwell))
    DG.gapWait = false

    -- The direction we were last sent, if it was recent. Two safe sides of a
    -- beam score the same to the last decimal, and re-picking between them
    -- each decision is the left-right shuffle: a change of direction costs
    -- something now, a reversal most, so the side picked first is the side
    -- kept until the other is clearly better - which a closed line always is.
    local hx, hz = 0, 0
    if DG.heading and os.clock() - DG.headingTime < CFG.dodgeHeadingMemory then
        hx, hz = DG.heading.X, DG.heading.Z
    end
    local turnCost = CFG.dodgeTurnCost

    -- Who we are trying to get to, if anyone. The box drifts toward them
    -- through safe ground and holds still when there is none: that is the
    -- whole of "approach" now, and pursuit no longer moves the character in
    -- this mode.
    -- Near the target, the box is the approach: the last stretch through a
    -- pattern is crossed one safe spot at a time. Far from it, pursuit walks
    -- the map and the box fires only for danger - unless pursuit is stopped at
    -- the edge of something, in which case the box picks the way in.
    local approach, preferred = nil, 0
    if RT.farmEnabled and not CFG.dodgeManual and NAV.cachedEnemy and NAV.cachedEnemy.Parent then
        local er = NAV.cachedEnemy:FindFirstChild("HumanoidRootPart") or NAV.cachedEnemy.PrimaryPart
        if er then
            local p = er.Position
            local ax, az = p.X - rx, p.Z - rz
            local near = CFG.dodgeReach * 1.5
            -- Also whenever a hub is firing or about to: the ring is the
            -- box's to hold from wherever the last dodge left the character,
            -- not only from within a box-length of the boss. Without this,
            -- a dodge that ended eighty studs out left it there.
            local hub = DG.hubs[NAV.cachedEnemy]
            local hubRing = CFG.dodgeHubHold and hub and hub.rate >= CFG.dodgeHubMinRate and (hub.active or hub.imminent)
            if ax * ax + az * az <= near * near or DG.pursuitBlocked or hubRing then
                approach = p
                preferred = getEnemyStandoff(NAV.cachedEnemy) - 0.5
            end
        end
    end
    local approachWeight = CFG.dodgeApproachWeight
    local moveAt = CFG.dodgeMoveAt

    -- The radial cost around each hub: the chance a random line through the
    -- hub covers a spot falls off as width over the circumference at that
    -- distance, times how often lines come, over the time we would stand
    -- there. Melee standoff sits deep inside it; the field pushes the
    -- character out to where a volley is a nuisance rather than a certainty.
    -- Only while it is firing: the rate stays up for ten seconds after a
    -- burst, and a radial cost that stays with it kept the character out
    -- through the whole quiet gap - the one time it could have been casting.
    local hubs = {}
    for i = 1, #DG.enemies do
        local e = DG.enemies[i]
        if e.hub and e.hub.rate >= CFG.dodgeHubMinRate and e.hub.active then hubs[#hubs + 1] = e end
    end
    local hubWeight, hubWidth = CFG.dodgeHubWeight, CFG.dodgeHubLineWidth
    local function hubCost(x, z)
        local c = 0
        for i = 1, #hubs do
            local e = hubs[i]
            local dx, dz = x - e.x, z - e.z
            local d = sqrt(dx * dx + dz * dz)
            if d < 4 then d = 4 end
            c = c + hubWeight * e.hub.rate * (hubWidth / (pi * d)) * dwell
        end
        return c
    end

    -- Going in to a hub is allowed only when there is time to get there and
    -- back out before the next volley fires: the last volley's time, the
    -- observed period, and the lines' learned arming delay say when that is.
    -- The hub's rhythm sets where to stand (4.10.6). While it fires, and
    -- for the last seconds of the gap before it fires again, the ring at
    -- dodgeHubStandoff: far enough out that the lines of a sweep have gaps
    -- between them. In the quiet, the ability standoff, to cast. The ring
    -- is held from both sides - inside it is as wrong as outside.
    DG.hubHold = false
    if approach and CFG.dodgeHubHold then
        local hub = DG.hubs[NAV.cachedEnemy]
        if hub and hub.rate >= CFG.dodgeHubMinRate and (hub.active or hub.imminent) then
            preferred = CFG.dodgeHubStandoff
            DG.hubHold = true
        end
    end
    local hold = DG.hubHold
    -- The ring pull is stronger than the ordinary approach: at the
    -- ordinary weight the distance cost of an eighteen-stud move beat it,
    -- and the character sat at thirty studs "safe here" while the sweep
    -- came round.
    -- The same stronger pull whenever the box is the approach - pursuit
    -- stopped at the edge of something - or the quiet gap goes by "safe
    -- here" at fifty studs, out of ability range.
    local boxDrives = hold or DG.pursuitBlocked
    local function approachCost(x, z)
        local ax, az = x - approach.X, z - approach.Z
        local dd = sqrt(ax * ax + az * az) - preferred
        local w = boxDrives and approachWeight * CFG.dodgeHubRingWeight or approachWeight
        if hold then return w * abs(dd) end
        return w * max(0, dd)
    end

    -- Five samples along the line from here to (rx+ox, rz+oz): three on the
    -- way, two once there, each at the moment it would actually happen. The
    -- score is half the worst of them and half the average - a spot hit at one
    -- moment on the way is not as bad as one hit at every moment, and in a
    -- field where everything is hit at SOME moment that difference is the
    -- only gradient there is. Pure max made every candidate in a bullet hell
    -- read exactly 1.0 and the nearest won. Returns worst, graded.
    local function score(ox, oz, dist)
        local T = dist / speed
        local worst, raw, total = 0, 0, 0
        local inside = CFG.dodgeInsideWeight
        -- Samples every few studs along the line, not three fixed fractions:
        -- three samples on an eighteen-stud line are six studs apart, and a
        -- mage shot is three studs wide. A line that stepped straight
        -- through one scored clean, and the character walked into it.
        local n = math.ceil(dist / CFG.dodgeSampleSpacing)
        if n < 2 then n = 2 elseif n > 8 then n = 8 end
        local count = 0
        for k = 1, n - 1 do
            local f = k / n
            count = count + 1
            local d = dangerAt(rx + ox * f, ry, rz + oz * f, T * f)
            if d > raw then raw = d end
            -- Less whatever is on you right now. Standing inside a beam, every
            -- line out starts inside the beam; counting that in full made every
            -- held box read as closed the moment it was chosen, and the choice
            -- re-rolled between the two sides each decision. What is already
            -- hitting you is no reason to prefer one way out over another -
            -- but time spent in it still is, so a residual stays in the
            -- average: three samples inside the ball cost more than one, and
            -- the nearest edge wins over the far one.
            local fresh = d - here0
            if fresh < 0 then fresh = 0 end
            local stale = d < here0 and d or here0
            total = total + fresh + stale * inside
            if fresh > worst then worst = fresh end
        end
        local cx, cz = rx + ox, rz + oz
        local d0 = dangerAt(cx, ry, cz, T)
        local d1 = dangerAt(cx, ry, cz, T + dwell * 0.5)
        local d2 = dangerAt(cx, ry, cz, T + dwell)
        total = total + d0 + d1 + d2
        if d0 > worst then worst = d0 end
        if d1 > worst then worst = d1 end
        if d2 > worst then worst = d2 end
        if d0 > raw then raw = d0 end
        if d1 > raw then raw = d1 end
        if d2 > raw then raw = d2 end
        return worst, worst * 0.5 + (total / (count + 3)) * 0.5, raw
    end

    -- Score every candidate. Cheap: it is arithmetic, no raycasts yet.
    local cands = DG.cands
    local distCost = CFG.dodgeDistanceCost
    for i, off in ipairs(DG.offsets) do
        local c = cands[i]
        if not c then c = {} cands[i] = c end
        local cx, cz = rx + off.x, rz + off.z
        local worst, graded, raw = score(off.x, off.z, off.dist)

        c.x, c.z, c.dist, c.danger = cx, cz, off.dist, worst
        local cost = graded + off.dist * distCost + hubCost(cx, cz)
        -- A change of direction costs; a reversal costs the most. Not while
        -- something is on you: then the shortest way out is the only way
        -- out, and keeping a heading was what walked the character round
        -- the inside of the ball instead of straight off its edge.
        if turnCost > 0 and here0 < 1 and (hx ~= 0 or hz ~= 0) then
            local dot = (off.x * hx + off.z * hz) / off.dist
            cost = cost + turnCost * (1 - dot) * 0.5 * (1 - here0)
        end
        -- The pull toward the target applies among SAFE spots only. Applied to
        -- every spot it was decisive in a crowded field where everything read
        -- much the same, and the nearest-to-the-boss won: that is the walk
        -- into the boss and the death at its feet.
        -- ...and among spots whose whole line is clean, undiscounted: from
        -- inside the ball the exit nearest the boss must not beat the exit
        -- nearest the edge.
        if approach then
            if raw < moveAt then
                cost = cost + approachCost(cx, cz)
            else
                cost = cost + approachWeight * CFG.dodgeReach * 2
            end
        end
        c.cost = cost
        c.valid = nil
        c.y = nil
    end

    -- Cheapest first, then pay for raycasts only until one passes.
    local order = DG.order
    for i = 1, #DG.offsets do order[i] = i end
    for i = #DG.offsets + 1, #order do order[i] = nil end
    table.sort(order, function(a, b) return cands[a].cost < cands[b].cost end)

    local params = DG.rayParams
    params.FilterDescendantsInstances = getRaycastExclusions(nil)

    local best, bestFallback = nil, nil
    local bestCost = math.huge
    local checked = 0
    for _, idx in ipairs(order) do
        local c = cands[idx]
        -- Costs only ever go UP from here (the corner penalty adds), so once
        -- the next candidate's base cost cannot beat the best adjusted cost
        -- already found, nothing after it can either.
        if best and c.cost >= bestCost then break end
        checked = checked + 1
        local y = floorAt(c.x, c.z, ry, params)
        -- Asymmetric, from the feet: a climb has to be within reach, a drop is
        -- allowed down to the drop limit.
        if y and (y - feetY) <= CFG.dodgeMaxClimb and (y - feetY) >= -CFG.dodgeMaxDrop then
            c.y = y
            if walkable(rootPos, c.x, y, c.z, params, aboveFloor) then
                c.valid = true
                -- Room beyond: a spot with a wall right behind it is a pocket.
                -- Continuing to flee from there is impossible, so it costs in
                -- proportion to how little room there is past it. This is what
                -- stops the character reversing into a corner or a prop and
                -- staying there.
                local dx, dz = c.x - rx, c.z - rz
                local len = sqrt(dx * dx + dz * dz)
                local adjusted = c.cost
                if len > 0.01 and CFG.dodgeCornerCost > 0 then
                    -- How much room is there PAST this spot - ahead, and to
                    -- each side? A spot with a wall behind it is a dead end;
                    -- one with walls beside it too is a pocket. Either is a
                    -- place the next dodge cannot start from, and the character
                    -- was sliding into exactly those and dying against them.
                    local ux, uz = dx / len, dz / len
                    local from = Vector3.new(c.x, y + 1.5, c.z)
                    local reach = CFG.dodgeReach
                    local pocket = 0
                    for _, probe in ipairs(DG.pocketProbes) do
                        local px2, pz2, weight = probe[1], probe[2], probe[3]
                        local dir = Vector3.new(ux * px2 - uz * pz2, 0, uz * px2 + ux * pz2)
                        local hit = Workspace:Raycast(from, dir * reach, params)
                        if hit then
                            local room = (hit.Position - from).Magnitude
                            pocket = pocket + weight * (1 - room / reach)
                        end
                    end
                    adjusted = adjusted + CFG.dodgeCornerCost * pocket
                end
                c.adjusted = adjusted
                if adjusted < bestCost then best, bestCost = c, adjusted end
            elseif not bestFallback then
                bestFallback = c
            end
        end
        -- The budget is a floor on effort, not a ceiling on safety: keep
        -- checking past it until something SAFE has passed, within reason.
        -- With a hard cut at twelve, a crowded field whose twelve cheapest
        -- spots all failed the floor or the wall check left nothing, and the
        -- blind fallback ran - which is the sprint toward the boss.
        if checked >= CFG.dodgeRayBudget and (best and best.danger < moveAt or checked >= 40) then break end
    end

    -- Nothing within reach is safe: look further, once. A wall of circles
    -- forty studs across cannot be left in eighteen, and the samples along a
    -- longer line are still taken at the moments they would happen, so
    -- crossing a fresh telegraph to reach open ground beyond it scores as
    -- exactly that. Only a far spot whose whole line reads clean is taken.
    if (not best or best.danger >= moveAt) and CFG.dodgeReachEscalate > 1 then
        local scale = CFG.dodgeReachEscalate
        local far = {}
        for _, off in ipairs(DG.offsets) do
            local sx, sz, sd = off.x * scale, off.z * scale, off.dist * scale
            if sd > CFG.dodgeReach then
                local worst, graded = score(sx, sz, sd)
                if worst < moveAt then
                    local cx, cz = rx + sx, rz + sz
                    local cost = graded + sd * distCost + hubCost(cx, cz)
                    if approach then cost = cost + approachCost(cx, cz) end
                    far[#far + 1] = { x = cx, z = cz, dist = sd, danger = worst, cost = cost }
                end
            end
        end
        table.sort(far, function(a, b) return a.cost < b.cost end)
        for i = 1, math.min(#far, CFG.dodgeRayBudget) do
            local c = far[i]
            local y = floorAt(c.x, c.z, ry, params)
            if y and (y - feetY) <= CFG.dodgeMaxClimb and (y - feetY) >= -CFG.dodgeMaxDrop
                and walkable(rootPos, c.x, y, c.z, params, aboveFloor) then
                c.y = y
                c.valid = true
                c.adjusted = c.cost
                best, bestCost = c, c.cost
                heavyDebugThrottled("dodge_far", 1.0, "Dodge",
                    string.format("Nothing safe within %.0f studs; going %.0f studs out.", CFG.dodgeReach, c.dist))
                break
            end
        end
    end

    -- Hysteresis, for a box whose LINE is still clear and only then. The old
    -- check re-read danger at the box and nowhere else, so an attack placed
    -- between the character and the box did not exist as far as the held box
    -- was concerned: the character walked its straight line into it while a
    -- step to either side was open. The bots that beat bullet hells commit to
    -- nothing - twinject re-picks its velocity every frame from scratch - so
    -- the box survives a decision only while every sample on the way to it
    -- and at it still passes. Otherwise it is dropped on the spot and the
    -- field is re-read, and the re-read prices the straight line, which is
    -- what puts the new box to the left or the right.
    local target = DG.target
    if target then
        local tx, tz = target.X - rx, target.Z - rz
        local d = sqrt(tx * tx + tz * tz)
        local worst, graded = score(tx, tz, d)
        if worst >= CFG.dodgeMoveAt then
            DG.target = nil
            target = nil
            DG.targetReason = "line closed"
        elseif best then
            local stillCost = graded + d * distCost + hubCost(target.X, target.Z)
            if approach then stillCost = stillCost + approachCost(target.X, target.Z) end
            if (best.adjusted or best.cost) > stillCost - CFG.dodgeHysteresis then
                best = nil    -- the current box wins
            end
        end
    end

    if DG.dangerHere < CFG.dodgeMoveAt then
        -- Here is safe. Stay if there is no one to close on, or we are already
        -- in range of them - otherwise let the box drift toward them, but ONLY
        -- onto a spot that is itself safe. A pattern with no safe way forward
        -- means waiting here, which is what a person does in a bullet hell.
        local inRange = true
        if approach then
            local ax, az = rx - approach.X, rz - approach.Z
            local d = sqrt(ax * ax + az * az)
            inRange = hold and abs(d - preferred) <= 2.5 or (not hold and d <= preferred + 1.5)
        end
        if inRange then
            DG.target = nil
            DG.targetReason = DG.hubHold and "safe here (hub, holding out)" or "safe here"
            return
        end
        -- A held box that just won the hysteresis stays held; dropping it here
        -- was what made the approach creep a stud at a time.
        if target and not best then return end
        if not best or best.danger >= CFG.dodgeMoveAt then
            DG.target = nil
            DG.targetReason = "waiting for a gap"
            DG.gapWait = true
            return
        end
        -- Hysteresis for the approach too, or the box creeps a stud at a time.
        local hereCost = hubCost(rx, rz)
        if approach then hereCost = hereCost + approachCost(rx, rz) end
        if (best.adjusted or best.cost) > hereCost - CFG.dodgeHysteresis then
            DG.target = nil
            DG.targetReason = "safe here"
            return
        end
    end

    local function commit(x, y, z)
        DG.target = Vector3.new(x, y, z)
        local v = Vector3.new(x - rx, 0, z - rz)
        if v.Magnitude > 0.5 then
            DG.heading = v.Unit
            DG.headingTime = os.clock()
        end
    end
    if best then
        commit(best.x, best.y, best.z)
        DG.targetReason = string.format("danger %.2f, %.0f studs", best.danger, best.dist)
    elseif not DG.target then
        if bestFallback then
            -- Every clear line is worse than a walled one. Take the walled one
            -- and let the humanoid slide along the wall rather than stand in it.
            commit(bestFallback.x, bestFallback.y, bestFallback.z)
            DG.targetReason = "walled, sliding"
        else
            -- Nothing has a floor. Away from the NEAREST enemy, blindly. This
            -- used to take the first enemy in the table - whichever that was -
            -- and read fields the entries do not have, so it errored.
            local away = Vector3.new(0, 0, 1)
            local nearest, nd = nil, math.huge
            for i = 1, #DG.enemies do
                local e = DG.enemies[i]
                local dx, dz = rx - e.x, rz - e.z
                local d2 = dx * dx + dz * dz
                if d2 < nd then nearest, nd = e, d2 end
            end
            if nearest and nd > 0.01 then away = Vector3.new(rx - nearest.x, 0, rz - nearest.z).Unit end
            local t = rootPos + away * CFG.dodgeReach
            commit(t.X, t.Y, t.Z)
            DG.targetReason = "blind"
            heavyDebugThrottled("dodge_blind", 1.0, "Dodge", "No candidate with a floor; running blind.")
        end
    end
end

-- ------------------------------------------------------------ visuals
local function destroyVisuals()
    if DG.folder then DG.folder:Destroy() end
    DG.folder, DG.box, DG.ring, DG.discs = nil, nil, nil, {}
end

local function buildVisuals()
    destroyVisuals()
    local folder = Instance.new("Folder")
    folder.Name = "Dodge"
    folder.Parent = getVisualRoot()
    DG.folder = folder

    local _, rootRadius, totalHeight = getPlayerHitboxMetrics()
    local box = Instance.new("Part")
    box.Name = "Target"
    box.Size = Vector3.new(rootRadius * 2, totalHeight, rootRadius * 2)
    box.Anchored, box.CanCollide, box.CanQuery, box.CanTouch, box.CastShadow = true, false, false, false, false
    box.Material = Enum.Material.Neon
    box.Color = CFG.colorDodgeTarget
    box.Transparency = 1
    box.Parent = folder
    DG.box = box

    -- The search range: the ring the outer candidates sit on. Seeing it is
    -- how you tell "it could not find anywhere" from "it was not looking far
    -- enough".
    local ring = Instance.new("Part")
    ring.Name = "Range"
    ring.Shape = Enum.PartType.Cylinder
    ring.Size = Vector3.new(0.08, CFG.dodgeReach * 2, CFG.dodgeReach * 2)
    ring.Anchored, ring.CanCollide, ring.CanQuery, ring.CanTouch, ring.CastShadow = true, false, false, false, false
    ring.Material = Enum.Material.ForceField
    ring.Color = CFG.colorDodgeTarget
    ring.Transparency = 1
    ring.Parent = folder
    DG.ring = ring

    DG.discs = {}
    for i = 1, #DG.offsets do
        local d = Instance.new("Part")
        d.Name = "C" .. i
        d.Shape = Enum.PartType.Cylinder
        d.Size = Vector3.new(0.15, 1.4, 1.4)
        d.Anchored, d.CanCollide, d.CanQuery, d.CanTouch, d.CastShadow = true, false, false, false, false
        d.Material = Enum.Material.Neon
        d.Transparency = 1
        d.Parent = folder
        DG.discs[i] = d
    end
end

local UPRIGHT = CFrame.Angles(0, 0, math.rad(90))

local function paint(root)
    if not DG.folder or not DG.folder.Parent then return end
    local box = DG.box
    if box then
        if CFG.dodgeShowTarget and DG.target then
            box.CFrame = CFrame.new(DG.target + Vector3.new(0, box.Size.Y * 0.5 - 2.5, 0))
            box.Transparency = 0.35
        else
            box.Transparency = 1
        end
    end
    local ring = DG.ring
    if ring and ring.Parent then
        if CFG.dodgeShowRange then
            local want = CFG.dodgeReach * 2
            if abs(ring.Size.Y - want) > 0.01 then ring.Size = Vector3.new(0.08, want, want) end
            ring.CFrame = CFrame.new(root.Position.X, root.Position.Y - 2.4, root.Position.Z) * UPRIGHT
            ring.Transparency = 0.82
        else
            ring.Transparency = 1
        end
    end
    if #DG.discs ~= #DG.offsets then buildVisuals() end
    local show = CFG.dodgeShowField
    local safe, danger = CFG.colorDodgeSafe, CFG.colorDodgeDanger
    for i, disc in ipairs(DG.discs) do
        local c = DG.cands[i]
        if not show or not c or not c.y then
            if disc.Transparency ~= 1 then disc.Transparency = 1 end
        else
            local t = min(c.danger, 1)
            local color = t < 0.5 and safe:Lerp(Color3.fromRGB(255, 220, 60), t * 2)
                or Color3.fromRGB(255, 220, 60):Lerp(danger, (t - 0.5) * 2)
            disc.CFrame = CFrame.new(c.x, c.y + 0.15, c.z) * UPRIGHT
            disc.Color = color
            disc.Transparency = 0.45
        end
    end
end

-- Is a step from here toward `to` clear? Pursuit asks before it moves. The
-- dodge decides twenty times a second, but a MoveTo issued between two
-- decisions can still put a foot into something the next decision would have
-- refused, and pursuit is the one thing that walks TOWARD attacks. Only the
-- next few studs are checked: further than that is the box's business.
local function stepClear(root, humanoid, to)
    if not DG.active or not CFG.dodgeEnabled or not DG.reach then return true end
    local rp = root.Position
    local dx, dz = to.X - rp.X, to.Z - rp.Z
    local len = sqrt(dx * dx + dz * dz)
    if len < 0.1 then return true end
    local step = min(len, CFG.dodgeStepProbe)
    local ux, uz = dx / len * step, dz / len * step
    local T = step / max(humanoid.WalkSpeed, 4)
    local d = max(
        dangerAt(rp.X + ux * 0.5, rp.Y, rp.Z + uz * 0.5, T * 0.5),
        dangerAt(rp.X + ux, rp.Y, rp.Z + uz, T),
        dangerAt(rp.X + ux, rp.Y, rp.Z + uz, T + CFG.dodgeDwell * 0.5),
        dangerAt(rp.X + ux, rp.Y, rp.Z + uz, T + CFG.dodgeDwell))
    return d < CFG.dodgeMoveAt
end

-- ------------------------------------------------------------ entry points
local function setDodgeActive(active)
    DG.active = active
    DG.target = nil
    DG.pursuitBlocked = false
    if active then
        buildOffsets()
        buildVisuals()
        DG.rayParams = RaycastParams.new()
        DG.rayParams.FilterType = Enum.RaycastFilterType.Exclude
        pcall(function() DG.rayParams.RespectCanCollide = true end)
        heavyDebug("Dodge", string.format("Dodge on: %d points across %d rings, reaching %.0f studs.",
            #DG.offsets, CFG.dodgeRings, CFG.dodgeReach))
    else
        destroyVisuals()
        heavyDebug("Dodge", "Dodge off.")
    end
end

-- Every frame while active. Decides on its own clock; paints when it did.
local function dodgeStep(root, humanoid)
    if not DG.active or not humanoid then return end
    local now = os.clock()
    if now - DG.lastDecision >= CFG.dodgeInterval then
        DG.lastDecision = now
        decide(root, humanoid)
        paint(root)
    end
end

-- Called by the main loop when DG.dangerHere says to move. Drives the
-- character at the box. Returns true while it is in charge.
local function runDodge(humanoid, root)
    if not DG.active then return false end
    local target = DG.target
    if not target then
        releaseMover(humanoid, root)
        return false
    end
    releaseFacing(humanoid)
    local arrived = driveTo(humanoid, root, target)
    -- The mover is named in the status so "is it tweening?" is answered by
    -- looking, not by guessing from how it moves.
    if arrived then
        DG.target = nil
        releaseMover(humanoid, root)
        setMovementState("DODGE arrived [" .. tostring(CFG.moveMode) .. "]")
    else
        setMovementState("DODGE " .. tostring(DG.targetReason) .. " [" .. tostring(CFG.moveMode) .. "]")
    end
    return true
end

S.setDodgeActive = setDodgeActive
S.buildDodgeVisuals = buildVisuals
S.dodgeStep = dodgeStep
S.runDodge = runDodge
S.dodgeDangerAt = dangerAt
S.dodgeStepClear = stepClear
end
