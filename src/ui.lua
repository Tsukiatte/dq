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
local MC = S.MC
local K = S.UIKit
local T = S.UIKit.Theme
local LocalPlayer = S.LocalPlayer
local RunService = S.RunService
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
local setTrialEnabled = S.setTrialEnabled
local setFreezeEnabled = S.setFreezeEnabled
local clearFrozenParts = S.clearFrozenParts
local setLowDetailEnabled = S.setLowDetailEnabled
local refreshLowDetail = S.refreshLowDetail
local clearKeepList = S.clearKeepList
local removeAttackRecord = S.removeAttackRecord
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
-- macro
local setMacroMode = S.setMacroMode
local toggleRecording = S.toggleRecording
local playMacro = S.playMacro
local stopPlayback = S.stopPlayback
local removeMacro = S.removeMacro
local moveMacro = S.moveMacro
local renameMacro = S.renameMacro
local clearMacros = S.clearMacros
local renderMacroRoute = S.renderMacroRoute
local saveMacrosToMap = S.saveMacrosToMap
local playMapMacros = S.playMapMacros
local stopMacroSubsystem = S.stopMacroSubsystem
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
    stopMacroSubsystem()
    -- Through setLowDetailEnabled, so the mode flag is cleared first and the
    -- effect restore is not immediately undone.
    setLowDetailEnabled(false)
    clearFrozenParts()
    destroyFacingRig()
    setPendingBindField(nil)
    setStreamerEnabled(false)

    -- Everything drawn in the world lives under this one folder.
    if RT.visualRoot then RT.visualRoot:Destroy() RT.visualRoot = nil end
    if RT.scriptGui then RT.scriptGui:Destroy() RT.scriptGui = nil end

    if _G.DungeonAutofarmDestruct == destructScript then _G.DungeonAutofarmDestruct = nil end
    if _G.DungeonAutofarmVersion == SCRIPT_VERSION then _G.DungeonAutofarmVersion = nil end
end

_G.DungeonAutofarmDestruct = destructScript

-- =========================================================================
-- The HUD. The only thing on screen with the GUI closed: bottom-left with a
-- margin, per the design. Title chip, stat panel, then the hint and the
-- status chip - the chip exists because the status used to sit raw on the
-- game world where red went unreadable.
-- =========================================================================
local function buildHud(parent)
    local hud = Instance.new("Frame")
    hud.Name = "HUD"
    hud.BackgroundTransparency = 1
    hud.AnchorPoint = Vector2.new(0, 1)
    hud.Position = UDim2.new(0, 20, 1, -20)
    hud.Size = UDim2.fromOffset(360, 173)
    hud.ZIndex = 2
    hud.Parent = parent
    K.vlist(hud, T.GapMd)

    -- Title chip: hugs its text rather than filling the HUD width.
    local chip = Instance.new("Frame")
    chip.Name = "TitleChip"
    chip.BackgroundColor3 = Color3.new(1, 1, 1)
    chip.BorderSizePixel = 0
    chip.AutomaticSize = Enum.AutomaticSize.X
    chip.Size = UDim2.fromOffset(0, 34)
    chip.ClipsDescendants = true
    chip.LayoutOrder = 1
    chip.ZIndex = 3
    chip.Parent = hud
    K.corner(chip, T.RadiusMd)
    K.stroke(chip, T.Hairline, 1)
    K.bodyGradient(chip)
    K.shadow(chip, 6, 2.0, 8, 0.065, T.RadiusMd)
    K.pad(chip, 0, 12, 0, 12)
    K.hlist(chip, T.GapMd)

    local chipAccent = Instance.new("Frame")
    chipAccent.Name = "AccentBar"
    chipAccent.BackgroundColor3 = Color3.new(1, 1, 1)
    chipAccent.BorderSizePixel = 0
    chipAccent.Size = UDim2.new(1, 0, 0, 3)
    chipAccent.ZIndex = 5
    chipAccent.Parent = chip
    K.accentGradient(chipAccent, 0)

    local function chipText(text, style, order)
        local l = K.label(chip, text, style, order)
        l.AutomaticSize = Enum.AutomaticSize.X
        l.Size = UDim2.fromOffset(0, 20)
        l.ZIndex = 4
        return l
    end
    local nameLabel = chipText("dqr autofarm", "windowChip", 1)
    chipText("|", "captionKey", 2).TextColor3 = T.TextMuted
    local userLabel = chipText("...", "rowStat", 3)
    userLabel.TextColor3 = T.TextSub
    chipText("|", "captionKey", 4).TextColor3 = T.TextMuted
    local fpsLabel = chipText("fps: --", "monoStat", 5)

    -- Stats panel.
    local stats = Instance.new("Frame")
    stats.Name = "Stats"
    stats.BackgroundColor3 = Color3.new(1, 1, 1)
    stats.BorderSizePixel = 0
    stats.AutomaticSize = Enum.AutomaticSize.Y
    stats.Size = UDim2.new(1, 0, 0, 0)
    stats.ClipsDescendants = true
    stats.LayoutOrder = 2
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

    local rows = Instance.new("Frame")
    rows.Name = "Rows"
    rows.BackgroundTransparency = 1
    rows.AutomaticSize = Enum.AutomaticSize.Y
    rows.Size = UDim2.new(1, 0, 0, 0)
    rows.Position = UDim2.fromOffset(0, 3)
    rows.ZIndex = 4
    rows.Parent = stats
    K.pad(rows, 8, T.GapXl, 8, T.GapXl)
    K.vlist(rows, 2)

    -- Label left in Montserrat, value right in Roboto Mono so the digits sit on
    -- a fixed grid and stop jittering as they tick.
    local function statRow(name, order)
        local r = Instance.new("Frame")
        r.Name = name
        r.BackgroundTransparency = 1
        r.Size = UDim2.new(1, 0, 0, 24)
        r.LayoutOrder = order
        r.ZIndex = 4
        r.Parent = rows
        K.hlist(r, T.GapMd)

        local key = K.label(r, name, "rowStat", 1)
        key.ZIndex = 4
        K.flexFill(key, 120)
        local value = K.label(r, "--", "monoStat", 2)
        value.Size = UDim2.new(0, 0, 1, 0)
        value.AutomaticSize = Enum.AutomaticSize.X
        value.TextXAlignment = Enum.TextXAlignment.Right
        value.ZIndex = 4
        return value
    end
    local statusValue = statRow("Status", 1)
    local targetValue = statRow("Target", 2)
    local worldValue = statRow("Enemies", 3)

    -- Footer.
    local footer = Instance.new("Frame")
    footer.Name = "Footer"
    footer.BackgroundTransparency = 1
    footer.Size = UDim2.new(1, 0, 0, 28)
    footer.LayoutOrder = 3
    footer.ZIndex = 3
    footer.Parent = hud
    K.hlist(footer, T.GapMd)

    local hint = K.label(footer, "[RSHIFT] to open GUI", "rowLabel", 1)
    hint.TextColor3 = T.TextSub
    hint.TextStrokeTransparency = 0.1
    hint.ZIndex = 3
    K.flexFill(hint, 158)

    local status = Instance.new("Frame")
    status.Name = "StatusChip"
    status.BackgroundColor3 = T.SurfaceChip
    status.BorderSizePixel = 0
    status.Size = UDim2.fromOffset(150, 24)
    status.LayoutOrder = 2
    status.ZIndex = 3
    status.Parent = footer
    K.corner(status, T.RadiusMd)
    K.stroke(status, T.Hairline, 1)
    K.pad(status, 0, 9, 0, 9)
    K.hlist(status, T.GapSm)

    local dot = Instance.new("Frame")
    dot.Name = "Dot"
    dot.BackgroundColor3 = T.StatusBad
    dot.BorderSizePixel = 0
    dot.Size = UDim2.fromOffset(6, 6)
    dot.LayoutOrder = 1
    dot.ZIndex = 4
    dot.Parent = status
    K.corner(dot, 3)

    local statusKey = K.label(status, "Autofarm:", "captionKey", 2)
    statusKey.AutomaticSize = Enum.AutomaticSize.X
    statusKey.Size = UDim2.fromOffset(0, 16)
    statusKey.ZIndex = 4
    local statusValueLabel = K.label(status, "Disabled", "captionStat", 3)
    statusValueLabel.AutomaticSize = Enum.AutomaticSize.X
    statusValueLabel.Size = UDim2.fromOffset(0, 16)
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
        worldValue.Text = string.format("%d  /  %d tg  /  %02d:%02d",
            UI.hudEnemyCount or 0, #HZ.detected,
            math.floor(seconds / 60), math.floor(seconds % 60))

        local running = RT.farmEnabled and not RT.destroyed
        local text, color
        if MC.recording then
            text, color = "Recording", Color3.fromRGB(255, 170, 60)
        elseif MC.playing then
            text, color = "Macro", Color3.fromRGB(150, 110, 255)
        elseif running then
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

    buildHud(gui)

    -- A full accordion is taller than a 768p screen, so the windows are capped
    -- against the actual viewport and their bodies scroll.
    local camera = workspace.CurrentCamera
    local viewportY = (camera and camera.ViewportSize.Y) or 900
    local windowH = math.clamp(viewportY - 140, 320, 720)

    local autofarm = K.window(gui, {
        name = "Autofarm", title = "Autofarm", width = 320, height = windowH,
        position = UDim2.fromOffset(24, 24), visible = false,
        info = "Everything the bot does while it is running. Sections stay collapsed until you open them.",
    })
    local routes = K.window(gui, {
        name = "Routes", title = "Routes & Data", width = 340, height = windowH,
        position = UDim2.fromOffset(360, 24), visible = false,
        info = "Where the bot goes, what it has learned, and how you appear on stream. All of it is stored per map.",
    })

    -- ------------------------------------------------------------------
    -- The island: which system is in charge. Legacy is the pathfinding and
    -- dodging bot; Macro replays runs you recorded. They are alternatives, so
    -- the sections belonging to the one you are NOT using are hidden rather
    -- than left on screen to be scrolled past.
    -- ------------------------------------------------------------------
    local legacySections, macroSections = {}, {}
    local modeIsland
    local function applyMode()
        local macroMode = MC.mode == "macro"
        for _, sec in ipairs(legacySections) do sec.holder.Visible = not macroMode end
        for _, sec in ipairs(macroSections) do sec.holder.Visible = macroMode end
        if modeIsland then modeIsland.render() end
    end

    modeIsland = K.segmented(autofarm.body, {
        { value = "legacy", label = "Legacy",
          tip = "The pathfinding bot: finds enemies, walks to them, fights them, dodges attack markers." },
        { value = "macro", label = "Macro",
          tip = "Replays runs you recorded yourself - where you walked, where you looked, what you pressed." },
    }, function() return MC.mode end, function(v)
        setMacroMode(v)
        applyMode()
        if S.refreshMacroPanel then S.refreshMacroPanel() end
    end, 1, "Which system drives your character. Only one can be in charge, so only one set of settings is shown.")
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
        "Planar distance to the enemy at which the attack fires."))
    track(K.slider(combat.content, "Safe distance", "Where it stands while fighting",
        CFG.minimumSafeDistance, CFG.maximumSafeDistance, false,
        function() return CFG.safeDistance end, function(v) CFG.safeDistance = v end, 3,
        "The standoff point is this far from the enemy. Too small and it stands inside the model."))
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
    local navigation = K.section(autofarm.body, "Navigation", nextOrder(),
        "How it gets to things, and what it does when it cannot.")
    table.insert(legacySections, navigation)
    track(K.slider(navigation.content, "Wall padding", "Above 2.0 blocks doorways",
        CFG.minimumWallPadding, CFG.maximumWallPadding, true,
        function() return CFG.wallPadding end, function(v) CFG.wallPadding = v end, 1,
        "How wide the navmesh thinks your character is. Past about 2.0 it will not fit through the game's doorways and every path fails."))
    track(K.toggle(navigation.content, "Follow path when idle",
        function() return CFG.followPath end, function(v) CFG.followPath = v end, 2,
        "With nothing to fight, walk the waypoints (or the macros) instead of standing still."))
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
    track(K.toggle(telegraphs.content, "Dodge attacks",
        function() return CFG.dodgeEnabled end, function(v) CFG.dodgeEnabled = v end, 1,
        "Step out of attack markers. Off means it still finds and highlights them but stands in them."))
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
    local pickTelegraphButton, pickOwnButton, freezeButton
    local function syncPickerButtons()
        local telegraphOn = HZ.pickerEnabled and not HZ.ownPickerEnabled and not LD.pickerEnabled
        local ownOn = HZ.pickerEnabled and HZ.ownPickerEnabled
        local keepOn = HZ.pickerEnabled and LD.pickerEnabled
        pickTelegraphButton.BackgroundColor3 = telegraphOn and T.AccentMid or T.SurfaceElement
        pickTelegraphButton.TextColor3 = telegraphOn and T.TextOnAccent or T.TextPrimary
        pickOwnButton.BackgroundColor3 = ownOn and T.AccentMid or T.SurfaceElement
        pickOwnButton.TextColor3 = ownOn and T.TextOnAccent or T.TextPrimary
        freezeButton.BackgroundColor3 = HZ.freezeEnabled and Color3.fromRGB(90, 190, 255) or T.SurfaceElement
        freezeButton.TextColor3 = HZ.freezeEnabled and T.TextOnAccent or T.TextPrimary
        if UI.keepPickerButton then
            UI.keepPickerButton.BackgroundColor3 = keepOn and T.AccentMid or T.SurfaceElement
            UI.keepPickerButton.TextColor3 = keepOn and T.TextOnAccent or T.TextPrimary
        end
    end
    pickTelegraphButton = pickers.add("Pick attack", "ghost", function()
        setTelegraphPickerEnabled(not (HZ.pickerEnabled and not HZ.ownPickerEnabled and not LD.pickerEnabled), "telegraph")
        syncPickerButtons()
    end, "Click an attack in the world - or a frozen copy of one - to add it to the Attack Book.")
    pickOwnButton = pickers.add("Pick own FX", "ghost", function()
        setTelegraphPickerEnabled(not (HZ.pickerEnabled and HZ.ownPickerEnabled), "own")
        syncPickerButtons()
    end, "Click one of your OWN ability effects to mark it as yours, so the bot stops dodging its own attacks.")
    freezeButton = pickers.add("Freeze", "ghost", function()
        setFreezeEnabled(not HZ.freezeEnabled)
        syncPickerButtons()
    end, "Hold a copy of every attack that appears. A telegraph only exists for half a second, which is not long enough to point at - this keeps one still so you can.")
    UI.pickerButton = pickTelegraphButton

    track(K.toggle(telegraphs.content, "Trial run (learn from damage)",
        function() return HZ.trialEnabled end,
        function(v) setTrialEnabled(v) end, 7,
        "Every hit you take is matched to whatever appeared around you just before it, and written into the Attack Book. Works with the loop off - stand still and let things hit you."))

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
    -- Attack Book
    -- ------------------------------------------------------------------
    local bookSection = K.section(autofarm.body, "Attack Book", nextOrder(),
        "What the trial runs and your picks have taught it. Each entry is a description of one attack.")
    table.insert(legacySections, bookSection)
    K.caption(bookSection.content,
        "Rename by typing. OFF means it is found but not dodged. Entries learned from inside a creature model are its swing hitbox, and start OFF.", 1)
    local bookList = K.list(bookSection.content, 200, 2)
    local bookButtons = K.buttonRow(bookSection.content, 3)

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
    bookButtons.add("Clear all", "danger", clearAttackBook, "Forget every learned attack.")
    S.refreshAttackBookPanel()

    -- ------------------------------------------------------------------
    -- Overlays
    -- ------------------------------------------------------------------
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
    track(K.toggle(overlays.content, "Macro route",
        function() return CFG.macroShowRoute end,
        function(v) CFG.macroShowRoute = v renderMacroRoute(MC.playIndex) end, 13,
        "The recorded route of the selected macro."))
    track(K.colorRow(overlays.content, "Macro route colour",
        function() return CFG.colorMacro end,
        function(c) CFG.colorMacro = c renderMacroRoute(MC.playIndex) end, 14,
        "Colour of that route."))
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
        if S.refreshMacroPanel then S.refreshMacroPanel() end
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
    end, "Put every slider, toggle and colour back to how it shipped. Does not touch your paths, macros or Attack Book, and is not saved until you press Save.")
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
        "Which dungeon's waypoints, macros and keep list are loaded. Saved separately per map.")
    local mapOptions = {}
    for _, code in ipairs(MAP_CODES) do
        table.insert(mapOptions, { value = code, label = code .. "  -  " .. (MAP_LABELS[code] or code) })
    end
    local mapDropdown = track(K.dropdown(mapSection.content, "Dungeon", mapOptions,
        function() return RT.currentMap end,
        function(code)
            setCurrentMap(code)
            if S.refreshPathPanel then S.refreshPathPanel() end
            if S.refreshMacroPanel then S.refreshMacroPanel() end
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
        if S.refreshMacroPanel then S.refreshMacroPanel() end
        if S.refreshMapPanel then S.refreshMapPanel() end
        setMovementState("config loaded (" .. RT.currentMap .. ")")
    end, "Read the config back from disk.")
    local mapSummary = K.caption(mapSection.content, "", 3)

    S.refreshMapPanel = function()
        if mapDropdown and mapDropdown.render then mapDropdown.render() end
        local keepCount = 0
        for _ in pairs(LD.keepNames) do keepCount = keepCount + 1 end
        mapSummary.Text = string.format("%s: %d waypoint(s), %d macro(s), %d kept part name(s).",
            RT.currentMap, #NAV.waypath, #MC.macros, keepCount)
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

    -- Macros ------------------------------------------------------------
    local macroSection = K.section(routes.body, "Macros", nextOrder2(),
        "Recorded runs: where you went, where you looked and what you pressed. Recorded from your normal camera.")
    table.insert(macroSections, macroSection)
    track(K.toggle(macroSection.content, "Use macros when idle",
        function() return MC.mode == "macro" end,
        function(v)
            setMacroMode(v and "macro" or "legacy")
            if S.refreshMacroPanel then S.refreshMacroPanel() end
        end, 1,
        "Whether the waypoints or the macros drive the bot when it has nothing to fight. They are alternatives, so exactly one is in charge."))
    local recordButtons = K.buttonRow(macroSection.content, 2)
    local recordButton, bindButton, playButton
    recordButton = recordButtons.add("Record", "danger", function()
        toggleRecording()
        S.refreshMacroPanel()
    end, "Start and stop recording. The loop switches off while you record - you are driving. The free camera is switched off too, because a macro is recorded from your own camera.")
    bindButton = recordButtons.add("Bind: ]", "ghost", function()
        -- The next key pressed becomes the bind; Escape cancels. Captured by
        -- the always-on listener in the macro module.
        MC.bindCapture = not MC.bindCapture
        S.refreshMacroPanel()
    end, "Click, then press a key. That key starts and stops recording from anywhere. Escape cancels.")
    local playButtons = K.buttonRow(macroSection.content, 3)
    playButton = playButtons.add("Play from top", "accent", function()
        if MC.playing then stopPlayback("stopped from the panel") else playMacro(1) end
        S.refreshMacroPanel()
    end, "Walk to the start of each macro in order, then replay it.")
    track(K.toggle(macroSection.content, "Loop macros",
        function() return CFG.macroLoop end, function(v) CFG.macroLoop = v end, 4,
        "Start the list again after the last macro."))
    track(K.toggle(macroSection.content, "Replay recorded facing",
        function() return CFG.macroFaceRecorded end,
        function(v) CFG.macroFaceRecorded = v end, 5,
        "Reproduce where you were LOOKING, not just where you walked. Attacks fire in the direction the camera points, so a click replayed facing the wrong way hits nothing."))
    local macroList = K.list(macroSection.content, 200, 6)

    -- File the open recordings under any map, and play any map's file back,
    -- without switching the whole GUI over first.
    local saveTargetMap = RT.currentMap
    local playTargetMap = RT.currentMap
    local mapValues = {}
    for _, code in ipairs(MAP_CODES) do
        table.insert(mapValues, { value = code, label = code .. "  -  " .. (MAP_LABELS[code] or code) })
    end

    track(K.dropdown(macroSection.content, "Save to map", mapValues,
        function() return saveTargetMap end, function(v) saveTargetMap = v end, 7,
        "Which map these recordings belong to. They are written to " .. CFG.macroFile
        .. ", which survives between executions."))
    local saveMapButtons = K.buttonRow(macroSection.content, 8)
    saveMapButtons.add("Save to map", "accent", function()
        saveMacrosToMap(saveTargetMap)
        setMovementState("macros saved to " .. saveTargetMap)
    end, "File the recordings you have open under the chosen map, and write the macro file.")
    saveMapButtons.add("Clear all", "danger", clearMacros, "Delete every macro currently open.")

    track(K.dropdown(macroSection.content, "Play map", mapValues,
        function() return playTargetMap end, function(v) playTargetMap = v end, 9,
        "Load that map's saved recordings and start playing them from the top."))
    local playMapButtons = K.buttonRow(macroSection.content, 10)
    playMapButtons.add("Play map", "accent", function()
        playMapMacros(playTargetMap)
        refreshAllWidgets()
        if S.refreshMapPanel then S.refreshMapPanel() end
        S.refreshMacroPanel()
    end, "Switch to that map, load its macros and play them from the top.")
    playMapButtons.add("Save file", "ghost", function()
        local ok = S.saveMacroFile and S.saveMacroFile()
        setMovementState(ok and "macro file written" or "no file access")
    end, "Write " .. CFG.macroFile .. " now, without touching anything else.")

    S.refreshMacroPanel = function()
        recordButton.Text = MC.recording and "STOP recording" or "Record"
        recordButton.BackgroundColor3 = MC.recording and Color3.fromRGB(232, 168, 52) or T.StatusBad
        bindButton.Text = MC.bindCapture and "press key" or ("Bind: " .. MC.recordBind.Name)
        bindButton.BackgroundColor3 = MC.bindCapture and T.AccentMid or T.SurfaceElement
        bindButton.TextColor3 = MC.bindCapture and T.TextOnAccent or T.TextPrimary
        playButton.Text = MC.playing and "Stop playback" or "Play from top"

        if not macroList.Parent then return end
        for _, child in ipairs(macroList:GetChildren()) do
            if child:IsA("GuiObject") then child:Destroy() end
        end
        if #MC.macros == 0 then
            local l = K.label(macroList, "No macros for " .. RT.currentMap .. " yet. Press Record, run the route yourself, press it again.", "captionSub", 1)
            l.Size = UDim2.new(1, 0, 0, 32)
            l.TextWrapped = true
            return
        end
        for i, macro in ipairs(MC.macros) do
            local playingThis = MC.playing and MC.playIndex == i
            local entry = K.listEntry(macroList, macro.name, string.format("%d pts, %.0fs, %d action%s%s",
                #macro.samples, macro.duration or 0, #(macro.actions or {}),
                #(macro.actions or {}) == 1 and "" or "s",
                playingThis and string.format("  -  PLAYING %d/%d", MC.playCursor, #macro.samples) or ""),
                i, 4)
            entry.frame.Size = UDim2.new(1, 0, 0, 42)
            entry.title.Visible = false
            if playingThis then entry.meta.TextColor3 = T.StatusGood end

            local nameBox = Instance.new("TextBox")
            nameBox.BackgroundColor3 = T.SurfaceField
            nameBox.BorderSizePixel = 0
            nameBox.Size = UDim2.new(1, 0, 0, 18)
            nameBox.Text = macro.name
            nameBox.TextColor3 = T.TextPrimary
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
                if text == "" then nameBox.Text = macro.name else renameMacro(i, text) end
            end)

            K.iconButton(entry.actions, "play", function()
                playMacro(i)
                renderMacroRoute(i)
                S.refreshMacroPanel()
            end, 1, "Play this macro.")
            K.iconButton(entry.actions, "up", function() moveMacro(i, -1) end, 2, "Play earlier in the list.")
            K.iconButton(entry.actions, "down", function() moveMacro(i, 1) end, 3, "Play later in the list.")
            K.iconButton(entry.actions, "delete", function() removeMacro(i) end, 4, "Delete this macro.")
        end
    end
    S.refreshMacroPanel()

    -- Streamer ----------------------------------------------------------
    local streamerSection = K.section(routes.body, "Streamer", nextOrder2(),
        "Masks your account identity on screen. Client-side only: the server, other players and every leaderboard still see the real account.")
    local streamerToggle = track(K.toggle(streamerSection.content, "Streamer Mode",
        function() return SM.enabled end,
        function(v) setStreamerEnabled(v) end, 1,
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
    local function setOpen(open)
        autofarm.frame.Visible = open
        routes.frame.Visible = open
        if not open then K.hideTip() end
    end
    table.insert(sliderConnections, UserInputService.InputBegan:Connect(function(input, processed)
        if processed then return end
        if input.KeyCode == Enum.KeyCode.RightShift then
            setOpen(not autofarm.frame.Visible)
        end
    end))

    -- Sensible starting state: Combat open so the window is not a wall of
    -- closed rows on first launch.
    combat.setOpen(true)
    macroSection.setOpen(true)
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
