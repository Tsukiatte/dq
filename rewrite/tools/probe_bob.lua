-- probe_bob.lua - At Bob: compare the modelled moving-beam wall with the real
-- secondBossMovingBeam model, list circle boxes near the character with their
-- windows, and report distance to Bob and the field's state. ~12 s.
local S = _G.DungeonAutofarmState
local H = game:GetService("HttpService")
local lp = game.Players.LocalPlayer
local rows = {}
local t0 = os.clock()
while os.clock() - t0 < 12 do
    local now = os.clock()
    local rt = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
    local wall = workspace:FindFirstChild("secondBossMovingBeam")
    local wallPos = wall and (wall.PrimaryPart or wall:FindFirstChild("middleBeam") and wall.middleBeam:FindFirstChildWhichIsA("BasePart")) 
    local modelled = nil
    for _, b in ipairs(S.hazards(now)) do
        if b.moving and b.name == "moving beam" and now <= b.untilAt then
            local along = b.offset + b.speed * math.max(now - b.pathStart, 0)
            modelled = Vector3.new(b.ox + b.dx * along, 0, b.oz + b.dz * along)
        end
    end
    local err = (modelled and wallPos) and (Vector3.new(wallPos.Position.X, 0, wallPos.Position.Z) - modelled).Magnitude or nil
    local circles, live = 0, 0
    if rt then
        for _, b in ipairs(S.hazards(now)) do
            if not b.moving and b.name and b.name:find("cricle") then
                local d = (Vector3.new(b.cframe.Position.X, 0, b.cframe.Position.Z) - Vector3.new(rt.Position.X, 0, rt.Position.Z)).Magnitude
                if d < 60 then circles = circles + 1 if now >= b.from and now <= b.untilAt then live = live + 1 end end
            end
        end
    end
    local t = S.BR.target
    rows[#rows + 1] = string.format("t%.0f %s | bob d=%s hp%s | wallErr %s | circles<60: %d (%d live) | here %.2f blinks %d", now - t0, S.RT.movementState,
        tostring((t and rt) and math.floor(S.flatDistance(t.root.Position, rt.Position)) or "-"), t and math.floor(t.humanoid.Health / t.humanoid.MaxHealth * 100) or -1,
        err and string.format("%.1f", err) or (wall and "no model" or "no wall"), circles, live, S.DG.here0 or 0, S.RT.blinks or 0)
    task.wait(1)
end
return H:JSONEncode({ rows = rows, hits = _G.DQRec5 and #_G.DQRec5.hits, timeLeft = lp.PlayerGui:FindFirstChild("timeLeftGui") and lp.PlayerGui.timeLeftGui.Frame.time.Text })
