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
