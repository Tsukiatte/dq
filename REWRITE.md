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
