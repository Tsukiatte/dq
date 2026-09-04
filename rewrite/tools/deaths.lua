-- deaths.lua - a compact death log you can read on screen or send on.
-- Run it once per session, after the bot and the recorder. It prints one line per death, and keeps them in
-- _G.DQDeaths so `return _G.DQDeaths.report()` gives the lot at any point. The recorder holds the full traces;
-- this is the summary that fits in a screenshot.
local Players = game:GetService("Players")
local lp = Players.LocalPlayer
if _G.DQDeaths and _G.DQDeaths.stop then pcall(_G.DQDeaths.stop) end
local D = { started = os.clock(), list = {}, conns = {} }
_G.DQDeaths = D
local function r1(v) return math.floor(v * 10 + 0.5) / 10 end

-- Signed depth: positive inside the box, negative outside by that distance.
local function depth(b, p)
    if b.moving then
        local along = b.offset + b.speed * math.max(os.clock() - b.pathStart, 0)
        local qx, qz = p.X - (b.ox + b.dx * along), p.Z - (b.oz + b.dz * along)
        local a = math.abs(qx * b.dx + qz * b.dz) - b.halfL
        local s = math.abs(-qx * b.dz + qz * b.dx) - b.halfW
        if a <= 0 and s <= 0 then return -math.max(a, s) end
        return -math.sqrt(math.max(a, 0) ^ 2 + math.max(s, 0) ^ 2)
    end
    if b.r then
        local d = b.r - math.sqrt((p.X - b.cx) ^ 2 + (p.Z - b.cz) ^ 2)
        if b.ring then
            local qx, qz = p.X - b.cx, p.Z - b.cz
            if qx * (b.sx or 0) + qz * (b.sz or 0) < 0 then return -999 end
            d = math.min(d, math.sqrt(qx * qx + qz * qz) - b.ring)
        end
        return d
    end
    local qx, qz = p.X - b.cx, p.Z - b.cz
    local oa = math.abs(qx * b.ax + qz * b.az) - b.ha
    local ob = math.abs(qx * b.bx + qz * b.bz) - b.hb
    if oa <= 0 and ob <= 0 then return -math.max(oa, ob) end
    return -math.sqrt(math.max(oa, 0) ^ 2 + math.max(ob, 0) ^ 2)
end

local function record()
    local S = _G.DungeonAutofarmState
    local c = lp.Character
    local rt = c and c:FindFirstChild("HumanoidRootPart")
    local now = os.clock()
    local e = { t = r1(now - D.started) }
    if S and rt then
        local boxes = S.hazards(now)
        local inside, near = nil, {}
        for _, b in ipairs(boxes) do
            local d = depth(b, rt.Position)
            local live = now >= (b.from or 0) and now <= (b.untilAt or 0)
            if d >= 0 and not b.weight then
                local cls = live and "live" or (now < (b.from or 0) and ("early by " .. r1((b.from or 0) - now)) or ("over by " .. r1(now - (b.untilAt or 0))))
                if not inside or live then inside = { name = b.name or "?", cls = cls, depth = r1(d) } end
            elseif -d <= 18 then
                near[#near + 1] = string.format("%s %.0f%s", b.name or "?", -d, live and "*" or "")
            end
        end
        table.sort(near)
        e.killer = inside and string.format("%s (%s, %.0f studs in)", inside.name, inside.cls, inside.depth) or "nothing contained us"
        e.near = table.concat(near, ", ", 1, math.min(#near, 4))
        e.state = tostring(S.RT.movementState)
        e.grace = S.DG.grace and S.DG.grace < math.huge and r1(S.DG.grace) or "none"
        e.danger = r1(S.DG.dangerHere or 0)
        e.blinkAgo = S.RT.lastBlinkAt and r1(now - S.RT.lastBlinkAt) or "never"
        e.spots = #(S.DG.cands or {})
        local t = S.BR.target
        e.target = t and string.format("%s %.0f studs", t.model.Name, S.flatDistance(t.root.Position, rt.Position)) or "none"
    end
    D.list[#D.list + 1] = e
    warn(string.format("[DQ death %d] %s | killed by %s | state %s | grace %s | %s | near: %s",
        #D.list, e.target or "?", e.killer or "?", e.state or "?", tostring(e.grace), tostring(e.spots) .. " spots", e.near or ""))
    pcall(writefile, "dq_deaths.json", game:GetService("HttpService"):JSONEncode(D.list))
end

local function hook(c)
    local hum = c:WaitForChild("Humanoid", 10)
    if hum then D.conns[#D.conns + 1] = hum.Died:Connect(function() pcall(record) end) end
end
if lp.Character then hook(lp.Character) end
D.conns[#D.conns + 1] = lp.CharacterAdded:Connect(hook)

function D.report()
    local out = {}
    for i, e in ipairs(D.list) do
        out[i] = string.format("%d) t%.0f %s | %s | state %s grace %s danger %s blink %s ago | near %s",
            i, e.t, tostring(e.target), tostring(e.killer), tostring(e.state), tostring(e.grace), tostring(e.danger), tostring(e.blinkAgo), tostring(e.near))
    end
    return out
end
function D.stop() for _, c in ipairs(D.conns) do pcall(function() c:Disconnect() end) end end
return { ok = true, note = "deaths will print in the console and save to dq_deaths.json" }
