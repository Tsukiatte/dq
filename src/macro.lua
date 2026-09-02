-- macro.lua - Macro Waypoints: record a run, list and reorder the recordings, play them back.
-- Module contract: receives the shared table S. Everything this module needs from
-- earlier modules is pulled into locals below; everything later modules need is
-- assigned onto S at the bottom. Load order is fixed by main.lua / build.py.
return function(S)
local RT = S.RT
local CFG = S.CFG
local MC = S.MC
local NAV = S.NAV
local LocalPlayer = S.LocalPlayer
local Workspace = S.Workspace
local UserInputService = S.UserInputService
local VirtualInputManager = S.VirtualInputManager
local heavyDebug = S.heavyDebug
local heavyDebugThrottled = S.heavyDebugThrottled
local setMovementState = S.setMovementState
local getVisualRoot = S.getVisualRoot
local walkTowardPoint = S.walkTowardPoint
local clearPointRoute = S.clearPointRoute
local releaseFacing = S.releaseFacing
local faceTowards = S.faceTowards
local setPathEditEnabled = S.setPathEditEnabled

-- =========================================================================
-- MACRO WAYPOINTS (2.5.0)
--
-- A macro is a recording of a run: where the character went, and what it did
-- along the way. Recording samples the root position on a distance/time budget
-- and logs every action input (attack click, Q, E, jump) against the sample it
-- happened at. Playback walks to the macro's start with the normal routed
-- pathfinding, then follows the samples in order, firing each action as its
-- anchor sample is reached.
--
-- WHY POSITIONS AND NOT HELD KEYS. The obvious reading of "record the inputs
-- and play them back" is to store W-down at 0.4s, W-up at 2.1s and re-send
-- them. That desynchronises within seconds in practice: a different framerate,
-- a slightly different spawn point, one clip on a doorframe, a knockback, any
-- of it shifts the character off the recorded line and every later input then
-- lands somewhere else, with no way to notice or recover. A position is
-- absolute - the replay steers back onto the recorded route after any
-- disturbance, and a macro recorded at 30fps plays correctly at 144. The
-- ACTIONS are still exactly the recorded inputs; they are anchored to where
-- along the route they were made rather than to a wall-clock offset, so they
-- stay attached to the thing they were aimed at.
-- =========================================================================

local ACTION_KEYS = {
    [Enum.KeyCode.Q] = "q",
    [Enum.KeyCode.E] = "e",
    [Enum.KeyCode.Space] = "jump",
}

local function macroCount(macro)
    return macro and macro.samples and #macro.samples or 0
end

-- One recorded moment: where the torso was, and which way it and the camera
-- were pointing.
--
-- The facing is stored as a LOOK VECTOR rather than an angle. Roblox's look
-- direction for yaw t is (-sin t, 0, -cos t) - the minus signs matter, and
-- 2.7.0 got them wrong, which pointed the replay a clean 180 degrees away from
-- where you had been standing. A unit vector has no sign convention to get
-- wrong on the way back out.
--
-- Both are recorded because they are different things. A humanoid keeps its
-- torso upright, so torso pitch is ~0 whatever you do with the mouse; the pitch
-- you actually aimed with lives on the camera.
local function sampleAt(root, t)
    local look = root.CFrame.LookVector
    local sample = {
        t = t,
        -- One decimal is well under the arrive radius and keeps the saved JSON
        -- to a sane size; a long macro is thousands of samples.
        x = math.floor(root.Position.X * 10 + 0.5) / 10,
        y = math.floor(root.Position.Y * 10 + 0.5) / 10,
        z = math.floor(root.Position.Z * 10 + 0.5) / 10,
        lx = math.floor(look.X * 1000 + 0.5) / 1000,
        ly = math.floor(look.Y * 1000 + 0.5) / 1000,
        lz = math.floor(look.Z * 1000 + 0.5) / 1000,
    }
    local camera = Workspace.CurrentCamera
    if camera then
        local cameraLook = camera.CFrame.LookVector
        sample.cx = math.floor(cameraLook.X * 1000 + 0.5) / 1000
        sample.cy = math.floor(cameraLook.Y * 1000 + 0.5) / 1000
        sample.cz = math.floor(cameraLook.Z * 1000 + 0.5) / 1000
    end
    return sample
end

-- The torso facing of a sample, or nil. Handles the 2.7.0 format, which stored
-- a bare yaw angle in `r`.
local function sampleLook(sample)
    if not sample then return nil end
    if sample.lx then
        local look = Vector3.new(sample.lx, sample.ly, sample.lz)
        if look.Magnitude > 0.01 then return look end
        return nil
    end
    if sample.r then
        return Vector3.new(-math.sin(sample.r), 0, -math.cos(sample.r))
    end
    return nil
end

local function samplePosition(macro, index)
    local sample = macro.samples[index]
    if not sample then return nil end
    return Vector3.new(sample.x, sample.y, sample.z)
end

-- ---------------------------------------------------------------- route draw
local function clearMacroRoute()
    if MC.routeFolder then MC.routeFolder:Destroy() end
    MC.routeFolder = nil
end

-- Draws the selected macro's route: a sparse line of dots plus a start orb.
-- Capped, and rebuilt only on selection / recording changes, never per frame.
local function renderMacroRoute(index)
    clearMacroRoute()
    if not CFG.macroShowRoute then return end
    local macro = MC.macros[index or MC.playIndex]
    local count = macroCount(macro)
    if count == 0 then return end

    local folder = Instance.new("Folder")
    folder.Name = "MacroRoute"
    folder.Parent = getVisualRoot()
    MC.routeFolder = folder

    local budget = 90
    local step = math.max(1, math.ceil(count / budget))
    for i = 1, count, step do
        local position = samplePosition(macro, i)
        local dot = Instance.new("Part")
        dot.Name = "MacroNode"
        dot.Shape = Enum.PartType.Ball
        dot.Size = Vector3.new(0.5, 0.5, 0.5)
        dot.Position = position
        dot.Anchored = true
        dot.CanCollide = false
        dot.CanQuery = false
        dot.CanTouch = false
        dot.CastShadow = false
        dot.Material = Enum.Material.Neon
        dot.Color = CFG.colorMacro
        dot.Transparency = 0.4
        dot.Parent = folder
    end

    local start = Instance.new("Part")
    start.Name = "MacroStart"
    start.Shape = Enum.PartType.Ball
    start.Size = Vector3.new(2.2, 2.2, 2.2)
    start.Position = samplePosition(macro, 1)
    start.Anchored = true
    start.CanCollide = false
    start.CanQuery = false
    start.CanTouch = false
    start.CastShadow = false
    start.Material = Enum.Material.Neon
    start.Color = Color3.fromRGB(120, 255, 160)
    start.Transparency = 0.2
    start.Parent = folder

    local billboard = Instance.new("BillboardGui")
    billboard.Size = UDim2.fromOffset(150, 26)
    billboard.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
    billboard.AlwaysOnTop = true
    billboard.Adornee = start
    billboard.Parent = start
    local label = Instance.new("TextLabel")
    label.Size = UDim2.fromScale(1, 1)
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.GothamBold
    label.Text = "START: " .. (macro.name or "macro")
    label.TextColor3 = Color3.fromRGB(150, 255, 190)
    label.TextStrokeTransparency = 0.2
    label.TextSize = 13
    label.Parent = billboard
end

-- ---------------------------------------------------------------- recording
-- ONLY the per-recording listener. The global bind listener lives in
-- MC.connections and must survive this: it used to share the table, so
-- starting a recording disconnected the record bind and it never fired again.
local function disconnectRecordInputs()
    for _, connection in ipairs(MC.recordConnections) do
        connection:Disconnect()
    end
    table.clear(MC.recordConnections)
end

local function stopRecording()
    if not MC.recording then return end
    MC.recording = false
    disconnectRecordInputs()

    local samples = MC.samples or {}
    MC.samples, MC.actions = nil, nil

    if #samples < 2 then
        heavyDebug("Macro", "Recording discarded: fewer than two position samples.")
        setMovementState("recording discarded (too short)")
        return
    end

    local macro = {
        name = string.format("Macro %d", #MC.macros + 1),
        samples = samples,
        actions = MC.lastActions or {},
        duration = samples[#samples].t,
        recordedAt = os.time(),
    }
    MC.lastActions = nil
    table.insert(MC.macros, macro)
    heavyDebug("Macro", string.format(
        "Recorded '%s': %d samples over %.1fs, %d action(s). Rename it in the panel, then Save.",
        macro.name, #macro.samples, macro.duration, #macro.actions))
    setMovementState(string.format("recorded %.0fs macro", macro.duration))
    renderMacroRoute(#MC.macros)
    if S.refreshMacroPanel then S.refreshMacroPanel() end
end

local function startRecording()
    if MC.recording then return end
    local character = LocalPlayer.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if not root then
        heavyDebug("Macro", "Cannot record: no character.")
        return
    end

    -- The bot must not be driving while you are. Recording is you playing.
    if RT.farmEnabled then
        RT.farmEnabled = false
        if S.setLoopButtonState then S.setLoopButtonState() end
        heavyDebug("Macro", "Loop switched off for recording - you are driving now.")
    end

    -- And the camera must be yours. The waypoint editor's free-fly camera
    -- detaches from the character entirely, so recording with it armed would
    -- capture a route the character never walked.
    if NAV.pathEditEnabled then
        setPathEditEnabled(false)
        if S.setFreecamButtonState then S.setFreecamButtonState() end
        heavyDebug("Macro", "Free-fly editor switched off: a macro is recorded from your own camera.")
    end

    MC.recording = true
    MC.recordStart = os.clock()
    MC.samples = { sampleAt(root, 0) }
    MC.actions = {}
    MC.lastActions = MC.actions
    MC.lastSampleTime = MC.recordStart
    MC.lastSamplePosition = root.Position

    disconnectRecordInputs()
    -- Actions are logged against the sample index they happened at, which is
    -- what keeps them attached to the place they were aimed at.
    table.insert(MC.recordConnections, UserInputService.InputBegan:Connect(function(input, processed)
        if processed or not MC.recording then return end
        local kind
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            kind = "click"
        else
            kind = ACTION_KEYS[input.KeyCode]
        end
        if not kind then return end
        table.insert(MC.actions, {
            t = os.clock() - MC.recordStart,
            i = #MC.samples,
            kind = kind,
        })
    end))

    heavyDebug("Macro", "RECORDING. Play the route normally; press the bind again to stop.")
    setMovementState("RECORDING macro")
    if S.refreshMacroPanel then S.refreshMacroPanel() end
end

local function toggleRecording()
    if MC.recording then stopRecording() else startRecording() end
end

-- Called every frame while recording, from the scanner loop (which runs whether
-- or not the bot is farming - and it is not, while you drive).
local function recordStep()
    if not MC.recording then return end
    local character = LocalPlayer.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if not root then return end

    local now = os.clock()
    local position = root.Position
    local moved = MC.lastSamplePosition and (position - MC.lastSamplePosition).Magnitude or math.huge
    if moved < CFG.macroSampleDistance and (now - MC.lastSampleTime) < CFG.macroSampleInterval then
        return
    end

    MC.lastSampleTime = now
    MC.lastSamplePosition = position
    table.insert(MC.samples, sampleAt(root, now - MC.recordStart))

    if #MC.samples >= CFG.macroMaxSamples then
        heavyDebug("Macro", "Sample limit reached; stopping the recording here.")
        stopRecording()
    end
end

-- ---------------------------------------------------------------- the list
local function removeMacro(index)
    if not MC.macros[index] then return end
    local macro = table.remove(MC.macros, index)
    heavyDebug("Macro", string.format("Deleted '%s'.", macro.name))
    if MC.playIndex > #MC.macros then MC.playIndex = 1 end
    clearMacroRoute()
    if S.refreshMacroPanel then S.refreshMacroPanel() end
end

local function moveMacro(index, delta)
    local target = index + delta
    if not MC.macros[index] or not MC.macros[target] then return end
    MC.macros[index], MC.macros[target] = MC.macros[target], MC.macros[index]
    if S.refreshMacroPanel then S.refreshMacroPanel() end
end

local function renameMacro(index, name)
    local macro = MC.macros[index]
    if not macro then return end
    macro.name = name
end

local function clearMacros()
    table.clear(MC.macros)
    MC.playIndex = 1
    clearMacroRoute()
    heavyDebug("Macro", "All macros for this map deleted.")
    if S.refreshMacroPanel then S.refreshMacroPanel() end
end

-- ---------------------------------------------------------------- playback
local function fireAction(kind, humanoid)
    if kind == "jump" then
        if humanoid then humanoid.Jump = true end
        return
    end
    if kind == "click" then
        local position = UserInputService:GetMouseLocation()
        pcall(function()
            VirtualInputManager:SendMouseButtonEvent(position.X, position.Y, 0, true, game, 0)
        end)
        task.delay(CFG.clickHoldDuration, function()
            pcall(function()
                VirtualInputManager:SendMouseButtonEvent(position.X, position.Y, 0, false, game, 0)
            end)
        end)
        return
    end
    local keyCode = kind == "q" and Enum.KeyCode.Q or kind == "e" and Enum.KeyCode.E or nil
    if not keyCode then return end
    pcall(function() VirtualInputManager:SendKeyEvent(true, keyCode, false, game) end)
    task.delay(CFG.abilityHoldDuration, function()
        pcall(function() VirtualInputManager:SendKeyEvent(false, keyCode, false, game) end)
    end)
end

local function resetPlaybackCursors()
    MC.playPhase = "approach"
    MC.playCursor = 1
    MC.playActionCursor = 1
    MC.playProgressDistance = nil
    MC.playProgressTime = os.clock()
    MC.playSkips = 0
    clearPointRoute()
end

local function stopPlayback(reason)
    if not MC.playing then return end
    MC.playing = false
    resetPlaybackCursors()
    clearPointRoute()
    heavyDebug("Macro", "Playback stopped: " .. tostring(reason or "asked to"))
    setMovementState("macro playback stopped")
    if S.refreshMacroPanel then S.refreshMacroPanel() end
end

local function playMacro(index)
    local macro = MC.macros[index]
    if not macro or macroCount(macro) < 2 then
        heavyDebug("Macro", "Nothing to play.")
        return
    end
    if MC.recording then stopRecording() end
    MC.playIndex = index
    MC.playing = true
    resetPlaybackCursors()
    renderMacroRoute(index)

    -- Playback needs the main loop running, since that is what drives the
    -- character each frame.
    if not RT.farmEnabled then
        RT.farmEnabled = true
        if S.setLoopButtonState then S.setLoopButtonState() end
        heavyDebug("Macro", "Loop switched on for playback.")
    end

    heavyDebug("Macro", string.format(
        "Playing '%s' (%d samples, %.1fs, %d actions). Walking to its start first.",
        macro.name, macroCount(macro), macro.duration or 0, #(macro.actions or {})))
    if S.refreshMacroPanel then S.refreshMacroPanel() end
end

local function advanceToNextMacro()
    local next = MC.playIndex + 1
    if next > #MC.macros then
        if not CFG.macroLoop then
            stopPlayback("reached the end of the list")
            return
        end
        next = 1
    end
    MC.playIndex = next
    resetPlaybackCursors()
    renderMacroRoute(next)
    heavyDebug("Macro", string.format("Next macro: '%s'.", MC.macros[next].name))
end

-- The playback branch of the main loop. Returns false once playback has ended.
local function runMacroPlayback(humanoid, root)
    if not MC.playing then return false end
    local macro = MC.macros[MC.playIndex]
    if not macro or macroCount(macro) < 2 then
        stopPlayback("the macro went away")
        return false
    end

    local now = os.clock()
    local rootPos = root.Position

    -- Phase 1: get to where the recording started, using the normal routed
    -- pathfinding - the character may be anywhere, and only the recorded part
    -- of the route is known to be walkable.
    if MC.playPhase == "approach" then
        local start = samplePosition(macro, 1)
        local distance, stuck = walkTowardPoint(humanoid, root, start)
        if distance <= CFG.macroStartRadius then
            MC.playPhase = "replay"
            MC.playCursor = 1
            MC.playActionCursor = 1
            MC.playProgressDistance = nil
            MC.playProgressTime = now
            MC.playSkips = 0
            clearPointRoute()
            heavyDebug("Macro", string.format("At the start of '%s'; replaying.", macro.name))
        elseif stuck then
            heavyDebug("Macro", string.format(
                "Cannot reach the start of '%s'; skipping it.", macro.name))
            advanceToNextMacro()
        else
            setMovementState(string.format("MACRO '%s' - to start (%.0f studs)", macro.name, distance))
        end
        return true
    end

    -- Phase 2: follow the recorded samples. Several may be consumed in one
    -- frame: the recording samples every 2.5 studs and the arrive radius is
    -- wider than that, which is what stops the replay crawling.
    local samples = macro.samples
    local count = #samples
    while MC.playCursor <= count do
        local point = samplePosition(macro, MC.playCursor)
        local delta = rootPos - point
        if Vector3.new(delta.X, 0, delta.Z).Magnitude > CFG.macroArriveRadius
            or math.abs(delta.Y) > 6 then
            break
        end
        MC.playCursor = MC.playCursor + 1
        MC.playProgressDistance = nil
    end

    -- Fire every action anchored at or before the sample we have reached. They
    -- go off in recorded order, so a click that came before a Q still does.
    local actions = macro.actions or {}
    while MC.playActionCursor <= #actions and actions[MC.playActionCursor].i < MC.playCursor do
        fireAction(actions[MC.playActionCursor].kind, humanoid)
        MC.playActionCursor = MC.playActionCursor + 1
    end

    if MC.playCursor > count then
        -- Anything left over fires at the end rather than being dropped.
        while MC.playActionCursor <= #actions do
            fireAction(actions[MC.playActionCursor].kind, humanoid)
            MC.playActionCursor = MC.playActionCursor + 1
        end
        heavyDebug("Macro", string.format("Finished '%s'.", macro.name))
        advanceToNextMacro()
        return true
    end

    -- Walk at the current sample directly: the recorded route is known to be
    -- walkable, so routing around it would be second-guessing the human who
    -- walked it.
    local target = samplePosition(macro, MC.playCursor)

    -- Facing: point the body the way it pointed when you recorded. faceTowards
    -- flattens to yaw, which is all a humanoid can do - it keeps its torso
    -- upright no matter where you look. The recorded pitch is kept in the file
    -- (see sampleAt) but is not applied to the body, because a body cannot
    -- express it.
    local look = CFG.macroFaceRecorded and sampleLook(macro.samples[MC.playCursor]) or nil
    if look then
        faceTowards(root, humanoid, rootPos + look * 12)
    else
        releaseFacing(humanoid)
    end
    if not NAV.lastIssuedMove
        or (NAV.lastIssuedMove - target).Magnitude > CFG.moveReissueThreshold then
        humanoid:MoveTo(target)
        NAV.lastIssuedMove = target
    end
    NAV.driving = true

    -- Stuck on one sample: skip it. A recorded route can be blocked by a door
    -- that is shut this run, or by having drifted below a ledge.
    local distance = (rootPos - target).Magnitude
    if not MC.playProgressDistance or distance < MC.playProgressDistance - 1.0 then
        MC.playProgressDistance = distance
        MC.playProgressTime = now
    elseif now - MC.playProgressTime >= CFG.macroGiveUpTime then
        MC.playCursor = MC.playCursor + 1
        MC.playSkips = MC.playSkips + 1
        MC.playProgressDistance = nil
        MC.playProgressTime = now
        humanoid.Jump = true
        if MC.playSkips >= CFG.macroSkipLimit then
            heavyDebug("Macro", string.format(
                "'%s' skipped %d samples in a row; giving up on it.", macro.name, MC.playSkips))
            advanceToNextMacro()
            return true
        end
        heavyDebugThrottled("macro_skip", 2.0, "Macro", string.format(
            "Stuck at sample %d/%d of '%s'; skipping ahead.", MC.playCursor, count, macro.name))
    end

    setMovementState(string.format("MACRO '%s' %d/%d", macro.name, MC.playCursor, count))
    return true
end

-- ---------------------------------------------------------------- bind + mode
local function setRecordBind(keyCode)
    MC.recordBind = keyCode
    MC.bindCapture = false
    heavyDebug("Macro", "Record bind set to " .. keyCode.Name .. ".")
    if S.refreshMacroPanel then S.refreshMacroPanel() end
end

-- "legacy" | "clone" | "macro". Legacy and Clone both fight and pathfind and
-- differ only in how they dodge; Macro replays a recording instead.
local function setMacroMode(mode)
    MC.mode = (mode == "macro" or mode == "clone") and mode or "legacy"
    S.setDodgeActive(MC.mode == "clone")
    if MC.mode ~= "macro" then
        if MC.playing then stopPlayback("switched to legacy waypoints") end
        if MC.recording then stopRecording() end
        clearMacroRoute()
    else
        -- The free-fly editor belongs to the waypoint system; it has no meaning
        -- in macro mode and would only get in the way of recording.
        if NAV.pathEditEnabled then
            setPathEditEnabled(false)
            if S.setFreecamButtonState then S.setFreecamButtonState() end
        end
        renderMacroRoute(MC.playIndex)
    end
    heavyDebug("Macro", "Mode: " .. MC.mode)
    if S.refreshMacroPanel then S.refreshMacroPanel() end
end

-- The record bind, and bind capture, live on one always-on listener.
local function startMacroInput()
    table.insert(MC.connections, UserInputService.InputBegan:Connect(function(input, processed)
        if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
        if MC.bindCapture then
            -- Escape cancels rather than binding itself.
            if input.KeyCode == Enum.KeyCode.Escape then
                MC.bindCapture = false
                if S.refreshMacroPanel then S.refreshMacroPanel() end
                return
            end
            setRecordBind(input.KeyCode)
            return
        end
        -- `processed` is true while a textbox has focus, which is exactly when
        -- the bind must not fire.
        if not processed and input.KeyCode == MC.recordBind then
            toggleRecording()
        end
    end))
end

-- ---------------------------------------------------------------- config i/o
-- Macros are plain data already (arrays of numbers and short strings), so they
-- round-trip through JSON as they are. A long macro is thousands of samples, so
-- the coordinates were rounded to one decimal at record time.
local function serializeMacros()
    local out = {}
    for _, macro in ipairs(MC.macros) do
        table.insert(out, {
            name = macro.name,
            samples = macro.samples,
            actions = macro.actions,
            duration = macro.duration,
            recordedAt = macro.recordedAt,
        })
    end
    return out
end

local function loadMacros(list)
    table.clear(MC.macros)
    MC.playIndex = 1
    clearMacroRoute()
    if type(list) ~= "table" then return 0 end
    for _, macro in ipairs(list) do
        if type(macro) == "table" and type(macro.samples) == "table" and #macro.samples >= 2 then
            table.insert(MC.macros, {
                name = type(macro.name) == "string" and macro.name or ("Macro " .. (#MC.macros + 1)),
                samples = macro.samples,
                actions = type(macro.actions) == "table" and macro.actions or {},
                duration = tonumber(macro.duration) or 0,
                recordedAt = tonumber(macro.recordedAt) or 0,
            })
        end
    end
    if S.refreshMacroPanel then S.refreshMacroPanel() end
    return #MC.macros
end

-- Save the recordings you have open into ANY map's slot, not only the one you
-- happen to have selected: you record a route once and file it where it belongs.
local function saveMacrosToMap(code)
    RT.macroData[code] = serializeMacros()
    heavyDebug("Macro", string.format("Filed %d macro(s) under %s.", #MC.macros, code))
    if S.saveMacroFile then S.saveMacroFile() end
    if S.refreshMacroPanel then S.refreshMacroPanel() end
end

-- Load a map's recordings and start playing them. Switching map through
-- setCurrentMap keeps the waypoints and keep list in step too.
local function playMapMacros(code)
    if S.setCurrentMap then S.setCurrentMap(code) end
    if #MC.macros == 0 then
        heavyDebug("Macro", string.format("%s has no macros saved.", code))
        setMovementState("no macros for " .. code)
        return
    end
    setMacroMode("macro")
    playMacro(1)
end

local function stopMacroSubsystem()
    if MC.recording then MC.recording = false end
    MC.playing = false
    disconnectRecordInputs()
    for _, connection in ipairs(MC.connections) do connection:Disconnect() end
    table.clear(MC.connections)
    clearMacroRoute()
end

S.startRecording = startRecording
S.stopRecording = stopRecording
S.toggleRecording = toggleRecording
S.recordStep = recordStep
S.removeMacro = removeMacro
S.moveMacro = moveMacro
S.renameMacro = renameMacro
S.clearMacros = clearMacros
S.playMacro = playMacro
S.stopPlayback = stopPlayback
S.runMacroPlayback = runMacroPlayback
S.setRecordBind = setRecordBind
S.setMacroMode = setMacroMode
S.startMacroInput = startMacroInput
S.serializeMacros = serializeMacros
S.loadMacros = loadMacros
S.renderMacroRoute = renderMacroRoute
S.clearMacroRoute = clearMacroRoute
S.stopMacroSubsystem = stopMacroSubsystem
S.saveMacrosToMap = saveMacrosToMap
S.playMapMacros = playMapMacros
end
