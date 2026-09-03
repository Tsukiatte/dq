# HANDOFF - the rewrite brief (2026-09-02)

Read this first in a new session. It is everything two days of work with Chris
learned, ordered by what matters most. The old code is frozen under
`legacy/4.11.3/` (tag `v4.11.3-legacy`, branch `legacy-4.11`); the previous
architecture handoff (v2.7.0) is kept there as `HANDOFF_v2.7.md`. **Do not
extend the old code. Rewrite.**

## 0. The ask, in Chris's words

> rewrite all the code, do it. keep a copy of the code right now how it is, but
> just rewrite it all. Reading attacks is the #1 thing right now. It simply does
> not know when an attack is active and when it isn't, for the high levels
> anyway. Keep the ui the same but the internals itself are different. Redo
> pathfinding, dodging, make it simpler. Once again, somebody did all this in
> 750 lines. Clearly we're doing too much here. create something new that won't
> get lagged back, or kicked, but tweens and does everything simpler yet better.
> most of them you can literally tell if they're done if the transparency is 0,
> cause it fades out.

His answers to the questions that were asked:

- **The rule:** precast visible = an attack is coming; precast fully faded =
  it is over; the hit lands at the moment it fades. "Except for projectiles,
  no [exceptions]. That should be it but I'm not for sure."
- **Map:** Northern Lands (NL) is the only map that matters right now.
- **Bosses:** never melee a boss - it has a melee too. Fight from ability
  range, about 30 studs. Q and E win the fight.
- **The 750-line script:** he only has a video of it (a Discord recording of
  someone else's bot). Ask him to attach it and go through the frames properly;
  earlier sessions never gave it a good look.
- **Rubber-banding:** he has not been lagged back or kicked himself; people
  who used speed were. Assume a server speed limit that snaps you back.
- **Walk speed** is 16 (the client anticheat's DEFAULT_WALKSPEED).
- At level 191 in NL a hit costs 200M-390M of 262.74M HP. **One hit is a
  death.** The metric is deaths per run, not hits per minute.

## 1. What the game actually does (measured, not guessed)

Every attack is a **Model with an invisible `hitBox` and a visible `precast`**
(both Parts). The hitBox never changes. The precast is the only observable.
`workspace.dungeonName` names the map; enemies live under
`workspace.dungeon.roomN.enemyFolder`; attacks are parented straight to
`workspace`. `ReplicatedStorage.timeSync` (`:GetTime()`) is the server clock
the boss events use. `StreamingEnabled` is on. Enemy Models carry values:
`StringValue enemyStyle` ("boss1"), `IntValue meleeDistance` (4),
`aggroRange` (50), `moveSpeed` (16), `level`, `damage`.

Northern Lands, measured in captures (`game/captures/`, `game/GAME_NOTES.md`):

| attack (Model name) | shape | what shows | hit |
|---|---|---|---|
| `northernMageShot` | hitBox 3.1 x 52 x 60 line, precast 2 x 1 x 60 | nothing for 0.9 s, then the precast APPEARS at 0.35 and lingers ~7 s | at 0.9 s (many certain hits at 0.9-1.0) |
| `spearmanStrikeHitbox`, `northernWarriorLineStrike` | 11 x 4 x 31 line | precast shown, fades | 0.85-0.88 s |
| `northernWarriorCircleStrike` | circle | precast shown | ~0.85 s |
| `firstBossPassiveBeam` | hitBox 8 x 64 x 250 through the boss | NOTHING, ever (precast transparency 1 for its whole 7.0 s life) | certain hits at 0.3-0.4 s. Unknown how long it keeps hurting |
| `firstBossJumpSlam` | hitBox 67 x 67 x 67 cube at the landing, precast 4 x 67 x 67 at 0.55 | shown | 1.8 s (one certain hit) |
| `firstBossCrissCross` (the "spiral") | 15-stud MeshPart, spins 10 deg/frame | a Part, no hitBox/precast | **spawns ON the player** on the remote event, sits at its origin until startTime and HURTS while it sits, then rolls `distance` over `duration`. ~15 on screen at once. This killed him most: 8 of the last 12 real deaths. |

Passive beams are a **sweep**: the fight save parks 18 of them at the arena
centre with yaws 20 degrees apart; the capture saw one every 0.5 s in bursts
of 4 and 13, ten seconds apart, each deleted at 7.0 s. From two beams the third
is known before it exists. At 27 studs the lines have no gap between them; at
50 they have ~10 studs.

Boss remote `ReplicatedStorage.remotes.northernBossSpecficEvents`, client
handler in `game/dumps/nl_fight_save/scripts.txt` (search
`northernBossSpecficEvents`):

- `First Boss Criss Cross Projectile`, `First Boss Seeking Spike`,
  `First Boss Big Spike`: args `{distance, duration, startTime, endTime, cframe}`.
  Body placed at cframe on the event; `CFrame = cframe + look * (distance *
  clamp((t - start) / duration))`; hidden after endTime. Radii ~7.5 / 10 / 20.
- `First Boss Jump Up` / `Jump Down`: a position (smoke). The slam Model
  appears separately.
- Second boss: `Second Boss Big Hitting Ground Spikes` {size, cframe, fireAt},
  `Second Boss Moving Beam` {distance, duration, t0, t1, cframe}.
- Third / bonus boss: orb beam pillars, sideways missile, `Bonus Boss Tall
  Swirly` {colour, fireAt} with `bonusBossColorSafeSpots`.

Other NL things that are NOT attacks and were learned as attacks once:
`workspace.FirstPart` (217-stud invisible cube round the arena),
`workspace.stunParts.<PlayerName>` (stun marker on a player), the parked
beam pool, map parts named generically (`MeshPart`, `Part`, `Ball`, `Ice`).

After a death the character respawns at the room 1 checkpoint ~90 studs from
the boss, inside beam reach and still the spirals' target: a respawn loop.

Aquatic Temple facts (if it ever matters) are in `game/GAME_NOTES.md` section 6.

## 2. The anticheat (client side, all that a client save can show)

`StarterPlayer.StarterCharacterScripts.HumanoidStates` - a 65 KB obfuscated
LocalScript. Deobfuscated logic (from Chris's Discord):

- WalkSpeed above 45 is reset to 16; JumpPower above 60 reset to 50.
- States PlatformStanding, Physics, StrafingNoPhysics, Flying, Swimming are
  disabled; entering one forces GettingUp and zeroes velocity.
- **Anti-hover:** Freefall for more than 3.5 s with |vertical velocity| < 1
  forces velocity (0, -30, 0). A tween that holds the character a hair above
  the floor for 3.5 s gets yanked down.

Server scripts are not in a client save; assume a server speed check
(people using speed got lagged back). BridgeNet2 warns on invalid packets.
Votekick remotes exist. **Rule for the mover: on the floor (raycast +
hip height), walk-speed pace, short tweens or `Humanoid:MoveTo`, never
airborne, never above 16 sustained.**

## 3. What went wrong in the old code (do not repeat)

1. **Learning attack timing by name from hits.** Blame went to the nearest
   part, so windows were poisoned (mage shot 0.9-1.2 s became 0.9-6.9 s;
   beams "armed at 7.0 s" = floor all life, never dodged, arena drawn full of
   boxes). Certain-only blame helped; the honest lesson is that a hit is a bad
   teacher. Read the game instead.
2. **Tracking gated by detection range.** Attack Models were only updated
   while a part was within the dodge's detection radius, so lifecycles and
   probes recorded garbage for anything that started far away. Track every
   attack Model from `workspace.ChildAdded` on, every frame, independent of
   the dodge.
3. **Generic names.** The client renames some boss Models to "Model"
   (Aquatic). Key by shape (hitBox size) or by the event that made it.
4. **Drawing pending attacks** as boxes: Chris cannot tell what the bot
   thinks. Draw only what can hurt, in one colour; a second colour for
   "coming".
5. **Dormancy, hubs, stamps, epochs, spans, long-lived flags** - each fixed a
   real bug and each is a page of code. The new reader should need none of
   them if it reads the precast honestly and takes boss events as exact.
6. **Melee on a boss is impossible** in a sweeping-beam fight. Ability range
   (26-30 studs) worked: 0 hits for 71 s and a kill in the harness.
7. The stuck detector fought the dodge's deliberate holds. One owner of
   movement at a time.
8. Projectiles must be live from the moment they exist, not from their start
   time: the criss cross at 0% of its path was most of the real deaths.
9. `tools/check.py` piped through `tail` hides its exit code; one broken
   commit got pushed that way. Chain without pipes.

## 4. The reader the new code needs

Per attack Model (hitBox + precast), from the moment it appears:

- **Precast visible (transparency < 1) = coming.** The shape is the hitBox.
  Treat it as floor you may cross only if you can be out before it fires,
  otherwise danger. Simplest safe rule: danger while visible.
- **Precast fades (transparency reaches 1, or the Model is removed) = it has
  fired.** Danger for a short linger (0.2-0.3 s), then floor.
- **Mage shot inverts this:** nothing shows for 0.9 s, the precast appears
  AT the hit and lingers 7 s. Rule: for Models whose precast is invisible at
  spawn, the danger is "from spawn until it becomes visible plus a linger",
  and the lingering visible line afterwards is floor. Verify with a probe.
- **Passive beam shows nothing at all.** Danger from spawn (hits at 0.3-0.4
  s) for a short pulse (hypothesis: ~1 s), then floor; predict the next two
  beams of a sweep from the last two headings (20 degrees per 0.5 s).
- **Projectiles from events:** exact bodies on exact schedules, live from
  the event, spawn point included.
- **First thing to build is a standalone probe** (200 lines): watch every
  Model with a hitBox under workspace from ChildAdded, sample precast
  transparency at 20 Hz, log hits from the Humanoid's HealthChanged with the
  Models enclosing the root at that instant. One NL run gives the table
  above with no guesses left. The 4.11.4 probe was gated by detection range
  and mostly logged at removal time; do not reuse it.

## 5. Movement and dodging (simpler)

- One danger field: for a point and a time, max over attacks (hitBox
  oriented-box distance, with the timing above), projectiles (path position
  at that time), enemies (their melee reach, from `meleeDistance`).
- Candidates: a ring of ~24 directions x 3 distances (4, 9, 14 studs),
  scored by the field sampled along the line and at arrival, plus a pull
  toward the standoff spot. Take the best; re-decide 10-20 times a second;
  never commit to a spot whose line went bad.
- Floor check per candidate: one downward raycast; wall check: one Blockcast.
- Mover: tween the root CFrame along the floor at 16 studs/s (or
  Humanoid:MoveTo when not dodging); keep Y from the floor raycast + hip
  height; tweens no longer than ~1 s each.
- Pursuit: straight line to the standoff point; if the Blockcast says wall,
  PathfindingService once, then follow waypoints; re-plan on block. Standoff:
  mobs at body + meleeDistance, bosses (`enemyStyle` contains "boss") at
  `bossStandoff` 26 inside `abilityRadius` 30. During a beam burst hold a
  ring at ~50 and come in during the 10 s gaps.
- Abilities: Q/E while the target is inside 30 studs; M1 only if inside melee
  reach anyway.

## 6. Keep the UI

`src/uikit.lua` is "perfect" (Chris). `src/ui.lua` is the layout: islands
Pathfind / Dodge / Attacks / Capture, sliders (Commitment, Pursuit probe,
attack range, ability radius), Save capture / Clear, Select attack, Draw zone,
mode Pathfind/Dodge, Autofarm toggle. Keep the same panels and names; bind
them to the new internals. Player-visible strings stay as they are.

## 7. The Studio harness (optional, semi-realistic)

Roblox Studio has the mid-fight NL save open (`C:\Users\Chris\Downloads\place
85776757589518 Level(2).rbxl`) and the Studio MCP is registered in
`C:\Users\Chris\Documents\Claude\.mcp.json` (`Roblox_Studio`, tools
`mcp__Roblox_Studio__*`; `studio_id` changes when the place reloads - call
`list_roblox_studios`). `execute_luau` (Edit / Client / Server) times out
near 60 s: keep in-code waits under 50 s.

- `tools/studio_install.lua` installs `StarterPlayerScripts.DQHarness`
  (one ModuleScript per `src/*.lua` + the Loader from
  `tools/studio_loader.lua`). `tools/studio_bosssim.lua` is the fight
  simulator (`ServerScriptService.DQBossSim`): boss dummy with the real
  enemy values, 3000 HP, rebuilt on death; beam sweeps in bursts;
  mage shots / strikes from posts; criss cross volleys ROUND THE PLAYER
  (`DQSimCrissCount`, `DQSimCrissSpread`); projectiles over the real remote on
  the game's clock; damage with 0.5 s i-frames. Attributes on `workspace`:
  `DQSimEnabled`, `DQSimVisible`, `DQSimBeamHurt` (pulse | long),
  `DQSimBurstGap`, `DQSimRate`, `DQSimWalkSpeed`, `DQSimBossHP`,
  `DQSimAbilityReach/Damage/Cooldown`; counters `DQSimHits`, `DQSimDamage`,
  `DQSimCasts`, `DQSimSwings`, `DQSimBossKills`, `DQSimBossHP`.
- Loader query (`PlayerScripts.DQHarness.DQHarnessQuery:Invoke(what, arg)`):
  `danger`, `detected`, `arming`, `watch <Model>`, `paths`, `hitlog`,
  `lifelog`, `delays`, `hubs`, `status`, `set {path,value}`, any dotted `S`
  path. State JSON in `DQHarnessState`. The Loader also wires the harness's
  swing/ability hooks to the sim and enables Q/E at radius 30.
- Refresh after a push: fetch by COMMIT SHA
  (`raw.githubusercontent.com/Tsukiatte/dq/<sha>/src/<name>.lua`); the
  branch URL is CDN-stale for minutes. The Loader keeps a SHIM header for
  executor globals before each module source. A rewrite with different module
  names needs the Loader's ORDER list and the installer updated.
- **Caveats (Chris):** the sim has about 5x the attack density of the real
  fight, and its spirals spawning on the player is not realistic. The beam
  hurt window is a guess (pulse). Use it to test mechanics, not to tune
  numbers.
- Best harness results with the old code: 0 hits in 71 s at ability range,
  a boss kill with 30 casts and 3 hits, ~1-2 hits per minute in blind mode.
  The real game still killed him. The harness is not the game.

## 8. Where everything is

- Repo: `C:\Users\Chris\Documents\GitHub\dq` (GitHub `Tsukiatte/dq`, branch
  `main`). Build: `python tools/check.py && python tools/build.py` (do not
  pipe check.py through tail - it hides the exit code). Bundle
  `DungeonAutofarm.lua`; Chris's loader pulls it from `main`.
- Rules from Chris that stand: bump the version + `CHANGELOG.md` + the
  in-script `SCRIPT_CHANGELOG` on every edit; commit with the trailer
  `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`; push.
- Old code: `legacy/4.11.3/` (src, bundle, tools, changelog, HANDOFF_v2.7).
- Game facts: `game/GAME_NOTES.md` (sections 1-6), `game/attack_models.txt`
  (246 attack Models with precast/hitBox properties), `game/remotes.txt`,
  `game/enemy_attack_names.txt`, `game/player_ability_names.txt`.
- Place dumps: `game/dumps/nl_fight_save/` and
  `game/dumps/aquatic_temple_save/` (`scripts.txt`, `tree.tsv`); the rbxl
  files themselves in `C:\Users\Chris\Downloads\` and
  `C:\Users\Chris\AppData\Local\Potassium\workspace\`. `tools/rbxl.py
  <file.rbxl> <outdir>` dumps a new one.
- Captures the script writes: `C:\Users\Chris\AppData\Local\Potassium\
  workspace\DungeonAutofarm_attacklog.txt` (overwritten on each save - copy
  it out). Kept copies in `game/captures/`.
- Executor: Potassium. Config file next to the capture. Executor globals the
  script uses: `writefile/readfile/isfile/listfiles`, `request`,
  `getgenv`, `setclipboard`, `VirtualInputManager` for keys/clicks.
- Memory for future sessions: `C:\Users\Chris\.claude\projects\
  C--Users-Chris-Documents-Claude\memory\dq-dungeon-autofarm.md`.

## 9. Plan for the first new session

1. Ask Chris to attach the 750-line bot video and study it frame by frame:
   how it stands, how far from the boss, what it dodges, what it ignores.
2. Build the standalone probe (section 4) and have him run one NL fight with
   it. Fill the table. Only then write the reader.
3. Write the new internals (`core`, `reader`, `field`, `dodge`, `mover`,
   `pursuit`, `bosses`, `main`); reuse `uikit.lua` and adapt `ui.lua`.
   Budget: under 5,000 lines total including the UI; the internals under
   2,500. Keep `tools/check.py` / `build.py` (update `tools/modules.py`'s
   ORDER) so the bundle and the harness keep working.
4. Test in the harness for mechanics, then real NL captures for truth. The
   metric that matters is deaths per NL run.
