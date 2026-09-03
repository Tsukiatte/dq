# Dungeon Autofarm 5.1 (rewrite) — Changelog

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

