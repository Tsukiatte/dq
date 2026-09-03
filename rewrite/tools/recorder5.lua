-- recorder5.lua - Live capture for the 5.1 rewrite through the Potassium bridge.
-- Records every health drop with the hazards the field knew about at that
-- instant (distance to each box, its window), the brain's state and target,
-- and the boss's health once a second. Saves dq_rec5.json every 10 s.
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local lp = Players.LocalPlayer
local S = _G.DungeonAutofarmState
if _G.DQRec5 and _G.DQRec5.stop then pcall(_G.DQRec5.stop) end
local R = { started = os.clock(), hits = {}, samples = {}, states = {}, conns = {} }
_G.DQRec5 = R
local function r1(v) return math.floor(v * 10 + 0.5) / 10 end
local function v3(v) return { r1(v.X), r1(v.Y), r1(v.Z) } end
local function now() return r1(os.clock() - R.started) end

local function boxDistance(b, p)
    if b.moving then
        local along = b.offset + b.speed * math.max(os.clock() - b.pathStart, 0)
        local cx, cz = b.ox + b.dx * along, b.oz + b.dz * along
        local qx, qz = p.X - cx, p.Z - cz
        local a = math.abs(qx * b.dx + qz * b.dz) - b.halfL
        local s = math.abs(-qx * b.dz + qz * b.dx) - b.halfW
        return r1(math.max(a, s, 0) == 0 and -math.min(-a, -s) or math.sqrt(math.max(a, 0) ^ 2 + math.max(s, 0) ^ 2))
    end
    local lpos = b.cframe:PointToObjectSpace(p)
    local ex = math.max(0, math.abs(lpos.X) - b.size.X * 0.5)
    local ez = math.max(0, math.abs(lpos.Z) - b.size.Z * 0.5)
    return r1(math.sqrt(ex * ex + ez * ez))
end

-- Everything that appears in workspace, kept for a few seconds: the killer
-- that the reader never boxed shows up here.
R.spawns = {}
R.conns[#R.conns + 1] = workspace.DescendantAdded:Connect(function(inst)
    if not (inst:IsA("BasePart") or inst:IsA("Model")) then return end
    local top = inst
    while top.Parent and top.Parent ~= workspace do top = top.Parent end
    if top.Name == "DungeonAutofarmVisuals" or (lp.Character and top == lp.Character) or top.Name == "dungeon" and inst.Parent and inst.Parent.Name == "enemyFolder" then return end
    local rt = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
    local p = inst:IsA("BasePart") and inst or (inst:IsA("Model") and (inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart")))
    local d = (p and rt) and r1((Vector3.new(p.Position.X, 0, p.Position.Z) - Vector3.new(rt.Position.X, 0, rt.Position.Z)).Magnitude) or nil
    R.spawns[#R.spawns + 1] = { at = os.clock(), name = (top ~= inst and (top.Name .. "/") or "") .. inst.Name, class = inst.ClassName, dist = d,
        size = p and string.format("%.0fx%.0fx%.0f", p.Size.X, p.Size.Y, p.Size.Z) or nil }
    if #R.spawns > 400 then table.remove(R.spawns, 1) end
end)
-- Boss announcements land in the same buffer.
pcall(function()
    local remotes = game:GetService("ReplicatedStorage"):FindFirstChild("remotes")
    for _, r in ipairs(remotes and remotes:GetChildren() or {}) do
        if r:IsA("RemoteEvent") and r.Name:lower():find("bossspecficevents") then
            R.conns[#R.conns + 1] = r.OnClientEvent:Connect(function(name, args)
                local rt = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
                local pos = typeof(args) == "Vector3" and args or (typeof(args) == "CFrame" and args.Position) or (type(args) == "table" and typeof(args[5]) == "CFrame" and args[5].Position) or nil
                local d = (pos and rt) and r1((Vector3.new(pos.X, 0, pos.Z) - Vector3.new(rt.Position.X, 0, rt.Position.Z)).Magnitude) or nil
                R.spawns[#R.spawns + 1] = { at = os.clock(), name = "EVENT " .. tostring(name), class = typeof(args), dist = d, size = (type(args) == "table" and #args >= 4) and string.format("dist%.0f dur%.1f", tonumber(args[1]) or 0, tonumber(args[2]) or 0) or nil }
            end)
        end
    end
end)

local function recentSpawns(t)
    local out = {}
    for i = #R.spawns, 1, -1 do
        local sp = R.spawns[i]
        if t - sp.at > 4 then break end
        if not sp.name:lower():find("passivebeam") or (sp.dist or 99) < 12 then
            out[#out + 1] = string.format("%.1fs %s(%s) d%s %s", t - sp.at, sp.name, sp.class, tostring(sp.dist), sp.size or "")
        end
    end
    return out
end

local function hookHumanoid(c)
    local hum = c:WaitForChild("Humanoid", 10)
    if not hum then return end
    local last = hum.Health
    R.conns[#R.conns + 1] = hum.HealthChanged:Connect(function(h)
        if h < last - 1 then
            local rt = c:FindFirstChild("HumanoidRootPart")
            local near = {}
            if rt and S and S.hazards then
                local t = os.clock()
                for _, b in ipairs(S.hazards(t)) do
                    local d = boxDistance(b, rt.Position)
                    if d <= 20 then
                        near[#near + 1] = { name = b.name, kind = b.kind or (b.moving and "path" or "zone"), dist = d,
                            firesIn = r1(b.from - t), endsIn = b.untilAt < math.huge and r1(b.untilAt - t) or nil, live = t >= b.from and t <= b.untilAt }
                    end
                end
                table.sort(near, function(a, b) return a.dist < b.dist end)
            end
            R.hits[#R.hits + 1] = { t = now(), lost = math.floor(last - h), fatal = h <= 0, pos = rt and v3(rt.Position) or nil, near = near, spawns = recentSpawns(os.clock()),
                state = S and S.RT.movementState, reason = S and S.DG and S.DG.reason, dangerHere = S and S.DG and r1(S.DG.dangerHere or 0),
                grace = S and S.DG and S.DG.grace ~= math.huge and r1(S.DG.grace) or nil,
                target = S and S.BR and S.BR.target and S.BR.target.model.Name or nil,
                cands = (function()
                    if not (S and S.DG and S.DG.cands) then return nil end
                    local list = {}
                    for i = 1, math.min(6, #S.DG.cands) do local cd = S.DG.cands[i]; list[i] = { dist = r1(cd.dist), danger = r1(cd.danger), cost = r1(cd.cost), valid = cd.valid == true } end
                    return list
                end)(),
                bossDist = (function()
                    local e = S and S.BR and S.BR.target
                    if e and rt then return r1(S.flatDistance(e.root.Position, rt.Position)) end
                end)() }
        end
        last = h
    end)
end
if lp.Character then hookHumanoid(lp.Character) end
R.conns[#R.conns + 1] = lp.CharacterAdded:Connect(function(c) R.states[#R.states + 1] = { t = now(), s = "respawn" } hookHumanoid(c) end)

task.spawn(function()
    while _G.DQRec5 == R and not R.stopped do
        task.wait(1)
        local e = S and S.BR and S.BR.target
        local rt = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
        R.samples[#R.samples + 1] = { t = now(), target = e and e.model.Name, hp = e and r1(e.humanoid.Health / math.max(e.humanoid.MaxHealth, 1) * 100),
            dist = (e and rt) and r1(S.flatDistance(e.root.Position, rt.Position)) or nil, state = S and S.RT.movementState, reason = S and S.DG and S.DG.reason,
            hazards = S and #S.hazards(os.clock()) or 0, tickMs = S and r1(S.RT.tickMs or 0) }
        if #R.samples > 1800 then table.remove(R.samples, 1) end
    end
end)
task.spawn(function()
    while _G.DQRec5 == R and not R.stopped do
        task.wait(10)
        pcall(writefile, "dq_rec5.json", HttpService:JSONEncode({ hits = R.hits, samples = R.samples, states = R.states }))
    end
end)
function R.stop() for _, c in ipairs(R.conns) do pcall(function() c:Disconnect() end) end R.stopped = true end
return { ok = true, version = _G.DungeonAutofarmVersion, loaded = S ~= nil }
