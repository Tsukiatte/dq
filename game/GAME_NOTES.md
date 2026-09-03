# What the game actually does

Read out of `place 77649408247578 Northern Lands Dungeon Quest Reborn.rbxl`
(a client-side `saveinstance` dump: 47,875 instances, 787 scripts, ~2 MB of
decompiled source). Everything below is from the game's own code, not inferred
from watching parts appear.

The headline: **the game tells the client where every ground attack will land
and exactly how long until it lands.** We have been reverse-engineering a
broadcast we were always able to just listen to.

---

## 1. Ground attacks: `precastHitbox`

`ReplicatedStorage.modules.PrecastHitbox` is required at startup by
`StarterPlayer.StarterPlayerScripts.ClientInitialize`. It listens on a
**BridgeNet2** bridge named `precastHitbox` and builds the telegraph part
locally from a payload the server sends to all players.

Payload, keyed by `BridgeNet2.ReferenceIdentifier("action")`:

| field | meaning |
|---|---|
| `action` | `"Cube"` or `"Circle"` |
| `cframe` | Cube only. Full orientation, already positioned. |
| `size` | Cube only, `Vector3`. |
| `position` | Circle only, `Vector3`. |
| `radius` | Circle only, number. The part is built `Vector3.new(0.5, r*2, r*2)` as a `Cylinder`. |
| `delayUntilAttack` | **Seconds from `startTime` until the hit lands.** |
| `startTime` | `workspace:GetServerTimeNow()` when the server cast it. |
| `properties` | Table of Part property overrides applied after construction. |

So time to impact is exactly:

```lua
local elapsed = workspace:GetServerTimeNow() - startTime
local timeToImpact = delayUntilAttack - elapsed
```

**This removes the entire "learn hitDelay from trial runs" plan.** No learning,
no averaging, no guessing. The number is handed to us before the attack exists.

### Why appearance scoring struggles with these

Straight from `createHitbox` and `tweenHitbox`:

- The part is created with `Transparency = 1` — **fully invisible** — and only
  tweens to `0.1` over `0.15 - elapsed` seconds.
- `CanQuery = false`, `CanTouch = false`, `CanCollide = false`, `Anchored = true`,
  `Material = Neon`.
- It is parented **directly to `workspace`**, not into a folder.
- After the hit it tweens out and is destroyed roughly **0.35 s** later
  (`0.1` fade in, `0.15` hold, `0.1` fade out, `0.1` wait, then `Trove:Clean()`).

An invisible, unqueryable part with no distinguishing parent is close to the
worst case for a scorer. It is trivial for a listener.

### How to hook it

BridgeNet2 is a plain ModuleScript in ReplicatedStorage, so we require the same
module and connect to the same bridge. No packet parsing, no namecall hook.

```lua
local RS = game:GetService("ReplicatedStorage")
local BridgeNet2 = require(RS.Utility.BridgeNet2)
local bridge = BridgeNet2.ReferenceBridge("precastHitbox")
local ACTION = BridgeNet2.ReferenceIdentifier("action")

bridge:Connect(function(data)
    local kind = data[ACTION]              -- "Cube" | "Circle"
    local eta  = data.delayUntilAttack
                 - (workspace:GetServerTimeNow() - data.startTime)
    -- data.cframe + data.size, or data.position + data.radius
end)
```

Note `ReferenceIdentifier` — BridgeNet2 compresses string keys, so the action
key is not the literal string `"action"` on the wire.

---

## 2. Enemy attack vocabulary

`ReplicatedStorage.enemyProjectiles` holds **307** enemy attack visuals, by
name. `ReplicatedStorage.projectiles` holds **251** *player* ability visuals and
`ReplicatedStorage.abilities` holds the **136** player abilities as Tools.

That split is the classification the scorer has been trying to infer:

- A name under `enemyProjectiles` **is** an enemy attack.
- A name under `projectiles` or `abilities` **is ours** — never dodge it.

Saved as `enemy_attack_names.txt`, `player_projectile_names.txt`,
`player_ability_names.txt`.

### Safe-spot mechanics (important, and we currently get these backwards)

Several bosses invert the rule — there is one place you *must* stand:

```
cyanSafeZoneMarker      purpleSafeZoneMarker     yellowSafeZoneMarker
safeSpotCircle          thirdBossSafeSpot        thirdBossSafeSpots
thirdBossMassSafeSpotCircles                     thirdBossMemorySafeZone
thirdBossMemoryDamageZone
```

A dodge grid that only knows "avoid red" will walk out of the safe circle and
die. These need to be recognised as *attractors*, not hazards.

### Precast / indicator markers

```
preCast  spikePrecast  flameLashPrecast  bossRiflePreCast
firstBossLaserPrecast  firstBossOrbPrecastLine  bonusBossFlamePreCast
hitIndicatorIceAOE  iceBeamIndicator  minionIndicator  arrowDownGui
```

These announce an attack without being the damage — exactly the case the
hand-drawn zone tool was built for.

---

## 3. Dungeon and run state, already on the client

Plain values under `Workspace`, no remote needed:

| value | type | use |
|---|---|---|
| `dungeonName` | StringValue | **Automatic map detection.** Matches `MapPlaces` names exactly. |
| `currentWave` | IntValue | Wave number. |
| `dungeonProgress` | StringValue | Run progress. |
| `dungeonStarted` | BoolValue | Run has begun. |
| `timeLeft` | IntValue | Countdown. |
| `tier`, `hardcore`, `vipServer`, `start` | | Run configuration. |
| `enemies` | Folder | **Enemy container** — scan this, not all of Workspace. |
| `Map` | Folder | Dungeon geometry. |

`ReplicatedStorage.Utility.MapPlaces` lists every dungeon name. All fourteen of
our map codes are there verbatim: Desert Temple, Winter Outpost, Pirate Island,
King's Castle, The Underworld, Samurai Palace, The Canals, Ghastly Harbor,
Steampunk Sewers, Orbital Outpost, Volcanic Chambers, Aquatic Temple,
Enchanted Forest, Northern Lands — plus Egg Island, Wave Defence, Boss Raid,
Tutorial, and three unreleased (Gilded Skies, Oni Dungeon, Krampus).

---

## 4. Other remotes worth knowing

`ReplicatedStorage.remotes` holds 184 entries. Relevant ones:

- `abilityCast`, `abilityUsed`, `abilitySetSwapped` — our own ability traffic.
  Better own-attack detection than watching animations.
- `bossSpecficEvents` — `(eventName, cframeOrTarget)`. Observed names:
  `"Spawn Minion"`, `"Minion Explosion"`, `"Second Boss Mark Target"`.
- `aquaticBossSpecficEvents`, `easterIslandBossSpecficEvents`,
  `enchantedBossSpecficEvents` — per-dungeon variants.
- `getDungeonStats`, `getData`, `Teleport` (RemoteFunction).

Each of the 136 abilities also has its own `abilityEvent` and `showOnClient`
RemoteEvent under `ReplicatedStorage.abilities.<Name>`, plus `cooldown`,
`cooldownLength`, `damage`, `levelReq`, `abilitySlot`, `abilityType`,
`spellAnim`. Real cooldowns and real ability radii are readable, no timing
guesswork.

---

## 5. What was NOT in the dump

- **No server code.** `ServerScriptService` and `ServerStorage` are empty — this
  is a client-side save. So how the server validates a hit is still unknown, and
  so is any server anti-cheat.
- **No client anti-cheat found.** The only `WalkSpeed` writes are Cmdr's freecam
  command (`__fc_walkspeed`).
- `Workspace.enemies` is empty here because this is the **lobby** place. Dungeons
  are separate places (`MapPlaces` / `PlaceManager`). Enemy model structure needs
  a dump taken inside a dungeon.
- Amusingly, `Workspace.DungeonAutofarmVisuals` is in the dump — the save was
  taken with our own script running.

---

## 6. What this changes, in order of value

1. **Listen to `precastHitbox` instead of scoring parts.** Exact geometry, exact
   time to impact, before the part is visible. Makes time-aware safety free and
   makes the freeze tool, most of the scorer, and much of the recommendation
   panel unnecessary for ground attacks.
2. **Pre-seed the Attack Book** from `enemyProjectiles`, and permanently veto
   everything under `projectiles` / `abilities` as our own.
3. **Read `Workspace.dungeonName`** and set the map automatically.
4. **Scan `Workspace.enemies`** instead of all of Workspace.
5. **Teach the grid about safe spots** — the listed markers are attractors.
   Without this, boss fights with a safe circle are actively worse with dodging
   on than off.
6. **Use `abilityCast` / `abilityUsed`** for own-attack detection, and the real
   `cooldown` values for ability timing.

Projectiles fired by enemies are still physical parts, so the existing sweep
stays useful for those; `precastHitbox` covers the ground-telegraph family.


## 5. What the captures and the Studio harness taught (2026-09-02)

Ground truth from two Northern Lands captures, the mid-fight place save, and
a Studio recreation of the Midgardian Champion room (`tools/studio_install.lua`,
`tools/studio_bosssim.lua`).

- **Every attack is a Model with an invisible `hitBox` and a `precast`.** The
  hitBox never changes. The precast is the only observable, and its meaning
  is per attack: for the mage shot it *appears* at the hit (0.9 s after the
  Model), for the boss beams it is never visible at all, for most bosses'
  attacks it fades *at* the hit (client handlers in `mapSpecificLocals`).
- **Timing must be learned from being hit** (`RT.armSpans`: first and last
  age the attack hurt), because the visuals do not say. A window makes the
  attack floor before `first - lead` and floor again after `last + linger`.
  Attacks that hit after their fade are `armLongLived`: fade does not end them.
- **`workspace.FirstPart`** is a 217-stud invisible cube around the boss arena.
  **`workspace.stunParts.<PlayerName>`** is a stun marker riding on a player.
  **14 `firstBossPassiveBeam` Models are parked at the arena centre** for the
  whole fight. None of these is an attack; all three were once learned as one.
- **The boss is a hub, and the beams are a sweep.** The fight save parks 18
  `firstBossPassiveBeam` Models at the centre with yaws 20 degrees apart
  (18.3, 38.3, 58.3 ... 178.3); the capture saw them appear every 0.5 s in
  bursts of 4 and 13, ten seconds apart, each deleted at 7.0 s. So a burst is
  a line sweeping round the boss 20 degrees per half second, and from two
  lines the third is known before it exists. How long each line HURTS is the
  one thing no capture has shown (the harness runs both hypotheses:
  `DQSimBeamHurt` pulse / long). Go in only while the hub is quiet.
- **Blame the attack that encloses you**, never the nearest part: a beam
  spawned through you a moment ago is nearer than the one burning you.
- **`StreamingEnabled` is on.** The saved place has no camera controller and
  loads characters itself.

- **Enemy Models carry their own numbers.** `Midgardian Champion` in the fight
  save: `StringValue enemyStyle = "boss1"`, `IntValue meleeDistance = 4`,
  `aggroRange = 50`, `moveSpeed = 16`, `level = 185`, `damage`, `exp`,
  `NumberValue attackSpeed = 1`, a `Script`, `hitSound`, `enemyNameplate`
  BillboardGui, HumanoidRootPart 5.1 x 60 x 2.6. The script reads style and
  melee distance (4.10.4).
- **Bosses are fought from ability range** (Chris, 2026-09-02): the bot must
  not close to melee - the boss has a melee too - and the abilities, radius
  about 30, are what win. `bossStandoff` 26.
