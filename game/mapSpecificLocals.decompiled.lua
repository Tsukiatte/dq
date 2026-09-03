-- Decompiled with Potassium's decompiler.

local LocalPlayer = game.Players.LocalPlayer;
local Debris = game:GetService("Debris");
local TweenService = game:GetService("TweenService");
local CollectionService = game:GetService("CollectionService");
local RunService = game:GetService("RunService");
local Random_new_ret = Random.new();
local timeSync = require(game.ReplicatedStorage.timeSync);
local CameraShaker = require(game.ReplicatedStorage.CameraShaker);
local workspace_Camera = workspace.Camera;
local u2 = CameraShaker.new(Enum.RenderPriority.Camera.Value, function(p1) -- Line: 12
    -- upvalues: workspace_Camera (copy)
    workspace_Camera.CFrame = workspace_Camera.CFrame * p1;
end);
u2:Start();
game.ReplicatedStorage.mapSpecificRemotes:WaitForChild("blindPlayers").OnClientEvent:Connect(function() -- Line: 18
    game.Lighting.FogEnd = 35;
    game.Lighting.FogColor = Color3.fromRGB(43, 8, 8);
end);
game.ReplicatedStorage.mapSpecificRemotes:WaitForChild("unblindPlayers").OnClientEvent:Connect(function() -- Line: 23
    game.Lighting.FogEnd = 750;
    game.Lighting.FogColor = Color3.fromRGB(127, 108, 87);
end);
game.ReplicatedStorage.remotes:WaitForChild("sanadaClientEvents").OnClientEvent:Connect(function(p3) -- Line: 28
    if p3 ~= "showFire" then
        if p3 == "hideFire" then
            workspace:WaitForChild("sanadaFireParts"):Destroy();
        end;

        return;
    end;

    local Children = workspace:WaitForChild("sanadaFireParts"):GetChildren();

    for _, v in pairs(Children) do
        if v.Name == "fire" then
            v.Transparency = 0;

            for _, child in pairs(v:GetChildren()) do
                if child:IsA("ParticleEmitter") then
                    child.Enabled = true;
                end;
            end;
        end;
    end;
end);
game.ReplicatedStorage.remotes:WaitForChild("golemClientEvents").OnClientEvent:Connect(function(p4) -- Line: 48
    if p4 ~= "showFire" then
        if p4 == "hideFire" then
            workspace:WaitForChild("golemFlames"):Destroy();
        end;

        return;
    end;

    local Children = workspace:WaitForChild("golemFlames"):GetChildren();

    for _, v in pairs(Children) do
        if v.Name == "flame" then
            v.Transparency = 0;

            for _, child in pairs(v:GetChildren()) do
                if child:IsA("ParticleEmitter") then
                    child.Enabled = true;
                end;
            end;
        end;
    end;
end);
game.ReplicatedStorage.remotes:WaitForChild("miyamotoClientEvents").OnClientEvent:Connect(function(p5, p6) -- Line: 68
    if p5 == "fireCyclone" then
        local HumanoidRootPart = p6[1].HumanoidRootPart;
        local v7 = p6[1].Humanoid:LoadAnimation(p6[2]);
        v7:Play();
        v7:AdjustSpeed(1.6);
        local u8 = game.ReplicatedStorage.enemyProjectiles["Flame Cyclone"]:Clone();
        game:GetService("Debris"):AddItem(u8, 3.5);
        u8.Parent = workspace;
        u8.PrimaryPart.flameSound:Play();
        u8.PrimaryPart.explode:Play();
        spawn(function() -- Line: 80
            -- upvalues: u8 (copy), HumanoidRootPart (copy)
            local v9 = 0;

            while u8:FindFirstChild("PrimaryPart") do
                u8:SetPrimaryPartCFrame(HumanoidRootPart.CFrame * CFrame.Angles(0, math.rad(v9), 0));
                wait();
                v9 = v9 + 50;
            end;
        end);
        local Random_new_ret2 = Random.new(tick());
        spawn(function() -- Line: 90
            -- upvalues: u8 (copy), Random_new_ret2 (copy)
            while u8:FindFirstChild("PrimaryPart") do
                for _, child in pairs(u8:GetChildren()) do
                    if child.Name == "crescent" and Random_new_ret2:NextInteger(0, 2) == 1 then
                        spawn(function() -- Line: 95
                            -- upvalues: child (copy)
                            child.Transparency = 0;
                            wait(0.1);

                            for i = 1, 5 do
                                child.Transparency = child.Transparency + 0.2;
                                wait();
                                local _ = i;
                            end;
                        end);
                    end;
                end;

                wait(0.2);
            end;
        end);

        return;
    end;

    if p5 == "endFireCyclone" then
        local v10 = game.ReplicatedStorage.enemyProjectiles.smokePart:Clone();
        game:GetService("Debris"):AddItem(v10, 5);
        v10.Parent = workspace;
        v10.CFrame = p6;
        wait(0.5);
        v10.smoke.Enabled = false;

        return;
    end;

    if p5 ~= "flameBeams" then
        if p5 == "showFire" then
            local Children = workspace:WaitForChild("miyamotoFlames"):GetChildren();

            for _, v in pairs(Children) do
                if v.Name == "flame" then
                    v.Transparency = 0;

                    for _, child in pairs(v:GetChildren()) do
                        if child:IsA("ParticleEmitter") then
                            child.Enabled = true;
                        end;
                    end;
                end;
            end;

            return;
        end;

        if p5 == "hideFire" then
            workspace:WaitForChild("miyamotoFlames"):Destroy();

            return;
        end;

        if p5 == "spinFlameShuriken" then
            while p6 do
                p6.CFrame = p6.CFrame * CFrame.Angles(0, 0.5235987755982988, 0);
                wait();
            end;
        end;

        return;
    end;

    local v11 = p6[1];
    local v12 = v11.Humanoid:LoadAnimation(p6[2]);
    local v13 = game.ReplicatedStorage.enemyProjectiles.flameEffect:Clone();
    game:GetService("Debris"):AddItem(v13, 5.5);
    v13.Parent = workspace;
    v13.CFrame = v11.HumanoidRootPart.CFrame;
    v12:Play();
    v12:AdjustSpeed(1.6);
    wait(4);
    v12:Stop();
end);
game.ReplicatedStorage.remotes:WaitForChild("bossSpecficEvents").OnClientEvent:Connect(function(p14, u15) -- Line: 159
    -- upvalues: Debris (copy), TweenService (copy)
    if p14 == "Spawn Minion" then
        local v16 = game.ReplicatedStorage.enemyProjectiles.mageBossMinionSpawnEffect:Clone();
        Debris:AddItem(v16, 2.5);
        v16.Parent = workspace;
        v16:SetPrimaryPartCFrame(u15);

        for _, child in pairs(v16:GetChildren()) do
            if child.Name == "helix" then
                TweenService:Create(child, TweenInfo.new(2, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0), {
                    Size = Vector3.new(9, 27, 9),
                    Transparency = 1
                }):Play();
            end;
        end;

        while v16:FindFirstChild("PrimaryPart") do
            v16:SetPrimaryPartCFrame(v16:GetPrimaryPartCFrame() * CFrame.Angles(0, 0.4363323129985824, 0) + Vector3.new(0, 0.1, 0));
            wait();
        end;
    else
        if p14 == "Minion Explosion" then
            local v17 = game.ReplicatedStorage.enemyProjectiles.minionExplosion:Clone();
            Debris:AddItem(v17, 3);
            v17.Parent = workspace;
            v17.CFrame = u15;
            TweenService:Create(v17, TweenInfo.new(0.2, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, 0, false, 0), {
                Size = Vector3.new(40, 40, 40),
                Transparency = 1
            }):Play();

            return;
        end;

        if p14 == "Second Boss Mark Target" then
            local u18 = game.ReplicatedStorage.enemyProjectiles.secondBossMark:Clone();
            Debris:AddItem(u18, 7);
            u18.Parent = workspace;
            u18:SetPrimaryPartCFrame(u15.CFrame + Vector3.new(0, 20, 0));
            local sword = u18.sword;
            spawn(function() -- Line: 208
                -- upvalues: u18 (copy), u15 (copy)
                while u18:FindFirstChild("PrimaryPart") do
                    u18:SetPrimaryPartCFrame(u15.CFrame);
                    wait();
                end;
            end);
            local v19 = tick() + 5;
            local v20 = v19 - tick();
            local v21 = v19 - tick();

            while v21 > 0 do
                sword:SetPrimaryPartCFrame(sword:GetPrimaryPartCFrame() * CFrame.Angles(0, 0.2617993877991494, 0) - Vector3.new(0, 4 * (v20 - v21), 0));
                v20 = v19 - tick();
                wait();
                v21 = v19 - tick();
            end;

            u18:Destroy();

            return;
        end;

        if p14 == "Second Boss Show Safe Spot" then
            u15.Union.Transparency = 0.3;
            u15.Union.PointLight.Enabled = true;
            u15.Union.TrailElectricityBlur.Enabled = true;
            u15.Union.safeGui.Enabled = true;

            for i = 1, 20 do
                local v22 = game.ReplicatedStorage.enemyProjectiles.safeSpotCircle:Clone();
                Debris:AddItem(v22, 2);
                v22.Parent = workspace;
                v22.CFrame = u15.hitBox.CFrame;
                local v23 = {
                    CFrame = v22.CFrame + Vector3.new(0, 25, 0)
                };
                TweenService:Create(v22, TweenInfo.new(2, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, 0, false, 0), v23):Play();
                wait(0.33);
                local _ = i;
            end;

            u15.Union.Transparency = 1;
            u15.Union.PointLight.Enabled = false;
            u15.Union.TrailElectricityBlur.Enabled = false;
            u15.Union.safeGui.Enabled = false;

            return;
        end;

        if p14 == "Second Boss Everyone Gets Hit" then
            for _, v in pairs(game.Players:GetPlayers()) do
                if v.Character then
                    local Character = v.Character;

                    if Character:FindFirstChild("Humanoid") and (Character:FindFirstChild("HumanoidRootPart") and Character.Humanoid.Health > 0) then
                        spawn(function() -- Line: 263
                            -- upvalues: Debris (ref), Character (copy), TweenService (ref)
                            local v24 = game.ReplicatedStorage.enemyProjectiles.secondBossFailedExplosion:Clone();
                            Debris:AddItem(v24, 0.4);
                            v24.Parent = workspace;
                            v24.CFrame = Character.HumanoidRootPart.CFrame;
                            TweenService:Create(v24, TweenInfo.new(0.4, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, 0, false, 0), {
                                Size = Vector3.new(30, 30, 30),
                                Transparency = 1
                            }):Play();
                        end);
                    end;
                end;
            end;

            return;
        end;

        if p14 == "Second Boss Big Explosion" then
            local v25 = game.ReplicatedStorage.enemyProjectiles.secondBossFailedExplosion:Clone();
            Debris:AddItem(v25, 2);
            v25.Parent = workspace;
            v25.CFrame = u15;
            TweenService:Create(v25, TweenInfo.new(0.7, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, 0, false, 0), {
                Size = Vector3.new(100, 100, 100),
                Transparency = 1
            }):Play();

            return;
        end;

        if p14 == "Final Boss Hover Arrow" then
            local v26 = game.ReplicatedStorage.enemyProjectiles.arrowDownGui:Clone();
            Debris:AddItem(v26, 30);
            v26.Parent = u15;
            TweenService:Create(v26, TweenInfo.new(0.6, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, -1, true, 0.2), {
                StudsOffset = Vector3.new(0, 4, 0)
            }):Play();

            return;
        end;

        if p14 == "Final Boss Safe Character" then
            local v27 = game.ReplicatedStorage.enemyProjectiles.forceField:Clone();
            Debris:AddItem(v27, 8);
            v27.Parent = workspace;

            while v27.Parent == workspace do
                v27.CFrame = u15.HumanoidRootPart.CFrame;
                wait();
            end;
        else
            if p14 == "Final Boss Charging" then
                local HumanoidRootPart = u15.HumanoidRootPart;
                local v28 = game.ReplicatedStorage.enemyProjectiles.finalBossRotatingCircle:Clone();
                Debris:AddItem(v28, 8);
                v28.Parent = workspace;
                v28:SetPrimaryPartCFrame(HumanoidRootPart.CFrame);

                return;
            end;

            if p14 == "Final Boss Explode" then
                local v29 = game.ReplicatedStorage.enemyProjectiles.finalBossExplosion:Clone();
                Debris:AddItem(v29, 5);
                v29.Parent = workspace;
                v29.CFrame = u15.HumanoidRootPart.CFrame;
                TweenService:Create(v29, TweenInfo.new(1, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, 0, false, 0), {
                    Size = Vector3.new(200, 200, 200),
                    Transparency = 1
                }):Play();
            end;
        end;
    end;
end);
local u30 = {};
game.ReplicatedStorage.remotes:WaitForChild("ghastlyBossSpecficEvents").OnClientEvent:Connect(function(p31, p32) -- Line: 346
    -- upvalues: Random_new_ret (copy), Debris (copy), u30 (copy), u2 (copy), CameraShaker (copy), TweenService (copy)
    if p31 == "Show Cannonball Rings" then
        local workspace_playerPickupCannonballRing = workspace.playerPickupCannonballRing;
        workspace_playerPickupCannonballRing.light.Enabled = true;
        workspace_playerPickupCannonballRing.Transparency = 0;
        workspace.playerFireCannon.cannon.light.Enabled = true;
        workspace.playerFireCannon.ring.Transparency = 0;

        return;
    end;

    if p31 == "Fire Cannon" then
        local v33 = workspace.corruptCannons:GetChildren()[Random_new_ret:NextInteger(1, 5)];
        local particle = v33.particle;
        local light = v33.light;
        local v34 = v33.explosionSound:Clone();
        v34.Parent = v33;
        Debris:AddItem(v34, 2);
        particle.Enabled = true;
        light.Enabled = true;
        v34.PlaybackSpeed = Random_new_ret:NextNumber(0.75, 1.25);
        v34:Play();
        wait(0.15);
        particle.Enabled = false;
        light.Enabled = false;

        return;
    end;

    if p31 == "Player Picked Up Cannonball" then
        local HumanoidRootPart = p32.HumanoidRootPart;
        local v35 = game.ReplicatedStorage.enemyProjectiles.overheadCannon:Clone();
        Debris:AddItem(v35, 25);
        v35.Parent = workspace;
        table.insert(u30, v35);

        while v35 and (v35.Parent and p32:FindFirstChild("HumanoidRootPart")) do
            v35:SetPrimaryPartCFrame(HumanoidRootPart.CFrame + Vector3.new(0, 6, 0));
            wait();
        end;

        v35:Destroy();

        return;
    end;

    if p31 ~= "Fire Cannon At Boat" then
        if p31 == "Spawn Crab" then
            local HumanoidRootPart = p32.HumanoidRootPart;
            local Humanoid = p32.Humanoid;
            local v36 = Humanoid:LoadAnimation(Humanoid.walking);
            Humanoid:LoadAnimation(Humanoid.idle):Play();
            local Position = HumanoidRootPart.Position;

            while Humanoid.Health > 0 do
                if (Position - HumanoidRootPart.Position).Magnitude > 0.5 then
                    if not v36.IsPlaying then
                        v36:Play();
                    end;
                else
                    v36:Stop();
                end;

                Position = HumanoidRootPart.Position;
                wait(0.2);
            end;
        else
            if p31 == "Crab Fire" then
                p32.Canon.particleAttach.particle.Enabled = true;
                p32.Canon.particleAttach.explosionSound:Play();
                wait(0.25);
                p32.Canon.particleAttach.particle.Enabled = false;

                return;
            end;

            if p31 == "Kraken Spawn" then
                local particle = workspace.krakenWaterParticlePart.particle;
                particle.Enabled = true;
                wait(0.6);
                particle.Enabled = false;

                return;
            end;

            if p31 == "Shake Screens" then
                u2:Shake(CameraShaker.Presets[p32]);

                return;
            end;

            if p31 == "Throw Shark" then
                local workspace_krakenSharkSpawnInWater = workspace.krakenSharkSpawnInWater;
                local u37 = game.ReplicatedStorage.enemyProjectiles.sharkThrowClient:Clone();
                Debris:AddItem(u37, 6);
                u37.Parent = workspace;
                u37:SetPrimaryPartCFrame(workspace_krakenSharkSpawnInWater.CFrame + Vector3.new(0, 1, 0));
                local CFrame_new_ret = CFrame.new(workspace_krakenSharkSpawnInWater.Position, p32.Position);
                local v38 = {
                    CFrame = CFrame_new_ret + CFrame_new_ret.LookVector * ((workspace_krakenSharkSpawnInWater.Position - p32.Position).Magnitude / 2) + Vector3.new(0, 80, 0)
                };
                local TweenInfo_new_ret = TweenInfo.new(0.75, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, 0);
                local v39 = TweenService:Create(u37.PrimaryPart, TweenInfo_new_ret, v38);
                v39:Play();
                local TweenInfo_new_ret2 = TweenInfo.new(0.75, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0);
                local u40 = TweenService:Create(u37.PrimaryPart, TweenInfo_new_ret2, {
                    CFrame = p32
                });
                v39.Completed:Connect(function() -- Line: 493
                    -- upvalues: u40 (copy)
                    u40:Play();
                end);
                u40.Completed:Connect(function() -- Line: 498
                    -- upvalues: u37 (copy)
                    wait(3.2);
                    u37.shark1:Destroy();
                    u37.shark2:Destroy();
                    u37.particlePart.particle.Enabled = false;
                end);

                return;
            end;

            if p31 == "Serpent Fire Breath" then
                local v41 = p32[2];
                local particle = p32[1].particlePart.particle;
                particle.Enabled = true;
                v41.Enabled = true;
                wait(1.8);
                particle.Enabled = false;
                v41.Enabled = false;

                return;
            end;

            if p31 == "Serpent Water Sprinklers" then
                local v42 = workspace.serpentWaterSpouts["particlePart" .. tostring(p32)];
                v42.particle.Enabled = true;
                wait(1.5);
                v42.particle.Enabled = false;

                return;
            end;

            if p31 == "Show Serpent Borders" then
                for _, child in pairs(workspace.serpentOutOfBoundsModel:GetChildren()) do
                    child.Transparency = 0;
                    child.particle.Enabled = true;
                end;
            end;
        end;

        return;
    end;

    for _, v in pairs(u30) do
        if v then
            v:Destroy();
        end;
    end;

    local workspace_playerPickupCannonballRing = workspace.playerPickupCannonballRing;
    workspace_playerPickupCannonballRing.light.Enabled = false;
    workspace_playerPickupCannonballRing.Transparency = 1;
    workspace.playerFireCannon.cannon.light.Enabled = false;
    workspace.playerFireCannon.ring.Transparency = 1;
    local cannon = workspace.playerFireCannon.cannon;
    local particle = cannon.particle;
    local light = cannon.light;
    local explosionSound = cannon.explosionSound;
    local workspace_playerFireCannonHitMark = workspace.playerFireCannonHitMark;
    local particle2 = workspace_playerFireCannonHitMark.particle;
    local light2 = workspace_playerFireCannonHitMark.light;
    local explosionSound2 = workspace_playerFireCannonHitMark.explosionSound;
    particle.Enabled = true;
    light.Enabled = true;
    explosionSound:Play();
    wait(0.1);
    particle2.Enabled = true;
    light2.Enabled = true;
    explosionSound2:Play();
    wait(0.1);
    particle.Enabled = false;
    light.Enabled = false;
    wait(1);
    particle2.Enabled = false;
    light2.Enabled = false;
end);
game.ReplicatedStorage.remotes:WaitForChild("steampunkBossSpecficEvents").OnClientEvent:Connect(function(p43, u44) -- Line: 533
    -- upvalues: TweenService (copy), u2 (copy), CameraShaker (copy), Debris (copy), Random_new_ret (copy)
    if p43 == "Drop Cogs" then
        for _, child in pairs(u44:GetChildren()) do
            if child:IsA("Model") then
                for _, child2 in pairs(child:GetChildren()) do
                    local v45 = {
                        CFrame = child2.CFrame + Vector3.new(0, -100, 0)
                    };
                    TweenService:Create(child2, TweenInfo.new(0.75, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, 0, false, 0), v45):Play();
                end;
            end;
        end;

        return;
    end;

    if p43 == "Shake Screens" then
        u2:Shake(CameraShaker.Presets[u44]);

        return;
    end;

    if p43 ~= "Second Boss Pulse Wave" then
        if p43 ~= "Second Boss Aura" then
            if p43 == "Second Boss Random Pulse" then
                u44.wave.ringglow.Transparency = 0.5;
                u44.precast.Transparency = 0.6;
                local TweenInfo_new_ret = TweenInfo.new(0.2, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, 0, false, 0);
                local v46 = TweenService:Create(u44.wave, TweenInfo_new_ret, {
                    Size = Vector3.new(30, 1, 30)
                });
                v46:Play();
                v46.Completed:Connect(function() -- Line: 609
                    -- upvalues: u44 (copy)
                    u44.precast.Transparency = 0.85;
                    u44.wave.ringglow.Transparency = 1;
                    u44.wave.Size = Vector3.new(1, 1, 1);
                end);
            end;

            return;
        end;

        local u47 = true;
        spawn(function() -- Line: 575
            -- upvalues: u47 (ref)
            wait(4.8);
            u47 = false;
        end);

        while u47 == true do
            local u48 = game.ReplicatedStorage.enemyProjectiles.secondBossGroundAura:Clone();
            Debris:AddItem(u48, 1);
            u48.Parent = workspace;
            local CFrame_Angles = CFrame.Angles;
            local v49 = Random_new_ret:NextInteger(-180, 180);
            u48.CFrame = (u44 + Vector3.new(0, -5.5, 0)) * CFrame_Angles(0, math.rad(v49), 0);
            local v50 = {
                Size = Vector3.new(60, 10, 60),
                Transparency = 1,
                CFrame = u48.CFrame + Vector3.new(0, 5, 0)
            };
            local v51 = TweenService:Create(u48, TweenInfo.new(0.7, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, 0, false, 0), v50);
            v51:Play();
            v51.Completed:Connect(function() -- Line: 593
                -- upvalues: u48 (copy)
                u48:Destroy();
            end);
            wait(0.1);
        end;

        return;
    end;

    local u52 = game.ReplicatedStorage.enemyProjectiles.secondBossWave:Clone();
    Debris:AddItem(u52, 1);
    u52.Parent = workspace;
    u52.CFrame = u44 + Vector3.new(0, -5.5, 0);
    local v53 = TweenService:Create(u52, TweenInfo.new(0.25, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, 0, false, 0), {
        Size = Vector3.new(280, 4, 280)
    });
    v53:Play();
    v53.Completed:Connect(function() -- Line: 567
        -- upvalues: u52 (copy)
        u52:Destroy();
    end);
end);
game.ReplicatedStorage.remotes:WaitForChild("orbitalBossSpecficEvents").OnClientEvent:Connect(function(p54, u55) -- Line: 618
    -- upvalues: u2 (copy), CameraShaker (copy), Debris (copy), TweenService (copy), Random_new_ret (copy)
    if p54 == "Shake Screens" then
        u2:Shake(CameraShaker.Presets[u55]);

        return;
    end;

    if p54 == "First Boss Rocket Shot" then
        local u56 = game.ReplicatedStorage.enemyProjectiles.firstBossRocket:Clone();
        Debris:AddItem(u56, 4);
        u56.Parent = workspace;
        u56:SetPrimaryPartCFrame(u55 + Vector3.new(0, 70, 0));
        local TweenInfo_new_ret = TweenInfo.new(1, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, 0, false, 0);
        local v57 = TweenService:Create(u56.PrimaryPart, TweenInfo_new_ret, {
            CFrame = u55
        });
        v57.Completed:Connect(function() -- Line: 636
            -- upvalues: Debris (ref), u55 (copy), TweenService (ref), u56 (copy)
            local v58 = game.ReplicatedStorage.enemyProjectiles.genericNeonBall:Clone();
            v58.Color = Color3.fromRGB(255, 85, 0);
            Debris:AddItem(v58, 3);
            v58.Parent = workspace;
            v58.CFrame = u55;
            v58.Transparency = 0;
            TweenService:Create(v58, TweenInfo.new(0.45, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, 0, false, 0), {
                Size = Vector3.new(30, 30, 30),
                Transparency = 1
            }):Play();
            v58.explosive:Play();

            for _, child in pairs(u56:GetChildren()) do
                child.Transparency = 1;
            end;
        end);
        v57:Play();

        return;
    end;

    if p54 == "First Boss Rocket Smoke" then
        local launchPart = u55.leftRocketPack.launchPart;
        local launchPart2 = u55.rightRocketPack.launchPart;

        for i = 1, 15 do
            local v59;

            if i % 2 == 0 then
                v59 = launchPart;
            else
                v59 = launchPart2;
            end;

            local v60 = game.ReplicatedStorage.enemyProjectiles.genericNeonBall:Clone();
            v60.Transparency = 0;
            v60.Color = Color3.fromRGB(255, 85, 0);
            Debris:AddItem(v60, 3);
            v60.Parent = workspace;
            local CFrame2 = v59.CFrame;
            local v61 = Random_new_ret:NextInteger(-3, 3);
            v60.CFrame = CFrame2 + Vector3.new(v61, 0, Random_new_ret:NextInteger(-3, 3));
            v60.explosive.PlaybackSpeed = Random_new_ret:NextNumber(1.4, 1.6);
            v60.explosive:Play();
            TweenService:Create(v60, TweenInfo.new(0.45, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, 0, false, 0), {
                Size = Vector3.new(8, 8, 8),
                Transparency = 1
            }):Play();
            wait(0.066);
            local _ = i;
        end;

        return;
    end;

    if p54 == "First Boss Flame Thrower" then
        u55.Enabled = true;
        wait(1.1);
        u55.Enabled = false;

        return;
    end;

    if p54 == "First Boss Player Caught Fire" then
        local Humanoid = u55.Humanoid;
        local u62 = game.ReplicatedStorage.enemyProjectiles.firstBossPlayerOnFire:Clone();
        Debris:AddItem(u62, 5);
        u62.Parent = workspace;
        local u63 = nil;
        u63 = game:GetService("RunService").Heartbeat:Connect(function() -- Line: 704
            -- upvalues: Humanoid (copy), u62 (copy), u55 (copy), u63 (ref)
            if Humanoid.Health > 0 then
                u62:SetPrimaryPartCFrame(u55.HumanoidRootPart.CFrame);

                return;
            end;

            u63:Disconnect();
            u63 = nil;
        end);
        wait(4);

        if u63 ~= nil then
            u63:Disconnect();
            u63 = nil;
        end;

        u62.Union.Transparency = 1;
        u62.PrimaryPart.flames.Enabled = false;

        return;
    end;

    if p54 == "First Boss Gatling Gun" then
        for i = 1, 20 do
            local v64 = game.ReplicatedStorage.enemyProjectiles.genericNeonBall:Clone();
            v64.Transparency = 0;
            v64.Color = Color3.fromRGB(255, 226, 0);
            Debris:AddItem(v64, 3);
            v64.Parent = workspace;
            local CFrame2 = u55.CFrame;
            local v65 = Random_new_ret:NextInteger(-1, 1);
            local v66 = Random_new_ret:NextInteger(-1, 1);
            v64.CFrame = CFrame2 + Vector3.new(v65, v66, Random_new_ret:NextInteger(-1, 1));
            v64.gunShot.PlaybackSpeed = Random_new_ret:NextNumber(1, 1.25);
            v64.gunShot:Play();
            TweenService:Create(v64, TweenInfo.new(0.45, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, 0, false, 0), {
                Size = Vector3.new(4.5, 4.5, 4.5),
                Transparency = 1
            }):Play();
            wait(0.1);
            local _ = i;
        end;

        return;
    end;

    if p54 == "First Boss Minion Explode" then
        local v67 = game.ReplicatedStorage.enemyProjectiles.genericNeonBall:Clone();
        v67.Transparency = 0;
        v67.Color = Color3.fromRGB(255, 85, 0);
        Debris:AddItem(v67, 3);
        v67.Parent = workspace;
        v67.CFrame = u55;
        v67.explosive:Play();
        TweenService:Create(v67, TweenInfo.new(0.55, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, 0, false, 0), {
            Size = Vector3.new(25, 25, 25),
            Transparency = 1
        }):Play();

        return;
    end;

    if p54 == "Third Boss Lights Out" then
        local bossRoomWhiteLights = workspace.Map.Lighting.PointLight.bossRoomWhiteLights;

        for _, child in pairs(bossRoomWhiteLights:GetChildren()) do
            child.PointLight.Enabled = false;
        end;

        for _, child in pairs(workspace.Map.Props.Fixtures.thirdBossLightsOut:GetChildren()) do
            child.Transparency = 1;
        end;

        wait(3.5);

        for _, child in pairs(bossRoomWhiteLights:GetChildren()) do
            child.PointLight.Enabled = true;
        end;

        for _, child in pairs(workspace.Map.Props.Fixtures.thirdBossLightsOut:GetChildren()) do
            child.Transparency = 0;
        end;

        return;
    end;

    if p54 ~= "Third Boss Life Steal" then
        if p54 == "Third Boss Life Steal Hit" then
            local v68 = u55[1];
            local v69 = u55[2];
            local _ = v69.HumanoidRootPart;
            local v70 = game.ReplicatedStorage.enemyProjectiles.thirdBossLifeStealBeamEffect.Beam:Clone();
            v70.Parent = workspace;
            Debris:AddItem(v70, 1);
            v70.Attachment0 = v69.Head.NeckRigAttachment;
            v70.Attachment1 = v68.Head.NeckRigAttachment;
        end;

        return;
    end;

    local PrimaryPartCFrame = u55:GetPrimaryPartCFrame();
    local u71 = game.ReplicatedStorage.enemyProjectiles.thirdBossLifeStealBeams:Clone();
    Debris:AddItem(u71, 7);
    u71.Parent = workspace;
    u71:SetPrimaryPartCFrame(PrimaryPartCFrame + PrimaryPartCFrame.LookVector * 4);

    for _, child in pairs(u71:GetChildren()) do
        if child.Name == "beam" or child.Name == "mainBeam" then
            spawn(function() -- Line: 788
                -- upvalues: TweenService (ref), child (copy), u71 (copy)
                local v72 = TweenService:Create(child, TweenInfo.new(0.48, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, 0, false, 0), {
                    Transparency = 0
                });
                v72.Completed:Connect(function() -- Line: 794
                    -- upvalues: u71 (ref), child (ref), TweenService (ref)
                    local v73 = {
                        CFrame = u71.PrimaryPart.CFrame + u71.PrimaryPart.CFrame.LookVector * (child.Size.Z / 2)
                    };
                    local v74 = TweenService:Create(child, TweenInfo.new(0.8, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, 0, false, 0), v73);
                    v74.Completed:Connect(function() -- Line: 800
                        -- upvalues: child (ref), TweenService (ref)
                        if child.Name == "mainBeam" then
                            TweenService:Create(child, TweenInfo.new(0.4, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, 0, false, 0), {
                                Size = Vector3.new(34, 34, 150),
                                Transparency = 1
                            }):Play();

                            return;
                        end;

                        child.Transparency = 1;
                    end);
                    v74:Play();
                end);
                v72:Play();
            end);
        end;
    end;
end);

local function moveAnimation(u75) -- Line: 837
    spawn(function() -- Line: 838
        -- upvalues: u75 (copy)
        wait(2);
        local HumanoidRootPart = u75:WaitForChild("HumanoidRootPart");
        local Humanoid = u75:WaitForChild("Humanoid");
        local v76 = Humanoid:LoadAnimation(Humanoid:FindFirstChild("walkAnim") or Humanoid:FindFirstChild("run"));
        local v77 = Humanoid:LoadAnimation(Humanoid.idle);
        local v78 = u75.Name == "Artillery Lava Walker" and 0.5 or 1;
        v77:Play();
        local Position = HumanoidRootPart.Position;

        while Humanoid.Health > 0 do
            if (Position - HumanoidRootPart.Position).Magnitude > 0.5 then
                if not v76.IsPlaying then
                    print("play duh jont");
                    v76:Play();
                    v76:AdjustSpeed(v78);
                end;
            else
                v76:Stop();
            end;

            Position = HumanoidRootPart.Position;
            wait(0.2);
        end;
    end);
end;

CollectionService:GetInstanceAddedSignal("Spider Mob"):Connect(function(u79) -- Line: 867
    spawn(function() -- Line: 838
        -- upvalues: u79 (copy)
        wait(2);
        local HumanoidRootPart = u79:WaitForChild("HumanoidRootPart");
        local Humanoid = u79:WaitForChild("Humanoid");
        local v80 = Humanoid:LoadAnimation(Humanoid:FindFirstChild("walkAnim") or Humanoid:FindFirstChild("run"));
        local v81 = Humanoid:LoadAnimation(Humanoid.idle);
        local v82 = u79.Name == "Artillery Lava Walker" and 0.5 or 1;
        v81:Play();
        local Position = HumanoidRootPart.Position;

        while Humanoid.Health > 0 do
            if (Position - HumanoidRootPart.Position).Magnitude > 0.5 then
                if not v80.IsPlaying then
                    print("play duh jont");
                    v80:Play();
                    v80:AdjustSpeed(v82);
                end;
            else
                v80:Stop();
            end;

            Position = HumanoidRootPart.Position;
            wait(0.2);
        end;
    end);
end);
local u83 = {};

for _, v in pairs(CollectionService:GetTagged("Spider Mob")) do
    spawn(function() -- Line: 838
        -- upvalues: v (copy)
        wait(2);
        local HumanoidRootPart = v:WaitForChild("HumanoidRootPart");
        local Humanoid = v:WaitForChild("Humanoid");
        local v84 = Humanoid:LoadAnimation(Humanoid:FindFirstChild("walkAnim") or Humanoid:FindFirstChild("run"));
        local v85 = Humanoid:LoadAnimation(Humanoid.idle);
        local v86 = v.Name == "Artillery Lava Walker" and 0.5 or 1;
        v85:Play();
        local Position = HumanoidRootPart.Position;

        while Humanoid.Health > 0 do
            if (Position - HumanoidRootPart.Position).Magnitude > 0.5 then
                if not v84.IsPlaying then
                    print("play duh jont");
                    v84:Play();
                    v84:AdjustSpeed(v86);
                end;
            else
                v84:Stop();
            end;

            Position = HumanoidRootPart.Position;
            wait(0.2);
        end;
    end);
end;

game.ReplicatedStorage.remotes:WaitForChild("volcanicBossSpecficEvents").OnClientEvent:Connect(function(p87, u88) -- Line: 874
    -- upvalues: u2 (copy), CameraShaker (copy), Debris (copy), TweenService (copy), u83 (copy), Random_new_ret (copy), RunService (copy)
    if p87 == "Shake Screens" then
        u2:Shake(CameraShaker.Presets[u88]);

        return;
    end;

    if p87 == "First Boss Sky Shot" then
        local v89 = game.ReplicatedStorage.enemyProjectiles.firstBossSkyShot:Clone();
        Debris:AddItem(v89, 3.5);
        v89:SetPrimaryPartCFrame(CFrame.new(u88));
        v89.Parent = workspace;
        wait(0.9);

        for i = 1, 6 do
            v89.Union.Beam1.Width0 = 20;
            v89.Union.Beam1.Width1 = 20;
            v89.Union.Beam2.Width0 = 20;
            v89.Union.Beam2.Width1 = 20;
            v89.precast.Transparency = 0;
            TweenService:Create(v89.Union.Beam1, TweenInfo.new(0.15, Enum.EasingStyle.Linear, Enum.EasingDirection.Out), {
                Width0 = 0,
                Width1 = 0
            }):Play();
            TweenService:Create(v89.Union.Beam2, TweenInfo.new(0.15, Enum.EasingStyle.Linear, Enum.EasingDirection.Out), {
                Width0 = 0,
                Width1 = 0
            }):Play();
            TweenService:Create(v89.precast, TweenInfo.new(0.15, Enum.EasingStyle.Linear, Enum.EasingDirection.Out), {
                Transparency = 0.9
            }):Play();
            wait(0.3);
            local _ = i;
        end;

        v89:Destroy();

        return;
    end;

    if p87 ~= "First Boss Orb Explosion" then
        if p87 == "First Boss Turret Spawn" then
            local ring1 = u88:WaitForChild("ring1");
            local ring2 = u88:WaitForChild("ring2");
            TweenService:Create(ring1, TweenInfo.new(1.5, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, -1, true), {
                Orientation = Vector3.new(360, 0, 0)
            }):Play();
            TweenService:Create(ring2, TweenInfo.new(1.5, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, -1, true), {
                Orientation = Vector3.new(0, 0, 360)
            }):Play();

            return;
        end;

        if p87 ~= "Second Boss Rock Fall" then
            if p87 == "Second Boss Geyser Spawn" then
                u88:WaitForChild("base"):WaitForChild("Attachment"):WaitForChild("ParticleEmitter").Enabled = true;

                return;
            end;

            if p87 == "Second Boss Player Hold Rock" then
                local HumanoidRootPart = u88:FindFirstChild("HumanoidRootPart");

                if HumanoidRootPart then
                    local u90 = game.ReplicatedStorage.enemyProjectiles.secondBossOverheadRock:Clone();
                    u90.Parent = workspace;
                    u90.CFrame = HumanoidRootPart.CFrame + Vector3.new(0, 6, 0);
                    u90.WeldConstraint.Part0 = HumanoidRootPart;
                    u83[u88] = u90;
                    u88.AncestryChanged:Connect(function() -- Line: 956
                        -- upvalues: u88 (copy), u90 (copy), u83 (ref)
                        if not u88:IsDescendantOf(game) then
                            u90:Destroy();
                            u83[u88] = nil;
                        end;
                    end);

                    return;
                end;
            elseif p87 == "Second Boss Player Drop Rock" then
                if u83[u88] then
                    u83[u88]:Destroy();

                    return;
                end;
            else
                if p87 == "Second Boss Destroy All Overhead Rocks" then
                    for _, v in pairs(u83) do
                        if v then
                            v:Destroy();
                        end;
                    end;

                    return;
                end;

                if p87 == "Third Boss Curse Char" then
                    local HumanoidRootPart = u88.HumanoidRootPart;

                    for i = 1, 6 do
                        local u91 = game.ReplicatedStorage.enemyProjectiles.thirdBossCurseRing:Clone();
                        Debris:AddItem(u91, 6);
                        u91.CFrame = HumanoidRootPart.CFrame * CFrame.Angles(Random_new_ret:NextNumber(0, 6.28), Random_new_ret:NextNumber(0, 6.28), Random_new_ret:NextNumber(0, 6.28));
                        u91.Parent = workspace;
                        TweenService:Create(u91, TweenInfo.new(0.7, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, -1, true), {
                            Orientation = Vector3.new(360, 0, 0)
                        }):Play();
                        TweenService:Create(u91, TweenInfo.new(6, Enum.EasingStyle.Linear, Enum.EasingDirection.Out), {
                            Size = Vector3.new(0.5, 3, 3)
                        }):Play();
                        RunService.Heartbeat:Connect(function() -- Line: 988
                            -- upvalues: u91 (copy), HumanoidRootPart (copy)
                            u91.Position = HumanoidRootPart.Position;
                        end);
                        local _ = i;
                    end;

                    return;
                end;

                if p87 == "Third Boss Curse Explosion" then
                    local HumanoidRootPart = u88.HumanoidRootPart;
                    local v92 = game.ReplicatedStorage.projectiles.genericNeonBall:Clone();
                    v92.Transparency = 0;
                    v92.Color = Color3.fromRGB(255, 0, 0);
                    Debris:AddItem(v92, 3);
                    v92.Parent = workspace;
                    v92.CFrame = HumanoidRootPart.CFrame;
                    TweenService:Create(v92, TweenInfo.new(0.8, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
                        Size = Vector3.new(170, 170, 170),
                        Transparency = 1
                    }):Play();

                    return;
                end;

                if p87 == "Third Boss Curse Sizzle" then
                    local HumanoidRootPart = u88.HumanoidRootPart;
                    local v93 = game.ReplicatedStorage.projectiles.genericNeonBall:Clone();
                    v93.Transparency = 1;
                    v93.Size = Vector3.new(0.1, 0.1, 0.1);
                    v93.Color = Color3.fromRGB(0, 255, 0);
                    Debris:AddItem(v93, 3);
                    v93.Parent = workspace;
                    v93.CFrame = HumanoidRootPart.CFrame;
                    TweenService:Create(v93, TweenInfo.new(0.25, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, 0, true), {
                        Size = Vector3.new(27, 27, 27),
                        Transparency = 0
                    }):Play();

                    return;
                end;

                if p87 == "Third Boss Dual Swing Crescent" then
                    local v94 = game.ReplicatedStorage.enemyProjectiles.thirdBossCrescent:Clone();
                    Debris:AddItem(v94, 3);
                    v94.PrimaryPart.CFrame = u88;
                    v94.Parent = workspace;
                    TweenService:Create(v94.PrimaryPart, TweenInfo.new(0.3, Enum.EasingStyle.Linear, Enum.EasingDirection.Out), {
                        CFrame = u88 + u88.LookVector * 220
                    }):Play();

                    return;
                end;

                if p87 == "Third Boss Link Players" then
                    local v95 = u88[1];
                    local v96 = u88[2];
                    local v97 = game.ReplicatedStorage.enemyProjectiles.thirdBossFrozenCircle:Clone();
                    Debris:AddItem(v97, 5);
                    v97.Parent = workspace;
                    v97.CFrame = v95.HumanoidRootPart.CFrame;
                    v97.WeldConstraint.Part0 = v95.HumanoidRootPart;
                    local v98 = game.ReplicatedStorage.enemyProjectiles.thirdBossFrozenCircle:Clone();
                    Debris:AddItem(v98, 5);
                    v98.Parent = workspace;
                    v98.CFrame = v96.HumanoidRootPart.CFrame;
                    v98.WeldConstraint.Part0 = v96.HumanoidRootPart;
                    local v99 = game.ReplicatedStorage.enemyProjectiles.thirdBossLinkBeam:Clone();
                    Debris:AddItem(v99, 5);
                    v99.Attachment0 = v95.HumanoidRootPart.RootRigAttachment;
                    v99.Attachment1 = v96.HumanoidRootPart.RootRigAttachment;
                    local v100 = game.ReplicatedStorage.enemyProjectiles.thirdBossLinkBeam:Clone();
                    Debris:AddItem(v100, 5);
                    v100.Attachment0 = v96.HumanoidRootPart.RootRigAttachment;
                    v100.Attachment1 = v95.HumanoidRootPart.RootRigAttachment;
                    local u101 = true;
                    spawn(function() -- Line: 1052
                        -- upvalues: u101 (ref)
                        wait(5);
                        u101 = false;
                    end);
                    v99.Parent = workspace;
                    v100.Parent = workspace;

                    while u101 == true do
                        if (v95.HumanoidRootPart.Position - v96.HumanoidRootPart.Position).Magnitude < 12 then
                            v97.Color = Color3.fromRGB(0, 255, 0);
                            v98.Color = Color3.fromRGB(0, 255, 0);
                            v99.Color = ColorSequence.new(Color3.fromRGB(0, 255, 0));
                            v100.Color = ColorSequence.new(Color3.fromRGB(0, 255, 0));
                        else
                            v97.Color = Color3.fromRGB(255, 0, 0);
                            v98.Color = Color3.fromRGB(255, 0, 0);
                            v99.Color = ColorSequence.new(Color3.fromRGB(255, 0, 0));
                            v100.Color = ColorSequence.new(Color3.fromRGB(255, 0, 0));
                        end;

                        wait(0.1);
                    end;

                    return;
                end;

                if p87 == "Third Boss Raise Lava" then
                    TweenService:Create(workspace.thirdBossFirewall, TweenInfo.new(1, Enum.EasingStyle.Linear, Enum.EasingDirection.Out), {
                        CFrame = workspace.thirdBossFirewall.CFrame + Vector3.new(0, 300, 0)
                    }):Play();
                    wait(5);
                    TweenService:Create(workspace.thirdBossFirewall, TweenInfo.new(1, Enum.EasingStyle.Linear, Enum.EasingDirection.Out), {
                        CFrame = workspace.thirdBossFirewall.CFrame - Vector3.new(0, 300, 0)
                    }):Play();

                    return;
                end;

                if p87 == "Artillery Mob Shot" then
                    local v102 = u88[1];
                    local v103 = u88[2];
                    v102.mainModel.mainModel.Attachment.particle.Enabled = true;
                    wait(0.15);
                    v102.mainModel.mainModel.Attachment.particle.Enabled = false;
                    wait(0.25);
                    local u104 = game.ReplicatedStorage.enemyProjectiles.artilleryRock:Clone();
                    Debris:AddItem(u104, 2);
                    u104.CFrame = v103 + Vector3.new(0, 100, 0);
                    u104.Parent = workspace;
                    local v105 = TweenService:Create(u104, TweenInfo.new(0.5, Enum.EasingStyle.Linear, Enum.EasingDirection.Out), {
                        CFrame = v103
                    });
                    v105.Completed:Connect(function() -- Line: 1093
                        -- upvalues: u104 (copy), TweenService (ref)
                        u104.explosion1:Play();
                        u104.particle2.Enabled = false;
                        u104.PointLight.Enabled = false;
                        TweenService:Create(u104, TweenInfo.new(0.35, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
                            Size = Vector3.new(15, 15, 15),
                            Transparency = 1
                        }):Play();
                    end);
                    v105:Play();

                    return;
                end;

                if p87 == "Explosive Mob Shot" then
                    u88.mainModel.mainModel.Attachment.particle.Enabled = true;
                    wait(0.15);
                    u88.mainModel.mainModel.Attachment.particle.Enabled = false;
                end;
            end;

            return;
        end;

        local u106 = game.ReplicatedStorage.enemyProjectiles.secondBossRock:Clone();
        Debris:AddItem(u106, 2);
        u106.CFrame = u88 + Vector3.new(0, 250, 0);
        u106.Parent = workspace;
        local v107 = TweenService:Create(u106, TweenInfo.new(1.5, Enum.EasingStyle.Linear, Enum.EasingDirection.Out), {
            CFrame = u88
        });
        v107.Completed:Connect(function() -- Line: 930
            -- upvalues: u106 (copy), Debris (ref), u88 (copy), TweenService (ref)
            u106.explosion1:Play();
            local v108 = game.ReplicatedStorage.projectiles.genericNeonBall:Clone();
            v108.Transparency = 0;
            v108.Color = Color3.fromRGB(255, 0, 0);
            Debris:AddItem(v108, 5);
            v108.Parent = workspace;
            v108.CFrame = u88;
            TweenService:Create(v108, TweenInfo.new(0.4, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
                Size = Vector3.new(42, 42, 42),
                Transparency = 1
            }):Play();
        end);
        v107:Play();

        return;
    end;

    local v109 = game.ReplicatedStorage.projectiles.genericNeonBall:Clone();
    v109.Transparency = 0;
    v109.Color = Color3.fromRGB(255, 0, 0);
    Debris:AddItem(v109, 5);
    v109.Parent = workspace;
    v109.CFrame = u88;
    local v110 = game.ReplicatedStorage.projectiles.sounds.Explosion:Clone();
    Debris:AddItem(v110, 2);
    v110.Parent = v109;
    v110:Play();
    TweenService:Create(v109, TweenInfo.new(0.4, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
        Size = Vector3.new(60, 60, 60),
        Transparency = 1
    }):Play();
end);
CollectionService:GetInstanceAddedSignal("runAnimations"):Connect(function(u111) -- Line: 1110
    spawn(function() -- Line: 838
        -- upvalues: u111 (copy)
        wait(2);
        local HumanoidRootPart = u111:WaitForChild("HumanoidRootPart");
        local Humanoid = u111:WaitForChild("Humanoid");
        local v112 = Humanoid:LoadAnimation(Humanoid:FindFirstChild("walkAnim") or Humanoid:FindFirstChild("run"));
        local v113 = Humanoid:LoadAnimation(Humanoid.idle);
        local v114 = u111.Name == "Artillery Lava Walker" and 0.5 or 1;
        v113:Play();
        local Position = HumanoidRootPart.Position;

        while Humanoid.Health > 0 do
            if (Position - HumanoidRootPart.Position).Magnitude > 0.5 then
                if not v112.IsPlaying then
                    print("play duh jont");
                    v112:Play();
                    v112:AdjustSpeed(v114);
                end;
            else
                v112:Stop();
            end;

            Position = HumanoidRootPart.Position;
            wait(0.2);
        end;
    end);
end);

for _, v in pairs(CollectionService:GetTagged("runAnimations")) do
    spawn(function() -- Line: 838
        -- upvalues: v (copy)
        wait(2);
        local HumanoidRootPart = v:WaitForChild("HumanoidRootPart");
        local Humanoid = v:WaitForChild("Humanoid");
        local v115 = Humanoid:LoadAnimation(Humanoid:FindFirstChild("walkAnim") or Humanoid:FindFirstChild("run"));
        local v116 = Humanoid:LoadAnimation(Humanoid.idle);
        local v117 = v.Name == "Artillery Lava Walker" and 0.5 or 1;
        v116:Play();
        local Position = HumanoidRootPart.Position;

        while Humanoid.Health > 0 do
            if (Position - HumanoidRootPart.Position).Magnitude > 0.5 then
                if not v115.IsPlaying then
                    print("play duh jont");
                    v115:Play();
                    v115:AdjustSpeed(v117);
                end;
            else
                v115:Stop();
            end;

            Position = HumanoidRootPart.Position;
            wait(0.2);
        end;
    end);
end;

game.ReplicatedStorage.remotes:WaitForChild("aquaticBossSpecficEvents").OnClientEvent:Connect(function(p118, p119) -- Line: 1117
    -- upvalues: u2 (copy), CameraShaker (copy), Debris (copy), RunService (copy), timeSync (copy), TweenService (copy)
    if p118 == "Shake Screens" then
        u2:Shake(CameraShaker.Presets[p119]);

        return;
    end;

    if p118 == "second boss show damage parts" then
        for _, child in pairs(workspace.secondBossDamageParts:GetChildren()) do
            child.Transparency = 0;
        end;

        return;
    end;

    if p118 == "first boss moving orb" then
        local u120 = p119[1];
        local u121 = p119[2];
        local u122 = p119[3];
        local u123 = p119[4];
        local u124 = p119[5];
        local u125 = game.ReplicatedStorage.enemyProjectiles.firstBossMoveOrb:Clone();
        u125.Name = "Model";
        Debris:AddItem(u125, 10);
        u125.CFrame = u120;
        u125.Parent = workspace;
        local u126 = nil;
        u126 = RunService.Heartbeat:Connect(function() -- Line: 1143
            -- upvalues: timeSync (ref), u122 (copy), u126 (ref), u125 (copy), TweenService (ref), u120 (copy), u123 (copy), u121 (copy), u124 (copy)
            local Time = timeSync:GetTime();

            if u122 < Time then
                u126:Disconnect();
                u126 = nil;
                u125.PointLight.Enabled = false;
                u125.Trail.Enabled = false;
                u125.particles.Enabled = false;
                TweenService:Create(u125, TweenInfo.new(1, Enum.EasingStyle.Linear, Enum.EasingDirection.Out), {
                    Transparency = 1
                }):Play();
                wait(1);
                u125:Destroy();
            end;

            u125.CFrame = u120 + u120.LookVector * (u123 * math.clamp((Time - u121) / u124, 0, 1));
        end);

        return;
    end;

    if p118 ~= "first boss laser shot" then
        if p118 ~= "third boss smite" then
            if p118 == "last boss mark character" then
                local HumanoidRootPart = p119:FindFirstChild("HumanoidRootPart");
                local Humanoid = p119:FindFirstChild("Humanoid");

                if HumanoidRootPart and (Humanoid and Humanoid.Health > 0) then
                    game.ReplicatedStorage.enemyProjectiles.lastBossCharMarkHolder.lastBossCharMark:Clone().Parent = HumanoidRootPart;

                    return;
                end;
            elseif p118 == "last boss remove mark" then
                local HumanoidRootPart = p119:FindFirstChild("HumanoidRootPart");

                if HumanoidRootPart then
                    for _, child in pairs(HumanoidRootPart:GetChildren()) do
                        if child.Name == "lastBossCharMark" then
                            child:Destroy();
                            local v127 = game.ReplicatedStorage.projectiles.genericNeonBall:Clone();
                            v127.Transparency = 0;
                            v127.Color = Color3.fromRGB(0, 255, 0);
                            Debris:AddItem(v127, 5);
                            v127.Parent = workspace;
                            v127.CFrame = HumanoidRootPart.CFrame;
                            TweenService:Create(v127, TweenInfo.new(0.4, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
                                Size = Vector3.new(25, 25, 25),
                                Transparency = 1
                            }):Play();
                        end;
                    end;

                    return;
                end;
            elseif p118 == "last boss moving orb" then
                local u128 = p119[1];
                local u129 = p119[2];
                local u130 = p119[3];
                local u131 = p119[4];
                local u132 = p119[5];
                local u133 = game.ReplicatedStorage.enemyProjectiles.finalBossOrbShot:Clone();
                u133.Name = "Model";
                Debris:AddItem(u133, 5);
                u133.CFrame = u128;
                u133.Parent = workspace;
                local u134 = nil;
                u134 = RunService.Heartbeat:Connect(function() -- Line: 1273
                    -- upvalues: timeSync (ref), u130 (copy), u134 (ref), u133 (copy), TweenService (ref), u128 (copy), u131 (copy), u129 (copy), u132 (copy)
                    local Time = timeSync:GetTime();

                    if u130 < Time then
                        u134:Disconnect();
                        u134 = nil;
                        u133.PointLight.Enabled = false;
                        u133.Trail.Enabled = false;
                        u133.lastBossCharMark.Bits.Enabled = false;
                        TweenService:Create(u133, TweenInfo.new(1, Enum.EasingStyle.Linear, Enum.EasingDirection.Out), {
                            Transparency = 1
                        }):Play();
                    end;

                    u133.CFrame = u128 + u128.LookVector * (u131 * math.clamp((Time - u129) / u132, 0, 1));
                end);
            end;

            return;
        end;

        local v135 = game.ReplicatedStorage.enemyProjectiles.thirdBossSmite:Clone();
        Debris:AddItem(v135, 5);
        v135.Position = p119.Position;
        v135.Parent = workspace;
        v135.particles1:Emit(30);
        v135.particles2:Emit(30);
        wait(0.3);
        v135.Beam.Enabled = false;

        return;
    end;

    local u136 = p119[1];
    local u137 = p119[2];
    local u138 = p119[3];
    local u139 = p119[4];
    local v140 = p119[5];
    local v141 = p119[6];
    local u142 = u137 - u136;
    local v143 = game.ReplicatedStorage.enemyProjectiles.firstBossLaserPrecast:Clone();
    v143.Name = "Model";
    Debris:AddItem(v143, 6);
    v143:SetPrimaryPartCFrame(u138);
    v143.Parent = workspace;
    TweenService:Create(v143.precast, TweenInfo.new(0.22, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, 0, true), {
        Transparency = 0
    }):Play();
    local u144 = game.ReplicatedStorage.enemyProjectiles.firstBossAttachPart:Clone();
    Debris:AddItem(u144, 10);
    u144.CFrame = u138;
    u144.Parent = workspace;
    u144.Trail.Enabled = true;
    local Beam = v140["top" .. v141]["top" .. v141 .. "Main"].Beam;
    Beam.Attachment1 = u144.Attachment;
    local u145 = false;
    local u146 = nil;
    u146 = RunService.Heartbeat:Connect(function() -- Line: 1193
        -- upvalues: timeSync (ref), u145 (ref), u136 (copy), Beam (copy), u144 (copy), u137 (copy), u146 (ref), u139 (copy), u142 (copy), u138 (copy)
        local Time = timeSync:GetTime();

        if u145 == false then
            if u136 < Time then
                u145 = true;
                Beam.Enabled = true;
                u144.particles.Enabled = true;
            end;
        else
            if u137 < Time then
                u146:Disconnect();
                u146 = nil;
                Beam.Enabled = false;
                u144.particles.Enabled = false;

                return;
            end;

            local v147 = u139 * math.clamp((Time - u136) / u142, 0, 1);
            u144.CFrame = u138 + u138.LookVector * v147;
        end;
    end);
end);
game.ReplicatedStorage.remotes:WaitForChild("enchantedBossSpecficEvents").OnClientEvent:Connect(function(p148, p149) -- Line: 1292
    -- upvalues: u2 (copy), CameraShaker (copy), Debris (copy), RunService (copy), timeSync (copy), TweenService (copy)
    if p148 == "Shake Screens" then
        u2:Shake(CameraShaker.Presets[p149]);

        return;
    end;

    if p148 ~= "First Boss Crystal Drop" then
        if p148 == "First Boss Crystal Drop Explosion" then
            local HumanoidRootPart = p149:FindFirstChild("HumanoidRootPart");

            if HumanoidRootPart then
                local CFrame2 = HumanoidRootPart.CFrame;
                local v150 = game.ReplicatedStorage.projectiles.genericNeonBall:Clone();
                v150.Transparency = 0;
                v150.Color = Color3.fromRGB(255, 134, 253);
                Debris:AddItem(v150, 3);
                v150.Parent = workspace;
                v150.CFrame = CFrame2;
                TweenService:Create(v150, TweenInfo.new(0.6, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
                    Size = Vector3.new(80, 80, 80),
                    Transparency = 1
                }):Play();

                return;
            end;
        else
            if p148 == "First Boss Player Pick Up Supplies" then
                local v151 = game.ReplicatedStorage.enemyProjectiles.firstBossSupplyOverhead:Clone();
                Debris:AddItem(v151, 8);
                v151:SetPrimaryPartCFrame(p149.HumanoidRootPart.CFrame);
                v151.mainPart.rootPartWeld.Part0 = p149.HumanoidRootPart;
                v151.Parent = p149;

                return;
            end;

            if p148 == "First Boss Remove Player Supplies" then
                local firstBossSupplyOverhead = p149:FindFirstChild("firstBossSupplyOverhead");

                if firstBossSupplyOverhead then
                    firstBossSupplyOverhead:Destroy();

                    return;
                end;
            else
                if p148 == "First Boss Remove All Player Supplies" then
                    local PrimaryPart = p149.PrimaryPart;
                    local v152 = game.ReplicatedStorage.projectiles.genericNeonBall:Clone();
                    v152.Transparency = 0;
                    v152.Color = Color3.fromRGB(255, 134, 253);
                    Debris:AddItem(v152, 3);
                    v152.Parent = workspace;
                    v152.CFrame = PrimaryPart.CFrame + PrimaryPart.CFrame.LookVector * 15;
                    TweenService:Create(v152, TweenInfo.new(0.8, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
                        Size = Vector3.new(200, 200, 200),
                        Transparency = 1
                    }):Play();

                    for _, v in pairs(game.Players:GetPlayers()) do
                        local Character = v.Character;

                        if Character then
                            local firstBossSupplyOverhead = Character:FindFirstChild("firstBossSupplyOverhead");

                            if firstBossSupplyOverhead then
                                firstBossSupplyOverhead:Destroy();
                            end;
                        end;
                    end;

                    return;
                end;

                if p148 == "First Boss Shoot Spinning Orb" then
                    local u153 = p149[2];
                    local u154 = p149[3];
                    local u155 = p149[4];
                    local u156 = p149[5];
                    local u157 = p149[6];
                    local u158 = p149[7];
                    local u159 = p149[8];
                    local u160 = u158 - u157;
                    local u161 = u157 - u156;
                    local CFrame2 = p149[1].PrimaryPart.CFrame;
                    local CFrame_new_ret = CFrame.new(CFrame2.Position, u153.Position);
                    local Magnitude = (u153.Position - CFrame2.Position).Magnitude;
                    local u162 = u156 - u154;
                    local u163 = game.ReplicatedStorage.enemyProjectiles.firstBossSpinningRock:Clone();
                    u163:SetPrimaryPartCFrame(CFrame2);
                    Debris:AddItem(u163, 15);
                    u163.Parent = workspace;
                    local u164 = nil;
                    u164 = RunService.Heartbeat:Connect(function() -- Line: 1409
                        -- upvalues: timeSync (ref), u156 (copy), u164 (ref), u153 (copy), u159 (copy), u163 (copy), RunService (ref), u158 (copy), u161 (copy), u157 (copy), u160 (copy), u155 (copy), u154 (copy), u162 (copy), CFrame_new_ret (copy), Magnitude (copy)
                        local Time = timeSync:GetTime();

                        if u156 >= Time then
                            local math_clamp_ret = math.clamp((Time - u154) / u162, 0, 1);
                            u163:SetPrimaryPartCFrame(CFrame_new_ret + CFrame_new_ret.LookVector * (Magnitude * math_clamp_ret));

                            return;
                        end;

                        u164:Disconnect();
                        u164 = nil;
                        local u165 = CFrame.new(u153.Position) * CFrame.Angles(0, math.rad(u159), 0);
                        u163:SetPrimaryPartCFrame(u165);
                        local u166 = nil;
                        u166 = RunService.Heartbeat:Connect(function() -- Line: 1418
                            -- upvalues: timeSync (ref), u158 (ref), u166 (ref), u163 (ref), u156 (ref), u161 (ref), u157 (ref), u160 (ref), u155 (ref), u165 (copy)
                            local Time2 = timeSync:GetTime();

                            if u158 < Time2 then
                                u166:Disconnect();
                                u166 = nil;
                                u163:Destroy();
                            end;

                            if u156 < Time2 then
                                local math_clamp_ret = math.clamp((Time2 - u156) / u161, 0, 1);
                                u163.cylinder.Size = Vector3.new(math_clamp_ret * 50, 1.5, 1.5);
                            end;

                            if u157 < Time2 then
                                u163.cylinder.Trail.Enabled = true;
                                local v167 = u155 * math.clamp((Time2 - u157) / u160, 0, 1);
                                u163:SetPrimaryPartCFrame(u165 * CFrame.Angles(0, math.rad(v167), 0));
                            end;
                        end);
                    end);

                    return;
                end;

                if p148 == "First Boss Crystal Spawn" then
                    p149.crystalFlash.Transparency = 0;
                    TweenService:Create(p149.crystalFlash, TweenInfo.new(0.7, Enum.EasingStyle.Linear, Enum.EasingDirection.Out), {
                        Transparency = 1
                    }):Play();

                    return;
                end;

                if p148 == "First Boss Crystal Hit" then
                    p149.Union.Transparency = 0;
                    p149.precast.Transparency = 0.6;
                    p149.crystalFlash.Transparency = 0;
                    p149.Crystal.particleAttachment.particles:Emit(60);
                    TweenService:Create(p149.Union, TweenInfo.new(0.5, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
                        Transparency = 1
                    }):Play();
                    TweenService:Create(p149.precast, TweenInfo.new(0.5, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
                        Transparency = 1
                    }):Play();
                    TweenService:Create(p149.crystalFlash, TweenInfo.new(0.5, Enum.EasingStyle.Linear, Enum.EasingDirection.Out), {
                        Transparency = 1
                    }):Play();

                    return;
                end;

                if p148 == "First Boss Orb Expand" then
                    TweenService:Create(p149.neon1, TweenInfo.new(1.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                        Size = Vector3.new(40.6, 20.6, 40.6)
                    }):Play();
                    TweenService:Create(p149.neon2, TweenInfo.new(1.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                        Size = Vector3.new(40.4, 20.4, 40.4)
                    }):Play();
                    TweenService:Create(p149.innerBall, TweenInfo.new(1.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                        Size = Vector3.new(40, 20, 40)
                    }):Play();
                    local u168 = TweenService:Create(p149.neon1, TweenInfo.new(0.25, Enum.EasingStyle.Linear, Enum.EasingDirection.Out), {
                        CFrame = p149.neon2.CFrame * CFrame.Angles(0, 2.0943951023931953, 0)
                    });
                    local u169 = TweenService:Create(p149.neon1, TweenInfo.new(0.25, Enum.EasingStyle.Linear, Enum.EasingDirection.Out), {
                        CFrame = p149.neon2.CFrame * CFrame.Angles(0, 4.1887902047863905, 0)
                    });
                    local u170 = TweenService:Create(p149.neon1, TweenInfo.new(0.25, Enum.EasingStyle.Linear, Enum.EasingDirection.Out), {
                        CFrame = p149.neon2.CFrame * CFrame.Angles(0, 6.283185307179586, 0)
                    });
                    u168:Play();
                    u168.Completed:Connect(function() -- Line: 1470
                        -- upvalues: u169 (copy)
                        u169:Play();
                    end);
                    u169.Completed:Connect(function() -- Line: 1471
                        -- upvalues: u170 (copy)
                        u170:Play();
                    end);
                    u170.Completed:Connect(function() -- Line: 1472
                        -- upvalues: u168 (copy)
                        u168:Play();
                    end);
                    local u171 = TweenService:Create(p149.neon2, TweenInfo.new(0.45, Enum.EasingStyle.Linear, Enum.EasingDirection.Out), {
                        CFrame = p149.neon2.CFrame * CFrame.Angles(0, 2.0943951023931953, 0)
                    });
                    local u172 = TweenService:Create(p149.neon2, TweenInfo.new(0.45, Enum.EasingStyle.Linear, Enum.EasingDirection.Out), {
                        CFrame = p149.neon2.CFrame * CFrame.Angles(0, 4.1887902047863905, 0)
                    });
                    local u173 = TweenService:Create(p149.neon2, TweenInfo.new(0.45, Enum.EasingStyle.Linear, Enum.EasingDirection.Out), {
                        CFrame = p149.neon2.CFrame * CFrame.Angles(0, 6.283185307179586, 0)
                    });
                    u171:Play();
                    u171.Completed:Connect(function() -- Line: 1477
                        -- upvalues: u172 (copy)
                        u172:Play();
                    end);
                    u172.Completed:Connect(function() -- Line: 1478
                        -- upvalues: u173 (copy)
                        u173:Play();
                    end);
                    u173.Completed:Connect(function() -- Line: 1479
                        -- upvalues: u171 (copy)
                        u171:Play();
                    end);

                    return;
                end;

                if p148 == "Second Boss Spawn Particles" then
                    local workspace_secondBossSpawnParticles = workspace.secondBossSpawnParticles;
                    workspace_secondBossSpawnParticles.bottom.Mist.Enabled = true;
                    workspace_secondBossSpawnParticles.top.Mist.Enabled = true;
                    wait(7);
                    workspace_secondBossSpawnParticles.bottom.Mist.Enabled = false;
                    workspace_secondBossSpawnParticles.top.Mist.Enabled = false;

                    return;
                end;

                if p148 == "Second Boss Spinning Laser" then
                    local u174 = p149[2];
                    local u175 = p149[3];
                    local u176 = p149[4];
                    local u177 = p149[5];
                    local u178 = p149[6];
                    local u179 = p149[7];
                    local u180 = p149[8];
                    local u181 = u179 - u178;
                    local u182 = u178 - u177;
                    local CFrame2 = p149[1].PrimaryPart.CFrame;
                    local CFrame_new_ret = CFrame.new(CFrame2.Position, u174.Position);
                    local Magnitude = (u174.Position - CFrame2.Position).Magnitude;
                    local u183 = u177 - u175;
                    local u184 = game.ReplicatedStorage.enemyProjectiles.secondBossSpinningLaser:Clone();
                    u184:SetPrimaryPartCFrame(CFrame2);
                    Debris:AddItem(u184, 35);
                    u184.Parent = workspace;
                    local u185 = nil;
                    u185 = RunService.Heartbeat:Connect(function() -- Line: 1514
                        -- upvalues: timeSync (ref), u177 (copy), u185 (ref), u174 (copy), u180 (copy), u184 (copy), RunService (ref), u179 (copy), u182 (copy), u178 (copy), u181 (copy), u176 (copy), u175 (copy), u183 (copy), CFrame_new_ret (copy), Magnitude (copy)
                        local Time = timeSync:GetTime();

                        if u177 >= Time then
                            local math_clamp_ret = math.clamp((Time - u175) / u183, 0, 1);
                            u184:SetPrimaryPartCFrame(CFrame_new_ret + CFrame_new_ret.LookVector * (Magnitude * math_clamp_ret));

                            return;
                        end;

                        u185:Disconnect();
                        u185 = nil;
                        local u186 = CFrame.new(u174.Position) * CFrame.Angles(0, math.rad(u180), 0);
                        u184:SetPrimaryPartCFrame(u186);
                        local u187 = nil;
                        u187 = RunService.Heartbeat:Connect(function() -- Line: 1523
                            -- upvalues: timeSync (ref), u179 (ref), u187 (ref), u184 (ref), u177 (ref), u182 (ref), u178 (ref), u181 (ref), u176 (ref), u186 (copy)
                            local Time2 = timeSync:GetTime();

                            if u179 < Time2 then
                                u187:Disconnect();
                                u187 = nil;
                                u184:Destroy();
                            end;

                            if u177 < Time2 then
                                local math_clamp_ret = math.clamp((Time2 - u177) / u182, 0, 1);
                                u184.cylinder.Size = Vector3.new(math_clamp_ret * 450, 1.5, 1.5);
                            end;

                            if u178 < Time2 then
                                local v188 = u176 * math.clamp((Time2 - u178) / u181, 0, 1);
                                u184:SetPrimaryPartCFrame(u186 * CFrame.Angles(0, math.rad(v188), 0));
                            end;
                        end);
                    end);

                    return;
                end;

                if p148 == "Third Boss Mark Char" then
                    local v189 = game.ReplicatedStorage.enemyProjectiles.thirdBossOverheadRingModel:Clone();
                    Debris:AddItem(v189, 60);
                    v189:SetPrimaryPartCFrame(CFrame.new(p149.HumanoidRootPart.Position));
                    v189.mainPart.rootPartWeld.Part0 = p149.HumanoidRootPart;
                    v189.Parent = p149.HumanoidRootPart;

                    return;
                end;

                if p148 == "Third Boss Unmark Char" then
                    for _, child in pairs(p149.HumanoidRootPart:GetChildren()) do
                        if child.Name == "thirdBossOverheadRingModel" then
                            child:Destroy();
                        end;
                    end;

                    return;
                end;

                if p148 == "Third Boss Mark Remove From All Chars" then
                    for _, v in pairs(p149) do
                        local HumanoidRootPart = v:FindFirstChild("HumanoidRootPart");

                        if HumanoidRootPart then
                            local thirdBossOverheadRingModel = HumanoidRootPart:FindFirstChild("thirdBossOverheadRingModel");

                            if thirdBossOverheadRingModel then
                                thirdBossOverheadRingModel:Destroy();
                            end;
                        end;
                    end;

                    return;
                end;

                if p148 == "Third Boss One Shot Beam" then
                    local u190 = p149[1];
                    local u191 = p149[2];
                    local u192 = nil;
                    u192 = RunService.Heartbeat:Connect(function() -- Line: 1586
                        -- upvalues: timeSync (ref), u191 (copy), u192 (ref), Debris (ref), u190 (copy), TweenService (ref), RunService (ref)
                        if u191 < timeSync:GetTime() then
                            u192:Disconnect();
                            u192 = nil;
                            local u193 = game.ReplicatedStorage.enemyProjectiles.thirdBossOneShotBeam:Clone();
                            Debris:AddItem(u193, 7);
                            u193:SetPrimaryPartCFrame(u190 + Vector3.new(0, 2, 0));
                            u193.Parent = workspace;
                            TweenService:Create(u193.concussiveBlast, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                                Size = Vector3.new(83.103, 1.187, 83.103),
                                Transparency = 1
                            }):Play();
                            TweenService:Create(u193.outerSphereWind, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                                Size = Vector3.new(33.98, 17.796, 37.382),
                                Position = u193.innerSphere.outerSphereWind.WorldPosition
                            }):Play();
                            TweenService:Create(u193.outerSphere, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                                Size = Vector3.new(33.515, 16.757, 34.374),
                                Position = u193.innerSphere.outerSphere.WorldPosition
                            }):Play();
                            TweenService:Create(u193.innerSphere, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                                Size = Vector3.new(21.188, 10.594, 21.731)
                            }):Play();
                            TweenService:Create(u193.innerBeam, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                                Size = Vector3.new(16, 147, 16),
                                Position = u193.innerSphere.innerBeam.WorldPosition
                            }):Play();
                            TweenService:Create(u193.outerBeam, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                                Size = Vector3.new(18, 113, 18),
                                Position = u193.innerSphere.outerBeam.WorldPosition
                            }):Play();
                            TweenService:Create(u193.outerRing, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                                Size = Vector3.new(51.116, 3.33, 51.669),
                                Position = u193.innerSphere.outerRing.WorldPosition
                            }):Play();
                            local u194 = {
                                outerSphereWind = 15,
                                innerBeam = 10,
                                outerBeam = 7,
                                outerRing = 6
                            };
                            local u195 = tick() + 5;
                            local u196 = nil;
                            u196 = RunService.Heartbeat:Connect(function() -- Line: 1616
                                -- upvalues: u195 (copy), u196 (ref), u193 (copy), u194 (copy)
                                if u195 >= tick() then
                                    for i, v in pairs(u194) do
                                        local v197 = u193[i];
                                        v197.CFrame = v197.CFrame * CFrame.Angles(0, math.rad(v), 0);
                                    end;

                                    return;
                                end;

                                u196:Disconnect();
                                u196 = nil;
                                u193:Destroy();
                            end);
                        end;
                    end);

                    return;
                end;

                if p148 == "Battle Mage Orb Shot" then
                    local u198 = p149[1];
                    local u199 = p149[2];
                    local u200 = p149[3];
                    local u201 = p149[4];
                    local u202 = p149[5];
                    local u203 = game.ReplicatedStorage.enemyProjectiles.battleMageOrb:Clone();
                    Debris:AddItem(u203, 10);
                    u203.CFrame = u202;
                    u203.Parent = workspace;
                    local u204 = nil;
                    u204 = RunService.Heartbeat:Connect(function() -- Line: 1646
                        -- upvalues: timeSync (ref), u200 (copy), u199 (copy), u202 (copy), u198 (copy), u203 (copy), u201 (copy), u204 (ref)
                        local Time = timeSync:GetTime();
                        local math_clamp_ret = math.clamp((Time - u200) / u199, 0, 1);
                        u203.CFrame = u202 + u202.LookVector * (math_clamp_ret * u198);

                        if u201 < Time then
                            u204:Disconnect();
                            u204 = nil;
                            u203.Transparency = 1;
                            u203.Mist.Enabled = false;
                        end;
                    end);

                    return;
                end;

                if p148 == "Mushroom Wizard Shot" then
                    for _, child in pairs(p149:GetChildren()) do
                        if child.Name == "precast" then
                            child.Transparency = 0;
                            child.Mist:Emit(80);
                        end;
                    end;

                    wait(0.1);

                    for _, child in pairs(p149:GetChildren()) do
                        if child.Name == "precast" then
                            TweenService:Create(child, TweenInfo.new(0.25, Enum.EasingStyle.Linear, Enum.EasingDirection.Out), {
                                Transparency = 1
                            }):Play();
                        end;
                    end;

                    return;
                end;

                if p148 == "Third Boss Mark Explosion" then
                    local v205 = game.ReplicatedStorage.projectiles.genericNeonBall:Clone();
                    v205.Transparency = 0;
                    v205.Color = Color3.fromRGB(255, 134, 253);
                    Debris:AddItem(v205, 3);
                    v205.Parent = workspace;
                    v205.CFrame = p149;
                    TweenService:Create(v205, TweenInfo.new(0.45, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
                        Size = Vector3.new(80, 80, 80),
                        Transparency = 1
                    }):Play();
                end;
            end;
        end;

        return;
    end;

    local u206 = p149[2];
    local u207 = p149[3];
    local u208 = u207 - u206;

    for _, v in pairs(p149[1]) do
        local HumanoidRootPart = v:FindFirstChild("HumanoidRootPart");
        local Humanoid = v:FindFirstChild("Humanoid");

        if HumanoidRootPart and (Humanoid and Humanoid.Health > 0) then
            local u209 = game.ReplicatedStorage.enemyProjectiles.firstBossCrystalDrop:Clone();
            Debris:AddItem(u209, 7);
            u209.CFrame = CFrame.new(HumanoidRootPart.Position) + Vector3.new(0, 30, 0);
            u209.Parent = workspace;
            local u210 = 0;
            local u211 = nil;
            u211 = RunService.Heartbeat:Connect(function() -- Line: 1316
                -- upvalues: timeSync (ref), u207 (copy), u211 (ref), u209 (copy), u206 (copy), u208 (copy), HumanoidRootPart (copy), u210 (ref)
                local Time = timeSync:GetTime();

                if u207 < Time then
                    u211:Disconnect();
                    u211 = nil;
                    u209:Destroy();

                    return;
                end;

                local math_clamp_ret = math.clamp((Time - u206) / u208, 0, 1);
                u209.CFrame = (CFrame.new(HumanoidRootPart.Position) + Vector3.new(0, 30 - math_clamp_ret * 30, 0)) * CFrame.Angles(0, math.rad(u210), 0);
                u210 = u210 + 5;
            end);
        end;
    end;
end);
game.ReplicatedStorage.remotes:WaitForChild("northernBossSpecficEvents").OnClientEvent:Connect(function(p212, u213) -- Line: 1693
    -- upvalues: u2 (copy), CameraShaker (copy), Debris (copy), TweenService (copy), RunService (copy), timeSync (copy)
    if p212 == "Shake Screens" then
        u2:Shake(CameraShaker.Presets[u213]);

        return;
    end;

    if p212 == "First Boss Slam Land" then
        local v214 = game.ReplicatedStorage.enemyProjectiles.genericNeonBall:Clone();
        v214.Transparency = 0;
        v214.Color = Color3.fromRGB(255, 0, 0);
        Debris:AddItem(v214, 3);
        v214.Parent = workspace;
        v214.CFrame = u213;
        v214.firstBossLand:Play();
        TweenService:Create(v214, TweenInfo.new(0.45, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
            Size = Vector3.new(80, 80, 80),
            Transparency = 1
        }):Play();

        return;
    end;

    if p212 == "First Boss Jump Up" then
        local v215 = game.ReplicatedStorage.enemyProjectiles.firstBossSmokePart:Clone();
        Debris:AddItem(v215, 3);
        v215.Position = u213;
        v215.Parent = workspace;
        v215.particles:Emit(150);
        workspace.firstBossSmokePart.particles:Emit(150);

        return;
    end;

    if p212 == "First Boss Jump Down" then
        local v216 = game.ReplicatedStorage.enemyProjectiles.firstBossSmokePart:Clone();
        Debris:AddItem(v216, 3);
        v216.Position = u213;
        v216.Parent = workspace;
        v216.particles:Emit(150);
        workspace.firstBossSmokePart.particles:Emit(150);

        return;
    end;

    if p212 == "First Boss Criss Cross Projectile" then
        local u217 = u213[1];
        local u218 = u213[2];
        local u219 = u213[3];
        local u220 = u213[4];
        local u221 = u213[5];
        local u222 = game.ReplicatedStorage.enemyProjectiles.firstBossCrissCross:Clone();
        Debris:AddItem(u222, 10);
        u222.CFrame = u221;
        u222.Parent = workspace;
        local u223 = 0;
        local u224 = nil;
        u224 = RunService.Heartbeat:Connect(function() -- Line: 1746
            -- upvalues: timeSync (ref), u219 (copy), u218 (copy), u221 (copy), u217 (copy), u222 (copy), u223 (ref), u220 (copy), u224 (ref)
            local Time = timeSync:GetTime();
            local math_clamp_ret = math.clamp((Time - u219) / u218, 0, 1);
            u222.CFrame = (u221 + u221.LookVector * (math_clamp_ret * u217)) * CFrame.Angles(0, math.rad(u223), 0);
            u223 = u223 + 10;

            if u220 < Time then
                u224:Disconnect();
                u224 = nil;
                u222.Transparency = 1;
                u222.Mist.Enabled = false;
                u222.Trail.Enabled = false;
            end;
        end);

        return;
    end;

    if p212 == "First Boss Seeking Spike" then
        local u225 = u213[1];
        local u226 = u213[2];
        local u227 = u213[3];
        local u228 = u213[4];
        local u229 = u213[5];
        local u230 = game.ReplicatedStorage.enemyProjectiles.firstBossSeekingSpikes:Clone();
        Debris:AddItem(u230, 10);
        u230.CFrame = u229;
        u230.Parent = workspace;
        local v231 = game.ReplicatedStorage.enemyProjectiles.firstBossBeamPart:Clone();
        Debris:AddItem(v231, 1.5);
        v231.Position = u229.Position;
        v231.Attachment2.WorldPosition = (u229 + u229.LookVector * u225).Position;
        v231.Parent = workspace;
        local u232 = 0;
        local u233 = nil;
        u233 = RunService.Heartbeat:Connect(function() -- Line: 1784
            -- upvalues: timeSync (ref), u227 (copy), u226 (copy), u229 (copy), u225 (copy), u230 (copy), u232 (ref), u228 (copy), u233 (ref)
            local Time = timeSync:GetTime();
            local math_clamp_ret = math.clamp((Time - u227) / u226, 0, 1);
            u230.CFrame = (u229 + u229.LookVector * (math_clamp_ret * u225)) * CFrame.Angles(0, math.rad(u232), 0);
            u232 = u232 + 10;

            if u228 < Time then
                u233:Disconnect();
                u233 = nil;
                u230.Transparency = 1;
                u230.Trail.Enabled = false;
            end;
        end);

        return;
    end;

    if p212 == "First Boss Big Spike" then
        local u234 = u213[1];
        local u235 = u213[2];
        local u236 = u213[3];
        local u237 = u213[4];
        local u238 = u213[5];
        local u239 = game.ReplicatedStorage.enemyProjectiles.firstBossBigSpike:Clone();
        Debris:AddItem(u239, 10);
        u239.CFrame = u238;
        u239.Parent = workspace;
        local u240 = game.ReplicatedStorage.enemyProjectiles.firstBossBeamPart:Clone();
        Debris:AddItem(u240, 10);
        u240.Position = u238.Position;
        u240.Attachment2.WorldPosition = (u238 + u238.LookVector * u234).Position;
        u240.Beam.Width0 = 40;
        u240.Beam.Width1 = 40;
        u240.Parent = workspace;
        local u241 = false;
        local u242 = 0;
        local u243 = nil;
        u243 = RunService.Heartbeat:Connect(function() -- Line: 1824
            -- upvalues: timeSync (ref), u236 (copy), u241 (ref), u239 (copy), u235 (copy), u238 (copy), u234 (copy), u242 (ref), u237 (copy), u243 (ref), u240 (copy)
            local Time = timeSync:GetTime();

            if u236 < Time then
                if not u241 then
                    u241 = true;
                    u239.Transparency = 0;
                    u239.Trail.Enabled = true;
                end;

                local math_clamp_ret = math.clamp((Time - u236) / u235, 0, 1);
                u239.CFrame = (u238 + u238.LookVector * (math_clamp_ret * u234)) * CFrame.Angles(0, math.rad(u242), 0);
                u242 = u242 + 10;

                if u237 < Time then
                    u243:Disconnect();
                    u243 = nil;
                    u239.Transparency = 1;
                    u239.Trail.Enabled = false;
                    u240:Destroy();
                end;
            end;
        end);

        return;
    end;

    if p212 == "First Boss Spike Hit Explosion" then
        local v244 = game.ReplicatedStorage.enemyProjectiles.genericNeonBall:Clone();
        v244.Transparency = 0;
        v244.Color = Color3.fromRGB(255, 80, 80);
        Debris:AddItem(v244, 3);
        v244.Parent = workspace;
        v244.CFrame = u213;
        v244.firstBossShurikenHit:Play();
        TweenService:Create(v244, TweenInfo.new(0.8, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
            Size = Vector3.new(175, 175, 175),
            Transparency = 1
        }):Play();

        return;
    end;

    if p212 == "Second Boss Big Hitting Ground Spikes" then
        local v245 = u213[1];
        local v246 = u213[2];
        local u247 = u213[3];
        local u248 = nil;
        local u249 = nil;

        if v245 == "small" then
            u248 = game.ReplicatedStorage.enemyProjectiles.smallIceSpikes:Clone();
            u249 = 40;
        elseif v245 == "medium" then
            u248 = game.ReplicatedStorage.enemyProjectiles.mediumIceSpikes:Clone();
            u249 = 60;
        elseif v245 == "large" then
            u248 = game.ReplicatedStorage.enemyProjectiles.largeIceSpikes:Clone();
            u249 = 100;
        end;

        Debris:AddItem(u248, 10);
        u248:SetPrimaryPartCFrame(v246);
        u248.Parent = workspace;
        local u250 = nil;
        u250 = RunService.Heartbeat:Connect(function() -- Line: 1884
            -- upvalues: timeSync (ref), u247 (copy), u250 (ref), u248 (ref), TweenService (ref), u249 (ref)
            if u247 < timeSync:GetTime() then
                u250:Disconnect();
                u250 = nil;
                u248.PrimaryPart.bigIceSpikeNoise:Play();
                u248.precast.Transparency = 0;
                u248.PrimaryPart.particles:Emit(150);

                for _, child in pairs(u248:GetChildren()) do
                    if child.Name == "Ice" then
                        local v251 = TweenService:Create(child, TweenInfo.new(0.1, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
                            Position = child.Position + Vector3.new(0, u249, 0)
                        });
                        v251.Completed:Connect(function() -- Line: 1896
                            -- upvalues: TweenService (ref), child (copy)
                            wait(0.25);
                            TweenService:Create(child, TweenInfo.new(0.3, Enum.EasingStyle.Linear, Enum.EasingDirection.Out), {
                                Transparency = 1
                            }):Play();
                        end);
                        v251:Play();
                    elseif child.Name == "precast" then
                        TweenService:Create(child, TweenInfo.new(0.4, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
                            Transparency = 1
                        }):Play();
                    end;
                end;
            end;
        end);

        return;
    end;

    if p212 == "Second Boss Moving Beam" then
        local u252 = u213[1];
        local u253 = u213[2];
        local u254 = u213[3];
        local u255 = u213[4];
        local u256 = u213[5];
        local u257 = game.ReplicatedStorage.enemyProjectiles.secondBossMovingBeam:Clone();
        Debris:AddItem(u257, 120);
        u257:SetPrimaryPartCFrame(u256);
        u257.Parent = workspace;
        local u258 = 0;
        local u259 = nil;
        u259 = RunService.Heartbeat:Connect(function() -- Line: 1922
            -- upvalues: timeSync (ref), u254 (copy), u253 (copy), u256 (copy), u252 (copy), u257 (copy), u258 (ref), u255 (copy), u259 (ref)
            local Time = timeSync:GetTime();
            local math_clamp_ret = math.clamp((Time - u254) / u253, 0, 1);
            u257:SetPrimaryPartCFrame((u256 + u256.LookVector * (math_clamp_ret * u252)) * CFrame.Angles(math.rad(u258), 0, 0));
            u258 = u258 + 10;

            if u255 < Time then
                u259:Disconnect();
                u259 = nil;
                u257:Destroy();
            end;
        end);

        return;
    end;

    if p212 == "Second Boss Orb Explosion" then
        local v260 = u213[1];
        local v261 = u213[2];
        local v262 = game.ReplicatedStorage.enemyProjectiles.genericNeonBall:Clone();
        v262.Transparency = 0;
        v262.Color = v261;
        Debris:AddItem(v262, 3);
        v262.Parent = workspace;
        v262.CFrame = v260;
        TweenService:Create(v262, TweenInfo.new(0.5, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
            Size = Vector3.new(120, 120, 120),
            Transparency = 1
        }):Play();
        v262.seondBossOrbExplosion:Play();

        return;
    end;

    if p212 == "Third Boss Bouncing Orb Beam" then
        local u263 = game.ReplicatedStorage.enemyProjectiles.thirdBossBouncingOrbBeam:Clone();
        Debris:AddItem(u263, 20);
        u263:SetPrimaryPartCFrame(u213 + Vector3.new(0, 4, 0));
        u263.Parent = workspace;
        TweenService:Create(u263.Beam, TweenInfo.new(0.3, Enum.EasingStyle.Linear, Enum.EasingDirection.Out), {
            Size = Vector3.new(24.429, 66.597, 24.429)
        }):Play();
        TweenService:Create(u263.Ring1, TweenInfo.new(0.3, Enum.EasingStyle.Linear, Enum.EasingDirection.Out), {
            Size = Vector3.new(33.447, 1.898, 33.447)
        }):Play();
        TweenService:Create(u263.Ring2, TweenInfo.new(0.3, Enum.EasingStyle.Linear, Enum.EasingDirection.Out), {
            Size = Vector3.new(45.049, 2.556, 45.049)
        }):Play();
        local u264 = tick() + 6;
        local u265 = nil;
        u265 = RunService.Heartbeat:Connect(function() -- Line: 1964
            -- upvalues: u263 (copy), u264 (copy), u265 (ref)
            u263.Ring1.CFrame = u263.Ring1.CFrame * CFrame.Angles(0, 0.20943951023931956, 0);
            u263.Ring2.CFrame = u263.Ring2.CFrame * CFrame.Angles(0, 0.2792526803190927, 0);

            if u264 < tick() then
                u265:Disconnect();
                u265 = nil;
                u263:Destroy();
            end;
        end);

        return;
    end;

    if p212 == "Third Boss Orb Explosion" then
        local v266 = game.ReplicatedStorage.enemyProjectiles.genericNeonBall:Clone();
        v266.Transparency = 0;
        v266.Color = Color3.fromRGB(255, 186, 129);
        Debris:AddItem(v266, 3);
        v266.Parent = workspace;
        v266.CFrame = u213;
        TweenService:Create(v266, TweenInfo.new(0.45, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
            Size = Vector3.new(90, 90, 90),
            Transparency = 1
        }):Play();
        v266.firstBossLand:Play();

        return;
    end;

    if p212 == "Third Boss Sideways Missile" then
        local u267 = u213[1];
        local u268 = u213[2];
        local u269 = u213[3];
        local u270 = u213[4];
        local u271 = u213[5];
        local u272 = game.ReplicatedStorage.enemyProjectiles.thirdBossMissile:Clone();
        Debris:AddItem(u272, 10);
        u272.CFrame = u271;
        u272.Parent = workspace;
        local v273 = game.ReplicatedStorage.enemyProjectiles.thirdBossBeamPart:Clone();
        Debris:AddItem(v273, 0.4);
        v273.Position = u271.Position;
        v273.Attachment2.WorldPosition = (u271 + u271.LookVector * u267).Position;
        v273.Parent = workspace;
        local u274 = 0;
        local u275 = nil;
        u275 = RunService.Heartbeat:Connect(function() -- Line: 2006
            -- upvalues: timeSync (ref), u269 (copy), u268 (copy), u271 (copy), u267 (copy), u272 (copy), u274 (ref), u270 (copy), u275 (ref)
            local Time = timeSync:GetTime();
            local math_clamp_ret = math.clamp((Time - u269) / u268, 0, 1);
            u272.CFrame = (u271 + u271.LookVector * (math_clamp_ret * u267 - 10)) * CFrame.Angles(0, 3.141592653589793, 0) * CFrame.Angles(0, 0, (math.rad(u274)));
            u274 = u274 + 10;

            if u270 < Time then
                u275:Disconnect();
                u275 = nil;
                u272.Transparency = 1;
            end;
        end);

        return;
    end;

    if p212 == "Spearman Strike" then
        spawn(function() -- Line: 2027
            -- upvalues: Debris (ref), u213 (copy), TweenService (ref)
            local v276 = game.ReplicatedStorage.enemyProjectiles.spearmanStrike:Clone();
            Debris:AddItem(v276, 5);
            v276.CFrame = u213;
            v276.Parent = workspace;
            TweenService:Create(v276, TweenInfo.new(0.25, Enum.EasingStyle.Linear, Enum.EasingDirection.Out), {
                Size = Vector3.new(10.888, 3.905, 31),
                CFrame = v276.CFrame - v276.CFrame.LookVector * 65
            }):Play();
            wait(0.2);
            TweenService:Create(v276, TweenInfo.new(0.25, Enum.EasingStyle.Linear, Enum.EasingDirection.Out), {
                Transparency = 1
            }):Play();
        end);
        local v277 = game.ReplicatedStorage.enemyProjectiles.spearmanStrike:Clone();
        Debris:AddItem(v277, 5);
        v277.CFrame = u213 * CFrame.Angles(0, 3.141592653589793, 0);
        v277.Parent = workspace;
        TweenService:Create(v277, TweenInfo.new(0.25, Enum.EasingStyle.Linear, Enum.EasingDirection.Out), {
            Size = Vector3.new(10.888, 3.905, 31),
            CFrame = v277.CFrame - v277.CFrame.LookVector * 65
        }):Play();
        wait(0.2);
        TweenService:Create(v277, TweenInfo.new(0.25, Enum.EasingStyle.Linear, Enum.EasingDirection.Out), {
            Transparency = 1
        }):Play();

        return;
    end;

    if p212 == "Warrior Line Strike" then
        local v278 = game.ReplicatedStorage.enemyProjectiles.spearmanStrike:Clone();
        v278.Color = Color3.fromRGB(0, 255, 247);
        Debris:AddItem(v278, 5);
        v278.CFrame = u213 * CFrame.Angles(0, 3.141592653589793, 0);
        v278.Parent = workspace;
        TweenService:Create(v278, TweenInfo.new(0.25, Enum.EasingStyle.Linear, Enum.EasingDirection.Out), {
            Size = Vector3.new(10.888, 3.905, 31),
            CFrame = v278.CFrame - v278.CFrame.LookVector * 65
        }):Play();
        wait(0.2);
        TweenService:Create(v278, TweenInfo.new(0.25, Enum.EasingStyle.Linear, Enum.EasingDirection.Out), {
            Transparency = 1
        }):Play();

        return;
    end;

    if p212 == "Bonus Boss Rune Color Change" then
        for _, child in pairs(workspace.bossRoomRunes:GetChildren()) do
            child.Color = Color3.fromRGB(255, 102, 102);
        end;

        return;
    end;

    if p212 == "Bonus Boss Safe Color Zone Activated" then
        for _, child in pairs(workspace.bonusBossColorSafeSpots:GetChildren()) do
            for _, child2 in pairs(child:GetChildren()) do
                if child2:IsA("Beam") then
                    child2.Enabled = true;
                end;
            end;
        end;

        return;
    end;

    if p212 == "Bonus Boss Safe Color Zone Deactivated" then
        for _, child in pairs(workspace.bonusBossColorSafeSpots:GetChildren()) do
            for _, child2 in pairs(child:GetChildren()) do
                if child2:IsA("Beam") then
                    child2.Enabled = false;
                end;
            end;
        end;

        return;
    end;

    if p212 == "Bonus Boss Tall Swirly" then
        local u279 = u213[1];
        local u280 = u213[2];
        local u281 = {
            red = Color3.fromRGB(255, 78, 78),
            yellow = Color3.fromRGB(255, 250, 94),
            green = Color3.fromRGB(78, 255, 69)
        };
        local u282 = game.ReplicatedStorage.enemyProjectiles.bonusBossTallSwirly:Clone();
        Debris:AddItem(u282, 10);
        u282:SetPrimaryPartCFrame(workspace.thirdBossMiddlePart.CFrame);

        for _, child in pairs(u282:GetChildren()) do
            if child:IsA("BasePart") then
                child.Color = u281[u279];
            end;
        end;

        u282.Parent = workspace;
        local u283 = nil;
        u283 = RunService.Heartbeat:Connect(function() -- Line: 2103
            -- upvalues: timeSync (ref), u280 (copy), u283 (ref), TweenService (ref), u282 (copy), u281 (copy), u279 (copy), Debris (ref)
            if u280 >= timeSync:GetTime() then
                u282.tallSwirl.CFrame = u282.tallSwirl.CFrame * CFrame.Angles(0, 0.5235987755982988, 0);
                u282.Whirl1.CFrame = u282.Whirl1.CFrame * CFrame.Angles(0, 0.4363323129985824, 0);
                u282.Whirl2.CFrame = u282.Whirl2.CFrame * CFrame.Angles(0, -0.5235987755982988, 0);

                return;
            end;

            u283:Disconnect();
            u283 = nil;
            TweenService:Create(u282.tallSwirl, TweenInfo.new(0.7, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
                Size = Vector3.new(150, 106.241, 150),
                Transparency = 1
            }):Play();
            TweenService:Create(u282.Whirl1, TweenInfo.new(0.7, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
                Size = Vector3.new(150, 15, 150),
                Transparency = 1
            }):Play();
            TweenService:Create(u282.Whirl2, TweenInfo.new(0.7, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
                Size = Vector3.new(170, 25, 170),
                Transparency = 1
            }):Play();
            local v284 = game.ReplicatedStorage.enemyProjectiles.genericNeonBall:Clone();
            v284.Transparency = 0;
            v284.Color = u281[u279];
            Debris:AddItem(v284, 3);
            v284.Parent = workspace;
            v284.CFrame = workspace.thirdBossMiddlePart.CFrame;
            TweenService:Create(v284, TweenInfo.new(0.8, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
                Size = Vector3.new(260, 260, 260),
                Transparency = 1
            }):Play();
        end);

        return;
    end;

    if p212 == "Bonus Boss Flame Pre Target" then
        local u285 = u213[1];
        local u286 = u213[2];
        local u287 = game.ReplicatedStorage.enemyProjectiles.bonusBossFlamePreCast:Clone();
        Debris:AddItem(u287, 10);
        u287.Parent = workspace;
        local u288 = nil;
        u288 = RunService.Heartbeat:Connect(function() -- Line: 2138
            -- upvalues: timeSync (ref), u286 (copy), u285 (copy), u287 (copy), u288 (ref)
            if timeSync:GetTime() < u286 then
                if u285 then
                    local Humanoid = u285:FindFirstChild("Humanoid");
                    local HumanoidRootPart = u285:FindFirstChild("HumanoidRootPart");

                    if Humanoid and (Humanoid.Health > 0 and HumanoidRootPart) then
                        u287.CFrame = CFrame.new(HumanoidRootPart.Position - Vector3.new(0, 1.5, 0)) * CFrame.Angles(0, 0, 1.5707963267948966);
                    end;
                end;
            else
                u288:Disconnect();
                u288 = nil;
                u287:Destroy();
            end;
        end);

        return;
    end;

    if p212 == "Bonus Boss Bad Orb Explosion" then
        local v289 = game.ReplicatedStorage.enemyProjectiles.genericNeonBall:Clone();
        v289.Transparency = 0;
        v289.Color = Color3.fromRGB(255, 70, 70);
        Debris:AddItem(v289, 3);
        v289.Parent = workspace;
        v289.CFrame = u213;
        TweenService:Create(v289, TweenInfo.new(0.8, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
            Size = Vector3.new(260, 260, 260),
            Transparency = 1
        }):Play();

        return;
    end;

    if p212 == "Bonus Boss Good Orb Explosion" then
        local v290 = game.ReplicatedStorage.enemyProjectiles.genericNeonBall:Clone();
        v290.Transparency = 0;
        v290.Color = Color3.fromRGB(83, 255, 94);
        Debris:AddItem(v290, 3);
        v290.Parent = workspace;
        v290.CFrame = u213;
        TweenService:Create(v290, TweenInfo.new(0.8, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
            Size = Vector3.new(260, 260, 260),
            Transparency = 1
        }):Play();

        return;
    end;

    if p212 ~= "Bonus Boss Freezing Orb Beam" then
        if p212 == "Bonus Boss Orb Explosion" then
            local v291 = game.ReplicatedStorage.enemyProjectiles.genericNeonBall:Clone();
            v291.Transparency = 0;
            v291.Color = Color3.fromRGB(0, 251, 255);
            Debris:AddItem(v291, 3);
            v291.Parent = workspace;
            v291.CFrame = u213;
            TweenService:Create(v291, TweenInfo.new(0.45, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
                Size = Vector3.new(45, 45, 45),
                Transparency = 1
            }):Play();
            v291.firstBossLand:Play();
        end;

        return;
    end;

    local u292 = game.ReplicatedStorage.enemyProjectiles.bonusBossFreezingOrbBeam:Clone();
    Debris:AddItem(u292, 20);
    u292:SetPrimaryPartCFrame(u213 + Vector3.new(0, 4, 0));
    u292.Parent = workspace;
    TweenService:Create(u292.Beam, TweenInfo.new(0.3, Enum.EasingStyle.Linear, Enum.EasingDirection.Out), {
        Size = Vector3.new(24.429, 66.597, 24.429)
    }):Play();
    TweenService:Create(u292.Ring1, TweenInfo.new(0.3, Enum.EasingStyle.Linear, Enum.EasingDirection.Out), {
        Size = Vector3.new(33.447, 1.898, 33.447)
    }):Play();
    TweenService:Create(u292.Ring2, TweenInfo.new(0.3, Enum.EasingStyle.Linear, Enum.EasingDirection.Out), {
        Size = Vector3.new(45.049, 2.556, 45.049)
    }):Play();
    local u293 = tick() + 6;
    local u294 = nil;
    u294 = RunService.Heartbeat:Connect(function() -- Line: 2192
        -- upvalues: u292 (copy), u293 (copy), u294 (ref)
        u292.Ring1.CFrame = u292.Ring1.CFrame * CFrame.Angles(0, 0.20943951023931956, 0);
        u292.Ring2.CFrame = u292.Ring2.CFrame * CFrame.Angles(0, 0.2792526803190927, 0);

        if u293 < tick() then
            u294:Disconnect();
            u294 = nil;
            u292:Destroy();
        end;
    end);
end);
local u295 = {};
local u296 = {};
game.ReplicatedStorage.remotes:WaitForChild("gildedBossSpecficEvents").OnClientEvent:Connect(function(p297, u298) -- Line: 2219
    -- upvalues: u2 (copy), CameraShaker (copy), u296 (copy), Debris (copy), TweenService (copy), RunService (copy), timeSync (copy), Random_new_ret (copy), u295 (copy), LocalPlayer (copy)
    if p297 == "Shake Screens" then
        u2:Shake(CameraShaker.Presets[u298]);

        return;
    end;

    if p297 == "First Boss Move Orb" then
        local v299 = u298[1];
        local u300 = u298[2];
        local u301 = u298[3];
        local v302 = u298[4];
        local v303 = u298[5];
        local u304;

        if u296[v303] then
            u304 = u296[v303];
        else
            u304 = game.ReplicatedStorage.enemyProjectiles.firstBossMovingOrb:Clone();
            Debris:AddItem(u304, 18);
            u304.CFrame = v299;
            u304.Parent = workspace;
            u296[v303] = u304;
        end;

        local u305 = nil;
        local CFrame_new_ret = CFrame.new(v299.Position, u300);
        local Magnitude = (v299.Position - u300).Magnitude;
        local u306 = Magnitude / v302;
        local u307 = u301 + u306;
        local u308 = game.ReplicatedStorage.enemyProjectiles.firstBossOrbPrecastLine:Clone();
        Debris:AddItem(u308, 4);
        u308:SetPrimaryPartCFrame(v299);
        u308.precast.Size = Vector3.new(10, 2.5, Magnitude);
        u308.precast.CFrame = u308.precast.CFrame + v299.LookVector * Magnitude / 2;
        u308.circlePrecast.CFrame = u308.circlePrecast.CFrame + v299.LookVector * Magnitude;
        u308.Parent = workspace;
        spawn(function() -- Line: 2262
            -- upvalues: TweenService (ref), u308 (copy)
            wait(0.2);
            TweenService:Create(u308.precast, TweenInfo.new(1.2, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
                Transparency = 1
            }):Play();
            TweenService:Create(u308.circlePrecast, TweenInfo.new(1.2, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
                Transparency = 1
            }):Play();
        end);
        u305 = RunService.Heartbeat:Connect(function() -- Line: 2267
            -- upvalues: timeSync (ref), u307 (copy), u305 (ref), Debris (ref), u300 (copy), TweenService (ref), u301 (copy), u306 (copy), CFrame_new_ret (copy), Magnitude (copy), u304 (ref)
            local Time = timeSync:GetTime();

            if u307 >= Time then
                local math_clamp_ret = math.clamp((Time - u301) / u306, 0, 1);
                u304.CFrame = CFrame_new_ret + CFrame_new_ret.LookVector * (math_clamp_ret * Magnitude);

                return;
            end;

            u305:Disconnect();
            u305 = nil;
            local v309 = game.ReplicatedStorage.projectiles.genericNeonBall:Clone();
            v309.Transparency = 0;
            v309.Color = Color3.fromRGB(97, 255, 137);
            Debris:AddItem(v309, 5);
            v309.Position = u300;
            v309.Parent = workspace;
            TweenService:Create(v309, TweenInfo.new(0.5, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
                Size = Vector3.new(35, 35, 35),
                Transparency = 1
            }):Play();
        end);

        return;
    end;

    if p297 == "First Boss Fire Beam" then
        local _ = u298[1];
        local _ = u298[2];

        return;
    end;

    if p297 == "First Boss Beam Track" then
        local v310 = u298[1];
        local u311 = u298[2];
        local u312 = workspace.firstBossSunDiskBeamPart.Beam:Clone();
        Debris:AddItem(u312, 10);
        u312.Parent = workspace.firstBossSunDiskBeamPart;
        u312.Attachment0 = workspace.firstBossSunDiskBeamPart.Attachment;
        u312.Attachment1 = v310.HumanoidRootPart.RootRigAttachment;
        local u313 = game.ReplicatedStorage.enemyProjectiles.firstBossBeamParticles:Clone();
        Debris:AddItem(u313, 10);
        u313.Parent = v310.HumanoidRootPart;
        local u314 = nil;
        u314 = RunService.Heartbeat:Connect(function() -- Line: 2308
            -- upvalues: timeSync (ref), u311 (copy), u314 (ref), u312 (copy), u313 (copy)
            if u311 < timeSync:GetTime() then
                u314:Disconnect();
                u314 = nil;
                u312:Destroy();
                u313:Destroy();
            end;
        end);

        return;
    end;

    if p297 == "Second Boss Add Highlight" then
        local v315 = game.ReplicatedStorage.enemyProjectiles.secondBossPassiveHighlight:Clone();
        Debris:AddItem(v315, 5);
        v315.Parent = u298;

        return;
    end;

    if p297 == "Second Boss Orb Beam" then
        local v316 = u298[1];
        local v317 = u298[2];
        v316.Transparency = 0;
        v316.PointLight.Enabled = true;
        v316.Beam.Attachment1 = v317.HumanoidRootPart.RootRigAttachment;

        return;
    end;

    if p297 == "Second Boss Orb Deactivate" then
        u298.Transparency = 1;
        u298.PointLight.Enabled = false;
        u298.Beam.Attachment1 = nil;

        return;
    end;

    if p297 == "Second Boss Big Circle" then
        local u318 = u298[1];
        local u319 = u298[2];
        local u320 = u298[3];
        local u321 = u320 - u319;
        spawn(function() -- Line: 2345
            -- upvalues: Debris (ref), TweenService (ref), Random_new_ret (ref)
            local CFrame2 = workspace.secondBossMiddlePart.CFrame;
            wait(0.6);
            local v322 = game.ReplicatedStorage.enemyProjectiles.bigRock:Clone();
            Debris:AddItem(v322, 5);
            v322.CFrame = CFrame2;
            v322.Parent = workspace;
            TweenService:Create(v322, TweenInfo.new(0.7, Enum.EasingStyle.Linear), {
                CFrame = CFrame2 + Vector3.new(0, 200, 0)
            }):Play();

            for i = 1, 10 do
                spawn(function() -- Line: 2354
                    -- upvalues: Debris (ref), CFrame2 (copy), Random_new_ret (ref)
                    local v323 = game.ReplicatedStorage.enemyProjectiles.secondBossBigRockDebris:Clone();
                    Debris:AddItem(v323, 2.2);
                    local v324 = Random_new_ret:NextNumber(-4, 4);
                    v323.CFrame = CFrame2 + Vector3.new(v324, 0, Random_new_ret:NextNumber(-4, 4)) * 2;
                    local v325 = Random_new_ret:NextNumber(6, 9);
                    local v326 = Random_new_ret:NextNumber(6, 9);
                    v323.Size = Vector3.new(v325, v326, Random_new_ret:NextNumber(6, 9));
                    v323.Parent = workspace;
                    local Attachment0 = v323.Attachment0;
                    local v327 = Random_new_ret:NextNumber(-2, 2);
                    local v328 = Random_new_ret:NextNumber(-2, 2);
                    Attachment0.Position = Vector3.new(v327, v328, Random_new_ret:NextNumber(-2, 2));
                    local VectorForce = v323.VectorForce;
                    local v329 = Random_new_ret:NextInteger(-33000, 33000);
                    local v330 = Random_new_ret:NextInteger(60000, 110000);
                    VectorForce.Force = Vector3.new(v329, v330, Random_new_ret:NextInteger(-33000, 33000)) * 8;
                    v323.VectorForce.Enabled = true;
                    wait(0.15);
                    v323.VectorForce.Enabled = false;
                end);
                local _ = i;
            end;
        end);
        local u331 = game.ReplicatedStorage.enemyProjectiles.secondBossBigCircle:Clone();
        Debris:AddItem(u331, 10);
        u331:SetPrimaryPartCFrame(u318);
        u331.Parent = workspace;
        local Y = u331.bigRock.Position.Y;
        local math_abs_ret = math.abs(u331.PrimaryPart.Position.Y - Y);
        local u332 = nil;
        u332 = RunService.Heartbeat:Connect(function() -- Line: 2380
            -- upvalues: timeSync (ref), u320 (copy), u332 (ref), u331 (copy), TweenService (ref), Debris (ref), u318 (copy), Random_new_ret (ref), u319 (copy), u321 (copy), Y (copy), math_abs_ret (copy)
            local Time = timeSync:GetTime();

            if u320 >= Time then
                local math_clamp_ret = math.clamp((Time - u319) / u321, 0, 1);
                u331.growingPrecast.Size = Vector3.new(2.1, math_clamp_ret * 80, math_clamp_ret * 80);
                u331.bigRock.Position = Vector3.new(u318.Position.X, Y - math_clamp_ret * math_abs_ret, u318.Position.Z);

                return;
            end;

            u332:Disconnect();
            u332 = nil;
            u331.growingPrecast.Size = Vector3.new(2.1, 80, 80);
            u331.growingPrecast.Transparency = 0;
            TweenService:Create(u331.growingPrecast, TweenInfo.new(0.5, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
                Transparency = 1
            }):Play();
            u331.precast.Transparency = 1;
            TweenService:Create(u331.bigRock, TweenInfo.new(0.5, Enum.EasingStyle.Linear, Enum.EasingDirection.Out), {
                Transparency = 1
            }):Play();
            local v333 = game.ReplicatedStorage.projectiles.genericNeonBall:Clone();
            v333.Transparency = 0;
            v333.Color = Color3.fromRGB(255, 110, 110);
            Debris:AddItem(v333, 5);
            v333.CFrame = u318;
            v333.Parent = workspace;
            TweenService:Create(v333, TweenInfo.new(0.6, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
                Size = Vector3.new(100, 100, 100),
                Transparency = 1
            }):Play();

            for i = 1, 10 do
                spawn(function() -- Line: 2401
                    -- upvalues: Debris (ref), u318 (ref), Random_new_ret (ref)
                    local v334 = game.ReplicatedStorage.enemyProjectiles.secondBossBigRockDebris:Clone();
                    Debris:AddItem(v334, 2.2);
                    local v335 = Random_new_ret:NextNumber(-4, 4);
                    v334.CFrame = u318 + Vector3.new(v335, 0, Random_new_ret:NextNumber(-4, 4)) * 2;
                    local v336 = Random_new_ret:NextNumber(6, 9);
                    local v337 = Random_new_ret:NextNumber(6, 9);
                    v334.Size = Vector3.new(v336, v337, Random_new_ret:NextNumber(6, 9));
                    v334.Parent = workspace;
                    local Attachment0 = v334.Attachment0;
                    local v338 = Random_new_ret:NextNumber(-2, 2);
                    local v339 = Random_new_ret:NextNumber(-2, 2);
                    Attachment0.Position = Vector3.new(v338, v339, Random_new_ret:NextNumber(-2, 2));
                    local VectorForce = v334.VectorForce;
                    local v340 = Random_new_ret:NextInteger(-33000, 33000);
                    local v341 = Random_new_ret:NextInteger(60000, 110000);
                    VectorForce.Force = Vector3.new(v340, v341, Random_new_ret:NextInteger(-33000, 33000)) * 8;
                    v334.VectorForce.Enabled = true;
                    wait(0.15);
                    v334.VectorForce.Enabled = false;
                end);
                local _ = i;
            end;
        end);

        return;
    end;

    if p297 == "Third Boss Passive Orb Spawn" then
        local u342 = u298[1];
        local u343 = u298[2];
        local u344 = u298[3];
        local u345 = u344 - u343;
        local u346 = u298[4];
        local v347 = u298[5];
        local u348 = game.ReplicatedStorage.enemyProjectiles.thirdBossPassiveOrb:Clone();
        Debris:AddItem(u348, 20);
        u348.CFrame = u342;
        u348.Parent = workspace;
        local u349 = nil;
        u295[v347] = { u348, u349 };
        u349 = RunService.Heartbeat:Connect(function() -- Line: 2440
            -- upvalues: timeSync (ref), u344 (copy), u349 (ref), u348 (copy), u343 (copy), u345 (copy), u342 (copy), u346 (copy)
            local Time = timeSync:GetTime();

            if u344 >= Time then
                local math_clamp_ret = math.clamp((Time - u343) / u345, 0, 1);
                u348.CFrame = u342 + u342.LookVector * (math_clamp_ret * u346);

                return;
            end;

            u349:Disconnect();
            u349 = nil;
            u348:Destroy();
        end);

        return;
    end;

    if p297 == "Third Boss Passive Orb Explode" then
        local v350 = u298[1];
        local v351 = u298[2];
        local v352 = u295[v351][2];

        if v352 then
            v352:Disconnect();
        end;

        u295[v351][1]:Destroy();
        local v353 = game.ReplicatedStorage.projectiles.genericNeonBall:Clone();
        v353.Transparency = 0;
        v353.Color = Color3.fromRGB(255, 110, 110);
        Debris:AddItem(v353, 5);
        v353.CFrame = v350;
        v353.Parent = workspace;
        TweenService:Create(v353, TweenInfo.new(0.75, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
            Size = Vector3.new(120, 120, 120),
            Transparency = 1
        }):Play();

        return;
    end;

    if p297 == "Third Boss Flame Wall" then
        local u354 = u298[1];
        local u355 = u298[2];
        local u356 = u298[3];
        local u357 = u356 - u355;
        local u358 = u298[4];
        local u359 = game.ReplicatedStorage.enemyProjectiles.thirdBossFlameWall:Clone();
        Debris:AddItem(u359, 20);
        u359:SetPrimaryPartCFrame(u354);
        u359.Parent = workspace;
        local u360 = nil;
        u360 = RunService.Heartbeat:Connect(function() -- Line: 2486
            -- upvalues: timeSync (ref), u356 (copy), u360 (ref), u359 (copy), u355 (copy), u357 (copy), u354 (copy), u358 (copy)
            local Time = timeSync:GetTime();

            if u356 >= Time then
                local math_clamp_ret = math.clamp((Time - u355) / u357, 0, 1);
                u359:SetPrimaryPartCFrame(u354 + u354.LookVector * (math_clamp_ret * u358));

                return;
            end;

            u360:Disconnect();
            u360 = nil;
            u359:Destroy();
        end);

        return;
    end;

    if p297 == "Third Boss Fireball Particles" then
        for _, descendant in pairs(u298:GetDescendants()) do
            if descendant:IsA("ParticleEmitter") then
                descendant:Emit(150);
            end;
        end;

        return;
    end;

    if p297 == "Dracani Wizard Shot" then
        for _, descendant in pairs(u298:GetDescendants()) do
            if descendant:IsA("Attachment") then
                TweenService:Create(descendant, TweenInfo.new(0.4, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
                    Position = descendant.Position + Vector3.new(0, -15, 0)
                }):Play();
            elseif descendant:IsA("Beam") then
                descendant.Enabled = true;
                TweenService:Create(descendant, TweenInfo.new(0.4, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
                    Width0 = 0
                }):Play();
                TweenService:Create(descendant, TweenInfo.new(0.4, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
                    Width1 = 0
                }):Play();
                spawn(function() -- Line: 2523
                    -- upvalues: descendant (copy)
                    wait(0.4);
                    descendant.Enabled = false;
                end);
            elseif descendant.Name == "precast" then
                descendant.Transparency = 0;
                TweenService:Create(descendant, TweenInfo.new(0.4, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
                    Transparency = 1
                }):Play();
            end;
        end;

        return;
    end;

    if p297 == "Third Boss Show Safe Zones" then
        for _, descendant in pairs(workspace.thirdBossSafeZones:GetDescendants()) do
            if descendant:IsA("Beam") or (descendant:IsA("PointLight") or descendant:IsA("BillboardGui")) then
                descendant.Enabled = true;
            end;
        end;

        for _, v in pairs(u298) do
            local char = v.char;

            if char then
                char:FindFirstChild("HumanoidRootPart");
                local v361 = game.ReplicatedStorage.enemyProjectiles[v.color .. "SafeZoneMarker"]:Clone();
                Debris:AddItem(v361, 60);
                v361.Parent = char;
                v361.Adornee = char.HumanoidRootPart;
                v361.Name = "safeZoneMarker";
            end;
        end;

        return;
    end;

    if p297 == "Third Boss Hide Safe Zones" then
        local v362 = game.ReplicatedStorage.projectiles.genericNeonBall:Clone();
        v362.Transparency = 0;
        v362.Color = Color3.fromRGB(255, 64, 64);
        Debris:AddItem(v362, 5);
        v362.Position = workspace.thirdBossMiddlePart.Position;
        v362.Parent = workspace;
        TweenService:Create(v362, TweenInfo.new(1, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
            Size = Vector3.new(300, 300, 300),
            Transparency = 1
        }):Play();

        for _, descendant in pairs(workspace.thirdBossSafeZones:GetDescendants()) do
            if descendant:IsA("Beam") or (descendant:IsA("PointLight") or descendant:IsA("BillboardGui")) then
                descendant.Enabled = false;
            end;
        end;

        for _, v in pairs(game.Players:GetPlayers()) do
            local Character = v.Character;

            if Character then
                local safeZoneMarker = Character:FindFirstChild("safeZoneMarker");

                if safeZoneMarker then
                    safeZoneMarker:Destroy();
                end;
            end;
        end;

        return;
    end;

    if p297 == "Second Boss Horizontal Line" then
        local v363 = u298[1];
        local u364 = u298[2];
        local u365 = game.ReplicatedStorage.enemyProjectiles.secondBossHorizontalLine:Clone();
        Debris:AddItem(u365, 5);
        u365:SetPrimaryPartCFrame(v363);
        u365.Parent = workspace;
        local u366 = nil;
        u366 = RunService.Heartbeat:Connect(function() -- Line: 2598
            -- upvalues: timeSync (ref), u364 (copy), u366 (ref), u365 (copy), TweenService (ref)
            if u364 < timeSync:GetTime() then
                u366:Disconnect();
                u366 = nil;

                for _, descendant in pairs(u365:GetDescendants()) do
                    if descendant:IsA("Attachment") then
                        TweenService:Create(descendant, TweenInfo.new(0.4, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
                            Position = descendant.Position + Vector3.new(0, -15, 0)
                        }):Play();
                    elseif descendant:IsA("Beam") then
                        descendant.Enabled = true;
                        TweenService:Create(descendant, TweenInfo.new(0.4, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
                            Width0 = 0
                        }):Play();
                        TweenService:Create(descendant, TweenInfo.new(0.4, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
                            Width1 = 0
                        }):Play();
                        spawn(function() -- Line: 2613
                            -- upvalues: descendant (copy)
                            wait(0.4);
                            descendant.Enabled = false;
                        end);
                    elseif descendant.Name == "precast" then
                        descendant.Transparency = 0;
                        TweenService:Create(descendant, TweenInfo.new(0.4, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
                            Transparency = 1
                        }):Play();
                    end;
                end;
            end;
        end);

        return;
    end;

    if p297 ~= "Second Boss Orb Beam Explode" then
        if p297 == "First Boss Blinding Blast" then
            local WorldCFrame = workspace.firstBossMiddlePart.blindingBlastAttachment.WorldCFrame;
            local u367 = game.ReplicatedStorage.enemyProjectiles.firstBossLookAwayGui:Clone();
            Debris:AddItem(u367, 10);
            u367.Parent = LocalPlayer.PlayerGui;
            local u368 = game.ReplicatedStorage.enemyProjectiles.firstBossBlindingBlastBeam:Clone();
            Debris:AddItem(u368, 7);
            u368:SetPrimaryPartCFrame(WorldCFrame - Vector3.new(0, 5, 0));
            u368.Parent = workspace;
            TweenService:Create(u368.concussiveBlast, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                Size = Vector3.new(83.103, 1.187, 83.103),
                Transparency = 1
            }):Play();
            TweenService:Create(u368.outerSphereWind, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                Size = Vector3.new(33.98, 17.796, 37.382),
                Position = u368.innerSphere.outerSphereWind.WorldPosition
            }):Play();
            TweenService:Create(u368.outerSphere, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                Size = Vector3.new(33.515, 16.757, 34.374),
                Position = u368.innerSphere.outerSphere.WorldPosition
            }):Play();
            TweenService:Create(u368.innerSphere, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                Size = Vector3.new(21.188, 10.594, 21.731)
            }):Play();
            TweenService:Create(u368.innerBeam, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                Size = Vector3.new(16, 147, 16),
                Position = u368.innerSphere.innerBeam.WorldPosition
            }):Play();
            TweenService:Create(u368.outerBeam, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                Size = Vector3.new(18, 113, 18),
                Position = u368.innerSphere.outerBeam.WorldPosition
            }):Play();
            TweenService:Create(u368.outerRing, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                Size = Vector3.new(51.116, 3.33, 51.669),
                Position = u368.innerSphere.outerRing.WorldPosition
            }):Play();
            local u369 = {
                outerSphereWind = 15,
                innerBeam = 10,
                outerBeam = 7,
                outerRing = 6
            };
            local u370 = nil;
            u370 = RunService.Heartbeat:Connect(function() -- Line: 2670
                -- upvalues: timeSync (ref), u298 (copy), u370 (ref), Debris (ref), WorldCFrame (copy), TweenService (ref), u367 (copy), u368 (copy), u369 (copy)
                if u298 >= timeSync:GetTime() then
                    for i, v in pairs(u369) do
                        local v371 = u368[i];
                        v371.CFrame = v371.CFrame * CFrame.Angles(0, math.rad(v), 0);
                    end;

                    return;
                end;

                u370:Disconnect();
                u370 = nil;
                local v372 = game.ReplicatedStorage.projectiles.genericNeonBall:Clone();
                v372.Transparency = 0;
                v372.Color = Color3.fromRGB(255, 251, 142);
                Debris:AddItem(v372, 5);
                v372.CFrame = WorldCFrame;
                v372.Parent = workspace;
                TweenService:Create(v372, TweenInfo.new(1, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
                    Size = Vector3.new(300, 300, 300),
                    Transparency = 1
                }):Play();
                wait(0.1);
                u367:Destroy();
                u368:Destroy();
            end);
        end;

        return;
    end;

    local v373 = game.ReplicatedStorage.projectiles.genericNeonBall:Clone();
    v373.Transparency = 0;
    v373.Color = Color3.fromRGB(255, 64, 64);
    Debris:AddItem(v373, 5);
    v373.CFrame = u298;
    v373.Parent = workspace;
    TweenService:Create(v373, TweenInfo.new(1, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
        Size = Vector3.new(300, 300, 300),
        Transparency = 1
    }):Play();
end);
game.ReplicatedStorage.remotes:WaitForChild("mapSpecificEvent").OnClientEvent:Connect(function(p374, u375) -- Line: 2698
    -- upvalues: u2 (copy), CameraShaker (copy), TweenService (copy), Debris (copy), Random_new_ret (copy)
    if p374 == "Shake Screens" then
        u2:Shake(CameraShaker.Presets[u375]);

        return;
    end;

    if p374 == "Steampunk Back Flames" then
        wait(0.5);

        for _, child in pairs(u375:GetChildren()) do
            if child.Name == "flamePart" then
                child.flame.Enabled = true;
            end;
        end;

        wait(1);

        for _, child in pairs(u375:GetChildren()) do
            if child.Name == "flamePart" then
                child.flame.Enabled = false;
            end;
        end;

        return;
    end;

    if p374 == "ROTG Enable Clouds Emitter" then
        u375.Enabled = true;

        return;
    end;

    if p374 == "ROTG Minion Glow" then
        for _, child in pairs(u375:GetChildren()) do
            if child:IsA("BasePart") then
                local v376 = {
                    Color = Color3.fromRGB(213, 115, 61)
                };
                TweenService:Create(child, TweenInfo.new(1, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, 0, false, 0), v376):Play();
                child.Material = Enum.Material.Neon;
            end;
        end;

        return;
    end;

    if p374 == "ROTG Minion Explosion" then
        local v377 = game.ReplicatedStorage.enemyProjectiles["Realm Of The Gods"].minionExplosionBall:Clone();
        Debris:AddItem(v377, 5);
        v377.Parent = workspace;
        v377.CFrame = u375;
        TweenService:Create(v377, TweenInfo.new(0.5, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, 0, false, 0), {
            Size = Vector3.new(45, 45, 45),
            Transparency = 1
        }):Play();

        return;
    end;

    if p374 == "ROTG Breath Fire" then
        u375.Enabled = true;
        wait(1.8);
        u375.Enabled = false;

        return;
    end;

    if p374 == "ROTG Breath Fire2" then
        u375.Enabled = true;
        wait(1.2);
        u375.Enabled = false;

        return;
    end;

    if p374 == "ROTG2 Rock Fall" then
        local u378 = game.ReplicatedStorage.enemyProjectiles["Realm Of The Gods"].rockDebri:Clone();
        u378.CFrame = u375 + Vector3.new(0, 50, 0);
        u378.CFrame = u378.CFrame * CFrame.Angles(Random_new_ret:NextInteger(0, 360), Random_new_ret:NextInteger(0, 360), Random_new_ret:NextInteger(0, 360));
        u378.Parent = workspace;
        Debris:AddItem(u378, 6);
        wait(0.6);
        local v379 = {
            CFrame = u378.CFrame + Vector3.new(0, -53, 0)
        };
        local v380 = TweenService:Create(u378, TweenInfo.new(0.5, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, 0, false, 0), v379);
        v380.Completed:Connect(function() -- Line: 2776
            -- upvalues: Debris (ref), u378 (copy), TweenService (ref)
            local v381 = game.ReplicatedStorage.enemyProjectiles["Realm Of The Gods"].minionExplosionBall:Clone();
            Debris:AddItem(v381, 5);
            v381.Parent = workspace;
            v381.CFrame = u378.CFrame;
            TweenService:Create(v381, TweenInfo.new(0.5, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, 0, false, 0), {
                Size = Vector3.new(45, 45, 45),
                Transparency = 1
            }):Play();
            wait(0.1);
            u378:Destroy();
        end);
        v380:Play();

        return;
    end;

    if p374 == "ROTG2 Player Pulled Bubble" then
        local v382 = game.ReplicatedStorage.enemyProjectiles["Realm Of The Gods"].playerPulledBubble:Clone();
        Debris:AddItem(v382, 2.5);
        v382.Parent = workspace;
        v382.CFrame = u375.CFrame;
        v382.WeldConstraint.Part0 = u375;

        return;
    end;

    if p374 == "ROTG2 Boss Arm Glow" then
        for _, child in pairs(u375.goldenParts:GetChildren()) do
            child.Material = Enum.Material.Neon;
        end;

        wait(0.85);
        local v383 = game.ReplicatedStorage.enemyProjectiles["Realm Of The Gods"].minionExplosionBall:Clone();
        Debris:AddItem(v383, 5);
        v383.Parent = workspace;
        v383.CFrame = u375:GetPrimaryPartCFrame() + u375:GetPrimaryPartCFrame().LookVector * 8 + Vector3.new(0, -4, 0);
        TweenService:Create(v383, TweenInfo.new(0.75, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, 0, false, 0), {
            Size = Vector3.new(60, 60, 60),
            Transparency = 1
        }):Play();
        wait(0.35);

        for _, child in pairs(u375.goldenParts:GetChildren()) do
            child.Material = Enum.Material.Glass;
        end;

        return;
    end;

    if p374 == "ROTG2 Charge" then
        for _, child in pairs(u375.goldenParts:GetChildren()) do
            child.Material = Enum.Material.Neon;
        end;

        for _, descendant in pairs(u375:GetDescendants()) do
            if descendant.Name == "chargeTrail" then
                descendant.Enabled = true;
            end;
        end;

        return;
    end;

    if p374 == "ROTG2 Charge End" then
        for _, child in pairs(u375.goldenParts:GetChildren()) do
            child.Material = Enum.Material.Glass;
        end;

        for _, descendant in pairs(u375:GetDescendants()) do
            if descendant.Name == "chargeTrail" then
                descendant.Enabled = false;
            end;
        end;

        return;
    end;

    if p374 == "ROTG2 Raise Arms Glow" then
        for _, child in pairs(u375.goldenParts:GetChildren()) do
            child.Material = Enum.Material.Neon;
        end;

        wait(2);

        for _, child in pairs(u375.goldenParts:GetChildren()) do
            child.Material = Enum.Material.Glass;
        end;

        return;
    end;

    if p374 == "Mystical Garden Shoot Earth Spikes" then
        for _, child in pairs(u375:GetChildren()) do
            if child:IsA("Model") then
                local v384 = game.ReplicatedStorage.enemyProjectiles["Mystical Garden"].secondBossLocalSpike:Clone();
                Debris:AddItem(v384, 1);
                v384.Parent = workspace;
                v384:SetPrimaryPartCFrame(child.PrimaryPart.CFrame);
                local v385 = {
                    CFrame = v384:GetPrimaryPartCFrame() + v384:GetPrimaryPartCFrame().LookVector * 180
                };
                local TweenInfo_new_ret = TweenInfo.new(0.3, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, 0, false, 0);
                TweenService:Create(v384.PrimaryPart, TweenInfo_new_ret, v385):Play();
            end;
        end;

        return;
    end;

    if p374 == "Mystical Garden Random Strike" then
        local CFrame2 = u375.PrimaryPart.CFrame;
        local v386 = game.ReplicatedStorage.enemyProjectiles["Mystical Garden"].secondBossLocalRockFall:Clone();
        Debris:AddItem(v386, 1.7);
        v386.Parent = workspace;
        v386:SetPrimaryPartCFrame(u375.PrimaryPart.CFrame + Vector3.new(0, 100, 0));
        local TweenInfo_new_ret = TweenInfo.new(0.7, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, 0, false, 0);
        local v387 = TweenService:Create(v386.PrimaryPart, TweenInfo_new_ret, {
            CFrame = CFrame2
        });
        v387.Completed:Connect(function() -- Line: 2891
            -- upvalues: Debris (ref), u375 (copy), TweenService (ref)
            for i = 1, 4 do
                local v388 = game.ReplicatedStorage.enemyProjectiles["Mystical Garden"].secondBossLocalSpike:Clone();
                Debris:AddItem(v388, 1);
                v388.Parent = workspace;
                v388:SetPrimaryPartCFrame(u375.PrimaryPart.CFrame * CFrame.Angles(0, math.rad(i * 90), 0));
                local v389 = {
                    CFrame = v388:GetPrimaryPartCFrame() + v388:GetPrimaryPartCFrame().LookVector * 150
                };
                local TweenInfo_new_ret2 = TweenInfo.new(0.3, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, 0, false, 0);
                TweenService:Create(v388.PrimaryPart, TweenInfo_new_ret2, v389):Play();
                local _ = i;
            end;
        end);
        v387:Play();

        return;
    end;

    if p374 == "Mystical Garden Throw Debris Up" then
        local particlePart = workspace.Arena.particlePart;
        particlePart.particle1.Enabled = true;
        particlePart.particle2.Enabled = true;
        wait(0.4);
        particlePart.particle1.Enabled = false;
        particlePart.particle2.Enabled = false;

        return;
    end;

    if p374 == "Mystical Garden Stab Ground" then
        local particlePart = workspace.Arena.particlePart;
        particlePart.particle1.Enabled = true;
        particlePart.particle2.Enabled = true;
        wait(3);
        particlePart.particle1.Enabled = false;
        particlePart.particle2.Enabled = false;

        return;
    end;

    if p374 == "Mystical Garden Orb Explosion" then
        u375.particle.Enabled = false;
        u375.PointLight.Enabled = false;
        u375.Trail.Enabled = false;
        TweenService:Create(u375, TweenInfo.new(0.5, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, 0, false, 0), {
            Size = Vector3.new(100, 100, 100),
            Transparency = 1
        }):Play();

        return;
    end;

    if p374 ~= "Mystical Garden Raise Shield" then
        if p374 == "Mystical Garden Lower Shield" then
            local PrimaryPart = workspace.Arena.forceField.PrimaryPart;
            local v390 = {
                CFrame = PrimaryPart.CFrame + Vector3.new(0, -50, 0)
            };
            local v391 = TweenService:Create(PrimaryPart, TweenInfo.new(0.65, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, 0, false, 0), v390);
            v391.Completed:Connect(function() -- Line: 2957
                -- upvalues: PrimaryPart (copy)
                PrimaryPart.Parent.forceField.Beam1.Enabled = false;
                PrimaryPart.Parent.forceField.Beam2.Enabled = false;
            end);
            v391:Play();
        end;

        return;
    end;

    local PrimaryPart = workspace.Arena.forceField.PrimaryPart;
    local v392 = {
        CFrame = PrimaryPart.CFrame + Vector3.new(0, 50, 0)
    };
    local v393 = TweenService:Create(PrimaryPart, TweenInfo.new(0.65, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, 0, false, 0), v392);
    PrimaryPart.Parent.forceField.Beam1.Enabled = true;
    PrimaryPart.Parent.forceField.Beam2.Enabled = true;
    v393:Play();
end);
game.ReplicatedStorage.remotes:WaitForChild("easterIslandBossSpecficEvents").OnClientEvent:Connect(function(p394, p395) -- Line: 2966
    -- upvalues: u2 (copy), CameraShaker (copy), Debris (copy), TweenService (copy)
    if p394 == "Shake Screens" then
        u2:Shake(CameraShaker.Presets[p395]);

        return;
    end;

    if p394 ~= "First Boss Explosive Bomb Throw" then
        if p394 == "First Boss Poison Bomb" then
            local v396 = game.ReplicatedStorage.enemyProjectiles.poisonBomb:Clone();
            Debris:AddItem(v396, 10);
            v396.Parent = workspace;
            v396.PrimaryPart.CFrame = p395 + Vector3.new(0, 50, 0);
            local TweenInfo_new_ret = TweenInfo.new(0.5, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, 0, false, 0);
            TweenService:Create(v396.PrimaryPart, TweenInfo_new_ret, {
                CFrame = p395
            }):Play();
            wait(0.5);
            v396.PrimaryPart.Poison.Enabled = true;
            v396.Union.Transparency = 0;
            wait(7);
            v396.Union.Transparency = 1;
            v396.PrimaryPart.Poison.Enabled = false;
            v396.eggPart:Destroy();
            v396.fuse:Destroy();

            return;
        end;

        if p394 ~= "First Boss Ice Bomb" then
            if p394 == "Second Boss Rock Fall" then
                local v397 = game.ReplicatedStorage.enemyProjectiles.rock:Clone();
                Debris:AddItem(v397, 5);
                v397.Parent = workspace;
                v397.CFrame = p395 + Vector3.new(0, 50, 0);
                TweenService:Create(v397, TweenInfo.new(0.3, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, 0, false, 0), {
                    CFrame = p395
                }):Play();
                wait(0.3);
                v397.hitSound:Play();
                v397.Transparency = 1;
                local v398 = game.ReplicatedStorage.enemyProjectiles.genericNeonBall:Clone();
                v398.Transparency = 0;
                v398.Color = Color3.fromRGB(109, 101, 91);
                Debris:AddItem(v398, 5);
                v398.Parent = workspace;
                v398.CFrame = p395;
                TweenService:Create(v398, TweenInfo.new(0.35, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, 0, false, 0), {
                    Size = Vector3.new(36, 36, 36),
                    Transparency = 1
                }):Play();
            end;

            return;
        end;

        local v399 = game.ReplicatedStorage.enemyProjectiles.iceBomb:Clone();
        Debris:AddItem(v399, 10);
        v399.Parent = workspace;
        v399.PrimaryPart.CFrame = p395 + Vector3.new(0, 50, 0);
        local TweenInfo_new_ret = TweenInfo.new(0.5, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, 0, false, 0);
        TweenService:Create(v399.PrimaryPart, TweenInfo_new_ret, {
            CFrame = p395
        }):Play();
        wait(1.65);
        local v400 = game.ReplicatedStorage.enemyProjectiles.genericNeonBall:Clone();
        v400.Transparency = 0;
        v400.Color = Color3.fromRGB(69, 206, 255);
        Debris:AddItem(v400, 5);
        v400.Parent = workspace;
        v400.CFrame = p395;
        TweenService:Create(v400, TweenInfo.new(0.35, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, 0, false, 0), {
            Size = Vector3.new(42, 42, 42),
            Transparency = 1
        }):Play();
        v399:Destroy();

        return;
    end;

    local rightHand = p395[1].rightHand;
    local v401 = p395[2];
    local v402 = game.ReplicatedStorage.enemyProjectiles.explosiveBomb:Clone();
    Debris:AddItem(v402, 10);
    v402.Parent = workspace;
    v402.PrimaryPart.CFrame = CFrame.new(rightHand.Position);
    v402.PrimaryPart.handWeld.Part0 = rightHand;
    wait(0.7);
    v402.PrimaryPart.handWeld:Destroy();
    v402.PrimaryPart.Anchored = true;
    local TweenInfo_new_ret = TweenInfo.new(0.48, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, 0, false, 0);
    TweenService:Create(v402.PrimaryPart, TweenInfo_new_ret, {
        CFrame = v401
    }):Play();
    wait(0.8);
    local v403 = game.ReplicatedStorage.enemyProjectiles.genericNeonBall:Clone();
    v403.Transparency = 0;
    v403.Color = Color3.fromRGB(255, 140, 0);
    Debris:AddItem(v403, 10);
    v403.Parent = workspace;
    v403.CFrame = v401;
    TweenService:Create(v403, TweenInfo.new(0.35, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, 0, false, 0), {
        Size = Vector3.new(40, 40, 40),
        Transparency = 1
    }):Play();
    v402:Destroy();
end);
game.ReplicatedStorage.remotes:WaitForChild("glitchBossSpecficEvents").OnClientEvent:Connect(function(p404, p405) -- Line: 3107
    -- upvalues: u2 (copy), CameraShaker (copy), Debris (copy), TweenService (copy), Random_new_ret (copy)
    if p404 == "Shake Screens" then
        u2:Shake(CameraShaker.Presets[p405]);

        return;
    end;

    if p404 == "First Boss Right Hand Blast Shot" then
        local particles = p405[1].rightHandModel.rightHandModel.Attachment.particles;
        particles.Enabled = true;
        wait(0.35);
        particles.Enabled = false;

        return;
    end;

    if p404 == "First Boss Left Hand Blast Shot" then
        local particles = p405[1].leftHandModel.leftHand.Attachment.particles;
        particles.Enabled = true;
        wait(0.35);
        particles.Enabled = false;

        return;
    end;

    if p404 == "First Boss Poison Bomb" then
        local v406 = game.ReplicatedStorage.enemyProjectiles.poisonBomb:Clone();
        Debris:AddItem(v406, 10);
        v406.Parent = workspace;
        v406.PrimaryPart.CFrame = p405 + Vector3.new(0, 50, 0);
        local TweenInfo_new_ret = TweenInfo.new(0.5, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, 0, false, 0);
        TweenService:Create(v406.PrimaryPart, TweenInfo_new_ret, {
            CFrame = p405
        }):Play();
        wait(0.5);
        v406.PrimaryPart.Poison.Enabled = true;
        v406.Union.Transparency = 0;
        wait(7);
        v406.Union.Transparency = 1;
        v406.PrimaryPart.Poison.Enabled = false;
        v406.eggPart:Destroy();
        v406.fuse:Destroy();

        return;
    end;

    if p404 ~= "First Boss Ice Bomb" then
        if p404 == "First Boss Death" then
            for i = 1, 15 do
                local v407 = game.ReplicatedStorage.projectiles.genericNeonBall:Clone();
                v407.Transparency = 0;
                Debris:AddItem(v407, 5);
                v407.Color = Color3.fromRGB(92, 167, 162);
                v407.Parent = workspace;
                local CFrame2 = workspace.bossSpawnPart.CFrame;
                local v408 = Random_new_ret:NextInteger(-2, 2);
                local v409 = Random_new_ret:NextInteger(-2, 2);
                v407.CFrame = CFrame2 + Vector3.new(v408, v409, Random_new_ret:NextInteger(-2, 2));
                v407.sound:Play();
                local TweenInfo_new_ret = TweenInfo.new(0.35, Enum.EasingStyle.Quart, Enum.EasingDirection.Out);
                local v410 = {
                    Transparency = 1
                };
                local v411 = Random_new_ret:NextInteger(30, 45);
                local v412 = Random_new_ret:NextInteger(30, 45);
                v410.Size = Vector3.new(v411, v412, Random_new_ret:NextInteger(30, 45));
                TweenService:Create(v407, TweenInfo_new_ret, v410):Play();
                wait(0.1);
                local _ = i;
            end;

            local v413 = game.ReplicatedStorage.projectiles.genericNeonBall:Clone();
            v413.Transparency = 0;
            Debris:AddItem(v413, 5);
            v413.Color = Color3.fromRGB(92, 167, 162);
            v413.Parent = workspace;
            v413.CFrame = workspace.bossSpawnPart.CFrame;
            v413.sound.Volume = 0.5;
            v413.sound.PlaybackSpeed = 0.5;
            v413.sound:Play();
            TweenService:Create(v413, TweenInfo.new(1, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
                Size = Vector3.new(100, 100, 100),
                Transparency = 1
            }):Play();

            for _, descendant in pairs(workspace:GetDescendants()) do
                if descendant:IsA("BasePart") and descendant.Name == "neonEndFlash" then
                    descendant.Color = Color3.fromRGB(92, 167, 162);
                end;
            end;
        end;

        return;
    end;

    local v414 = game.ReplicatedStorage.enemyProjectiles.iceBomb:Clone();
    Debris:AddItem(v414, 10);
    v414.Parent = workspace;
    v414.PrimaryPart.CFrame = p405 + Vector3.new(0, 50, 0);
    local TweenInfo_new_ret = TweenInfo.new(0.5, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, 0, false, 0);
    TweenService:Create(v414.PrimaryPart, TweenInfo_new_ret, {
        CFrame = p405
    }):Play();
    wait(1.65);
    local v415 = game.ReplicatedStorage.enemyProjectiles.genericNeonBall:Clone();
    v415.Transparency = 0;
    v415.Color = Color3.fromRGB(69, 206, 255);
    Debris:AddItem(v415, 5);
    v415.Parent = workspace;
    v415.CFrame = p405;
    TweenService:Create(v415, TweenInfo.new(0.35, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, 0, false, 0), {
        Size = Vector3.new(42, 42, 42),
        Transparency = 1
    }):Play();
    v414:Destroy();
end);