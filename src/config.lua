-- config.lua - JSON config persistence through the executor's file API.
-- Module contract: receives the shared table S. Everything this module needs from
-- earlier modules is pulled into locals below; everything later modules need is
-- assigned onto S at the bottom. Load order is fixed by main.lua / build.py.
return function(S)
local RT = S.RT
local Workspace = S.Workspace
local SM = S.SM
local describeInstancePath = S.describeInstancePath
local HZ = S.HZ
local NAV = S.NAV
local CFG = S.CFG
local toHexString = S.toHexString
local heavyDebug = S.heavyDebug
local parseHexColor = S.parseHexColor
local renderPathMarkers = S.renderPathMarkers
local SCRIPT_VERSION = S.SCRIPT_VERSION

--[[ ===========================================================================
    CONFIG PERSISTENCE

    Uses the executor's writefile/readfile, which are not part of Roblox itself,
    so every call is guarded and the script stays functional without them.

    Manual binds are stored as instance paths rather than references, and
    re-resolved by name on load. Paths are the fragile part: a game that renames
    or restructures its GUI between sessions will simply fail to resolve those
    entries, which is why a failed resolve is skipped quietly rather than
    treated as an error.
=========================================================================== ]]

local LD = S.LD
local MC = S.MC
local MAP_LABELS = S.MAP_LABELS
local refreshLowDetail = S.refreshLowDetail
local serializeMacros = S.serializeMacros
local serializeZones = S.serializeZones
local loadZones = S.loadZones
local loadMacros = S.loadMacros

local CONFIG_FILE = "DungeonAutofarm_config.json"

local function hasFileAccess()
    return type(writefile) == "function"
        and type(readfile) == "function"
        and type(isfile) == "function"
end

local function resolveInstancePath(path)
    local node = game
    for segment in string.gmatch(path, "[^%.]+") do
        if node == game and segment == "game" then
            -- Leading "game" is part of the recorded path; skip it.
        else
            local nextNode = node:FindFirstChild(segment)
            if not nextNode then return nil end
            node = nextNode
        end
    end
    return node ~= game and node or nil
end

-- =========================================================================
-- PER-MAP STORAGE (2.4.0)
--
-- The waypoint path and the low-detail keep list are properties of a dungeon,
-- not of the session, so they are stored per map code. RT.mapData holds every
-- map the config knows about; the live NAV.waypath / LD.keepNames are just the
-- selected map's entry checked out for editing. Switching map checks the
-- current one back in and the new one out.
-- =========================================================================

local function syncCurrentMapToStore()
    local waypath = {}
    for _, pos in ipairs(NAV.waypath) do
        table.insert(waypath, { x = pos.X, y = pos.Y, z = pos.Z })
    end
    local keep = {}
    for name in pairs(LD.keepNames) do
        table.insert(keep, name)
    end
    -- The Attack Book and the hand-drawn zones are properties of a dungeon
     -- too: what hurts you in Ghastly Harbor is not what hurts you in the
     -- Underworld, and a book shared across all fourteen would be a book full
     -- of entries that never match.
    local book = {}
    for _, record in ipairs(HZ.attackBook) do table.insert(book, record) end
    RT.attackData[RT.currentMap] = book
    RT.zoneData[RT.currentMap] = serializeZones()

    RT.mapData[RT.currentMap] = { waypath = waypath, keep = keep }
    -- Macros are bulky and live in their own file; the map store only carries
    -- the light data.
    RT.macroData[RT.currentMap] = serializeMacros()
end

-- =========================================================================
-- The macro file. Separate from the config because a single ten-minute
-- recording is thousands of samples, and keeping it apart means the config
-- stays small and hand-editable while the macros stay easy to copy between
-- machines or hand to someone else.
-- =========================================================================
local function saveMacroFile()
    if not hasFileAccess() then return false, "no file access in this executor" end
    local ok, err = pcall(function()
        local payload = { version = SCRIPT_VERSION, maps = RT.macroData }
        writefile(CFG.macroFile, game:GetService("HttpService"):JSONEncode(payload))
    end)
    if ok then
        local total = 0
        for _, list in pairs(RT.macroData) do total = total + #list end
        heavyDebug("Config", string.format("Saved %d macro(s) to %s.", total, CFG.macroFile))
        return true
    end
    heavyDebug("Config", "Macro save failed: " .. tostring(err))
    return false, tostring(err)
end

local function loadMacroFile()
    if not hasFileAccess() then return false end
    local exists = false
    pcall(function() exists = isfile(CFG.macroFile) end)
    if not exists then return false end

    local data
    local ok = pcall(function()
        data = game:GetService("HttpService"):JSONDecode(readfile(CFG.macroFile))
    end)
    if not ok or type(data) ~= "table" or type(data.maps) ~= "table" then
        heavyDebug("Config", "Macro file unreadable; starting with none.")
        return false
    end

    table.clear(RT.macroData)
    local total = 0
    for code, list in pairs(data.maps) do
        if MAP_LABELS[code] and type(list) == "table" then
            RT.macroData[code] = list
            total = total + #list
        end
    end
    heavyDebug("Config", string.format("Loaded %d macro(s) across %d map(s) from %s.",
        total, (function() local c = 0 for _ in pairs(RT.macroData) do c = c + 1 end return c end)(),
        CFG.macroFile))
    return true
end

-- Checks a map's stored data out into the live tables. Does NOT save.
local function applyMapFromStore(code)
    local entry = RT.mapData[code] or {}

    table.clear(NAV.waypath)
    if type(entry.waypath) == "table" then
        for _, p in ipairs(entry.waypath) do
            if type(p) == "table" and tonumber(p.x) and tonumber(p.y) and tonumber(p.z) then
                table.insert(NAV.waypath, Vector3.new(p.x, p.y, p.z))
            end
        end
    end
    NAV.pathIndex = 1
    renderPathMarkers()
    if S.refreshPathPanel then S.refreshPathPanel() end

    table.clear(LD.keepNames)
    if type(entry.keep) == "table" then
        for _, name in ipairs(entry.keep) do
            if type(name) == "string" then LD.keepNames[name] = true end
        end
    end
    refreshLowDetail()
    if S.refreshMapPanel then S.refreshMapPanel() end

    local macroCount = loadMacros(RT.macroData[code])

    table.clear(HZ.attackBook)
    for _, record in ipairs(RT.attackData[code] or {}) do
        table.insert(HZ.attackBook, record)
    end
    S.invalidateAttackBook()
    local zoneCount = loadZones(RT.zoneData[code])
    S.clearPrecastZones()

    local keepCount = 0
    for _ in pairs(LD.keepNames) do keepCount = keepCount + 1 end
    heavyDebug("Map", string.format(
        "%s (%s): %d waypoint(s), %d macro(s), %d attack(s), %d zone(s), %d kept name(s).",
        code, MAP_LABELS[code] or code, #NAV.waypath, macroCount,
        #HZ.attackBook, zoneCount, keepCount))
end

-- The map picker. Checks the current map in, then the requested one out.
local function setCurrentMap(code)
    if not MAP_LABELS[code] or code == RT.currentMap then
        if code == RT.currentMap then applyMapFromStore(code) end
        return
    end
    syncCurrentMapToStore()
    RT.currentMap = code
    applyMapFromStore(code)
end

local function buildConfigTable()
    local binds = {}
    for obj, field in pairs(SM.manualBinds) do
        if obj.Parent then
            table.insert(binds, { path = describeInstancePath(obj), field = field })
        end
    end

    local learned = {}
    for name in pairs(HZ.learnedNames) do
        table.insert(learned, name)
    end

    -- Names learned as our own ability effects (2.2.0), so they are recognised
    -- on sight next session without waiting for the timing signal again.
    local ownNames = {}
    for name in pairs(HZ.ownNames) do
        table.insert(ownNames, name)
    end

    -- Per-map storage (2.4.0). The live waypath and keep list belong to whichever
    -- map is selected; everything already loaded for the other maps is carried
    -- through untouched, so saving one dungeon never drops the rest.
    syncCurrentMapToStore()
    local maps = {}
    for code, entry in pairs(RT.mapData) do
        maps[code] = entry
    end

    return {
        version = SCRIPT_VERSION,
        combat = {
            attackRange = CFG.attackRange,
            safeDistance = CFG.safeDistance,
            wallPadding = CFG.wallPadding,
            damageBrickDetectionRange = CFG.damageBrickDetectionRange,
            autoQ = RT.autoQEnabled,
            autoE = RT.autoEEnabled,
            faceTarget = CFG.faceTarget,
            followPath = CFG.followPath,
            loopPath = CFG.loopPath,
            waypointClearRadius = CFG.waypointClearRadius,
            macroMode = MC.mode,
            cloneCount = CFG.cloneCount,
            cloneRings = CFG.cloneRings,
            cloneRadius = CFG.cloneRadius,
            cloneInnerRadius = CFG.cloneInnerRadius,
            cloneAutoRings = CFG.cloneAutoRings,
            cloneRingSpacing = CFG.cloneRingSpacing,
            pathfindingEnabled = CFG.pathfindingEnabled,
            usePrecast = CFG.usePrecast,
            showPrecast = CFG.showPrecast,
            safeZoneEnabled = CFG.safeZoneEnabled,
            autoDetectMap = CFG.autoDetectMap,
            dodgeEnabled = CFG.dodgeEnabled,
            cloneSafetyMargin = CFG.cloneSafetyMargin,
            cloneCommitTime = CFG.cloneCommitTime,
            cloneManual = CFG.cloneManual,
            cloneEnemyRadius = CFG.cloneEnemyRadius,
            cloneEnemySoftRadius = CFG.cloneEnemySoftRadius,
            cloneSafeDwell = CFG.cloneSafeDwell,
            cloneKeepDistance = CFG.cloneKeepDistance,
            threatWeight = CFG.threatWeight,
            threatLethal = CFG.threatLethal,
            threatHorizon = CFG.threatHorizon,
            threatFalloff = CFG.threatFalloff,
            showThreatGradient = CFG.showThreatGradient,
            dodgeProjectiles = CFG.dodgeProjectiles,
            cloneGridSpacing = CFG.cloneGridSpacing,
            cloneMaxCells = CFG.cloneMaxCells,
            cloneDangerCost = CFG.cloneDangerCost,
            cloneDepthBonus = CFG.cloneDepthBonus,
            showClonePrisms = CFG.showClonePrisms,
            cloneDiscScale = CFG.cloneDiscScale,
            showClones = CFG.showClones,
            macroLoop = CFG.macroLoop,
            macroShowRoute = CFG.macroShowRoute,
            macroRecordBind = MC.recordBind.Name,
            abilityRadiusEnabled = CFG.abilityRadiusEnabled,
            abilityRadius = CFG.abilityRadius,
            showAbilityRadius = CFG.showAbilityRadius,
            recoveryEnabled = CFG.recoveryEnabled,
        },
        visuals = {
            renderPath = RT.renderPathEnabled,
            renderHazards = RT.renderHazardsEnabled,
            renderHitbox = RT.renderHitboxEnabled,
            showWalls = CFG.showWalls,
            panelAutofarm = CFG.panelAutofarm,
            panelRoutes = CFG.panelRoutes,
            panelAccount = CFG.panelAccount,
            panelConfigs = CFG.panelConfigs,
            panelAttacks = CFG.panelAttacks,
            pinnedWindows = (function()
                local names = {}
                for name in pairs(RT.pinnedWindows) do table.insert(names, name) end
                return names
            end)(),
            guiBlur = CFG.guiBlur,
            guiDim = CFG.guiDim,
            menuKey = CFG.menuKey,
            debugLevel = RT.debugLevel,
        },
        streamer = {
            enabled = SM.enabled,
            fields = SM.fields,
            vipColor = toHexString(SM.vipColor),
            levelColor = toHexString(SM.levelColor),
            borderColor = toHexString(SM.borderColor),
            avatarImage = SM.avatarImage,
            autoHideOverlays = SM.autoHideOverlays,
            binds = binds,
        },
        learnedTelegraphNames = learned,
        ownAttackNames = ownNames,
        -- Plain data by construction (partSignature + name/hits/flags), so it
        -- round-trips through JSON as-is.
        attackBook = HZ.attackBook,
        currentMap = RT.currentMap,
        maps = maps,
        attacksByMap = RT.attackData,
        zonesByMap = RT.zoneData,
    }
end

local function saveConfig()
    if not hasFileAccess() then
        heavyDebug("Config", "Executor exposes no writefile; cannot save.")
        return false, "no file access in this executor"
    end

    local ok, err = pcall(function()
        local json = game:GetService("HttpService"):JSONEncode(buildConfigTable())
        writefile(CONFIG_FILE, json)
    end)

    if ok then
        heavyDebug("Config", "Saved to " .. CONFIG_FILE)
        saveMacroFile()
        return true
    end

    heavyDebug("Config", "Save failed: " .. tostring(err))
    return false, tostring(err)
end

-- Returns applied, message. Widgets are refreshed by the caller, which owns them.
-- The apply half of a config load, split out (2.10.0) so a stored profile can
-- be applied without a file read behind it: loadConfig reads the file and hands
-- the decoded table here, and the Configs panel hands it one it already had.
-- Returns whether Streamer Mode should come up enabled.
local function applyConfigData(data)
    local combat = data.combat
    if type(combat) == "table" then
        CFG.attackRange = tonumber(combat.attackRange) or CFG.attackRange
        CFG.safeDistance = tonumber(combat.safeDistance) or CFG.safeDistance
        CFG.wallPadding = tonumber(combat.wallPadding) or CFG.wallPadding
        CFG.damageBrickDetectionRange = tonumber(combat.damageBrickDetectionRange) or CFG.damageBrickDetectionRange
        RT.autoQEnabled = combat.autoQ == true
        RT.autoEEnabled = combat.autoE == true
        if combat.faceTarget ~= nil then
            CFG.faceTarget = combat.faceTarget == true
        end
        if combat.followPath ~= nil then
            CFG.followPath = combat.followPath == true
        end
        if combat.loopPath ~= nil then
            CFG.loopPath = combat.loopPath == true
        end
        CFG.waypointClearRadius = tonumber(combat.waypointClearRadius) or CFG.waypointClearRadius
        if combat.abilityRadiusEnabled ~= nil then
            CFG.abilityRadiusEnabled = combat.abilityRadiusEnabled == true
        end
        CFG.abilityRadius = tonumber(combat.abilityRadius) or CFG.abilityRadius
        if combat.showAbilityRadius ~= nil then
            CFG.showAbilityRadius = combat.showAbilityRadius == true
        end
        if combat.recoveryEnabled ~= nil then
            CFG.recoveryEnabled = combat.recoveryEnabled == true
        end
        if combat.macroMode == "macro" or combat.macroMode == "legacy"
            or combat.macroMode == "clone" then
            MC.mode = combat.macroMode
        end
        CFG.cloneCount = tonumber(combat.cloneCount) or CFG.cloneCount
        CFG.cloneRings = tonumber(combat.cloneRings) or CFG.cloneRings
        CFG.cloneRadius = tonumber(combat.cloneRadius) or CFG.cloneRadius
        CFG.cloneInnerRadius = tonumber(combat.cloneInnerRadius) or CFG.cloneInnerRadius
        CFG.cloneRingSpacing = tonumber(combat.cloneRingSpacing) or CFG.cloneRingSpacing
        if combat.cloneAutoRings ~= nil then CFG.cloneAutoRings = combat.cloneAutoRings == true end
        if combat.pathfindingEnabled ~= nil then CFG.pathfindingEnabled = combat.pathfindingEnabled == true end
        if combat.usePrecast ~= nil then CFG.usePrecast = combat.usePrecast == true end
        if combat.showPrecast ~= nil then CFG.showPrecast = combat.showPrecast == true end
        if combat.safeZoneEnabled ~= nil then CFG.safeZoneEnabled = combat.safeZoneEnabled == true end
        if combat.autoDetectMap ~= nil then CFG.autoDetectMap = combat.autoDetectMap == true end
        if combat.dodgeEnabled ~= nil then CFG.dodgeEnabled = combat.dodgeEnabled == true end
        CFG.cloneSafetyMargin = tonumber(combat.cloneSafetyMargin) or CFG.cloneSafetyMargin
        CFG.cloneCommitTime = tonumber(combat.cloneCommitTime) or CFG.cloneCommitTime
        if combat.showClones ~= nil then CFG.showClones = combat.showClones == true end
        if combat.cloneManual ~= nil then CFG.cloneManual = combat.cloneManual == true end
        CFG.cloneEnemyRadius = tonumber(combat.cloneEnemyRadius) or CFG.cloneEnemyRadius
        CFG.cloneEnemySoftRadius = tonumber(combat.cloneEnemySoftRadius) or CFG.cloneEnemySoftRadius
        CFG.cloneSafeDwell = tonumber(combat.cloneSafeDwell) or CFG.cloneSafeDwell
        if combat.cloneKeepDistance ~= nil then CFG.cloneKeepDistance = combat.cloneKeepDistance == true end
        CFG.threatWeight = tonumber(combat.threatWeight) or CFG.threatWeight
        CFG.threatLethal = tonumber(combat.threatLethal) or CFG.threatLethal
        CFG.threatHorizon = tonumber(combat.threatHorizon) or CFG.threatHorizon
        CFG.threatFalloff = tonumber(combat.threatFalloff) or CFG.threatFalloff
        if combat.showThreatGradient ~= nil then CFG.showThreatGradient = combat.showThreatGradient == true end
        if combat.dodgeProjectiles ~= nil then CFG.dodgeProjectiles = combat.dodgeProjectiles == true end
        CFG.cloneGridSpacing = tonumber(combat.cloneGridSpacing) or CFG.cloneGridSpacing
        CFG.cloneMaxCells = tonumber(combat.cloneMaxCells) or CFG.cloneMaxCells
        CFG.cloneDangerCost = tonumber(combat.cloneDangerCost) or CFG.cloneDangerCost
        CFG.cloneDepthBonus = tonumber(combat.cloneDepthBonus) or CFG.cloneDepthBonus
        if combat.showClonePrisms ~= nil then CFG.showClonePrisms = combat.showClonePrisms == true end
        CFG.cloneDiscScale = tonumber(combat.cloneDiscScale) or CFG.cloneDiscScale
        if combat.macroLoop ~= nil then CFG.macroLoop = combat.macroLoop == true end
        if combat.macroShowRoute ~= nil then CFG.macroShowRoute = combat.macroShowRoute == true end
        if type(combat.macroRecordBind) == "string" then
            -- Enum.KeyCode[name] throws on a bad name rather than returning nil.
            local ok, keyCode = pcall(function() return Enum.KeyCode[combat.macroRecordBind] end)
            if ok and keyCode then MC.recordBind = keyCode end
        end
    end

    local visuals = data.visuals
    if type(visuals) == "table" then
        if visuals.renderPath ~= nil then RT.renderPathEnabled = visuals.renderPath == true end
        if visuals.renderHazards ~= nil then RT.renderHazardsEnabled = visuals.renderHazards == true end
        if visuals.renderHitbox ~= nil then RT.renderHitboxEnabled = visuals.renderHitbox == true end
        if visuals.showWalls ~= nil then CFG.showWalls = visuals.showWalls == true end
        if visuals.panelAutofarm ~= nil then CFG.panelAutofarm = visuals.panelAutofarm == true end
        if visuals.panelRoutes ~= nil then CFG.panelRoutes = visuals.panelRoutes == true end
        if visuals.panelAccount ~= nil then CFG.panelAccount = visuals.panelAccount == true end
        if visuals.panelConfigs ~= nil then CFG.panelConfigs = visuals.panelConfigs == true end
        if visuals.panelAttacks ~= nil then CFG.panelAttacks = visuals.panelAttacks == true end
        if type(visuals.pinnedWindows) == "table" then
            table.clear(RT.pinnedWindows)
            for _, name in ipairs(visuals.pinnedWindows) do
                if type(name) == "string" then RT.pinnedWindows[name] = true end
            end
        end
        CFG.guiBlur = tonumber(visuals.guiBlur) or CFG.guiBlur
        CFG.guiDim = tonumber(visuals.guiDim) or CFG.guiDim
        -- Only a name Enum.KeyCode actually has: a typo here would lock the
        -- interface behind a key that does not exist.
        if type(visuals.menuKey) == "string" then
            local ok, code = pcall(function() return Enum.KeyCode[visuals.menuKey] end)
            if ok and code then CFG.menuKey = visuals.menuKey end
        end
        RT.debugLevel = tonumber(visuals.debugLevel) or RT.debugLevel
    end
    -- Enemy attacks are always highlighted since 2.3.0; an older config that
    -- saved the toggle off must not switch them off.
    RT.renderHazardsEnabled = true

    local streamer = data.streamer
    if type(streamer) == "table" then
        if type(streamer.fields) == "table" then
            for key in pairs(SM.fields) do
                if type(streamer.fields[key]) == "string" then
                    SM.fields[key] = streamer.fields[key]
                end
            end
        end
        SM.vipColor = parseHexColor(streamer.vipColor) or SM.vipColor
        SM.levelColor = parseHexColor(streamer.levelColor) or SM.levelColor
        SM.borderColor = parseHexColor(streamer.borderColor) or SM.borderColor
        if type(streamer.avatarImage) == "string" then
            SM.avatarImage = streamer.avatarImage
        end
        if streamer.autoHideOverlays ~= nil then
            SM.autoHideOverlays = streamer.autoHideOverlays == true
        end

        if type(streamer.binds) == "table" then
            local resolved, missed = 0, 0
            for _, entry in ipairs(streamer.binds) do
                if type(entry) == "table" and type(entry.path) == "string" and SM.targets[entry.field] then
                    local obj = resolveInstancePath(entry.path)
                    if obj then
                        SM.manualBinds[obj] = entry.field
                        resolved = resolved + 1
                    else
                        missed = missed + 1
                    end
                end
            end
            if resolved > 0 or missed > 0 then
                heavyDebug("Config", string.format(
                    "Restored %d manual binds, %d could not be resolved.", resolved, missed))
            end
        end
    end

    if type(data.learnedTelegraphNames) == "table" then
        for _, name in ipairs(data.learnedTelegraphNames) do
            if type(name) == "string" then
                HZ.learnedNames[name] = true
            end
        end
    end

    table.clear(RT.attackData)
    if type(data.attacksByMap) == "table" then
        for code, list in pairs(data.attacksByMap) do
            if MAP_LABELS[code] and type(list) == "table" then RT.attackData[code] = list end
        end
    end
    table.clear(RT.zoneData)
    if type(data.zonesByMap) == "table" then
        for code, list in pairs(data.zonesByMap) do
            if MAP_LABELS[code] and type(list) == "table" then RT.zoneData[code] = list end
        end
    end

    if type(data.attackBook) == "table" then
        table.clear(HZ.attackBook)
        for _, record in ipairs(data.attackBook) do
            if type(record) == "table" and type(record.name) == "string"
                and type(record.partName) == "string" and tonumber(record.sx) then
                table.insert(HZ.attackBook, record)
            end
        end
        S.invalidateAttackBook()
        -- Pre-2.11 configs kept ONE book for every dungeon. Adopt it into
        -- whichever map the config names rather than dropping it, and let the
        -- user move entries about from there.
        if #HZ.attackBook > 0 and not RT.attackData[RT.currentMap] then
            local adopted = {}
            for _, record in ipairs(HZ.attackBook) do table.insert(adopted, record) end
            RT.attackData[RT.currentMap] = adopted
            heavyDebug("Config", string.format(
                "Adopted %d pre-2.11 attack book entries into map %s.", #adopted, RT.currentMap))
        end
    end

    if type(data.ownAttackNames) == "table" then
        local restored = 0
        for _, name in ipairs(data.ownAttackNames) do
            if type(name) == "string" and not HZ.learnedNames[name] then
                HZ.ownNames[name] = true
                restored = restored + 1
            end
        end
        if restored > 0 then
            heavyDebug("Config", string.format("Restored %d own-attack effect names.", restored))
        end
    end

    -- Per-map data (2.4.0), and the pre-2.4 single top-level waypath, which is
    -- adopted into whichever map the config names so an existing setup is not
    -- lost by upgrading.
    table.clear(RT.mapData)
    if type(data.maps) == "table" then
        for code, entry in pairs(data.maps) do
            if MAP_LABELS[code] and type(entry) == "table" then
                RT.mapData[code] = {
                    waypath = type(entry.waypath) == "table" and entry.waypath or {},
                    keep = type(entry.keep) == "table" and entry.keep or {},
                }
                -- Pre-2.7 configs kept the macros inline; adopt them into the
                -- macro store so nothing recorded before the split is lost.
                if type(entry.macros) == "table" and #entry.macros > 0
                    and not RT.macroData[code] then
                    RT.macroData[code] = entry.macros
                end
            end
        end
    end

    if type(data.currentMap) == "string" and MAP_LABELS[data.currentMap] then
        RT.currentMap = data.currentMap
    end

    if type(data.waypath) == "table" and not RT.mapData[RT.currentMap] then
        RT.mapData[RT.currentMap] = { waypath = data.waypath, keep = {} }
        heavyDebug("Config", string.format(
            "Adopted the pre-2.4 waypoint path into map %s.", RT.currentMap))
    end

    loadMacroFile()
    applyMapFromStore(RT.currentMap)
    local mapCount = 0
    for _ in pairs(RT.mapData) do mapCount = mapCount + 1 end
    heavyDebug("Config", string.format("Loaded map %s of %d stored.", RT.currentMap, mapCount))

    return streamer and streamer.enabled == true
end

-- =========================================================================
-- NAMED CONFIGS (2.10.0)
--
-- A saved config is a full snapshot of buildConfigTable() under a name, in its
-- own file. The working config is still DungeonAutofarm_config.json and still
-- autoloads; these are the ones you keep deliberately - a setup per dungeon, a
-- careful one and a reckless one, whatever you like.
-- =========================================================================

local function saveConfigStore()
    if not hasFileAccess() then return false, "no file access in this executor" end
    local ok, err = pcall(function()
        local payload = { version = SCRIPT_VERSION, configs = RT.configs }
        writefile(CFG.configFile, game:GetService("HttpService"):JSONEncode(payload))
    end)
    if ok then
        heavyDebug("Config", string.format("Wrote %d saved config(s) to %s.", #RT.configs, CFG.configFile))
        return true
    end
    heavyDebug("Config", "Config store save failed: " .. tostring(err))
    return false, tostring(err)
end

local function loadConfigStore()
    if not hasFileAccess() then return false end
    local exists = false
    pcall(function() exists = isfile(CFG.configFile) end)
    if not exists then return false end

    local data
    local ok = pcall(function()
        data = game:GetService("HttpService"):JSONDecode(readfile(CFG.configFile))
    end)
    if not ok or type(data) ~= "table" or type(data.configs) ~= "table" then
        heavyDebug("Config", "Config store unreadable; starting with none.")
        return false
    end

    table.clear(RT.configs)
    for _, entry in ipairs(data.configs) do
        if type(entry) == "table" and type(entry.name) == "string" and type(entry.data) == "table" then
            table.insert(RT.configs, {
                name = entry.name,
                savedAt = tonumber(entry.savedAt) or 0,
                data = entry.data,
            })
        end
    end
    heavyDebug("Config", string.format("Loaded %d saved config(s).", #RT.configs))
    return true
end

-- Saving under a name that already exists overwrites it, which is what you
-- want when you are tuning one setup rather than accumulating near-duplicates.
local function saveNamedConfig(name)
    name = tostring(name):gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then return false, "give it a name" end

    local snapshot = { name = name, savedAt = os.time(), data = buildConfigTable() }
    for i, entry in ipairs(RT.configs) do
        if entry.name == name then
            RT.configs[i] = snapshot
            saveConfigStore()
            heavyDebug("Config", string.format("Overwrote saved config '%s'.", name))
            if S.refreshConfigPanel then S.refreshConfigPanel() end
            return true
        end
    end
    table.insert(RT.configs, snapshot)
    saveConfigStore()
    heavyDebug("Config", string.format("Saved config '%s'.", name))
    if S.refreshConfigPanel then S.refreshConfigPanel() end
    return true
end

local function loadNamedConfig(index)
    local entry = RT.configs[index]
    if not entry then return false end
    local wantsStreamer = applyConfigData(entry.data)
    heavyDebug("Config", string.format("Loaded saved config '%s'.", entry.name))
    if S.refreshAllWidgets then S.refreshAllWidgets() end
    if S.refreshPathPanel then S.refreshPathPanel() end
    if S.refreshMacroPanel then S.refreshMacroPanel() end
    if S.refreshMapPanel then S.refreshMapPanel() end
    if S.refreshAttackBookPanel then S.refreshAttackBookPanel() end
    return true, wantsStreamer
end

local function deleteNamedConfig(index)
    local entry = table.remove(RT.configs, index)
    if not entry then return false end
    saveConfigStore()
    heavyDebug("Config", string.format("Deleted saved config '%s'.", entry.name))
    if S.refreshConfigPanel then S.refreshConfigPanel() end
    return true
end

local function renameNamedConfig(index, name)
    local entry = RT.configs[index]
    if not entry then return false end
    name = tostring(name):gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then return false end
    entry.name = name
    saveConfigStore()
    if S.refreshConfigPanel then S.refreshConfigPanel() end
    return true
end

local function loadConfig()
    if not hasFileAccess() then
        return false, "no file access in this executor"
    end

    local exists = false
    pcall(function() exists = isfile(CONFIG_FILE) end)
    if not exists then
        return false, "no saved config yet"
    end

    local data
    local ok, err = pcall(function()
        data = game:GetService("HttpService"):JSONDecode(readfile(CONFIG_FILE))
    end)

    if not ok or type(data) ~= "table" then
        heavyDebug("Config", "Load failed: " .. tostring(err))
        return false, "config file unreadable"
    end

    local wantsStreamer = applyConfigData(data)
    loadConfigStore()
    heavyDebug("Config", "Loaded from " .. CONFIG_FILE)
    return true, wantsStreamer
end

local function syncStreamerToggleWidget()
    if SM.syncToggleWidget then
        pcall(SM.syncToggleWidget)
    end
end

S.loadConfig = loadConfig
S.saveConfig = saveConfig
-- The game publishes the dungeon it has loaded. Following it means the
-- waypoints, macros, attack book and drawn zones for that dungeon are already
-- in place by the time you can move, instead of waiting to be picked.
local MAP_BY_GAME_NAME = {
    ["desert temple"] = "DT", ["winter outpost"] = "WO", ["pirate island"] = "PI",
    ["king's castle"] = "KC", ["the underworld"] = "TU", ["samurai palace"] = "SP",
    ["the canals"] = "TC", ["ghastly harbor"] = "GH", ["steampunk sewers"] = "SS",
    ["orbital outpost"] = "OO", ["volcanic chambers"] = "VC", ["aquatic temple"] = "AT",
    ["enchanted forest"] = "EF", ["northern lands"] = "NL",
}

local function applyDetectedMap(raw)
    if not CFG.autoDetectMap then return end
    local code = MAP_BY_GAME_NAME[string.lower(tostring(raw or ""))]
    if not code or code == RT.currentMap then return end
    setCurrentMap(code)
    heavyDebug("Map", string.format(
        "The game says we are in %s; switched to %s and loaded its data.", raw, code))
    if S.refreshAllWidgets then S.refreshAllWidgets() end
    if S.refreshPathPanel then S.refreshPathPanel() end
    if S.refreshMacroPanel then S.refreshMacroPanel() end
    if S.refreshMapPanel then S.refreshMapPanel() end
    if S.refreshAttackBookPanel then S.refreshAttackBookPanel() end
    if S.refreshZonePanel then S.refreshZonePanel() end
end

local function watchDungeonName()
    local value = Workspace:FindFirstChild("dungeonName")
    if not value or not value:IsA("StringValue") then return false end
    applyDetectedMap(value.Value)
    table.insert(RT.indexConnections, value.Changed:Connect(applyDetectedMap))
    heavyDebug("Map", "Following Workspace.dungeonName; the map picker now switches itself.")
    return true
end

S.setCurrentMap = setCurrentMap
S.watchDungeonName = watchDungeonName
S.applyDetectedMap = applyDetectedMap
S.saveNamedConfig = saveNamedConfig
S.loadNamedConfig = loadNamedConfig
S.deleteNamedConfig = deleteNamedConfig
S.renameNamedConfig = renameNamedConfig
S.loadConfigStore = loadConfigStore
S.saveMacroFile = saveMacroFile
S.loadMacroFile = loadMacroFile
S.syncCurrentMapToStore = syncCurrentMapToStore
S.syncStreamerToggleWidget = syncStreamerToggleWidget
end
