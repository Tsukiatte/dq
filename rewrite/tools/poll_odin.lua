-- poll_odin.lua - Everything the room shows about a boss we have not mapped (Odin): the touch-test report per attack
-- name (spawn-to-hit delay, hits per Model, precast on/off, lifetime), the remote events of the last two minutes,
-- the distinct attack spawn names with sizes, and the deaths with the boxes near them. Run through the bridge
-- repeatedly while the target is the boss; the data lives only until the next teleport.
local lp = game.Players.LocalPlayer
local S = _G.DungeonAutofarmState
local R = _G.DQRec5
local out = { version = _G.DungeonAutofarmVersion, timeLeft = workspace:FindFirstChild("timeLeft") and workspace.timeLeft.Value }
local e = S and S.BR.target
local rt = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
out.target = e and string.format("%s hp%.0f%% d%.0f", e.model.Name, e.humanoid.Health / math.max(e.humanoid.MaxHealth, 1) * 100, rt and S.flatDistance(e.root.Position, rt.Position) or -1)
if e and e.root then out.bossPos = string.format("%.0f,%.0f,%.0f", e.root.Position.X, e.root.Position.Y, e.root.Position.Z) end
local ok, rep = pcall(function() return _G.DQHitProbe.report() end)
out.probe = ok and rep or tostring(rep)
out.events, out.spawns = {}, {}
local now, seen = os.clock(), {}
for i = #(R and R.spawns or {}), 1, -1 do
    local sp = R.spawns[i]
    if now - sp.at > 120 then break end
    if sp.name:sub(1, 5) == "EVENT" then
        if #out.events < 20 then out.events[#out.events + 1] = string.format("-%.0fs %s(%s) d%s %s", now - sp.at, sp.name, sp.class, tostring(sp.dist), sp.size or "") end
    elseif sp.name:sub(1, 8) ~= "dungeon/" and sp.name:sub(1, 4) ~= "Map/" then
        local key = sp.name .. " " .. sp.class .. " " .. tostring(sp.size)
        local rec = seen[key]
        if not rec then rec = { n = 0, minD = 999 } seen[key] = rec end
        rec.n = rec.n + 1
        if sp.dist and sp.dist < rec.minD then rec.minD = sp.dist end
    end
end
for k, rec in pairs(seen) do out.spawns[#out.spawns + 1] = string.format("%s x%d nearest%.0f", k, rec.n, rec.minD) end
table.sort(out.spawns)
out.learned = {}
for name, h in pairs(S and S.RD.hitDelay or {}) do out.learned[#out.learned + 1] = string.format("%s n%d %.2f-%.2f", name, h.n, h.min, h.max) end
table.sort(out.learned)
out.deaths = {}
for _, h in ipairs(R and R.hits or {}) do
    if h.fatal then
        local near = {}
        for k, n in ipairs(h.near or {}) do if k <= 4 then near[#near + 1] = string.format("%s d%s f%s%s", n.name, tostring(n.dist), tostring(n.firesIn), n.live and "*" or "") end end
        local v = h.verdict or {}
        out.deaths[#out.deaths + 1] = string.format("t%.0f %s boss%s [%s] %s %s depth%s | near: %s | spawns: %s", h.t, h.target or "?", tostring(h.bossDist), tostring(h.state), tostring(v.class), tostring(v.name), tostring(v.depth), table.concat(near, "; "), table.concat(h.spawns or {}, " | "))
    end
end
return out
