-- ui.lua - Control window, streamer panel, path panel, destruct.
-- Module contract: receives the shared table S. Everything this module needs from
-- earlier modules is pulled into locals below; everything later modules need is
-- assigned onto S at the bottom. Load order is fixed by main.lua / build.py.
return function(S)
local RT = S.RT
local SM = S.SM
local refreshStreamerOverlay = S.refreshStreamerOverlay
local setPendingBindField = S.setPendingBindField
local toHexString = S.toHexString
local parseHexColor = S.parseHexColor
local setStreamerStatus = S.setStreamerStatus
local normalizeImageId = S.normalizeImageId
local restoreHiddenElements = S.restoreHiddenElements
local heavyDebug = S.heavyDebug
local saveConfig = S.saveConfig
local loadConfig = S.loadConfig
local syncStreamerToggleWidget = S.syncStreamerToggleWidget
local setStreamerEnabled = S.setStreamerEnabled
local UI = S.UI
local LocalPlayer = S.LocalPlayer
local resetPursuitPath = S.resetPursuitPath
local clearEscapeRoute = S.clearEscapeRoute
local clearHazardHighlights = S.clearHazardHighlights
local clearWallHighlights = S.clearWallHighlights
local clearHitboxVisualizer = S.clearHitboxVisualizer
local clearHoverHighlight = S.clearHoverHighlight
local setTelegraphPickerEnabled = S.setTelegraphPickerEnabled
local setPathEditEnabled = S.setPathEditEnabled
local NAV = S.NAV
local destroyFacingRig = S.destroyFacingRig
local UserInputService = S.UserInputService
local setMovementState = S.setMovementState
local CFG = S.CFG
local renderPathMarkers = S.renderPathMarkers
local moveWaypoint = S.moveWaypoint
local removeWaypoint = S.removeWaypoint
local updateHazardHighlights = S.updateHazardHighlights
local renderCurrentPath = S.renderCurrentPath
local renderEscapeRoute = S.renderEscapeRoute
local clearRenderedPath = S.clearRenderedPath
local clearEscapeNodes = S.clearEscapeNodes
local updateHitboxVisualizer = S.updateHitboxVisualizer
local HZ = S.HZ
local updateWallHighlights = S.updateWallHighlights
local dumpStreamerCandidates = S.dumpStreamerCandidates
local sliderConnections = S.sliderConnections
local SCRIPT_VERSION = S.SCRIPT_VERSION
local SCRIPT_BUILD_DATE = S.SCRIPT_BUILD_DATE
local printChangelog = S.printChangelog
local SCRIPT_CODENAME = S.SCRIPT_CODENAME
local clearWaypath = S.clearWaypath
local DEBUG_OFF = S.DEBUG_OFF
local DEBUG_NORMAL = S.DEBUG_NORMAL
local DEBUG_VERBOSE = S.DEBUG_VERBOSE
local debugLastValues = S.debugLastValues
local debugThrottleClocks = S.debugThrottleClocks
local stopWorldIndex = S.stopWorldIndex
local resetWallCatalog = S.resetWallCatalog
local setTrialEnabled = S.setTrialEnabled
local removeAttackRecord = S.removeAttackRecord
local clearAttackBook = S.clearAttackBook
local invalidateAttackBook = S.invalidateAttackBook
local describeRecord = S.describeRecord

local function addCorner(instance, radius)
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, radius)
    corner.Parent = instance
end

local function createStreamerPanel(parentGui, makeDraggable)
    local panel = Instance.new("Frame")
    panel.Name = "StreamerPanel"
    panel.Size = UDim2.fromOffset(288, 470)
    panel.Position = UDim2.new(0, 24, 0, 20)
    panel.BackgroundColor3 = Color3.fromRGB(25, 27, 34)
    panel.BorderSizePixel = 0
    panel.Active = true
    panel.Visible = false
    panel.Parent = parentGui
    addCorner(panel, 10)

    local header = Instance.new("TextLabel")
    header.Size = UDim2.new(1, -24, 0, 30)
    header.Position = UDim2.fromOffset(12, 8)
    header.BackgroundTransparency = 1
    header.Font = Enum.Font.GothamBold
    header.Text = "Streamer Mode"
    header.TextColor3 = Color3.fromRGB(190, 140, 255)
    header.TextSize = 16
    header.TextXAlignment = Enum.TextXAlignment.Left
    header.Parent = panel
    makeDraggable(header, panel)

    local closeButton = Instance.new("TextButton")
    closeButton.Size = UDim2.fromOffset(24, 24)
    closeButton.Position = UDim2.new(1, -32, 0, 10)
    closeButton.BackgroundColor3 = Color3.fromRGB(55, 60, 74)
    closeButton.BorderSizePixel = 0
    closeButton.Font = Enum.Font.GothamBold
    closeButton.Text = "X"
    closeButton.TextColor3 = Color3.fromRGB(230, 232, 240)
    closeButton.TextSize = 12
    closeButton.Parent = panel
    addCorner(closeButton, 6)
    closeButton.MouseButton1Click:Connect(function()
        panel.Visible = false
    end)

    local toggle = Instance.new("TextButton")
    toggle.Size = UDim2.new(1, -24, 0, 32)
    toggle.Position = UDim2.fromOffset(12, 42)
    toggle.BackgroundColor3 = Color3.fromRGB(180, 64, 64)
    toggle.BorderSizePixel = 0
    toggle.Font = Enum.Font.GothamBold
    toggle.Text = "Streamer Mode: OFF"
    toggle.TextColor3 = Color3.fromRGB(255, 255, 255)
    toggle.TextSize = 13
    toggle.Parent = panel
    addCorner(toggle, 7)

    SM.statusLabel = Instance.new("TextLabel")
    SM.statusLabel.Size = UDim2.new(1, -24, 0, 18)
    SM.statusLabel.Position = UDim2.fromOffset(12, 78)
    SM.statusLabel.BackgroundTransparency = 1
    SM.statusLabel.Font = Enum.Font.Gotham
    SM.statusLabel.Text = "Off. Original display restored."
    SM.statusLabel.TextColor3 = Color3.fromRGB(160, 165, 180)
    SM.statusLabel.TextSize = 11
    SM.statusLabel.TextXAlignment = Enum.TextXAlignment.Left
    SM.statusLabel.TextTruncate = Enum.TextTruncate.AtEnd
    SM.statusLabel.Parent = panel

    local scroller = Instance.new("ScrollingFrame")
    scroller.Size = UDim2.new(1, -20, 1, -148)
    scroller.Position = UDim2.fromOffset(10, 100)
    scroller.BackgroundTransparency = 1
    scroller.BorderSizePixel = 0
    scroller.ScrollBarThickness = 4
    scroller.ScrollBarImageColor3 = Color3.fromRGB(80, 85, 100)
    scroller.CanvasSize = UDim2.new(0, 0, 0, 0)
    scroller.AutomaticCanvasSize = Enum.AutomaticSize.Y
    scroller.Parent = panel

    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0, 8)
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Parent = scroller

    local order = 0
    local fieldBoxes = {}

    -- Load rewrites the underlying values, so the widgets need syncing after.
    local function refreshPanelFields()
        for _, entry in pairs(fieldBoxes) do
            entry.box.Text = entry.read()
        end
    end

    local function createRow(labelText, initialValue, placeholder, bindField, onChanged, reader)
        order = order + 1

        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, -4, 0, 44)
        row.BackgroundTransparency = 1
        row.LayoutOrder = order
        row.Parent = scroller

        local caption = Instance.new("TextLabel")
        caption.Size = UDim2.new(1, 0, 0, 16)
        caption.BackgroundTransparency = 1
        caption.Font = Enum.Font.GothamMedium
        caption.Text = labelText
        caption.TextColor3 = Color3.fromRGB(200, 204, 216)
        caption.TextSize = 12
        caption.TextXAlignment = Enum.TextXAlignment.Left
        caption.Parent = row

        local box = Instance.new("TextBox")
        box.Size = UDim2.new(1, bindField and -38 or 0, 0, 24)
        box.Position = UDim2.fromOffset(0, 18)
        box.BackgroundColor3 = Color3.fromRGB(38, 41, 51)
        box.BorderSizePixel = 0
        box.Font = Enum.Font.Gotham
        box.PlaceholderText = placeholder
        box.Text = initialValue
        box.TextColor3 = Color3.fromRGB(238, 240, 246)
        box.TextSize = 12
        box.ClearTextOnFocus = false
        box.Parent = row
        addCorner(box, 5)

        box.FocusLost:Connect(function()
            onChanged(box.Text)
            refreshStreamerOverlay()
        end)

        if bindField then
            local bindButton = Instance.new("TextButton")
            bindButton.Size = UDim2.fromOffset(32, 24)
            bindButton.Position = UDim2.new(1, -32, 0, 18)
            bindButton.BackgroundColor3 = Color3.fromRGB(55, 60, 74)
            bindButton.BorderSizePixel = 0
            bindButton.Font = Enum.Font.GothamBold
            bindButton.Text = "bind"
            bindButton.TextColor3 = Color3.fromRGB(190, 195, 210)
            bindButton.TextSize = 10
            bindButton.Parent = row
            addCorner(bindButton, 5)

            bindButton.MouseButton1Click:Connect(function()
                local arming = SM.pendingBindField ~= bindField
                setPendingBindField(arming and bindField or nil)
                bindButton.BackgroundColor3 = arming
                    and Color3.fromRGB(232, 142, 78)
                    or Color3.fromRGB(55, 60, 74)
            end)
        end

        if reader then
            fieldBoxes[labelText] = { box = box, read = reader }
        end

        return box
    end

    createRow("Username", SM.fields.username, "Displayed name", "username",
        function(v) SM.fields.username = v end,
        function() return SM.fields.username end)
    createRow("HP", SM.fields.hp, "Leave blank to keep real HP", "hp",
        function(v) SM.fields.hp = v end,
        function() return SM.fields.hp end)
    createRow("VIP title", SM.fields.vipTitle, "e.g. LEGEND", "vipTitle",
        function(v) SM.fields.vipTitle = v end,
        function() return SM.fields.vipTitle end)
    createRow("EXP", SM.fields.exp, "Leave blank to keep real EXP", "exp",
        function(v) SM.fields.exp = v end,
        function() return SM.fields.exp end)
    createRow("Level", SM.fields.level, "e.g. 200", "level",
        function(v) SM.fields.level = v end,
        function() return SM.fields.level end)
    createRow("Coins", SM.fields.coins, "e.g. 17.98B", "coins",
        function(v) SM.fields.coins = v end,
        function() return SM.fields.coins end)
    createRow("Gems", SM.fields.gems, "e.g. 14.80K", "gems",
        function(v) SM.fields.gems = v end,
        function() return SM.fields.gems end)
    createRow("Nametag trim colour (hex)", toHexString(SM.borderColor), "FFC83C", "border",
        function(v)
            local color = parseHexColor(v)
            if color then
                SM.borderColor = color
            else
                setStreamerStatus("Bad hex colour. Use 6 digits, e.g. FFC83C.")
            end
        end,
        function() return toHexString(SM.borderColor) end)
    createRow("VIP tag colour (hex)", toHexString(SM.vipColor), "FFC83C", nil,
        function(v)
            local color = parseHexColor(v)
            if color then
                SM.vipColor = color
            else
                setStreamerStatus("Bad hex colour. Use 6 digits, e.g. FFC83C.")
            end
        end,
        function() return toHexString(SM.vipColor) end)
    createRow("Level tag colour (hex)", toHexString(SM.levelColor), "78BEFF", nil,
        function(v)
            local color = parseHexColor(v)
            if color then
                SM.levelColor = color
            else
                setStreamerStatus("Bad hex colour. Use 6 digits, e.g. 78BEFF.")
            end
        end,
        function() return toHexString(SM.levelColor) end)
    createRow("Avatar image ID", "", "Decal/image asset ID or URL", "avatar",
        function(v)
            SM.avatarImage = normalizeImageId(v)
            if v ~= "" and SM.avatarImage == "" then
                setStreamerStatus("Could not read an asset ID from that.")
            end
        end,
        function() return SM.avatarImage end)

    order = order + 1
    local hideRow = Instance.new("Frame")
    hideRow.Size = UDim2.new(1, -4, 0, 62)
    hideRow.BackgroundTransparency = 1
    hideRow.LayoutOrder = order
    hideRow.Parent = scroller

    local hideCaption = Instance.new("TextLabel")
    hideCaption.Size = UDim2.new(1, 0, 0, 16)
    hideCaption.BackgroundTransparency = 1
    hideCaption.Font = Enum.Font.GothamMedium
    hideCaption.Text = "Hide GUI elements"
    hideCaption.TextColor3 = Color3.fromRGB(200, 204, 216)
    hideCaption.TextSize = 12
    hideCaption.TextXAlignment = Enum.TextXAlignment.Left
    hideCaption.Parent = hideRow

    local autoHideButton = Instance.new("TextButton")
    autoHideButton.Size = UDim2.new(1, 0, 0, 20)
    autoHideButton.Position = UDim2.fromOffset(0, 18)
    autoHideButton.BackgroundColor3 = Color3.fromRGB(52, 168, 83)
    autoHideButton.BorderSizePixel = 0
    autoHideButton.Font = Enum.Font.Gotham
    autoHideButton.Text = "Auto-hide telemetry overlays: ON"
    autoHideButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    autoHideButton.TextSize = 11
    autoHideButton.Parent = hideRow
    addCorner(autoHideButton, 5)

    autoHideButton.MouseButton1Click:Connect(function()
        SM.autoHideOverlays = not SM.autoHideOverlays
        autoHideButton.Text = "Auto-hide telemetry overlays: " .. (SM.autoHideOverlays and "ON" or "OFF")
        autoHideButton.BackgroundColor3 = SM.autoHideOverlays
            and Color3.fromRGB(52, 168, 83)
            or Color3.fromRGB(180, 64, 64)
        if not SM.autoHideOverlays then
            restoreHiddenElements()
        end
        refreshStreamerOverlay()
    end)

    local hidePickButton = Instance.new("TextButton")
    hidePickButton.Size = UDim2.new(0.55, -2, 0, 20)
    hidePickButton.Position = UDim2.fromOffset(0, 42)
    hidePickButton.BackgroundColor3 = Color3.fromRGB(55, 60, 74)
    hidePickButton.BorderSizePixel = 0
    hidePickButton.Font = Enum.Font.GothamBold
    hidePickButton.Text = "Click to hide"
    hidePickButton.TextColor3 = Color3.fromRGB(190, 195, 210)
    hidePickButton.TextSize = 10
    hidePickButton.Parent = hideRow
    addCorner(hidePickButton, 5)

    hidePickButton.MouseButton1Click:Connect(function()
        local arming = SM.pendingBindField ~= "hide"
        setPendingBindField(arming and "hide" or nil)
        hidePickButton.BackgroundColor3 = arming
            and Color3.fromRGB(232, 142, 78)
            or Color3.fromRGB(55, 60, 74)
    end)

    local unhideButton = Instance.new("TextButton")
    unhideButton.Size = UDim2.new(0.45, -2, 0, 20)
    unhideButton.Position = UDim2.new(0.55, 4, 0, 42)
    unhideButton.BackgroundColor3 = Color3.fromRGB(90, 95, 110)
    unhideButton.BorderSizePixel = 0
    unhideButton.Font = Enum.Font.GothamBold
    unhideButton.Text = "Unhide all"
    unhideButton.TextColor3 = Color3.fromRGB(230, 232, 240)
    unhideButton.TextSize = 10
    unhideButton.Parent = hideRow
    addCorner(unhideButton, 5)

    unhideButton.MouseButton1Click:Connect(function()
        restoreHiddenElements()
        setStreamerStatus("All hidden elements restored.")
    end)

    order = order + 1
    local dumpButton = Instance.new("TextButton")
    dumpButton.Size = UDim2.new(1, -4, 0, 26)
    dumpButton.BackgroundColor3 = Color3.fromRGB(232, 142, 78)
    dumpButton.BorderSizePixel = 0
    dumpButton.Font = Enum.Font.GothamBold
    dumpButton.Text = "Dump GUI candidates to console"
    dumpButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    dumpButton.TextSize = 11
    dumpButton.LayoutOrder = order
    dumpButton.Parent = scroller
    addCorner(dumpButton, 5)

    dumpButton.MouseButton1Click:Connect(function()
        local ok, result = xpcall(dumpStreamerCandidates, debug.traceback)
        if ok then
            setStreamerStatus(string.format("Dumped %d candidates to console.", result))
        else
            setStreamerStatus("Dump failed, see console.")
            heavyDebug("FATAL", "GUI dump threw:\n" .. tostring(result))
        end
    end)

    order = order + 1
    local configRow = Instance.new("Frame")
    configRow.Size = UDim2.new(1, -4, 0, 26)
    configRow.BackgroundTransparency = 1
    configRow.LayoutOrder = order
    configRow.Parent = scroller

    local saveButton = Instance.new("TextButton")
    saveButton.Size = UDim2.new(0.5, -3, 1, 0)
    saveButton.BackgroundColor3 = Color3.fromRGB(52, 168, 83)
    saveButton.BorderSizePixel = 0
    saveButton.Font = Enum.Font.GothamBold
    saveButton.Text = "Save config"
    saveButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    saveButton.TextSize = 11
    saveButton.Parent = configRow
    addCorner(saveButton, 5)

    local loadButton = Instance.new("TextButton")
    loadButton.Size = UDim2.new(0.5, -3, 1, 0)
    loadButton.Position = UDim2.new(0.5, 3, 0, 0)
    loadButton.BackgroundColor3 = Color3.fromRGB(78, 142, 232)
    loadButton.BorderSizePixel = 0
    loadButton.Font = Enum.Font.GothamBold
    loadButton.Text = "Load config"
    loadButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    loadButton.TextSize = 11
    loadButton.Parent = configRow
    addCorner(loadButton, 5)

    saveButton.MouseButton1Click:Connect(function()
        local ok, reason = saveConfig()
        setStreamerStatus(ok and "Config saved." or ("Save failed: " .. tostring(reason)))
    end)

    loadButton.MouseButton1Click:Connect(function()
        local ok, reason = loadConfig()
        if not ok then
            setStreamerStatus("Load failed: " .. tostring(reason))
            return
        end
        syncStreamerToggleWidget()
        refreshStreamerOverlay()
        setStreamerStatus("Config loaded.")
    end)

    local rescanButton = Instance.new("TextButton")
    rescanButton.Size = UDim2.new(0.5, -14, 0, 28)
    rescanButton.Position = UDim2.new(0, 12, 1, -40)
    rescanButton.BackgroundColor3 = Color3.fromRGB(78, 142, 232)
    rescanButton.BorderSizePixel = 0
    rescanButton.Font = Enum.Font.GothamBold
    rescanButton.Text = "Rescan GUI"
    rescanButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    rescanButton.TextSize = 12
    rescanButton.Parent = panel
    addCorner(rescanButton, 6)
    rescanButton.MouseButton1Click:Connect(refreshStreamerOverlay)

    local clearBindsButton = Instance.new("TextButton")
    clearBindsButton.Size = UDim2.new(0.5, -14, 0, 28)
    clearBindsButton.Position = UDim2.new(0.5, 2, 1, -40)
    clearBindsButton.BackgroundColor3 = Color3.fromRGB(90, 95, 110)
    clearBindsButton.BorderSizePixel = 0
    clearBindsButton.Font = Enum.Font.GothamBold
    clearBindsButton.Text = "Clear binds"
    clearBindsButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    clearBindsButton.TextSize = 12
    clearBindsButton.Parent = panel
    addCorner(clearBindsButton, 6)
    clearBindsButton.MouseButton1Click:Connect(function()
        table.clear(SM.manualBinds)
        setPendingBindField(nil)
        refreshStreamerOverlay()
        setStreamerStatus("Manual binds cleared.")
    end)

    local function syncToggle()
        toggle.Text = "Streamer Mode: " .. (SM.enabled and "ON" or "OFF")
        toggle.BackgroundColor3 = SM.enabled
            and Color3.fromRGB(148, 92, 232)
            or Color3.fromRGB(180, 64, 64)
        autoHideButton.Text = "Auto-hide telemetry overlays: " .. (SM.autoHideOverlays and "ON" or "OFF")
        autoHideButton.BackgroundColor3 = SM.autoHideOverlays
            and Color3.fromRGB(52, 168, 83)
            or Color3.fromRGB(180, 64, 64)
        refreshPanelFields()
    end

    SM.syncToggleWidget = syncToggle

    toggle.MouseButton1Click:Connect(function()
        setStreamerEnabled(not SM.enabled)
        syncToggle()
    end)

    syncToggle()

    return panel
end

local function setLoopButtonState()
    if not UI.toggleButton or not UI.statusLabel then return end
    if RT.farmEnabled then
        UI.toggleButton.Text = "Loop: ON"
        UI.toggleButton.BackgroundColor3 = Color3.fromRGB(52, 168, 83)
        UI.statusLabel.Text = "Status: Running"
        UI.statusLabel.TextColor3 = Color3.fromRGB(111, 232, 143)
    else
        UI.toggleButton.Text = "Loop: OFF"
        UI.toggleButton.BackgroundColor3 = Color3.fromRGB(180, 64, 64)
        UI.statusLabel.Text = "Status: Paused"
        UI.statusLabel.TextColor3 = Color3.fromRGB(255, 145, 145)
    end
end

local function setAbilityButtonState(button, keyName, enabled)
    if not button then return end
    button.Text = "Auto " .. keyName .. ": " .. (enabled and "ON" or "OFF")
    button.BackgroundColor3 = enabled and Color3.fromRGB(52, 168, 83) or Color3.fromRGB(180, 64, 64)
end

local function updateEnemyDisplay(enemy, enemyCount)
    if not UI.enemyCountLabel or not UI.closestEnemyLabel or not UI.enemyHealthLabel then return end
    UI.enemyCountLabel.Text = "Enemies detected (Map): " .. tostring(enemyCount or 0)
    if not enemy then
        UI.closestEnemyLabel.Text = "Closest enemy: None"
        UI.enemyHealthLabel.Text = "HP: --"
        return
    end

    local humanoid = enemy:FindFirstChildWhichIsA("Humanoid")
    UI.closestEnemyLabel.Text = "Target: " .. enemy.Name
    if humanoid then
        UI.enemyHealthLabel.Text = string.format("HP: %.0f / %.0f", humanoid.Health, humanoid.MaxHealth)
    else
        UI.enemyHealthLabel.Text = "HP: (Billboard Tracked)"
    end
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

    if RT.mainConnection then
        RT.mainConnection:Disconnect()
        RT.mainConnection = nil
    end

    if RT.enemyScanConnection then
        RT.enemyScanConnection:Disconnect()
        RT.enemyScanConnection = nil
    end

    stopWorldIndex()
    if RT.animatorConnection then
        RT.animatorConnection:Disconnect()
        RT.animatorConnection = nil
    end
    if RT.healthConnection then
        RT.healthConnection:Disconnect()
        RT.healthConnection = nil
    end
    -- Defined by the main module, which loads after this one: late-bound.
    if S.unhookAttackRemotes then S.unhookAttackRemotes() end

    for _, connection in ipairs(sliderConnections) do
        connection:Disconnect()
    end
    table.clear(sliderConnections)

    setTelegraphPickerEnabled(false)
    setPathEditEnabled(false)
    if NAV.pathFolder then NAV.pathFolder:Destroy() NAV.pathFolder = nil end
    destroyFacingRig()
    setPendingBindField(nil)
    setStreamerEnabled(false)

    -- Everything drawn in the world lives under this one folder.
    if RT.visualRoot then
        RT.visualRoot:Destroy()
        RT.visualRoot = nil
    end

    if RT.scriptGui then
        RT.scriptGui:Destroy()
        RT.scriptGui = nil
    end

    if _G.DungeonAutofarmDestruct == destructScript then
        _G.DungeonAutofarmDestruct = nil
    end
    if _G.DungeonAutofarmVersion == SCRIPT_VERSION then
        _G.DungeonAutofarmVersion = nil
    end
end

_G.DungeonAutofarmDestruct = destructScript

local function createControlUI()
    local bookPanel  -- Attack Book panel; built below, referenced by the buttons above it
    local playerGui = LocalPlayer:WaitForChild("PlayerGui")
    local oldGui = playerGui:FindFirstChild("DungeonAutofarmUI")
    if oldGui then oldGui:Destroy() end

    RT.scriptGui = Instance.new("ScreenGui")
    RT.scriptGui.Name = "DungeonAutofarmUI"
    RT.scriptGui.ResetOnSpawn = false
    RT.scriptGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    RT.scriptGui.Parent = playerGui
    RT.scriptGui:SetAttribute("Version", SCRIPT_VERSION)
    RT.scriptGui:SetAttribute("BuildDate", SCRIPT_BUILD_DATE)

    -- Main Control Window
    local mainFrame = Instance.new("Frame")
    mainFrame.Name = "Main"
    mainFrame.Size = UDim2.fromOffset(300, 932)
    mainFrame.Position = UDim2.new(1, -320, 0, 20)
    mainFrame.BackgroundColor3 = Color3.fromRGB(25, 27, 34)
    mainFrame.BorderSizePixel = 0
    mainFrame.Active = true
    mainFrame.Parent = RT.scriptGui
    addCorner(mainFrame, 10)

    -- Draggable Header Logic
    local function makeDraggable(topHandle, targetFrame)
        local dragging = false
        local dragStart, startPos
        topHandle.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragging = true
                dragStart = input.Position
                startPos = targetFrame.Position
            end
        end)
        table.insert(sliderConnections, UserInputService.InputChanged:Connect(function(input)
            if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
                local delta = input.Position - dragStart
                targetFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
            end
        end))
        table.insert(sliderConnections, UserInputService.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragging = false
            end
        end))
    end

    -- Header strip: title on the left, version badge on the right
    local header = Instance.new("Frame")
    header.Name = "Header"
    header.Size = UDim2.new(1, 0, 0, 42)
    header.Position = UDim2.fromOffset(0, 0)
    header.BackgroundTransparency = 1
    header.Active = true
    header.Parent = mainFrame

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -104, 0, 34)
    title.Position = UDim2.fromOffset(12, 8)
    title.BackgroundTransparency = 1
    title.Font = Enum.Font.GothamBold
    title.Text = "Dungeon Autofarm"
    title.TextColor3 = Color3.fromRGB(245, 245, 250)
    title.TextSize = 18
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.TextTruncate = Enum.TextTruncate.AtEnd
    title.Parent = header
    makeDraggable(header, mainFrame)

    UI.versionBadge = Instance.new("TextButton")
    UI.versionBadge.Name = "VersionBadge"
    UI.versionBadge.Size = UDim2.fromOffset(80, 22)
    UI.versionBadge.Position = UDim2.new(1, -92, 0, 14)
    UI.versionBadge.BackgroundColor3 = Color3.fromRGB(45, 49, 62)
    UI.versionBadge.BorderSizePixel = 0
    UI.versionBadge.AutoButtonColor = false
    UI.versionBadge.Font = Enum.Font.GothamBold
    UI.versionBadge.Text = "v" .. SCRIPT_VERSION
    UI.versionBadge.TextColor3 = Color3.fromRGB(120, 190, 255)
    UI.versionBadge.TextSize = 12
    UI.versionBadge.Parent = header
    addCorner(UI.versionBadge, 6)

    UI.versionBadge.MouseEnter:Connect(function()
        UI.versionBadge.BackgroundColor3 = Color3.fromRGB(62, 68, 86)
        UI.versionBadge.Text = SCRIPT_BUILD_DATE
        UI.versionBadge.TextSize = 11
    end)
    UI.versionBadge.MouseLeave:Connect(function()
        UI.versionBadge.BackgroundColor3 = Color3.fromRGB(45, 49, 62)
        UI.versionBadge.Text = "v" .. SCRIPT_VERSION
        UI.versionBadge.TextSize = 12
    end)
    UI.versionBadge.MouseButton1Click:Connect(printChangelog)

    -- Active Telegraph Inspector Window
    local telegraphFrame = Instance.new("Frame")
    telegraphFrame.Name = "TelegraphInspector"
    telegraphFrame.Size = UDim2.fromOffset(260, 280)
    telegraphFrame.Position = UDim2.new(1, -590, 0, 20)
    telegraphFrame.BackgroundColor3 = Color3.fromRGB(25, 27, 34)
    telegraphFrame.BorderSizePixel = 0
    telegraphFrame.Active = true
    telegraphFrame.Parent = RT.scriptGui
    addCorner(telegraphFrame, 10)

    local telegraphTitle = Instance.new("TextLabel")
    telegraphTitle.Size = UDim2.new(1, -24, 0, 32)
    telegraphTitle.Position = UDim2.fromOffset(12, 6)
    telegraphTitle.BackgroundTransparency = 1
    telegraphTitle.Font = Enum.Font.GothamBold
    telegraphTitle.Text = "Active Telegraphs Feed"
    telegraphTitle.TextColor3 = Color3.fromRGB(255, 105, 105)
    telegraphTitle.TextSize = 15
    telegraphTitle.TextXAlignment = Enum.TextXAlignment.Left
    telegraphTitle.Parent = telegraphFrame
    makeDraggable(telegraphTitle, telegraphFrame)

    local scrollContainer = Instance.new("ScrollingFrame")
    scrollContainer.Size = UDim2.new(1, -20, 1, -44)
    scrollContainer.Position = UDim2.fromOffset(10, 36)
    scrollContainer.BackgroundTransparency = 1
    scrollContainer.BorderSizePixel = 0
    scrollContainer.ScrollBarThickness = 4
    scrollContainer.ScrollBarImageColor3 = Color3.fromRGB(80, 85, 100)
    scrollContainer.CanvasSize = UDim2.new(0, 0, 0, 0)
    scrollContainer.AutomaticCanvasSize = Enum.AutomaticSize.Y
    scrollContainer.Parent = telegraphFrame

    local listLayout = Instance.new("UIListLayout")
    listLayout.Padding = UDim.new(0, 5)
    listLayout.SortOrder = Enum.SortOrder.LayoutOrder
    listLayout.Parent = scrollContainer

    UI.telegraphFeedList = scrollContainer

    UI.statusLabel = Instance.new("TextLabel")
    UI.statusLabel.Size = UDim2.new(1, -24, 0, 24)
    UI.statusLabel.Position = UDim2.fromOffset(12, 43)
    UI.statusLabel.BackgroundTransparency = 1
    UI.statusLabel.Font = Enum.Font.GothamMedium
    UI.statusLabel.TextSize = 14
    UI.statusLabel.TextXAlignment = Enum.TextXAlignment.Left
    UI.statusLabel.Parent = mainFrame

    UI.toggleButton = Instance.new("TextButton")
    UI.toggleButton.Size = UDim2.new(1, -24, 0, 38)
    UI.toggleButton.Position = UDim2.fromOffset(12, 72)
    UI.toggleButton.BorderSizePixel = 0
    UI.toggleButton.Font = Enum.Font.GothamBold
    UI.toggleButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    UI.toggleButton.TextSize = 15
    UI.toggleButton.Parent = mainFrame
    addCorner(UI.toggleButton, 7)

    local statsFrame = Instance.new("Frame")
    statsFrame.Size = UDim2.new(1, -24, 0, 128)
    statsFrame.Position = UDim2.fromOffset(12, 118)
    statsFrame.BackgroundColor3 = Color3.fromRGB(35, 38, 47)
    statsFrame.BorderSizePixel = 0
    statsFrame.Parent = mainFrame
    addCorner(statsFrame, 7)

    local function createStatLabel(y)
        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(1, -16, 0, 22)
        label.Position = UDim2.fromOffset(8, y)
        label.BackgroundTransparency = 1
        label.Font = Enum.Font.Gotham
        label.TextColor3 = Color3.fromRGB(220, 222, 230)
        label.TextSize = 13
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.TextTruncate = Enum.TextTruncate.AtEnd
        label.Parent = statsFrame
        return label
    end

    UI.enemyCountLabel = createStatLabel(6)
    UI.closestEnemyLabel = createStatLabel(29)
    UI.enemyHealthLabel = createStatLabel(52)
    UI.damageBrickCountLabel = createStatLabel(75)
    UI.movementStateLabel = createStatLabel(98)
    UI.movementStateLabel.TextColor3 = Color3.fromRGB(120, 190, 255)
    UI.movementStateLabel.Font = Enum.Font.GothamMedium
    setMovementState("waiting")
    updateEnemyDisplay(nil, 0)

    local function createAbilityButton(x)
        local button = Instance.new("TextButton")
        button.Size = UDim2.fromOffset(132, 38)
        button.Position = UDim2.fromOffset(x, 254)
        button.BorderSizePixel = 0
        button.Font = Enum.Font.GothamBold
        button.TextColor3 = Color3.fromRGB(255, 255, 255)
        button.TextSize = 14
        button.Parent = mainFrame
        addCorner(button, 7)
        return button
    end

    UI.qAbilityButton = createAbilityButton(12)
    UI.eAbilityButton = createAbilityButton(156)

    local function createSlider(labelPrefix, y, minVal, maxVal, initialVal, isFloat, onChanged)
        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(1, -24, 0, 22)
        label.Position = UDim2.fromOffset(12, y)
        label.BackgroundTransparency = 1
        label.Font = Enum.Font.GothamMedium
        label.TextColor3 = Color3.fromRGB(220, 222, 230)
        label.TextSize = 13
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.Parent = mainFrame

        local track = Instance.new("Frame")
        track.Size = UDim2.new(1, -24, 0, 8)
        track.Position = UDim2.fromOffset(12, y + 26)
        track.BackgroundColor3 = Color3.fromRGB(66, 70, 82)
        track.BorderSizePixel = 0
        track.Active = true
        track.Parent = mainFrame
        addCorner(track, 4)

        local fill = Instance.new("Frame")
        fill.Size = UDim2.fromScale(0, 1)
        fill.BackgroundColor3 = Color3.fromRGB(78, 142, 232)
        fill.BorderSizePixel = 0
        fill.Parent = track
        addCorner(fill, 4)

        local knob = Instance.new("Frame")
        knob.Size = UDim2.fromOffset(16, 16)
        knob.AnchorPoint = Vector2.new(0.5, 0.5)
        knob.BackgroundColor3 = Color3.fromRGB(238, 240, 246)
        knob.BorderSizePixel = 0
        knob.Active = true
        knob.Parent = track
        addCorner(knob, 8)

        local dragging = false
        local function setFromAlpha(alpha)
            alpha = math.clamp(alpha, 0, 1)
            local value
            if isFloat then
                value = math.floor((minVal + ((maxVal - minVal) * alpha)) * 10 + 0.5) / 10
                label.Text = string.format("%s: %.1f", labelPrefix, value)
            else
                value = math.floor(minVal + ((maxVal - minVal) * alpha) + 0.5)
                label.Text = labelPrefix .. ": " .. tostring(value)
            end
            fill.Size = UDim2.fromScale(alpha, 1)
            knob.Position = UDim2.fromScale(alpha, 0.5)
            onChanged(value)
        end

        local function setFromX(x)
            if track.AbsoluteSize.X > 0 then
                setFromAlpha((x - track.AbsolutePosition.X) / track.AbsoluteSize.X)
            end
        end

        local function beginDrag(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragging = true
                setFromX(input.Position.X)
            end
        end

        track.InputBegan:Connect(beginDrag)
        knob.InputBegan:Connect(beginDrag)
        table.insert(sliderConnections, UserInputService.InputChanged:Connect(function(input)
            if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
                setFromX(input.Position.X)
            end
        end))
        table.insert(sliderConnections, UserInputService.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragging = false
            end
        end))

        setFromAlpha((initialVal - minVal) / (maxVal - minVal))
    end

    -- Ability radius gate (2.2.0): Q/E only fire while an enemy is inside the
    -- radius, and the radius can be drawn around the character.
    local function makeHalfButton(x, y)
        local button = Instance.new("TextButton")
        button.Size = UDim2.fromOffset(132, 32)
        button.Position = UDim2.fromOffset(x, y)
        button.BackgroundColor3 = Color3.fromRGB(180, 64, 64)
        button.BorderSizePixel = 0
        button.Font = Enum.Font.GothamBold
        button.TextColor3 = Color3.fromRGB(255, 255, 255)
        button.TextSize = 13
        button.Parent = mainFrame
        addCorner(button, 7)
        return button
    end

    UI.abilityRadiusButton = makeHalfButton(12, 298)
    UI.showAbilityRadiusButton = makeHalfButton(156, 298)

    local function syncAbilityRadiusButtons()
        UI.abilityRadiusButton.Text = "Q/E in radius: " .. (CFG.abilityRadiusEnabled and "ON" or "OFF")
        UI.abilityRadiusButton.BackgroundColor3 = CFG.abilityRadiusEnabled
            and Color3.fromRGB(52, 168, 83) or Color3.fromRGB(180, 64, 64)
        UI.showAbilityRadiusButton.Text = "Show radius: " .. (CFG.showAbilityRadius and "ON" or "OFF")
        UI.showAbilityRadiusButton.BackgroundColor3 = CFG.showAbilityRadius
            and Color3.fromRGB(52, 168, 83) or Color3.fromRGB(180, 64, 64)
    end
    syncAbilityRadiusButtons()

    UI.abilityRadiusButton.MouseButton1Click:Connect(function()
        CFG.abilityRadiusEnabled = not CFG.abilityRadiusEnabled
        syncAbilityRadiusButtons()
    end)
    UI.showAbilityRadiusButton.MouseButton1Click:Connect(function()
        CFG.showAbilityRadius = not CFG.showAbilityRadius
        syncAbilityRadiusButtons()
        updateHitboxVisualizer()
    end)

    createSlider("Ability radius", 336, CFG.minAbilityRadius, CFG.maxAbilityRadius, CFG.abilityRadius, false, function(v)
        CFG.abilityRadius = v
        if CFG.showAbilityRadius then updateHitboxVisualizer() end
    end)

    createSlider("Attack range", 386, CFG.minimumAttackRange, CFG.maximumAttackRange, CFG.attackRange, false, function(v) CFG.attackRange = v end)
    createSlider("Safe distance", 436, CFG.minimumSafeDistance, CFG.maximumSafeDistance, CFG.safeDistance, false, function(v) CFG.safeDistance = v end)
    createSlider("Wall padding clearance", 486, CFG.minimumWallPadding, CFG.maximumWallPadding, CFG.wallPadding, true, function(v) CFG.wallPadding = v end)
    createSlider("Telegraph buffer range", 536, CFG.minimumDamageBrickRange, CFG.maximumDamageBrickRange, CFG.damageBrickDetectionRange, false, function(v) CFG.damageBrickDetectionRange = v end)

    -- Enemy attacks are always highlighted since 2.3.0; the slot the toggle used
    -- holds the trial-run switch and the Attack Book panel button instead.
    UI.trialButton = makeHalfButton(12, 591)
    UI.trialButton.Text = "Trial Run: OFF"
    UI.attackBookButton = makeHalfButton(156, 591)
    UI.attackBookButton.BackgroundColor3 = Color3.fromRGB(148, 92, 232)
    UI.attackBookButton.Text = "Attack Book (0)"

    UI.renderPathButton = Instance.new("TextButton")
    UI.renderPathButton.Size = UDim2.new(1, -24, 0, 32)
    UI.renderPathButton.Position = UDim2.fromOffset(12, 629)
    UI.renderPathButton.BackgroundColor3 = Color3.fromRGB(52, 168, 83)
    UI.renderPathButton.BorderSizePixel = 0
    UI.renderPathButton.Font = Enum.Font.GothamBold
    UI.renderPathButton.Text = "Render path nodes: ON"
    UI.renderPathButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    UI.renderPathButton.TextSize = 13
    UI.renderPathButton.Parent = mainFrame
    addCorner(UI.renderPathButton, 7)

    UI.renderHitboxButton = Instance.new("TextButton")
    UI.renderHitboxButton.Size = UDim2.new(1, -24, 0, 32)
    UI.renderHitboxButton.Position = UDim2.fromOffset(12, 667)
    UI.renderHitboxButton.BackgroundColor3 = Color3.fromRGB(52, 168, 83)
    UI.renderHitboxButton.BorderSizePixel = 0
    UI.renderHitboxButton.Font = Enum.Font.GothamBold
    UI.renderHitboxButton.Text = "Render Player Hitbox: ON"
    UI.renderHitboxButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    UI.renderHitboxButton.TextSize = 13
    UI.renderHitboxButton.Parent = mainFrame
    addCorner(UI.renderHitboxButton, 7)

    UI.wallDisplayButton = Instance.new("TextButton")
    UI.wallDisplayButton.Size = UDim2.fromOffset(132, 32)
    UI.wallDisplayButton.Position = UDim2.fromOffset(12, 705)
    UI.wallDisplayButton.BackgroundColor3 = CFG.showWalls and Color3.fromRGB(52, 168, 83) or Color3.fromRGB(180, 64, 64)
    UI.wallDisplayButton.BorderSizePixel = 0
    UI.wallDisplayButton.Font = Enum.Font.GothamBold
    UI.wallDisplayButton.Text = "Show Walls: " .. (CFG.showWalls and "ON" or "OFF")
    UI.wallDisplayButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    UI.wallDisplayButton.TextSize = 13
    UI.wallDisplayButton.Parent = mainFrame
    addCorner(UI.wallDisplayButton, 7)

    UI.pathEditButton = Instance.new("TextButton")
    UI.pathEditButton.Size = UDim2.fromOffset(132, 32)
    UI.pathEditButton.Position = UDim2.fromOffset(156, 705)
    UI.pathEditButton.BackgroundColor3 = Color3.fromRGB(180, 64, 64)
    UI.pathEditButton.BorderSizePixel = 0
    UI.pathEditButton.Font = Enum.Font.GothamBold
    UI.pathEditButton.Text = "Edit Path: OFF"
    UI.pathEditButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    UI.pathEditButton.TextSize = 13
    UI.pathEditButton.Parent = mainFrame
    addCorner(UI.pathEditButton, 7)

    UI.streamerPanelButton = Instance.new("TextButton")
    UI.streamerPanelButton.Size = UDim2.new(1, -24, 0, 32)
    UI.streamerPanelButton.Position = UDim2.fromOffset(12, 743)
    UI.streamerPanelButton.BackgroundColor3 = Color3.fromRGB(148, 92, 232)
    UI.streamerPanelButton.BorderSizePixel = 0
    UI.streamerPanelButton.Font = Enum.Font.GothamBold
    UI.streamerPanelButton.Text = "Streamer Mode Panel"
    UI.streamerPanelButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    UI.streamerPanelButton.TextSize = 13
    UI.streamerPanelButton.Parent = mainFrame
    addCorner(UI.streamerPanelButton, 7)

    -- Two pickers side by side: mark a telegraph the heuristics missed, or mark
    -- one of your own ability effects so it is never treated as one (2.2.0).
    UI.pickerButton = makeHalfButton(12, 781)
    UI.pickerButton.Text = "Pick Telegraph: OFF"
    UI.ownPickerButton = makeHalfButton(156, 781)
    UI.ownPickerButton.Text = "Pick Own FX: OFF"

    UI.debugButton = Instance.new("TextButton")
    UI.debugButton.Size = UDim2.new(1, -24, 0, 32)
    UI.debugButton.Position = UDim2.fromOffset(12, 819)
    UI.debugButton.BackgroundColor3 = Color3.fromRGB(78, 142, 232)
    UI.debugButton.BorderSizePixel = 0
    UI.debugButton.Font = Enum.Font.GothamBold
    UI.debugButton.Text = "Debug: NORMAL"
    UI.debugButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    UI.debugButton.TextSize = 13
    UI.debugButton.Parent = mainFrame
    addCorner(UI.debugButton, 7)

    local destructButton = Instance.new("TextButton")
    destructButton.Size = UDim2.new(1, -24, 0, 32)
    destructButton.Position = UDim2.fromOffset(12, 857)
    destructButton.BackgroundColor3 = Color3.fromRGB(202, 55, 55)
    destructButton.BorderSizePixel = 0
    destructButton.Font = Enum.Font.GothamBold
    destructButton.Text = "Destruct"
    destructButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    destructButton.TextSize = 13
    destructButton.Parent = mainFrame
    addCorner(destructButton, 7)

    -- Footer build stamp (always visible; badge hover swaps, this does not)
    local buildStamp = Instance.new("TextLabel")
    buildStamp.Name = "BuildStamp"
    buildStamp.Size = UDim2.new(1, -24, 0, 18)
    buildStamp.Position = UDim2.fromOffset(12, 897)
    buildStamp.BackgroundTransparency = 1
    buildStamp.Font = Enum.Font.Gotham
    buildStamp.Text = string.format("v%s \"%s\"  -  build %s", SCRIPT_VERSION, SCRIPT_CODENAME, SCRIPT_BUILD_DATE)
    buildStamp.TextColor3 = Color3.fromRGB(120, 125, 140)
    buildStamp.TextSize = 11
    buildStamp.TextXAlignment = Enum.TextXAlignment.Center
    buildStamp.Parent = mainFrame

    SM.panel = createStreamerPanel(RT.scriptGui, makeDraggable)

    UI.streamerPanelButton.MouseButton1Click:Connect(function()
        SM.panel.Visible = not SM.panel.Visible
    end)

    -- Path waypoint editor panel: lists the waypoints with reorder / delete, and
    -- is shown while Edit Path is on.
    local pathPanel = Instance.new("Frame")
    pathPanel.Name = "PathPanel"
    pathPanel.Size = UDim2.fromOffset(268, 452)
    pathPanel.Position = UDim2.new(0, 24, 0, 20)
    pathPanel.BackgroundColor3 = Color3.fromRGB(25, 27, 34)
    pathPanel.BorderSizePixel = 0
    pathPanel.Active = true
    pathPanel.Visible = false
    pathPanel.Parent = RT.scriptGui
    addCorner(pathPanel, 10)

    local pathTitle = Instance.new("TextLabel")
    pathTitle.Size = UDim2.new(1, -20, 0, 26)
    pathTitle.Position = UDim2.fromOffset(12, 8)
    pathTitle.BackgroundTransparency = 1
    pathTitle.Font = Enum.Font.GothamBold
    pathTitle.Text = "Path Waypoints"
    pathTitle.TextColor3 = Color3.fromRGB(255, 200, 90)
    pathTitle.TextSize = 15
    pathTitle.TextXAlignment = Enum.TextXAlignment.Left
    pathTitle.Parent = pathPanel
    makeDraggable(pathTitle, pathPanel)

    local pathHint = Instance.new("TextLabel")
    pathHint.Size = UDim2.new(1, -20, 0, 30)
    pathHint.Position = UDim2.fromOffset(12, 34)
    pathHint.BackgroundTransparency = 1
    pathHint.Font = Enum.Font.Gotham
    pathHint.Text = "Fly: WASD + E/Q. Look: hold right mouse. Left-click the map to drop a point."
    pathHint.TextColor3 = Color3.fromRGB(160, 165, 180)
    pathHint.TextSize = 11
    pathHint.TextWrapped = true
    pathHint.TextXAlignment = Enum.TextXAlignment.Left
    pathHint.TextYAlignment = Enum.TextYAlignment.Top
    pathHint.Parent = pathPanel

    -- Clear-radius slider (how close counts as passing a waypoint).
    local radiusLabel = Instance.new("TextLabel")
    radiusLabel.Size = UDim2.new(1, -20, 0, 16)
    radiusLabel.Position = UDim2.fromOffset(12, 70)
    radiusLabel.BackgroundTransparency = 1
    radiusLabel.Font = Enum.Font.GothamMedium
    radiusLabel.Text = string.format("Clear radius: %.0f", CFG.waypointClearRadius)
    radiusLabel.TextColor3 = Color3.fromRGB(220, 222, 230)
    radiusLabel.TextSize = 12
    radiusLabel.TextXAlignment = Enum.TextXAlignment.Left
    radiusLabel.Parent = pathPanel

    local radiusTrack = Instance.new("Frame")
    radiusTrack.Size = UDim2.new(1, -20, 0, 8)
    radiusTrack.Position = UDim2.fromOffset(10, 90)
    radiusTrack.BackgroundColor3 = Color3.fromRGB(66, 70, 82)
    radiusTrack.BorderSizePixel = 0
    radiusTrack.Active = true
    radiusTrack.Parent = pathPanel
    addCorner(radiusTrack, 4)
    local radiusFill = Instance.new("Frame")
    radiusFill.BackgroundColor3 = Color3.fromRGB(90, 190, 255)
    radiusFill.BorderSizePixel = 0
    radiusFill.Parent = radiusTrack
    addCorner(radiusFill, 4)
    local radiusKnob = Instance.new("Frame")
    radiusKnob.Size = UDim2.fromOffset(16, 16)
    radiusKnob.AnchorPoint = Vector2.new(0.5, 0.5)
    radiusKnob.BackgroundColor3 = Color3.fromRGB(238, 240, 246)
    radiusKnob.BorderSizePixel = 0
    radiusKnob.Active = true
    radiusKnob.Parent = radiusTrack
    addCorner(radiusKnob, 8)

    local function setRadiusAlpha(alpha)
        alpha = math.clamp(alpha, 0, 1)
        local value = math.floor(CFG.minWaypointClearRadius
            + (CFG.maxWaypointClearRadius - CFG.minWaypointClearRadius) * alpha + 0.5)
        CFG.waypointClearRadius = value
        radiusLabel.Text = string.format("Clear radius: %d", value)
        radiusFill.Size = UDim2.fromScale(alpha, 1)
        radiusKnob.Position = UDim2.fromScale(alpha, 0.5)
        if NAV.showRadius then renderPathMarkers() end
    end
    setRadiusAlpha((CFG.waypointClearRadius - CFG.minWaypointClearRadius)
        / (CFG.maxWaypointClearRadius - CFG.minWaypointClearRadius))
    local radiusDragging = false
    local function radiusFromX(x)
        if radiusTrack.AbsoluteSize.X > 0 then
            setRadiusAlpha((x - radiusTrack.AbsolutePosition.X) / radiusTrack.AbsoluteSize.X)
        end
    end
    local function radiusBegin(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            radiusDragging = true
            radiusFromX(input.Position.X)
        end
    end
    radiusTrack.InputBegan:Connect(radiusBegin)
    radiusKnob.InputBegan:Connect(radiusBegin)
    table.insert(sliderConnections, UserInputService.InputChanged:Connect(function(input)
        if radiusDragging and (input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch) then
            radiusFromX(input.Position.X)
        end
    end))
    table.insert(sliderConnections, UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            radiusDragging = false
        end
    end))

    local showRadiusButton = Instance.new("TextButton")
    showRadiusButton.Size = UDim2.new(1, -20, 0, 26)
    showRadiusButton.Position = UDim2.fromOffset(10, 106)
    showRadiusButton.BackgroundColor3 = Color3.fromRGB(180, 64, 64)
    showRadiusButton.BorderSizePixel = 0
    showRadiusButton.Font = Enum.Font.GothamBold
    showRadiusButton.Text = "Show Radius: OFF"
    showRadiusButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    showRadiusButton.TextSize = 12
    showRadiusButton.Parent = pathPanel
    addCorner(showRadiusButton, 6)
    showRadiusButton.MouseButton1Click:Connect(function()
        NAV.showRadius = not NAV.showRadius
        showRadiusButton.Text = "Show Radius: " .. (NAV.showRadius and "ON" or "OFF")
        showRadiusButton.BackgroundColor3 = NAV.showRadius and Color3.fromRGB(52, 168, 83) or Color3.fromRGB(180, 64, 64)
        renderPathMarkers()
    end)

    local pathList = Instance.new("ScrollingFrame")
    pathList.Size = UDim2.new(1, -20, 1, -216)
    pathList.Position = UDim2.fromOffset(10, 140)
    pathList.BackgroundTransparency = 1
    pathList.BorderSizePixel = 0
    pathList.ScrollBarThickness = 4
    pathList.ScrollBarImageColor3 = Color3.fromRGB(80, 85, 100)
    pathList.CanvasSize = UDim2.new(0, 0, 0, 0)
    pathList.AutomaticCanvasSize = Enum.AutomaticSize.Y
    pathList.Parent = pathPanel
    local pathLayout = Instance.new("UIListLayout")
    pathLayout.Padding = UDim.new(0, 4)
    pathLayout.SortOrder = Enum.SortOrder.LayoutOrder
    pathLayout.Parent = pathList
    UI.pathListFrame = pathList

    -- Save / Load / Clear row along the bottom.
    local function bottomButton(text, x, color, onClick)
        local b = Instance.new("TextButton")
        b.Size = UDim2.fromOffset(78, 30)
        b.Position = UDim2.new(0, x, 1, -38)
        b.BackgroundColor3 = color
        b.BorderSizePixel = 0
        b.Font = Enum.Font.GothamBold
        b.Text = text
        b.TextColor3 = Color3.fromRGB(255, 255, 255)
        b.TextSize = 12
        b.Parent = pathPanel
        addCorner(b, 6)
        b.MouseButton1Click:Connect(onClick)
        return b
    end
    local savePathButton = bottomButton("Save", 10, Color3.fromRGB(52, 168, 83), function()
        local ok, err = saveConfig()
        setMovementState(ok and "path + config saved" or ("save failed: " .. tostring(err)))
    end)
    bottomButton("Load", 94, Color3.fromRGB(78, 142, 232), function()
        loadConfig()
        renderPathMarkers()
        if S.refreshPathPanel then S.refreshPathPanel() end
        setMovementState("config loaded")
    end)
    bottomButton("Clear", 178, Color3.fromRGB(180, 64, 64), clearWaypath)
    savePathButton.Active = true

    -- Assign the forward-declared rebuilder now that the list frame exists.
    S.refreshPathPanel = function()
        if not UI.pathListFrame then return end
        for _, child in ipairs(UI.pathListFrame:GetChildren()) do
            if child:IsA("GuiObject") then child:Destroy() end
        end
        for i, pos in ipairs(NAV.waypath) do
            local row = Instance.new("Frame")
            row.Size = UDim2.new(1, 0, 0, 30)
            row.BackgroundColor3 = Color3.fromRGB(35, 38, 47)
            row.BorderSizePixel = 0
            row.LayoutOrder = i
            row.Parent = UI.pathListFrame
            addCorner(row, 5)

            local info = Instance.new("TextLabel")
            info.Size = UDim2.new(1, -96, 1, 0)
            info.Position = UDim2.fromOffset(8, 0)
            info.BackgroundTransparency = 1
            info.Font = Enum.Font.GothamMedium
            info.Text = string.format("#%d  (%.0f, %.0f, %.0f)", i, pos.X, pos.Y, pos.Z)
            info.TextColor3 = Color3.fromRGB(225, 227, 235)
            info.TextSize = 12
            info.TextXAlignment = Enum.TextXAlignment.Left
            info.TextTruncate = Enum.TextTruncate.AtEnd
            info.Parent = row

            local function miniButton(text, x, color, onClick)
                local b = Instance.new("TextButton")
                b.Size = UDim2.fromOffset(26, 24)
                b.Position = UDim2.new(1, x, 0.5, -12)
                b.BackgroundColor3 = color
                b.BorderSizePixel = 0
                b.Font = Enum.Font.GothamBold
                b.Text = text
                b.TextColor3 = Color3.fromRGB(255, 255, 255)
                b.TextSize = 14
                b.Parent = row
                addCorner(b, 5)
                b.MouseButton1Click:Connect(onClick)
            end
            miniButton("^", -90, Color3.fromRGB(70, 110, 175), function() moveWaypoint(i, -1) end)
            miniButton("v", -62, Color3.fromRGB(70, 110, 175), function() moveWaypoint(i, 1) end)
            miniButton("X", -32, Color3.fromRGB(180, 64, 64), function() removeWaypoint(i) end)
        end
    end
    S.refreshPathPanel()

    -- Attack Book panel (2.3.0): what the trial runs have learned. Rename a row
    -- by typing in its name box, ON/OFF decides whether it is dodged, X forgets
    -- it, Save writes the book (with everything else) to the config.
    bookPanel = Instance.new("Frame")
    bookPanel.Name = "AttackBookPanel"
    bookPanel.Size = UDim2.fromOffset(300, 452)
    bookPanel.Position = UDim2.new(0, 300, 0, 20)
    bookPanel.BackgroundColor3 = Color3.fromRGB(25, 27, 34)
    bookPanel.BorderSizePixel = 0
    bookPanel.Active = true
    bookPanel.Visible = false
    bookPanel.Parent = RT.scriptGui
    addCorner(bookPanel, 10)

    local bookTitle = Instance.new("TextLabel")
    bookTitle.Size = UDim2.new(1, -20, 0, 26)
    bookTitle.Position = UDim2.fromOffset(12, 8)
    bookTitle.BackgroundTransparency = 1
    bookTitle.Font = Enum.Font.GothamBold
    bookTitle.Text = "Attack Book"
    bookTitle.TextColor3 = Color3.fromRGB(255, 120, 120)
    bookTitle.TextSize = 15
    bookTitle.TextXAlignment = Enum.TextXAlignment.Left
    bookTitle.Parent = bookPanel
    makeDraggable(bookTitle, bookPanel)

    local bookHint = Instance.new("TextLabel")
    bookHint.Size = UDim2.new(1, -20, 0, 44)
    bookHint.Position = UDim2.fromOffset(12, 34)
    bookHint.BackgroundTransparency = 1
    bookHint.Font = Enum.Font.Gotham
    bookHint.Text = "Trial Run ON: every hit you take is matched to what appeared around you and named here. Type to rename. OFF = not dodged. X = forget. Save writes the book to the config."
    bookHint.TextColor3 = Color3.fromRGB(160, 165, 180)
    bookHint.TextSize = 11
    bookHint.TextWrapped = true
    bookHint.TextXAlignment = Enum.TextXAlignment.Left
    bookHint.TextYAlignment = Enum.TextYAlignment.Top
    bookHint.Parent = bookPanel

    local bookList = Instance.new("ScrollingFrame")
    bookList.Size = UDim2.new(1, -20, 1, -132)
    bookList.Position = UDim2.fromOffset(10, 84)
    bookList.BackgroundTransparency = 1
    bookList.BorderSizePixel = 0
    bookList.ScrollBarThickness = 4
    bookList.ScrollBarImageColor3 = Color3.fromRGB(80, 85, 100)
    bookList.CanvasSize = UDim2.new(0, 0, 0, 0)
    bookList.AutomaticCanvasSize = Enum.AutomaticSize.Y
    bookList.Parent = bookPanel
    local bookLayout = Instance.new("UIListLayout")
    bookLayout.Padding = UDim.new(0, 4)
    bookLayout.SortOrder = Enum.SortOrder.LayoutOrder
    bookLayout.Parent = bookList

    local function bookButton(text, x, color, onClick)
        local b = Instance.new("TextButton")
        b.Size = UDim2.fromOffset(86, 30)
        b.Position = UDim2.new(0, x, 1, -38)
        b.BackgroundColor3 = color
        b.BorderSizePixel = 0
        b.Font = Enum.Font.GothamBold
        b.Text = text
        b.TextColor3 = Color3.fromRGB(255, 255, 255)
        b.TextSize = 12
        b.Parent = bookPanel
        addCorner(b, 6)
        b.MouseButton1Click:Connect(onClick)
        return b
    end
    bookButton("Save", 10, Color3.fromRGB(52, 168, 83), function()
        local ok, err = saveConfig()
        setMovementState(ok and "attack book + config saved" or ("save failed: " .. tostring(err)))
    end)
    bookButton("Clear", 106, Color3.fromRGB(180, 64, 64), function()
        clearAttackBook()
    end)
    bookButton("Close", 202, Color3.fromRGB(70, 75, 90), function()
        bookPanel.Visible = false
    end)

    S.refreshAttackBookPanel = function()
        if UI.attackBookButton then
            UI.attackBookButton.Text = string.format("Attack Book (%d)", #HZ.attackBook)
        end
        if not bookList.Parent then return end
        for _, child in ipairs(bookList:GetChildren()) do
            if child:IsA("GuiObject") then child:Destroy() end
        end
        if #HZ.attackBook == 0 then
            local empty = Instance.new("TextLabel")
            empty.Size = UDim2.new(1, 0, 0, 24)
            empty.BackgroundTransparency = 1
            empty.Font = Enum.Font.Gotham
            empty.Text = "Nothing learned yet. Turn Trial Run on and take a hit."
            empty.TextColor3 = Color3.fromRGB(150, 153, 165)
            empty.TextSize = 12
            empty.Parent = bookList
            return
        end
        for i, record in ipairs(HZ.attackBook) do
            local row = Instance.new("Frame")
            row.Size = UDim2.new(1, 0, 0, 46)
            row.BackgroundColor3 = Color3.fromRGB(35, 38, 47)
            row.BorderSizePixel = 0
            row.LayoutOrder = i
            row.Parent = bookList
            addCorner(row, 5)

            local nameBox = Instance.new("TextBox")
            nameBox.Size = UDim2.new(1, -104, 0, 20)
            nameBox.Position = UDim2.fromOffset(8, 3)
            nameBox.BackgroundColor3 = Color3.fromRGB(45, 48, 58)
            nameBox.BorderSizePixel = 0
            nameBox.Font = Enum.Font.GothamBold
            nameBox.Text = record.name
            nameBox.TextColor3 = record.enabled ~= false and Color3.fromRGB(255, 140, 140) or Color3.fromRGB(150, 153, 165)
            nameBox.TextSize = 12
            nameBox.TextXAlignment = Enum.TextXAlignment.Left
            nameBox.ClearTextOnFocus = false
            nameBox.Parent = row
            addCorner(nameBox, 4)
            nameBox.FocusLost:Connect(function()
                local text = nameBox.Text:gsub("^%s+", ""):gsub("%s+$", "")
                if text == "" then
                    nameBox.Text = record.name
                else
                    record.name = text
                end
            end)

            local info = Instance.new("TextLabel")
            info.Size = UDim2.new(1, -104, 0, 18)
            info.Position = UDim2.fromOffset(8, 25)
            info.BackgroundTransparency = 1
            info.Font = Enum.Font.Gotham
            info.Text = string.format("%d hit%s, %.0f dmg - %s%s%s",
                record.hits or 0, (record.hits or 0) == 1 and "" or "s", record.damage or 0,
                describeRecord(record),
                record.moving and ", moving" or "",
                record.melee and ", in creature" or "")
            info.TextColor3 = Color3.fromRGB(170, 175, 190)
            info.TextSize = 10
            info.TextXAlignment = Enum.TextXAlignment.Left
            info.TextTruncate = Enum.TextTruncate.AtEnd
            info.Parent = row

            local onOff = Instance.new("TextButton")
            onOff.Size = UDim2.fromOffset(40, 24)
            onOff.Position = UDim2.new(1, -90, 0.5, -12)
            onOff.BackgroundColor3 = record.enabled ~= false and Color3.fromRGB(52, 168, 83) or Color3.fromRGB(90, 95, 110)
            onOff.BorderSizePixel = 0
            onOff.Font = Enum.Font.GothamBold
            onOff.Text = record.enabled ~= false and "ON" or "OFF"
            onOff.TextColor3 = Color3.fromRGB(255, 255, 255)
            onOff.TextSize = 11
            onOff.Parent = row
            addCorner(onOff, 5)
            onOff.MouseButton1Click:Connect(function()
                record.enabled = not (record.enabled ~= false)
                invalidateAttackBook()
            end)

            local del = Instance.new("TextButton")
            del.Size = UDim2.fromOffset(26, 24)
            del.Position = UDim2.new(1, -36, 0.5, -12)
            del.BackgroundColor3 = Color3.fromRGB(180, 64, 64)
            del.BorderSizePixel = 0
            del.Font = Enum.Font.GothamBold
            del.Text = "X"
            del.TextColor3 = Color3.fromRGB(255, 255, 255)
            del.TextSize = 14
            del.Parent = row
            addCorner(del, 5)
            del.MouseButton1Click:Connect(function()
                removeAttackRecord(i)
            end)
        end
    end
    S.refreshAttackBookPanel()

    UI.pathEditButton.MouseButton1Click:Connect(function()
        local turnOn = not NAV.pathEditEnabled
        if turnOn then
            -- Pause farming while editing so the character holds still and only
            -- the camera flies; remember the state to restore on exit.
            NAV.farmWasEnabled = RT.farmEnabled
            RT.farmEnabled = false
            stopCharacterMovement()
            setLoopButtonState()
        end
        setPathEditEnabled(turnOn)
        pathPanel.Visible = turnOn
        if turnOn then S.refreshPathPanel() end
        UI.pathEditButton.Text = turnOn and "Edit Path: ON" or "Edit Path: OFF"
        UI.pathEditButton.BackgroundColor3 = turnOn
            and Color3.fromRGB(232, 168, 52) or Color3.fromRGB(180, 64, 64)
        if not turnOn and NAV.farmWasEnabled then
            RT.farmEnabled = true
            setLoopButtonState()
        end
    end)

    UI.toggleButton.MouseButton1Click:Connect(function()
        if RT.destroyed then return end
        RT.farmEnabled = not RT.farmEnabled
        setLoopButtonState()
        if not RT.farmEnabled then
            resetPursuitPath()
            clearHitboxVisualizer()
            clearHoverHighlight()
            stopCharacterMovement()
            updateEnemyDisplay(nil, 0)
        end
    end)

    UI.qAbilityButton.MouseButton1Click:Connect(function()
        RT.autoQEnabled = not RT.autoQEnabled
        setAbilityButtonState(UI.qAbilityButton, "Q", RT.autoQEnabled)
    end)

    UI.eAbilityButton.MouseButton1Click:Connect(function()
        RT.autoEEnabled = not RT.autoEEnabled
        setAbilityButtonState(UI.eAbilityButton, "E", RT.autoEEnabled)
    end)

    UI.trialButton.MouseButton1Click:Connect(function()
        setTrialEnabled(not HZ.trialEnabled)
        UI.trialButton.Text = "Trial Run: " .. (HZ.trialEnabled and "ON" or "OFF")
        UI.trialButton.BackgroundColor3 = HZ.trialEnabled
            and Color3.fromRGB(232, 142, 78) or Color3.fromRGB(180, 64, 64)
        if HZ.trialEnabled then
            bookPanel.Visible = true
            S.refreshAttackBookPanel()
        end
    end)

    UI.attackBookButton.MouseButton1Click:Connect(function()
        bookPanel.Visible = not bookPanel.Visible
        if bookPanel.Visible then S.refreshAttackBookPanel() end
    end)

    UI.renderPathButton.MouseButton1Click:Connect(function()
        RT.renderPathEnabled = not RT.renderPathEnabled
        UI.renderPathButton.Text = "Render path nodes: " .. (RT.renderPathEnabled and "ON" or "OFF")
        UI.renderPathButton.BackgroundColor3 = RT.renderPathEnabled and Color3.fromRGB(52, 168, 83) or Color3.fromRGB(180, 64, 64)
        if RT.renderPathEnabled then
            renderCurrentPath()
            renderEscapeRoute()
        else
            clearRenderedPath()
            clearEscapeNodes()
        end
    end)

    UI.renderHitboxButton.MouseButton1Click:Connect(function()
        RT.renderHitboxEnabled = not RT.renderHitboxEnabled
        UI.renderHitboxButton.Text = "Render Player Hitbox: " .. (RT.renderHitboxEnabled and "ON" or "OFF")
        UI.renderHitboxButton.BackgroundColor3 = RT.renderHitboxEnabled and Color3.fromRGB(52, 168, 83) or Color3.fromRGB(180, 64, 64)
        if not RT.renderHitboxEnabled then clearHitboxVisualizer() else updateHitboxVisualizer() end
    end)

    UI.wallDisplayButton.MouseButton1Click:Connect(function()
        CFG.showWalls = not CFG.showWalls
        UI.wallDisplayButton.Text = "Show Walls: " .. (CFG.showWalls and "ON" or "OFF")
        UI.wallDisplayButton.BackgroundColor3 = CFG.showWalls and Color3.fromRGB(52, 168, 83) or Color3.fromRGB(180, 64, 64)
        -- The invisible-wall sweep rides the world index's round-robin while the
        -- overlay is on; turning it off drops the catalog and the boxes.
        if not CFG.showWalls then
            resetWallCatalog()
            updateWallHighlights()
        else
            NAV.forceRescan = true
        end
    end)

    local function syncPickerButtons()
        local telegraphOn = HZ.pickerEnabled and not HZ.ownPickerEnabled
        local ownOn = HZ.pickerEnabled and HZ.ownPickerEnabled
        UI.pickerButton.Text = "Pick Telegraph: " .. (telegraphOn and "ON" or "OFF")
        UI.pickerButton.BackgroundColor3 = telegraphOn
            and Color3.fromRGB(232, 142, 78) or Color3.fromRGB(180, 64, 64)
        UI.ownPickerButton.Text = "Pick Own FX: " .. (ownOn and "ON" or "OFF")
        UI.ownPickerButton.BackgroundColor3 = ownOn
            and Color3.fromRGB(232, 142, 78) or Color3.fromRGB(180, 64, 64)
    end

    UI.pickerButton.MouseButton1Click:Connect(function()
        local turnOn = not (HZ.pickerEnabled and not HZ.ownPickerEnabled)
        setTelegraphPickerEnabled(turnOn, "telegraph")
        syncPickerButtons()
    end)

    UI.ownPickerButton.MouseButton1Click:Connect(function()
        local turnOn = not (HZ.pickerEnabled and HZ.ownPickerEnabled)
        setTelegraphPickerEnabled(turnOn, "own")
        syncPickerButtons()
    end)

    UI.debugButton.MouseButton1Click:Connect(function()
        RT.debugLevel = (RT.debugLevel + 1) % 3
        local names = { [DEBUG_OFF] = "OFF", [DEBUG_NORMAL] = "NORMAL", [DEBUG_VERBOSE] = "VERBOSE" }
        local colors = {
            [DEBUG_OFF] = Color3.fromRGB(90, 95, 110),
            [DEBUG_NORMAL] = Color3.fromRGB(78, 142, 232),
            [DEBUG_VERBOSE] = Color3.fromRGB(232, 142, 78),
        }
        UI.debugButton.Text = "Debug: " .. names[RT.debugLevel]
        UI.debugButton.BackgroundColor3 = colors[RT.debugLevel]
        -- Clear the change/throttle caches so the new level re-emits current state
        -- immediately instead of waiting for the next genuine transition.
        table.clear(debugLastValues)
        table.clear(debugThrottleClocks)
    end)

    destructButton.MouseButton1Click:Connect(destructScript)

    setLoopButtonState()
    setAbilityButtonState(UI.qAbilityButton, "Q", RT.autoQEnabled)
    setAbilityButtonState(UI.eAbilityButton, "E", RT.autoEEnabled)
end

S.createControlUI = createControlUI
S.stopCharacterMovement = stopCharacterMovement
S.updateEnemyDisplay = updateEnemyDisplay
end
