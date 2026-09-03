-- Players.OPhhSZQjWxdy.PlayerScripts.Ui.bossQueue
-- Decompiled with Potassium's decompiler.

local Players = game:GetService("Players");
local ReplicatedStorage = game:GetService("ReplicatedStorage");
local UserInputService = game:GetService("UserInputService");
ReplicatedStorage:WaitForChild("Utility", 10);
local u1 = nil;
local u2 = nil;
local u3 = nil;
local success, result = pcall(function() -- Line: 12
    -- upvalues: u1 (ref)
    u1 = require(script:WaitForChild("chooseBoss", 5));
end);

if not success then
    warn("Failed to require chooseBoss module: " .. tostring(result));
end;

local success2, result2 = pcall(function() -- Line: 17
    -- upvalues: u2 (ref)
    u2 = require(script:WaitForChild("gameSearch", 5));
end);

if not success2 then
    warn("Failed to require gameSearch module: " .. tostring(result2));
end;

local success3, result3 = pcall(function() -- Line: 22
    -- upvalues: u3 (ref)
    u3 = require(script:WaitForChild("lobbyInfo", 5));
end);

if not success3 then
    warn("Failed to require lobbyInfo module: " .. tostring(result3));
end;

local LocalPlayer = Players.LocalPlayer;
local bossQueueGui = LocalPlayer:WaitForChild("PlayerGui", 10):WaitForChild("bossQueueGui", 20);

if not bossQueueGui then
    warn("bossQueueGui never appeared in PlayerGui!");

    return;
end;

local function safeWaitForChild(p4, p5, p6) -- Line: 36
    local v7 = p4:FindFirstChild(p5);

    if v7 then
        return v7;
    end;

    local v8 = 0;

    while v8 < (p6 or 10) do
        task.wait(0.1);
        v8 = v8 + 0.1;
        local v9 = p4:FindFirstChild(p5);

        if v9 then
            return v9;
        end;
    end;

    warn("Timeout waiting for " .. p5 .. " in " .. p4.Name);

    return nil;
end;

local u10 = safeWaitForChild(bossQueueGui, "chooseBoss");
local u11 = safeWaitForChild(bossQueueGui, "gameSearch");
local u12 = safeWaitForChild(bossQueueGui, "lobbyInfo");
local u13 = safeWaitForChild(bossQueueGui, "selectOption");

if u10 and (u11 and (u12 and u13)) then
    local u14 = safeWaitForChild(u10, "xFrame");

    if u14 then
        u14 = safeWaitForChild(u14, "xButton");
    end;

    local u15 = safeWaitForChild(u11, "xFrame");

    if u15 then
        u15 = safeWaitForChild(u15, "xButton");
    end;

    local u16 = safeWaitForChild(u12, "xFrame");

    if u16 then
        u16 = safeWaitForChild(u16, "xButton");
    end;

    local u17 = safeWaitForChild(u13, "Frame");
    local u18;

    if u17 then
        u18 = safeWaitForChild(u17, "joinGame");
    else
        u18 = u17;
    end;

    if u17 then
        u17 = safeWaitForChild(u17, "createGame");
    end;

    local u19 = safeWaitForChild(u13, "xFrame");

    if u19 then
        u19 = safeWaitForChild(u19, "xButton");
    end;

    local function inLobby() -- Line: 76
        -- upvalues: LocalPlayer (copy)
        local bossLobbies = workspace:FindFirstChild("bossLobbies");

        if bossLobbies then
            for _, child in pairs(bossLobbies:GetChildren()) do
                local players = child:FindFirstChild("players");

                if players then
                    for _, child2 in pairs(players:GetChildren()) do
                        if LocalPlayer.Name == child2.Name then
                            return "raid";
                        end;
                    end;
                end;
            end;
        end;

        local games = workspace:FindFirstChild("games");

        if games then
            local inGame = games:FindFirstChild("inGame");

            if inGame then
                for _, child in pairs(inGame:GetChildren()) do
                    for _, child2 in pairs(child:GetChildren()) do
                        if child2.Name == LocalPlayer.Name then
                            return "dungeon";
                        end;
                    end;
                end;
            end;

            local inLobby = games:FindFirstChild("inLobby");

            if inLobby then
                for _, child in pairs(inLobby:GetChildren()) do
                    for _, child2 in pairs(child:GetChildren()) do
                        if child2.Name == LocalPlayer.Name then
                            return "dungeon";
                        end;
                    end;
                end;
            end;
        end;

        return "none";
    end;

    local u20 = {};

    local function setupExitButton(u21) -- Line: 121
        -- upvalues: u20 (copy)
        if not u21 then
            return;
        end;

        u21.Activated:Connect(function() -- Line: 123
            -- upvalues: u20 (ref)
            u20.Close();
        end);
        u21.MouseEnter:Connect(function() -- Line: 126
            -- upvalues: u21 (copy)
            u21.TextColor3 = Color3.fromRGB(255, 0, 0);
        end);
        u21.MouseLeave:Connect(function() -- Line: 129
            -- upvalues: u21 (copy)
            u21.TextColor3 = Color3.fromRGB(255, 255, 255);
        end);
    end;

    function u20.Init() -- Line: 134
        -- upvalues: u1 (ref), u2 (ref), u3 (ref), setupExitButton (copy), u19 (copy), u16 (copy), u15 (copy), u14 (copy), u17 (copy), bossQueueGui (copy), u13 (copy), u11 (copy), u12 (copy), u18 (copy), UserInputService (copy), u20 (copy)
        if u1 and u1.Init then
            local success4, result4 = pcall(u1.Init);

            if not success4 then
                warn("chooseBossModule.Init failed: " .. tostring(result4));
            end;
        end;

        if u2 and u2.Init then
            local success4, result4 = pcall(u2.Init);

            if not success4 then
                warn("gameSearchModule.Init failed: " .. tostring(result4));
            end;
        end;

        if u3 and u3.Init then
            local success4, result4 = pcall(u3.Init);

            if not success4 then
                warn("lobbyInfoModule.Init failed: " .. tostring(result4));
            end;
        end;

        setupExitButton(u19);
        setupExitButton(u16);
        setupExitButton(u15);
        setupExitButton(u14);

        if u17 then
            u17.Activated:Connect(function() -- Line: 156
                -- upvalues: bossQueueGui (ref), u13 (ref), u11 (ref), u12 (ref)
                if bossQueueGui:FindFirstChild("chooseBoss") then
                    bossQueueGui.chooseBoss.Visible = true;
                end;

                if u13 then
                    u13.Visible = false;
                end;

                if u11 then
                    u11.Visible = false;
                end;

                if u12 then
                    u12.Visible = false;
                end;

                if bossQueueGui.lobbyInfo and bossQueueGui.lobbyInfo:FindFirstChild("startBackground") then
                    bossQueueGui.lobbyInfo.startBackground.Visible = false;
                end;
            end);
            u17.MouseEnter:Connect(function() -- Line: 166
                -- upvalues: u17 (ref)
                u17.TextColor3 = Color3.fromRGB(255, 190, 38);
                local main = u17:FindFirstChild("main");

                if main then
                    main.ImageColor3 = Color3.fromRGB(97, 57, 24);
                end;
            end);
            u17.MouseLeave:Connect(function() -- Line: 171
                -- upvalues: u17 (ref)
                u17.TextColor3 = Color3.fromRGB(255, 255, 255);
                local main = u17:FindFirstChild("main");

                if main then
                    main.ImageColor3 = Color3.fromRGB(190, 111, 47);
                end;
            end);
        end;

        if u18 then
            u18.Activated:Connect(function() -- Line: 179
                -- upvalues: u13 (ref), u11 (ref), u12 (ref)
                if u13 then
                    u13.Visible = false;
                end;

                if u11 then
                    u11.Visible = true;
                end;

                if u12 then
                    u12.Visible = false;
                end;
            end);
            u18.MouseEnter:Connect(function() -- Line: 185
                -- upvalues: u18 (ref)
                u18.TextColor3 = Color3.fromRGB(0, 255, 0);
                local main = u18:FindFirstChild("main");

                if main then
                    main.ImageColor3 = Color3.fromRGB(91, 120, 54);
                end;
            end);
            u18.MouseLeave:Connect(function() -- Line: 190
                -- upvalues: u18 (ref)
                u18.TextColor3 = Color3.fromRGB(255, 255, 255);
                local main = u18:FindFirstChild("main");

                if main then
                    main.ImageColor3 = Color3.fromRGB(158, 207, 93);
                end;
            end);
        end;

        UserInputService.InputBegan:Connect(function(p22, p23) -- Line: 197
            -- upvalues: u20 (ref)
            if p23 then
                return;
            end;

            if p22.KeyCode == Enum.KeyCode.ButtonB then
                u20.Close();
            end;
        end);
    end;

    function u20.Open() -- Line: 205
        -- upvalues: bossQueueGui (copy), inLobby (copy), u13 (copy), u12 (copy), u1 (ref)
        if bossQueueGui.Enabled then
            return;
        end;

        local v24 = inLobby();

        if v24 == "dungeon" then
            return;
        end;

        if v24 == "raid" then
            if u13 then
                u13.Visible = false;
            end;

            if u12 then
                u12.Visible = true;
            end;
        end;

        if u1 and u1.GetKeys then
            task.spawn(u1.GetKeys);
        end;

        bossQueueGui.Enabled = true;
    end;

    function u20.Close() -- Line: 225
        -- upvalues: bossQueueGui (copy), u13 (copy), u11 (copy), u12 (copy), u10 (copy)
        bossQueueGui.Enabled = false;

        if u13 then
            u13.Visible = true;
        end;

        if u11 then
            u11.Visible = false;
        end;

        if u12 then
            u12.Visible = false;
        end;

        if u10 then
            u10.Visible = false;
        end;
    end;

    u20.Init();

    return u20;
end;

warn("One or more critical bossQueue frames missing - UI may not function");