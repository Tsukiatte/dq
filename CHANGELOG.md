# Dungeon Autofarm — Changelog

Version lives in `DungeonAutofarm.lua` as `SCRIPT_VERSION` / `SCRIPT_BUILD_DATE` /
`SCRIPT_CODENAME`, mirrored in the in-script `SCRIPT_CHANGELOG` table. Keep this
file and that table in sync on every edit.

**Bump rules (semver):**
- `MAJOR` — rewrite or breaking change to core architecture
- `MINOR` — new feature, new UI element, new subsystem
- `PATCH` — bugfix, tuning, constant change, refactor with no new behaviour

---

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
