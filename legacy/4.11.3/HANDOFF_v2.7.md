# Dungeon Autofarm — Handoff

Context for whoever picks this up next. Updated at **v2.7.0 "Kitbuilt"**.

- **Repo:** `Tsukiatte/dq`. Source is `src/*.lua` (eight modules, Roblox Luau,
  run through an executor). `DungeonAutofarm.lua` at the root is a **built
  bundle — never edit it by hand**; run `python tools/build.py` after editing a
  module. `af.luau` is the pre-2.0 single file left in the repo for reference.
- **Load in game:** `loadstring(game:HttpGet("https://raw.githubusercontent.com/Tsukiatte/dq/main/DungeonAutofarm.lua"))()`
- **Target game:** Dungeon Quest Reborn (Roblox).
- **History:** `CHANGELOG.md`, newest first. It is the reasoning record, not just
  a list — read the entry for anything you are about to touch.

---

## What it does

An autopilot. It keeps an index of the world, walks to the nearest reachable
enemy, attacks it, fires Q/E on a timer (optionally only when an enemy is in
range), steps out of red attack telegraphs, and — when all of that has wedged
the character somewhere — walks the user's hand-placed path to get out. A
separate Streamer Mode masks the account identity on screen.

---

## Layout: the modules

Each file in `src/` is `return function(S) ... end`. `S` is one shared table.
A module pulls what it needs from earlier modules into locals at the top
(`local heavyDebug = S.heavyDebug`) and publishes what later modules need at the
bottom (`S.heavyDebug = heavyDebug`). **Load order is fixed and load-bearing**
(`tools/modules.py`, `main.lua`): a module may only import from modules above it.

| Order | Module | Holds |
|---|---|---|
| 1 | `core` | Version + `SCRIPT_CHANGELOG`, services, **`CFG`** (all tuning, ~100 keys — start here for behaviour changes), the state tables `UI` `SM` `NAV` `HZ` **`RT`**, debug logging, `getVisualRoot` |
| 2 | `uikit` | **The widget kit**: theme tokens, window, section, row, toggle, slider, dropdown, colour picker, list, buttons, tooltips |
| 3 | `hazards` | Classifiers + memo caches, `isDamageBrick`, hazard geometry, overlays, telegraph feed, **world index**, pickers |
| 4 | `nav` | Pursuit routing, retry ladder, steering (`steerTowards`), blacklists, escape routing, facing rig, **routed point walking** (`walkTowardPoint`, `followPath`) |
| 5 | `path` | Manual waypoint path: markers, editing, free-fly editor, progression, **recovery** |
| 6 | `macro` | **Macro Waypoints**: recording, the macro list, playback |
| 7 | `streamer` | Streamer Mode (untouched since 1.x) |
| 8 | `config` | JSON save/load, **per-map storage** |
| 9 | `ui` | Control window, streamer panel, route panel, attack book panel, map panel, `destructScript` |
| 10 | `main` | Enemy scan, attack, abilities, remote hook, the two Heartbeat loops, `startAutofarm()` |

**`RT`** is where the old loose mutable locals live (`RT.farmEnabled`,
`RT.debugLevel`, `RT.destroyed`, the connections, the render toggles). They are
table fields, not locals, because a local copied into another module would go
stale. `CFG`/`UI`/`SM`/`NAV`/`HZ` are unchanged from 1.x.

**Late binding.** Two things are defined by a *later* module than the one that
calls them and are read as `S.x` at call time rather than imported:
`S.refreshPathPanel` (assigned in `ui`, called from `path`) and
`S.unhookAttackRemotes` (defined in `main`, called from `ui`'s destruct). If you
add another, do the same; `tools/check.py` will refuse a load-time import of a
later module's export.

**Register cap.** Each module is its own function scope, so Luau's 200-register
limit applies per module. The biggest is ~70 top-level locals. Not a concern any
more, but `check.py` still prints the counts.

**Adding a cross-module function:** define it, add `S.name = name` to the
footer of its module, add `local name = S.name` to the header of the consumer.
Run `check.py`; it will tell you if you forgot either half.

---

## The interface (2.7.0)

`src/uikit.lua` is a port of the Figma kit (file `z7K7RSX8F911V8r4Q01nSU`).
Every colour, radius, gap and type size comes from that file's variables, so
the two stay comparable - **if you change a visual constant, change it there
and nowhere else**. Three rules carried over from the design's own notes:

- **No image assets.** Chevrons, the confirm tick, the pencil and the bin are
  built from Frames. Nothing can fail to load.
- **The accent gradient is defined once** (`Theme.AccentA/Mid/B`, applied by
  `accentGradient`). Every window, button, toggle and slider fill reads it.
- **Elevation is stacked Frames** behind the panel at low alpha, because Roblox
  has no box-shadow and the kit takes no assets. Eight layers at 0.07 come to
  about the design's `0 14px 34px rgba(0,0,0,.45)`.

Two windows, both accordions, plus a HUD. `ui.lua` composes them; it holds no
visual constants of its own. The **HUD is the only thing on screen with the GUI
closed** (bottom-left, `CFG.showHud`); **RightShift** toggles the windows. Every
control takes an explanation string, shown as a tooltip after a second's hover.

**The Legacy / Macro island** at the top of the Autofarm window drives
`MC.mode`, and `applyMode()` hides the sections belonging to whichever system is
not in charge - `legacySections` and `macroSections` in `createControlUI`. Add a
new section to one of those lists or it will show in both modes.

**Widgets that display a value must be registered** with `track(...)` so
`refreshAllWidgets()` can put them back in step after a config load or a Reset
to defaults. A widget returns `{ ..., render = fn }` for exactly that.

**A Roblox Instance rejects new fields.** `chevron`, `buttonRow`, `segmented`
and the rest return TABLES holding their frame plus their functions - do not go
back to hanging methods off the Instance.

## Verification

Three tools, all in `tools/`, all need `pip install lupa luaparser` once.

```bash
python tools/check.py
```
Real parse of every module (an actual Lua interpreter, not the old keyword
balance heuristic), then a scope-aware free-name audit (every identifier is a
local, an import, or a known Roblox global — this catches a function used from a
module that never imported it, and a variable that should have become `RT.x`),
then cross-module wiring (every `S.x` read is exported somewhere; every import
comes from an earlier module), then top-level local counts, then version
consistency (`SCRIPT_VERSION` == first `SCRIPT_CHANGELOG` entry == first
`CHANGELOG.md` heading). Exits non-zero on any failure.

```bash
python tools/build.py
```
Runs `check.py`, refuses on failure, then writes `DungeonAutofarm.lua` and
parses the result. **Run this before every commit** — the bundle is what the
game loads.

```bash
python tools/smoke.py
```
Executes the bundle under a stub Roblox (`game`, `Instance.new`, `Vector3`,
`Enum`... all permissive fakes) right through `startAutofarm()` and three rounds
of every connected callback. Every module body runs, every import is
dereferenced, the whole UI is built, the config loader runs, the idle branch of
the main loop runs. It proves the code path does not throw on the way in; it
does not prove behaviour. A `CALLBACK ERROR` that mentions a stub artefact
(arithmetic on a `Stub<...>`) is the runner's limitation, not necessarily a bug —
read the traceback line.

The first in-game run is still the real test. **Ask the user to confirm the
startup banner version** matches what you just built; several rounds were spent
debugging logs from a stale file. With the bundle on GitHub's raw CDN there is
also a few minutes of cache after a push.

---

## The world index (hazards.lua)

This replaced the per-scan `Workspace:GetDescendants()` walk in 2.1.0 and is the
reason the lag spike went away. Understand it before touching anything that
finds enemies or telegraphs.

- Built once at startup — the `GetDescendants` result is ingested in slices of
  `CFG.indexBuildBudget` per frame — then kept current by
  `Workspace.DescendantAdded` / `DescendantRemoving`.
- `HZ.enemyModels` — every Model with a Humanoid. `HZ.billboards` — every
  BillboardGui (candidate health tags for enemies without a Humanoid).
  `findNearestEnemy` (main.lua) iterates these; dozens of instances, not tens of
  thousands.
- `HZ.partPool` — every BasePart not under our visual folder, as a dense array
  (`HZ.partPoolIndex` gives O(1) swap-remove). `worldIndexStep` runs every frame
  from the scanner loop: it classifies every part in `HZ.freshParts` (added since
  last frame — telegraphs are caught the frame they appear) and then a
  round-robin slice of the pool (`CFG.partEvalBudget`, scaled to keep a full lap
  under ~2s), so a pooled effect part turned into a telegraph by a property
  change is still caught within a lap.
- Membership lives in sets (`HZ.candidateSet`, `HZ.invisWallSet`); the arrays
  the per-frame filter and the overlay iterate (`HZ.candidates`, `HZ.invisWalls`)
  are rebuilt by `rebuildCatalogArrays` only when `HZ.catalogDirty`.
- `scanDamageBricks` (per frame) is unchanged in spirit: filter the catalog down
  to in-range, still-visible, not-ours.

**Everything this script draws goes under `RT.visualRoot`** (`getVisualRoot()`
in core, a Folder named `DungeonAutofarmVisuals`). The index skips that subtree,
`isDamageBrick` and the raycast exclusions test it once. Put any new visual
folder under it.

---

## Navigation, in the order it degrades

1. **Navmesh path.** `PathfindingService:ComputeAsync`.
2. **Retry ladder.** Slimmer agent, then two thirds, then one third of the way.
3. **Direct walking** with `steerTowards`: stepped waypoints, probe fan
   ±20/40/65/90/120°. Since 2.2.0 a probe hit only blocks if it is
   **wall-like**: upward-facing normals are floor/ramp (`CFG.walkableNormalY`)
   and a lip under `CFG.maxStepHeight` is stepped onto — that is what fixed the
   stuck-on-inclines problem, see `hitBlocksWalking`. Destinations may drop up
   to `CFG.maxDropHeight` but climb at most `CFG.maxClimbHeight`.
4. **Bench the enemy** after walking at it gains no ground for 7s — and since
   2.2.0 that goes straight into recovery if a path exists.
5. **Recovery** (`path.lua`). Detector: the character stayed inside
   `CFG.recoveryStuckRadius` (10) for `CFG.recoveryStuckTime` (2.5s) while
   `NAV.driving` was true — a flag the pursuit follower and the point walker set
   each frame when they are actually moving toward a goal; standing in range
   attacking or dodging never trips it. Walks to the nearest waypoint and on for
   `CFG.recoveryWaypoints`, then `exitRecovery` clears the bench and hands back.
   Re-sticking within `CFG.recoveryRepeatWindow` continues from where the last
   recovery ended and walks `CFG.recoveryEscalation` more points. An enemy inside
   attack range ends it early. **No path set = nothing to recover along**; the
   log says so, throttled.

**Macros (2.5.0, macro.lua).** `MC.mode` (`"legacy"` / `"macro"`) picks which
idle system is in charge; in macro mode the idle branch does not walk the
waypoint path. Recording samples the root every `CFG.macroSampleDistance` or
`CFG.macroSampleInterval` into `MC.samples`, and logs action inputs into
`MC.actions` **anchored to the sample index** they happened at. Playback is two
phases: `approach` (routed `walkTowardPoint` to sample 1) then `replay` (direct
`MoveTo` along the samples, firing actions as their anchor is passed).

**Movement is stored as positions, not held keys — deliberately.** Replaying
key-down/key-up on a timer desynchronises within seconds (framerate, spawn
point, one doorframe clip) with no way to recover; an absolute position
self-corrects. The actions are still the recorded inputs. Do not "fix" this by
switching to timed input replay.

`MC.playing` takes its own branch in the main loop **below hazard escape and
above everything else** — so telegraphs are still dodged and the replay rejoins
the route, but pursuit, recovery, the stuck detector and target facing all stand
down. Macro stuck handling is its own: skip a sample after
`CFG.macroGiveUpTime`, abandon the macro after `CFG.macroSkipLimit` skips.
Recording runs from the **scanner** loop (`recordStep`), because while you
record the bot is deliberately not farming and the combat loop is not running.

**Point walking** (`walkTowardPoint`, nav.lua) is what both idle path-following
and recovery use. It routes through the navmesh (slim agent, jumping allowed),
follows the route with the same jump/invisible-wall handling as pursuit, drops to
direct steering after `CFG.pointRouteStallLimit` stalls or when there is no
route, and returns `distance, stuck` — `stuck` meaning no progress toward the
point for `CFG.pointGiveUpTime`, which `followPath` and recovery use to skip a
waypoint.

**`pathIndex` is runtime progress, never saved.** `progressPath` advances it as
the player passes waypoints in order (and stays out of the way while recovery
drives it). Passed waypoints' markers are destroyed individually
(`refreshPathMarkers`); a full rebuild (`renderPathMarkers`) only happens on
edit, load, loop-wrap and radius toggles.

Two blacklists still feed steering and are different things: `NAV.blockedHeadings`
(a direction, widening arc, 7s) and `NAV.blockedAreas` (a place, 7 studs, 14s,
never recorded while dodging). Neither can cause paralysis.

---

## Telegraph detection

Unchanged in principle: name matching, appearance (`looksLikeTelegraph`), and the
manual picker with name learning. Two additions in 2.2.0:

- **Own attacks.** `isDamageBrick` vetoes `HZ.ownParts[part]` and
  `HZ.ownNames[name]` right after the manual-pick check. Parts get there by
  timing: `noteOwnAction` is called when an Action-priority animation starts on
  our character (`watchOwnAnimations`, main.lua) or when this client fires an
  attack-ish remote (the hook); `markOwnIfRecent` then claims any part that
  appears within `CFG.ownAttackWindow` and `CFG.ownAttackRadius` and learns its
  name unless generic. The auto-clicker and Q/E spam deliberately do **not**
  count as casts. `ownAttackNames` is saved in the config. The **Pick Own FX**
  button marks by hand. A hand-picked telegraph and a learned own-name are
  mutually exclusive; whichever was done last wins.
- **Check order** in `isDamageBrick`: our visuals → fully transparent → manual
  telegraph pick → own → ownership → humanoid ancestor → learned telegraph name →
  CanCollide → heuristics.

**Attack Book + trial runs (2.3.0).** The evidence-based layer. With `Trial
Run` on, every drop in health calls `recordDamageEvent` (hazards.lua): suspects
are the hazards already detected in range plus every part in `HZ.recentParts`
that appeared within `CFG.damageCorrelationWindow` and
`CFG.damageCorrelationRadius`; the closest `CFG.damageSuspectLimit` become or
confirm records in `HZ.attackBook`. A record is plain data (`partSignature`:
name, parent, class, material, shape, colour, size + name/hits/damage/flags),
matched by name when specific, by look when generic (`matchesAttackRecord`),
memoised in `attackMatchCache`. `isDamageBrick` consults it right after the
ownership veto and **before** the creature-part veto - records learned from a
part inside a creature are swing hitboxes and start `enabled = false`. The panel
(`S.refreshAttackBookPanel`, late-bound from ui) renames / toggles / deletes;
`invalidateAttackBook` after any change. Saved as `attackBook` in the config.

**Projectiles (2.3.0).** `HZ.recentParts` (young parts) and every candidate get
`updateMotion` each frame; `getHazardMotion(part)` returns the flat velocity
when it exceeds `CFG.projectileMinSpeed`. **All danger tests go through
`hazardClosestPoint`**, which sweeps the closest point along the next
`CFG.projectileLookahead` seconds of travel - that is the whole prediction.
`looksLikeProjectile` (young + moving + small) sits before the CanCollide rule
in `isDamageBrick`; `buildEscapeCandidates` (nav.lua) adds two candidates
perpendicular to each moving hazard.

**Highlights are always on** with a name tag (`Tag_<id>` BillboardGui) and, for
moving hazards, a predicted-path line (`Pred_<id>` Part, owner tracked in
`HZ.predictionOwner`), all pooled in `HZ.highlightsFolder`.

**Freeze (2.4.0).** A telegraph lasts well under a second, which is not long
enough to point at. `Freeze` copies every detected attack into
`HZ.frozenFolder`: an anchored, `CanQuery = true`, childless clone that outlives
the original, carrying the original's name and parent as the attributes
`DQOriginalName` / `DQOriginalParent`. `resolvePickedIdentity` is what every
picker calls, so picking a copy acts on the real attack's identity. Capped at
`CFG.freezeCap`; cleared on toggle-off and on Destruct.

**Pick Telegraph writes to the Attack Book** (`source = "picked"`), as well as
the learned-names set, so hand picks are renameable and deletable like anything
the trial runs found.

**Low detail (2.4.0), `LD` in core.** `LD.keepNames` is a set of lowercased part
names (saved per map). `lowDetailStep` (run from `worldIndexStep`) sweeps a
bounded slice of the part pool per frame and calls `hidePart` / `restorePart`:
**`Transparency = 1` and no shadow, never destruction**, so collision is
untouched and a hidden floor is still walkable. `shouldKeepVisible` always keeps
kept names, current attack candidates, Terrain/Baseplate, and anything under a
model with a Humanoid. Particles/trails/beams are indexed into `LD.effects` and
switched off with the mode. **`setLowDetailEnabled(false)` must run on Destruct**
(it does) or the dungeon is left invisible after the script is gone.

**Per-map storage (2.4.0), config.lua.** `RT.mapData[code] = { waypath, keep,
macros }` for every map the config knows; the live `NAV.waypath` /
`LD.keepNames` / `MC.macros` are the selected map's entry checked out for
editing. `syncCurrentMapToStore` checks in,
`applyMapFromStore` checks out, `setCurrentMap` does both. `buildConfigTable`
syncs first and writes every stored map, so saving one never drops the rest. A
pre-2.4 top-level `waypath` is adopted into the named map on load. Map codes and
labels are `MAP_CODES` / `MAP_LABELS` in core — **the labels are cosmetic
guesses**, correct them freely.

`Dump GUI candidates to console` (Streamer panel) still exists for GUI structure.
For telegraph problems, ask for the `[Picker]`, `[OwnAttack]`, `[Trial]`,
`[Freeze]`, `[LowDetail]` and `[Map]` log lines.

---

## Attacking and abilities

- Attacks are **always the mouse click** via `VirtualInputManager`. The remote
  hook records the first attack-ish remote this client fires and logs it, but
  the bot never fires it — see 2.2.0 in the changelog for why.
- The `__namecall` hook is allocation-free, lives `CFG.remoteHookLifetime` (3
  minutes) and is restored on Destruct. Its only job is own-attack timing. Set
  `CFG.hookRemotes = false` to never install it.
- Q/E: `useAutoAbilities` sends key events every `CFG.abilityInterval`; with
  `CFG.abilityRadiusEnabled` it only does so while the current target is within
  `CFG.abilityRadius`. `CFG.showAbilityRadius` draws the sphere (a
  `SphereHandleAdornment` in `updateHitboxVisualizer`).

---

## Streamer Mode

Untouched since 1.x. Local cosmetic overlay only — the server, other players and
leaderboards see the real account. See the 1.5–1.9 changelog entries. One known
cost: `discoverStreamerTargets` walks `PlayerGui:GetDescendants()` every 1.5s
while the mode is on; if a stutter is reported *with streamer mode on*, that is
the first suspect.

---

## Config persistence

`DungeonAutofarm_config.json` via the executor's `writefile`/`readfile`, guarded.
Loaded before the UI is built. Saved: combat sliders, ability toggles, ability
radius gate + radius + display, face target, path following, clear radius,
recovery on/off, visual toggles, debug level, streamer fields, learned telegraph
names, **learned own-attack names**, path waypoints as raw coordinates. Manual
binds are instance paths — still the fragile part.

---

## Gotchas (each one cost a release)

**`pcall` with no handler hides everything.** Both loops are `xpcall` +
`debug.traceback`. Keep them that way.

**Assigning `HumanoidRootPart.CFrame` resets the assembly's velocity.** Facing
uses `AlignOrientation`; the CFrame path is a fallback that carries velocity.

**`Workspace:Raycast` returns the first hit, collidable or not.** Use
`castSolid`.

**A rename that hits a table key breaks the parse.** `{ debugLevel = debugLevel }`
— the key must not be renamed. The 2.0.0 split protected keys explicitly. After
any bulk rename run `check.py`; the real parser catches it.

**Per-frame Instance churn is the main frame-rate risk**, and **a full
`GetDescendants()` walk on a timer is the main spike risk**. Both are gone; do
not reintroduce either. Anything that touches every part on the map goes through
the world index's round-robin. Anything drawn is pooled.

**A `__namecall` hook runs on every method call in the client.** Allocate
nothing on its fast path. The `{...}` table in the old hook was a GC-pause
generator.

**Definition order inside a module is load-bearing** (flat `local function`s),
and **module order is load-bearing** across modules. `check.py` catches both.

**`NAV.driving` must be set by any new branch that moves the character toward a
goal**, or the recovery detector will never arm for it (and conversely, never set
it while deliberately holding still or it will fire spuriously).

---

## Working agreement with this user

- **Bump `SCRIPT_VERSION` on every edit** (core.lua), prepend to
  `SCRIPT_CHANGELOG`, mirror in `CHANGELOG.md`, **then `python tools/build.py`**.
  Semver: MAJOR = rewrite/architecture, MINOR = feature, PATCH = fix. Never ask,
  just do it — `check.py` refuses a mismatch anyway.
- They debug by pasting console screenshots. **Read the version tag in the log
  lines** before analysing.
- They propose fixes and the proposals have been good. Take them seriously.
- Explain *why* a bug happened, not just that it is fixed.

---

## Known open items

- **Not yet run in-game after 2.0–2.3.** Everything above passed the parser, the
  name audit and the stub smoke run; the first live session should watch for:
  the `[Index]` "World index ready" line and its counts, `[OwnAttack]` learning
  lines during a fight (and whether they are the right effects), `[Trial]` lines
  during a trial run (are the learned parts the actual attacks, and are the
  auto-names sensible), name tags on the right parts, predicted-path lines on
  real projectiles, `RECOVERY` entries in the movement readout and whether they
  end sensibly, and the frame time. Streamer Mode was not exercised at all.
- **Trial-run blind spots.** A hit from a melee swing with no spawned part
  learns nothing (by design). A hit while a *harmless* fresh part happens to be
  nearby (loot drop, a spell of another player that is not ownership-tagged)
  can learn that part as an attack; X it in the panel. Two suspects per hit is
  the cap.
- **Projectile prediction is linear.** Homing or arcing projectiles are
  predicted along their current velocity only.
- **Low detail hides by part NAME**, so a map that names its walls and its
  treasure chests the same thing cannot separate them. If that bites, the keep
  list would need to become signature-based like the Attack Book.
- **Nothing hidden by low detail is ever re-hidden if the game rewrites its
  Transparency.** The sweep only revisits a part when it comes round the pool
  again (a lap is bounded but not instant), which is fine for static geometry
  and wrong for anything that animates its own transparency.
- **`CFG.hookRemotes`, trial runs and freezing all keep working with the loop
  off**; if a report says "nothing happens with the loop off", check which of
  those three is actually armed before looking further.
- **Macro config size is untested.** A 10-minute macro is roughly 5,000 samples;
  several of those across 14 maps could make the config file large enough that
  the executor's `writefile` becomes noticeable. If it bites, the fix is a
  separate `DungeonAutofarm_macros_<MAP>.json` per map rather than one file.
- **Macro playback does not verify the run.** If a dungeon's layout is
  randomised between runs, or a door needs an event the recording assumed, the
  replay walks the old route and skips its way through. It has no notion of
  "this room is not the room I recorded".
- **Recorded clicks replay at the CURRENT mouse position**, not the recorded
  one — the attack method already worked that way, but for macros it means an
  attack fires wherever the camera happens to point. If the game needs the
  cursor on the target, recording the mouse ray per action is the next step.
- **Navmesh often returns `NoPath` map-wide** in this game. Unresolved. Direct
  walking and now the routed path cover it.
- **Own-attack timing has one known blind spot:** an enemy telegraph landing at
  our feet inside the 0.45s after one of our casts is claimed as ours for that
  spawn. Names only get learned from such a spawn if non-generic; if a real
  telegraph name ever gets learned as ours, `Pick Telegraph` on it fixes it and
  the config keeps the correction.
- **`HZ.billboards` may be large** in a game with many BillboardGuis (item
  drops, NPC names). The scan iterates all of them every 0.35s and does
  `GetDescendants` on each; if the scan line in the log shows a high count and
  frames dip, cache the TextLabel per billboard.
- **Manual binds resolve by path**; `CFG.wallPadding` above ~2.0 still makes
  doorways impassable for the navmesh; visualisers remain the cheapest thing to
  turn off (Debug OFF, then path nodes, then hazard highlights).
