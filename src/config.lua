-- config.lua - JSON config persistence through the executor's file API, the
-- per-map store (waypoints, keep list, attack book, zones), named configs,
-- the map picker and the mode switch.
return function(S)
local CFG = S.CFG
local RT = S.RT
local SM = S.SM
local HZ = S.HZ
local NAV = S.NAV
local LD = S.LD
local ZN = S.ZN
local Workspace = S.Workspace
local heavyDebug = S.heavyDebug
local toHexString = S.toHexString
local parseHexColor = S.parseHexColor
local describeInstancePath = S.describeInstancePath
local renderPathMarkers = S.renderPathMarkers
local refreshLowDetail = S.refreshLowDetail
local serializeZones = S.serializeZones
local loadZones = S.loadZones
local invalidateAttackBook = S.invalidateAttackBook
local MAP_LABELS = S.MAP_LABELS
local SCRIPT_VERSION = S.SCRIPT_VERSION

local CONFIG_FILE = "DungeonAutofarm_config.json"
local HttpService = game:GetService("HttpService")

local function hasFileAccess()
    return type(writefile) == "function" and type(readfile) == "function" and type(isfile) == "function"
end
local function resolveInstancePath(path)
    local node = game
    for segment in string.gmatch(path, "[^%.]+") do
        if not (node == game and segment == "game") then
            local nextNode = node:FindFirstChild(segment)
            if not nextNode then return nil end
            node = nextNode
        end
    end
    return node ~= game and node or nil
end

-- ------------------------------------------------------------------ mode
local function setMode(mode)
    if mode ~= "legacy" and mode ~= "clone" then mode = "clone" end
    RT.mode = mode
    if S.setDodgeActive then S.setDodgeActive(mode == "clone") end
end

-- ------------------------------------------------------------------ per-map store
local function syncCurrentMapToStore()
    local waypath = {}
    for _, pos in ipairs(NAV.waypath) do waypath[#waypath + 1] = { x = pos.X, y = pos.Y, z = pos.Z } end
    local keep = {}
    for name in pairs(LD.keepNames) do keep[#keep + 1] = name end
    local book = {}
    for _, r in ipairs(HZ.attackBook) do book[#book + 1] = { name = r.name, enabled = r.enabled ~= false, hits = r.hits or 0, damage = r.damage or 0 } end
    RT.attackData[RT.currentMap] = book
    RT.zoneData[RT.currentMap] = serializeZones()
    RT.mapData[RT.currentMap] = { waypath = waypath, keep = keep }
end
local function applyMapFromStore(code)
    local entry = RT.mapData[code] or {}
    NAV.waypath = {}
    if type(entry.waypath) == "table" then
        for _, p in ipairs(entry.waypath) do
            if type(p) == "table" and tonumber(p.x) and tonumber(p.y) and tonumber(p.z) then
                NAV.waypath[#NAV.waypath + 1] = Vector3.new(p.x, p.y, p.z)
            end
        end
    end
    NAV.pathIndex = 1
    renderPathMarkers()
    if S.refreshPathPanel then S.refreshPathPanel() end
    LD.keepNames = {}
    if type(entry.keep) == "table" then
        for _, name in ipairs(entry.keep) do if type(name) == "string" then LD.keepNames[name] = true end end
    end
    refreshLowDetail()
    HZ.attackBook = {}
    for _, r in ipairs(RT.attackData[code] or {}) do
        if type(r) == "table" and type(r.name) == "string" then
            HZ.attackBook[#HZ.attackBook + 1] = { name = r.name, enabled = r.enabled ~= false, hits = tonumber(r.hits) or 0, damage = tonumber(r.damage) or 0 }
        end
    end
    invalidateAttackBook()
    loadZones(RT.zoneData[code])
    if S.refreshMapPanel then S.refreshMapPanel() end
    if S.refreshAttackBookPanel then S.refreshAttackBookPanel() end
    heavyDebug("Map", string.format("%s (%s): %d waypoint(s), %d attack(s), %d zone(s).", code, MAP_LABELS[code] or code, #NAV.waypath, #HZ.attackBook, #ZN.defs))
end
local function setCurrentMap(code)
    if not MAP_LABELS[code] then return end
    if code ~= RT.currentMap then
        syncCurrentMapToStore()
        RT.currentMap = code
    end
    applyMapFromStore(code)
end

-- ------------------------------------------------------------------ the table
-- Every CFG value with a plain type is saved by name; colours as hex.
local function buildConfigTable()
    local cfg = {}
    for key, default in pairs(RT.cfgDefaults) do
        local v = CFG[key]
        local t = typeof(v)
        if t == "number" or t == "boolean" or t == "string" then cfg[key] = v
        elseif t == "Color3" then cfg[key] = toHexString(v) end
    end
    local pinned = {}
    for name in pairs(RT.pinnedWindows) do pinned[#pinned + 1] = name end
    local binds = {}
    for obj, field in pairs(SM.manualBinds or {}) do
        if obj.Parent then binds[#binds + 1] = { path = describeInstancePath(obj), field = field } end
    end
    local own, learned = {}, {}
    for name in pairs(HZ.ownNames) do own[#own + 1] = name end
    for name in pairs(HZ.learnedNames) do learned[#learned + 1] = name end
    syncCurrentMapToStore()
    return {
        version = SCRIPT_VERSION,
        cfg = cfg,
        rt = {
            mode = RT.mode, autoQ = RT.autoQEnabled, autoE = RT.autoEEnabled,
            renderPath = RT.renderPathEnabled, renderHazards = RT.renderHazardsEnabled, renderHitbox = RT.renderHitboxEnabled,
            debugLevel = RT.debugLevel, pinnedWindows = pinned,
        },
        streamer = {
            enabled = SM.enabled, fields = SM.fields,
            vipColor = toHexString(SM.vipColor), levelColor = toHexString(SM.levelColor), borderColor = toHexString(SM.borderColor),
            avatarImage = SM.avatarImage, autoHideOverlays = SM.autoHideOverlays, binds = binds,
        },
        ownAttackNames = own,
        learnedTelegraphNames = learned,
        currentMap = RT.currentMap,
        maps = RT.mapData,
        attacksByMap = RT.attackData,
        zonesByMap = RT.zoneData,
    }
end

local function applyConfigData(data)
    if type(data.cfg) == "table" then
        for key, default in pairs(RT.cfgDefaults) do
            local v = data.cfg[key]
            local t = typeof(default)
            if v ~= nil then
                if t == "number" and tonumber(v) then CFG[key] = tonumber(v)
                elseif t == "boolean" then CFG[key] = v == true
                elseif t == "string" and type(v) == "string" then CFG[key] = v
                elseif t == "Color3" and type(v) == "string" then CFG[key] = parseHexColor(v) or default end
            end
        end
    elseif type(data.combat) == "table" then
        -- A 4.x file: keep what still means the same thing.
        local c = data.combat
        RT.autoQEnabled = c.autoQ == true
        RT.autoEEnabled = c.autoE == true
        CFG.abilityRadius = tonumber(c.abilityRadius) or CFG.abilityRadius
        CFG.attackRange = tonumber(c.attackRange) or CFG.attackRange
        if c.followPath ~= nil then CFG.followPath = c.followPath == true end
        if c.loopPath ~= nil then CFG.loopPath = c.loopPath == true end
        CFG.waypointClearRadius = tonumber(c.waypointClearRadius) or CFG.waypointClearRadius
        if c.mode == "legacy" or c.mode == "clone" then RT.mode = c.mode end
        if type(data.visuals) == "table" then
            local v = data.visuals
            CFG.guiBlur = tonumber(v.guiBlur) or CFG.guiBlur
            CFG.guiDim = tonumber(v.guiDim) or CFG.guiDim
            if type(v.menuKey) == "string" then CFG.menuKey = v.menuKey end
        end
    end
    local rt = data.rt
    if type(rt) == "table" then
        if rt.mode == "legacy" or rt.mode == "clone" then RT.mode = rt.mode end
        if rt.autoQ ~= nil then RT.autoQEnabled = rt.autoQ == true end
        if rt.autoE ~= nil then RT.autoEEnabled = rt.autoE == true end
        if rt.renderPath ~= nil then RT.renderPathEnabled = rt.renderPath == true end
        if rt.renderHazards ~= nil then RT.renderHazardsEnabled = rt.renderHazards == true end
        if rt.renderHitbox ~= nil then RT.renderHitboxEnabled = rt.renderHitbox == true end
        RT.debugLevel = tonumber(rt.debugLevel) or RT.debugLevel
        if type(rt.pinnedWindows) == "table" then
            RT.pinnedWindows = {}
            for _, name in ipairs(rt.pinnedWindows) do if type(name) == "string" then RT.pinnedWindows[name] = true end end
        end
    end
    local ok = pcall(function() return Enum.KeyCode[CFG.menuKey] end)
    if not ok then CFG.menuKey = RT.cfgDefaults.menuKey end
    setMode(RT.mode)

    local streamer = data.streamer
    if type(streamer) == "table" then
        if type(streamer.fields) == "table" then
            for key in pairs(SM.fields) do
                if type(streamer.fields[key]) == "string" then SM.fields[key] = streamer.fields[key] end
            end
        end
        SM.vipColor = parseHexColor(streamer.vipColor) or SM.vipColor
        SM.levelColor = parseHexColor(streamer.levelColor) or SM.levelColor
        SM.borderColor = parseHexColor(streamer.borderColor) or SM.borderColor
        if type(streamer.avatarImage) == "string" then SM.avatarImage = streamer.avatarImage end
        if streamer.autoHideOverlays ~= nil then SM.autoHideOverlays = streamer.autoHideOverlays == true end
        if type(streamer.binds) == "table" and SM.manualBinds then
            for _, bind in ipairs(streamer.binds) do
                if type(bind) == "table" and type(bind.path) == "string" then
                    local obj = resolveInstancePath(bind.path)
                    if obj then SM.manualBinds[obj] = bind.field end
                end
            end
        end
    end
    HZ.ownNames = {}
    for _, name in ipairs(type(data.ownAttackNames) == "table" and data.ownAttackNames or {}) do
        if type(name) == "string" then HZ.ownNames[string.lower(name)] = true end
    end
    HZ.learnedNames = {}
    for _, name in ipairs(type(data.learnedTelegraphNames) == "table" and data.learnedTelegraphNames or {}) do
        if type(name) == "string" then HZ.learnedNames[string.lower(name)] = true end
    end
    if type(data.maps) == "table" then RT.mapData = data.maps end
    if type(data.attacksByMap) == "table" then RT.attackData = data.attacksByMap end
    if type(data.zonesByMap) == "table" then RT.zoneData = data.zonesByMap end
    if type(data.currentMap) == "string" and MAP_LABELS[data.currentMap] then RT.currentMap = data.currentMap end
    applyMapFromStore(RT.currentMap)
    return streamer ~= nil and streamer.enabled == true
end

-- ------------------------------------------------------------------ files
local function saveConfig()
    if not hasFileAccess() then return false, "no file access in this executor" end
    local ok, err = pcall(function() writefile(CONFIG_FILE, HttpService:JSONEncode(buildConfigTable())) end)
    if ok then heavyDebug("Config", "Saved to " .. CONFIG_FILE) return true end
    heavyDebug("Config", "Save failed: " .. tostring(err))
    return false, tostring(err)
end
local function saveConfigStore()
    if not hasFileAccess() then return false, "no file access in this executor" end
    local ok, err = pcall(function() writefile(CFG.configFile, HttpService:JSONEncode({ version = SCRIPT_VERSION, configs = RT.configs })) end)
    if ok then return true end
    return false, tostring(err)
end
local function loadConfigStore()
    if not hasFileAccess() then return false end
    local exists = false
    pcall(function() exists = isfile(CFG.configFile) end)
    if not exists then return false end
    local data
    local ok = pcall(function() data = HttpService:JSONDecode(readfile(CFG.configFile)) end)
    if not ok or type(data) ~= "table" or type(data.configs) ~= "table" then return false end
    RT.configs = {}
    for _, entry in ipairs(data.configs) do
        if type(entry) == "table" and type(entry.name) == "string" and type(entry.data) == "table" then
            RT.configs[#RT.configs + 1] = { name = entry.name, savedAt = tonumber(entry.savedAt) or 0, data = entry.data }
        end
    end
    return true
end
local function saveNamedConfig(name)
    name = tostring(name):gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then return false, "give it a name" end
    local snapshot = { name = name, savedAt = os.time(), data = buildConfigTable() }
    local replaced = false
    for i, entry in ipairs(RT.configs) do
        if entry.name == name then RT.configs[i] = snapshot replaced = true break end
    end
    if not replaced then RT.configs[#RT.configs + 1] = snapshot end
    saveConfigStore()
    if S.refreshConfigPanel then S.refreshConfigPanel() end
    return true
end
local function loadNamedConfig(index)
    local entry = RT.configs[index]
    if not entry then return false end
    local wantsStreamer = applyConfigData(entry.data)
    if S.refreshAllWidgets then S.refreshAllWidgets() end
    if S.refreshPathPanel then S.refreshPathPanel() end
    if S.refreshMapPanel then S.refreshMapPanel() end
    if S.refreshAttackBookPanel then S.refreshAttackBookPanel() end
    return true, wantsStreamer
end
local function deleteNamedConfig(index)
    if not table.remove(RT.configs, index) then return false end
    saveConfigStore()
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
    if not hasFileAccess() then return false, "no file access in this executor" end
    local exists = false
    pcall(function() exists = isfile(CONFIG_FILE) end)
    if not exists then return false, "no saved config yet" end
    local data
    local ok, err = pcall(function() data = HttpService:JSONDecode(readfile(CONFIG_FILE)) end)
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
    if SM.syncToggleWidget then pcall(SM.syncToggleWidget) end
end

-- ------------------------------------------------------------------ the game's map
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
    heavyDebug("Map", string.format("The game says %s; switched to %s.", tostring(raw), code))
    if S.refreshAllWidgets then S.refreshAllWidgets() end
    if S.refreshZonePanel then S.refreshZonePanel() end
end
local function watchDungeonName()
    local value = Workspace:FindFirstChild("dungeonName")
    if not value or not value:IsA("StringValue") then return false end
    applyDetectedMap(value.Value)
    table.insert(RT.indexConnections, value.Changed:Connect(applyDetectedMap))
    return true
end

-- One button's worth of tuning: the dodge section back to how it shipped.
local function applyRecommendedDodge()
    for key, value in pairs(RT.cfgDefaults) do
        if string.sub(key, 1, 5) == "dodge" or key == "moveMode" or key == "moveSpeed" or key == "hitAfter"
            or key == "damageBrickClearance" or key == "preemptiveClearance" then
            CFG[key] = value
        end
    end
    heavyDebug("Dodge", "Dodge settings reset to the recommended tuning.")
end

S.loadConfig = loadConfig
S.saveConfig = saveConfig
S.applyRecommendedDodge = applyRecommendedDodge
S.setCurrentMap = setCurrentMap
S.watchDungeonName = watchDungeonName
S.applyDetectedMap = applyDetectedMap
S.saveNamedConfig = saveNamedConfig
S.loadNamedConfig = loadNamedConfig
S.deleteNamedConfig = deleteNamedConfig
S.renameNamedConfig = renameNamedConfig
S.loadConfigStore = loadConfigStore
S.setMode = setMode
S.syncCurrentMapToStore = syncCurrentMapToStore
S.syncStreamerToggleWidget = syncStreamerToggleWidget
end
