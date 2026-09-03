-- field.lua - Where is safe, when, and which nearby spot to be on.
-- Module contract: receives the shared table S; imports from core and reader.
--
-- dangerAt(x, y, z, t): 1 inside a hazard live at time t, fading over a
-- shoulder outside it, 0 clear. A telegraphed box counts as live `dodgeLead`
-- before it fires; a moving box counts as live `dodgePathLead` before it
-- arrives. Melee mobs are hazards too.
--
-- decide(): scores a ring of spots around the character. Each spot's line is
-- sampled at the moments it would be crossed. Danger already on you is
-- discounted only until the ground under you fires (grace); after that,
-- time inside is the hit. Nothing safe within reach: one wider look.
return function(S)
local CFG = S.CFG
local RT = S.RT
local RD = S.RD
local hazards = S.hazards
local Workspace = S.Workspace
local raycastParams = S.raycastParams
local floorY = S.floorY
local heavyDebugThrottled = S.heavyDebugThrottled

local DG = {
    target = nil,           -- Vector3 to go to, or nil (here is fine)
    reason = "",
    dangerHere = 0,
    grace = math.huge,
    lastDecision = -math.huge,
    offsets = {},
    cands = {},
    heading = nil, headingAt = -math.huge,
    boxes = {},
    reach = 2.0,
    halfHeight = 5,
    approach = nil,         -- { x, z, standoff } from the brain
    approachIsBoss = false,
}

local sqrt, abs, max, min, cos, sin, pi = math.sqrt, math.abs, math.max, math.min, math.cos, math.sin, math.pi

local function buildOffsets()
    table.clear(DG.offsets)
    local rings, rays = max(CFG.dodgeRings, 1), max(CFG.dodgeRays, 6)
    for ring = 1, rings do
        local r = CFG.dodgeReach * ring / rings
        local phase = (ring % 2 == 0) and pi / rays or 0
        for i = 0, rays - 1 do
            local a = phase + i / rays * 2 * pi
            DG.offsets[#DG.offsets + 1] = { x = cos(a) * r, z = sin(a) * r, dist = r }
        end
    end
end

-- Depth of a point inside an oriented box (negative outside, distance to the
-- surface in the flat plane), and whether it is at the right height.
local function boxDepth(cf, size, px, py, pz, halfHeight)
    local lp = cf:PointToObjectSpace(Vector3.new(px, py, pz))
    if abs(lp.Y) > size.Y * 0.5 + halfHeight then return -math.huge end
    local ox, oz = abs(lp.X) - size.X * 0.5, abs(lp.Z) - size.Z * 0.5
    if ox <= 0 and oz <= 0 then return -max(ox, oz) end   -- inside: positive depth
    return -sqrt(max(ox, 0) ^ 2 + max(oz, 0) ^ 2)         -- outside: negative distance
end
-- A cylinder Part lies along its X axis; its round face spans Y/Z.
local function cylDepth(cf, size, px, py, pz, halfHeight)
    local lp = cf:PointToObjectSpace(Vector3.new(px, py, pz))
    local r = size.Y * 0.5
    if abs(lp.X) > size.X * 0.5 + halfHeight then return -math.huge end
    return r - sqrt(lp.Y * lp.Y + lp.Z * lp.Z)
end

local function dangerFromDepth(depth, reach, shoulder)
    -- depth > 0 inside; the character's own radius counts.
    local d = depth + reach
    if d >= 0 then return 1 end
    if -d < shoulder then return 1 + d / shoulder end
    return 0
end

local function dangerAt(px, py, pz, t)
    local reach, halfHeight, shoulder = DG.reach, DG.halfHeight, CFG.dodgeShoulder
    local now = DG.now
    local at = now + t
    local worst = 0
    for i = 1, #DG.boxes do
        local b = DG.boxes[i]
        local lead = b.moving and CFG.dodgePathLead or (b.telegraphed and CFG.dodgeLead or (b.from > now and CFG.dodgeLead or 0))
        if at >= b.from - lead and at <= b.untilAt then
            local depth
            if b.moving then
                -- Where the body is at time `at`, along its line.
                local along = b.offset + b.speed * max(at - b.pathStart, 0)
                local cx, cz = b.ox + b.dx * along, b.oz + b.dz * along
                if abs(py - b.oy) <= b.halfH + halfHeight then
                    local qx, qz = px - cx, pz - cz
                    local a = abs(qx * b.dx + qz * b.dz) - b.halfL
                    local s = abs(-qx * b.dz + qz * b.dx) - b.halfW
                    depth = (a <= 0 and s <= 0) and -max(a, s) or -sqrt(max(a, 0) ^ 2 + max(s, 0) ^ 2)
                else
                    depth = -math.huge
                end
            elseif b.cyl then
                depth = cylDepth(b.cframe, b.size, px, py, pz, halfHeight)
            elseif b.round then
                local c = b.cframe.Position
                if abs(py - c.Y) <= b.size.Y * 0.5 + halfHeight then
                    depth = b.size.X * 0.5 - sqrt((px - c.X) ^ 2 + (pz - c.Z) ^ 2)
                else
                    depth = -math.huge
                end
            else
                depth = boxDepth(b.cframe, b.size, px, py, pz, halfHeight)
            end
            local d = dangerFromDepth(depth, reach, shoulder)
            if d > worst then worst = d if worst >= 1 then return 1 end end
        end
    end
    -- Melee mobs: being next to one is the attack.
    for i = 1, #RD.enemies do
        local e = RD.enemies[i]
        if e.melee and not e.isBoss then
            local tt = min(t, 0.6)
            local dx, dz = px - (e.x + e.vx * tt), pz - (e.z + e.vz * tt)
            local d = sqrt(dx * dx + dz * dz) - (e.extent + e.meleeDistance + CFG.meleeBuffer)
            local v = dangerFromDepth(-d, reach, shoulder * 2)
            if v > worst then worst = v if worst >= 1 then return 1 end end
        end
    end
    return worst
end

-- Seconds until the ground under the character fires: the soonest live-from
-- among boxes covering it, zero if one is already live, huge if none.
local function graceHere(px, py, pz)
    local now = DG.now
    local grace = math.huge
    for i = 1, #DG.boxes do
        local b = DG.boxes[i]
        if not b.moving and now <= b.untilAt then
            local depth
            if b.cyl then depth = cylDepth(b.cframe, b.size, px, py, pz, DG.halfHeight)
            elseif b.round then
                local c = b.cframe.Position
                depth = (abs(py - c.Y) <= b.size.Y * 0.5 + DG.halfHeight) and (b.size.X * 0.5 - sqrt((px - c.X) ^ 2 + (pz - c.Z) ^ 2)) or -math.huge
            else depth = boxDepth(b.cframe, b.size, px, py, pz, DG.halfHeight) end
            if depth + DG.reach >= 0 then
                local eta = max(b.from - now, 0)
                if eta < grace then grace = eta end
            end
        end
    end
    return grace
end

local function walkable(fromPos, x, y, z, params)
    -- A sweep of a slab the character's size from here to there: anything solid
    -- in the way and the spot is behind a wall.
    local to = Vector3.new(x, y + 2.5, z)
    local from = Vector3.new(fromPos.X, fromPos.Y, fromPos.Z)
    local hit = Workspace:Blockcast(CFrame.new(from), Vector3.new(2.5, 4.5, 2.5), to - from, params)
    return hit == nil
end

local function decide(root, hum)
    local now = os.clock()
    DG.now = now
    DG.boxes = hazards(now)
    DG.reach = root.Size.X * 0.5 + CFG.dodgeMargin
    DG.halfHeight = (hum.HipHeight + root.Size.Y) * 0.5 + 2.5
    if #DG.offsets == 0 or DG.offsetsKey ~= CFG.dodgeReach .. "/" .. CFG.dodgeRings .. "/" .. CFG.dodgeRays then
        buildOffsets()
        DG.offsetsKey = CFG.dodgeReach .. "/" .. CFG.dodgeRings .. "/" .. CFG.dodgeRays
    end
    local rp = root.Position
    local rx, ry, rz = rp.X, rp.Y, rp.Z
    local dwell = CFG.dodgeDwell
    local here0 = dangerAt(rx, ry, rz, 0)
    DG.here0 = here0
    DG.dangerHere = max(here0, dangerAt(rx, ry, rz, dwell * 0.5), dangerAt(rx, ry, rz, dwell))
    RT.moveBoost = here0 >= CFG.dodgeMoveAt
    local speed = RT.moveBoost and CFG.tweenEscape or CFG.tweenWalk
    local grace = here0 > 0 and graceHere(rx, ry, rz) or math.huge
    DG.grace = grace
    local moveAt = CFG.dodgeMoveAt

    -- Preferences: keep the heading we last took (no left-right shuffle), move
    -- across the target's line rather than along it (strafe), and stay in the
    -- standoff band around the target.
    local hx, hz = 0, 0
    if DG.heading and now - DG.headingAt < 1.0 then hx, hz = DG.heading.X, DG.heading.Z end
    local ap = DG.approach
    local ax, az, adist = 0, 0, 0
    if ap then
        ax, az = ap.x - rx, ap.z - rz
        adist = sqrt(ax * ax + az * az)
        if adist > 0.01 then ax, az = ax / adist, az / adist end
    end

    local function score(ox, oz, dist)
        local T = dist / speed
        local worst, total, n = 0, 0, 0
        local steps = max(2, min(8, math.ceil(dist / 2.5)))
        for k = 1, steps - 1 do
            local f = k / steps
            local d = dangerAt(rx + ox * f, ry, rz + oz * f, T * f)
            local fresh = (T * f < grace) and (d - here0) or d
            if fresh < 0 then fresh = 0 end
            local stale = d < here0 and d or here0
            total = total + fresh + stale * CFG.dodgeInsideWeight
            if fresh > worst then worst = fresh end
            n = n + 1
        end
        local cx, cz = rx + ox, rz + oz
        for _, extra in ipairs({ 0, dwell * 0.5, dwell }) do
            local d = dangerAt(cx, ry, cz, T + extra)
            total = total + d
            if d > worst then worst = d end
            n = n + 1
        end
        return worst, worst * 0.5 + (total / n) * 0.5
    end

    local function costOf(ox, oz, dist, graded)
        local cost = graded + dist * CFG.dodgeDistanceCost
        if (hx ~= 0 or hz ~= 0) and here0 < 1 then
            local dot = (ox * hx + oz * hz) / dist
            cost = cost + 0.05 * (1 - dot) * 0.5
        end
        -- Standing in danger with a target: prefer backing away from it. A
        -- spot behind you is the one that is not in the next attack.
        if ap and here0 >= CFG.dodgeMoveAt and adist > 1 then
            local toward = (ox * ax + oz * az) / dist
            cost = cost + CFG.dodgeOutwardWeight * (toward + 1) * 0.5
        end
        -- The pull toward the target's band applies at every distance: in a
        -- field of attacks the spot outranks travel, so the spots themselves
        -- must carry the approach (5.1.0 reached the Champion this way; a pull
        -- limited to the last thirty studs left it hopping at the entrance).
        -- Weaker far out, so a safe spot still beats a closer risky one.
        if ap then
            local cx, cz = rx + ox, rz + oz
            local dxa, dza = cx - ap.x, cz - ap.z
            local dd = sqrt(dxa * dxa + dza * dza)
            local band = ap.standoff
            local outBy = max(dd - (band + 3), (band - 3) - dd, 0)
            local near = adist < band + 30
            cost = cost + CFG.dodgeApproachWeight * (near and 1 or 0.6) * outBy
            -- Inside the last stretch, moving across the line to the target is
            -- preferred to moving along it.
            if near and CFG.strafe and adist > 1 then
                local radial = abs((ox * ax + oz * az) / dist)
                cost = cost + CFG.dodgeStrafeWeight * radial
            end
        end
        return cost
    end

    local params = raycastParams(nil)
    local cands = DG.cands
    table.clear(cands)
    local function evaluate(scale)
        for _, off in ipairs(DG.offsets) do
            local ox, oz, dist = off.x * scale, off.z * scale, off.dist * scale
            local worst, graded = score(ox, oz, dist)
            cands[#cands + 1] = { ox = ox, oz = oz, dist = dist, danger = worst, cost = costOf(ox, oz, dist, graded) }
        end
        table.sort(cands, function(a, b) return a.cost < b.cost end)
        local best, checked = nil, 0
        for _, c in ipairs(cands) do
            if best and c.cost >= best.cost then break end
            checked = checked + 1
            local x, z = rx + c.ox, rz + c.oz
            local y = floorY(x, ry, z, params)
            if y and y - (ry - DG.halfHeight) <= CFG.maxStepHeight + 3 and y >= ry - CFG.maxDropHeight then
                if walkable(rp, x, y, z, params) then
                    c.x, c.y, c.z, c.valid = x, y, z, true
                    if not best or c.cost < best.cost then best = c end
                end
            end
            if checked >= 14 and best and best.danger < moveAt then break end
            if checked >= 40 then break end
        end
        return best
    end

    local best = evaluate(1)
    for _, scale in ipairs({ CFG.dodgeFarScale, CFG.dodgeFarScale2 }) do
        if best and best.danger < moveAt then break end
        if scale and scale > 1 then
            table.clear(cands)
            local far = evaluate(scale)
            if far and (not best or far.danger < best.danger) then best = far end
        end
    end

    -- Keep the current spot while its line stays clean and nothing beats it
    -- clearly; drop it the moment its line closes.
    local target = DG.target
    if target then
        local tx, tz = target.X - rx, target.Z - rz
        local d = sqrt(tx * tx + tz * tz)
        if d < 1.2 then
            target = nil
            DG.target = nil
        else
            local worst, graded = score(tx, tz, d)
            if worst >= moveAt then
                target = nil
                DG.target = nil
                DG.reason = "line closed"
            elseif here0 >= moveAt then
                -- Escaping: the spot is kept until reached or its line closes.
                -- Re-picking between two near-equal spots each tick was the
                -- shuttle between two attacks.
                return
            elseif best then
                local stillCost = costOf(tx, tz, d, graded)
                if best.cost > stillCost - CFG.dodgeHysteresis then return end
            end
        end
    end

    if DG.dangerHere < moveAt then
        -- Here is safe. Move only for a reason: out of the band, or a clearly
        -- better spot toward the target.
        if not best or best.danger >= moveAt then
            DG.target = nil
            DG.reason = "waiting for a gap"
            return
        end
        local hereCost = costOf(0, 0, 0.001, 0)
        if best.cost > hereCost - CFG.dodgeHysteresis then
            DG.target = nil
            DG.reason = "safe here"
            return
        end
    end

    if best then
        DG.target = Vector3.new(best.x, best.y, best.z)
        local v = Vector3.new(best.ox, 0, best.oz)
        if v.Magnitude > 0.5 then DG.heading, DG.headingAt = v.Unit, now end
        DG.reason = string.format("danger %.2f, %.0f studs", best.danger, best.dist)
    elseif not DG.target then
        -- Nothing with a floor: away from the nearest enemy, blindly.
        local nearest, nd = nil, math.huge
        for _, e in ipairs(RD.enemies) do
            local dx, dz = rx - e.x, rz - e.z
            local d2 = dx * dx + dz * dz
            if d2 < nd then nearest, nd = e, d2 end
        end
        local away = nearest and Vector3.new(rx - nearest.x, 0, rz - nearest.z).Unit or Vector3.new(0, 0, 1)
        DG.target = rp + away * CFG.dodgeReach
        DG.reason = "blind"
        heavyDebugThrottled("blind", 1, "Field", "no candidate with a floor")
    end
end

S.DG = DG
S.dangerAt = dangerAt
S.decide = decide
end
