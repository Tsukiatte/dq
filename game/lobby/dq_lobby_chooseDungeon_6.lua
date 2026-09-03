-- Players.OPhhSZQjWxdy.PlayerScripts.Ui.queue.chooseDungeon
-- Decompiled with Potassium's decompiler.

local Players = game:GetService("Players");
local ReplicatedStorage = game:GetService("ReplicatedStorage");
local SoundService = game:GetService("SoundService");
local Utility = ReplicatedStorage:WaitForChild("Utility");
local AudioService = require(Utility:WaitForChild("AudioService"));
local PlaceManager = require(Utility:WaitForChild("PlaceManager"));
local MapPlaces = require(Utility:WaitForChild("MapPlaces"));
local modules = ReplicatedStorage:WaitForChild("modules");
local ChinaPolicyService = require(modules:WaitForChild("ChinaPolicyService"));
local queueGui = Players.LocalPlayer:WaitForChild("PlayerGui"):WaitForChild("queueGui", 72000);
local chooseDungeon = queueGui:WaitForChild("chooseDungeon");
local private = chooseDungeon:WaitForChild("private");
local privateInner = private:WaitForChild("Frame"):WaitForChild("privateInner");
local backgroundFillLeft = chooseDungeon:WaitForChild("backgroundFillLeft");
local ScrollingFrame = backgroundFillLeft:WaitForChild("ScrollingFrame");
local waveDefenceTab = backgroundFillLeft:WaitForChild("waveDefenceTab");
local backgroundFillMiddle = chooseDungeon:WaitForChild("backgroundFillMiddle");
local dungeonName = backgroundFillMiddle:WaitForChild("dungeonName");
local recommendedLevel = backgroundFillMiddle:WaitForChild("recommendedLevel");
local TextButton = backgroundFillMiddle:WaitForChild("startMain"):WaitForChild("TextButton");
local backgroundFillRight = chooseDungeon:WaitForChild("backgroundFillRight");
local hardcoreSection = backgroundFillRight:WaitForChild("hardcoreSection");
local Frame = chooseDungeon:WaitForChild("levelReq"):WaitForChild("Frame");
local leftArrow = Frame:WaitForChild("leftArrow");
local rightArrow = Frame:WaitForChild("rightArrow");
local TextBox = Frame:WaitForChild("TextBox");

local function makeUnselected(p1) -- Line: 35
    p1.inner.ImageColor3 = Color3.fromRGB(65, 65, 65);
    p1.inner.background.ImageColor3 = Color3.fromRGB(38, 38, 38);
    p1.title.TextColor3 = Color3.fromRGB(255, 255, 255);
    p1.title.TextStrokeColor3 = Color3.fromRGB(29, 29, 29);
end;

local function makeSelected(p2) -- Line: 42
    p2.inner.ImageColor3 = Color3.fromRGB(94, 125, 166);
    p2.inner.background.ImageColor3 = Color3.fromRGB(34, 43, 121);
    p2.title.TextColor3 = Color3.fromRGB(255, 255, 255);
    p2.title.TextStrokeColor3 = Color3.fromRGB(0, 0, 127);
end;

local function isWaveDefence() -- Line: 49
    -- upvalues: waveDefenceTab (copy)
    return waveDefenceTab.toggled.Value;
end;

local function getHardcore() -- Line: 53
    -- upvalues: hardcoreSection (copy)
    return hardcoreSection.hardcore.chosenIndicatorBackground.chosenIndicatorFill.chosen.Visible;
end;

local function getPrivate() -- Line: 57
    -- upvalues: privateInner (copy)
    return privateInner.chosenIndicatorBackground.chosenIndicatorFill.chosen.Visible;
end;

local function getDungeonName() -- Line: 61
    -- upvalues: ScrollingFrame (copy)
    for _, child in pairs(ScrollingFrame:GetChildren()) do
        if child:IsA("ImageLabel") and child.chosenIndicatorBackground.chosenIndicatorFill.chosen.Visible == true then
            return child.Name;
        end;
    end;
end;

local function getDungeonDifficulty() -- Line: 71
    -- upvalues: chooseDungeon (copy)
    for _, child in pairs(chooseDungeon.backgroundFillRight:GetChildren()) do
        if child:IsA("ImageLabel") and (child:FindFirstChild("chosenIndicatorBackground") and child.chosenIndicatorBackground.chosenIndicatorFill.chosen.Visible == true) then
            return child.Name;
        end;
    end;
end;

local u3 = { "Easy", "Medium", "Hard", "Insane", "Nightmare" };

local function updateLevelAndName() -- Line: 82
    -- upvalues: getDungeonName (copy), getDungeonDifficulty (copy), backgroundFillRight (copy), recommendedLevel (copy), waveDefenceTab (copy), hardcoreSection (copy), backgroundFillMiddle (copy), dungeonName (copy), AudioService (copy), SoundService (copy), u3 (copy), updateLevelAndName (copy), PlaceManager (copy)
    local v4 = getDungeonName();

    if not v4 then
        return;
    end;

    local v5 = getDungeonDifficulty();

    if v4 == "Egg Island" then
        for _, child in pairs(backgroundFillRight:GetChildren()) do
            if child:IsA("ImageLabel") then
                if child.Name == "Easy" or child.Name == "Nightmare" then
                    child.Visible = true;
                else
                    child.Visible = false;
                end;
            end;
        end;

        if v5 ~= "Easy" and v5 ~= "Nightmare" then
            for _, child in pairs(backgroundFillRight:GetChildren()) do
                if child:IsA("ImageLabel") then
                    if child.Name == "Easy" or child.Name == "Nightmare" then
                        if child.Name == "Easy" then
                            child.chosenIndicatorBackground.chosenIndicatorFill.chosen.Visible = true;
                        else
                            child.chosenIndicatorBackground.chosenIndicatorFill.chosen.Visible = false;
                        end;

                        child.Visible = true;
                    else
                        child.Visible = false;
                        child.chosenIndicatorBackground.chosenIndicatorFill.chosen.Visible = false;
                    end;
                end;
            end;
        end;

        recommendedLevel.Text = "0";

        if waveDefenceTab.toggled.Value == true then
            hardcoreSection.Visible = false;
            backgroundFillMiddle.ImageLabel.Image = "rbxassetid://3185846655";
            dungeonName.Text = "Difficulty: " .. v4;
        else
            hardcoreSection.Visible = true;
            backgroundFillMiddle.ImageLabel.Image = "http://www.roblox.com/asset/?id=4752419543";
            dungeonName.Text = v4;
        end;

        hardcoreSection.Visible = false;
        AudioService.Play("clickSound", SoundService);
    elseif v4 == "Krampus" then
        for _, child in pairs(backgroundFillRight:GetChildren()) do
            if child:IsA("ImageLabel") then
                if child.Name == "Nightmare" then
                    child.Visible = true;
                else
                    child.Visible = false;
                end;
            end;
        end;

        if v5 ~= "Nightmare" then
            for _, child in pairs(backgroundFillRight:GetChildren()) do
                if child:IsA("ImageLabel") then
                    if child.Name == "Nightmare" then
                        if child.Name == "Nightmare" then
                            child.chosenIndicatorBackground.chosenIndicatorFill.chosen.Visible = true;
                        else
                            child.chosenIndicatorBackground.chosenIndicatorFill.chosen.Visible = false;
                        end;

                        child.Visible = true;
                    else
                        child.Visible = false;
                        child.chosenIndicatorBackground.chosenIndicatorFill.chosen.Visible = false;
                    end;
                end;
            end;
        end;

        recommendedLevel.Text = "195";

        if waveDefenceTab.toggled.Value == true then
            hardcoreSection.Visible = false;
            backgroundFillMiddle.ImageLabel.Image = "rbxassetid://3185846655";
            dungeonName.Text = "Difficulty: " .. v4;
        else
            hardcoreSection.Visible = true;
            backgroundFillMiddle.ImageLabel.Image = "rbxassetid://11917447197";
            dungeonName.Text = v4;
        end;

        hardcoreSection.Visible = false;
        AudioService.Play("clickSound", SoundService);
    else
        local v6 = game.ReplicatedStorage.remotes.getDungeonStats:InvokeServer(v4);

        if not v6 or typeof(v6) ~= "table" then
            warn("[ChooseDungeon] Failed to get dungeon stats for: " .. tostring(v4));

            return;
        end;

        for _, v in pairs(u3) do
            if v6[v] then
                backgroundFillRight[v].Visible = true;
            else
                backgroundFillRight[v].Visible = false;
                backgroundFillRight[v].chosenIndicatorBackground.chosenIndicatorFill.chosen.Visible = false;
            end;
        end;

        if not (v5 and v6[v5]) then
            for i, v in pairs(v6) do
                if typeof(v) == "table" and backgroundFillRight:FindFirstChild(i) then
                    backgroundFillRight[i].chosenIndicatorBackground.chosenIndicatorFill.chosen.Visible = true;
                    updateLevelAndName();

                    return;
                end;
            end;
        end;

        recommendedLevel.Text = v6[v5].levelReq;

        if waveDefenceTab.toggled.Value == true then
            hardcoreSection.Visible = false;
            backgroundFillMiddle.ImageLabel.Image = "rbxassetid://3185846655";
            dungeonName.Text = "Difficulty: " .. v4;
        else
            hardcoreSection.Visible = true;
            backgroundFillMiddle.ImageLabel.Image = v6.imageId;
            dungeonName.Text = v4;
        end;

        AudioService.Play("clickSound", SoundService);
    end;

    if PlaceManager.IsTutorial() then
        backgroundFillRight.Insane.Visible = false;
        backgroundFillRight.Nightmare.Visible = false;
        hardcoreSection.Visible = false;
        waveDefenceTab.Visible = false;
    end;
end;

return {
    Init = function() -- Line: 236, Name: Init
        -- upvalues: leftArrow (copy), rightArrow (copy), TextBox (copy), hardcoreSection (copy), AudioService (copy), SoundService (copy), private (copy), privateInner (copy), TextButton (copy), waveDefenceTab (copy), backgroundFillMiddle (copy), backgroundFillRight (copy), backgroundFillLeft (copy), chooseDungeon (copy), makeUnselected (copy), makeSelected (copy), updateLevelAndName (copy), getDungeonName (copy), getDungeonDifficulty (copy), queueGui (copy), ScrollingFrame (copy), ChinaPolicyService (copy), PlaceManager (copy), MapPlaces (copy)
        leftArrow.MouseEnter:Connect(function(p7, p8) -- Line: 237
            -- upvalues: leftArrow (ref)
            leftArrow.ImageColor3 = Color3.fromRGB(12, 254, 109);
        end);
        leftArrow.MouseLeave:Connect(function(p9, p10) -- Line: 240
            -- upvalues: leftArrow (ref)
            leftArrow.ImageColor3 = Color3.fromRGB(255, 255, 255);
        end);
        rightArrow.MouseEnter:Connect(function(p11, p12) -- Line: 243
            -- upvalues: rightArrow (ref)
            rightArrow.ImageColor3 = Color3.fromRGB(12, 254, 109);
        end);
        rightArrow.MouseLeave:Connect(function(p13, p14) -- Line: 246
            -- upvalues: rightArrow (ref)
            rightArrow.ImageColor3 = Color3.fromRGB(255, 255, 255);
        end);
        leftArrow.MouseButton1Down:Connect(function() -- Line: 250
            -- upvalues: TextBox (ref)
            local v15 = tonumber(TextBox.Text) - 1;

            if v15 >= 0 then
                TextBox.Text = tostring(v15);

                return;
            end;

            TextBox.Text = "0";
        end);
        rightArrow.MouseButton1Down:Connect(function() -- Line: 259
            -- upvalues: TextBox (ref)
            local v16 = tonumber(TextBox.Text) + 1;
            TextBox.Text = tostring(v16);
        end);
        TextBox:GetPropertyChangedSignal("Text"):Connect(function() -- Line: 264
            -- upvalues: TextBox (ref)
            local v17 = tonumber(TextBox.Text);

            if tonumber(v17) then
                if tonumber(v17) < 0 then
                    TextBox.Text = 0;
                end;
            else
                TextBox.Text = 0;
            end;
        end);
        hardcoreSection.hardcore.TextButton.Activated:Connect(function() -- Line: 276
            -- upvalues: hardcoreSection (ref), AudioService (ref), SoundService (ref)
            if hardcoreSection.hardcore.chosenIndicatorBackground.chosenIndicatorFill.chosen.Visible == true then
                hardcoreSection.hardcore.chosenIndicatorBackground.chosenIndicatorFill.chosen.Visible = false;
                hardcoreSection.hardcoreInfo.Visible = false;
            else
                hardcoreSection.hardcore.chosenIndicatorBackground.chosenIndicatorFill.chosen.Visible = true;
                hardcoreSection.hardcoreInfo.Visible = true;
            end;

            AudioService.Play("clickSound", SoundService);
        end);
        hardcoreSection.hardcore.TextButton.MouseEnter:Connect(function(p18, p19) -- Line: 286
            -- upvalues: hardcoreSection (ref)
            hardcoreSection.hardcore.chosenIndicatorBackground.ImageColor3 = Color3.fromRGB(63, 63, 63);
        end);
        hardcoreSection.hardcore.TextButton.MouseLeave:Connect(function(p20, p21) -- Line: 289
            -- upvalues: hardcoreSection (ref)
            hardcoreSection.hardcore.chosenIndicatorBackground.ImageColor3 = Color3.fromRGB(111, 111, 111);
        end);
        private:WaitForChild("Frame"):WaitForChild("button").Activated:Connect(function() -- Line: 294
            -- upvalues: privateInner (ref), AudioService (ref), SoundService (ref)
            if privateInner.chosenIndicatorBackground.chosenIndicatorFill.chosen.Visible == true then
                privateInner.chosenIndicatorBackground.chosenIndicatorFill.chosen.Visible = false;
                privateInner.privateInfo.Visible = false;
            else
                privateInner.chosenIndicatorBackground.chosenIndicatorFill.chosen.Visible = true;
                privateInner.privateInfo.Visible = true;
            end;

            AudioService.Play("clickSound", SoundService);
        end);
        private.Frame.button.MouseEnter:Connect(function(p22, p23) -- Line: 304
            -- upvalues: private (ref)
            private.Frame.privateInner.chosenIndicatorBackground.ImageColor3 = Color3.fromRGB(55, 55, 55);
        end);
        private.Frame.button.MouseLeave:Connect(function(p24, p25) -- Line: 307
            -- upvalues: private (ref)
            private.Frame.privateInner.chosenIndicatorBackground.ImageColor3 = Color3.fromRGB(85, 85, 85);
        end);
        TextButton.MouseEnter:Connect(function(p26, p27) -- Line: 311
            -- upvalues: TextButton (ref)
            TextButton.TextColor3 = Color3.fromRGB(255, 0, 0);
            TextButton.Parent.ImageColor3 = Color3.fromRGB(97, 25, 25);
        end);
        TextButton.MouseLeave:Connect(function(p28, p29) -- Line: 315
            -- upvalues: TextButton (ref)
            TextButton.TextColor3 = Color3.fromRGB(255, 255, 255);
            TextButton.Parent.ImageColor3 = Color3.fromRGB(180, 48, 48);
        end);
        waveDefenceTab.MouseEnter:Connect(function() -- Line: 320
            -- upvalues: waveDefenceTab (ref)
            waveDefenceTab.title.TextColor3 = Color3.fromRGB(0, 85, 255);
        end);
        waveDefenceTab.MouseLeave:Connect(function() -- Line: 323
            -- upvalues: waveDefenceTab (ref)
            waveDefenceTab.title.TextColor3 = Color3.fromRGB(255, 255, 255);
        end);
        waveDefenceTab.Activated:Connect(function() -- Line: 326
            -- upvalues: waveDefenceTab (ref), backgroundFillMiddle (ref), backgroundFillRight (ref), backgroundFillLeft (ref), chooseDungeon (ref), makeUnselected (ref), makeSelected (ref), updateLevelAndName (ref)
            if waveDefenceTab.toggled.Value == true then
                waveDefenceTab.toggled.Value = false;
                waveDefenceTab.info.Visible = false;
                backgroundFillMiddle.ImageColor3 = Color3.fromRGB(65, 65, 65);
                backgroundFillRight.ImageColor3 = Color3.fromRGB(65, 65, 65);
                backgroundFillLeft.ImageColor3 = Color3.fromRGB(65, 65, 65);
                chooseDungeon.levelReq.Frame.ImageColor3 = Color3.fromRGB(65, 65, 65);
                chooseDungeon.private.Frame.ImageColor3 = Color3.fromRGB(65, 65, 65);
                chooseDungeon.levelReq.ImageColor3 = Color3.fromRGB(38, 38, 38);
                chooseDungeon.private.ImageColor3 = Color3.fromRGB(38, 38, 38);
                chooseDungeon.ImageColor3 = Color3.fromRGB(38, 38, 38);
                backgroundFillMiddle.waveDefence.Visible = false;
                makeUnselected(waveDefenceTab);
            else
                waveDefenceTab.toggled.Value = true;
                waveDefenceTab.info.Visible = true;
                backgroundFillMiddle.ImageColor3 = Color3.fromRGB(77, 99, 126);
                backgroundFillRight.ImageColor3 = Color3.fromRGB(77, 99, 126);
                backgroundFillLeft.ImageColor3 = Color3.fromRGB(77, 99, 126);
                chooseDungeon.levelReq.Frame.ImageColor3 = Color3.fromRGB(77, 99, 126);
                chooseDungeon.private.Frame.ImageColor3 = Color3.fromRGB(77, 99, 126);
                chooseDungeon.levelReq.ImageColor3 = Color3.fromRGB(35, 40, 81);
                chooseDungeon.private.ImageColor3 = Color3.fromRGB(35, 40, 81);
                chooseDungeon.ImageColor3 = Color3.fromRGB(35, 40, 81);
                backgroundFillMiddle.waveDefence.Visible = true;
                makeSelected(waveDefenceTab);
            end;

            updateLevelAndName();
        end);
        TextButton.MouseButton1Down:Connect(function() -- Line: 357
            -- upvalues: getDungeonName (ref), getDungeonDifficulty (ref), chooseDungeon (ref), hardcoreSection (ref), privateInner (ref), waveDefenceTab (ref), queueGui (ref)
            local v30 = getDungeonName();
            local v31 = getDungeonDifficulty();
            local v32 = tonumber(chooseDungeon.levelReq.Frame.TextBox.Text);
            local Visible = privateInner.chosenIndicatorBackground.chosenIndicatorFill.chosen.Visible;

            if game.ReplicatedStorage.remotes.createLobby:InvokeServer(v30, v31, v32, hardcoreSection.hardcore.chosenIndicatorBackground.chosenIndicatorFill.chosen.Visible, Visible, waveDefenceTab.toggled.Value) == true then
                queueGui.lobbyInfo.startBackground.Visible = true;

                if Visible == true then
                    queueGui.lobbyInfo.whitelist.Visible = true;
                end;

                chooseDungeon.Visible = false;
                queueGui.lobbyInfo.Visible = true;
            end;
        end);

        for _, child in pairs(ScrollingFrame:GetChildren()) do
            if child:IsA("ImageLabel") then
                child.TextButton.MouseButton1Down:Connect(function() -- Line: 381
                    -- upvalues: child (copy), ScrollingFrame (ref), updateLevelAndName (ref)
                    if not child.chosenIndicatorBackground.chosenIndicatorFill.chosen.Visible then
                        for _, child2 in pairs(ScrollingFrame:GetChildren()) do
                            if child2:IsA("ImageLabel") and child2.Name ~= child.Name then
                                child2.chosenIndicatorBackground.chosenIndicatorFill.chosen.Visible = false;
                            end;
                        end;

                        child.chosenIndicatorBackground.chosenIndicatorFill.chosen.Visible = true;
                    end;

                    updateLevelAndName();
                end);
                child.MouseEnter:Connect(function(p33, p34) -- Line: 395
                    -- upvalues: child (copy)
                    if child.Name == "Egg Island" then
                        child.chosenIndicatorBackground.ImageColor3 = Color3.fromRGB(60, 42, 74);

                        return;
                    end;

                    if child.Name == "Krampus" then
                        child.chosenIndicatorBackground.ImageColor3 = Color3.fromRGB(0, 81, 125);

                        return;
                    end;

                    child.chosenIndicatorBackground.ImageColor3 = Color3.fromRGB(63, 63, 63);
                end);
                child.MouseLeave:Connect(function(p35, p36) -- Line: 406
                    -- upvalues: child (copy)
                    if child.Name == "Egg Island" then
                        child.chosenIndicatorBackground.ImageColor3 = Color3.fromRGB(103, 71, 125);

                        return;
                    end;

                    if child.Name == "Krampus" then
                        child.chosenIndicatorBackground.ImageColor3 = Color3.fromRGB(0, 81, 125);

                        return;
                    end;

                    child.chosenIndicatorBackground.ImageColor3 = Color3.fromRGB(111, 111, 111);
                end);
            end;
        end;

        for _, child in pairs(backgroundFillRight:GetChildren()) do
            if child:IsA("ImageLabel") then
                child.TextButton.MouseButton1Down:Connect(function() -- Line: 423
                    -- upvalues: child (copy), backgroundFillRight (ref), updateLevelAndName (ref)
                    if not child.chosenIndicatorBackground.chosenIndicatorFill.chosen.Visible then
                        for _, child2 in pairs(backgroundFillRight:GetChildren()) do
                            if child2:IsA("ImageLabel") and child2.Name ~= child.Name then
                                child2.chosenIndicatorBackground.chosenIndicatorFill.chosen.Visible = false;
                            end;
                        end;

                        child.chosenIndicatorBackground.chosenIndicatorFill.chosen.Visible = true;
                    end;

                    updateLevelAndName();
                end);
                child.MouseEnter:Connect(function(p37, p38) -- Line: 437
                    -- upvalues: child (copy)
                    child.chosenIndicatorBackground.ImageColor3 = Color3.fromRGB(63, 63, 63);
                end);
                child.MouseLeave:Connect(function(p39, p40) -- Line: 440
                    -- upvalues: child (copy)
                    child.chosenIndicatorBackground.ImageColor3 = Color3.fromRGB(111, 111, 111);
                end);
            end;
        end;

        local v41 = {
            ["Desert Temple"] = true,
            ["Winter Outpost"] = true,
            ["Pirate Island"] = true,
            ["King\'s Castle"] = true,
            ["The Underworld"] = true,
            ["Samurai Palace"] = true,
            ["The Canals"] = true,
            ["Ghastly Harbor"] = true,
            ["Steampunk Sewers"] = true,
            ["Orbital Outpost"] = true,
            ["Volcanic Chambers"] = true
        };

        if ChinaPolicyService:IsActive() then
            for _, child in pairs(ScrollingFrame:GetChildren()) do
                if child:IsA("ImageLabel") then
                    if v41[child.Name] then
                        child.Visible = true;
                    else
                        child.Visible = false;
                    end;
                end;
            end;
        end;

        local v42 = PlaceManager.IsTutorial();
        chooseDungeon.tutorialText.Visible = v42;

        if v42 then
            for _, child in chooseDungeon.backgroundFillLeft.ScrollingFrame:GetChildren() do
                if child:IsA("GuiObject") then
                    child.Visible = false;
                    child.chosenIndicatorBackground.chosenIndicatorFill.chosen.Visible = false;
                end;
            end;

            chooseDungeon.private.Visible = false;
            chooseDungeon.levelReq.Visible = false;
        end;

        chooseDungeon.backgroundFillRight.Insane.Visible = not v42;
        chooseDungeon.backgroundFillRight.Nightmare.Visible = not v42;
        chooseDungeon.backgroundFillRight.hardcoreSection.Visible = not v42;
        chooseDungeon.backgroundFillLeft.ScrollingFrame["Tutorial Dungeon"].Visible = v42;
        chooseDungeon.backgroundFillLeft.ScrollingFrame["Tutorial Dungeon"].chosenIndicatorBackground.chosenIndicatorFill.chosen.Visible = v42;
        local Children = chooseDungeon.backgroundFillLeft.ScrollingFrame:GetChildren();
        local v43 = false;

        for _, v in Children do
            if v:IsA("GuiObject") and (v.Visible and not MapPlaces.IsAvailable(v.Name)) then
                v.Visible = false;

                if v.chosenIndicatorBackground.chosenIndicatorFill.chosen.Visible then
                    v.chosenIndicatorBackground.chosenIndicatorFill.chosen.Visible = false;
                    v43 = true;
                end;
            end;
        end;

        if v43 and not getDungeonName() then
            for _, v in Children do
                if v:IsA("ImageLabel") and v.Visible then
                    v.chosenIndicatorBackground.chosenIndicatorFill.chosen.Visible = true;
                    break;
                end;
            end;
        end;

        updateLevelAndName();
    end
};