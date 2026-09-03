-- ui.lua - The HUD and the two control windows, built from the kit.
-- Module contract: receives the shared table S. Everything this module needs from
-- earlier modules is pulled into locals below; everything later modules need is
-- assigned onto S at the bottom. Load order is fixed by main.lua / build.py.
return function(S)
local RT = S.RT
local CFG = S.CFG
local UI = S.UI
local SM = S.SM
local NAV = S.NAV
local HZ = S.HZ
local LD = S.LD
local DG = S.DG
local ZN = S.ZN
local K = S.UIKit
local T = S.UIKit.Theme
local LocalPlayer = S.LocalPlayer
local Players = S.Players
local RunService = S.RunService
local Lighting = S.Lighting
local UserInputService = S.UserInputService
local heavyDebug = S.heavyDebug
local setMovementState = S.setMovementState
local sliderConnections = S.sliderConnections
local SCRIPT_VERSION = S.SCRIPT_VERSION
local SCRIPT_BUILD_DATE = S.SCRIPT_BUILD_DATE
local SCRIPT_CODENAME = S.SCRIPT_CODENAME
local printChangelog = S.printChangelog
local DEBUG_OFF = S.DEBUG_OFF
local DEBUG_NORMAL = S.DEBUG_NORMAL
local DEBUG_VERBOSE = S.DEBUG_VERBOSE
local debugLastValues = S.debugLastValues
local debugThrottleClocks = S.debugThrottleClocks
-- hazards
local clearHazardHighlights = S.clearHazardHighlights
local clearWallHighlights = S.clearWallHighlights
local clearHitboxVisualizer = S.clearHitboxVisualizer
local clearHoverHighlight = S.clearHoverHighlight
local updateHazardHighlights = S.updateHazardHighlights
local updateWallHighlights = S.updateWallHighlights
local updateHitboxVisualizer = S.updateHitboxVisualizer
local setTelegraphPickerEnabled = S.setTelegraphPickerEnabled
local setLowDetailEnabled = S.setLowDetailEnabled
local refreshLowDetail = S.refreshLowDetail
local clearKeepList = S.clearKeepList
local removeAttackRecord = S.removeAttackRecord
local addZoneDef = S.addZoneDef
local PC = S.PC
local clearPrecastZones = S.clearPrecastZones
local removeZoneDef = S.removeZoneDef
local clearZonePreview = S.clearZonePreview
local clearAttackBook = S.clearAttackBook
local invalidateAttackBook = S.invalidateAttackBook
local describeRecord = S.describeRecord
local resetWallCatalog = S.resetWallCatalog
local stopWorldIndex = S.stopWorldIndex
-- nav
local resetPursuitPath = S.resetPursuitPath
local clearEscapeRoute = S.clearEscapeRoute
local renderCurrentPath = S.renderCurrentPath
local renderEscapeRoute = S.renderEscapeRoute
local clearRenderedPath = S.clearRenderedPath
local clearEscapeNodes = S.clearEscapeNodes
local destroyFacingRig = S.destroyFacingRig
-- path
local setPathEditEnabled = S.setPathEditEnabled
local renderPathMarkers = S.renderPathMarkers
local moveWaypoint = S.moveWaypoint
local removeWaypoint = S.removeWaypoint
local clearWaypath = S.clearWaypath
-- streamer
local refreshStreamerOverlay = S.refreshStreamerOverlay
local setPendingBindField = S.setPendingBindField
local setStreamerEnabled = S.setStreamerEnabled
local setStreamerStatus = S.setStreamerStatus
local restoreHiddenElements = S.restoreHiddenElements
local dumpStreamerCandidates = S.dumpStreamerCandidates
local toHexString = S.toHexString
local parseHexColor = S.parseHexColor
local normalizeImageId = S.normalizeImageId
-- config
local saveConfig = S.saveConfig
local loadConfig = S.loadConfig
local syncStreamerToggleWidget = S.syncStreamerToggleWidget
local setCurrentMap = S.setCurrentMap
local saveNamedConfig = S.saveNamedConfig
local loadNamedConfig = S.loadNamedConfig
local deleteNamedConfig = S.deleteNamedConfig
local renameNamedConfig = S.renameNamedConfig
local MAP_CODES = S.MAP_CODES
local MAP_LABELS = S.MAP_LABELS

-- Every widget that shows a live value registers a render function here, so
-- "Reset to defaults" and a config load can put the whole GUI back in step
-- with the values behind it in one call.
local renderers = {}
local function track(widget)
    if widget and widget.render then table.insert(renderers, widget.render) end
    return widget
end
local function refreshAllWidgets()
    for _, render in ipairs(renderers) do pcall(render) end
end

local function stopCharacterMovement()
    local character = LocalPlayer.Character
    local humanoid = character and character:FindFirstChildWhichIsA("Humanoid")
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if humanoid and root then
        humanoid:MoveTo(root.Position)
        -- Rotation goes back to the Humanoid, or the character would stay locked
        -- facing a stale direction after the script stops driving it.
        humanoid.AutoRotate = true
    end
end

local function setLoopButtonState()
    if UI.masterToggleRender then pcall(UI.masterToggleRender) end
end

local function updateEnemyDisplay(enemy, enemyCount)
    UI.hudEnemyCount = enemyCount or 0
    if not enemy then
        UI.hudTarget = "None"
        UI.hudTargetHp = ""
        return
    end
    UI.hudTarget = enemy.Name
    local humanoid = enemy:FindFirstChildWhichIsA("Humanoid")
    if humanoid then
        UI.hudTargetHp = string.format("%.0f / %.0f", humanoid.Health, humanoid.MaxHealth)
    else
        UI.hudTargetHp = "billboard"
    end
end

local function destructScript()
    if RT.destroyed then return end
    RT.destroyed = true
    RT.farmEnabled = false
    RT.renderPathEnabled = false
    RT.renderHazardsEnabled = false
    RT.renderHitboxEnabled = false
    resetPursuitPath()
    clearEscapeRoute()
    clearHazardHighlights()
    if S.restoreAttackColors then S.restoreAttackColors() end
    clearWallHighlights()
    clearHitboxVisualizer()
    clearHoverHighlight()
    stopCharacterMovement()

    if RT.mainConnection then RT.mainConnection:Disconnect() RT.mainConnection = nil end
    if RT.enemyScanConnection then RT.enemyScanConnection:Disconnect() RT.enemyScanConnection = nil end
    if RT.hudConnection then RT.hudConnection:Disconnect() RT.hudConnection = nil end
    stopWorldIndex()
    if RT.animatorConnection then RT.animatorConnection:Disconnect() RT.animatorConnection = nil end
    if RT.healthConnection then RT.healthConnection:Disconnect() RT.healthConnection = nil end
    -- Defined by the main module, which loads after this one: late-bound.
    if S.unhookAttackRemotes then S.unhookAttackRemotes() end

    for _, connection in ipairs(sliderConnections) do connection:Disconnect() end
    table.clear(sliderConnections)

    setTelegraphPickerEnabled(false)
    setPathEditEnabled(false)
    S.setDodgeActive(false)
    if S.stopBossEventListeners then S.stopBossEventListeners() end
    clearPrecastZones()
    -- Through setLowDetailEnabled, so the mode flag is cleared first and the
    -- effect restore is not immediately undone.
    setLowDetailEnabled(false)
    destroyFacingRig()
    setPendingBindField(nil)
    setStreamerEnabled(false)

    -- Everything drawn in the world lives under this one folder.
    -- The blur lives in Lighting, outside our own GUI, so it has to be taken
    -- out by hand or it stays on the player's screen after we are gone.
    if RT.blurEffect then RT.blurEffect:Destroy() RT.blurEffect = nil end
    if RT.visualRoot then RT.visualRoot:Destroy() RT.visualRoot = nil end
    if RT.scriptGui then RT.scriptGui:Destroy() RT.scriptGui = nil end

    if _G.DungeonAutofarmDestruct == destructScript then _G.DungeonAutofarmDestruct = nil end
    if _G.DungeonAutofarmVersion == SCRIPT_VERSION then _G.DungeonAutofarmVersion = nil end
    if _G.DungeonAutofarmState == S then _G.DungeonAutofarmState = nil end
end

_G.DungeonAutofarmDestruct = destructScript
-- Read-only window for a live inspection tool; nothing in the script reads it back.
_G.DungeonAutofarmState = S

-- =========================================================================
-- The HUD. The only thing on screen with the GUI closed: bottom-left with a
-- margin, per the design. Title chip, stat panel, then the hint and the
-- status chip - the chip exists because the status used to sit raw on the
-- game world where red went unreadable.
-- =========================================================================
local function buildHud(parent)
    -- Explicit geometry throughout, matching the design's 360x173 HUD: chip at
    -- y=0 (h34), stats at y=42 (h95), footer at y=145 (h28).
    --
    -- Nothing here uses AutomaticSize or a UIListLayout. 2.7.1 did, and the HUD
    -- came apart in game: an auto-sizing frame, anchored to the bottom, holding
    -- auto-sizing children, never resolved to a stable size and the stat values
    -- ended up drawn at the top-left corner of the screen. Fixed numbers cannot
    -- do that.
    local hud = Instance.new("Frame")
    hud.Name = "HUD"
    hud.BackgroundTransparency = 1
    hud.AnchorPoint = Vector2.new(0, 1)
    hud.Position = UDim2.new(0, 20, 1, -20)
    hud.Size = UDim2.fromOffset(360, 173)
    hud.ZIndex = 2
    hud.Parent = parent

    -- Title chip.
    local chip = Instance.new("Frame")
    chip.Name = "TitleChip"
    chip.BackgroundColor3 = Color3.new(1, 1, 1)
    chip.BorderSizePixel = 0
    chip.Position = UDim2.fromOffset(0, 0)
    chip.Size = UDim2.fromOffset(326, 34)
    chip.ClipsDescendants = true
    chip.ZIndex = 3
    chip.Parent = hud
    K.corner(chip, T.RadiusMd)
    K.stroke(chip, T.Hairline, 1)
    K.bodyGradient(chip)
    K.shadow(chip, 6, 2.0, 8, 0.065, T.RadiusMd)

    local chipAccent = Instance.new("Frame")
    chipAccent.Name = "AccentBar"
    chipAccent.BackgroundColor3 = Color3.new(1, 1, 1)
    chipAccent.BorderSizePixel = 0
    chipAccent.Size = UDim2.new(1, 0, 0, 3)
    chipAccent.ZIndex = 5
    chipAccent.Parent = chip
    K.accentGradient(chipAccent, 0)

    local function chipText(text, style, x, width)
        local l = K.label(chip, text, style, 1)
        l.Position = UDim2.fromOffset(x, 7)
        l.Size = UDim2.fromOffset(width, 20)
        l.TextTruncate = Enum.TextTruncate.AtEnd
        l.ZIndex = 4
        return l
    end
    chipText("dqr autofarm", "windowChip", 12, 112)
    chipText("|", "captionKey", 130, 6).TextColor3 = T.TextMuted
    local userLabel = chipText("...", "rowStat", 144, 104)
    userLabel.TextColor3 = T.TextSub
    chipText("|", "captionKey", 252, 6).TextColor3 = T.TextMuted
    local fpsLabel = chipText("fps: --", "monoStat", 264, 54)

    -- Stats panel.
    local stats = Instance.new("Frame")
    stats.Name = "Stats"
    stats.BackgroundColor3 = Color3.new(1, 1, 1)
    stats.BorderSizePixel = 0
    stats.Position = UDim2.fromOffset(0, 42)
    stats.Size = UDim2.fromOffset(360, 95)
    stats.ClipsDescendants = true
    stats.ZIndex = 3
    stats.Parent = hud
    K.corner(stats, T.RadiusLg)
    K.stroke(stats, T.Hairline, 1)
    K.bodyGradient(stats)
    K.shadow(stats)

    local statsAccent = Instance.new("Frame")
    statsAccent.Name = "AccentBar"
    statsAccent.BackgroundColor3 = Color3.new(1, 1, 1)
    statsAccent.BorderSizePixel = 0
    statsAccent.Size = UDim2.new(1, 0, 0, 3)
    statsAccent.ZIndex = 5
    statsAccent.Parent = stats
    K.accentGradient(statsAccent, 0)

    -- Label left in Montserrat, value right in Roboto Mono so the digits sit on
    -- a fixed grid and stop jittering as they tick.
    local function statRow(name, y)
        local key = K.label(stats, name, "rowStat", 1)
        key.Position = UDim2.fromOffset(14, y)
        key.Size = UDim2.fromOffset(140, 24)
        key.ZIndex = 4

        local value = K.label(stats, "--", "monoStat", 2)
        value.Position = UDim2.fromOffset(160, y)
        value.Size = UDim2.fromOffset(186, 24)
        value.TextXAlignment = Enum.TextXAlignment.Right
        value.TextTruncate = Enum.TextTruncate.AtEnd
        value.ZIndex = 4
        return value
    end
    local statusValue = statRow("Status", 11)
    local targetValue = statRow("Target", 37)
    local worldValue = statRow("World", 63)

    -- Footer.
    local hint = K.label(hud, "[RSHIFT] to open GUI", "rowLabel", 1)
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
    dot.BackgroundColor3 = T.StatusGood
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

    -- The movement readout goes through here, so setMovementState still works.
    UI.movementStateLabel = statusValue

    local frames, elapsed, playStart = 0, 0, os.clock()
    RT.hudConnection = RunService.Heartbeat:Connect(function(dt)
        if RT.destroyed then return end
        frames = frames + 1
        elapsed = elapsed + dt
        if elapsed < 0.25 then return end
        local fps = frames / elapsed
        frames, elapsed = 0, 0

        hud.Visible = CFG.showHud
        if not CFG.showHud then return end

        fpsLabel.Text = string.format("fps: %d", math.floor(fps + 0.5))
        -- Streamer Mode is about not showing the real name on stream, so the
        -- HUD must honour it too - it is the one panel that is always visible.
        userLabel.Text = SM.enabled and (SM.fields.username ~= "" and SM.fields.username or "Streamer")
            or LocalPlayer.Name

        local seconds = os.clock() - playStart
        targetValue.Text = UI.hudTarget or "None"
        worldValue.Text = string.format("%d enemies / %d tg / %02d:%02d",
            UI.hudEnemyCount or 0, #HZ.detected,
            math.floor(seconds / 60), math.floor(seconds % 60))

        local running = RT.farmEnabled and not RT.destroyed
        local text, color
        if running then
            text, color = "Running", T.StatusGood
        else
            text, color = "Disabled", T.StatusBad
        end
        if statusValueLabel.Text ~= text then
            statusValueLabel.Text = text
            statusValueLabel.TextColor3 = color
            dot.BackgroundColor3 = color
        end
    end)

    return hud
end

-- =========================================================================
-- The control windows
-- =========================================================================
local function createControlUI()
    -- Forward declarations. The Attacks panel is built before the Telegraphs
    -- section but shares its pickers, so both refresh functions have to exist
    -- as locals before either half refers to the other - otherwise the earlier
    -- reference silently binds to a global and does nothing.
    local syncPickerButtons, syncAttackButtons
    local playerGui = LocalPlayer:WaitForChild("PlayerGui")
    local oldGui = playerGui:FindFirstChild("DungeonAutofarmUI")
    if oldGui then oldGui:Destroy() end

    local gui = Instance.new("ScreenGui")
    gui.Name = "DungeonAutofarmUI"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 100
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.Parent = playerGui
    gui:SetAttribute("Version", SCRIPT_VERSION)
    gui:SetAttribute("BuildDate", SCRIPT_BUILD_DATE)
    RT.scriptGui = gui
    K.ensureTip(gui)

    -- The world behind the interface. The dim is a sheet in this ScreenGui at
    -- a ZIndex below the windows; the blur is a Lighting effect, which only
    -- touches the 3D view and never the GUI drawn on top of it.
    local dim = Instance.new("Frame")
    dim.Name = "Dim"
    dim.BackgroundColor3 = Color3.new(0, 0, 0)
    dim.BackgroundTransparency = 1
    dim.BorderSizePixel = 0
    dim.Size = UDim2.fromScale(1, 1)
    dim.Visible = false
    dim.ZIndex = 1
    dim.Parent = gui

    if RT.blurEffect then RT.blurEffect:Destroy() end
    RT.blurEffect = nil
    pcall(function()
        local blur = Instance.new("BlurEffect")
        blur.Name = "DungeonAutofarmBlur"
        blur.Size = 0
        blur.Enabled = false
        blur.Parent = Lighting
        RT.blurEffect = blur
    end)

    buildHud(gui)

    -- A full accordion is taller than a 768p screen, so the windows are capped
    -- against the actual viewport and their bodies scroll.
    local camera = workspace.CurrentCamera
    local viewportY = (camera and camera.ViewportSize.Y) or 900
    local windowH = math.clamp(viewportY - 140, 320, 720)

    -- Whether the interface itself is open. A pinned window ignores it; every
    -- other window follows it, and the blur and dim follow it too - they belong
    -- to the interface, not to a window someone left pinned.
    local guiOpen = false
    local windows = {}
    local applyVisibility

    local function registerWindow(name, win)
        windows[name] = win
        return win
    end

    local onPinChanged = function(win) applyVisibility() end

    local autofarm = K.window(gui, {
        onPinChanged = onPinChanged,
        name = "Autofarm", title = "Autofarm", width = 320, height = windowH,
        position = UDim2.fromOffset(24, 24), visible = false,
        info = "Everything the bot does while it is running. Sections stay collapsed until you open them.",
    })
    -- Windows are laid out for a wide screen and dragged from there, but a
    -- position off the edge of a small one is a window you cannot reach to
    -- drag. Every default gets clamped into the actual viewport.
    local viewportX = (camera and camera.ViewportSize.X) or 1600
    local function place(x, y, w, h)
        return UDim2.fromOffset(
            math.clamp(x, 8, math.max(8, viewportX - w - 8)),
            math.clamp(y, 8, math.max(8, viewportY - h - 8)))
    end

    local account = K.window(gui, {
        onPinChanged = onPinChanged,
        name = "Account", title = "User", width = 310, height = 172,
        position = place(716, 24, 310, 172), visible = false,
    })

    local configs = K.window(gui, {
        onPinChanged = onPinChanged,
        name = "Configs", title = "Configs", width = 310, height = 360,
        position = place(716, 214, 310, 360), visible = false,
        info = "Saved setups. Each one is a complete snapshot of every setting, kept in its own file so it survives between sessions.",
    })

    local attacks = K.window(gui, {
        onPinChanged = onPinChanged,
        name = "Attacks", title = "Attacks", width = 330, height = 720,
        position = place(1040, 300, 330, 720), visible = false,
        info = "Everything about this map's attacks: freeze them so you can point at one, add it to the book, and draw a hazard around a decoration that only announces one.",
    })

    local modules = K.window(gui, {
        onPinChanged = onPinChanged,
        name = "Modules", title = "Modules", width = 260, height = 260,
        position = place(1040, 24, 260, 260), visible = false,
        info = "Which panels appear when you open the interface. This one always does - hiding the thing that unhides everything else would be a door that locks behind you.",
    })

    local routes = K.window(gui, {
        onPinChanged = onPinChanged,
        name = "Routes", title = "Routes & Data", width = 340, height = windowH,
        position = UDim2.fromOffset(360, 24), visible = false,
        info = "Where the bot goes, what it has learned, and how you appear on stream. All of it is stored per map.",
    })

    registerWindow("Autofarm", autofarm)
    registerWindow("Routes", routes)
    registerWindow("Account", account)
    registerWindow("Configs", configs)
    registerWindow("Attacks", attacks)
    local queue = K.window(gui, {
        onPinChanged = onPinChanged,
        name = "Queue", title = "Auto queue", width = 310, height = 540,
        position = place(1390, 24, 310, 540), visible = false,
        info = "The loop outside the fight: which dungeon to queue from the lobby, and replaying a run when it ends.",
    })
    registerWindow("Modules", modules)
    registerWindow("Queue", queue)

    -- ------------------------------------------------------------------
    -- Account panel. Headshot, name, rank, and the two actions.
    -- ------------------------------------------------------------------
    local accountCard = Instance.new("Frame")
    accountCard.Name = "PlayerCard"
    accountCard.BackgroundTransparency = 1
    accountCard.Size = UDim2.new(1, 0, 0, 66)
    accountCard.LayoutOrder = 1
    accountCard.Parent = account.body
    K.hlist(accountCard, T.GapLg)

    local accountAvatar = Instance.new("ImageLabel")
    accountAvatar.Name = "Avatar"
    accountAvatar.BackgroundColor3 = T.SurfaceField
    accountAvatar.BorderSizePixel = 0
    accountAvatar.Size = UDim2.fromOffset(66, 66)
    accountAvatar.LayoutOrder = 1
    accountAvatar.Parent = accountCard
    K.corner(accountAvatar, T.RadiusMd)
    K.stroke(accountAvatar, T.Hairline, 1)

    local accountText = Instance.new("Frame")
    accountText.BackgroundTransparency = 1
    accountText.Size = UDim2.new(1, -78, 1, 0)
    accountText.LayoutOrder = 2
    accountText.Parent = accountCard
    K.vlist(accountText, 3)

    local accountName = K.label(accountText, "", "windowTitle", 1)
    accountName.Size = UDim2.new(1, 0, 0, 20)
    accountName.TextTruncate = Enum.TextTruncate.AtEnd
    local accountRank = K.label(accountText, "", "rowLabel", 2)
    accountRank.Size = UDim2.new(1, 0, 0, 18)
    accountRank.TextColor3 = T.TextSub

    -- The headshot request yields, so it cannot run inline.
    local realHeadshot = ""
    task.spawn(function()
        local ok, content = pcall(function()
            return Players:GetUserThumbnailAsync(LocalPlayer.UserId,
                Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
        end)
        if ok and type(content) == "string" then
            realHeadshot = content
            if S.refreshAccountPanel then S.refreshAccountPanel() end
        end
    end)

    -- Streamer Mode exists so your name is not on screen while you stream, and
    -- this panel would put both the name and the face back on it the moment you
    -- opened the GUI. So it masks like everything else does.
    S.refreshAccountPanel = function()
        local masked = SM.enabled
        accountName.Text = "Username: " .. (masked
            and (SM.fields.username ~= "" and SM.fields.username or "Streamer")
            or LocalPlayer.Name)
        accountRank.Text = "Rank: " .. CFG.accountRank
        accountAvatar.Image = masked and SM.avatarImage or realHeadshot
    end
    S.refreshAccountPanel()
    table.insert(renderers, S.refreshAccountPanel)

    local accountButtons = K.buttonRow(account.body, 2)
    accountButtons.add("Logout", "accent", function()
        -- Placeholder: there is no account system behind this yet. It closes
        -- the interface rather than pretending to sign anything out.
        heavyDebug("Account", "No account system yet - Logout just closes the interface.")
        if S.setPanelsOpen then S.setPanelsOpen(false) end
    end, "There is no account system yet, so this only closes the interface. It is here for when there is one.")
    accountButtons.add("Detach", "danger", destructScript,
        "Unload the script completely: stops both loops, puts the world back the way it was and removes the interface.")

    -- ------------------------------------------------------------------
    -- Attacks: this map's book, the pickers, and the zone tools.
    -- ------------------------------------------------------------------
    local attackMapValues = {}
    for _, code in ipairs(MAP_CODES) do
        table.insert(attackMapValues, { value = code, label = code .. "  -  " .. (MAP_LABELS[code] or code) })
    end
    local attackMapDropdown = track(K.dropdown(attacks.body, "Map", attackMapValues,
        function() return RT.currentMap end,
        function(code)
            setCurrentMap(code)
            refreshAllWidgets()
            if S.refreshPathPanel then S.refreshPathPanel() end
            if S.refreshMapPanel then S.refreshMapPanel() end
            S.refreshAttackBookPanel()
            S.refreshZonePanel()
        end, 1,
        "The attack book and the drawn zones below belong to this dungeon. Switching here switches everything else too."))

    -- The game announces its own ground attacks; we listen rather than guess.
    K.caption(attacks.body,
        "The game tells the client where every ground attack will land and exactly when. That is read directly - shape, position and time to impact - so these need no learning and no picking.", 2)
    track(K.toggle(attacks.body, "Read announced attacks",
        function() return CFG.usePrecast end,
        function(v)
            CFG.usePrecast = v
            if v then S.startPrecastListener() else clearPrecastZones() end
        end, 3,
        "Listen to the game's own precastHitbox broadcast. Off falls back to judging attacks by how they look, which is much worse: the game's own telegraph part is invisible for its first fraction of a second."))
    track(K.toggle(attacks.body, "Draw announced attacks",
        function() return CFG.showPrecast end, function(v) CFG.showPrecast = v end, 4,
        "Draw each announced attack, warming from yellow to red as its impact approaches. Ours, not the game's - the game's own marker is invisible at first."))
    track(K.toggle(attacks.body, "Paint attacks by stage",
        function() return CFG.recolorAttacks end,
        function(v)
            CFG.recolorAttacks = v
            if not v and S.restoreAttackColors then S.restoreAttackColors() end
        end, 4.5,
        "Paint the game's own attack parts: green while the spot is still safe to cross, yellow when it is about to fire, red while it hurts. The invisible damage volume is shown too. Colours are under Overlays."))
    track(K.toggle(attacks.body, "Stand in safe spots",
        function() return CFG.safeZoneEnabled end, function(v) CFG.safeZoneEnabled = v end, 5,
        "Some bosses mark the one circle you must stand IN. With this off the dodge treats the floor as uniformly safe and calmly walks you out of it."))

    local precastLabel = K.label(attacks.body, "", "captionSub", 6)
    precastLabel.Size = UDim2.new(1, 0, 0, 30)
    precastLabel.TextWrapped = true
    S.refreshPrecastPanel = function()
        if not precastLabel.Parent then return end
        if not CFG.usePrecast then
            precastLabel.Text = "Not listening."
        elseif PC.failed then
            precastLabel.Text = "Could not attach to the game's broadcast; falling back to appearance scoring."
        elseif PC.received == 0 then
            precastLabel.Text = "Attached, but the game has not broadcast anything yet. "
                .. "Not every dungeon announces its attacks this way."
        else
            precastLabel.Text = string.format(
                "Listening. %d pending, %d understood of %d broadcast.",
                #PC.zones, PC.total, PC.received)
        end
    end
    S.refreshPrecastPanel()

    local hitLabel = K.label(attacks.body, "No hits taken yet.", "captionSub", 7.45)
    hitLabel.Size = UDim2.new(1, 0, 0, 30)
    hitLabel.TextWrapped = true
    S.refreshHitPanel = function()
        if not hitLabel.Parent then return end
        hitLabel.Text = HZ.lastHitName
            and ("Last hit: next to '" .. tostring(HZ.lastHitName) .. "'. Every hit is written into the capture, and an unknown culprit is learned.")
            or "No hits taken yet."
    end

    K.caption(attacks.body,
        "If an attack is going unnoticed, record a fight and send the file. A place file says what exists in storage; this says what actually spawned, what it was called, and what the script decided about it.", 7.5)
    track(K.toggle(attacks.body, "Record what spawns",
        function() return CFG.diagnoseAttacks end,
        function(v)
            CFG.diagnoseAttacks = v
            if v then S.clearAttackLog() end
        end, 7.6,
        "Log every part that appears near you, whether or not it was treated as an attack. The misses are the point: a part judged harmless is invisible in every other log, and that is exactly the case that needs explaining."))
    local captureRow = K.buttonRow(attacks.body, 7.7)
    captureRow.add("Save capture", "accent", function()
        local ok, err = S.saveAttackLog()
        setMovementState(ok and ("wrote " .. CFG.diagnoseFile) or ("capture failed: " .. tostring(err)))
    end, "Write the recording to a file next to your config. Run a fight with recording on, then press this and send me the file.")
    captureRow.add("Clear", "ghost", function()
        S.clearAttackLog()
        setMovementState("capture cleared")
    end, "Start the recording over.")

    K.caption(attacks.body,
        "By hand, for anything the broadcast does not cover: click an attack to add it to this map's book, or draw a hazard around a decoration that only announces one.", 8)

    local attackPickers = K.buttonRow(attacks.body, 9)
    local pickButton2, zoneButton
    syncAttackButtons = function()
        local pickOn = HZ.pickerEnabled and not HZ.ownPickerEnabled and not LD.pickerEnabled and not ZN.pickerEnabled
        local zoneOn = HZ.pickerEnabled and ZN.pickerEnabled
        pickButton2.BackgroundColor3 = pickOn and T.AccentMid or T.SurfaceElement
        pickButton2.TextColor3 = pickOn and T.TextOnAccent or T.TextPrimary
        zoneButton.BackgroundColor3 = zoneOn and T.AccentMid or T.SurfaceElement
        zoneButton.TextColor3 = zoneOn and T.TextOnAccent or T.TextPrimary
    end
    pickButton2 = attackPickers.add("Select attack", "ghost", function()
        local on = not (HZ.pickerEnabled and not HZ.ownPickerEnabled and not LD.pickerEnabled and not ZN.pickerEnabled)
        setTelegraphPickerEnabled(on, "telegraph")
        syncAttackButtons()
        syncPickerButtons()
    end, "Click an attack to add it to this map's Attack Book.")
    zoneButton = attackPickers.add("Draw zone", "ghost", function()
        local on = not (HZ.pickerEnabled and ZN.pickerEnabled)
        setTelegraphPickerEnabled(on, "zone")
        syncAttackButtons()
        syncPickerButtons()
    end, "Press on a decoration that announces an attack, drag outwards to size a hazard around it, release. Every copy of that decoration then carries one.")

    local shapeDropdown = track(K.dropdown(attacks.body, "Zone shape", {
        { value = "circle" }, { value = "square" },
    }, function() return ZN.draftShape end, function(v) ZN.draftShape = v end, 10,
        "The shape drawn by the next drag. Circle suits a shockwave, square suits a floor tile."))

    K.caption(attacks.body, "This map's attack book", 11)
    local attackList = K.list(attacks.body, 170, 12)
    local attackButtons = K.buttonRow(attacks.body, 13)

    K.caption(attacks.body, "Zones drawn on this map", 14)
    local zoneList = K.list(attacks.body, 110, 15)
    local zoneButtons = K.buttonRow(attacks.body, 16)

    S.refreshZonePanel = function()
        if not zoneList.Parent then return end
        for _, child in ipairs(zoneList:GetChildren()) do
            if child:IsA("GuiObject") then child:Destroy() end
        end
        if #ZN.defs == 0 then
            local l = K.label(zoneList, "None. Arm Draw zone, press on a warning decoration and drag outwards.", "captionSub", 1)
            l.Size = UDim2.new(1, 0, 0, 32)
            l.TextWrapped = true
            return
        end
        for i, def in ipairs(ZN.defs) do
            local row = K.listEntry(zoneList, def.name,
                string.format("%s, %.0f studs%s", def.shape, def.radius,
                    def.parentName ~= "" and (" - in " .. def.parentName) or ""), i, 1, 40)
            K.iconButton(row.actions, "delete", function()
                removeZoneDef(i)
            end, 1, "Remove this zone. Every volume it placed goes with it.")
        end
    end
    S.refreshZonePanel()

    zoneButtons.add("Save map data", "accent", function()
        local ok, err = saveConfig()
        setMovementState(ok and ("saved " .. RT.currentMap) or ("save failed: " .. tostring(err)))
    end, "Write this map's attack book and zones to the config, so they are there next time you execute.")
    zoneButtons.add("Clear zones", "danger", function()
        for i = #ZN.defs, 1, -1 do removeZoneDef(i) end
    end, "Remove every zone drawn on this map.")

    -- ------------------------------------------------------------------
    -- Configs: save the whole setup under a name, as many as you like.
    -- ------------------------------------------------------------------
    local configList
    K.textField(configs.body, "type name", function(name)
        local ok, why = saveNamedConfig(name)
        setMovementState(ok and ("saved config '" .. name .. "'") or ("save failed: " .. tostring(why)))
    end, 1, "Type a name and press the tick to save every current setting under it. An existing name is overwritten.")
    configList = K.list(configs.body, 240, 2)

    S.refreshConfigPanel = function()
        if not configList.Parent then return end
        for _, child in ipairs(configList:GetChildren()) do
            if child:IsA("GuiObject") then child:Destroy() end
        end
        if #RT.configs == 0 then
            local l = K.label(configList, "Nothing saved yet. Name your current setup above and press the tick.", "captionSub", 1)
            l.Size = UDim2.new(1, 0, 0, 32)
            l.TextWrapped = true
            return
        end
        for i, entry in ipairs(RT.configs) do
            local stamp = entry.savedAt > 0
                and os.date("%m/%d/%Y : %H:%M", entry.savedAt) or "unsaved"
            local row = K.listEntry(configList, entry.name, stamp, i, 2)
            K.tip(row.frame, "Click to load this config. The pencil renames it, the bin deletes it.")

            -- Loading is the thing you do most, so it is the whole row rather
            -- than a third icon competing with the two in the design.
            row.frame.Active = true
            row.frame.InputBegan:Connect(function(input)
                if input.UserInputType ~= Enum.UserInputType.MouseButton1
                    and input.UserInputType ~= Enum.UserInputType.Touch then return end
                local ok, wantsStreamer = loadNamedConfig(i)
                if ok then
                    if wantsStreamer ~= SM.enabled then setStreamerEnabled(wantsStreamer) end
                    refreshAllWidgets()
                    setMovementState("loaded config '" .. entry.name .. "'")
                end
            end)

            K.iconButton(row.actions, "edit", function()
                -- Rename in place: the title label becomes a box.
                local box = Instance.new("TextBox")
                box.BackgroundColor3 = T.SurfaceField
                box.BorderSizePixel = 0
                box.Size = UDim2.new(1, 0, 0, 16)
                box.Text = entry.name
                box.TextColor3 = T.TextPrimary
                box.TextSize = 12
                box.TextXAlignment = Enum.TextXAlignment.Left
                box.ClearTextOnFocus = false
                box.LayoutOrder = 0
                K.setFont(box, "sans", Enum.FontWeight.SemiBold)
                box.Parent = row.title.Parent
                K.corner(box, 4)
                K.pad(box, 0, 4, 0, 4)
                row.title.Visible = false
                box:CaptureFocus()
                box.FocusLost:Connect(function()
                    renameNamedConfig(i, box.Text)
                    S.refreshConfigPanel()
                end)
            end, 1, "Rename this config.")

            K.iconButton(row.actions, "delete", function()
                deleteNamedConfig(i)
            end, 2, "Delete this config.")
        end
    end
    S.refreshConfigPanel()

    -- ------------------------------------------------------------------
    -- Modules: which panels exist on screen.
    -- ------------------------------------------------------------------
    local panelToggles = {}
    -- The menu key, above everything else in Modules: it is the one setting
    -- that decides whether you can reach the rest.
    local menuKeyRow = K.buttonRow(modules.body, 0)
    local menuKeyButton
    local function refreshMenuKeyButton()
        if not menuKeyButton then return end
        menuKeyButton.Text = RT.menuBindCapture and "press a key" or ("Menu key: " .. CFG.menuKey)
        menuKeyButton.BackgroundColor3 = RT.menuBindCapture and T.AccentMid or T.SurfaceElement
        menuKeyButton.TextColor3 = RT.menuBindCapture and T.TextOnAccent or T.TextPrimary
    end
    menuKeyButton = menuKeyRow.add("Menu key: " .. CFG.menuKey, "ghost", function()
        RT.menuBindCapture = not RT.menuBindCapture
        refreshMenuKeyButton()
    end, "The key that opens and closes the whole interface. Click, then press the key you want. Escape cancels.")

    K.caption(modules.body,
        "Switch a panel off and it stays off when you open the interface. This panel is always here, so there is always a way back.", 1)

    local function panelToggle(label, order, get, set, explain)
        local widget = track(K.squareToggle(modules.body, label, get, set, order, explain))
        table.insert(panelToggles, widget)
        return widget
    end

    -- ------------------------------------------------------------------
    -- The island: how the character dodges. Legacy and Dodge both fight and
    -- pathfind and differ only in how they dodge, so they share every section
    -- except the Dodge section, which is shown only for Dodge.
    -- ------------------------------------------------------------------
    local legacySections, cloneSections = {}, {}
    local modeIsland
    local function applyMode()
        local mode = RT.mode
        for _, sec in ipairs(cloneSections) do sec.holder.Visible = mode == "clone" end
        if modeIsland then modeIsland.render() end
    end

    modeIsland = K.segmented(autofarm.body, {
        { value = "legacy", label = "Pathfind",
          tip = "Finds enemies, walks to them, fights them, and dodges by searching for a safe point each time something lands near you." },
        { value = "clone", label = "Dodge",
          tip = "The same bot, dodging differently: a box that is never in danger, and a character that follows it. Pursuit still walks the map underneath it; the box outranks pursuit whenever it has somewhere to be." },
    }, function() return RT.mode end, function(v)
        S.setMode(v)
        applyMode()
    end, 1, "Which system dodges for you. Only one can be in charge, so only its settings are shown.")
    track(modeIsland)

    -- ------------------------------------------------------------------
    -- Master switch, fenced off at the top of the window.
    -- ------------------------------------------------------------------
    local master = track(K.toggle(autofarm.body, "Enable Autofarm",
        function() return RT.farmEnabled end,
        function(v)
            RT.farmEnabled = v
            if not v then
                resetPursuitPath()
                clearHitboxVisualizer()
                clearHoverHighlight()
                stopCharacterMovement()
                updateEnemyDisplay(nil, 0)
            end
        end, 2,
        "The main loop. Off means the script watches and learns but never drives your character."))
    UI.masterToggleRender = master.render
    UI.toggleButton = master.row
    K.separator(autofarm.body, 3)

    local order = 3
    local function nextOrder() order = order + 1 return order end

    -- ------------------------------------------------------------------
    -- Combat
    -- ------------------------------------------------------------------
    local combat = K.section(autofarm.body, "Combat", nextOrder(),
        "Which enemy to attack and how close to stand.")
    table.insert(legacySections, combat)
    track(K.dropdown(combat.content, "Target", {
        { value = "closest" }, { value = "lowest HP" }, { value = "highest HP" },
    }, function() return CFG.targetMode end, function(v) CFG.targetMode = v end, 1,
        "closest is the safe default. The HP modes only consider enemies within "
        .. math.floor(CFG.targetHpRange) .. " studs, so a wounded straggler across the map does not drag the bot to it."))
    track(K.slider(combat.content, "Attack range", "How close before it starts swinging",
        CFG.minimumAttackRange, CFG.maximumAttackRange, false,
        function() return CFG.attackRange end, function(v) CFG.attackRange = v end, 2,
        "Planar distance to the enemy at which the attack fires. The bot stands at the edge of the enemy's melee - its body plus a swing - but never further than this, so it can always reach."))
    track(K.slider(combat.content, "Click interval", "Seconds between attacks",
        0.05, 1.0, true,
        function() return CFG.clickInterval end, function(v) CFG.clickInterval = v end, 4,
        "How often the attack input is sent. Lower is faster but noisier."))
    track(K.toggle(combat.content, "Face target",
        function() return CFG.faceTarget end,
        function(v) CFG.faceTarget = v end, 5,
        "Hold the character aimed at its target at all times, including while circling and dodging."))

    -- ------------------------------------------------------------------
    -- Abilities
    -- ------------------------------------------------------------------
    local abilities = K.section(autofarm.body, "Abilities", nextOrder(),
        "The Q and E keys, and when they are allowed to fire.")
    table.insert(legacySections, abilities)
    track(K.toggle(abilities.content, "Auto Q",
        function() return RT.autoQEnabled end, function(v) RT.autoQEnabled = v end, 1,
        "Press Q on a timer."))
    track(K.toggle(abilities.content, "Auto E",
        function() return RT.autoEEnabled end, function(v) RT.autoEEnabled = v end, 2,
        "Press E on a timer."))
    track(K.toggle(abilities.content, "Only when enemy in radius",
        function() return CFG.abilityRadiusEnabled end,
        function(v) CFG.abilityRadiusEnabled = v end, 3,
        "Hold Q and E until the target is actually close enough to hit, instead of firing them into empty air."))
    track(K.slider(abilities.content, "Ability radius", "Studs",
        CFG.minAbilityRadius, CFG.maxAbilityRadius, false,
        function() return CFG.abilityRadius end,
        function(v) CFG.abilityRadius = v if CFG.showAbilityRadius then updateHitboxVisualizer() end end, 4,
        "How close the target must be for the gate above to open."))
    track(K.toggle(abilities.content, "Show radius",
        function() return CFG.showAbilityRadius end,
        function(v) CFG.showAbilityRadius = v updateHitboxVisualizer() end, 5,
        "Draw the ability radius as a sphere around your character."))
    track(K.colorRow(abilities.content, "Radius colour",
        function() return CFG.colorAbilityRadius end,
        function(c) CFG.colorAbilityRadius = c updateHitboxVisualizer() end, 6,
        "Colour of that sphere."))

    -- ------------------------------------------------------------------
    -- Navigation
    -- ------------------------------------------------------------------
    local attackSection = K.section(autofarm.body, "Attacking", nextOrder(),
        "How the basic attack is delivered.")
    table.insert(legacySections, attackSection)
    K.caption(attackSection.content,
        "The weapon is a Tool whose Activated event the server handles, and Tool:Activate() raises it from the client - no cursor, so nothing to press by accident.", 1)
    track(K.dropdown(attackSection.content, "Method", {
        { value = "auto", label = "Auto - Activate, click if no tool" },
        { value = "tool", label = "Tool only - never clicks" },
        { value = "click", label = "Click only" },
    }, function() return CFG.attackMethod end, function(v) CFG.attackMethod = v end, 2,
        "Auto uses Tool:Activate() when a weapon is equipped and falls back to a click otherwise. Tool only never touches the mouse at all. Click only is the old behaviour."))
    track(K.toggle(attackSection.content, "Allow auto-clicking",
        function() return CFG.autoClickEnabled end, function(v) CFG.autoClickEnabled = v end, 3,
        "Off means the script never synthesises a mouse click for anything. Turn it off if the bot is pressing buttons instead of swinging - with Method on Auto or Tool it will still attack."))
    track(K.toggle(attackSection.content, "Click at the cursor",
        function() return CFG.clickAtCursor end, function(v) CFG.clickAtCursor = v end, 4,
        "Off sends any click to the middle of the screen instead of wherever your cursor is resting. Clicking at the cursor is what made the bot press whatever happened to be under it."))

    local navigation = K.section(autofarm.body, "Navigation", nextOrder(),
        "How it gets to things, and what it does when it cannot.")
    table.insert(legacySections, navigation)
    -- Testing switches. Negative orders put them above everything else in the
    -- section without renumbering it.
    track(K.toggle(navigation.content, "Follow the game's map",
        function() return CFG.autoDetectMap end, function(v) CFG.autoDetectMap = v end, -3,
        "The game publishes the dungeon name in Workspace.dungeonName. With this on the map picker follows it, so waypoints and the attack book both switch themselves when you enter a dungeon."))
    track(K.toggle(navigation.content, "Pathfinding",
        function() return CFG.pathfindingEnabled end, function(v) CFG.pathfindingEnabled = v end, -2,
        "Off stops the bot driving your character: no pursuit, no waypoints, no recovery. It still picks targets and swings if one is in reach. For testing."))
    track(K.toggle(navigation.content, "Dodging",
        function() return CFG.dodgeEnabled end, function(v) CFG.dodgeEnabled = v end, -1,
        "Off means it still finds and highlights attacks but stands in them. For testing."))
    track(K.slider(navigation.content, "Wall padding", "Above 2.0 blocks doorways",
        CFG.minimumWallPadding, CFG.maximumWallPadding, true,
        function() return CFG.wallPadding end, function(v) CFG.wallPadding = v end, 1,
        "How wide the navmesh thinks your character is. Past about 2.0 it will not fit through the game's doorways and every path fails."))
    track(K.toggle(navigation.content, "Follow path when idle",
        function() return CFG.followPath end, function(v) CFG.followPath = v end, 2,
        "With nothing to fight, walk the waypoints instead of standing still."))
    track(K.toggle(navigation.content, "Loop path",
        function() return CFG.loopPath end, function(v) CFG.loopPath = v end, 3,
        "Return to the first waypoint after the last, rather than holding at the end."))
    track(K.slider(navigation.content, "Waypoint clear radius", "How close counts as passing one",
        CFG.minWaypointClearRadius, CFG.maxWaypointClearRadius, false,
        function() return CFG.waypointClearRadius end,
        function(v) CFG.waypointClearRadius = v if NAV.showRadius then renderPathMarkers() end end, 4,
        "Come this close to the next waypoint in order and it is marked passed."))
    track(K.toggle(navigation.content, "Show clear radius",
        function() return NAV.showRadius end,
        function(v) NAV.showRadius = v renderPathMarkers() end, 5,
        "Draw that radius as a sphere around each live waypoint."))
    track(K.toggle(navigation.content, "Recovery (path as last resort)",
        function() return CFG.recoveryEnabled end, function(v) CFG.recoveryEnabled = v end, 6,
        "When normal navigation has wedged itself, walk the hand-placed path to get out. Needs a path for the current map."))
    track(K.slider(navigation.content, "Recovery stuck time", "Seconds loitering before it gives up",
        1.0, 8.0, true,
        function() return CFG.recoveryStuckTime end, function(v) CFG.recoveryStuckTime = v end, 7,
        "How long it must stay in one place - while actively trying to move - before recovery starts."))
    track(K.slider(navigation.content, "Recovery stuck radius", "Studs that count as one place",
        4, 30, false,
        function() return CFG.recoveryStuckRadius end, function(v) CFG.recoveryStuckRadius = v end, 8,
        "Staying inside a circle this size counts as not moving."))
    track(K.slider(navigation.content, "Recovery waypoints", "How far along the path to walk",
        1, 10, false,
        function() return CFG.recoveryWaypoints end, function(v) CFG.recoveryWaypoints = v end, 9,
        "How many waypoints to walk before handing back to normal pursuit."))

    -- ------------------------------------------------------------------
    -- Telegraphs
    -- ------------------------------------------------------------------
    local telegraphs = K.section(autofarm.body, "Telegraphs", nextOrder(),
        "Enemy attack markers: spotting them, dodging them, and teaching the script new ones.")
    table.insert(legacySections, telegraphs)
    track(K.slider(telegraphs.content, "Detection range", "Studs",
        CFG.minimumDamageBrickRange, CFG.maximumDamageBrickRange, false,
        function() return CFG.damageBrickDetectionRange end,
        function(v) CFG.damageBrickDetectionRange = v end, 2,
        "How far out attack markers are tracked at all."))
    track(K.slider(telegraphs.content, "Dodge clearance", "How far outside one it stands",
        1, 12, true,
        function() return CFG.damageBrickClearance end, function(v) CFG.damageBrickClearance = v end, 3,
        "The margin it keeps from the edge of a marker."))
    track(K.slider(telegraphs.content, "Pre-emptive clearance", "How early it starts moving",
        2, 20, true,
        function() return CFG.preemptiveClearance end, function(v) CFG.preemptiveClearance = v end, 4,
        "A wider ring used for ranking where to run, so it leans away before it is actually in danger."))
    track(K.slider(telegraphs.content, "Projectile lookahead", "Seconds of travel to dodge",
        0.2, 3.0, true,
        function() return CFG.projectileLookahead end, function(v) CFG.projectileLookahead = v end, 5,
        "A moving attack is treated as filling the strip it will cross in this long, so it steps out of the line rather than away from where the projectile is now."))

    local pickers = K.buttonRow(telegraphs.content, 6)
    local pickTelegraphButton, pickOwnButton
    syncPickerButtons = function()
        local telegraphOn = HZ.pickerEnabled and not HZ.ownPickerEnabled and not LD.pickerEnabled
        local ownOn = HZ.pickerEnabled and HZ.ownPickerEnabled
        local keepOn = HZ.pickerEnabled and LD.pickerEnabled
        pickTelegraphButton.BackgroundColor3 = telegraphOn and T.AccentMid or T.SurfaceElement
        pickTelegraphButton.TextColor3 = telegraphOn and T.TextOnAccent or T.TextPrimary
        pickOwnButton.BackgroundColor3 = ownOn and T.AccentMid or T.SurfaceElement
        pickOwnButton.TextColor3 = ownOn and T.TextOnAccent or T.TextPrimary
        if UI.keepPickerButton then
            UI.keepPickerButton.BackgroundColor3 = keepOn and T.AccentMid or T.SurfaceElement
            UI.keepPickerButton.TextColor3 = keepOn and T.TextOnAccent or T.TextPrimary
        end
    end
    pickTelegraphButton = pickers.add("Pick attack", "ghost", function()
        setTelegraphPickerEnabled(not (HZ.pickerEnabled and not HZ.ownPickerEnabled and not LD.pickerEnabled), "telegraph")
        syncPickerButtons()
    end, "Click an attack in the world to add it to the Attack Book.")
    pickOwnButton = pickers.add("Pick own FX", "ghost", function()
        setTelegraphPickerEnabled(not (HZ.pickerEnabled and HZ.ownPickerEnabled), "own")
        syncPickerButtons()
    end, "Click one of your OWN ability effects to mark it as yours, so the bot stops dodging its own attacks.")
    UI.pickerButton = pickTelegraphButton


    K.caption(telegraphs.content, "Learned attack names", 8)
    local learnedList = K.list(telegraphs.content, 120, 9)
    K.caption(telegraphs.content, "Learned own-effect names", 10)
    local ownList = K.list(telegraphs.content, 100, 11)

    local function refreshNameLists()
        for _, child in ipairs(learnedList:GetChildren()) do
            if child:IsA("GuiObject") then child:Destroy() end
        end
        for _, child in ipairs(ownList:GetChildren()) do
            if child:IsA("GuiObject") then child:Destroy() end
        end
        local function fill(container, set, empty, onDelete)
            local names = {}
            for name in pairs(set) do names[#names + 1] = name end
            table.sort(names)
            if #names == 0 then
                local l = K.label(container, empty, "captionSub", 1)
                l.Size = UDim2.new(1, 0, 0, 20)
                return
            end
            for i, name in ipairs(names) do
                local entry = K.listEntry(container, name, "", i, 1)
                entry.frame.Size = UDim2.new(1, 0, 0, 28)
                entry.meta.Visible = false
                K.iconButton(entry.actions, "delete", function()
                    onDelete(name)
                    refreshNameLists()
                end, 1, "Forget this name.")
            end
        end
        fill(learnedList, HZ.learnedNames, "Nothing learned yet.", function(name)
            HZ.learnedNames[name] = nil
            invalidateAttackBook()
        end)
        fill(ownList, HZ.ownNames, "Nothing learned yet.", function(name)
            HZ.ownNames[name] = nil
            invalidateAttackBook()
        end)
    end
    refreshNameLists()
    S.refreshNameLists = refreshNameLists

    -- ------------------------------------------------------------------
    -- Clone evasion
    -- ------------------------------------------------------------------
    local cloneSection = K.section(autofarm.body, "Dodge", nextOrder(),
        "A box that is never in danger, and a character that follows it.")
    table.insert(cloneSections, cloneSection)
    K.caption(cloneSection.content,
        "A few dozen points around you are checked twenty times a second: what lands on the way there, and what lands once you stop, at the moments those things happen. The box goes on the best one and you go to the box. There is no path - deciding every frame and moving exactly, the straight line is the path.", 1)

    local dodgeButtons = K.buttonRow(cloneSection.content, 2)
    dodgeButtons.add("Recommended settings", "accent", function()
        S.applyRecommendedDodge()
        refreshAllWidgets()
        setMovementState("dodge settings reset")
    end, "Put every setting in this section back to the tuned values.")

    track(K.toggle(cloneSection.content, "Manual run (no autofarm)",
        function() return CFG.dodgeManual end, function(v) CFG.dodgeManual = v end, 3,
        "Dodge only. No target hunting, no pursuit, no waypoints: you drive, and it pulls you out of attacks."))
    track(K.dropdown(cloneSection.content, "Movement", {
        { value = "tween", label = "Tween - exact, walking pace, collision-checked" },
        { value = "walk", label = "Walk - Humanoid:MoveTo" },
        { value = "steer", label = "Steer - Humanoid:Move (takes controls)" },
        { value = "velocity", label = "Velocity - direct (takes controls)" },
    }, function() return CFG.moveMode end, function(v) CFG.moveMode = v end, 4,
        "How the character is driven. Tween steps the position straight at the box, never faster than walking and never through anything, and it is the only one Roblox's own control script cannot overrule. MoveTo arrives within about two studs and accelerates for a quarter of a second, which in a narrow gap is late and off the mark."))
    track(K.slider(cloneSection.content, "Reach", "Studs to the outer ring",
        8, 30, false,
        function() return CFG.dodgeReach end, function(v) CFG.dodgeReach = v end, 5,
        "How far out it looks for somewhere to stand."))
    track(K.slider(cloneSection.content, "Rings", "Circles of candidates",
        1, 5, false,
        function() return CFG.dodgeRings end, function(v) CFG.dodgeRings = v end, 6,
        "More rings find nearer spots; each costs a ring of checks."))
    track(K.slider(cloneSection.content, "Rays", "Directions per ring",
        8, 32, false,
        function() return CFG.dodgeRays end, function(v) CFG.dodgeRays = v end, 7,
        "More directions find narrower gaps."))
    track(K.slider(cloneSection.content, "Lead", "Seconds before impact a zone counts",
        0.3, 3, true,
        function() return CFG.dodgeLead end, function(v) CFG.dodgeLead = v end, 8,
        "An announced attack is floor you may cross until this long before it lands. Higher is more cautious; too high and every marker is a wall."))
    track(K.slider(cloneSection.content, "Stay clear for", "Seconds after arriving",
        0, 3, true,
        function() return CFG.dodgeDwell end, function(v) CFG.dodgeDwell = v end, 9,
        "A spot only counts if nothing lands on it for this long after you get there. This is what stops it walking somewhere, stopping, and being hit by what it already knew about."))
    track(K.slider(cloneSection.content, "Move at", "Danger here that triggers a move",
        0.05, 0.6, true,
        function() return CFG.dodgeMoveAt end, function(v) CFG.dodgeMoveAt = v end, 10,
        "Danger runs 0 to 1. Low means it leaves at the first warmth; high means it tolerates the edge of things."))
    track(K.slider(cloneSection.content, "Commitment", "Cost of changing direction",
        0, 0.6, true,
        function() return CFG.dodgeTurnCost end, function(v) CFG.dodgeTurnCost = v end, 11,
        "Two safe sides of a beam score the same, and re-picking between them each decision is the left-right shuffle. A change of direction costs this much danger and a reversal all of it, so the side picked first is kept until the other is clearly better - which a closed line always is. Switched off while something is on you: then the shortest way out is the only way out."))
    track(K.slider(cloneSection.content, "Approach", "Pull toward the target across safe ground",
        0, 0.05, true,
        function() return CFG.dodgeApproachWeight end, function(v) CFG.dodgeApproachWeight = v end, 11.5,
        "The box is the approach. Among safe spots it prefers ones nearer the target, so the character closes only through clear ground and waits when there is none. Pursuit no longer moves the character in this mode - it walked straight through patterns to get in range."))
    track(K.slider(cloneSection.content, "Pursuit probe", "Studs ahead pursuit checks before a step",
        2, 12, false,
        function() return CFG.dodgeStepProbe end, function(v) CFG.dodgeStepProbe = v end, 11.7,
        "Pursuit walks the map underneath the dodge and asks before every step whether this many studs of its route are clear. If they are not it holds, and the box picks the way in one safe spot at a time."))
    track(K.slider(cloneSection.content, "Probe size", "0 uses your root part",
        0, 3, true,
        function() return CFG.dodgeProbe end, function(v) CFG.dodgeProbe = v end, 12,
        "How wide it believes you are when testing a spot. The root part is what the game damages against; probing with the whole body makes narrow gaps read as closed."))
    track(K.slider(cloneSection.content, "Corner penalty", "Cost of a spot with a wall behind it",
        0, 1, true,
        function() return CFG.dodgeCornerCost end, function(v) CFG.dodgeCornerCost = v end, 12.5,
        "A spot you cannot keep fleeing from is a pocket. This is how much it costs in proportion to how little room lies beyond it - what stops the character reversing into a corner or a prop and staying there."))
    track(K.toggle(cloneSection.content, "Show search range",
        function() return CFG.dodgeShowRange end, function(v) CFG.dodgeShowRange = v end, 12.7,
        "Draw the ring the outer candidates sit on, so you can tell nowhere-was-safe from it-was-not-looking-far-enough."))
    track(K.toggle(cloneSection.content, "Show field",
        function() return CFG.dodgeShowField end, function(v) CFG.dodgeShowField = v end, 13,
        "Draw the candidate points, green through yellow to red by danger."))
    track(K.toggle(cloneSection.content, "Show the box",
        function() return CFG.dodgeShowTarget end, function(v) CFG.dodgeShowTarget = v end, 14,
        "Draw the box the character is heading for."))

    -- The Attack Book lives in the Attacks panel (it is per map, and it
    -- belongs with the pickers that fill it). These are the widgets it uses.
    local bookList = attackList
    local bookButtons = attackButtons
    K.caption(attacks.body, "", 17)

    S.refreshAttackBookPanel = function()
        if not bookList.Parent then return end
        for _, child in ipairs(bookList:GetChildren()) do
            if child:IsA("GuiObject") then child:Destroy() end
        end
        if #HZ.attackBook == 0 then
            local l = K.label(bookList, "Nothing learned yet. Turn Trial Run on and take a hit.", "captionSub", 1)
            l.Size = UDim2.new(1, 0, 0, 32)
            l.TextWrapped = true
            return
        end
        for i, record in ipairs(HZ.attackBook) do
            local entry = K.listEntry(bookList, record.name, string.format("%d hit%s, %.0f dmg - %s%s%s",
                record.hits or 0, (record.hits or 0) == 1 and "" or "s", record.damage or 0,
                describeRecord(record), record.moving and ", moving" or "",
                record.melee and ", in creature" or ""), i, 2)
            entry.title.Visible = false

            local nameBox = Instance.new("TextBox")
            nameBox.BackgroundColor3 = T.SurfaceField
            nameBox.BorderSizePixel = 0
            nameBox.Size = UDim2.new(1, 0, 0, 18)
            nameBox.Text = record.name
            nameBox.TextColor3 = record.enabled ~= false and T.TextPrimary or T.TextMuted
            nameBox.TextSize = 12
            nameBox.TextXAlignment = Enum.TextXAlignment.Left
            nameBox.ClearTextOnFocus = false
            nameBox.LayoutOrder = 0
            K.setFont(nameBox, "sans", Enum.FontWeight.SemiBold)
            nameBox.Parent = entry.title.Parent
            K.corner(nameBox, 4)
            K.pad(nameBox, 0, 4, 0, 4)
            nameBox.FocusLost:Connect(function()
                local text = nameBox.Text:gsub("^%s+", ""):gsub("%s+$", "")
                if text == "" then nameBox.Text = record.name else record.name = text end
            end)

            local onOff = Instance.new("TextButton")
            onOff.Size = UDim2.fromOffset(34, 22)
            onOff.BackgroundColor3 = record.enabled ~= false and T.StatusGood or T.SurfaceHover
            onOff.BorderSizePixel = 0
            onOff.Text = record.enabled ~= false and "ON" or "OFF"
            onOff.TextColor3 = record.enabled ~= false and T.TextOnAccent or T.TextSub
            onOff.TextSize = 10
            onOff.LayoutOrder = 1
            K.setFont(onOff, "sans", Enum.FontWeight.Bold)
            onOff.Parent = entry.actions
            K.corner(onOff, 4)
            K.tip(onOff, "Whether this attack is dodged.")
            onOff.MouseButton1Click:Connect(function()
                record.enabled = not (record.enabled ~= false)
                invalidateAttackBook()
                S.refreshAttackBookPanel()
            end)

            K.iconButton(entry.actions, "delete", function()
                removeAttackRecord(i)
            end, 2, "Forget this attack.")
        end
    end
    bookButtons.add("Save", "accent", function()
        local ok, err = saveConfig()
        setMovementState(ok and "attack book saved" or ("save failed: " .. tostring(err)))
    end, "Write the Attack Book, and everything else, to the config file.")
    bookButtons.add("Clear all", "danger", clearAttackBook,
        "Forget every attack learned on this map.")
    S.refreshAttackBookPanel()

    -- ------------------------------------------------------------------
    -- Overlays
    -- ------------------------------------------------------------------
    -- ------------------------------------------------------------------
    -- Auto queue: the loop outside the fight
    -- ------------------------------------------------------------------
    local queueSection = K.section(queue.body, "Queue", 1,
        "Queue the next run from the lobby, and replay a finished one.")
    K.caption(queueSection.content,
        "In the lobby: a party for the map and difficulty below is created and started through the game's own lobby remotes, no button pressed. In a run: when the dungeon ends and you own the party, the same replay the Replay button sends goes out and the next run begins. Set this up once and let the script run on join.", 1)
    track(K.toggle(queueSection.content, "Auto queue",
        function() return CFG.autoQueue end,
        function(v)
            CFG.autoQueue = v
            if S.LB then S.LB.arrivedAt = nil S.LB.lastAttempt = -math.huge end
        end, 2,
        "Queue and replay on their own."))
    track(K.toggle(queueSection.content, "Autofarm off in lobby, on in dungeon",
        function() return CFG.autoFarmByPlace end,
        function(v) CFG.autoFarmByPlace = v if S.LB then S.LB.farmAppliedFor = nil end end, 2.5,
        "The master switch follows the place: off on arriving in the lobby, on on arriving in a dungeon. Once per place change, so flipping it yourself inside a place still sticks."))
    local mapOptions = {}
    for i, name in ipairs(S.QUEUE_MAPS or {}) do mapOptions[i] = { value = name, label = name } end
    track(K.dropdown(queueSection.content, "Map", mapOptions,
        function() return CFG.autoQueueMap end,
        function(v) CFG.autoQueueMap = v end, 3,
        "The dungeon to queue, by the name on its lobby tile."))
    local diffOptions = {}
    for i, name in ipairs(S.QUEUE_DIFFICULTIES or {}) do diffOptions[i] = { value = name, label = name } end
    track(K.dropdown(queueSection.content, "Difficulty", diffOptions,
        function() return CFG.autoQueueDifficulty end,
        function(v) CFG.autoQueueDifficulty = v end, 4,
        "The difficulty tile to pick."))
    track(K.toggle(queueSection.content, "Hardcore",
        function() return CFG.autoQueueHardcore end, function(v) CFG.autoQueueHardcore = v end, 5,
        "The lobby's hardcore option: one life for everyone in the party."))
    track(K.toggle(queueSection.content, "Private party",
        function() return CFG.autoQueuePrivate end, function(v) CFG.autoQueuePrivate = v end, 6,
        "Nobody joins the run uninvited. Off, the party is listed for others to join."))
    track(K.slider(queueSection.content, "Lobby delay", "seconds", 2, 30, false,
        function() return CFG.autoQueueDelay end, function(v) CFG.autoQueueDelay = v end, 7,
        "How long to sit in the lobby before queueing, so the character and data have loaded."))
    track(K.toggle(queueSection.content, "Replay when a run ends",
        function() return CFG.autoQueueReplay end, function(v) CFG.autoQueueReplay = v end, 8,
        "As the party owner, send the game's own replay when the dungeon-finished flag goes up, so the next run starts without a trip through the lobby."))
    track(K.slider(queueSection.content, "Replay delay", "seconds", 0, 30, false,
        function() return CFG.autoQueueReplayDelay end, function(v) CFG.autoQueueReplayDelay = v end, 9,
        "Seconds after the run ends before replaying. Loot lands in that time."))
    local queueLabel = K.label(queueSection.content, "", "captionSub", 10)
    queueLabel.Size = UDim2.new(1, 0, 0, 22)
    queueLabel.TextWrapped = true
    S.refreshQueuePanel = function()
        if not queueLabel.Parent then return end
        queueLabel.Text = "Queue: " .. tostring(S.LB and S.LB.status or "off")
    end
    S.refreshQueuePanel()
    local queueButtons = K.buttonRow(queueSection.content, 11)
    queueButtons.add("Queue now", "accent", function()
        if S.queueNow then S.queueNow("button") end
    end)
    queueButtons.add("Replay now", "accent", function()
        if S.replayNow then S.replayNow() end
    end)

    local overlays = K.section(autofarm.body, "Overlays", nextOrder(),
        "Everything the script draws in the world. Each one can be switched off and recoloured.")
    local function overlayPair(name, orderBase, getShow, setShow, getColor, setColor, explain)
        track(K.toggle(overlays.content, name, getShow, setShow, orderBase, explain))
        track(K.colorRow(overlays.content, name .. " colour", getColor, setColor, orderBase + 1,
            "Colour of the " .. string.lower(name) .. " overlay."))
    end
    overlayPair("Waypoints", 1,
        function() return CFG.showWaypoints end,
        function(v) CFG.showWaypoints = v renderPathMarkers() end,
        function() return CFG.colorWaypoint end,
        function(c) CFG.colorWaypoint = c renderPathMarkers() end,
        "The orbs and numbers of the hand-placed path.")
    overlayPair("Pursuit route", 3,
        function() return RT.renderPathEnabled end,
        function(v)
            RT.renderPathEnabled = v
            if v then renderCurrentPath() renderEscapeRoute() else clearRenderedPath() clearEscapeNodes() end
        end,
        function() return CFG.colorPursuit end,
        function(c) CFG.colorPursuit = c renderCurrentPath() end,
        "The dotted line to the enemy it is chasing.")
    overlayPair("Escape route", 5,
        function() return CFG.showEscapeRoute end,
        function(v) CFG.showEscapeRoute = v renderEscapeRoute() end,
        function() return CFG.colorEscape end,
        function(c) CFG.colorEscape = c renderEscapeRoute() end,
        "The route it takes out of an attack marker.")
    overlayPair("Telegraph highlight", 7,
        function() return RT.renderHazardsEnabled end,
        function(v) RT.renderHazardsEnabled = v updateHazardHighlights() end,
        function() return CFG.colorTelegraph end,
        function(c) CFG.colorTelegraph = c updateHazardHighlights() end,
        "The box drawn around every enemy attack, and its name tag.")
    track(K.colorRow(overlays.content, "Stage: safe to cross", function() return CFG.colorStageFloor end,
        function(c) CFG.colorStageFloor = c end, 7.2, "Attack paint while the spot is still floor."))
    track(K.colorRow(overlays.content, "Stage: about to fire", function() return CFG.colorStageSoon end,
        function(c) CFG.colorStageSoon = c end, 7.3, "Attack paint inside the lead."))
    track(K.colorRow(overlays.content, "Stage: live", function() return CFG.colorStageLive end,
        function(c) CFG.colorStageLive = c end, 7.4, "Attack paint while it hurts, or when nothing is known about its timing."))
    overlayPair("Invisible walls", 9,
        function() return CFG.showWalls end,
        function(v)
            CFG.showWalls = v
            if v then NAV.forceRescan = true else resetWallCatalog() updateWallHighlights() end
        end,
        function() return CFG.colorWall end,
        function(c) CFG.colorWall = c updateWallHighlights() end,
        "Collision walls the game keeps invisible. Off by default because there can be a lot of them.")
    overlayPair("Hitbox", 11,
        function() return RT.renderHitboxEnabled end,
        function(v) RT.renderHitboxEnabled = v updateHitboxVisualizer() end,
        function() return CFG.colorHitbox end,
        function(c) CFG.colorHitbox = c updateHitboxVisualizer() end,
        "Your own character's collision shape.")
    track(K.slider(overlays.content, "Background blur", "While the interface is open",
        0, 32, false,
        function() return CFG.guiBlur end,
        function(v) CFG.guiBlur = v applyVisibility() end, 17,
        "Blurs the game behind the windows so the interface reads clearly. 0 turns it off."))
    track(K.slider(overlays.content, "Background dim", "While the interface is open",
        0, 0.8, true,
        function() return CFG.guiDim end,
        function(v) CFG.guiDim = v applyVisibility() end, 18,
        "Darkens the game behind the windows. 0 turns it off."))
    track(K.toggle(overlays.content, "HUD",
        function() return CFG.showHud end, function(v) CFG.showHud = v end, 15,
        "The panel in the bottom-left corner. It is the only thing on screen with the GUI closed."))
    track(K.colorRow(overlays.content, "GUI accent",
        function() return CFG.accentColor end,
        function(c) CFG.accentColor = c end, 16,
        "The orange used across the whole interface. Takes effect on the next launch."))

    -- ------------------------------------------------------------------
    -- Performance
    -- ------------------------------------------------------------------
    local performance = K.section(autofarm.body, "Performance", nextOrder(),
        "Low detail: hide everything you do not need to see.")
    track(K.toggle(performance.content, "Low detail",
        function() return LD.enabled end,
        function(v) setLowDetailEnabled(v) end, 1,
        "Hide every part in the world whose name is not in the keep list. Enemies, attacks and our own markers always stay. Collision is untouched - hidden floor is still solid."))
    track(K.toggle(performance.content, "Also kill particles",
        function() return CFG.lowDetailKillEffects end,
        function(v) CFG.lowDetailKillEffects = v refreshLowDetail() end, 2,
        "Switch off particle emitters, trails and beams as well. Usually the other half of the frame cost."))
    local keepButtons = K.buttonRow(performance.content, 3)
    UI.keepPickerButton = keepButtons.add("Pick parts to keep", "ghost", function()
        setTelegraphPickerEnabled(not (HZ.pickerEnabled and LD.pickerEnabled), "keep")
        syncPickerButtons()
    end, "Click parts in the world to keep them visible in low detail. Click again to drop one.")
    keepButtons.add("Clear keeps", "danger", clearKeepList, "Empty the keep list for this map.")
    local keepList = K.list(performance.content, 140, 4)
    syncPickerButtons()

    -- ------------------------------------------------------------------
    -- Debug & config
    -- ------------------------------------------------------------------
    local debugSection = K.section(autofarm.body, "Debug & config", nextOrder(),
        "Logging, and the config file.")
    track(K.dropdown(debugSection.content, "Debug", {
        { value = "OFF" }, { value = "NORMAL" }, { value = "VERBOSE" },
    }, function()
        return RT.debugLevel == DEBUG_OFF and "OFF"
            or RT.debugLevel == DEBUG_VERBOSE and "VERBOSE" or "NORMAL"
    end, function(v)
        RT.debugLevel = v == "OFF" and DEBUG_OFF or v == "VERBOSE" and DEBUG_VERBOSE or DEBUG_NORMAL
        -- Clear the change/throttle caches so the new level re-emits current
        -- state immediately instead of waiting for the next genuine transition.
        table.clear(debugLastValues)
        table.clear(debugThrottleClocks)
    end, 1, "How much the script prints. VERBOSE is a firehose; NORMAL is decisions and errors."))
    track(K.toggle(debugSection.content, "Remote hook",
        function() return CFG.hookRemotes end, function(v) CFG.hookRemotes = v end, 2,
        "Watch this client's own attack remotes, purely to know when YOU cast something so your own effects are not mistaken for enemy attacks. Removed again after a few minutes. Takes effect on the next launch."))
    local configButtons = K.buttonRow(debugSection.content, 3)
    configButtons.add("Save", "accent", function()
        local ok, err = saveConfig()
        setMovementState(ok and "config saved" or ("save failed: " .. tostring(err)))
    end, "Write everything to DungeonAutofarm_config.json.")
    configButtons.add("Load", "ghost", function()
        loadConfig()
        refreshAllWidgets()
        if S.refreshPathPanel then S.refreshPathPanel() end
        if S.refreshMapPanel then S.refreshMapPanel() end
        S.refreshAttackBookPanel()
        refreshNameLists()
        setMovementState("config loaded")
    end, "Read it back from disk, discarding unsaved changes.")
    local configButtons2 = K.buttonRow(debugSection.content, 4)
    configButtons2.add("Reset defaults", "danger", function()
        for key, value in pairs(RT.cfgDefaults) do CFG[key] = value end
        refreshAllWidgets()
        renderPathMarkers()
        updateHazardHighlights()
        updateHitboxVisualizer()
        heavyDebug("Config", "Every tuning value reset to its shipped default. Not saved until you press Save.")
        setMovementState("defaults restored (not saved)")
    end, "Put every slider, toggle and colour back to how it shipped. Does not touch your paths or Attack Book, and is not saved until you press Save.")
    configButtons2.add("Changelog", "ghost", printChangelog, "Print the full version history to the console.")
    configButtons2.add("Destruct", "danger", destructScript, "Shut the script down and put everything back.")

    local stamp = K.label(autofarm.body, string.format('v%s "%s"  -  build %s',
        SCRIPT_VERSION, SCRIPT_CODENAME, SCRIPT_BUILD_DATE), "captionSub", nextOrder())
    stamp.Size = UDim2.new(1, 0, 0, 16)
    stamp.TextXAlignment = Enum.TextXAlignment.Center

    -- ==================================================================
    -- WINDOW 2: Routes & Data
    -- ==================================================================
    local order2 = 0
    local function nextOrder2() order2 = order2 + 1 return order2 end

    -- Map ---------------------------------------------------------------
    local mapSection = K.section(routes.body, "Map", nextOrder2(),
        "Which dungeon's waypoints and keep list are loaded. Saved separately per map.")
    local mapOptions = {}
    for _, code in ipairs(MAP_CODES) do
        table.insert(mapOptions, { value = code, label = code .. "  -  " .. (MAP_LABELS[code] or code) })
    end
    local mapDropdown = track(K.dropdown(mapSection.content, "Dungeon", mapOptions,
        function() return RT.currentMap end,
        function(code)
            setCurrentMap(code)
            if S.refreshPathPanel then S.refreshPathPanel() end
            if S.refreshMapPanel then S.refreshMapPanel() end
        end, 1,
        "Switching checks the current map's data back in first, so nothing is lost."))
    local mapButtons = K.buttonRow(mapSection.content, 2)
    mapButtons.add("Save all maps", "accent", function()
        local ok, err = saveConfig()
        setMovementState(ok and ("saved (" .. RT.currentMap .. ")") or ("save failed: " .. tostring(err)))
    end, "Write every map's data to the config.")
    mapButtons.add("Reload", "ghost", function()
        loadConfig()
        refreshAllWidgets()
        if S.refreshPathPanel then S.refreshPathPanel() end
        if S.refreshMapPanel then S.refreshMapPanel() end
        setMovementState("config loaded (" .. RT.currentMap .. ")")
    end, "Read the config back from disk.")
    local mapSummary = K.caption(mapSection.content, "", 3)

    S.refreshMapPanel = function()
        if mapDropdown and mapDropdown.render then mapDropdown.render() end
        local keepCount = 0
        for _ in pairs(LD.keepNames) do keepCount = keepCount + 1 end
        mapSummary.Text = string.format("%s: %d waypoint(s), %d kept part name(s).",
            RT.currentMap, #NAV.waypath, keepCount)
        if not keepList.Parent then return end
        for _, child in ipairs(keepList:GetChildren()) do
            if child:IsA("GuiObject") then child:Destroy() end
        end
        local names = {}
        for name in pairs(LD.keepNames) do names[#names + 1] = name end
        table.sort(names)
        if #names == 0 then
            local l = K.label(keepList, "Nothing kept yet. Arm the picker and click the parts you want to see.", "captionSub", 1)
            l.Size = UDim2.new(1, 0, 0, 32)
            l.TextWrapped = true
            return
        end
        for i, name in ipairs(names) do
            local entry = K.listEntry(keepList, name, "", i, 1)
            entry.frame.Size = UDim2.new(1, 0, 0, 28)
            entry.meta.Visible = false
            K.iconButton(entry.actions, "delete", function()
                LD.keepNames[name] = nil
                refreshLowDetail()
                S.refreshMapPanel()
            end, 1, "Stop keeping this part name.")
        end
    end

    -- Waypoints ---------------------------------------------------------
    local waypointSection = K.section(routes.body, "Waypoints", nextOrder2(),
        "A route you place by hand. Used when idle, and as the way out when the bot gets wedged.")
    table.insert(legacySections, waypointSection)
    local freecamButton
    local waypointButtons = K.buttonRow(waypointSection.content, 1)
    freecamButton = waypointButtons.add("Freecam: OFF", "ghost", function()
        local turnOn = not NAV.pathEditEnabled
        if turnOn then
            -- Farming pauses while editing so the character holds still and
            -- only the camera flies; the state is restored on exit.
            NAV.farmWasEnabled = RT.farmEnabled
            RT.farmEnabled = false
            stopCharacterMovement()
            setLoopButtonState()
        end
        setPathEditEnabled(turnOn)
        if turnOn then S.refreshPathPanel() end
        S.setFreecamButtonState()
        if not turnOn and NAV.farmWasEnabled then
            RT.farmEnabled = true
            setLoopButtonState()
        end
    end, "Fly a free camera and left-click the map to drop waypoints. WASD + E/Q to move, hold right mouse to look. Farming pauses while it is on.")
    waypointButtons.add("Clear", "danger", clearWaypath, "Delete every waypoint for this map.")
    UI.pathEditButton = freecamButton

    S.setFreecamButtonState = function()
        freecamButton.Text = "Freecam: " .. (NAV.pathEditEnabled and "ON" or "OFF")
        freecamButton.BackgroundColor3 = NAV.pathEditEnabled and T.AccentMid or T.SurfaceElement
        freecamButton.TextColor3 = NAV.pathEditEnabled and T.TextOnAccent or T.TextPrimary
    end

    local pathList = K.list(waypointSection.content, 200, 2)
    UI.pathListFrame = pathList
    S.refreshPathPanel = function()
        if not pathList.Parent then return end
        for _, child in ipairs(pathList:GetChildren()) do
            if child:IsA("GuiObject") then child:Destroy() end
        end
        if #NAV.waypath == 0 then
            local l = K.label(pathList, "No waypoints for " .. RT.currentMap .. " yet. Turn Freecam on and click the map.", "captionSub", 1)
            l.Size = UDim2.new(1, 0, 0, 32)
            l.TextWrapped = true
            return
        end
        for i, pos in ipairs(NAV.waypath) do
            local passed = i < NAV.pathIndex
            local entry = K.listEntry(pathList,
                string.format("#%d%s", i, passed and "  (passed)" or ""),
                string.format("%.0f, %.0f, %.0f", pos.X, pos.Y, pos.Z), i, 3)
            entry.frame.Size = UDim2.new(1, 0, 0, 38)
            if passed then entry.title.TextColor3 = T.TextMuted end
            K.iconButton(entry.actions, "up", function() moveWaypoint(i, -1) end, 1, "Move earlier in the route.")
            K.iconButton(entry.actions, "down", function() moveWaypoint(i, 1) end, 2, "Move later in the route.")
            K.iconButton(entry.actions, "delete", function() removeWaypoint(i) end, 3, "Delete this waypoint.")
        end
    end
    S.refreshPathPanel()
    S.setFreecamButtonState()

    -- Streamer ----------------------------------------------------------
    local streamerSection = K.section(routes.body, "Streamer", nextOrder2(),
        "Masks your account identity on screen. Client-side only: the server, other players and every leaderboard still see the real account.")
    local streamerToggle = track(K.toggle(streamerSection.content, "Streamer Mode",
        function() return SM.enabled end,
        function(v)
            setStreamerEnabled(v)
            -- The account panel shows the name and the face, so it has to mask
            -- the moment the mode changes rather than on the next refresh.
            if S.refreshAccountPanel then S.refreshAccountPanel() end
        end, 1,
        "Rewrite what THIS client renders. It hides your name on stream; it does not change your name in the game."))
    SM.syncToggleWidget = streamerToggle.render

    -- The live preview card: what a viewer will see.
    local card = Instance.new("Frame")
    card.Name = "PlayerCard"
    card.BackgroundTransparency = 1
    card.Size = UDim2.new(1, 0, 0, 66)
    card.LayoutOrder = 2
    card.Parent = streamerSection.content
    K.hlist(card, T.GapLg)

    local avatar = Instance.new("ImageLabel")
    avatar.Name = "Avatar"
    avatar.BackgroundColor3 = T.SurfaceField
    avatar.BorderSizePixel = 0
    avatar.Size = UDim2.fromOffset(66, 66)
    avatar.LayoutOrder = 1
    avatar.Parent = card
    K.corner(avatar, T.RadiusMd)
    K.stroke(avatar, T.Hairline, 1)

    local cardText = Instance.new("Frame")
    cardText.BackgroundTransparency = 1
    cardText.Size = UDim2.new(1, -78, 1, 0)
    cardText.LayoutOrder = 2
    cardText.Parent = card
    K.vlist(cardText, 3)
    K.flexFill(cardText, 78)
    local cardName = K.label(cardText, "", "windowTitle", 1)
    cardName.Size = UDim2.new(1, 0, 0, 20)
    local cardRank = K.label(cardText, "", "rowLabel", 2)
    cardRank.Size = UDim2.new(1, 0, 0, 18)
    cardRank.TextColor3 = T.TextSub

    local function refreshCard()
        cardName.Text = "Username: " .. (SM.fields.username ~= "" and SM.fields.username or LocalPlayer.Name)
        cardRank.Text = "Rank: " .. (SM.fields.vipTitle ~= "" and SM.fields.vipTitle or "(unchanged)")
        avatar.Image = SM.avatarImage ~= "" and SM.avatarImage or ""
    end
    refreshCard()
    table.insert(renderers, refreshCard)

    -- One text row per masked field, with an optional bind button for anything
    -- the keyword matching does not find on its own.
    local bindButtons = {}
    local function fieldRow(name, placeholder, bindField, get, set, order, explain)
        local holder = Instance.new("Frame")
        holder.BackgroundTransparency = 1
        holder.Size = UDim2.new(1, 0, 0, 48)
        holder.LayoutOrder = order
        holder.Parent = streamerSection.content
        K.vlist(holder, 2)

        local caption = K.label(holder, name, "captionKey", 1)
        caption.Size = UDim2.new(1, 0, 0, 14)

        local line = Instance.new("Frame")
        line.BackgroundTransparency = 1
        line.Size = UDim2.new(1, 0, 0, 28)
        line.LayoutOrder = 2
        line.Parent = holder
        K.hlist(line, T.GapSm)

        local box = Instance.new("TextBox")
        box.BackgroundColor3 = T.SurfaceField
        box.BorderSizePixel = 0
        box.Size = UDim2.new(1, bindField and -56 or 0, 1, 0)
        box.Text = get()
        box.PlaceholderText = placeholder
        box.PlaceholderColor3 = T.TextMuted
        box.TextColor3 = T.TextPrimary
        box.TextSize = 12
        box.TextXAlignment = Enum.TextXAlignment.Left
        box.ClearTextOnFocus = false
        box.ClipsDescendants = true
        box.LayoutOrder = 1
        K.setFont(box, "sans", Enum.FontWeight.Medium)
        box.Parent = line
        K.corner(box, T.RadiusMd)
        K.stroke(box, T.Hairline, 1)
        K.pad(box, 0, 8, 0, 8)
        K.flexFill(box, bindField and 56 or 0)
        K.tip(box, explain)
        box.FocusLost:Connect(function()
            set(box.Text)
            box.Text = get()
            refreshCard()
            refreshStreamerOverlay()
        end)

        if bindField then
            local bind = Instance.new("TextButton")
            bind.BackgroundColor3 = T.SurfaceElement
            bind.BorderSizePixel = 0
            bind.Size = UDim2.fromOffset(50, 28)
            bind.Text = "bind"
            bind.TextColor3 = T.TextSub
            bind.TextSize = 11
            bind.LayoutOrder = 2
            K.setFont(bind, "sans", Enum.FontWeight.SemiBold)
            bind.Parent = line
            K.corner(bind, T.RadiusMd)
            K.stroke(bind, T.Hairline, 1)
            K.tip(bind, "Arm this, then click the element on screen to bind it to this field - for anything the automatic matching misses.")
            bindButtons[bindField] = bind
            bind.MouseButton1Click:Connect(function()
                local arming = SM.pendingBindField ~= bindField
                setPendingBindField(arming and bindField or nil)
                for field, b in pairs(bindButtons) do
                    local on = arming and field == bindField
                    b.BackgroundColor3 = on and T.AccentMid or T.SurfaceElement
                    b.TextColor3 = on and T.TextOnAccent or T.TextSub
                end
            end)
        end

        table.insert(renderers, function() box.Text = get() end)
        return box
    end

    fieldRow("Username", "Displayed name", "username",
        function() return SM.fields.username end, function(v) SM.fields.username = v end, 3,
        "Any text containing your real name is rewritten to this.")
    fieldRow("VIP title", "e.g. LEGEND", "vipTitle",
        function() return SM.fields.vipTitle end, function(v) SM.fields.vipTitle = v end, 4,
        "The title or rank tag.")
    fieldRow("HP", "Leave blank to keep real HP", "hp",
        function() return SM.fields.hp end, function(v) SM.fields.hp = v end, 5,
        "Leave blank and the real value keeps updating.")
    fieldRow("EXP", "Leave blank to keep real EXP", "exp",
        function() return SM.fields.exp end, function(v) SM.fields.exp = v end, 6, "")
    fieldRow("Level", "e.g. 200", "level",
        function() return SM.fields.level end, function(v) SM.fields.level = v end, 7, "")
    fieldRow("Coins", "e.g. 17.98B", "coins",
        function() return SM.fields.coins end, function(v) SM.fields.coins = v end, 8, "")
    fieldRow("Gems", "e.g. 14.80K", "gems",
        function() return SM.fields.gems end, function(v) SM.fields.gems = v end, 9, "")
    fieldRow("Avatar image ID", "Asset ID or URL", "avatar",
        function() return SM.avatarImage end,
        function(v)
            SM.avatarImage = normalizeImageId(v)
            if v ~= "" and SM.avatarImage == "" then
                setStreamerStatus("That does not look like an image ID.")
            end
        end, 10,
        "A script cannot upload an image to Roblox, so this has to be an asset that already exists.")

    track(K.colorRow(streamerSection.content, "Nametag trim colour",
        function() return SM.borderColor end,
        function(c) SM.borderColor = c refreshStreamerOverlay() end, 11,
        "The gold border on the overhead nametag."))
    track(K.colorRow(streamerSection.content, "VIP tag colour",
        function() return SM.vipColor end,
        function(c) SM.vipColor = c refreshStreamerOverlay() end, 12, ""))
    track(K.colorRow(streamerSection.content, "Level tag colour",
        function() return SM.levelColor end,
        function(c) SM.levelColor = c refreshStreamerOverlay() end, 13, ""))

    track(K.toggle(streamerSection.content, "Auto-hide telemetry overlays",
        function() return SM.autoHideOverlays end,
        function(v)
            SM.autoHideOverlays = v
            if not v then restoreHiddenElements() end
            refreshStreamerOverlay()
        end, 14,
        "Hide the World Position / Place Version / Server Age style readouts. Only fires when at least two known phrases sit under one container."))

    local streamerButtons = K.buttonRow(streamerSection.content, 15)
    local hidePickButton
    hidePickButton = streamerButtons.add("Click to hide", "ghost", function()
        local arming = SM.pendingBindField ~= "hide"
        setPendingBindField(arming and "hide" or nil)
        hidePickButton.BackgroundColor3 = arming and T.AccentMid or T.SurfaceElement
        hidePickButton.TextColor3 = arming and T.TextOnAccent or T.TextPrimary
    end, "Arm this, then click any GUI element on screen to hide it.")
    streamerButtons.add("Unhide all", "ghost", function()
        restoreHiddenElements()
        setStreamerStatus("All hidden elements restored.")
    end, "Put back everything that was hidden.")
    local streamerButtons2 = K.buttonRow(streamerSection.content, 16)
    streamerButtons2.add("Rescan", "ghost", refreshStreamerOverlay,
        "Look for identity elements again, for anything that appeared after the mode was switched on.")
    streamerButtons2.add("Dump GUI", "ghost", function()
        local ok, result = pcall(dumpStreamerCandidates)
        setStreamerStatus(ok and ("Dumped " .. tostring(result) .. " elements to console.") or "Dump failed.")
    end, "Print every identity-bearing GUI element, with its full path, to the console. Paste that when reporting a miss.")

    SM.statusLabel = K.caption(streamerSection.content, "Off. Original display restored.", 17)
    SM.panel = routes.frame

    -- Live telegraphs ---------------------------------------------------
    local feedSection = K.section(routes.body, "Live telegraphs", nextOrder2(),
        "Every enemy attack in range right now.")
    table.insert(legacySections, feedSection)
    UI.damageBrickCountLabel = K.caption(feedSection.content, "Telegraphs Active: 0", 1)
    UI.telegraphFeedList = K.list(feedSection.content, 220, 2)

    -- ------------------------------------------------------------------
    -- Open and close
    -- ------------------------------------------------------------------
    -- A window is on screen if the interface is open OR it is pinned, and in
    -- both cases only if its module is switched on. The blur and the dim follow
    -- the interface alone: dimming the whole game for one pinned readout would
    -- be absurd.
    local function panelEnabled(name)
        if name == "Autofarm" then return CFG.panelAutofarm end
        if name == "Routes" then return CFG.panelRoutes end
        if name == "Account" then return CFG.panelAccount end
        if name == "Configs" then return CFG.panelConfigs end
        if name == "Attacks" then return CFG.panelAttacks end
        if name == "Queue" then return CFG.panelQueue end
        return true      -- Modules is never switchable; see the Modules panel.
    end

    applyVisibility = function()
        for name, win in pairs(windows) do
            local pinned = win.isPinned()
            RT.pinnedWindows[name] = pinned or nil
            win.frame.Visible = (guiOpen or pinned) and panelEnabled(name)
        end
        dim.Visible = guiOpen and CFG.guiDim > 0
        dim.BackgroundTransparency = 1 - CFG.guiDim
        if RT.blurEffect then
            RT.blurEffect.Enabled = guiOpen and CFG.guiBlur > 0
            RT.blurEffect.Size = CFG.guiBlur
        end
        if not guiOpen then K.hideTip() end
    end

    local function setOpen(open)
        guiOpen = open and true or false
        applyVisibility()
    end
    S.setPanelsOpen = setOpen

    -- Built here rather than beside the other panel code because flipping one
    -- has to re-run setOpen, and setOpen has to exist first.
    panelToggle("Autofarm", 2,
        function() return CFG.panelAutofarm end,
        function(v) CFG.panelAutofarm = v applyVisibility() end,
        "The main window: combat, abilities, navigation, telegraphs, overlays.")
    panelToggle("Routes & Data", 3,
        function() return CFG.panelRoutes end,
        function(v) CFG.panelRoutes = v applyVisibility() end,
        "Maps, waypoints, streamer mode and the live telegraph feed.")
    panelToggle("User", 4,
        function() return CFG.panelAccount end,
        function(v) CFG.panelAccount = v applyVisibility() end,
        "Your account card, and Detach.")
    panelToggle("Attacks", 5,
        function() return CFG.panelAttacks end,
        function(v) CFG.panelAttacks = v applyVisibility() end,
        "This map's attack book, the pickers, and the zone drawing tools.")
    panelToggle("Configs", 6,
        function() return CFG.panelConfigs end,
        function(v) CFG.panelConfigs = v applyVisibility() end,
        "Saved setups.")
    panelToggle("Auto queue", 6.5,
        function() return CFG.panelQueue end,
        function(v) CFG.panelQueue = v applyVisibility() end,
        "Queueing from the lobby and replaying a finished run.")
    panelToggle("HUD", 7,
        function() return CFG.showHud end,
        function(v) CFG.showHud = v end,
        "The panel in the bottom-left corner. Unlike the rest it stays on screen with the interface closed - it is the only thing that does.")
    table.insert(sliderConnections, UserInputService.InputBegan:Connect(function(input, processed)
        if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
        if RT.menuBindCapture then
            -- Escape cancels rather than binding itself.
            if input.KeyCode ~= Enum.KeyCode.Escape and input.KeyCode ~= Enum.KeyCode.Unknown then
                CFG.menuKey = input.KeyCode.Name
                heavyDebug("UI", "Menu key set to " .. CFG.menuKey .. ".")
            end
            RT.menuBindCapture = false
            refreshMenuKeyButton()
            return
        end
        if processed then return end
        -- Toggle the interface state, not a window's visibility: with a window
        -- pinned, "is Autofarm visible" was true while the interface was
        -- closed, and the key could never open it again.
        if input.KeyCode.Name == CFG.menuKey then
            setOpen(not guiOpen)
        end
    end))

    -- Sensible starting state: Combat open so the window is not a wall of
    -- closed rows on first launch.
    for name, win in pairs(windows) do
        if RT.pinnedWindows[name] then win.setPinned(true) end
    end
    applyVisibility()

    combat.setOpen(true)
    queueSection.setOpen(true)
    mapSection.setOpen(true)
    applyMode()
    refreshAllWidgets()
    if S.refreshMapPanel then S.refreshMapPanel() end
end

S.createControlUI = createControlUI
S.setLoopButtonState = setLoopButtonState
S.stopCharacterMovement = stopCharacterMovement
S.updateEnemyDisplay = updateEnemyDisplay
S.refreshAllWidgets = refreshAllWidgets
S.destructScript = destructScript
end
