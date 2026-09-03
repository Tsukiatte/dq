-- recorder_dump.lua - Summary of the live recorder started by recorder_live.lua.
local HttpService = game:GetService("HttpService")
local R = _G.DQRec
if not R then return "recorder not running" end
local S = _G.DungeonAutofarmState
local lp = game.Players.LocalPlayer
local c = lp.Character
local hum = c and c:FindFirstChildOfClass("Humanoid")
local rt = c and c:FindFirstChild("HumanoidRootPart")
local function r1(v) return math.floor(v * 10 + 0.5) / 10 end
local elapsed = r1(os.clock() - R.started)
local recentParts = {}
for i = math.max(1, #R.parts - 24), #R.parts do recentParts[#recentParts + 1] = R.parts[i] end
local recentEvents = {}
for i = math.max(1, #R.events - 14), #R.events do recentEvents[#recentEvents + 1] = R.events[i] end
pcall(function() writefile("dq_rec.json", HttpService:JSONEncode({ started = R.started, parts = R.parts, events = R.events, hits = R.hits })) end)
return HttpService:JSONEncode({
    elapsed = elapsed, parts = #R.parts, events = #R.events, hits = #R.hits,
    health = hum and math.floor(hum.Health) or nil, pos = rt and { r1(rt.Position.X), r1(rt.Position.Y), r1(rt.Position.Z) } or nil,
    dungeon = workspace:FindFirstChild("dungeonName") and workspace.dungeonName.Value or nil,
    wave = workspace:FindFirstChild("currentWave") and workspace.currentWave.Value or nil,
    progress = workspace:FindFirstChild("dungeonProgress") and workspace.dungeonProgress.Value or nil,
    dodge = S and S.DG and { target = S.DG.target ~= nil, reason = S.DG.targetReason, dangerHere = S.DG.dangerHere and r1(S.DG.dangerHere) or nil,
        gapWait = S.DG.gapWait, hubHold = S.DG.hubHold } or nil,
    hazards = S and S.HZ and { detected = #S.HZ.detected } or nil,
    nav = S and S.NAV and { driving = S.NAV.driving, enemy = S.NAV.cachedEnemy and S.NAV.cachedEnemy.Name or nil } or nil,
    allHits = R.hits, recentEvents = recentEvents, recentParts = recentParts,
})
