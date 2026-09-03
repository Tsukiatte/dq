-- main.lua - Startup and the loop. Every frame: the reader reads, the dodge
-- decides, then exactly one of the dodge, pursuit or the waypath drives the
-- mover. Abilities fire when the target is inside the ability radius; the
-- basic attack only when a mob is inside reach anyway. Bosses are never
-- approached to melee.
return function(S)
local CFG = S.CFG
local RT = S.RT
local NAV = S.NAV
local HZ = S.HZ
local DG = S.DG
local MV = S.MV
local Players = S.Players
local RunService = S.RunService
local UserInputService = S.UserInputService
local VirtualInputManager = S.VirtualInputManager
local Workspace = S.Workspace
local LocalPlayer = S.LocalPlayer
local heavyDebug = S.heavyDebug
local heavyDebugThrottled = S.heavyDebugThrottled
local setMovementState = S.setMovementState
local printVersionBanner = S.printVersionBanner
local loadConfig = S.loadConfig
local createControlUI = S.createControlUI
local setStreamerEnabled = S.setStreamerEnabled
local syncStreamerToggleWidget = S.syncStreamerToggleWidget
local readerStep = S.readerStep
local startReader = S.startReader
local scanEnemies = S.scanEnemies
local recordHit = S.recordHit
local pickTarget = S.pickTarget
local pursuitStep = S.pursuitStep
local followPath = S.followPath
local resetPursuitPath = S.resetPursuitPath
local dodgeStep = S.dodgeStep
local fieldRefresh = S.fieldRefresh
local moveTo = S.moveTo
local moverStop = S.moverStop
local moverStep = S.moverStep
local faceToward = S.faceToward
local drawStep = S.drawStep
local lowDetailStep = S.lowDetailStep
local progressPath = S.progressPath
local updateEnemyDisplay = S.updateEnemyDisplay

local clock = os.clock
local fmt = string.format
local camera = Workspace.CurrentCamera

-- ------------------------------------------------------------------ the character
local function watchHealth(character)
    if RT.healthConnection then RT.healthConnection:Disconnect() RT.healthConnection = nil end
    local humanoid = character and character:FindFirstChildWhichIsA("Humanoid")
    if not humanoid then return end
    RT.lastHealth = humanoid.Health
    RT.healthConnection = humanoid.HealthChanged:Connect(function(health)
        local last = RT.lastHealth
        RT.lastHealth = health
        if not last or health >= last then return end
        local damage = last - health
        task.defer(function() pcall(recordHit, damage) end)
        if health <= 0 then RT.deaths = RT.deaths + 1 end
    end)
end

-- ------------------------------------------------------------------ abilities and the swing
local function pressAbilityKey(keyCode)
    if RT.abilityHook then pcall(RT.abilityHook, keyCode) end
    pcall(function() VirtualInputManager:SendKeyEvent(true, keyCode, false, game) end)
    task.delay(CFG.abilityHoldDuration, function()
        pcall(function() VirtualInputManager:SendKeyEvent(false, keyCode, false, game) end)
    end)
end
local function targetWithin(radius)
    local e = NAV.cachedEntry
    local char = LocalPlayer.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not e or not root or not e.root.Parent then return false end
    local a, b = e.root.Position, root.Position
    local dx, dz = a.X - b.X, a.Z - b.Z
    return math.sqrt(dx * dx + dz * dz) <= radius
end
local function useAutoAbilities()
    if not RT.autoQEnabled and not RT.autoEEnabled then return end
    if CFG.abilityRadiusEnabled and not targetWithin(CFG.abilityRadius) then return end
    local now = clock()
    if RT.autoQEnabled and now - RT.lastQTime >= CFG.abilityInterval then
        RT.lastQTime = now
        pressAbilityKey(Enum.KeyCode.Q)
    end
    if RT.autoEEnabled and now - RT.lastETime >= CFG.abilityInterval then
        RT.lastETime = now
        pressAbilityKey(Enum.KeyCode.E)
    end
end

RT.gameSpecificAttackMethod = function(enemy)
    local now = clock()
    if now - RT.lastClickTime < CFG.clickInterval then return end
    local character = LocalPlayer.Character
    if not character then return end
    local method = CFG.attackMethod
    local swung = false
    if method == "auto" or method == "tool" then
        local tool = character:FindFirstChildOfClass("Tool")
        if tool then swung = pcall(function() tool:Activate() end) end
    end
    if not swung and method ~= "tool" and CFG.autoClickEnabled then
        local x, y
        if CFG.clickAtCursor then
            local m = UserInputService:GetMouseLocation()
            x, y = m.X, m.Y
        else
            local viewport = camera and camera.ViewportSize
            x = viewport and viewport.X * 0.5 or 400
            y = viewport and viewport.Y * 0.5 or 300
        end
        pcall(function() VirtualInputManager:SendMouseButtonEvent(x, y, 0, true, game, 0) end)
        task.delay(CFG.clickHoldDuration, function()
            pcall(function() VirtualInputManager:SendMouseButtonEvent(x, y, 0, false, game, 0) end)
        end)
        swung = true
    end
    RT.lastClickTime = now
end

-- The basic attack goes only when a mob is inside reach anyway; a boss is
-- never approached for it.
local function swingIfInReach(e, root)
    if not e or not RT.gameSpecificAttackMethod then return end
    local reach = e.boss and CFG.attackRange or math.max(CFG.attackRange, (e.extent or 2) + (e.melee or CFG.enemyMeleeReach) + 1.5)
    if targetWithin(reach) then RT.gameSpecificAttackMethod(e.model) end
end

-- ------------------------------------------------------------------ start
local function startAutofarm()
    printVersionBanner()
    local configLoaded, wantsStreamer = loadConfig()
    createControlUI()
    if configLoaded and wantsStreamer then
        setStreamerEnabled(true)
        syncStreamerToggleWidget()
    end
    if S.setMode then S.setMode(RT.mode) end

    local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    watchHealth(character)
    startReader()
    if S.watchDungeonName then S.watchDungeonName() end
    table.insert(RT.indexConnections, LocalPlayer.CharacterAdded:Connect(function(newChar)
        RT.respawnedAt = clock()
        watchHealth(newChar)
        resetPursuitPath()
        moverStop()
        heavyDebug("Loop", "Respawned.")
    end))

    -- Enemies, the target, the drawings and low detail on their own clock.
    local lastScan = -math.huge
    RT.enemyScanConnection = RunService.Heartbeat:Connect(function()
        if RT.destroyed then return end
        local now = clock()
        local ok, err = xpcall(function()
            if NAV.forceRescan or now - lastScan >= CFG.enemyScanInterval then
                NAV.forceRescan = false
                lastScan = now
                scanEnemies()
                local char = LocalPlayer.Character
                local root = char and char:FindFirstChild("HumanoidRootPart")
                if root and RT.farmEnabled then pickTarget(root) end
            end
            drawStep(now)
            lowDetailStep()
        end, debug.traceback)
        if not ok then heavyDebugThrottled("scan_error", 1.0, "FATAL", "Scanner threw:\n" .. tostring(err)) end
    end)

    -- The loop.
    RT.mainConnection = RunService.Heartbeat:Connect(function(dt)
        if type(dt) ~= "number" or dt <= 0 or dt > 1 then dt = 1 / 60 end
        RT.frameDelta = dt
        if RT.destroyed then return end
        local now = clock()
        local ok, err = xpcall(function()
            readerStep(now, dt)
            local char = LocalPlayer.Character
            local hum = char and char:FindFirstChildWhichIsA("Humanoid")
            local root = char and char:FindFirstChild("HumanoidRootPart")
            if not RT.farmEnabled then
                if MV.target then moverStop() end
                return
            end
            if not hum or not root or hum.Health <= 0 then
                setMovementState("no character")
                moverStop()
                NAV.cachedEnemy = nil
                NAV.cachedEntry = nil
                if updateEnemyDisplay then updateEnemyDisplay(nil, 0) end
                return
            end
            if not NAV.pathEditEnabled and progressPath then progressPath(root.Position) end
            fieldRefresh(now)

            if DG.active and CFG.dodgeEnabled then
                dodgeStep(root, hum, now)
            else
                DG.target = nil
                DG.dangerHere = 0
                DG.gapWait = false
                DG.pursuitBlocked = false
            end
            useAutoAbilities()

            local e = NAV.cachedEntry
            if e and not e.root.Parent then e = nil NAV.cachedEntry = nil NAV.cachedEnemy = nil end
            local face = (CFG.faceTarget and e) and e.root.Position or nil

            if DG.target then
                moveTo(DG.target, CFG.dodgeSpeed, "dodge", face)
                setMovementState(fmt("DODGE %s [%s]", DG.targetReason, CFG.moveMode))
            elseif CFG.dodgeManual then
                moverStop()
                setMovementState(fmt("DODGE manual (danger %.2f)", DG.dangerHere))
            elseif not CFG.pathfindingEnabled then
                moverStop()
                setMovementState("pathfinding off (testing)")
                swingIfInReach(e, root)
            elseif e then
                if DG.gapWait then
                    moverStop()
                    setMovementState(fmt("HOLD for a gap (danger %.2f)", DG.dangerHere))
                else
                    pursuitStep(root, hum, now)
                end
                swingIfInReach(e, root)
            elseif CFG.followPath and #NAV.waypath > 0 and not NAV.pathEditEnabled then
                if not followPath(hum, root) then
                    moverStop()
                    setMovementState("IDLE - path done")
                end
            else
                moverStop()
                setMovementState("IDLE - no target")
            end

            local driving = moverStep(dt)
            if not driving and face and CFG.moveMode == "tween" then faceToward(root, hum, face) end
        end, debug.traceback)
        if not ok then
            setMovementState("ERROR - see console")
            heavyDebugThrottled("loop_error", 1.0, "FATAL", "Main loop threw:\n" .. tostring(err))
        end
    end)
    heavyDebug("Loop", "Running.")
end

S.unhookAttackRemotes = function() end
S.startAutofarm = startAutofarm
startAutofarm()
end
