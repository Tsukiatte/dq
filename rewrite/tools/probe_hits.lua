-- probe_hits.lua - When does each attack actually hit? The server tests an attack's hitBox with a touch query at the
-- moment of damage, which puts a TouchTransmitter on the part for one frame. Watching for that on every attack
-- Model gives the real spawn-to-hit delay per attack name, and whether it hits once or keeps testing.
-- Run through the bridge; read with `return _G.DQHitProbe.report()`.
local lp = game.Players.LocalPlayer
if _G.DQHitProbe and _G.DQHitProbe.stop then pcall(_G.DQHitProbe.stop) end
local H = { started = os.clock(), models = {}, samples = {}, conns = {} }
_G.DQHitProbe = H
local function r2(v) return math.floor(v * 100 + 0.5) / 100 end
local function partsOf(model)
    local list = {}
    for _, d in ipairs(model:GetDescendants()) do if d:IsA("BasePart") then list[#list + 1] = d end end
    if model:IsA("BasePart") then list[#list + 1] = model end
    return list
end
local function watch(inst)
    if H.models[inst] then return end
    local name = inst.Name
    local n = string.lower(name)
    if n:find("dungeonautofarm") or n == "geyser" then return end
    local parts = partsOf(inst)
    if #parts == 0 then return end
    local m = { name = name, spawn = os.clock(), touches = {}, conns = {}, precastAt = nil }
    H.models[inst] = m
    local function hookPart(p)
        m.conns[#m.conns + 1] = p.ChildAdded:Connect(function(c)
            if c:IsA("TouchTransmitter") then m.touches[#m.touches + 1] = { t = os.clock() - m.spawn, part = p.Name } end
        end)
        if string.lower(p.Name):find("precast", 1, true) then
            m.conns[#m.conns + 1] = p:GetPropertyChangedSignal("Transparency"):Connect(function()
                if not m.precastAt and p.Transparency < 0.9 then m.precastAt = os.clock() - m.spawn end
                if m.precastAt and not m.precastGoneAt and p.Transparency >= 0.99 then m.precastGoneAt = os.clock() - m.spawn end
            end)
            if p.Transparency < 0.9 then m.precastAt = 0 end
        end
    end
    for _, p in ipairs(parts) do hookPart(p) end
    m.conns[#m.conns + 1] = inst.DescendantAdded:Connect(function(d) if d:IsA("BasePart") then hookPart(d) end end)
    m.conns[#m.conns + 1] = inst.AncestryChanged:Connect(function()
        if inst.Parent then return end
        m.gone = os.clock() - m.spawn
        for _, c in ipairs(m.conns) do pcall(c.Disconnect, c) end
        H.models[inst] = nil
        local s = H.samples[name] or { n = 0, hits = {}, hitCounts = {}, precast = {}, precastGone = {}, life = {}, noHit = 0 }
        H.samples[name] = s
        s.n = s.n + 1
        s.life[#s.life + 1] = m.gone
        if #m.touches > 0 then
            s.hits[#s.hits + 1] = m.touches[1].t
            s.hitCounts[#s.hitCounts + 1] = #m.touches
            if #m.touches > 1 then s.lastHits = s.lastHits or {} s.lastHits[#s.lastHits + 1] = m.touches[#m.touches].t end
        else s.noHit = s.noHit + 1 end
        if m.precastAt then s.precast[#s.precast + 1] = m.precastAt end
        if m.precastGoneAt then s.precastGone[#s.precastGone + 1] = m.precastGoneAt end
    end)
end
for _, c in ipairs(workspace:GetChildren()) do
    if (c:IsA("Model") or c:IsA("BasePart")) and c.Name ~= "Terrain" and c.Name ~= "Map" and c.Name ~= "dungeon" then watch(c) end
end
H.conns[#H.conns + 1] = workspace.ChildAdded:Connect(function(c)
    if c:IsA("Model") or c:IsA("BasePart") then task.defer(function() if c.Parent then watch(c) end end) end
end)
local function stats(list)
    if #list == 0 then return "-" end
    local s = table.clone(list)
    table.sort(s)
    local sum = 0
    for _, v in ipairs(s) do sum = sum + v end
    return string.format("n%d med%.2f min%.2f max%.2f mean%.2f", #s, s[math.ceil(#s / 2)], s[1], s[#s], sum / #s)
end
function H.report()
    local out = { elapsed = r2(os.clock() - H.started), watching = 0, attacks = {} }
    for _ in pairs(H.models) do out.watching = out.watching + 1 end
    local names = {}
    for name in pairs(H.samples) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do
        local s = H.samples[name]
        if #s.hits > 0 or s.n >= 3 then
            local counts = {}
            for _, c in ipairs(s.hitCounts) do counts[c] = (counts[c] or 0) + 1 end
            local cs = {}
            for c, k in pairs(counts) do cs[#cs + 1] = c .. "x" .. k end
            table.sort(cs)
            out.attacks[#out.attacks + 1] = string.format("%s: seen %d, no-hit %d | first hit %s | hits per model %s%s | precast on %s | precast off %s | lifetime %s",
                name, s.n, s.noHit, stats(s.hits), table.concat(cs, " "), s.lastHits and (" | last hit " .. stats(s.lastHits)) or "", stats(s.precast), stats(s.precastGone), stats(s.life))
        end
    end
    return out
end
function H.stop() for _, c in ipairs(H.conns) do pcall(c.Disconnect, c) end for _, m in pairs(H.models) do for _, c in ipairs(m.conns) do pcall(c.Disconnect, c) end end end
local n = 0
for _ in pairs(H.models) do n = n + 1 end
return { ok = true, watching = n }
