# Dungeon Autofarm — Changelog

Version lives in `DungeonAutofarm.lua` as `SCRIPT_VERSION` / `SCRIPT_BUILD_DATE` /
`SCRIPT_CODENAME`, mirrored in the in-script `SCRIPT_CHANGELOG` table. Keep this
file and that table in sync on every edit.

**Bump rules (semver):**
- `MAJOR` — rewrite or breaking change to core architecture
- `MINOR` — new feature, new UI element, new subsystem
- `PATCH` — bugfix, tuning, constant change, refactor with no new behaviour

---

## 4.11.1 - 2026-09-02

- `stampAttackWindow(position, radius, first, last, prefix)`: the stamp goes
  to the nearest tracked Model whose key starts with `prefix` ("model" for the
  Aquatic laser). Verified live: without the filter a mage shot within the
  radius took the window.
- Simulator: the criss cross fires in volleys (`DQSimCrissCount` 5, spread
  `DQSimCrissSpread` 20 studs round the player) - Chris counts ~15 crossing
  the map at once in the real fight.

## 4.11.0 - 2026-09-02 - "Aquatic Temple"

From Chris's Aquatic Temple capture (8 hits) and the place file's client
handler for `aquaticBossSpecficEvents`:

- The boss's attack Models are renamed **"Model"** on the client (the laser
  precast, the orbs). Learning by name pooled them all into one window
  (396 "model" lifecycles, all live for their whole 5 s). A generic name is
  keyed with the hitBox's rounded size: `model:4x8x35`.
- **`first boss laser shot`** `{start, end, cframe, distance, ...}`: the
  window is stamped onto the precast Model at that place
  (`S.stampAttackWindow`, `HZ.windowStamps` for Models not yet tracked) and
  kept as a cube zone along the line for the sweep.
- **`first boss moving orb` / `last boss moving orb`** `{cframe, start, end,
  distance, duration}`: Parts with no hitBox, so the index never sees them;
  `PC.paths` from the event, radius `aquaticOrbRadius` (5, not captured yet).
- **`third boss smite`**: circle zone (`aquaticSmiteRadius` 10, 0.6 s).
  **`second boss show damage parts`**: each child of
  `workspace.secondBossDamageParts` a cube zone for `aquaticDamagePartHold`.
- Seeds: `cubepylonshot` 0.8-1.1 s (certain hit), `model:4x8x35` 0.9-3.6 s.
- **Learning epoch** (`LEARN_EPOCH` 2): every save drops its learned timing
  once, whatever build wrote it - a save rewritten by a new build had carried
  the poisoned values forward.

## 4.10.10 - 2026-09-02 - "From the moment it exists"

Chris's real capture of the Midgardian Champion (2026-09-02), seven deaths:

- **Five were `firstBossCrissCross` at 0% along its path with `danger=0.00`.**
  The game's client code places the body at its origin on the event (on the
  player) and it sits there until its start time; the server hurts while it
  sits. `PC.paths` entries carry `spawn` and are live from it, in `dangerAt`
  and in hit attribution.
- **One was `firstBossJumpSlam`** (67-stud cube round the landing, precast
  shown) at 1.8 s, certain. Seeded (`DEFAULT_ARM_DELAYS` / `DEFAULT_ARM_SPANS`).
- **Every beam and mage shot in that run was "armed +7.0s (learned time)"**:
  timing learned before 4.10.2 by nearest-part blame, persisted in the config.
  Floor for its whole life, so never dodged, and drawn as a box the whole time
  (the "ton of boxes"). Saves older than 4.10.2 no longer carry learned
  timing or learned names into a new session (`trustLearned`).
- **Floor is not drawn** (`drawPendingHazards` false): a box now means it can
  hurt. It appears the moment the attack is about to arm.
- Simulator: the criss cross spawns at the player and hurts from spawn.

## 4.10.9 - 2026-09-02

- The stronger (`dodgeHubRingWeight`) pull applies whenever the dodge box is
  the approach - pursuit stopped at the edge of something - not only on the
  ring. Otherwise the quiet gap went by "safe here" at 50 studs, out of
  ability range.

## 4.10.8 - 2026-09-02

- The hub ring pull is `dodgeHubRingWeight` (3) times the ordinary approach
  weight. At the ordinary weight the distance cost of an 18-stud move beat it
  and the character sat at 30 studs "safe here" while the sweep came round.
- With no path and the target within `directHopDistance` (8 studs), walk to
  it directly. The path to a standoff point a stud or two away was failing
  ("NO PATH - retrying"), which read as stuck, blacklisted the spot and fled.
- Simulator: a dead boss is rebuilt (a dead Humanoid cannot be revived by
  setting Health), so kills per run can be counted.

## 4.10.7 - 2026-09-02

- The hub ring is held from wherever the last dodge left the character: the
  approach (and so the ring pull) is set whenever the target hub is active or
  imminent, not only within a box-length of the boss or with pursuit blocked.
  A dodge that ended 80 studs out during a burst had left it standing there.

## 4.10.6 - 2026-09-02

- **The hub's rhythm sets where to stand.** `hub.active` (lines coming now)
  and `hub.imminent` (the gap, `hub.gap`, is nearly used up: within
  `dodgeHubLeave` 2.5 s of the next burst) hold a ring at `dodgeHubStandoff`
  (now 50 studs: at 27 the lines of a 20-degree sweep have no gap between
  them, at 50 they have ~10). The ring is held from both sides. In the quiet
  the character comes in to the ability standoff and casts.
- The radial hub cost applies only while the hub is active: the 10 s rate
  window kept it on through the whole quiet gap.
- Pursuit does not walk in while the ring is held (`DG.hubHold`).

## 4.10.5 - 2026-09-02

- A hub's lines are the ones **centred** on it (within `dodgeHubTolerance`
  along the line too). A mage shot crossing the boss was counted as one of its
  beams and took over the hub's name, arming delay and headings.
- The hub period is the interval between lines of one burst; an interval over
  `dodgeHubBurstGap` (2 s) is a gap (`hub.gap`), not the period. Folding the
  10 s gap in put the period at ~2 s for the first half of every burst, so
  every predicted line came late - when the hits were landing.

## 4.10.4 - 2026-09-02 - "Fight from range"

- The game's enemy Models carry their own numbers (`enemyStyle` "boss1",
  `meleeDistance` 4, `aggroRange` 50, `moveSpeed` 16, `level`, `damage`) and
  the script reads them (`isBossModel`, `getEnemyMeleeReach`).
- A boss (style says boss, or line attacks pass through it) is fought from
  ability range: `bossStandoff` 26 studs, inside the `abilityRadius` (now 30)
  and outside its melee. The swing only goes if we are inside our own reach
  anyway. A mob's standoff is its body plus the melee distance the game gives
  it.
- The dodge's danger ring round an enemy is its melee reach, not where we
  stand. The approach arrives half a stud inside the standoff, so a swing or an
  ability is in range on arrival.
- The stuck detector leaves the dodge's deliberate holds alone (gap wait, hub
  hold, blocked pursuit): it had been jumping the character into the pattern
  it was waiting out.
- Harness: `RT.abilityHook` (the Loader tells the simulator about Q/E),
  simulator boss carries `enemyStyle`/`meleeDistance`, abilities damage it from
  `DQSimAbilityReach` (30) every `DQSimAbilityCooldown` (1 s).

## 4.10.3 - 2026-09-02

- A scripted projectile (`PC.paths`) is a hit candidate: where the game's own
  numbers put a spike right now. A hit while one rolled over us was pinned on
  whatever floor line we stood in, which taught that line a 6 s window. The
  hit log says `projectile <name> is here now` and `BLAMED projectile`.
- `firstbosspassivebeam` is seeded with a window of 0.3-1.2 s
  (`DEFAULT_ARM_SPANS`). Nothing on the beam Model ever shows, so with no
  window every beam was a wall for its whole 7 s; a burst of 13 was a wall
  everywhere, the character froze at the arena edge and the projectiles took
  it. A hypothesis: a certain hit at a later age widens it on the spot.

## 4.10.2 - 2026-09-02 - "Read the sweep"

- A hit teaches an attack's window only when the blame is **certain**: the
  attack encloses us and no other live one does (`noteAttackHit(part,
  confident)`; the hit log says `certain` or `ambiguous (n enclosing)`). An
  ambiguous guess used to stretch the window for the rest of the fight - the
  mage shot's 0.9-1.2 s became 0.9-6.9 s from being blamed for beams, and every
  red line on the floor was a wall for 8 s. That was the "hitboxes stay longer
  than the attack".
- **The sweep.** The fight save parks the Midgardian Champion's beams 20
  degrees apart, and the capture saw them every 0.5 s in bursts of 4 and 13,
  10 s apart. A hub records each line's heading; when the last two steps
  agree, the next `dodgePredictSteps` lines are placed before they exist
  (`hub.pred`), floor until their time and a line for as long as such lines
  have hurt (`dodgePredictedLive` until learned).
- A hub whose expected volley is a whole period overdue is quiet and the
  approach is allowed. Before, an expected time in the past held the
  character out forever.
- Simulator: bursts of 13 and 4 beams, 20 degrees per 0.5 s, every
  `DQSimBurstGap` (10 s); `DQSimBeamHurt` = `pulse` (0.3-1.0 s) or `long`
  (0.5-7 s); the fight save's own floating boss Model is removed.

## 4.10.1 - 2026-09-02

- While a hub's gate is closed the character waits on a ring
  (`dodgeHubStandoff`, 20 studs) instead of drifting out to 55, so the dash in
  and out fits inside a volley gap.
- Blame for a hit goes only to an attack that encloses us, when any does.
- Seeds from the Northern Lands captures and the harness (`gamedata.lua`):
  `northernmageshot` 0.9 s, the strikes 0.85 s, all over by 1.2 s
  (`DEFAULT_ARM_SPANS`); `firstbosspassivebeam` is long-lived
  (`DEFAULT_LONG_LIVED`). Applied wherever nothing has been learned.

## 4.10.0 - 2026-09-02 - "Stay out of the hub"

In the Studio recreation of the Midgardian Champion, every remaining hit came
with `danger=1.00` and a safe box 18 studs away: at melee standoff the
character stands where every beam crosses, and two crossing beams cannot be
cleared inside their 1.5 s telegraph. Pushed out to ~60 studs it took **no
hits for a minute**.

An enemy that long line attacks pass through is a **hub** (`DG.hubs`). Each
new line part (>= 60 studs) whose axis passes within 12 studs of an enemy is
counted once; the rate over the last 10 s and the interval between volleys
are kept per enemy. Then:

- every candidate carries a radial cost: `rate x (width / (pi x distance)) x dwell`,
  the chance a random line through the hub covers that spot over the time
  we would stand there;
- the approach to melee is allowed only when `now + approachTime + exit <
  lastVolley + period + armingDelay`, i.e. there is time to go in and get
  back out before the next volley fires (`DG.hubHold`, shown in the status).

Enemies that fire no lines are untouched.

## 4.9.9 - 2026-09-02

- A parked Model (dormant, or silent for 30 s) never gets the blame for a
  hit. The 14 beams parked at the arena centre kept being credited with hits
  from live beams passing through, which woke the pool and stretched every
  beam's learned window to the length of the fight.
- A learned window is trusted as it stands (`done: window over` at
  `last + armAssumedLinger`), without waiting a further 2 s for the visuals
  to fade. The mage shot's line stays drawn ~7 s after its single hit.
- Harness: strikes fire at 0.85 s (the capture measured 0.88 s), not 0.4 s.

## 4.9.8 - 2026-09-02

Candidate lines are sampled every `dodgeSampleSpacing` (2.5) studs, 2-8
samples per line, instead of at three fixed fractions. Three samples on an
18-stud line sit 6 studs apart and a mage shot is 3 studs wide: a line that
stepped straight through one scored clean. Arrival is sampled at T as well
as T+dwell/2 and T+dwell.

## 4.9.7 - 2026-09-02

- Boss projectile paths failed the dodge's vertical test: a rolling body's
  centre rides its radius above the floor (the big spike's 20 studs up) and
  the tolerance reached ~10. The path existed and was ignored; the hit landed
  with `danger=0.00`. A path's vertical reach is now at least its radius.
- `FirstPart` kept being learned from a hit taken inside it despite the age
  guard. A big anchored part (>= 40 on any axis), or any anchored part
  directly under Workspace, is never learned as an attack.

## 4.9.6 - 2026-09-02

A hit that lands after an attack's warning has faded (and the fade marked it
over) means the attack keeps hurting after its warning - the passive beams
burn for four seconds after the precast goes. Such attacks are remembered by
name (`armLongLived`, saved); their fade no longer ends them, only the learned
window, a removed hitBox or the Model going away. The harness simulator was
corrected to the game's convention (precast fades **at** the hit) after it
was caught teaching the learner that beams arm at 5.4 s.

## 4.9.5 - 2026-09-02

Every `HIT` block in the capture now carries a `DODGE` line: danger reading,
reason, whether a box was held, `gapWait`, `pursuitBlocked`, and the HUD
status at that instant. Harness metric after 4.9.4: ~5 hits/min against the
recreated Midgardian Champion (was ~10). The rest get explained one by one.

## 4.9.4 - 2026-09-02

From the Studio harness, three things the real Northern Lands fight also has:

- **FirstPart**, the 217-stud invisible cube around the boss arena, was learned
  as an attack after a hit: the 20-second age guard used the index timestamp,
  and parts present before the script started never get one. Nothing
  arena-sized (>= 100 x 40 x 100) is an attack now, and no timestamp = old.
- The **14 passive-beam Models parked at the arena centre** read as live for
  the whole fight - a permanent wall through the middle. A ground-truth Model
  that has shown nothing, not moved and not hit us for `dormantAfter` (10 s)
  is dormant; moving, showing, a hitBox change or a hit wakes it as a fresh
  spawn (its timers restart from that moment).
- The enemy attack name table held **generic names** (`meshpart`, `ball`,
  `wave`, `ice`, ...) that matched map geometry. Removed; structure still
  catches the attacks.

## 4.9.3 - 2026-09-02

From the Studio harness: a hit was blamed on the *nearest* known attack, and a
beam that appeared 0.2 s ago through where we stand is nearer than the one
that has been burning us for a second. That taught every beam to be live
from 0.2 s and turned the arena into walls. Attribution now scores candidates
(encloses us +2, old enough to have fired +1, armed and not over +1, learned
window covers now +2; ties to the nearest) and the capture's HIT block gets a
`BLAMED` line saying who and why.

## 4.9.2 - 2026-09-02

Found on the first run in the Studio test harness: `updateHazardHighlights`
keyed adornments with the debug-id API, which needs plugin permissions in
Studio and threw every tick - after the scan built its volumes and *before*
the dodge decided. The dodge never ran once and the character stood in beams
reporting `dangerHere 0`. Parts are keyed with a weak-table counter now, and
the highlight and telegraph-feed renderers run under `pcall`: nothing
cosmetic can take the dodge down again.

## 4.9.1 - 2026-09-02

### The seven-second delay
The second Northern Lands capture: every `northernMageShot`,
`spearmanStrikeHitbox` and `northernWarriorLineStrike` carried a saved arm
delay of ~7 s (`armed +6.9s (learned time)`), learned by 4.5.1 from the Model
being deleted at 7.0 s as if that were the precast fading. Each one was
therefore **floor for its first 5.7 s**. Learned timing (`armDelays`,
`armSpans`) and auto-learned names from saves written before 4.9.1 are
discarded on load; hand picks (attack book `source = "picked"`) are kept.

### What a mage shot actually is
`0.9:channels 0>2 0.9:HIT`: nothing visible for the first 0.6-0.9 s, then the
precast appears (0.35) and a second channel switches on at the very moment
the hit lands. The visible "precast" is the hit, not the warning. The
hit-window learning from 4.9.0 handles exactly this once the poisoned delay
is gone.

### Also
A part that has stood in the world for 20 s is never learned as an attack
(`Workspace.FirstPart` was). Learned names that match an anchored part
directly under Workspace are dropped on load.

## 4.9.0 - 2026-09-02 - "Learn from the hit"

### What the capture said
For every `northernMageShot`, `spearmanStrikeHitbox`, `northernWarriorLineStrike`
and `firstBossPassiveBeam`: precast Transparency **1.00 for its entire 7.0 s
life**, hitBox present until the Model was deleted, nothing the tracker
watched ever changed. So every one of them was a seven-second wall, whenever
it actually fired.

### Every channel, and a timeline
The tracker watches every way an attack can show itself: part, Decal and
Texture transparency; ParticleEmitter, Beam, Trail, Gui and Highlight
`Enabled`; Sounds playing; parts arriving after spawn; the hitBox changing
(CanTouch, CanQuery, size, transparency). Each attack's own timeline
(`0.0:channels 0>1 1.4:sound 1.4:armed:sound 2.1:done:faded …`) is written to
the ATTACK LIFECYCLES section of the capture file.

### Learn from the hit
Being hit is the one unambiguous signal. The nearest known attack (by its
**nearest point**, not its centre, so a 274-stud beam gets the blame) learns
its **window**: first and last age at which it has hurt us (`RT.armSpans`,
saved). From the next cast on it is floor until the lead, danger through the
window, and floor again `armAssumedLinger` (1.0 s) after - unless it is still
visibly on. The one that just hit is never "over". This replaces the
strike-and-pin rule.

### Also from this run
- A part named after **you** under `workspace.stunParts` (a stun marker riding
  on the character) had been learned as an attack. Status markers are never
  hazards, are never learned, and are purged from an old save on load.
- Enchanted Forest: `Crystal 52.9s`, `Glow 53.0s` - the appearance scorer
  highlighting decoration by the dozen for a minute, which was itself a frame
  cost. Decoration names never pass the scorer, and anything flagged on looks
  alone that is still there after `appearanceMaxAge` (12 s) is scenery for
  good.

## 4.8.0 - 2026-09-02 - "Gone means gone"

### Attacks that stayed red after they finished
Four or five seconds of red after an attack had visibly finished - the hammer
bots' most of all, and most of the Steampunk boss's - and the character
guided itself along them like invisible walls. In `updateArming`:

- The precast's darkest transparency was tracked **only while pending**, so
  anything that armed the moment it appeared (live-from-spawn attacks, which
  a pulsing or fast-brightening precast produces via `armMinDelay`) never had
  a minimum to compare its fade against, never counted as over, and stood
  until the game's Debris deleted the Model. Tracked always now.
- Expiry follows the game's own rule: an attack is **over when everything
  visible about it has faded to transparent or been removed** (after having
  been visible), or when its **hitBox is gone** while the rest lingers for
  effects. No longer tied to how, or whether, it armed.
- Attacks split across sibling Models (`crossShuriken/hitBoxes` beside
  `crossShuriken/precasts`) borrow the parent's visuals and precast.
- `PrimaryPart` anchors are never hazards, and neither is decoration inside a
  Model that has a hitBox (the ball's core, a cog's teeth). The 4x1x2 anchor
  at the centre of every attack was a five-stud hot spot.

### Diagonal stairs
Every forward probe (segment test, waypoint step, idle path step) now runs
its hit through `hitBlocksWalking`, the step-versus-wall classifier the
direct steerer already had: a surface facing up is floor, and a lip under
`maxStepHeight` (2.4) is stepped onto. The shin-height probe added in 4.5.1
for the pillar plinth had been reading every stair riser as a wall, steering
the character diagonally up each flight.

### Found reading
- The mover watchdog **rewrote `moveMode` to `walk`** after one second of no
  movement - which a cornered character always produces - so the tween you
  chose silently became walk for the rest of the session. It borrows walk
  for three seconds now (`RT.moverFallbackUntil`) and hands back.
- The wall-stall sidestep kept its anchor across ticks it did not run, so it
  could fire a sidestep and a hop on the first tick of a new path.

## 4.7.0 - 2026-09-02 - "Steampunk knows too"

`src/northern.lua` is now `src/bossevents.lua`: one listener per map remote,
hooking every one present (`northernBossSpecficEvents`,
`steampunkBossSpecficEvents`, the shared `mapSpecificEvent`), with a handler
table per map. Read from the Steampunk Sewers client handler and the Evil
Scientist's models live in Studio.

| event | what we do |
|---|---|
| Drop Cogs | every cog part is tweened 100 studs straight down over 0.75 s: each landing footprint is a cube zone with the exact time |
| Steampunk Back Flames (`mapSpecificEvent`) | flame jets light 0.5 s after the event for 1 s: each jet is a zone with that window |
| Second Boss Random Pulse (the ball) | live from spawn; named in the log |
| Second Boss Pulse Wave / Aura | visuals; the damage is the six beam Models, which arm through their precasts |

Server-spawned Models (the six-beam pulse wave lattice, `outwardBlastSize1-5`,
`secondBossPunchCircle`, `secondBossZigZag`, `secondBossOrbShot`,
`bossCannonBeam`, `bossHorizontalBeam`) arm through their precasts as
before. Two arming delays are **seeded** (`DEFAULT_ARM_DELAYS` in
gamedata.lua) so the first cast is time-aware without being learned: the
pulse-wave `beam` at 4.5 s (measured 4.8 s in the 15:19 video), and the ball
(`secondbossrandompulse`) at 0 = live from the start. Anything learned in
play overrides a seed.

Settings renamed: `useNorthern` → `useBossEvents`, `northernSafeLead` →
`bossSafeLead`, `northernFlameDelay` → `bossFlameDelay`.

## 4.6.0 - 2026-09-02 - "Northern Lands knows"

Read from the game's client handler for `northernBossSpecficEvents` and from
the attack models live in Roblox Studio (via the Studio MCP). Every timed
attack of the three NL bosses and the bonus boss is sent to the client
*before* it happens, with the numbers the client animates it with. Those
numbers are the attack. New module `src/northern.lua` hooks the remote and
requires the game's own `timeSync` clock, so it reads the same timestamps.

| event | what we do |
|---|---|
| First Boss Criss Cross Projectile, Seeking Spike, Big Spike | scripted **path**: position(t) from start CFrame, distance, duration, start/end time |
| Second Boss Big Hitting Ground Spikes | circle zone, radius 15/25/40, **exact** impact time, held 0.7 s |
| Second Boss Moving Beam | scripted path, a 57-stud bar sweeping along its look vector |
| Third Boss Bouncing Orb Beam, Bonus Boss Freezing Orb Beam | pillar zone held open 6 s |
| Third Boss Sideways Missile | scripted path with the missile's 10-stud head start |
| Spearman Strike, Warrior Line Strike | cube zone behind the cframe, 0.5 s |
| Bonus Boss Tall Swirly | arena explosion at its exact time + a **timed safe window** on the matching colour spots |
| Bonus Boss Flame Pre Target | the marker is never a hazard; the flame lands where it stops |

The dodge gained three sources: `PC.paths` (where a projectile *will* be at
time t, as a box in its own frame), zones with `holdFor`, and
`PC.safeWindows` (outside the spot is danger only around the explosion).

Also: precasts that rest fully invisible and are faded *in* by the server
(`secondBossLines/1-11`, `bonusBossSweepingFlames`) are live until they show
and a telegraph from then on, rather than live forever. The full model table
(246 attacks, precast/hitBox sizes and transparencies) is in
`game/attack_models.txt`.

## 4.5.1 - 2026-09-02

### Played-out attacks
A precast that was visible and has faded all the way (plus `armDoneLinger`,
0.3 s) marks its attack as **over**. It leaves the detected set: no danger,
no highlight, not in the count. The strips of a beam pattern stayed red for
seconds after the beams had fired and the dodge kept weaving between attacks
that were over.

The colours are honest now: **amber** with `floor 2.3s` only while the dodge
actually treats the part as floor; `arms in 0.8s` in red once its impact is
within the lead; `announced` in red when its timing is unknown and it is
being dodged as live. A hit taken while announced saves that attack as
live-from-spawn (`armDelays[name] = 0`) so it is never re-learned from its
fade.

### Standing into the pillar
Every pursuit probe looked at chest height, and the plinth of a pillar is
below that: the probes said clear, the feet hit the plinth, and the character
stood into the wall. The forward probe, the side-clearance rays and the
segment check all have a **shin-height** ray now. A character that has
stopped moving on a path for `wallStallTime` (0.6 s) sidesteps, alternating
sides, hops, and lets the path recompute from the new spot.

## 4.5.0 - 2026-09-02 - "Telegraphs are floor"

### Dodging attacks that were not happening
The boss arena was a lattice of red strips for five seconds before a single
beam fired. The dodge treated every strip as live from the moment it appeared
and carved its safe ground into slivers around attacks that were not
happening — the video shows 41 telegraphs and the character weaving between
strips 1.5 s old that fired at 4.8 s.

The game's own client script (`mapSpecificLocals`) says how to tell. Every
attack is a Model with an invisible `hitBox` and a visible `precast`, and the
precast is tweened **out** at the instant the hit lands. So:

- a visible `precast` is a telegraph — floor you may cross;
- the precast **fading** is the hit, and arms the Model;
- a `hitBox` that moves is live regardless (a shot in flight).

The age at which each attack arms is learned by its Model name
(`RT.armDelays`, saved with the config), so the *next* cast is time-aware
from the moment it appears: floor until `Lead` seconds before its impact,
then danger. The first cast of anything is still dodged as if live. A hit
taken while an attack reads as a telegraph makes that attack live from spawn
from then on (`noteTelegraphHit`).

Announced-but-not-live parts are drawn **amber** with `arms in 2.3s` on the
tag and turn red the frame they arm.

### Waiting for a gap under the pipes
The floor probe started four studs above the root. Under the pipes and
machinery of a boss room it hit the pipe, read its top as the floor, and
rejected every candidate — `waiting for a gap` with nothing wrong but the
ceiling, in the corner the character then died in. It starts just above the
root now.

## 4.4.1 - 2026-09-02

### Kiting idle melee bots into a wall
The enemy circle was body plus swing at 1.5, and enemies were extrapolated by
their velocity out to the dwell (~1.5 s). A mob walking at you was predicted
onto every spot near you, so the only safe ground was always further back.
The hard circle is now the **body only** (`extent + 1`); the swing is an
attack, and the game spawns a `hitBox` for it that is detected like any
other. A soft ring out to the standoff is a preference below the move
threshold. Enemies are extrapolated **0.4 s** ahead at most
(`dodgeEnemyLookahead`).

### Leaving the ball sideways
The discount that ended the shuffle zeroed every path sample inside the ball,
so nothing said "shortest time inside", and the new turn cost (0.25 — thirty
studs of distance) then picked the exit by whichever way the character had
last walked. Path samples inside the thing already hitting you keep half
their cost in the average (`dodgeInsideWeight`), so the nearest edge wins;
the turn cost is switched off while something is on you and its default is
0.1; and the pull toward the boss applies only to spots whose whole line is
clean *undiscounted*, so the exit nearest the boss cannot beat the exit
nearest the edge.

## 4.4.0 - 2026-09-02 - "Pick a side"

### The left-right shuffle
Against a sweeping beam it strafed left, then right, then left, with both
sides safe. Two causes, one of them new in 4.3.0. Standing *inside* the beam,
every line out starts inside it, so the new line check read every held box
as closed the moment it was chosen and the choice re-rolled between two
identical sides each decision. Path samples now **discount whatever is
already on you** — what is hitting you is not a reason to prefer one way out
over another; how soon the line is clear of it is. And a change of direction
costs (**Commitment** slider, default 0.25), a reversal all of it, for 1.5 s
after the last move, so the side picked first is kept until the other is
clearly better — which a closed line always is.

### Enemies outrank attacks
Enemies read 1.5 against an attack's 1.0. A line through a mob loses to a
line through an attack and is taken only when everything else is worse — so
it no longer strafes out of an attack into a mob, and cornered with the mob
as the only way out, it goes through the mob.

### The enemy is the distance
**Safe distance** and **Enemy space** are gone. The chase and the dodge both
stand at the enemy's body plus an ordinary swing (`enemyMeleeReach`, 5
studs), capped at your **Attack range** minus 1.5 so the bot can always
reach. Big bosses get a bigger circle from their own extents.

### The walk into the boss
Three causes. The pull toward the target applied to dangerous spots too and
was decisive in a crowded field where everything read much the same, so the
nearest-to-the-boss won — it applies among *safe* spots only now. The raycast
budget cut off at twelve, and a crowded field whose twelve cheapest spots all
failed the floor or wall check left nothing, so the blind fallback ran — it
keeps checking until something safe passes (cap 40). And the blind fallback
read `e.X` on entries that store `x`, so it errored, and fled the *first*
enemy in the table rather than the nearest. Pursuit also holds while the
dodge is `waiting for a gap`: five clear studs at a time was how it walked
into a pattern one step per tick.

### Walls
Pursuit goals are kept off walls: two hip-height side rays push the goal off
any wall closer than the character's clearance, so the next MoveTo angles
away instead of along it. The dodge's walk check is a body-wide `Blockcast`
rather than a centre-line ray.

### GUI
Legacy is called **Pathfind**.

## 4.3.0 - 2026-09-02 - "Nothing is held"

### The straight line into a new attack
The box had hysteresis, and the hysteresis re-read danger **at the box and
nowhere else**. An attack placed between the character and the box did not
exist as far as the held box was concerned, so the character kept walking its
straight line into it while a step to either side was open.

The bots that beat bullet hells commit to nothing. twinject, the Touhou player
(`github.com/Netdex/twinject`), is a velocity-obstacle bot: it re-picks its
velocity every frame from scratch and holds no target at all. The box now
survives a decision only while every sample along the line to it *and* at it
still passes. Otherwise it is dropped on the spot (`line closed`), the field
is re-read, and the re-read prices the straight line - which is what puts the
new box to the left or the right. A held box that wins the re-read is kept,
which also stops the approach creeping a stud at a time.

### Pursuit is back, underneath the dodge
4.2.0 dropped pursuit outright in Dodge mode, so the bot could no longer cross
a room. Pursuit walks the map again. The loop only reaches it with no box to
follow, and even then it gets a step only if the next **Pursuit probe** studs
of its route are clear (`dodgeStepClear`). When they are not, the character
holds (`holding for a gap`) and the box, told pursuit is blocked, picks the
way in one safe spot at a time. Near the target the box is the approach, as
before. Dodging always outranks pursuit.

### Macros are gone
The recorder, the player, the macro file, the island option, the Routes
section, the overlay toggles and every `macro*` setting. The island is
**Legacy** or **Dodge**; a saved `macroMode` of `macro` loads as Legacy. Dodge
is the default.

### Settings versus lists of settings
Section headers are darker than the rows, and an open section's rows sit in a
darker well, so a setting and a list you can open no longer look the same.

## 4.2.1 - 2026-09-02
- The HUD status names the active mover in brackets — `DODGE waiting for a gap
  [tween]` — so "is it tweening?" is answered by looking. The **Movement**
  dropdown at the top of the Dodge section switches between tween, walk, steer
  and velocity; tween is the default, and only a config saved on an older build
  would override it.

## 4.2.0 - 2026-09-02 - "The box is the approach"

The bullet-hell screenshot was the most diagnostic yet: **42 telegraphs
detected** on the HUD, the whole floor red, the box sitting on a lethal spot.
Detection was working. The dodge was being handed a field it could not read.

### One box the size of the arena
The mesh-swarm clustering from 3.0.5 collapses six-plus parts under one Model
into a single bounding box. A boss pattern of forty `hitBox`es under one Model
became **one hazard covering the arena** — every candidate read 1.0, and the
pockets between the bullets did not exist as far as the dodge could see.

Parts the game says are attacks are exact geometry and are never merged now.
Clustering still applies to what it was built for.

### No gradient
The candidate score was the *worst* of its five samples. In a busy field every
candidate is hit at *some* moment, so every score was exactly 1.0 and the
nearest won — even if lethal. It is now **half the worst and half the
average**: a spot hit at one moment on the way is not as bad as one hit at every
moment, and in a bullet hell that difference is the only gradient there is.

### The box is the approach
Pursuit drove the character straight through the pattern to get in range
whenever *here* was momentarily safe. In Dodge mode pursuit no longer moves the
character at all. Among safe candidates the box prefers ones nearer the target
(**Approach**), so the character closes on the boss only across clear ground —
and when there is no safe way forward it **waits**, which is what a person does
in a bullet hell. In range and safe, it stands and swings.

The enemy soft ring is now a preference weighted below the move threshold,
because standing at attack range was reading as "unsafe" and the character would
oscillate at the edge of it.

### Denser field
Four rings of twenty-four. The pockets are small; sixteen rays at eighteen studs
put seven studs between samples on the outer ring, wider than the gaps.

## 4.1.1 - 2026-09-02

### Noticed once, never again
The capture made it plain. From one Cog Shooter shot, `steampunkRangeMobShot`:

```
HAZ | Union   | tr 1.00 | anc cog2(Model) < cogModel(Model) < steampunkRangeMobShot
-   | precast | tr 0.80 | anc steampunkRangeMobShot(Model)
```

Same model, opposite verdicts. The cogs spawn **at the enemy**; the purple
precast spawns **on the player** — a moment after we swung, because we swing
constantly. That is precisely the window `markOwnIfRecent` reads as "one of
ours". The first cast of any attack aimed at you survived because no swing
preceded it; every one after was claimed as our own effect and waved through.
It also explains why Select attack would not take it.

Ground truth now beats timing: a structural or named enemy attack, or anything
inside a creature, is never marked as ours, whatever the clock says.

### Backing into walls
Two changes, because the screenshot showed them compounding.

- **Enemies are judged where they will be.** Each enemy carries a velocity
  from its last position, and the danger test uses `position + velocity * t`.
  A spot thirteen studs from an advancing mob is eight studs a second later;
  scoring it where it *is* made the character sidestep into whatever was
  beside it instead of backing away from the advance. Big bosses widen their
  circle by their body, so a stomping leg counts — the log showed the Cyclops
  landing hits with its legs at 2 studs while its root sat well outside the
  circle.
- **Walls are pockets, not just obstacles.** Reachability was already checked;
  now three rays from each candidate — ahead and to both sides — price how
  little room lies past it. A dead end costs; a pocket costs more. The loop
  still stops as soon as no remaining base cost can beat the best adjusted
  one, so it is a handful of extra rays per decision.

## 4.1.0 - 2026-09-02 - "Ground truth, all the way down"

### Most attacks were dropped one line after being detected
3.4.0 made classification structural, so the **invisible `hitBox`** that
actually damages you became a candidate. Then, in `scanDamageBricks`, the
per-frame loop had its own gate:

```lua
if instance.Parent and instance.Transparency < CFG.telegraphTransparencyCutoff
```

It threw the `hitBox` out of `HZ.detected` **every frame**, regardless of what
classification had decided. Only the visible `precast` survived. So the red disc
showed, the precast faded, and the damage volume underneath — the pool that
grows twice, the yellow disc, the purple beam — was never dodged at all. Every
one of this level's attack names was already in the table; nothing was
*missed*, it was *discarded*.

Parts the game says are attacks are now stamped `HZ.groundTruth` at
classification and exempt from that gate. The gate still applies to the
appearance-scoring fallback, where a faded telegraph really has resolved.

### Body parts were hazards
`LeftHand 50.7s`, `MeshPart 29.8s`, `Glow 29.8s` — creature body parts tracked
as attacks for a minute at a time. The creature check looked only at the
**nearest** Model, so a hand inside an Accessory's Model or a glow inside a gear
Model slipped through to the appearance scorer. `insideCreature` walks every
ancestor now. A creature's own `hitBox` still counts; nothing else inside a
creature does.

### Every hit names its culprit
On any drop in health, everything within `hitSearchRadius` is ranked by
distance and written into the capture — tagged `known`, `body`, `map` or
`UNKNOWN`. The nearest thing that is not ours, not the map and not a creature's
body is the culprit, and **if detection did not know it, its model name is
learned** on the spot. The old trial-run learner did this and was removed when
the name tables arrived; the tables turned out incomplete for exactly the
attacks that matter, and a hit is the one signal appearance cannot fake. The
Attacks panel shows the last culprit.

### Reversing into corners
The dodge now charges extra for a spot with a wall right behind it: one ray
from the candidate in the direction of flight, and a **Corner penalty** in
proportion to how little room lies beyond. A pocket you cannot keep fleeing
from is not a refuge. Candidates are still checked cheapest-first and the loop
stops as soon as no later base cost can beat the best adjusted one, so it costs
about one extra raycast per decision.

### Show search range
A ring at `Reach`, so nowhere-was-safe and it-was-not-looking-far-enough stop
looking the same.

## 4.0.0 - 2026-09-02 - "The box"

The dodge is rebuilt from scratch around the shape of the thing that actually
works in a few hundred lines: **a box that is never in danger, and a character
that follows it.**

### Removed
`clone.lua` and `threat.lua`, and with them the 900-cell grid, the heat field,
the space-time A\*, the enclosure, cover, depth, freshness, hysteresis and
slicing passes, and **seventy-nine settings**. Three of the last six fixes had
been one of those heuristics undoing another. What remains of the dodge is
**1009 lines** across `dodge.lua`, `mover.lua` and `precast.lua`.

### What it does now
1. **Know where danger is, now and in the next second or two.** Exact geometry
   and exact timing for announced attacks; the footprint for physical ones; a
   short swept segment for anything moving, so the square in front of a shot is
   hot and the square behind it is not; a circle for every enemy; safe-spot
   markers inverted.
2. **Look at a few dozen points around the character**, twenty times a second.
   For each: what would hit you *on the way there*, sampled at three points
   along the line at the times you would be on them — and what would hit you
   *once you stopped*, at arrival and after `Stay clear for`. Cheapest first,
   and raycasts (floor, wall) are paid only until one passes.
3. **Put a box on the best one. Move the character straight at the box.** Do
   it again next frame.

There is no path. A path is what you need when you decide rarely and move
imprecisely. Deciding every frame and moving exactly, the straight line to the
current best point *is* the path, and the on-the-way check in step 2 is what
keeps that line off anything that lands while you are on it.

The box only ever sits on ground that will be clear when you get there and
stays clear once you have. When here is fine, the box comes home and the
character gets on with fighting.

### Kept unchanged
Ground-truth detection (structural `hitBox`/`precast` matching, the name
tables), the `precastHitbox` listener, `Workspace.dungeonName` map detection,
and the collision-checked, walking-pace **tween** mover from 3.6.2. Those are
the parts that were verified against the game rather than inferred.

### Settings
Fourteen, in one section, with a **Recommended settings** button beside them.
The saved `macroMode` value stays `"clone"` so existing configs load; the island
just says **Dodge**.

## 3.6.2 - 2026-09-02

### Why it stood still
Nothing was disabling **Roblox's default control module**. It calls
`Humanoid:Move(...)` every frame from player input — with no keys held, that is
`Move(Vector3.zero)` — on **RenderStepped, before physics**. Our call lands on
Heartbeat, *after*. So the control script's "stop" is what physics actually
acts on, and both `steer` and `velocity` were overruled every single frame.

`MoveTo` survived only because it is a separate, persistent mechanism the
control module does not clobber. That is the whole reason walking "worked" and
the two supposedly-better modes did not.

### Tween is the default
Writing the root's CFrame is the one path the Humanoid does not mediate, so the
control module cannot argue with it. It is also, as you said, simply what the
other script is doing.

Two things make it behave:

- **Capped to walking speed.** Each step is at most `WalkSpeed * frameDelta`, so
  the displacement a server sees is ordinary walking — there is no
  teleport-sized jump to notice.
- **Collision-checked.** Every step is raycast first and stopped short of
  whatever it hits, and if the character is flat against something the Humanoid
  takes over, because it knows how to slide along a wall and step over a lip.
  **Clipping through geometry is the one genuinely conspicuous thing about
  moving this way**, and it is now impossible rather than merely unlikely.

The Move-based modes take the player's controls while they run and hand them
straight back when they stop.

## 3.6.1 - 2026-09-02

### Fixing the regression 3.6.0 shipped
The new `velocity` mover wrote the horizontal velocity and then, on the very
next line, called:

```lua
humanoid:Move(Vector3.zero, false)
```

`Move(zero)` is an instruction to **brake**, and the Humanoid re-applies its own
idea of velocity every physics step. So the mover set a velocity and the
Humanoid immediately cancelled it, every frame. The two fought and the Humanoid
always wins — the character stood still in the middle of attacks.

Both must be told the **same direction**. Then they agree: the Humanoid handles
animation, footing and slopes, and the direct write removes the acceleration
ramp.

### The default is `steer` now
Plain `Humanoid:Move` with a direction. It still fixes the two things that made
MoveTo miss — no ~2 stud arrival tolerance and no internal re-planning — and it
**cannot stall**, because it is the Humanoid driving itself through its own API.
`velocity` remains available and is now correct; it is the faster-reacting
option, not the default one.

### A watchdog, so this cannot happen again
Any mode that is asked to move and produces no movement for a second falls back
to `walk` and says so in the log. A bug in a mover should never be able to
strand the character inside an attack, whatever else it does.

## 3.6.0 - 2026-09-02 - "Actuator"

### The dodging was never the problem
Every dodge in this script was issued as `Humanoid:MoveTo`. That is pathing-and-
walking built for getting somewhere *eventually*, and it:

- **accelerates from a standstill**, taking roughly a quarter of a second to
  reach WalkSpeed — in a fight where telegraphs land in 0.7s, a third of the
  budget is gone before the character is really moving;
- **arrives only within about two studs**, which in a three-stud gap between two
  beams means standing on the edge of one;
- **re-plans on every call**, so re-issuing it each frame restarts the
  acceleration;
- **slides along geometry**, so a wall turns a dodge into a scrape.

"Stands in the middle of attacks", "goes to the edge of an attack instead of
around it", "barely keeps its distance from walls" are all descriptions of an
**actuator** failing, not a chooser failing. The grid can pick the perfect cell
and MoveTo will still put you two studs off it, a quarter of a second late.

**Movement is now selectable:**

| mode | behaviour |
|---|---|
| `walk` | `Humanoid:MoveTo`. What it always did. |
| `steer` | `Humanoid:Move` each frame — no arrival tolerance, still accelerates. |
| **`velocity`** | **Writes horizontal assembly velocity directly. Instant direction changes, exact speed, physics still applies so walls and floors behave. Default.** |
| `tween` | Steps the root CFrame. Stud-exact and instantaneous, ignores collision — which is both why it is precise and why it is conspicuous. |

### Simple mode
The clone system has **sixty-eight settings**. Each was a fair response to a
specific failure, but together they interact in ways nobody can hold in their
head — enclosure fought cover, freshness fought hysteresis, the wall pass fought
the slicing. Three of the last six bug fixes were one heuristic undoing another.

**Simple mode** keeps exact geometry, exact timing and precise movement, and
turns off every heuristic that has been caught fighting another one. It also
disables slicing so the field is one consistent snapshot rather than a mosaic of
different ages.

That is roughly what a script doing this well in a few hundred lines actually
contains, and it is the configuration to judge the dodging by: when it fails,
there are few enough moving parts left to say why.

## 3.5.2 - 2026-09-02

### Shuffling on the spot with clear ground in sight
Three causes, and they compounded.

**1. Goal choice had no hysteresis.** `bestGoal` took the plain argmin every
time it re-picked. Two near-equal cells trade places as the field updates, and
the bot takes a step toward each in turn — which is the shuffle. A new goal must
now beat the held one by **`cloneGoalHysteresis`** before it can take over. The
held goal is still dropped instantly if it turns lethal.

**2. A full A\* ran every frame.** Sixty times a second, against a goal that
changes a few times a second. Even with the destination fixed, the route wobbled
as heat shifted and `MoveTo` was re-issued at a slightly different first step
each frame. The path is now **reused between plans** and rebuilt only when the
goal moves, the window slides, the next step goes lethal, or
`clonePathInterval` (0.12s) elapses. Reached cells are dropped off the front so
a reused path advances rather than steering back at the step behind.

**3. The field carries answers of different ages.** Since 3.2.0 only a slice of
the grid is re-measured per pass — so a stale cell that looks wonderful wins,
gets refreshed, turns out to be terrible, and some other stale cell wins
instead. That oscillation is pure measurement lag, nothing to do with the
danger. **Age is now a cost** in the goal score.

The third is the one I would not have found without the screenshot: it is a
direct consequence of the slicing added for performance, and it only shows up as
behaviour, never as a wrong number.

## 3.5.1 - 2026-09-02

Two bugs in the day-old cover code, both found by watching a clip of the
Midgardian Champion fight rather than by reading the code.

### The cover ray was cast from the wrong place
`TH.origin` picked the nearest enemy and then **overrode it** with the soonest
announced zone. A radial fan is a dozen separate zones, and a ray from the
middle of one beam to a cell says nothing about whether anything is shielding
you — the beams converge on the **boss**, and that is the only origin that
makes the question meaningful.

The nearest enemy now wins outright; an announced zone is a fallback for when
there is no enemy to blame.

### Enclosure was fighting cover
Pressing against the thing that is shielding you is the entire point of cover.
But the enclosure pass counts **any solid neighbour as heat**, so it was shoving
the bot back out from behind the pillar and into the open — which is exactly
where the beams are.

Covered cells are now largely exempt from the enclosure penalty. Two rules that
were each right on their own and cancelled each other out in the one situation
they both existed for.

## 3.5.0 - 2026-09-02 - "Space-time"

### Space-time A\*
Each cell now stores its heat at **three fixed moments**, and the search
interpolates for the time it would *actually* arrive having gone round whatever
was in the way. Arrival time is carried alongside cost through the search, which
makes the space genuinely `(x, z, t)` rather than `(x, z)`.

The rule that was not being enforced before: **if a telegraph goes live along
the route while you are still crossing, the route is discarded.** Sampling each
cell at its straight-line ETA said "that cell is fine" for a cell you would only
reach much later, by which time it was lethal.

The geometry per threat source is computed once and only the time weighting is
evaluated three times, so the third slice is nearly free.

### Cover
When a radial burst fills the arena there is **no open safe ground**, and
hunting for the least bad patch of it is the wrong question. The right one is
whether something solid is between you and where the attack is coming from —
and the arena pillars are exactly that. The grid used to see them only as
obstacles to route around.

One ray from the dominant threat origin to the cell, budgeted and cached by
world position. **Cover is a discount, not a bonus**: it removes a share of the
danger rather than inventing safety, so a covered spot standing in a pool of
fire is still a bad idea. Covered cells are tinted blue so hiding reads as a
decision rather than the bot wandering behind a pillar.

### Enveloped no longer means stopping
Three branches used to give up and stand still, and the worst was the quietest:
`bestGoal` can pick **the cell you are already standing in** — everything else
scored worse — so `#path == 0` and it held position *inside the attack*.

Every one of those now runs anyway:
1. The bearing the beyond-grid scan liked.
2. Directly away from whatever is throwing the most at us.
3. The coolest of the eight directions around us, judged fresh rather than from
   the cached field — because the field is what has just failed.

And the current cell is no longer offered as a destination while it is hot.
Nowhere better existing is not a reason to stay in an attack.

## 3.4.0 - 2026-09-02 - "Ground truth first"

### The capture found it
From a live Steampunk Sewers fight: **895 of 900 parts missed**, and among them:

```
- | hitBox  | Part | 8 studs | size 22 22 22  | tr 1.00 | anc hammerBotHit(Model)
- | precast | Part | 8 studs | size 1.3 22 22 | tr 0.80 | anc hammerBotHit(Model)
```

`hammerbothit` **is** in the name table. It was never reached, because
`isDamageBrick` had this above every name check:

```lua
if part.Transparency >= CFG.telegraphTransparencyCutoff then return false end  -- 0.99
```

**In this game the `hitBox` — the part that actually damages you — is created at
Transparency 1.** Fully invisible, by design. `GAME_NOTES.md` records exactly
that about `PrecastHitbox`, and I wrote it down and then left a rule that threw
those parts away first. Appearance scoring was overruling ground truth.

The five things it *did* detect were enemy hands 88 studs away.

### Detection is structural now, and runs first
A part is an attack if **its name or an ancestor model's name is a known
attack**, or if it is a **`hitBox`/`precast` inside any model without a
Humanoid** — whatever it looks like. Transparency and the CanCollide gate now
apply only to the appearance-scoring fallback underneath.

The second rule is the important one: every attack in this game is built the
same way — a Model containing a PrimaryPart, an invisible `hitBox` and a visible
`precast` — so it catches bosses nobody has dumped, without needing a name.

Ownership is still checked inside that block, since your own abilities are built
the same way. Verified against the capture: all three Chromatic Rain models are
in `OWN_EFFECTS` and stay ours.

### Own-attack learning could poison the whole game
`markOwnIfRecent` learns the *name* of anything appearing near you just after
you cast. A boss `precast` landing at your feet a moment after your ability
would teach the script that **"precast" is yours** — and every attack in the
game uses that name. Shared grammar names (`precast`, `hitBox`, `part`, `beam`,
`ball`, …) can no longer be learned as ours; the specific instance still can.

## 3.3.0 - 2026-09-02 - "Open ground"

### Attack capture — so misses stop being guesswork
A place file says what exists in `ReplicatedStorage`. It does **not** say what a
part is named, parented or shaped when it actually spawns during a fight, and
`Workspace.enemies` was empty in both dumps. I have now diagnosed missed attacks
by inference from a static snapshot twice and been wrong twice.

**Record what spawns** logs every part that appears near you — name, class,
size, transparency, collision, material, colour, velocity, full ancestry — along
with **what this script decided about it**. **Save capture** writes it beside
your config.

The misses are the whole point: a part judged harmless appears in no other log,
which is exactly the case that needs explaining. One fight recorded tells me
more than any number of dumps.

### Enclosure — stop backing into corners
A green pocket ringed by red is a **trap**: somewhere you can stand right now
with nowhere to go the moment it closes. Cells now inherit a share of the heat
around them, sampled both immediately and at **Escape range** (6 studs), so:

- An enclosed pocket reads hotter than open ground of equal local safety.
- **Walls count as heat**, so corners are included — the old "avoid wall edges"
  rule is now a special case of one general one rather than a separate rule.

The effect is that the bot strafes into the open rather than reversing into a
dead end that happens to be green.

Assigned from a stored base, never accumulated, and unmeasured neighbours are
skipped rather than counted as walls — both traps this sliced field has already
sprung once each.

### Adaptive lookahead
Taken from the standalone heatmap prototype, which scales its prediction window
inversely with the agent's speed. Every horizon here was a fixed constant
regardless of `WalkSpeed`, so a crawling character got the same warning time as
a sprinting one. Horizons now stretch as speed drops (square root, so halving
speed widens the window ~40% rather than doubling it).

## 3.2.6 - 2026-09-02

### The window is a circle
The corners of a square window are its **furthest** cells — 1.4 times the
radius — which made them simultaneously the least useful ground in the grid and
the most expensive to path to. They were a quarter of the total work.

| | reach | cells |
|---|---|---|
| square (was) | 21 studs | 841 |
| circle, same reach | 21 studs | 613 — **73% of the work** |
| circle, same budget | **24 studs** | 797 |

So it is either a quarter cheaper or three studs further-sighted, and further
sight is worth a great deal given how often being cornered came down to not
seeing past the grid.

The cell array stays square, because the indexing is arithmetic and a ragged
array would cost more than it saved. The corners are simply never active: never
measured, never drawn, never routed through. And because they are never
*measured*, they cannot be mistaken for walls by the edge-warming pass — the
same trap that produced the drifting yellow circles in 3.2.4.

## 3.2.5 - 2026-09-02

### Every boss attack in the game was missing
Bosses keep their attacks in a **subfolder of their own**:

```
enemyProjectiles.Steampunk.bossCannonBeam.hitBox
enemyProjectiles.Steampunk.bossCannonBeam.precast
```

The name table was built from **top-level children only**, and then dropped
Folders to avoid picking up gear — which threw away every per-boss folder, and
with it **111 attack models**. That is exactly why nothing on the Cyclops Siege
Bot registered.

Rebuilt recursively from both dumps: **519 names, up from 238**. Equipment is
still excluded, now at any depth.

Note `hitbox` and `precast` in the list. Every one of those boss models is built
the same way — a PrimaryPart, a `hitBox` and a `precast` — so those two names
alone catch attacks from bosses nobody has dumped yet.

### Cornered, and doing nothing about it
Two separate failures, which compounded into the behaviour you described.

- **The grid only sees about twenty studs.** Boxed in with attacks filling all
  of it, the genuinely clear ground is outside the window and `bestGoal` cannot
  consider it — so it picks the least bad cell it *can* see, which when you are
  cornered is the corner. When the whole window is hot it now samples **16
  bearings well beyond the grid** and heads for the coolest. Only the direction
  comes from out there; the A\* still does the local routing, because beyond the
  window it has no idea what the floor does.
- **The stuck detector is switched off while dodging** — holding position inside
  a telegraph's clearance is sometimes correct, so that suppression is right in
  general. But it meant **nothing at all** was watching for the character being
  wedged between a wall and an enemy, and it would push into the corner
  indefinitely. Clone mode has its own now: after `Unstick after` seconds
  without progress it hops, abandons the goal, and marks what it was pushing
  against impassable so the search stops choosing the same wall.

## 3.2.4 - 2026-09-02

### The drifting yellow circles
The wall-edge pass was treating **"not measured yet"** as **"wall"**:

```lua
if not other.standable then touching = true end
```

Since 3.2.0 only a *slice* of the grid is measured each pass, so after every
window shift most cells are simply unknown — and every freshly measured cell
sitting next to one was given edge heat of **21, which is 38% of lethal and
lands squarely in the yellow band**. The result was a ring of yellow following
the frontier of each pass across the grid, which is exactly the drifting circles
you were seeing.

Cells carry a `measured` flag now, and only a neighbour that has actually been
measured *and* found impassable counts as a wall.

This is the second bug the sliced evaluation has caused in three versions, both
in code that post-processes the field. The rule: **anything that reads
neighbouring cells must distinguish unknown from known-bad**, because at any
moment most of the grid is a pass or two out of date.

### Heights were measured from the wrong place
`rise` was compared against `rootY` — the HumanoidRootPart's **centre**, which
sits about three studs above the floor. So `Step height 2.5` actually described
a rise of five and a half studs, and the slider meant something quite different
from what it said.

It baselines against the floor the character is standing on now, found with one
downward ray per pass.

## 3.2.3 - 2026-09-02

### Attacking without the mouse
The basic attack was a synthetic click **at the cursor's current position** — so
it pressed whatever the cursor happened to be resting on, which was regularly
one of the buttons.

There is a proper way to do this. The weapon is a `Tool`, its `Activated` event
is handled on the server, and **`Tool:Activate()` raises that same event
straight from the client**. No cursor, nothing to press by accident, and no
fight with the player over where the mouse is pointing.

**Method** (in the new Attacking section):
- **Auto** — `Tool:Activate()` when a weapon is equipped, click if not. Default.
- **Tool only** — never touches the mouse under any circumstances.
- **Click only** — the old behaviour, kept for anything Activate does not drive.

Two more switches:
- **Allow auto-clicking** — off means the script never synthesises a click for
  anything. With Method on Auto or Tool it still attacks perfectly well.
- **Click at the cursor** — off by default now. Any click that does happen goes
  to the middle of the viewport instead, which is clear of the interface.

The detected attack remote is still deliberately not fired. Its argument
signature is unknown, and replaying it with guessed arguments either does
nothing or risks a malformed-remote kick — `Activate` gets the same result
through a supported path.

## 3.2.2 - 2026-09-02

### Walls are threats
The grid only ever asked **"is there a floor within reach"**, which says nothing
about whether you can actually get there. A wall has a floor. A ledge you would
have to jump onto has a floor. Both read as open ground, and the bot discovered
otherwise by walking into them.

- **Cells are probed upward** through the space the character would occupy.
  Anything solid standing there and the cell is out. `RespectCanCollide` keeps
  the cast from tripping over this game's decorative walk-through geometry,
  which is everywhere; where the engine is too old for that property the hit is
  checked by hand.
- **A rise above `Step height` (2.5) is reachable but charged**, scaled by how
  high it is. A jump mid-fight is a moment spent not dodging, so the search
  should only spend it when the alternative is worse — which is what heat, as
  opposed to a hard block, expresses.
- **Ground beside anything impassable is warmed** (`Avoid wall edges`).
  Otherwise the cheapest route hugs every wall, and a wall is exactly where you
  get cornered when an attack lands.

**Wall threat** (60), **Step height** and the edge warming are all adjustable,
and included in Recommended settings.

### A bug caught while writing it
The edge-warming pass runs over **every** cell, while only a *slice* is
re-evaluated each pass. Adding heat there would have piled up on the cells it
had not just measured, growing without bound until everything read lethal. The
pass assigns from a stored base value now instead of accumulating — the same
trap the sliced evaluation will set for anything else that post-processes the
field.

## 3.2.1 - 2026-09-02

### Projectile timing was wrong in both directions
The corridor was scored with the **ground-attack urgency ramp**, and a ramp is
the wrong shape for something moving:

| projectile | ramp (was) | window (now) |
|---|---|---|
| arrives in 2.0s | 12 — stroll in | 0 |
| arrives in 0.5s | 67 | 35 |
| arrives in 0.2s | 86 | **75** |
| passing now | 100 | **100** |
| **passed 0.5s ago** | **100 — flees** | **0** |

Two separate errors. A corridor a shot reached in two seconds read as nearly
cool, so the bot walked straight in. And the ground *behind* a projectile stayed
lethal — **it was fleeing the safest place on the map**.

A projectile is dangerous in a **window around the moment it passes**. The core
of that window is geometric: the projectile's own width plus yours, over its
speed. So one formula gives a 100 st/s shot a lethal window of a twentieth of a
second, and a 9-stud tornado ambling at 5 st/s a window of nearly two seconds
either side — because it genuinely takes that long to move its own width past a
point. Around the core sit **Projectile lead** (1.1s, generous — being early is
how you get hit) and **Projectile wake** (0.3s, short — gone is gone).

The "will I still be standing here" sample covers the rest: a shot arriving in
two seconds is cool on arrival and lethal at arrival-plus-dwell, so the bot will
cross the corridor but will not stop in it.

### Recommended settings
A button at the top of the Clone section that resets the whole thing to the
tuning arrived at across the dungeons tested so far. The values live in
`config.lua` beside the loader, so the defaults and the reset cannot drift
apart.

## 3.2.0 - 2026-09-02 - "Thrift"

Performance. Measured against a 900-cell grid (radius 22 at 1.5 spacing)
evaluating twelve times a second.

### The expensive mistakes
- **`getPlayerHitboxMetrics()` was inside the per-cell threat query.** It walks
  the character and does two Instance lookups. At 900 cells x 2 time samples
  that was **3,600 Instance lookups per evaluation**, twelve times a second,
  re-deriving numbers that had not changed since the last frame. Computed once
  per pass now, along with `GetServerTimeNow()`.
- **The two time samples walked every threat source twice.** Same zones, same
  volumes, same projectiles — only the time differed. `getThreatPair` does both
  in one walk, halving the dominant cost of the whole system.
- **A\* cleared four arrays of 900 entries on every call**, and A\* runs every
  frame while dodging: roughly a quarter of a million table writes per second
  doing nothing but zeroing. A **generation stamp** gives the same guarantee for
  free — an entry not stamped with the current generation is simply unset.
- **The open set was a linear scan.** It is a **binary heap over two parallel
  numeric arrays** now — no per-push table allocation, which is what a heap of
  `{k, f}` pairs would have cost.
- **Painting wrote all three properties on all 900 discs unconditionally.**
  Every one crosses into the engine. It writes only what changed: position only
  when the window slides, colour only when the band changes.
- **The goal was found by scanning all 900 cells every frame.** It is
  arithmetic from the world coordinates now.
- Squared-distance comparisons before taking any square root, and `math.*`
  hoisted to module locals — each call was two hash lookups.

### Sliced evaluation
The structural one, and the setting to reach for first if frames still suffer.
The grid no longer has to judge every cell inside a single frame: **Cells per
pass** (320) are re-tested each think and the rest keep their previous answer.
A cell's verdict can be a couple of passes old, which is a far better trade than
a hitch — and the cell you are actually standing in is re-queried every frame
by the main loop regardless.

### Small safe zones
Not a shape problem, as it turned out. **The safety probe was the drawn disc** —
your whole body including limbs — and a probe of radius r cannot see a pocket
narrower than 2r. That made it blind to precisely the small pockets that matter.

**Probe size** is now its own setting, independent of the disc: 0 uses your root
part, which is what the game actually damages against, and the margin dropped
from 0.75 to 0.4. Shrinking the probe is what finds narrow gaps; the disc stays
whatever size reads best on screen.

## 3.1.2 - 2026-09-02

### A delayed attack should be green until it nearly lands
It wasn't. The squared urgency ramp reached lethal **a full second before
impact**:

| time to impact | squared (was) | cubed (now) |
|---|---|---|
| 2.0s | 25 | 12 |
| 1.5s | 39 | 24 |
| 1.0s | **56 — lethal** | 42 |
| 0.7s | 68 | **56 — lethal** |
| 0.0s | 100 | 100 |

That difference matters more than it looks. Reaching lethal early turns every
marker into a **wall**, and when several attacks overlap and no square is ever
truly safe, walls everywhere means **no route at all** — which is exactly the
situation where the bot froze. A gradient always leaves somewhere to flow to.

**Ramp sharpness** is adjustable; 3 is the new default.

### Following the gradient
Two changes that make "keep moving to lower heat" the actual behaviour:

- **Goal choice now weights the heat where you *will* be** over the heat where
  you land (`Trust the future`, 0.65). A square that is cool on arrival and hot
  a moment later is a trap, not a destination — it was being scored the same as
  one that stays cool.
- **When nothing is safe, it stops committing.** Holding a destination for a
  third of a second is the wrong shape of decision when the field changes
  faster than that. Saturated, it re-picks every pass and flows downhill, so it
  is never in the hottest place for long.

### The ramp is readable now
Nine bands — dark green, deep green, green, yellow-green, light yellow, dark
yellow, orange, red, deep red — built from the three colours in the panel so
the pickers still mean something. **Quantised into discrete steps** rather than
blended: across several hundred discs a continuous ramp turns to mush, and the
edge between cooler and hotter ground is the thing you actually need to see.

## 3.1.1 - 2026-09-02

### A projectile is a line, not a place
A moving hazard heated only the square it currently occupied, so the ground
**in front of an oncoming shot read as perfectly cool** and the bot walked into
it. It now heats the whole corridor it is about to sweep:

- The point is projected onto the line of travel. Behind the projectile is the
  one safe place to be, and is left cool.
- Heat is weighted by **whether it arrives there about when you would** — the
  same urgency curve as an announced attack, so a corridor a shot reaches in
  three seconds is warm and one it reaches as you get there is lethal.
- **Slow drifters count.** `threatSweepMinSpeed` is 3 studs/sec against the
  sidestep reflex's 12: a tornado ambling across the floor still owns the
  ground in front of it, even though it is far too slow to be worth
  sidestepping.

### It could not walk away from things
The bigger one. Entering evasion at all was still decided by the **old binary
test**:

```lua
local inHazard = CFG.dodgeEnabled and not isPositionSafeFromDamageBricks(...)
```

So a square at heat 40 — visibly orange, halfway to lethal — was called "safe",
the bot skipped the dodge branch entirely, and went off to pursue an enemy
straight through it. **The heat field was being computed and then ignored for
the one decision that actually matters.**

In Clone mode the gate is now the field itself: any heat at or above **Move at
heat** (6 of 100, deliberately low) means relocate. Legacy keeps the binary
test, which is the right model for how Legacy dodges.

## 3.1.0 - 2026-09-02 - "Heat"

Safety stops being a yes or no. It is now **heat**: a number from 0 to 100, at
a point *and at a moment*.

The screenshot that prompted this is the argument for it — a fan of radial
beams where every square is unsafe. A boolean leaves the search nothing to
choose between, so the character stands still and dies. A scalar field always
has a least-bad answer, and the thin cool wedges between the beams fall out of
it for free.

### ThreatManager (`src/threat.lua`)
`getThreatAt(position, atTime)` combines every source into one number, additive
where they overlap:

- **Announced ground attacks** — exact circle or oriented-box geometry from the
  game's own broadcast, scaled by an **urgency curve**. Squared, so a marker
  firing in four seconds is barely warm and one firing now is lethal. That ramp
  is what produces the gradient rather than a wall.
- **Live hazards** — full weight; there is nothing to wait for.
- **Enemies** — constant in time, because melee never telegraphs and never
  expires.
- **Safe-spot markers** — inverted: outside the circle is the danger.
- A **warm shoulder** outside every edge, so the middle of a gap beats its lip.

The box test rotates the *world point* into the box's frame, which turns an
oriented-box problem back into two 1-D comparisons — exact and cheaper than
rotating the box.

### A\* across the field
```
F = G + H + (threat * threatWeight)
```
G is distance travelled, H is octile distance remaining, and the threat term is
what buys a longer cool route over a short hot one. **Caution** is literally
"how many studs of detour is one point of heat worth" — the survival-versus-
speed dial in one number, defaulted high since you chose survival first.

Cells at or above **Lethal at** are impassable. If that leaves no route at all,
the search re-runs with them merely expensive: being cornered is not a reason
to stand still and take it.

Scratch buffers are reused across searches and the open set is a linear scan —
a heap of tables would allocate more per push than the scan costs on a window
of a few hundred cells.

### Projectile steering
A per-frame reflex under the grid, for what is already in the air. Closest
approach is solved analytically, then the dodge is the component of the offset
**perpendicular** to the line of travel — the shortest way out of the path,
where backing off along it would just be outrun.

### Seeing it
Discs are drawn green through amber to red by heat, with two gradient stops so
the middle reads as amber rather than a muddy blend.

## 3.0.5 - 2026-09-02

### Attacks made of hundreds of meshes no longer melt the frame
One attack in this game can be several hundred MeshParts. Tested one by one
that is *cells x parts* distance computations per evaluation — a 17x17 grid
against 300 parts is **86,000** — and drawn one by one it is **300
BillboardGuis**, which is what actually freezes the picture.

- **Dense clusters collapse to a box.** A model with `hazardClusterMin` parts or
  more (6) becomes the single bounding volume it effectively is. Nobody threads
  between the meshes of a lava pool, so the per-part precision was buying
  nothing and costing everything.
- **Sparse groups and loose parts are left alone**, because there the gaps
  between parts are real and worth keeping.
- **Overlays are capped** to the nearest `maxHazardOverlays` (28). The far ones
  are not what is about to hit you, and the same pass cleans up anything that
  drops off the list.

### It walked into melee anyway
The grid drew a circle around every enemy and called it unsafe — and then the
chase walked straight through it, because `getStandOffPosition` used
`CFG.safeDistance` (8) and knew nothing about the grid. The dodge kept its
distance and the pursuit immediately gave it back, which on a high tier is one
tap.

- **Keep distance while chasing** (on by default): the chase stops at the same
  `Enemy space` circle the grid draws.
- **Attack reach scales with it**, so the bot does not close the gap purely so
  it can swing.

## 3.0.4 - 2026-09-02

### One line was hiding most of the attacks
`isDamageBrick` had this, near the top of its heuristics:

```lua
if not parent or parent == Workspace then return false end
```

The theory was that a real attack lives inside a model, and a part loose in
Workspace is scenery. **This game does the exact opposite.** `PrecastHitbox`
does `Part.Parent = workspace` literally, and the boss beams do the same — so
that single line was vetoing precisely the things most worth seeing, which is
why whole attacks read as clear green floor.

Loose parts now fall through to the appearance test, which is what the rule was
a crude approximation of anyway.

### It was dodging its own ability
`Workspace.vfxPool` holds the player's own pooled hit effects — `Ability Attack
Hit`, `Melee Attack V1`..`V3`. Their parts carry generic names like `Part`, so
neither the name tables nor the own-effect timing caught them, and the bot fled
from its own ability the moment it landed (the parts labelled `Part >> 155 st/s`
at odd heights). Anything under that pool is ours.

### Defaults
Retuned now that the footprint is measured from the body rather than including
cosmetics, so these are honest numbers rather than compensation:

| setting | was | now |
|---|---|---|
| Disc size | 1.0 (needed halving) | **1.0**, and correct |
| Safety margin | 0.5 | **0.75** |
| Depth bonus | 1.0 | **1.5** — prefer open ground |
| Enemy space / spacing | 11 / 18 | **12 / 20** |
| Must stay safe for | 1.6 | 1.6 |
| Spacing / cells | 1.5 / 900 | 1.5 / 900 |

## 3.0.3 - 2026-09-02

### Enemies get a circle of their own
Melee enemies do not telegraph anything — being next to one **is** the attack,
and the grid had no concept of that at all. It saw clear floor and walked the
character into stabbing range.

- **Enemy space** (11 studs): cells this close to a live enemy are unsafe.
- **Enemy spacing** (18 studs): beyond the hard circle, standing near an enemy
  is allowed but expensive. The bot will pass through to reach somewhere
  better; it will not choose to stop there.

### Two fixes for "walks a few steps, then stops and dies"
Both were real, and they compounded.

- **The committed goal was a window index.** The window is centred on the
  character and slides as it walks, so index `k` means a *different world cell*
  a moment later. Every time you crossed a cell boundary the committed goal
  silently moved — which is exactly the observed behaviour: it sets off, takes
  a few steps, and then believes it has arrived somewhere it was never going.
  The goal is held as a **world key** now.
- **A cell was judged only at the instant of arrival.** So a spot where an
  already-announced attack lands a moment later read as perfectly green. The
  bot walked there, stopped, and was killed by something the script already
  knew about. A cell now has to **stay safe for `Must stay safe for` seconds
  (1.6 by default)** to count as a destination.
  - There is a fallback to merely-safe-on-arrival, because a moment when
    everything has something inbound must not return *nothing* — standing still
    is the worst available answer.
  - Cells that are safe now but do not hold are drawn dim, so "passable but not
    somewhere to stop" is visible rather than mysterious.

## 3.0.2 - 2026-09-02

### The grid was padding every attack far too heavily
`isPositionSafeFromDamageBricks` added **`CFG.damageBrickClearance` (3.5 studs)
on top of your body** to every hazard. That constant was tuned for the Legacy
escape, which commits to a single dash — a fat hedge is cheap insurance there.
On a dense grid hunting for real pockets it is wrong, and it **stacks**: three
overlapping attacks and there is nowhere green left to stand at all.

- The test now takes an **exact clearance**, and the grid passes its own disc
  radius plus **Safety margin** and nothing else. Red means *your body would be
  in this*.
- Legacy still gets the old hedge; it is the right trade for a one-shot dash.
- **Safety margin is now the only padding there is.** Every stud of it is taken
  off the walkable space between two attacks, which is the honest way to
  present that dial.

### The footprint is measured properly, and keeps being measured
- It was `character:GetExtentsSize()`, which **includes accessories and the
  held weapon** — a big cosmetic sword or a pair of wings convinced the bot it
  needed several extra studs to fit through a gap.
- Now only the BaseParts directly under the character count (limbs and torso;
  an Accessory keeps its Handle a level down), measured in the root's own frame
  so turning does not change it, and clamped by `cloneMaxFootprint`.
- **It was sampled once at build**, so the only thing that ever corrected it was
  dying. It is re-measured on a timer and carried in the grid signature, so
  equipping something — or the character finishing loading after the script
  started — resizes the discs on its own.

### Flicker
A window shift blanked every cell's verdict and repainted before the next
evaluation could fill them in. At 1.5-stud spacing you cross a cell boundary
roughly every 0.075s while running, against an 0.08s evaluation interval — so
it blanked on very nearly every frame you moved. Verdicts are now cached by
world position and carried across the shift (the cell is in the same place it
was; the answer from a moment ago beats nothing), and a shift forces an
immediate re-evaluation for the cells that are genuinely new.

## 3.0.1 - 2026-09-02
Three fixes to 3.0.0, all found from a single in-game log.

- **`RT.connections` never existed.** `watchDungeonName` threw on
  `table.insert` into it, so the map was detected once at startup but never
  followed after - and because the throw aborted the startup sequence,
  `watchOwnAbilityRemotes` below it **never ran at all**. Both now use
  `RT.indexConnections`, which is the table that actually exists and gets torn
  down properly.
- **The precast readout was built once and never refreshed**, so it said zero
  however many attacks had gone past. `precastStep` now refreshes it whenever
  the counts change.
- **The payload handler dropped anything it could not read, silently.** That
  made "listening" and "nothing is arriving" look identical from the outside.
  It now counts every payload received, prints the first three key by key, and
  finds the shape name by value if the compressed key is not the one we asked
  BridgeNet2 for. The panel reports understood-of-received, because those are
  different failures needing different fixes.

## 3.0.0 - 2026-09-02 - "Ground truth"

The script stops guessing what an attack is and listens to the game tell it.
Everything here comes from reading the place file; see `game/GAME_NOTES.md`.

### It listens now
- `ReplicatedStorage.modules.PrecastHitbox` broadcasts **every ground attack**
  on a BridgeNet2 bridge, carrying the shape (Cube or Circle), the exact
  geometry, `startTime`, and **`delayUntilAttack`**. We require the same module
  the game does and connect to the same bridge.
- **Time to impact is arithmetic**, not something learned from being hit:
  `delayUntilAttack - (GetServerTimeNow() - startTime)`.
- This matters more than it sounds. The part the game builds starts at
  `Transparency = 1` — **fully invisible** — with `CanQuery` false, parented
  straight to `workspace`, and only fades in over 0.15 s. It is close to the
  worst case for an appearance scorer and trivial for a listener.
- Announced attacks are drawn in our own colours, warming from yellow to red as
  impact approaches.
- If the bridge is ever missing the listener says so and the appearance scorer
  carries on underneath.

### Cells are judged at the time you would arrive
`isPositionSafeFromDamageBricks` takes an `atTime`, and the clone grid passes
each cell's walking distance over WalkSpeed. So the bot can **cross a marker
that fires in a second and a half** to reach real safety, instead of treating
every marker as a wall and being cornered by the third one.

### It knows whose attack it is
- **238 enemy attack names** from `ReplicatedStorage.enemyProjectiles` and
  **293 of ours** from `.projectiles` / `.abilities`, as lookup tables. That is
  precisely the mine-or-theirs question the scorer used to guess at, and it is
  now answered before any heuristic runs.
- Gear and mob templates are deliberately excluded: an Accessory named
  `bossRifle` is a weapon an enemy is holding, and fleeing from it would mean
  fleeing from every enemy in the room.

### Safe-spot bosses
Some bosses mark the one circle you **must stand in** — `safeSpotCircle`,
`thirdBossSafeSpots`, `cyanSafeZoneMarker` and friends. These are attractors
now, not hazards. Before this, dodging was **actively worse than no dodging**
on those fights: the grid saw uniform safety and calmly walked you out of the
only survivable place on the floor.

### Smaller things it can now just read
- **The map follows `Workspace.dungeonName`**, so waypoints, macros, the attack
  book and the drawn zones all switch themselves on entering a dungeon.
- **Enemies are scanned from `Workspace.enemies`** rather than all of Workspace.
- **Our own casts come from the `abilityCast` / `abilityUsed` remotes** — exact,
  fired before the effect spawns, and impossible to confuse with an enemy
  playing a similar animation.

### Removed
All three existed to work around not knowing what an attack was:
- **Freeze.** Its whole purpose was holding a copy of a telegraph that lasts
  half a second so you could point at it. Those arrive as data now, before they
  are visible.
- **Trial runs / damage correlation.** The plan was to learn `hitDelay` from
  being hit. The number is transmitted.
- **The recommendation queue.** Built to correct the scorer; the scorer now has
  ground truth for the things it used to get wrong.

Manual picking and hand-drawn zones stay, for anything the broadcast does not
cover.

## 2.15.1 - 2026-09-02
- **Clone discs are sized from your real footprint.** They were sized from the
  HumanoidRootPart, which is two studs wide; the body with its limbs is wider.
  Now `GetExtentsSize` on the character, with a **Disc size** scale to match by
  eye.
- The safety test is given the same radius, so a green disc still means the
  whole footprint fits. Without that the discs would have grown and the promise
  would not have.

## 2.15.0 - 2026-09-02 - "Grid"

### Clone mode: a grid, and a search across it
The ring is gone. Clone mode now keeps a **grid anchored to the world**, and
dodges by **searching across it** rather than dashing to a point.

- **Dense.** Discs the size of your hitbox every 1.5 studs, overlapping, so a
  safe pocket a few studs wide between two boss attacks still shows up. Green
  means your whole body fits there untouched: the test uses the hitbox radius
  plus **Safety margin**, not the centre point. Raise the margin if you are
  being grazed.
- **World-anchored.** A cell has an identity, so its floor height is raycast
  once and cached, and its verdict stays valid while you walk toward it. The
  ring slid under you and was re-derived every frame.
- **Pathfinding.** Dijkstra from your cell across the window. A red cell costs
  **Danger cost** green ones to cross, so it is crossed only when there is no
  way around - and there often is not, when you are standing inside the
  attack. Pits and walls are never crossed. Diagonals require both orthogonal
  neighbours clear, so the corner of a red cell is never clipped on the way
  past. The old ring checked the straight line for walls only and would run
  through a red strip to a green node behind it.
- **Depth.** A wave from every red cell outward tells each green one how far it
  is from trouble, and **Depth bonus** lets the chooser prefer the interior of
  a safe region to a single green cell about to close. Edge cells draw dimmer.
- **Walls are learned by trying.** A blocked first step marks that cell
  impassable until its next refresh and the next search routes around it.
- **Drawn.** The path is a blue trail across the discs and the goal is solid
  blue, so when it runs somewhere you can see why.
- The cell budget caps the cost (900 by default, about 22 studs of reach at 1.5
  spacing). **Tall prisms** are off by default at that density.

### Also
- **The menu key is rebindable**, at the top of Modules. Click, press a key,
  Escape cancels. Only a name `Enum.KeyCode` actually has is accepted on load,
  so a typo in the config cannot lock the interface behind a key that does not
  exist.
- **Fixed: a pinned window stopped the menu key from reopening the interface.**
  The handler toggled on "is Autofarm visible", which was true while pinned and
  closed, so the key only ever closed. It toggles the interface state now.

## 2.14.0 - 2026-09-02 - "Second opinion"

### Recommendations
The scorer already has an opinion about every part on screen. Freeze-and-pick
made you find the right one with the mouse in a field of held copies; this
**puts the opinion forward instead** and you answer from a list.

- **One candidate at a time**, nearest first, at a rate you set (**Rate**,
  recommendations per second). Never one already in the book, already answered,
  or already in the list.
- Each is **held in the world in its own colour with a number on it** - a neon
  copy with a highlight and a label - and listed in the Attacks panel with the
  same colour down its left edge. "The cyan one" means the same thing in both
  places.
- **Tick**: it is an attack. A book entry is written from the signature
  captured when it was put forward, **so it works after the part is long
  gone**. Inside a creature model it is added OFF, like a learned swing hitbox.
- **Cross**: it only looks like one. **Remembered per map**, and vetoed in
  `isDamageBrick`, so the bot stops dodging it as well as stops asking.
- **Entries outlive their part on purpose.** An attack is on screen for a
  fraction of a second, and that was the whole reason freeze existed. They
  expire a while after the part is gone (`recommendTTL`), or when you answer.
- **List size** caps how many wait at once; nothing new arrives until you
  answer something or one expires. **Clear list** drops them all without
  learning or rejecting anything.
- Freeze, Select attack and Draw zone remain underneath as the manual route.

### Also
- List entries can carry a colour bar; tick and cross icons join the kit.

## 2.13.0 - 2026-09-02 - "Floor"

### Testing switches
- **Pathfinding** and **Dodging**, at the top of Navigation. Off stops the bot
  driving your character with what it finds - it still finds it. With
  pathfinding off it still picks a target and still swings if one is in reach;
  recovery goes quiet with it, since recovery is pathfinding's own last resort.
- Dodging **moved here from Telegraphs** so one setting has one control.
- **Both are saved now.** Dodging never was.

### Clone ring geometry
Widening the radius opened a hole around the character. Two defects
compounding:
- The innermost ring sat at **55% of the radius**, so at 30 studs the nearest
  volume was 16 studs away - and the hole grew with every widening, in the one
  place you most need somewhere to step. Now the first ring sits at a fixed
  **Inner radius** (4 studs) regardless.
- Every ring got **the same number of volumes**, so the outer ring's were
  nearly twice as far apart as the inner ring's - gaps wide enough to be hit in.
  Volumes are now shared out **by circumference**.
- **Auto rings** (on by default) adds rings as the radius grows so the gap
  between them stays about **Ring spacing** (6 studs). The Rings slider is the
  floor, not the answer. Both are settings; turn Auto rings off to get the
  slider back as the literal count.
- The volume cap still wins: the per-ring minimum of three can push the total
  over it on many rings, and the cap is the promise.

## 2.12.0 - 2026-09-02 - "Pinned"
- **A pin on every window header**, beside the info circle. Grey when it is not
  pinned, accent when it is - a thumbtack drawn from two frames, like every
  other glyph in the kit.
- **A pinned window stays on screen after RightShift closes the rest**, and is
  still draggable. Click the pin again and it goes back to hiding with
  everything else - if the interface is closed at the time, it disappears
  immediately.
- **Pins are remembered between sessions**, so a readout you always want is set
  up once.
- A pinned window still respects its switch in **Modules**: turning a module off
  means off, pinned or not.
- **The blur and the dim stay tied to the interface**, not to any pinned window.
  Dimming the whole game because one small panel is pinned would be absurd.
- Visibility is now decided in one place (`applyVisibility`) from two inputs -
  is the interface open, and is this window pinned - rather than each caller
  setting `.Visible` on six frames and hoping they agree.

## 2.11.0 - 2026-09-02 - "Fieldwork"

### The Attacks panel
Everything about one dungeon's attacks, in one place: **the map**, **Freeze**,
**Select attack**, **Draw zone**, this map's **Attack Book**, and the zones
drawn on it.

- **Freeze** holds a still copy of every attack that appears. A telegraph is on
  screen for a fraction of a second, which is not long enough to point at one.
- **Select attack** puts what you clicked into the book. Clicking a frozen copy
  records the original's identity, not the copy's.
- **Draw zone** is for the case no amount of appearance scoring can solve: an
  attack announced by something that is not the damage - a rune on the floor, a
  glow, a decal. Press on the decoration, **drag outwards to size a circle or a
  square around it**, release. From then on **every copy of that decoration
  carries a hazard volume**, and the dodge treats it like any other.
  The volumes are real Parts rather than a parallel list, because everything
  downstream - the safety test, the penalty field, the clone ring - already
  understands Parts.

### Per-map, and saved
- **The Attack Book and the zones are stored per map now**, with the waypoints,
  macros and keep lists. What hurts you in Ghastly Harbor is not what hurts you
  in the Underworld, and one book shared across all fourteen is a book mostly
  full of entries that never match. They persist between executions.
- A pre-2.11 global book is **adopted into whichever map the config names**
  rather than dropped.

### Clone
- **Manual mode**: the ring dodges for you and nothing else runs - no target
  hunting, no pursuit, no waypoints. You drive, it pulls you out of attacks.
- **Rings cap at 10, volumes at 100.**

### Interface
- **Opening the interface blurs and darkens the game behind it.** The blur is a
  Lighting effect, so it only touches the 3D view and never the GUI on top of
  it; the dim is a sheet behind the windows. Both adjustable, both zero to
  disable, and the blur is removed from Lighting on Destruct so it cannot be
  left on your screen after the script is gone.
- **List entries are laid out explicitly.** They were a horizontal list holding
  a frame holding a vertical list, and nested auto-layout has now mangled three
  separate things in this GUI. Two labels and a row of icons do not need a
  layout engine to place them.

## 2.10.0 - 2026-09-02 - "Profiles"
Two new panels.

### Configs
- **Save the whole setup under a name, as many as you like.** Type a name,
  press the tick, and every current setting is snapshotted. Click a row to load
  it back, the pencil renames, the bin deletes, and each row shows when it was
  saved.
- Loading is the row itself rather than a third icon, because it is the thing
  you do most and the design has two icons.
- Saving under a name that already exists **overwrites** it, which is what you
  want when you are tuning one setup rather than accumulating near-duplicates.
- They live in their own `DungeonAutofarm_configs.json`, so the working config
  stays one small readable file.
- To make this possible `loadConfig` was split: `applyConfigData(data)` does the
  applying, and `loadConfig` is now just the file read in front of it. A stored
  profile goes through the same path a file load does.

### Modules
- **Turns each panel on and off.** Autofarm, Routes & Data, User, Configs and
  the HUD. A panel switched off stays off when you next open the interface.
- **A square toggle**, deliberately a different shape from the pill used for
  settings: a pill reads as a setting, and these are not settings - they decide
  whether a thing is on screen at all. On takes the accent gradient, off greys
  out.
- **The Modules panel is not in its own list.** Hiding the thing that unhides
  everything else is a door that locks behind you.

### Also
- **Window positions are clamped into the viewport.** The defaults are laid out
  for a wide screen; on a small one a window could previously open past the edge
  where there was no titlebar left to drag it back by.

## 2.9.0 - 2026-09-02 - "Clone"
Clone evasion: a third mode beside Legacy and Macro.

### What it is
- A ring of **player-sized volumes** follows the character - a tall prism the
  size of your own hitbox, with a **flat pad beneath it that is green when
  nothing would be hitting you there and red when something would**. The bot
  dodges by stepping into the best green one.
- Legacy and Clone are the same bot and differ only in how they dodge: Legacy
  searches for an escape point each time something lands near you, Clone reads
  a field of standing answers. Macro still replaces both with a recording. The
  island at the top of the Autofarm window picks between all three, and only
  the sections belonging to the current mode are shown.

### Why a fixed ring rather than a search
- The candidates are **fixed relative to the character**, so the answer is
  stable frame to frame instead of being re-derived under pressure - and it is
  **on screen**, so a dodge that goes wrong can be watched rather than
  reconstructed from a log afterwards.
- **Projectiles come free.** Safety goes through
  `isPositionSafeFromDamageBricks`, which measures against `hazardClosestPoint`,
  which already sweeps a moving hazard along the strip it will cross over the
  next `CFG.projectileLookahead` seconds. So a volume standing in the line of an
  incoming projectile is red *before* the projectile gets there. That is the
  whole reason to test positions rather than test contact.

### Details
- **Two interleaved rings** by default (24 volumes): a near option and a far
  one, offset by half a step so there are no spokes with gaps between them.
- A volume is also red if there is no floor under it, or the floor is more than
  `CFG.cloneMaxDrop` below / `CFG.cloneMaxClimb` above you - a spot you cannot
  stand on is not a dodge.
- The chosen volume is **held for `CFG.cloneCommitTime`**, so the character does
  not stutter between two equally good options under a moving hazard. Ranking is
  hazard penalty first, distance as the tie-break, because a shorter dash is a
  dash you finish. Only the best five get a reachability raycast.
- Positions update every frame (a CFrame write); safety is re-tested on its own
  `CFG.cloneEvalInterval` clock, because that is what costs raycasts. The pool
  is built once and reused - no per-frame Instance churn.
- The ring is **rebuilt when the count, rings or radius change and on respawn**
  (it is sized from your character's own hitbox), and **torn down on a mode
  switch or Destruct**.
- If every volume is red the log says so and names the likely cause: the attack
  is wider than the ring. Widen **Radius**.
- Settings: volumes, rings, radius, safety margin, commit time, show the ring,
  and both colours. All saved.

## 2.8.0 - 2026-09-02 - "Account"
- **Account panel**, built from Window E of the kit: your Roblox headshot
  (`GetUserThumbnailAsync`, fetched off-thread since it yields), your in-game
  name, a rank, and **Logout** / **Detach**. It is a third window and opens and
  closes with the other two on **RightShift**.
- **It masks under Streamer Mode.** A panel showing your username and your face
  would put both straight back on screen the moment you opened the GUI on
  stream, which would defeat the one thing Streamer Mode is for. It follows the
  same masking as the HUD, avatar included, and updates the instant the mode is
  toggled rather than on the next refresh.
- **Rank is `CFG.accountRank`**, a plain string, currently `DEVELOPER`. There is
  no account system behind it yet, so **Logout closes the interface** rather
  than pretending to sign anything out - its tooltip says exactly that.
  **Detach** unloads the script completely.
- Danger buttons take dark text rather than white, matching the design.
  `#ff6060` is light enough that dark type has more contrast on it anyway.

## 2.7.4 - 2026-09-02
Macro rotation. It *was* being recorded - it just never survived to the screen.

- **The main loop threw the facing away every frame.** During playback the
  facing block fell through to `releaseFacing(humanoid)`, which switches the
  AlignOrientation rig off and hands rotation back to the Humanoid. So
  `runMacroPlayback` applied the recorded direction and the same tick undid it a
  microsecond later. That is why it looked like rotation was not being recorded
  at all. Playback now owns facing outright.
- **The direction was reconstructed with the wrong sign.** Roblox's look vector
  for yaw *t* is `(-sin t, 0, -cos t)`; 2.7.0 used `(sin t, 0, cos t)`, which
  points a clean 180 degrees the other way. Facing is now stored as a **look
  vector** rather than an angle, so there is no sign convention left to get
  wrong on the way back out.
- **Pitch is recorded**, as asked - both the torso's and the camera's. Only yaw
  is applied to the body: a humanoid keeps its torso upright, so torso pitch is
  ~0 no matter where you point the mouse, and the pitch you actually aim with
  lives on the camera. Both are in the file for anything that wants them.
- Macros recorded by 2.7.0-2.7.3 still play: the old bare-yaw `r` field is read
  through the same path, now with the signs the right way round.

## 2.7.3 - 2026-09-01
The actual fix for the blank labels, and a HUD that stays in one piece.

- **Row labels were being pushed out of the window, not collapsed.** 2.7.1
  blamed `UIFlexItem` and was wrong. The real cause: `hoverable()` parented a
  full-width invisible `TextButton` into the row to catch clicks - and a row has
  a **horizontal `UIListLayout`**, which lays out *every* GuiObject child. The
  hit button was `Size (1,1)` scale at `LayoutOrder 0`, so it sorted first, took
  the entire row width, and shoved the label and the control past the right-hand
  edge where the window clipped them.
  The tell was there in the screenshot: captions, buttons, list entries and
  window titles all rendered. Every one of those reaches the screen without
  going through `row()`. A clickable row now raises `InputBegan` on itself
  (`Active = true`), so nothing extra joins the layout.
- **The HUD came apart in game** - footer at the bottom, stat values drawn at
  the top-left corner of the screen. It was a bottom-anchored frame with
  `AutomaticSize.Y` containing auto-sizing children inside a `UIListLayout`,
  which never resolved to a stable size. Rebuilt with the design's explicit
  geometry: 360x173, chip at y=0, stats at y=42, footer at y=145. No
  `AutomaticSize`, no layout, nothing that can fail to converge.

## 2.7.2 - 2026-09-01
- `flexFill` no longer reads `instance.Size` back in order to rebuild it. Every
  caller wants full height, so the height is a parameter with a sensible
  default. One less thing to get wrong, and it stops the smoke runner tripping
  over its own `Size` stub (which returns a Vector3, so `.Y` was a number).
- **Tooling: `build.py` runs the smoke test itself and fails on it.**
  `smoke.py` always did exit non-zero; the 2.7.1 push slipped through because
  the command piped it to `grep`, so the chain took *grep's* exit status and
  grep had happily matched the word "ERROR". Folding smoke into `build.py`
  removes the opportunity to invoke it wrongly.

## 2.7.1 - 2026-09-01
Fixes for the 2.7.0 interface, all three found from in-game screenshots.

- **Every row label rendered blank.** `flexFill` added a `UIFlexItem` in Fill
  mode to the label, but the label's base width was already 100%. Flex *grows*
  an item from its base size, so the pass had negative slack to distribute and
  collapsed the labels to nothing. The buttons were unaffected because their
  base width was 0 - which is exactly the tell: TextButtons and list entries
  showed their text, every `label()` inside a `row()` did not.
  Flex is gone. Widths are explicit arithmetic against the `reserve` each call
  site already passed. A wrong `reserve` now gives a label that is slightly the
  wrong width rather than an invisible one, which is the failure mode worth
  having in code that cannot be tested outside the game.
- **The HUD title chip collapsed to a bare accent line.** The chip and its five
  labels were all `AutomaticSize.X` inside a `ClipsDescendants` frame - nested
  automatic sizing that never resolved. Fixed widths now, totalling the design's
  326px chip.
- **The HUD Status row read "Movement: Movement: ...".** `setMovementState`
  prefixed the text, and it now writes into a row that is already labelled
  Status. The prefix is gone.
- The HUD frame sizes to its contents, so a taller stats panel can no longer
  push the footer off the bottom of the screen. Third stat row relabelled World
  (it carries enemies / telegraphs / playtime).

## 2.7.0 - 2026-09-01 - "Kitbuilt"
The interface, rebuilt from the Figma kit, plus the macro follow-ups.

### The GUI
- **Built from a component kit** (`src/uikit.lua`) ported from the Figma file:
  the tokens, type styles, spacing and radii all come from that document, so
  the two stay comparable. Three rules carried over from the design notes:
  **no image assets** (the chevrons, tick, pencil and bin are built from
  Frames, so nothing can fail to load); **the accent gradient is defined once**
  and everything reads it from there; and panel elevation is stacked Frames
  behind the panel, because Roblox has no box-shadow and the kit takes no
  assets.
- **Two windows, both accordions**: *Autofarm* (Combat, Abilities, Navigation,
  Telegraphs, Attack Book, Overlays, Performance, Debug & config) and *Routes &
  Data* (Map, Waypoints, Macros, Streamer, Live telegraphs). Sections are
  collapsed until you open them. Bodies scroll and window height is clamped to
  the actual viewport, so a full accordion still fits on a 768p laptop.
- **The HUD is the only thing on screen with the GUI closed**, bottom-left with
  a margin: title chip, status / target / world stats, and the status chip -
  which exists because the status used to sit raw on the game world where red
  went unreadable. **RightShift** opens and closes the windows.
- **Hover any control for a second** and a small grey box follows your cursor
  with an explanation of what it does. Every toggle, slider, dropdown, colour
  row and button has one.
- **The Legacy / Macro island** sits at the top. Legacy is the pathfinding and
  dodging bot; Macro replays your recordings. They are alternatives, so the
  sections belonging to the one you are not using are hidden rather than left
  on screen to scroll past.

### Everything is configurable now
- **Every overlay has a switch and a colour**: waypoints, pursuit route, escape
  route, telegraph highlight, invisible walls, hitbox, ability radius, macro
  route, plus a GUI accent colour and a HUD switch.
- **Targeting modes**: closest (as before), lowest HP, highest HP. The HP modes
  only consider enemies within `CFG.targetHpRange`, so a wounded straggler on
  the far side of the dungeon does not drag the bot across the map.
- **Dodging has a master switch**, and **Reset defaults** puts every slider,
  toggle and colour back to how it shipped without touching your paths, macros
  or Attack Book.

### Macros
- **Fixed: the record keybind stopped working after the first recording.**
  `startRecording` called `disconnectMacroInputs()`, which cleared the same
  table the global bind listener lived in - so the bind fired once to start,
  once to stop, and never again. There are two lists now: `MC.connections` for
  the global bind, `MC.recordConnections` for the per-recording listener.
- **Rotation is recorded.** Each sample now carries the yaw you were facing,
  and playback reproduces it. This matters more than it sounds: attacks fire in
  the direction the camera points, so a click replayed while facing the wrong
  way hits nothing. Macros recorded before this fall back to looking where they
  walk. Toggle: *Replay recorded facing*.
- **Save to map / Play map.** A dropdown picks which of the fourteen dungeons
  the open recordings belong to, and another loads and plays any map's
  recordings without switching the GUI over first.
- **Macros have their own file**, `DungeonAutofarm_macros.json`, keyed by map.
  A ten-minute recording is thousands of samples; keeping them out of the
  config leaves that small and hand-editable, and makes the macros easy to copy
  between machines or hand to someone else. Pre-2.7 macros stored inline in the
  config are adopted into it on load.

## 2.6.0 - 2026-09-01 - "Firstperson"
- **Macros are a top-level mode now.** They had been nested inside the waypoint
  editor's panel behind a Waypoints/Macros selector, which was wrong on its own
  terms: the two systems are peers. Macros get their own **Macros** button in
  the main window and their own panel, with the idle-mode switch
  (Waypoints / Macros) at the top of it.
- **Recording switches the free-fly editor off.** This is the real bug: the
  editor detaches the camera from the character entirely, so recording with it
  armed captured a route the character never walked - and you cannot drive in
  first person while a free camera has your input. Starting a recording now
  disables the editor, and so does switching the idle mode to Macros, since the
  editor has no meaning there.
- The waypoint panel's **Clear** button is no longer context-sensitive (it only
  ever clears waypoints); the macro panel has its own **Clear all**.

## 2.5.1 - 2026-09-01
- **Fixed: the macro Record and Bind buttons could not be reached.** The Route
  panel was only ever opened by the **Edit Path** button, and that same button
  also armed the free-fly camera editor and paused the loop. So the only path to
  the recorder was Edit Path -> Macros, by which point the camera was flying and
  the character could not be driven - which is the one thing recording requires.
  The feature shipped unusable.
- Opening the panel and arming the editor are now **separate**: the main-window
  button is **Route Panel** (it just shows the panel), and **Freecam** lives
  inside the panel's waypoint view, where it is hidden in macro mode because it
  means nothing there.

## 2.5.0 - 2026-09-01 - "Playback"
Macro Waypoints: record a run, keep the recordings per map, play them back.

### The mode dropdown
- The path panel (now **Route**) has a two-way selector at the top:
  **Waypoints** (the legacy hand-placed path) and **Macros** (recorded runs).
  They are alternative answers to "what do I do when there is nothing to
  fight", so exactly one is in charge - in macro mode the idle branch no longer
  walks the waypoint path, and switching to legacy stops any playback.
- The bottom **Clear** button is context-sensitive: it clears whichever list
  the current mode owns. **Save** and **Load** are unchanged and cover both.

### Recording
- **Record** button, plus a **bind box**: click it, press a key, that key now
  starts and stops recording from anywhere (Escape cancels the capture). The
  bind is saved with the config. The listener ignores the key while a text box
  has focus, so renaming a macro cannot start a recording.
- Starting a recording **switches the loop off** - you are driving, and the bot
  must not fight you for the character. Starting playback switches it back on,
  since the main loop is what drives movement each frame.
- A recording captures the start position as its first sample and then samples
  the root every `CFG.macroSampleDistance` (2.5 studs) or
  `CFG.macroSampleInterval` (0.12s), whichever comes first, plus every action
  input - attack click, Q, E, jump - anchored to the sample it happened at.
  Coordinates are rounded to one decimal, which is far under the arrive radius
  and keeps a long macro's JSON to a sane size.

### Why positions and not held keys
- The obvious reading of "record the inputs and play them back" is to store
  W-down at 0.4s, W-up at 2.1s and re-send them on a timer. That desynchronises
  within seconds in practice: a different framerate, a slightly different spawn
  point, one clip on a doorframe or one knockback shifts the character off the
  recorded line, and every later input then lands somewhere else with no way to
  notice or recover.
- Movement is therefore stored as **absolute positions**. The replay steers back
  onto the recorded route after any disturbance, and a macro recorded at 30fps
  plays correctly at 144. The **actions are still exactly the recorded inputs** -
  they are anchored to the point along the route where they were made rather
  than to a wall-clock offset, so they stay attached to whatever they were
  aimed at.

### Playback
- **Play from top** runs the list in order; **Play this** on a row starts from
  that one. **Loop** restarts the list after the last macro.
- Each macro plays in two phases. **Approach**: walk to its first sample using
  the normal routed pathfinding (navmesh where there is one, steering where
  there is not) - the character may be anywhere, and only the recorded part of
  the route is known to be walkable. **Replay**: follow the samples in order,
  firing each action as its anchor sample is reached. Several samples are
  consumed per frame when the character is moving well, so the replay does not
  crawl.
- **Hazard escape still sits above playback**, so it dodges telegraphs that were
  not there when you recorded and then rejoins the route - which works precisely
  because the samples are absolute. Everything else (pursuit, recovery, the
  stuck detector, target facing) stands down while a macro is playing: the
  recording already contains the fighting, and being pulled off the route would
  detach every later action from the place it was aimed at.
- **Stuck handling is the macro's own**: no progress toward a sample for
  `CFG.macroGiveUpTime` skips that sample and jumps; `CFG.macroSkipLimit`
  skips in a row abandons the macro and moves to the next. A door that is shut
  this run, or having drifted below a ledge, is survivable rather than terminal.

### Storage and display
- Macros are stored **per map**, in the same per-map entry as that map's
  waypoints and low-detail keep list, so a dungeon's whole setup travels
  together. The list is renamable (type in the row) and reorderable (^ / v / X).
- The selected macro's route is drawn in the world as a sparse violet line with
  a green **START** orb and its name, capped and rebuilt only on selection, not
  per frame. `CFG.macroShowRoute` turns it off.

### Structure
- New module `src/macro.lua`, loaded between `path` and `streamer`
  (`tools/modules.py`, `main.lua`). It imports from core/nav only and is
  consumed by config, ui and main.

## 2.4.0 - 2026-09-01 - "Cartography"
Four requests: hold attacks still long enough to pick them, trial runs with the
loop off, a low-detail world, and per-map storage.

### Freeze Parts
- **A telegraph exists for well under a second**, which is not long enough to
  point a mouse at - so "Pick Telegraph" was nearly unusable for exactly the
  attacks it exists for. **Freeze** (third button on the picker row) holds a
  **copy** of every attack the moment it is detected: an anchored, query-able,
  childless clone in our visual folder that stays after the real part is gone.
  Copies are inert (no collision, no touch, no scripts) and live under the
  visual root, so the classifiers and our own raycasts ignore them.
- The copy records the original's **name and parent** as attributes, so picking
  a copy produces an Attack Book entry about the real attack, not about the
  copy. Same for the own-effect picker.
- Capped at `CFG.freezeCap` (400) with a throttled log line; turning Freeze off
  clears them all, as does Destruct.

### Pick Telegraph now writes to the Attack Book
- A hand pick used to only add a name to the learned-names set, which had no UI
  at all - the only way to undo one was to find the part and click it again. It
  now **also creates an Attack Book entry** (`source = "picked"`, enabled, 0
  hits), so hand picks and trial-run discoveries land in the same list with the
  same rename / disable / delete controls. Clicking a marked part again removes
  both the learned name and the entry.

### Trial runs work with the loop off
- The hazard scan lived in the main combat loop, which returns immediately when
  the loop is off - so with farming paused there was no hazard list, no
  highlights, no name tags, nothing to freeze, and the damage correlator had an
  empty suspect list. The scan now runs from the scanner loop **whenever Trial
  Run, Freeze or a picker is armed**, farming or not. Standing still and letting
  an attack hit you is the natural way to study it, and that no longer requires
  the bot to be driving your character at the same time.
- Motion tracking and the pruning of aged-out parts moved into the world index
  step, where they belong: they are index maintenance, and previously
  `HZ.recentParts` was only pruned from inside the combat loop, so with the loop
  off it grew without bound.

### Low Detail
- **Hides every part in the world whose name you did not pick.** Enemies
  (anything under a model with a Humanoid), anything currently classified as an
  attack, and our own markers are always kept - hiding those would defeat the
  point of running the bot.
- **Hiding is `Transparency = 1` + no shadow, never destruction.** Collision is
  untouched: a hidden floor is still solid and still walkable. Originals are
  snapshotted per part and restored on toggle-off and on Destruct.
- **Particles, trails, beams, smoke, fire and sparkles** are indexed separately
  and switched off with the mode (`CFG.lowDetailKillEffects`); in Roblox they
  are usually the other half of the frame cost.
- Parts are swept from the world index pool a bounded slice per frame
  (`CFG.lowDetailBudget`), so turning it on across a whole dungeon costs a
  little work for a couple of seconds rather than one long freeze.
- **Pick parts to keep** is a third picker mode: click a part to keep or drop
  its name. The keep list is shown in the panel with an X per entry.

### Per-map storage
- Waypoint paths and low-detail keep lists are properties of a dungeon, not of
  the session, so they are now stored **per map** across all fourteen: DT, WO,
  PI, KC, TU, SP, TC, GH, SS, OO, VC, AT, EF, NL. `RT.mapData` holds every map
  the config knows about; the live `NAV.waypath` / `LD.keepNames` are the
  selected map's entry checked out for editing.
- **Map & Detail panel** (button next to Hitbox): `<` / `>` to pick the map,
  Save all maps, Reload config, and the low-detail controls. Switching maps
  checks the current one back in first, so nothing is lost, and **saving one map
  never drops the others**.
- The selected map is stored in the config and **loaded on execution**, so a
  session comes up on the dungeon you left it on.
- A pre-2.4 config with a single top-level `waypath` has it adopted into
  whichever map the config names, so an existing route is not lost by upgrading.

## 2.3.0 - 2026-09-01 - "Fieldnotes"
Three requests: learn from damage on "trial runs", predict projectiles, and
always show enemy attacks with their names.

### Trial runs and the Attack Book
- **Trial Run** (button where the highlight toggle was): while it is on, every
  drop in health is a lesson. The suspects for a hit are the hazards already
  detected in range (strongest evidence - we were standing in one) plus every
  part that appeared within `CFG.damageCorrelationWindow` (1.5s) before the hit
  and within `CFG.damageCorrelationRadius` (25 studs) of us. The closest two are
  written into the **Attack Book** or confirm an existing entry (hit count goes
  up). A hit with no candidate at all - a melee swing with no spawned part, a
  DoT tick - learns nothing and says so in the log; that is what keeps the book
  from filling with scenery.
- **What a record is**: a plain-data signature of the part (name, parent name,
  class, material, shape, colour, size) plus a name, hit count, max damage,
  `moving`, `melee` and `enabled`. A part matches a record **by name** when the
  name is specific (and by parent name too when that is specific), **by look**
  (material, shape, anchored, colour within `attackColorTolerance`, size within
  `attackSizeTolerance`) when the name is generic like `Part`. Matches are
  memoised per part and cleared when the book changes.
- **Naming**: the part's own name if it says something, else the parent's name,
  else `Attack N`. Rename by typing in the panel.
- **Melee hitboxes start OFF.** A part learned from inside a creature model is
  that creature's swing hitbox; dodging it keeps the bot out of its own attack
  range, so the record is created disabled and the log says so. Turn it on in
  the panel if that is really wanted.
- **Detection order** in `isDamageBrick`: our visuals, fully transparent, manual
  telegraph pick, own effect, ownership, **attack book**, creature-part veto,
  learned telegraph name, **projectile**, CanCollide, heuristics. The book sits
  above the creature-part veto precisely so an enabled melee record can work.
- **Attack Book panel**: name box (editable), `N hits, dmg, look, moving, in
  creature`, ON/OFF, X. Bottom row: **Save** (writes the book with the rest of
  the config), Clear, Close. The main-window button shows the entry count. The
  book is restored on load and used for detection whether or not a trial run is
  on.

### Projectile prediction
- Parts that appeared in the last `CFG.projectileTrackWindow` (6s) and every
  detected hazard have their velocity tracked each frame (smoothed half/half so
  a spawn teleport does not read as speed). Big anchored collidable parts are
  skipped so a streaming burst does not cost a frame.
- **A moving hazard is dodged along the strip it will sweep** over the next
  `CFG.projectileLookahead` (1.2s): `hazardClosestPoint` takes the closest point
  along that sweep instead of the part's current position, and the safety test,
  the penalty field and the repulsion vector all go through it. A projectile
  heading at the character reads as a hazard before it arrives; stepping out of
  its line reads as safe even while it is still close.
- **Escape candidates sideways**: each moving hazard adds two candidates
  perpendicular to its travel, which the swept-strip penalty then ranks.
- **Projectile discovery**: a small thing (`projectileMaxSize`) that appeared
  moments ago and is moving faster than `projectileMinSpeed` (8 st/s) is a
  hazard whatever it is called and however it is anchored - tested before the
  anchored/non-collidable telegraph rules, which would otherwise reject most
  projectiles. A young part that *starts* moving is re-classified on the spot.

### Always highlighted, always named
- The red highlight is no longer a toggle; every detected enemy attack is drawn.
  Each one carries a **billboard tag**: its Attack Book name (or part name),
  plus `>> 24 st/s` if moving or its age if not. Moving hazards also get a thin
  neon **predicted-path line** along the sweep, so the prediction is visible.
  Tags and lines are pooled with the highlight and cleaned up with it.
- An old config that saved the highlight toggle off no longer switches it off.

## 2.2.0 - 2026-09-01 - "Lifeline"
Priorities 2 and 1 from the handover list (the stuck-on-terrain problem and the
manual path as the fallback), plus the two extra asks (Q/E radius, own attacks).

### The bot got stuck on anything that was not flat, obvious floor
- **The shin-height steering probe treated every ramp and step as a wall.**
  `headingClearDistance` fires two rays per heading, one at roughly shin height
  (about 1.4 studs above the feet) and one at head height. On any upward slope
  the shin ray hit the ramp surface itself within a few studs and reported the
  heading blocked. "Straight ahead" was therefore never clear the whole way on
  an incline, the fan swung to whichever sideways heading was roomier, and the
  bot ground along the foot of every slope. A probe hit now only counts if it is
  wall-like: a surface facing up (`CFG.walkableNormalY`, 60 degrees) is floor or
  ramp, and a lip no taller than a step (`CFG.maxStepHeight`, checked by looking
  down from head height just past the hit) is stepped onto. Tall walls are still
  caught by the head-height ray, which is unchanged.
- **Drops were refused.** The steering destination check rejected any candidate
  more than 12 studs above OR below - so a ledge down into the next room was
  "off a ledge" and never taken. It is asymmetric now: a climb must be within a
  jump (`CFG.maxClimbHeight`, 7), a drop is allowed up to `CFG.maxDropHeight` (30).
- **A stall on a navmesh route now hops.** The jump-on-stall only fired for
  direct routes; a navmesh route stuck on a lip or an invisible wall (the mesh is
  baked without them) just recomputed the same path. Jumping is free and clears
  most of them.

### The manual path is finished: routed, and the last resort
- **Walking to a waypoint uses the navmesh.** `walkTowardPoint` was a straight
  steer at the point, which is exactly what fails across a drop or up a ramp with
  a lip. It now asks `PathfindingService` for a route to the point (slim agent,
  jumping allowed), follows it like the pursuit follower (jump waypoints,
  invisible-wall probe, stall counter), and only steers directly when the navmesh
  has no answer. It also measures progress toward the point itself, so a caller
  can tell "arrived" from "walked into a wall for six seconds".
- **An unreachable waypoint is skipped**, not parked on forever
  (`CFG.pointGiveUpTime`).
- **Recovery mode.** If the character stays inside a 10-stud circle for 2.5s
  while it is actively trying to move (`CFG.recoveryStuckRadius/Time`) - not
  while dodging, not while standing in range attacking - normal navigation has
  wedged itself. The bot walks to the nearest path waypoint and on along the path
  for two points, then hands back to pursuit with the bench cleared. Re-sticking
  within 12s continues further along the path rather than returning to the same
  nearest point, and walks two more points each time. The direct walker giving
  up on an enemy (the old "benched" branch) now goes to recovery too. An enemy
  within attack range ends recovery early - a mob in your face is not a wedge.
  No path set = a throttled log line and the old behaviour.
- `progressPath` no longer touches `pathIndex` while recovery drives it, and the
  passed-marker update is incremental (see 2.1.0).

### Q/E radius gate (requested)
- **"Q/E in radius" button**: auto Q/E only fire while the current target is
  within **Ability radius** (new slider, 5-60 studs). **"Show radius"** draws it
  as a translucent sphere on the character. All three are saved with the config.

### Own attacks were being dodged (requested)
- A fresh, glowing, warm-coloured disc at our feet is exactly what the appearance
  test looks for, so the bot's own slashes and ability effects scored as
  telegraphs and it backed away from them.
- **Timing against our own casts.** Two signals say "we just cast": an
  Action-priority animation starting on our character (idle/walk/jump are
  Core/Idle/Movement priority, attacks are Action), and this client firing an
  attack-ish remote. A part that appears within `CFG.ownAttackWindow` (0.45s) of
  either, within `CFG.ownAttackRadius` (14 studs) of us, is ours. Neither signal
  is the auto-clicker or the Q/E key spam - those fire ten times a second whether
  anything casts or not and would leave the window permanently open.
- **Names are learned** (unless generic like "Part") and **saved with the
  config**, so the next cast is recognised on sight even outside the window.
- **Pick Own FX** button: the telegraph picker's twin. Click one of your own
  effects to mark it (and learn its name) as ours; click again to unmark. A
  hand-picked telegraph always outranks a learned own-name, and vice versa.
- Check order in `isDamageBrick`: our visuals, transparency, manual telegraph
  pick, own part / own name, ownership, humanoid ancestor, learned telegraph
  name, then the heuristics.

### Attack path
- **The detected remote is never fired any more.** Its argument signature is
  unknown, so `FireServer(position, enemy)` either did nothing or risked a
  malformed-remote kick - and once a remote was detected the click path was
  skipped entirely, i.e. a bot that silently stops attacking. The remote is now
  recorded for own-attack timing only; attacking is always the mouse click.

## 2.1.0 - 2026-09-01 - "Steady"
Priority 1: 20 lag spikes in 10 seconds, from the moment the script starts,
regardless of what it is doing.

### The spike
- **The scanner walked `Workspace:GetDescendants()` every 0.35s and classified
  every part on the map inside one Heartbeat.** That single call allocates an
  array of every instance in the world; the loop then ran `isDamageBrick` (six
  ancestor tests, ownership with `GetAttributes` and a Players loop and a
  recursive parent walk, name matching, the appearance test) on every BasePart.
  Three times a second. And every 4s `flushClassificationCaches` wiped the memo
  caches, so the very next scan recomputed all of it from scratch: a spike every
  0.35s with a bigger one every 4s, on any map, from startup. That is the "1
  every 0.5 seconds" measurement.
- **Replaced by a world index** (`hazards.lua`, WORLD INDEX). Built once - and
  even that ingest is sliced across frames (`CFG.indexBuildBudget`) so it never
  lands as one freeze - then kept current by `DescendantAdded` /
  `DescendantRemoving`, which are O(1) per instance. Enemy models (anything with
  a Humanoid) and candidate health billboards are sets the scan simply iterates:
  dozens of instances per scan instead of tens of thousands. Parts go into a
  pool that is re-classified round-robin, a bounded slice per frame
  (`CFG.partEvalBudget`, scaled so a full lap is about two seconds on a huge
  map), so a pooled effect part that is turned INTO a telegraph by a property
  change is still caught. A part that has just been added goes to the front of
  the queue and is classified the frame it appears - the case that matters for
  telegraphs. The catalog arrays are rebuilt from the sets only when membership
  changes.
- **The `__namecall` hook allocated a table on every method call in the
  client.** `local args = {...}` ran for every `FindFirstChild`, `IsA`, `Raycast`
  the game or this script made, and was never read. That is a constant
  allocation stream feeding the garbage collector - periodic GC pauses from the
  moment the hook went in. Rewritten: one string compare on the fast path, no
  allocation, removed again after `CFG.remoteHookLifetime` (3 minutes; it only
  exists for own-attack timing now), restored on Destruct.

### Smaller per-frame costs
- Telegraph feed rows are pooled: built once, hidden when unused, text rewritten.
  They were five Instances per hazard destroyed and recreated four times a second.
- Path node pool only writes Position/Size/Color when they changed.
- `RespectCanCollide` support is tested once at startup, not with a pcall and a
  closure inside every raycast (dozens per frame while steering).
- Every instance the script draws now lives under one `DungeonAutofarmVisuals`
  folder: one ancestor test in `isDamageBrick` and one raycast exclusion instead
  of six each, and the world index skips the whole subtree.
- Passing a path waypoint destroys that waypoint's marker instead of rebuilding
  every marker on the path (with Show Radius on that was a hundred-plus
  Instances per crossing).
- The hitbox adornments re-point their adornee each refresh; after a respawn they
  used to point at the dead root and simply vanish.

## 2.0.0 - 2026-09-01 - "Modular"
Priority "1" (the split): stop making Claude read 5000 lines to change one
thing. No behaviour change - this is purely structure and tooling.

- **Split into `src/` modules**: `core`, `hazards`, `nav`, `path`, `streamer`,
  `config`, `ui`, `main`, each a function receiving one shared table `S`.
  Imports are `local x = S.x` at the top of a module, exports `S.x = x` at the
  bottom. Load order is fixed (`tools/modules.py`, `main.lua`) and a module may
  only import from modules above it; the two late-bound cases
  (`refreshPathPanel`, `unhookAttackRemotes`) are read as `S.x` at call time.
- **Loose mutable locals moved into `RT`** (`farmEnabled`, `debugLevel`, the
  connections, the render toggles...). A bare local copied into another module
  would go stale; a table field does not. The rename was done on code spans
  only, with table-constructor keys protected - `debugLevel = debugLevel` in the
  config table is the exact case that bit 1.12.0.
- **The 200-register cap is gone as a concern**: each module is its own function
  scope, and the biggest is under 70 top-level locals. The four functions that
  were globals only to dodge the cap are locals again.
- **`DungeonAutofarm.lua` is a built bundle**, produced by `python tools/build.py`
  from the modules, one `loadstring` and one HTTP request. `main.lua` is a
  development loader that fetches the modules one by one.
- **`tools/check.py` replaces `luacheck.py`.** It parses every module with a real
  Lua interpreter (lupa), audits every identifier against locals / imports /
  known globals (a scope-aware use-before-definition sweep), checks that every
  `S.x` read is exported somewhere and every import comes from an earlier
  module, counts top-level locals, and refuses a version mismatch between
  `SCRIPT_VERSION`, the in-script changelog and this file. `build.py` runs it
  first and will not build on a failure.
- **`tools/smoke.py`** executes the bundle under a stub Roblox right through
  `startAutofarm()` and a few Heartbeat ticks: every module body runs, every
  import is dereferenced, the whole UI is built. It does not prove behaviour;
  it proves the code path does not throw on the way in.

## 1.21.0 - 2026-09-01 - "Milestone"
Fix pass on the path system.

- **Save/Load are now in the path panel.** The panel gained a **Save**, **Load**
  and **Clear** row along the bottom, so there is an obvious button to write the
  path to the config (and read it back) without hunting for it in the streamer
  panel.
- **Waypoints clear as you pass them.** Come within the **clear radius** of the
  next waypoint *in order* and it is marked passed and vanishes from the world.
  New **clear-radius slider** and a **Show Radius** toggle (draws the radius as a
  translucent sphere) in the panel. Only the next-in-sequence waypoint is ever
  consumed, so you cannot skip ahead by wandering near a later one.
- **The saved config is never touched by this.** Clearing is purely visual /
  progress (a `pathIndex`, not saved); `NAV.waypath` keeps every point, so Save
  writes the whole path and Load brings it all back.
- **The path doubles as unstuck guidance.** When the bot benches an enemy as
  unreachable (i.e. it wedged itself), it now walks the path to get out instead of
  just standing there reselecting.
- **You can actually turn the camera in Edit Path now.** Holding right-mouse to
  look locks the cursor in place (`MouseBehavior`), so the look delta keeps
  coming instead of dying the instant the pointer hits a screen edge.

## 1.20.0 - 2026-09-01 - "Cartographer"
Fix pass, four items.

- **Telegraph feed stopped stacking.** The empty-state "No active hazards" row is
  a `TextLabel`, and the per-refresh cleanup only destroyed `Frame`/`TextButton`
  rows, so one copy piled up every refresh. Cleanup now clears every `GuiObject`.
- **Show Walls shows every invisible wall.** The range filter and the 40-count cap
  are gone - it draws them all now (it is opt-in, so the cost is yours to spend).
- **Gates are gone; a hardcoded waypoint path replaces them.** No more marking
  parts and hoping they drop. Instead: an **Edit Path** button opens a free-fly
  camera - **WASD** to move, **E/Q** up/down, **hold right mouse** to look - and
  **left-click the map** to drop a waypoint there. Each waypoint gets an orb and a
  numbered `BillboardGui`, joined by a faint line. A **Path Waypoints** panel
  lists them with up / down / delete, plus Clear All. The bot walks the path (in
  order, holding at the end unless `CFG.loopPath`) whenever it has nothing to
  fight. Farming auto-pauses while you edit so only the camera moves.
- **The path saves and reloads.** Waypoints are stored as raw coordinates in the
  config (Save / Load in the Streamer panel), so a route you lay out once comes
  back next session.

## 1.19.0 - 2026-09-01 - "Portcullis"
Fix pass: manual gates, obstacle-aware pathing, and the FPS drops.

### Gates are marked by hand now
- **Auto-detection is gone.** The name/appearance guessing that drove barriers is
  removed. Instead there is a **Mark Gates** button: arm it and click a wall to
  mark (or unmark) it as a gate. Marked gates draw **blue** while the picker is
  armed or the overlay is on, so you can see what is marked.
- **Marks are saved and reloaded.** They persist to the config as instance paths
  (the same mechanism as manual streamer binds) and re-resolve on load, so a
  dungeon you have set up once comes back marked.
- **The push through a gate fires off the gate itself dropping** - destroyed, or
  made passable - not an enemy-count guess. That is exactly "a gate that drops
  after the section is cleared," so it is both simpler and more reliable, and the
  boss-minion edge case disappears entirely.
- The **Show Walls** button now toggles the green invisible-wall overlay; gates
  are blue and show alongside it (and while marking).

### Stop running into walls the navmesh does not know about
- The navmesh is baked without the game's invisible walls, so a valid navmesh
  path could still drive the character straight into one. The follower now
  **probes the short step to each waypoint and steers around a solid** that is
  actually in the way (and asks for a fresh path), instead of grinding on it.
  Marked gates and invisible walls are solid, so this catches both.

### FPS
- **The two full-map scans are now one.** The enemy scan and the hazard/wall
  catalog each ran their own `Workspace:GetDescendants()` - the single biggest
  recurring cost on a large map. They share one traversal now.
- Removing auto-detection also removed the per-part gate name-walk that ran over
  every part on the map twice a second.
- (Carried from the fix list: the 1.17 openness steering no longer ray-scans
  every heading each frame.)

## 1.18.0 - 2026-09-01 - "Breach"
Three requests: steer to where a barrier drops when a section unlocks, a
barrier/invisible-wall overlay with a toggle, and the FPS drops.

### Push through the opening on a section unlock
- **A section unlock is read from the enemy count jumping up** - specifically a
  rise *from a cleared count*. That "from cleared" part is the whole trick for
  the boss case: a boss that spawns minions does it while the count is still
  high (the boss is alive), so the count never fell to cleared and the push does
  not fire. Only a genuine clear-the-room-then-new-mobs-appear sequence trips it.
  Tunables: `sectionClearThreshold`, `sectionUnlockJump`.
- **On unlock, the bot pushes through where the barrier stood** into the new
  room, for `advanceDuration` seconds or until it arrives. The last barrier
  position and the forward direction through it are remembered as the catalog
  sees them, so the aim point survives the barrier being deleted. If an enemy is
  already within `advanceYieldRange`, fighting it comes first - the push only
  covers the gap where the bot would otherwise idle at the old barrier line
  waiting for the next room's mobs to stream in.

### Wall overlay (one toggle)
- New **Show Walls (Barrier/Invis)** button. Barriers draw **blue**, invisible
  collision walls draw **green**. One button toggles both, saved with the config.
- **Off by default, and capped.** Highlighting is the first thing to cost frames,
  and invisible walls can be numerous, so the overlay only scans for them while
  it is on, only within `wallDisplayRange`, and never draws more than
  `wallDisplayCap` of each. Boxes are pooled and reused, so a static set is free
  to hold on screen.
- An invisible wall is defined as solid + see-through + anchored + wall-shaped
  (thin in one horizontal axis), so invisible floors and trigger volumes are not
  swept up.

### FPS drops
- **The 1.17 "run toward open space" steering was scanning every heading, every
  frame.** It measured all eleven fan directions to rank them for openness -
  six capsule rays each, and on executors without native collision filtering
  each of those fans out into several more casts. That was the regression. It
  now takes the first heading that is clear the whole way (in the open, that is
  straight ahead on the first probe - a handful of rays, as before) and only
  falls back to ranking openness when nothing is clear the whole way, i.e. when
  it is actually boxed in and the extra work is warranted.
- **Barrier and invisible-wall classification is memoised.** The catalog tests
  every part on the map, and the barrier name-walk was re-running for thousands
  of parts twice a second; it is now cached per part like the other classifiers
  and dropped every four seconds.
- If frames still dip, the remaining lever is the two separate full-map scans
  (enemy scan and hazard catalog) - folding them into one traversal is the next
  step, called out here so it is not forgotten.

## 1.17.0 - 2026-09-01 - "Frontier"
Three requests: the stutter that survived 1.16.0, barriers as the way forward,
and running toward open space instead of into walls.

### Stutter, three remaining sources
1.16.0 killed the Instance churn (a framerate problem). What was left was
*character* stutter - the body itself jerking while the game ran fine - from
three per-frame writes to the humanoid.

- **Facing snapped rigidly every frame.** The AlignOrientation was rigid, so it
  slammed the body to the exact bearing to the enemy each frame. Against a close,
  moving target that bearing swings several degrees per frame, and the body
  whipped back and forth to track it. It now eases with a high responsiveness:
  still a fast turn, but a smooth one, no whip. (`CFG.faceResponsiveness`.)
- **Direct mode re-sent `MoveTo` every frame.** The steer result is a fixed world
  point held for a beat, but it was handed to `MoveTo` on every Heartbeat, and
  each call restarts the humanoid's approach - a micro-stutter as it walked. The
  goal is now re-sent only when the carrot actually shifts, which still happens
  about ten times a second as the character advances, so it never times out.
- **The bot shuffled on the spot while attacking.** The standoff point is always
  `safeDistance` from the enemy in the *current* player-to-enemy direction, so it
  orbits the enemy as the bot moves, and `MoveTo` chased it every frame - a
  constant foot-shuffle the whole time it stood in range. Inside a small deadband
  it now holds position and lets facing and the attack run.

### Barriers are the way forward
- **When there is no enemy to fight, the bot walks to the nearest section
  barrier** instead of standing idle. Barriers seal a room until it is cleared,
  then vanish, so heading to one pushes the bot through the dungeon rather than
  parking it where the last mob died. It stops a few studs short (barriers are
  solid) and holds there; when the barrier drops or the next room's mobs stream
  in, normal combat resumes.
- **Idle only, on purpose.** Seek never runs while an enemy is targetable, so a
  mis-detected barrier can never pull the bot off an actual fight - the worst a
  false positive can do is walk it at a wall while it had nothing to do anyway,
  and the existing stuck detection covers that.
- Detection is **name-driven** (`CFG.barrierNames`), not appearance-driven: a
  wall-shaped part is otherwise indistinguishable from ordinary map geometry, and
  a false positive is worse than a miss here. The default list is deliberately
  narrow. **If barriers are being missed, paste what the game actually names them
  and the list grows.** Piggybacks the half-second hazard catalog sweep, so it
  adds no per-frame cost. Toggle with `CFG.seekBarriers` (saved with the config).

### Runs toward open space
- **Steering prefers the roomiest heading, not the first clear one.** The probe
  used to answer only "clear at 14 studs?" and take the first heading that
  passed, smallest deviation first - which happily picked a direction clear by a
  hair and scraped along the wall behind it. It now measures how far each heading
  stays clear and, among headings within a small deviation of the goal, takes the
  most open one. Deviation is only a tiebreak, so it still goes straight when
  straight is open but swings toward daylight when the goal side is walled.
- The committed-heading logic is kept - it still holds a chosen deviation to
  avoid oscillating - but only while that heading stays genuinely open, so it
  peels off a wall it has started to scrape instead of grinding along it.

## 1.16.0 - 2026-09-01 - "Smooth"
Three per-frame costs, largest first.

- **Path markers were rebuilt from scratch on every recompute.** A 48-waypoint
  route over 178 studs, with a marker every 1.5 studs, is roughly 166 Parts - all
  destroyed and recreated each time, and while stuck that was every 0.2s. Around
  800 Instance creations a second purely to draw a line. Markers are now pooled
  and reused in place, only the surplus is destroyed, and the total is capped at
  80: a long route draws a sparser line instead of an unbounded one. The escape
  route renderer got the same treatment.
- **The steering fan ran every frame.** Six rays per candidate heading across up
  to eleven headings, re-cast continuously in direct mode. The result is now held
  for 0.1s, or until the goal moves more than 4 studs. The stall detector is what
  catches a heading going bad, and it invalidates the cache when it fires, so a
  blacklisted heading is never served from it.
- **Facing wrote to the physics assembly.** Even carrying velocity across the
  write, assigning `CFrame` moves the assembly and forces a physics resolve plus
  a replication update. Facing now uses an `AlignOrientation` constraint built
  once per character: a single property write, no position change, no physics
  resolve. Rigid, so it still snaps rather than easing. The CFrame path remains
  as a fallback for clients without the constraint, and the attack routine uses
  the same helper.
- The constraint is rebuilt automatically after a respawn and torn down on
  destruct.

## 1.15.1 - 2026-09-01
- **Fixed: the character stopped moving entirely after 1.15.0.** Assigning
  `HumanoidRootPart.CFrame` resets the assembly's velocity. The new facing code
  did that every Heartbeat, so the character was reset to a standstill before it
  could build up any walking speed - it sat still on a perfectly good path. The
  logs showed it exactly: `waypoints=48 idx=3`, distance frozen at 178.1,
  `moved=false`.
- Linear and angular velocity are now carried across the CFrame write, so only
  the orientation changes.
- Facing is also skipped while already pointed within about six degrees, so the
  write happens on turns rather than on every frame.
- The attack routine had the same CFrame write, throttled to the click rate
  rather than per frame but still resetting velocity ten times a second. It now
  goes through the same safe path.
- Any oversized "bad area" entries recorded while the character was pinned expire
  on their own 14s timer.

## 1.15.0 - 2026-09-01 - "Facing"
- **The character now always faces its current target.** Previously `AutoRotate`
  was left on, so it faced whichever way it was walking and only snapped to the
  enemy for the instant an attack fired.
- Turning is taken off the Humanoid and driven directly, yaw only: position is
  preserved and pitch/roll stay flat, so it changes which way the character looks
  without moving or tipping it. `Humanoid:MoveTo` drives velocity rather than
  facing, so the two do not fight - the bot strafes and circles while staying
  pointed at the enemy.
- Applied after the branch runs, so facing survives a **hazard escape**: it backs
  out of a telegraph still aimed at the enemy, ready to attack the moment it is
  clear.
- Rotation is handed back to the Humanoid whenever the script stops driving the
  character - loop off, destruct, no target - otherwise it would stay locked
  facing a stale direction.
- `CFG.faceTarget` controls it, defaults on, and is saved with the config.

## 1.14.0 - 2026-09-01 - "Deadzone"
### Telegraph detection
- **"effects", "props", "lighting" and "decorations" removed from the
  map-geometry veto.** That veto only ever runs on non-collidable parts, and an
  Effects folder is exactly where a game puts its attack markers - so it was
  rejecting the very things the scan looks for. Likely the single biggest cause
  of the misses.
- **Detection by appearance, not just name.** A telegraph called "Part" or given
  an internal id was previously invisible. Anchored, non-collidable parts that
  are flat on the floor or cylindrical, with a footprint between 3 and 160 studs,
  now score on: translucency, warm colour (the near-universal red/orange/yellow
  telegraph palette), Neon or ForceField material, and **whether they appeared in
  the last 10 seconds** - worth double, since scenery is present from the start
  and an attack marker is not. Three signals accepts.
- Every anchored non-collidable part is timestamped the moment it appears, before
  any filtering, since "appeared just now" is only meaningful if recorded then.
  The table is pruned with the other caches.
- Map geometry no longer vetoes a part that looks like an attack marker.

### Getting unstuck
- **Standing still now blacklists the place, not just the direction.** 1.13.0
  retired a heading; that does not help in a corner or doorway where every
  heading out is bad. Holding position for 1.6s marks a 7-stud radius as bad for
  14s, and steering will not pick a destination inside one.
- **Explicitly skipped while dodging**, as you asked: holding still inside a
  telegraph's clearance is the escape logic working correctly, and blacklisting
  there would fight it.
- Re-trapping in a known area grows its radius rather than stacking overlapping
  entries, so a wide dead-end ends up covered by a single region.
- Escape candidates inside a blacklisted area sort **last rather than out**. A
  spot that trapped us is a poor place to flee to, but still better than standing
  in the damage.
- Readout shows `DIRECT 84 studs (steer 40) [2h 1a blocked]` - headings and areas.

## 1.13.0 - 2026-09-01 - "Breadcrumb"
- **Headings that produce no movement are blacklisted.** The steering probes only
  see what they cast at, so a heading can look clear and still walk into
  something - a thin lip, an invisible collider, a shallow-angle wall. Recovery
  worked, but the next pick chose the same direction again the moment the
  commitment window lapsed. That loop is what kept it grinding against walls.
- Detection is world-space and separate from progress-toward-enemy: moving less
  than 2 studs for 1.1s while actively walking means the heading is bad,
  regardless of whether the target is getting closer.
- **A repeat offender widens.** Re-blocking a direction already in the list
  extends its timer and grows its arc by 12 degrees, up to 75. A direction that
  fails repeatedly is usually a wall being clipped at a shallow angle rather than
  a one-off snag, so a wider exclusion is warranted.
- Entries expire after 7s, so a door opening or a moving platform is retried
  rather than written off permanently.
- **The blacklist never causes paralysis.** If no heading survives it, the pick is
  retried ignoring it entirely - standing still is never better than trying a
  direction that failed a while ago. That second sweep is skipped when the
  blacklist is empty, since it would be identical.
- Blacklisted headings deliberately survive a pursuit reset. The walls that
  caused them have not moved; only the timer should clear them.
- Movement readout shows `DIRECT 84 studs (steer 40) [2 blocked]`.

## 1.12.1 - 2026-09-01
- **Fixed: "Expected '}' ... got '=' " at line 3047.** The 1.12.0 rename rewrote
  `learnedTelegraphNames` everywhere, including where it was a **table key** in
  the saved config. `{ HZ.learnedNames = learned }` is not valid Lua - a
  constructor key cannot be a dotted name - so the whole script failed to parse.
- Fixed the matching read, `data.learnedTelegraphNames`, which the same rename
  had turned into `data.HZ.learnedNames`. That one was syntactically valid, so it
  would have silently failed to restore learned telegraph names from a saved
  config rather than erroring.
- The serialised field name is unchanged, so existing config files still load.
- Hardened the pre-flight checker: it now verifies bracket balance and flags any
  dotted name used as a key inside a table constructor. It only counted block
  keywords before, which is why a brace-level error got through. Confirmed it
  fails on the exact broken form.

## 1.12.0 - 2026-09-01 - "Feeler"
### Why direct walking still hit walls
- **A wall behind a non-collidable part read as clear.** `Raycast` returns the
  first thing it meets, and the probe accepted the heading whenever that first
  hit was non-collidable - so any wall standing behind a decoration, a banner or
  an effect part was invisible to it. Dungeons are full of those, which is why it
  looked random. Non-collidable hits are now skipped through, natively via
  `RespectCanCollide` where the client supports it, otherwise by re-casting past
  each one.
- **The probe was a single zero-width ray at chest height.** It missed anything
  the character's shoulders clip and anything low, such as a railing. Clearance is
  now a crude capsule: two heights across the character's own width, six rays.
- **Steering oscillated in corners.** With two equally good headings it re-picked
  from scratch every frame and ground itself into the corner between them. A
  chosen deviation is now held for 0.45s before reconsidering.
- The destination floor check is kept, so it still will not steer off a ledge.

### Locals
- Grouped pursuit/routing state into `NAV` and telegraph/hazard state into `HZ`,
  joining `CFG`, `UI` and `SM`. **192 to 154 of the 200 register limit.**
- Done as a single-pass regex this time. The 1.6.0 rename applied rules
  sequentially, so an earlier result could be matched again by a later rule -
  which is what produced `SM.UI.statusLabel`. A single pass never rescans
  replaced text. The one genuine clash, `steerCommitTime` existing as both a
  local and a `CFG` field, was caught by an automated check and corrected.

## 1.11.0 - 2026-09-01 - "Compass"
- **Direct walking is now the unconditional fallback.** Benching on a failed path
  was the core mistake: when nothing on the map is routable, every enemy gets
  benched in turn and the bot cycles all fourteen of them doing nothing, which is
  exactly what the logs showed. A failed path now always results in walking at the
  target. Heading the right way is strictly better than standing still, and the
  route often opens up once the gap closes.
- **Benching moved to where it belongs.** An enemy is set aside only after walking
  at it gains no ground for 7 seconds - measured as distance to the enemy, not
  distance travelled, so circling an obstacle does not read as success.
- **Obstacle steering.** Straight-line walking is useless against a wall, so the
  direct mode probes its heading each frame and fans outwards - 20, 40, 65, 90,
  120 degrees either side - taking the smallest deviation that is clear and has
  floor at the end of it. Re-probed every frame rather than cached, since without
  a navmesh obstacles are only known by looking.
- The navmesh probe is now only an optimisation and a diagnostic: when it confirms
  the navmesh is dead, `ComputeAsync` is skipped for 20s. The fallback no longer
  depends on its verdict, so a place where local pathing works but distant targets
  are unroutable still gets walked at.
- Stuck-jump now fires for any direct route, not only when the navmesh was
  declared dead.
- Movement readout shows `DIRECT 84 studs (steer 40)` so the steering is visible
  without the console.

## 1.10.0 - 2026-09-01 - "Deadreckoning"
- **Handles places with no usable navmesh.** Logs showed *every* path failing with
  NoPath at 73-126 studs, across every enemy on the map. That is not fourteen
  unreachable enemies, it is a place where `ComputeAsync` cannot answer at all -
  so benching each target in turn was the wrong conclusion and just cycled
  forever.
- **Probe before concluding.** After 3 consecutive total failures the script paths
  8 studs sideways. If even that fails, the place is the problem rather than the
  target: the navmesh is marked unusable for 20s, the bench list is cleared, and
  movement switches to walking directly. It retests afterwards, so a map where
  pathfinding works again recovers on its own.
- **While in that mode no `ComputeAsync` is issued at all** - not for pursuit, not
  for escape validation. Each failed attempt was four yielding calls, which is
  what produced the log flood and the frame cost alongside it.
- **Direct walking is stepped**, one hop per 12 studs, each dropped onto the floor
  by raycast, rather than a single long MoveTo. Short hops let the humanoid follow
  stairs and ramps and give the stuck detector intermediate progress to measure.
  A stall in this mode also triggers a jump, since without a navmesh there is
  nothing to warn about a step or lip.
- **Direct-walk fallback range raised from 35 to 150 studs.** At 35 every failure
  in the logs (73 studs and up) fell straight past it into the bench.
- Bench logging throttled to once per 2s.

## 1.9.0 - 2026-09-01 - "Keepsake"
- **Fixed a 1.8.0 regression: benched targets were retried every frame.** On
  failure the old code set `currentPathEnemy = nil`, which made `targetChanged`
  permanently true - and `targetChanged` bypasses the recompute rate limit. The
  result was four `ComputeAsync` calls per frame against a route that could never
  succeed, which is what the NoPath log spam showed. The enemy reference is now
  kept, `lastPathComputeTime` is stamped, and the retry interval applies.
- **Benched targets are dropped immediately.** The bench only affected the next
  scan, so a dead target was still pursued for up to a full scan interval.
  The main loop now drops it the same frame and requests an immediate rescan
  instead of waiting out the remainder of the interval.
- **Fixed the Streamer Mode flicker.** The overlay was reasserted on a 0.12s poll,
  so whenever the game rewrote a label - an EXP tick, a heal, a stat refresh -
  the real value was on screen until the next poll. Each target is now watched
  with `GetPropertyChangedSignal`, so the correction lands in the same frame as
  the game's write. The poll stays as a backstop. Writing `Text` refires the same
  signal, so there is a per-element re-entrancy guard.
- **Config save/load.** `Save config` / `Load config` in the Streamer panel write
  `DungeonAutofarm_config.json`, and it is loaded automatically at startup before
  the UI is built, so widgets come up showing saved values. Stores the combat
  ranges, ability toggles, visual toggles, debug level, every streamer field and
  colour, auto-hide, learned telegraph names, and manual binds.
- Manual binds are saved as instance **paths** and re-resolved by name on load.
  Paths are the fragile part - a game that renames or restructures its GUI
  between sessions will not resolve them - so a failed resolve is skipped quietly
  and counted in the log rather than treated as an error.
- `writefile`/`readfile` come from the executor, not Roblox, so every call is
  guarded and the script still runs where they are unavailable, reporting
  "no file access in this executor" instead of failing.

## 1.8.0 - 2026-09-01 - "Detour"
- **Fixed: `Enum.PathStatus.NoPath` was terminal.** A failed path cleared the
  waypoints, flagged a recompute, and nothing else - so the bot re-requested the
  same dead route every 0.5s and stood still indefinitely. NoPath means the
  navmesh found no route, not that anything errored, so retrying it unchanged
  could never succeed.
- **Retry ladder.** On failure it now retries with a slimmer agent radius (1.0
  instead of the configured wall padding, which at 2.0+ makes the agent too wide
  for many doorways), then aims at two thirds and one third of the way to the
  target. A shorter hop usually routes fine, and from there a full path often
  succeeds. The attempt that recovered is logged.
- **Direct-walk fallback** within 35 studs. At that range a NoPath usually just
  means the standoff point landed off the navmesh, so walking straight at the
  target is reasonable and the existing stuck detector recovers if it snags.
- **Unreachable enemies are benched for 10s.** Beyond the fallback range, a
  target that fails every attempt is set aside so the scanner picks the next
  nearest instead of the bot locking onto something sealed off. Map-wide scanning
  finds enemies through walls and in unopened rooms, so this came up often.
  Benched enemies still count toward the on-screen total; they are just not
  targeted. The table is pruned when they die or the bench expires.

## 1.7.1 - 2026-09-01
- **Fixed: the nametag border was not being recoloured.** 1.7.0 only looked for
  `UIStroke`, but most nametags draw the border as a gold Frame sitting behind a
  slightly smaller inner Frame, so nothing was ever detected. Trim is now
  identified by **colour** rather than class: warm golds and yellows where red and
  green are both strong and clearly above blue. The green HP fill, the cream badge
  backing and dark panels all fail that test, so they are left alone.
- Trim detection now also covers billboards parented into PlayerGui and adorned to
  the head, not only ones nested under the character. The adornee check keeps
  other players' nametags out of it.
- `applyBorderColorTo` reordered so the property actually drawing the trim wins:
  a visible background - which is what the colour match keys on - now takes
  priority over a stroke the element may also carry.
- The GUI dump lists every detected trim piece with its path and current colour,
  so a miss can be reported precisely.

## 1.7.0 - 2026-09-01 - "Goldleaf"
- **Coins and Gems fields** in Streamer Mode, matched on name keywords
  (coin/gold/cash/money/currency and gem/diamond/crystal/robux), each with a bind
  button for anything the keywords miss.
- **Nametag trim colour.** Recolours the gold border on the overhead billboard.
  The trim can be a `UIStroke`, a bordered frame, or a plain coloured backing
  frame depending on how the game built it, so all three are handled and the most
  specific wins.
- Auto-detection for the trim is deliberately scoped to `UIStroke` instances
  inside BillboardGuis under the character. Sweeping every `UIStroke` in PlayerGui
  would repaint unrelated HUD elements. Anything outside that scope can be bound
  by clicking it.
- Original snapshots now cover `UIStroke.Color`, `BorderColor3`,
  `BackgroundColor3` and `ImageColor3`, so restore returns the trim to its real
  colour when Streamer Mode is switched off.

## 1.6.1 - 2026-09-01
- **Fixed: "attempt to index nil with 'statusLabel'".** Collateral from the 1.6.0
  rename. `streamerStatusLabel` was rewritten to `SM.statusLabel` first, and the
  later `statusLabel` -> `UI.statusLabel` rule then matched *inside* that result,
  producing `SM.UI.statusLabel`. The word-boundary guard did not help because `.`
  is itself a word boundary. Audited the whole file for the same pattern; this
  symbol was the only one affected, at 14 sites.
- **Added "Dump GUI candidates to console".** Walks PlayerGui and the character,
  and prints every identity-bearing element with its class, current text and full
  instance path. Flags USERNAME, DISPLAYNAME, PAIR_VALUE (`5.30M/5.30M`,
  `129.84M/3.69B`, `5307855/5307855`), BARE_NUMBER (a level tag), HP_TEXT,
  EXP_TEXT, VIP_TEXT, PARENTHESISED (`(Ghastly Achiever)`), NAMEHINT, and AVATAR.

## 1.6.0 - 2026-09-01 - "Backstage"
- **Fixed: "Out of local registers ... exceeded limit 200".** Luau caps a function
  scope at 200 registers and the main chunk had reached 227 locals, so the script
  no longer compiled at all. Related locals are now grouped into three tables -
  `CFG` (tuning), `UI` (widget references), `SM` (streamer mode state) - bringing
  the count to 160. Purely a rename; no behaviour changed.
- **Telemetry overlays are hidden automatically** in Streamer Mode: the World
  Position / Data Loaded / Place Version / Server Age readout and similar
  (job id, session id, user id, client version, account age).
  A container is only hidden when at least two known phrases appear beneath it,
  so a single label that merely mentions "position" will not trigger it, and the
  outermost container holding all the matches is what gets hidden, so no empty
  frame is left behind.
- **Click-to-hide** for anything the phrase list misses, plus Unhide all. Previous
  visibility is recorded per element and restored when Streamer Mode is switched
  off, when auto-hide is turned off, or on Destruct.

## 1.5.0 - 2026-09-01 - "Greenroom"
- **Streamer Mode.** New panel (button in the main window) that masks the account
  identity on screen while streaming. Editable: username, HP, VIP title, EXP,
  level, VIP tag colour, level tag colour, and avatar image. Applies to the game
  GUI and to the overhead nametag.
- **Client-side only.** This changes what this client renders. The server, other
  players and every leaderboard still see the real account. It hides your name on
  stream; it does not change your name in the game.
- Targets are found by content, not by path, since the game's GUI hierarchy is
  unknown to this script: any text containing the real username or display name
  is rewritten, and any image sourced from the real user id is swapped. HP, EXP,
  level and VIP labels are matched on name keywords up to four ancestors deep.
- Username is substituted into the live text rather than overwriting it, so
  surrounding wording survives and the label keeps updating. Leaving HP or EXP
  blank keeps the real value.
- **Bind buttons** on each row for anything the keywords miss: arm the row, click
  the element on screen, and it is bound to that field.
- Targets are sticky once found. A masked label no longer matches the real name,
  so forgetting it would let the real name flash back for up to one discovery
  interval whenever the game rewrote that label.
- Originals are snapshotted on capture and restored when the mode is switched off
  or the script is destructed.
- Avatar takes an asset ID, an `rbxassetid://` string, or a Roblox URL. A script
  cannot upload an image to Roblox, so the picture has to already be an uploaded
  asset.
- Overlay reasserts on a 0.12s clock with rediscovery every 1.5s, both well off
  the per-frame path.

## 1.4.0 - 2026-09-01 - "Lightfoot"
Performance pass. No behaviour changes intended; several things were running once
per Heartbeat that had no reason to.

- **Ownership test memoised, and its inner loop fixed.** `isOwnedByPlayerOrTeammate`
  called `GetAttributes()` - which allocates a fresh table - and five
  `FindFirstChild` calls *once per player*, for every candidate part, every frame.
  Both are now computed once per part and the result is cached. This was the
  single largest cost.
- **Map-geometry and part-shape classification memoised.** The shape test ran a
  `pcall` plus two string searches per hazard, three times a frame.
  Caches are dropped every 4s so late-attached ownership still registers.
- **Enemy scanner walks Workspace once instead of twice.** Two full
  `GetDescendants()` passes per scan became one, with billboards collected during
  the pass and resolved after. Scan interval 0.15s to 0.35s.
- **Visualisers moved off the per-frame path.** The telegraph feed was destroying
  and rebuilding roughly eight Instances per hazard *every frame*; hazard
  highlights and the hitbox adornments likewise. They now refresh on their own
  clocks (0.2-0.25s) or when the hazard set changes.
- **Highlight cleanup is O(n) not O(n*m).** It ran `table.find` over the hazard
  list for every existing child; now a set lookup.
- **Escape search is much cheaper.** Candidate fan cut from 6x16 to 4x10, and the
  per-candidate clearance test from 9 raycasts to 3 - roughly 900 casts per escape
  down to about 120. The navmesh validation added in 1.3.0 is what actually
  decides reachability, so the raycast sweep only has to rank plausibly.
  Its two per-call loop tables are no longer reallocated.
- **Debug strings are built only when they will be printed.** The per-frame
  movement dump and the per-entity scanner line formatted their text and then
  threw it away when throttled or filtered.
- Catalog refresh 0.3s to 0.5s.

## 1.3.0 - 2026-09-01 - "Sidestep"
- **Telegraph picker.** New `Pick Telegraphs` button. Click any part in the world
  to mark it as a hazard; click a marked part to unmark. Marking also *learns the
  part name*, so later spawns of the same attack are caught with no further
  clicks. Picks outrank the CanCollide and map-geometry filters that were
  rejecting real telegraphs. Hovering highlights the part under the cursor, and
  each pick logs name, parent, class, transparency and CanCollide - paste those
  lines and the automatic rules can be widened to match.
- **Broader automatic detection.** Name matching was exact-equality against three
  strings. Now substring matching, split into strong names that stand alone
  (telegraph, precast, aoe, indicator, warning, dangerzone, damagezone,
  attackzone, hitzone) and weak names that still require an enemy attack
  container (hitbox, hitpart, damage, circle, ring, zone, shockwave).
- **Deeper catalog scan.** The refresh walked `Workspace:GetChildren()` and one
  level below, so any telegraph nested deeper than a model's direct children was
  invisible to it. Now walks `GetDescendants()`.
- **Transparent telegraphs are ignored.** A part at transparency >= 0.99 is no
  longer a hazard. Tested per frame rather than per catalog refresh, so one that
  fades mid-cycle stops being dodged immediately, and ahead of manual picks, so a
  marked part also stops counting once it fades.
- **Escape points are verified reachable.** Ranked candidates are now validated
  against the real navmesh and the resulting path is *followed waypoint by
  waypoint*. Previously the code picked a raycast-clear point and issued a single
  straight-line `MoveTo`, which walked into concave geometry and stuck. Validation
  runs off the Heartbeat because `ComputeAsync` yields; the route is recomputed
  when it runs out, when its destination stops being safe, or every 0.4s.
  Unvalidated straight-line escape remains as a last resort and logs when used.
- **Hazard avoidance is planar.** Safety, penalty and repulsion all ignore Y and
  compare on X/Z only. Set `hazardIgnoreVertical = false` to restore height gating.
- Escape routes render as orange nodes (pursuit stays blue), under the existing
  path-render toggle.

## 1.2.1 - 2026-09-01
- **Fixed the stall.** `Enum.Font.GothamItalic` is not a real member of
  `Enum.Font`. It was assigned to the "No active hazards detected" placeholder
  in `updateTelegraphFeedUI`, which only builds when the hazard list is empty -
  so every tick without an active telegraph threw and aborted before
  `attackEnemy`. Exactly matched the "only moves when a telegraph is up"
  symptom. Now `Enum.Font.Gotham`.

## 1.2.0 - 2026-09-01 - "Glasshouse"
- **Main loop no longer swallows errors.** Both Heartbeat loops used a bare
  `pcall`, so any fault downstream aborted the tick silently and the bot looked
  like it was choosing not to move. Now `xpcall` + `debug.traceback`, printed
  under the `FATAL` category.
- Character, humanoid and root are refetched every tick instead of using the
  upvalues captured at load. Stale references across a respawn threw on access.
- Added branch tracing: the loop logs which arm it takes (HAZARD ESCAPE /
  PURSUE / IDLE / no character) on transition only.
- Added a `Movement:` readout to the stats panel showing live pursuit state
  (`PURSUE wp 3/9`, `NO PATH - retrying`, `HAZARD ESCAPE`, `ERROR`).
- `attackEnemy` now reports which guard rejected it rather than returning silently.
- `updatePursuitMovement` dumps its full recompute decision state once per second.
- Added 3-level debug toggle (OFF / NORMAL / VERBOSE). Per-entity scanner lines
  moved to VERBOSE; the scan summary is throttled to one line per 2s. NORMAL is
  now readable instead of a firehose.

## 1.1.0 — 2026-09-01 — "Navmesh"
- Added the version-tracking system: `SCRIPT_VERSION`, `SCRIPT_BUILD_DATE`,
  `SCRIPT_CODENAME` and the `SCRIPT_CHANGELOG` table.
- Added a clickable version badge to the main window header (top-right).
  Hover swaps it to the build date; click dumps the full changelog to console.
- Added a footer build stamp at the bottom of the main window.
- Restructured the header into a dedicated `Header` frame so the whole strip
  stays draggable now that the title shares the row with the badge.
- Version banner prints on startup; every `heavyDebug` line is now version-tagged.
- Version + build date exposed as `ScreenGui` attributes and as
  `_G.DungeonAutofarmVersion` for external inspection.

## 1.0.0 — 2026-09-01
- Baseline. Removed the flawed Phase 2 straight-line shortcut to force robust
  Navmesh routing.
