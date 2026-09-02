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

                -- Big bosses reach well past their root. The circle grows with
                -- the body so a stomping leg counts; ordinary mobs add nothing.
                local ext = DG.enemyExt[model]
                if not ext or clock - ext.t > 0.5 then
                    local extra = 0
                    local ok, size = pcall(function() return model:GetExtentsSize() end)
                    if ok and size then extra = min(max(max(size.X, size.Z) * 0.5 - 3, 0), 20) end
                    ext = { r = extra, t = clock }
                    DG.enemyExt[model] = ext
                end

                DG.enemies[#DG.enemies + 1] = {
                    x = pos.X, y = pos.Y, z = pos.Z, vx = vx, vz = vz, extra = ext.r,
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

    -- 1. Announced ground attacks: exact shape, exact time. A zone hurts from
    -- `lead` seconds before it lands until `linger` after. Before that it is
    -- floor you may cross; that is the entire value of knowing the timing.
    local now = DG.now
    for i = 1, #PC.zones do
        local zone = PC.zones[i]
        local eta = zone.impactAt - now
        if t >= eta - CFG.dodgeLead and t <= eta + CFG.dodgeLinger then
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

    -- 2. Physical hazards already in the world. They are live now, so time
    -- does not enter into it - except that the moving ones are handled below
    -- as the line they sweep rather than the point they occupy.
    local point = Vector3.new(px, py, pz)
    for i = 1, #HZ.volumes do
        local volume = HZ.volumes[i]
        local part = volume.part
        if (not part or part.Parent) and not (part and DG.moverSet[part]) then
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

    -- 4. Enemies, at time t - where an advancing one will be, not where it is.
    -- Melee never telegraphs: being next to one is the attack.
    local hard0, soft0 = CFG.dodgeEnemyRadius, CFG.dodgeEnemySoft
    for i = 1, #DG.enemies do
        local e = DG.enemies[i]
        local hard = hard0 + e.extra
        local soft = max(soft0 + e.extra, hard + 0.1)
        local dx, dz = px - (e.x + e.vx * t), pz - (e.z + e.vz * t)
        local d2 = dx * dx + dz * dz
        if d2 < soft * soft then
            local d = sqrt(d2)
            if d < hard then return 1 end
            worst = max(worst, CFG.dodgeEnemySoftWeight * (1 - (d - hard) / (soft - hard)))
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
    local result = Workspace:Raycast(Vector3.new(x, rootY + 4, z), Vector3.new(0, -(4 + CFG.dodgeMaxDrop), 0), params)
    local y = result and result.Position.Y or false
    DG.floorCache[key] = { y = y, t = now }
    DG.floorCacheSize = DG.floorCacheSize + 1
    if DG.floorCacheSize > 3000 then table.clear(DG.floorCache) DG.floorCacheSize = 0 end
    return y
end

-- Is the straight walk from the character to (x, z) clear of solid geometry?
local function walkable(rootPos, x, y, z, params)
    local from = Vector3.new(rootPos.X, rootPos.Y, rootPos.Z)
    local to = Vector3.new(x, y + 1.5, z)
    local hit = Workspace:Raycast(from, to - from, params)
    return hit == nil
end

-- The decision. Fills DG.dangerHere and DG.target.
local function decide(root, humanoid)
    if DG.offsetsKey ~= string.format("%d/%d/%.1f", max(floor(CFG.dodgeRings), 1),
        max(floor(CFG.dodgeRays), 6), CFG.dodgeReach) then buildOffsets() end

    refreshSources()

    local rootPos = root.Position
    local rx, ry, rz = rootPos.X, rootPos.Y, rootPos.Z
    local speed = max(humanoid.WalkSpeed, 4)
    local dwell = CFG.dodgeDwell

    -- Here: now, and a moment from now. Standing still is a decision too.
    DG.dangerHere = max(dangerAt(rx, ry, rz, 0), dangerAt(rx, ry, rz, dwell * 0.5), dangerAt(rx, ry, rz, dwell))

    -- Who we are trying to get to, if anyone. The box drifts toward them
    -- through safe ground and holds still when there is none: that is the
    -- whole of "approach" now, and pursuit no longer moves the character in
    -- this mode.
    -- Near the target, the box is the approach: the last stretch through a
    -- pattern is crossed one safe spot at a time. Far from it, pursuit walks
    -- the map and the box fires only for danger - unless pursuit is stopped at
    -- the edge of something, in which case the box picks the way in.
    local approach = nil
    if RT.farmEnabled and not CFG.dodgeManual and NAV.cachedEnemy and NAV.cachedEnemy.Parent then
        local er = NAV.cachedEnemy:FindFirstChild("HumanoidRootPart") or NAV.cachedEnemy.PrimaryPart
        if er then
            local p = er.Position
            local ax, az = p.X - rx, p.Z - rz
            local near = CFG.dodgeReach * 1.5
            if ax * ax + az * az <= near * near or DG.pursuitBlocked then approach = p end
        end
    end
    local preferred = max(CFG.attackRange, CFG.dodgeEnemyRadius + 1)
    local approachWeight = CFG.dodgeApproachWeight
    local fractions = DG.pathFractions

    -- Five samples along the line from here to (rx+ox, rz+oz): three on the
    -- way, two once there, each at the moment it would actually happen. The
    -- score is half the worst of them and half the average - a spot hit at one
    -- moment on the way is not as bad as one hit at every moment, and in a
    -- field where everything is hit at SOME moment that difference is the
    -- only gradient there is. Pure max made every candidate in a bullet hell
    -- read exactly 1.0 and the nearest won. Returns worst, graded.
    local function score(ox, oz, dist)
        local T = dist / speed
        local worst, total = 0, 0
        for k = 1, #fractions do
            local f = fractions[k]
            local d = dangerAt(rx + ox * f, ry, rz + oz * f, T * f)
            total = total + d
            if d > worst then worst = d end
        end
        local cx, cz = rx + ox, rz + oz
        local d1 = dangerAt(cx, ry, cz, T + dwell * 0.5)
        local d2 = dangerAt(cx, ry, cz, T + dwell)
        total = total + d1 + d2
        if d1 > worst then worst = d1 end
        if d2 > worst then worst = d2 end
        return worst, worst * 0.5 + (total / (#fractions + 2)) * 0.5
    end

    -- Score every candidate. Cheap: it is arithmetic, no raycasts yet.
    local cands = DG.cands
    local distCost = CFG.dodgeDistanceCost
    for i, off in ipairs(DG.offsets) do
        local c = cands[i]
        if not c then c = {} cands[i] = c end
        local cx, cz = rx + off.x, rz + off.z
        local worst, graded = score(off.x, off.z, off.dist)

        c.x, c.z, c.dist, c.danger = cx, cz, off.dist, worst
        c.cost = graded + off.dist * distCost
        if approach then
            local ax, az = cx - approach.X, cz - approach.Z
            local toEnemy = sqrt(ax * ax + az * az)
            c.cost = c.cost + approachWeight * max(0, toEnemy - preferred)
        end
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
        if y and abs(y - ry) <= CFG.dodgeMaxClimb + 0.1 and y > ry - CFG.dodgeMaxDrop then
            c.y = y
            if walkable(rootPos, c.x, y, c.z, params) then
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
        if checked >= CFG.dodgeRayBudget then break end
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
            local stillCost = graded + d * distCost
            if approach then
                local ax, az = target.X - approach.X, target.Z - approach.Z
                stillCost = stillCost + approachWeight * max(0, sqrt(ax * ax + az * az) - preferred)
            end
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
            inRange = sqrt(ax * ax + az * az) <= preferred + 1.5
        end
        if inRange then
            DG.target = nil
            DG.targetReason = "safe here"
            return
        end
        -- A held box that just won the hysteresis stays held; dropping it here
        -- was what made the approach creep a stud at a time.
        if target and not best then return end
        if not best or best.danger >= CFG.dodgeMoveAt then
            DG.target = nil
            DG.targetReason = "waiting for a gap"
            return
        end
        -- Hysteresis for the approach too, or the box creeps a stud at a time.
        local hereCost = 0
        if approach then
            local ax, az = rx - approach.X, rz - approach.Z
            hereCost = approachWeight * max(0, sqrt(ax * ax + az * az) - preferred)
        end
        if (best.adjusted or best.cost) > hereCost - CFG.dodgeHysteresis then
            DG.target = nil
            DG.targetReason = "safe here"
            return
        end
    end

    if best then
        DG.target = Vector3.new(best.x, best.y, best.z)
        DG.targetReason = string.format("danger %.2f, %.0f studs", best.danger, best.dist)
    elseif not DG.target then
        if bestFallback then
            -- Every clear line is worse than a walled one. Take the walled one
            -- and let the humanoid slide along the wall rather than stand in it.
            DG.target = Vector3.new(bestFallback.x, bestFallback.y, bestFallback.z)
            DG.targetReason = "walled, sliding"
        else
            -- Nothing has a floor. Away from the nearest enemy, blindly.
            local away = Vector3.new(0, 0, 1)
            if #DG.enemies > 0 then
                local e = DG.enemies[1]
                local v = Vector3.new(rx - e.X, 0, rz - e.Z)
                if v.Magnitude > 0.1 then away = v.Unit end
            end
            DG.target = rootPos + away * CFG.dodgeReach
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
            local t = c.danger
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
        dangerAt(rp.X + ux, rp.Y, rp.Z + uz, T + CFG.dodgeDwell * 0.5))
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
