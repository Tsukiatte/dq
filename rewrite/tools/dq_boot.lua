-- dq_boot.lua: load the bot and its telemetry once the place has settled. Run by autoexec/dq_autoboot.lua in
-- Dungeon Quest places (lobby and dungeons alike); the bot's own place rule turns farming on only in a dungeon.
task.spawn(function()
    task.wait(7)
    if _G.DungeonAutofarmState then return end   -- already running here (a manual load beat us to it)
    -- The staged build, and the last verified one behind it: a bundle that will not compile must never leave the
    -- run with no bot at all.
    local f = loadstring(readfile("dq_rewrite.lua"))
    if not f then
        warn("[DQ boot] dq_rewrite.lua does not compile; falling back to dq_rewrite_prev.lua")
        f = loadstring(readfile("dq_rewrite_prev.lua"))
    end
    if f then pcall(f) end
    task.wait(2)
    if not workspace:FindFirstChild("dungeon") then return end   -- the lobby has nothing to record
    pcall(function() loadstring(readfile("dq_recorder6.lua"))() end)
    pcall(function() loadstring(readfile("dq_probe_hits.lua"))() end)
    pcall(function() loadstring(readfile("dq_probe_odin.lua"))() end)
    pcall(function() loadstring(readfile("dq_deaths_tool.lua"))() end)
    pcall(function() loadstring(readfile("dq_probe_cc.lua"))() end)
    pcall(function() loadstring(readfile("dq_probe_nodes.lua"))() end)
end)
