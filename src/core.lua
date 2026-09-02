-- core.lua - Version, services, CFG tuning, shared state tables, runtime flags, debug logging.
-- Module contract: receives the shared table S. Everything this module needs from
-- earlier modules is pulled into locals below; everything later modules need is
-- assigned onto S at the bottom. Load order is fixed by main.lua / build.py.
return function(S)

--[[
================================================================================
    DUNGEON QUEST REBORN - ADVANCED AUTOFARM
================================================================================
    VERSION : 3.6.2
    BUILD   : 2026-09-01

    VERSIONING RULES (semantic):
        MAJOR -> rewrite / breaking change to core architecture
        MINOR -> new feature, new UI element, new subsystem
        PATCH -> bugfix, tuning, constant change, refactor with no new behaviour

    Bump SCRIPT_VERSION and prepend a SCRIPT_CHANGELOG entry on EVERY edit.
================================================================================
]]

local SCRIPT_VERSION = "3.6.2"
local SCRIPT_BUILD_DATE = "2026-09-01"
local SCRIPT_CODENAME = "Actuator"

-- Newest entry first.
local SCRIPT_CHANGELOG = {
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
-- MC = macro recording and playback.
local MC = {}
-- CL = clone evasion: the ring of volumes and what each one currently thinks.
local CL = {}
-- ZN = hand-drawn hazard zones: the definitions, and the live volumes built
-- from them.
local ZN = {}
-- PC = precast: the attacks the game has announced but not yet landed.
local PC = {}
-- TH = threat field: the sources it is built from each pass.
local TH = {}
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

-- Macros (2.5.0). A macro is a recording of a run: where the character went and
-- what it did, sampled as it happened. Playback walks the recorded route and
-- fires the recorded actions at the point along it where they were made.
--
-- Movement is stored as POSITIONS, not as held keys. Replaying raw key presses
-- desynchronises within seconds - a different framerate, a slightly different
-- spawn point or one bump into a doorframe and every later input lands
-- somewhere else - whereas a position is absolute and self-correcting, so the
-- replay converges back onto the recorded route after any disturbance. The
-- actions (clicks, Q, E, jumps) are the recorded inputs, anchored to the sample
-- they were made at rather than to a wall-clock offset.
CFG.macroSampleInterval = 0.12   -- seconds between position samples at most
CFG.macroSampleDistance = 2.5    -- ...or this far moved, whichever comes first
CFG.macroArriveRadius = 4.5      -- how close counts as having reached a sample
CFG.macroStartRadius = 6.0       -- close enough to the start to begin the replay
CFG.macroGiveUpTime = 6.0        -- no progress toward a sample for this long: skip it
CFG.macroSkipLimit = 12          -- consecutive skips before the macro is abandoned
CFG.macroMaxSamples = 9000       -- roughly 18 minutes; a guard, not a target
CFG.macroLoop = false            -- restart the list after the last macro
CFG.macroShowRoute = true        -- draw the selected macro's route in the world
CFG.macroFaceRecorded = true     -- replay the facing you had, not just where you walked
CFG.macroFile = "DungeonAutofarm_macros.json"

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

-- Clone evasion (2.9.0). A ring of player-sized volumes around the character,
-- each continuously tested against the live hazards. When something is about to
-- hit you the bot steps into the best green one. It is the same job the Legacy
-- escape search does, except the candidates are visible and you can watch it
-- decide.
CFG.cloneCount = 24              -- total volumes, spread over the rings below
CFG.cloneRings = 2               -- inner ring at 55% of the radius, outer at 100%
CFG.cloneRadius = 12.0
CFG.cloneEvalInterval = 0.08     -- how often safety is re-tested (positions move every frame)
CFG.cloneSafetyMargin = 0.75      -- extra clearance a clone must have to count as safe
CFG.cloneMaxDrop = 12.0          -- a clone whose floor is further below this is off a ledge
CFG.cloneMaxClimb = 6.0
-- Terrain as heat (3.2.2). "Has a floor" is not the same question as "can I get
-- there": a ledge you must jump onto and a wall in the way both have perfectly
-- good floors. A Roblox humanoid steps up about this much for free; anything
-- higher needs a jump, and a jump in the middle of a boss fight is a moment
-- spent not dodging.
CFG.cloneStepHeight = 2.5
CFG.threatWallWeight = 60        -- heat for ground you cannot simply walk onto
CFG.threatWallSpread = true      -- warm the cells beside a wall as well
-- Enclosure. A green pocket ringed by red is a TRAP: you can stand in it right
-- now and have nowhere to go the moment it closes. Cells inherit a share of the
-- heat around them, so an enclosed pocket reads hotter than open ground of the
-- same local safety and the bot strafes out instead of backing into a corner.
-- Space-time slices (3.5.0). Each cell stores its heat at three moments, and
-- the search interpolates for the time it would actually arrive having gone
-- round whatever was in the way. Sampling a cell at its straight-line ETA is a
-- different question from what it will be when you really get there.
-- Cover (3.5.0). When a radial burst fills the arena there is no open safe
-- ground, and the answer is not to find the least bad patch of it - it is to
-- put something solid between you and the source. The arena pillars are exactly
-- that, and until now the grid treated them only as obstacles to route round.
CFG.coverEnabled = true
CFG.coverRelief = 0.75           -- share of a source's heat that cover removes
CFG.coverBudget = 90             -- line-of-sight rays per pass
CFG.coverRefresh = 0.4           -- seconds a cover verdict is trusted
CFG.colorCover = Color3.fromRGB(90, 160, 255)

CFG.threatSliceMid = 1.0         -- seconds; the middle sample
CFG.threatSliceLate = 2.6        -- seconds; the late sample
CFG.threatEnclosureWeight = 0.55
CFG.threatEnclosureRange = 6.0   -- studs out to sample for a way through

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

-- Adaptive lookahead. Borrowed from the standalone heatmap prototype, which
-- scales its prediction window inversely with the agent's speed: a slow agent
-- cannot dodge reactively, so it has to see danger coming much earlier. Every
-- horizon in this script was a fixed constant regardless of WalkSpeed, which
-- meant the same warning time whether you were sprinting or crawling.
CFG.adaptiveLookahead = true
CFG.lookaheadBaseSpeed = 16      -- the WalkSpeed the tuned horizons assume

CFG.escapeScanEnabled = true
CFG.escapeScanRays = 16          -- directions sampled beyond the grid
CFG.escapeScanFar = 2.8          -- times the grid radius
CFG.escapeMargin = 12            -- heat it must beat the local best by to bother

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

CFG.cloneGoalHysteresis = 45     -- a new goal must beat the held one by this
CFG.clonePathInterval = 0.12     -- seconds between full re-plans
CFG.cloneFreshnessBias = 18      -- score penalty for a cell measured long ago

CFG.cloneStuckTime = 0.7         -- seconds of no progress before intervening
CFG.cloneStuckDistance = 1.5     -- studs that counts as progress
CFG.cloneCommitTime = 0.35       -- hold a chosen clone this long before reconsidering
-- Where the innermost ring sits. Not a fraction of the radius: a fraction
-- means the hole around the character grows every time you widen the ring,
-- which is the one place you most need somewhere to step.
CFG.cloneInnerRadius = 4.0
-- Rings are added automatically so the gap between them stays about this, no
-- matter how wide the ring is. The Rings slider is the floor, not the answer.
CFG.cloneAutoRings = true
CFG.cloneRingSpacing = 6.0
CFG.cloneMaxVolumes = 100        -- slider ceilings
CFG.cloneMaxRings = 10
-- Manual mode: the ring dodges for you, but nothing else runs. No target
-- hunting, no pursuit, no waypoints - you drive, it pulls you out of attacks.
CFG.cloneManual = false
CFG.showClones = true
-- The grid (2.15.0). Dense by default: boss fights have safe pockets a few
-- studs wide, and a disc the size of your hitbox every 1.5 studs is what it
-- takes to find one. The cell budget caps the cost; the radius is a request.
CFG.cloneGridSpacing = 1.5
CFG.cloneMaxCells = 900
CFG.cloneDangerCost = 25         -- a red cell costs this many green ones to cross
CFG.cloneDepthBonus = 1.5        -- studs of extra travel one cell of depth is worth
CFG.clonePenaltyWeight = 0.05
CFG.cloneFloorRefresh = 3.0      -- seconds a cached floor height is trusted
CFG.cloneFloorBudget = 150       -- floor raycasts per evaluation
-- Cells re-tested per pass. The whole grid no longer has to be judged in one
-- go: verdicts persist between passes, so a big grid refreshes in slices
-- instead of dropping a frame every time it thinks. This is the single knob
-- that decides whether a large radius is affordable on a weak machine.
CFG.cloneEvalBudget = 320
CFG.showClonePrisms = false      -- hundreds of prisms at boss density; off unless asked
CFG.colorClonePath = Color3.fromRGB(80, 170, 255)
-- Disc diameter as a multiple of the character's real footprint (2.15.1).
CFG.cloneDiscScale = 1.0
CFG.cloneMaxFootprint = 3.0      -- studs; a cosmetic cannot inflate past this
-- Melee enemies do not telegraph. Standing next to one is simply fatal, so the
-- grid gives every live enemy a circle of its own.
CFG.cloneEnemyRadius = 12.0
CFG.cloneEnemySoftRadius = 20.0  -- beyond the hard circle, discouraged not forbidden
-- Chasing obeys the same circle the grid draws. Without this the dodge kept its
-- distance and the pursuit immediately walked back into melee, which on a high
-- tier is one tap.
CFG.cloneKeepDistance = true

-- Threat field (3.1.0). Heat rather than a yes/no verdict: in a fan of beams
-- every square is unsafe, so a boolean leaves the search nothing to choose
-- between and the character stands still and dies.
CFG.threatWeight = 2.6           -- studs of detour one point of heat is worth
CFG.threatLethal = 55            -- at or above this a cell is impassable...
CFG.threatDesperate = true       -- ...unless there is no path at all
CFG.threatHorizon = 4.0          -- seconds ahead an announced attack starts to matter
-- Shape of the ramp from "announced" to "landing". Higher stays cool longer and
-- then reddens hard, which is what a delayed attack actually does: it is not
-- dangerous at all until it nearly lands. Squared went lethal a full second
-- early, which quietly turned every marker into a wall.
CFG.threatCurve = 3.0
-- How much the heat where you WILL be outweighs the heat where you arrive. A
-- cell that is cool now and hot in a moment is a trap, not a destination.
CFG.threatFutureBias = 0.65
CFG.threatFalloff = 7.0          -- studs of warm shoulder outside a hazard edge
-- What safety actually probes with, in studs, INDEPENDENT of the disc drawn on
-- screen. This is what decides the smallest gap the grid can find: a probe of
-- radius r cannot see a safe pocket narrower than 2r, so probing with the whole
-- body including limbs made it blind to exactly the small pockets that matter.
-- The game damages against the root part, which is about a stud across, so that
-- is what the probe should be. 0 means "use the character's root radius".
CFG.threatProbeRadius = 0
CFG.threatMargin = 0.4           -- clearance added to the probe before anything counts
-- Any heat at or above this and the bot relocates. Deliberately low: standing
-- in something warm waiting for it to become lethal is not a plan.
CFG.threatMoveAt = 6
-- A moving hazard heats the whole corridor it is about to sweep, not just the
-- square it currently occupies.
CFG.threatSweepEnabled = true
CFG.threatSweepTime = 3.0        -- seconds of flight path treated as dangerous
-- A projectile is dangerous in a WINDOW around the moment it passes, not on a
-- ramp. Before it arrives you can cross and be gone; once it has passed, the
-- ground behind it is the safest on the map. The ground-attack ramp got both
-- of those backwards.
CFG.threatProjectileLead = 1.1   -- seconds before the pass that still count
CFG.threatProjectileWake = 0.3   -- seconds after it, before the ground is clear
CFG.showThreatGradient = true    -- colour discs by heat rather than safe/unsafe
-- Discrete bands rather than a continuous blend. Across several hundred discs a
-- smooth ramp turns to mush; banding makes "this patch is cooler than that one"
-- readable at a glance, which is the whole point of drawing it.
CFG.threatColorBands = 9

-- Projectile steering: the reflex under the grid, for things already in the air.
CFG.dodgeProjectiles = true
CFG.dodgeLookahead = 1.4         -- seconds of flight time considered
CFG.dodgeMinProjectileSpeed = 12 -- studs/sec before the sidestep reflex engages
CFG.threatSweepMinSpeed = 3      -- studs/sec before a hazard heats its own path
CFG.dodgeStrength = 14           -- studs the sideways shove aims for
CFG.colorThreatWarm = Color3.fromRGB(255, 170, 40)
-- A cell has to STAY safe this long after arrival, not merely be safe at the
-- instant of arrival. Standing still is a decision too.
CFG.cloneSafeDwell = 1.6
CFG.cloneFootprintRefresh = 0.5  -- seconds between re-measuring the character
CFG.colorCloneSafe = Color3.fromRGB(60, 220, 120)
CFG.colorCloneDanger = Color3.fromRGB(255, 70, 70)

-- Account panel (2.8.0). Rank is a plain string for now; there is no account
-- system behind it yet.
CFG.accountRank = "DEVELOPER"

-- Overlay colours (2.7.0). Everything this script draws in the world reads its
-- colour from here, so the Overlays section can recolour any of it. accentColor
-- drives the whole GUI: the three gradient stops are derived from it.
CFG.colorTelegraph = Color3.fromRGB(255, 30, 30)
CFG.colorWall = Color3.fromRGB(40, 220, 90)
CFG.colorHitbox = Color3.fromRGB(0, 220, 255)
CFG.colorAbilityRadius = Color3.fromRGB(170, 100, 255)
CFG.colorPursuit = Color3.fromRGB(0, 160, 255)
CFG.colorEscape = Color3.fromRGB(255, 170, 0)
CFG.colorWaypoint = Color3.fromRGB(255, 190, 40)
CFG.colorMacro = Color3.fromRGB(150, 110, 255)
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
-- Macros live in their own file, keyed by map: they are far bulkier than the
-- rest of the config (thousands of samples each) and being separate makes them
-- easy to open, copy between machines and hand to someone else.
RT.macroData = {}
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
-- dungeon, so they are keyed by map like the waypoints and the macros.
RT.attackData = {}
RT.zoneData = {}
RT.rejectData = nil

-- Clone evasion state (2.9.0).
-- Macros (2.5.0). "legacy" = the hand-placed waypoint path; "macro" = recorded
-- runs. The dropdown at the top of the path panel picks which one is in charge
-- when the bot has nothing to fight.
MC.mode = "legacy"
MC.macros = {}                   -- the current map's recordings, in play order
MC.recording = false
MC.recordStart = 0
MC.samples = nil                 -- being recorded: array of { t, x, y, z }
MC.actions = nil                 -- being recorded: array of { t, i, kind }
MC.lastSampleTime = 0
MC.lastSamplePosition = nil
MC.recordBind = Enum.KeyCode.RightBracket
MC.bindCapture = false           -- the next key pressed becomes the bind
-- TWO connection lists, deliberately. The bind listener is global and must
-- outlive any recording; the action listener belongs to one recording and is
-- torn down with it. They shared a table until 2.7.0, so starting a recording
-- disconnected the bind key and it never fired again.
MC.connections = {}              -- global: the record bind, and bind capture
MC.recordConnections = {}        -- per-recording: the action input listener
MC.playing = false
MC.playIndex = 1                 -- which macro in the list
MC.playPhase = "approach"        -- "approach" (walk to its start) then "replay"
MC.playCursor = 1                -- sample index being walked to
MC.playActionCursor = 1          -- next action not yet fired
MC.playProgressTime = 0
MC.playProgressDistance = nil
MC.playSkips = 0
MC.routeFolder = nil             -- drawn route of the selected macro

-- Clone evasion. `nodes` is the pool: each entry is { prism, pad, offset,
-- position, safe, penalty }. Built once when the mode is entered and reused.
CL.active = false
CL.folder = nil
CL.nodes = {}
CL.lastEvalTime = -math.huge
CL.chosen = nil                  -- the node currently being run to
CL.chosenAt = 0
CL.safeCount = 0
-- The grid (2.15.0): cells in window order, the floor cache by world key, the
-- current path as cell indices, and the committed goal.
CL.cells = {}
CL.floorCache = {}
CL.path = {}
CL.goal = nil
CL.goalAt = 0
CL.centerI = nil
CL.centerJ = nil
CL.reach = 1
CL.side = 3
CL.signature = ""
CL.footprintRadius = 1.5
CL.footprintCheckedAt = -math.huge
CL.evalCursor = 1
CL.progressPos = nil
CL.progressAt = 0
CL.escapeDir = nil
CL.escapeAt = 0
CL.coverCache = {}
CL.coverCursor = 1
CL.coverOrigin = nil
CL.goalScore = math.huge
CL.pathAt = 0
CL.pathCenterI = nil
CL.pathCenterJ = nil
-- Indices of the cells inside the circle. The array stays square because the
-- indexing is arithmetic; the corners are simply never active.
CL.activeCells = {}
CL.searchGen = 0
-- Last verdict per world cell, so a window shift can carry the answer over
-- instead of blanking it. See the flicker note in clone.lua.
CL.verdictCache = {}
-- The committed goal, as a WORLD key rather than a window index: the window
-- slides as you walk, so an index means somewhere different a moment later.
-- The committed goal, as WORLD cell coordinates: the window slides as you
-- walk, so an index into it means somewhere different a moment later.
CL.goalI = nil
CL.goalJ = nil

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
PC.parts = {}
PC.folder = nil
PC.connection = nil
PC.bridge = nil
PC.failed = false
PC.total = 0

TH.enemyPositions = {}
TH.origin = nil
TH.projectiles = {}
TH.LETHAL = 100
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
S.MC = MC
S.CL = CL
S.ZN = ZN
S.PC = PC
S.TH = TH
S.MAP_CODES = MAP_CODES
S.MAP_LABELS = MAP_LABELS
end
