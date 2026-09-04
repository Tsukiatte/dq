-- poll6.lua - Read the recorder6 capture through the bridge: verdicts per
-- kind, movement effectiveness, and for the recent deaths a compact trace of
-- the seconds before. Returns a table small enough to read in one go.
local lp = game.Players.LocalPlayer
local S = _G.DungeonAutofarmState
local R = _G.DQRec5
local out = { version = _G.DungeonAutofarmVersion, timeLeft = lp.PlayerGui:FindFirstChild("timeLeftGui") and lp.PlayerGui.timeLeftGui.Frame.time.Text }
if not R then out.error = "no recorder" return out end
out.elapsed = math.floor(os.clock() - R.started)
out.state = S and S.RT.movementState
out.blinks = S and S.RT.blinks
local e = S and S.BR and S.BR.target
local rt = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
out.target = e and string.format("%s hp%d%% d%d", e.model.Name, math.floor(e.humanoid.Health / math.max(e.humanoid.MaxHealth, 1) * 100), rt and S.flatDistance(e.root.Position, rt.Position) or -1)
out.range = S and { cap = S.RD.abilityRange, reach = S.RD.abilityReach }
-- verdicts
local vs = {}
for k, v in pairs(R.verdicts or {}) do vs[#vs + 1] = string.format("%s x%d avgBy%.1f", k, v.n, v.n > 0 and v.bySum / v.n or 0) end
table.sort(vs)
out.verdicts = vs
-- movement
local m = R.move
if m and m.n > 0 then
    out.movement = string.format("commanded %d samples: speed/walkspeed %.2f, direction match %.2f, stuck %.0f%%, idle samples %d", m.n, m.effSum / m.n, m.dotSum / math.max(m.n, 1), m.stuck / m.n * 100, m.idle or 0)
end
out.blinkLog = {}
for i = math.max(1, #R.blinkLog - 6), #R.blinkLog do local b = R.blinkLog[i] if b then out.blinkLog[#out.blinkLog + 1] = string.format("t%.0f %sst grace%s near=%s", b.t, tostring(b.dist), tostring(b.grace), tostring(b.near)) end end
out.reflexLog = {}
for i = math.max(1, #R.reflexLog - 8), #R.reflexLog do local x = R.reflexLog[i] if x then out.reflexLog[#out.reflexLog + 1] = string.format("t%.0f %s", x.t, x.reflex) end end
-- what the room is throwing: the last remote events and the distinct spawn names of the last 90 s (Odin is unmapped)
out.recentEvents, out.recentSpawns = {}, {}
local nowC, seen = os.clock(), {}
for i = #(R.spawns or {}), 1, -1 do
    local sp = R.spawns[i]
    if nowC - sp.at > 90 then break end
    if sp.name:sub(1, 5) == "EVENT" then
        if #out.recentEvents < 12 then out.recentEvents[#out.recentEvents + 1] = string.format("-%.0fs %s d%s %s", nowC - sp.at, sp.name, tostring(sp.dist), sp.size or "") end
    elseif sp.name:sub(1, 8) ~= "dungeon/" and sp.name:sub(1, 4) ~= "Map/" then   -- mob debris and map parts are not attacks
        local key = sp.name .. " " .. tostring(sp.size)
        seen[key] = (seen[key] or 0) + 1
    end
end
for k, n in pairs(seen) do out.recentSpawns[#out.recentSpawns + 1] = k .. " x" .. n end
table.sort(out.recentSpawns)
out.learned = {}
for name, h in pairs(S and S.RD.hitDelay or {}) do out.learned[#out.learned + 1] = string.format("%s n%d %.2f-%.2f", name, h.n, h.min, h.max) end
table.sort(out.learned)
-- deaths
local deaths = 0
for _, h in ipairs(R.hits) do if h.fatal then deaths = deaths + 1 end end
out.deaths = deaths
out.hits = {}
local firstShown = math.max(1, #R.hits - 5)
for i = firstShown, #R.hits do
    local h = R.hits[i]
    local v = h.verdict or {}
    local near = {}
    for k, n in ipairs(h.near or {}) do if k <= 3 then near[#near + 1] = string.format("%s d%s f%s%s", n.name, tostring(n.dist), tostring(n.firesIn), n.live and "*" or "") end end
    local head = string.format("t%.0f %s boss%s [%s] %s%s | verdict: %s %s%s | near: %s",
        h.t, h.fatal and "DEAD" or "hit", tostring(h.bossDist), tostring(h.state), h.reflex and ("reflex=" .. h.reflex .. " ") or "", h.lastBlinkAgo and ("blinkAgo=" .. h.lastBlinkAgo) or "",
        v.class or "?", v.name and (v.name .. "(" .. tostring(v.kind) .. ") depth" .. tostring(v.depth)) or (v.nearest and ("nearest " .. v.nearest.name .. " d" .. tostring(v.nearest.dist) .. " f" .. tostring(v.nearest.firesIn)) or ""),
        v.by and v.by > 0 and (" by " .. v.by .. "s") or "", table.concat(near, "; "))
    if h.hopFail then head = head .. " | " .. h.hopFail end
    local lines = { head }
    -- the trace: every third sample of the last 3 s
    local tr = h.trace or {}
    for j = math.max(1, #tr - 30), #tr, 3 do
        local r = tr[j]
        if r then
            lines[#lines + 1] = string.format("  %+.1fs v%s ws%s md%s eff%s dot%s cast%s | %s%s | tg%s h0%s hd%s gr%s | %s | %s | %s%s",
                r.t - h.t, tostring(r.v), tostring(r.ws), tostring(r.md), tostring(r.eff), tostring(r.dot), tostring(r.bc), tostring(r.st), r.rf and (" RF:" .. r.rf) or "",
                tostring(r.tg), tostring(r.h0), tostring(r.hd), tostring(r.gr), tostring(r.near), tostring(r.ch), tostring(r.ev), r.bo and " boost" or "")
        end
    end
    local sp = {}
    for k, s in ipairs(h.spawns or {}) do if k <= 8 then sp[#sp + 1] = s end end
    lines[#lines + 1] = "  spawns: " .. table.concat(sp, " | ")
    if h.beams then lines[#lines + 1] = "  beams: " .. h.beams end
    out.hits[#out.hits + 1] = table.concat(lines, "\n")
end
return out
