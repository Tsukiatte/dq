-- Players.OPhhSZQjWxdy.PlayerScripts.Ui.queue
-- Decompiled with Potassium's decompiler.

local Players = game:GetService("Players");
local ReplicatedStorage = game:GetService("ReplicatedStorage");
local UserInputService = game:GetService("UserInputService");
local SoundService = game:GetService("SoundService");
local script_chooseDungeon = require(script.chooseDungeon);
local script_gameSearch = require(script.gameSearch);
local script_lobbyInfo = require(script.lobbyInfo);
local Utility = ReplicatedStorage:WaitForChild("Utility");
local PlaceManager = require(Utility:WaitForChild("PlaceManager"));
local AudioService = require(Utility:WaitForChild("AudioService"));
local LocalPlayer = Players.LocalPlayer;
local PlayerScripts = LocalPlayer:WaitForChild("PlayerScripts");
local xboxSelection = require(PlayerScripts:WaitForChild("xboxSelection"));
local queueGui = LocalPlayer:WaitForChild("PlayerGui"):WaitForChild("queueGui", 72000);
local chooseDungeon = queueGui:WaitForChild("chooseDungeon");
local xButton = chooseDungeon:WaitForChild("xFrame"):WaitForChild("xButton");
local gameSearch = queueGui:WaitForChild("gameSearch");
local xButton2 = gameSearch:WaitForChild("xFrame"):WaitForChild("xButton");
local lobbyInfo = queueGui:WaitForChild("lobbyInfo");
local xButton3 = lobbyInfo:WaitForChild("xFrame"):WaitForChild("xButton");
local selectOption = queueGui:WaitForChild("selectOption");
local Frame = selectOption:WaitForChild("Frame");
local joinGame = Frame:WaitForChild("joinGame");
local createGame = Frame:WaitForChild("createGame");
local xButton4 = selectOption:WaitForChild("xFrame"):WaitForChild("xButton");

local function inALobby(p1) -- Line: 37
    for _, child in pairs(workspace.games.inGame:GetChildren()) do
        for _, child2 in pairs(child:GetChildren()) do
            if child2.Name == p1.Name then
                return true;
            end;
        end;
    end;

    for _, child in pairs(workspace.games.inLobby:GetChildren()) do
        for _, child2 in pairs(child:GetChildren()) do
            if child2.Name == p1.Name then
                return true;
            end;
        end;
    end;

    return false;
end;

local u2 = {};

local function setupExitButton(u3) -- Line: 59
    -- upvalues: AudioService (copy), SoundService (copy), u2 (copy)
    u3.Activated:Connect(function() -- Line: 60
        -- upvalues: AudioService (ref), SoundService (ref), u2 (ref)
        AudioService.Play("clickSound", SoundService);
        u2.Close();
    end);
    u3.MouseEnter:Connect(function() -- Line: 65
        -- upvalues: u3 (copy)
        u3.TextColor3 = Color3.fromRGB(255, 0, 0);
    end);
    u3.MouseLeave:Connect(function() -- Line: 69
        -- upvalues: u3 (copy)
        u3.TextColor3 = Color3.fromRGB(255, 255, 255);
    end);
end;

function u2.Init() -- Line: 74
    -- upvalues: script_chooseDungeon (copy), script_gameSearch (copy), script_lobbyInfo (copy), setupExitButton (copy), xButton4 (copy), xButton3 (copy), xButton2 (copy), xButton (copy), UserInputService (copy), u2 (copy), createGame (copy), AudioService (copy), SoundService (copy), chooseDungeon (copy), selectOption (copy), gameSearch (copy), lobbyInfo (copy), xboxSelection (copy), joinGame (copy), PlaceManager (copy)
    script_chooseDungeon.Init();
    script_gameSearch.Init();
    script_lobbyInfo.Init();
    setupExitButton(xButton4);
    setupExitButton(xButton3);
    setupExitButton(xButton2);
    setupExitButton(xButton);
    UserInputService.InputBegan:Connect(function(p4, p5) -- Line: 84
        -- upvalues: u2 (ref)
        if p5 then
            return;
        end;

        if p4.KeyCode == Enum.KeyCode.ButtonB then
            u2.Close();
        end;
    end);
    createGame.Activated:Connect(function() -- Line: 92
        -- upvalues: AudioService (ref), SoundService (ref), chooseDungeon (ref), selectOption (ref), gameSearch (ref), lobbyInfo (ref), UserInputService (ref), xboxSelection (ref)
        print("clicked");
        AudioService.Play("clickSound", SoundService);
        chooseDungeon.Visible = true;
        selectOption.Visible = false;
        gameSearch.Visible = false;
        lobbyInfo.Visible = false;
        lobbyInfo.startBackground.Visible = false;

        if UserInputService:GetLastInputType() == Enum.UserInputType.Gamepad1 then
            xboxSelection.forceSelect(chooseDungeon.backgroundFillLeft.ScrollingFrame["Desert Temple"].TextButton);
        end;
    end);
    createGame.MouseEnter:Connect(function() -- Line: 107
        -- upvalues: createGame (ref)
        createGame.TextColor3 = Color3.fromRGB(255, 190, 38);
        createGame.main.ImageColor3 = Color3.fromRGB(97, 57, 24);
    end);
    createGame.MouseLeave:Connect(function() -- Line: 112
        -- upvalues: createGame (ref)
        createGame.TextColor3 = Color3.fromRGB(255, 255, 255);
        createGame.main.ImageColor3 = Color3.fromRGB(190, 111, 47);
    end);
    joinGame.Activated:Connect(function() -- Line: 117
        -- upvalues: AudioService (ref), SoundService (ref), gameSearch (ref), selectOption (ref), lobbyInfo (ref)
        AudioService.Play("clickSound", SoundService);
        gameSearch.Visible = true;
        selectOption.Visible = false;
        lobbyInfo.Visible = false;
    end);
    joinGame.MouseEnter:Connect(function() -- Line: 125
        -- upvalues: joinGame (ref)
        joinGame.TextColor3 = Color3.fromRGB(0, 255, 0);
        joinGame.main.ImageColor3 = Color3.fromRGB(91, 120, 54);
    end);
    joinGame.MouseLeave:Connect(function() -- Line: 130
        -- upvalues: joinGame (ref)
        joinGame.TextColor3 = Color3.fromRGB(255, 255, 255);
        joinGame.main.ImageColor3 = Color3.fromRGB(158, 207, 93);
    end);
    selectOption.tutorialText.Visible = PlaceManager.IsTutorial();
end;

function u2.Toggle() -- Line: 138
    -- upvalues: queueGui (copy), u2 (copy)
    if queueGui.selectOption.Visible then
        u2.Close();

        return;
    end;

    u2.Open();
end;

function u2.Open() -- Line: 146
    -- upvalues: inALobby (copy), LocalPlayer (copy), queueGui (copy), UserInputService (copy), xboxSelection (copy)
    if inALobby(LocalPlayer) then
        queueGui.lobbyInfo.Visible = true;
        queueGui.gameSearch.Visible = false;
        queueGui.selectOption.Visible = false;
        queueGui.chooseDungeon.Visible = false;

        return;
    end;

    queueGui.lobbyInfo.Visible = false;
    queueGui.gameSearch.Visible = false;
    queueGui.chooseDungeon.Visible = false;
    queueGui.selectOption.Visible = true;

    if UserInputService:GetLastInputType() == Enum.UserInputType.Gamepad1 then
        xboxSelection.forceSelect(queueGui.selectOption.Frame.joinGame);
    end;
end;

function u2.Close() -- Line: 164
    -- upvalues: queueGui (copy)
    queueGui.lobbyInfo.Visible = false;
    queueGui.gameSearch.Visible = false;
    queueGui.chooseDungeon.Visible = false;
    queueGui.selectOption.Visible = false;
end;

u2.Init();

return u2;