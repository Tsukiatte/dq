-- recorder_summary.lua - Compact progress read of the live recorder: deaths by
-- enemy, damage dealt to each boss, where the character is, and the last hits.
local H = game:GetService("HttpService")
local R = _G.DQRec
if not R then return "recorder not running" end
local S = _G.DungeonAutofarmState
local function r1(v) return math.floor(v * 10 + 0.5) / 10 end
local deaths, byEnemy = 0, {}
for _, h in ipairs(R.hits) do
    if h.fatal then deaths = deaths + 1; local k = h.enemy or "?"; byEnemy[k] = (byEnemy[k] or 0) + 1 end
end
local bosses = {}
for _, s in ipairs(R.bossHp) do
    local b = bosses[s.name]
    if not b then b = { first = s.hp, last = s.hp, max = s.max, tFirst = s.t, tLast = s.t, boss = s.boss } bosses[s.name] = b end
    b.last, b.tLast = s.hp, s.t
    if s.hp > b.first then b.first = s.hp end
end
for name, b in pairs(bosses) do
    b.dealtPct = b.max > 0 and r1((b.first - b.last) / b.max * 100) or nil
    b.seconds = r1(b.tLast - b.tFirst)
    b.first, b.last, b.max = nil, nil, nil
end
local recent = {}
for i = math.max(1, #R.hits - 4), #R.hits do
    local h = R.hits[i]
    if h then
        local near = {}
        for j = 1, math.min(#h.near, 3) do local n = h.near[j]; near[j] = (n.model or n.name) .. "/" .. n.name .. " d" .. tostring(n.dist) .. " age" .. tostring(n.age) .. " " .. tostring(n.v and n.v.arm and (n.v.arm.armedBy or (n.v.arm.impactIn and ("in" .. n.v.arm.impactIn)) or "pending") or "-") end
        recent[#recent + 1] = { t = h.t, fatal = h.fatal, enemy = h.enemy, state = h.state, reason = h.dodge and h.dodge.reason, boost = h.boost, near = near }
    end
end
local lp = game.Players.LocalPlayer
local c = lp.Character
local hum = c and c:FindFirstChildOfClass("Humanoid")
local last = R.bossHp[#R.bossHp]
return H:JSONEncode({
    elapsed = r1(os.clock() - R.started), version = _G.DungeonAutofarmVersion,
    dungeon = workspace:FindFirstChild("dungeonName") and workspace.dungeonName.Value or nil,
    progress = workspace:FindFirstChild("dungeonProgress") and workspace.dungeonProgress.Value or nil,
    health = hum and math.floor(hum.Health) or "dead", deaths = deaths, deathsByEnemy = byEnemy,
    target = last and { name = last.name, hpPct = last.max > 0 and r1(last.hp / last.max * 100) or nil, boss = last.boss } or nil,
    bosses = bosses, state = S and S.RT and S.RT.movementState, dodge = S and S.DG and S.DG.targetReason,
    parts = #R.parts, events = #R.events, recentHits = recent,
})
