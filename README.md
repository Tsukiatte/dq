# DungeonAutofarm

## Loading it

Paste [`loader.lua`](loader.lua) into your executor rather than a bare
loadstring. `raw.githubusercontent` sits behind Fastly with a five minute TTL,
and a stale fetch is indistinguishable from a broken script once it is running
— you end up debugging a version you are not executing. The loader busts the
query string, sends no-cache headers through `request` (`HttpGet` takes none),
and prints the version it found **before** running it, so a stale copy is
caught rather than executed.

Set `DEV = true` in it to load from a local file instead and skip the network
entirely while iterating. Set `PIN` to a commit SHA for anything you hand to
other people: a SHA URL can never be stale, and a bad push cannot reach anyone
who has not chosen to update.

The bare one-liner still works if you want it, but it will occasionally hand
you a five-minute-old script:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/Tsukiatte/dq/main/DungeonAutofarm.lua?t="..tick()))()
```
