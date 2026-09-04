# Dungeon Quest Reborn autofarm, 5.1 rewrite - hand-over

Branch `rewrite` of `Tsukiatte/dq`. Built bundle: `rewrite/DungeonAutofarm.lua`
(version 5.1.72 at hand-over). `main` still holds the old 4.12.20 build and is
untouched.

The target: Northern Lands (NL), Chris's character at level 192, where every
enemy hit is a one-shot. The bot must kill the Midgardian Champion (boss 1) and
Bob the Frost Giant (boss 2) inside the 10-minute dungeon timer without ever
being hit, using abilities only, and without tripping the anti-cheat.

Read this file, then `REWRITE.md` (design notes and measured game facts) and
`HANDOFF.md` (the client anti-cheat, section 2). `rewrite/CHANGELOG.md` has the
reasoning behind every version.

## Where it stands

- The Champion dies in about two to three minutes of the run on most runs
  (fastest 2:06). One to three deaths there is typical; the fan, the slam and
  the aimed criss cross are what still kill.
- Bob was killed in run 32 (5.1.68) with two deaths at him. Runs before that
  reached him with time left but did not finish him.
- The bonus boss vote after Bob is declined by default; its arena is unmapped.
- No anti-cheat kick since the movement rules in "Anti-cheat" below were
  adopted (5.1.44 onward).

## Rules Chris set (keep them)

- Abilities only. Never close to weapon range on high-level mobs. Auto attack
  off. A big standoff from every mob (34 studs past its body).
- Boss fights are inside the arena, every time. The aimed attacks spawn on you
  at the arena mouth with nowhere to step.
- Constant movement in a fight. Never stand still, never hover outside.
- Teleports ("blinks") are a reflex out of a box that is about to fire, a few
  studs only, rare, in fights only, never while pathing, never into the floor.
- Visuals: show every hitbox the bot knows, no clutter. The white box is the
  spot the bot is walking to and must never touch anything about to fire.
- Champion and Bob logic are separate. Never mix them. See `BOSS_PROFILES` in
  `src/core.lua`.
- The Bob fight position is between him and the crystals, in ability range, so
  the orbs can be led into their crystal.
- Every edit bumps `SCRIPT_VERSION`, `SCRIPT_CHANGELOG` in `src/core.lua` and
  `rewrite/CHANGELOG.md`. Player-visible strings stay neutral.

## Layout

`rewrite/src/` is concatenated into one bundle by `tools/build.py`. Each
module is a function that receives the shared table `S` and adds to it.

| module | job |
|---|---|
| `core.lua` | version, config defaults (`CFG`), attack timing seeds (`TIMING`), per-boss profiles (`BOSS_PROFILES`), Bob's crystal lookup, shared helpers |
| `uikit.lua` | the interface kit (windows, sliders, toggles, theme) |
| `reader.lua` | reads the world: enemies, every attack Model / precast / projectile, boss remote announcements, predicted zones (beam lanes, mage volleys, Bob's circle chain, his sweeping wall), our own ability range, the arena leash |
| `field.lua` | the danger field: `dangerAt(x,y,z,t)` over every box, the spot search (`decide`), the blink reflex |
| `mover.lua` | Humanoid-only movement: `driveTo`, speed bursts, stall tracking |
| `brain.lua` | the state machine: rooms, approach, fight (casts), back-off, strafe, reflexes (slam, fan, orb leading), travel with pathfinding |
| `draw.lua` | hitbox visuals: filled boxes coloured by stage, a faint second outline at the size the bot treats as unsafe, trail strips for moving projectiles, the target marker |
| `lobby.lua` | queueing, dungeon start, the bonus boss vote, run-complete detection |
| `config.lua` | persistence (`DungeonAutofarm5_config.json`, whitelisted keys only) |
| `ui.lua` | the windows and the HUD |
| `main.lua` | the Heartbeat loop, destructor, `_G` handles |

## Build and test loop

```bash
cd rewrite && python tools/check.py && python tools/build.py
```

`check.py` catches free names and module contract mistakes; `build.py` writes
`rewrite/DungeonAutofarm.lua`. Then copy the bundle to Potassium's workspace:

```bash
cp rewrite/DungeonAutofarm.lua "$LOCALAPPDATA/Potassium/workspace/dq_rewrite.lua"
cp rewrite/tools/recorder6.lua "$LOCALAPPDATA/Potassium/workspace/dq_recorder6.lua"
cp rewrite/tools/recorder6.lua "$LOCALAPPDATA/Potassium/workspace/dq_recorder5.lua"
```

(The teleport hooks load `dq_recorder5.lua` by name; both copies are the same
file.) The autoexec `Potassium/autoexec/dqr.luau` loads the workspace bundle on
every place join, falling back to the raw GitHub URL of this branch, then the
`main` bundle.

Hot-load mid-run from the executor:

```lua
loadstring(readfile("dq_rewrite.lua"))()          -- new instance destructs the old one
loadstring(readfile("dq_recorder6.lua"))()        -- the telemetry recorder
```

Room progress and the leash state survive a hot-load through `_G`.

Client scripts die on teleport. Queue a script with `queue_on_teleport` before
the level loads: wait 7 s, load the bundle, load the recorder. From the lobby,
`_G.DungeonAutofarmState.queueNow("claude")` creates a private NL lobby and
teleports. `autoStartDungeon` presses START in the level.

Chris tests in the real game only; the Studio harness is for mechanics.

## Telemetry - the way to find out what is wrong

`tools/recorder6.lua` runs beside the bot and keeps:

- a 10 Hz trace of the last six seconds: intended move direction vs measured
  velocity, WalkSpeed, state, spot distance, danger here, grace, nearest box,
  reflex, boost, cast flag;
- a verdict for every death: `inside-live` (the model called the box live),
  `inside-early` (box present, model said not yet, by N s), `inside-expired`
  (model said over, by N s), `outside-all` (no box contained the character:
  undetected attack or padding too small), with the nearest box;
- per-kind verdict counts, blink and reflex logs, movement effectiveness.

Read it with `tools/poll6.lua` (run through the executor; it returns a table).
The verdicts found, in one evening: Bob's beams kill 2-4 studs outside their
hitbox; Bob's circle Models are destroyed when they fire and the reader used to
forget them at that moment; the horizontal beam fires at 0.6 s not 1.1; the
orbs kill on contact; the ability cast animation roots the character.

Movement effectiveness has stayed at 0.92-0.96 of commanded speed with 0.9+
direction match, so deaths are the model or the choice, not the legs.

Never run a whole-game script scan (`grep_scripts` on the bridge) on the live
client: it froze the game at 0 fps for a minute.

## Anti-cheat (seven kicks, all server-side)

1. a 14-stud hop; 2. lag-spike CFrame step and floor fall; 3. sustained
per-frame CFrame driving; 4. chained blinks (3-4 in a row); 5. blinks at 3 s /
2 per 10 s; 6. blinks while pathing between rooms plus 8-stud hops; 7. plain
walking to Bob at WalkSpeed 22 for ~10 s.

Rules that have held since: ordinary movement is `Humanoid:Move` only, never a
CFrame write. Speed above 16 is a burst of at most 1.5 s then 1.2 s rest.
Blinks: at most 8 studs, 5 s apart (one extra hop inside the cooldown per 20 s
for a box already on the character), four a minute, in fights only, floor
raycast at the destination, standing height, never airborne. The client
anti-cheat (HANDOFF.md section 2) resets WalkSpeed above 45 and yanks a
character that hovers.

## Game facts measured (see REWRITE.md for the long form)

- Dungeon timer 10 minutes. Respawn after death is at the arena mouth, 131-137
  studs from the Champion.
- Champion: passive beams 8 x 63.7 x 250 through the hub; slow sweep +20 deg
  per beam every 0.5 s, fast fan 16/s for ~7 s with lanes drifting 3 deg per
  revolution; lethal 0.3-2.2 s after the Model appears; the precast fades at
  0.6 s and must not end the danger. Aimed criss cross: 15-stud MeshPart
  spawned on or next to the player, 240 studs in 8 s along its LookVector,
  lethal on contact. Big spike 40 wide, kills 4-7 studs outside its mesh.
  Jump slam: the `firstBossJumpSlam` Model (67 wide) appears about two seconds
  before the hit with the boss landing on the player; the `First Boss Jump
  Down` event arrives with the hit, not before. Arena leash ~122 studs from the
  Champion, arms once the fight is joined. Ability damage 11-15 % of boss HP
  per second at 30-40 studs.
- Bob (at -45, 30, 298): circle chain along the line through him, both
  directions, 22 studs and 0.27 s per step, circles 22-76 wide with a kill
  radius ~7 studs past the cylinder, lethal 0.6-1.6 s, and the Model is
  destroyed when it fires. Spread beam: nine 12 x 64 x 400 spokes at 20 deg,
  hits ~4 studs outside the box, fires ~0.9 s. Horizontal wave: 10-wide beams
  23.5 studs apart every 0.15 s, fires ~0.6 s. Sweeping wall
  `secondBossMovingBeam` (balls 52 apart) at ~19 studs/s; the announced path
  for it is 100-200 studs off, use the model. Orbs `secondBoss<Colour>Orb`
  follow the player and explode on contact; crystals `secondBossCrystals`
  children `red` (-144, 23, 268), `green` (-159, 23, 335), `yellow`
  (-105, 23, 377).
- Mobs: warrior circle 25-34 wide, warrior line 8 x 83, spearman line 8 x 140,
  mage volley 7 x 35 shots 0.1 s apart marching from the mage through the
  player; all hit about 0.25 s after they look finished. A melee mob's swing
  reach is a hard zone.
- Our ability: two "Geyser" tools (Q and E). The geyser lands on the target up
  to the range cap (measured 47-48 studs) and short of a farther target. The
  reader measures this per slot from each cast.

## Known problems, in the order they matter

1. Champion slam: the reflex now starts when the Model appears (5.1.72). The
   escape needs ~42 studs in 2 s, which is at the edge of what a 1.5 s burst
   allows; the blink covers the last few studs. Watch the verdicts.
2. Champion fan: the bot runs out to 85 studs from the hub and hops between
   lanes there. 100 was against the rocks. Not yet tuned with the profiles.
3. Aimed criss cross: it can spawn directly on the character and kill within
   0.1 s. Only a blink saves it; the second-hop allowance is for this.
4. Bob's orbs: the leading step (run to the far side of the matching crystal)
   is untested as of 5.1.71-72. The orb bubble (14 studs) keeps the bot away
   meanwhile.
5. Mob rooms: melee mobs cornering the bot is handled by wall openness costs
   and a back-off that picks the most open heading (5.1.63); the mage volley
   is now a full-length zone so the escape is sideways (5.1.72). Both need a
   few runs of verdicts.
6. Bonus boss and the third boss: unmapped. The blink is whitelisted to the
   Champion, Bob and mob fights until they are.
7. The saved config overrides defaults for whitelisted keys. It once carried
   `bossStandoff 26` and `autoAttack true` from early builds and cost many
   runs. When a default changes, set it live and save.

## Tools

- `tools/recorder6.lua`, `tools/poll6.lua` - telemetry, above.
- `tools/recorder5.lua`, `tools/poll5.lua` - the older, simpler pair.
- `tools/probe_bob.lua`, `tools/probe_circle.lua` - one-off measurements.
- `tools/check.py`, `tools/build.py`, `tools/smoke.py`, `tools/luatools.py`,
  `tools/modules.py` - the build.

Configuration lives in `CFG` in `src/core.lua`; the comments beside each value
say what it does and which run set it.

## Update, late 2026-09-03: the real hit signal, and Chris's 6.x line

Chris now runs a 6.x bundle written from the 5.1.72 rules ("6.6.0 Parked",
bundle only, no source in this repo). My patches on it are the files
`DungeonAutofarm-6.6.0.lua` (his), `-6.6.1`, `-6.6.2`, `-6.6.3` here, and the
Potassium workspace `dq_rewrite.lua` is the latest of those. Port them to the
6.x source: the notes in each `SCRIPT_CHANGELOG` entry say what and why.

**How to know when an attack actually hits.** The server tests an attack's
hitBox with a touch query at the moment of damage. That leaves a
`TouchTransmitter` child on the hitBox part for one frame. Listening for it
(`hitBox.ChildAdded`, class TouchTransmitter) gives the exact spawn-to-hit
delay of every hitBox attack without dying. `tools/probe_hits.lua` measures
it per attack name; 6.6.1+ learns each attack's window from it after three
samples and overrides the seed.

Measured this way (Northern Lands, Nightmare):

| attack | hits | after the Model appears | telegraph | Model lifetime |
|---|---|---|---|---|
| Champion passive beam | once | 0.92 s (0.39-1.03, n=363) | pink line visible from spawn, fades by 1.1 s | 7 s, harmless after the hit |
| Champion jump slam | once | 1.98 s | precast from spawn, off at 2.15 s | 5 s |
| Northern mage shot | once | 0.75-0.97 s | precast from spawn | |
| Champion criss cross | no touch test on the client part | server-side, continuous; can spawn on the player and kill within 0.1 s | | 10 s |
| Bob horizontal beam | once | 1.03-1.08 s (n=54) | precast from spawn, off at 1.23 s | 5 s |
| Bob spread beam | once | 0.92-1.20 s (n=42) | precast from spawn, off at 1.35 s | 5 s |
| Bob circle, ice spikes, wall | no touch test on the client parts | server-side; circle precast off at 1.18 s, spikes at 0.95-1.65 s | | 10 s / 18 s |

The old seeds held the beam lethal for 3.5 s and the mage shot for 2.5 s;
those windows, not the movement, are why the first boss looked unreadable and
the fan had no gaps. Every death-derived window in the table above the update
should be treated as superseded by a touch-test measurement where one exists.

Other findings on the 6.6.0 run: the reflexes (slam, fan) ran headings that
were safe but walled, so the character stood against rocks and died (fixed in
6.6.3: a heading must pass the wall sweep, else the field's spot); the blink
was allowed in mob fights with a second hop inside the cooldown, and seventeen
hops in pairs three seconds apart got kick eight (6.6.2: mapped bosses only,
six seconds apart, three a minute); the cast reach sat one stud past the
standing distance (6.6.1: range plus six). Not touched: 6.6.0 movement
effectiveness is lower than 5.1's (0.86-0.92 of commanded speed, 4-7 % stuck)
and it died at 7-11 studs from warriors.

Later bundles on 6.6.x, same evening (each a patch on the previous, notes in
`SCRIPT_CHANGELOG`): 6.6.7 exact windows without lead for measured attacks
(a beam is safe to cross until its one hit), effect parts never labelled,
stopped spears expire; 6.6.8 field at 60 Hz with arrival checked every 0.15 s
through the dwell; 6.6.9 range probed outward from a landed cast (a Q+E pair
landed 8.5 % on Bob from 57 studs) and remembered across runs; 6.6.10-6.6.13
Bob's orbs, settled as a pull on the field toward the spot behind the orb's
crystal with the field's spot leading while an orb is out (a separate orb
drive fought the dodging and went back and forth); 6.6.12 never stand on
ground about to go hot (reflex, blocked walk, in-range, orb hold). Runs on
6.6.7+ killed both bosses.
6.6.14 one stillness threshold for bare projectiles, owned by the reader tick,
deleted a second after they stop (two thresholds made spear boxes flash);
6.6.15 spread beam padding 8 (deaths 2.4 and 7.8 studs outside its box), ice
spike zones +6 studs and 1.2 s (they slow the character, which is what then
gets it killed), the blink's walk test on measured speed, exact windows opening
0.3 s before the earliest measured hit.
6.6.16 lane danger limited to three seconds ahead of a moving body (Bob's slow
wall had painted the whole entrance), blink destinations checked clear for the
whole dwell; 6.6.17 fan radius 70 (85 was the rocks, where the slam then landed
on a cornered bot), the reflex takes the most open safe heading of ten, corners
included, an eight-stud head-start hop on the slam's first frame, and the
speed burst may last a whole slam. Northern Lands has a third boss after Bob in
the same run: Odin (`thirdBoss*` attacks: bouncing orbs at 20-40 studs/s,
missiles at 85, multirings, bounce walls). Unmapped; the bot reaches him with a
minute or two left.
6.6.18 fan radius 75 with every spot inside it costing while the fan is on, the
fan reflex from anywhere inside at full burst; 6.6.19 range probe +5 to a cap
of 90 and cast reach range+12 (a cast landed 52 % from 66-72 studs), and mobs
are approached only with a spell off cooldown (wait at 70 from a quiet mob);
6.6.20 one slam reflex per slam (the Jump Down event was restarting it and
hopping twice), blink destinations clear for 0.75 s not the whole dwell (in the
fan nothing passed a 1.5 s test, so the blink vanished exactly where it was
needed), a box firing within a second counts as hot for the stand-still rule.
6.6.21-6.6.22 Bob's wall: its placement jump read as a huge velocity for one
sample and swept a phantom wall across the arena (first 0.4 s ignored, speed
clamped to 40), and a still wall was boxed along the world X axis instead of
the line between its two balls, so an angled wall had no box where it stood.
The replayed run on 6.6.20 killed the Champion with no deaths at all.
6.6.23 a keep-out pad of 45 studs round the Champion (spots closer cost);
6.6.24 zone lead scales with the zone's radius, a slowed character may hop
early; 6.6.25 anti-cheat kick nine: the game lowers WalkSpeed itself (ice
spike slow) and puts a part under `workspace.stunParts/<player>` while stunned;
the bot no longer forces WalkSpeed back up and stands still while stunned.
6.6.26, the fan regression Chris saw: the Champion re-aims a POOL of parked
passive beam Models. A re-aim never moves a full-line hitBox (its centre is the
hub) and the sweep's re-track gate wanted the precast seen off first, so a
Model re-cast within a second of its last hit went blind for the rest of the
fight - the fan deaths had no beam box anywhere near. Every tracked Model is
now watched (precast Transparency dropping, or a parked hitBox turning) and
re-tracked that frame. Same bundle: a field spot on the far side of a wall box
is never taken (the bot walked through Bob's wall to a "clean" spot behind
it); the slam reflex leaves the 67-stud cube through its nearest face (54 to a
corner - it ran the diagonal and died at 40 of 44 twice) and the head-start
hop is tried for 0.6 s; Bob's circles late in the chain kill as they appear
(predicted `at` is +0.1 not +0.6) and the circle strip is three nested bands
warmer toward its axis so the field walks out sideways. recorder6's boxDepth
now uses the radius for cylinders (it read a standing cylinder as a slab, so
circle verdicts before this were wrong).
6.6.27 streamer mode, a section in the Overlays window (CFG.streamer*): hides
the nameplate's name/title/VIP and the HUD name (`playerStatus.Frame.playerName`),
the health numbers/bar, `playerStatsLeaderboard` and Roblox's PlayerList, other
players' nameplates, the chat; the character is a black 2x5x2 block (the spot
marker's size) under `DungeonAutofarmVisuals`. Every property it touches is
restored when the mode goes off (ST.saved).
6.6.28: the drawing sweep (drawTick, every 3 s) destroys anything under the
visuals root that is not the Hazards folder; the streamer block is spared by
name. Anything else parented there needs the same exemption.
6.6.29-6.6.31 (round watched live on 2026-09-03 night): 6.6.26 had called
`depthOf` (a field.lua local) from brain.lua - the brain stage errored every
frame of a slam and released the character, two slam deaths standing still;
`S.depthOf` is exported now. Fan mode lasts 4 s past the last burst (it walked
back in between bursts). No range cap from a missed cast, and both ability
slots are seeded from the remembered range (Q and E are both "Geyser"; the
name-keyed seed held one slot, the other started at 49 and dragged the standoff
to 43). 6.6.31 travel: waypoints count height (a spiral stair's upper loop sat
right overhead and the flat test called it reached; every stall then skipped
further up the spiral while the body pushed into the stair mesh, 28 s stuck),
a stall re-plans from here before skipping, navmesh Jump waypoints are jumped.
Boot: `autoexec/dq_autoboot.lua` (Potassium) loads `workspace/dq_boot.lua` in
Dungeon Quest places, which loads dq_rewrite + recorder6 + probe_hits after 7 s.
Copies of both are in tools/. Delete the autoexec file to stop the auto-load.
6.6.32-6.6.33 (rounds watched live, 2026-09-04): the fan measured at last -
every passive beam hitBox is 8 x 64 x 250 centred on ONE hub (full lines, so
yaw mod 180 is right), the slow sweep is a pair 20 degrees apart stepping 20
degrees every 0.5 s, and the fan is 18 lines 10 degrees apart within 0.4 s.
At 86 studs the gaps are 5 studs; at 90 about 7; the rocks are near 100 and
the arena kills past ~128. Chain predictions are skipped during a burst (they
painted phantom lanes), the beam is `slim = 2`, fanRadius 90. Other fixes,
one per death: the range seed ran before the Tools existed and never again
(every run started at 46-49 - now retried, and a slot first seen by its cast
starts from the remembered range); mages within 90 are aggro (it stood still
"waiting for cooldown" and a volley landed), mage shot pad 3; the slam run
ends four studs clear of the box and never heads past 105 from the boss (it
ran to 140 and the arena killed it); Bob's circles march out 26 a step and
shrink 6 (the one-circle fallback grew them both ways into 100-wide phantoms);
hot ground keeps its heading (five reversals in 3 s let the wall walk over
it). 6.6.33: the cast gate used the aim point, which is the centroid of the
mob group inside the AoE - at a 74 standoff it sat at 85 against a reach of
81 and NOTHING WAS CAST for minutes ("strafing back and forth"); the gate is
the nearer of aim point and body, and the cast aims at the nearest body when
the centroid is out of reach. Measured hit windows persist in the config
(`learnedHits`, seeded into RD.hitDelay at start). Odin: profile with
arenaPull; his remote events on `northernBossSpecficEvents` are only Bouncing
Orb Beam, Orb Explosion (90-stud ball, zone radius 48) and Sideways Missile -
the Curse/Mark/Link/Lava "Third Boss" events in mapSpecificLocals belong to
other maps' third bosses. Everything else of his is server Models learned by
the touch test; `tools/poll_odin.lua` dumps the probe report, events, spawn
names and deaths while the target is Odin (data dies at the teleport).
A death while `workspace.stunParts/<player>` exists is accepted: moving then
is a kick risk (kick nine).
6.6.34-6.6.40 (live rounds, 2026-09-04 00:00-01:00):
- Bob: the pull toward the crystal is bounded (60 studs' worth) and fades on
  hot ground; the orb bubble is 17 studs / 0.75 warm; an orb within 14 starts
  a one-second straight run ("orb" reflex) toward the crystal that refuses
  lanes. Three Bob deaths were the orb catching the bot (stun inside its
  bubble, then a beam).
- Mobs: the approach closes on the AoE group centre (aimPoint) so a cast at
  the standoff lands among them.
- Champion: Jump Up -> 1.2-1.3 s later a criss cross spawns ON the player
  (d0.8-2.7 in five deaths, kills in 0.1 s) -> 0.8 s later the slam Model
  lands on the player. Jump Up starts a straight tangential run ("jump"
  reflex) and a hop at +1.1..1.35 s (the only reaction to the criss cross).
  THE SLAM HITBOX FOLLOWS THE PLAYER during the jump (recorder traces: the box
  depth stayed ~35 while the bot ran 30 studs); when it locks is not measured
  yet - recorder6 now tracks the slam hitBox after spawn (poll6 `slams`:
  age:movedFromSpawn/characterDistance). The slam hop and slam run ignore
  warm lanes (all 48 hop spots read hot from criss cross lanes once).
- Odin (probe_odin.lua, 2026-09-04): thirdBossMultiRings = eight INVISIBLE
  static parts round the arena centre (thirdBossMiddlePart, ~30 studs from
  Odin's root): center 25-wide cylinder + half-ring arcs of radii 25, 37.5,
  50, 62.5, 75, 87.5, 105 on alternating sides; a new Model at a new yaw
  every ~1 s, each alive 4-8 s; no touch test on them. Modelled as annulus
  zones ("ring arc", 6 thick, own half) tied to the Model. thirdBossLineShot:
  a 219-stud ray from Odin, 13 wide, pairs counter-rotating 12.5 deg/0.5 s,
  one touch hit at 0.85-0.89 s (seeded exact). thirdBossBouncingOrb: 12-stud
  balls, 20 s life, bounce (velocity-tracked). Sideways Missile events: 340
  studs in 4 s (85 studs/s), 10x10x30 mesh. Bounce walls ~106 from the centre.
  Orb Explosion zone 20 (the bot stood 7.6 from one and lived).
- Tools: per-instance dumps dq_rec6_<job>_<time>.json / dq_probe_... /
  dq_odin_...; poll_odin.lua; dq_boot skips the lobby and loads probe_odin.
6.6.41-6.6.45 (last of the 2026-09-04 session):
- THE SLAM BOX IS STATIC (recorder `slams` probe: moved 0 in every sample; the
  earlier "it follows the player" was the recorder re-anchoring to the precast
  after the hit). Slam runs failed on radial speed (12 studs/s of 22) from
  switching headings: the kept heading now wins unless another is 15 studs
  shorter; the step check looks 0.4 s further on (a criss cross reached the
  step after the check). The criss cross that spawns ON the player comes
  0.7-1.3 s after Jump Up; the hop window is 1.1-1.35 s (a gamble; often
  misses). This is the one death per Champion fight still unsolved.
- Bob's orbs: they close at ~30 studs/s against our 22. The burst never rests
  while an orb is out, the lead starts the moment an orb exists (was: within
  160), the pull is 0.2/stud, the handoff is 5 studs from the crystal (22 let
  the orb turn and follow the bot back out - "it forgot the orb").
- Odin: the ring arcs kill AS THEY APPEAR (a death 4 studs outside two 10-thick
  bands at the instant a set spawned), flash visible ~1.5 s, then sit invisible
  for 20 s; arc zones live 1.8 s, 12 thick. Rings every 12.5 studs on
  alternating sides: the one radius clear of every set is ~96 from the arena
  centre (thirdBossMiddlePart), between the 87.5 and 105 rings -> the Odin
  profile has `ringBand`, the field pulls to CFG.ringBandRadius (96) at
  CFG.ringBandWeight (0.3/stud). Untested at the time of writing. Missile box
  24 x 44 (a missile 12 studs away killed with the 10x30 box clear).
