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
    track(K.slider(combat.content, "Ability radius", "studs", 15, 80, false, function() return CFG.abilityRadius end, function(v) CFG.abilityRadius = v end, 4, "Q and E fire only with the target inside this."))
    track(K.slider(combat.content, "Attack range", "studs", 4, 20, false, function() return CFG.attackRange end, function(v) CFG.attackRange = v end, 5, "The weapon's reach."))
    combat.setOpen(true)

    local standing = K.section(body, "Standing", next(), "How far from each kind of enemy to fight.")
    track(K.toggle(standing.content, "Standoff from ability range", function() return CFG.autoStandoff end, function(v) CFG.autoStandoff = v end, 0, "Measure how far your ability reaches from where it lands, and fight bosses from just inside that. The slider below is used until it has been measured, or when this is off."))
    local rangeCaption = K.caption(standing.content, "Ability range: not measured yet", 0)
    track(K.slider(standing.content, "Boss standoff", "studs", 10, 80, false, function() return CFG.bossStandoff end, function(v) CFG.bossStandoff = v end, 1, "Inside ability range, outside its melee."))
    track(K.slider(standing.content, "Mob standoff", "studs", 15, 50, false, function() return CFG.mobStandoff end, function(v) CFG.mobStandoff = v end, 2, "From any mob, past its body. Abilities reach about 40; at high level one swing or shot kills, so never inside weapon reach."))
    track(K.toggle(standing.content, "Strafe at standoff", function() return CFG.strafe end, function(v) CFG.strafe = v end, 4, "Circle the target instead of standing still."))
    track(K.slider(standing.content, "Strafe speed", "of walk", 0.2, 1.0, true, function() return CFG.strafeSpeedFraction end, function(v) CFG.strafeSpeedFraction = v end, 5, "Fraction of the walking speed used while circling."))

    local moving = K.section(body, "Moving", next(), "The tween along the floor.")
    track(K.slider(moving.content, "Walk", "studs/s", 12, 30, false, function() return CFG.tweenWalk end, function(v) CFG.tweenWalk = v end, 1, "Speed assumed when planning a walk. The character walks at its own WalkSpeed; only the escape burst changes it."))
    track(K.slider(moving.content, "Escape", "studs/s", 12, 34, false, function() return CFG.tweenEscape end, function(v) CFG.tweenEscape = v end, 2, "Speed while leaving danger."))

    -- ---------------------------------------------------------------- Dodge
    local d = dodge.body
    track(K.toggle(d, "Blink out of hitboxes", function() return CFG.blink end, function(v) CFG.blink = v end, 0, "A hop of a few studs when a lethal box covers you and fires before you could walk out. Only onto floor at the same height."))
    track(K.slider(d, "Blink distance", "studs", 4, 8, false, function() return CFG.blinkMax end, function(v) CFG.blinkMax = v end, 0, "At most this far; the nearest clear spot wins."))
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
    track(K.toggle(q.content, "Stay for the bonus boss", function() return CFG.bonusBoss end, function(v) CFG.bonusBoss = v end, 7.5, "After the last boss the game asks whether to stay and fight the bonus boss. Off answers no; its attacks are not mapped yet."))
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
    -- Bottom-left, as the old build drew it: title chip, stat card, then the
    -- hint and the status pill. Fixed geometry throughout: auto-sizing frames
    -- anchored to the bottom never settled to a stable size in game.
    local hud = Instance.new("Frame")
    hud.Name = "HUD"
    hud.BackgroundTransparency = 1
    hud.AnchorPoint = Vector2.new(0, 1)
    hud.Position = UDim2.new(0, 20, 1, -20)
    hud.Size = UDim2.fromOffset(360, 173)
    hud.ZIndex = 2
    hud.Parent = gui

    -- A rounded panel with the accent along its top edge. The accent is a
    -- pill inset from the corners: a full-width square bar poked out past
    -- the rounding (ClipsDescendants clips to the rectangle, not the curve).
    local function panel(name, y, w, h, radius)
        local p = Instance.new("Frame")
        p.Name = name
        p.BackgroundColor3 = Color3.new(1, 1, 1)
        p.BorderSizePixel = 0
        p.Position = UDim2.fromOffset(0, y)
        p.Size = UDim2.fromOffset(w, h)
        p.ZIndex = 3
        p.Parent = hud
        K.corner(p, radius)
        K.stroke(p, T.Hairline, 1)
        K.bodyGradient(p)
        K.shadow(p, 6, 2.0, 8, 0.065, radius)
        local bar = Instance.new("Frame")
        bar.Name = "AccentBar"
        bar.BackgroundColor3 = Color3.new(1, 1, 1)
        bar.BorderSizePixel = 0
        bar.Position = UDim2.fromOffset(4, 0)
        bar.Size = UDim2.new(1, -8, 0, 3)
        bar.ZIndex = 5
        bar.Parent = p
        K.corner(bar, 2)
        K.accentGradient(bar, 0)
        return p
    end

    -- Title chip: name | build | fps.
    local chip = panel("TitleChip", 0, 326, 34, T.RadiusMd)
    local function chipText(text, style, x, width)
        local l = K.label(chip, text, style, 1)
        l.Position = UDim2.fromOffset(x, 7)
        l.Size = UDim2.fromOffset(width, 20)
        l.TextTruncate = Enum.TextTruncate.AtEnd
        l.ZIndex = 4
        return l
    end
    chipText("dqr pathfinding", "windowChip", 12, 138)
    chipText("|", "captionKey", 154, 6).TextColor3 = T.TextMuted
    chipText(SCRIPT_VERSION, "rowStat", 168, 70).TextColor3 = T.TextSub
    chipText("|", "captionKey", 240, 6).TextColor3 = T.TextMuted
    local fpsLabel = chipText("fps: --", "monoStat", 254, 66)

    -- Stat card: label left, value right in mono so the digits sit still.
    local stats = panel("Stats", 42, 360, 95, T.RadiusLg)
    local function statRow(name, y)
        local key = K.label(stats, name, "rowStat", 1)
        key.Position = UDim2.fromOffset(14, y)
        key.Size = UDim2.fromOffset(120, 24)
        key.ZIndex = 4
        local value = K.label(stats, "--", "monoStat", 2)
        value.Position = UDim2.fromOffset(140, y)
        value.Size = UDim2.fromOffset(206, 24)
        value.TextXAlignment = Enum.TextXAlignment.Right
        value.TextTruncate = Enum.TextTruncate.AtEnd
        value.ZIndex = 4
        return value
    end
    local playtimeValue = statRow("Playtime", 11)
    local statusValue = statRow("Status", 37)
    local pingValue = statRow("Ping", 63)

    -- Footer: the hint and the status pill.
    local hint = K.label(hud, "[" .. CFG.menuKey .. "] to open GUI", "rowLabel", 1)
    hint.Position = UDim2.fromOffset(0, 147)
    hint.Size = UDim2.fromOffset(200, 24)
    hint.TextColor3 = T.TextSub
    hint.TextStrokeTransparency = 0.1
    hint.ZIndex = 3

    local status = Instance.new("Frame")
    status.Name = "StatusChip"
    status.BackgroundColor3 = T.SurfaceChip
    status.BorderSizePixel = 0
    status.Position = UDim2.fromOffset(210, 147)
    status.Size = UDim2.fromOffset(150, 24)
    status.ZIndex = 3
    status.Parent = hud
    K.corner(status, T.RadiusMd)
    K.stroke(status, T.Hairline, 1)

    local dot = Instance.new("Frame")
    dot.Name = "Dot"
    dot.BackgroundColor3 = T.StatusBad
    dot.BorderSizePixel = 0
    dot.AnchorPoint = Vector2.new(0, 0.5)
    dot.Position = UDim2.new(0, 9, 0.5, 0)
    dot.Size = UDim2.fromOffset(6, 6)
    dot.ZIndex = 4
    dot.Parent = status
    K.corner(dot, 3)

    local statusKey = K.label(status, "Autofarm:", "captionKey", 1)
    statusKey.Position = UDim2.fromOffset(21, 0)
    statusKey.Size = UDim2.new(1, -21, 1, 0)
    statusKey.ZIndex = 4

    local statusValueLabel = K.label(status, "Disabled", "captionStat", 2)
    statusValueLabel.Position = UDim2.fromOffset(76, 0)
    statusValueLabel.Size = UDim2.new(1, -85, 1, 0)
    statusValueLabel.TextColor3 = T.StatusBad
    statusValueLabel.ZIndex = 4

    local Stats = game:GetService("Stats")
    local frames, elapsed, playStart = 0, 0, RT.hudPlayStart or os.clock()
    RT.hudPlayStart = playStart
    RT.hudConnection = RunService.Heartbeat:Connect(function(dt)
        if RT.destroyed then return end
        frames, elapsed = frames + 1, elapsed + dt
        if elapsed < 0.25 then return end
        local fps = frames / elapsed
        frames, elapsed = 0, 0

        fpsLabel.Text = string.format("fps: %d", math.floor(fps + 0.5))
        local seconds = os.clock() - playStart
        playtimeValue.Text = string.format("%02d:%02d", math.floor(seconds / 60), math.floor(seconds % 60))
        statusValue.Text = tostring(RT.movementState or "idle")
        if rangeCaption and rangeCaption.Parent then
            local parts = {}
            for slot, s in pairs(RD.abilitySlots or {}) do
                parts[#parts + 1] = string.format("%s %s: %s", string.upper(slot), s.name or "?", s.cap and (s.cap .. " studs") or (s.reach and ("at least " .. s.reach) or "?"))
            end
            table.sort(parts)
            rangeCaption.Text = #parts > 0 and ("Ability range measured - " .. table.concat(parts, ", ") .. ". The least ranged one sets the fight distance.") or "Ability range: not measured yet (cast at a target)"
        end
        local ping = 0
        pcall(function() ping = Stats.Network.ServerStatsItem["Data Ping"]:GetValue() end)
        pingValue.Text = string.format("%d", math.floor(ping + 0.5))

        local running = RT.farmEnabled and not RT.destroyed
        local text, color = running and "Running" or "Disabled", running and T.StatusGood or T.StatusBad
        if statusValueLabel.Text ~= text or dot.BackgroundColor3 ~= color then
            statusValueLabel.Text = text
            statusValueLabel.TextColor3 = color
            dot.BackgroundColor3 = color
        end
    end)
end

S.buildUI = buildUI
S.destructScript = destructScript
S.setLoopButtonState = function() if UI.masterRender then pcall(UI.masterRender) end end
S.refreshAllWidgets = refreshAll
end
