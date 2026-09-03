--[[
    studio_install.lua - Installs the autofarm into an open Roblox Studio place
    as a test harness. Run from the Studio command bar (or through the Studio
    MCP's execute_luau) in EDIT mode.

    What it builds:
      StarterPlayer.StarterPlayerScripts.DQHarness   (Folder)
          <one ModuleScript per src module, fetched from GitHub>
          Loader                                      (LocalScript, tools/studio_loader.lua)
          DQHarnessState / DQHarnessQuery             (made by the Loader at run time)
      ServerScriptService.DQBossSim                   (Script) - the fight simulator,
          installed separately by studio_bosssim.lua

    The Loader mirrors main.lua: one shared table S, modules called in ORDER.
    Executor-only globals are shimmed with locals prepended to every module, so
    the same source that runs in the executor runs here unchanged.

    Set HttpService.HttpEnabled first (this script does it) - Studio needs it to
    fetch from raw.githubusercontent.com. To test local edits instead of the
    pushed branch, set BASE to a local HTTP server serving src/.
]]

local BASE = "https://raw.githubusercontent.com/Tsukiatte/dq/main/src/"
local LOADER_URL = "https://raw.githubusercontent.com/Tsukiatte/dq/main/tools/studio_loader.lua"
local ORDER = { "core", "gamedata", "uikit", "reader", "field", "bosses", "mover", "dodge", "pursuit", "draw", "tools", "path", "streamer", "config", "ui", "main" }

local HttpService = game:GetService("HttpService")
local StarterPlayer = game:GetService("StarterPlayer")
pcall(function() HttpService.HttpEnabled = true end)

local scripts = StarterPlayer:FindFirstChild("StarterPlayerScripts")
local old = scripts:FindFirstChild("DQHarness")
if old then old:Destroy() end
local folder = Instance.new("Folder")
folder.Name = "DQHarness"
folder.Parent = scripts

-- Shims for executor-only globals. Each is a local so the module body's free
-- references bind to it. Anything the harness cannot provide is a no-op that
-- reports it once.
local SHIM = [[
local __reported = {}
local function __missing(name)
    return function(...)
        if not __reported[name] then
            __reported[name] = true
            warn("[DQHarness] executor function not available in Studio: " .. name)
        end
        return nil
    end
end
local getgenv = getgenv or function() return _G end
local writefile = writefile or __missing("writefile")
local readfile = readfile or __missing("readfile")
local isfile = isfile or function() return false end
local listfiles = listfiles or function() return {} end
local request = request or __missing("request")
local getrawmetatable = getrawmetatable or __missing("getrawmetatable")
local setreadonly = setreadonly or __missing("setreadonly")
local newcclosure = newcclosure or function(f) return f end
local getnamecallmethod = getnamecallmethod or __missing("getnamecallmethod")
local hookmetamethod = hookmetamethod or __missing("hookmetamethod")
local setclipboard = setclipboard or __missing("setclipboard")
]]

local fetched = 0
for _, name in ipairs(ORDER) do
    local url = BASE .. name .. ".lua?t=" .. tostring(os.time())
    local ok, source = pcall(function() return HttpService:GetAsync(url, true) end)
    if not ok or type(source) ~= "string" or #source == 0 then
        error(("[DQHarness] could not fetch %s.lua: %s"):format(name, tostring(source)))
    end
    local module = Instance.new("ModuleScript")
    module.Name = name
    module.Source = SHIM .. "\n" .. source
    module.Parent = folder
    fetched = fetched + 1
end

local loader = Instance.new("LocalScript")
loader.Name = "Loader"
-- The Loader's source lives in tools/studio_loader.lua so it can be edited
-- and versioned like everything else.
local loaderUrl = LOADER_URL .. "?t=" .. tostring(os.time())
local okL, loaderSource = pcall(function() return HttpService:GetAsync(loaderUrl, true) end)
if not okL or type(loaderSource) ~= "string" or #loaderSource == 0 then
    error("[DQHarness] could not fetch studio_loader.lua: " .. tostring(loaderSource))
end
loader.Source = loaderSource
loader.Parent = folder

print(("[DQHarness] installed %d modules + Loader under %s"):format(fetched, folder:GetFullName()))
