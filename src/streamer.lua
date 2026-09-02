-- streamer.lua - Streamer Mode: local cosmetic masking of the account identity.
-- Module contract: receives the shared table S. Everything this module needs from
-- earlier modules is pulled into locals below; everything later modules need is
-- assigned onto S at the bottom. Load order is fixed by main.lua / build.py.
return function(S)
local RT = S.RT
local SM = S.SM
local heavyDebug = S.heavyDebug
local LocalPlayer = S.LocalPlayer
local RunService = S.RunService
local heavyDebugThrottled = S.heavyDebugThrottled
local UserInputService = S.UserInputService
local SCRIPT_VERSION = S.SCRIPT_VERSION

--[[ ===========================================================================
    STREAMER MODE

    Local cosmetic overlay for streaming: masks the account identity on screen.
    It rewrites what THIS client renders, nothing else. The server, other
    players, and every leaderboard still see the real account, so this hides
    your name on stream, it does not change your name in the game.

    The game's GUI hierarchy is unknown to this script, so targets are found by
    content rather than by path: any text showing the real username or display
    name is rewritten, any image sourced from the real user id is swapped. HP,
    EXP, level and VIP fields are matched by name keywords, and anything the
    keywords miss can be bound by hand with the row's bind button.
=========================================================================== ]]

SM.enabled = false
SM.connection = nil
SM.bindConnection = nil
SM.panel = nil
SM.statusLabel = nil

SM.fields = {
    username = "Streamer",
    hp = "",
    vipTitle = "",
    exp = "",
    level = "",
    coins = "",
    gems = "",
}

SM.vipColor = Color3.fromRGB(255, 200, 60)
SM.borderColor = Color3.fromRGB(255, 200, 60)
SM.levelColor = Color3.fromRGB(120, 190, 255)
SM.avatarImage = ""

-- [field] = { [instance] = true }. Populated by auto-detection and by binds.
SM.targets = {
    username = {},
    hp = {},
    vipTitle = {},
    exp = {},
    level = {},
    coins = {},
    gems = {},
    border = {},
    avatar = {},
}

SM.manualBinds = {}
SM.originals = {}
SM.pendingBindField = nil
SM.lastDiscoveryTime = -math.huge
SM.discoveryInterval = 1.5
SM.applyInterval = 0.12
SM.lastApplyTime = -math.huge

-- Text that identifies a developer/telemetry overlay worth hiding on stream.
-- A container is hidden when at least two of these appear beneath it, so a
-- single label that merely mentions "position" is not enough to trigger it.
SM.debugOverlayPhrases = {
    "world position", "data loaded", "place version", "server age",
    "server region", "job id", "jobid", "instance id", "session id",
    "client version", "build id", "user id", "userid", "account age",
}

SM.hiddenElements = {}
SM.autoHideOverlays = true

-- [instance] = { connections } watching Text/Image so an override is reasserted
-- the instant the game writes, rather than on the next poll.
SM.signalConnections = {}
-- Set by the panel so a config-driven enable can update the toggle's own label.
SM.syncToggleWidget = nil
-- Re-entrancy guard: writing Text refires the same signal we are handling.
SM.applyingTo = {}

-- Forward declaration; defined once applyBorderColorTo is available.
local applyToTarget

SM.fieldKeywords = {
    hp = { "hp", "health", "hitpoint" },
    exp = { "exp", "xp", "experience" },
    level = { "level", "lvl", "rank" },
    vipTitle = { "vip", "title", "tag", "premium", "badge" },
    coins = { "coin", "gold", "cash", "money", "currency" },
    gems = { "gem", "diamond", "crystal", "robux" },
}

local function parseHexColor(text)
    if type(text) ~= "string" then return nil end
    local hex = text:gsub("#", ""):gsub("%s", "")
    if #hex ~= 6 then return nil end
    local r = tonumber(hex:sub(1, 2), 16)
    local g = tonumber(hex:sub(3, 4), 16)
    local b = tonumber(hex:sub(5, 6), 16)
    if not r or not g or not b then return nil end
    return Color3.fromRGB(r, g, b)
end

local function toHexString(color)
    return string.format("%02X%02X%02X",
        math.floor(color.R * 255 + 0.5),
        math.floor(color.G * 255 + 0.5),
        math.floor(color.B * 255 + 0.5))
end

-- Roblox cannot upload an image from a script. Accepts an asset id, an
-- rbxassetid:// string, or a roblox.com URL, and normalises to rbxassetid://.
local function normalizeImageId(text)
    if type(text) ~= "string" then return "" end
    local digits = text:match("(%d+)")
    if not digits then return "" end
    return "rbxassetid://" .. digits
end

local function isTextObject(obj)
    return obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox")
end

local function isImageObject(obj)
    return obj:IsA("ImageLabel") or obj:IsA("ImageButton")
end

local function rememberStreamerOriginal(obj)
    if SM.originals[obj] then return end
    local snapshot = {}
    if isTextObject(obj) then
        snapshot.Text = obj.Text
        snapshot.TextColor3 = obj.TextColor3
    end
    if isImageObject(obj) then
        snapshot.Image = obj.Image
        snapshot.ImageColor3 = obj.ImageColor3
    end
    if obj:IsA("UIStroke") then
        snapshot.StrokeColor = obj.Color
    end
    if obj:IsA("GuiObject") then
        snapshot.BorderColor3 = obj.BorderColor3
        snapshot.BackgroundColor3 = obj.BackgroundColor3
    end
    SM.originals[obj] = snapshot
end

-- Registers a target and starts watching it. The watch is what removes the
-- flicker: polling every 0.12s meant the game's own write (on an EXP tick, a
-- damage number, a stat refresh) was visible until the next poll came round.
-- Reacting to the property signal puts the correction in the same frame.
local function registerStreamerTarget(field, obj)
    local set = SM.targets[field]
    if not set or set[obj] then return end

    set[obj] = true
    rememberStreamerOriginal(obj)

    if not SM.signalConnections[obj] then
        local connections = {}

        local function watch(property)
            local ok, signal = pcall(function()
                return obj:GetPropertyChangedSignal(property)
            end)
            if ok and signal then
                table.insert(connections, signal:Connect(function()
                    if SM.enabled then
                        applyToTarget(field, obj)
                    end
                end))
            end
        end

        if isTextObject(obj) then watch("Text") end
        if isImageObject(obj) then watch("Image") end

        SM.signalConnections[obj] = connections
    end

    if SM.enabled then
        applyToTarget(field, obj)
    end
end

local function unwatchStreamerTarget(obj)
    local connections = SM.signalConnections[obj]
    if not connections then return end
    for _, connection in ipairs(connections) do
        connection:Disconnect()
    end
    SM.signalConnections[obj] = nil
end

local function unwatchAllStreamerTargets()
    for obj in pairs(SM.signalConnections) do
        unwatchStreamerTarget(obj)
    end
    table.clear(SM.signalConnections)
    table.clear(SM.applyingTo)
end

-- Most nametags draw their "border" as a gold Frame sitting behind a slightly
-- smaller inner Frame, not as a UIStroke. Detecting by class alone therefore
-- missed it entirely, so trim is identified by colour instead: warm golds and
-- yellows, where red and green are both strong and clearly above blue.
-- The green HP fill, the cream badge backing and dark panels all fail this.
local function isTrimColor(color)
    return color.R >= 0.55
        and color.G >= 0.38
        and color.B <= 0.55
        and color.R >= color.G
        and (color.G - color.B) >= 0.15
end

-- Collects the trim pieces of any nametag billboard in `container`. Scoped to
-- billboards so a gold element elsewhere in the HUD is never repainted.
local function collectNametagTrim(container, character)
    for _, obj in ipairs(container:GetDescendants()) do
        local billboard = obj:FindFirstAncestorOfClass("BillboardGui")
        if billboard then
            -- Billboards living outside the character only count when they are
            -- adorned to it, so other players' nametags are left alone.
            local ownsIt = character and (billboard:IsDescendantOf(character)
                or (billboard.Adornee and billboard.Adornee:IsDescendantOf(character)))

            if ownsIt then
                local isTrim = false

                if obj:IsA("UIStroke") then
                    isTrim = true
                elseif obj:IsA("GuiObject") and not isTextObject(obj) then
                    if obj.BackgroundTransparency < 0.95 and isTrimColor(obj.BackgroundColor3) then
                        isTrim = true
                    elseif isImageObject(obj) and obj.ImageTransparency < 0.95 and isTrimColor(obj.ImageColor3) then
                        isTrim = true
                    end
                end

                if isTrim then
                    registerStreamerTarget("border", obj)
                end
            end
        end
    end
end

-- The gold trim on the nametag can be a UIStroke, a bordered frame, or a plain
-- coloured backing frame depending on how the game built it, so all three are
-- handled and the most specific one wins.
local function applyBorderColorTo(obj, color)
    if obj:IsA("UIStroke") then
        obj.Color = color
        return
    end

    -- Ordered so the property that is actually drawing the trim wins. A visible
    -- background is what the colour detection matched on, so it takes priority
    -- over a stroke the element may also happen to carry.
    if isImageObject(obj) and obj.Image ~= "" and obj.ImageTransparency < 0.95 then
        obj.ImageColor3 = color
        return
    end

    if obj:IsA("GuiObject") then
        if obj.BackgroundTransparency < 0.95 then
            obj.BackgroundColor3 = color
            return
        end
        if obj.BorderSizePixel > 0 then
            obj.BorderColor3 = color
            return
        end
        local stroke = obj:FindFirstChildOfClass("UIStroke")
        if stroke then
            rememberStreamerOriginal(stroke)
            stroke.Color = color
        end
    end
end

local function nameMatchesKeywords(obj, keywords)
    local node = obj
    local depth = 0
    while node and depth < 4 do
        local lowered = string.lower(node.Name)
        for _, word in ipairs(keywords) do
            if string.find(lowered, word, 1, true) then
                return true
            end
        end
        node = node.Parent
        depth = depth + 1
    end
    return false
end

-- Targets are sticky: only destroyed instances are dropped. Detection is by
-- content, so a label already showing the fake name no longer matches the real
-- one; forgetting it would let the real name flash back for up to one discovery
-- interval whenever the game rewrote that label.
local function pruneDeadStreamerTargets()
    for obj in pairs(SM.hiddenElements) do
        if not obj.Parent then
            SM.hiddenElements[obj] = nil
        end
    end

    for _, set in pairs(SM.targets) do
        for obj in pairs(set) do
            if not obj.Parent then
                set[obj] = nil
                SM.originals[obj] = nil
                SM.manualBinds[obj] = nil
                unwatchStreamerTarget(obj)
            end
        end
    end
end

local function scanContainerForStreamerTargets(container, realName, realDisplay, realUserId)
    for _, obj in ipairs(container:GetDescendants()) do
        local isOurs = RT.scriptGui and obj:IsDescendantOf(RT.scriptGui)
        if not isOurs then
            if isTextObject(obj) then
                local text = obj.Text
                if text ~= "" then
                    if string.find(text, realName, 1, true)
                        or (realDisplay ~= realName and string.find(text, realDisplay, 1, true)) then
                        registerStreamerTarget("username", obj)
                    end

                    for field, keywords in pairs(SM.fieldKeywords) do
                        if SM.fields[field] ~= "" and nameMatchesKeywords(obj, keywords) then
                            registerStreamerTarget(field, obj)
                        end
                    end
                end
            elseif isImageObject(obj) then
                if string.find(obj.Image, realUserId, 1, true) then
                    registerStreamerTarget("avatar", obj)
                end
            end
        end
    end
end

local function hideStreamerElement(obj, reason)
    if not obj or SM.hiddenElements[obj] then return end
    if RT.scriptGui and obj:IsDescendantOf(RT.scriptGui) then return end
    if not obj:IsA("GuiObject") then return end

    SM.hiddenElements[obj] = obj.Visible
    obj.Visible = false
    heavyDebug("Streamer", string.format("Hid '%s' (%s) - %s", obj.Name, obj.ClassName, reason))
end

local function restoreHiddenElements()
    for obj, wasVisible in pairs(SM.hiddenElements) do
        if obj.Parent then
            pcall(function() obj.Visible = wasVisible end)
        end
    end
    table.clear(SM.hiddenElements)
end

-- Finds telemetry overlays like the World Position / Data Loaded / Place Version
-- / Server Age readout and hides the container holding them, rather than each
-- row, so no empty frame is left behind.
local function hideDebugOverlays(playerGui)
    if not SM.autoHideOverlays then return end

    local matchCounts = {}

    for _, obj in ipairs(playerGui:GetDescendants()) do
        local isOurs = RT.scriptGui and obj:IsDescendantOf(RT.scriptGui)
        if not isOurs and isTextObject(obj) and obj.Text ~= "" then
            local lowered = string.lower(obj.Text)
            local matched = false
            for _, phrase in ipairs(SM.debugOverlayPhrases) do
                if string.find(lowered, phrase, 1, true) then
                    matched = true
                    break
                end
            end

            if matched then
                -- Credit the label and its nearby ancestors, so the shared
                -- container accumulates the highest count.
                local node = obj
                local depth = 0
                while node and depth < 5 and not node:IsA("ScreenGui") do
                    matchCounts[node] = (matchCounts[node] or 0) + 1
                    node = node.Parent
                    depth = depth + 1
                end
            end
        end
    end

    for node, count in pairs(matchCounts) do
        if count >= 2 and node:IsA("GuiObject") then
            -- Hide the outermost container that still holds every match, so the
            -- whole readout goes at once.
            local best = node
            local walker = node.Parent
            local depth = 0
            while walker and depth < 4 and walker:IsA("GuiObject") do
                if (matchCounts[walker] or 0) == count then
                    best = walker
                end
                walker = walker.Parent
                depth = depth + 1
            end
            hideStreamerElement(best, string.format("telemetry overlay, %d matches", count))
        end
    end
end

-- Applies one field to one element. Split out of the bulk apply so a property
-- signal can correct a single label immediately without sweeping everything.
applyToTarget = function(field, obj)
    if not obj.Parent or SM.applyingTo[obj] then return end
    SM.applyingTo[obj] = true

    if field == "border" then
        applyBorderColorTo(obj, SM.borderColor)

    elseif field == "avatar" then
        if SM.avatarImage ~= "" and isImageObject(obj) and obj.Image ~= SM.avatarImage then
            obj.Image = SM.avatarImage
        end

    elseif field == "username" then
        if isTextObject(obj) then
            local realName = LocalPlayer.Name
            local realDisplay = LocalPlayer.DisplayName or realName
            local fakeName = SM.fields.username ~= "" and SM.fields.username or "Streamer"
            local current = obj.Text
            local replaced = string.gsub(current, realName, fakeName)
            if realDisplay ~= realName then
                replaced = string.gsub(replaced, realDisplay, fakeName)
            end
            if replaced ~= current then
                obj.Text = replaced
            end
        end

    else
        local value = SM.fields[field]
        if value and value ~= "" and isTextObject(obj) then
            if obj.Text ~= value then
                obj.Text = value
            end
            if field == "vipTitle" then
                obj.TextColor3 = SM.vipColor
            elseif field == "level" then
                obj.TextColor3 = SM.levelColor
            end
        end
    end

    SM.applyingTo[obj] = nil
end

-- Full path from the DataModel, so a reported element can be located exactly.
local function describeInstancePath(obj)
    local segments = {}
    local node = obj
    local depth = 0
    while node and node ~= game and depth < 12 do
        table.insert(segments, 1, node.Name)
        node = node.Parent
        depth = depth + 1
    end
    return table.concat(segments, ".")
end

-- Prints every GUI element that looks identity-bearing, with its path, class and
-- current text. Run it, copy the console, and the matching rules can be widened
-- to whatever this particular game actually uses.
local function dumpStreamerCandidates()
    local realName = LocalPlayer.Name
    local realDisplay = LocalPlayer.DisplayName or realName
    local realUserId = tostring(LocalPlayer.UserId)

    print(string.rep("=", 78))
    print(string.format("  STREAMER GUI DUMP  |  v%s  |  account: %s (display '%s', id %s)",
        SCRIPT_VERSION, realName, realDisplay, realUserId))
    print(string.rep("=", 78))

    local total = 0

    local function dumpContainer(container, containerLabel)
        if not container then return end
        print(string.format("--- %s ---", containerLabel))
        local found = 0

        for _, obj in ipairs(container:GetDescendants()) do
            local isOurs = RT.scriptGui and obj:IsDescendantOf(RT.scriptGui)
            if not isOurs then
                local reasons = nil

                local function note(tag)
                    reasons = reasons or {}
                    table.insert(reasons, tag)
                end

                if isTextObject(obj) and obj.Text ~= "" then
                    local text = obj.Text
                    local lowered = string.lower(text)

                    if string.find(text, realName, 1, true) then note("USERNAME") end
                    if realDisplay ~= realName and string.find(text, realDisplay, 1, true) then note("DISPLAYNAME") end
                    -- Value shapes visible in the HUD: "5.30M/5.30M", "129.84M/3.69B",
                    -- "5307855/5307855", a bare level number, and VIP/title text.
                    if string.match(text, "^%s*[%d%.,]+[KMBT]?%s*/%s*[%d%.,]+[KMBT]?%s*$") then note("PAIR_VALUE") end
                    if string.match(text, "^%s*%d+%s*$") then note("BARE_NUMBER") end
                    if string.find(lowered, "hp", 1, true) or string.find(lowered, "health", 1, true) then note("HP_TEXT") end
                    if string.find(lowered, "exp", 1, true) then note("EXP_TEXT") end
                    if string.find(lowered, "vip", 1, true) then note("VIP_TEXT") end
                    if string.match(text, "^%s*%b()%s*$") then note("PARENTHESISED") end

                    for field, keywords in pairs(SM.fieldKeywords) do
                        if nameMatchesKeywords(obj, keywords) then note("NAMEHINT:" .. field) end
                    end

                    if reasons then
                        found = found + 1
                        total = total + 1
                        print(string.format("[%s] %s", table.concat(reasons, ","), obj.ClassName))
                        print(string.format("    text : %q", text))
                        print(string.format("    path : %s", describeInstancePath(obj)))
                    end
                elseif isImageObject(obj) and obj.Image ~= "" then
                    if string.find(obj.Image, realUserId, 1, true) then
                        found = found + 1
                        total = total + 1
                        print(string.format("[AVATAR] %s", obj.ClassName))
                        print(string.format("    image: %s", obj.Image))
                        print(string.format("    path : %s", describeInstancePath(obj)))
                    end
                end
            end
        end

        if found == 0 then
            print("  (nothing matched here)")
        end
    end

    dumpContainer(LocalPlayer:FindFirstChildOfClass("PlayerGui"), "PlayerGui")
    dumpContainer(LocalPlayer.Character, "Character (nametag billboards)")

    print("--- nametag trim currently detected ---")
    local trimCount = 0
    for obj in pairs(SM.targets.border) do
        if obj.Parent then
            trimCount = trimCount + 1
            local swatch
            if obj:IsA("UIStroke") then
                swatch = "stroke " .. toHexString(obj.Color)
            elseif isImageObject(obj) and obj.Image ~= "" and obj.ImageTransparency < 0.95 then
                swatch = "image tint " .. toHexString(obj.ImageColor3)
            elseif obj:IsA("GuiObject") and obj.BackgroundTransparency < 0.95 then
                swatch = "background " .. toHexString(obj.BackgroundColor3)
            else
                swatch = "border " .. toHexString(obj.BorderColor3)
            end
            print(string.format("[TRIM] %s (%s)", obj.ClassName, swatch))
            print(string.format("    path : %s", describeInstancePath(obj)))
        end
    end
    if trimCount == 0 then
        print("  (none detected - use the trim row's bind button and click the border)")
    end

    print(string.rep("=", 78))
    print(string.format("  %d candidate elements, %d trim pieces.", total, trimCount))
    print(string.rep("=", 78))

    return total
end

local function discoverStreamerTargets()
    local realName = LocalPlayer.Name
    local realDisplay = LocalPlayer.DisplayName or realName
    local realUserId = tostring(LocalPlayer.UserId)

    pruneDeadStreamerTargets()

    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if playerGui then
        scanContainerForStreamerTargets(playerGui, realName, realDisplay, realUserId)
        hideDebugOverlays(playerGui)
    end

    -- Character descendants carry the overhead nametag billboards.
    local character = LocalPlayer.Character
    if character then
        scanContainerForStreamerTargets(character, realName, realDisplay, realUserId)

        collectNametagTrim(character, character)
    end

    -- Some games parent the nametag billboard into PlayerGui and adorn it to the
    -- head instead of nesting it under the character, so check there too. The
    -- adornee test keeps other players' nametags out of it.
    if playerGui and character then
        collectNametagTrim(playerGui, character)
    end

    for obj, field in pairs(SM.manualBinds) do
        if obj.Parent then
            registerStreamerTarget(field, obj)
        else
            SM.manualBinds[obj] = nil
        end
    end
end

local function applyStreamerOverlay()
    for field, set in pairs(SM.targets) do
        for obj in pairs(set) do
            applyToTarget(field, obj)
        end
    end
end

local function restoreStreamerOriginals()
    for obj, snapshot in pairs(SM.originals) do
        if obj.Parent then
            pcall(function()
                if snapshot.Text ~= nil and isTextObject(obj) then
                    obj.Text = snapshot.Text
                    obj.TextColor3 = snapshot.TextColor3
                end
                if snapshot.Image ~= nil and isImageObject(obj) then
                    obj.Image = snapshot.Image
                    obj.ImageColor3 = snapshot.ImageColor3
                end
                if snapshot.StrokeColor ~= nil and obj:IsA("UIStroke") then
                    obj.Color = snapshot.StrokeColor
                end
                if snapshot.BorderColor3 ~= nil and obj:IsA("GuiObject") then
                    obj.BorderColor3 = snapshot.BorderColor3
                    obj.BackgroundColor3 = snapshot.BackgroundColor3
                end
            end)
        end
    end
    table.clear(SM.originals)
end

local function setStreamerStatus(text)
    if SM.statusLabel then
        SM.statusLabel.Text = text
    end
end

local function countStreamerTargets()
    local total = 0
    for _, set in pairs(SM.targets) do
        for _ in pairs(set) do
            total = total + 1
        end
    end
    return total
end

local function setStreamerEnabled(enabled)
    SM.enabled = enabled

    if SM.connection then
        SM.connection:Disconnect()
        SM.connection = nil
    end

    if not enabled then
        unwatchAllStreamerTargets()
        restoreStreamerOriginals()
        restoreHiddenElements()
        for field in pairs(SM.targets) do
            SM.targets[field] = {}
        end
        setStreamerStatus("Off. Original display restored.")
        heavyDebug("Streamer", "Streamer mode disabled, originals restored.")
        return
    end

    discoverStreamerTargets()
    applyStreamerOverlay()
    SM.lastDiscoveryTime = os.clock()
    setStreamerStatus(string.format("On. %d elements masked.", countStreamerTargets()))
    heavyDebug("Streamer", string.format("Streamer mode enabled. %d elements masked.", countStreamerTargets()))

    -- The game rewrites its own labels, so the overlay has to be reasserted.
    -- Both clocks are deliberately slow; this is cosmetic and must not cost frames.
    SM.connection = RunService.Heartbeat:Connect(function()
        if RT.destroyed or not SM.enabled then return end
        local clock = os.clock()

        if clock - SM.lastApplyTime >= SM.applyInterval then
            SM.lastApplyTime = clock
            local ok, err = xpcall(applyStreamerOverlay, debug.traceback)
            if not ok then
                heavyDebugThrottled("streamer_apply_err", 2.0, "FATAL", "Streamer overlay threw:\n" .. tostring(err))
            end
        end

        if clock - SM.lastDiscoveryTime >= SM.discoveryInterval then
            SM.lastDiscoveryTime = clock
            local ok, err = xpcall(discoverStreamerTargets, debug.traceback)
            if not ok then
                heavyDebugThrottled("streamer_scan_err", 2.0, "FATAL", "Streamer discovery threw:\n" .. tostring(err))
            else
                setStreamerStatus(string.format("On. %d elements masked.", countStreamerTargets()))
            end
        end
    end)
end

local function refreshStreamerOverlay()
    if not SM.enabled then return end
    discoverStreamerTargets()
    applyStreamerOverlay()
    setStreamerStatus(string.format("On. %d elements masked.", countStreamerTargets()))
end

-- Bind mode: the next GUI click assigns that element to the pending field, for
-- anything the keyword matching did not find.
local function setPendingBindField(field)
    SM.pendingBindField = field

    if SM.bindConnection then
        SM.bindConnection:Disconnect()
        SM.bindConnection = nil
    end

    if not field then return end

    setStreamerStatus("Bind armed: click the " .. field .. " element on screen.")

    SM.bindConnection = UserInputService.InputBegan:Connect(function(input, processed)
        if not SM.pendingBindField then return end
        if input.UserInputType ~= Enum.UserInputType.MouseButton1
            and input.UserInputType ~= Enum.UserInputType.Touch then
            return
        end

        local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
        if not playerGui then return end

        local inset = game:GetService("GuiService"):GetGuiInset()
        local position = UserInputService:GetMouseLocation()
        local candidates = playerGui:GetGuiObjectsAtPosition(position.X - inset.X, position.Y - inset.Y)

        for _, obj in ipairs(candidates) do
            local isOurs = RT.scriptGui and obj:IsDescendantOf(RT.scriptGui)
            if not isOurs and SM.pendingBindField == "hide" and obj:IsA("GuiObject") then
                hideStreamerElement(obj, "hidden by hand")
                setStreamerStatus(string.format("Hid '%s'.", obj.Name))
                setPendingBindField(nil)
                return
            end

            if not isOurs and SM.pendingBindField == "border" and obj:IsA("GuiObject") then
                SM.manualBinds[obj] = "border"
                registerStreamerTarget("border", obj)
                setStreamerStatus(string.format("Bound '%s' as nametag trim.", obj.Name))
                setPendingBindField(nil)
                applyStreamerOverlay()
                return
            end

            if not isOurs and (isTextObject(obj) or isImageObject(obj)) then
                local field = SM.pendingBindField
                SM.manualBinds[obj] = field
                registerStreamerTarget(field, obj)
                heavyDebug("Streamer", string.format("Bound '%s' (%s) to field '%s'.",
                    obj.Name, obj.ClassName, field))
                setStreamerStatus(string.format("Bound '%s' to %s.", obj.Name, field))
                setPendingBindField(nil)
                applyStreamerOverlay()
                return
            end
        end

        setStreamerStatus("Nothing bindable under the cursor. Try again.")
    end)
end

S.describeInstancePath = describeInstancePath
S.dumpStreamerCandidates = dumpStreamerCandidates
S.normalizeImageId = normalizeImageId
S.parseHexColor = parseHexColor
S.refreshStreamerOverlay = refreshStreamerOverlay
S.restoreHiddenElements = restoreHiddenElements
S.setPendingBindField = setPendingBindField
S.setStreamerEnabled = setStreamerEnabled
S.setStreamerStatus = setStreamerStatus
S.toHexString = toHexString
end
