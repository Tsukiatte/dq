--[[
    studio_loader.lua - the DQHarness Loader (a LocalScript under
    StarterPlayer.StarterPlayerScripts.DQHarness). Installed by
    tools/studio_install.lua; the simulator is tools/studio_bosssim.lua.

    Mirrors main.lua's module wiring inside Studio, then adds what the
    harness needs: the teleport curtain removed, a state StringValue and a
    query BindableFunction (both under PlayerScripts.DQHarness because the
    game wipes PlayerGui on death), the farm switched on in Dodge mode, a
    follow camera (the saved place has no camera controller), and a swing
    hook that tells the simulator when the autofarm would attack.

    Query (DQHarnessQuery:Invoke(what, arg)):
      "danger"            danger at the root now / +0.6 / +1.2 s
      "detected" [n]      the hazard index, with arming state
      "arming" [n]        one line per tracked attack Model
      "watch" <ModelName> 9 s sampler of the next Model of that name
      "paths" [secs]      scripted projectile prediction vs sim body vs mesh
      "hitlog" [n]        HZ.hitLog tail
      "lifelog" [n]       HZ.lifeLog tail
      "delays"            learned arming delays and windows
      "set" {path,value}  assign any dotted S path (e.g. CFG.attackRange)
      "<dotted.path>"     describe any S value
]]
local ORDER = { "core", "gamedata", "uikit", "hazards", "precast", "bossevents", "nav", "mover", "dodge", "path", "streamer", "config", "ui", "main" }
local folder = script.Parent
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer
-- The game's own client scripts put up a teleport curtain while they wait for
-- a dungeon flow that never comes here.
task.spawn(function()
    while true do
        local gui = player:FindFirstChild("PlayerGui")
        if gui then
            for _, g in ipairs(gui:GetChildren()) do
                if g.Name == "teleportCurtainWhite" or g.Name == "teleportCurtain" then g:Destroy() end
            end
        end
        task.wait(1)
    end
end)
local S = {}
S.HARNESS = true
for _, name in ipairs(ORDER) do
    local module = require(folder:WaitForChild(name))
    if type(module) ~= "function" then error(("[DQHarness] %s did not return a module function"):format(name)) end
    local ok, err = pcall(module, S)
    if not ok then error(("[DQHarness] %s failed while loading: %s"):format(name, tostring(err))) end
end
print("[DQHarness] loaded " .. #ORDER .. " modules")

-- Harness objects live under PlayerScripts.DQHarness: the game wipes PlayerGui on death.
local state = Instance.new("StringValue")
state.Name = "DQHarnessState"
state.Parent = folder
local query = Instance.new("BindableFunction")
query.Name = "DQHarnessQuery"
query.Parent = folder

task.spawn(function()
    while true do
        local RT, HZ, DG, NAV, CFG, UI = S.RT, S.HZ, S.DG, S.NAV, S.CFG, S.UI
        local char = player.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        local enemies = 0
        if HZ then for _ in pairs(HZ.enemyModels) do enemies = enemies + 1 end end
        local info = {
            version = S.SCRIPT_VERSION, mode = RT and RT.mode, farm = RT and RT.farmEnabled,
            status = RT and RT.movementStatus or (UI and UI.hudStatus),
            pos = root and { math.floor(root.Position.X), math.floor(root.Position.Y), math.floor(root.Position.Z) } or nil,
            hp = hum and math.floor(hum.Health) or nil,
            detected = HZ and #HZ.detected, volumes = HZ and #HZ.volumes, enemies = enemies,
            dodgeActive = DG and DG.active, dangerHere = DG and DG.dangerHere, target = DG and DG.target and tostring(DG.target) or nil,
            reason = DG and DG.targetReason, gapWait = DG and DG.gapWait,
            cachedEnemy = NAV and NAV.cachedEnemy and NAV.cachedEnemy.Name or nil,
            moveMode = CFG and CFG.moveMode, zones = S.PC and #S.PC.zones, paths = S.PC and #S.PC.paths,
            simHits = workspace:GetAttribute("DQSimHits"), simDamage = workspace:GetAttribute("DQSimDamage"),
        }
        local ok, json = pcall(function() return HttpService:JSONEncode(info) end)
        state.Value = ok and json or ("encode failed: " .. tostring(json))
        task.wait(0.5)
    end
end)

local function describe(v, depth)
    depth = depth or 0
    local t = typeof(v)
    if t == "table" then
        local n = 0 for _ in pairs(v) do n = n + 1 end
        if depth >= 1 then return "table(" .. n .. ")" end
        local parts, shown = {}, 0
        for k, val in pairs(v) do
            shown = shown + 1
            if shown > 12 then parts[#parts + 1] = "..." break end
            parts[#parts + 1] = tostring(k) .. "=" .. describe(val, depth + 1)
        end
        return "{" .. table.concat(parts, ", ") .. "}"
    elseif t == "Instance" then
        return v.ClassName .. ":" .. v.Name .. "<" .. tostring(v.Parent and v.Parent.Name) .. ">"
    end
    return tostring(v)
end
local function rootPart() return player.Character and player.Character:FindFirstChild("HumanoidRootPart") end
local function armingLine(model, st)
    return string.format("%s present=%s age=%.1f armed=%s done=%s impact=%s liveUntil=%s ch=%d on=%d minT=%.2f ev=[%s]",
        st.name, tostring(model.Parent ~= nil), os.clock() - st.spawn, tostring(st.armedBy or (st.armedAt and "?" or "no")), tostring(st.doneAt ~= nil),
        st.impactAt and string.format("%.1f", st.impactAt - st.spawn) or "-", st.liveUntil and string.format("%.1f", st.liveUntil - st.spawn) or "-",
        #st.channels, st.lastOn or 0, st.minT < math.huge and st.minT or 1, table.concat(st.events, " "))
end
query.OnInvoke = function(what, arg)
    local ok, result = pcall(function()
        if what == "danger" then
            local root = rootPart()
            if not root then return "no root" end
            local p = root.Position
            local f = S.dodgeDangerAt
            return string.format("dangerAt(root) t0=%.2f t0.6=%.2f t1.2=%.2f | reach=%s halfHeight=%s dangerHere=%s", f(p.X, p.Y, p.Z, 0), f(p.X, p.Y, p.Z, 0.6), f(p.X, p.Y, p.Z, 1.2), tostring(S.DG.reach), tostring(S.DG.halfHeight), tostring(S.DG.dangerHere))
        elseif what == "detected" then
            local out, root = {}, rootPart()
            for i, part in ipairs(S.HZ.detected) do
                if i > (arg or 20) then out[#out + 1] = "..." break end
                local st = S.HZ.armState[part]
                out[#out + 1] = string.format("%s<%s> gt=%s tr=%.2f dist=%.1f %s", part.Name, tostring(part.Parent and part.Parent.Name), tostring(S.HZ.groundTruth[part]), part.Transparency,
                    root and (part.Position - root.Position).Magnitude or -1,
                    st and string.format("armed=%s done=%s impact=%s", tostring(st.armedBy or (st.armedAt and "?" or "no")), tostring(st.doneAt ~= nil), st.impactAt and string.format("%.1f", st.impactAt - st.spawn) or "-") or "st=nil")
            end
            return table.concat(out, "\n")
        elseif what == "arming" then
            local out = {}
            for model, st in pairs(S.HZ.arming) do
                if #out >= (arg or 15) then break end
                if model.Parent then out[#out + 1] = armingLine(model, st) end
            end
            return table.concat(out, "\n")
        elseif what == "watch" then
            -- Sample the next Model named `arg` for 9 s: what the CLIENT sees on its
            -- precast, and what the tracker records, every 0.25 s.
            local name = arg or "northernMageShot"
            local model
            local conn
            conn = workspace.ChildAdded:Connect(function(c) if c.Name == name and c:IsA("Model") then model = c end end)
            local t0 = os.clock()
            repeat task.wait(0.05) until model or os.clock() - t0 > 12
            conn:Disconnect()
            if not model then return "no " .. name .. " appeared in 12s" end
            local start = os.clock()
            local lines = { "watching " .. name }
            for i = 1, 36 do
                local pc = model:FindFirstChild("precast")
                local hb = model:FindFirstChild("hitBox")
                local st = S.HZ.arming[model]
                local root = rootPart()
                local dOn0, dOn6, inVol = -1, -1, false
                if hb and hb.Parent and root then
                    local p = S.volumeClosestPoint({ part = hb }, root.Position)
                    dOn0 = S.dodgeDangerAt(p.X, root.Position.Y, p.Z, 0)
                    dOn6 = S.dodgeDangerAt(p.X, root.Position.Y, p.Z, 0.6)
                    for _, v in ipairs(S.HZ.volumes) do if v.part == hb or v.part == pc then inVol = true break end end
                end
                lines[#lines + 1] = string.format("%.2f pc=%s hb=%s det=%s vol=%s dangerOnBeam(t0)=%.2f (t0.6)=%.2f st=%s", os.clock() - start,
                    pc and string.format("%.2f", pc.Transparency) or "nil", hb and "yes" or "nil",
                    tostring((function() for _, p in ipairs(S.HZ.detected) do if p == pc or p == hb then return true end end return false end)()),
                    tostring(inVol), dOn0, dOn6,
                    st and string.format("age=%.1f on=%d armed=%s done=%s dormant=%s impact=%s liveUntil=%s clockDelta=%.2f", os.clock() - st.spawn, st.lastOn or 0, tostring(st.armedBy or (st.armedAt and "?" or "no")), tostring(st.doneAt ~= nil), tostring(st.dormant), st.impactAt and string.format("%.1f", st.impactAt - st.spawn) or "-", st.liveUntil and string.format("%.1f", st.liveUntil - st.spawn) or "-", (S.DG.clock or 0) - os.clock()) or "nil")
                if not model.Parent then lines[#lines + 1] = "removed" break end
                task.wait(0.25)
            end
            return table.concat(lines, "\n")
        elseif what == "paths" then
            -- Poll for up to `arg` seconds (default 12) waiting for a path, then
            -- sample it every 0.25 s: where the dodge predicts it, where the
            -- sim's damaging body is, where the rendered mesh is, and the
            -- danger reading at our feet.
            local deadline = os.clock() + (arg or 12)
            repeat task.wait(0.1) until #S.PC.paths > 0 or os.clock() > deadline
            if #S.PC.paths == 0 then return "no path appeared" end
            local lines = {}
            for i = 1, 24 do
                local p = S.PC.paths[1]
                if not p then lines[#lines + 1] = "path gone" break end
                local now = workspace:GetServerTimeNow()
                local k = math.clamp((now - p.t0) / p.dur, 0, 1)
                local s = k * p.dist + p.offset
                local cx, cz = p.ox + p.dx * s, p.oz + p.dz * s
                local body = workspace:FindFirstChild("firstBossCrissCrossBody") or workspace:FindFirstChild("firstBossSeekingSpikesBody") or workspace:FindFirstChild("firstBossBigSpikeBody")
                local mesh = workspace:FindFirstChild("firstBossCrissCross") or workspace:FindFirstChild("firstBossSeekingSpikes") or workspace:FindFirstChild("firstBossBigSpike")
                local root = rootPart()
                lines[#lines + 1] = string.format("%s k=%.2f pred=(%.0f,%.0f) body=%s mesh=%s root=%s dangerHere=%.2f t0in=%.1f t1in=%.1f",
                    p.name, k, cx, cz,
                    body and string.format("(%.0f,%.0f,y%.0f)", body.Position.X, body.Position.Z, body.Position.Y) or "nil",
                    mesh and string.format("(%.0f,%.0f,y%.0f,tr%.1f)", mesh.Position.X, mesh.Position.Z, mesh.Position.Y, mesh.Transparency) or "nil",
                    root and string.format("(%.0f,%.0f)", root.Position.X, root.Position.Z) or "nil",
                    root and S.dodgeDangerAt(root.Position.X, root.Position.Y, root.Position.Z, 0) or -1,
                    p.t0 - now, p.t1 - now)
                task.wait(0.25)
            end
            return table.concat(lines, "\n")
        elseif what == "hitlog" then
            local n, out = #S.HZ.hitLog, {}
            for i = math.max(1, n - (arg or 12)), n do out[#out + 1] = S.HZ.hitLog[i] end
            return table.concat(out, "\n")
        elseif what == "lifelog" then
            local n, out = #S.HZ.lifeLog, {}
            for i = math.max(1, n - (arg or 10)), n do out[#out + 1] = S.HZ.lifeLog[i] end
            return table.concat(out, "\n")
        elseif what == "hubs" then
            -- Every hub: cadence, sweep step, the last headings, the predicted lines.
            local out = {}
            local nowc = os.clock()
            for model, hub in pairs(S.DG.hubs) do
                local angs = {}
                for i = math.max(1, #hub.angles - 3), #hub.angles do
                    local e = hub.angles[i]
                    angs[#angs + 1] = string.format("%.0fdeg@%.1fs", math.deg(e.a), e.t - nowc)
                end
                local preds = {}
                for i = 1, #(hub.pred or {}) do
                    local L = hub.pred[i]
                    preds[#preds + 1] = string.format("%.0fdeg from %.2f to %.2f", math.deg(L.a), L.from - nowc, L.untilAt - nowc)
                end
                out[#out + 1] = string.format("%s rate=%.2f period=%s fire=%s step=%s name=%s lastSpawn=%.1fs angles=[%s] pred=[%s]",
                    model.Name, hub.rate, tostring(hub.period), tostring(hub.fire), hub.step and string.format("%.0fdeg", math.deg(hub.step)) or "nil", tostring(hub.name), hub.lastSpawn - nowc, table.concat(angs, " "), table.concat(preds, " | "))
            end
            return #out > 0 and table.concat(out, "\n") or "no hubs"
        elseif what == "delays" then
            return describe(S.RT.armDelays) .. " spans=" .. describe(S.RT.armSpans)
        elseif what == "set" then
            local t = S
            local keys = string.split(arg.path, ".")
            for i = 1, #keys - 1 do t = t[keys[i]] end
            local last = keys[#keys]
            t[last] = arg.value
            return "set " .. arg.path .. " = " .. tostring(arg.value)
        else
            local t = S
            for _, key in ipairs(string.split(what, ".")) do
                if t == nil then break end
                t = t[key]
            end
            return describe(t)
        end
    end)
    return ok and result or ("ERR " .. tostring(result))
end

-- Switch the farm on once the character exists, in Dodge mode.
task.spawn(function()
    repeat task.wait(0.5) until player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    task.wait(2)
    if S.setMode then S.setMode("clone") end
    if S.RT then S.RT.farmEnabled = true end
    -- Abilities win boss fights: Q/E on, gated to the ability radius.
    if S.RT then S.RT.autoQEnabled = true S.RT.autoEEnabled = true end
    if S.CFG then S.CFG.abilityRadiusEnabled = true S.CFG.abilityRadius = 30 end
    print("[DQHarness] farm enabled")
end)
-- Swings: the real swing needs the executor's input injection, so the sim
-- gets told instead. RT.gameSpecificAttackMethod is set once the game is
-- detected; wrap it when it appears.
task.spawn(function()
    local RS = game:GetService("ReplicatedStorage")
    local remote = RS:WaitForChild("DQSimAttack", 30)
    if not remote then warn("[DQHarness] no DQSimAttack remote") return end
    repeat task.wait(0.25) until S.RT and S.RT.gameSpecificAttackMethod
    local orig = S.RT.gameSpecificAttackMethod
    local last = 0
    S.RT.gameSpecificAttackMethod = function(enemy)
        pcall(orig, enemy)
        if os.clock() - last >= 0.1 then
            last = os.clock()
            remote:FireServer("swing")
        end
    end
    S.RT.abilityHook = function(key)
        remote:FireServer("ability", tostring(key))
    end
    print("[DQHarness] swing hook installed")
end)

-- DQ follow camera: this saved place has no camera controller.
task.spawn(function()
    local cam = workspace.CurrentCamera
    RunService.RenderStepped:Connect(function()
        local char = player.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if not root then return end
        cam.CameraType = Enum.CameraType.Scriptable
        cam.CFrame = CFrame.lookAt(root.Position + Vector3.new(0, 45, 55), root.Position)
    end)
end)
