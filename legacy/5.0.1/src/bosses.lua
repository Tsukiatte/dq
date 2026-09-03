-- bosses.lua - What is known about Northern Lands, measured in the real game
-- (Chris's capture of 2026-09-02) and read out of the client handler in the
-- place file. Per attack name: the age at which the precast flashes and the
-- hit lands. The Midgardian Champion's passive beams sweep twenty degrees per
-- half second, so from two beams the next ones are predicted before they
-- exist. The arena is the 217-stud cube FirstPart; a player outside it gets a
-- criss cross spawned on them, so after a respawn the standoff pull is strong.
return function(S)
local CFG = S.CFG
local RT = S.RT
local HZ = S.HZ
local Workspace = S.Workspace
local LocalPlayer = S.LocalPlayer
local heavyDebug = S.heavyDebug
local addVirtualAttack = S.addVirtualAttack

local clock = os.clock

-- Age (s after the Model appears) of the flash = the hit. From the capture:
-- beam 0.90-0.95, mage shot 0.95-1.03, spearman strike 0.86, warrior line
-- strike 0.65-0.67, warrior circle strike 0.63-0.68 (25-stud) / 0.35-0.40
-- (34-stud), jump slam 1.8 (from the older capture, one hit; unverified).
local FLASH = {
    firstbosspassivebeam = 0.92,
    northernmageshot = 0.98,
    spearmanstrikehitbox = 0.86,
    northernwarriorlinestrike = 0.66,
    northernwarriorcirclestrike = 0.65,
    firstbossjumpslam = 1.8,
}
local function flashTimeFor(rec)
    local T = FLASH[rec.key]
    if T and rec.key == "northernwarriorcirclestrike" and rec.part and rec.part.Size.Y >= 30 then T = 0.37 end
    return T
end

-- ------------------------------------------------------------------ the sweep
-- Beams are 250-stud lines through the boss, one every 0.5 s, twenty degrees
-- apart, in bursts of up to 13, ten seconds apart. Yaw is taken modulo 180
-- because a line through the centre is the same line turned round.
local BEAM = { step = 20, period = 0.5, ahead = 3 }
local sweep = { last = nil, prev = nil, preds = {} }

local function yawOf(cf)
    local l = cf.LookVector
    return (math.deg(math.atan2(l.X, -l.Z)) + 360) % 180
end
local function angleDelta(a, b)
    local d = (b - a) % 180
    if d > 90 then d = d - 180 end
    return d
end

local function onAttackShape(rec)
    if rec.kind ~= "model" or rec.key ~= "firstbosspassivebeam" or rec.pre or not rec.part then return end
    local yaw = yawOf(rec.part.CFrame)
    local now = clock()
    -- A predicted line that has now arrived is dropped for the real one.
    for i = #sweep.preds, 1, -1 do
        local p = sweep.preds[i]
        if math.abs(angleDelta(p.yaw, yaw)) < 6 or now > p.close then
            p.rec.dropped = true
            table.remove(sweep.preds, i)
        end
    end
    sweep.prev = sweep.last
    sweep.last = { yaw = yaw, at = rec.spawn, cf = rec.part.CFrame, size = rec.part.Size }
    local prev = sweep.prev
    if not prev or rec.spawn - prev.at > 1.2 then return end
    local delta = angleDelta(prev.yaw, yaw)
    if math.abs(math.abs(delta) - BEAM.step) > 6 then return end
    local dir = delta > 0 and 1 or -1
    local period = math.max(0.3, math.min(0.8, rec.spawn - prev.at))
    local T = FLASH.firstbosspassivebeam
    local centre = rec.part.CFrame.Position
    for k = 1, BEAM.ahead do
        local py = (yaw + dir * BEAM.step * k) % 180
        local spawnAt = rec.spawn + period * k
        local already = false
        for _, p in ipairs(sweep.preds) do
            if math.abs(angleDelta(p.yaw, py)) < 6 then already = true break end
        end
        if not already then
            local cf = CFrame.new(centre) * CFrame.Angles(0, -math.rad(py), 0)
            local open, close = spawnAt + T - CFG.dodgeLead, spawnAt + T + CFG.hitAfter
            local vrec = addVirtualAttack("firstBossPassiveBeam (predicted)", cf, rec.part.Size, open, close)
            sweep.preds[#sweep.preds + 1] = { yaw = py, close = close, rec = vrec }
        end
    end
end

-- A burst is in progress while a beam appeared in the last two seconds.
local function sweepActive(now)
    return sweep.last ~= nil and now - sweep.last.at < 2.0
end

-- ------------------------------------------------------------------ the arena
local arena
local function inArena(pos)
    if not arena then
        local fp = Workspace:FindFirstChild("FirstPart")
        if fp and fp:IsA("BasePart") then
            local c, s = fp.Position, fp.Size
            arena = { x0 = c.X - s.X * 0.5, x1 = c.X + s.X * 0.5, z0 = c.Z - s.Z * 0.5, z1 = c.Z + s.Z * 0.5 }
        else
            return true
        end
    end
    return pos.X >= arena.x0 and pos.X <= arena.x1 and pos.Z >= arena.z0 and pos.Z <= arena.z1
end

-- Where to stand off a given enemy right now.
local function standoffFor(enemy, now)
    if enemy.boss then
        if sweepActive(now) then return CFG.bossSweepStandoff end
        return CFG.bossStandoff
    end
    local extent = enemy.extent or 2
    local reach = extent + (enemy.melee or CFG.enemyMeleeReach) + 1
    return math.max(extent + 1, math.min(reach, CFG.attackRange - 1.5))
end

-- The approach is urgent outside the arena with a boss alive: the criss
-- cross is aimed at players standing there.
local function approachUrgency(now)
    local char = LocalPlayer.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then return 1 end
    local bossAlive = false
    for _, e in ipairs(HZ.enemies) do if e.boss then bossAlive = true break end end
    if bossAlive and (not inArena(root.Position) or now - RT.respawnedAt < 6) then return 5 end
    return 1
end

local function onBossEvent(remoteName, name, args)
    if name == "First Boss Jump Up" then heavyDebug("Boss", "Jump up: expect a slam.") end
end

S.flashTimeFor = flashTimeFor
S.onAttackShape = onAttackShape
S.onBossEvent = onBossEvent
S.sweepActive = sweepActive
S.inArena = inArena
S.standoffFor = standoffFor
S.approachUrgency = approachUrgency
S.FLASH_TIMES = FLASH
end
