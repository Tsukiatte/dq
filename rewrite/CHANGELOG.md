# Dungeon Autofarm 5.1 (rewrite) — Changelog

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

