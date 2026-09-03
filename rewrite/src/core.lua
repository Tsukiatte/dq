-- core.lua - Services, settings, runtime state, timing seeds, small helpers.
-- Module contract: receives the shared table S. Every later module pulls what it
-- needs from S; this one defines the vocabulary. See REWRITE.md.
return function(S)
local SCRIPT_VERSION = "5.1.72"
local SCRIPT_BUILD_DATE = "2026-09-03"
local SCRIPT_CHANGELOG = {
    { version = "5.1.72", date = "2026-09-03", notes = "Champion slam: the reflex starts when the slam Model appears, two seconds before the hit; the Jump Down event turned out to arrive with the hit itself (the trace showed the reflex starting at the moment of death). Mage volley: the predicted march covers the whole line, so the closest clean spot is sideways rather than further along it. A blink to the marker needs it four studs away." },
    { version = "5.1.71", date = "2026-09-03", notes = "Bob (Chris): the fight position is his home point - at ability range from him on the crystals' side, near the arena centre - so the orbs can be led without leaving range. An orb that follows the character is led into the crystal of its colour: the bot runs to the far side of that crystal at escape speed and holds there while the orb comes. Bob only." },
    { version = "5.1.70", date = "2026-09-03", notes = "Bob: the circle Model itself is destroyed when it fires, not only its precast, and the reader dropped the record with it - two more deaths seven studs outside a circle it had just forgotten. A record whose Model is gone now lives on its remembered geometry until its window closes." },
    { version = "5.1.69", date = "2026-09-03", notes = "Per-boss profiles (Chris: keep the Champion and Bob apart). The arena pull, the fan reflex and the slam reflex are the Champion only; Bob keeps the chain line, the wall and the orb bubble. Attack windows stay keyed by attack name; the blink, the measured range and the mob rules are shared." },
    { version = "5.1.68", date = "2026-09-03", notes = "From the death verdicts at Bob: the horizontal beam fires 0.6 s after it appears, not 1.1 (a death 0.4 s before the model said so); the spread beam hits four studs outside its box; the following orbs get a 14-stud bubble (one killed at 1.2 studs with no box round it). No ability is cast while the ground here goes hot within 1.2 s: the cast animation roots the character, and the trace showed it commanded to run and not moving in the second before a death." },
    { version = "5.1.67", date = "2026-09-03", notes = "Into the arena, every time (Chris): boss-fight spots beyond the arena edge cost during the fan as well (the edge is the fan radius then), and the approach to a boss runs at escape speed while it is more than twenty-five studs outside the band, so the bot does not linger at the mouth where the aimed attacks spawn on it." },
    { version = "5.1.66", date = "2026-09-03", notes = "Champion fan: out to 85 studs, not 100, which was against the rocks (the trace showed 4 studs a second while commanded 22), and the reflex no longer re-arms once the bot is near that radius. A spot counts as clean only under 0.2 path danger, and a spot under eight studs costs extra while the ground here is hot. The blink may hop a second time inside its cooldown, two seconds on and once per twenty seconds, when a box is already on the character (the aimed criss cross spawns on you)." },
    { version = "5.1.65", date = "2026-09-03", notes = "Ability range per slot (Chris): every cast is queued with its slot, and the projectile that appears takes the measurement, so Q and E are measured separately and the least ranged one sets the fight distance - two studs inside a known cap, one past a reach that is only a lower bound. The Ability radius and Boss standoff sliders go to 80; auto standoff can go to 70. Bob: a circle whose precast is destroyed when it fires vanished from the field at that moment (three deaths just outside circles the model no longer had); the last geometry is kept while the window is open, and the circles are padded ten studs. A blocked travel step takes the spot instead of standing still beside the box." },
    { version = "5.1.64", date = "2026-09-03", notes = "Bob: the spread and horizontal beams kill at least 2.2 studs outside their 12-wide hitbox (the recorder saw a death there right after a blink to a spot the model called clear), so their padding is 2.5 studs with a 1-stud shoulder, and a blink destination must be 2.5 studs clear of every box." },
    { version = "5.1.63", date = "2026-09-03", notes = "Walls (Chris: melee mobs back it into a corner and it dies there). Every spot that passes the floor and sweep checks now looks 24 studs round itself in six directions and costs more the closer the walls are, so an open spot beats a corner. The back-off from a mob tries straight back, then 40, 80 and 120 degrees either side, and takes the most open way the field allows." },
    { version = "5.1.62", date = "2026-09-03", notes = "Telemetry: the field reports how many spots it evaluated and why they were rejected (no floor, not walkable, lethal on arrival) and which one it chose, for the new recorder that traces intent against movement at ten samples a second and gives every death a verdict. The marker is now the closest clean spot (clean path, clean ground), and when it is within blink range the blink goes to the marker itself (Chris)." },
    { version = "5.1.61", date = "2026-09-03", notes = "Champion slam: the landing announcement now starts a reflex - straight out from the landing point at escape speed until 44 studs clear, bending the line only round a live box - instead of leaving it to the spot search, whose rings reach 30 studs and kept picking spots inside the 67-stud circle (three slam deaths in run 30)." },
    { version = "5.1.60", date = "2026-09-03", notes = "Ability range: measured against where the character and target stood at the cast, not half a second later when the geyser appears; the first reading was a 30-stud cap beside a 56-stud reach. A reach beyond a supposed cap discards the cap. Auto standoff only ever moves the bot further out than the slider, never closer, and never past 45. Beam padding and margins back to the 5.1.51 values: the slim passive beam and the 4-stud shoulder came in together and the Champion deaths went up. The take-off ring is not an attack (Chris): the zone placed at Jump Up is gone; only the landing ring at Jump Down is fled." },
    { version = "5.1.59", date = "2026-09-03", notes = "After the last boss the game asks whether to stay for the bonus boss; run 29 sat on that vote with the timer frozen for ten minutes. The vote is now answered two seconds in, no by default (its arena is not mapped), yes with the new Queue toggle. Once a run is complete the bot stands still instead of walking the rooms again." },
    { version = "5.1.58", date = "2026-09-03", notes = "The ability's range is measured from where its geyser lands when the target is further away (the client script carries no range; the server caps the placement), and the boss is fought from two studs inside it (Chris). Shown in the Standing section. The blink is limited to the Champion, Bob and mob fights until the third boss is mapped: it teleported all over that arena. Margins: 2.5 studs of reach and a 4-stud shoulder, so spots on a box's edge cost and the bot stops further out (it was grazed on an edge). Every drawn hitbox now carries a faint second outline at the size the bot treats as unsafe." },
    { version = "5.1.57", date = "2026-09-03", notes = "Champion (Chris): boss-fight spots are pulled back inside the arena - beyond the standoff band plus twenty studs costs, past forty-five it is out of the question - because the aimed attacks spawn on you at the mouth with nowhere to step. The blink now fires for a box that will cover you within 0.6 s, moving bodies included (the criss cross gave no warning before), 5 s apart, four a minute, up to 8 studs. Slam counts as live from 1.5 s and five studs wider (a death landed 3.3 studs outside it). Passive beams hold 2.6 s with slim padding so the fan has gaps past 80 studs. A respawn outside the leash is pulled back in by a gradient instead of wandering out (run 28)." },
    { version = "5.1.56", date = "2026-09-03", notes = "Champion: back to the 5.1.51 beam window (3.5 s, normal padding) and standoff during the fan; the 95-stud fan standoff added in 5.1.53 left the bot twenty studs from the arena edge and the leash killed it twice. The jump slam lands where the player stood at Jump Up, so a slam zone is placed there at Jump Up: three seconds to leave instead of two." },
    { version = "5.1.55", date = "2026-09-03", notes = "Interface: the HUD is the old build's again - title chip with the build number and fps, a Playtime / Status / Ping card, the open-GUI hint and the Autofarm pill. Window corners: the header now shares the frame's rounding and the accent is an inset pill, so nothing square shows past the corners; the body stops short of the bottom corners." },
    { version = "5.1.54", date = "2026-09-03", notes = "The spot marker never sits on a box about to fire (Chris): a spot whose own ground is lethal on arrival or during the dwell sorts last, and a kept spot is dropped the moment its ground closes. Bob\'s chain line is a soft band the bot will not stand in but may cross; the circles are predicted both ways from the first one and pruned by the second. Against mobs, dodges prefer straight back over sideways." },
    { version = "5.1.53", date = "2026-09-03", notes = "Mob attacks (Chris): they hit about a quarter second after they look finished, so their windows run to 1.5 s and a fading precast no longer ends them early. Champion: a passive beam is held 2.0 s instead of 3.5 and padded 1.5 studs, so the fan's gaps exist in the model; during the fan the bot backs to 95 studs at escape speed instead of walking toward 135. The big spike kills 4-6 studs outside its 40-stud body, so it is 52 wide now. Visuals: a stopped projectile is a hazard for one second, not for as long as it lies there, and only announced paths draw their sweep strip - the yellow strips that stayed on the floor were thrown spears." },
    { version = "5.1.52", date = "2026-09-03", notes = "Bob (Chris): the floating beam fans are padded by the body radius only instead of 4.5 studs a side, so the gaps between spokes exist again. The circle chain's whole line through Bob is a zone from the first circle, so the escape is sideways, never along the line toward the next circle." },
    { version = "5.1.51", date = "2026-09-03", notes = "Travel steps are refused only for danger that would land during the crossing (0.6+); the soft lane danger was blocking every other step of the approach." },
    { version = "5.1.50", date = "2026-09-03", notes = "Bob: the circle chain is predicted from its first circle (0.27 s, 22 studs and 6 studs wider per step, lethal 0.6 s after each appears) so the bot leaves the line before the chain reaches it. The sweeping wall is tracked from its real model (balls and beam, ~19 studs/s); the announced path was a hundred studs off and is no longer used." },
    { version = "5.1.49", date = "2026-09-03", notes = "Danger weighs three times as much as before in a spot's cost. At every death in the beam fan the cheapest spots were all lethal while clean ones 75 studs out lost on the pull toward the boss and the distance term; that is why it stood in the red." },
    { version = "5.1.48", date = "2026-09-03", notes = "Bob's circles: seeded to fire 0.6 s after the Model appears (deaths came 0.2-0.5 s before the old 1.2) and padded 3 studs wider than their precast cylinder (deaths at 1.5 studs outside it). Seeds may carry a pad the reader applies to the box." },
    { version = "5.1.47", date = "2026-09-03", notes = "A moving projectile's whole remaining lane (spirals, saw discs, the big spike) is soft danger ahead of the body, so the bot never sits where one is going to pass, and the lane is drawn to its end." },
    { version = "5.1.46", date = "2026-09-03", notes = "The armed leash survives a reload of the script (mirrored in _G per boss); a reload at the respawn point left the character standing outside the arena and dead." },
    { version = "5.1.45", date = "2026-09-03", notes = "Leftover drawings from the older build that the autoexec loads first (its PrecastZones and Dodge folders) froze in place as yellow slabs; the draw module now removes anything under the visuals root that is not its own, every three seconds." },
    { version = "5.1.44", date = "2026-09-03", notes = "Seventh kick came while simply walking toward Bob at 22. Every kick so far shares speed above 16 held for seconds. The burst now runs at most 1.5 s before 1.2 s at walking speed, and approaches walk at 16." },
    { version = "5.1.43", date = "2026-09-03", notes = "Box footprints follow the part's orientation: whichever local axis points up is the height. At Bob a hitbox stood on end read as a 63-stud floor box, the whole arena counted as lethal, and the blink fired on every cooldown with nothing there." },
    { version = "5.1.42", date = "2026-09-03", notes = "Mage volleys are predicted: two aligned shots within 0.4 s reveal the line, and the next 70 studs of it become a zone firing from 0.3 s, so the field leaves the line instead of standing where the last shot lands. A lone mage killed the character by walking it down that line." },
    { version = "5.1.41", date = "2026-09-03", notes = "Room progress is kept in _G so a reload inside the dungeon no longer sends the character back toward room 1." },
    { version = "5.1.40", date = "2026-09-03", notes = "The boss's body is a wall again for the spot sweep (fifteen collidable parts; the character ran in place against his legs toward a spot behind him), and a spot not reached for 0.6 s of standing still is dropped for another." },
    { version = "5.1.39", date = "2026-09-03", notes = "Every travel step is checked against the field before it is walked; the approach marched into crossing projectiles because that check only ran while a dodge spot was held." },
    { version = "5.1.38", date = "2026-09-03", notes = "Blink only inside a fight (a target within 70 studs); hops while walking between rooms made the sixth kick. A bare projectile that has been still for 0.6 s is spent: a thrown spear in the ground blocked the field for five seconds." },
    { version = "5.1.37", date = "2026-09-03", notes = "No more jumping: the mover's stall hop fired in place whenever walking did nothing (a hovering character after a hop), which read as jump spam and helped nothing. Stalls are recorded for the brain instead." },
    { version = "5.1.36", date = "2026-09-03", notes = "Blink lands at the Humanoid's standing height with a small downward velocity, and never fires mid-jump; a hop that inherited a mid-stride height left the character hovering until the anti-hover yanked it down. Hop is 4 or 6 studs, no longer 8." },
    { version = "5.1.35", date = "2026-09-03", notes = "Fifth kick with hops 3 s apart and two per ten seconds. The blink is now 8 s apart and at most three a minute; everything else about it is unchanged." },
    { version = "5.1.34", date = "2026-09-03", notes = "The bot walked onto beam lanes while gaps stood empty: a lane about to 'expire' in the model scored better than a gap padded by two neighbours' shoulders, but in the burst every lane re-fires every 1.1 s. Passive beams now hold 3.5 s and the shoulder is 1.5 studs, so gaps read clean and lanes read lethal for as long as the burst lasts." },
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
    boostMaxRun = 1.5,            -- seconds the burst may run before it must rest
    boostRest = 1.2,              -- seconds at walking speed after a full burst
    approachWalkSpeed = 22,       -- WalkSpeed while closing on a boss from far out (0 = leave it)
    maxStepHeight = 2.4,
    maxDropHeight = 30,

    -- Standing.
    mobStandoff = 34,             -- from any mob, melee or ranged: abilities only, never within weapon reach (Chris)
    meleeBuffer = 10,             -- soft band past a melee mob's swing where spots are merely disfavoured
    castSafeGrace = 1.2,          -- no ability cast while the ground here goes hot within this: the cast animation roots the character
    orbBubble = 14,
    orbLeadBehind = 12,           -- studs past the crystal, on the far side from the orb, to stand while it comes
    bobHomeWeight = 0.02,         -- per stud from Bob's home point (band distance from him, toward the crystals)               -- studs round Bob's following orbs; they explode at contact and killed at 1.2 studs
    fanRadius = 85,               -- during the Champion's beam fan: out to here from the hub, between the lanes (100 was against the rocks: 4 studs/s while commanded 22)
    leashRadius = 122,            -- Champion arena: death past ~128 studs from the boss; the respawn point is 131-137 out
    bonusBoss = false,            -- after the last boss: stay for the bonus boss? Its arena is not mapped; off
    bonusVoteDelay = 2.0,         -- seconds after the vote appears before answering
    autoStandoff = true,          -- boss standoff from the measured ability range (Chris); the slider is the fallback until a cast has measured it
    autoStandoffOffset = 2,       -- studs inside the measured range
    autoStandoffMax = 70,         -- never further than this
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
    dodgeShoulder = 2.5,          -- spots within this of a box edge cost a little: the bot stopped on an edge and was grazed (5.1.51 had 1.5; 4.0 kept it in dodge mode near everything)
    slimShoulder = 1.0,           -- shoulder for `slim` hazards (a seed's slim value is their reach): the beam fans need their gaps            -- studs of warm edge outside a hazard
    dodgeLead = 1.2,              -- a standing telegraph counts as live this long before it fires
    dodgePathLead = 0.4,          -- a moving projectile's line: the time to sidestep
    dodgeDwell = 1.5,             -- a spot must stay clear this long after arrival (the big spike front: 100 studs/s, announced 1.4 s ahead)
    blink = true,                 -- reflex hop out of a lethal box that fires before a walk could clear it
    blinkMax = 8,                 -- studs, at most; an 8-wide beam needs 5.2 from its centre, and the other script's hop is barely visible
    blinkWindow = 0.6,            -- hop when the ground here goes lethal within this many seconds (0 = already live)
    blinkDoubleGap = 2.0,         -- a second hop inside the cooldown is allowed, once per twenty seconds, for a box already on us
    blinkCooldown = 5.0,          -- seconds between hops; kicks four and five came from hopping too often (3 s, chained)
    blinkPerMinute = 4,           -- and no more than this many in any sixty seconds
    stepBlockAt = 0.6,            -- a travel step is refused at or above this danger during the crossing (lanes at 0.5 may be crossed)
    pathLaneDanger = 0.5,         -- standing anywhere on a projectile's remaining lane counts this much: relocate, never sit there
    dodgeMoveAt = 0.15,           -- danger here at or above this: relocate
    dodgeHysteresis = 0.1,
    dodgeDangerWeight = 3.0,      -- the danger term is worth this much against pulls and distance: a lethal spot never beats a clean one
    dodgeDistanceCost = 0.008,
    dodgeSafeDistanceCost = 0.04,
    dodgeSafeWorst = 0.2,         -- a spot counts as clean only under this path danger (0.47 four studs away was being taken)
    dodgeWallLook = 24,           -- studs of wall look-out round every candidate spot
    dodgeWallWeight = 0.05,       -- per stud the mean free distance falls short of three quarters of that (melee mobs cornered the bot - Chris) -- among clean spots the nearest wins (Chris: the marker is the closest safe spot, in blink range when possible)
    dodgeFarScale = 1.6,          -- second look this many times further when nothing near is safe
    dodgeFarScale2 = 2.5,         -- and a third, further still
    dodgeOutwardWeight = 0.25,    -- when everything near is hot, prefer spots away from the target: back out
    dodgeMobRetreat = 2.5,        -- times the outward weight against mobs, and sideways costs more than straight back (Chris)
    dodgeInsideWeight = 0.85,
    dodgeStrafeWeight = 0.15,     -- preference for moving across the target's line rather than along it
    dodgeApproachWeight = 0.03,   -- pull toward the standoff band, per stud out of it
    dodgeArenaWeight = 0.04,      -- boss fights: per stud beyond the band plus twenty, and a flat two past forty-five (the arena mouth)

    -- Reader defaults for attacks with no seed.
    defaultFire = 1.5,            -- a telegraphed Model with no seed fires this long after it appears
    defaultLive = 0.6,            -- and hurts this long after firing
    fadeLinger = 0.55,            -- after its precast fades an attack is over this much later (Chris: the hit lands ~0.25 s after the visual looks done)
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
-- Per-boss behaviour, kept apart on purpose (Chris: the Champion and Bob
-- are separate; never mix the two). Everything attack-specific is keyed by
-- the attack name in TIMING and the reader; everything boss-specific is
-- switched here. Shared by every fight: the field, the blink, the measured
-- ability range, the mob rules.
--   Champion: arena pull (spots stay inside the arena), the beam fan reflex
--             (out to fanRadius between the lanes), the slam reflex, the leash.
--   Bob:      the circle chain line and per-step circles, the sweeping wall
--             from its model, the orb bubble; no arena pull.
local BOSS_PROFILES = {
    ["midgardian champion"] = { arenaPull = true, fan = true, slam = true, orbs = false, home = false },
    ["bob the frost giant"] = { arenaPull = false, fan = false, slam = false, orbs = true, home = true },
}
local DEFAULT_PROFILE = { arenaPull = false, fan = false, slam = false, orbs = false, home = false }

-- Bob's crystals: the orbs that follow the player explode on it unless led
-- into the crystal of their colour. Found by name under the crystal Model,
-- with the measured positions as the fallback.
local CRYSTAL_FALLBACK = { red = Vector3.new(-144, 23, 268), green = Vector3.new(-159, 23, 335), yellow = Vector3.new(-105, 23, 377) }
local crystalCache = {}
local function bobCrystal(colour)
    colour = string.lower(colour or "")
    local c = crystalCache[colour]
    if c and os.clock() - c.at < 5 then return c.pos end
    local pos = nil
    local holder = workspace:FindFirstChild("secondBossCrystals", true)
    if holder then
        for _, d in ipairs(holder:GetDescendants()) do
            if d:IsA("BasePart") and string.lower(d.Name):find(colour, 1, true) then pos = d.Position break end
        end
        if not pos then
            for _, d in ipairs(holder:GetChildren()) do
                if string.lower(d.Name):find(colour, 1, true) then
                    local p = d:IsA("BasePart") and d or d:FindFirstChildWhichIsA("BasePart", true)
                    if p then pos = p.Position break end
                end
            end
        end
    end
    pos = pos or CRYSTAL_FALLBACK[colour]
    crystalCache[colour] = { at = os.clock(), pos = pos }
    return pos
end
local function bobCrystalCentroid()
    local sum, n = Vector3.zero, 0
    for _, colour in ipairs({ "red", "green", "yellow" }) do
        local p = bobCrystal(colour)
        if p then sum, n = sum + p, n + 1 end
    end
    if n == 0 then return nil end
    return sum / n
end
local function bossProfile(name)
    return BOSS_PROFILES[string.lower(name or "")] or DEFAULT_PROFILE
end

local TIMING = {
    northernmageshot            = { first = 0.5, last = 1.5, holdFull = true },   -- mob attacks hit ~0.25 s after their visual looks finished; the fade must not end them
    spearmanstrikehitbox        = { first = 0.6, last = 1.5, holdFull = true },
    northernwarriorlinestrike   = { first = 0.6, last = 1.5, holdFull = true },
    northernwarriorcirclestrike = { first = 0.6, last = 1.5, holdFull = true },
    firstbosspassivebeam        = { first = 0.3, last = 3.5, holdFull = true },   -- lethal 0.3-2.1 s after appearing, held longer because a lane re-fires in the burst; the 5.1.51 window that killed the Champion in two minutes   -- hurts 0.3-2.2 s after appearing, and in the burst its lane re-fires every 1.1 s: a lane never expires while the burst lasts
    firstbossjumpslam           = { first = 1.5, last = 5.0, pad = 5 },   -- the Model appears at landing; deaths inside from ~1.8 s and 3.3 studs outside the 67-wide box
    secondbosscriclehitbox      = { first = 0.6, last = 1.6, pad = 10 },   -- precast-only cylinder (22/28/34 wide, growing with distance); hits 0.7-1.0 s after it appears, a body wider than the cylinder
    secondbosshorizontalbeam    = { first = 0.6, last = 5.0, slim = 2.5 },   -- killed 0.4 s before the old 1.1   -- 10x64x400 beams 23.5 studs apart marching across the arena
    secondbossspreadbeam        = { first = 0.9, last = 2.5, slim = 4.0 },   -- a hit landed 3.9 studs outside the 12-wide box (run 32)   -- a death landed 2.2 studs outside the 12-wide box (run 31)   -- killed 0.5 s before the 1.5 s default                            -- nine 12x64x400 spokes 20 degrees apart from Bob; gaps widen with distance
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
S.bossProfile = bossProfile
S.bobCrystal = bobCrystal
S.bobCrystalCentroid = bobCrystalCentroid
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
