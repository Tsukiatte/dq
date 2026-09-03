# Dungeon Autofarm 5.1 (rewrite) — Changelog

## 5.1.71 - 2026-09-03 - "Home and the crystals"

- Core: profile flags `orbs` / `home`; `S.bobCrystal(colour)`, `S.bobCrystalCentroid()`; `orbLeadBehind` 12, `bobHomeWeight` 0.02. Field: home pull for Bob. Brain: step 0b leads the nearest orb to the far side of its crystal.

## 5.1.70 - 2026-09-03 - "Remembered"

- Reader tick: a record whose Model is gone is kept on `lastCFrame` until `untilAt`.

## 5.1.69 - 2026-09-03 - "Two bosses, two profiles"

- Core: `BOSS_PROFILES` / `S.bossProfile`. Field: arena pull gated on the profile. Brain: fan standoff gated on the profile.

## 5.1.68 - 2026-09-03 - "Verdicts"

- Core: horizontal beam first 0.6; spread slim 4.0; `castSafeGrace` 1.2; `orbBubble` 14. Reader: orb bubble on bare parts; chain line width capped at three steps of growth. Brain: casts gated on safety. Recorder: `busyCasting` in the trace.

## 5.1.67 - 2026-09-03 - "In, every time"

- Field: arena pull applies during the fan with `fanRadius` as the edge. Brain: boss approach at `tweenEscape` beyond band+25.

## 5.1.66 - 2026-09-03 - "Off the rocks"

- Core: `fanRadius` 85, `dodgeSafeWorst` 0.2, `blinkDoubleGap` 2.0. Reader: fan reflex only from inside radius-12. Field: small-spot penalty on hot ground; second blink inside the cooldown (`RT.lastBlinkDouble`).

## 5.1.65 - 2026-09-03 - "Per slot"

- Reader: `ourAbilityNames`, `noteOurProjectile`, `RD.abilitySlots[slot] = { name, cap, reach }`; cached geometry for anchor-less records. Brain: `RT.castQueue`; standoff from the least ranged slot; blocked travel goes via the spot. UI: sliders to 80, per-slot caption. Core: `autoStandoffMax` 70, circle pad 10.

## 5.1.64 - 2026-09-03 - "Two studs wider"

- Bob beam seeds `slim` 2.5, `slimShoulder` 1.0; blink bare reach 2.5 (both checks).

## 5.1.63 - 2026-09-03 - "Not into the wall"

- Field: candidate openness (`dodgeWallLook` 24, `dodgeWallWeight` 0.05). Brain: back-off direction search over seven headings by free distance.

## 5.1.62 - 2026-09-03 - "See it"

- Field: `DG.evalStats` and `DG.chosen`. Tools: `recorder6.lua` (10 Hz trace, death verdicts, movement effectiveness, blink/reflex logs) and `poll6.lua`.

## 5.1.61 - 2026-09-03 - "Slam reflex"

- Reader: `First Boss Jump Down` sets `RT.reflex` (centre, radius 44, 3.2 s). Brain: step 0 flees the reflex centre at `tweenEscape`, trying 0/35/70 degrees either side through `stepSafe`.

## 5.1.60 - 2026-09-03 - "Measured at the cast"

- Reader `noteGeyser` uses `RT.lastCastPos` / `RT.lastCastTargetPos`; on-target within 8 studs = reach, short along the aim = cap; a reach past the cap clears it.

## 5.1.59 - 2026-09-03 - "No thanks, bonus boss"

- Lobby: answers `bonusBossPlayerVote` (`bonusBoss`, `bonusVoteDelay`); `S.runComplete()`.
- Brain: `run complete` idle instead of re-walking rooms. UI: "Stay for the bonus boss" toggle (persisted).

## 5.1.58 - 2026-09-03 - "Range, measured"

- Reader: `noteGeyser` sets `RD.abilityRange` (cap) / `RD.abilityReach`. Brain: `RT.lastCastAt` / `RT.lastCastTargetDist`; `S.abilityReach()`; `standoffFor` uses `abilityRange + autoStandoffOffset` when `autoStandoff`.
- Field: `BLINK_BOSSES` whitelist (Champion, Bob) plus mob fights.
- Core: `autoStandoff` true, `autoStandoffOffset` 2. Config persists `autoStandoff`. UI: toggle and a live caption in Standing.

## 5.1.57 - 2026-09-03 - "Inside the arena, hop sooner"

- Field: `graceHere` includes moving bodies; grace computed every tick; blink gate is `grace <= blinkWindow`; walk margin 0.35; destination clear for 1.0 s; `dodgeArenaWeight` 0.04 (+2 past band+45) for boss targets.
- Core: `blinkWindow` 0.6, `blinkCooldown` 5, `blinkMax` 8, slam seed first 1.5. UI slider to 8.

## 5.1.56 - 2026-09-03 - "Back inside"

- Brain: fan standoff override removed. Core: passive beam seed back to 3.5 s, no slim.
- Reader: `First Boss Jump Up` places a `slam soon` zone (36) at the player, firing in 3.0 s.

## 5.1.55 - 2026-09-03 - "The old HUD"

- UI: HUD rebuilt after 4.12's (chip: name | build | fps; card: Playtime, Status, Ping; hint; Autofarm pill).
- UIKit `window`: header from y=0 with the frame radius plus a square filler; accent is a 3 px pill inset 4 px; body ends `RadiusLg` above the bottom.

## 5.1.54 - 2026-09-03 - "Never on a live box"

- Field: boxes may carry `weight`; `score` returns the endpoint danger; lethal-endpoint candidates cost +100; kept target dropped on `spot closed`; mob retreat via `dodgeMobRetreat`.
- Reader: `circle line` weight 0.5; `chain()` both directions on the first circle.
- Brain: `DG.approach.isBoss`. Draw: weighted boxes at 0.85 transparency.

## 5.1.53 - 2026-09-03 - "A quarter second"

- Mob seeds: `last` 1.5 with `holdFull`; `fadeLinger` 0.55.
- `firstbosspassivebeam` last 2.0, `slim` 1.5; `slim` is now the reach in studs (0.8 for Bob's beams). `secondbossspreadbeam` 0.9-2.5. Fan standoff 95 (the standoff override had been lost in 5.1.26).
- Big spike path and mesh half sizes +8. Stopped bare projectiles are hazards for 1 s (`stillSince`).
- Draw: moving bodies coloured by stage; sweep strips only for non-`part` kinds.

## 5.1.52 - 2026-09-03 - "Sideways"

- Seeds may set `slim`; `slimReach` 0.8 / `slimShoulder` 0.3 replace the 3 + 1.5 padding for `secondbosshorizontalbeam` and `secondbossspreadbeam`.
- Reader: `noteCircle` adds a `circle line` zone (400 long, chain width) from the first circle; per-step `circle next` zones only once the direction is measured.

## 5.1.51 - 2026-09-03 - "Cross the lane"

- `stepBlockAt` 0.6 replaces `dodgeMoveAt` in `stepSafe`.

## 5.1.50 - 2026-09-03 - "Bob, read properly"

- Reader: `noteCircle` predicts nine circles of a chain as `circle next` zones.
- Reader: `RD.walls` tracks `secondBossMovingBeam` models by their balls; the `Second Boss Moving Beam` remote handler is removed.

## 5.1.49 - 2026-09-03 - "Danger first"

- Field: `dodgeDangerWeight` 3.0 multiplies the graded danger in `costOf`.

## 5.1.48 - 2026-09-03 - "Bob's circles"

- `secondbosscriclehitbox` seed first 0.6, last 1.6, pad 3; reader applies seed pads to box sizes.

## 5.1.47 - 2026-09-03 - "The whole lane"

- Field: `pathLaneDanger` (0.5) along the remaining path ahead of a moving body.
- Draw: the sweep strip runs to the end of the path.

## 5.1.46 - 2026-09-03 - "Stay armed"

- Reader: `RD.leashArmed` mirrored in `_G.DungeonAutofarmLeashArmed`.

## 5.1.45 - 2026-09-03 - "Sweep the floor"

- Draw: `sweepForeign` removes non-Hazards children of the visuals root every 3 s.

## 5.1.44 - 2026-09-03 - "Short bursts"

- Mover: `boostMaxRun` 1.5 s then `boostRest` 1.2 s; brain approaches at walking speed.

## 5.1.43 - 2026-09-03 - "Which way is up"

- Field: `boxDepth` picks the vertical axis from the CFrame.

## 5.1.42 - 2026-09-03 - "The volley line"

- Reader: `noteVolley` adds a `volley next` zone along the march of a mage volley.

## 5.1.41 - 2026-09-03 - "Remember the room"

- Brain: `reachedOrder` mirrored in `_G.DungeonAutofarmReached`.

## 5.1.40 - 2026-09-03 - "Walls are walls"

- Field: the target model is no longer excluded from the walkability sweep; `RT.stalledFor` > 0.6 drops the current spot.

## 5.1.39 - 2026-09-03 - "Look before stepping"

- Brain: `travel` checks `stepSafe` before each drive; blocked steps stand still.

## 5.1.38 - 2026-09-03 - "In the fight only"

- Blink requires `DG.approach` within 70 studs.
- Reader: bare projectiles still for 0.6 s are spent.
- Draw: a moving body is drawn as the body, with the coming second's sweep as a faint strip.

## 5.1.37 - 2026-09-03 - "No jumping"

- Mover: stall no longer jumps; `RT.stalledFor` exposed.

## 5.1.36 - 2026-09-03 - "Land"

- Blink: standing height from HipHeight, refuse when mid-air, downward nudge after the write, rings 4/6, `blinkMax` 6.
- Draw: outline colour initialised.

## 5.1.35 - 2026-09-03 - "Rarer"

- `blinkCooldown` 8.0; `blinkPerMinute` 3 replaces the per-10-s cap.

## 5.1.34 - 2026-09-03 - "Lanes are traps, gaps are safe"

- Passive beam `last` 3.5 s; `dodgeShoulder` 1.5.

## 5.1.33 - 2026-09-03 - "Commit"

- Field: leash is a hard edge (danger 1 past `leashRadius` - 4), no shoulder.
- Field: while escaping, the target is kept until reached unless a candidate is clearly better (danger lower by 0.25).
- `strafeSpeedFraction` 1.0.

## 5.1.32 - 2026-09-03 - "Outlines"

- Draw: SelectionBox outline per hazard part, coloured by stage; `hazardTransparency` 0.6.

## 5.1.31 - 2026-09-03 - "Hold the beam, hop last"

- Reader: seeds may set `holdFull`; the passive beam holds its 2.4 s window through the precast fade.
- Blink: walk-first gate, `blinkCooldown` 3.0, `blinkPer10s` 2, destination clear through 1.5 s and 26+ studs from any mob.
- Brain: the back-off line is checked with `stepSafe`; when it crosses an attack the field's spot is used instead.

## 5.1.30 - 2026-09-03 - "A second clear"

- `blinkTarget` samples the bare metric at 0, 0.25, 0.5, 0.75 and 1.0 s; tie-break by graded danger at 0.6 and 1.2 s.

## 5.1.29 - 2026-09-03 - "Bare check"

- `dangerAt` takes optional reach/shoulder overrides; `blinkTarget` accepts any spot outside the boxes (radius 1.2, no shoulder) now and at 0.5 s, tie-broken by the graded danger at 0.6 s.

## 5.1.28 - 2026-09-03 - "Blink"

- Field: `blinkTarget` + reflex in `decide` (`blink`, `blinkMax` 8, `blinkWindow` 0.45, `blinkCooldown` 1.2). Floor-verified destination, clear sweep, headroom, never airborne, velocity untouched.
- UI: toggle and distance slider in Dodge; HUD shows blink count. Recorder/poll carry blink counts.

## 5.1.27 - 2026-09-03 - "Reach"

- `abilityRadius` 42.

## 5.1.26 - 2026-09-03 - "Abilities only"

- `mobStandoff` 34 replaces melee/ranged standoffs; `meleeMobMaxReach` 16; `autoAttack` off by default.
- Brain backs straight off any target inside standoff minus 6 (12 for the boss).
- Field: a melee mob's swing reach (extent + meleeDistance + 2) is danger 1; the `meleeBuffer` (10) band past it is soft.
- UI: one "Mob standoff" slider; config persists `mobStandoff`.

## 5.1.25 - 2026-09-03 - "Armed"

- Reader arms `RD.leash` once inside 110 studs of the Champion (sticky per boss); the field applies it to everything outside `leashRadius`.

## 5.1.24 - 2026-09-03 - "Trace"

- `bossStandoff` 38; `RT.configTrace` records load/save history.

## 5.1.23 - 2026-09-03 - "Chains"

- `noteBeam` matches interleaved 20-degree chains (dt 0.08-0.8 s), predicts two lanes per chain, prunes predictions after 0.5 s.

## 5.1.22 - 2026-09-03 - "Further out"

- `bossStandoff` 48.

## 5.1.21 - 2026-09-03 - "Band"

- Leash danger only within 40 studs outside `leashRadius`.
- `rangedStandoff` 22.

## 5.1.20 - 2026-09-03 - "Burst early"

- `RT.moveBoost` follows `DG.dangerHere` (dwell-aware) instead of `here0`.

## 5.1.19 - 2026-09-03 - "Leash"

- Reader sets `RD.leash` for the Midgardian Champion; the field scores everything past `leashRadius` (122) as lethal.

## 5.1.18 - 2026-09-03 - "No retreat"

- Brain: boss standoff no longer depends on the beam fan (`RD.fanUntil` stays informational).
- Passive beam timing seed `first` 0.3.

## 5.1.17 - 2026-09-03 - "Lanes"

- Reader: `noteBeam` predicts the next two sweep lanes as `beam next` zones; four beams within 0.5 s set `RD.fanUntil`.
- Reader: `First Boss Jump Down` (Vector3) adds a 67-stud `slam soon` zone 2.5 s ahead.
- Brain: boss standoff becomes 135 during the fan; a `back off` branch walks straight out when well inside the band.
- `bossStandoff` 35, `dodgeReach` 30, far scales 1.6 / 2.5.

## 5.1.16 - 2026-09-03 - "Inside the room"

- `nextRoom`: reached = inside the room's bounding box (cached) or within 25 studs of its anchor.
- `dodgeInterval` 0.016: the field decides every frame.

## 5.1.15 - 2026-09-03 - "Tuning is not a setting"

- Dodge tuning keys removed from the persisted set.

## 5.1.14 - 2026-09-03 - "Look further ahead"

- `dodgeDwell` 1.5 (was 0.6).

## 5.1.13 - 2026-09-03 - "Margin"

- `dodgeMargin` 2.0.

## 5.1.12 - 2026-09-03 - "Settings, not constants"

- `config.lua` persists a whitelist of UI-exposed keys; tuning constants follow the code defaults.

## 5.1.11 - 2026-09-03 - "Soft zone"

- Melee-mob proximity is a soft preference (max 0.5), `meleeBuffer` 4; attack boxes decide.
- `dodgeMargin` 1.5 (body radius): a beam killed 1.5 studs outside its box.

## 5.1.10 - 2026-09-03 - "Forward only"

- `nextRoom` tracks the furthest room order reached; rooms passed at range count as behind.

## 5.1.9 - 2026-09-03 - "From the announcement"

- Moving bodies (criss cross, big spike, seeking spike, projectiles) are danger from the moment they are known, at their origin until their start time; no 0.4 s lead gate.
- Remote paths ignore height (`ground`); drawn at the character's floor.
- Field floor check allows a rise of 0.2 studs per stud of distance (ramps).
- Brain plans walks at the Humanoid's WalkSpeed; the burst is only an escape.

## 5.1.8 - 2026-09-03 - "On its own legs"

- Third kick, server-side, during ordinary driving. The mover writes no positions: every move is a Humanoid walk; the escape burst is a temporary WalkSpeed of `tweenEscape`, restored after. Stalls against a wall for half a second hop.
- `tweenWalk` is now the planning speed only (default 16).

## 5.1.7 - 2026-09-03 - "Not a wall"

- The target's model is excluded from the spot walkability sweep; the boss's body was blocking every far escape from the slam.

## 5.1.6 - 2026-09-03 - "Walk"

- The field's spot outranks travel only while danger here is present now or the brain's next step is unsafe when crossed (`stepSafe`); future danger alone no longer stops a clean walk.

## 5.1.5 - 2026-09-03 - "Pull"

- The field's pull toward the target band applies at every distance (0.6x beyond the last 30 studs); the strafe bias only inside. Restores the 5.1.0 approach.

## 5.1.4 - 2026-09-03 - "Travel"

- Travel goes straight when the swept line is clear; otherwise paths, replanned at most every 4 s or when the target moved 20 studs, resuming past waypoints behind the character. A moving boss had caused a replan every half second and a shuffle on the spot.
- Mover counts its exit branches (`MV.counts`).

## 5.1.3 - 2026-09-03 - "Room first"

- Target picker: mobs within 150 studs before any boss; a boss only when nothing is nearer. Travel with no progress for 2.5 s skips a waypoint.

## 5.1.2 - 2026-09-03 - "Never a jump"

- Mover: step capped at a 30 fps frame regardless of the real delta; a frame over 0.12 s writes nothing; nothing is written while airborne or over a missing floor. After an anticheat kick that followed lag, a fall through the floor and a jump.
- Draw: 10 Hz, at most 60 boxes, within 130 studs.

## 5.1.1 - 2026-09-03 - "Back out"

- Melee mobs: danger radius `meleeBuffer` 8 past the swing, standoff 20, retreat instead of circle when inside the band.
- Escape spot kept until reached or its line closes; far look to `dodgeFarScale2` 4x; `dodgeOutwardWeight` prefers spots away from the target when here is hot.

## 5.1.0 - 2026-09-03 - "Lean"

- Rewrite. See REWRITE.md at the repo root.

