-- Decompiled with Potassium's decompiler.

local ReplicatedStorage = game:GetService("ReplicatedStorage");
local RunService = game:GetService("RunService");
local Utility = ReplicatedStorage:WaitForChild("Utility");
local BridgeNet2 = require(Utility:WaitForChild("BridgeNet2"));
local TweenService = require(Utility:WaitForChild("TweenService"));
local Trove = require(Utility:WaitForChild("Trove"));
require(Utility:WaitForChild("Robug"));
local u1 = BridgeNet2.ReferenceBridge("precastHitbox");
local u2 = BridgeNet2.ReferenceIdentifier("action");
local v3 = RunService:IsClient();
local u4 = RunService:IsServer();
local u5 = {};

local function detectTerrain(p6) -- Line: 18
    local RaycastParams_new_ret = RaycastParams.new();
    RaycastParams_new_ret.FilterType = Enum.RaycastFilterType.Include;
    RaycastParams_new_ret.FilterDescendantsInstances = { workspace.Terrain };
    RaycastParams_new_ret.IgnoreWater = false;
    local v7 = workspace:Raycast(p6.Position + Vector3.new(0, 5, 0), Vector3.new(0, -15, 0), RaycastParams_new_ret);

    if not v7 then
        return p6;
    end;

    local RightVector = p6.RightVector;
    local Normal = v7.Normal;
    local v8 = RightVector:Cross(Normal);

    return CFrame.fromMatrix(v7.Position, RightVector, Normal, v8);
end;

local function createHitbox(p9, p10: vector, p11: string, p12: userdata?) -- Line: 37
    local Part = Instance.new("Part");
    Part.Material = "Neon";
    Part.Anchored = true;
    Part.CanTouch = false;
    Part.CanQuery = false;
    Part.CanCollide = false;
    Part.Transparency = 1;
    Part.Shape = p11;
    Part.Size = p10;
    Part.CFrame = p9;
    Part.Parent = workspace;

    if p12 then
        for i, v in p12 do
            Part[i] = v;
        end;
    end;

    if p11 == "Cylinder" then
        Part.CFrame = Part.CFrame * CFrame.Angles(0, 0, 1.5707963267948966);
    end;

    return Part;
end;

local function tweenHitbox(u13, u14, p15, p16) -- Line: 63
    -- upvalues: TweenService (copy)
    TweenService.tween(u13, {
        Transparency = 0.1
    }, {
        Style = "Sine",
        Dir = "Out",
        Time = 0.15 - p16
    });
    task.delay(p15 - p16, function() -- Line: 68
        -- upvalues: TweenService (ref), u13 (copy), u14 (copy)
        TweenService.tween(u13, {
            Transparency = 0
        }, {
            Time = 0.1,
            Style = "Sine",
            Dir = "Out"
        });
        task.wait(0.15);
        TweenService.tween(u13, {
            Transparency = 1
        }, {
            Time = 0.1,
            Style = "Sine",
            Dir = "Out"
        });
        task.wait(0.1);
        u14:Clean();
    end);
end;

function u5.Cube(p17, p18: vector, p19: number, p20: number, p21: userdata) -- Line: 85
    -- upvalues: u4 (copy), u1 (copy), BridgeNet2 (copy), u2 (copy), detectTerrain (copy), Trove (copy), tweenHitbox (copy)
    if u4 then
        u1:Fire(BridgeNet2.AllPlayers(), {
            [u2] = "Cube",
            cframe = p17,
            size = p18,
            delayUntilAttack = p19,
            startTime = p20,
            properties = p21
        });

        return;
    end;

    local v22 = workspace:GetServerTimeNow() - p20;
    local v23 = detectTerrain(p17);
    local Part = Instance.new("Part");
    Part.Material = "Neon";
    Part.Anchored = true;
    Part.CanTouch = false;
    Part.CanQuery = false;
    Part.CanCollide = false;
    Part.Transparency = 1;
    Part.Shape = "Block";
    Part.Size = p18;
    Part.CFrame = v23;
    Part.Parent = workspace;

    if p21 then
        for i, v in p21 do
            Part[i] = v;
        end;
    end;

    local v24 = Trove.new();
    v24:Add(Part);
    tweenHitbox(Part, v24, p19, v22);
end;

function u5.Circle(p25: vector, p26: number, p27: number, p28: number, p29: userdata) -- Line: 108
    -- upvalues: u4 (copy), u1 (copy), BridgeNet2 (copy), u2 (copy), detectTerrain (copy), createHitbox (copy), Trove (copy), tweenHitbox (copy)
    if u4 then
        u1:Fire(BridgeNet2.AllPlayers(), {
            [u2] = "Circle",
            position = p25,
            radius = p26,
            delayUntilAttack = p27,
            startTime = p28,
            properties = p29
        });

        return;
    end;

    local v30 = workspace:GetServerTimeNow() - p28;
    local v31 = createHitbox(detectTerrain(CFrame.new(p25)), Vector3.new(0.5, p26 * 2, p26 * 2), "Cylinder", p29);
    local v32 = Trove.new();
    v32:Add(v31);
    tweenHitbox(v31, v32, p27, v30);
end;

if v3 then
    u1:Connect(function(p33) -- Line: 132
        -- upvalues: u2 (copy), u5 (copy)
        u5[p33[u2]](p33.cframe or p33.position, p33.size or p33.radius, p33.delayUntilAttack, p33.startTime, p33.properties);
    end);
end;

return u5;