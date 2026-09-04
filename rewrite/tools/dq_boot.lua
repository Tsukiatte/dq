-- dq_boot.lua: load the bot and its telemetry once the place has settled. Run by autoexec/dq_autoboot.lua in
-- Dungeon Quest places (lobby and dungeons alike); the bot's own place rule turns farming on only in a dungeon.
task.spawn(function()
    task.wait(7)
    if _G.DungeonAutofarmState then return end   -- already running here (a manual load beat us to it)
    pcall(function() loadstring(readfile("dq_rewrite.lua"))() end)
    task.wait(2)
    pcall(function() loadstring(readfile("dq_recorder6.lua"))() end)
    pcall(function() loadstring(readfile("dq_probe_hits.lua"))() end)
end)
