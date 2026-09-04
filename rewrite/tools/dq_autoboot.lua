-- dq_autoboot.lua (autoexec): in Dungeon Quest places, load the bot and its telemetry after the game loads.
-- Delete this file to stop the bot loading by itself.
if not game:IsLoaded() then game.Loaded:Wait() end
local KNOWN = { [77649408247578] = true, [85776757589518] = true }   -- lobby, Northern Lands
local isDQ = KNOWN[game.PlaceId] == true
if not isDQ then
    local ok, info = pcall(function() return game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId) end)
    isDQ = ok and type(info) == "table" and type(info.Name) == "string" and string.lower(info.Name):find("dungeon quest", 1, true) ~= nil
end
if isDQ then pcall(function() loadstring(readfile("dq_boot.lua"))() end) end
