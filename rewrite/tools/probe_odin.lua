-- probe_odin.lua - What an unmapped boss's Models do over time (Odin). Every thirdBoss* Model or part that appears is
-- watched: each part's size, position relative to the boss, yaw and transparency are sampled at 0, 0.5, 1, 2, 4 and
-- 8 s after it appears, and the character's deaths are stamped with the distance to every such part at that moment.
-- Saved to dq_odin_<job>_<time>.json every 5 s. Loaded by dq_boot in dungeon places; harmless elsewhere.
local lp = game.Players.LocalPlayer
if _G.DQOdin and _G.DQOdin.stop then pcall(_G.DQOdin.stop) end
local O = { started = os.clock(), models = {}, deaths = {}, conns = {}, count = 0 }
_G.DQOdin = O
O.file = string.format("dq_odin_%s_%s.json", string.sub(game.JobId ~= "" and game.JobId or "local", 1, 8), os.date("%H%M%S"))
local HttpService = game:GetService("HttpService")
local function r1(v) return math.floor(v * 10 + 0.5) / 10 end
local bossRootCache, bossRootAt = nil, -math.huge
local function bossRoot()
    if bossRootCache and bossRootCache.Parent and os.clock() - bossRootAt < 5 then return bossRootCache end
    bossRootAt = os.clock()
    for _, m in ipairs(workspace:GetDescendants()) do
        if m:IsA("Model") and m.Name == "Odin" then bossRootCache = m:FindFirstChild("HumanoidRootPart") or m.PrimaryPart return bossRootCache end
    end
end
local function rel(p)
    local br = bossRoot()
    if not br then return nil end
    local d = p - br.Position
    return { r1(d.X), r1(d.Y), r1(d.Z), dist = r1(math.sqrt(d.X * d.X + d.Z * d.Z)) }
end
local function partsOf(inst)
    if inst:IsA("BasePart") then return { inst } end
    local list = {}
    for _, d in ipairs(inst:GetDescendants()) do if d:IsA("BasePart") then list[#list + 1] = d end end
    return list
end
local function sample(inst)
    local parts = {}
    for _, d in ipairs(partsOf(inst)) do
        local look = d.CFrame.LookVector
        parts[#parts + 1] = { name = d.Name, size = string.format("%.0fx%.0fx%.0f", d.Size.X, d.Size.Y, d.Size.Z), rel = rel(d.Position),
            yaw = r1(math.deg(math.atan2(look.X, look.Z))), tr = r1(d.Transparency), shape = d:IsA("Part") and tostring(d.Shape):gsub("Enum.PartType.", "") or d.ClassName, cc = d.CanCollide }
    end
    return parts
end
local function watch(inst)
    local n = string.lower(inst.Name)
    if not n:find("thirdboss", 1, true) or O.models[inst] then return end
    local rec = { name = inst.Name, class = inst.ClassName, t = r1(os.clock() - O.started), samples = {} }
    O.models[inst] = rec
    O.count = O.count + 1
    task.spawn(function()
        local t0 = os.clock()
        for _, dt in ipairs({ 0, 0.5, 1, 2, 4, 8 }) do
            local wait = dt - (os.clock() - t0)
            if wait > 0 then task.wait(wait) end
            if not inst.Parent then rec.goneAt = r1(os.clock() - O.started) break end
            rec.samples[#rec.samples + 1] = { dt = dt, parts = sample(inst) }
        end
    end)
end
for _, c in ipairs(workspace:GetChildren()) do if c:IsA("Model") or c:IsA("BasePart") then watch(c) end end
O.conns[#O.conns + 1] = workspace.ChildAdded:Connect(function(c)
    if c:IsA("Model") or c:IsA("BasePart") then task.defer(function() if c.Parent then watch(c) end end) end
end)
local function hookHumanoid(c)
    local hum = c:WaitForChild("Humanoid", 10)
    if not hum then return end
    O.conns[#O.conns + 1] = hum.Died:Connect(function()
        local rt = c:FindFirstChild("HumanoidRootPart")
        local near = {}
        for inst, rec in pairs(O.models) do
            if inst.Parent and rt then
                for _, d in ipairs(partsOf(inst)) do
                    local dd = (Vector3.new(d.Position.X, 0, d.Position.Z) - Vector3.new(rt.Position.X, 0, rt.Position.Z)).Magnitude
                    if dd < 120 then near[#near + 1] = string.format("%s/%s d%.0f size %.0fx%.0fx%.0f tr%.1f age%.1f", inst.Name, d.Name, dd, d.Size.X, d.Size.Y, d.Size.Z, d.Transparency, os.clock() - O.started - rec.t) end
                end
            end
        end
        table.sort(near)
        O.deaths[#O.deaths + 1] = { t = r1(os.clock() - O.started), rel = rt and rel(rt.Position) or nil, near = near }
    end)
end
if lp.Character then hookHumanoid(lp.Character) end
O.conns[#O.conns + 1] = lp.CharacterAdded:Connect(hookHumanoid)
task.spawn(function()
    while _G.DQOdin == O and not O.stopped do
        task.wait(5)
        if O.count > 0 then
            local models = {}
            for _, rec in pairs(O.models) do models[#models + 1] = rec end
            table.sort(models, function(a, b) return a.t < b.t end)
            pcall(writefile, O.file, HttpService:JSONEncode({ savedAt = os.date("%H:%M:%S"), placeId = game.PlaceId, count = O.count, models = models, deaths = O.deaths }))
        end
    end
end)
function O.stop() O.stopped = true for _, c in ipairs(O.conns) do pcall(c.Disconnect, c) end end
return { ok = true, watching = O.count }
