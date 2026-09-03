-- core.lua - Version, services, CFG tuning, shared state tables, runtime flags, debug logging.
-- Module contract: receives the shared table S. Everything this module needs from
-- earlier modules is pulled into locals below; everything later modules need is
-- assigned onto S at the bottom. Load order is fixed by main.lua / build.py.
return function(S)

--[[
================================================================================
    DUNGEON QUEST REBORN - ADVANCED AUTOFARM
================================================================================
    VERSION : 5.0.0
    BUILD   : 2026-09-02

    5.0.0 is the rewrite. The internals (reader, field, bosses, mover, dodge,
    pursuit, draw, tools, config, main) are new; uikit.lua, ui.lua, path.lua,
    streamer.lua and gamedata.lua are kept. The 4.11 code is frozen under
    legacy/4.11.3.

    VERSIONING RULES (semantic):
        MAJOR -> rewrite / breaking change to core architecture
        MINOR -> new feature, new UI element, new subsystem
        PATCH -> bugfix, tuning, constant change, refactor with no new behaviour

    Bump SCRIPT_VERSION and prepend a SCRIPT_CHANGELOG entry on EVERY edit.
================================================================================
]]

local SCRIPT_VERSION = "5.0.0"
local SCRIPT_BUILD_DATE = "2026-09-02"
local SCRIPT_CODENAME = "Northern Lands"

-- Newest entry first.
local SCRIPT_CHANGELOG = {
    { version = "5.0.0", date = "2026-09-02", notes = "The rewrite. Reading attacks comes first and comes from the game, not from being hit: every attack Model is tracked from the moment it appears and its precast is read every frame. Chris's real Northern Lands capture (six deaths, 136 seconds, 422 attacks) fixed the rule - the precast is visible from spawn, flashes to 0.17 at the instant the hit lands and fades out a fifth of a second later; the invisible hitBox that lingers for seven seconds afterwards is floor. Beams, mage shots and strikes all hurt once, at that flash, so the reader carries the measured flash time per attack and the dodge treats a telegraph as floor until shortly before it and floor again shortly after. Boss projectiles come from the boss remote with their exact path. The beam sweep is predicted from its last two beams. Movement is a tween along the floor at walking speed, or MoveTo, never faster and never airborne. The dodge scores a ring of candidates at the moments it would reach them and holds still when here is fine. Bosses are fought from ability range and never in melee. The UI, the waypoint editor, streamer mode and the config files are unchanged." },
}

-- ---------------------------------------------------------------- services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local UserInputService = game:GetService("UserInputService")
local PathfindingService = game:GetService("PathfindingService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local LocalPlayer = Players.LocalPlayer

-- ---------------------------------------------------------------- shared tables
-- One table per subsystem, shared through S so every module sees the same
-- values. A bare local copied into another module would go stale.
local CFG = {}   -- tuning; everything the sliders and toggles edit
local RT = {}    -- runtime flags and handles
local UI = {}    -- widgets the internals write to
local SM = {}    -- streamer mode (streamer.lua)
local NAV = {}   -- pursuit and the manual waypath (pursuit.lua, path.lua)
local HZ = {}    -- the reader: attacks, enemies, hits, the book
local LD = {}    -- low detail
local DG = {}    -- the dodge
local ZN = {}    -- hand-drawn zones
local PC = {}    -- reader statistics the Attacks panel shows

-- ---------------------------------------------------------------- CFG: combat
CFG.faceTarget = true
CFG.attackRange = 10             -- planar distance at which the basic attack fires (mobs only)
CFG.minimumAttackRange = 3
CFG.maximumAttackRange = 25
CFG.targetMode = "closest"       -- closest | lowest HP | highest HP
CFG.targetHpRange = 150.0
CFG.attackMethod = "auto"        -- auto | tool | click
CFG.autoClickEnabled = true
CFG.clickAtCursor = false
CFG.clickInterval = 0.1
CFG.clickHoldDuration = 0.02
CFG.abilityInterval = 0.1
CFG.abilityHoldDuration = 0.04
CFG.abilityRadiusEnabled = true
CFG.abilityRadius = 30
CFG.minAbilityRadius = 5
CFG.maxAbilityRadius = 60
CFG.showAbilityRadius = false
CFG.bossStandoff = 26            -- studs from a boss, inside the ability radius
CFG.bossSweepStandoff = 45       -- studs from a boss while its beam sweep is firing
CFG.enemyMeleeReach = 5          -- a mob's swing beyond its body, when it carries no meleeDistance
CFG.inRangeDeadband = 1.5

-- ---------------------------------------------------------------- CFG: movement
CFG.pathfindingEnabled = true
CFG.dodgeEnabled = true
CFG.moveMode = "tween"           -- tween | walk (steer and velocity are read as walk)
CFG.moveSpeed = 16               -- studs per second the tween walks at; the game's walk speed
CFG.dodgeSpeed = 16              -- studs per second while dodging; never above 16 sustained
CFG.moveArriveRadius = 1.0
CFG.wallPadding = 2.0            -- navmesh agent radius
CFG.minimumWallPadding = 1.0
CFG.maximumWallPadding = 6.0
CFG.maxClimbHeight = 7.0
CFG.maxStepHeight = 2.4
CFG.pathRecomputeInterval = 1.0
CFG.pointGiveUpTime = 6.0
CFG.followPath = true
CFG.loopPath = false
CFG.waypointClearRadius = 16.0
CFG.minWaypointClearRadius = 4.0
CFG.maxWaypointClearRadius = 60.0
CFG.freecamSpeed = 90
CFG.freecamLookSensitivity = 0.35
CFG.recoveryEnabled = false
CFG.recoveryStuckRadius = 10.0
CFG.recoveryStuckTime = 2.5
CFG.recoveryWaypoints = 2
CFG.recoveryEscalation = 2
CFG.recoveryRepeatWindow = 12.0
CFG.recoveryMaxTime = 25.0
CFG.recoveryArriveRadius = 6.0
CFG.autoDetectMap = true

-- ---------------------------------------------------------------- CFG: reader
CFG.usePrecast = true            -- read attack Models (off: only projectiles and enemies are dodged)
CFG.showPrecast = true           -- draw the attacks the reader considers live
CFG.safeZoneEnabled = true
CFG.damageBrickDetectionRange = 120   -- studs: attacks further out are tracked but not scored or drawn
CFG.minimumDamageBrickRange = 10
CFG.maximumDamageBrickRange = 150
CFG.damageBrickClearance = 2.5   -- studs kept from the edge of every attack shape
CFG.preemptiveClearance = 6.5    -- soft ring beyond that, for ranking where to stand
CFG.projectileLookahead = 1.2    -- seconds of a moving part's travel treated as its strip
CFG.hitAfter = 0.25              -- an attack hurts until this long after its flash
CFG.fadeLinger = 0.25            -- an attack of unknown timing hurts until this long after its fade
CFG.hookRemotes = false
CFG.diagnoseAttacks = false
CFG.diagnoseFile = "DungeonAutofarm_attacklog.txt"
CFG.diagnoseMax = 900

-- ---------------------------------------------------------------- CFG: dodge
CFG.dodgeReach = 18
CFG.dodgeRings = 3
CFG.dodgeRays = 24
CFG.dodgeProbe = 0
CFG.dodgeLead = 0.45             -- an attack hurts from this long before its flash (the Lead slider)
CFG.dodgeDwell = 1.0
CFG.dodgeMoveAt = 0.15
CFG.dodgeTurnCost = 0.1
CFG.dodgeApproachWeight = 0.012
CFG.dodgeStepProbe = 5
CFG.dodgeCornerCost = 0.35
CFG.dodgeDistanceCost = 0.006
CFG.dodgeSampleSpacing = 2.5
CFG.dodgeMaxClimb = 3.0
CFG.dodgeMaxDrop = 10.0
CFG.dodgeValidate = 12           -- best candidates checked against the floor and the walls
CFG.dodgeManual = false
CFG.dodgeShowField = true
CFG.dodgeShowTarget = true
CFG.dodgeShowRange = true
CFG.dodgeInterval = 0.08         -- seconds between decisions while nothing is on us

-- ---------------------------------------------------------------- CFG: visuals
CFG.showWalls = false
CFG.showPursuitRoute = true
CFG.showEscapeRoute = true
CFG.showWaypoints = true
CFG.showHud = true
CFG.maxHazardOverlays = 28
CFG.visualRefreshInterval = 0.2
CFG.colorTelegraph = Color3.fromRGB(255, 30, 30)
CFG.colorTelegraphPending = Color3.fromRGB(255, 176, 40)
CFG.colorWall = Color3.fromRGB(40, 220, 90)
CFG.colorHitbox = Color3.fromRGB(0, 220, 255)
CFG.colorAbilityRadius = Color3.fromRGB(170, 100, 255)
CFG.colorPursuit = Color3.fromRGB(0, 160, 255)
CFG.colorEscape = Color3.fromRGB(255, 170, 0)
CFG.colorWaypoint = Color3.fromRGB(255, 190, 40)
CFG.colorDodgeTarget = Color3.fromRGB(255, 255, 255)
CFG.colorDodgeSafe = Color3.fromRGB(60, 220, 120)
CFG.colorDodgeDanger = Color3.fromRGB(255, 70, 70)
CFG.accentColor = Color3.fromRGB(255, 182, 38)
CFG.zoneDefaultRadius = 12.0
CFG.zoneDefaultHeight = 14.0
CFG.zoneMinRadius = 2.0
CFG.zoneMaxRadius = 120.0
CFG.lowDetailBudget = 400
CFG.lowDetailKillEffects = true

-- ---------------------------------------------------------------- CFG: interface
CFG.guiBlur = 14
CFG.guiDim = 0.35
CFG.menuKey = "RightShift"
CFG.panelAutofarm = true
CFG.panelRoutes = true
CFG.panelAccount = true
CFG.panelConfigs = true
CFG.panelAttacks = true
CFG.configFile = "DungeonAutofarm_configs.json"
CFG.accountRank = "DEVELOPER"
CFG.enemyScanInterval = 0.35

-- ---------------------------------------------------------------- RT
RT.farmEnabled = true
RT.destroyed = false
RT.mode = "clone"                -- "clone" = Dodge, "legacy" = Pathfind (both names kept for saved configs)
RT.autoQEnabled = true
RT.autoEEnabled = true
RT.renderPathEnabled = true
RT.renderHazardsEnabled = true
RT.renderHitboxEnabled = true
RT.lastQTime = -math.huge
RT.lastETime = -math.huge
RT.lastClickTime = -math.huge
RT.gameSpecificAttackMethod = nil
RT.abilityHook = nil             -- harness: called with the KeyCode whenever an ability is pressed
RT.mainConnection = nil
RT.enemyScanConnection = nil
RT.hudConnection = nil
RT.healthConnection = nil
RT.animatorConnection = nil
RT.indexConnections = {}
RT.scriptGui = nil
RT.blurEffect = nil
RT.visualRoot = nil
RT.pinnedWindows = {}
RT.menuBindCapture = false
RT.configs = {}
RT.mapData = {}
RT.attackData = {}
RT.zoneData = {}
RT.frameDelta = 1 / 60
RT.movementStatus = ""
RT.lastHealth = nil
RT.respawnedAt = -math.huge
RT.deaths = 0
-- Read by gamedata.lua's seed tables; unused by the reader (timing is not learned).
RT.armDelays = {}
RT.armSpans = {}
RT.armLongLived = {}
RT.cfgDefaults = {}

-- ---------------------------------------------------------------- maps
local MAP_CODES = { "DT", "WO", "PI", "KC", "TU", "SP", "TC", "GH", "SS", "OO", "VC", "AT", "EF", "NL" }
local MAP_LABELS = {
    DT = "Desert Temple",     WO = "Winter Outpost",   PI = "Pirate Island",
    KC = "King's Castle",     TU = "The Underworld",   SP = "Samurai Palace",
    TC = "The Canals",        GH = "Ghastly Harbor",   SS = "Steampunk Sewers",
    OO = "Orbital Outpost",   VC = "Volcanic Chambers", AT = "Aquatic Temple",
    EF = "Enchanted Forest",  NL = "Northern Lands",
}
RT.currentMap = "NL"

-- ---------------------------------------------------------------- UI hooks
UI.movementStateLabel = nil
UI.damageBrickCountLabel = nil
UI.telegraphFeedList = nil
UI.pickerButton = nil
UI.pathEditButton = nil
UI.pathListFrame = nil
UI.keepPickerButton = nil
UI.hudTarget = "None"
UI.hudTargetHp = ""
UI.hudEnemyCount = 0

-- ---------------------------------------------------------------- NAV (pursuit.lua fills the rest; path.lua reads these)
NAV.waypath = {}                 -- array of Vector3, in visit order
NAV.pathIndex = 1
NAV.pathFolder = nil
NAV.pathMarkers = {}
NAV.showRadius = false
NAV.pathEditEnabled = false
NAV.pathEditConnections = {}
NAV.freecamCFrame = nil
NAV.freecamYaw = 0
NAV.freecamPitch = 0
NAV.freecamKeys = {}
NAV.freecamLooking = false
NAV.savedCameraType = nil
NAV.farmWasEnabled = false
NAV.forceRescan = false
NAV.cachedEnemy = nil
NAV.cachedEntry = nil
NAV.cachedEnemyCount = 0
NAV.benched = {}
NAV.recovery = nil
NAV.stuckAnchor = nil
NAV.stuckAnchorTime = 0
NAV.lastRecoveryEnd = -math.huge
NAV.lastRecoveryIndex = nil
NAV.driving = false
NAV.walkAnchor = nil

-- ---------------------------------------------------------------- HZ (reader.lua fills the rest)
HZ.attacks = {}                  -- every tracked attack record, live
HZ.detected = {}                 -- the ones that can hurt now or within a second (the HUD count)
HZ.enemies = {}                  -- { model, root, humanoid, name, melee, style, boss, extent }
HZ.hitLog = {}
HZ.lastHitName = nil
HZ.lastHitAt = -math.huge
HZ.attackBook = {}               -- per-map records { name, enabled, hits, damage }
HZ.bookByName = {}
HZ.learnedNames = {}             -- lowercased part names the picker added as attacks
HZ.ownNames = {}                 -- lowercased names that are our own effects
HZ.pickerEnabled = false
HZ.ownPickerEnabled = false
HZ.pickerMouse = nil
HZ.pickerConnections = {}
HZ.stats = {}                    -- per name: n, flash times, inside/hit buckets (capture)

LD.enabled = false
LD.keepNames = {}
LD.hidden = {}
LD.disabledEffects = {}
LD.pickerEnabled = false

DG.active = false
DG.target = nil
DG.targetReason = ""
DG.dangerHere = 0
DG.gapWait = false
DG.pursuitBlocked = false
DG.heading = nil
DG.headingTime = 0
DG.goal = nil                    -- where pursuit would like to be (the approach pull)
DG.cands = {}
DG.lastDecision = -math.huge

ZN.defs = {}
ZN.pickerEnabled = false
ZN.draftShape = "circle"
ZN.draftRadius = 0
ZN.root = nil
ZN.dragging = false

PC.failed = false
PC.received = 0
PC.total = 0
PC.zones = 0

-- ---------------------------------------------------------------- debug
local DEBUG_OFF = 0
local DEBUG_NORMAL = 1
local DEBUG_VERBOSE = 2
RT.debugLevel = DEBUG_NORMAL
local debugLastValues = {}
local debugThrottleClocks = {}
local sliderConnections = {}

local function heavyDebug(category, message, level)
    if RT.debugLevel < (level or DEBUG_NORMAL) then return end
    print(string.format("[HEAVY_DEBUG][v%s][%s][%.3f] %s", SCRIPT_VERSION, category, os.clock(), tostring(message)))
end
local function heavyDebugThrottled(key, interval, category, message, level)
    local now = os.clock()
    local last = debugThrottleClocks[key]
    if last and (now - last) < interval then return end
    debugThrottleClocks[key] = now
    heavyDebug(category, message, level)
end
local function heavyDebugOnChange(key, value, category, message, level)
    if debugLastValues[key] == value then return end
    debugLastValues[key] = value
    heavyDebug(category, message, level)
end
local function setMovementState(text)
    RT.movementStatus = text
    if UI.movementStateLabel then UI.movementStateLabel.Text = text end
end
local function getVisualRoot()
    local root = RT.visualRoot
    if root and root.Parent then return root end
    root = Instance.new("Folder")
    root.Name = "DungeonAutofarmVisuals"
    RT.visualRoot = root
    root.Parent = Workspace
    return root
end
local function printVersionBanner()
    print(string.rep("=", 62))
    print(string.format("  DUNGEON AUTOFARM  |  v%s \"%s\"  |  build %s", SCRIPT_VERSION, SCRIPT_CODENAME, SCRIPT_BUILD_DATE))
    print(string.rep("=", 62))
end
local function printChangelog()
    printVersionBanner()
    print("  CHANGELOG (newest first):")
    for _, entry in ipairs(SCRIPT_CHANGELOG) do
        print(string.format("   - v%-8s %s  %s", entry.version, entry.date, entry.notes))
    end
    print(string.rep("=", 62))
end

-- Snapshot of every tuning value, for Reset defaults and the config whitelist.
for key, value in pairs(CFG) do RT.cfgDefaults[key] = value end

-- ---------------------------------------------------------------- exports
S.SCRIPT_VERSION = SCRIPT_VERSION
S.SCRIPT_BUILD_DATE = SCRIPT_BUILD_DATE
S.SCRIPT_CODENAME = SCRIPT_CODENAME
S.SCRIPT_CHANGELOG = SCRIPT_CHANGELOG
S.Players = Players
S.RunService = RunService
S.Workspace = Workspace
S.ReplicatedStorage = ReplicatedStorage
S.Lighting = Lighting
S.UserInputService = UserInputService
S.PathfindingService = PathfindingService
S.VirtualInputManager = VirtualInputManager
S.CollectionService = CollectionService
S.TweenService = TweenService
S.LocalPlayer = LocalPlayer
S.CFG = CFG
S.RT = RT
S.UI = UI
S.SM = SM
S.NAV = NAV
S.HZ = HZ
S.LD = LD
S.DG = DG
S.ZN = ZN
S.PC = PC
S.MAP_CODES = MAP_CODES
S.MAP_LABELS = MAP_LABELS
S.DEBUG_OFF = DEBUG_OFF
S.DEBUG_NORMAL = DEBUG_NORMAL
S.DEBUG_VERBOSE = DEBUG_VERBOSE
S.debugLastValues = debugLastValues
S.debugThrottleClocks = debugThrottleClocks
S.sliderConnections = sliderConnections
S.heavyDebug = heavyDebug
S.heavyDebugThrottled = heavyDebugThrottled
S.heavyDebugOnChange = heavyDebugOnChange
S.setMovementState = setMovementState
S.getVisualRoot = getVisualRoot
S.printVersionBanner = printVersionBanner
S.printChangelog = printChangelog
end
