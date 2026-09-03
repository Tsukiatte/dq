-- core.lua - Services, settings, runtime state, timing seeds, small helpers.
-- Module contract: receives the shared table S. Every later module pulls what it
-- needs from S; this one defines the vocabulary. See REWRITE.md.
return function(S)
local SCRIPT_VERSION = "5.1.33"
local SCRIPT_BUILD_DATE = "2026-09-03"
local SCRIPT_CHANGELOG = {
    { version = "5.1.33", date = "2026-09-03", notes = "The bot hovered outside the Champion arena and stood still under the aimed spiral. Two causes: the leash zone's graded shoulder reached 12 studs into the arena and turned the approach into a dodge from 110 studs (now a hard edge with a 4-stud margin); and in a field where every spot is hot the escape target was dropped and re-picked every frame, so the character jittered in place (now kept until reached unless a clearly better spot exists). Strafe at full walk speed: never stand still in the arena." },
    { version = "5.1.32", date = "2026-09-03", notes = "Hazard boxes get a thin outline in their stage colour so every known hitbox reads as a shape; fill transparency 0.6." },
    { version = "5.1.31", date = "2026-09-03", notes = "Fourth kick: three or four blinks in a row. Root cause was the reader ending a passive beam's danger when its precast faded at 0.6 s while the beam kills for two seconds, so hops landed in beams the model called safe and hopped again. Beams now hold their full window. The blink is walk-first (only when the field's own spot cannot be reached before the box fires), 3 s apart, at most two in ten seconds, destinations clear for 1.5 s and at least 26 studs from any mob." },
    { version = "5.1.30", date = "2026-09-03", notes = "A blink destination must stay clear of every box for a full second (five samples), moving bodies included; it was checked only now and at 0.5 s, and Chris watched the character land where the next shot arrived." },
    { version = "5.1.29", date = "2026-09-03", notes = "Blink destinations only have to be outside the boxes themselves (body radius, no shoulder): with the field's padded metric a spot 8 studs beside a 7-wide mage shot still read as danger and the reflex never found anywhere to go. Three room-1 deaths inside live shots with no blink." },
    { version = "5.1.28", date = "2026-09-03", notes = "Blink reflex, asked for by Chris after the second script's video: when a lethal box covers the character and fires within 0.45 s, hop at most 8 studs to the nearest clear floor. Runs every frame outside the movement logic. The destination's floor is raycast and must match the current feet within 1.5 studs; the sweep there must be clear and there must be headroom; never while airborne; rotation, velocity and WalkSpeed untouched; 1.2 s between hops. Off switch and size in the Dodge window." },
    { version = "5.1.27", date = "2026-09-03", notes = "Ability radius 42: with the 34-stud mob standoff a 30-stud cast radius would never fire at a mob." },
    { version = "5.1.26", date = "2026-09-03", notes = "Mobs are fought from 34 studs whatever their type, with abilities only (auto attack off by default): at high level any mob's one swing kills, and the warriors were counted as ranged because their melee distance is above 8. Any target that closes to within standoff minus six is backed away from in a straight line at the burst speed. A melee mob's swing reach is a hard zone, the ten studs past it a soft one." },
    { version = "5.1.25", date = "2026-09-03", notes = "The leash arms only after the character has been within 110 studs of the Champion and stays armed for that boss. As a band it was a wall from the outside: run 19 hopped at its outer edge for six minutes without entering." },
    { version = "5.1.24", date = "2026-09-03", notes = "Standoff back to 38: at 48 the abilities did 0.35% per second. The config keeps a trace of what it loaded and saved (RT.configTrace) to catch the standoff reverting to 26 between places." },
    { version = "5.1.23", date = "2026-09-03", notes = "Beam lanes: each new beam is matched to any beam of the last 0.8 s that sits 20 degrees away, and that chain's next two lanes become zones; the sweeps run interleaved, so a single last-pair rule never fired." },
    { version = "5.1.22", date = "2026-09-03", notes = "Boss standoff 48: the abilities reach about 53 studs and measured the same damage per second at 40-50 as at 30-40, and the beam lanes are wider further out." },
    { version = "5.1.21", date = "2026-09-03", notes = "The leash is a 40-stud band outside the arena, not everything beyond it: the walk in from room 2 was being scored as lethal. Ranged mobs are fought from 22 studs; at 7-11 a mage shot leaves no time." },
    { version = "5.1.20", date = "2026-09-03", notes = "The escape burst keys off danger within the dwell window, not only danger at this instant. Five big-spike deaths in one fight: the field saw the front coming and walked away from it at 16." },
    { version = "5.1.19", date = "2026-09-03", notes = "The Champion's arena has a leash: every unexplained death sat 129-137 studs from the boss with nothing tracked nearby, three of them while strafing at 135. The field now treats the ground past 122 studs from him as danger, so a respawn walks in at once and no spot is chosen out there." },
    { version = "5.1.18", date = "2026-09-03", notes = "The fan retreat is gone: beams fire eight to ten a second through most of the fight, so the detector held the boss at 135 studs and the character strafed there dealing nothing. Passive beams get a 0.3 s telegraph (the earliest death inside one), so the field may step out through a fresh beam instead of treating it as a wall." },
    { version = "5.1.17", date = "2026-09-03", notes = "Champion: the next two beam lanes of the slow sweep are zones (20 degrees on, half a second apart); the fast fan is detected and the boss is left for its 125-stud reach until it ends; the jump's target is a slam zone 2.5 s ahead. Standoff 35 (the abilities' best band). Dodge rings reach 30 studs so a 40-wide body can be sidestepped; far looks at 48 and 75." },
    { version = "5.1.16", date = "2026-09-03", notes = "A room counts as reached when the character stands inside its bounding box, not only within 25 studs of its first spawn part (the bot walked back toward room 2 after two boss kills). The field decides every frame: the aimed criss cross kills on spawn and a moving character survives it far more often than a parked one." },
    { version = "5.1.15", date = "2026-09-03", notes = "Dodge tuning keys are no longer persisted; the saved 0.6 s dwell was overriding 5.1.14 on load." },
    { version = "5.1.14", date = "2026-09-03", notes = "Dwell 1.5 s: a spot must stay clear for 1.5 s after arrival and here counts as dangerous when something arrives within 1.5 s. The big spike's front leaves the boss 1.4 s after its announcement at 100 studs/s; with a 0.6 s window the field noticed it 0.9 s out and could not clear 23 studs." },
    { version = "5.1.13", date = "2026-09-03", notes = "Body margin 2.0: a mage shot killed 3.3 studs outside its box and a circle 1.5 outside; the game reaches past the visible hitBox." },
    { version = "5.1.12", date = "2026-09-03", notes = "The config file keeps only the settings the UI exposes. It used to snapshot every tuning constant, so each new default (margin, melee buffer, walk speed) was overridden by the old saved value on load." },
    { version = "5.1.11", date = "2026-09-03", notes = "Melee mobs are a soft zone (danger at most 0.5, buffer 4) instead of a lethal 19-stud circle; their strikes are tracked as boxes anyway, and the hard circle left the field with no spot in room 1 while mage shots landed. The body margin is 1.5 studs: a beam killed at 1.5 studs outside its box." },
    { version = "5.1.10", date = "2026-09-03", notes = "The next room is the first past the furthest room stood in; rooms passed at range no longer pull the character back (it walked toward room 2 after the Champion died)." },
    { version = "5.1.9", date = "2026-09-03", notes = "Sixteen deaths in one Champion fight, read from the recorder. A moving body is danger from the moment it is announced (the aimed criss cross sits on the player until its start time; the field used to notice it 0.4 s before). Remote-announced paths are ground attacks whatever height their CFrame carries (the big spike was filtered out vertically). A far spot up a ramp is allowed. Walks are planned at the Humanoid's real WalkSpeed, so the escape burst is no longer permanent when the saved walk speed is above 16." },
    { version = "5.1.8", date = "2026-09-03", notes = "Third anti-cheat kick, from the server, during ordinary driving. The mover no longer writes positions at all: every move is a Humanoid walk, and leaving danger raises WalkSpeed to the escape value for the burst and restores it after. Real collisions, real falls, legal speed. Half a second against a wall is a hop." },
    { version = "5.1.7", date = "2026-09-03", notes = "The target is not a wall. The swept walkability check that validates a spot treated the boss's own sixty-stud body as solid, so with the jump slam centred on the character every spot outside the ball lay behind him and failed, and the field kept a six-stud spot at danger 1.0. The target's model is excluded from that check." },
    { version = "5.1.6", date = "2026-09-03", notes = "Walk when the walk is clean. The field's spot outranked travel whenever anything was about to arrive within the dwell, which at the arena entrance is always, so the character hopped in place for a whole run. The spot now outranks travel only while the ground here is dangerous now, or while the brain's own next step would be unsafe at the moment it is crossed." },
    { version = "5.1.5", date = "2026-09-03", notes = "The spots carry the approach again. At the arena entrance something is always about to arrive, so the field always has a spot and the spot outranks travel; with the pull toward the target limited to the last thirty studs, those spots led nowhere and the character hopped at the entrance until the aimed shot came. The pull now applies at every distance, weaker far out." },
    { version = "5.1.4", date = "2026-09-03", notes = "Travel that travels. The Champion walks, so the approach path's end moved more than eight studs every half second, travel replanned from scratch each time, the index went back to the waypoint under the character, and it shuffled on the spot for a whole fight while the mover reported four hundred good steps. Now: straight at the target when the line is clear, otherwise a path replanned at most every four seconds or when the target has moved twenty studs, resumed past the waypoints already behind." },
    { version = "5.1.3", date = "2026-09-03", notes = "The room first. The target picker favoured a boss within four hundred studs, so from three rooms back it pathed at Bob the Frost Giant through a gate that opens only when this room is cleared, and pushed a wall for six seconds. Mobs within 150 studs come first; a boss only when there is nothing nearer. Travel that makes no progress for 2.5 s skips a waypoint." },
    { version = "5.1.2", date = "2026-09-03", notes = "Never a jump. An anticheat kick followed a lag spike, a fall through the floor and a short teleport: the tween stepped speed times the frame delta, so one long frame wrote several studs at once. The step is capped at what a 30 fps frame allows whatever the delta, a spike frame writes nothing, nothing is written while airborne or over a missing floor, and the drawing is throttled to ten times a second, sixty boxes, within 130 studs, so it cannot be the spike." },
    { version = "5.1.1", date = "2026-09-03", notes = "First live run of the rewrite: the Champion from 100% to dead at ability range, four deaths on the aimed shot's cadence. Then the mob rooms said two things. Melee mobs killed at three and six studs: their danger radius now runs eight studs past their swing and they are fought from twenty, retreating rather than circling. Crossing mage lines had every near spot hot and the character shuttled between two attacks: an escape spot is now kept until reached or its line closes, the far look goes to four times reach, and when everything near is hot spots away from the target are preferred, so it backs out." },
    { version = "5.1.0", date = "2026-09-03", notes = "Rewrite. About 1400 lines of logic on the same interface kit: a reader that turns every attack into boxes with live windows, a field that scores a ring of spots with the fire time of the ground under you as the cutoff, a floor-following tween, and a brain that clears rooms, walks straight to the boss, fights at ability range and strafes. Timings are seeds measured in eight recorded runs, never learned from being hit." },
}

-- Executed automatically on entering a place, the script can run before the
-- local player has replicated. Nothing is captured until it exists.
if not game:IsLoaded() then game.Loaded:Wait() end
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
while not LocalPlayer do task.wait(0.1) LocalPlayer = Players.LocalPlayer end

local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local PathfindingService = game:GetService("PathfindingService")
local VirtualInputManager = game:GetService("VirtualInputManager")

-- A previous instance hands over cleanly.
if _G.DungeonAutofarmDestruct then pcall(_G.DungeonAutofarmDestruct) end
_G.DungeonAutofarmVersion = SCRIPT_VERSION

-- ------------------------------------------------------------------ settings
local CFG = {
    -- Movement. The tween writes the root's CFrame along the floor; the
    -- client's own checker resets WalkSpeed above 45 and watches Freefall, and
    -- neither is touched. 22 studs/s ran whole fights without a kick; a
    -- position hop got one in five minutes and is not offered.
    tweenWalk = 16,               -- studs/s assumed for planning; the character walks at its own WalkSpeed
    tweenEscape = 22,             -- WalkSpeed while leaving danger (a burst)
    approachWalkSpeed = 22,       -- WalkSpeed while closing on a boss from far out (0 = leave it)
    maxStepHeight = 2.4,
    maxDropHeight = 30,

    -- Standing.
    mobStandoff = 34,             -- from any mob, melee or ranged: abilities only, never within weapon reach (Chris)
    meleeBuffer = 10,             -- soft band past a melee mob's swing where spots are merely disfavoured
    leashRadius = 122,            -- Champion arena: death past ~128 studs from the boss; the respawn point is 131-137 out
    bossStandoff = 38,            -- ability damage 11-15%/s at 30-40 studs, ~0 past 45 (48 measured 0.35%/s)
    meleeMobMaxReach = 16,        -- a mob whose meleeDistance is at most this is melee (warriors sit above 8)
    strafe = true,                -- circle the target at standoff instead of standing
    strafeSpeedFraction = 1.0,    -- of tweenWalk

    -- Fighting.
    attackRange = 10,             -- weapon reach
    abilityRadius = 42,           -- casts land out to ~40-42 studs (measured on the Champion); must exceed mobStandoff or mobs are never hit
    abilityInterval = 0.4,        -- seconds between presses of the same key
    autoQ = true,
    autoE = true,
    autoAttack = false,           -- high-level dungeons: abilities only
    clickInterval = 0.25,

    -- Dodge field.
    dodgeInterval = 0.016,
    dodgeReach = 30,              -- rings at 10/20/30: a 40-wide body needs 23 studs of sidestep
    dodgeRings = 3,
    dodgeRays = 16,
    dodgeMargin = 2.0,            -- studs of clearance round the character; hits landed 1.5-3.3 studs outside their boxes            -- studs of clearance round the character
    dodgeShoulder = 3,            -- studs of warm edge outside a hazard
    dodgeLead = 1.2,              -- a standing telegraph counts as live this long before it fires
    dodgePathLead = 0.4,          -- a moving projectile's line: the time to sidestep
    dodgeDwell = 1.5,             -- a spot must stay clear this long after arrival (the big spike front: 100 studs/s, announced 1.4 s ahead)
    blink = true,                 -- reflex hop out of a lethal box that fires before a walk could clear it
    blinkMax = 8,                 -- studs, at most; the other script's hop is barely visible
    blinkWindow = 0.45,           -- hop when the box on us fires within this many seconds (0 = already live)
    blinkCooldown = 3.0,          -- seconds between hops; four kicks say chained hops are what the server flags
    blinkPer10s = 2,              -- and no more than this many in any ten seconds
    dodgeMoveAt = 0.15,           -- danger here at or above this: relocate
    dodgeHysteresis = 0.1,
    dodgeDistanceCost = 0.008,
    dodgeFarScale = 1.6,          -- second look this many times further when nothing near is safe
    dodgeFarScale2 = 2.5,         -- and a third, further still
    dodgeOutwardWeight = 0.25,    -- when everything near is hot, prefer spots away from the target: back out
    dodgeInsideWeight = 0.85,
    dodgeStrafeWeight = 0.15,     -- preference for moving across the target's line rather than along it
    dodgeApproachWeight = 0.03,   -- pull toward the standoff band, per stud out of it

    -- Reader defaults for attacks with no seed.
    defaultFire = 1.5,            -- a telegraphed Model with no seed fires this long after it appears
    defaultLive = 0.6,            -- and hurts this long after firing
    fadeLinger = 0.3,             -- after its precast fades an attack is over this much later
    projectileLookahead = 1.0,    -- seconds of a moving part's path treated as its box
    spentTransparency = 0.97,

    -- Drawing. One translucent box per hazard, nothing else.
    drawHazards = true,
    drawTarget = true,
    colorFloor = Color3.fromRGB(60, 220, 120),
    colorSoon = Color3.fromRGB(255, 220, 40),
    colorLive = Color3.fromRGB(255, 50, 50),
    colorTarget = Color3.fromRGB(255, 255, 255),
    hazardTransparency = 0.6,

    -- Loop outside the fight (lobby.lua).
    autoQueue = false,
    autoQueueMap = "Northern Lands",
    autoQueueDifficulty = "Nightmare",
    autoQueueHardcore = false,
    autoQueuePrivate = true,
    autoQueueMinLevel = 0,
    autoQueueDelay = 8,
    autoQueueRetry = 25,
    autoQueueStartDelay = 2.0,
    autoQueueReplay = true,
    autoQueueReplayDelay = 6,
    autoFarmByPlace = true,
    autoStartDungeon = true,
    autoStartDelay = 6,

    -- Interface.
    menuKey = "RightShift",
    debugPrints = false,
    autosaveInterval = 10,
}

-- ------------------------------------------------------------ timing seeds
-- Per attack Model name (lowercased): when it first hurts and when it stops,
-- in seconds after the Model appears. Measured in the recorded runs of
-- 2026-09-02/03 (game/captures). `long` = it burns until the Model goes.
local TIMING = {
    northernmageshot            = { first = 0.5, last = 1.2 },
    spearmanstrikehitbox        = { first = 0.6, last = 1.2 },
    northernwarriorlinestrike   = { first = 0.6, last = 1.2 },
    northernwarriorcirclestrike = { first = 0.6, last = 1.2 },
    firstbosspassivebeam        = { first = 0.3, last = 2.4, holdFull = true },   -- hurts 0.3-2.2 s after the Model appears; its precast fades at 0.6 s, which must NOT end the danger
    firstbossjumpslam           = { first = 1.8, last = 5.0 },
    secondbosscriclehitbox      = { first = 1.2, last = 2.5 },
    secondbosshorizontalbeam    = { first = 1.1, last = 5.0 },
    cubepylonshot               = { first = 0.8, last = 1.1 },
}

-- Bare parts that are attacks (no hitBox/precast Model round them). Matched by
-- lowercase substring of the part name.
local PROJECTILE_HINTS = { "crisscross", "spearmanstrike", "seekingspike", "bigspike", "missile", "orb", "rock", "genericneonball", "freezepart", "shuriken", "bomb" }

-- ------------------------------------------------------------ runtime state
local RT = {
    farmEnabled = true,
    destroyed = false,
    movementState = "starting",
    frameDelta = 1 / 60,
    tickMs = 0,
    visualRoot = nil,
    blurEffect = nil,
    scriptGui = nil,
    moveBoost = false,
    walkSpeedBefore = nil,
    lastQ = -math.huge, lastE = -math.huge, lastClick = -math.huge,
    pinnedWindows = {},
    autosaveStarted = false,
}
local UI = {}

-- ------------------------------------------------------------------ helpers
local throttle = {}
local function heavyDebug(tag, text)
    if CFG.debugPrints then print(string.format("[DQ %s][%s] %s", SCRIPT_VERSION, tag, text)) end
end
local function heavyDebugThrottled(key, seconds, tag, text)
    local now = os.clock()
    if (throttle[key] or -math.huge) + seconds > now then return end
    throttle[key] = now
    heavyDebug(tag, text)
end

local function setMovementState(text)
    RT.movementState = text
end

-- One Folder under Workspace holds every instance this script draws, so a
-- single ancestor test excludes them from raycasts and the reader.
local function getVisualRoot()
    if RT.visualRoot and RT.visualRoot.Parent then return RT.visualRoot end
    local folder = Instance.new("Folder")
    folder.Name = "DungeonAutofarmVisuals"
    folder.Parent = Workspace
    RT.visualRoot = folder
    return folder
end

local function character()
    return LocalPlayer.Character
end
local function rootPart()
    local c = LocalPlayer.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end
local function humanoid()
    local c = LocalPlayer.Character
    return c and c:FindFirstChildOfClass("Humanoid")
end

local function flatDistance(a, b)
    local dx, dz = a.X - b.X, a.Z - b.Z
    return math.sqrt(dx * dx + dz * dz)
end

local function isOurs(inst)
    return RT.visualRoot ~= nil and inst:IsDescendantOf(RT.visualRoot)
end

local function raycastParams(extraExclude)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    local list = {}
    if LocalPlayer.Character then list[#list + 1] = LocalPlayer.Character end
    if RT.visualRoot then list[#list + 1] = RT.visualRoot end
    if extraExclude then list[#list + 1] = extraExclude end
    params.FilterDescendantsInstances = list
    params.IgnoreWater = true
    pcall(function() params.RespectCanCollide = true end)
    return params
end

-- Floor height under a point, or nil.
local function floorY(x, y, z, params)
    local hit = Workspace:Raycast(Vector3.new(x, y + 6, z), Vector3.new(0, -46, 0), params)
    return hit and hit.Position.Y or nil
end

S.SCRIPT_VERSION = SCRIPT_VERSION
S.SCRIPT_BUILD_DATE = SCRIPT_BUILD_DATE
S.SCRIPT_CHANGELOG = SCRIPT_CHANGELOG
S.Players = Players
S.LocalPlayer = LocalPlayer
S.Workspace = Workspace
S.RunService = RunService
S.ReplicatedStorage = ReplicatedStorage
S.UserInputService = UserInputService
S.PathfindingService = PathfindingService
S.VirtualInputManager = VirtualInputManager
S.CFG = CFG
S.RT = RT
S.UI = UI
S.sliderConnections = {}   -- the kit tracks widget connections here; the interface tears them down
S.TIMING = TIMING
S.PROJECTILE_HINTS = PROJECTILE_HINTS
S.heavyDebug = heavyDebug
S.heavyDebugThrottled = heavyDebugThrottled
S.setMovementState = setMovementState
S.getVisualRoot = getVisualRoot
S.character = character
S.rootPart = rootPart
S.humanoid = humanoid
S.flatDistance = flatDistance
S.isOurs = isOurs
S.raycastParams = raycastParams
S.floorY = floorY
_G.DungeonAutofarmState = S
end
