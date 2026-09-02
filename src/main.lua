-- main.lua - Enemy scanner, attack, abilities, remote hook, heartbeat loops, startup.
-- Module contract: receives the shared table S. Everything this module needs from
-- earlier modules is pulled into locals below; everything later modules need is
-- assigned onto S at the bottom. Load order is fixed by main.lua / build.py.
return function(S)
local RT = S.RT
local Workspace = S.Workspace
local camera = Workspace.CurrentCamera
local heavyDebugOnChange = S.heavyDebugOnChange
local LocalPlayer = S.LocalPlayer
local updatePursuitMovement = S.updatePursuitMovement
local CFG = S.CFG
local VirtualInputManager = S.VirtualInputManager
local heavyDebug = S.heavyDebug
local Players = S.Players
local NAV = S.NAV
local HZ = S.HZ
local updateWallHighlights = S.updateWallHighlights
local heavyDebugThrottled = S.heavyDebugThrottled
local faceTowards = S.faceTowards
local UserInputService = S.UserInputService
local printVersionBanner = S.printVersionBanner
local loadConfig = S.loadConfig
local createControlUI = S.createControlUI
local setStreamerEnabled = S.setStreamerEnabled
local syncStreamerToggleWidget = S.syncStreamerToggleWidget
local RunService = S.RunService
local updateEnemyDisplay = S.updateEnemyDisplay
local setMovementState = S.setMovementState
local resetPursuitPath = S.resetPursuitPath
local clearEscapeRoute = S.clearEscapeRoute
local clearHitboxVisualizer = S.clearHitboxVisualizer
local clearHoverHighlight = S.clearHoverHighlight
local flushClassificationCaches = S.flushClassificationCaches
local scanDamageBricks = S.scanDamageBricks
local progressPath = S.progressPath
local updateHitboxVisualizer = S.updateHitboxVisualizer
local isPositionSafeFromDamageBricks = S.isPositionSafeFromDamageBricks
local pruneBlockedAreas = S.pruneBlockedAreas
local blockArea = S.blockArea
local resolveEscapeRoute = S.resolveEscapeRoute
local followEscapeRoute = S.followEscapeRoute
local getActiveHazardRepulsionVector = S.getActiveHazardRepulsionVector
local followPath = S.followPath
local stopCharacterMovement = S.stopCharacterMovement
local releaseFacing = S.releaseFacing
local DEBUG_VERBOSE = S.DEBUG_VERBOSE
local startWorldIndex = S.startWorldIndex
local worldIndexStep = S.worldIndexStep
local rebuildCatalogArrays = S.rebuildCatalogArrays
local noteOwnAction = S.noteOwnAction
local runRecovery = S.runRecovery
local enterRecovery = S.enterRecovery
local updateStuckDetector = S.updateStuckDetector
local dodgeStepClear = S.dodgeStepClear
local startPrecastListener = S.startPrecastListener
local DG = S.DG
local ZN = S.ZN
local LD = S.LD
local dodgeStep = S.dodgeStep
local runDodge = S.runDodge
local buildDodgeVisuals = S.buildDodgeVisuals

-- Trial runs (2.3.0): every drop in health is handed to the correlator while a
-- trial run is on. The connection is per character and rebuilt on respawn.
local function watchHealth(character)
    if RT.healthConnection then
        RT.healthConnection:Disconnect()
        RT.healthConnection = nil
    end
    local humanoid = character and character:FindFirstChildWhichIsA("Humanoid")
    if not humanoid then return end
    RT.lastHealth = humanoid.Health
    RT.healthConnection = humanoid.HealthChanged:Connect(function(health)
        local last = RT.lastHealth
        RT.lastHealth = health
        if not last or health >= last then return end
        -- Every hit names what was next to you, and teaches detection the
        -- name if it did not already know it.
        if S.recordHit then
            local damage = last - health
            task.defer(S.recordHit, damage)
        end
    end)
end

-- =========================================================================
-- Remote hook (2.1.0 rewrite).
--
-- The old hook replaced __namecall with a closure that built `local args =
-- {...}` on EVERY namecall in the client - every FindFirstChild, IsA, Raycast,
-- GetDescendants the game or this script made - and never even read the
-- table. That is a permanent allocation stream feeding the garbage collector,
-- i.e. periodic GC pauses from the moment the script started. The hook is now
-- a single string compare on the fast path, allocates nothing, is removed
-- again after CFG.remoteHookLifetime, and is restored on Destruct.
--
-- What it is for now: timing. When THIS client fires an attack-ish remote, one
-- of our own casts just happened, and a part that appears right after it near
-- us is our own effect, not a telegraph (see hazards.lua, markOwnIfRecent).
-- The detected remote is NOT fired by the bot any more - see the attack method.
-- =========================================================================

local ATTACK_REMOTE_WORDS = { "attack", "swing", "hit", "spell", "ability", "skill", "cast", "m1" }

local function unhookAttackRemotes()
    local original = RT.originalNamecall
    if not original then return end
    RT.originalNamecall = nil
    pcall(function()
        local mt = getrawmetatable(game)
        setreadonly(mt, false)
        mt.__namecall = original
        setreadonly(mt, true)
    end)
    heavyDebug("Remote", "__namecall hook removed.")
end

local function hookAttackRemotes()
    if not CFG.hookRemotes or RT.originalNamecall then return end
    pcall(function()
        local mt = getrawmetatable(game)
        if not mt then return end
        local oldNamecall = mt.__namecall
        RT.originalNamecall = oldNamecall
        RT.hookInstalledAt = os.clock()
        setreadonly(mt, false)

        mt.__namecall = newcclosure(function(self, ...)
            local method = getnamecallmethod()
            if method == "FireServer" or method == "InvokeServer" then
                local ok, name = pcall(function() return string.lower(self.Name) end)
                if ok then
                    for _, word in ipairs(ATTACK_REMOTE_WORDS) do
                        if string.find(name, word, 1, true) then
                            noteOwnAction("remote " .. name)
                            if not RT.detectedAttackRemote then
                                RT.detectedAttackRemote = self
                                heavyDebug("Remote", "This client fires an attack-ish remote: " .. name
                                    .. " (recorded for own-attack timing; the bot attacks by clicking).")
                            end
                            break
                        end
                    end
                end
            end
            return oldNamecall(self, ...)
        end)

        setreadonly(mt, true)
    end)
end

-- Our own casts also show up as an Action-priority animation starting on our
-- character (idle/walk/jump are Core/Idle/Movement priority). This is the
-- primary own-attack timing signal: no hook, no per-call cost, and it fires
-- only when a cast actually happens - not on every key press the auto-ability
-- spam sends.
local function watchOwnAnimations(character)
    if RT.animatorConnection then
        RT.animatorConnection:Disconnect()
        RT.animatorConnection = nil
    end
    local humanoid = character and character:FindFirstChildWhichIsA("Humanoid")
    if not humanoid then return end
    local animator = humanoid:FindFirstChildOfClass("Animator") or humanoid
    local ok, connection = pcall(function()
        return animator.AnimationPlayed:Connect(function(track)
            local priority = track.Priority
            -- Action = 2, Action2..4 above it; Core is 1000 and must not count.
            if priority and priority.Value >= Enum.AnimationPriority.Action.Value
                and priority ~= Enum.AnimationPriority.Core then
                local animation = track.Animation
                noteOwnAction("animation " .. (animation and animation.Name or "?"))
            end
        end)
    end)
    if ok then
        RT.animatorConnection = connection
    end
end

-- Attack Execution
-- Where pursuit is about to step: its next waypoint if it has a route, else
-- straight at the enemy.
local function pursuitAhead(enemyRoot)
    local wp = NAV.waypoints and NAV.waypoints[NAV.index]
    if wp ~= nil then
        local t = typeof(wp)
        if t == "Vector3" then return wp end
        if t == "PathWaypoint" or (t == "table" and wp.Position) then return wp.Position end
    end
    return enemyRoot.Position
end

local function attackEnemy(enemy)
    if not enemy then
        heavyDebugOnChange("attack_guard", "nil_enemy", "Attack", "ABORT: enemy is nil.")
        return
    end

    local enemyRoot = enemy:FindFirstChild("HumanoidRootPart") or enemy.PrimaryPart or enemy:FindFirstChildWhichIsA("BasePart")
    local character = LocalPlayer.Character
    local humanoid = character and character:FindFirstChildWhichIsA("Humanoid")
    local root = character and character:FindFirstChild("HumanoidRootPart")

    if not enemyRoot or not humanoid or not root then
        heavyDebugOnChange("attack_guard", "missing_parts", "Attack", string.format(
            "ABORT: enemyRoot=%s playerHumanoid=%s playerRoot=%s (enemy: %s)",
            tostring(enemyRoot ~= nil), tostring(humanoid ~= nil), tostring(root ~= nil), enemy.Name))
        return
    end
    heavyDebugOnChange("attack_guard", "ok", "Attack", "Guards passed, entering pursuit for " .. enemy.Name)

    -- With pathfinding off the bot still picks a target and still swings if it
    -- happens to be in reach; it just stops driving your character there.
    if not CFG.pathfindingEnabled then
        setMovementState("pathfinding off (testing)")
    elseif DG.active and CFG.dodgeEnabled then
        -- Pursuit walks the map; the dodge outranks it. The loop only reaches
        -- this with no box to follow, and even then pursuit gets a step only
        -- if the next few studs of its route are clear. When they are not the
        -- character holds, and the box - told pursuit is blocked - picks the
        -- way in one safe spot at a time. (4.2.0 had dropped pursuit outright,
        -- so the bot could no longer cross a room.)
        -- And not while the dodge itself is waiting for a gap: five clear
        -- studs at a time was how it walked into a pattern one step per tick.
        if not DG.gapWait and dodgeStepClear(root, humanoid, pursuitAhead(enemyRoot)) then
            DG.pursuitBlocked = false
            updatePursuitMovement(enemy, humanoid, root, enemyRoot)
        else
            DG.pursuitBlocked = true
            humanoid:MoveTo(root.Position)
            setMovementState(DG.gapWait and "waiting for a gap [hold]" or "holding for a gap")
        end
    else
        updatePursuitMovement(enemy, humanoid, root, enemyRoot)
    end

    local flatOffset = Vector3.new(root.Position.X - enemyRoot.Position.X, 0, root.Position.Z - enemyRoot.Position.Z)
    -- Reach has to cover the stand-off distance, otherwise the bot would walk
    -- back into melee purely so it could swing.
    local reach = math.max(CFG.attackRange, S.getEnemyStandoff(enemy) + 1.5)
    if flatOffset.Magnitude <= reach and RT.farmEnabled and not RT.destroyed and RT.gameSpecificAttackMethod then
        RT.gameSpecificAttackMethod(enemy)
    end
end

local function pressAbilityKey(keyCode)
    pcall(function()
        VirtualInputManager:SendKeyEvent(true, keyCode, false, game)
    end)
    task.delay(CFG.abilityHoldDuration, function()
        pcall(function()
            VirtualInputManager:SendKeyEvent(false, keyCode, false, game)
        end)
    end)
end

-- Ability gate (2.2.0): with the radius gate on, Q/E only fire while the
-- current target is inside CFG.abilityRadius. The nearest enemy is the current
-- target, so "any enemy in radius" and "the target in radius" are the same test.
local function enemyWithinAbilityRadius()
    local enemy = NAV.cachedEnemy
    if not enemy then return false end
    local character = LocalPlayer.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    local enemyRoot = enemy:FindFirstChild("HumanoidRootPart") or enemy.PrimaryPart or enemy:FindFirstChildWhichIsA("BasePart")
    if not root or not enemyRoot then return false end
    return (enemyRoot.Position - root.Position).Magnitude <= CFG.abilityRadius
end

local function useAutoAbilities()
    if not RT.autoQEnabled and not RT.autoEEnabled then return end
    if CFG.abilityRadiusEnabled and not enemyWithinAbilityRadius() then return end
    local now = os.clock()
    if RT.autoQEnabled and now - RT.lastQTime >= CFG.abilityInterval then
        RT.lastQTime = now
        pressAbilityKey(Enum.KeyCode.Q)
    end
    if RT.autoEEnabled and now - RT.lastETime >= CFG.abilityInterval then
        RT.lastETime = now
        pressAbilityKey(Enum.KeyCode.E)
    end
end

-- Enemy scan (2.1.0). Reads the world index instead of walking Workspace: the
-- candidate set is every model carrying a Humanoid plus every BillboardGui that
-- might be a floating health tag, both maintained by DescendantAdded/Removing.
-- Dozens of instances to look at per scan rather than tens of thousands.
local function findNearestEnemy()
    local character = LocalPlayer.Character
    local playerRoot = character and character:FindFirstChild("HumanoidRootPart")
    if not playerRoot then
        heavyDebug("Scanner", "Scan skipped: LocalPlayer HumanoidRootPart missing.")
        return nil, 0
    end

    local nearestEnemy = nil
    local nearestDistance = math.huge
    local nearestScore = math.huge
    local enemyCount = 0
    local seenModels = {}
    local now = os.clock()
    local rootPos = playerRoot.Position

    -- Workspace.enemies is where the game puts them (game/GAME_NOTES.md), so
    -- the sweep starts there instead of walking the whole world.
    local enemiesFolder = Workspace:FindFirstChild("enemies")

    local function evaluateEntity(model, healthValue, sourceTag)
        if not model or model == character or seenModels[model] then
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

        -- Benched for being unreachable. Still counted, just not targeted, so
        -- the on-screen enemy count keeps reflecting what is actually alive.
        local benchedUntil = NAV.benched[model]
        if benchedUntil then
            if now < benchedUntil then
                seenModels[model] = true
                enemyCount = enemyCount + 1
                return
            end
            NAV.benched[model] = nil
        end

        seenModels[model] = true
        enemyCount = enemyCount + 1
        local distance = (rootPos - root.Position).Magnitude
        local health = healthValue or (humanoid and humanoid.Health) or nil
        -- Guarded so the string.format cost is not paid on every entity every
        -- scan while VERBOSE is off, which is almost always.
        if RT.debugLevel >= DEBUG_VERBOSE then
            heavyDebug("Scanner", string.format("Found valid entity via [%s]: %s | Distance: %.1f | HP: %s", sourceTag, model.Name, distance, tostring(healthValue or (humanoid and humanoid.Health))), DEBUG_VERBOSE)
        end

        -- Targeting (2.7.0). "closest" scores on distance, as it always did.
        -- The HP modes score on health but only consider enemies inside
        -- targetHpRange, so a wounded straggler on the far side of the dungeon
        -- does not drag the bot across the map; outside that range they fall
        -- back to distance, which keeps the bot moving toward something.
        local score, inRange
        if CFG.targetMode == "lowest HP" and health then
            inRange = distance <= CFG.targetHpRange
            score = inRange and health or (1e9 + distance)
        elseif CFG.targetMode == "highest HP" and health then
            inRange = distance <= CFG.targetHpRange
            score = inRange and -health or (1e9 + distance)
        else
            score = distance
        end

        if score < nearestScore then
            nearestScore = score
            nearestDistance = distance
            nearestEnemy = model
        end
    end

    for model in pairs(HZ.enemyModels) do
        if model.Parent then
            local humanoid = model:FindFirstChildWhichIsA("Humanoid")
            if humanoid and humanoid.Health > 0 then
                evaluateEntity(model, humanoid.Health, "Humanoid")
            end
        else
            HZ.enemyModels[model] = nil
        end
    end

    -- Health billboards catch enemies that have no Humanoid at all. A model
    -- already found by its Humanoid never gets its tag parsed.
    for gui in pairs(HZ.billboards) do
        local parent = gui.Parent
        if parent then
            local containerModel = parent:IsA("Model") and parent or parent:FindFirstAncestorOfClass("Model")
            if containerModel and not seenModels[containerModel] then
                for _, desc in ipairs(gui:GetDescendants()) do
                    if desc:IsA("TextLabel") then
                        local txt = desc.Text
                        local currentHp = tonumber(txt:match("([%d,]+)%s*/")) or tonumber(txt:match("^([%d,]+)"))
                        if currentHp then
                            evaluateEntity(containerModel, currentHp, "BillboardTag")
                            break
                        end
                    end
                end
            end
        else
            HZ.billboards[gui] = nil
        end
    end

    heavyDebugThrottled("scan_done", 2.0, "Scanner", string.format("Scan completed. Total unique enemies counted: %d. Nearest target: %s @ %.1f studs", enemyCount, tostring(nearestEnemy and nearestEnemy.Name or "None"), nearestDistance ~= math.huge and nearestDistance or -1))
    return nearestEnemy, enemyCount
end

local function detectGameAndInitialize()
    pcall(hookAttackRemotes)

    RT.gameSpecificAttackMethod = function(enemy)
        local now = os.clock()
        if now - RT.lastClickTime < CFG.clickInterval then return end

        local character = LocalPlayer.Character
        local root = character and character:FindFirstChild("HumanoidRootPart")
        local enemyRoot = enemy and enemy:FindFirstChild("HumanoidRootPart")
        if not root or not enemyRoot then return end

        -- Same velocity-reset trap as the facing helper, just throttled to the
        -- click rate rather than every frame. Routed through the safe path.
        local humanoid = character:FindFirstChildWhichIsA("Humanoid")
        if humanoid then
            faceTowards(root, humanoid, enemyRoot.Position)
        end

        -- Tool:Activate() first. The weapon is a Tool whose Activated event is
        -- handled server-side, and Activate raises that event from the client
        -- directly: no cursor involved, so nothing to accidentally press, and
        -- no fight with the player over where the mouse is pointing.
        --
        -- The detected remote is still deliberately NOT fired. Its argument
        -- signature is unknown, and replaying it with guessed arguments either
        -- does nothing or risks a malformed-remote kick.
        local method = CFG.attackMethod
        local swung = false
        if method == "auto" or method == "tool" then
            local tool = character:FindFirstChildOfClass("Tool")
            if tool then
                swung = pcall(function() tool:Activate() end)
            end
        end

        if not swung and method ~= "tool" and CFG.autoClickEnabled then
            -- Falling back to a synthetic click. Aimed at the middle of the
            -- viewport rather than wherever the cursor is: clicking at the
            -- cursor meant clicking whatever it happened to be resting on,
            -- which was regularly one of our own buttons.
            local x, y
            if CFG.clickAtCursor then
                local mousePosition = UserInputService:GetMouseLocation()
                x, y = mousePosition.X, mousePosition.Y
            else
                local viewport = camera and camera.ViewportSize
                x = viewport and viewport.X * 0.5 or 400
                y = viewport and viewport.Y * 0.5 or 300
            end
            pcall(function()
                VirtualInputManager:SendMouseButtonEvent(x, y, 0, true, game, 0)
            end)
            task.delay(CFG.clickHoldDuration, function()
                pcall(function()
                    VirtualInputManager:SendMouseButtonEvent(x, y, 0, false, game, 0)
                end)
            end)
            swung = true
        end

        if not swung then
            heavyDebugThrottled("attack_none", 3.0, "Combat",
                "No tool equipped and clicking is off, so there is nothing to attack with.")
        end

        RT.lastClickTime = now
    end
end

local function startAutofarm()
    printVersionBanner()

    -- Loaded before the UI is built so sliders and toggles come up already
    -- showing the saved values rather than the defaults.
    local configLoaded, wantsStreamerMode = loadConfig()

    createControlUI()

    if configLoaded then
        heavyDebug("Config", "Applied saved settings on startup.")
        if wantsStreamerMode then
            setStreamerEnabled(true)
            syncStreamerToggleWidget()
        end
    end

    local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    local humanoid = character:WaitForChild("Humanoid")
    local root = character:WaitForChild("HumanoidRootPart")

    startWorldIndex()

    -- The game's own attack broadcast, and its own idea of which dungeon this
    -- is. Both are cheap and both beat anything we can infer.
    if CFG.usePrecast then startPrecastListener() end
    if S.watchDungeonName then S.watchDungeonName() end
    if S.watchOwnAbilityRemotes then S.watchOwnAbilityRemotes() end
    detectGameAndInitialize()
    watchOwnAnimations(character)
    watchHealth(character)
    S.setMode(RT.mode)

    LocalPlayer.CharacterAdded:Connect(function(newChar)
        character = newChar
        humanoid = newChar:WaitForChild("Humanoid")
        root = newChar:WaitForChild("HumanoidRootPart")
        watchOwnAnimations(newChar)
        watchHealth(newChar)
        -- The box is sized from the character, so a respawn rebuilds it.
        if DG.active then buildDodgeVisuals() end
    end)

    -- Index maintenance + throttled enemy scan. The index step runs even while
    -- farming is paused: it is bounded and cheap, and it keeps the catalog warm
    -- for when the loop is switched back on.
    local lastScanClock = 0
    RT.enemyScanConnection = RunService.Heartbeat:Connect(function(delta)
        if RT.destroyed then return end

        local indexOk, indexErr = xpcall(worldIndexStep, debug.traceback)
        if not indexOk then
            heavyDebugThrottled("index_error", 1.0, "FATAL", "World index threw:\n" .. tostring(indexErr))
        end

        local now = os.clock()
        if RT.originalNamecall and now - RT.hookInstalledAt >= CFG.remoteHookLifetime then
            unhookAttackRemotes()
        end

        -- Trial runs, freezing and picking work with the loop OFF (2.4.0): they
        -- are about watching and learning, not fighting, and the natural way to
        -- study an attack is to stand there and let it hit you. The hazard scan
        -- (which also feeds the highlights, the name tags, the frozen copies and
        -- the pickers need a live world index) therefore runs whenever any of
        -- those is armed, even while farming is paused.
        if not RT.farmEnabled then
            if HZ.pickerEnabled or ZN.pickerEnabled or LD.pickerEnabled then
                local character = LocalPlayer.Character
                local liveRoot = character and character:FindFirstChild("HumanoidRootPart")
                if liveRoot then
                    local ok, err = xpcall(scanDamageBricks, debug.traceback, liveRoot.Position)
                    if not ok then
                        heavyDebugThrottled("idle_scan_error", 1.0, "FATAL",
                            "Hazard scan (loop off) threw:\n" .. tostring(err))
                    end
                end
            end
            return
        end
        if NAV.forceRescan or (now - lastScanClock >= CFG.enemyScanInterval) then
            NAV.forceRescan = false
            lastScanClock = now
            local ok, err = xpcall(function()
                NAV.cachedEnemy, NAV.cachedEnemyCount = findNearestEnemy()
                updateEnemyDisplay(NAV.cachedEnemy, NAV.cachedEnemyCount)
                rebuildCatalogArrays()
                if now - HZ.lastWallRenderTime >= CFG.visualRefreshInterval then
                    HZ.lastWallRenderTime = now
                    updateWallHighlights()
                end
            end, debug.traceback)
            if not ok then
                heavyDebugThrottled("scan_error", 1.0, "FATAL", "Scanner threw:\n" .. tostring(err))
            end
        end
    end)

    -- Unconditional Main Combat Loop
    RT.mainConnection = RunService.Heartbeat:Connect(function(delta)
        -- Real frame time, for movers that step the character by hand rather
        -- than handing a destination to the humanoid.
        RT.frameDelta = delta or (1 / 60)
        if RT.destroyed or not RT.farmEnabled then return end

        -- xpcall, not pcall: a silent pcall here hid every downstream fault and
        -- made the loop look like it was simply choosing not to move.
        local ok, err = xpcall(function()
            -- Refetch the character every tick. The captured upvalues go stale
            -- across a respawn, and touching a destroyed part throws.
            local character = LocalPlayer.Character
            local liveHumanoid = character and character:FindFirstChildWhichIsA("Humanoid")
            local liveRoot = character and character:FindFirstChild("HumanoidRootPart")

            if not liveHumanoid or not liveRoot or liveHumanoid.Health <= 0 then
                heavyDebugOnChange("loop_branch", "dead", "Loop", string.format(
                    "IDLE (no live character): humanoid=%s root=%s health=%s",
                    tostring(liveHumanoid ~= nil), tostring(liveRoot ~= nil),
                    liveHumanoid and tostring(liveHumanoid.Health) or "n/a"))
                setMovementState("no character")
                NAV.cachedEnemy = nil
                resetPursuitPath()
                clearEscapeRoute()
                clearHitboxVisualizer()
                clearHoverHighlight()
                updateEnemyDisplay(nil, 0)
                return
            end

            humanoid = liveHumanoid
            root = liveRoot

            local tickClock = os.clock()

            if tickClock - RT.lastCacheFlushTime >= CFG.classificationCacheLifetime then
                flushClassificationCaches()
            end

            scanDamageBricks(root.Position)
            if not NAV.pathEditEnabled then progressPath(root.Position) end

            -- Adornment properties only need refreshing when the character's own
            -- dimensions change, which is rare. No reason to touch them per frame.
            if tickClock - HZ.lastHitboxTime >= CFG.hitboxVisualRefreshInterval then
                HZ.lastHitboxTime = tickClock
                updateHitboxVisualizer()
            end

            useAutoAbilities()

            -- The dodge decides every frame whether or not anything is
            -- threatening, so the box is already in the right place when it
            -- is needed.
            if DG.active then dodgeStep(root, humanoid) end

            -- Manual: dodge only. It pulls you out of attacks and nothing else
            -- runs, so the character is yours between dodges.
            if DG.active and CFG.dodgeManual then
                if DG.target or DG.dangerHere >= CFG.dodgeMoveAt then
                    heavyDebugOnChange("loop_branch", "dodge_manual_move", "Loop",
                        "BRANCH: DODGE MANUAL - moving.")
                    runDodge(humanoid, root)
                else
                    heavyDebugOnChange("loop_branch", "dodge_manual", "Loop",
                        "BRANCH: DODGE MANUAL - watching; you have the controls.")
                    setMovementState(string.format("DODGE manual (danger %.2f)", DG.dangerHere))
                    NAV.lastIssuedMove = nil
                end
                releaseFacing(humanoid)
                return
            end

            -- Whichever branch below actually moves the character toward a goal
            -- sets this; the recovery detector reads it after the branch.
            NAV.driving = false

            -- In Dodge mode the trigger is the dodge's own verdict on here, and
            -- an en-route box keeps it in charge until it arrives.
            local inHazard
            if DG.active then
                -- The box is in charge whenever it has somewhere to be, whether
                -- that is out of danger or nearer the target.
                inHazard = CFG.dodgeEnabled and DG.target ~= nil
            else
                inHazard = CFG.dodgeEnabled and not isPositionSafeFromDamageBricks(root.Position, 0.5)
            end

            -- Location-based stuck detection. Deliberately skipped while dodging:
            -- holding still inside a telegraph's clearance is the escape logic
            -- working, not a trap, and blacklisting there would fight it.
            pruneBlockedAreas(tickClock)
            if inHazard then
                NAV.spotAnchor = nil
            elseif not NAV.spotAnchor
                or (root.Position - NAV.spotAnchor).Magnitude >= CFG.stuckAreaMoveThreshold then
                NAV.spotAnchor = root.Position
                NAV.spotAnchorTime = tickClock
            elseif tickClock - NAV.spotAnchorTime >= CFG.stuckAreaTime then
                blockArea(root.Position, tickClock)
                NAV.spotAnchor = root.Position
                NAV.spotAnchorTime = tickClock
                NAV.steerAngle = nil
                NAV.needsRecompute = true
                humanoid.Jump = true
            end

            if inHazard then
                heavyDebugOnChange("loop_branch", "hazard", "Loop", string.format(
                    "BRANCH: HAZARD ESCAPE (%d telegraphs in range).", #HZ.detected))

                local clock = os.clock()
                local routeSpent = NAV.escapeIndex > #NAV.escapeWaypoints
                local targetStillSafe = NAV.escapeTarget ~= nil
                    and isPositionSafeFromDamageBricks(NAV.escapeTarget, 0.5)

                -- Recompute when the route runs out, the destination stopped being
                -- safe (a new telegraph landed on it), or the cache went stale.
                if not DG.active and not NAV.computingEscape
                    and (routeSpent or not targetStillSafe
                        or (clock - NAV.lastEscapeTime) >= CFG.escapeRecomputeInterval) then
                    NAV.lastEscapeTime = clock
                    local enemyPosition = NAV.cachedEnemy and NAV.cachedEnemy:GetPivot().Position or root.Position
                    local fromPosition = root.Position
                    task.spawn(function()
                        resolveEscapeRoute(fromPosition, enemyPosition, NAV.cachedEnemy)
                    end)
                end

                if DG.active then
                    if not runDodge(humanoid, root) then
                        local repulsion = getActiveHazardRepulsionVector(root.Position)
                        local fallbackDir = repulsion.Magnitude > 0.1 and repulsion.Unit or Vector3.new(0, 0, 1)
                        humanoid:MoveTo(root.Position + (fallbackDir * 10))
                        setMovementState("DODGE - repulsion fallback")
                    end
                elseif not followEscapeRoute(humanoid, root) then
                    local repulsion = getActiveHazardRepulsionVector(root.Position)
                    local fallbackDir = repulsion.Magnitude > 0.1 and repulsion.Unit or Vector3.new(0, 0, 1)
                    humanoid:MoveTo(root.Position + (fallbackDir * 10))
                    setMovementState("HAZARD - repulsion fallback")
                    heavyDebugThrottled("hazard_fallback", 1.0, "Loop", "No escape route yet. Using raw repulsion vector.")
                end
            elseif NAV.recovery then
                -- Wedged: walking the manual path out. Everything else waits.
                heavyDebugOnChange("loop_branch", "recovery", "Loop",
                    "BRANCH: RECOVERY (walking the manual path to get unstuck).")
                if #NAV.escapeWaypoints > 0 then clearEscapeRoute() end
                runRecovery(humanoid, root)
            elseif NAV.cachedEnemy and NAV.benched[NAV.cachedEnemy]
                and tickClock < NAV.benched[NAV.cachedEnemy] then
                -- The direct walker gave up on this target: walking at it gained
                -- no ground for CFG.directWalkGiveUpTime. That is a wedge, so it
                -- goes to recovery if there is a path to recover along; otherwise
                -- the target is dropped and the scanner picks the next one.
                heavyDebugOnChange("loop_branch", "benched", "Loop",
                    "BRANCH: target unreachable; recovering along the path.")
                NAV.cachedEnemy = nil
                NAV.forceRescan = true
                if not CFG.pathfindingEnabled or not enterRecovery(root, "target unreachable") then
                    setMovementState("target unreachable, reselecting")
                end
            elseif NAV.cachedEnemy then
                heavyDebugOnChange("loop_branch", "pursue", "Loop", "BRANCH: PURSUE " .. NAV.cachedEnemy.Name)
                if #NAV.escapeWaypoints > 0 then clearEscapeRoute() end
                attackEnemy(NAV.cachedEnemy)
            else
                if #NAV.escapeWaypoints > 0 then clearEscapeRoute() end
                -- Remember whether the character was under our control this frame,
                -- so we know to issue a single stop when it drops to true idle.
                local wasDriving = NAV.enemy ~= nil or NAV.walkAnchor ~= nil
                if NAV.enemy then resetPursuitPath() end

                -- No enemy: walk the hand-placed path rather than standing
                -- still. Only when idle, so it never competes with an active
                -- fight.
                local walking = CFG.followPath and CFG.pathfindingEnabled
                    and not NAV.pathEditEnabled
                    and followPath(humanoid, root)

                if walking then
                    heavyDebugOnChange("loop_branch", "path", "Loop", "BRANCH: FOLLOW PATH")
                else
                    heavyDebugOnChange("loop_branch", "idle", "Loop", "BRANCH: IDLE (no target, no path).")
                    setMovementState("IDLE - no target")
                    if wasDriving then stopCharacterMovement() end
                    NAV.walkAnchor = nil
                end
            end

            -- Last resort (2.2.0): loitering in one spot while trying to move
            -- means all of the above has wedged itself. Walk the manual path.
            -- Recovery is pathfinding's own last resort, so it goes quiet with it.
            if CFG.pathfindingEnabled then
                updateStuckDetector(root, NAV.driving, inHazard, tickClock)
            end

            -- Applied after the branch so facing survives a hazard escape: the
            -- bot backs out of the telegraph while still pointed at the enemy,
            -- which keeps it in position to attack the moment it is clear. Not
            -- during recovery - there the character should look where it walks.
            if CFG.faceTarget and NAV.cachedEnemy and not NAV.recovery then
                local targetRoot = NAV.cachedEnemy:FindFirstChild("HumanoidRootPart")
                    or NAV.cachedEnemy.PrimaryPart
                    or NAV.cachedEnemy:FindFirstChildWhichIsA("BasePart")
                if targetRoot then
                    faceTowards(root, humanoid, targetRoot.Position)
                else
                    releaseFacing(humanoid)
                end
            else
                releaseFacing(humanoid)
            end
        end, debug.traceback)

        if not ok then
            setMovementState("ERROR - see console")
            heavyDebugThrottled("loop_error", 1.0, "FATAL", "Main loop threw:\n" .. tostring(err))
        end
    end)
end

S.unhookAttackRemotes = unhookAttackRemotes
S.findNearestEnemy = findNearestEnemy

startAutofarm()

end
