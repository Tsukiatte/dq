# Rewrite (2026-09-03) — lean logic, tested against the live client

## Why
4.x grew to ~14k lines of logic and still dies to the same things. Eight
recorded runs (game/captures/) say where the deaths come from; the reference
video says what "unafraid" looks like. This rewrite keeps the UI kit, keeps the
lobby loop, and rebuilds the logic in about 1500 lines.

## What the evidence says (do not relearn this)
- Every Model attack is `hitBox` (invisible damage volume) + `precast`
  (visible warning). Fire time is per attack name and known for the Northern
  Lands (gamedata seeds: mage shot 0.5 s, spearman/warrior 0.6 s, jump slam
  1.8-5.0 s, passive beam 0-2.0 s, horizontal beam 1.1-5.0 s, circle line
  1.2-2.5 s). The Model outlives the attack; "over" = precast faded + 0.3 s
  unless the seed says it burns on. Never learn timing from being hit.
- Bare projectiles (criss cross, spearman strike mesh, orbs) are moving parts:
  the danger is the box swept along their velocity, not the point they occupy.
  Spent = faded and stationary.
- Boss remotes announce scripted attacks with exact start/end/cframe; the
  precastHitbox bridge announces ground telegraphs with exact impact time.
- The Midgardian Champion's aimed criss cross spawns ON the player's position
  every 4-16 s at any distance and one-shots at 262M HP. Movement cannot dodge
  it. The reference script stands inside attacks unharmed (frames show its HP
  unchanged while beams cross it): that is immunity, not dodging, and the
  first attempt at a position hop here got an anticheat kick. Not copied.
- Lanes of the criss-cross lattice are 15 wide on a 15-stud grid: a moving
  line's lead must be the time to sidestep (0.4 s), not the standing lead.
- Danger "already on you" may be discounted only until the thing you stand in
  fires; after that, time inside is the hit.
- A passing step is judged for the moment it is crossed; a hold for a gap must
  time out. Standing still at the spawn is the worst place to be.
- Autoexec runs before LocalPlayer replicates: wait for it. A queued dungeon
  waits for `changeStartValue`. The raw GitHub cache lags a push by minutes.
- Tween (CFrame steps on the floor) at 16-22 studs/s never drew a kick.

## Architecture (load order)
| module | lines | job |
| --- | --- | --- |
| core | ~200 | services, CFG, RT, version, small helpers, wait for player |
| uikit | kept | widgets |
| reader | ~400 | every current hazard as oriented boxes with [from, until]: Model attacks by seed, moving parts as swept boxes, boss events, precast bridge |
| field | ~250 | danger(x,z,t); ring search with grace cutoff and a wider second ring; strafe bias toward tangential motion around the target |
| mover | ~120 | floor-following tween; walk 16, escape 22; controls handed back on stop |
| brain | ~300 | rooms: nearest mob, standoff by melee/ranged, strafe; travel: straight or navmesh to the next room/boss; boss: ability range, orbit, abilities on cooldown |
| draw | ~150 | one translucent box per hazard, colour by stage; target marker; nothing else |
| lobby | kept | queue, START, replay, park |
| config | ~150 | load/save/autosave of CFG |
| ui | ~450 | Autofarm, Dodge, Auto queue, Overlays, Configs windows on the kit |
| main | ~150 | startup, heartbeat, HUD |

Budget: logic (reader+field+mover+brain+draw+main) under 1400. If a module
needs more than its budget, the design is wrong, not the budget.

## How it is tested
Against the live client through the Potassium bridge: `execute_luau_file` the
bundle, `tools/recorder_live.lua` records hits with the reader's verdicts, and
each change is judged on deaths per boss and boss damage per minute alive.

## Rules learned from the live runs (2026-09-03, 5.1.8 - 5.1.12)

- **Never write the root's position.** Three anti-cheat kicks, all server-side:
  a 14-stud hop (4.12.11), a lag-spike step plus a fall through the floor
  (5.1.1), and ordinary per-frame CFrame driving (5.1.6/5.1.7). Since 5.1.8 the
  mover only calls `Humanoid:Move`; the escape burst is a temporary WalkSpeed
  of `tweenEscape` (22) restored the moment the burst ends. 4.12.14 ran the
  boss approach at WalkSpeed 22 for whole runs without a kick, and the client
  checker only resets values above 45.
- **A moving body is danger from its announcement.** The aimed criss cross is
  placed on the player's position at the event and hurts there until its start
  time; the big spike's front leaves the boss at the event. The field evaluates
  the body's position at the time asked for, so no lead gate is needed.
- **Remote-announced paths carry the boss's height.** They are ground attacks
  (`ground = true`); the vertical filter must not drop them.
- **The body counts.** A beam killed 1.5 studs outside its hitBox: `dodgeMargin`
  1.5 on top of the root's half width.
- **Melee mobs are a soft zone.** Their strikes are telegraphed Models and are
  tracked as boxes; a hard 19-stud circle round each mob left the field with no
  spot in room 1 while mage shots landed.
- **Settings, not constants, persist.** The config file keeps only UI-exposed
  keys (`PERSIST` in config.lua); snapshotting all of CFG kept every old
  default alive across releases.

### Test loop

1. `cd rewrite && python tools/check.py && python tools/build.py`, then copy
   `rewrite/DungeonAutofarm.lua` to Potassium's workspace as `dq_rewrite.lua`.
2. In the lobby instance, `queue_on_teleport` a script that waits 7 s, runs
   `loadstring(readfile("dq_rewrite.lua"))()` and `dq_recorder5.lua`, and
   re-loads if the autoexec's main bundle takes over later; then
   `S.queueNow("claude")`.
3. Poll with `tools/poll5.lua` (deaths with nearby boxes and the field's top
   candidates, boss health, state histogram, mover counters).
4. Patch, rebuild, `loadstring(readfile("dq_rewrite.lua"))()` mid-run; the new
   instance destructs the old one.

### Champion facts that cost runs to learn (2026-09-03, runs 14-17)

- The dungeon clock is 10 minutes. The fight is ~7 s of ability uptime at
  30-40 studs (11-15 % of boss health per second there, nothing past 40); every
  death costs ~25 s. Deaths are the whole problem.
- **Arena leash.** Past ~128 studs from the Champion the character dies with
  nothing near it; the respawn point is 131-137 out. The field treats ground
  past `leashRadius` (122) as lethal so a respawn walks in immediately.
- **Beams** are 8 x 250 through the boss's position, fired 8-10 a second for
  most of the fight with scattered yaws; they hurt from ~0.3 s after the Model
  appears (seed `first` 0.3) and for ~2 s. Retreating past their reach is the
  leash - do not.
- **Aimed criss cross**: 15-stud mesh spawned 2-17 studs from the player,
  start time = announcement, 30 studs/s along its LookVector; a moving
  character survives most of them, a parked one does not.
- **Big spike**: 40-wide front, announced 1.4 s before it leaves the boss at
  100 studs/s. Needs 23 studs of sidestep at the burst speed, so the burst
  keys off dwell-aware danger, not danger at this instant.
- **Jump slam**: `First Boss Jump Down` (Vector3) is the landing point; the
  67-stud slam Model appears at landing and hits 1.8 s later.

### Mobs at high level (Chris, 2026-09-03)

The bot must never be within weapon reach of any mob: abilities only and
dodging. 5.1.26 fights every mob from `mobStandoff` (34) past its body with
auto attack off, counts warriors as melee (`meleeMobMaxReach` 16; their melee
distance is above 8, which is why they were approached to 22 studs and one
circle strike killed), backs straight off any target inside standoff minus six,
and makes a melee mob's swing reach a hard zone. `abilityRadius` (42) must stay
above `mobStandoff` or nothing is ever cast at a mob.
