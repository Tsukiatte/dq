-- Players.OPhhSZQjWxdy.PlayerScripts.Ui.queue.lobbyInfo
-- Decompiled with Potassium's decompiler.

local Players = game:GetService("Players");
local ReplicatedStorage = game:GetService("ReplicatedStorage");
local SoundService = game:GetService("SoundService");
local Utility = ReplicatedStorage:WaitForChild("Utility");
local AudioService = require(Utility:WaitForChild("AudioService"));
local LocalPlayer = Players.LocalPlayer;
local queueGui = LocalPlayer:WaitForChild("PlayerGui"):WaitForChild("queueGui", 72000);
local lobbyInfo = queueGui:WaitForChild("lobbyInfo");
local ScrollingFrame = lobbyInfo:WaitForChild("backgroundFill"):WaitForChild("ScrollingFrame");
local whitelist = lobbyInfo:WaitForChild("whitelist");
local selectWhitelist = lobbyInfo:WaitForChild("selectWhitelist");

local function findLobby(p1) -- Line: 18
    -- upvalues: LocalPlayer (copy)
    for _, child in pairs(workspace.games.inGame:GetChildren()) do
        local v2 = child;

        for _, child2 in pairs(child:GetChildren()) do
            if child2.Name == LocalPlayer.Name then
                return v2;
            end;
        end;
    end;

    for _, child in pairs(workspace.games.inLobby:GetChildren()) do
        local v3 = child;

        for _, child2 in pairs(child:GetChildren()) do
            if child2.Name == LocalPlayer.Name then
                return v3;
            end;
        end;
    end;

    return nil;
end;

ReplicatedStorage.remotes.removePlayer.OnClientEvent:Connect(function(p4) -- Line: 120
    -- upvalues: ScrollingFrame (copy)
    local v5 = ScrollingFrame:FindFirstChild(p4);

    if v5 then
        v5:Destroy();
    end;
end);
local HttpService = game:GetService("HttpService");

local function addMemberRow(p6, u7, p8, p9, p10, u11) -- Line: 131
    -- upvalues: ReplicatedStorage (copy), LocalPlayer (copy), lobbyInfo (copy), queueGui (copy), ScrollingFrame (copy)
    local v12 = ReplicatedStorage.ui.playerFrame:Clone();

    if u7 == LocalPlayer.Name then
        v12.kickPlayerButton.Text = "Leave";
        v12.kickPlayerButton.MouseButton1Down:Connect(function() -- Line: 136
            -- upvalues: lobbyInfo (ref), queueGui (ref), ReplicatedStorage (ref)
            lobbyInfo.Visible = false;
            queueGui:WaitForChild("gameSearch").Visible = true;
            ReplicatedStorage.remotes.leaveGame:FireServer();
        end);
    elseif LocalPlayer.Name == p6.Name then
        lobbyInfo.startBackground.Visible = true;
        v12.kickPlayerButton.Text = "Kick";
        v12.kickPlayerButton.MouseButton1Down:Connect(function() -- Line: 144
            -- upvalues: u11 (copy), ReplicatedStorage (ref), u7 (copy)
            if u11 then
                local kickGlobalMember = ReplicatedStorage.remotes:FindFirstChild("kickGlobalMember");

                if kickGlobalMember then
                    kickGlobalMember:FireServer(u7);
                end;
            else
                ReplicatedStorage.remotes.kickPlayer:FireServer(u7);
            end;
        end);
    elseif p10 then
        v12.kickPlayerButton.Text = "OWNER";
        v12.kickPlayerButton.mainBox.ImageColor3 = Color3.new(0.9725490196078431, 0.792156862745098, 0.36470588235294116);
        v12.kickPlayerButton.backgroundBox.ImageColor3 = Color3.new(0.5882352941176471, 0.47058823529411764, 0.23529411764705882);
        v12.kickPlayerButton.TextStrokeColor3 = Color3.new(0.43137254901960786, 0.35294117647058826, 0.14901960784313725);
    else
        v12.kickPlayerButton.Visible = false;
    end;

    v12.playerLevelBorder.playerLevel.Text = tostring(p9);
    v12.playerNameBorder.playerName.Text = p8;
    v12.Name = u7;
    v12.Parent = ScrollingFrame;
end;

ReplicatedStorage.remotes.populateLobby.OnClientEvent:Connect(function() -- Line: 173
    -- upvalues: findLobby (copy), LocalPlayer (copy), selectWhitelist (copy), whitelist (copy), ScrollingFrame (copy), HttpService (copy), addMemberRow (copy), Players (copy)
    local v13 = findLobby(LocalPlayer);

    if not v13 then
        return;
    end;

    selectWhitelist.Visible = false;
    whitelist.Visible = false;

    for _, child in ScrollingFrame:GetChildren() do
        if not child:IsA("UIListLayout") then
            child:Destroy();
        end;
    end;

    local v14 = nil;
    local Attribute = v13:GetAttribute("Roster");
    local v15;

    if type(Attribute) == "string" then
        local v16;
        v16, v15 = pcall(HttpService.JSONDecode, HttpService, Attribute);

        if v16 then
            if type(v15) ~= "table" then
                v15 = v14;
            end;
        else
            v15 = v14;
        end;
    else
        v15 = v14;
    end;

    if v15 then
        for _, v in v15 do
            addMemberRow(v13, v.n, v.d, v.l, v.o == true, v.r == true);
        end;
    else
        for _, child in v13:GetChildren() do
            if child:IsA("StringValue") and child.Name ~= "mapName" then
                local v17 = Players:FindFirstChild(child.Name);

                if v17 then
                    addMemberRow(v13, child.Name, v17.DisplayName, v17.leaderstats.Level.Value, child.Name == v13.Name, false);
                end;
            end;
        end;
    end;

    if LocalPlayer.Name == v13.Name and v13.mapName.private.Value == true then
        whitelist.Visible = true;
    end;
end);
ReplicatedStorage.remotes.clearLobby.OnClientEvent:Connect(function() -- Line: 222
    -- upvalues: ScrollingFrame (copy), lobbyInfo (copy), queueGui (copy)
    for _, child in pairs(ScrollingFrame:GetChildren()) do
        if not child:IsA("UIListLayout") then
            child:Destroy();
        end;
    end;

    lobbyInfo.Visible = false;
    queueGui:WaitForChild("gameSearch").Visible = true;
end);
ReplicatedStorage.remotes.addPlayerToLobby.OnClientEvent:Connect(function(p18) -- Line: 232
    -- upvalues: LocalPlayer (copy), findLobby (copy), ReplicatedStorage (copy), Players (copy), ScrollingFrame (copy)
    print("player added to lobby: " .. p18);
    local v19 = p18 ~= LocalPlayer.Name and findLobby(LocalPlayer);

    if v19 then
        local u20 = ReplicatedStorage.ui.playerFrame:Clone();

        if v19.Name == LocalPlayer.Name then
            u20.kickPlayerButton.Text = "Kick";
            u20.kickPlayerButton.MouseButton1Down:Connect(function() -- Line: 240
                -- upvalues: ReplicatedStorage (ref), u20 (copy)
                ReplicatedStorage.remotes.kickPlayer:FireServer(u20.Name);
            end);
        else
            u20.kickPlayerButton.Visible = false;
        end;

        local playerLevel = u20.playerLevelBorder.playerLevel;
        local Value = Players:FindFirstChild(p18).leaderstats.Level.Value;
        playerLevel.Text = tostring(Value);
        u20.playerNameBorder.playerName.Text = Players:FindFirstChild(p18).DisplayName;
        u20.Name = p18;
        u20.Parent = ScrollingFrame;
    end;
end);
lobbyInfo.startBackground.startFrame.startButton.MouseButton1Click:Connect(function() -- Line: 254
    -- upvalues: ReplicatedStorage (copy), lobbyInfo (copy)
    ReplicatedStorage.remotes.startDungeon:FireServer();
    lobbyInfo.startBackground.Visible = false;
end);

return {
    Init = function() -- Line: 38, Name: Init
        -- upvalues: whitelist (copy), findLobby (copy), LocalPlayer (copy), selectWhitelist (copy), Players (copy), ReplicatedStorage (copy), AudioService (copy), SoundService (copy), lobbyInfo (copy)
        whitelist.buttonFrame.button.Activated:Connect(function() -- Line: 39
            -- upvalues: findLobby (ref), LocalPlayer (ref), selectWhitelist (ref), Players (ref), ReplicatedStorage (ref), AudioService (ref), SoundService (ref)
            local v21 = findLobby(LocalPlayer);

            if v21 then
                if selectWhitelist.Visible == false then
                    for _, child in pairs(selectWhitelist.ScrollingFrame:GetChildren()) do
                        if child:IsA("ImageLabel") then
                            child:Destroy();
                        end;
                    end;

                    for _, v in pairs(Players:GetPlayers()) do
                        if v.Name ~= LocalPlayer.Name then
                            local u22 = ReplicatedStorage.ui.whitelistPlayerFrame:Clone();

                            if v21.mapName.private:FindFirstChild(v.Name) then
                                u22.Name = v.Name;
                                u22.whitelisted.Value = true;
                                u22.TextButton.TextColor3 = Color3.fromRGB(0, 255, 0);
                                u22.ImageColor3 = Color3.fromRGB(116, 255, 101);
                                u22.TextButton.Text = v.DisplayName;
                            else
                                u22.Name = v.Name;
                                u22.whitelisted.Value = false;
                                u22.TextButton.Text = v.DisplayName;
                            end;

                            u22.TextButton.Activated:Connect(function() -- Line: 62
                                -- upvalues: u22 (copy), ReplicatedStorage (ref), v (copy), AudioService (ref), SoundService (ref)
                                if u22.whitelisted.Value == true then
                                    u22.whitelisted.Value = false;
                                    u22.TextButton.TextColor3 = Color3.fromRGB(255, 255, 255);
                                    u22.ImageColor3 = Color3.fromRGB(255, 255, 255);
                                    ReplicatedStorage.remotes.removePlayerFromWhitelist:FireServer(v.Name);
                                else
                                    u22.whitelisted.Value = true;
                                    u22.TextButton.TextColor3 = Color3.fromRGB(0, 255, 0);
                                    u22.ImageColor3 = Color3.fromRGB(116, 255, 101);
                                    ReplicatedStorage.remotes.addPlayerToWhitelist:FireServer(v.Name);
                                end;

                                AudioService.Play("clickSound", SoundService);
                            end);
                            u22.Parent = selectWhitelist.ScrollingFrame;
                        end;
                    end;

                    selectWhitelist.Visible = true;
                else
                    for _, child in pairs(selectWhitelist.ScrollingFrame:GetChildren()) do
                        if child:IsA("ImageLabel") then
                            child:Destroy();
                        end;
                    end;

                    selectWhitelist.Visible = false;
                end;
            end;

            AudioService.Play("clickSound", SoundService);
        end);
        whitelist.buttonFrame.button.MouseEnter:Connect(function(p23, p24) -- Line: 92
            -- upvalues: whitelist (ref)
            whitelist.buttonFrame.TextLabel.TextColor3 = Color3.fromRGB(226, 152, 255);
            whitelist.buttonFrame.ImageColor3 = Color3.fromRGB(96, 96, 144);
        end);
        whitelist.buttonFrame.button.MouseLeave:Connect(function(p25, p26) -- Line: 97
            -- upvalues: whitelist (ref)
            whitelist.buttonFrame.TextLabel.TextColor3 = Color3.fromRGB(255, 255, 255);
            whitelist.buttonFrame.ImageColor3 = Color3.fromRGB(170, 170, 255);
        end);
        lobbyInfo.startBackground.startFrame.startButton.MouseButton1Click:Connect(function() -- Line: 102
            -- upvalues: ReplicatedStorage (ref), lobbyInfo (ref)
            ReplicatedStorage.remotes.startDungeon:FireServer();
            lobbyInfo.startBackground.Visible = false;
        end);
        lobbyInfo.startBackground.startFrame.startButton.MouseEnter:Connect(function(p27, p28) -- Line: 107
            -- upvalues: lobbyInfo (ref)
            lobbyInfo.startBackground.startFrame.startButton.TextColor3 = Color3.fromRGB(255, 255, 0);
            lobbyInfo.startBackground.startFrame.ImageColor3 = Color3.fromRGB(136, 121, 59);
        end);
        lobbyInfo.startBackground.startFrame.startButton.MouseLeave:Connect(function(p29, p30) -- Line: 112
            -- upvalues: lobbyInfo (ref)
            lobbyInfo.startBackground.startFrame.startButton.TextColor3 = Color3.fromRGB(255, 255, 255);
            lobbyInfo.startBackground.startFrame.ImageColor3 = Color3.fromRGB(255, 242, 88);
        end);
    end
};