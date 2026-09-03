-- core.lua - Version, services, CFG tuning, shared state tables, runtime flags, debug logging.
-- Module contract: receives the shared table S. Everything this module needs from
-- earlier modules is pulled into locals below; everything later modules need is
-- assigned onto S at the bottom. Load order is fixed by main.lua / build.py.
return function(S)

--[[
================================================================================
    DUNGEON QUEST REBORN - ADVANCED AUTOFARM
================================================================================
    VERSION : 4.12.1
    BUILD   : 2026-09-02

    VERSIONING RULES (semantic):
        MAJOR -> rewrite / breaking change to core architecture
        MINOR -> new feature, new UI element, new subsystem
        PATCH -> bugfix, tuning, constant change, refactor with no new behaviour

    Bump SCRIPT_VERSION and prepend a SCRIPT_CHANGELOG entry on EVERY edit.
================================================================================
]]

local SCRIPT_VERSION = "4.12.2"
-- Bump to throw away every learned attack timing in every save, once.
local LEARN_EPOCH = 2
local SCRIPT_BUILD_DATE = "2026-09-02"
local SCRIPT_CODENAME = "Aquatic Temple"

-- Newest entry first.
local SCRIPT_CHANGELOG = {
    { version = "4.12.2", date = "2026-09-02", notes = "Window. The shared state table is published as _G.DungeonAutofarmState while the script runs and cleared on destruct, so a live inspection tool can read what the reader classifies, which spot the dodge holds and what the mover is doing without a rebuild for every question. No behaviour change." },
    { version = "4.12.1", date = "2026-09-02", notes = "Stairs and walls. The tween mover stepped horizontally and never re-sampled the floor, and its single wall ray left the root centre three studs up and missed every riser beneath it - up a staircase it drove the legs into each step and physics fought back, and a flight that turns ninety degrees was hopeless. It follows the floor now: the floor under the next point is raycast each frame, the root is placed at its own measured height above it, a rise within the step height is climbed, and walls are read at knee and chest with the steerer's own step-versus-wall classifier. The dodge judged candidate heights against the root with abs(), which rejected any spot even a fraction of a stud downhill while allowing six studs up; heights are judged from the feet, asymmetric, and the walk sweep keeps the root's height above the destination floor so it clears stair risers. Pursuit no longer passes a waypoint until the one after it is in clear sight - with four-stud spacing and a four-stud advance radius it was passing every corner early and aiming through the inside wall - and a wall stall now goes round to the roomier side and keeps going that way, where it used to alternate sides and shuffle on the spot against a wall it could simply have walked along." },
    { version = "4.12.0", date = "2026-09-02", notes = "Restored from 4.11.3 as the base going forward. The 5.0.x rewrite is shelved under legacy/5.0.1 - it never ran in the real game and Chris judged 4.11.3 the one that was working decently. Nothing else changed in this version; the strip and the pathfinding fixes follow on top of it." },
    { version = "4.11.3", date = "2026-09-02", notes = "Harness only: the simulator logged a dead boss with a variable that did not exist yet, the error skipped the rebuild, and every run after a kill had no target. Fixed." },
    { version = "4.11.2", date = "2026-09-02", notes = "A Model tracked before its hitBox replicated was keyed by its bare name and armed as known live, and stayed that way. When the hitBox turns up it is keyed properly and given the timing that key knows; a window an event stamped on it is kept." },
    { version = "4.11.1", date = "2026-09-02", notes = "The laser's window stamp goes to the nearest Model whose key starts with model, not to whatever attack sits within the radius: in the harness a mage shot took it. And the simulator fires the criss cross in volleys round the player - Chris counts fifteen crossing the map at once in the real fight." },
    { version = "4.11.0", date = "2026-09-02", notes = "Aquatic Temple, from the capture and the place file. The boss's attack Models are renamed Model on the client - the laser precast, the orbs - so learning by name pooled them all into one window; a generic name is keyed with the hitBox's rounded size instead. The laser shot event says exactly when its line hurts, and that window is stamped onto the Model, held for it if it has not arrived yet, and kept as a zone besides. The first and last bosses' orbs are Parts with no hitBox, invisible to the index; their path from the event is the whole of the hazard. The third boss's smite and the second boss's damage parts become zones. The cube pylon shot is seeded from a certain hit at 0.8 seconds. And a learning epoch: one clean slate for every save, whatever build wrote it." },
    { version = "4.10.10", date = "2026-09-02", notes = "From the moment it exists. Chris's real capture of the Midgardian Champion, 2026-09-02: seven deaths. Five were the criss cross projectile at zero percent along its path with the dodge reading zero danger - the game places the body at its origin on the event, on the player, and it sits there hurting until its start time; the dodge had counted it only from the start. A scripted projectile now hurts from the moment it exists. One was the jump slam, a sixty-seven stud cube round the landing, at 1.8 seconds - seeded. And every beam and mage shot in that run was armed at 7.0 seconds, the moment it was removed: timing taught before 4.10.2 by whatever part was nearest, which made them floor for their whole life and drew the arena full of boxes. Learning from before 4.10.2 is dropped, and floor is no longer drawn - a box means it can hurt." },
    { version = "4.10.9", date = "2026-09-02", notes = "The stronger pull applies whenever the box is the approach - pursuit stopped at the edge of something - not only on the ring. Otherwise the quiet gap went by safe here at fifty studs, out of ability range, and the fight took four minutes that could take two." },
    { version = "4.10.8", date = "2026-09-02", notes = "The ring pull is three times the ordinary approach weight: at the ordinary weight the distance cost of an eighteen-stud move beat it and the character sat at thirty studs, safe here, while the sweep came round. And a target within eight studs with no path is walked to directly: the path to the standoff point a stud or two away was failing, which read as stuck, which blacklisted the spot and fled from it." },
    { version = "4.10.7", date = "2026-09-02", notes = "The ring is the box's to hold from wherever the last dodge left the character, not only from within a box-length of the boss: a dodge that ended eighty studs out during a burst left it standing there." },
    { version = "4.10.6", date = "2026-09-02", notes = "The hub's rhythm sets where to stand. While it fires, and for the last seconds of the gap before it fires again, the character holds a ring fifty studs out - far enough that a sweep's lines have gaps between them, which at twenty-seven studs they do not - and the ring is held from both sides. In the quiet it comes in to the ability standoff and casts. The radial cost applies only while the hub is actually firing: the rate stays up for ten seconds after a burst, and a cost that stayed with it kept the character out through the whole quiet gap, the one time it could have been casting. Pursuit does not walk in while the ring is held." },
    { version = "4.10.5", date = "2026-09-02", notes = "Two corrections to the sweep reading, from watching it in the harness. A hub's lines are the ones centred on it: a mage shot that happened to cross the boss was being counted as one of its beams and took over the hub's name, arming delay and headings. And the period is the interval between the lines of one burst; the ten-second gap between bursts was being folded in, which put the period at two seconds for the first half of every burst and made every predicted line come late - exactly when the hits were landing." },
    { version = "4.10.4", date = "2026-09-02", notes = "Fight from range. The enemy Models carry their own numbers - enemyStyle boss1, meleeDistance 4, aggroRange 50, moveSpeed 16 - and the script now reads them instead of guessing. An enemy whose style says boss, or that line attacks pass through, is a boss, and a boss is fought from ability range: the standoff is twenty-six studs, inside the thirty-stud ability radius and outside its melee, and the swing only goes if we happen to be in our own reach anyway. A mob's standoff is its body plus the melee distance the game gives it. The dodge's danger ring round an enemy is its melee, not where we stand, so standing at range no longer reads as danger. The stuck detector leaves the dodge's deliberate holds alone: it had been jumping the character into the pattern it was waiting out." },
    { version = "4.10.3", date = "2026-09-02", notes = "Two more from the harness. A scripted projectile is a hit candidate: where the game's own numbers put a spike right now. A hit while one rolled over us was pinned on whatever floor line we stood in, and that line learned a six-second window. And the Midgardian Champion's beams carry a window from the start - a pulse, 0.3 to 1.2 seconds after each appears - because nothing on them ever shows, and with no window every beam was a wall for its whole seven seconds: a burst of thirteen was a wall everywhere, the character froze at the arena edge, and the projectiles took it. The window is a hypothesis the game corrects: a certain hit at a later age widens it on the spot." },
    { version = "4.10.2", date = "2026-09-02", notes = "Read the sweep. Two things from the harness. First, a hit teaches an attack's window only when the blame is certain - the attack encloses us and no other does. An ambiguous guess used to stretch the window for the rest of the fight: the mage shot's 0.9 to 1.2 seconds became 0.9 to 6.9 from being blamed for beams, and every red line on the floor was a wall for eight seconds. That was the hitboxes that stayed longer than the attack. Second, the Midgardian Champion's beams are a sweep: the fight save parks them twenty degrees apart and the capture saw them every half second in bursts of four and thirteen, ten seconds apart. The hub now records each line's heading, and when the last two steps agree the next lines are placed before they exist - floor until their time, a line for as long as such lines have been seen to hurt. A hub whose expected volley is a whole period overdue is quiet, and the approach is allowed; before, an expected time in the past held the character out forever." },
    { version = "4.10.1", date = "2026-09-02", notes = "What the harness and the captures taught, written into the script. While a hub's gate is closed the character waits on a twenty-stud ring instead of drifting out to fifty-five, so the dash in and out fits inside a volley gap. Blame for a hit goes only to an attack that encloses us when any does - a mage line five studs away with a matching window was outscoring the beam we stood in. And the Northern Lands timings are seeded: mage shot and strikes arm at 0.85 to 0.9 seconds and are over by 1.2, and the passive beams keep burning after their warning fades - so the first cast of each is already handled, before anything is learned." },
    { version = "4.10.0", date = "2026-09-02", notes = "Stay out of the hub. In the Studio recreation of the Midgardian Champion, every remaining hit came with the dodge reading full danger and holding a safe box eighteen studs away: at melee standoff the character stands where every beam crosses, and two crossing beams cannot be cleared inside their telegraph. Pushed out to sixty studs it took no hits for a minute. So an enemy that long line attacks pass through is a hub. Each new line whose axis passes near an enemy is counted once; the rate over the last ten seconds and the interval between volleys are kept per enemy. Every candidate carries a radial cost - the chance a random line through the hub covers the spot, which falls off as width over the circumference at that distance, times the rate, over the dwell - and the approach to melee is allowed only when there is time to get there and back out before the next volley fires. Enemies that fire no lines are untouched." },
    { version = "4.9.9", date = "2026-09-02", notes = "A parked Model - dormant, or silent for half a minute - never gets the blame for a hit: the pool of fourteen beams at the arena centre kept being credited with hits from live beams passing through it, which woke the pool and stretched every beam's window to the length of the fight. And a learned window is trusted as it stands: the mage shot's line stays drawn for seven seconds after its single hit, and waiting for it to fade kept a dead attack on the field." },
    { version = "4.9.8", date = "2026-09-02", notes = "Candidate lines are sampled every two and a half studs now, up to eight samples, instead of at three fixed fractions. Three samples on an eighteen-stud line sit six studs apart and a mage shot is three studs wide: a line that stepped straight through one scored clean, and in the harness the character walked into shots it had correctly marked live." },
    { version = "4.9.7", date = "2026-09-02", notes = "Two from the harness. The boss projectiles' paths were failing the dodge's vertical test: a rolling body's centre rides its radius above the floor, the big spike's twenty studs up, and the tolerance reached ten - the path was there and ignored, and the hit landed with the dodge reading no danger. A path's vertical reach is now at least its radius. And FirstPart, the 217-stud trigger volume around the arena, kept being learned from a hit taken inside it despite the age guard; a big anchored part, or any anchored part sitting directly under Workspace, is never learned as an attack." },
    { version = "4.9.6", date = "2026-09-02", notes = "From the harness: a hit that lands after an attack's warning has faded and marked it over means that attack keeps hurting after its warning - the passive beams burn for four seconds after the precast goes. Such an attack is remembered by name (saved), and from then on its fade does not end it; only its learned window, a removed hitBox or the Model going away does. The simulator itself was corrected to the game's convention - the precast fades at the instant the hit begins - after it was caught teaching the learner that beams arm at 5.4 seconds." },
    { version = "4.9.5", date = "2026-09-02", notes = "Every hit in the capture now records what the dodge believed at that instant - its danger reading, its reason, whether it had a box, whether it was waiting for a gap or holding pursuit, and the HUD status. From the Studio harness: the hit rate against the recreated Midgardian Champion fell from about ten a minute to five after 4.9.4, and the remaining hits need to be explained one by one rather than tuned away." },
    { version = "4.9.4", date = "2026-09-02", notes = "From the Studio harness, three things the real Northern Lands fight also has. The 217-stud invisible cube around the boss arena was being learned as an attack after a hit - the age guard used the index timestamp, and parts present before the script started never get one - which put the whole fight inside danger; nothing arena-sized is an attack now, and a part with no timestamp counts as old. The 14 passive-beam Models parked at the arena centre, never shown and never moved, read as live for the whole fight - a permanent wall through the middle; a ground-truth Model that has shown nothing, not moved and not hit us for ten seconds is dormant, and moving, showing, a hitBox change or a hit wakes it as a fresh spawn. And the enemy attack name table held generic names - meshpart, ball, wave, ice - that matched map geometry; they are gone, and structure still catches the attacks." },
    { version = "4.9.3", date = "2026-09-02", notes = "Blame, from the Studio harness: a hit was credited to the nearest known attack, and a beam that appeared a fifth of a second ago through where we stand is nearer than the one that has been burning us for a second. That taught every beam to be live from 0.2 seconds and made the whole arena walls. Attribution now scores candidates - the part encloses us, it is old enough to have fired, it is armed and not over, its learned window covers this moment - and the capture line says who was blamed and why." },
    { version = "4.9.2", date = "2026-09-02", notes = "Found in the Studio test harness on the first run: the highlight renderer keyed its adornments with the debug-id API, which needs plugin permissions there and threw every tick - after the scan had built its volumes and before the dodge decided, so the dodge never ran once and the character stood in beams reporting no danger. Parts are keyed with a weak-table counter now, and the highlight and telegraph-feed renderers are walled off in pcall: nothing cosmetic can take the dodge down again." },
    { version = "4.9.1", date = "2026-09-02", notes = "The capture from the second Northern Lands run found the number that killed it: every mage shot and line strike carried a saved arm delay of about seven seconds, learned by 4.5.1 from the Model being deleted at 7.0s as if that were the precast fading, so each one was floor for its first 5.7 seconds. Learned timing and auto-learned names from saves written before 4.9.1 are discarded on load; hand picks and the attack book are kept. The same capture showed what a mage shot actually is: nothing visible for its first 0.6 to 0.9 seconds, then the precast appears and a second channel switches on at the very moment the hit lands. That is what the hit-window learning from 4.9.0 is for, and with the poisoned seven-second delay gone it can do its job. A part that has stood in the world for twenty seconds is never learned as an attack - a map part called FirstPart was." },
    { version = "4.9.0", date = "2026-09-02", notes = "Learn from the hit. The capture from Northern Lands settled it: for every mage shot, line strike and passive beam the precast part sat at Transparency 1 for its entire seven-second life, the hitBox stayed until the game deleted the Model, and nothing the tracker watched ever changed - so every one of them was a seven-second wall regardless of when it actually fired. Two answers. The tracker now watches every channel an attack can show through - part, Decal and Texture transparency, ParticleEmitter, Beam, Trail, Gui and Highlight enabled, Sounds playing, parts arriving, the hitBox changing - and writes each attack's own timeline into the capture file. And being hit, the one signal that is never ambiguous, teaches the attack its window: the first and last age at which it has hurt us, saved by name, so from the next cast on it is floor until the lead, danger through the window, and floor again after. A hit is blamed on the nearest known attack by its nearest point rather than its centre, so a 274-stud beam whose edge is on us gets the blame. Two other things from the same run: a part named after the player under workspace.stunParts - a stun marker riding on the character - had been learned as an attack, a hazard that followed the character everywhere; and in the Enchanted Forest the appearance scorer was highlighting crystals and glows by the dozen for a minute at a time, which was itself a frame cost. Decoration names never pass the scorer now, and anything flagged on looks alone that is still there after twelve seconds is scenery for good." },
    { version = "4.8.0", date = "2026-09-02", notes = "Gone means gone. Attacks stayed red for four or five seconds after they had visibly finished - the hammer bots' most of all, and most of the Steampunk boss's - and the character guided itself along them like invisible walls. Three bugs and two gaps in the arming code. The precast's darkest transparency was tracked only while the attack was pending, so anything that armed the moment it appeared - live-from-spawn attacks, which a pulsing precast produces - never had a minimum to compare its fade against, never counted as over, and stood until the game deleted it. Expiry now tracks every visible part from the first frame and follows the game's own rule: an attack is over when everything visible about it has faded to transparent or been removed, or when its hitBox - the part that hurts - is gone while the rest lingers for effects. Attacks split across sibling Models borrow the parent's visuals. Anchor parts and decoration inside a hitBox Model are not hazards at all: the four-stud PrimaryPart at the centre of every attack was a hot spot. Stairs: every forward probe now runs through the step-versus-wall classifier the direct steerer already had, so a riser under 2.4 studs is stepped onto rather than steered around - the shin-height probe added for the pillar plinth had been reading every stair riser as a wall and walking the character diagonally up each flight. And two things found reading: the mover's watchdog permanently rewrote the Movement setting to walk after one second against anything, which a cornered character always is - it borrows walk for three seconds now; and the wall-stall sidestep could fire on the first tick of a new path from an anchor left over from the last one." },
    { version = "4.7.0", date = "2026-09-02", notes = "Steampunk knows too. The Northern Lands module is now the boss-events module: one listener per map remote, hooking every one it finds - northernBossSpecficEvents, steampunkBossSpecficEvents and the shared mapSpecificEvent so far - with a handler table per map. Read from the Steampunk Sewers client handler and the Evil Scientist's models live in Studio: Drop Cogs tweens every cog part a hundred studs straight down over three quarters of a second, so each landing footprint becomes a cube zone with the exact time; Back Flames lights its flame jets half a second after the event for a second, so each jet is a zone with the exact window. The rest of the kit - the six-beam pulse wave that is the lattice from the video, the five concentric outward blasts, the punch circle, the zig-zag, the orb shot, the cannon and horizontal beams, the ball - are server-spawned Models and arm through their precasts. Two of those are seeded so the first cast is time-aware without being learned: the pulse-wave beams fire 4.8 seconds after their strips appear, seeded at 4.5; the ball is live from the start." },
    { version = "4.6.0", date = "2026-09-02", notes = "Northern Lands knows. Read from the game's own client handler for northernBossSpecficEvents and from the attack models live in Studio: every timed attack of the three bosses and the bonus boss is sent to the client before it happens with the numbers the client animates it with, and those numbers are the attack. The script now hooks that remote and reads the game's own synced clock. Rolling projectiles - the criss cross, the seeking spike, the big spike, the moving beam, the sideways missile - become scripted paths: the dodge asks where each one WILL be at the moment it would be somewhere, from start, distance and duration, instead of extrapolating a mesh from two frames of motion. Ground spikes become circles with exact impact times and the spike's real radius. Orb beam pillars are zones held open for their six seconds. The bonus boss's tall swirly registers the arena explosion at its exact time and turns the matching colour spots into a timed safe window - outside them is the danger, but only around the explosion. The flame marker that follows a player is never a hazard itself; the flame lands where it stops. Spearman and warrior line strikes are cubes. Precasts that rest fully invisible and are faded in by the server - the lattice of secondBossLines, the sweeping flames - are live until they show and a telegraph from then, instead of live forever. The full model table is in game/attack_models.txt." },
    { version = "4.5.1", date = "2026-09-02", notes = "Two things from two screenshots. A played-out attack is nothing now: a precast that was visible and has faded all the way, plus a short linger, marks its attack as over, and it leaves the detected set - no danger, no highlight, not in the count. The strips of a beam pattern stayed red for seconds after the beams had fired and the dodge kept weaving between attacks that were over. The amber colour and the tag are honest now: amber and floor 2.3s only while the dodge actually treats the part as floor, arms in when its impact is within the lead, announced when its timing is unknown and it is being dodged as live. A hit taken while announced saves that attack as live-from-spawn permanently rather than letting it be re-learned from its fade next session. And the wall: every pursuit probe looked at chest height, and the plinth of a pillar is below that, so the probes said clear, the feet hit the plinth, and the character stood into the wall. Forward, side and segment probes have a shin-height ray now, and a character that has stopped moving on a path for more than a moment sidesteps, alternating sides, hops, and lets the path recompute." },
    { version = "4.5.0", date = "2026-09-02", notes = "Telegraphs are floor. The boss arena was a lattice of red strips for five seconds before a single beam fired, and the dodge treated every strip as live from the moment it appeared, carving its safe ground into slivers to avoid attacks that were not happening - the video showed forty-one telegraphs and the character weaving between strips at 1.5 seconds old that fired at 4.8. The game's own client script says how to tell: every attack is a Model with an invisible hitBox and a visible precast, and the precast is faded OUT at the instant the hit lands. So a visible precast is a telegraph, the fade is the hit, and a hitBox that moves is live regardless. Each attack's arming age is learned by its Model name and saved, so the next cast is time-aware from the moment it appears: floor until its lead, then danger. The first cast of anything is still dodged as if live, and a hit taken while an attack reads as a telegraph makes that attack live from spawn from then on. Announced-but-not-live parts are drawn amber with arms in 2.3s on the tag and turn red the frame they arm. And the floor probe now starts just above the root rather than four studs up: under the pipes of a boss room it was reading a pipe as the floor and rejecting every spot - waiting for a gap with nothing wrong but the ceiling, in the corner the character then died in." },
    { version = "4.4.1", date = "2026-09-02", notes = "Two numbers from 4.4.0 were wrong in the same direction. The enemy circle was body plus swing at 1.5, and enemies were extrapolated by their velocity out to the dwell - so a mob walking at you was predicted onto every spot near you and the only safe ground was always further back: the character kited two idle melee bots backward into a wall two rooms away. The hard circle is the body and nothing more now - the swing is an attack, and the game spawns a hitBox for it that is detected like any other - with a soft ring out to the standoff as a preference, and enemies are extrapolated 0.4 seconds ahead at most. And inside the boss's ball the exit was chosen sideways and slowly: the discount that ended the shuffle zeroed every path sample inside the ball, so nothing said shortest time inside, and the new turn cost then picked the exit by whichever way the character had last walked. Path samples inside the thing already hitting you keep half their cost in the average, so three samples in the ball cost more than one and the nearest edge wins; the turn cost is switched off while something is on you; and the pull toward the boss applies only to spots whose whole line is clean, undiscounted, so the exit nearest the boss cannot beat the exit nearest the edge." },
    { version = "4.4.0", date = "2026-09-02", notes = "Pick a side. The left-right shuffle against a sweeping beam had a cause 4.3.0 made worse: standing inside the beam, every line out starts inside it, so the new line check read every held box as closed the moment it was chosen and the choice re-rolled between two identical sides each decision. Path samples now discount whatever is already on you - what is hitting you is not a reason to prefer one way out over another; how soon the line is clear of it is - and a change of direction costs, a reversal most, so the side picked first is kept until the other is clearly better, which a closed line always is. Enemies outrank attacks at 1.5 against 1.0: a line through a mob loses to a line through an attack and is taken only when everything else is worse, so it no longer strafes out of an attack into a mob, and cornered with the mob as the only way out it goes through the mob. The enemy is the distance: the Safe distance and Enemy space sliders are gone, and the chase and the dodge both stand at the enemy's body plus a swing, capped by your own attack range so it can always reach. The walk into the boss had three causes: the pull toward the target was applied to dangerous spots too and was decisive in a crowded field, so the nearest-to-the-boss won - it applies among safe spots only now; the raycast budget cut off at twelve and a crowded field whose twelve cheapest spots all failed left nothing, so the blind fallback ran - it keeps checking until something safe passes; and the blind fallback itself read fields its entries do not have and fled the first enemy in the table rather than the nearest. Pursuit holds while the dodge is waiting for a gap - five clear studs at a time was how it walked into a pattern one step per tick. Pursuit goals are kept off walls: two hip-height side rays push the goal off any wall closer than the character's clearance, and the dodge's walk check is a body-wide sweep rather than a centre line. Legacy is called Pathfind." },
    { version = "4.3.0", date = "2026-09-02", notes = "Nothing is held. The box had hysteresis, and the hysteresis re-read danger at the box and nowhere else - so an attack placed between the character and the box did not exist as far as the held box was concerned, and the character walked its straight line into it while a step to either side was open. The bots that beat bullet hells commit to nothing: twinject, the Touhou player, re-picks its velocity every frame from scratch. The box now survives a decision only while every sample along the line to it and at it still passes; otherwise it is dropped on the spot, the field is re-read, and the re-read prices the straight line, which is what puts the new box to the left or the right. Pursuit is back underneath the dodge: 4.2.0 had dropped it outright so the bot could no longer cross a room. The loop only reaches pursuit with no box to follow, and even then it gets a step only if the next few studs of its route are clear; when they are not it holds and the box, told pursuit is blocked, picks the way in one safe spot at a time. Near the target the box is the approach as before. Macros are gone - the recorder, the player, the file, the island option, the Routes section and their settings - and the island is Legacy or Dodge. Section headers and the well their rows sit in are darker than the rows now, so a setting and a list of settings no longer look the same." },
    { version = "4.2.1", date = "2026-09-02", notes = "The HUD status names the active mover in brackets - DODGE waiting for a gap [tween] - so whether it is tweening is answered by looking rather than guessed from how it moves. The Movement dropdown at the top of the Dodge section switches between tween, walk, steer and velocity; tween is the default and nothing in a saved config overrides it unless one was saved on an older build." },
    { version = "4.2.0", date = "2026-09-02", notes = "Bullet hell. The HUD showed forty-two telegraphs detected and the whole floor red with the box on a lethal spot, so detection was working and the dodge was being handed a field it could not read. Three causes. The mesh-swarm clustering from 3.0.5 merged a boss pattern of forty hitBoxes under one Model into one bounding box the size of the arena, so every candidate read as lethal and the pockets between bullets did not exist as far as the dodge could see - exact attack geometry is never merged now. The candidate score was the worst of its five samples, which in a busy field is 1.0 for every candidate with no gradient left, so the nearest won; it is now half the worst and half the average, and a spot hit at one moment beats one hit at every moment. And pursuit walked straight through the pattern to get in range: the box is the approach now, drifting toward the target only across safe ground and waiting when there is none, which is what a person does in a bullet hell. The field is denser too, four rings of twenty-four, because the pockets are small." },
    { version = "4.1.1", date = "2026-09-02", notes = "Why the same attack was noticed once and never again: an attack aimed at the player spawns at the player, a moment after we swung, and the own-attack timing heuristic claimed it as one of our own effects. The capture showed it plainly - the cogs of a Cog Shooter shot spawned at the enemy and were dodged, the precast of the same shot spawned on us and was waved through. Ground truth now beats timing: a structural or named enemy attack, or anything inside a creature, is never marked as ours. Enemies are judged where they will be, not where they are, from their own velocity, so the character backs away from an advance instead of sidestepping into whatever is beside it; big bosses widen their circle by their body so a stomping leg counts. And walls are pockets now, not just obstacles: three rays from each candidate - ahead and to both sides - price how little room lies past it." },
    { version = "4.1.0", date = "2026-09-02", notes = "Most attacks were being dropped one line after being detected. 3.4.0 made classification structural so the invisible hitBox that actually damages you became a candidate - and the per-frame scan had its own transparency gate that threw it out again every frame. The precast showed, the precast faded, and the damage volume underneath was never dodged. Parts the game says are attacks are stamped as ground truth at classification and exempt from that gate. Creature body parts were reaching the appearance scorer whenever they sat inside a nested gear Model, because the creature check looked only at the nearest Model; it walks every ancestor now. Every hit names what was next to you, writes it into the capture, and learns an unknown culprit by its model name, so damage teaches detection again. The dodge charges extra for a spot with a wall right behind it - a pocket you cannot keep fleeing from - which is what stops the character reversing into a corner or a prop. And the search range is drawn as a ring." },
    { version = "4.0.0", date = "2026-09-02", notes = "The dodge is rebuilt from scratch around the thing that actually works in a few hundred lines: a box that is never in danger, and a character that follows it. clone.lua and threat.lua are gone - the 900-cell grid, the heat field, the space-time A*, the enclosure, cover, depth, freshness, hysteresis and slicing passes, and seventy-nine settings with them. What remains is 1009 lines across dodge, mover and precast. A few dozen points around the character are checked twenty times a second for what lands on the way there and what lands once you stop, at the moments those things happen, using exact geometry and timing for announced attacks, the footprint for physical ones, a swept segment for anything moving and a circle for every enemy. The box goes on the best point; the character goes to the box. There is no path: deciding every frame and moving exactly, the straight line is the path, and the on-the-way check is what keeps that line off anything that lands while you are on it. Ground truth detection, the precast listener and the collision-checked tween mover are kept unchanged." },
    { version = "3.6.2", date = "2026-09-02", notes = "Why steer and velocity both stood still: nothing was disabling Roblox's default control module. It calls Humanoid:Move every frame from input - with no keys held that is Move(zero) - on RenderStepped, BEFORE physics, while ours lands on Heartbeat after. Its stop is what physics sees. MoveTo survived only because it is a separate persistent mechanism. Tween is the default now, because writing the CFrame is the one path the control module cannot argue with, and it is what a script that tweens to a marker is doing. It is capped to the distance the character could actually have walked this frame, so the speed a server sees is ordinary walking speed, and each step is raycast so it never passes through anything - clipping through a wall is the one genuinely conspicuous thing about moving this way and it is now impossible. The Move-based modes take the player controls while they run and hand them straight back." },
    { version = "3.6.1", date = "2026-09-02", notes = "Fixes the regression 3.6.0 shipped. The new velocity mover wrote the horizontal velocity and then called Humanoid:Move(Vector3.zero) on the very next line - and Move(zero) is an instruction to BRAKE, which the Humanoid re-applies every physics step. The two fought and the Humanoid always wins, so the character stood still in the middle of attacks. Both must be told the same direction; then the Humanoid handles animation, footing and slopes while the direct write removes the acceleration ramp. The default is now steer, which is plain Humanoid:Move with a direction: it still fixes the arrival tolerance and the re-planning that made MoveTo miss, and it cannot stall because it is the Humanoid driving itself. And a watchdog - any mode that is asked to move and produces no movement for a second falls back to walk, so a mover bug can never again strand the character inside an attack." },
    { version = "3.6.0", date = "2026-09-02", notes = "Every dodge was issued as Humanoid:MoveTo, and that is most of why the dodging looked broken however good the decision was. MoveTo accelerates for about a quarter of a second, arrives only within roughly two studs, and re-plans on every call - so in a three-stud gap between two beams it arrives late and off the mark. Standing in the middle of attacks, stopping at the edge of one instead of going around, and scraping along walls are all descriptions of an actuator failing rather than a chooser failing. Movement is now selectable: walk is the old MoveTo, steer uses Humanoid:Move, velocity writes the horizontal assembly velocity directly for instant direction changes and exact arrival while physics still applies, and tween steps the root CFrame for stud-exact movement that ignores collision. Velocity is the default. Also added Simple mode: the clone system has sixty-eight settings and they have repeatedly been caught fighting each other, so Simple turns off every heuristic that has done so and leaves exact geometry, exact timing and precise movement." },
    { version = "3.5.2", date = "2026-09-02", notes = "The shuffling on the spot with clear ground in sight had three causes and they compounded. Goal choice took the plain argmin, so two near-equal cells traded places as the field updated and the bot took a step toward each in turn; a new goal must now beat the held one by a margin. A full A* ran EVERY FRAME - sixty times a second - against a goal that changes a few times a second, so the route wobbled and MoveTo was re-issued at a slightly different first step each time; the path is reused between plans now and only rebuilt when the goal moves, the window slides, the next step goes lethal, or a short interval elapses. And since 3.2.0 only a slice of the grid is re-measured per pass, so cells carry answers of different ages - a stale cell that looks wonderful wins, gets refreshed, turns out terrible, and another stale cell wins instead. Measurement age is now a cost in the score." },
    { version = "3.5.1", date = "2026-09-02", notes = "Two things in the new cover code were wrong, found by watching a clip of the Midgardian Champion. The cover ray was cast from the soonest announced zone rather than the enemy, and a fan of beams is a dozen separate zones - a ray from the middle of one beam to a cell says nothing about whether anything is shielding you. The boss is where the beams converge, so the nearest enemy is the origin outright and a zone is only a fallback when there is no enemy. And enclosure was fighting cover: pressing against the thing shielding you is the entire point, but enclosure counts any solid neighbour as heat, so it shoved the bot back out from behind the pillar into the open where the beams are. Covered cells are now largely exempt from it." },
    { version = "3.5.0", date = "2026-09-02", notes = "Space-time A*. Each cell stores its heat at three fixed moments and the search interpolates for the time it would ACTUALLY arrive, having gone round whatever was in the way - so a telegraph that goes live while we are still crossing now costs us, where sampling at the straight-line ETA said the cell was fine. Arrival time is carried alongside cost through the search, which makes the space (x, z, t) rather than (x, z). Cover: one ray from the dominant threat origin to a cell says whether something solid is in the way, and cover discounts that danger rather than inventing safety - when a radial burst fills the arena there is no open safe ground and a pillar is the answer, where the grid used to see pillars only as obstacles to route around. And being enveloped no longer stops it: every branch that used to give up - no goal, no route, or a best cell that is the one you are already standing in - now runs on a bearing anyway, because nowhere better existing is not a reason to stand in an attack." },
    { version = "3.4.0", date = "2026-09-02", notes = "The capture found it. In this game the hitBox - the part that actually damages you - is created at Transparency 1, fully invisible, exactly as GAME_NOTES records for PrecastHitbox. And isDamageBrick rejected anything at 0.99 or above BEFORE checking a single name, so hammerBotHit.hitBox and spinBotSpin.hitBox were thrown away with their names sitting in the table, never reached: 895 of 900 parts missed. Appearance scoring was overruling ground truth. Detection is now structural and runs first: a part whose name or ancestor model is a known attack, or a hitBox/precast inside any non-character model, is an attack whatever it looks like - which also generalises to bosses nobody has dumped, since every attack in the game is built that way. Transparency and the CanCollide gate now apply only to the guesswork underneath. Own-attack learning can no longer claim shared grammar names like precast or hitBox, which would have poisoned every attack in the game at once." },
    { version = "3.3.0", date = "2026-09-02", notes = "Attack capture: Record what spawns logs every part that appears near you along with the verdict, then Save capture writes it to a file. A place file says what exists in ReplicatedStorage; it does not say what a part is named, parented or shaped when it actually spawns in a fight, and both dumps had an empty Workspace.enemies - so misses have been diagnosed by inference twice and got it wrong twice. The misses are the point: a part judged harmless appears in no other log. Enclosure: cells inherit a share of the heat around them, so a green pocket ringed by red reads hot because it is a trap, and walls count as heat so corners do too. Open ground now beats an enclosed pocket of equal local safety, which is what stops the bot backing into a corner instead of strafing out. And adaptive lookahead, taken from the standalone heatmap prototype: horizons stretch when WalkSpeed is low, because a slow character cannot dodge reactively and has to see danger earlier." },
    { version = "3.2.6", date = "2026-09-02", notes = "The pathfinding window is a circle rather than a square. The corners of a square are its furthest cells - 1.4 times the radius - so they were the least useful ground in the grid and the most expensive to path to, and they were a quarter of the total work. Dropping them costs nothing and buys about three more studs of sight for the same cell budget: 24 studs instead of 21 at the default. The cell array stays square because the indexing is arithmetic; the corners are simply never active, never measured, never drawn and never routed through - and because they are never measured they cannot be mistaken for walls by the edge pass." },
    { version = "3.2.5", date = "2026-09-02", notes = "Every boss attack in the game was missing from the name table. Bosses keep their attacks in a subfolder of their own - enemyProjectiles.Steampunk.bossCannonBeam and so on - and the table was built from top-level children only, then dropped Folders to avoid picking up gear, which threw away 111 attack models. Rebuilt recursively from both dumps: 519 names, up from 238. Every one of those models is built the same way, a PrimaryPart plus a hitBox and a precast, so those two names now catch attacks from bosses nobody has dumped. Two fixes for being cornered. The grid only sees about twenty studs, so boxed in with attacks filling all of it the clear ground was invisible and the bot settled for the least bad corner; when the whole window is hot it now samples bearings well beyond the grid and heads for the coolest. And the ordinary stuck detector is switched off while dodging, so nothing at all was watching for the character being wedged between a wall and an enemy - it now hops, drops the goal and marks the obstruction impassable." },
    { version = "3.2.4", date = "2026-09-02", notes = "The drifting yellow circles were the wall-edge pass treating cells the slicing had not reached yet as if they were walls. Since 3.2.0 only a slice of the grid is measured per pass, so after every window shift most cells are simply unknown - and each freshly measured cell next to one was being given edge heat of 21, which is 38 percent of lethal and lands exactly in the yellow band. It now only counts neighbours that have actually been measured and found impassable. Separately, heights were compared against the root part centre rather than the floor underfoot, and the root sits about three studs up: Step height 2.5 really described a rise of five and a half, so the slider said one thing and the grid did another. It measures from the floor now." },
    { version = "3.2.3", date = "2026-09-02", notes = "The basic attack no longer needs the mouse. The weapon is a Tool whose Activated event the server handles, and Tool:Activate() raises that same event straight from the client - no cursor involved, so there is nothing to press by accident and nothing to fight the player over. Auto uses it whenever a weapon is equipped and falls back to a click otherwise; Tool only never touches the mouse at all. And when a click IS used it goes to the middle of the viewport rather than wherever the cursor happens to be resting, which is what made the bot press buttons. Allow auto-clicking is the off switch." },
    { version = "3.2.2", date = "2026-09-02", notes = "Terrain is a threat now, not just a floor check. The grid only ever asked whether a cell had a floor within reach, which says nothing about whether you can get there: a wall has a floor, and so does a ledge you would have to jump onto. Both read as open ground and the bot found out by walking into them. Cells are probed upward through the space the character would occupy, so anything solid standing there is out; a rise above Step height is reachable but charged Wall threat in proportion, because a jump mid-fight is a moment spent not dodging. Ground beside anything impassable is warmed too, so the cheapest route stops hugging walls, which is where you get cornered. Wall threat, Step height and the edge warming are all adjustable." },
    { version = "3.2.1", date = "2026-09-02", notes = "Projectiles were using the ground-attack urgency ramp, which got the timing wrong in both directions: a corridor a shot reached in two seconds read as 12 out of 100 so the bot strolled into it, and the ground BEHIND a projectile stayed at 100, so it fled the safest place on the map. A projectile is dangerous in a WINDOW around the moment it passes, not on a ramp. The core of that window is geometric - the projectile width plus yours, over its speed - so a fast shot is lethal for a fraction of a second while a wide slow tornado owns the ground for seconds either side, from one formula. Around it sit a generous lead, because being early is how you get hit, and a short wake, because gone is gone. Also added a Recommended settings button that resets the whole Clone section to the tuning arrived at so far." },
    { version = "3.2.0", date = "2026-09-02", notes = "Performance. getPlayerHitboxMetrics was being called inside the per-cell threat query, which at 900 cells and two time samples was 3,600 Instance lookups per evaluation, twelve times a second, re-deriving numbers that had not changed - it is computed once per pass now. The two time samples walk the threat sources once instead of twice, halving the dominant cost. The grid is evaluated in SLICES with verdicts persisting between passes, so a large radius no longer has to judge every cell inside one frame. A* stopped clearing four arrays of 900 entries on every call (a quarter of a million pointless writes a second while dodging) in favour of a generation stamp, and its open set is a real binary heap over parallel numeric arrays rather than a linear scan. Painting writes only the properties that actually changed. Separately: the safety probe is now its own setting rather than the drawn disc - probing with the whole body including limbs made the grid blind to any pocket narrower than your shoulders, which is why small safe zones went unseen." },
    { version = "3.1.2", date = "2026-09-02", notes = "A delayed attack is harmless until it nearly lands, and the squared urgency ramp did not say that - it went lethal a FULL SECOND before impact, which quietly turned every marker into a wall. With attacks overlapping, walls everywhere means no route at all; a gradient always leaves somewhere to flow to. The ramp is now cubed and adjustable, so a marker reads green through most of its wind-up and reddens hard at the end. Goal choice weights the heat where you WILL be over the heat where you land, because a square that is cool now and hot in a moment is a trap. And when nothing is safe at all it stops committing to a destination and simply flows downhill every pass, which is the behaviour that survives a saturated field. The discs are a nine-band ramp now - dark green, green, yellow-green, light yellow, dark yellow, orange, red - because across hundreds of discs a two-stop blend cannot show the difference between cool and coolest." },
    { version = "3.1.1", date = "2026-09-02", notes = "Two fixes. A projectile is a line through space and time, not a place: a moving hazard now heats the whole corridor it is about to sweep, weighted by whether it arrives there about when you would, so the ground in front of an oncoming shot stops reading as perfectly cool. Tornadoes and other slow drifters count too, at a much lower speed bar than the sidestep reflex uses. And the bigger one - entering evasion at all was still decided by the OLD binary test, so a heat-40 square was called safe and the bot skipped dodging entirely to go pursue an enemy through it. The field was being computed and then ignored for the one decision that matters. In Clone mode any heat at or above Move at heat now means relocate." },
    { version = "3.1.0", date = "2026-09-02", notes = "Safety stops being a yes or no and becomes heat: a number from 0 to 100 at a point AND at a moment, so the same square is cool now and lethal in a second. In a fan of radial beams every square is unsafe, a boolean leaves the search nothing to choose between, and the character stands still and dies - a scalar field always has a least-bad answer and the gaps fall out of it for free. New ThreatManager combines announced attacks (exact geometry and impact time, ramped by an urgency curve), live hazards, enemy circles and inverted safe-spot markers. The grid search is now A* with F = G + H + threat*weight, where the weight is literally how many studs of detour one point of heat is worth; cells above the lethal threshold are impassable, and if every route crosses one it re-runs allowing them rather than standing still. Projectile steering sits underneath as a per-frame reflex, shoving sideways out of the path of anything already in the air. Discs are drawn as a green-amber-red gradient." },
    { version = "3.0.5", date = "2026-09-02", notes = "Attacks built from hundreds of meshes no longer melt the frame. A dense group of parts under one model collapses into the single box it effectively is - nobody threads between the meshes of a lava pool - so the safety tests run against a handful of volumes rather than every part, and highlights and name tags are capped to the nearest few instead of drawing three hundred BillboardGuis. Chasing also keeps its distance now: the grid drew a circle around every enemy and called it unsafe, then the pursuit walked straight through it into melee using its own smaller stand-off, so the dodge kept its distance and the chase gave it back. Attack reach scales with the stand-off so it does not close the gap merely to swing." },
    { version = "3.0.4", date = "2026-09-02", notes = "One line was hiding most attacks: isDamageBrick rejected any part parented straight to Workspace, on the theory that a real attack lives inside a model. This game does the opposite - PrecastHitbox does Part.Parent = workspace literally, and so do the boss beams - so that veto was throwing away exactly what mattered. Loose parts fall through to the appearance test now. Workspace.vfxPool holds the player OWN pooled hit effects under generic names like Part, which is why the bot fled from its own ability the moment it landed; anything in that pool is ours. Defaults retuned now that the footprint is measured honestly: disc scale back to 1.0, safety margin 0.75, depth bonus 1.5, enemy space 12 and 20." },
    { version = "3.0.3", date = "2026-09-02", notes = "Enemies get a circle of their own: melee does not telegraph, being next to one IS the attack, so cells within Enemy space are unsafe and cells out to Enemy spacing are expensive. Two fixes for the dithering. The committed goal was a window INDEX, but the window is centred on the character and slides as it walks, so the goal silently moved to a different place every time you crossed a cell boundary - it is a world key now. And a cell was judged only at the instant of arrival, so somewhere an announced attack would land a moment later read as green: the bot walked there, stopped, and died. A cell must now stay safe for Must stay safe for seconds after arrival to count as a destination, with a fallback to merely-safe so a moment with something inbound everywhere never returns nothing." },
    { version = "3.0.2", date = "2026-09-02", notes = "The grid was padding every attack by 3.5 studs beyond the body, because it borrowed CFG.damageBrickClearance from the Legacy escape - which commits to one dash, where a fat hedge is cheap. On a dense grid that padding stacks, and three overlapping attacks left nowhere green to stand. Red now means your body would actually be in it, plus only the Safety margin you dial in. The footprint is measured from your body parts rather than GetExtentsSize, so a big cosmetic or held weapon no longer inflates it, and it is re-measured on a timer and carried in the grid signature - it used to be sampled once at build, so the only thing that ever corrected it was dying. Fixed the flicker: a window shift blanked every verdict and repainted before the next evaluation, and at 1.5 stud spacing you cross a cell about every 0.075s against an 0.08s interval, so it blanked on nearly every frame you moved." },
    { version = "3.0.1", date = "2026-09-02", notes = "Three fixes to 3.0.0, all found from one in-game log. RT.connections never existed: the dungeonName watcher threw on it, which also meant the ability-remote hook below it never ran at all. The precast readout was rendered once at build and never again, so it read zero however many attacks had gone past. And the payload handler dropped anything it could not read without a word, so 'Listening' and 'nothing is arriving' looked identical - it now counts every payload, prints the first three key by key, and finds the shape name even if the compressed key is not the one we asked for." },
    { version = "3.0.0", date = "2026-09-02", notes = "The script stops guessing what an attack is and listens to the game tell it. ReplicatedStorage.modules.PrecastHitbox broadcasts every ground attack on a BridgeNet2 bridge with its exact shape, position, and delayUntilAttack, so time to impact is arithmetic and each clone-grid cell is now judged at the moment you would arrive there rather than right now. 238 enemy attack names and 293 of our own are read from the game as tables, which is the mine-or-theirs question the appearance scorer used to guess. Safe-spot bosses are handled: the markers that mean STAND HERE are attractors, where before the dodge walked you out of the only survivable circle. The map follows Workspace.dungeonName, enemies are scanned from Workspace.enemies, and our own casts come from the abilityCast remote rather than animation watching. Removed: freeze, trial-run damage learning, and the recommendation queue - all three existed to work around not knowing what an attack was." },
    { version = "2.15.1", date = "2026-09-02", notes = "Clone discs are sized from the character's real bounding footprint instead of the 2-stud root part, with a Disc size scale to match by eye. The safety test is given the same radius, so a green disc still means the whole footprint fits." },
    { version = "2.15.0", date = "2026-09-02", notes = "Clone mode moved from a ring to a dense grid anchored to the world, and the dodge became a search across it. Discs the size of your hitbox every 1.5 studs, overlapping, so a safe pocket a few studs wide between two boss attacks still shows up; green means your whole body fits there. The way out is found cell by cell: red cells cost twenty-five green ones to cross so they are crossed only when there is no way around, pits and walls are never crossed, and a depth pass lets it prefer the interior of a safe area over a single green cell about to close. The old ring checked the straight line for walls only and would run through a red strip to a green node behind it. Floor heights are cached per cell; walls are learned by trying. Also: the menu key is rebindable at the top of Modules, and a pinned window no longer stops the key from reopening the interface." },
    { version = "2.14.0", date = "2026-09-02", notes = "Recommendations replace freeze-and-pick as the way to fill the Attack Book. The scorer puts forward what it currently believes is an attack, nearest first, one at a time at a rate you set, each held in the world in its own colour with a number on it and listed in the Attacks panel. Tick writes a book entry from the signature captured when it was put forward, so it works after the part is gone; cross is remembered per map and vetoes the name as a hazard, so the bot stops dodging it as well as stops asking. Entries outlive their part on purpose - that was the whole reason freeze existed. Freeze and the pickers remain underneath as the manual route." },
    { version = "2.13.0", date = "2026-09-02", notes = "Two testing switches at the top of Navigation: Pathfinding and Dodging. Off stops the bot driving your character with what it finds - it still finds it. Dodging moved here from Telegraphs so one setting has one control, and both are saved now (Dodging never was). Clone ring geometry fixed: the innermost ring sat at 55% of the radius, so widening the ring opened a hole around the character, and every ring got the same number of volumes, so the outer ring had gaps nearly twice as wide as the inner one. Now the first ring sits at a fixed inner radius, rings are added automatically so the gap between them stays about Ring spacing, and volumes are shared out by circumference." },
    { version = "2.12.0", date = "2026-09-02", notes = "Every window header has a pin beside the info circle. Grey when it is not pinned, accent when it is; a pinned window stays on screen after RightShift closes the rest, and is still draggable. Click it again and it goes back to hiding with everything else. Pins are remembered between sessions. The blur and dim stay tied to the interface rather than to any pinned window - dimming the whole game for one pinned readout would be absurd." },
    { version = "2.11.0", date = "2026-09-02", notes = "New Attacks panel: pick the map, freeze the attacks so a half-second telegraph can be pointed at, select one into the Attack Book, and draw a hazard around a decoration that only ANNOUNCES an attack - press on it, drag outwards, release, and every copy of that decoration carries one from then on. The Attack Book and the drawn zones are now stored PER MAP and survive between executions; a pre-2.11 global book is adopted into the current map. Clone gained a manual mode - the ring dodges for you and nothing else runs. Rings cap at 10 and volumes at 100. Opening the interface blurs and darkens the game behind it, both adjustable. List entries are laid out explicitly now; nested auto-layout had mangled them." },
    { version = "2.10.0", date = "2026-09-02", notes = "Two new panels. Configs saves the whole setup under a name, as many as you like, into its own file: type a name and press the tick, click a row to load it, pencil renames, bin deletes, each showing when it was saved. Modules turns each panel on and off with a square toggle - accent gradient on, greyed out off - and the Modules panel is deliberately not in its own list, because hiding the thing that unhides everything else is a door that locks behind you. Window positions are clamped into the viewport, so a default laid out for a wide screen cannot land off the edge of a small one where it could not be dragged back." },
    { version = "2.9.0", date = "2026-09-02", notes = "Clone evasion, a third mode beside Legacy and Macro. A ring of player-sized volumes follows the character, each one a standing question - would anything be hitting you here? - answered continuously and shown on a pad under it, green safe, red not. When an attack lands on the character the bot steps into the best green one. Projectiles are covered without extra work: safety measures against the swept path of a moving hazard, so a volume in the line of fire goes red before the projectile arrives. Volumes, rings, radius, margin, commit time and both colours are all settings; the ring is rebuilt on a settings change and on respawn, and torn down on a mode switch or Destruct." },
    { version = "2.8.0", date = "2026-09-02", notes = "Account panel: your Roblox headshot, your name and a rank, with Logout and Detach. It opens and closes with the other windows on RightShift. It masks under Streamer Mode - a panel showing your name and your face would otherwise put both back on screen the moment you opened the GUI on stream. Rank is CFG.accountRank, a plain string for now; Logout is a placeholder that closes the interface, since there is no account system behind it yet." },
    { version = "2.7.4", date = "2026-09-02", notes = "Macro rotation actually works now. It was being recorded and stored correctly, then thrown away: the main loop fell through to releaseFacing() every frame during playback, switching the alignment rig off a microsecond after the macro switched it on. Playback now owns facing. The direction was also reconstructed with the wrong sign, which would have pointed the replay 180 degrees away - facing is stored as a look vector instead of an angle, so there is no sign convention to get wrong. Pitch is recorded too, from the torso and from the camera; only yaw is applied to the body, because a humanoid keeps its torso upright." },
    { version = "2.7.3", date = "2026-09-01", notes = "Found the real cause of the blank row labels: hoverable() parented a full-width invisible TextButton into the row to catch clicks, and a row has a horizontal UIListLayout - so the layout laid the hit button out as a list item, at full width and sorting first, pushing the label and the control off the edge where the window clipped them. A clickable row now raises InputBegan on itself, so nothing extra joins the layout. The HUD is rebuilt with explicit geometry: nested AutomaticSize inside a bottom-anchored auto-sizing frame never resolved and the stat values were being drawn at the top-left of the screen." },
    { version = "2.7.2", date = "2026-09-01", notes = "flexFill no longer reads the instance size back to rebuild it - every caller wants full height, so the height is a parameter. Tooling: build.py now runs the smoke test itself and fails on it. smoke.py always did exit non-zero; the 2.7.1 push slipped through because the command piped it to grep, which matched the error text and returned success. Folding it into build.py removes the chance to invoke it wrongly." },
    { version = "2.7.1", date = "2026-09-01", notes = "Fixed the 2.7.0 interface: every row label rendered blank because UIFlexItem Fill was applied to labels whose base width was already 100%, so the flex pass had negative slack and collapsed them to nothing (the buttons were fine, their base width was 0). Flex is gone; widths are explicit arithmetic. Also fixed the HUD title chip collapsing to a bare accent line (nested automatic sizing inside a clipping frame) and the Status row reading 'Movement: Movement: ...'." },
    { version = "2.7.0", date = "2026-09-01", notes = "The interface is rebuilt from the Figma kit: two accordion windows plus an always-on HUD in the bottom-left, hover tooltips on everything after a second, and a Legacy/Macro island at the top that hides whichever system is not in charge. Every overlay is now switchable and recolourable, targeting gained lowest/highest HP modes and dodging a master switch. Macros record your FACING as well as your position, save to any map you pick from a dropdown into their own DungeonAutofarm_macros.json, and can be played back per map. Fixed: the record keybind stopped working after the first recording because starting one disconnected the listener it shared." },
    { version = "2.6.0", date = "2026-09-01", notes = "Macros are a top-level mode with their own panel and their own button, no longer nested inside the waypoint editor. Recording now switches the free-fly editor OFF: a macro is recorded from your ordinary first-person camera, and a detached camera would capture a route the character never walked. Switching the idle mode to Macros disables the editor for the same reason." },
    { version = "2.5.1", date = "2026-09-01", notes = "Fixed: the macro Record and Bind buttons were unreachable. The Route panel was only opened by the Edit Path button, which also threw the camera into free-fly and paused the loop - so the only way to reach the recorder was to hijack the camera first, which is exactly what makes recording impossible. Opening the panel and arming the free-fly editor are now separate buttons." },
    { version = "2.5.0", date = "2026-09-01", notes = "Macro Waypoints. A dropdown at the top of the path panel switches between the legacy hand-placed waypoints and the new macro mode. Record (with a rebindable key) captures where you went and what you did; the recordings are listed, renamable, reorderable and stored per map alongside the waypoints. Play walks to the start of each macro with the normal routed pathfinding, then replays it. Movement is stored as positions rather than held keys, so the replay self-corrects instead of drifting; the actions are the recorded inputs, anchored to the point along the route where they were made." },
    { version = "2.4.0", date = "2026-09-01", notes = "Freeze Parts holds a copy of every attack on screen so a telegraph that lasts half a second can still be pointed at, and Pick Telegraph now writes straight into the Attack Book. Trial runs, freezing and picking all work with the loop OFF. Low Detail mode hides everything in the world except the part names you pick (enemies, attacks and markers always stay); collision is untouched. Waypoint paths and low-detail keep lists are now stored PER MAP across the 14 dungeons, with a map picker; the chosen map loads on execution." },
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
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

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
-- LD = low-detail mode: the keep list and what is currently hidden.
local LD = {}
-- DG = dodge: the box, the candidates around the character, and what was
-- gathered for the last decision.
local DG = {}
-- ZN = hand-drawn hazard zones: the definitions, and the live volumes built
-- from them.
local ZN = {}
-- PC = precast: the attacks the game has announced but not yet landed.
local PC = {}
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
CFG.wallPadding = 2.0
CFG.wallStallTime = 0.6     -- seconds without moving, on a path, before a sidestep
-- How the basic attack is delivered (3.2.3).
--   "auto"  - Tool:Activate() when a tool is equipped, click if not
--   "tool"  - Tool:Activate() only; never touches the mouse
--   "click" - the old synthetic click, for anything Activate does not drive
--
-- Activate is the right answer here. The weapon is a Tool whose Activated is
-- handled on the server, and Tool:Activate() raises that same event from the
-- client - no cursor, no GUI to hit, nothing for the player to fight over.
CFG.attackMethod = "auto"
-- Clicking at the cursor meant clicking whatever the cursor happened to be
-- over, which was regularly a button. When a click is used at all it goes to a
-- fixed point instead.
CFG.clickAtCursor = false
-- The off switch: with this off the script never synthesises a mouse click.
CFG.autoClickEnabled = true
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
CFG.directHopDistance = 8.0    -- with no path and the target this near, just walk to it
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
CFG.abilityRadius = 30
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
-- Some attacks are built from hundreds of small meshes. Tested and drawn one by
-- one they cost more than the whole rest of the script put together, so a dense
-- group is collapsed into the one box it effectively is.
CFG.hazardClusterMin = 6            -- parts under one model before it becomes a box
CFG.maxHazardOverlays = 28          -- highlights and name tags drawn at once

-- long enough to point at it. While Freeze is on, every detected attack is
-- copied into a held snapshot that stays put after the real one is gone, so it
-- can be pointed at and added to the Attack Book at leisure.

-- Low detail (2.4.0). Everything in the world is hidden except the parts whose
-- names you picked, plus enemies, attacks and our own markers. Collision is
-- untouched: hidden floor is still solid, it is only invisible.
CFG.lowDetailBudget = 400           -- parts hidden/restored per frame while sweeping
CFG.lowDetailKillEffects = true     -- also switch off particles, trails and beams

-- Targeting (2.7.0). "closest" is the historical behaviour; the HP modes pick
-- among enemies within targetHpRange so the bot does not sprint across the
-- dungeon for a wounded straggler, falling back to closest when none qualify.
CFG.targetMode = "closest"       -- closest | lowest HP | highest HP
CFG.targetHpRange = 150.0

-- Testing switches, at the top of Navigation. Off means the bot still finds
-- and reports things, it just stops driving your character with them.
CFG.pathfindingEnabled = true
CFG.dodgeEnabled = true

-- The game's own attack broadcast (3.0.0). See game/GAME_NOTES.md.
CFG.usePrecast = true            -- listen to the precastHitbox bridge
CFG.showPrecast = true           -- draw the announced zones ourselves
CFG.precastHorizon = 6.0         -- seconds ahead we care about
CFG.precastLingerTime = 0.45     -- seconds a zone stays dangerous after impact
CFG.precastMaxZones = 160
CFG.colorPrecastEarly = Color3.fromRGB(255, 190, 60)
CFG.colorPrecastImminent = Color3.fromRGB(255, 60, 60)

-- Safe-spot bosses: markers that mean STAND HERE, not run away.
CFG.safeZoneEnabled = true
CFG.safeZonePull = 900           -- penalty for being outside a live safe zone
CFG.colorSafeZone = Color3.fromRGB(90, 255, 190)

-- Follow Workspace.dungeonName instead of making you pick the map.
CFG.autoDetectMap = true

-- Hand-drawn hazard zones (2.11.0). Some attacks are announced by a
-- decoration that is not itself the damage - a rune on the floor, a glow - and
-- no amount of appearance scoring will make a decal into a hitbox. So you point
-- at the decoration and draw the volume around it yourself, and from then on
-- every copy of that decoration carries one.
-- Dodge (4.0.0). Few on purpose: the previous system had sixty-eight and they
-- were caught fighting each other three times in six versions.
CFG.dodgeInterval = 0.05         -- seconds between decisions
CFG.dodgeReach = 18              -- studs to the outer ring of candidates
CFG.dodgeRings = 4
CFG.dodgeRays = 24
CFG.dodgeProbe = 0               -- studs; 0 uses the root part's radius
CFG.dodgeMargin = 0.5            -- clearance on top of the probe
CFG.dodgeShoulder = 3.0          -- studs of warm edge outside a hazard
CFG.dodgeLead = 1.2              -- seconds before impact a zone counts as live
CFG.dodgeLinger = 0.35           -- seconds after impact it still does
CFG.dodgeDwell = 1.2             -- seconds a spot must stay clear after arrival
CFG.dodgeMoveAt = 0.15           -- danger here at or above this: relocate
CFG.dodgeHysteresis = 0.12       -- a new spot must beat the box by this
CFG.dodgeDistanceCost = 0.008    -- danger-equivalent per stud of travel
-- The enemy is the distance (4.4.0): its circle is its body plus an ordinary
-- swing, capped by our own attack range, and the chase stands at the same
-- number. The soft ring past it is a preference, not a danger.
CFG.enemyMeleeReach = 5
CFG.dodgeEnemySoftWidth = 6
-- Pick a side and keep it: a change of direction costs this much danger, a
-- reversal all of it, for dodgeHeadingMemory seconds after the last move.
CFG.dodgeTurnCost = 0.1
CFG.dodgeHeadingMemory = 1.5
-- Enemies are extrapolated by their velocity only this far ahead.
CFG.dodgeEnemyLookahead = 0.4
-- What a path sample inside the thing already hitting you still costs, as a
-- share of full: time spent in it matters, which way out does not.
CFG.dodgeInsideWeight = 0.5
-- Studs between samples along a candidate line (2 to 8 samples per line).
CFG.dodgeSampleSpacing = 2.5
-- Hubs (4.10.0): enemies that long line attacks pass through.
CFG.dodgeHubLineLength = 60    -- a part at least this long is a line
CFG.dodgeHubTolerance = 12     -- the line's axis passes within this of the enemy
CFG.dodgeHubMinRate = 0.15     -- lines per second before an enemy counts as a hub
CFG.dodgeHubWeight = 1.0       -- radial cost scale
CFG.dodgeHubLineWidth = 8      -- typical beam width, for the coverage estimate
CFG.dodgeHubExit = 0.8         -- seconds needed to get back out after going in
CFG.dodgeHubFireGuess = 1.2    -- arming delay assumed for a hub's lines until one is learned
CFG.dodgeHubStandoff = 50      -- the ring to hold while a hub fires: out where a sweep's lines have gaps between them
CFG.dodgeHubLeave = 2.5        -- seconds before the next burst is due to be back on the ring
CFG.dodgeHubRingWeight = 3     -- the ring pull, as a multiple of the ordinary approach weight
CFG.bossStandoff = 26          -- where to stand against a boss: inside ability range, outside its melee
CFG.dodgeHubBurstGap = 2.0     -- an interval longer than this between a hub's lines is a gap, not the period
CFG.dodgePredictSteps = 2      -- how many of a sweeping hub's next lines to predict
CFG.dodgePredictedLive = 1.0   -- how long a predicted line hurts when nothing has been learned
-- A precast that has brightened back by this much from its darkest is fading:
-- the attack has fired. Anything that arms sooner than armMinDelay after it
-- appears is never treated as a telegraph again.
CFG.armFadeStep = 0.08
CFG.armMinDelay = 0.3
-- Seconds after a precast has fully faded before the attack counts as over.
CFG.armDoneLinger = 0.3
-- Seconds past the last learned hit age before an attack counts as over.
CFG.armAssumedLinger = 1.0
-- A hit is blamed on the nearest known attack within this many studs of us
-- (to its nearest point, not its centre).
CFG.hitAttributeRadius = 6
-- Something flagged on looks alone that is still there after this long is
-- scenery, not an attack.
CFG.appearanceMaxAge = 12
-- A ground-truth attack Model that has shown nothing, not moved and not hit
-- us for this long is parked (a pool), not attacking.
CFG.dormantAfter = 10
-- Boss event remotes (4.6.0 Northern Lands, 4.7.0 every map). See bossevents.lua.
CFG.useBossEvents = true
-- Aquatic Temple (4.11.0)
CFG.aquaticOrbRadius = 5        -- the boss's rolling orbs (a Part renamed "Model"; size not captured yet)
CFG.aquaticSmiteRadius = 10     -- third boss smite
CFG.aquaticDamagePartHold = 4   -- seconds the second boss's damage parts are treated as live
CFG.bossSafeLead = 2.5      -- seconds before the swirly explodes that the colour spot becomes the only safe ground
CFG.bossFlameDelay = 0.5    -- seconds after the flame marker stops that the flame lands (not in the client script; a guess)
CFG.dodgeMoverMinSpeed = 3       -- studs/sec before a hazard counts as moving
CFG.dodgeMoverWindow = 0.15      -- half-width, seconds, of a mover's swept segment
CFG.dodgeMaxClimb = 3.0
CFG.dodgeMaxDrop = 10.0
CFG.dodgeRayBudget = 20          -- candidates raycast per decision, cheapest first
CFG.dodgeManual = false          -- dodge only; you drive the rest
CFG.dodgeShowField = true
CFG.dodgeShowTarget = true
CFG.dodgeShowRange = true        -- draw the ring the candidates sit inside
-- The box IS the approach. Among safe spots it prefers ones nearer the
-- target, so the character closes on the boss only through ground that is
-- clear and simply waits when there is none. Pursuit no longer drives in
-- Dodge mode; it was walking straight through the pattern to get in range.
CFG.dodgeApproachWeight = 0.012  -- danger-equivalent per stud short of the target
-- Enemy soft ring is a preference, not a danger: it must sit below dodgeMoveAt
-- or standing at attack range reads as unsafe and the character oscillates.
CFG.dodgeEnemySoftWeight = 0.12
-- Pursuit walks the map underneath the dodge (4.3.0) and asks before every
-- step whether the next few studs of its route are clear. This is how many.
CFG.dodgeStepProbe = 5
-- A spot with a wall right behind it is a pocket. Continuing to flee from
-- there is impossible, so it costs extra in proportion to how little room
-- there is beyond it.
CFG.dodgeCornerCost = 0.35
-- Damage attribution: how far around you to look for the culprit on a hit.
CFG.hitSearchRadius = 14
CFG.hitLearnCooldown = 0.4
CFG.colorDodgeTarget = Color3.fromRGB(255, 255, 255)
CFG.colorDodgeSafe = Color3.fromRGB(60, 220, 120)
CFG.colorDodgeDanger = Color3.fromRGB(255, 70, 70)

CFG.zoneDefaultRadius = 12.0
CFG.zoneDefaultHeight = 14.0
CFG.zoneMinRadius = 2.0
CFG.zoneMaxRadius = 120.0
CFG.zoneColor = Color3.fromRGB(255, 110, 40)
CFG.zoneTransparency = 0.72

-- The world behind the interface (2.11.0). Blur is a Lighting effect, so it
-- only touches the 3D view and never the GUI on top of it; the dim is a plain
-- black sheet behind the windows.
CFG.guiBlur = 14                 -- 0 disables it
CFG.guiDim = 0.35                -- 0 disables it

-- Which panels appear when you open the interface (2.10.0). The Modules panel
-- itself is deliberately not in this list: hiding the thing that unhides
-- everything else is a door that locks behind you.
-- The key that opens and closes the whole interface. A KeyCode name.
CFG.menuKey = "RightShift"
CFG.panelAutofarm = true
CFG.panelRoutes = true
CFG.panelAccount = true
CFG.panelConfigs = true
CFG.panelAttacks = true

-- Saved configs. As many as you like, each a full snapshot of every setting.
CFG.configFile = "DungeonAutofarm_configs.json"

-- Looking past the edge of the grid (3.2.5). The window only reaches about
-- twenty studs; cornered with attacks inside all of it, the genuinely clear
-- ground is simply invisible and the bot settles for the least bad corner.
-- Attack capture (3.3.0). A place file says what exists in ReplicatedStorage;
-- it does not say what a part is NAMED, PARENTED or SHAPED when it actually
-- spawns during a fight, and both dumps had an empty Workspace.enemies. This
-- records every part that appears near you along with the verdict, so a miss
-- can be read rather than guessed at.
CFG.diagnoseAttacks = false
CFG.diagnoseRadius = 90
CFG.diagnoseMax = 900
CFG.diagnoseFile = "DungeonAutofarm_attacklog.txt"

-- Being pinned is its own failure, and the ordinary stuck detector is switched
-- off while dodging.
-- Anti-dither (3.5.2). Three separate things were making it shuffle on the
-- spot with clear ground in sight, and they compounded.
-- How the character is driven (3.6.0). MoveTo accelerates for a quarter of a
-- second, arrives within about two studs, and re-plans every call - which in a
-- three-stud gap between beams means arriving late and off the mark. Most of
-- what looks like bad decisions is that.
--   walk | steer | velocity | tween
-- tween by default. It is the only mode the default control module cannot
-- overrule: Move() and velocity writes both go through the Humanoid, and
-- Roblox's control script calls Move(zero) every frame from input on
-- RenderStepped, before physics, so it wins over anything we set on Heartbeat.
-- Writing the CFrame skips the Humanoid entirely, which is exactly why a script
-- that tweens to a marker has precision the Humanoid API cannot give it.
CFG.moveMode = "tween"
-- Take the player's controls while using a Move-based mode, and hand them back
-- the moment it stops.
CFG.moveTakeControls = true
CFG.moveArriveRadius = 1.2       -- studs; MoveTo's own tolerance is nearer 2

-- Account panel (2.8.0). Rank is a plain string for now; there is no account
-- system behind it yet.
CFG.accountRank = "DEVELOPER"

-- Overlay colours (2.7.0). Everything this script draws in the world reads its
-- colour from here, so the Overlays section can recolour any of it. accentColor
-- drives the whole GUI: the three gradient stops are derived from it.
CFG.colorTelegraph = Color3.fromRGB(255, 30, 30)
CFG.drawPendingHazards = false  -- draw attacks still on their timer (floor)? Off: only what can hurt is boxed
CFG.colorTelegraphPending = Color3.fromRGB(255, 176, 40)   -- announced, not yet live
CFG.colorWall = Color3.fromRGB(40, 220, 90)
CFG.colorHitbox = Color3.fromRGB(0, 220, 255)
CFG.colorAbilityRadius = Color3.fromRGB(170, 100, 255)
CFG.colorPursuit = Color3.fromRGB(0, 160, 255)
CFG.colorEscape = Color3.fromRGB(255, 170, 0)
CFG.colorWaypoint = Color3.fromRGB(255, 190, 40)
CFG.accentColor = Color3.fromRGB(255, 182, 38)

-- Overlay visibility, so the Overlays section can switch each one off.
CFG.showPursuitRoute = true
CFG.showEscapeRoute = true
CFG.showWaypoints = true
CFG.showHud = true

-- The dungeons, as the config keys them. Waypoint paths and low-detail keep
-- lists are stored per map, so one config carries every dungeon you set up.
-- The labels are cosmetic only; correct them freely.
local MAP_CODES = { "DT", "WO", "PI", "KC", "TU", "SP", "TC", "GH", "SS", "OO", "VC", "AT", "EF", "NL" }
local MAP_LABELS = {
    DT = "Desert Temple",     WO = "Winter Outpost",   PI = "Pirate Island",
    KC = "King's Castle",     TU = "The Underworld",   SP = "Samurai Palace",
    TC = "The Canals",        GH = "Ghastly Harbor",   SS = "Steampunk Sewers",
    OO = "Orbital Outpost",   VC = "Volcanic Chambers", AT = "Aquatic Temple",
    EF = "Enchanted Forest",  NL = "Northern Lands",
}

-- Runtime Variables
RT.gameSpecificAttackMethod = nil
RT.abilityHook = nil             -- harness: called with the KeyCode whenever an ability is pressed
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
-- Live safe-spot markers: the places a boss says you MUST stand.
HZ.safeZones = {}
-- Attack capture: [part] = true for things already recorded, and the pending
-- lines waiting to be written.
HZ.diagnosed = setmetatable({}, { __mode = "k" })
HZ.diagnoseLines = {}
HZ.diagnoseCount = 0
-- Parts the GAME says are attacks (structure or name), stamped at
-- classification so the per-frame scan can exempt them from appearance
-- tests. Weak keys: a destroyed part drops out on its own.
HZ.groundTruth = setmetatable({}, { __mode = "k" })
-- Arming (4.5.0). Every attack in this game is a Model with an invisible
-- hitBox and a visible precast, and the client fades the precast OUT at the
-- moment the hit lands. So a visible precast is a telegraph - floor you may
-- cross - and the fade is the hit. Per attack Model: when it was first seen,
-- its precast, the least transparent that precast has been, and when it
-- armed. Keyed weakly so dead attacks fall out.
HZ.arming = setmetatable({}, { __mode = "k" })
HZ.armState = setmetatable({}, { __mode = "k" })   -- [part] = its Model's arming record
HZ.lifeLog = {}                  -- one line per attack Model's lifecycle, for the capture file
HZ.windowStamps = {}             -- windows announced by events for Models not yet tracked
HZ.scenery = setmetatable({}, { __mode = "k" })   -- appearance-only detections that outlived appearanceMaxAge
-- What was next to you each time you took damage. Newest last, capped.
HZ.hitLog = {}
HZ.lastHitAt = -math.huge
HZ.lastHitName = nil
-- What the safety tests actually iterate: single parts, plus one box for each
-- dense cluster. Rebuilt with HZ.detected.
HZ.volumes = {}
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
HZ.attackBook = {}               -- array of learned attack records (plain data, saved)
HZ.recentParts = {}              -- [part] = os.clock() it was added; motion-tracked while young
HZ.motion = {}                   -- [part] = { position, time, velocity, moving }
HZ.predictionOwner = {}          -- [prediction line Part] = the hazard it belongs to
HZ.damageEvents = 0
RT.lastHealth = nil
RT.healthConnection = nil

-- Low detail. keepNames is what the user picked (lowercased part names, saved
-- per map); hidden remembers what each part looked like so it can be restored.
LD.enabled = false
LD.keepNames = {}
LD.hidden = {}                   -- [part] = { transparency, castShadow }
LD.effects = {}                  -- [ParticleEmitter/Trail/Beam/...] = true
LD.disabledEffects = {}          -- [effect] = true, switched off by us
LD.cursor = 1                    -- round-robin position of the hide/restore sweep
LD.sweeping = false              -- a full pass is pending (mode or keep list changed)
LD.pickerEnabled = false

-- Per-map storage. RT.mapData[code] = { waypath = {...}, keep = {...} } for
-- every map in the config, so saving one map never drops the others.
RT.currentMap = MAP_CODES[1]
RT.mapData = {}
-- Named config snapshots: { name, savedAt, data }. Kept in their own file so
-- the working config stays one small readable thing.
RT.configs = {}
RT.blurEffect = nil
-- Seconds since the last frame, for movers that step by hand.
RT.frameDelta = 1 / 60
RT.moverProgressPos = nil
RT.moverProgressAt = nil
RT.controlsDisabled = false
-- Which windows are pinned, by name. Pinned windows stay on screen after the
-- interface is closed, so a readout you want while playing does not cost you
-- the whole GUI.
RT.pinnedWindows = {}
-- Workspace.vfxPool: the player's own pooled hit effects.
RT.vfxPool = nil
RT.menuBindCapture = false
-- Per-map attack books, and per-map hand-drawn zones. Both are properties of a
-- dungeon, so they are keyed by map like the waypoints.
RT.attackData = {}
-- How long after it appears each attack (by Model name) arms, learned from
-- watching its precast fade. Saved with the config; the earliest seen wins.
RT.armDelays = {}
-- Learned from being hit, by Model name: { first, last } = the earliest and
-- latest age after appearing at which the attack has hurt us. Saved.
RT.armSpans = {}
-- Attack names that have hit us after their warning faded: fade does not end
-- these; their learned window does. Saved.
RT.armLongLived = {}
RT.zoneData = {}
RT.rejectData = nil

-- Which system drives the character: "legacy" searches for a safe point when
-- something lands near you; "clone" is the box. The value is "clone" rather
-- than "dodge" so a config saved on an earlier build still loads.
RT.mode = "clone"

-- Dodge (4.0.0). See dodge.lua.
DG.active = false
DG.folder = nil
DG.box = nil
DG.discs = {}
DG.offsets = {}                  -- fixed candidate offsets around the character
DG.offsetsKey = ""
DG.cands = {}                    -- scratch: one record per offset
DG.order = {}                    -- scratch: candidate indices sorted by cost
DG.pathFractions = { 0.34, 0.67, 1.0 }
-- Directions probed for room beyond a candidate, in the candidate's own frame:
-- (forward, sideways, weight). Ahead matters most; the sides are what turn a
-- dead end into a pocket.
DG.pocketProbes = { { 1, 0, 0.5 }, { 0, 1, 0.25 }, { 0, -1, 0.25 } }
DG.enemies = {}
-- Last seen position per enemy model, for velocity; body half-extent per
-- model, refreshed occasionally. Both weak-keyed so dead enemies fall out.
DG.enemyPrev = setmetatable({}, { __mode = "k" })
DG.movers = {}
DG.moverSet = {}
DG.floorCache = {}
DG.floorCacheSize = 0
DG.rayParams = nil
DG.reach = 1.5
DG.halfHeight = 5
DG.now = 0
DG.dangerHere = 0
DG.target = nil                  -- where the box is; nil when here is fine
DG.targetReason = ""
DG.lastDecision = -math.huge
DG.pursuitBlocked = false
DG.gapWait = false               -- here is safe and nowhere safe to go: pursuit holds too
DG.hubs = setmetatable({}, { __mode = "k" })     -- [enemy Model] = { times, lastSpawn, period, rate, fire }
DG.hubSeen = setmetatable({}, { __mode = "k" })  -- line parts already counted
DG.hubHold = false
DG.heading = nil                 -- unit direction of the last box, for the turn cost
DG.headingTime = 0        -- pursuit's next step was refused; the box takes over the approach

-- Hand-drawn zones. `defs` is what gets saved (a signature plus a shape);
-- `live` is [decoration part] = the volume currently following it.
ZN.defs = {}
ZN.live = {}
ZN.folder = nil
ZN.pickerEnabled = false
ZN.connections = {}
ZN.root = nil                    -- the decoration being measured from
ZN.dragging = false
ZN.draftRadius = 0
ZN.draftShape = "circle"         -- circle | square
ZN.preview = nil

-- Announced attacks, newest last: { shape, cframe|position, size|radius,
-- startTime, delay, impactAt, part }. Filled by the precastHitbox listener.
PC.zones = {}
-- Boss events (4.6.0): scripted projectiles and timed safe windows, from
-- the per-map boss remotes. See bossevents.lua.
PC.paths = {}
PC.safeWindows = {}
PC.parts = {}
PC.folder = nil
PC.connection = nil
PC.bridge = nil
PC.failed = false
PC.total = 0

PC.received = 0                  -- payloads seen on the bridge, parsed or not
PC.lastShown = -1
PC.lastTotal = -1

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
-- The HUD's Status row. No "Movement:" prefix any more: the row it writes into
-- is already labelled, and the prefix was showing up twice.
local function setMovementState(text)
    if UI.movementStateLabel then
        UI.movementStateLabel.Text = text
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

-- A snapshot of every tuning value as shipped, taken before the config loader
-- runs, so "Reset to defaults" has something true to restore.
RT.cfgDefaults = {}
for key, value in pairs(CFG) do RT.cfgDefaults[key] = value end

S.CFG = CFG
S.CollectionService = CollectionService
S.Lighting = Lighting
S.ReplicatedStorage = ReplicatedStorage
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
S.LEARN_EPOCH = LEARN_EPOCH
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
S.LD = LD
S.DG = DG
S.ZN = ZN
S.PC = PC
S.MAP_CODES = MAP_CODES
S.MAP_LABELS = MAP_LABELS
end
