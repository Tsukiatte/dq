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

-- How far the abilities reach: measured range plus the geyser's own radius,
-- else the configured cast radius.
S.abilityReach = function()
    if CFG.autoStandoff and RD.abilityRange then
        return math.max(CFG.abilityRadius, math.min(RD.abilityRange, CFG.autoStandoffMax) + 3)
    end
    return CFG.abilityRadius
end

local function standoffFor(e)
    -- No fan override: a 95-stud standoff during the beam fan put the bot
    -- twenty studs from the arena edge and the leash killed it twice (run 28).
    -- With the ability's range measured, the boss is fought from just inside
    -- it (Chris: the safest spot that still hits).
    if e.isBoss then
        -- During the beam fan the fight is from the edge: the lanes are far
        -- enough apart there to stand between and hop across.
        if os.clock() < (RD.fanUntil or -math.huge) + 1.0 then return CFG.fanRadius end
        if CFG.autoStandoff and RD.abilitySlots then
            -- The least ranged slot: two studs inside a known cap, one past a
            -- reach that is only a lower bound. Never closer than the slider.
            local best = nil
            for _, s in pairs(RD.abilitySlots) do
                local v = s.cap and (s.cap - 2) or (s.reach and (s.reach + 1))
                if v and (not best or v < best) then best = v end
            end
            if best then return math.max(CFG.bossStandoff, math.min(best, CFG.autoStandoffMax)) end
        end
        return CFG.bossStandoff
    end
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
    -- Progress survives a reload of the script inside the same dungeon.
    if BR.reachedOrder == nil then BR.reachedOrder = _G.DungeonAutofarmReached or 0 end
    for _, r in ipairs(rooms) do
        local inside = false
        if r.box then
            local lp = r.box.cf:PointToObjectSpace(rp)
            inside = abs(lp.X) <= r.box.size.X * 0.5 + 4 and abs(lp.Z) <= r.box.size.Z * 0.5 + 4
        end
        if (inside or flat(rp, r.position) < 25) and r.order > (BR.reachedOrder or 0) then BR.reachedOrder = r.order _G.DungeonAutofarmReached = r.order end
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
local stepSafe
local function travel(hum, root, to, speed, label, exclude)
    local rp = root.Position
    local now = os.clock()
    if flat(rp, to) < 70 and lineClear(rp, to, exclude) then
        BR.waypoints = nil
        if not stepSafe(root.Position, to, speed) then
            -- The next stretch is cut by an attack: stand for the moment rather
            -- than walk into it (the field moves us if standing is unsafe).
            if DG.target then
                -- The spot instead of standing beside the box that cut the line.
                driveTo(hum, root, DG.target, CFG.tweenEscape, 1.0)
                setMovementState(label .. " blocked; via spot")
                return false
            end
            releaseMover(hum, root)
            setMovementState(label .. " blocked")
            return false
        end
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
    if not stepSafe(root.Position, wp, speed) then
        if DG.target then
            driveTo(hum, root, DG.target, CFG.tweenEscape, 1.0)
            setMovementState(label .. " blocked; via spot")
            return false
        end
        releaseMover(hum, root)
        setMovementState(label .. " blocked")
        return false
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
    if d <= S.abilityReach() then
        -- Each cast queues up for the reader, which measures the range from
        -- where the projectile lands.
        RT.castQueue = RT.castQueue or {}
        local function queueCast(slot)
            RT.castQueue[#RT.castQueue + 1] = { slot = slot, at = now, pos = root.Position, targetPos = ep }
            while #RT.castQueue > 4 do table.remove(RT.castQueue, 1) end
        end
        if CFG.autoQ and now - RT.lastQ >= CFG.abilityInterval then RT.lastQ = now pressKey(Enum.KeyCode.Q) queueCast("q") end
        if CFG.autoE and now - RT.lastE >= CFG.abilityInterval then RT.lastE = now pressKey(Enum.KeyCode.E) queueCast("e") end
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
stepSafe = function(rp, to, speed)
    local dx, dz = to.X - rp.X, to.Z - rp.Z
    local len = sqrt(dx * dx + dz * dz)
    if len < 0.1 then return true end
    local step = min(len, 6)
    local ux, uz = dx / len * step, dz / len * step
    local T = step / max(speed, 4)
    local d = max(dangerAt(rp.X + ux * 0.5, rp.Y, rp.Z + uz * 0.5, T * 0.5), dangerAt(rp.X + ux, rp.Y, rp.Z + uz, T), dangerAt(rp.X + ux, rp.Y, rp.Z + uz, T + 0.3))
    -- A step is refused only for what would hurt during the crossing; a lane
    -- whose body is far off (soft danger) may be crossed, never sat on.
    return d < CFG.stepBlockAt
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
        DG.approach = { x = target.root.Position.X, z = target.root.Position.Z, standoff = standoffFor(target), model = target.model, isBoss = target.isBoss }
    else
        DG.approach = nil
    end

    if now - DG.lastDecision >= CFG.dodgeInterval then
        DG.lastDecision = now
        local ok, err = pcall(decide, root, hum)
        if not ok then heavyDebugThrottled("decide_err", 2, "Field", tostring(err)) end
    end

    -- 0. A reflex: an announced instadeath with a known centre (the slam).
    -- Straight out from it at escape speed until clear of its radius, the
    -- field consulted only to bend the line round a live box.
    local rf = RT.reflex
    if rf then
        if now > rf.untilAt then
            RT.reflex = nil
        else
            local rp = root.Position
            local away = Vector3.new(rp.X - rf.from.X, 0, rp.Z - rf.from.Z)
            local dist = away.Magnitude
            if dist >= rf.radius then
                RT.reflex = nil
            else
                if dist < 0.5 then away = Vector3.new(1, 0, 0) dist = 1 end
                local u = away / dist
                local dest
                for _, deg in ipairs({ 0, 35, -35, 70, -70 }) do
                    local r = math.rad(deg)
                    local dx, dz = u.X * math.cos(r) - u.Z * math.sin(r), u.X * math.sin(r) + u.Z * math.cos(r)
                    local cand = rp + Vector3.new(dx, 0, dz) * 14
                    if stepSafe(rp, cand, CFG.tweenEscape) then dest = cand break end
                end
                dest = dest or (rp + u * 14)
                driveTo(hum, root, dest, CFG.tweenEscape, 1.0)
                setMovementState(string.format("flee %s %.0f/%.0f", rf.name, dist, rf.radius))
                return
            end
        end
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
            -- Walking speed, always: a boss approach at 22 for ten seconds was a kick.
            travel(hum, root, target.root.Position, walkSpeed(), "approach", target.model)
            if d <= S.abilityReach() then fight(hum, root, target, now) end
            return
        end
        BR.waypoints = nil
        fight(hum, root, target, now)
        if d < standoff - (target.isBoss and 12 or 6) then
            -- Well inside the band (the boss leapt onto us, a mob charged): straight out.
            local rp, ep = root.Position, target.root.Position
            local away = Vector3.new(rp.X - ep.X, 0, rp.Z - ep.Z)
            if away.Magnitude > 0.5 then
                -- The most open way out: straight back when the way is clear,
                -- else round the side, else past the target. A ray at chest
                -- height finds the wall; a step under six studs is a corner.
                local u = away.Unit
                local params = raycastParams(target.model)
                local dest, bestScore = nil, -math.huge
                for _, deg in ipairs({ 0, 40, -40, 80, -80, 120, -120 }) do
                    local r = math.rad(deg)
                    local dx, dz = u.X * math.cos(r) - u.Z * math.sin(r), u.X * math.sin(r) + u.Z * math.cos(r)
                    local dir = Vector3.new(dx, 0, dz)
                    local hit = Workspace:Raycast(rp + Vector3.new(0, 2, 0), dir * 22, params)
                    local free = hit and hit.Distance or 22
                    if free >= 6 then
                        local cand = rp + dir * min(12, free - 3)
                        if stepSafe(rp, cand, CFG.tweenEscape) then
                            local score = free - math.abs(deg) / 40
                            if score > bestScore then bestScore, dest = score, cand end
                        end
                    end
                end
                if dest then
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

    -- 3. Nothing to fight: on to the next room, unless the run is over.
    if S.runComplete and S.runComplete() then
        releaseMover(hum, root)
        setMovementState("run complete")
        return
    end
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
