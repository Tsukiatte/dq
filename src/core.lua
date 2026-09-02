-- core.lua - Version, services, CFG tuning, shared state tables, runtime flags, debug logging.
-- Module contract: receives the shared table S. Everything this module needs from
-- earlier modules is pulled into locals below; everything later modules need is
-- assigned onto S at the bottom. Load order is fixed by main.lua / build.py.
return function(S)

--[[
================================================================================
    DUNGEON QUEST REBORN - ADVANCED AUTOFARM
================================================================================
    VERSION : 2.3.0
    BUILD   : 2026-09-01

    VERSIONING RULES (semantic):
        MAJOR -> rewrite / breaking change to core architecture
        MINOR -> new feature, new UI element, new subsystem
        PATCH -> bugfix, tuning, constant change, refactor with no new behaviour

    Bump SCRIPT_VERSION and prepend a SCRIPT_CHANGELOG entry on EVERY edit.
================================================================================
]]

local SCRIPT_VERSION = "2.3.0"
local SCRIPT_BUILD_DATE = "2026-09-01"
local SCRIPT_CODENAME = "Fieldnotes"

-- Newest entry first.
local SCRIPT_CHANGELOG = {
    { version = "2.3.0", date = "2026-09-01", notes = "Trial runs: with Trial Run on, every hit taken is matched to the parts that appeared around the player just before it, and those are written into a named Attack Book (what the attack and its warning look like) that drives detection from then on; panel to rename / disable / delete entries, Save writes it to the config. Projectile prediction: moving hazards are dodged along the strip they will sweep, not where they are, and escape candidates are added sideways out of their path. Enemy attacks are always highlighted now, with a billboard name tag and a predicted-path line on moving ones." },
    { version = "2.2.0", date = "2026-09-01", notes = "Recovery: when the character loiters in a 10-stud area for 2.5s while trying to move, it walks the nearest stretch of the manual path (routed through the navmesh, jumping allowed) and then returns to pursuit; re-sticking soon after walks further. Path waypoints are now reached by navmesh route, not a straight steer, and an unreachable one is skipped. Terrain: the shin-height steering probe no longer treats ramps and steps as walls (that is what pinned the bot at the foot of every incline), drops are allowed while climbs are capped at a jump, and a stall on a navmesh route hops too. Q/E can be limited to an enemy radius (button + slider + drawn radius). Own ability effects are recognised by timing against our own casts and learned by name (saved), with a Pick Own FX picker; the bot no longer dodges its own slashes. Attacks always click; the guessed remote is never fired." },
    { version = "2.1.0", date = "2026-09-01", notes = "Lag spike fix. The scanner walked Workspace:GetDescendants() and classified every part three times a second, with a full cache flush every 4s: a spike every 0.35s from startup. Replaced by a world index built once in slices and kept current by DescendantAdded/Removing, with a bounded round-robin re-check per frame. The __namecall hook allocated a table on every method call in the client (GC pressure); rewritten allocation-free, auto-removed after 3 minutes, restored on Destruct. Telegraph feed rows pooled, path node writes diffed, RespectCanCollide tested once instead of per cast, all visuals under one folder, marker clearing incremental, hitbox adornee survives respawn." },
    { version = "2.0.0", date = "2026-09-01", notes = "Split into src/ modules (core, hazards, nav, path, streamer, config, ui, main) wired through one shared table; loose runtime flags moved into RT; loader main.lua and single-file bundle DungeonAutofarm.lua built by tools/build.py. tools/check.py parses every module with a real Lua parser and audits every name, import and export; tools/smoke.py runs startup under a stub Roblox. No behaviour change." },
    { version = "1.21.0", date = "2026-09-01", notes = "Path editor: Save/Load/Clear buttons in the panel, a clear-radius slider and a Show Radius toggle, and right-drag look now locks the mouse so the camera actually turns. Waypoints clear as the player passes within the radius (next-in-order only; the saved config keeps them all). The path is also used as guidance to walk out when the bot gets stuck on an unreachable enemy." },
    { version = "1.20.0", date = "2026-09-01", notes = "Gates replaced by a hardcoded waypoint PATH: an Edit Path mode flies a free camera (WASD+EQ, right-drag look) and left-click drops ordered waypoints with numbered billboards; a panel reorders/deletes them; saved to the config as coordinates. The bot walks the path when idle. Show Walls now shows every invisible wall (no cap). Fixed the telegraph feed stacking 'No active hazards' rows." },
    { version = "1.19.0", date = "2026-09-01", notes = "Gates are now marked BY HAND (Mark Gates picker, drawn blue) instead of auto-detected; marks save to the config and reload. The push through a dropped gate fires off the gate actually dropping, not an enemy-count guess. FPS: the two full-map scans are merged into one traversal. Invisible walls the navmesh ignores are now steered around instead of walked into." },
    { version = "1.18.0", date = "2026-09-01", notes = "Pushes through where a barrier just dropped when a section unlocks (detected by an enemy-count jump up from cleared, so a boss spawning minions does not trip it). New Show Walls toggle draws barriers blue and invisible collision walls green. FPS: the 1.17 openness steering no longer ray-scans every heading each frame, and barrier/wall classification is memoised." },
    { version = "1.17.0", date = "2026-09-01", notes = "Seeks section barriers when idle (the way forward), steering now runs toward the most open heading instead of the first barely-clear one, and three more stutter sources removed: rigid facing snap eased, per-frame MoveTo spam in direct mode and the in-range shuffle both gated." },
    { version = "1.16.0", date = "2026-09-01", notes = "Stutter fix: path markers pooled and capped instead of rebuilt each recompute, steering fan cached, facing moved to an AlignOrientation constraint." },
    { version = "1.15.1", date = "2026-09-01", notes = "Fixed 1.15.0 regression: writing CFrame every frame to face the target zeroed the assembly velocity, pinning the character in place on a valid path. Velocity is now carried across the write." },
    { version = "1.15.0", date = "2026-09-01", notes = "Character now holds its aim on the current target at all times, including while approaching, circling and dodging." },
    { version = "1.14.0", date = "2026-09-01", notes = "Telegraphs also detected by appearance, not just name; Effects/Props folders no longer veto them. Standing still without dodging blacklists the location itself." },
    { version = "1.13.0", date = "2026-09-01", notes = "Headings that produce no movement are blacklisted with a widening arc and a timer, so steering stops re-picking a direction that just failed." },
    { version = "1.12.1", date = "2026-09-01", notes = "Fixed syntax error from the 1.12.0 rename: learnedTelegraphNames was a table key and became an invalid dotted key. Also fixed the matching config read." },
    { version = "1.12.0", date = "2026-09-01", notes = "Steering probe no longer treats a wall hidden behind a non-collidable part as clear; now a two-height capsule test with heading commitment. Locals grouped into NAV and HZ tables, 192 to 154." },
    { version = "1.11.0", date = "2026-09-01", notes = "Direct walking is now the unconditional fallback with obstacle steering. Enemies are benched only after walking at them gains no ground, instead of on a failed path." },
    { version = "1.10.0", date = "2026-09-01", notes = "Detects places with no usable navmesh via a short probe and switches to stepped direct walking instead of benching every enemy. Fallback range 35 to 150 studs." },
    { version = "1.9.0", date = "2026-09-01", notes = "Config save/load to JSON with auto-load on startup. Streamer flicker fixed via property signals. Fixed 1.8.0 bench regression that retried a failed path every frame." },
    { version = "1.8.0", date = "2026-09-01", notes = "NoPath recovery: retry ladder with a slimmer agent and progressively nearer aim points, direct-walk fallback for close targets, and an unreachable-enemy bench so the scanner moves on." },
    { version = "1.7.1", date = "2026-09-01", notes = "Nametag trim is now detected by colour, not class, so gold Frames are caught and not just UIStroke. Also covers billboards adorned from PlayerGui." },
    { version = "1.7.0", date = "2026-09-01", notes = "Streamer Mode gains Coins and Gems fields plus a nametag trim colour, auto-detected from UIStroke inside character billboards." },
    { version = "1.6.1", date = "2026-09-01", notes = "Fixed SM.UI.statusLabel double-prefix from the 1.6.0 rename. Added Dump GUI candidates button for reporting what a game actually uses." },
    { version = "1.6.0", date = "2026-09-01", notes = "Fixed the 200-register compile error by grouping locals into CFG/UI/SM tables. Streamer Mode can now hide telemetry overlays automatically and any GUI element by click." },
    { version = "1.5.0", date = "2026-09-01", notes = "Streamer Mode: local cosmetic masking of username, HP, VIP title, EXP, level, tag colours and avatar image, across both the game GUI and the overhead nametag. Client-side only." },
    { version = "1.4.0", date = "2026-09-01", notes = "Performance pass. Memoised classifiers, single scanner traversal, visualisers moved off the per-frame path, cheaper escape search, no per-frame string building." },
    { version = "1.3.0", date = "2026-09-01", notes = "Click-to-mark telegraph picker with name learning. Fully transparent parts no longer count. Escape points validated against the navmesh and followed as a path. Hazard avoidance now planar (X/Z only)." },
    { version = "1.2.1", date = "2026-09-01", notes = "Fixed invalid Enum.Font.GothamItalic in the empty-telegraph label. It threw every tick the hazard list was empty, aborting the loop before pursuit." },
    { version = "1.2.0", date = "2026-09-01", notes = "Main loop no longer swallows errors (xpcall + traceback). Added branch tracing, live Movement state readout, 3-level debug toggle. Character refetched each tick." },
    { version = "1.1.0", date = "2026-09-01", notes = "Added version tracking system + on-screen version badge (click to dump changelog)." },
    { version = "1.0.0", date = "2026-09-01", notes = "Baseline. Removed flawed Phase 2 straight-line shortcut to force robust Navmesh routing." },
}

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local PathfindingService = game:GetService("PathfindingService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local CollectionService = game:GetService("CollectionService")

if _G.DungeonAutofarmDestruct then
    pcall(_G.DungeonAutofarmDestruct)
end

_G.DungeonAutofarmVersion = SCRIPT_VERSION

-- Grouped into tables rather than kept as separate locals: Luau caps a function
-- scope at 200 registers and the main chunk had grown past it.
-- CFG = tuning, UI = widget references, SM = streamer mode state.
local CFG = {}
local UI = {}
local SM = {}
local NAV = {}
local HZ = {}
-- RT = loose runtime flags and handles (farmEnabled, debugLevel, connections...)
-- that used to be bare locals. They live in a table so every module sees the
-- same value; a bare local copied into another module would go stale.
local RT = {}

-- Configuration
RT.farmEnabled = true
-- Keep the character turned toward its target at all times. Turning is taken
-- off the Humanoid, which otherwise faces whichever way it is walking, so the
-- bot stays pointed at the enemy while approaching, circling or dodging.
CFG.faceTarget = true

CFG.attackRange = 10
CFG.safeDistance = 8
CFG.wallPadding = 2.0
CFG.clickInterval = 0.1
CFG.clickHoldDuration = 0.02
CFG.abilityInterval = 0.1
CFG.abilityHoldDuration = 0.04

CFG.damageBrickDetectionRange = 120
CFG.damageBrickClearance = 3.5
CFG.preemptiveClearance = 6.5

-- Hazard avoidance is planar: a telegraph is dodged on X/Z regardless of how far
-- above or below the player it sits. Set false to restore height gating.
CFG.hazardIgnoreVertical = true

-- A telegraph faded to fully invisible has resolved and no longer threatens.
CFG.telegraphTransparencyCutoff = 0.99
-- A part that appeared this recently is very likely an attack marker rather
-- than scenery, which is the strongest signal the shape heuristic has.
CFG.telegraphRecentSpawnWindow = 10.0

-- Escape routing. Candidates are ranked cheaply, then the top few are validated
-- against the real navmesh, because a straight MoveTo walks into concave geometry.
CFG.escapeRecomputeInterval = 0.4
CFG.escapeValidationBudget = 6
CFG.escapeWaypointAdvanceDistance = 3.5

CFG.minimumAttackRange = 3
CFG.maximumAttackRange = 25
CFG.minimumSafeDistance = 3
CFG.maximumSafeDistance = 25
CFG.minimumDamageBrickRange = 10
CFG.maximumDamageBrickRange = 150
CFG.minimumWallPadding = 1.0
CFG.maximumWallPadding = 6.0

CFG.enemyScanInterval = 0.35
CFG.damageBrickCatalogRefreshInterval = 0.5

-- Visualiser and inspector refresh rate. These rebuild Instances, so they run on
-- their own clock instead of every Heartbeat.
CFG.visualRefreshInterval = 0.2
CFG.telegraphFeedRefreshInterval = 0.25
CFG.hitboxVisualRefreshInterval = 0.25

-- Ownership and map-geometry answers are stable per part but expensive to derive,
-- so they are memoised and the cache is dropped wholesale on this interval.
CFG.classificationCacheLifetime = 4.0
-- An enemy the navmesh cannot reach is benched for this long so the scanner
-- moves on. Below this range a failed path falls back to walking straight at it.
CFG.unreachableCooldown = 10.0
CFG.directWalkFallbackRange = 150.0

-- Some places have no usable navmesh at all: every ComputeAsync returns NoPath
-- regardless of distance. Rather than bench every enemy on the map, that state
-- is detected with a short probe and the bot switches to walking directly.
CFG.navmeshProbeDistance = 8.0
CFG.navmeshFailureThreshold = 3
CFG.navmeshRetestInterval = 20.0
CFG.directWalkStepLength = 12.0
CFG.steerProbeDistance = 14.0
-- How far ahead the navmesh follower checks for a solid the mesh did not bake in
-- (an invisible wall). Short, so it only reacts to something genuinely in the way.
CFG.wallProbeDistance = 6.0
-- How long a chosen steering deviation is held before reconsidering.
CFG.steerCommitTime = 0.45
-- Steering casts six rays per candidate heading. Re-running the whole fan every
-- frame was pure waste; the answer barely changes between frames.
CFG.steerRefreshInterval = 0.1
-- Upper bound on path marker Parts. A long route draws a sparser line rather
-- than an unbounded number of Instances.
CFG.pathNodeBudget = 80
-- A heading that produces no movement for this long gets blacklisted, so the
-- steering stops re-picking the direction that just failed.
CFG.headingStallTime = 1.1
CFG.headingStallDistance = 2.0
CFG.headingBlacklistTime = 7.0
CFG.headingBlacklistArc = 32.0
CFG.headingBlacklistArcGrowth = 12.0
CFG.headingBlacklistMaxArc = 75.0

-- Standing in one spot this long, while NOT dodging, marks the spot itself as
-- bad. Distinct from the heading blacklist: that retires a direction, this
-- retires a location, which is what breaks a corner or doorway trap.
CFG.stuckAreaTime = 1.6
CFG.stuckAreaMoveThreshold = 2.5
CFG.stuckAreaRadius = 7.0
CFG.stuckAreaLife = 14.0
-- Give up on an enemy only after walking at it achieves nothing for this long.
CFG.directWalkGiveUpTime = 7.0

CFG.pathRecomputeInterval = 0.2
CFG.pathFailureRetryInterval = 0.5
CFG.pathTargetMoveThreshold = 3.0
CFG.waypointAdvanceDistance = 4.0
CFG.stuckTimeout = 0.65
CFG.stuckProgressDistance = 0.8

-- Facing. The rig eases toward the target rather than snapping rigidly: a rigid
-- constraint re-aimed every frame at a fast-changing bearing (a close, moving
-- enemy) was still whipping the body around frame to frame, which read as
-- stutter. A high responsiveness turns quickly but smoothly instead.
CFG.faceResponsiveness = 40
CFG.faceMaxTorque = 1e6

-- MoveTo housekeeping. Re-issuing MoveTo every frame to a point that jitters by
-- fractions of a stud makes the humanoid restart its approach constantly, which
-- shows up as a shuffle on the spot while attacking and a micro-stutter while
-- walking. The move goal is only re-sent when it actually shifts, and once
-- inside the deadband the character is told to hold position instead.
CFG.moveReissueThreshold = 1.25
CFG.inRangeDeadband = 2.0

-- Steering now prefers the most open heading it can find, not merely the first
-- one that is clear at the probe distance. A heading is measured for how far it
-- stays clear; among headings within a small deviation of the goal the roomiest
-- wins, so the bot runs into open space rather than scraping along a wall.
CFG.steerOpennessDeviationBudget = 45
CFG.steerOpennessMargin = 4.0

-- When there is no enemy to fight, walk the hardcoded path (set in the editor)
-- instead of standing idle. loopPath returns to the first waypoint after the last
-- rather than holding at the end.
CFG.followPath = true
CFG.loopPath = false
-- A waypoint is "passed" (and its marker cleared from the world) once the player
-- comes within this radius of it - but only the next one in order, and only the
-- in-world marker: the saved config keeps every waypoint. Slider in the editor.
CFG.waypointClearRadius = 16.0
CFG.minWaypointClearRadius = 4.0
CFG.maxWaypointClearRadius = 60.0
-- Free-fly camera used by the path editor.
CFG.freecamSpeed = 90            -- studs per second at full tilt
CFG.freecamLookSensitivity = 0.35

-- Wall overlay (one toggle button). Draws every invisible collision wall in
-- GREEN. Off by default: highlighting is the first thing to cost frames.
CFG.showWalls = false
-- An invisible wall: solid, effectively see-through, anchored, and wall-shaped
-- (thin in one horizontal axis) so invisible floors and ceilings are ignored.
CFG.invisibleWallTransparencyCutoff = 0.9
CFG.invisibleWallMinFootprint = 4.0
CFG.invisibleWallMaxThickness = 6.0

-- World index (2.1.0). The scanner no longer walks Workspace:GetDescendants()
-- on every scan; it keeps an index maintained by DescendantAdded/Removing and
-- re-classifies a slice of the part pool each frame. These bound the per-frame
-- work so it never lands as one spike.
CFG.indexBuildBudget = 2500      -- instances ingested per frame while the initial index builds
CFG.partEvalBudget = 300         -- pooled parts re-classified per frame (round-robin)
CFG.freshEvalBudget = 400        -- newly added parts classified per frame, ahead of the pool
CFG.remoteHookLifetime = 180     -- seconds the __namecall hook stays installed after startup

-- Terrain (2.2.0). A steering probe hit only counts as an obstacle when it is
-- wall-like: a surface whose normal points up this much is a floor or a ramp
-- the humanoid simply walks up, and a lip no taller than a step is stepped onto.
CFG.walkableNormalY = 0.5        -- cos(60 deg): slopes up to 60 degrees are floor
CFG.maxStepHeight = 2.4          -- a lip this low is stepped onto, not steered around
CFG.maxClimbHeight = 7.0         -- steering may pick a destination this much higher (a jump)
CFG.maxDropHeight = 30.0         -- ...or this much lower (a drop; falling is fine here)

-- Routed point walking (2.2.0): path waypoints and recovery hops. Each hop is a
-- navmesh path when one exists and direct steering when it does not.
CFG.pointRouteAgentRadius = 1.0
CFG.pointRouteRecomputeInterval = 3.0
CFG.pointRouteTargetMoveThreshold = 3.0
CFG.pointRouteStallLimit = 2     -- stalls on a navmesh hop before it is abandoned for direct steering
CFG.pointGiveUpTime = 6.0        -- no progress toward the point for this long = unreachable, skip it

-- Recovery (2.2.0): the manual path as the last resort. Staying inside
-- recoveryStuckRadius for recoveryStuckTime while trying to move means normal
-- navigation has wedged itself; the bot then walks the nearest stretch of the
-- manual path and only then goes back to chasing enemies.
CFG.recoveryEnabled = true
CFG.recoveryStuckRadius = 10.0
CFG.recoveryStuckTime = 2.5
CFG.recoveryWaypoints = 2        -- path waypoints walked before pursuit is retried
CFG.recoveryEscalation = 2       -- extra waypoints each time it re-sticks soon after
CFG.recoveryRepeatWindow = 12.0  -- "soon after" = within this many seconds of the last recovery
CFG.recoveryMaxTime = 25.0
CFG.recoveryArriveRadius = 6.0

-- Abilities (2.2.0). Q/E can be limited to when an enemy is within abilityRadius.
CFG.abilityRadiusEnabled = false
CFG.abilityRadius = 20
CFG.minAbilityRadius = 5
CFG.maxAbilityRadius = 60
CFG.showAbilityRadius = false

-- Own-attack recognition (2.2.0). A part that appears within ownAttackWindow
-- seconds of one of OUR casts (an Action-priority animation starting on our
-- character, or an attack remote fired from this client) and within
-- ownAttackRadius of us is our own effect, not a telegraph. Its name is learned
-- so later casts are recognised on sight, and learned names are saved.
CFG.ownAttackWindow = 0.45
CFG.ownAttackRadius = 14.0
CFG.hookRemotes = true           -- watch this client's FireServer calls for cast timing

-- Trial runs / attack book (2.3.0). While a trial run is on, every hit we take
-- is correlated with the parts that appeared around us just before it, and the
-- winners go into the attack book: a named record of what the attack (or its
-- warning telegraph) looks like. The book drives detection from then on and is
-- saved with the config.
CFG.damageCorrelationWindow = 1.5   -- a part that appeared this long before the hit is a suspect
CFG.damageCorrelationRadius = 25.0  -- ...if it is within this of us (planar)
CFG.damageSuspectLimit = 2          -- at most this many parts learned per hit
CFG.attackColorTolerance = 0.18     -- RGB distance that still counts as "same colour"
CFG.attackSizeTolerance = 0.45      -- +/- fraction per axis that still counts as "same size"

-- Projectiles (2.3.0). A hazard that is moving is treated as occupying the strip
-- it will sweep over the next projectileLookahead seconds, so the dodge steps
-- out of its path rather than away from where it happens to be right now.
CFG.projectileMinSpeed = 8.0        -- studs/s; slower than this is not "moving"
CFG.projectileLookahead = 1.2
CFG.projectileTrackWindow = 6.0     -- newly added parts are motion-tracked this long
CFG.projectileMaxSize = 14.0        -- longer than this on its longest axis is not a projectile
CFG.hazardTagEnabled = true         -- billboard name tag on every highlighted attack

-- Runtime Variables
RT.gameSpecificAttackMethod = nil
RT.detectedAttackRemote = nil
RT.lastClickTime = -math.huge
RT.mainConnection = nil
RT.enemyScanConnection = nil
RT.childAddedConnection = nil
RT.scriptGui = nil
RT.destroyed = false

UI.toggleButton = nil
UI.statusLabel = nil
UI.versionBadge = nil
UI.enemyCountLabel = nil
UI.closestEnemyLabel = nil
UI.enemyHealthLabel = nil
UI.damageBrickCountLabel = nil
UI.movementStateLabel = nil
UI.debugButton = nil
UI.pickerButton = nil
UI.streamerPanelButton = nil
UI.qAbilityButton = nil
UI.eAbilityButton = nil
UI.renderPathButton = nil
UI.renderHazardsButton = nil
UI.renderHitboxButton = nil
UI.wallDisplayButton = nil
UI.pathEditButton = nil
UI.pathListFrame = nil

RT.autoQEnabled = false
RT.autoEEnabled = false
RT.renderPathEnabled = true
RT.renderHazardsEnabled = true
RT.renderHitboxEnabled = true
RT.lastQTime = -math.huge
RT.lastETime = -math.huge
local sliderConnections = {}

NAV.waypoints = {}
NAV.index = 1
NAV.enemy = nil
NAV.lastTarget = nil
NAV.lastComputeTime = -math.huge
NAV.computing = false
NAV.nodesFolder = nil
HZ.highlightsFolder = nil
HZ.hitboxFolder = nil
HZ.hoverFolder = nil
NAV.blockedConnection = nil
NAV.needsRecompute = false
NAV.progressPosition = nil
NAV.progressTime = os.clock()
NAV.lastIssuedMove = nil

HZ.detected = {}
HZ.spawnTimes = {}
-- First time each anchored, non-collidable part was seen. Feeds the "appeared
-- moments ago" signal for telegraphs the name rules do not recognise.
HZ.seenAt = {}
-- Parts the user marked by hand with the picker.
HZ.manualParts = {}
-- Lowercased part names learned from picks, so later spawns of the same attack
-- are caught automatically instead of needing a click each time.
HZ.learnedNames = {}
HZ.pickerEnabled = false
HZ.pickerMouse = nil
HZ.pickerConnections = {}

-- Escape routing state (hazard branch). Separate from the pursuit path.
NAV.escapeWaypoints = {}
NAV.escapeIndex = 1
NAV.escapeTarget = nil
NAV.lastEscapeTime = -math.huge
NAV.computingEscape = false
NAV.escapeNodesFolder = nil
HZ.candidates = {}
HZ.lastCatalogTime = -math.huge
HZ.lastVisualTime = -math.huge
HZ.lastFeedTime = -math.huge
HZ.lastHitboxTime = -math.huge
HZ.lastRenderedCount = -1

-- Global Cache for Mobs & Billboards
NAV.cachedEnemy = nil
NAV.cachedEnemyCount = 0
-- Set when a target is benched, so the next Heartbeat rescans immediately
-- instead of waiting out the remainder of the scan interval.
NAV.forceRescan = false
-- Consecutive total pathfinding failures, and the deadline until which the
-- navmesh is treated as unusable in this place.
NAV.failureStreak = 0
NAV.navmeshDeadUntil = -math.huge
-- True while the active route is a straight walk rather than a navmesh path.
NAV.routeIsDirect = false
NAV.directProgressTime = os.clock()
NAV.directProgressPosition = nil

-- Hardcoded path: an ordered list of world points the bot walks between when it
-- has nothing to fight. Set by hand in the path editor (fly the camera, click the
-- map to drop points, reorder them). Saved to the config as coordinates.
NAV.waypath = {}                 -- array of Vector3, in visit order
NAV.pathIndex = 1                -- next unpassed waypoint (progress, not saved)
NAV.pathFolder = nil             -- holds the marker parts + their BillboardGuis
NAV.showRadius = false           -- draw the clear radius around live waypoints
NAV.walkAnchor = nil             -- shared stall anchor for the point-walker
NAV.walkAnchorTime = 0

-- Path editor state (free-fly camera + click to place).
NAV.pathEditEnabled = false
NAV.pathEditConnections = {}
NAV.freecamCFrame = nil
NAV.freecamYaw = 0
NAV.freecamPitch = 0
NAV.freecamKeys = {}
NAV.freecamLooking = false
NAV.savedCameraType = nil

-- Wall overlay: invisible collision walls draw green.
HZ.invisWalls = {}
HZ.wallHighlightsFolder = nil
HZ.lastWallRenderTime = -math.huge

-- World index (2.1.0). Maintained by events; never rebuilt per scan.
HZ.enemyModels = {}              -- [Model] = true: models carrying a live Humanoid
HZ.billboards = {}               -- [BillboardGui] = true: candidate floating health tags
HZ.partPool = {}                 -- array of every BasePart in Workspace that is not ours
HZ.partPoolIndex = {}            -- [part] = its index in partPool, for O(1) swap-remove
HZ.poolCursor = 1                -- round-robin position of the per-frame re-classification
HZ.freshParts = {}               -- parts added since the last frame; classified ahead of the pool
HZ.candidateSet = {}             -- [part] = true, mirrors the HZ.candidates array
HZ.invisWallSet = {}             -- [part] = true, mirrors HZ.invisWalls
HZ.indexBuild = nil              -- { list = GetDescendants(), cursor = n } while the initial index builds
HZ.indexReady = false
HZ.catalogDirty = false          -- candidate set changed; rebuild the array before the next filter
RT.indexConnections = {}

-- Own attacks (2.2.0).
HZ.ownParts = setmetatable({}, { __mode = "k" })  -- parts recognised as our own effects
HZ.ownNames = {}                 -- lowercased names learned as ours (saved with the config)
HZ.ownPickerEnabled = false      -- the picker is marking own attacks rather than telegraphs
RT.lastOwnActionTime = -math.huge
RT.lastOwnActionSource = nil
RT.animatorConnection = nil
RT.originalNamecall = nil
RT.hookInstalledAt = -math.huge
RT.visualRoot = nil

-- Routed point walking and recovery (2.2.0).
NAV.pointRoute = nil             -- { target, waypoints, index, direct, computedAt, stalls, needsRecompute }
NAV.computingPoint = false
NAV.pointProgressDistance = nil  -- best distance to the current point so far
NAV.pointProgressTime = 0
NAV.driving = false              -- set each frame by whichever branch is actively moving the character
NAV.stuckAnchor = nil            -- recovery detector: where the character has been loitering
NAV.stuckAnchorTime = 0
NAV.recovery = nil               -- { index, remaining, deadline, startedAt, stuckAt }
NAV.lastRecoveryEnd = -math.huge
NAV.lastRecoveryIndex = nil
NAV.pathMarkers = {}             -- [waypoint index] = { orb, link, sphere } drawn in the world

-- Trial runs, attack book, projectiles (2.3.0).
HZ.trialEnabled = false          -- damage taken is being correlated and learned
HZ.attackBook = {}               -- array of learned attack records (plain data, saved)
HZ.recentParts = {}              -- [part] = os.clock() it was added; motion-tracked while young
HZ.motion = {}                   -- [part] = { position, time, velocity, moving }
HZ.predictionOwner = {}          -- [prediction line Part] = the hazard it belongs to
HZ.damageEvents = 0
RT.lastHealth = nil
RT.healthConnection = nil

-- Smallest deviation first, so steering hugs the intended heading.
local STEER_FAN_ANGLES = { 0, 20, -20, 40, -40, 65, -65, 90, -90, 120, -120 }
-- Relative to the root's centre: roughly shin height and roughly head height.
local STEER_PROBE_HEIGHTS = { -1.6, 1.6 }

-- Flat world directions that recently produced no movement, each with an expiry
-- and an arc. Absolute rather than relative to the target, because walls are
-- fixed in world space: a heading blocked once is blocked from anywhere nearby.
NAV.blockedHeadings = {}
-- World positions that trapped the character, each with a radius and expiry.
NAV.blockedAreas = {}
NAV.spotAnchor = nil
NAV.spotAnchorTime = 0
NAV.stallAnchor = nil
NAV.stallTime = 0
NAV.steerAngle = nil
NAV.steerCache = nil
NAV.steerCacheAngle = nil
NAV.steerCacheTime = -math.huge
NAV.steerCacheGoal = nil
NAV.faceAligner = nil
NAV.faceAttachment = nil
NAV.steerTime = 0
-- [enemy model] = os.clock() expiry. Populated when pathing gives up.
NAV.benched = {}

-- Telegraph Inspector Window Reference
UI.telegraphFeedList = nil

-- Heavy Debug Logger
-- OFF     = silence
-- NORMAL  = decisions, state changes, errors (default; readable)
-- VERBOSE = every entity seen every scan (firehose)
local DEBUG_OFF = 0
local DEBUG_NORMAL = 1
local DEBUG_VERBOSE = 2
RT.debugLevel = DEBUG_NORMAL
local debugThrottleClocks = {}

local function heavyDebug(category, message, level)
    if RT.debugLevel < (level or DEBUG_NORMAL) then return end
    print(string.format("[HEAVY_DEBUG][v%s][%s][%.3f] %s", SCRIPT_VERSION, category, os.clock(), tostring(message)))
end

-- Rate-limited log. One line per `key` per `interval` seconds, so a per-frame
-- statement can be left in permanently without drowning the console.
local function heavyDebugThrottled(key, interval, category, message, level)
    local now = os.clock()
    local last = debugThrottleClocks[key]
    if last and (now - last) < interval then return end
    debugThrottleClocks[key] = now
    heavyDebug(category, message, level)
end

-- Logs only when the value for `key` actually changes. Used for branch/state
-- transitions, where a repeated line carries no information.
local debugLastValues = {}
local function heavyDebugOnChange(key, value, category, message, level)
    if debugLastValues[key] == value then return end
    debugLastValues[key] = value
    heavyDebug(category, message, level)
end

-- Mirrors the current movement decision onto the UI so the state is readable
-- in-game without tailing the console.
local function setMovementState(text)
    if UI.movementStateLabel then
        UI.movementStateLabel.Text = "Movement: " .. text
    end
end

-- One Folder under Workspace holds every instance this script draws. A single
-- ancestor test (instead of one per visual folder) tells the classifiers and the
-- raycasts to ignore our own markers, and the world index skips the subtree.
local function getVisualRoot()
    local root = RT.visualRoot
    if root and root.Parent then return root end
    root = Instance.new("Folder")
    root.Name = "DungeonAutofarmVisuals"
    -- Recorded before parenting, so the world index sees it as ours from the
    -- very first DescendantAdded it fires.
    RT.visualRoot = root
    root.Parent = Workspace
    return root
end

-- Newer clients filter non-collidable geometry out of a raycast natively. Tested
-- once here rather than with a pcall (and a closure) inside every single cast.
RT.respectCanCollide = pcall(function()
    local params = RaycastParams.new()
    params.RespectCanCollide = true
end)

-- Version Banner / Changelog Dump
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

S.CFG = CFG
S.CollectionService = CollectionService
S.DEBUG_NORMAL = DEBUG_NORMAL
S.DEBUG_OFF = DEBUG_OFF
S.DEBUG_VERBOSE = DEBUG_VERBOSE
S.HZ = HZ
S.LocalPlayer = LocalPlayer
S.NAV = NAV
S.PathfindingService = PathfindingService
S.Players = Players
S.RT = RT
S.RunService = RunService
S.SCRIPT_BUILD_DATE = SCRIPT_BUILD_DATE
S.SCRIPT_CHANGELOG = SCRIPT_CHANGELOG
S.SCRIPT_CODENAME = SCRIPT_CODENAME
S.SCRIPT_VERSION = SCRIPT_VERSION
S.SM = SM
S.UI = UI
S.UserInputService = UserInputService
S.VirtualInputManager = VirtualInputManager
S.Workspace = Workspace
S.STEER_FAN_ANGLES = STEER_FAN_ANGLES
S.STEER_PROBE_HEIGHTS = STEER_PROBE_HEIGHTS
S.debugLastValues = debugLastValues
S.debugThrottleClocks = debugThrottleClocks
S.heavyDebug = heavyDebug
S.heavyDebugOnChange = heavyDebugOnChange
S.heavyDebugThrottled = heavyDebugThrottled
S.printChangelog = printChangelog
S.printVersionBanner = printVersionBanner
S.setMovementState = setMovementState
S.sliderConnections = sliderConnections
S.getVisualRoot = getVisualRoot
end
