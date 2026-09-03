-- draw.lua - One translucent box per hazard, coloured by stage, and the spot.
-- Module contract: receives the shared table S; imports from core, reader, field.
return function(S)
local CFG = S.CFG
local RT = S.RT
local DG = S.DG
local hazards = S.hazards
local getVisualRoot = S.getVisualRoot

local DR = { folder = nil, parts = {}, target = nil, lastDraw = -math.huge }

local function folder()
    if DR.folder and DR.folder.Parent then return DR.folder end
    local f = Instance.new("Folder")
    f.Name = "Hazards"
    f.Parent = getVisualRoot()
    DR.folder = f
    return f
end

local function newBox()
    local p = Instance.new("Part")
    p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
    p.Material = Enum.Material.Neon
    p.Transparency = CFG.hazardTransparency
    p.Parent = folder()
    return p
end

local function stageColor(b, now)
    if now >= b.from then return CFG.colorLive end
    local lead = b.moving and CFG.dodgePathLead or CFG.dodgeLead
    if b.from - now <= lead then return CFG.colorSoon end
    return CFG.colorFloor
end

local function drawTick(now)
    if now - DR.lastDraw < 0.1 then return end
    -- Our own drawing must never be the lag: only what is near, and not many.
    local lp = S.LocalPlayer.Character
    local rt = lp and lp:FindFirstChild("HumanoidRootPart")
    local rp = rt and rt.Position
    DR.lastDraw = now
    local used = {}
    if CFG.drawHazards then
        local list = hazards(now)
        local drawn = 0
        for i, b in ipairs(list) do
            local bx, bz
            if b.moving then bx, bz = b.ox, b.oz else bx, bz = b.cframe.Position.X, b.cframe.Position.Z end
            local near = not rp or ((bx - rp.X) ^ 2 + (bz - rp.Z) ^ 2) < 130 * 130
            if near and drawn < 60 then
            drawn = drawn + 1
            local key = i
            local p = DR.parts[key]
            if not p or not p.Parent then p = newBox() DR.parts[key] = p end
            used[key] = true
            if b.moving then
                -- The rectangle it sweeps over the window we look ahead.
                local len = b.speed * CFG.projectileLookahead + b.halfL * 2
                local along = b.offset + b.speed * math.max(now - b.pathStart, 0)
                local cx, cz = b.ox + b.dx * (along + len * 0.5 - b.halfL), b.oz + b.dz * (along + len * 0.5 - b.halfL)
                p.Size = Vector3.new(b.halfW * 2, 1, len)
                p.CFrame = CFrame.lookAt(Vector3.new(cx, b.oy - b.halfH + 0.6, cz), Vector3.new(cx + b.dx, b.oy - b.halfH + 0.6, cz + b.dz))
                p.Shape = Enum.PartType.Block
            elseif b.round then
                p.Shape = Enum.PartType.Cylinder
                p.Size = Vector3.new(0.6, b.size.X, b.size.X)
                p.CFrame = b.cframe * CFrame.Angles(0, 0, math.rad(90))
            elseif b.cyl then
                p.Shape = Enum.PartType.Cylinder
                p.Size = Vector3.new(b.size.X, b.size.Y, b.size.Z)
                p.CFrame = b.cframe
            else
                p.Shape = Enum.PartType.Block
                p.Size = Vector3.new(b.size.X, math.min(b.size.Y, 1.5), b.size.Z)
                p.CFrame = b.cframe - Vector3.new(0, b.size.Y * 0.5 - 0.8, 0)
            end
            local c = stageColor(b, now)
            if p.Color ~= c then p.Color = c end
            p.Transparency = CFG.hazardTransparency
            end
        end
    end
    for key, p in pairs(DR.parts) do
        if not used[key] then p:Destroy() DR.parts[key] = nil end
    end
    if CFG.drawTarget and DG.target then
        local t = DR.target
        if not t or not t.Parent then
            t = Instance.new("Part")
            t.Anchored, t.CanCollide, t.CanQuery, t.CanTouch = true, false, false, false
            t.Material = Enum.Material.Neon
            t.Color = CFG.colorTarget
            t.Transparency = 0.35
            t.Size = Vector3.new(2, 5, 2)
            t.Parent = folder()
            DR.target = t
        end
        t.CFrame = CFrame.new(DG.target + Vector3.new(0, 3, 0))
    elseif DR.target then
        DR.target:Destroy()
        DR.target = nil
    end
end

local function clearDrawing()
    if DR.folder then DR.folder:Destroy() end
    DR.folder, DR.target = nil, nil
    table.clear(DR.parts)
end

S.drawTick = drawTick
S.clearDrawing = clearDrawing
end
