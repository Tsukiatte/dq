# Running this on your own PC

The bot is one self-contained Lua file. Nothing else is required to farm; the
telemetry and the Claude bridge are optional extras on top.

## The bot

1. Install Potassium and run it once, so `%LOCALAPPDATA%\Potassium\workspace`
   exists.
2. From this repo:

   ```
   powershell -ExecutionPolicy Bypass -File rewrite\tools\install.ps1 -AutoBoot
   ```

   It copies the newest `DungeonAutofarm-*.lua` into the workspace as
   `dq_rewrite.lua`, copies the telemetry scripts under the names the boot
   script expects, and (with `-AutoBoot`) installs the autoexec entry.
   `-Root <path>` if Potassium lives somewhere else.
3. In Dungeon Quest, execute:

   ```
   loadstring(readfile("dq_rewrite.lua"))()
   ```

   Right Shift opens the menu. With `-AutoBoot` you can skip this: the bot
   loads itself about seven seconds into any Dungeon Quest place and survives
   the teleports between rounds. Delete
   `%LOCALAPPDATA%\Potassium\autoexec\dq_autoboot.lua` to stop that.

Settings worth checking on the first run: Auto queue, "Press START in the
dungeon", the place rule that turns farming on in a dungeon and off in the
lobby, and auto attack **off** since the whole thing is tuned for abilities
only.

### Carrying the learning over

`DungeonAutofarm6_config.json` in the workspace holds the measured ability
range and the measured hit window of every attack the touch test has seen.
Copy it from another install and the first run starts there instead of
relearning:

```
powershell -ExecutionPolicy Bypass -File rewrite\tools\install.ps1 -Config C:\path\to\DungeonAutofarm6_config.json
```

The tuning assumes a character whose abilities one-shot Northern Lands mobs.
On a weaker one it still fights, but the standoff and the boss timings were
measured against that.

## Telemetry (optional)

`dq_recorder6.lua`, `dq_probe_hits.lua` and `dq_probe_odin.lua` are installed
alongside the bot and load only inside a dungeon. They write JSON next to
themselves: a 10 Hz trace with a verdict for every death, the spawn-to-hit
delay of every attack from the server's own touch test, and Odin's parts
sampled over time. `poll6.lua` and `poll_odin.lua` read them back.

## Letting Claude drive it (optional)

Separate from the bot, and only if you want live debugging the way the
6.6.x work was done:

1. Install Claude Code and the Potassium MCP server on the same PC as Roblox.
   The bridge listens on `ws://127.0.0.1:8081`.
2. Set `POTASSIUM_AUTH_TOKEN` for the bridge to a token you generate. Never
   commit it.
3. Put that server's client script in `%LOCALAPPDATA%\Potassium\autoexec` as
   `mcp.lua`, with `CONFIG.Url = "ws://127.0.0.1:8081"` and `CONFIG.Token` set
   to the same value.

The client dials out, so both ends stay on loopback and nothing is exposed to
the network. The bridge takes one client at a time: whichever Roblox instance
is running Potassium on that PC is the one Claude sees.

`CONTEXT.md` is the engineering hand-over: what every version changed, the
measured attack timings for all three Northern Lands bosses, and the problems
still open.
