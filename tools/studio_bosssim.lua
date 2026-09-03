--[[
    studio_bosssim.lua - Midgardian Champion (Northern Lands first boss) fight
    simulator for the Studio test harness. Run from the command bar (or the
    Studio MCP execute_luau) in EDIT mode, in the mid-fight save of the NL place
    (place 85776757589518 Level(2).rbxl). It installs ServerScriptService.DQBossSim,
    which does the work in PLAY mode.

    Everything here is reconstructed from what the game showed us:
      - 14 firstBossPassiveBeam Models parked at the arena centre (-580,24,470):
        precast 8x2.1x250, hitBox 8x63.7x250, both invisible, life 7.0 s.
      - northernMageShot: nothing visible for ~0.9 s, then the precast turns
        visible and the hit lands at that instant; removed ~8 s after appearing.
        Built to npcMageShot's proportions (precast 60x1x2, hitBox 60x53x3).
      - spearman / warrior line strikes: 11x4x31, hit early, life 7 s.
      - First Boss Criss Cross Projectile / Seeking Spike / Big Spike: fired
        over ReplicatedStorage.remotes.northernBossSpecficEvents with the
        payloads the client handler reads, on the game's timeSync clock, with a
        server-side damaging mesh following the same motion.

    Attributes on Workspace (set from the command bar to steer a test):
      DQSimEnabled   (bool, default true)   master switch
      DQSimVisible   (bool, default true)   show telegraphs (false = blind, like the real mage shots)
      DQSimBeams     (bool) DQSimMages (bool) DQSimStrikes (bool) DQSimProjectiles (bool)
      DQSimRate      (number, default 1.0)  cadence multiplier
      DQSimBeamHurt  ("pulse" | "long", default "pulse") how long a passive beam hurts:
                     pulse = 0.3-1.0 s after it appears, long = 0.5-7.0 s (its whole life)
      DQSimBurstGap  (number, default 10)  seconds between beam bursts
      DQSimBossHP    (number, default 3000) DQSimSwingDamage (25) DQSimReach (14)
      DQSimHits      (number)               hits taken by the player (read-only counter)
      DQSimDamage    (number)               total damage dealt (read-only)
]]

local ServerScriptService = game:GetService("ServerScriptService")

local old = ServerScriptService:FindFirstChild("DQBossSim")
if old then old:Destroy() end

local SOURCE = [==[
local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local WS = workspace
local CENTRE = Vector3.new(-580, 21, 470)      -- arena floor at the middle part
local ARENA_RADIUS = 95

-- This game loads characters itself and teleports them to the dungeon start
-- once; the harness loads them and keeps them in the arena.
Players.CharacterAutoLoads = true
local ARENA_SPAWN = CFrame.new(CENTRE + Vector3.new(-40, 4, 0))
local function placeInArena(char)
    local r = char:WaitForChild("HumanoidRootPart", 5)
    if r then task.wait(0.3) r.CFrame = ARENA_SPAWN end
end
Players.PlayerAdded:Connect(function(player)
    player.CharacterAdded:Connect(placeInArena)
    task.wait(1)
    if not player.Character then pcall(function() player:LoadCharacter() end) end
end)
task.defer(function()
    for _, player in ipairs(Players:GetPlayers()) do
        player.CharacterAdded:Connect(placeInArena)
        if not player.Character then pcall(function() player:LoadCharacter() end) else task.spawn(placeInArena, player.Character) end
    end
end)
task.spawn(function()
    while true do
        for _, player in ipairs(Players:GetPlayers()) do
            local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
            if root and (root.Position - CENTRE).Magnitude > 150 then root.CFrame = ARENA_SPAWN end
        end
        task.wait(0.5)
    end
end)

local function attr(name, default)
    local v = WS:GetAttribute(name)
    if v == nil then WS:SetAttribute(name, default) return default end
    return v
end
attr("DQSimEnabled", true)
attr("DQSimVisible", true)
attr("DQSimBeams", true)
attr("DQSimMages", true)
attr("DQSimStrikes", true)
attr("DQSimProjectiles", true)
attr("DQSimRate", 1.0)
WS:SetAttribute("DQSimHits", 0)
WS:SetAttribute("DQSimDamage", 0)

local function log(text) print("[DQBossSim] " .. text) end

-- ------------------------------------------------------------ world
local dn = WS:FindFirstChild("dungeonName")
if dn then dn.Value = "Northern Lands" end
local spawnLoc = WS:FindFirstChild("playerSpawn")
if spawnLoc and spawnLoc:IsA("SpawnLocation") then
    spawnLoc.CFrame = CFrame.new(CENTRE + Vector3.new(-45, 2, 0))
end
local enemies = WS:FindFirstChild("enemies")
if not enemies then enemies = Instance.new("Folder") enemies.Name = "enemies" enemies.Parent = WS end

-- ------------------------------------------------------------ the boss
local boss = nil
local function makeBoss()
    local old = enemies:FindFirstChild("Midgardian Champion")
    if old then old:Destroy() end
    local m = Instance.new("Model")
    m.Name = "Midgardian Champion"
    local root = Instance.new("Part")
    root.Name = "HumanoidRootPart"
    root.Size = Vector3.new(6, 10, 6)
    root.Anchored = true
    root.CanCollide = true
    root.Color = Color3.fromRGB(120, 160, 255)
    root.Material = Enum.Material.Ice
    root.CFrame = CFrame.new(CENTRE + Vector3.new(0, 5, 0))
    root.Parent = m
    local head = Instance.new("Part")
    head.Name = "Head"
    head.Size = Vector3.new(4, 4, 4)
    head.Anchored = true
    head.CanCollide = false
    head.Color = root.Color
    head.CFrame = CFrame.new(CENTRE + Vector3.new(0, 12, 0))
    head.Parent = m
    local hum = Instance.new("Humanoid")
    hum.MaxHealth = attr("DQSimBossHP", 3000)
    hum.Health = hum.MaxHealth
    hum.BreakJointsOnDeath = false
    hum.Parent = m
    -- The values the real enemy Models carry.
    local style = Instance.new("StringValue") style.Name = "enemyStyle" style.Value = "boss1" style.Parent = m
    local melee = Instance.new("IntValue") melee.Name = "meleeDistance" melee.Value = 4 melee.Parent = m
    local aggro = Instance.new("IntValue") aggro.Name = "aggroRange" aggro.Value = 50 aggro.Parent = m
    local speed = Instance.new("IntValue") speed.Name = "moveSpeed" speed.Value = 16 speed.Parent = m
    m.PrimaryPart = root
    m.Parent = enemies
    boss = m
    WS:SetAttribute("DQSimBossHP", math.floor(hum.Health))
    return m
end
makeBoss()

-- The fight save carries the real boss Model, parked in the air where the
-- fight left it. Two enemies of the same name confused the chase; the dummy
-- is the boss here.
do
    local dungeon = WS:FindFirstChild("dungeon")
    for _, d in ipairs(dungeon and dungeon:GetDescendants() or {}) do
        if d:IsA("Model") and d.Name == "Midgardian Champion" then d:Destroy() end
    end
end

-- ------------------------------------------------------------ the bot's swings
-- The harness loader fires this whenever the autofarm would swing at its
-- target (the real swing needs the executor's input injection). A swing
-- within reach takes a bite out of the boss; a dead boss comes back after a
-- few seconds so a run can measure kills per minute.
local attackRemote = RS:FindFirstChild("DQSimAttack")
if not attackRemote then
    attackRemote = Instance.new("RemoteEvent")
    attackRemote.Name = "DQSimAttack"
    attackRemote.Parent = RS
end
WS:SetAttribute("DQSimBossKills", 0)
WS:SetAttribute("DQSimSwings", 0)
local kills, swings, casts = 0, 0, 0
local bossDown = false
local lastCast = {}
WS:SetAttribute("DQSimCasts", 0)
attackRemote.OnServerEvent:Connect(function(player, kind)
    local char = player.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local bh = boss and boss:FindFirstChildOfClass("Humanoid")
    local br = boss and boss:FindFirstChild("HumanoidRootPart")
    if not (root and bh and br) or bossDown then return end
    local flat = Vector3.new(root.Position.X - br.Position.X, 0, root.Position.Z - br.Position.Z)
    local reach, damage = attr("DQSimReach", 14), attr("DQSimSwingDamage", 25)
    if kind == "ability" then
        -- Q/E: a cooldown per player, a longer reach, a bigger bite.
        local t = tick()
        if t - (lastCast[player] or 0) < attr("DQSimAbilityCooldown", 1.0) then return end
        lastCast[player] = t
        reach, damage = attr("DQSimAbilityReach", 30), attr("DQSimAbilityDamage", 100)
    end
    if flat.Magnitude <= reach then
        if kind == "ability" then
            casts = casts + 1
            WS:SetAttribute("DQSimCasts", casts)
        else
            swings = swings + 1
            WS:SetAttribute("DQSimSwings", swings)
        end
        bh:TakeDamage(damage)
        WS:SetAttribute("DQSimBossHP", math.floor(bh.Health))
        if bh.Health <= 0 then
            bossDown = true
            kills = kills + 1
            WS:SetAttribute("DQSimBossKills", kills)
            log(string.format("BOSS DOWN #%d at t=%.0f after %d swings; hits taken so far %d", kills, WS.DistributedGameTime, swings, hits))
            -- A dead Humanoid stays dead whatever its Health is set to:
            -- rebuild the boss instead.
            task.delay(5, function()
                makeBoss()
                bossDown = false
                log("boss back")
            end)
        end
    end
end)

-- ------------------------------------------------------------ damage
local hits = 0
local damageTotal = 0
local lastHitAt = {}   -- [player][hitbox] = time
local function pointInPart(part, p)
    local lp = part.CFrame:PointToObjectSpace(p)
    local h = part.Size * 0.5
    return math.abs(lp.X) <= h.X and math.abs(lp.Y) <= h.Y and math.abs(lp.Z) <= h.Z
end
local function pointInCylinderPart(part, p)
    -- Cylinder Parts lie along X: radius from Y/Z.
    local lp = part.CFrame:PointToObjectSpace(p)
    local h = part.Size * 0.5
    local r = math.min(h.Y, h.Z)
    return math.abs(lp.X) <= h.X and (lp.Y * lp.Y + lp.Z * lp.Z) <= r * r
end
local function hurtPlayersIn(hitBox, damage, tag)
    for _, player in ipairs(Players:GetPlayers()) do
        local char = player.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if root and hum and hum.Health > 0 then
            local inside
            if hitBox:IsA("Part") and hitBox.Shape == Enum.PartType.Cylinder then
                inside = pointInCylinderPart(hitBox, root.Position)
            elseif hitBox:IsA("Part") and hitBox.Shape == Enum.PartType.Ball then
                inside = (root.Position - hitBox.Position).Magnitude <= hitBox.Size.X * 0.5
            else
                inside = pointInPart(hitBox, root.Position)
            end
            if inside then
                lastHitAt[player] = lastHitAt[player] or {}
                local t = tick()
                if (lastHitAt[player][hitBox] or 0) + 0.5 <= t then
                    lastHitAt[player][hitBox] = t
                    hum:TakeDamage(damage)
                    hits = hits + 1
                    damageTotal = damageTotal + damage
                    WS:SetAttribute("DQSimHits", hits)
                    WS:SetAttribute("DQSimDamage", damageTotal)
                    log(string.format("HIT %s by %s (%d dmg)", player.Name, tag, damage))
                end
            end
        end
    end
end

-- Active windows: { hitBox, damage, tag, from, until }
local live = {}
local function addLive(hitBox, damage, tag, from, untilAt)
    live[#live + 1] = { hitBox = hitBox, damage = damage, tag = tag, from = from, untilAt = untilAt }
end
RunService.Heartbeat:Connect(function()
    local now = tick()
    for i = #live, 1, -1 do
        local w = live[i]
        if now > w.untilAt or not w.hitBox.Parent then
            table.remove(live, i)
        elseif now >= w.from then
            hurtPlayersIn(w.hitBox, w.damage, w.tag)
        end
    end
end)

Players.PlayerAdded:Connect(function(player)
    player.CharacterAdded:Connect(function(char)
        local hum = char:WaitForChild("Humanoid")
        hum.MaxHealth = 2000
        hum.Health = 2000
        hum.WalkSpeed = 16
    end)
end)
for _, player in ipairs(Players:GetPlayers()) do
    if player.Character then
        local hum = player.Character:FindFirstChildOfClass("Humanoid")
        if hum then hum.MaxHealth = 2000 hum.Health = 2000 end
    end
end

local function nearestPlayerPosition(from)
    local best, bd = nil, math.huge
    for _, player in ipairs(Players:GetPlayers()) do
        local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
        if root then
            local d = (root.Position - from).Magnitude
            if d < bd then best, bd = root.Position, d end
        end
    end
    return best
end

local function visible() return attr("DQSimVisible", true) end

-- ------------------------------------------------------------ builders
local function makeAttackModel(name, precastSize, hitBoxSize, cframe)
    local m = Instance.new("Model")
    m.Name = name
    local pp = Instance.new("Part")
    pp.Name = "PrimaryPart"
    pp.Size = Vector3.new(4, 1, 2)
    pp.Anchored = true pp.CanCollide = false pp.CanQuery = true pp.CanTouch = true
    pp.Transparency = 1
    pp.CFrame = cframe
    pp.Parent = m
    local pc = Instance.new("Part")
    pc.Name = "precast"
    pc.Size = precastSize
    pc.Anchored = true pc.CanCollide = false pc.CanQuery = true pc.CanTouch = true
    pc.Material = Enum.Material.Neon
    pc.Color = Color3.fromRGB(255, 0, 0)
    pc.Transparency = 1
    pc.CFrame = cframe * CFrame.new(0, precastSize.Y * 0.5 + 0.05, 0)
    pc.Parent = m
    local hb = Instance.new("Part")
    hb.Name = "hitBox"
    hb.Size = hitBoxSize
    hb.Anchored = true hb.CanCollide = false hb.CanQuery = true hb.CanTouch = true
    hb.Material = Enum.Material.Neon
    hb.Color = Color3.fromRGB(0, 213, 255)
    hb.Transparency = 1
    hb.CFrame = cframe * CFrame.new(0, hitBoxSize.Y * 0.5, 0)
    hb.Parent = m
    m.PrimaryPart = pp
    return m, pc, hb
end

-- ------------------------------------------------------------ attacks
-- Passive beam: a 250-stud line through the centre at an angle. In the real
-- fight nothing about it is visible on the Model; the harness shows the
-- precast when DQSimVisible so a person can follow along. Telegraph 1.5 s,
-- live 1.5 -> 5.5 s, removed at 7.0 s.
local beamTemplate = nil
for _, c in ipairs(WS:GetChildren()) do
    if c.Name == "firstBossPassiveBeam" and c:IsA("Model") then beamTemplate = beamTemplate or c end
end
-- What the fight save and the captures say about these beams: the parked
-- pool holds them at yaws 20 degrees apart (18.3, 38.3, 58.3 ... 178.3), and
-- the capture saw them appear every 0.5 s in bursts of 4 and 13, ten seconds
-- apart, each deleted at 7.0 s with nothing on the Model ever visible. So
-- a burst is a line sweeping round the boss 20 degrees per half second. How
-- long each line HURTS is the one thing no capture has shown; DQSimBeamHurt
-- picks the hypothesis ("pulse" or "long").
local function passiveBeam(angle)
    local cf = CFrame.new(CENTRE + Vector3.new(0, 0, 0)) * CFrame.Angles(0, angle, 0)
    local m, pc, hb
    if beamTemplate then
        m = beamTemplate:Clone()
        pc = m:FindFirstChild("precast")
        hb = m:FindFirstChild("hitBox")
        m:PivotTo(cf * CFrame.new(0, 24 - 21, 0))
    else
        m, pc, hb = makeAttackModel("firstBossPassiveBeam", Vector3.new(8, 2.1, 250), Vector3.new(8, 63.7, 250), cf)
    end
    m:SetAttribute("DQSim", true)
    m.Parent = WS
    Debris:AddItem(m, 7.0)
    local t0 = tick()
    if pc then pc.Transparency = 1 end
    local hurt = attr("DQSimBeamHurt", "pulse")
    if hb then
        if hurt == "long" then
            addLive(hb, 150, "passive beam", t0 + 0.5, t0 + 7.0)
        else
            addLive(hb, 150, "passive beam", t0 + 0.3, t0 + 1.0)
        end
    end
end

-- Mage shot: a 60-stud line from a caster position toward the player. Nothing
-- visible for 0.9 s, then the precast shows AND the hit lands. Removed at 8 s.
local MAGE_POSTS = {
    CENTRE + Vector3.new(48, 0, 0), CENTRE + Vector3.new(-34, 0, 40), CENTRE + Vector3.new(-30, 0, -42),
}
local function mageShot()
    local from = MAGE_POSTS[math.random(#MAGE_POSTS)]
    local target = nearestPlayerPosition(from) or CENTRE
    local flat = Vector3.new(target.X - from.X, 0, target.Z - from.Z)
    if flat.Magnitude < 1 then flat = Vector3.new(0, 0, -1) end
    local dir = flat.Unit
    local cf = CFrame.lookAt(from + dir * 30, from + dir * 60)
    local m, pc, hb = makeAttackModel("northernMageShot", Vector3.new(2, 1, 60.4), Vector3.new(3.1, 52.5, 60.4), cf)
    m.Parent = WS
    Debris:AddItem(m, 8.0)
    local t0 = tick()
    task.delay(0.9, function()
        if pc.Parent then pc.Transparency = visible() and 0.35 or 1 end
    end)
    addLive(hb, 100, "mage shot", t0 + 0.9, t0 + 1.2)
end

-- Line strike: a spearman's lunge, 31 studs long, from a post at the arena
-- edge toward the player. Hit at 0.4 s, removed at 7 s.
local function lineStrike(kind)
    local from = MAGE_POSTS[math.random(#MAGE_POSTS)] + Vector3.new(math.random(-15, 15), 0, math.random(-15, 15))
    local target = nearestPlayerPosition(from) or CENTRE
    local flat = Vector3.new(target.X - from.X, 0, target.Z - from.Z)
    if flat.Magnitude < 1 then flat = Vector3.new(0, 0, -1) end
    local dir = flat.Unit
    local cf = CFrame.lookAt(from + dir * 15.5, from + dir * 31)
    local m, pc, hb = makeAttackModel(kind, Vector3.new(11, 1, 31), Vector3.new(11, 4, 31), cf)
    m.Parent = WS
    Debris:AddItem(m, 7.0)
    local t0 = tick()
    -- The capture measured the real strikes at 0.88 s after appearing.
    -- Warning shown until then, then it fades at the hit.
    if visible() then pc.Transparency = 0.5 end
    task.delay(0.85, function() if pc.Parent then pc.Transparency = 1 end end)
    addLive(hb, 60, kind, t0 + 0.85, t0 + 1.15)
end

-- Boss projectiles over the real remote, on the game's clock, with a
-- server-side damaging mesh following the same motion.
local remote = RS:FindFirstChild("remotes") and RS.remotes:FindFirstChild("northernBossSpecficEvents")
local timeSyncOk, timeSync = pcall(function() return require(RS:WaitForChild("timeSync")) end)
local function gameTime()
    if timeSyncOk and timeSync and timeSync.GetTime then
        local ok, t = pcall(function() return timeSync:GetTime() end)
        if ok and t then return t end
    end
    return tick()
end
local function rollingProjectile(eventName, templateName, radius, damage, distance, duration, atPlayer)
    if not remote then return end
    local target = nearestPlayerPosition(CENTRE) or CENTRE
    local flat = Vector3.new(target.X - CENTRE.X, 0, target.Z - CENTRE.Z)
    if flat.Magnitude < 1 then flat = Vector3.new(0, 0, -1) end
    local dir = flat.Unit
    local startCF
    if atPlayer then
        -- The real criss cross: placed ON the player, then rolls off in some
        -- direction. It hurts while it sits there.
        local a = math.random() * math.pi * 2
        local d2 = Vector3.new(math.cos(a), 0, math.sin(a))
        local origin = Vector3.new(target.X, CENTRE.Y + radius, target.Z)
        startCF = CFrame.lookAt(origin, origin + d2 * 40)
    else
        startCF = CFrame.lookAt(CENTRE + Vector3.new(0, radius, 0) + dir * 8, CENTRE + Vector3.new(0, radius, 0) + dir * 40)
    end
    local t0 = gameTime() + 0.6          -- a short wind-up like the real one
    local t1 = t0 + duration
    remote:FireAllClients(eventName, { distance, duration, t0, t1, startCF })
    -- Server-side body for damage: an invisible sphere on the same schedule.
    local body = Instance.new("Part")
    body.Name = templateName .. "Body"
    body.Shape = Enum.PartType.Ball
    body.Size = Vector3.new(radius * 2, radius * 2, radius * 2)
    body.Anchored = true body.CanCollide = false body.CanQuery = false body.CanTouch = false
    body.Transparency = 1
    body.CFrame = startCF
    body.Parent = WS
    Debris:AddItem(body, duration + 1.5)
    local conn
    conn = RunService.Heartbeat:Connect(function()
        if not body.Parent then conn:Disconnect() return end
        local now = gameTime()
        local k = math.clamp((now - t0) / duration, 0, 1)
        body.CFrame = startCF + startCF.LookVector * (k * distance)
        if now > t1 then conn:Disconnect() end
    end)
    local realT0 = tick() + 0.6
    addLive(body, damage, eventName, atPlayer and tick() or realT0, realT0 + duration)
    log(eventName .. " fired")
end

-- ------------------------------------------------------------ schedule
local function rate() return math.max(attr("DQSimRate", 1.0), 0.1) end
local burstIndex = 0
local angle = 0
task.spawn(function()
    while true do
        task.wait(attr("DQSimBurstGap", 10) / rate())
        if attr("DQSimEnabled", true) and attr("DQSimBeams", true) then
            -- Alternate the short and the long burst the capture saw.
            burstIndex = (burstIndex or 0) + 1
            local count = (burstIndex % 2 == 1) and 13 or 4
            local step = math.rad(20) * ((math.random() < 0.5) and 1 or -1)
            angle = math.random() * math.pi * 2
            log(string.format("beam burst of %d, step %.0f deg", count, math.deg(step)))
            for i = 1, count do
                if not attr("DQSimEnabled", true) then break end
                passiveBeam(angle)
                angle = angle + step
                task.wait(0.5 / rate())
            end
        end
    end
end)
task.spawn(function()
    while true do
        task.wait(3.0 / rate())
        if attr("DQSimEnabled", true) and attr("DQSimMages", true) then mageShot() end
    end
end)
task.spawn(function()
    while true do
        task.wait(4.0 / rate())
        if attr("DQSimEnabled", true) and attr("DQSimStrikes", true) then
            lineStrike(math.random() < 0.5 and "spearmanStrikeHitbox" or "northernWarriorLineStrike")
        end
    end
end)
task.spawn(function()
    local i = 0
    while true do
        task.wait(8.0 / rate())
        if attr("DQSimEnabled", true) and attr("DQSimProjectiles", true) then
            i = i + 1
            if i % 3 == 1 then
                rollingProjectile("First Boss Criss Cross Projectile", "firstBossCrissCross", 7.5, 120, 90, 3.0, true)
            elseif i % 3 == 2 then
                rollingProjectile("First Boss Seeking Spike", "firstBossSeekingSpikes", 10, 120, 90, 2.5)
            else
                rollingProjectile("First Boss Big Spike", "firstBossBigSpike", 20, 200, 110, 3.5)
            end
        end
    end
end)

log("running: beam bursts (13 then 4, 20 deg per 0.5 s) every " .. tostring(attr("DQSimBurstGap", 10)) .. "s, hurt=" .. tostring(attr("DQSimBeamHurt", "pulse")) .. "; mage shot every 3s, strike every 4s, projectile every 8s (x DQSimRate). Telegraphs visible=" .. tostring(visible()))
]==]

local sim = Instance.new("Script")
sim.Name = "DQBossSim"
sim.Source = SOURCE
sim.Parent = ServerScriptService
print("[DQBossSim] installed at " .. sim:GetFullName())
