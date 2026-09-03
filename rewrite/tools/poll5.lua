-- poll5.lua - One-call summary of a live 5.1 run through the Potassium bridge.
-- Needs recorder5.lua running (_G.DQRec5). Returns JSON: deaths with the
-- hazards around each, the field's top candidates at that instant, boss
-- health progress, state histogram, mover counters.
local S = _G.DungeonAutofarmState
local R = _G.DQRec5
local H = game:GetService("HttpService")
local lp = game.Players.LocalPlayer
local c = lp.Character
local hum = c and c:FindFirstChildOfClass("Humanoid")
local rt = c and c:FindFirstChild("HumanoidRootPart")
local out = { version = _G.DungeonAutofarmVersion, elapsed = R and math.floor(os.clock() - R.started), hits = {},
    health = hum and math.floor(hum.Health / 1e6) or "dead", walkSpeed = hum and hum.WalkSpeed, state = S and S.RT.movementState,
    pos = rt and string.format("%.0f,%.0f,%.0f", rt.Position.X, rt.Position.Y, rt.Position.Z) }
local from = tonumber(_G.DQPollFrom) or 1
if R then
    for i = from, #R.hits do
        local h = R.hits[i]
        local near = {}
        for j = 1, math.min(4, #h.near) do local n = h.near[j]; near[j] = string.format("%s d%.1f f%.1f%s", n.name, n.dist, n.firesIn or 0, n.live and " live" or "") end
        local cands = {}
        if h.cands then for j, cd in ipairs(h.cands) do cands[j] = string.format("%.0fst dg%.1f c%.2f %s", cd.dist, cd.danger, cd.cost, cd.valid and "ok" or "x") end end
        out.hits[#out.hits + 1] = { t = h.t, fatal = h.fatal, bossDist = h.bossDist, state = h.state, here = h.dangerHere, grace = h.grace, near = near, cands = cands, spawns = h.spawns }
    end
    out.totalHits = #R.hits
    -- Effective ability range: the largest distance at which the boss lost
    -- health over the following second (the abilities are the only damage
    -- beyond attackRange), and a histogram of damage by distance band.
    local far, bands, secs = 0, {}, {}
    for i = 1, #R.samples - 1 do
        local a, b = R.samples[i], R.samples[i + 1]
        if a.hp and b.hp and a.dist and a.target == b.target then
            local band = tostring(math.floor(a.dist / 10) * 10)
            secs[band] = (secs[band] or 0) + 1
            if b.hp < a.hp - 0.05 then
                if a.dist > far then far = a.dist end
                bands[band] = (bands[band] or 0) + (a.hp - b.hp)
            end
        end
    end
    out.damageReach = far
    local dps = {}
    for band, s in pairs(secs) do dps[band] = string.format("%.2f%%/s over %ds", (bands[band] or 0) / s, s) end
    out.damageByDistance = dps
    local first = R.samples[1]
    local last = R.samples[#R.samples]
    out.bossHp = { first = first and first.hp, last = last and last.hp, dist = last and last.dist, target = last and last.target }
    local st = {}
    for _, s in ipairs(R.samples) do local k = (s.state or "?"):match("^%a+") or "?"; st[k] = (st[k] or 0) + 1 end
    out.states = st
end
out.counts = S and S.MV and S.MV.counts
out.enemies = {}
if S and rt then for _, e in ipairs(S.RD.enemies) do out.enemies[#out.enemies + 1] = e.model.Name .. (e.isBoss and "[B]" or e.melee and "[M]" or "[R]") .. " d" .. math.floor(S.flatDistance(Vector3.new(e.x, 0, e.z), rt.Position)) end end
return H:JSONEncode(out)
