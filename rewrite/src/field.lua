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
-- Orientation-aware: whichever local axis points up is the height, the
-- other two are the footprint. A hitbox stood on end (its 63-stud length
-- vertical) used to be read as a 63-stud-wide floor box.
local function boxDepth(cf, size, px, py, pz, halfHeight)
    local lp = cf:PointToObjectSpace(Vector3.new(px, py, pz))
    local ux, uy, uz = abs(cf.RightVector.Y), abs(cf.UpVector.Y), abs(cf.LookVector.Y)
    local a, b, h, ha, hb
    if uy >= ux and uy >= uz then
        a, b, h, ha, hb = lp.X, lp.Z, lp.Y, size.X, size.Z
        if abs(h) > size.Y * 0.5 + halfHeight then return -math.huge end
    elseif ux >= uz then
        a, b, h, ha, hb = lp.Y, lp.Z, lp.X, size.Y, size.Z
        if abs(h) > size.X * 0.5 + halfHeight then return -math.huge end
    else
        a, b, h, ha, hb = lp.X, lp.Y, lp.Z, size.X, size.Y
        if abs(h) > size.Z * 0.5 + halfHeight then return -math.huge end
    end
    local oa, ob = abs(a) - ha * 0.5, abs(b) - hb * 0.5
    if oa <= 0 and ob <= 0 then return -max(oa, ob) end   -- inside: positive depth
    return -sqrt(max(oa, 0) ^ 2 + max(ob, 0) ^ 2)         -- outside: negative distance
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

-- `reachO` / `shoulderO` override the padding: the blink asks the bare
-- question (is this point inside a box, body radius only), not the graded one.
local function dangerAt(px, py, pz, t, reachO, shoulderO)
    local reach, halfHeight, shoulder = reachO or DG.reach, DG.halfHeight, shoulderO or CFG.dodgeShoulder
    local now = DG.now
    local at = now + t
    local worst = 0
    for i = 1, #DG.boxes do
        local b = DG.boxes[i]
        -- A moving body is real from the moment it is announced: the aimed
        -- criss cross sits on the player until its start time and hurts there,
        -- and the big spike's front is already on its way. Static zones fire at
        -- `from`, so they matter from `lead` seconds before.
        local live
        if b.moving then
            live = at <= b.untilAt
        else
            local lead = b.telegraphed and CFG.dodgeLead or (b.from > now and CFG.dodgeLead or 0)
            live = at >= b.from - lead and at <= b.untilAt
        end
        if live then
            local depth
            if b.moving then
                -- Where the body is at time `at`, along its line.
                local along = b.offset + b.speed * max(at - b.pathStart, 0)
                local cx, cz = b.ox + b.dx * along, b.oz + b.dz * along
                -- Remote-announced paths carry the boss's height; they are ground attacks.
                if b.ground or abs(py - b.oy) <= b.halfH + halfHeight then
                    local qx, qz = px - cx, pz - cz
                    local ahead = qx * b.dx + qz * b.dz
                    local a = abs(ahead) - b.halfL
                    local s = abs(-qx * b.dz + qz * b.dx) - b.halfW
                    depth = (a <= 0 and s <= 0) and -max(a, s) or -sqrt(max(a, 0) ^ 2 + max(s, 0) ^ 2)
                    -- The rest of its lane, ahead of the body, is a place not to
                    -- stand: soft danger until the body has passed or the path ends.
                    if depth + reach < 0 and ahead > b.halfL and s <= reach then
                        local remaining = b.speed * max(b.untilAt - at, 0)
                        if ahead - b.halfL <= remaining and worst < CFG.pathLaneDanger then worst = CFG.pathLaneDanger end
                    end
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
            -- Slim boxes (Bob's beam fans) get the body radius and little else:
            -- padded to 21 studs wide, the nine spokes left no gap to stand in.
            local d
            if b.slim then d = dangerFromDepth(depth, math.min(reach, b.slim), math.min(shoulder, CFG.slimShoulder))
            else d = dangerFromDepth(depth, reach, shoulder) end
            if b.weight then d = d * b.weight end
            if d > worst then worst = d if worst >= 1 then return 1 end end
        end
    end
    -- Outside the arena leash is the attack that has no box.
    local L = RD.leash
    if L and L.enemy.root.Parent then
        local ep = L.enemy.root.Position
        local dx, dz = px - ep.X, pz - ep.Z
        local depth = sqrt(dx * dx + dz * dz) - L.radius
        -- Armed only once the fight is joined (reader). A hard edge with a
        -- four-stud margin and no shoulder: a graded band reached twelve studs
        -- into the arena and turned the approach into a dodge at 110 studs.
        if depth > -4 then return 1 end
    end
    -- Melee mobs: a soft zone, never a wall. Their strikes are telegraphed
    -- Models and count in full above; the zone only keeps the spots away from
    -- them. A hard 19-stud circle made every spot in room 1 look lethal and
    -- the character stood still in the mage shots.
    for i = 1, #RD.enemies do
        local e = RD.enemies[i]
        if e.melee and not e.isBoss then
            local tt = min(t, 0.6)
            local dx, dz = px - (e.x + e.vx * tt), pz - (e.z + e.vz * tt)
            local d = sqrt(dx * dx + dz * dz)
            local swing = e.extent + (e.meleeDistance or 8) + 2
            local v
            if d <= swing + reach then
                v = 1   -- inside the swing: the one hit
            else
                v = dangerFromDepth(-(d - swing - CFG.meleeBuffer), reach, shoulder * 2) * 0.5
            end
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
        if b.moving and now <= b.untilAt and (b.ground or abs(py - b.oy) <= b.halfH + DG.halfHeight) then
            -- When does the body reach this point? Stepped a tenth of a second
            -- at a time over the next second.
            for k = 0, 10 do
                local t = k * 0.1
                if t >= grace then break end
                local along = b.offset + b.speed * max(now + t - b.pathStart, 0)
                local qx, qz = px - (b.ox + b.dx * along), pz - (b.oz + b.dz * along)
                local a = abs(qx * b.dx + qz * b.dz) - b.halfL
                local s = abs(-qx * b.dz + qz * b.dx) - b.halfW
                if a <= DG.reach and s <= DG.reach then grace = t break end
            end
        elseif not b.moving and now <= b.untilAt then
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


-- The blink's destination: the nearest clear spot on the same floor, at most
-- CFG.blinkMax studs away. Every candidate is checked for a floor at the
-- destination (raycast there, within 1.5 studs of the current feet, facing
-- up), a clear sweep from here to there, and headroom. The character is
-- never placed where the floor is not, and never while airborne.
local function blinkTarget(root, hum, rx, ry, rz)
    local params = raycastParams(DG.approach and DG.approach.model or nil)
    local rp = root.Position
    -- Standing height is the Humanoid's own, not whatever the stride is at
    -- this instant: a hop that inherited a mid-step height left the character
    -- hovering a hair above the floor until the game yanked it down.
    local standard = hum.HipHeight + root.Size.Y * 0.5
    local under = Workspace:Raycast(rp, Vector3.new(0, -(standard + 3), 0), params)
    if not under or under.Normal.Y < 0.7 then return nil end
    local measured = rp.Y - under.Position.Y
    if math.abs(measured - standard) > 0.8 then return nil end   -- mid-jump or mid-fall: no hop
    local above = standard + 0.05
    local feetY = under.Position.Y
    for _, dist in ipairs({ 4, 6, 8 }) do   -- eight is what a 15-wide criss cross lane needs from its centre
        if dist > CFG.blinkMax + 0.01 then break end
        local best, bestScore = nil, math.huge
        for i = 0, 15 do
            local a = i / 16 * 2 * math.pi
            local x, z = rx + math.cos(a) * dist, rz + math.sin(a) * dist
            -- Outside every box now and half a second on, body radius only: the
            -- graded metric's six studs of padding rejected every spot within 8.
            -- Clear of every box for the next second (body radius, no shoulder),
            -- including where projectiles will be; a spot clear now but hit at
            -- 0.7 s was a teleport into the attack.
            local clear = true
            for _, tt in ipairs({ 0, 0.25, 0.5, 0.75, 1.0 }) do
                if dangerAt(x, ry, z, tt, 2.5, 0) >= 0.5 then clear = false break end
            end
            -- Never land beside a mob: its strike is centred on it.
            if clear then
                for _, e in ipairs(RD.enemies) do
                    if not e.isBoss then
                        local ddx, ddz = x - e.x, z - e.z
                        if ddx * ddx + ddz * ddz < (CFG.mobStandoff - 8) ^ 2 then clear = false break end
                    end
                end
            end
            if clear then
                local d1 = math.max(dangerAt(x, ry, z, 0.6), dangerAt(x, ry, z, 1.2))
                do
                    local hit = Workspace:Raycast(Vector3.new(x, ry + 2, z), Vector3.new(0, -(above + 6), 0), params)
                    if hit and hit.Normal.Y > 0.7 and abs(hit.Position.Y - feetY) <= 1.5 then
                        local dest = Vector3.new(x, hit.Position.Y + above, z)
                        if walkable(rp, x, hit.Position.Y, z, params) and not Workspace:Raycast(dest, Vector3.new(0, 3.5, 0), params) then
                            local score = d1
                            if score < bestScore then best, bestScore = dest, score end
                        end
                    end
                end
            end
        end
        if best then return best end
    end
    return nil
end

local BLINK_BOSSES = { ["midgardian champion"] = true, ["bob the frost giant"] = true }

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
    -- The burst is for anything arriving within the dwell, not only what is
    -- already here: the big spike front is announced ~2 s out and needs 23
    -- studs of sidestep, which 16 studs/s does not give.
    RT.moveBoost = DG.dangerHere >= CFG.dodgeMoveAt
    local speed = RT.moveBoost and CFG.tweenEscape or (RT.walkSpeed or CFG.tweenWalk)
    -- Always, not only when the ground is already hot: a box arriving within
    -- the blink window is what the blink is for.
    local grace = graceHere(rx, ry, rz)
    DG.grace = grace
    local moveAt = CFG.dodgeMoveAt

    -- Reflex, outside the movement logic: a lethal box on the character that
    -- fires before a walk could clear it. A hop of at most CFG.blinkMax studs
    -- to the nearest clear floor, no more often than CFG.blinkCooldown.
    -- Rotation, velocity and WalkSpeed are untouched; the height comes from
    -- the floor at the destination.
    -- Only inside a fight: a target within 70 studs. Hops while pathing
    -- between rooms were what the sixth kick was made of.
    local apB = DG.approach
    -- Only where the attacks are mapped: on the third boss the hop fired at
    -- everything and the bot teleported all over the arena (run 29).
    local inFight = apB ~= nil and sqrt((apB.x - rx) ^ 2 + (apB.z - rz) ^ 2) <= 70
        and (not apB.isBoss or (apB.model and BLINK_BOSSES[string.lower(apB.model.Name)] == true))
    local sinceBlink = now - (RT.lastBlinkAt or -math.huge)
    local blinkReady = sinceBlink >= CFG.blinkCooldown
        or (grace <= 0.15 and sinceBlink >= CFG.blinkDoubleGap and now - (RT.lastBlinkDouble or -math.huge) >= 20)
    if CFG.blink and inFight and grace <= CFG.blinkWindow and blinkReady then
        -- Walk first: if the spot the field already holds is reachable before
        -- the box fires, the legs do it. Only a box that fires sooner than the
        -- walk can clear earns a hop, and no more than blinkPer10s of them.
        local walkOk = false
        if DG.target then
            local tx, tz = DG.target.X - rx, DG.target.Z - rz
            walkOk = sqrt(tx * tx + tz * tz) / CFG.tweenEscape + 0.35 <= grace   -- turning and acceleration eat a third of a second
        end
        RT.blinkTimes = RT.blinkTimes or {}
        local recent = 0
        for i = #RT.blinkTimes, 1, -1 do if now - RT.blinkTimes[i] <= 60 then recent = recent + 1 else break end end
        local dest = nil
        if not walkOk and recent < CFG.blinkPerMinute then
            -- The marker first, when it is within reach and its ground is clear
            -- for the next second; the ring search only when it is not.
            local tg = DG.target
            if tg then
                local tx, tz = tg.X - rx, tg.Z - rz
                if sqrt(tx * tx + tz * tz) <= CFG.blinkMax + 0.5 then
                    local clear = true
                    for _, tt in ipairs({ 0, 0.25, 0.5, 0.75, 1.0 }) do
                        if dangerAt(tg.X, ry, tg.Z, tt, 2.5, 0) >= 0.5 then clear = false break end
                    end
                    if clear then dest = Vector3.new(tg.X, tg.Y + hum.HipHeight + root.Size.Y * 0.5, tg.Z) end
                end
            end
            dest = dest or blinkTarget(root, hum, rx, ry, rz)
        end
        if dest then
            RT.blinkTimes[#RT.blinkTimes + 1] = now
            if #RT.blinkTimes > 20 then table.remove(RT.blinkTimes, 1) end
            if now - (RT.lastBlinkAt or -math.huge) < CFG.blinkCooldown then RT.lastBlinkDouble = now end
            RT.lastBlinkAt = now
            RT.blinks = (RT.blinks or 0) + 1
            RT.lastBlink = { at = now, from = rp, to = dest, dist = (Vector3.new(dest.X, 0, dest.Z) - Vector3.new(rx, 0, rz)).Magnitude, grace = grace }
            root.CFrame = CFrame.new(dest) * (root.CFrame - root.CFrame.Position)
            local v = root.AssemblyLinearVelocity
            root.AssemblyLinearVelocity = Vector3.new(v.X, -4, v.Z)   -- settle onto the floor at once
            DG.target = nil
            DG.reason = string.format("blink %.0f studs", RT.lastBlink.dist)
            heavyDebugThrottled("blink", 0.5, "Field", DG.reason)
            return
        end
    end

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
        local endWorst = 0
        for _, extra in ipairs({ 0, dwell * 0.5, dwell }) do
            local d = dangerAt(cx, ry, cz, T + extra)
            total = total + d
            if d > worst then worst = d end
            if d > endWorst then endWorst = d end
            n = n + 1
        end
        return worst, worst * 0.5 + (total / n) * 0.5, endWorst
    end

    local function costOf(ox, oz, dist, graded)
        -- Danger dominates: a lethal spot near the boss used to out-score a
        -- clean spot far out because the band pull and the distance term
        -- together exceeded the danger term. Now no pull can buy a death.
        local cost = graded * CFG.dodgeDangerWeight + dist * CFG.dodgeDistanceCost
        if (hx ~= 0 or hz ~= 0) and here0 < 1 then
            local dot = (ox * hx + oz * hz) / dist
            cost = cost + 0.05 * (1 - dot) * 0.5
        end
        -- Standing in danger with a target: prefer backing away from it. A
        -- spot behind you is the one that is not in the next attack.
        if ap and DG.dangerHere >= CFG.dodgeMoveAt and adist > 1 then
            local toward = (ox * ax + oz * az) / dist
            local back = (toward + 1) * 0.5   -- 0 straight back, 0.5 sideways, 1 toward
            if ap.isBoss then
                cost = cost + CFG.dodgeOutwardWeight * back
            else
                -- Mobs (Chris): back off rather than sidestep toward the walls.
                cost = cost + CFG.dodgeOutwardWeight * CFG.dodgeMobRetreat * sqrt(back)
            end
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
            -- Boss fights stay inside the arena (Chris): the mouth and the corners
            -- are where the aimed attacks spawn on you with nowhere to step.
            -- Always inside the arena (Chris): the edge is the band plus twenty,
            -- or the fan radius while the fan lasts; past it costs, twenty-five
            -- further it is out of the question.
            -- Bob: pull toward his home point, band distance from him toward the
            -- crystals, so an orb can be led without leaving ability range.
            if ap.isBoss and S.bossProfile(ap.model and ap.model.Name).home then
                local cen = S.bobCrystalCentroid()
                if cen then
                    local hx, hz = cen.X - ap.x, cen.Z - ap.z
                    local hl = sqrt(hx * hx + hz * hz)
                    if hl > 1 then
                        local homeX, homeZ = ap.x + hx / hl * band, ap.z + hz / hl * band
                        cost = cost + CFG.bobHomeWeight * sqrt((cx - homeX) ^ 2 + (cz - homeZ) ^ 2)
                    end
                end
            end
            if ap.isBoss and S.bossProfile(ap.model and ap.model.Name).arenaPull then
                local fan = now < (RD.fanUntil or -math.huge) + 1.0
                local far = dd - (fan and CFG.fanRadius or (band + 20))
                if far > 0 then cost = cost + CFG.dodgeArenaWeight * far end
                if far > 25 then cost = cost + 2 end
            end
            -- Outside the arena leash everything reads lethal alike; this gradient
            -- is what brings a respawn at 135 studs back in instead of out to 150
            -- (run 28's two leash deaths).
            local L = RD.leash
            if L and L.enemy.root.Parent then
                local lx, lz = cx - L.enemy.root.Position.X, cz - L.enemy.root.Position.Z
                local outL = sqrt(lx * lx + lz * lz) - (L.radius - 8)
                if outL > 0 then cost = cost + 0.08 * outL end
            end
            -- Inside the last stretch, moving across the line to the target is
            -- preferred to moving along it.
            if near and CFG.strafe and adist > 1 then
                local radial = abs((ox * ax + oz * az) / dist)
                cost = cost + CFG.dodgeStrafeWeight * radial
            end
        end
        return cost
    end

    -- The target's body IS a wall: the Champion has fifteen collidable parts,
    -- and a spot picked behind him left the character running in place
    -- against his legs.
    local params = raycastParams(nil)
    local cands = DG.cands
    table.clear(cands)
    local function evaluate(scale)
        for _, off in ipairs(DG.offsets) do
            local ox, oz, dist = off.x * scale, off.z * scale, off.dist * scale
            local worst, graded, endWorst = score(ox, oz, dist)
            -- The spot itself must not be inside anything firing while we stand
            -- there (Chris: the marker never touches a box about to go off).
            -- Such spots sort last; they are taken only when nothing else exists.
            local cost = costOf(ox, oz, dist, graded)
            if endWorst >= 0.999 then cost = cost + 100 end
            -- Clean path and clean ground: the nearest such spot is the marker
            -- (Chris: the closest available safe spot, so a blink can reach it).
            local safe = worst < CFG.dodgeSafeWorst and endWorst < CFG.dodgeMoveAt
            if safe then cost = cost - 10 + dist * CFG.dodgeSafeDistanceCost end
            -- Hot ground and a spot four studs away: that is dithering, not a dodge.
            if (DG.dangerHere or 0) >= 0.5 and dist < 8 then cost = cost + 1 end
            cands[#cands + 1] = { ox = ox, oz = oz, dist = dist, danger = worst, endDanger = endWorst, cost = cost, safe = safe }
        end
        table.sort(cands, function(a, b) return a.cost < b.cost end)
        local best, checked = nil, 0
        local st = DG.evalStats
        st.total = st.total + #cands
        for _, c in ipairs(cands) do
            if best and c.cost >= best.cost then break end
            checked = checked + 1
            if (c.endDanger or 0) >= 0.999 then st.lethalEnd = st.lethalEnd + 1 end
            local x, z = rx + c.ox, rz + c.oz
            local y = floorY(x, ry, z, params)
            -- A far spot may sit up a ramp: the allowed rise grows with distance.
            if y and y - (ry - DG.halfHeight) <= CFG.maxStepHeight + 3 + c.dist * 0.2 and y >= ry - CFG.maxDropHeight then
                if walkable(rp, x, y, z, params) then
                    c.x, c.y, c.z, c.valid = x, y, z, true
                    st.valid = st.valid + 1
                    -- Openness: how far the walls are from this spot.
                    local free = 0
                    local origin = Vector3.new(x, y + 2.5, z)
                    for k = 0, 5 do
                        local a = k * (math.pi / 3)
                        local hit = Workspace:Raycast(origin, Vector3.new(cos(a), 0, sin(a)) * CFG.dodgeWallLook, params)
                        free = free + (hit and hit.Distance or CFG.dodgeWallLook)
                    end
                    c.open = free / 6
                    c.cost = c.cost + CFG.dodgeWallWeight * max(0, CFG.dodgeWallLook * 0.75 - c.open)
                    if not best or c.cost < best.cost then best = c end
                else
                    st.notWalkable = st.notWalkable + 1
                end
            else
                st.noFloor = st.noFloor + 1
            end
            if checked >= 14 and best and best.danger < moveAt then break end
            if checked >= 40 then break end
        end
        return best
    end

    DG.evalStats = { total = 0, valid = 0, noFloor = 0, notWalkable = 0, lethalEnd = 0 }
    local best = evaluate(1)
    for _, scale in ipairs({ CFG.dodgeFarScale, CFG.dodgeFarScale2 }) do
        if best and best.danger < moveAt then break end
        if scale and scale > 1 then
            table.clear(cands)
            local far = evaluate(scale)
            if far and (not best or far.danger < best.danger) then best = far end
        end
    end

    -- A spot we have failed to move toward for half a second is blocked by
    -- something the sweep missed: drop it and pick another.
    if DG.target and (RT.stalledFor or 0) > 0.6 then
        DG.target = nil
        DG.reason = "stalled"
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
            local worst, graded, endWorst = score(tx, tz, d)
            if endWorst >= 0.999 then
                -- The spot itself is about to be hit: never keep it.
                target = nil
                DG.target = nil
                DG.reason = "spot closed"
            elseif here0 >= moveAt then
                -- Escaping: the spot is kept until reached, or until a clearly
                -- better one exists. Dropping it the moment its line reads hot
                -- re-picked a different direction every frame when everything
                -- was hot, and the character stood still and died.
                if best and best.danger < worst - 0.25 then
                    target = nil
                    DG.target = nil
                    DG.reason = "better spot"
                else
                    return
                end
            elseif worst >= moveAt then
                target = nil
                DG.target = nil
                DG.reason = "line closed"
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
        DG.chosen = { dist = best.dist, danger = best.danger, endDanger = best.endDanger, cost = best.cost }
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
