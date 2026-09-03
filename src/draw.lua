-- draw.lua - Everything drawn in the world and the live feed. Only what can
-- hurt is drawn: red for an attack whose window is open, amber for one that
-- opens within a second. The dodge's candidates, its target and its search
-- ring; the character's own hitbox and ability radius; the route.
return function(S)
local CFG = S.CFG
local RT = S.RT
local UI = S.UI
local HZ = S.HZ
local DG = S.DG
local NAV = S.NAV
local K = S.UIKit
local LocalPlayer = S.LocalPlayer
local getVisualRoot = S.getVisualRoot
local attackWindow = S.attackWindow

local V3 = Vector3.new
local clock = os.clock
local folder
local function root()
    if folder and folder.Parent then return folder end
    folder = Instance.new("Folder")
    folder.Name = "Overlays"
    folder.Parent = getVisualRoot()
    return folder
end

-- A pool of anchored, non-colliding parts reused frame to frame.
local function makePool(name, shape)
    local pool = { parts = {}, used = 0, name = name, shape = shape }
    function pool.take()
        pool.used = pool.used + 1
        local part = pool.parts[pool.used]
        if not part or not part.Parent then
            part = Instance.new("Part")
            part.Name = name
            part.Anchored = true
            part.CanCollide = false
            part.CanQuery = false
            part.CanTouch = false
            part.CastShadow = false
            part.Material = Enum.Material.Neon
            if shape then part.Shape = shape end
            part.Parent = root()
            pool.parts[pool.used] = part
        end
        return part
    end
    function pool.reset() pool.used = 0 end
    function pool.hide()
        for i = pool.used + 1, #pool.parts do
            local part = pool.parts[i]
            if part.Parent and part.Transparency < 1 then part.Transparency = 1 end
        end
    end
    function pool.clear()
        for _, part in ipairs(pool.parts) do if part.Parent then part:Destroy() end end
        pool.parts = {}
        pool.used = 0
    end
    return pool
end
local hazardBoxes = makePool("Hazard")
local hazardDiscs = makePool("HazardDisc", Enum.PartType.Cylinder)
local candDiscs = makePool("Candidate", Enum.PartType.Cylinder)
local misc = makePool("Overlay")
local routeOrbs = makePool("Route", Enum.PartType.Ball)

-- ------------------------------------------------------------------ hazards
local function clearHazardHighlights()
    hazardBoxes.clear()
    hazardDiscs.clear()
end
local function updateHazardHighlights()
    hazardBoxes.reset()
    hazardDiscs.reset()
    if RT.renderHazardsEnabled and CFG.showPrecast and not RT.destroyed then
        local now = clock()
        local shown = 0
        for _, rec in ipairs(HZ.detected) do
            if shown >= CFG.maxHazardOverlays then break end
            local open, close = attackWindow(rec)
            if open then
                local live = now >= open and now <= close
                local colour = live and CFG.colorTelegraph or CFG.colorTelegraphPending
                local ok = pcall(function()
                    if rec.kind == "part" then
                        local part = hazardDiscs.take()
                        local p = rec.inst.Position
                        part.Size = V3(0.6, rec.radius * 2, rec.radius * 2)
                        part.CFrame = CFrame.new(p.X, p.Y, p.Z) * CFrame.Angles(0, 0, math.rad(90))
                        part.Color = colour
                        part.Transparency = 0.55
                    elseif rec.shape == "disc" then
                        local part = hazardDiscs.take()
                        local c = rec.center or rec.part.Position
                        part.Size = V3(0.6, rec.radius * 2, rec.radius * 2)
                        part.CFrame = CFrame.new(c.X, c.Y, c.Z) * CFrame.Angles(0, 0, math.rad(90))
                        part.Color = colour
                        part.Transparency = 0.55
                    else
                        local part = hazardBoxes.take()
                        local cf = rec.cframe or rec.part.CFrame
                        local size = rec.size or rec.part.Size
                        part.Size = V3(size.X, 0.6, size.Z)
                        part.CFrame = cf - V3(0, size.Y * 0.5 - 0.5, 0)
                        part.Color = colour
                        part.Transparency = live and 0.45 or 0.7
                    end
                end)
                if ok then shown = shown + 1 end
            end
        end
    end
    hazardBoxes.hide()
    hazardDiscs.hide()
end

-- ------------------------------------------------------------------ the dodge
local function updateDodgeVisuals()
    candDiscs.reset()
    misc.reset()
    if DG.active and not RT.destroyed and RT.farmEnabled then
        local char = LocalPlayer.Character
        local rootPart = char and char:FindFirstChild("HumanoidRootPart")
        if rootPart then
            local y = rootPart.Position.Y - 2.5
            if CFG.dodgeShowField then
                for i, c in ipairs(DG.cands) do
                    if i > 72 then break end
                    local part = candDiscs.take()
                    part.Size = V3(0.3, 1.2, 1.2)
                    part.CFrame = CFrame.new(c.x, y, c.z) * CFrame.Angles(0, 0, math.rad(90))
                    local d = math.max(0, math.min(1, c.danger))
                    part.Color = CFG.colorDodgeSafe:Lerp(CFG.colorDodgeDanger, d)
                    part.Transparency = c.valid == false and 0.85 or 0.4
                end
            end
            if CFG.dodgeShowRange then
                local ring = misc.take()
                ring.Shape = Enum.PartType.Cylinder
                ring.Size = V3(0.2, CFG.dodgeReach * 2, CFG.dodgeReach * 2)
                ring.CFrame = CFrame.new(rootPart.Position.X, y - 0.2, rootPart.Position.Z) * CFrame.Angles(0, 0, math.rad(90))
                ring.Color = CFG.colorDodgeTarget
                ring.Transparency = 0.92
            end
            if CFG.dodgeShowTarget and DG.target then
                local box = misc.take()
                box.Shape = Enum.PartType.Block
                box.Size = V3(2.5, 3.5, 2.5)
                box.CFrame = CFrame.new(DG.target)
                box.Color = CFG.colorDodgeTarget
                box.Transparency = 0.6
            end
            if CFG.showEscapeRoute and DG.target then
                local line = misc.take()
                line.Shape = Enum.PartType.Block
                local a, b = rootPart.Position, DG.target
                local len = (b - a).Magnitude
                if len > 0.5 then
                    line.Size = V3(0.3, 0.3, len)
                    line.CFrame = CFrame.lookAt((a + b) * 0.5, b)
                    line.Color = CFG.colorEscape
                    line.Transparency = 0.3
                end
            end
        end
    end
    candDiscs.hide()
    misc.hide()
end

-- ------------------------------------------------------------------ the route
local function clearRenderedPath() routeOrbs.clear() end
local function renderCurrentPath()
    routeOrbs.reset()
    if RT.renderPathEnabled and NAV.route and NAV.route.waypoints and not RT.destroyed then
        local wps = NAV.route.waypoints
        for i = NAV.route.index or 1, #wps do
            if routeOrbs.used >= 24 then break end
            local orb = routeOrbs.take()
            orb.Size = V3(0.8, 0.8, 0.8)
            orb.CFrame = CFrame.new(wps[i].Position + V3(0, 0.5, 0))
            orb.Color = CFG.colorPursuit
            orb.Transparency = 0.3
        end
    end
    routeOrbs.hide()
end

-- ------------------------------------------------------------------ own hitbox
local adornFolder
local function clearHitboxVisualizer()
    if adornFolder then adornFolder:Destroy() adornFolder = nil end
end
local function updateHitboxVisualizer()
    local wantHitbox = RT.renderHitboxEnabled and RT.farmEnabled
    local wantRadius = CFG.showAbilityRadius
    local char = LocalPlayer.Character
    local rootPart = char and char:FindFirstChild("HumanoidRootPart")
    if not rootPart or (not wantHitbox and not wantRadius) or RT.destroyed then
        clearHitboxVisualizer()
        return
    end
    if not adornFolder or not adornFolder.Parent then
        adornFolder = Instance.new("Folder")
        adornFolder.Name = "PlayerAdornments"
        adornFolder.Parent = getVisualRoot()
    end
    local box = adornFolder:FindFirstChild("HitboxSolidBox")
    if wantHitbox then
        if not box then
            box = Instance.new("SelectionBox")
            box.Name = "HitboxSolidBox"
            box.LineThickness = 0.03
            box.SurfaceTransparency = 0.8
            box.Parent = adornFolder
        end
        box.Color3 = CFG.colorHitbox
        box.SurfaceColor3 = CFG.colorHitbox
        if box.Adornee ~= rootPart then box.Adornee = rootPart end
    elseif box then
        box:Destroy()
    end
    local sphere = adornFolder:FindFirstChild("AbilityRadius")
    if wantRadius then
        if not sphere then
            sphere = Instance.new("SphereHandleAdornment")
            sphere.Name = "AbilityRadius"
            sphere.Transparency = 0.82
            sphere.AlwaysOnTop = false
            sphere.Parent = adornFolder
        end
        sphere.Color3 = CFG.colorAbilityRadius
        if sphere.Adornee ~= rootPart then sphere.Adornee = rootPart end
        if sphere.Radius ~= CFG.abilityRadius then sphere.Radius = CFG.abilityRadius end
    elseif sphere then
        sphere:Destroy()
    end
end

-- ------------------------------------------------------------------ the feed
local function updateFeed()
    local list = UI.telegraphFeedList
    if not list or not list.Parent then return end
    if UI.damageBrickCountLabel then UI.damageBrickCountLabel.Text = "Telegraphs Active: " .. #HZ.detected end
    for _, child in ipairs(list:GetChildren()) do
        if child:IsA("GuiObject") then child:Destroy() end
    end
    local now = clock()
    for i, rec in ipairs(HZ.detected) do
        if i > 16 then break end
        local open, close = attackWindow(rec)
        local state = "coming"
        if open and now >= open and now <= close then state = "LIVE"
        elseif open then state = string.format("in %.1fs", open - now) end
        local text = string.format("%s  %s  age %.1f%s", rec.name, state, now - rec.spawn,
            rec.flashTime and string.format("  flash %.2f", rec.flashTime) or "")
        local label = K.label(list, text, "captionSub", i)
        label.Size = UDim2.new(1, 0, 0, 18)
        label.TextTruncate = Enum.TextTruncate.AtEnd
    end
end

-- ------------------------------------------------------------------ the step
local lastHazard, lastDodge, lastFeed = -math.huge, -math.huge, -math.huge
local function drawStep(now)
    if RT.destroyed then return end
    if now - lastHazard >= CFG.visualRefreshInterval then
        lastHazard = now
        pcall(updateHazardHighlights)
        pcall(updateHitboxVisualizer)
        pcall(renderCurrentPath)
    end
    if now - lastDodge >= 0.1 then
        lastDodge = now
        pcall(updateDodgeVisuals)
    end
    if now - lastFeed >= 0.5 then
        lastFeed = now
        pcall(updateFeed)
    end
end

local function clearAll()
    clearHazardHighlights()
    candDiscs.clear()
    misc.clear()
    routeOrbs.clear()
    clearHitboxVisualizer()
end

S.drawStep = drawStep
S.clearHazardHighlights = clearHazardHighlights
S.updateHazardHighlights = updateHazardHighlights
S.clearHitboxVisualizer = clearHitboxVisualizer
S.updateHitboxVisualizer = updateHitboxVisualizer
S.renderCurrentPath = renderCurrentPath
S.clearRenderedPath = clearRenderedPath
S.clearDrawings = clearAll
-- Names the UI imports from the old modules. Walls are not catalogued any
-- more; the escape route is the dodge line drawn with the box.
S.clearWallHighlights = function() end
S.updateWallHighlights = function() end
S.resetWallCatalog = function() end
S.renderEscapeRoute = function() end
S.clearEscapeRoute = function() end
S.clearEscapeNodes = function() end
S.destroyFacingRig = function() end
end
