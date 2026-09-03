-- Advanced Autofarm Script for Dungeon Quest Reborn
-- Bugfix: Eliminated flawed Phase 2 straight-line shortcut to force robust Navmesh routing

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local PathfindingService = game:GetService("PathfindingService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local CollectionService = game:GetService("CollectionService")

if _G.DungeonAutofarmDestruct then
    pcall(_G.DungeonAutofarmDestruct)
end

-- Configuration
local farmEnabled = true
local attackRange = 10
local safeDistance = 8
local wallPadding = 2.0
local clickInterval = 0.1
local clickHoldDuration = 0.02
local abilityInterval = 0.1
local abilityHoldDuration = 0.04

local damageBrickDetectionRange = 120
local damageBrickClearance = 3.5
local preemptiveClearance = 6.5

local minimumAttackRange = 3
local maximumAttackRange = 25
local minimumSafeDistance = 3
local maximumSafeDistance = 25
local minimumDamageBrickRange = 10
local maximumDamageBrickRange = 150
local minimumWallPadding = 1.0
local maximumWallPadding = 6.0

local enemyScanInterval = 0.15
local damageBrickCatalogRefreshInterval = 0.3
local pathRecomputeInterval = 0.2
local pathFailureRetryInterval = 0.5
local pathTargetMoveThreshold = 3.0
local waypointAdvanceDistance = 4.0
local stuckTimeout = 0.65
local stuckProgressDistance = 0.8

-- Runtime Variables
local gameSpecificAttackMethod = nil
local detectedAttackRemote = nil
local lastClickTime = -math.huge
local mainConnection = nil
local enemyScanConnection = nil
local childAddedConnection = nil
local scriptGui = nil
local destroyed = false

local toggleButton = nil
local statusLabel = nil
local enemyCountLabel = nil
local closestEnemyLabel = nil
local enemyHealthLabel = nil
local damageBrickCountLabel = nil
local qAbilityButton = nil
local eAbilityButton = nil
local renderPathButton = nil
local renderHazardsButton = nil
local renderHitboxButton = nil

local autoQEnabled = false
local autoEEnabled = false
local renderPathEnabled = true
local renderHazardsEnabled = true
local renderHitboxEnabled = true
local lastQTime = -math.huge
local lastETime = -math.huge
local sliderConnections = {}

local currentPathWaypoints = {}
local currentPathIndex = 1
local currentPathEnemy = nil
local lastPathTargetPosition = nil
local lastPathComputeTime = -math.huge
local isComputingPath = false
local pathNodesFolder = nil
local hazardHighlightsFolder = nil
local hitboxVisualizerFolder = nil
local hoverHighlightFolder = nil
local pathBlockedConnection = nil
local pathNeedsRecompute = false
local lastProgressPosition = nil
local lastProgressTime = os.clock()
local lastIssuedMovePosition = nil

local detectedDamageBricks = {}
local hazardSpawnTimes = {}
local manuallyBlacklistedBricks = {}
local damageBrickCandidates = {}
local lastDamageBrickCatalogTime = -math.huge

-- Global Cache for Mobs & Billboards
local cachedEnemy = nil
local cachedEnemyCount = 0

-- Telegraph Inspector Window Reference
local telegraphFeedList = nil

-- Heavy Debug Logger
local function heavyDebug(category, message)
    local now = os.clock()
    print(string.format("[HEAVY_DEBUG][%s][%.3f] %s", category, now, tostring(message)))
end

-- Remote Hook & Logger
local function hookAttackRemotes()
    pcall(function()
        local mt = getrawmetatable(game)
        if not mt then return end
        local oldNamecall = mt.__namecall
        setreadonly(mt, false)

        mt.__namecall = newcclosure(function(self, ...)
            local method = getnamecallmethod()
            local args = {...}

            if method == "FireServer" or method == "fireServer" then
                local remoteName = tostring(self.Name):lower()
                if remoteName:find("attack") or remoteName:find("swing") or remoteName:find("hit") or remoteName:find("spell") or remoteName:find("ability") or remoteName:find("m1") or remoteName:find("use") then
                    if not detectedAttackRemote then
                        detectedAttackRemote = self
                    end
                end
            end

            return oldNamecall(self, ...)
        end)

        setreadonly(mt, true)
    end)
end

-- Realistic Player Hitbox
local function getPlayerHitboxMetrics()
    local character = LocalPlayer.Character
    if not character then
        return Vector3.new(2, 5, 2), 1.25, 5.0, Vector3.zero
    end

    local hrp = character:FindFirstChild("HumanoidRootPart")
    local size = hrp and hrp.Size or Vector3.new(2, 5, 2)
    local radius = math.max(size.X, size.Z) * 0.6
    local totalHeight = size.Y + 0.5

    return size, radius, totalHeight, Vector3.zero
end

local function clearHitboxVisualizer()
    if hitboxVisualizerFolder then
        hitboxVisualizerFolder:Destroy()
        hitboxVisualizerFolder = nil
    end
end

local function updateHitboxVisualizer()
    if not renderHitboxEnabled or not farmEnabled then
        clearHitboxVisualizer()
        return
    end

    local character = LocalPlayer.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if not root then
        clearHitboxVisualizer()
        return
    end

    if not hitboxVisualizerFolder then
        hitboxVisualizerFolder = Instance.new("Folder")
        hitboxVisualizerFolder.Name = "DungeonPlayerHitboxVisualizer"
        hitboxVisualizerFolder.Parent = Workspace
    end

    local size, radius, totalHeight = getPlayerHitboxMetrics()

    local cylAdorn = hitboxVisualizerFolder:FindFirstChild("HitboxPlanarCylinder")
    if not cylAdorn then
        cylAdorn = Instance.new("CylinderHandleAdornment")
        cylAdorn.Name = "HitboxPlanarCylinder"
        cylAdorn.Adornee = root
        cylAdorn.Color3 = Color3.fromRGB(0, 220, 255)
        cylAdorn.Transparency = 0.65
        cylAdorn.ZIndex = 3
        cylAdorn.AlwaysOnTop = true
        cylAdorn.Parent = hitboxVisualizerFolder
    end
    cylAdorn.Height = totalHeight
    cylAdorn.Radius = radius
    cylAdorn.CFrame = CFrame.Angles(math.rad(90), 0, 0)

    local boxAdorn = hitboxVisualizerFolder:FindFirstChild("HitboxSolidBox")
    if not boxAdorn then
        boxAdorn = Instance.new("SelectionBox")
        boxAdorn.Name = "HitboxSolidBox"
        boxAdorn.Adornee = root
        boxAdorn.Color3 = Color3.fromRGB(0, 255, 200)
        boxAdorn.LineThickness = 0.03
        boxAdorn.SurfaceColor3 = Color3.fromRGB(0, 180, 255)
        boxAdorn.SurfaceTransparency = 0.8
        boxAdorn.Parent = hitboxVisualizerFolder
    end
end

local function isOwnedByPlayerOrTeammate(instance)
    if not instance then return false end
    local character = LocalPlayer.Character

    if character and instance:IsDescendantOf(character) then
        return true
    end

    for _, player in ipairs(Players:GetPlayers()) do
        local pChar = player.Character
        if pChar and instance:IsDescendantOf(pChar) then
            return true
        end

        local creator = instance:FindFirstChild("Creator") 
            or instance:FindFirstChild("creator") 
            or instance:FindFirstChild("Owner") 
            or instance:FindFirstChild("Player")
            or instance:FindFirstChild("Caster")
            
        if creator and (creator.Value == player or creator.Value == pChar or creator.Value == player.Name or creator.Value == player.UserId) then
            return true
        end

        for attr, val in pairs(instance:GetAttributes()) do
            if (attr:lower():find("creator") or attr:lower():find("owner") or attr:lower():find("player") or attr:lower():find("caster")) 
                and (val == player.Name or val == player.UserId or (character and val == character.Name)) then
                return true
            end
        end
    end

    if instance.Parent and instance.Parent ~= Workspace then
        return isOwnedByPlayerOrTeammate(instance.Parent)
    end

    return false
end

local mapFolderNames = {
    "map", "rooms", "room", "geometry", "terrain", "dungeonmap",
    "environment", "structures", "spawns", "doors", "walls", "floors", 
    "lighting", "effects", "props", "arena", "gate", "door", "decorations"
}

local function isMapGeometry(part)
    local cur = part
    while cur and cur ~= Workspace do
        local lowerName = string.lower(cur.Name)
        for _, name in ipairs(mapFolderNames) do
            if string.find(lowerName, name, 1, true) then
                return true
            end
        end
        cur = cur.Parent
    end
    return false
end

local nonDamagingKeywords = {
    "entry", "intro", "cutscene", "cinematic", "spawn", "trigger", 
    "door", "gate", "transition", "portal", "barrier", "camera", "boundary",
    "blade", "staff", "sword", "weapon", "bow", "wand", "hammer", "axe"
}

local function isDamageBrick(part)
    if not part:IsA("BasePart") then return false end

    if pathNodesFolder and part:IsDescendantOf(pathNodesFolder) then return false end
    if hazardHighlightsFolder and part:IsDescendantOf(hazardHighlightsFolder) then return false end
    if hitboxVisualizerFolder and part:IsDescendantOf(hitboxVisualizerFolder) then return false end
    if hoverHighlightFolder and part:IsDescendantOf(hoverHighlightFolder) then return false end
    if part.Name == "DungeonAutofarmPathNodes" or string.find(part.Name, "^Node_") or string.find(part.Name, "^SubNode_") then return false end
    if part.Name == "Terrain" or part.Name == "Baseplate" then return false end

    if isOwnedByPlayerOrTeammate(part) then return false end

    local ancestorModel = part:FindFirstAncestorOfClass("Model")
    if ancestorModel and ancestorModel:FindFirstChildOfClass("Humanoid") then
        return false
    end

    if part.CanCollide then return false end
    if isMapGeometry(part) then return false end
    if manuallyBlacklistedBricks[part] then return true end

    local parent = part.Parent
    if not parent or parent == Workspace then return false end

    local parentName = string.lower(parent.Name)
    local partName = string.lower(part.Name)

    for _, word in ipairs(nonDamagingKeywords) do
        if string.find(parentName, word, 1, true) or string.find(partName, word, 1, true) then
            return false
        end
    end

    local isTelegraphName = (partName == "precast" 
        or partName == "hitbox" 
        or partName == "telegraph")

    if not isTelegraphName then
        return false
    end

    local isEnemyAttackContainer = string.find(parentName, "^npc")
        or string.find(parentName, "^boss")
        or string.find(parentName, "^mob")
        or string.find(parentName, "^enemy")
        or string.find(parentName, "flameshot", 1, true)
        or string.find(parentName, "middlefire", 1, true)
        or string.find(parentName, "strike", 1, true)
        or string.find(parentName, "slam", 1, true)
        or string.find(parentName, "cleave", 1, true)
        or string.find(parentName, "blast", 1, true)
        or string.find(parentName, "spin", 1, true)
        or string.find(parentName, "fire", 1, true)

    if isEnemyAttackContainer then
        return true
    end

    return false
end

local function closestPointOnPart(part, worldPosition)
    local localPos = part.CFrame:PointToObjectSpace(worldPosition)
    local size = part.Size
    local halfSize = size * 0.5
    local clampedLocal = localPos

    local isCylinder = false
    local isSphere = false

    if part:IsA("Part") then
        local success, shape = pcall(function() return part.Shape end)
        if success then
            isCylinder = (shape == Enum.PartType.Cylinder)
            isSphere = (shape == Enum.PartType.Ball)
        end
    end

    local partNameLower = part.Name:lower()
    if not isCylinder then
        isCylinder = part:IsA("CylinderHandleAdornment") or (partNameLower:find("cylinder") ~= nil) or (partNameLower:find("ring") ~= nil)
    end
    if not isSphere then
        isSphere = (partNameLower:find("sphere") ~= nil) or (partNameLower:find("ball") ~= nil)
    end

    if isCylinder then
        local halfLength = halfSize.X
        local radius = math.min(halfSize.Y, halfSize.Z)
        local clampedX = math.clamp(localPos.X, -halfLength, halfLength)
        local yzVec = Vector2.new(localPos.Y, localPos.Z)
        local yzDist = yzVec.Magnitude

        if yzDist > radius then
            local norm = yzVec.Unit * radius
            clampedLocal = Vector3.new(clampedX, norm.X, norm.Y)
        else
            clampedLocal = Vector3.new(clampedX, localPos.Y, localPos.Z)
        end
    elseif isSphere then
        local radius = math.min(halfSize.X, halfSize.Y, halfSize.Z)
        if localPos.Magnitude > radius then
            clampedLocal = localPos.Unit * radius
        else
            clampedLocal = localPos
        end
    else
        clampedLocal = Vector3.new(
            math.clamp(localPos.X, -halfSize.X, halfSize.X),
            math.clamp(localPos.Y, -halfSize.Y, halfSize.Y),
            math.clamp(localPos.Z, -halfSize.Z, halfSize.Z)
        )
    end

    return part.CFrame:PointToWorldSpace(clampedLocal)
end

local function isPositionSafeFromDamageBricks(position, extraClearance)
    local _, playerRadius, totalHeight = getPlayerHitboxMetrics()
    local clearance = damageBrickClearance + playerRadius + (extraClearance or 0)
    local halfHeight = (totalHeight * 0.5) + 2.0

    for _, part in ipairs(detectedDamageBricks) do
        if part.Parent then
            local closest = closestPointOnPart(part, position)
            local horizontalDist = Vector2.new(position.X - closest.X, position.Z - closest.Z).Magnitude
            local verticalDist = math.abs(position.Y - closest.Y)
            
            if horizontalDist < clearance and verticalDist < halfHeight then
                return false
            end
        end
    end
    return true
end

local function evaluateHazardPenaltyAtPoint(pos)
    local totalPenalty = 0
    local now = os.clock()
    local _, playerRadius, totalHeight = getPlayerHitboxMetrics()
    local effectivePreemptive = preemptiveClearance + playerRadius
    local halfHeight = (totalHeight * 0.5) + 2.0

    for _, part in ipairs(detectedDamageBricks) do
        if part.Parent then
            local closest = closestPointOnPart(part, pos)
            local horizontalDist = Vector2.new(pos.X - closest.X, pos.Z - closest.Z).Magnitude
            local verticalDist = math.abs(pos.Y - closest.Y)

            if horizontalDist < effectivePreemptive and verticalDist < halfHeight then
                local depth = (effectivePreemptive - horizontalDist) / effectivePreemptive
                local spawnTime = hazardSpawnTimes[part] or now
                local age = math.clamp(now - spawnTime, 0.1, 4.0)
                
                local ageWeight = (1.0 + age * 4.5) ^ 2
                totalPenalty = totalPenalty + (depth * depth * 350 * ageWeight)
            end
        end
    end

    return totalPenalty
end

local function getActiveHazardRepulsionVector(pos)
    local repulsion = Vector3.zero
    local now = os.clock()
    local _, playerRadius, totalHeight = getPlayerHitboxMetrics()
    local effectivePreemptive = preemptiveClearance + playerRadius
    local halfHeight = (totalHeight * 0.5) + 2.0

    for _, part in ipairs(detectedDamageBricks) do
        if part.Parent then
            local closest = closestPointOnPart(part, pos)
            local flatOffset = Vector3.new(pos.X - closest.X, 0, pos.Z - closest.Z)
            local dist = flatOffset.Magnitude
            local verticalDist = math.abs(pos.Y - closest.Y)

            if dist < effectivePreemptive and verticalDist < halfHeight then
                local spawnTime = hazardSpawnTimes[part] or now
                local ageWeight = (1.0 + math.clamp(now - spawnTime, 0.1, 4.0) * 3.5) ^ 2
                local strength = ((effectivePreemptive - dist) / effectivePreemptive) * ageWeight

                local dir = dist > 0.01 and flatOffset.Unit or Vector3.new(pos.X - part.Position.X, 0, pos.Z - part.Position.Z).Unit
                if dir.Magnitude < 0.01 then dir = Vector3.new(0, 0, 1) end
                
                repulsion = repulsion + (dir * strength * 25)
            end
        end
    end

    return repulsion
end

local function clearHazardHighlights()
    if hazardHighlightsFolder then
        hazardHighlightsFolder:Destroy()
        hazardHighlightsFolder = nil
    end
end

local function updateHazardHighlights()
    if not renderHazardsEnabled then
        clearHazardHighlights()
        return
    end

    if not hazardHighlightsFolder then
        hazardHighlightsFolder = Instance.new("Folder")
        hazardHighlightsFolder.Name = "DungeonHazardHighlights"
        hazardHighlightsFolder.Parent = Workspace
    end

    for _, child in ipairs(hazardHighlightsFolder:GetChildren()) do
        local adornee = child:IsA("Highlight") and child.Adornee or (child:IsA("CylinderHandleAdornment") or child:IsA("SphereHandleAdornment") or child:IsA("SelectionBox")) and child.Adornee
        if not adornee or not adornee.Parent or not table.find(detectedDamageBricks, adornee) then
            child:Destroy()
        end
    end

    for _, part in ipairs(detectedDamageBricks) do
        if part.Parent then
            local highlightId = "Highlight_" .. part:GetDebugId()
            if not hazardHighlightsFolder:FindFirstChild(highlightId) then
                local isCylinder = false
                local isSphere = false
                if part:IsA("Part") then
                    local success, shape = pcall(function() return part.Shape end)
                    if success then
                        isCylinder = (shape == Enum.PartType.Cylinder)
                        isSphere = (shape == Enum.PartType.Ball)
                    end
                end

                local partNameLower = part.Name:lower()
                if not isCylinder then
                    isCylinder = (partNameLower:find("cylinder") ~= nil) or (partNameLower:find("ring") ~= nil)
                end
                if not isSphere then
                    isSphere = (partNameLower:find("sphere") ~= nil) or (partNameLower:find("ball") ~= nil)
                end

                if part:IsA("MeshPart") then
                    local hl = Instance.new("Highlight")
                    hl.Name = highlightId
                    hl.Adornee = part
                    hl.FillColor = Color3.fromRGB(255, 0, 0)
                    hl.FillTransparency = 0.65
                    hl.OutlineColor = Color3.fromRGB(255, 40, 40)
                    hl.OutlineTransparency = 0.1
                    hl.Parent = hazardHighlightsFolder
                elseif isCylinder then
                    local adorn = Instance.new("CylinderHandleAdornment")
                    adorn.Name = highlightId
                    adorn.Adornee = part
                    adorn.Height = part.Size.X
                    adorn.Radius = math.min(part.Size.Y, part.Size.Z) * 0.5
                    adorn.Color3 = Color3.fromRGB(255, 30, 30)
                    adorn.Transparency = 0.5
                    adorn.ZIndex = 2
                    adorn.AlwaysOnTop = true
                    adorn.CFrame = CFrame.Angles(0, math.rad(90), 0)
                    adorn.Parent = hazardHighlightsFolder
                elseif isSphere then
                    local adorn = Instance.new("SphereHandleAdornment")
                    adorn.Name = highlightId
                    adorn.Adornee = part
                    adorn.Radius = math.min(part.Size.X, part.Size.Y, part.Size.Z) * 0.5
                    adorn.Color3 = Color3.fromRGB(255, 30, 30)
                    adorn.Transparency = 0.5
                    adorn.ZIndex = 2
                    adorn.AlwaysOnTop = true
                    adorn.Parent = hazardHighlightsFolder
                else
                    local box = Instance.new("SelectionBox")
                    box.Name = highlightId
                    box.Adornee = part
                    box.Color3 = Color3.fromRGB(255, 30, 30)
                    box.LineThickness = 0.04
                    box.SurfaceColor3 = Color3.fromRGB(255, 0, 0)
                    box.SurfaceTransparency = 0.65
                    box.Parent = hazardHighlightsFolder
                end
            end
        end
    end
end

local function clearHoverHighlight()
    if hoverHighlightFolder then
        hoverHighlightFolder:Destroy()
        hoverHighlightFolder = nil
    end
end

local function setHoverHighlight(part)
    clearHoverHighlight()
    if not part or not part.Parent then return end

    hoverHighlightFolder = Instance.new("Folder")
    hoverHighlightFolder.Name = "DungeonHoverInspect"
    hoverHighlightFolder.Parent = Workspace

    local hl = Instance.new("Highlight")
    hl.Adornee = part
    hl.FillColor = Color3.fromRGB(0, 255, 255)
    hl.FillTransparency = 0.4
    hl.OutlineColor = Color3.fromRGB(255, 255, 0)
    hl.OutlineTransparency = 0
    hl.Parent = hoverHighlightFolder

    local box = Instance.new("SelectionBox")
    box.Adornee = part
    box.Color3 = Color3.fromRGB(255, 255, 0)
    box.LineThickness = 0.08
    box.Parent = hoverHighlightFolder
end

local function updateTelegraphFeedUI()
    if not telegraphFeedList then return end

    for _, child in ipairs(telegraphFeedList:GetChildren()) do
        if child:IsA("Frame") or child:IsA("TextButton") then
            child:Destroy()
        end
    end

    if #detectedDamageBricks == 0 then
        local emptyLabel = Instance.new("TextLabel")
        emptyLabel.Size = UDim2.new(1, 0, 0, 24)
        emptyLabel.BackgroundTransparency = 1
        emptyLabel.Font = Enum.Font.GothamItalic
        emptyLabel.Text = "No active hazards detected"
        emptyLabel.TextColor3 = Color3.fromRGB(150, 153, 165)
        emptyLabel.TextSize = 12
        emptyLabel.Parent = telegraphFeedList
        return
    end

    local now = os.clock()
    for i, part in ipairs(detectedDamageBricks) do
        local row = Instance.new("TextButton")
        row.Size = UDim2.new(1, 0, 0, 36)
        row.BackgroundColor3 = Color3.fromRGB(35, 38, 47)
        row.BorderSizePixel = 0
        row.AutoButtonColor = false
        row.Text = ""
        row.Parent = telegraphFeedList

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 5)
        corner.Parent = row

        local nameLabel = Instance.new("TextLabel")
        nameLabel.Size = UDim2.new(0.65, -6, 0, 18)
        nameLabel.Position = UDim2.fromOffset(6, 2)
        nameLabel.BackgroundTransparency = 1
        nameLabel.Font = Enum.Font.GothamBold
        nameLabel.Text = string.format("%d. %s", i, part.Name)
        nameLabel.TextColor3 = Color3.fromRGB(255, 95, 95)
        nameLabel.TextSize = 12
        nameLabel.TextXAlignment = Enum.TextXAlignment.Left
        nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
        nameLabel.Parent = row

        local parentLabel = Instance.new("TextLabel")
        parentLabel.Size = UDim2.new(0.65, -6, 0, 14)
        parentLabel.Position = UDim2.fromOffset(6, 18)
        parentLabel.BackgroundTransparency = 1
        parentLabel.Font = Enum.Font.Gotham
        parentLabel.Text = part.Parent and part.Parent.Name or "Workspace"
        parentLabel.TextColor3 = Color3.fromRGB(170, 175, 190)
        parentLabel.TextSize = 11
        parentLabel.TextXAlignment = Enum.TextXAlignment.Left
        parentLabel.TextTruncate = Enum.TextTruncate.AtEnd
        parentLabel.Parent = row

        local spawnTime = hazardSpawnTimes[part] or now
        local age = math.max(now - spawnTime, 0)
        local ageLabel = Instance.new("TextLabel")
        ageLabel.Size = UDim2.new(0.35, -6, 1, 0)
        ageLabel.Position = UDim2.new(0.65, 0, 0, 0)
        ageLabel.BackgroundTransparency = 1
        ageLabel.Font = Enum.Font.GothamMedium
        ageLabel.Text = string.format("Age: %.1fs", age)
        ageLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
        ageLabel.TextSize = 11
        ageLabel.TextXAlignment = Enum.TextXAlignment.Right
        ageLabel.Parent = row

        row.MouseEnter:Connect(function()
            row.BackgroundColor3 = Color3.fromRGB(50, 55, 70)
            setHoverHighlight(part)
        end)
        row.MouseLeave:Connect(function()
            row.BackgroundColor3 = Color3.fromRGB(35, 38, 47)
            clearHoverHighlight()
        end)
    end
end

local function scanDamageBricks(rootPosition)
    local now = os.clock()
    if now - lastDamageBrickCatalogTime >= damageBrickCatalogRefreshInterval then
        local candidates = {}
        for _, instance in ipairs(Workspace:GetChildren()) do
            if instance:IsA("Model") and not isOwnedByPlayerOrTeammate(instance) then
                for _, part in ipairs(instance:GetChildren()) do
                    if part:IsA("BasePart") and isDamageBrick(part) then
                        table.insert(candidates, part)
                        if not hazardSpawnTimes[part] then
                            hazardSpawnTimes[part] = now
                        end
                    end
                end
            end
        end
        damageBrickCandidates = candidates
        lastDamageBrickCatalogTime = now
    end

    local found = {}
    for _, instance in ipairs(damageBrickCandidates) do
        if instance.Parent and not isOwnedByPlayerOrTeammate(instance) then
            local closestPoint = closestPointOnPart(instance, rootPosition)
            if (rootPosition - closestPoint).Magnitude <= damageBrickDetectionRange then
                table.insert(found, instance)
                if not hazardSpawnTimes[instance] then
                    hazardSpawnTimes[instance] = now
                end
            end
        else
            hazardSpawnTimes[instance] = nil
        end
    end
    detectedDamageBricks = found

    if damageBrickCountLabel then
        damageBrickCountLabel.Text = "Telegraphs Active: " .. tostring(#found)
    end

    updateHazardHighlights()
    updateTelegraphFeedUI()
end

local function watchForNewHazards()
    if childAddedConnection then
        childAddedConnection:Disconnect()
    end

    childAddedConnection = Workspace.DescendantAdded:Connect(function(descendant)
        if descendant:IsA("BasePart") then
            task.defer(function()
                if isDamageBrick(descendant) then
                    local now = os.clock()
                    hazardSpawnTimes[descendant] = now
                    if not table.find(damageBrickCandidates, descendant) then
                        table.insert(damageBrickCandidates, descendant)
                    end
                    local character = LocalPlayer.Character
                    local root = character and character:FindFirstChild("HumanoidRootPart")
                    if root then
                        local closestPoint = closestPointOnPart(descendant, root.Position)
                        if (root.Position - closestPoint).Magnitude <= damageBrickDetectionRange then
                            if not table.find(detectedDamageBricks, descendant) then
                                table.insert(detectedDamageBricks, descendant)
                                updateHazardHighlights()
                                updateTelegraphFeedUI()
                                pathNeedsRecompute = true
                                lastPathComputeTime = -math.huge
                            end
                        end
                    end
                end
            end)
        end
    end)
end

local function clearRenderedPath()
    if pathNodesFolder then
        pathNodesFolder:Destroy()
        pathNodesFolder = nil
    end
end

-- Render High-Visibility Path
local function renderCurrentPath()
    clearRenderedPath()
    if not renderPathEnabled or #currentPathWaypoints == 0 then return end

    pathNodesFolder = Instance.new("Folder")
    pathNodesFolder.Name = "DungeonAutofarmPathNodes"
    pathNodesFolder.Parent = Workspace

    for index, waypoint in ipairs(currentPathWaypoints) do
        local node = Instance.new("Part")
        node.Name = "Node_" .. tostring(index)
        node.Size = Vector3.new(0.45, 0.45, 0.45)
        node.Position = waypoint.Position + Vector3.new(0, 0.2, 0)
        node.Anchored = true
        node.CanCollide = false
        node.CanQuery = false
        node.CanTouch = false
        node.CastShadow = false
        node.Material = Enum.Material.Neon
        node.Color = Color3.fromRGB(0, 160, 255)
        node.Parent = pathNodesFolder

        local nextWaypoint = currentPathWaypoints[index + 1]
        if nextWaypoint then
            local dist = (nextWaypoint.Position - waypoint.Position).Magnitude
            local numSubNodes = math.floor(dist / 1.5)
            for i = 1, numSubNodes do
                local alpha = i / (numSubNodes + 1)
                local subPos = waypoint.Position:Lerp(nextWaypoint.Position, alpha)

                local subNode = Instance.new("Part")
                subNode.Name = "SubNode_" .. tostring(index) .. "_" .. tostring(i)
                subNode.Size = Vector3.new(0.18, 0.18, 0.18)
                subNode.Position = subPos + Vector3.new(0, 0.2, 0)
                subNode.Anchored = true
                subNode.CanCollide = false
                subNode.CanQuery = false
                subNode.CanTouch = false
                subNode.CastShadow = false
                subNode.Material = Enum.Material.Neon
                subNode.Color = Color3.fromRGB(255, 255, 255)
                subNode.Parent = pathNodesFolder
            end
        end
    end
end

local function resetPursuitPath()
    if pathBlockedConnection then
        pathBlockedConnection:Disconnect()
        pathBlockedConnection = nil
    end
    currentPathWaypoints = {}
    currentPathIndex = 1
    currentPathEnemy = nil
    lastPathTargetPosition = nil
    lastPathComputeTime = -math.huge
    pathNeedsRecompute = false
    isComputingPath = false
    lastProgressPosition = nil
    lastProgressTime = os.clock()
    lastIssuedMovePosition = nil
    clearRenderedPath()
end

local function projectToGround(position, enemy)
    local exclusions = {}
    if LocalPlayer.Character then table.insert(exclusions, LocalPlayer.Character) end
    if enemy then table.insert(exclusions, enemy) end
    if pathNodesFolder then table.insert(exclusions, pathNodesFolder) end
    if hazardHighlightsFolder then table.insert(exclusions, hazardHighlightsFolder) end
    if hitboxVisualizerFolder then table.insert(exclusions, hitboxVisualizerFolder) end
    if hoverHighlightFolder then table.insert(exclusions, hoverHighlightFolder) end

    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = exclusions
    params.IgnoreWater = false

    local result = Workspace:Raycast(
        Vector3.new(position.X, position.Y + 6, position.Z),
        Vector3.new(0, -40, 0),
        params
    )
    return result and (result.Position + Vector3.new(0, 0.1, 0)) or position
end

local function isPathSegmentClear(fromPosition, toPosition, enemy)
    local flatDelta = Vector3.new(toPosition.X - fromPosition.X, 0, toPosition.Z - fromPosition.Z)
    local distance = flatDelta.Magnitude
    if distance < 0.1 then return true end

    local exclusions = {}
    if LocalPlayer.Character then table.insert(exclusions, LocalPlayer.Character) end
    if enemy then table.insert(exclusions, enemy) end
    if pathNodesFolder then table.insert(exclusions, pathNodesFolder) end
    if hazardHighlightsFolder then table.insert(exclusions, hazardHighlightsFolder) end
    if hitboxVisualizerFolder then table.insert(exclusions, hitboxVisualizerFolder) end
    if hoverHighlightFolder then table.insert(exclusions, hoverHighlightFolder) end

    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = exclusions
    params.IgnoreWater = true

    local direction = flatDelta.Unit
    local side = Vector3.new(-direction.Z, 0, direction.X)
    local _, playerRadius = getPlayerHitboxMetrics()
    local clearanceOffset = math.max(wallPadding, playerRadius + 0.6)

    for _, sideOffset in ipairs({0, clearanceOffset, -clearanceOffset}) do
        for _, height in ipairs({1.2, 2.8, 4.2}) do
            local origin = fromPosition + Vector3.new(0, height, 0) + (side * sideOffset)
            local destination = toPosition + Vector3.new(0, height, 0) + (side * sideOffset)
            local hit = Workspace:Raycast(origin, destination - origin, params)
            if hit and hit.Instance and hit.Instance.CanCollide then
                return false
            end
        end
    end

    local groundCheck = Workspace:Raycast(
        toPosition + Vector3.new(0, 3.0, 0),
        Vector3.new(0, -12, 0),
        params
    )
    if not groundCheck then
        return false
    end

    return true
end

local function findStagingSafePoint(rootPos, targetPos, enemy)
    local candidates = {}
    local _, playerRadius = getPlayerHitboxMetrics()

    for _, part in ipairs(detectedDamageBricks) do
        if part.Parent then
            local localPos = part.CFrame:PointToObjectSpace(rootPos)
            local size = part.Size
            local halfSize = size * 0.5
            local pushDist = damageBrickClearance + playerRadius + 1.0

            local escapeLocal
            if halfSize.X < halfSize.Z then
                local xDir = localPos.X >= 0 and 1 or -1
                escapeLocal = Vector3.new(xDir * (halfSize.X + pushDist), 0, math.clamp(localPos.Z, -halfSize.Z, halfSize.Z))
            else
                local zDir = localPos.Z >= 0 and 1 or -1
                escapeLocal = Vector3.new(math.clamp(localPos.X, -halfSize.X, halfSize.X), 0, zDir * (halfSize.Z + pushDist))
            end

            local edgeWorld = projectToGround(part.CFrame:PointToWorldSpace(escapeLocal), enemy)
            
            if isPathSegmentClear(rootPos, edgeWorld, enemy) then
                local penalty = evaluateHazardPenaltyAtPoint(edgeWorld)
                local isSafe = isPositionSafeFromDamageBricks(edgeWorld, 0.5)
                local distToTarget = Vector2.new(edgeWorld.X - targetPos.X, edgeWorld.Z - targetPos.Z).Magnitude
                table.insert(candidates, {
                    Position = edgeWorld,
                    Distance = (edgeWorld - rootPos).Magnitude,
                    DistToTarget = distToTarget,
                    Penalty = penalty,
                    IsSafe = isSafe
                })
            end
        end
    end

    local distances = {2, 4, 7, 10, 14, 20}
    local angles = {0, 15, -15, 30, -30, 45, -45, 60, -60, 90, -90, 120, -120, 150, -150, 180}

    for _, dist in ipairs(distances) do
        for _, angle in ipairs(angles) do
            local rad = math.rad(angle)
            local offset = Vector3.new(math.sin(rad) * dist, 0, math.cos(rad) * dist)
            local candidate = projectToGround(Vector3.new(rootPos.X + offset.X, rootPos.Y, rootPos.Z + offset.Z), enemy)
            
            if isPathSegmentClear(rootPos, candidate, enemy) then
                local penalty = evaluateHazardPenaltyAtPoint(candidate)
                local isSafe = isPositionSafeFromDamageBricks(candidate, 0.5)
                local distToTarget = Vector2.new(candidate.X - targetPos.X, candidate.Z - targetPos.Z).Magnitude
                table.insert(candidates, {
                    Position = candidate,
                    Distance = dist,
                    DistToTarget = distToTarget,
                    Penalty = penalty,
                    IsSafe = isSafe
                })
            end
        end
    end

    table.sort(candidates, function(a, b)
        if a.IsSafe ~= b.IsSafe then
            return a.IsSafe
        end
        if math.abs(a.Distance - b.Distance) > 1.0 then
            return a.Distance < b.Distance
        end
        return a.DistToTarget < b.DistToTarget
    end)

    return candidates[1] and candidates[1].Position or nil
end

local function getStandOffPosition(root, enemyRoot)
    local enemyPosition = enemyRoot.Position
    local offset = root.Position - enemyPosition
    local flatOffset = Vector3.new(offset.X, 0, offset.Z)
    local directionAway

    if flatOffset.Magnitude > 0.001 then
        directionAway = flatOffset.Unit
    else
        local look = enemyRoot.CFrame.LookVector
        local flatLook = Vector3.new(-look.X, 0, -look.Z)
        directionAway = flatLook.Magnitude > 0.001 and flatLook.Unit or Vector3.new(0, 0, 1)
    end

    return enemyPosition + (directionAway * math.max(safeDistance, 2))
end

-- Primary Wall-Aware Pathfinding Router with Debug Output
local function computePursuitPath(root, enemy, targetPosition)
    if isComputingPath then 
        heavyDebug("Pathfinding", "Skipped: Already computing path in another thread.")
        return false 
    end
    isComputingPath = true

    if pathBlockedConnection then
        pathBlockedConnection:Disconnect()
        pathBlockedConnection = nil
    end

    local groundedStart = projectToGround(root.Position, enemy)
    local groundedTarget = projectToGround(targetPosition, enemy)
    local distanceToTarget = (groundedStart - groundedTarget).Magnitude
    heavyDebug("Pathfinding", string.format("Attempting path to %s. Distance: %.1f studs", enemy.Name, distanceToTarget))

    local inHazard = not isPositionSafeFromDamageBricks(groundedStart, 0.5)

    if inHazard then
        local stagingPointB = findStagingSafePoint(groundedStart, groundedTarget, enemy)
        if stagingPointB then
            heavyDebug("Pathfinding", "Phase 1: Executing Staging Escape Point B via Side-Escape.")
            local waypointsCombined = {
                {Position = groundedStart, Action = Enum.PathWaypointAction.Walk},
                {Position = stagingPointB, Action = Enum.PathWaypointAction.Walk}
            }

            local pathBC = PathfindingService:CreatePath({
                AgentRadius = wallPadding,
                AgentHeight = 4.5,
                AgentCanJump = true,
                AgentCanClimb = false,
                WaypointSpacing = 4
            })
            local successBC, _ = pcall(function()
                pathBC:ComputeAsync(stagingPointB, groundedTarget)
            end)

            if successBC and pathBC.Status == Enum.PathStatus.Success then
                local rawBC = pathBC:GetWaypoints()
                for i = 2, #rawBC do
                    table.insert(waypointsCombined, rawBC[i])
                end
            end

            currentPathWaypoints = waypointsCombined
            currentPathIndex = 2
            currentPathEnemy = enemy
            lastPathTargetPosition = targetPosition
            lastPathComputeTime = os.clock()
            lastIssuedMovePosition = nil
            pathNeedsRecompute = false
            isComputingPath = false
            renderCurrentPath()
            return true
        end
    end

    local path = PathfindingService:CreatePath({
        AgentRadius = wallPadding,
        AgentHeight = 4.5,
        AgentCanJump = true,
        AgentCanClimb = false,
        WaypointSpacing = 4
    })

    local success, computeErr = pcall(function()
        path:ComputeAsync(groundedStart, groundedTarget)
    end)

    if success and path.Status == Enum.PathStatus.Success then
        local rawWaypoints = path:GetWaypoints()
        if #rawWaypoints > 1 then
            heavyDebug("Pathfinding", string.format("SUCCESS: Navmesh path computed with %d waypoints.", #rawWaypoints))
            currentPathWaypoints = rawWaypoints
            currentPathIndex = 2
            currentPathEnemy = enemy
            lastPathTargetPosition = targetPosition
            lastPathComputeTime = os.clock()
            lastIssuedMovePosition = nil
            pathNeedsRecompute = false

            pathBlockedConnection = path.Blocked:Connect(function()
                heavyDebug("Pathfinding", "Path blocked event triggered. Forcing recompute.")
                pathNeedsRecompute = true
            end)

            isComputingPath = false
            renderCurrentPath()
            return true
        else
            heavyDebug("Pathfinding", "FAILED: Path status was Success, but waypoint count was <= 1.")
        end
    else
        heavyDebug("Pathfinding", string.format("FAILED: ComputeAsync error or non-success status. Status: %s | Error: %s", tostring(path.Status), tostring(computeErr)))
    end

    isComputingPath = false
    currentPathWaypoints = {}
    currentPathIndex = 1
    pathNeedsRecompute = true
    clearRenderedPath()
    return false
end

local function updatePursuitMovement(enemy, humanoid, root, enemyRoot)
    local targetPosition = getStandOffPosition(root, enemyRoot)
    local now = os.clock()

    local targetChanged = currentPathEnemy ~= enemy
    local targetMoved = not lastPathTargetPosition or (targetPosition - lastPathTargetPosition).Magnitude >= pathTargetMoveThreshold
    local inHazard = not isPositionSafeFromDamageBricks(root.Position, 0.5)
    local retryDelay = #currentPathWaypoints == 0 and pathFailureRetryInterval or pathRecomputeInterval
    local canRecompute = (now - lastPathComputeTime >= retryDelay) or inHazard

    if not lastProgressPosition then
        lastProgressPosition = root.Position
        lastProgressTime = now
    elseif (root.Position - lastProgressPosition).Magnitude >= stuckProgressDistance then
        lastProgressPosition = root.Position
        lastProgressTime = now
    elseif currentPathIndex <= #currentPathWaypoints
        and (root.Position - targetPosition).Magnitude > waypointAdvanceDistance
        and now - lastProgressTime >= stuckTimeout then
        heavyDebug("Stuck", "Stuck timeout reached. Forcing path recompute.")
        pathNeedsRecompute = true
        lastProgressPosition = root.Position
        lastProgressTime = now
    end

    if targetChanged or ((targetMoved or pathNeedsRecompute or #currentPathWaypoints == 0) and canRecompute) then
        if not isComputingPath then
            heavyDebug("Movement", "Triggering path recompute.")
            task.spawn(function()
                computePursuitPath(root, enemy, targetPosition)
            end)
        end
    end

    while currentPathIndex <= #currentPathWaypoints do
        local waypoint = currentPathWaypoints[currentPathIndex]
        local waypointDelta = root.Position - waypoint.Position
        local horizontalDistance = Vector3.new(waypointDelta.X, 0, waypointDelta.Z).Magnitude

        if horizontalDistance > waypointAdvanceDistance or math.abs(waypointDelta.Y) > 4.5 then
            break
        end
        currentPathIndex = currentPathIndex + 1
    end

    local waypoint = currentPathWaypoints[currentPathIndex]
    if waypoint then
        humanoid.AutoRotate = true
        if not lastIssuedMovePosition or (lastIssuedMovePosition - waypoint.Position).Magnitude > 0.15 then
            if waypoint.Action == Enum.PathWaypointAction.Jump then
                humanoid.Jump = true
            end
            humanoid:MoveTo(waypoint.Position)
            lastIssuedMovePosition = waypoint.Position
        end
    elseif (root.Position - targetPosition).Magnitude > waypointAdvanceDistance then
        pathNeedsRecompute = true
        lastIssuedMovePosition = nil
    else
        humanoid:MoveTo(targetPosition)
    end
end

-- Attack Execution
function attackEnemy(enemy)
    if not enemy then return end

    local enemyHumanoid = enemy:FindFirstChildWhichIsA("Humanoid")
    local enemyRoot = enemy:FindFirstChild("HumanoidRootPart") or enemy.PrimaryPart or enemy:FindFirstChildWhichIsA("BasePart")
    local character = LocalPlayer.Character
    local humanoid = character and character:FindFirstChildWhichIsA("Humanoid")
    local root = character and character:FindFirstChild("HumanoidRootPart")

    if not enemyRoot or not humanoid or not root then
        return
    end

    updatePursuitMovement(enemy, humanoid, root, enemyRoot)

    local flatOffset = Vector3.new(root.Position.X - enemyRoot.Position.X, 0, root.Position.Z - enemyRoot.Position.Z)
    if flatOffset.Magnitude <= attackRange and farmEnabled and not destroyed and gameSpecificAttackMethod then
        gameSpecificAttackMethod(enemy)
    end
end

local function pressAbilityKey(keyCode)
    pcall(function()
        VirtualInputManager:SendKeyEvent(true, keyCode, false, game)
    end)
    task.delay(abilityHoldDuration, function()
        pcall(function()
            VirtualInputManager:SendKeyEvent(false, keyCode, false, game)
        end)
    end)
end

local function useAutoAbilities()
    if not autoQEnabled and not autoEEnabled then return end
    local now = os.clock()
    if autoQEnabled and now - lastQTime >= abilityInterval then
        lastQTime = now
        pressAbilityKey(Enum.KeyCode.Q)
    end
    if autoEEnabled and now - lastETime >= abilityInterval then
        lastETime = now
        pressAbilityKey(Enum.KeyCode.E)
    end
end

-- Heavy Debug Enhanced Map-Wide Enemy Scanner
function findNearestEnemy_MapWide()
    local character = LocalPlayer.Character
    local playerRoot = character and character:FindFirstChild("HumanoidRootPart")
    if not playerRoot then 
        heavyDebug("Scanner", "Scan skipped: LocalPlayer HumanoidRootPart missing.")
        return nil, 0 
    end

    local nearestEnemy = nil
    local nearestDistance = math.huge
    local enemyCount = 0
    local seenModels = {}

    local function evaluateEntity(model, healthValue, sourceTag)
        if not model or not model:IsA("Model") or model == character or seenModels[model] then 
            return 
        end
        if Players:GetPlayerFromCharacter(model) then 
            return 
        end

        local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
        if not root then return end

        local humanoid = model:FindFirstChildWhichIsA("Humanoid")
        if humanoid and humanoid.Health <= 0 then return end
        if healthValue and healthValue <= 0 then return end

        seenModels[model] = true
        enemyCount = enemyCount + 1
        local distance = (playerRoot.Position - root.Position).Magnitude
        heavyDebug("Scanner", string.format("Found valid entity via [%s]: %s | Distance: %.1f | HP: %s", sourceTag, model.Name, distance, tostring(healthValue or (humanoid and humanoid.Health))))
        
        if distance < nearestDistance then
            nearestDistance = distance
            nearestEnemy = model
        end
    end

    -- Pass 1: Direct Humanoid model check
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj:IsA("Model") and not seenModels[obj] then
            local humanoid = obj:FindFirstChildWhichIsA("Humanoid")
            if humanoid and humanoid.Health > 0 and not Players:GetPlayerFromCharacter(obj) then
                if obj ~= character and not obj:IsDescendantOf(character) then
                    evaluateEntity(obj, humanoid.Health, "HumanoidDirect")
                end
            end
        end
    end

    -- Pass 2: BillboardGui Health Tag check
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj:IsA("BillboardGui") then
            local containerModel = obj.Parent and obj.Parent:FindFirstAncestorOfClass("Model") or obj.Parent
            if containerModel and containerModel:IsA("Model") and not seenModels[containerModel] then
                for _, desc in ipairs(obj:GetDescendants()) do
                    if desc:IsA("TextLabel") then
                        local txt = desc.Text
                        local currentHp = tonumber(txt:match("([%d,]+)%s*/")) or tonumber(txt:match("^([%d,]+)"))
                        if currentHp then
                            evaluateEntity(containerModel, currentHp, "BillboardTag")
                        end
                    end
                end
            end
        end
    end

    heavyDebug("Scanner", string.format("Scan completed. Total unique enemies counted: %d. Nearest target: %s", enemyCount, tostring(nearestEnemy and nearestEnemy.Name or "None")))
    return nearestEnemy, enemyCount
end

function detectGameAndInitialize()
    pcall(hookAttackRemotes)

    gameSpecificAttackMethod = function(enemy)
        local now = os.clock()
        if now - lastClickTime < clickInterval then return end

        local character = LocalPlayer.Character
        local root = character and character:FindFirstChild("HumanoidRootPart")
        local enemyRoot = enemy and enemy:FindFirstChild("HumanoidRootPart")
        if not root or not enemyRoot then return end

        root.CFrame = CFrame.new(root.Position, Vector3.new(enemyRoot.Position.X, root.Position.Y, enemyRoot.Position.Z))

        if detectedAttackRemote and detectedAttackRemote.Parent then
            pcall(function()
                detectedAttackRemote:FireServer(enemyRoot.Position, enemy)
            end)
        else
            local mousePosition = UserInputService:GetMouseLocation()
            pcall(function()
                VirtualInputManager:SendMouseButtonEvent(mousePosition.X, mousePosition.Y, 0, true, game, 0)
            end)
            task.delay(clickHoldDuration, function()
                pcall(function()
                    VirtualInputManager:SendMouseButtonEvent(mousePosition.X, mousePosition.Y, 0, false, game, 0)
                end)
            end)
        end

        lastClickTime = now
    end
end

local function addCorner(instance, radius)
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, radius)
    corner.Parent = instance
end

local function setLoopButtonState()
    if not toggleButton or not statusLabel then return end
    if farmEnabled then
        toggleButton.Text = "Loop: ON"
        toggleButton.BackgroundColor3 = Color3.fromRGB(52, 168, 83)
        statusLabel.Text = "Status: Running"
        statusLabel.TextColor3 = Color3.fromRGB(111, 232, 143)
    else
        toggleButton.Text = "Loop: OFF"
        toggleButton.BackgroundColor3 = Color3.fromRGB(180, 64, 64)
        statusLabel.Text = "Status: Paused"
        statusLabel.TextColor3 = Color3.fromRGB(255, 145, 145)
    end
end

local function setAbilityButtonState(button, keyName, enabled)
    if not button then return end
    button.Text = "Auto " .. keyName .. ": " .. (enabled and "ON" or "OFF")
    button.BackgroundColor3 = enabled and Color3.fromRGB(52, 168, 83) or Color3.fromRGB(180, 64, 64)
end

local function updateEnemyDisplay(enemy, enemyCount)
    if not enemyCountLabel or not closestEnemyLabel or not enemyHealthLabel then return end
    enemyCountLabel.Text = "Enemies detected (Map): " .. tostring(enemyCount or 0)
    if not enemy then
        closestEnemyLabel.Text = "Closest enemy: None"
        enemyHealthLabel.Text = "HP: --"
        return
    end

    local humanoid = enemy:FindFirstChildWhichIsA("Humanoid")
    closestEnemyLabel.Text = "Target: " .. enemy.Name
    if humanoid then
        enemyHealthLabel.Text = string.format("HP: %.0f / %.0f", humanoid.Health, humanoid.MaxHealth)
    else
        enemyHealthLabel.Text = "HP: (Billboard Tracked)"
    end
end

local function stopCharacterMovement()
    local character = LocalPlayer.Character
    local humanoid = character and character:FindFirstChildWhichIsA("Humanoid")
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if humanoid and root then
        humanoid:MoveTo(root.Position)
    end
end

local function destructScript()
    if destroyed then return end
    destroyed = true
    farmEnabled = false
    renderPathEnabled = false
    renderHazardsEnabled = false
    renderHitboxEnabled = false
    resetPursuitPath()
    clearHazardHighlights()
    clearHitboxVisualizer()
    clearHoverHighlight()
    stopCharacterMovement()

    if mainConnection then
        mainConnection:Disconnect()
        mainConnection = nil
    end

    if enemyScanConnection then
        enemyScanConnection:Disconnect()
        enemyScanConnection = nil
    end

    if childAddedConnection then
        childAddedConnection:Disconnect()
        childAddedConnection = nil
    end

    for _, connection in ipairs(sliderConnections) do
        connection:Disconnect()
    end
    table.clear(sliderConnections)

    if scriptGui then
        scriptGui:Destroy()
        scriptGui = nil
    end

    if _G.DungeonAutofarmDestruct == destructScript then
        _G.DungeonAutofarmDestruct = nil
    end
end

_G.DungeonAutofarmDestruct = destructScript

local function createControlUI()
    local playerGui = LocalPlayer:WaitForChild("PlayerGui")
    local oldGui = playerGui:FindFirstChild("DungeonAutofarmUI")
    if oldGui then oldGui:Destroy() end

    scriptGui = Instance.new("ScreenGui")
    scriptGui.Name = "DungeonAutofarmUI"
    scriptGui.ResetOnSpawn = false
    scriptGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    scriptGui.Parent = playerGui

    -- Main Control Window
    local mainFrame = Instance.new("Frame")
    mainFrame.Name = "Main"
    mainFrame.Size = UDim2.fromOffset(300, 670)
    mainFrame.Position = UDim2.new(1, -320, 0, 20)
    mainFrame.BackgroundColor3 = Color3.fromRGB(25, 27, 34)
    mainFrame.BorderSizePixel = 0
    mainFrame.Active = true
    mainFrame.Parent = scriptGui
    addCorner(mainFrame, 10)

    -- Draggable Header Logic
    local function makeDraggable(topHandle, targetFrame)
        local dragging = false
        local dragStart, startPos
        topHandle.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragging = true
                dragStart = input.Position
                startPos = targetFrame.Position
            end
        end)
        table.insert(sliderConnections, UserInputService.InputChanged:Connect(function(input)
            if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
                local delta = input.Position - dragStart
                targetFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
            end
        end))
        table.insert(sliderConnections, UserInputService.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragging = false
            end
        end))
    end

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -24, 0, 34)
    title.Position = UDim2.fromOffset(12, 8)
    title.BackgroundTransparency = 1
    title.Font = Enum.Font.GothamBold
    title.Text = "Dungeon Autofarm"
    title.TextColor3 = Color3.fromRGB(245, 245, 250)
    title.TextSize = 18
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = mainFrame
    makeDraggable(title, mainFrame)

    -- Active Telegraph Inspector Window
    local telegraphFrame = Instance.new("Frame")
    telegraphFrame.Name = "TelegraphInspector"
    telegraphFrame.Size = UDim2.fromOffset(260, 280)
    telegraphFrame.Position = UDim2.new(1, -590, 0, 20)
    telegraphFrame.BackgroundColor3 = Color3.fromRGB(25, 27, 34)
    telegraphFrame.BorderSizePixel = 0
    telegraphFrame.Active = true
    telegraphFrame.Parent = scriptGui
    addCorner(telegraphFrame, 10)

    local telegraphTitle = Instance.new("TextLabel")
    telegraphTitle.Size = UDim2.new(1, -24, 0, 32)
    telegraphTitle.Position = UDim2.fromOffset(12, 6)
    telegraphTitle.BackgroundTransparency = 1
    telegraphTitle.Font = Enum.Font.GothamBold
    telegraphTitle.Text = "Active Telegraphs Feed"
    telegraphTitle.TextColor3 = Color3.fromRGB(255, 105, 105)
    telegraphTitle.TextSize = 15
    telegraphTitle.TextXAlignment = Enum.TextXAlignment.Left
    telegraphTitle.Parent = telegraphFrame
    makeDraggable(telegraphTitle, telegraphFrame)

    local scrollContainer = Instance.new("ScrollingFrame")
    scrollContainer.Size = UDim2.new(1, -20, 1, -44)
    scrollContainer.Position = UDim2.fromOffset(10, 36)
    scrollContainer.BackgroundTransparency = 1
    scrollContainer.BorderSizePixel = 0
    scrollContainer.ScrollBarThickness = 4
    scrollContainer.ScrollBarImageColor3 = Color3.fromRGB(80, 85, 100)
    scrollContainer.CanvasSize = UDim2.new(0, 0, 0, 0)
    scrollContainer.AutomaticCanvasSize = Enum.AutomaticSize.Y
    scrollContainer.Parent = telegraphFrame

    local listLayout = Instance.new("UIListLayout")
    listLayout.Padding = UDim.new(0, 5)
    listLayout.SortOrder = Enum.SortOrder.LayoutOrder
    listLayout.Parent = scrollContainer

    telegraphFeedList = scrollContainer

    statusLabel = Instance.new("TextLabel")
    statusLabel.Size = UDim2.new(1, -24, 0, 24)
    statusLabel.Position = UDim2.fromOffset(12, 43)
    statusLabel.BackgroundTransparency = 1
    statusLabel.Font = Enum.Font.GothamMedium
    statusLabel.TextSize = 14
    statusLabel.TextXAlignment = Enum.TextXAlignment.Left
    statusLabel.Parent = mainFrame

    toggleButton = Instance.new("TextButton")
    toggleButton.Size = UDim2.new(1, -24, 0, 38)
    toggleButton.Position = UDim2.fromOffset(12, 72)
    toggleButton.BorderSizePixel = 0
    toggleButton.Font = Enum.Font.GothamBold
    toggleButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    toggleButton.TextSize = 15
    toggleButton.Parent = mainFrame
    addCorner(toggleButton, 7)

    local statsFrame = Instance.new("Frame")
    statsFrame.Size = UDim2.new(1, -24, 0, 105)
    statsFrame.Position = UDim2.fromOffset(12, 118)
    statsFrame.BackgroundColor3 = Color3.fromRGB(35, 38, 47)
    statsFrame.BorderSizePixel = 0
    statsFrame.Parent = mainFrame
    addCorner(statsFrame, 7)

    local function createStatLabel(y)
        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(1, -16, 0, 22)
        label.Position = UDim2.fromOffset(8, y)
        label.BackgroundTransparency = 1
        label.Font = Enum.Font.Gotham
        label.TextColor3 = Color3.fromRGB(220, 222, 230)
        label.TextSize = 13
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.TextTruncate = Enum.TextTruncate.AtEnd
        label.Parent = statsFrame
        return label
    end

    enemyCountLabel = createStatLabel(6)
    closestEnemyLabel = createStatLabel(29)
    enemyHealthLabel = createStatLabel(52)
    damageBrickCountLabel = createStatLabel(75)
    updateEnemyDisplay(nil, 0)

    local function createAbilityButton(x)
        local button = Instance.new("TextButton")
        button.Size = UDim2.fromOffset(132, 38)
        button.Position = UDim2.fromOffset(x, 231)
        button.BorderSizePixel = 0
        button.Font = Enum.Font.GothamBold
        button.TextColor3 = Color3.fromRGB(255, 255, 255)
        button.TextSize = 14
        button.Parent = mainFrame
        addCorner(button, 7)
        return button
    end

    qAbilityButton = createAbilityButton(12)
    eAbilityButton = createAbilityButton(156)

    local function createSlider(labelPrefix, y, minVal, maxVal, initialVal, isFloat, onChanged)
        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(1, -24, 0, 22)
        label.Position = UDim2.fromOffset(12, y)
        label.BackgroundTransparency = 1
        label.Font = Enum.Font.GothamMedium
        label.TextColor3 = Color3.fromRGB(220, 222, 230)
        label.TextSize = 13
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.Parent = mainFrame

        local track = Instance.new("Frame")
        track.Size = UDim2.new(1, -24, 0, 8)
        track.Position = UDim2.fromOffset(12, y + 26)
        track.BackgroundColor3 = Color3.fromRGB(66, 70, 82)
        track.BorderSizePixel = 0
        track.Active = true
        track.Parent = mainFrame
        addCorner(track, 4)

        local fill = Instance.new("Frame")
        fill.Size = UDim2.fromScale(0, 1)
        fill.BackgroundColor3 = Color3.fromRGB(78, 142, 232)
        fill.BorderSizePixel = 0
        fill.Parent = track
        addCorner(fill, 4)

        local knob = Instance.new("Frame")
        knob.Size = UDim2.fromOffset(16, 16)
        knob.AnchorPoint = Vector2.new(0.5, 0.5)
        knob.BackgroundColor3 = Color3.fromRGB(238, 240, 246)
        knob.BorderSizePixel = 0
        knob.Active = true
        knob.Parent = track
        addCorner(knob, 8)

        local dragging = false
        local function setFromAlpha(alpha)
            alpha = math.clamp(alpha, 0, 1)
            local value
            if isFloat then
                value = math.floor((minVal + ((maxVal - minVal) * alpha)) * 10 + 0.5) / 10
                label.Text = string.format("%s: %.1f", labelPrefix, value)
            else
                value = math.floor(minVal + ((maxVal - minVal) * alpha) + 0.5)
                label.Text = labelPrefix .. ": " .. tostring(value)
            end
            fill.Size = UDim2.fromScale(alpha, 1)
            knob.Position = UDim2.fromScale(alpha, 0.5)
            onChanged(value)
        end

        local function setFromX(x)
            if track.AbsoluteSize.X > 0 then
                setFromAlpha((x - track.AbsolutePosition.X) / track.AbsoluteSize.X)
            end
        end

        local function beginDrag(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragging = true
                setFromX(input.Position.X)
            end
        end

        track.InputBegan:Connect(beginDrag)
        knob.InputBegan:Connect(beginDrag)
        table.insert(sliderConnections, UserInputService.InputChanged:Connect(function(input)
            if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
                setFromX(input.Position.X)
            end
        end))
        table.insert(sliderConnections, UserInputService.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragging = false
            end
        end))

        setFromAlpha((initialVal - minVal) / (maxVal - minVal))
    end

    createSlider("Attack range", 275, minimumAttackRange, maximumAttackRange, attackRange, false, function(v) attackRange = v end)
    createSlider("Safe distance", 325, minimumSafeDistance, maximumSafeDistance, safeDistance, false, function(v) safeDistance = v end)
    createSlider("Wall padding clearance", 375, minimumWallPadding, maximumWallPadding, wallPadding, true, function(v) wallPadding = v end)
    createSlider("Telegraph buffer range", 425, minimumDamageBrickRange, maximumDamageBrickRange, damageBrickDetectionRange, false, function(v) damageBrickDetectionRange = v end)

    renderHazardsButton = Instance.new("TextButton")
    renderHazardsButton.Size = UDim2.new(1, -24, 0, 32)
    renderHazardsButton.Position = UDim2.fromOffset(12, 480)
    renderHazardsButton.BackgroundColor3 = Color3.fromRGB(52, 168, 83)
    renderHazardsButton.BorderSizePixel = 0
    renderHazardsButton.Font = Enum.Font.GothamBold
    renderHazardsButton.Text = "Highlight Telegraphs (Red): ON"
    renderHazardsButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    renderHazardsButton.TextSize = 13
    renderHazardsButton.Parent = mainFrame
    addCorner(renderHazardsButton, 7)

    renderPathButton = Instance.new("TextButton")
    renderPathButton.Size = UDim2.new(1, -24, 0, 32)
    renderPathButton.Position = UDim2.fromOffset(12, 518)
    renderPathButton.BackgroundColor3 = Color3.fromRGB(52, 168, 83)
    renderPathButton.BorderSizePixel = 0
    renderPathButton.Font = Enum.Font.GothamBold
    renderPathButton.Text = "Render path nodes: ON"
    renderPathButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    renderPathButton.TextSize = 13
    renderPathButton.Parent = mainFrame
    addCorner(renderPathButton, 7)

    renderHitboxButton = Instance.new("TextButton")
    renderHitboxButton.Size = UDim2.new(1, -24, 0, 32)
    renderHitboxButton.Position = UDim2.fromOffset(12, 556)
    renderHitboxButton.BackgroundColor3 = Color3.fromRGB(52, 168, 83)
    renderHitboxButton.BorderSizePixel = 0
    renderHitboxButton.Font = Enum.Font.GothamBold
    renderHitboxButton.Text = "Render Player Hitbox: ON"
    renderHitboxButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    renderHitboxButton.TextSize = 13
    renderHitboxButton.Parent = mainFrame
    addCorner(renderHitboxButton, 7)

    local destructButton = Instance.new("TextButton")
    destructButton.Size = UDim2.new(1, -24, 0, 32)
    destructButton.Position = UDim2.fromOffset(12, 594)
    destructButton.BackgroundColor3 = Color3.fromRGB(202, 55, 55)
    destructButton.BorderSizePixel = 0
    destructButton.Font = Enum.Font.GothamBold
    destructButton.Text = "Destruct"
    destructButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    destructButton.TextSize = 13
    destructButton.Parent = mainFrame
    addCorner(destructButton, 7)

    toggleButton.MouseButton1Click:Connect(function()
        if destroyed then return end
        farmEnabled = not farmEnabled
        setLoopButtonState()
        if not farmEnabled then
            resetPursuitPath()
            clearHitboxVisualizer()
            clearHoverHighlight()
            stopCharacterMovement()
            updateEnemyDisplay(nil, 0)
        end
    end)

    qAbilityButton.MouseButton1Click:Connect(function()
        autoQEnabled = not autoQEnabled
        setAbilityButtonState(qAbilityButton, "Q", autoQEnabled)
    end)

    eAbilityButton.MouseButton1Click:Connect(function()
        autoEEnabled = not autoEEnabled
        setAbilityButtonState(eAbilityButton, "E", autoEEnabled)
    end)

    renderHazardsButton.MouseButton1Click:Connect(function()
        renderHazardsEnabled = not renderHazardsEnabled
        renderHazardsButton.Text = "Highlight Telegraphs (Red): " .. (renderHazardsEnabled and "ON" or "OFF")
        renderHazardsButton.BackgroundColor3 = renderHazardsEnabled and Color3.fromRGB(52, 168, 83) or Color3.fromRGB(180, 64, 64)
        updateHazardHighlights()
    end)

    renderPathButton.MouseButton1Click:Connect(function()
        renderPathEnabled = not renderPathEnabled
        renderPathButton.Text = "Render path nodes: " .. (renderPathEnabled and "ON" or "OFF")
        renderPathButton.BackgroundColor3 = renderPathEnabled and Color3.fromRGB(52, 168, 83) or Color3.fromRGB(180, 64, 64)
        if renderPathEnabled then renderCurrentPath() else clearRenderedPath() end
    end)

    renderHitboxButton.MouseButton1Click:Connect(function()
        renderHitboxEnabled = not renderHitboxEnabled
        renderHitboxButton.Text = "Render Player Hitbox: " .. (renderHitboxEnabled and "ON" or "OFF")
        renderHitboxButton.BackgroundColor3 = renderHitboxEnabled and Color3.fromRGB(52, 168, 83) or Color3.fromRGB(180, 64, 64)
        if not renderHitboxEnabled then clearHitboxVisualizer() else updateHitboxVisualizer() end
    end)

    destructButton.MouseButton1Click:Connect(destructScript)

    setLoopButtonState()
    setAbilityButtonState(qAbilityButton, "Q", autoQEnabled)
    setAbilityButtonState(eAbilityButton, "E", autoEEnabled)
end

function startAutofarm()
    createControlUI()
    local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    local humanoid = character:WaitForChild("Humanoid")
    local root = character:WaitForChild("HumanoidRootPart")

    watchForNewHazards()
    detectGameAndInitialize()

    LocalPlayer.CharacterAdded:Connect(function(newChar)
        character = newChar
        humanoid = newChar:WaitForChild("Humanoid")
        root = newChar:WaitForChild("HumanoidRootPart")
        watchForNewHazards()
    end)

    -- Dedicated Throttled Enemy Scanning Loop
    local lastScanClock = 0
    enemyScanConnection = RunService.Heartbeat:Connect(function()
        if destroyed or not farmEnabled then return end
        local now = os.clock()
        if now - lastScanClock >= enemyScanInterval then
            lastScanClock = now
            pcall(function()
                cachedEnemy, cachedEnemyCount = findNearestEnemy_MapWide()
                updateEnemyDisplay(cachedEnemy, cachedEnemyCount)
            end)
        end
    end)

    -- Unconditional Main Combat Loop
    mainConnection = RunService.Heartbeat:Connect(function()
        if destroyed or not farmEnabled then return end

        pcall(function()
            if not humanoid or humanoid.Health <= 0 then
                cachedEnemy = nil
                resetPursuitPath()
                clearHitboxVisualizer()
                clearHoverHighlight()
                updateEnemyDisplay(nil, 0)
                return
            end

            scanDamageBricks(root.Position)
            updateHitboxVisualizer()
            useAutoAbilities()

            local inHazard = not isPositionSafeFromDamageBricks(root.Position, 0.5)

            if inHazard then
                local escapeTarget = findStagingSafePoint(root.Position, cachedEnemy and cachedEnemy:GetPivot().Position or root.Position, cachedEnemy)
                if escapeTarget then
                    humanoid:MoveTo(escapeTarget)
                else
                    local repulsion = getActiveHazardRepulsionVector(root.Position)
                    local fallbackDir = repulsion.Magnitude > 0.1 and repulsion.Unit or Vector3.new(0, 0, 1)
                    humanoid:MoveTo(root.Position + (fallbackDir * 10))
                end
            elseif cachedEnemy then
                attackEnemy(cachedEnemy)
            else
                if currentPathEnemy then
                    resetPursuitPath()
                    stopCharacterMovement()
                end
            end
        end)
    end)
end

startAutofarm()
