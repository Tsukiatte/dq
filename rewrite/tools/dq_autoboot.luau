--// dq_autoboot.luau - the only file that belongs in Potassium's autoexec folder (beside mcp.lua).
--//
--// It loads the CURRENT build from the workspace folder rather than carrying a copy of its own, so updating the bot
--// means dropping a new dq_rewrite.lua in there and nothing else. If that file will not compile it falls back to
--// dq_rewrite_prev.lua, which is only ever a build that has been loaded in game successfully, so a bad build can
--// never leave a run with no bot at all. Everything it does is announced in the console.
--//
--// Do NOT leave a second copy of the bundle in autoexec: loading the bot twice stops the first copy, so two loaders
--// racing means whichever finishes last wins and the other's window disappears.

local function say(...) print("[DQ boot]", ...) end

task.spawn(function()
    if _G.DQAutoBooted and _G.DQAutoBooted == game.JobId then return end   -- once per place, not once per injection
    _G.DQAutoBooted = game.JobId

    if not game:IsLoaded() then game.Loaded:Wait() end
    local Players = game:GetService("Players")
    while not Players.LocalPlayer do task.wait(0.1) end
    local lp = Players.LocalPlayer
    while not lp.Character do task.wait(0.2) end
    task.wait(4)   -- the map, the character's tools and the game's own GUI all want a moment

    if type(readfile) ~= "function" then say("this executor has no readfile; nothing can be loaded") return end
    local function tryLoad(name)
        local ok, src = pcall(readfile, name)
        if not ok or type(src) ~= "string" or #src < 1000 then return nil, name .. " is missing or empty" end
        local fn, err = loadstring(src)
        if not fn then return nil, name .. " will not compile: " .. tostring(err) end
        local ran, rerr = pcall(fn)
        if not ran then return nil, name .. " errored while starting: " .. tostring(rerr) end
        return true
    end

    if _G.DungeonAutofarmState then
        say("a copy is already running (" .. tostring(_G.DungeonAutofarmState.SCRIPT_VERSION) .. "); leaving it alone")
    else
        local ok, why = tryLoad("dq_rewrite.lua")
        if not ok then
            say(why)
            say("falling back to dq_rewrite_prev.lua")
            local ok2, why2 = tryLoad("dq_rewrite_prev.lua")
            if not ok2 then say(why2) say("NO BOT LOADED") return end
        end
        local S = _G.DungeonAutofarmState
        say("loaded " .. (S and tostring(S.SCRIPT_VERSION) or "?"))
    end

    -- The telemetry only belongs in a dungeon: the lobby has nothing to record.
    if not workspace:FindFirstChild("dungeon") then say("lobby: telemetry not started") return end
    local loaded = {}
    for _, name in ipairs({ "dq_recorder6.lua", "dq_deaths_tool.lua", "dq_probe_nodes.lua", "dq_probe_cc.lua", "dq_probe_hits.lua", "dq_probe_odin.lua" }) do
        local ok = tryLoad(name)
        loaded[#loaded + 1] = (ok and "" or "FAILED ") .. name
    end
    say("telemetry: " .. table.concat(loaded, ", "))
end)
