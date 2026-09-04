<#
    install.ps1 - put the Dungeon Quest autofarm into a Potassium install on this PC.

    From the repo:      powershell -ExecutionPolicy Bypass -File rewrite\tools\install.ps1 -AutoBoot
    With loose files:   keep this script beside DungeonAutofarm-*.lua and the tools, then run the same line.

    -Root      the Potassium folder, if it is not %LOCALAPPDATA%\Potassium
    -AutoBoot  also install the autoexec entry, so the bot loads itself in every Dungeon Quest place
    -Config    an existing DungeonAutofarm6_config.json to carry over (the measured ability range and hit windows)
    -Force     overwrite a config that is already there
#>
param(
    [string]$Root = (Join-Path $env:LOCALAPPDATA 'Potassium'),
    [switch]$AutoBoot,
    [string]$Config,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

# The bundle and the tools sit either in the repo (rewrite\ and rewrite\tools\) or all in one folder beside this script.
$searchDirs = @($here, (Split-Path -Parent $here))
$bundle = $null
foreach ($d in $searchDirs) {
    $found = Get-ChildItem -Path (Join-Path $d 'DungeonAutofarm-*.lua') -ErrorAction SilentlyContinue
    if ($found) {
        $bundle = $found | Sort-Object { try { [version]($_.BaseName -replace '^DungeonAutofarm-', '') } catch { [version]'0.0.0' } } | Select-Object -Last 1
        break
    }
}
if (-not $bundle) { throw "No DungeonAutofarm-*.lua found near $here. Run this from the repo, or put the bundle beside the script." }

$workspace = Join-Path $Root 'workspace'
$autoexec  = Join-Path $Root 'autoexec'
if (-not (Test-Path $Root)) { throw "No Potassium folder at $Root. Install Potassium and run it once, or pass -Root <path>." }
if (-not (Test-Path $workspace)) { New-Item -ItemType Directory -Path $workspace | Out-Null }

function Find-Tool([string]$name) {
    foreach ($d in $searchDirs) {
        $p = Join-Path $d $name
        if (Test-Path $p) { return $p }
        $p = Join-Path (Join-Path $d 'tools') $name
        if (Test-Path $p) { return $p }
    }
    return $null
}

# source name -> name Potassium must see (dq_boot.lua loads these by exactly these names)
$map = [ordered]@{
    'recorder6.lua'  = 'dq_recorder6.lua'
    'probe_hits.lua' = 'dq_probe_hits.lua'
    'probe_odin.lua' = 'dq_probe_odin.lua'
    'poll6.lua'      = 'dq_poll6.lua'
    'poll_odin.lua'  = 'dq_poll_odin.lua'
    'dq_boot.lua'    = 'dq_boot.lua'
}

Copy-Item -Path $bundle.FullName -Destination (Join-Path $workspace 'dq_rewrite.lua') -Force
Write-Host ("bot       {0} -> workspace\dq_rewrite.lua" -f $bundle.Name)

foreach ($src in $map.Keys) {
    $path = Find-Tool $src
    if ($path) {
        Copy-Item -Path $path -Destination (Join-Path $workspace $map[$src]) -Force
        Write-Host ("tool      {0} -> workspace\{1}" -f $src, $map[$src])
    } else {
        Write-Host ("missing   {0} (optional; telemetry only)" -f $src)
    }
}

if ($AutoBoot) {
    $boot = Find-Tool 'dq_autoboot.lua'
    if (-not $boot) { throw "dq_autoboot.lua not found; leave off -AutoBoot or fetch the tools folder." }
    if (-not (Test-Path $autoexec)) { New-Item -ItemType Directory -Path $autoexec | Out-Null }
    Copy-Item -Path $boot -Destination (Join-Path $autoexec 'dq_autoboot.lua') -Force
    Write-Host "autoexec  dq_autoboot.lua installed (delete it to stop the bot loading by itself)"
}

if ($Config) {
    if (-not (Test-Path $Config)) { throw "No config at $Config" }
    $target = Join-Path $workspace 'DungeonAutofarm6_config.json'
    if ((Test-Path $target) -and -not $Force) {
        Write-Host "config    one is already there; pass -Force to replace it"
    } else {
        Copy-Item -Path $Config -Destination $target -Force
        Write-Host "config    carried over (measured ability range and hit windows)"
    }
}

Write-Host ""
Write-Host ("Installed into {0}" -f $workspace)
Write-Host 'In Dungeon Quest, execute with Potassium:  loadstring(readfile("dq_rewrite.lua"))()'
Write-Host 'Right Shift opens the menu. Leave auto attack off; the tuning is abilities only.'
