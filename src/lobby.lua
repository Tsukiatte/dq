-- lobby.lua - The loop outside the fight: queue a run from the lobby, replay it when it ends.
-- Module contract: receives the shared table S. Everything this module needs from
-- earlier modules is pulled into locals below; everything later modules need is
-- assigned onto S at the bottom. Load order is fixed by main.lua / build.py.
return function(S)
local RT = S.RT
local CFG = S.CFG
local Workspace = S.Workspace
local ReplicatedStorage = S.ReplicatedStorage
local LocalPlayer = S.LocalPlayer
local heavyDebug = S.heavyDebug

-- =========================================================================
-- AUTO QUEUE (4.12.5)
--
-- Read from the game's own lobby scripts (PlayerScripts.Ui.queue.* and the
-- Replay button, decompiled live on 2026-09-02; copies under game/lobby/).
-- The buttons are thin: every one of them ends in a remote call, so the loop
-- makes the same calls and never has to find a button on screen.
--
--   Lobby   remotes.createLobby:InvokeServer(map, difficulty, minLevel,
--           hardcore, private, waveDefence) -> true when the party exists,
--           then remotes.startDungeon:FireServer(). Map and difficulty are
--           the names on the lobby's own tiles ("Northern Lands",
--           "Nightmare"). The intro screen and the Play button are cosmetic;
--           the server does not need them pressed.
--   Level   workspace.dungeon.bossRoom.dungeonFinished (BoolValue) turns
--           true when the run is over, win or lose. The party owner
--           (PlaceManager.GetPlaceTeleportData().ownerId) may then send
--           remotes.replayDungeon:FireServer(data) with the same values the
--           game's Replay button collects, and the server rebuilds the run.
--           Anyone else simply waits to be returned to the lobby, where the
--           lobby half of this loop queues again.
--
-- Which place we are in comes from ReplicatedStorage.Utility.PlaceManager
-- ("Lobby" / "Level"), the game's own answer.
-- =========================================================================

local LB = {
    place = nil,
    placeAt = -math.huge,
    arrivedAt = nil,
    lastAttempt = -math.huge,
    attempts = 0,
    busy = false,
    status = "off",
    finishedSeenAt = nil,
    replayFired = false,
    placeManager = nil,
    farmAppliedFor = nil,
}

local function placeManager()
    if LB.placeManager ~= nil then return LB.placeManager or nil end
    local ok, pm = pcall(function()
        local util = ReplicatedStorage:FindFirstChild("Utility")
        local mod = util and util:FindFirstChild("PlaceManager")
        return mod and require(mod) or nil
    end)
    LB.placeManager = (ok and pm) or false
    return LB.placeManager or nil
end

-- "Lobby" or "Level" (a dungeon), from the game's own PlaceManager, with
-- the workspace values as a fallback.
local function placeName()
    local pm = placeManager()
    if pm and pm.GetPlaceName then
        local ok, name = pcall(pm.GetPlaceName)
        if ok and type(name) == "string" and name ~= "" then return name end
    end
    local dn = Workspace:FindFirstChild("dungeonName")
    if dn and dn.Value ~= "" then return "Level" end
    if Workspace:FindFirstChild("Lobby") then return "Lobby" end
    return "?"
end

-- The master switch, by place: off in the lobby (nothing to fight, and the
-- loop must not try), on in a dungeon. Applied once per place change, so a
-- hand on the switch inside a place is respected.
local function setFarm(on, why)
    if RT.farmEnabled == on then return end
    RT.farmEnabled = on
    if S.setLoopButtonState then pcall(S.setLoopButtonState) end
    heavyDebug("Queue", (on and "Autofarm on: " or "Autofarm off: ") .. why)
end

local function setStatus(text)
    if LB.status ~= text then
        LB.status = text
        if S.refreshQueuePanel then S.refreshQueuePanel() end
    end
end

local function remote(name)
    local folder = ReplicatedStorage:FindFirstChild("remotes")
    return folder and folder:FindFirstChild(name) or nil
end

-- The lobby half. Returns true if an attempt was started.
local function queueNow(reason)
    if LB.busy then return false end
    LB.busy = true
    LB.lastAttempt = os.clock()
    LB.attempts = LB.attempts + 1
    task.spawn(function()
        local ok, err = pcall(function()
            local create, start = remote("createLobby"), remote("startDungeon")
            if not create or not start then error("the lobby remotes are not present") end
            -- A party we already made (a retry after a start that did not
            -- teleport): just start it.
            local gui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
            local queueGui = gui and gui:FindFirstChild("queueGui")
            local info = queueGui and queueGui:FindFirstChild("lobbyInfo")
            if info and info.Visible then
                setStatus("party open; starting")
                start:FireServer()
                return
            end
            setStatus(string.format("creating %s, %s", tostring(CFG.autoQueueMap), tostring(CFG.autoQueueDifficulty)))
            local accepted = create:InvokeServer(CFG.autoQueueMap, CFG.autoQueueDifficulty,
                tonumber(CFG.autoQueueMinLevel) or 0, CFG.autoQueueHardcore == true,
                CFG.autoQueuePrivate == true, false)
            if accepted ~= true then
                setStatus("declined by the game")
                heavyDebug("Queue", string.format("The game declined the party (%s, %s): %s",
                    tostring(CFG.autoQueueMap), tostring(CFG.autoQueueDifficulty), tostring(accepted)))
                return
            end
            task.wait(CFG.autoQueueStartDelay)
            setStatus("starting")
            start:FireServer()
            heavyDebug("Queue", string.format("Queued %s on %s%s; start sent (%s).",
                tostring(CFG.autoQueueMap), tostring(CFG.autoQueueDifficulty),
                CFG.autoQueueHardcore and ", hardcore" or "", tostring(reason or "auto")))
        end)
        if not ok then
            setStatus("failed; will retry")
            heavyDebug("Queue", "Queueing threw: " .. tostring(err))
        end
        LB.busy = false
    end)
    return true
end

-- The dungeon half: exactly what the game's own Replay button sends.
local function collectDungeonData()
    local data = {}
    for _, name in ipairs({ "dungeonName", "dungeonProgress", "dungeonStarted", "hardcore" }) do
        local v = Workspace:FindFirstChild(name)
        if v and v:IsA("ValueBase") then data[name] = v.Value end
    end
    if data.hardcore ~= nil then data.isHardcore = data.hardcore end
    local dungeon = Workspace:FindFirstChild("dungeon")
    if dungeon then
        for _, child in ipairs(dungeon:GetChildren()) do
            if child:IsA("ValueBase") then data[child.Name] = child.Value end
        end
        local bossRoom = dungeon:FindFirstChild("bossRoom")
        if bossRoom then
            for _, child in ipairs(bossRoom:GetChildren()) do
                if child:IsA("ValueBase") then data[child.Name] = child.Value end
            end
        end
    end
    return data
end

local function isOwner()
    local pm = placeManager()
    if not (pm and pm.GetPlaceTeleportData) then return true end
    local ok, td = pcall(pm.GetPlaceTeleportData)
    if not ok or type(td) ~= "table" or td.ownerId == nil then return true end
    return td.ownerId == LocalPlayer.UserId
end

local function dungeonFinishedValue()
    local dungeon = Workspace:FindFirstChild("dungeon")
    local bossRoom = dungeon and dungeon:FindFirstChild("bossRoom")
    local v = bossRoom and bossRoom:FindFirstChild("dungeonFinished")
    if v and v:IsA("BoolValue") then return v end
    return nil
end

local function replayNow()
    local replay = remote("replayDungeon")
    if not replay then return false end
    local data = collectDungeonData()
    if not data.dungeonName then return false end
    LB.replayFired = true
    replay:FireServer(data)
    setStatus("replay sent")
    heavyDebug("Queue", "Run finished; replay sent for " .. tostring(data.dungeonName) .. ".")
    return true
end

local function lobbyTick(now)
    -- The place does not change mid-session; re-read it now and then in case
    -- the module was not ready at the first tick.
    if not LB.place or LB.place == "?" or now - LB.placeAt > 5 then
        LB.place, LB.placeAt = placeName(), now
    end
    if CFG.autoFarmByPlace and LB.place ~= LB.farmAppliedFor and (LB.place == "Lobby" or LB.place == "Level") then
        LB.farmAppliedFor = LB.place
        setFarm(LB.place == "Level", LB.place == "Level" and "in a dungeon" or "in the lobby")
    end
    if not CFG.autoQueue then
        setStatus("off")
        return
    end
    if LB.place == "Lobby" then
        LB.arrivedAt = LB.arrivedAt or now
        if LB.busy then return end
        local waited = now - LB.arrivedAt
        if waited < CFG.autoQueueDelay then
            setStatus(string.format("in the lobby; queueing in %.0fs", CFG.autoQueueDelay - waited))
            return
        end
        if now - LB.lastAttempt < CFG.autoQueueRetry then return end
        queueNow("auto")
    elseif LB.place == "Level" then
        LB.arrivedAt = nil
        if not CFG.autoQueueReplay or LB.replayFired then return end
        local v = dungeonFinishedValue()
        if v and v.Value then
            LB.finishedSeenAt = LB.finishedSeenAt or now
            if not isOwner() then
                setStatus("run finished; waiting for the game to return us")
                return
            end
            local left = CFG.autoQueueReplayDelay - (now - LB.finishedSeenAt)
            if left > 0 then
                setStatus(string.format("run finished; replay in %.0fs", left))
                return
            end
            replayNow()
        else
            setStatus("in a run")
        end
    else
        setStatus("waiting for the place to load")
    end
end

S.LB = LB
S.lobbyTick = lobbyTick
S.queueNow = queueNow
S.replayNow = replayNow
-- The lobby's own tiles, in its order, released ones only (2026-09-02).
S.QUEUE_MAPS = {
    "Desert Temple", "Winter Outpost", "Pirate Island", "King's Castle", "The Underworld",
    "Samurai Palace", "The Canals", "Steampunk Sewers", "Ghastly Harbor", "Orbital Outpost",
    "Volcanic Chambers", "Enchanted Forest", "Aquatic Temple", "Northern Lands", "Egg Island",
}
S.QUEUE_DIFFICULTIES = { "Easy", "Medium", "Hard", "Insane", "Nightmare" }
end
