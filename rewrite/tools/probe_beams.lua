-- probe_beams.lua - What actually changes on the Champion's attack Models when they fire, and when the player dies
-- relative to those changes. Run through the bridge during the Champion fight; read the result back after ~40 s
-- with `return _G.DQBeamProbe.report()`.
--
-- Every Model in workspace whose name matches the attack list gets a Changed listener on each of its BaseParts
-- (Transparency, CFrame/Position, Color, CanTouch, CanQuery, Size) plus ChildAdded (particles, sounds), and every
-- Attribute change. Each event is logged with the time, the Model, the part, the property and the new value. Deaths
-- are logged with the character position and, for each Model within 40 studs, the last known property state and how
-- long ago each property last changed. The report groups, per Model name, the property transitions that precede
-- deaths by a consistent delay: that is the real "live" signal and its lead time.
local Players = game:GetService("Players")
local lp = Players.LocalPlayer
if _G.DQBeamProbe and _G.DQBeamProbe.stop then pcall(_G.DQBeamProbe.stop) end
local P = { started = os.clock(), events = {}, models = {}, deaths = {}, conns = {} }
_G.DQBeamProbe = P
local WATCH = { "passivebeam", "crisscross", "jumpslam", "bigspike", "seekingspike", "beampart", "smokepart" }
local function r2(v) return math.floor(v * 100 + 0.5) / 100 end
local function now() return r2(os.clock() - P.started) end
local function watched(name)
    local n = string.lower(name)
    for _, w in ipairs(WATCH) do if n:find(w, 1, true) then return true end end
    return false
end
local function log(model, part, prop, value)
    local m = P.models[model]
    if not m then return end
    local t = now()
    m.last[part.Name .. "." .. prop] = { t = t, v = value }
    P.events[#P.events + 1] = { t = t, model = m.id, part = part.Name, prop = prop, v = value }
    if #P.events > 6000 then table.remove(P.events, 1) end
end
local function fmt(v)
    if typeof(v) == "Vector3" then return string.format("%.1f,%.1f,%.1f", v.X, v.Y, v.Z) end
    if typeof(v) == "Color3" then return string.format("%d,%d,%d", v.R * 255, v.G * 255, v.B * 255) end
    if type(v) == "number" then return tostring(r2(v)) end
    return tostring(v)
end
local function hookPart(model, part)
    local m = P.models[model]
    for _, prop in ipairs({ "Transparency", "Color", "CanTouch", "CanQuery", "CanCollide", "Size" }) do
        local ok, sig = pcall(function() return part:GetPropertyChangedSignal(prop) end)
        if ok then m.conns[#m.conns + 1] = sig:Connect(function() log(model, part, prop, fmt(part[prop])) end) end
    end
    -- position: polled (CFrame signals fire every physics step for moving parts)
    m.parts[#m.parts + 1] = part
    m.lastPos[part] = part.Position
    m.conns[#m.conns + 1] = part.ChildAdded:Connect(function(c) log(model, part, "child+", c.ClassName .. ":" .. c.Name) end)
    m.conns[#m.conns + 1] = part.ChildRemoved:Connect(function(c) log(model, part, "child-", c.ClassName .. ":" .. c.Name) end)
end
local nextId = 0
local function hookModel(model)
    if P.models[model] or not watched(model.Name) then return end
    nextId = nextId + 1
    local m = { id = model.Name .. "#" .. nextId, name = model.Name, conns = {}, parts = {}, last = {}, lastPos = {}, born = now() }
    P.models[model] = m
    for _, d in ipairs(model:GetDescendants()) do if d:IsA("BasePart") then hookPart(model, d) end end
    m.conns[#m.conns + 1] = model.DescendantAdded:Connect(function(d) if d:IsA("BasePart") then hookPart(model, d) end log(model, d.Parent or model, "desc+", d.ClassName .. ":" .. d.Name) end)
    m.conns[#m.conns + 1] = model.AttributeChanged:Connect(function(a) log(model, model, "attr:" .. a, fmt(model:GetAttribute(a))) end)
    m.conns[#m.conns + 1] = model.AncestryChanged:Connect(function() if not model.Parent then log(model, model, "parent", "nil") end end)
    P.events[#P.events + 1] = { t = now(), model = m.id, part = "-", prop = "tracked", v = tostring(#m.parts) .. " parts" }
end
for _, c in ipairs(workspace:GetChildren()) do if c:IsA("Model") then hookModel(c) end end
P.conns[#P.conns + 1] = workspace.ChildAdded:Connect(function(c) if c:IsA("Model") then task.defer(hookModel, c) end end)
-- position polling at 20 Hz: a move of more than 2 studs is an event (pooled beams are re-aimed by moving)
task.spawn(function()
    while _G.DQBeamProbe == P and not P.stopped do
        task.wait(0.05)
        for model, m in pairs(P.models) do
            if not model.Parent then
                for _, c in ipairs(m.conns) do pcall(c.Disconnect, c) end
                P.models[model] = nil
            else
                for _, part in ipairs(m.parts) do
                    if part.Parent then
                        local p = part.Position
                        local lastP = m.lastPos[part]
                        if lastP and (p - lastP).Magnitude > 2 then log(model, part, "moved", fmt(p)) end
                        m.lastPos[part] = p
                    end
                end
            end
        end
    end
end)
-- deaths: the state of every watched Model within 40 studs, and how long ago each property last changed
local function hookHumanoid(c)
    local hum = c:WaitForChild("Humanoid", 10)
    if not hum then return end
    local last = hum.Health
    P.conns[#P.conns + 1] = hum.HealthChanged:Connect(function(h)
        if h < last - 1 then
            local rt = c:FindFirstChild("HumanoidRootPart")
            local t = now()
            local near = {}
            if rt then
                for model, m in pairs(P.models) do
                    local best = math.huge
                    for _, part in ipairs(m.parts) do
                        if part.Parent then
                            -- distance from the character to the part's box (flat)
                            local lp2 = part.CFrame:PointToObjectSpace(rt.Position)
                            local ex, ez = math.max(0, math.abs(lp2.X) - part.Size.X * 0.5), math.max(0, math.abs(lp2.Z) - part.Size.Z * 0.5)
                            local d = math.sqrt(ex * ex + ez * ez)
                            if d < best then best = d end
                        end
                    end
                    if best <= 40 then
                        local state = {}
                        for k, e in pairs(m.last) do state[#state + 1] = string.format("%s=%s (%.2fs ago)", k, tostring(e.v), t - e.t) end
                        table.sort(state)
                        near[#near + 1] = { model = m.id, dist = r2(best), age = r2(t - m.born), state = state }
                    end
                end
                table.sort(near, function(a, b) return a.dist < b.dist end)
            end
            P.deaths[#P.deaths + 1] = { t = t, fatal = h <= 0, pos = rt and rt.Position, near = near }
        end
        last = h
    end)
end
if lp.Character then hookHumanoid(lp.Character) end
P.conns[#P.conns + 1] = lp.CharacterAdded:Connect(hookHumanoid)

function P.report(maxEvents)
    local out = { elapsed = now(), models = 0, events = #P.events, deaths = {} }
    for _ in pairs(P.models) do out.models = out.models + 1 end
    for _, d in ipairs(P.deaths) do
        local lines = {}
        for k, n in ipairs(d.near) do if k <= 3 then lines[#lines + 1] = string.format("%s d%.1f age%.1f | %s", n.model, n.dist, n.age, table.concat(n.state, "; ")) end end
        out.deaths[#out.deaths + 1] = string.format("t%.2f %s\n    %s", d.t, d.fatal and "DEAD" or "hit", table.concat(lines, "\n    "))
    end
    -- property transitions per Model name: which properties change at all, and the typical values
    local transitions = {}
    for _, e in ipairs(P.events) do
        local key = e.model:gsub("#%d+$", "") .. " " .. e.part .. "." .. e.prop
        local tr = transitions[key] or { n = 0, values = {} }
        tr.n = tr.n + 1
        tr.values[tostring(e.v)] = (tr.values[tostring(e.v)] or 0) + 1
        transitions[key] = tr
    end
    local list = {}
    for k, tr in pairs(transitions) do
        local vals = {}
        for v, n in pairs(tr.values) do vals[#vals + 1] = v .. " x" .. n end
        table.sort(vals)
        list[#list + 1] = string.format("%s x%d: %s", k, tr.n, table.concat(vals, ", "):sub(1, 160))
    end
    table.sort(list)
    out.transitions = list
    -- the last events, in order
    local tail = {}
    local n = maxEvents or 60
    for i = math.max(1, #P.events - n + 1), #P.events do
        local e = P.events[i]
        tail[#tail + 1] = string.format("t%.2f %s %s.%s=%s", e.t, e.model, e.part, e.prop, tostring(e.v))
    end
    out.tail = tail
    return out
end
function P.stop()
    for _, c in ipairs(P.conns) do pcall(c.Disconnect, c) end
    for _, m in pairs(P.models) do for _, c in ipairs(m.conns) do pcall(c.Disconnect, c) end end
    P.stopped = true
end
local n = 0
for _ in pairs(P.models) do n = n + 1 end
return { ok = true, watching = n }
