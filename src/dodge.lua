-- dodge.lua - Where to stand. A ring of candidates round the character,
-- each scored by the danger along the straight line to it (at the moments it
-- would be crossed) and at it for the dwell after arriving, plus a small
-- distance cost, a turn cost against the last heading, and a pull toward
-- where pursuit wants to be. The best one is the target; when here is fine
-- and pursuit is not blocked there is no target and pursuit drives.
return function(S)
local CFG = S.CFG
local DG = S.DG
local dangerAt = S.dangerAt
local dangerAlong = S.dangerAlong
local dangerOver = S.dangerOver
local floorAt = S.floorAt
local wallBetween = S.wallBetween

local V3 = Vector3.new
local INF = math.huge
local TAU = math.pi * 2

local function setDodgeActive(active)
    DG.active = active and true or false
    if not DG.active then
        DG.target = nil
        DG.gapWait = false
        DG.pursuitBlocked = false
        DG.dangerHere = 0
    end
end

local function decide(root, hum, now)
    local p = root.Position
    local x, z = p.X, p.Z
    local speed = CFG.dodgeSpeed
    local dwell = CFG.dodgeDwell
    local hereNow = dangerAt(x, z, now)
    local here = math.max(hereNow, dangerOver(x, z, now, math.min(dwell, 0.6)))
    DG.dangerHere = here
    local moveAt = CFG.dodgeMoveAt
    local goal = DG.goal
    local urgency = S.approachUrgency and S.approachUrgency(now) or 1

    -- Nothing on us and pursuit free to walk: no target, pursuit drives.
    if here < moveAt and not DG.pursuitBlocked then
        DG.target = nil
        DG.targetReason = "safe here"
        DG.gapWait = false
        DG.cands = {}
        return
    end

    local rings, rays, reach = CFG.dodgeRings, CFG.dodgeRays, CFG.dodgeReach
    local cands = {}
    local goalDistHere
    if goal then
        local gx, gz = goal.X - x, goal.Z - z
        goalDistHere = math.sqrt(gx * gx + gz * gz)
    end
    local hx, hz = 0, 0
    if DG.heading and now - DG.headingTime < 1.5 then hx, hz = DG.heading.X, DG.heading.Z end
    for r = 1, rings do
        local dist = reach * r / rings
        for i = 1, rays do
            local a = (i - 1) / rays * TAU + (r % 2) * (math.pi / rays)
            local ux, uz = math.cos(a), math.sin(a)
            local cx, cz = x + ux * dist, z + uz * dist
            local tArrive = now + dist / speed
            local lineWorst = dangerAlong(x, z, cx, cz, now, speed, hereNow)
            local arrive = dangerOver(cx, cz, tArrive, dwell)
            local danger = math.max(lineWorst, arrive)
            local cost = danger + CFG.dodgeDistanceCost * dist
            if goalDistHere then
                local gx, gz = goal.X - cx, goal.Z - cz
                local progress = goalDistHere - math.sqrt(gx * gx + gz * gz)
                cost = cost - CFG.dodgeApproachWeight * urgency * progress
            end
            if hx ~= 0 or hz ~= 0 then
                cost = cost + CFG.dodgeTurnCost * (1 - (ux * hx + uz * hz)) * 0.5
            end
            cands[#cands + 1] = { x = cx, z = cz, ux = ux, uz = uz, dist = dist, danger = danger, cost = cost }
        end
    end
    table.sort(cands, function(a, b) return a.cost < b.cost end)
    DG.cands = cands

    -- Validate the best few against the world: a floor to stand on within
    -- climb and drop limits, and no wall across the line.
    local best
    local budget = CFG.dodgeValidate
    for i = 1, math.min(#cands, budget) do
        local c = cands[i]
        local fy = floorAt(c.x, p.Y, c.z)
        if fy then
            local rise = fy - (p.Y - hum.HipHeight - root.Size.Y * 0.5)
            if rise <= CFG.dodgeMaxClimb and -rise <= CFG.dodgeMaxDrop then
                local target = V3(c.x, fy + hum.HipHeight + root.Size.Y * 0.5, c.z)
                if not wallBetween(p, target) then
                    c.target = target
                    c.valid = true
                    best = c
                    break
                end
            end
        end
        c.valid = false
    end

    if here >= moveAt then
        -- Something is on us or about to be: go to the least bad spot unless
        -- it is no better than here and here is not lethal.
        if best and (best.danger < here - 0.05 or here >= 1) then
            DG.target = best.target
            DG.targetReason = string.format("out (%.2f -> %.2f)", here, best.danger)
            DG.heading = V3(best.ux, 0, best.uz)
            DG.headingTime = now
            DG.gapWait = false
        else
            DG.target = nil
            DG.targetReason = "nowhere better"
            DG.gapWait = true
        end
        return
    end

    -- Here is safe and pursuit is blocked: a safe step that gains ground, or
    -- hold and wait for a gap.
    if best and best.danger < moveAt and goalDistHere then
        local gx, gz = goal.X - best.x, goal.Z - best.z
        local progress = goalDistHere - math.sqrt(gx * gx + gz * gz)
        if progress > 1.5 then
            DG.target = best.target
            DG.targetReason = string.format("in (%.2f)", best.danger)
            DG.heading = V3(best.ux, 0, best.uz)
            DG.headingTime = now
            DG.gapWait = false
            return
        end
    end
    DG.target = nil
    DG.targetReason = "waiting for a gap"
    DG.gapWait = true
end

-- Decide every frame while something is on us, otherwise on the interval.
local function dodgeStep(root, hum, now)
    if not DG.active then return end
    local due = now - DG.lastDecision >= CFG.dodgeInterval
    if not due and DG.dangerHere < CFG.dodgeMoveAt and DG.target == nil then return end
    DG.lastDecision = now
    decide(root, hum, now)
    if DG.target and S.MV.arrived then DG.target = nil end
end

S.setDodgeActive = setDodgeActive
S.dodgeStep = dodgeStep
end
