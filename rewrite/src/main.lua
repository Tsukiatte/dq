-- main.lua - Startup and the heartbeat.
-- Module contract: receives the shared table S; imports from everything before it.
return function(S)
local CFG = S.CFG
local RT = S.RT
local RD = S.RD
local SCRIPT_VERSION = S.SCRIPT_VERSION
local SCRIPT_BUILD_DATE = S.SCRIPT_BUILD_DATE
local LocalPlayer = S.LocalPlayer
local RunService = S.RunService
local readerStart = S.readerStart
local readerTick = S.readerTick
local brainTick = S.brainTick
local drawTick = S.drawTick
local lobbyTick = S.lobbyTick
local autosaveTick = S.autosaveTick
local loadConfig = S.loadConfig
local startAutosave = S.startAutosave
local buildUI = S.buildUI
local releaseMover = S.releaseMover
local setMovementState = S.setMovementState
local heavyDebugThrottled = S.heavyDebugThrottled

print(string.format("DUNGEON AUTOFARM %s  |  build %s  |  %d hazards known by name", SCRIPT_VERSION, SCRIPT_BUILD_DATE, (function() local n = 0 for _ in pairs(S.TIMING) do n = n + 1 end return n end)()))

loadConfig()
startAutosave()
buildUI()
readerStart()
setMovementState("ready")

RT.mainConnection = RunService.Heartbeat:Connect(function(delta)
    if RT.destroyed then return end
    RT.frameDelta = delta or (1 / 60)
    local t0 = os.clock()
    local now = t0
    local ok, err = pcall(function()
        readerTick(now)
        lobbyTick(now)
        autosaveTick(now)
        if RT.farmEnabled then
            brainTick(now)
        else
            local c = LocalPlayer.Character
            releaseMover(c and c:FindFirstChildOfClass("Humanoid"), c and c:FindFirstChild("HumanoidRootPart"))
            setMovementState("off")
        end
        drawTick(now)
    end)
    if not ok then heavyDebugThrottled("main_err", 1, "Main", tostring(err)) end
    RT.tickMs = (RT.tickMs or 0) * 0.9 + (os.clock() - t0) * 1000 * 0.1
end)
end
