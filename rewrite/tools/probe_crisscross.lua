-- probe_crisscross.lua: the Champion's criss cross, which is what actually kills the bot at him.
-- For every ball: how far from the character it appears, how fast it closes, its nearest approach, and whether the
-- character lost health while it was near. Writes dq_crisscross.json and prints one line per ball that hurts.
local Players, Workspace = game:GetService("Players"), game:GetService("Workspace")
local lp = Players.LocalPlayer
if _G.DQCC and _G.DQCC.stop then pcall(_G.DQCC.stop) end
local P = { started = os.clock(), list = {}, conns = {}, jumpAt = -1e9 }
_G.DQCC = P
local function r1(v) return math.floor(v * 10 + 0.5) / 10 end
local function root() local c = lp.Character return c and c:FindFirstChild("HumanoidRootPart") end
local function hum() local c = lp.Character return c and c:FindFirstChildOfClass("Humanoid") end
local function flat(a, b) return (Vector3.new(a.X, 0, a.Z) - Vector3.new(b.X, 0, b.Z)).Magnitude end

local function watch(part, kind)
    local rt, hm = root(), hum()
    if not (rt and hm) then return end
    local rec = { t = r1(os.clock() - P.started), kind = kind, d0 = r1(flat(part.Position, rt.Position)),
        size = string.format("%.0fx%.0fx%.0f", part.Size.X, part.Size.Y, part.Size.Z),
        afterJump = r1(os.clock() - P.jumpAt), near = 1e9, hurtAt = nil, lost = 0 }
    P.list[#P.list + 1] = rec
    if #P.list > 150 then table.remove(P.list, 1) end
    task.spawn(function()
        local hp0, first = hm.Health, part.Position
        for i = 1, 30 do
            task.wait(0.1)
            local rt2, hm2 = root(), hum()
            if not (part.Parent and rt2 and hm2) then break end
            local d = flat(part.Position, rt2.Position)
            if d < rec.near then rec.near = r1(d) rec.nearAt = r1(i * 0.1) end
            if not rec.speed and i == 2 then rec.speed = r1(flat(part.Position, first) / 0.2) end
            if hm2.Health < hp0 - 0.5 and not rec.hurtAt then
                rec.hurtAt, rec.lost, rec.hurtD = r1(i * 0.1), math.floor(hp0 - hm2.Health), r1(d)
                warn(string.format("[DQ cc] hurt by %s: appeared %.0f studs away%s, hit at %.0f studs after %.1f s, ball %s at %s studs/s",
                    kind, rec.d0, rec.afterJump < 3 and (" " .. rec.afterJump .. " s after Jump Up") or "", rec.hurtD, rec.hurtAt, rec.size, tostring(rec.speed)))
            end
            hp0 = math.min(hp0, hm2.Health)
        end
        pcall(writefile, "dq_crisscross.json", game:GetService("HttpService"):JSONEncode(P.list))
    end)
end

P.conns[#P.conns + 1] = Workspace.DescendantAdded:Connect(function(d)
    task.defer(function()
        if not d.Parent then return end
        local top = d
        while top.Parent and top.Parent ~= Workspace do top = top.Parent end
        local n = string.lower(top.Name)
        if n:find("jumpup", 1, true) or n == "first boss jump up" then P.jumpAt = os.clock() return end
        if not d:IsA("BasePart") then return end
        if n:find("crisscross", 1, true) then watch(d, top.Name) end
    end)
end)
function P.stop() for _, c in ipairs(P.conns) do pcall(function() c:Disconnect() end) end end
return { ok = true, note = "criss cross probe running" }
