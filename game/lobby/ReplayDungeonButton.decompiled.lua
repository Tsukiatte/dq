-- Players.OPhhSZQjWxdy.PlayerGui.ReplayDungeonButton.Replay.LocalScript
-- Decompiled with Potassium's decompiler.

local script_Parent = script.Parent;
local Players = game:GetService("Players");
local ReplicatedStorage = game:GetService("ReplicatedStorage");
game:GetService("RunService");
local Utility = ReplicatedStorage:WaitForChild("Utility");
local PlaceManager = require(Utility:WaitForChild("PlaceManager"));

if PlaceManager.GetPlaceName() ~= "Level" then
    script_Parent.Visible = false;

    return;
end;

local replayDungeon = ReplicatedStorage:WaitForChild("remotes"):WaitForChild("replayDungeon");
local u1 = nil;
local u2 = nil;
script_Parent.Visible = false;

local function isDungeonOwner() -- Line: 38
    -- upvalues: Players (copy), PlaceManager (copy)
    local LocalPlayer = Players.LocalPlayer;

    if not LocalPlayer then
        return false;
    end;

    local PlaceTeleportData = PlaceManager.GetPlaceTeleportData();

    if not PlaceTeleportData then
        print("[Replay] No teleport data found");

        return false;
    end;

    local ownerId = PlaceTeleportData.ownerId;

    if not ownerId then
        print("[Replay] No ownerId in teleport data");

        return false;
    end;

    local v3 = LocalPlayer.UserId == ownerId;
    print("[Replay] Owner check - LocalPlayer:", LocalPlayer.UserId, "OwnerId:", ownerId, "IsOwner:", v3);

    return v3;
end;

local function collectDungeonData() -- Line: 60
    local v4 = {};
    local dungeonName = workspace:FindFirstChild("dungeonName");

    if dungeonName and dungeonName:IsA("StringValue") then
        v4.dungeonName = dungeonName.Value;
    end;

    local dungeonProgress = workspace:FindFirstChild("dungeonProgress");

    if dungeonProgress and dungeonProgress:IsA("StringValue") then
        v4.dungeonProgress = dungeonProgress.Value;
    end;

    local dungeonStarted = workspace:FindFirstChild("dungeonStarted");

    if dungeonStarted and dungeonStarted:IsA("BoolValue") then
        v4.dungeonStarted = dungeonStarted.Value;
    end;

    local hardcore = workspace:FindFirstChild("hardcore");

    if hardcore and hardcore:IsA("BoolValue") then
        v4.hardcore = hardcore.Value;
        v4.isHardcore = hardcore.Value;
    end;

    local dungeon = workspace:FindFirstChild("dungeon");

    if dungeon then
        for _, child in pairs(dungeon:GetChildren()) do
            if child:IsA("ValueBase") then
                v4[child.Name] = child.Value;
            end;
        end;

        local bossRoom = dungeon:FindFirstChild("bossRoom");

        if bossRoom then
            for _, child in pairs(bossRoom:GetChildren()) do
                if child:IsA("ValueBase") then
                    v4[child.Name] = child.Value;
                end;
            end;
        end;
    end;

    return v4;
end;

local function getDungeonFinished() -- Line: 106
    local dungeon = workspace:FindFirstChild("dungeon");

    if not dungeon then
        return false, nil;
    end;

    local bossRoom = dungeon:FindFirstChild("bossRoom");

    if not bossRoom then
        return false, nil;
    end;

    local dungeonFinished = bossRoom:FindFirstChild("dungeonFinished");

    if dungeonFinished and dungeonFinished:IsA("BoolValue") then
        return dungeonFinished.Value, dungeonFinished;
    end;

    return false, nil;
end;

local function updateVisibility() -- Line: 119
    -- upvalues: getDungeonFinished (copy), isDungeonOwner (copy), script_Parent (copy), u2 (ref), u1 (ref)
    local v5, u6 = getDungeonFinished();
    local v7 = isDungeonOwner();
    script_Parent.Visible = v5 and v7;

    if u2 then
        u2:Disconnect();
        u2 = nil;
    end;

    u1 = u6;

    if u6 then
        u2 = u6.Changed:Connect(function() -- Line: 131
            -- upvalues: isDungeonOwner (ref), script_Parent (ref), u6 (copy)
            local v8 = isDungeonOwner();
            script_Parent.Visible = u6.Value and v8;
            print("[Replay] dungeonFinished changed, button visible =", script_Parent.Visible, "(finished:", u6.Value, "isOwner:", v8, ")");
        end);
    end;

    print("[Replay] Initial button visibility =", script_Parent.Visible, "(finished:", v5, "isOwner:", v7, ")");
end;

task.spawn(function() -- Line: 142
    -- upvalues: getDungeonFinished (copy), updateVisibility (copy)
    local v9 = 0;

    while v9 < 40 do
        local _, v10 = getDungeonFinished();

        if v10 then
            updateVisibility();
            break;
        end;

        v9 = v9 + 1;
        task.wait(0.5);
    end;

    if v9 >= 40 then
        print("[Replay] Timed out waiting for dungeonFinished");
    end;
end);
script_Parent.MouseButton1Click:Connect(function() -- Line: 159
    -- upvalues: Players (copy), collectDungeonData (copy), replayDungeon (copy)
    if not Players.LocalPlayer then
        return;
    end;

    local v11 = collectDungeonData();

    if not v11.dungeonName then
        warn("[Replay] Could not determine dungeon name");

        return;
    end;

    print("[Replay] Player clicked replay for dungeon:", v11.dungeonName);
    print("[Replay] Collected dungeon data:", game:GetService("HttpService"):JSONEncode(v11));
    replayDungeon:FireServer(v11);
    print("[Replay] Fired replayDungeon event to server");
end);