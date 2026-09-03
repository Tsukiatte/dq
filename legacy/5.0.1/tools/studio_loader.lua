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

    The harness is for mechanics (does a tween move, does a hook fire), not
    for numbers: its attack density is about five times the real fight's.

    Query (DQHarnessQuery:Invoke(what, arg)):
      "danger"            danger at the root now / +0.6 / +1.2 s
      "detected" [n]      what can hurt now or within a second
      "attacks" [n]       every tracked attack record
      "hitlog" [n]        HZ.hitLog tail
      "capture"           the capture report text
      "status"            the HUD movement line and the dodge's state
      "set" {path,value}  assign any dotted S path (e.g. CFG.bossStandoff)
      "<dotted.path>"     describe any S value
]]
local ORDER = { "core", "gamedata", "uikit", "reader", "field", "bosses", "mover", "dodge", "pursuit", "draw", "tools", "path", "streamer", "config", "ui", "main" }
local folder = script.Parent
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer
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

local state = Instance.new("StringValue")
state.Name = "DQHarnessState"
state.Parent = folder
local query = Instance.new("BindableFunction")
query.Name = "DQHarnessQuery"
query.Parent = folder

local function rootPart() return player.Character and player.Character:FindFirstChild("HumanoidRootPart") end

task.spawn(function()
    while true do
        local RT, HZ, DG, NAV, CFG = S.RT, S.HZ, S.DG, S.NAV, S.CFG
        local root = rootPart()
        local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
        local info = {
            version = S.SCRIPT_VERSION, mode = RT and RT.mode, farm = RT and RT.farmEnabled,
            status = RT and RT.movementStatus,
            pos = root and { math.floor(root.Position.X), math.floor(root.Position.Y), math.floor(root.Position.Z) } or nil,
            hp = hum and math.floor(hum.Health) or nil,
            detected = HZ and #HZ.detected, attacks = HZ and #HZ.attacks, enemies = HZ and #HZ.enemies,
            dangerHere = DG and DG.dangerHere, target = DG and DG.target and tostring(DG.target) or nil,
            reason = DG and DG.targetReason, gapWait = DG and DG.gapWait, pursuitBlocked = DG and DG.pursuitBlocked,
            cachedEnemy = NAV and NAV.cachedEnemy and NAV.cachedEnemy.Name or nil,
            moveMode = CFG and CFG.moveMode, deaths = RT and RT.deaths,
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
local function recLine(rec, now, root)
    local open, close = S.attackWindow(rec)
    local d = -1
    if root then
        local ok, dist = pcall(S.attackDistance, rec, root.Position.X, root.Position.Z, now)
        if ok then d = dist end
    end
    return string.format("%s kind=%s age=%.2f tr=%.2f vis@%s flash@%s fade@%s T=%s window=%s..%s dist=%.1f%s",
        rec.name, rec.kind, now - rec.spawn, rec.tr or 1,
        rec.visAt and string.format("%.2f", rec.visAt - rec.spawn) or "-",
        rec.flashAt and string.format("%.2f", rec.flashAt - rec.spawn) or "-",
        rec.fadeAt and string.format("%.2f", rec.fadeAt - rec.spawn) or "-",
        rec.flashTime and string.format("%.2f", rec.flashTime) or "-",
        open and string.format("%+.2f", open - now) or "-", close and close < math.huge and string.format("%+.2f", close - now) or "-",
        d, rec.pre and " pre" or "")
end
query.OnInvoke = function(what, arg)
    local ok, result = pcall(function()
        local now = os.clock()
        local root = rootPart()
        if what == "danger" then
            if not root then return "no root" end
            local p = root.Position
            S.fieldRefresh(now)
            return string.format("dangerAt(root) t0=%.2f t0.6=%.2f t1.2=%.2f | dangerHere=%s target=%s reason=%s",
                S.dangerAt(p.X, p.Z, now), S.dangerAt(p.X, p.Z, now + 0.6), S.dangerAt(p.X, p.Z, now + 1.2),
                tostring(S.DG.dangerHere), tostring(S.DG.target), tostring(S.DG.targetReason))
        elseif what == "detected" or what == "attacks" then
            local list = what == "detected" and S.HZ.detected or S.HZ.attacks
            local out = {}
            for i, rec in ipairs(list) do
                if i > (arg or 20) then out[#out + 1] = "..." break end
                out[#out + 1] = recLine(rec, now, root)
            end
            return #out > 0 and table.concat(out, "\n") or "none"
        elseif what == "hitlog" then
            local n, out = #S.HZ.hitLog, {}
            for i = math.max(1, n - (arg or 12)), n do out[#out + 1] = S.HZ.hitLog[i] end
            return table.concat(out, "\n")
        elseif what == "capture" then
            return S.buildAttackLog()
        elseif what == "status" then
            return string.format("move=%s | enemy=%s | dangerHere=%.2f target=%s reason=%s gapWait=%s pursuitBlocked=%s | route=%s",
                tostring(S.RT.movementStatus), tostring(S.NAV.cachedEnemy and S.NAV.cachedEnemy.Name),
                S.DG.dangerHere or 0, tostring(S.DG.target), tostring(S.DG.targetReason), tostring(S.DG.gapWait), tostring(S.DG.pursuitBlocked),
                S.NAV.route and (S.NAV.route.waypoints and (#S.NAV.route.waypoints .. " wps") or "direct") or "none")
        elseif what == "set" then
            local t = S
            local keys = string.split(arg.path, ".")
            for i = 1, #keys - 1 do t = t[keys[i]] end
            t[keys[#keys]] = arg.value
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

-- Switch the farm on once the character exists, in Dodge mode, abilities on.
task.spawn(function()
    repeat task.wait(0.5) until player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    task.wait(2)
    if S.setMode then S.setMode("clone") end
    if S.RT then
        S.RT.farmEnabled = true
        S.RT.autoQEnabled = true
        S.RT.autoEEnabled = true
    end
    if S.CFG then S.CFG.abilityRadiusEnabled = true S.CFG.abilityRadius = 30 end
    print("[DQHarness] farm enabled")
end)
-- Swings and abilities are told to the simulator; the real inputs need the executor.
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
    S.RT.abilityHook = function(key) remote:FireServer("ability", tostring(key)) end
    print("[DQHarness] swing hook installed")
end)
-- Follow camera: this saved place has no camera controller.
task.spawn(function()
    local cam = workspace.CurrentCamera
    RunService.RenderStepped:Connect(function()
        local root = rootPart()
        if not root then return end
        cam.CameraType = Enum.CameraType.Scriptable
        cam.CFrame = CFrame.lookAt(root.Position + Vector3.new(0, 45, 55), root.Position)
    end)
end)
