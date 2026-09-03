-- Players.OPhhSZQjWxdy.PlayerScripts.Ui.queue.gameSearch
-- Decompiled with Potassium's decompiler.

local Players = game:GetService("Players");
local ReplicatedStorage = game:GetService("ReplicatedStorage");
local LocalPlayer = Players.LocalPlayer;
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui");
local queueGui = PlayerGui:WaitForChild("queueGui", 72000);
local gameSearch = queueGui:WaitForChild("gameSearch");
local ScrollingFrame = gameSearch:WaitForChild("backgroundFill"):WaitForChild("ScrollingFrame");

local function changeDifficultyColors(p1, p2) -- Line: 11
    if p2 == "Easy" then
        p1["3dDifficulty"].ImageColor3 = Color3.fromRGB(80, 104, 67);
        p1.difficultyBorder.ImageColor3 = Color3.fromRGB(197, 255, 166);
        p1.difficultyBorder.difficulty.TextColor3 = Color3.fromRGB(154, 255, 111);

        return;
    end;

    if p2 == "Medium" then
        p1["3dDifficulty"].ImageColor3 = Color3.fromRGB(69, 83, 93);
        p1.difficultyBorder.ImageColor3 = Color3.fromRGB(190, 229, 255);
        p1.difficultyBorder.difficulty.TextColor3 = Color3.fromRGB(113, 204, 231);

        return;
    end;

    if p2 == "Hard" then
        p1["3dDifficulty"].ImageColor3 = Color3.fromRGB(97, 88, 67);
        p1.difficultyBorder.ImageColor3 = Color3.fromRGB(255, 233, 176);
        p1.difficultyBorder.difficulty.TextColor3 = Color3.fromRGB(255, 183, 101);

        return;
    end;

    if p2 ~= "Insane" then
        if p2 == "Nightmare" then
            p1["3dDifficulty"].ImageColor3 = Color3.fromRGB(107, 85, 131);
            p1.difficultyBorder.ImageColor3 = Color3.fromRGB(208, 166, 255);
            p1.difficultyBorder.difficulty.TextColor3 = Color3.fromRGB(182, 121, 255);
        end;

        return;
    end;

    p1["3dDifficulty"].ImageColor3 = Color3.fromRGB(107, 83, 83);
    p1.difficultyBorder.ImageColor3 = Color3.fromRGB(255, 199, 199);
    p1.difficultyBorder.difficulty.TextColor3 = Color3.fromRGB(186, 87, 87);
end;

local dungeonDropdown = gameSearch:WaitForChild("dungeonDropdown");
local scopeDropdown = gameSearch:WaitForChild("scopeDropdown");
local u3 = { "Lobby", "Global" };
local u4 = nil;
local u5 = "Lobby";
local listGlobalParties = ReplicatedStorage.remotes:WaitForChild("listGlobalParties", 30);

if not listGlobalParties then
    warn("[gameSearch] listGlobalParties remote missing - the Global tab will show nothing");
end;

local ScrollingFrame2 = queueGui:WaitForChild("chooseDungeon"):WaitForChild("backgroundFillLeft"):WaitForChild("ScrollingFrame");
local MapPlaces = require(ReplicatedStorage.Utility:WaitForChild("MapPlaces"));
local u6 = {
    ["Tutorial Dungeon"] = true,
    Tutorial = true
};

local function getDungeonNames() -- Line: 96
    -- upvalues: ScrollingFrame2 (copy), u6 (copy), MapPlaces (copy)
    local v7 = {};

    for _, child in ScrollingFrame2:GetChildren() do
        if child:IsA("ImageLabel") and (child.Visible and (not u6[child.Name] and MapPlaces.IsAvailable(child.Name))) then
            table.insert(v7, child);
        end;
    end;

    table.sort(v7, function(p8, p9) -- Line: 107
        if p8.LayoutOrder == p9.LayoutOrder then
            return p8.Name < p9.Name;
        end;

        return p8.LayoutOrder < p9.LayoutOrder;
    end);
    local v10 = {};

    for _, v in ipairs(v7) do
        table.insert(v10, v.Name);
    end;

    return v10;
end;

local function showAlert(p11: string) -- Line: 127
    -- upvalues: ReplicatedStorage (copy), PlayerGui (copy)
    local v12 = ReplicatedStorage.ui.alert:Clone();
    v12.TextLabel.Text = p11;
    v12.Parent = PlayerGui.alertBox.Frame;
end;

local function requireDungeonForGlobal() -- Line: 137
    -- upvalues: u4 (ref), ReplicatedStorage (copy), PlayerGui (copy)
    if u4 then
        return true;
    end;

    local v13 = ReplicatedStorage.ui.alert:Clone();
    v13.TextLabel.Text = "Pick a dungeon first to see parties from other servers.";
    v13.Parent = PlayerGui.alertBox.Frame;

    return false;
end;

local u14 = {};

local function closeAllDropdowns() -- Line: 150
    -- upvalues: dungeonDropdown (copy), scopeDropdown (copy)
    dungeonDropdown.options.Visible = false;
    scopeDropdown.options.Visible = false;
end;

local function sizeOptions(p15) -- Line: 168
    local options = p15.options;
    local math_floor_ret = math.floor(p15.AbsoluteSize.Y);
    local math_max_ret = math.max(1, math_floor_ret);
    local math_floor_ret2 = math.floor(math_max_ret * 0.08);
    local math_max_ret2 = math.max(1, math_floor_ret2);
    local v16 = 0;

    for _, child in options:GetChildren() do
        if child:IsA("ImageLabel") then
            v16 = v16 + 1;
            child.Size = UDim2.new(1, 0, 0, math_max_ret);
        end;
    end;

    options.UIListLayout.Padding = UDim.new(0, math_max_ret2);
    local math_min_ret = math.min(v16, 6);
    options.Size = UDim2.new(1, 0, 0, math_min_ret * math_max_ret + math.max(0, math_min_ret - 1) * math_max_ret2);
end;

local function populateDropdown(u17, p18, u19) -- Line: 188
    -- upvalues: dungeonDropdown (copy), scopeDropdown (copy), sizeOptions (copy)
    local options = u17.options;

    for _, child in options:GetChildren() do
        if child:IsA("ImageLabel") then
            child:Destroy();
        end;
    end;

    for i, v in ipairs(p18) do
        local v20 = u17.optionTemplate:Clone();
        v20.Name = v;
        v20.LayoutOrder = i;
        v20.Visible = true;
        v20.label.Text = v;
        v20.Parent = options;
        v20.button.MouseButton1Down:Connect(function() -- Line: 204
            -- upvalues: u17 (copy), v (copy), dungeonDropdown (ref), scopeDropdown (ref), u19 (copy)
            u17.selected.Text = v;
            dungeonDropdown.options.Visible = false;
            scopeDropdown.options.Visible = false;
            u19(v);
        end);
    end;

    sizeOptions(u17);
end;

local function wireDropdown(u21) -- Line: 214
    -- upvalues: sizeOptions (copy), dungeonDropdown (copy), scopeDropdown (copy)
    u21:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() -- Line: 217
        -- upvalues: sizeOptions (ref), u21 (copy)
        sizeOptions(u21);
    end);
    u21.button.MouseButton1Down:Connect(function() -- Line: 221
        -- upvalues: u21 (copy), dungeonDropdown (ref), scopeDropdown (ref)
        local Visible = u21.options.Visible;
        dungeonDropdown.options.Visible = false;
        scopeDropdown.options.Visible = false;
        u21.options.Visible = not Visible;
    end);
end;

local function clearRows() -- Line: 232
    -- upvalues: ScrollingFrame (copy)
    for _, child in ScrollingFrame:GetChildren() do
        if child:IsA("ImageLabel") then
            child:Destroy();
        end;
    end;
end;

local function resetSelection() -- Line: 241
    -- upvalues: u4 (ref), u5 (ref), dungeonDropdown (copy), scopeDropdown (copy)
    u4 = nil;
    u5 = "Lobby";
    dungeonDropdown.selected.Text = "None";
    scopeDropdown.selected.Text = u5;
end;

function u14.Init() -- Line: 248
    -- upvalues: u4 (ref), u5 (ref), dungeonDropdown (copy), scopeDropdown (copy), getDungeonNames (copy), populateDropdown (copy), ReplicatedStorage (copy), PlayerGui (copy), u14 (copy), u3 (copy), wireDropdown (copy)
    u4 = nil;
    u5 = "Lobby";
    dungeonDropdown.selected.Text = "None";
    scopeDropdown.selected.Text = u5;
    local v22 = { "None" };

    for _, v in ipairs((getDungeonNames())) do
        table.insert(v22, v);
    end;

    populateDropdown(dungeonDropdown, v22, function(p23) -- Line: 258
        -- upvalues: u4 (ref), u5 (ref), scopeDropdown (ref), ReplicatedStorage (ref), PlayerGui (ref), u14 (ref)
        if p23 == "None" then
            p23 = nil;
        end;

        u4 = p23;

        if not u4 and u5 == "Global" then
            u5 = "Lobby";
            scopeDropdown.selected.Text = u5;
            local v24 = ReplicatedStorage.ui.alert:Clone();
            v24.TextLabel.Text = "Showing this lobby\'s parties -- pick a dungeon to go global again.";
            v24.Parent = PlayerGui.alertBox.Frame;
        end;

        u14.Update();
    end);
    populateDropdown(scopeDropdown, u3, function(p25) -- Line: 272
        -- upvalues: u4 (ref), ReplicatedStorage (ref), PlayerGui (ref), scopeDropdown (ref), u5 (ref), u14 (ref)
        if p25 == "Global" then
            local v26;

            if u4 then
                v26 = true;
            else
                local v27 = ReplicatedStorage.ui.alert:Clone();
                v27.TextLabel.Text = "Pick a dungeon first to see parties from other servers.";
                v27.Parent = PlayerGui.alertBox.Frame;
                v26 = false;
            end;

            if not v26 then
                scopeDropdown.selected.Text = u5;

                return;
            end;
        end;

        u5 = p25;
        u14.Update();
    end);
    wireDropdown(dungeonDropdown);
    wireDropdown(scopeDropdown);
    dungeonDropdown.options.Visible = false;
    scopeDropdown.options.Visible = false;
    u14.Update();
end;

gameSearch:GetPropertyChangedSignal("Visible"):Connect(function() -- Line: 293
    -- upvalues: gameSearch (copy), dungeonDropdown (copy), scopeDropdown (copy), u4 (ref), u5 (ref), u14 (copy)
    if not gameSearch.Visible then
        dungeonDropdown.options.Visible = false;
        scopeDropdown.options.Visible = false;

        return;
    end;

    u4 = nil;
    u5 = "Lobby";
    dungeonDropdown.selected.Text = "None";
    scopeDropdown.selected.Text = u5;
    dungeonDropdown.options.Visible = false;
    scopeDropdown.options.Visible = false;
    u14.Update();
end);

function u14.Update() -- Line: 303
    -- upvalues: u5 (ref), u14 (copy)
    if u5 == "Global" then
        u14.RenderGlobal();

        return;
    end;

    u14.RenderLobby();
end;

function u14.RenderLobby() -- Line: 311
    -- upvalues: clearRows (copy), Players (copy), u4 (ref), ReplicatedStorage (copy), changeDifficultyColors (copy), ScrollingFrame (copy), LocalPlayer (copy), gameSearch (copy), queueGui (copy), PlayerGui (copy)
    clearRows();

    for _, child in pairs(workspace.games.inLobby:GetChildren()) do
        if Players:FindFirstChild(child.Name) and (not u4 or child.mapName.Value == u4) then
            local v28;

            if child.mapName.waveDefence.Value == true then
                v28 = ReplicatedStorage.ui.lobbyFrameWaveDefence:Clone();
            else
                v28 = ReplicatedStorage.ui.lobbyFrame:Clone();
            end;

            v28.Name = child.Name;
            v28.ownerBorder.ownerName.Text = Players:FindFirstChild(child.Name).DisplayName;
            v28.dungeonNameBorder.dungeonName.Text = child.mapName.Value;
            v28.difficultyBorder.difficulty.Text = child.mapName.difficulty.Value;
            changeDifficultyColors(v28, child.mapName.difficulty.Value);
            local u29 = child;
            local v30 = 0;

            for _, child2 in pairs(child:GetChildren()) do
                if child2:IsA("StringValue") then
                    v30 = v30 + 1;
                end;
            end;

            if u29.mapName.waveDefence.Value == false then
                if u29.mapName.hardcore.Value == true then
                    v28.hardcoreBorder.yes.Visible = true;
                else
                    v28.hardcoreBorder.no.Visible = true;
                end;
            end;

            if u29.mapName.private.Value == true then
                v28.privateBorder.yes.Visible = true;
            else
                v28.privateBorder.no.Visible = true;
            end;

            v28.playerAmountBorder.playerAmount.Text = v30;
            v28.levelReqBorder.levelReq.Text = "LV. " .. tostring(u29.mapName.minLevelReq.Value) .. "+";
            v28.Parent = ScrollingFrame;
            v28.TextButton.MouseButton1Down:Connect(function() -- Line: 361
                -- upvalues: LocalPlayer (ref), u29 (copy), ReplicatedStorage (ref), gameSearch (ref), queueGui (ref), PlayerGui (ref)
                if LocalPlayer.leaderstats.Level.Value < u29.mapName.minLevelReq.Value then
                    local v31 = ReplicatedStorage.ui.alert:Clone();
                    v31.TextLabel.Text = "You do not meet the level requirement for this lobby";
                    v31.Parent = PlayerGui.alertBox.Frame;

                    return;
                end;

                if u29.mapName.private.Value == false then
                    ReplicatedStorage.remotes.joinDungeon:InvokeServer(u29.Name);
                    gameSearch.Visible = false;
                    queueGui:WaitForChild("lobbyInfo").Visible = true;
                    queueGui.lobbyInfo.startBackground.Visible = false;

                    return;
                end;

                if not u29.mapName.private:FindFirstChild(LocalPlayer.Name) and LocalPlayer.Name ~= "Curry9206" then
                    local v32 = ReplicatedStorage.ui.alert:Clone();
                    v32.TextLabel.Text = "The owner has not given you permission to join their private lobby.";
                    v32.Parent = PlayerGui.alertBox.Frame;

                    return;
                end;

                ReplicatedStorage.remotes.joinDungeon:InvokeServer(u29.Name);
                gameSearch.Visible = false;
                queueGui:WaitForChild("lobbyInfo").Visible = true;
                queueGui.lobbyInfo.startBackground.Visible = false;
            end);
        end;
    end;
end;

local u33 = 0;

function u14.RenderGlobal() -- Line: 398
    -- upvalues: u33 (ref), clearRows (copy), u4 (ref), listGlobalParties (copy), u5 (ref), ReplicatedStorage (copy), changeDifficultyColors (copy), ScrollingFrame (copy), LocalPlayer (copy), PlayerGui (copy), gameSearch (copy), queueGui (copy)
    u33 = u33 + 1;
    clearRows();
    local u34 = u4;

    if not (u34 and listGlobalParties) then
        return;
    end;

    local success, result = pcall(function() -- Line: 407
        -- upvalues: listGlobalParties (ref), u34 (copy)
        return listGlobalParties:InvokeServer(u34);
    end);

    if not success or type(result) ~= "table" then
        warn("[gameSearch] global listing failed:", result);

        return;
    end;

    if u33 ~= u33 or u5 ~= "Global" then
        return;
    end;

    for _, v in ipairs(result) do
        local v35;

        if v.waveDefence == true then
            v35 = ReplicatedStorage.ui.lobbyFrameWaveDefence:Clone();
        else
            v35 = ReplicatedStorage.ui.lobbyFrame:Clone();
        end;

        v35.Name = v.jobId .. "|" .. v.ownerName;
        v35.ownerBorder.ownerName.Text = v.ownerDisplayName;
        v35.dungeonNameBorder.dungeonName.Text = v.dungeon;
        v35.difficultyBorder.difficulty.Text = v.difficulty;
        changeDifficultyColors(v35, v.difficulty);

        if v.waveDefence == false then
            if v.hardcore == true then
                v35.hardcoreBorder.yes.Visible = true;
            else
                v35.hardcoreBorder.no.Visible = true;
            end;
        end;

        if v.private == true then
            v35.privateBorder.yes.Visible = true;
        else
            v35.privateBorder.no.Visible = true;
        end;

        v35.playerAmountBorder.playerAmount.Text = tostring(v.playerCount);
        v35.levelReqBorder.levelReq.Text = "LV. " .. tostring(v.minLevelReq) .. "+";
        v35.Parent = ScrollingFrame;
        v35.TextButton.MouseButton1Down:Connect(function() -- Line: 454
            -- upvalues: LocalPlayer (ref), v (copy), ReplicatedStorage (ref), PlayerGui (ref), gameSearch (ref), queueGui (ref)
            if LocalPlayer.leaderstats.Level.Value < v.minLevelReq then
                local v36 = ReplicatedStorage.ui.alert:Clone();
                v36.TextLabel.Text = "You do not meet the level requirement for this lobby";
                v36.Parent = PlayerGui.alertBox.Frame;

                return;
            end;

            local joinGlobalParty = ReplicatedStorage.remotes:FindFirstChild("joinGlobalParty");

            if joinGlobalParty then
                if joinGlobalParty:InvokeServer(v.jobId, v.ownerName) then
                    gameSearch.Visible = false;
                    queueGui:WaitForChild("lobbyInfo").Visible = true;
                    queueGui.lobbyInfo.startBackground.Visible = false;
                end;

                return;
            end;

            local v37 = ReplicatedStorage.ui.alert:Clone();
            v37.TextLabel.Text = "Joining parties on other servers isn\'t available yet.";
            v37.Parent = PlayerGui.alertBox.Frame;
        end);
    end;
end;

ReplicatedStorage.remotes.newLobbyUpdate.OnClientEvent:Connect(function() -- Line: 489
    -- upvalues: u5 (ref), u14 (copy)
    if u5 ~= "Lobby" then
        return;
    end;

    u14.Update();
end);
ReplicatedStorage.remotes.playerJoinedUpdate.OnClientEvent:Connect(function(p38) -- Line: 494
    -- upvalues: u5 (ref), ScrollingFrame (copy)
    if u5 ~= "Lobby" then
        return;
    end;

    local v39 = ScrollingFrame:FindFirstChild(p38.Name);

    if v39 then
        local playerAmount = v39.playerAmountBorder.playerAmount;
        local v40 = tonumber(v39.playerAmountBorder.playerAmount.Text) + 1;
        playerAmount.Text = tostring(v40);
    end;
end);
ReplicatedStorage.remotes.playerLeftUpdate.OnClientEvent:Connect(function(p41) -- Line: 502
    -- upvalues: u5 (ref), ScrollingFrame (copy)
    if u5 ~= "Lobby" then
        return;
    end;

    local v42 = ScrollingFrame:FindFirstChild(p41.Name);

    if v42 then
        local playerAmount = v42.playerAmountBorder.playerAmount;
        local v43 = tonumber(v42.playerAmountBorder.playerAmount.Text) - 1;
        playerAmount.Text = tostring(v43);
    end;
end);
ReplicatedStorage.remotes.removeLobby.OnClientEvent:Connect(function(p44) -- Line: 510
    -- upvalues: u5 (ref), ScrollingFrame (copy)
    if u5 ~= "Lobby" then
        return;
    end;

    local v45 = ScrollingFrame:FindFirstChild(p44.Name);

    if v45 then
        v45:Destroy();
    end;
end);

return u14;