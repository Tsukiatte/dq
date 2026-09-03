-- probe_circle.lua - Watch Bob's circle hitboxes: class, shape, size, orientation
-- and how they change over their life, with the player's distance at each sample.
-- Run at Bob; returns JSON after ~3 s.
local H = game:GetService("HttpService")
local lp = game.Players.LocalPlayer
local out = { models = {} }
local seen = 0
local function describe(m)
    local parts = {}
    for _, d in ipairs(m:GetDescendants()) do
        if d:IsA("BasePart") then
            local up = d.CFrame.UpVector
            local right = d.CFrame.RightVector
            parts[#parts + 1] = string.format("%s %s shape=%s size=%.1f,%.1f,%.1f tr=%.2f cancollide=%s upY=%.2f rightY=%.2f pos=%.0f,%.0f,%.0f",
                d.Name, d.ClassName, d:IsA("Part") and tostring(d.Shape) or "-", d.Size.X, d.Size.Y, d.Size.Z, d.Transparency, tostring(d.CanCollide), up.Y, right.Y, d.Position.X, d.Position.Y, d.Position.Z)
        end
    end
    return parts
end
local t0 = os.clock()
local tracked = {}
while os.clock() - t0 < 3 do
    for _, m in ipairs(workspace:GetChildren()) do
        if m:IsA("Model") and m.Name:lower():find("cricle") and not tracked[m] and seen < 3 then
            tracked[m] = true
            seen = seen + 1
            local rec = { name = m.Name, first = describe(m), samples = {} }
            out.models[#out.models + 1] = rec
            task.spawn(function()
                local start = os.clock()
                while m.Parent and os.clock() - start < 3 do
                    local hb = m:FindFirstChild("hitBox")
                    local pc = m:FindFirstChild("precast")
                    local rt = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
                    rec.samples[#rec.samples + 1] = string.format("t%.1f hb=%s pcTr=%s dist=%s",
                        os.clock() - start, hb and string.format("%.1f,%.1f,%.1f", hb.Size.X, hb.Size.Y, hb.Size.Z) or "-", pc and string.format("%.2f", pc.Transparency) or "-",
                        (hb and rt) and string.format("%.1f", (Vector3.new(hb.Position.X, 0, hb.Position.Z) - Vector3.new(rt.Position.X, 0, rt.Position.Z)).Magnitude) or "-")
                    task.wait(0.25)
                end
                rec.gone = os.clock() - start
            end)
        end
    end
    task.wait(0.1)
end
task.wait(3)
return H:JSONEncode(out)
