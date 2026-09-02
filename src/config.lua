-- config.lua - JSON config persistence through the executor's file API.
-- Module contract: receives the shared table S. Everything this module needs from
-- earlier modules is pulled into locals below; everything later modules need is
-- assigned onto S at the bottom. Load order is fixed by main.lua / build.py.
return function(S)
local RT = S.RT
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
local MAP_LABELS = S.MAP_LABELS
local refreshLowDetail = S.refreshLowDetail

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
    RT.mapData[RT.currentMap] = { waypath = waypath, keep = keep }
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

    local keepCount = 0
    for _ in pairs(LD.keepNames) do keepCount = keepCount + 1 end
    heavyDebug("Map", string.format("%s (%s): %d waypoint(s), %d kept part name(s).",
        code, MAP_LABELS[code] or code, #NAV.waypath, keepCount))
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
        return true
    end

    heavyDebug("Config", "Save failed: " .. tostring(err))
    return false, tostring(err)
end

-- Returns applied, message. Widgets are refreshed by the caller, which owns them.
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
    end

    local visuals = data.visuals
    if type(visuals) == "table" then
        if visuals.renderPath ~= nil then RT.renderPathEnabled = visuals.renderPath == true end
        if visuals.renderHazards ~= nil then RT.renderHazardsEnabled = visuals.renderHazards == true end
        if visuals.renderHitbox ~= nil then RT.renderHitboxEnabled = visuals.renderHitbox == true end
        if visuals.showWalls ~= nil then CFG.showWalls = visuals.showWalls == true end
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

    if type(data.attackBook) == "table" then
        table.clear(HZ.attackBook)
        for _, record in ipairs(data.attackBook) do
            if type(record) == "table" and type(record.name) == "string"
                and type(record.partName) == "string" and tonumber(record.sx) then
                table.insert(HZ.attackBook, record)
            end
        end
        S.invalidateAttackBook()
        if #HZ.attackBook > 0 then
            heavyDebug("Config", string.format("Restored %d attack book entries.", #HZ.attackBook))
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

    applyMapFromStore(RT.currentMap)
    local mapCount = 0
    for _ in pairs(RT.mapData) do mapCount = mapCount + 1 end
    heavyDebug("Config", string.format("Loaded map %s of %d stored.", RT.currentMap, mapCount))

    heavyDebug("Config", "Loaded from " .. CONFIG_FILE)
    return true, streamer and streamer.enabled == true
end

local function syncStreamerToggleWidget()
    if SM.syncToggleWidget then
        pcall(SM.syncToggleWidget)
    end
end

S.loadConfig = loadConfig
S.saveConfig = saveConfig
S.setCurrentMap = setCurrentMap
S.syncCurrentMapToStore = syncCurrentMapToStore
S.syncStreamerToggleWidget = syncStreamerToggleWidget
end
