-- main.lua - DEVELOPMENT loader. Fetches src/*.lua one file at a time from GitHub
-- and wires them through one shared table S, in the fixed load order below.
--
-- For normal use load the built bundle instead - one request, always a consistent
-- set of modules (GitHub's raw CDN caches each file separately for a few minutes,
-- so per-file loading right after a push can mix old and new modules):
--
--   loadstring(game:HttpGet("https://raw.githubusercontent.com/Tsukiatte/dq/main/DungeonAutofarm.lua"))()
--
-- The bundle is produced by `python tools/build.py`, which also runs the checker.
-- Set getgenv().DQ_BASE to point this loader somewhere else (a fork, a branch).

local BASE = (type(getgenv) == "function" and getgenv().DQ_BASE)
    or "https://raw.githubusercontent.com/Tsukiatte/dq/main/src/"

-- Definition order is load-bearing: a module may only import from modules above it.
-- Keep in sync with tools/modules.py.
local ORDER = { "core", "gamedata", "uikit", "hazards", "precast", "bossevents", "nav", "mover", "dodge", "path", "streamer", "config", "ui", "main" }

local S = {}
for _, name in ipairs(ORDER) do
    -- The query string defeats the raw CDN cache so a fresh push loads immediately.
    local url = BASE .. name .. ".lua?t=" .. tostring(os.time())
    local ok, source = pcall(function() return game:HttpGet(url) end)
    if not ok or type(source) ~= "string" or #source == 0 then
        error(("[DungeonAutofarm] could not fetch %s.lua: %s"):format(name, tostring(source)))
    end
    local chunk, err = loadstring(source, "=" .. name)
    if not chunk then
        error(("[DungeonAutofarm] %s.lua failed to compile: %s"):format(name, tostring(err)))
    end
    local module = chunk()
    if type(module) ~= "function" then
        error(("[DungeonAutofarm] %s.lua did not return a module function"):format(name))
    end
    module(S)
end
