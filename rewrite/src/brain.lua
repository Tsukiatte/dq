-- brain.lua - What to do this frame: dodge, fight, or travel.
-- Module contract: receives the shared table S; imports from core, reader,
-- field and mover.
--
-- Priority is fixed: the field's spot outranks everything; then fight the
-- target from its standoff, strafing round it; then travel to the next room.
return function(S)
local CFG = S.CFG
local RT = S.RT
local RD = S.RD
local DG = S.DG
local decide = S.decide
local dangerAt = S.dangerAt
local driveTo = S.driveTo
local faceToward = S.faceToward
local releaseMover = S.releaseMover
-- The speed a walk is planned at: the Humanoid's own, once the mover has read it.
local function walkSpeed() return RT.walkSpeed or CFG.tweenWalk end
local Workspace = S.Workspace
local LocalPlayer = S.LocalPlayer
local PathfindingService = S.PathfindingService
local VirtualInputManager = S.VirtualInputManager
local raycastParams = S.raycastParams
local floorY = S.floorY
local setMovementState = S.setMovementState
local heavyDebug = S.heavyDebug
local heavyDebugThrottled = S.heavyDebugThrottled

local BR = {
    target = nil,
    waypoints = nil, index = 1, pathAt = -math.huge, pathTo = nil,
    strafeDir = 1, strafeFlipAt = -math.huge,
    visitedRooms = {},
    roomBoxes = {},
    lastDecision = -math.huge,
}

local sqrt, abs, max, min = math.sqrt, math.abs, math.max, math.min

local function flat(a, b) local dx, dz = a.X - b.X, a.Z - b.Z return sqrt(dx * dx + dz * dz) end

local function standoffFor(e)
    if e.isBoss then return CFG.bossStandoff end
    return e.extent + CFG.mobStandoff
end

-- The room first: a boss three rooms away sits behind gates that open only
-- when this room is cleared, and pathing at it walked into a wall for good.
local function pickTarget(rp)
    local best, bestScore = nil, math.huge
    local boss, bossD = nil, math.huge
    for _, e in ipairs(RD.enemies) do
        if e.humanoid.Health > 0 and e.model.Parent then
            local d = flat(rp, e.root.Position)
            if e.isBoss then
                if d < bossD then boss, bossD = e, d end
            elseif d < 150 and d < bestScore then
                best, bestScore = e, d
            end
        end
    end
    if best then return best end
    if boss and bossD < 400 then return boss end
    return nil
end

-- ------------------------------------------------------------ travel
local function roomTargets()
    local out = {}
    local dungeon = Workspace:FindFirstChild("dungeon")
    if not dungeon then return out end
    for _, room in ipairs(dungeon:GetChildren()) do
        local order = room:FindFirstChild("order")
        local ord = order and type(order.Value) == "number" and order.Value or (room.Name == "bossRoom" and 99 or nil)
        if ord then
            local anchor
            local ef = room:FindFirstChild("enemyFolder")
            if ef then
                for _, s in ipairs(ef:GetChildren()) do
                    if s:IsA("BasePart") then anchor = s.Position break end
                    if s:IsA("Model") and s.PrimaryPart then anchor = s.PrimaryPart.Position break end
                end
            end
            if not anchor then
                local p = room:FindFirstChildWhichIsA("BasePart", true)
                anchor = p and p.Position
            end
            if anchor then
                -- The room's footprint, measured once: standing inside it is what
                -- 'reached' means. Anchors can sit far from the path walked.
                local box = BR.roomBoxes[room]
                if box == nil then
                    local ok, cf, size = pcall(function() return room:GetBoundingBox() end)
                    box = ok and { cf = cf, size = size } or false
                    BR.roomBoxes[room] = box
                end
                out[#out + 1] = { order = ord, position = anchor, name = room.Name, box = box or nil }
            end
        end
    end
    table.sort(out, function(a, b) return a.order < b.order end)
    return out
end

-- The next room is the first one past the furthest we have stood in. A room
-- whose anchor we never came within 25 studs of (its mobs died from range) is
-- behind us all the same; 5.1.9 walked back to room 2 after the Champion.
local function nextRoom(rp)
    local rooms = roomTargets()
    for _, r in ipairs(rooms) do
        local inside = false
        if r.box then
            local lp = r.box.cf:PointToObjectSpace(rp)
            inside = abs(lp.X) <= r.box.size.X * 0.5 + 4 and abs(lp.Z) <= r.box.size.Z * 0.5 + 4
        end
        if (inside or flat(rp, r.position) < 25) and r.order > (BR.reachedOrder or 0) then BR.reachedOrder = r.order end
    end
    for _, r in ipairs(rooms) do
        if r.order > (BR.reachedOrder or 0) then return r end
    end
    return nil
end

local function computePath(from, to)
    local path = PathfindingService:CreatePath({ AgentRadius = 2.5, AgentHeight = 5, AgentCanJump = true, WaypointSpacing = 4 })
    local ok = pcall(function() path:ComputeAsync(from, to) end)
    if ok and path.Status == Enum.PathStatus.Success then
        local wps = {}
        for _, w in ipairs(path:GetWaypoints()) do wps[#wps + 1] = w.Position end
        if #wps >= 2 then return wps end
    end
    -- Straight line, in steps, when the navmesh has no answer.
    local wps = {}
    local d = flat(from, to)
    local n = max(1, min(24, math.floor(d / 8)))
    for i = 1, n do wps[#wps + 1] = from:Lerp(to, i / n) end
    return wps
end

-- Is the straight line to `to` walkable? A slab the character's size swept
-- along it, against everything solid.
local function lineClear(rp, to, exclude)
    local params = raycastParams(exclude)
    local from = rp
    local dest = Vector3.new(to.X, rp.Y, to.Z)
    local hit = Workspace:Blockcast(CFrame.new(from), Vector3.new(2.5, 4.5, 2.5), dest - from, params)
    return hit == nil
end

-- Walk toward `to`. A moving target must not mean a new plan every frame: the
-- Champion walks, and replanning from scratch each half second reset the
-- index to the waypoint under the character, which shuffled on the spot for
-- a whole fight. Straight when the line is clear; otherwise a path, replanned
-- rarely, resumed past the waypoints already behind.
local function travel(hum, root, to, speed, label, exclude)
    local rp = root.Position
    local now = os.clock()
    if flat(rp, to) < 70 and lineClear(rp, to, exclude) then
        BR.waypoints = nil
        driveTo(hum, root, to, speed, 1.5)
        setMovementState(label .. " straight")
        return
    end
    if not BR.waypoints or not BR.pathTo or flat(BR.pathTo, to) > 20 or now - BR.pathAt > 4 or BR.index > #BR.waypoints then
        BR.waypoints = computePath(rp, to)
        BR.pathAt = now
        BR.pathTo = to
        -- Resume past whatever is already behind us.
        BR.index = 1
        for i, w in ipairs(BR.waypoints) do
            local dx, dz = w.X - rp.X, w.Z - rp.Z
            local nx, nz = to.X - rp.X, to.Z - rp.Z
            if dx * nx + dz * nz > 0 and flat(rp, w) > 2.5 then BR.index = i break end
        end
    end
    local wp = BR.waypoints[BR.index]
    while wp and flat(rp, wp) < 3 and BR.index < #BR.waypoints do
        BR.index = BR.index + 1
        wp = BR.waypoints[BR.index]
    end
    if not wp then return end
    -- No progress for a while: the way is shut (a gate, a wall the navmesh
    -- did not know). Replan, and after that skip the waypoint.
    if not BR.progressAt or flat(rp, BR.progressPos or rp) > 1.5 then BR.progressAt, BR.progressPos = now, rp end
    if now - BR.progressAt > 2.5 then
        BR.progressAt = now
        if BR.index < #BR.waypoints then BR.index = BR.index + 1 else BR.waypoints = nil end
        heavyDebugThrottled("stall", 2, "Brain", "no progress; skipping a waypoint")
        return
    end
    driveTo(hum, root, wp, speed, 1.5)
    setMovementState(string.format("%s %d/%d", label, BR.index, #BR.waypoints))
end

-- ------------------------------------------------------------ fighting
local function pressKey(key)
    pcall(function() VirtualInputManager:SendKeyEvent(true, key, false, game) end)
    task.delay(0.05, function() pcall(function() VirtualInputManager:SendKeyEvent(false, key, false, game) end) end)
end

local function fight(hum, root, e, now)
    local ep = e.root.Position
    local d = flat(root.Position, ep)
    faceToward(root, hum, ep)
    if d <= CFG.abilityRadius then
        if CFG.autoQ and now - RT.lastQ >= CFG.abilityInterval then RT.lastQ = now pressKey(Enum.KeyCode.Q) end
        if CFG.autoE and now - RT.lastE >= CFG.abilityInterval then RT.lastE = now pressKey(Enum.KeyCode.E) end
    end
    if CFG.autoAttack and d <= CFG.attackRange + e.extent and now - RT.lastClick >= CFG.clickInterval then
        RT.lastClick = now
        local tool = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Tool")
        if tool then pcall(function() tool:Activate() end) end
    end
end

-- A point a few studs along the tangent round the target, flipped when the
-- way ahead is dangerous or blocked or every few seconds for variety.
local function strafePoint(root, e, standoff, now)
    local rp = root.Position
    local ep = e.root.Position
    local rx, rz = rp.X - ep.X, rp.Z - ep.Z
    local d = sqrt(rx * rx + rz * rz)
    if d < 0.5 then return nil end
    local ux, uz = rx / d, rz / d
    local tx, tz = -uz * BR.strafeDir, ux * BR.strafeDir
    local stepLen = 6
    -- Pull toward the band as we go round; a melee mob inside the band is
    -- backed away from, not circled.
    local radial = standoff - d
    local clampR = e.melee and 8 or 4
    if e.melee and radial > 2 then stepLen = 2 end
    local px, pz = rp.X + tx * stepLen + ux * max(min(radial, clampR), -clampR), rp.Z + tz * stepLen + uz * max(min(radial, clampR), -clampR)
    local params = raycastParams(e.model)
    local y = floorY(px, rp.Y, pz, params)
    local blocked = (not y) or abs(y - rp.Y) > CFG.maxStepHeight + 3 or dangerAt(px, rp.Y, pz, stepLen / walkSpeed()) >= CFG.dodgeMoveAt
    if blocked or now - BR.strafeFlipAt > 4 then
        BR.strafeDir = -BR.strafeDir
        BR.strafeFlipAt = now
        if blocked then return nil end
    end
    return Vector3.new(px, y or rp.Y, pz)
end

-- Is the next stretch of a walk safe for the moment it is crossed? Three
-- samples along it at the times they would be reached, plus a short dwell.
local function stepSafe(rp, to, speed)
    local dx, dz = to.X - rp.X, to.Z - rp.Z
    local len = sqrt(dx * dx + dz * dz)
    if len < 0.1 then return true end
    local step = min(len, 6)
    local ux, uz = dx / len * step, dz / len * step
    local T = step / max(speed, 4)
    local d = max(dangerAt(rp.X + ux * 0.5, rp.Y, rp.Z + uz * 0.5, T * 0.5), dangerAt(rp.X + ux, rp.Y, rp.Z + uz, T), dangerAt(rp.X + ux, rp.Y, rp.Z + uz, T + 0.3))
    return d < CFG.dodgeMoveAt
end

-- ------------------------------------------------------------ tick
local function brainTick(now)
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not hum or not root or hum.Health <= 0 then
        setMovementState("no character")
        BR.waypoints = nil
        return
    end

    local target = pickTarget(root.Position)
    BR.target = target
    if target then
        DG.approach = { x = target.root.Position.X, z = target.root.Position.Z, standoff = standoffFor(target), model = target.model }
    else
        DG.approach = nil
    end

    if now - DG.lastDecision >= CFG.dodgeInterval then
        DG.lastDecision = now
        local ok, err = pcall(decide, root, hum)
        if not ok then heavyDebugThrottled("decide_err", 2, "Field", tostring(err)) end
    end

    -- 1. The field's spot outranks everything while the ground here is
    -- dangerous now, or when the walk the brain wants is itself unsafe. With
    -- something always about to arrive somewhere, a spot chosen for future
    -- danger must not stop a walk whose own next step is clean.
    if DG.target then
        local useSpot = (DG.here0 or 0) >= CFG.dodgeMoveAt
        if not useSpot then
            local walkTo
            if target then
                local standoff = standoffFor(target)
                if flat(root.Position, target.root.Position) > standoff + 3 then walkTo = target.root.Position end
            end
            if not walkTo then
                local room = nextRoom(root.Position)
                walkTo = room and room.position
            end
            useSpot = walkTo == nil or not stepSafe(root.Position, walkTo, walkSpeed())
        end
        if useSpot then
            local speed = RT.moveBoost and CFG.tweenEscape or walkSpeed()
            driveTo(hum, root, DG.target, speed, 1.2)
            setMovementState("dodge " .. DG.reason)
            if target then fight(hum, root, target, now) end
            return
        end
    end

    -- 2. A target: close to standoff, then fight and strafe.
    if target then
        local standoff = standoffFor(target)
        local d = flat(root.Position, target.root.Position)
        if d > standoff + 3 then
            local speed = (target.isBoss and d > 45) and CFG.tweenEscape or walkSpeed()
            travel(hum, root, target.root.Position, speed, "approach", target.model)
            if d <= CFG.abilityRadius then fight(hum, root, target, now) end
            return
        end
        BR.waypoints = nil
        fight(hum, root, target, now)
        if d < standoff - (target.isBoss and 12 or 6) then
            -- Well inside the band (the boss leapt onto us, a mob charged): straight out.
            local rp, ep = root.Position, target.root.Position
            local away = Vector3.new(rp.X - ep.X, 0, rp.Z - ep.Z)
            if away.Magnitude > 0.5 then
                local dest = rp + away.Unit * 12
                if stepSafe(rp, dest, CFG.tweenEscape) then
                    driveTo(hum, root, dest, CFG.tweenEscape, 1.0)
                    setMovementState("back off")
                    return
                elseif DG.target then
                    -- The straight line back is through an attack (the mage volleys
                    -- were walked into this way); take the field's spot instead.
                    driveTo(hum, root, DG.target, CFG.tweenEscape, 1.0)
                    setMovementState("back off via spot")
                    return
                end
            end
        end
        if CFG.strafe then
            local p = strafePoint(root, target, standoff, now)
            if p then
                local speed = (target.melee and d < standoff - 2) and CFG.tweenEscape or walkSpeed() * CFG.strafeSpeedFraction
                driveTo(hum, root, p, speed, 1.0)
                setMovementState("strafe")
                return
            end
        end
        releaseMover(hum, root)
        setMovementState("in range")
        return
    end

    -- 3. Nothing to fight: on to the next room.
    local room = nextRoom(root.Position)
    if room then
        travel(hum, root, room.position, walkSpeed(), "to " .. room.name)
        return
    end
    releaseMover(hum, root)
    setMovementState("idle")
end

S.BR = BR
S.brainTick = brainTick
S.standoffFor = standoffFor
end
