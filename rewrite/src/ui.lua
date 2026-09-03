-- ui.lua - The HUD and the control windows, built from the kit.
-- Module contract: receives the shared table S; imports from core, uikit,
-- reader, field, mover, brain, draw, lobby, config.
return function(S)
local K = S.UIKit
local T = K.Theme
local CFG = S.CFG
local RT = S.RT
local UI = S.UI
local RD = S.RD
local DG = S.DG
local BR = S.BR
local SCRIPT_VERSION = S.SCRIPT_VERSION
local LocalPlayer = S.LocalPlayer
local Players = S.Players
local RunService = S.RunService
local UserInputService = S.UserInputService
local Workspace = S.Workspace
local sliderConnections = S.sliderConnections
local releaseMover = S.releaseMover
local restoreWalkSpeed = S.restoreWalkSpeed
local readerStop = S.readerStop
local clearDrawing = S.clearDrawing
local saveConfig = S.saveConfig
local loadConfig = S.loadConfig
local heavyDebug = S.heavyDebug

local windows = {}
local guiOpen = false
local widgets = {}
local function track(w) widgets[#widgets + 1] = w return w end
local function refreshAll() for _, w in ipairs(widgets) do if w.render then pcall(w.render) end end end

-- ------------------------------------------------------------ teardown
local function destructScript()
    if RT.destroyed then return end
    RT.destroyed = true
    pcall(saveConfig)
    for _, c in ipairs(sliderConnections) do pcall(function() c:Disconnect() end) end
    table.clear(sliderConnections)
    if RT.hudConnection then RT.hudConnection:Disconnect() RT.hudConnection = nil end
    if RT.mainConnection then RT.mainConnection:Disconnect() RT.mainConnection = nil end
    local c = LocalPlayer.Character
    local hum = c and c:FindFirstChildOfClass("Humanoid")
    local root = c and c:FindFirstChild("HumanoidRootPart")
    pcall(releaseMover, hum, root)
    pcall(restoreWalkSpeed, hum)
    pcall(readerStop)
    pcall(clearDrawing)
    if RT.blurEffect then RT.blurEffect:Destroy() RT.blurEffect = nil end
    if RT.visualRoot then RT.visualRoot:Destroy() RT.visualRoot = nil end
    if RT.scriptGui then RT.scriptGui:Destroy() RT.scriptGui = nil end
    if _G.DungeonAutofarmDestruct == destructScript then _G.DungeonAutofarmDestruct = nil end
    if _G.DungeonAutofarmVersion == SCRIPT_VERSION then _G.DungeonAutofarmVersion = nil end
    if _G.DungeonAutofarmState == S then _G.DungeonAutofarmState = nil end
end
_G.DungeonAutofarmDestruct = destructScript

-- ------------------------------------------------------------ build
local function buildUI()
    local playerGui = LocalPlayer:WaitForChild("PlayerGui")
    local old = playerGui:FindFirstChild("DungeonAutofarmUI")
    if old then old:Destroy() end
    local gui = Instance.new("ScreenGui")
    gui.Name = "DungeonAutofarmUI"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 100
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.Parent = playerGui
    RT.scriptGui = gui
    K.ensureTip(gui)

    local camera = Workspace.CurrentCamera
    local vw = camera and camera.ViewportSize.X or 1600
    local vh = camera and camera.ViewportSize.Y or 900
    local windowH = math.clamp(vh - 140, 320, 640)
    local function place(x, y, w, h)
        return UDim2.fromOffset(math.clamp(x, 8, math.max(8, vw - w - 8)), math.clamp(y, 8, math.max(8, vh - h - 8)))
    end
    local applyVisibility
    local function win(name, title, x, y, w, h, info)
        local api = K.window(gui, { onPinChanged = function() applyVisibility() end, name = name, title = title,
            width = w, height = h, position = place(x, y, w, h), visible = false, info = info })
        windows[name] = api
        return api
    end
    local autofarm = win("Autofarm", "Autofarm", 24, 24, 320, windowH, "Everything the bot does while it runs.")
    local dodge = win("Dodge", "Dodge", 360, 24, 320, windowH, "How the field reads danger and picks a spot.")
    local queue = win("Queue", "Auto queue", 696, 24, 310, 540, "The loop outside the fight.")
    local overlays = win("Overlays", "Overlays", 1022, 24, 300, 420, "What is drawn in the world.")
    local configs = win("Configs", "Configs", 1022, 460, 300, 200, "Settings on disk.")

    -- ---------------------------------------------------------------- Autofarm
    local n = 0
    local function next() n = n + 1 return n end
    local body = autofarm.body
    local master = track(K.toggle(body, "Enable Autofarm", function() return RT.farmEnabled end, function(v)
        RT.farmEnabled = v
        if not v then
            local c = LocalPlayer.Character
            pcall(releaseMover, c and c:FindFirstChildOfClass("Humanoid"), c and c:FindFirstChild("HumanoidRootPart"))
        end
    end, next(), "The master switch. Off in the lobby and on in a dungeon by itself when Auto queue's place rule is on."))
    UI.masterRender = master.render

    local combat = K.section(body, "Fighting", next(), "Range, abilities and the swing.")
    track(K.toggle(combat.content, "Auto Q", function() return CFG.autoQ end, function(v) CFG.autoQ = v end, 1, "Press Q on cooldown while the target is inside the ability radius."))
    track(K.toggle(combat.content, "Auto E", function() return CFG.autoE end, function(v) CFG.autoE = v end, 2, "Press E on cooldown while the target is inside the ability radius."))
    track(K.toggle(combat.content, "Auto attack", function() return CFG.autoAttack end, function(v) CFG.autoAttack = v end, 3, "Swing the weapon while the target is in reach. Off for high-level dungeons: abilities only."))
    track(K.slider(combat.content, "Ability radius", "studs", 15, 50, false, function() return CFG.abilityRadius end, function(v) CFG.abilityRadius = v end, 4, "Q and E fire only with the target inside this."))
    track(K.slider(combat.content, "Attack range", "studs", 4, 20, false, function() return CFG.attackRange end, function(v) CFG.attackRange = v end, 5, "The weapon's reach."))
    combat.setOpen(true)

    local standing = K.section(body, "Standing", next(), "How far from each kind of enemy to fight.")
    track(K.slider(standing.content, "Boss standoff", "studs", 10, 60, false, function() return CFG.bossStandoff end, function(v) CFG.bossStandoff = v end, 1, "Inside ability range, outside its melee."))
    track(K.slider(standing.content, "Mob standoff", "studs", 15, 50, false, function() return CFG.mobStandoff end, function(v) CFG.mobStandoff = v end, 2, "From any mob, past its body. Abilities reach about 40; at high level one swing or shot kills, so never inside weapon reach."))
    track(K.toggle(standing.content, "Strafe at standoff", function() return CFG.strafe end, function(v) CFG.strafe = v end, 4, "Circle the target instead of standing still."))
    track(K.slider(standing.content, "Strafe speed", "of walk", 0.2, 1.0, true, function() return CFG.strafeSpeedFraction end, function(v) CFG.strafeSpeedFraction = v end, 5, "Fraction of the walking speed used while circling."))

    local moving = K.section(body, "Moving", next(), "The tween along the floor.")
    track(K.slider(moving.content, "Walk", "studs/s", 12, 30, false, function() return CFG.tweenWalk end, function(v) CFG.tweenWalk = v end, 1, "Speed assumed when planning a walk. The character walks at its own WalkSpeed; only the escape burst changes it."))
    track(K.slider(moving.content, "Escape", "studs/s", 12, 34, false, function() return CFG.tweenEscape end, function(v) CFG.tweenEscape = v end, 2, "Speed while leaving danger."))

    -- ---------------------------------------------------------------- Dodge
    local d = dodge.body
    K.caption(d, "Every attack becomes a box with a live window. A ring of spots round you is scored at the moments each would be reached; danger already on you is discounted only until the ground under you fires.", 1)
    track(K.slider(d, "Reach", "studs", 8, 30, false, function() return CFG.dodgeReach end, function(v) CFG.dodgeReach = v end, 2, "Radius of the ring of spots."))
    track(K.slider(d, "Lead", "s", 0.3, 2.0, true, function() return CFG.dodgeLead end, function(v) CFG.dodgeLead = v end, 3, "A standing telegraph counts as live this long before it fires."))
    track(K.slider(d, "Path lead", "s", 0.1, 1.0, true, function() return CFG.dodgePathLead end, function(v) CFG.dodgePathLead = v end, 4, "A moving projectile's line counts as live this long before it arrives: the time to step aside."))
    track(K.slider(d, "Dwell", "s", 0.2, 1.5, true, function() return CFG.dodgeDwell end, function(v) CFG.dodgeDwell = v end, 5, "A spot must stay clear this long after arrival."))
    track(K.slider(d, "Move at", "danger", 0.05, 0.6, true, function() return CFG.dodgeMoveAt end, function(v) CFG.dodgeMoveAt = v end, 6, "Danger here at or above this: relocate."))
    track(K.slider(d, "Far look", "x reach", 1.0, 4.0, true, function() return CFG.dodgeFarScale end, function(v) CFG.dodgeFarScale = v end, 7, "When nothing within reach is safe, look this many times further, once."))
    track(K.slider(d, "Strafe bias", "", 0, 0.5, true, function() return CFG.dodgeStrafeWeight end, function(v) CFG.dodgeStrafeWeight = v end, 8, "Preference for moving across the target's line rather than along it."))
    track(K.slider(d, "Default fire", "s", 0.3, 3.0, true, function() return CFG.defaultFire end, function(v) CFG.defaultFire = v end, 9, "A telegraphed attack with no seed is assumed to fire this long after it appears."))
    track(K.slider(d, "Default live", "s", 0.2, 3.0, true, function() return CFG.defaultLive end, function(v) CFG.defaultLive = v end, 10, "And to hurt for this long."))

    -- ---------------------------------------------------------------- Queue
    local q = K.section(queue.body, "Queue", 1, "Queue the next run from the lobby, and replay a finished one.")
    K.caption(q.content, "In the lobby a party for the map and difficulty below is created and started through the game's own lobby remotes. In a run, when the dungeon ends and you own the party, the same replay the Replay button sends goes out.", 1)
    track(K.toggle(q.content, "Auto queue", function() return CFG.autoQueue end, function(v) CFG.autoQueue = v if S.LB then S.LB.arrivedAt = nil S.LB.lastAttempt = -math.huge end end, 2, "Queue and replay on their own."))
    track(K.toggle(q.content, "Press START in the dungeon", function() return CFG.autoStartDungeon end, function(v) CFG.autoStartDungeon = v end, 2.4, "A queued run waits at the spawn until START is pressed; the script presses it."))
    track(K.toggle(q.content, "Autofarm off in lobby, on in dungeon", function() return CFG.autoFarmByPlace end, function(v) CFG.autoFarmByPlace = v if S.LB then S.LB.farmAppliedFor = nil end end, 2.5, "The master switch follows the place, once per place change."))
    local mapOptions, diffOptions = {}, {}
    for i, name in ipairs(S.QUEUE_MAPS or {}) do mapOptions[i] = { value = name, label = name } end
    for i, name in ipairs(S.QUEUE_DIFFICULTIES or {}) do diffOptions[i] = { value = name, label = name } end
    track(K.dropdown(q.content, "Map", mapOptions, function() return CFG.autoQueueMap end, function(v) CFG.autoQueueMap = v end, 3, "The dungeon to queue, by the name on its lobby tile."))
    track(K.dropdown(q.content, "Difficulty", diffOptions, function() return CFG.autoQueueDifficulty end, function(v) CFG.autoQueueDifficulty = v end, 4, "The difficulty tile."))
    track(K.toggle(q.content, "Hardcore", function() return CFG.autoQueueHardcore end, function(v) CFG.autoQueueHardcore = v end, 5, "One life for everyone in the party."))
    track(K.toggle(q.content, "Private party", function() return CFG.autoQueuePrivate end, function(v) CFG.autoQueuePrivate = v end, 6, "Nobody joins uninvited."))
    track(K.slider(q.content, "Lobby delay", "s", 2, 30, false, function() return CFG.autoQueueDelay end, function(v) CFG.autoQueueDelay = v end, 7, "Seconds in the lobby before queueing."))
    track(K.toggle(q.content, "Replay when a run ends", function() return CFG.autoQueueReplay end, function(v) CFG.autoQueueReplay = v end, 8, "As the party owner, send the game's own replay when the run ends."))
    local queueLabel = K.label(q.content, "", "captionSub", 10)
    queueLabel.Size = UDim2.new(1, 0, 0, 22)
    S.refreshQueuePanel = function()
        if queueLabel.Parent then queueLabel.Text = "Queue: " .. tostring(S.LB and S.LB.status or "off") end
    end
    S.refreshQueuePanel()
    local qb = K.buttonRow(q.content, 11)
    qb.add("Queue now", "accent", function() if S.queueNow then S.queueNow("button") end end)
    qb.add("Replay now", "accent", function() if S.replayNow then S.replayNow() end end)
    q.setOpen(true)

    -- ---------------------------------------------------------------- Overlays
    local o = overlays.body
    track(K.toggle(o, "Draw attacks", function() return CFG.drawHazards end, function(v) CFG.drawHazards = v if not v then clearDrawing() end end, 1, "One translucent box per attack, coloured by stage."))
    track(K.toggle(o, "Draw the spot", function() return CFG.drawTarget end, function(v) CFG.drawTarget = v end, 2, "The spot the field is heading for."))
    track(K.slider(o, "Box transparency", "", 0.3, 0.95, true, function() return CFG.hazardTransparency end, function(v) CFG.hazardTransparency = v end, 3, "How see-through the attack boxes are."))
    track(K.colorRow(o, "Safe to cross", function() return CFG.colorFloor end, function(c) CFG.colorFloor = c end, 4, "Not firing for a while yet."))
    track(K.colorRow(o, "About to fire", function() return CFG.colorSoon end, function(c) CFG.colorSoon = c end, 5, "Inside the lead."))
    track(K.colorRow(o, "Live", function() return CFG.colorLive end, function(c) CFG.colorLive = c end, 6, "Hurts now."))

    -- ---------------------------------------------------------------- Configs
    local cb = configs.body
    K.caption(cb, string.format("Version %s. Settings save on their own whenever they change, when a teleport begins, and when the script is closed.", SCRIPT_VERSION), 1)
    local row = K.buttonRow(cb, 2)
    row.add("Save now", "accent", function() saveConfig() end)
    row.add("Reload", "accent", function() loadConfig() refreshAll() end)
    track(K.toggle(cb, "Debug prints", function() return CFG.debugPrints end, function(v) CFG.debugPrints = v end, 3, "Log what the script decides to the console."))
    K.button(cb, "Close the script", "danger", function() destructScript() end, 4, "Remove everything this script made and stop.")

    -- ---------------------------------------------------------------- open/close
    local dim = Instance.new("Frame")
    dim.Name = "Dim"
    dim.BackgroundColor3 = Color3.new(0, 0, 0)
    dim.BackgroundTransparency = 0.5
    dim.BorderSizePixel = 0
    dim.Size = UDim2.fromScale(1, 1)
    dim.Visible = false
    dim.ZIndex = 1
    dim.Parent = gui

    applyVisibility = function()
        for _, w in pairs(windows) do w.frame.Visible = guiOpen or w.isPinned() end
        dim.Visible = guiOpen
        if not guiOpen then K.hideTip() end
    end
    local function setOpen(open)
        guiOpen = open and true or false
        applyVisibility()
    end
    sliderConnections[#sliderConnections + 1] = UserInputService.InputBegan:Connect(function(input, processed)
        if processed then return end
        if input.KeyCode.Name == CFG.menuKey then setOpen(not guiOpen) end
    end)
    applyVisibility()

    -- ---------------------------------------------------------------- HUD
    local hud = Instance.new("Frame")
    hud.Name = "HUD"
    hud.BackgroundColor3 = T.SurfaceHeader or Color3.fromRGB(24, 24, 30)
    hud.BackgroundTransparency = 0.15
    hud.BorderSizePixel = 0
    hud.Size = UDim2.fromOffset(250, 86)
    hud.Position = UDim2.new(0, 12, 1, -98)
    hud.ZIndex = 2
    hud.Parent = gui
    K.corner(hud, 6)
    K.vlist(hud, 2)
    K.pad(hud, 6, 8, 6, 8)
    local function line(text, order)
        local l = K.label(hud, text, "captionSub", order)
        l.Size = UDim2.new(1, 0, 0, 16)
        l.TextXAlignment = Enum.TextXAlignment.Left
        l.TextTruncate = Enum.TextTruncate.AtEnd
        return l
    end
    local hudTitle = line("dqr autofarm  " .. SCRIPT_VERSION, 1)
    local hudStatus = line("", 2)
    local hudTarget = line("", 3)
    local hudWorld = line("[" .. CFG.menuKey .. "] opens the interface", 4)
    local frames, elapsed, fps = 0, 0, 0
    RT.hudConnection = RunService.Heartbeat:Connect(function(dt)
        if RT.destroyed then return end
        frames, elapsed = frames + 1, elapsed + dt
        if elapsed >= 0.5 then fps = frames / elapsed frames, elapsed = 0, 0 end
        hudStatus.Text = string.format("%s  |  %s", RT.farmEnabled and "running" or "off", tostring(RT.movementState))
        hudStatus.TextColor3 = RT.farmEnabled and (T.StatusGood or Color3.fromRGB(90, 220, 120)) or (T.StatusBad or Color3.fromRGB(230, 90, 90))
        local t = BR.target
        hudTarget.Text = t and string.format("target: %s  %.0f%%", t.model.Name, t.humanoid.Health / math.max(t.humanoid.MaxHealth, 1) * 100) or "target: none"
        hudWorld.Text = string.format("%d enemies  %d hazards  fps %d  %.1fms", #RD.enemies, RD.count, math.floor(fps + 0.5), RT.tickMs or 0)
    end)
end

S.buildUI = buildUI
S.destructScript = destructScript
S.setLoopButtonState = function() if UI.masterRender then pcall(UI.masterRender) end end
S.refreshAllWidgets = refreshAll
end
