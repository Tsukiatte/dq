-- field.lua - One danger field. For a point and a time: the worst of every
-- attack whose window contains that time (its shape at that time, with a hard
-- margin and a soft ring outside it) and every enemy's body. 1 is lethal.
--
-- The dodge samples the field about a thousand times per decision, so once
-- per frame every live attack is snapshotted into plain numbers (centre,
-- axes, half sizes, path) and the samples are pure arithmetic.
return function(S)
local CFG = S.CFG
local HZ = S.HZ
local attackWindow = S.attackWindow
local gameTime = S.gameTime

local HORIZON = 4.0          -- seconds ahead the snapshot keeps an attack for
local snap = {}              -- attack entries
local bodies = {}            -- enemy entries
local snapAt = -math.huge

-- Rebuild the snapshot for this frame.
local function fieldRefresh(now)
    snapAt = now
    local n = 0
    local usePrecast = CFG.usePrecast
    for i = 1, #HZ.attacks do
        local rec = HZ.attacks[i]
        if rec.kind ~= "model" or usePrecast then
            local open, close = attackWindow(rec)
            if open and close >= now and open <= now + HORIZON then
                local ok = pcall(function()
                    local e = { open = open, close = close }
                    if rec.kind == "part" then
                        e.kind = 3
                        e.r = rec.radius
                        local ev = rec.ev
                        if ev then
                            e.path = true
                            e.ox, e.oz = ev.origin.X, ev.origin.Z
                            e.lx, e.lz = ev.look.X, ev.look.Z
                            e.dist, e.dur, e.start = ev.dist, ev.dur, ev.start
                        else
                            local p = rec.pos
                            e.ox, e.oz = p.X, p.Z
                            local v = rec.vel
                            e.vx, e.vz = v and v.X or 0, v and v.Z or 0
                            e.t0 = rec.sampledAt
                        end
                    elseif rec.shape == "disc" then
                        e.kind = 2
                        local c = rec.center or rec.part.Position
                        e.ox, e.oz, e.r = c.X, c.Z, rec.radius
                    else
                        e.kind = 1
                        local cf = rec.cframe or rec.part.CFrame
                        local size = rec.size or rec.part.Size
                        local p = cf.Position
                        local rv, lv = cf.RightVector, cf.LookVector
                        e.ox, e.oz = p.X, p.Z
                        -- Planar axes; a pitched box is projected as if flat.
                        local rl = math.sqrt(rv.X * rv.X + rv.Z * rv.Z)
                        local ll = math.sqrt(lv.X * lv.X + lv.Z * lv.Z)
                        e.rx, e.rz = rl > 0.01 and rv.X / rl or 1, rl > 0.01 and rv.Z / rl or 0
                        e.lx, e.lz = ll > 0.01 and lv.X / ll or 0, ll > 0.01 and lv.Z / ll or 1
                        e.hx, e.hz = size.X * 0.5, size.Z * 0.5
                    end
                    n = n + 1
                    snap[n] = e
                end)
                if not ok then n = n end
            end
        end
    end
    for i = #snap, n + 1, -1 do snap[i] = nil end
    local m = 0
    for i = 1, #HZ.enemies do
        local en = HZ.enemies[i]
        local root = en.root
        if root.Parent then
            local p = root.Position
            m = m + 1
            local b = bodies[m] or {}
            b.x, b.z, b.hard = p.X, p.Z, (en.extent or 2) + 1.5
            bodies[m] = b
        end
    end
    for i = #bodies, m + 1, -1 do bodies[i] = nil end
end

-- Planar distance from (x, z) to entry e at time t; 0 or less inside.
local function entryDistance(e, x, z, t)
    local kind = e.kind
    if kind == 1 then
        local dx, dz = x - e.ox, z - e.oz
        local lx = dx * e.rx + dz * e.rz
        local lz = dx * e.lx + dz * e.lz
        local ax = math.abs(lx) - e.hx
        local az = math.abs(lz) - e.hz
        if ax < 0 then ax = 0 end
        if az < 0 then az = 0 end
        return math.sqrt(ax * ax + az * az)
    end
    local px, pz
    if kind == 2 then
        px, pz = e.ox, e.oz
    elseif e.path then
        local k = (gameTime(t) - e.start) / e.dur
        if k < 0 then k = 0 elseif k > 1 then k = 1 end
        px, pz = e.ox + e.lx * (k * e.dist), e.oz + e.lz * (k * e.dist)
    else
        local dt = t - e.t0
        if dt > CFG.projectileLookahead then dt = CFG.projectileLookahead end
        if dt < 0 then dt = 0 end
        px, pz = e.ox + e.vx * dt, e.oz + e.vz * dt
    end
    local dx, dz = px - x, pz - z
    return math.sqrt(dx * dx + dz * dz) - e.r
end

local function dangerAt(x, z, t)
    if t - snapAt > 1.5 then fieldRefresh(t) end
    local worst = 0
    local margin = CFG.damageBrickClearance
    local soft = CFG.preemptiveClearance
    for i = 1, #snap do
        local e = snap[i]
        if t >= e.open and t <= e.close then
            local d = entryDistance(e, x, z, t)
            local v
            if d <= margin then return 1
            elseif d < margin + soft then v = 0.6 * (1 - (d - margin) / soft)
            else v = 0 end
            if v > worst then worst = v end
        end
    end
    for i = 1, #bodies do
        local b = bodies[i]
        local dx, dz = b.x - x, b.z - z
        local d = math.sqrt(dx * dx + dz * dz)
        local v
        if d <= b.hard then return 1
        elseif d < b.hard + 4 then v = 0.3 * (1 - (d - b.hard) / 4)
        else v = 0 end
        if v > worst then worst = v end
    end
    return worst
end

-- Worst danger along the straight line from (x0,z0) to (x1,z1) walked at
-- `speed` starting at time t0, sampled every CFG.dodgeSampleSpacing studs at
-- the moment each sample would be reached. Returns worst, mean. `here` is
-- the danger at the start: the first samples are still inside whatever is
-- being left and that is not the line's fault.
local function dangerAlong(x0, z0, x1, z1, t0, speed, here)
    local dx, dz = x1 - x0, z1 - z0
    local len = math.sqrt(dx * dx + dz * dz)
    if len < 0.01 then return 0, 0 end
    local n = math.max(1, math.min(8, math.ceil(len / CFG.dodgeSampleSpacing)))
    local worst, sum = 0, 0
    for i = 1, n do
        local k = i / n
        local t = t0 + (len * k) / speed
        local v = dangerAt(x0 + dx * k, z0 + dz * k, t)
        if here and here > 0 and k < 0.5 then v = math.max(0, v - here) end
        if v > worst then worst = v end
        sum = sum + v
    end
    return worst, sum / n
end

-- Worst danger at a point over [t, t + dwell], sampled four times a second.
local function dangerOver(x, z, t, dwell)
    local worst = dangerAt(x, z, t)
    local steps = math.max(1, math.floor(dwell / 0.25))
    for i = 1, steps do
        if worst >= 1 then break end
        local v = dangerAt(x, z, t + i * 0.25)
        if v > worst then worst = v end
    end
    return worst
end

S.fieldRefresh = fieldRefresh
S.dangerAt = dangerAt
S.dangerAlong = dangerAlong
S.dangerOver = dangerOver
end
