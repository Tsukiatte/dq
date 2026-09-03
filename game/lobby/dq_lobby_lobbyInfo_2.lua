-- Players.OPhhSZQjWxdy.PlayerScripts.Ui.bossQueue.lobbyInfo
-- Decompiled with Potassium's decompiler.

local Players = game:GetService("Players");
local SoundService = game:GetService("SoundService");
local Utility = game:GetService("ReplicatedStorage"):WaitForChild("Utility");
local AudioService = require(Utility:WaitForChild("AudioService"));
local LocalPlayer = Players.LocalPlayer;
local bossQueueGui = LocalPlayer:WaitForChild("PlayerGui"):WaitForChild("bossQueueGui", 24000);
local lobbyInfo = bossQueueGui:WaitForChild("lobbyInfo");
local ScrollingFrame = lobbyInfo:WaitForChild("backgroundFill"):WaitForChild("ScrollingFrame");
local selectWhitelist = lobbyInfo:WaitForChild("selectWhitelist");
local whitelist = lobbyInfo:WaitForChild("whitelist");

local function findBossLobby(p1) -- Line: 18
    for _, child in pairs(workspace.bossLobbies:GetChildren()) do
        local v2 = child;

        for _, child2 in pairs(child.players:GetChildren()) do
            if p1.Name == child2.Name then
                return v2;
            end;
        end;
    end;

    return nil;
end;

local HttpService = game:GetService("HttpService");

local function addMemberRow(p3, u4, p5, p6, p7, u8) -- Line: 32
    -- upvalues: LocalPlayer (copy), lobbyInfo (copy), ScrollingFrame (copy)
    local v9 = game.ReplicatedStorage.ui.playerFrame:Clone();

    if u4 == LocalPlayer.Name then
        v9.kickPlayerButton.Text = "Leave";
        v9.kickPlayerButton.MouseButton1Down:Connect(function() -- Line: 37
            game.ReplicatedStorage.remotes.playerLeaveBossLobby:FireServer();
        end);
    elseif LocalPlayer.Name == p3.Name then
        lobbyInfo.startBackground.Visible = true;
        v9.kickPlayerButton.Text = "Kick";
        v9.kickPlayerButton.MouseButton1Down:Connect(function() -- Line: 43
            -- upvalues: u8 (copy), u4 (copy)
            if u8 then
                local kickGlobalMember = game.ReplicatedStorage.remotes:FindFirstChild("kickGlobalMember");

                if kickGlobalMember then
                    kickGlobalMember:FireServer(u4);
                end;
            else
                game.ReplicatedStorage.remotes.kickPlayerFromBossLobby:FireServer(u4);
            end;
        end);
    elseif p7 then
        v9.kickPlayerButton.Text = "OWNER";
        v9.kickPlayerButton.mainBox.ImageColor3 = Color3.new(0.9725490196078431, 0.792156862745098, 0.36470588235294116);
        v9.kickPlayerButton.backgroundBox.ImageColor3 = Color3.new(0.5882352941176471, 0.47058823529411764, 0.23529411764705882);
        v9.kickPlayerButton.TextStrokeColor3 = Color3.new(0.43137254901960786, 0.35294117647058826, 0.14901960784313725);
    else
        v9.kickPlayerButton.Visible = false;
    end;

    v9.playerLevelBorder.playerLevel.Text = tostring(p6);
    v9.playerNameBorder.playerName.Text = p5;
    v9.Name = u4;
    v9.Parent = ScrollingFrame;
end;

local function clearRows() -- Line: 72
    -- upvalues: ScrollingFrame (copy)
    for _, child in ScrollingFrame:GetChildren() do
        if child:IsA("ImageLabel") then
            child:Destroy();
        end;
    end;
end;

local function renderLobby(p10) -- Line: 83
    -- upvalues: clearRows (copy), HttpService (copy), addMemberRow (copy), Players (copy)
    clearRows();
    local v11 = nil;
    local Attribute = p10:GetAttribute("Roster");
    local v12;

    if type(Attribute) == "string" then
        local v13;
        v13, v12 = pcall(HttpService.JSONDecode, HttpService, Attribute);

        if v13 then
            if type(v12) ~= "table" then
                v12 = v11;
            end;
        else
            v12 = v11;
        end;
    else
        v12 = v11;
    end;

    if v12 then
        for _, v in v12 do
            addMemberRow(p10, v.n, v.d, v.l, v.o == true, v.r == true);
        end;

        return;
    end;

    for _, child in p10.players:GetChildren() do
        local v14 = Players:FindFirstChild(child.Name);

        if v14 then
            addMemberRow(p10, child.Name, v14.DisplayName, v14.leaderstats.Level.Value, child.Name == p10.Name, false);
        end;
    end;
end;

local u15 = {};

local function disconnectAll() -- Line: 116
    -- upvalues: u15 (copy)
    for _, v in u15 do
        v:Disconnect();
    end;

    table.clear(u15);
end;

local function joinLobby() -- Line: 124
    -- upvalues: findBossLobby (copy), LocalPlayer (copy), u15 (copy), lobbyInfo (copy), whitelist (copy), renderLobby (copy), bossQueueGui (copy), clearRows (copy)
    local u16 = findBossLobby(LocalPlayer);

    if not u16 then
        return;
    end;

    for _, v in u15 do
        v:Disconnect();
    end;

    table.clear(u15);

    if u16.Name == LocalPlayer.Name then
        lobbyInfo.startBackground.Visible = true;

        if u16.private.Value == true then
            whitelist.Visible = true;
        end;
    end;

    renderLobby(u16);
    table.insert(u15, u16.players.ChildAdded:Connect(function() -- Line: 139
        -- upvalues: renderLobby (ref), u16 (copy)
        renderLobby(u16);
    end));
    table.insert(u15, u16.players.ChildRemoved:Connect(function(p17) -- Line: 143
        -- upvalues: LocalPlayer (ref), u15 (ref), lobbyInfo (ref), bossQueueGui (ref), clearRows (ref), renderLobby (ref), u16 (copy)
        if p17.Name ~= LocalPlayer.Name then
            renderLobby(u16);

            return;
        end;

        for _, v in u15 do
            v:Disconnect();
        end;

        table.clear(u15);
        lobbyInfo.Visible = false;
        bossQueueGui:WaitForChild("gameSearch").Visible = true;
        clearRows();
    end));
    local AttributeChangedSignal = u16:GetAttributeChangedSignal("Roster");
    table.insert(u15, AttributeChangedSignal:Connect(function() -- Line: 156
        -- upvalues: renderLobby (ref), u16 (copy)
        renderLobby(u16);
    end));
end;

game.ReplicatedStorage.remotes.removePlayer.OnClientEvent:Connect(function(p18) -- Line: 257
    -- upvalues: ScrollingFrame (copy)
    local v19 = ScrollingFrame:FindFirstChild(p18);

    if v19 then
        v19:Destroy();
    end;
end);
game.ReplicatedStorage.remotes.showOnClientPlayerJoinedBossLobby.OnClientEvent:Connect(joinLobby);

return {
    Init = function() -- Line: 163, Name: Init
        -- upvalues: findBossLobby (copy), LocalPlayer (copy), selectWhitelist (copy), whitelist (copy), joinLobby (copy), lobbyInfo (copy), AudioService (copy), SoundService (copy)
        if findBossLobby(LocalPlayer) then
            selectWhitelist.Visible = false;
            whitelist.Visible = false;
            joinLobby();
        end;

        lobbyInfo.startBackground.startFrame.startButton.MouseButton1Click:Connect(function() -- Line: 173
            -- upvalues: lobbyInfo (ref)
            game.ReplicatedStorage.remotes.startDungeon:FireServer();
            lobbyInfo.startBackground.Visible = false;
        end);
        whitelist.buttonFrame.button.Activated:Connect(function() -- Line: 178
            -- upvalues: findBossLobby (ref), LocalPlayer (ref), selectWhitelist (ref), AudioService (ref), SoundService (ref)
            local v20 = findBossLobby(LocalPlayer);

            if v20 then
                if selectWhitelist.Visible == false then
                    for _, child in pairs(selectWhitelist.ScrollingFrame:GetChildren()) do
                        if child:IsA("ImageLabel") then
                            child:Destroy();
                        end;
                    end;

                    for _, v in pairs(game.Players:GetPlayers()) do
                        if v.Name ~= LocalPlayer.Name then
                            local u21 = game.ReplicatedStorage.ui.whitelistPlayerFrame:Clone();

                            if v20.private:FindFirstChild(v.Name) then
                                u21.Name = v.Name;
                                u21.whitelisted.Value = true;
                                u21.TextButton.TextColor3 = Color3.fromRGB(0, 255, 0);
                                u21.ImageColor3 = Color3.fromRGB(116, 255, 101);
                                u21.TextButton.Text = v.DisplayName;
                            else
                                u21.Name = v.Name;
                                u21.whitelisted.Value = false;
                                u21.TextButton.Text = v.DisplayName;
                            end;

                            u21.TextButton.Activated:Connect(function() -- Line: 202
                                -- upvalues: u21 (copy), v (copy), AudioService (ref), SoundService (ref)
                                if u21.whitelisted.Value == true then
                                    u21.whitelisted.Value = false;
                                    u21.TextButton.TextColor3 = Color3.fromRGB(255, 255, 255);
                                    u21.ImageColor3 = Color3.fromRGB(255, 255, 255);
                                    game.ReplicatedStorage.remotes.removePlayerFromBossWhitelist:FireServer(v.Name);
                                else
                                    u21.whitelisted.Value = true;
                                    u21.TextButton.TextColor3 = Color3.fromRGB(0, 255, 0);
                                    u21.ImageColor3 = Color3.fromRGB(116, 255, 101);
                                    game.ReplicatedStorage.remotes.addPlayerToBossWhitelist:FireServer(v.Name);
                                end;

                                AudioService.Play("clickSound", SoundService);
                            end);
                            u21.Parent = selectWhitelist.ScrollingFrame;
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
        whitelist.buttonFrame.button.MouseEnter:Connect(function(p22, p23) -- Line: 233
            -- upvalues: whitelist (ref)
            whitelist.buttonFrame.TextLabel.TextColor3 = Color3.fromRGB(226, 152, 255);
            whitelist.buttonFrame.ImageColor3 = Color3.fromRGB(96, 96, 144);
        end);
        whitelist.buttonFrame.button.MouseLeave:Connect(function(p24, p25) -- Line: 237
            -- upvalues: whitelist (ref)
            whitelist.buttonFrame.TextLabel.TextColor3 = Color3.fromRGB(255, 255, 255);
            whitelist.buttonFrame.ImageColor3 = Color3.fromRGB(170, 170, 255);
        end);
        lobbyInfo.startBackground.startFrame.startButton.MouseEnter:Connect(function(p26, p27) -- Line: 241
            -- upvalues: lobbyInfo (ref)
            lobbyInfo.startBackground.startFrame.startButton.TextColor3 = Color3.fromRGB(255, 255, 0);
            lobbyInfo.startBackground.startFrame.ImageColor3 = Color3.fromRGB(136, 121, 59);
        end);
        lobbyInfo.startBackground.startFrame.startButton.MouseLeave:Connect(function(p28, p29) -- Line: 245
            -- upvalues: lobbyInfo (ref)
            lobbyInfo.startBackground.startFrame.startButton.TextColor3 = Color3.fromRGB(255, 255, 255);
            lobbyInfo.startBackground.startFrame.ImageColor3 = Color3.fromRGB(255, 242, 88);
        end);
        lobbyInfo.startBackground.startFrame.startButton.Activated:Connect(function() -- Line: 251
            -- upvalues: lobbyInfo (ref)
            game.ReplicatedStorage.remotes.startBossRaid:FireServer();
            lobbyInfo.startBackground.Visible = false;
        end);
    end
};