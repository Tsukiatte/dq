-- config.lua - Settings on disk: load at start, save when they change.
-- Module contract: receives the shared table S; imports from core.
return function(S)
local CFG = S.CFG
local RT = S.RT
local LocalPlayer = S.LocalPlayer
local heavyDebug = S.heavyDebug

local FILE = "DungeonAutofarm5_config.json"
local CF = { lastJson = nil, lastAt = -math.huge }

local function hasFiles()
    return type(writefile) == "function" and type(readfile) == "function" and type(isfile) == "function"
end

-- Everything in CFG that is a number, boolean or string, plus colours as hex.
local function snapshot()
    local out = {}
    for k, v in pairs(CFG) do
        local t = typeof(v)
        if t == "number" or t == "boolean" or t == "string" then out[k] = v
        elseif t == "Color3" then out[k] = "#" .. v:ToHex() end
    end
    out.__version = S.SCRIPT_VERSION
    out.__farmEnabled = RT.farmEnabled
    return out
end

local function apply(data)
    for k, v in pairs(data) do
        local cur = CFG[k]
        if cur ~= nil then
            local t = typeof(cur)
            if t == "Color3" and type(v) == "string" then
                local ok, c = pcall(Color3.fromHex, v)
                if ok then CFG[k] = c end
            elseif typeof(v) == t then
                CFG[k] = v
            end
        end
    end
end

local function saveConfig()
    if not hasFiles() then return false end
    local ok, json = pcall(function() return game:GetService("HttpService"):JSONEncode(snapshot()) end)
    if not ok then return false end
    local wrote = pcall(writefile, FILE, json)
    if wrote then CF.lastJson = json end
    return wrote
end

local function loadConfig()
    if not hasFiles() then return false end
    local exists = false
    pcall(function() exists = isfile(FILE) end)
    if not exists then return false end
    local ok, data = pcall(function() return game:GetService("HttpService"):JSONDecode(readfile(FILE)) end)
    if not ok or type(data) ~= "table" then return false end
    apply(data)
    heavyDebug("Config", "loaded " .. FILE)
    return true
end

local function autosaveTick(now)
    if now - CF.lastAt < CFG.autosaveInterval then return end
    CF.lastAt = now
    if not hasFiles() then return end
    local ok, json = pcall(function() return game:GetService("HttpService"):JSONEncode(snapshot()) end)
    if ok and json ~= CF.lastJson then
        if pcall(writefile, FILE, json) then CF.lastJson = json end
    end
end

local function startAutosave()
    if RT.autosaveStarted then return end
    RT.autosaveStarted = true
    pcall(function()
        LocalPlayer.OnTeleport:Connect(function(state)
            if state == Enum.TeleportState.Started or state == Enum.TeleportState.RequestedFromServer then saveConfig() end
        end)
    end)
end

S.loadConfig = loadConfig
S.saveConfig = saveConfig
S.autosaveTick = autosaveTick
S.startAutosave = startAutosave
end
