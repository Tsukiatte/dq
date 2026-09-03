-- mover.lua - The one thing that moves the character. A tween along the
-- floor: every frame the root is stepped toward the target at walking speed,
-- kept at floor height from a downward raycast, stopped by a wall raycast at
-- chest height. Never faster than CFG.moveSpeed, never airborne, never a
-- state the client anticheat objects to. Or, in walk mode, Humanoid:MoveTo.
return function(S)
local CFG = S.CFG
local RT = S.RT
local Workspace = S.Workspace
local LocalPlayer = S.LocalPlayer

local V3 = Vector3.new
local MV = { target = nil, speed = 16, owner = "", face = nil, blocked = false, arrived = false,
             lastMoveTo = nil, walkForced = false, driving = false }

local rayParams
local function params()
    if not rayParams then
        rayParams = RaycastParams.new()
        rayParams.FilterType = Enum.RaycastFilterType.Exclude
        pcall(function() rayParams.RespectCanCollide = true end)
    end
    local excl = {}
    local char = LocalPlayer.Character
    if char then excl[#excl + 1] = char end
    if RT.visualRoot then excl[#excl + 1] = RT.visualRoot end
    rayParams.FilterDescendantsInstances = excl
    return rayParams
end

-- Floor height under (x, z) searched from y + 3 down to y - 12; nil = no floor.
local function floorAt(x, y, z)
    local r = Workspace:Raycast(V3(x, y + 3, z), V3(0, -15, 0), params())
    if r then return r.Position.Y end
    return nil
end

-- A solid between two points at knee and chest height. Steps count as floor.
local function wallBetween(from, to)
    local dir = to - from
    local flat = V3(dir.X, 0, dir.Z)
    if flat.Magnitude < 0.05 then return false end
    for _, h in ipairs({ 1.2, 2.6 }) do
        local r = Workspace:Raycast(from + V3(0, h, 0), flat, params())
        if r and r.Instance then
            -- A low, walkable-topped edge is a step, not a wall.
            if not (h == 1.2 and r.Normal.Y > 0.5) then return true, r end
        end
    end
    return false
end

local function moverStop()
    if MV.target == nil and not MV.driving then return end
    MV.target = nil
    MV.driving = false
    MV.lastMoveTo = nil
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if hum and root then
        pcall(function() hum:MoveTo(root.Position) end)
        hum.AutoRotate = true
    end
end

-- Ask to be at `point`, moving at `speed`, facing `face` (a position) or the
-- way we go. `owner` is a label for the HUD. Called every decision; cheap.
local function moveTo(point, speed, owner, face, forceWalk)
    MV.target = point
    MV.speed = speed or CFG.moveSpeed
    MV.owner = owner or ""
    MV.face = face
    MV.walkForced = forceWalk == true
    MV.arrived = false
end

-- Turn the root toward a position without moving it (standing and casting).
local function faceToward(root, hum, target)
    if not root or not target then return end
    local p = root.Position
    local look = V3(target.X - p.X, 0, target.Z - p.Z)
    if look.Magnitude < 0.5 then return end
    hum.AutoRotate = false
    root.CFrame = CFrame.lookAt(p, p + look.Unit)
end

-- One frame of movement. Returns true while driving.
local function moverStep(dt)
    local char = LocalPlayer.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not root or not hum or not MV.target then return false end
    local pos = root.Position
    local target = MV.target
    local dx, dz = target.X - pos.X, target.Z - pos.Z
    local dist = math.sqrt(dx * dx + dz * dz)
    if dist <= CFG.moveArriveRadius then
        MV.arrived = true
        if MV.driving and CFG.moveMode ~= "tween" then pcall(function() hum:MoveTo(pos) end) end
        MV.driving = false
        return false
    end
    MV.driving = true
    if CFG.moveMode ~= "tween" or MV.walkForced then
        hum.AutoRotate = true
        if not MV.lastMoveTo or (MV.lastMoveTo - target).Magnitude > 1 then
            MV.lastMoveTo = target
            pcall(function() hum:MoveTo(target) end)
        end
        return true
    end
    local step = math.min(dist, MV.speed * dt)
    local nx, nz = pos.X + dx / dist * step, pos.Z + dz / dist * step
    local fy = floorAt(nx, pos.Y, nz)
    if not fy then MV.blocked = true return true end
    local ny = fy + hum.HipHeight + root.Size.Y * 0.5
    local rise = ny - pos.Y
    if rise > CFG.maxStepHeight + 0.5 or -rise > CFG.dodgeMaxDrop then MV.blocked = true return true end
    local next = V3(nx, ny, nz)
    if wallBetween(pos, next) then MV.blocked = true return true end
    MV.blocked = false
    local look
    if MV.face then look = V3(MV.face.X - nx, 0, MV.face.Z - nz) else look = V3(dx, 0, dz) end
    hum.AutoRotate = false
    if look.Magnitude > 0.1 then
        root.CFrame = CFrame.lookAt(next, next + look.Unit)
    else
        root.CFrame = CFrame.new(next) * (root.CFrame - root.CFrame.Position)
    end
    root.AssemblyLinearVelocity = V3(0, 0, 0)
    return true
end

S.MV = MV
S.moveTo = moveTo
S.moverStop = moverStop
S.moverStep = moverStep
S.faceToward = faceToward
S.floorAt = floorAt
S.wallBetween = wallBetween
end
