$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
. (Join-Path $root 'tools\common.ps1')

$game = Find-GameRoot
if (-not $game) { Write-Host 'ERROR: game folder not found.'; exit 1 }

$mods = Join-Path $game 'platform\steam\ue4ss\Mods'
if (-not (Test-Path $mods)) {
    Write-Host ''
    Write-Host 'ERROR: UE4SS for Phantom Blade Zero is not installed.'
    Write-Host 'Install it first (Nexus Mods: search "UE4SS for PBZ"), then run this again.'
    Write-Host ''
    exit 1
}

$dest = Join-Path $mods 'PBZPerfectHealAccessory'
$keep = $null
$cfgOld = Join-Path $dest 'Scripts\config.lua'
if (Test-Path $cfgOld) { $keep = Get-Content -Raw $cfgOld }

if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
New-Item -ItemType Directory -Path $dest | Out-Null

$items = @('enabled.txt', 'README.md', 'LICENSE', 'Configure Heal Percent.cmd',
           'Install.cmd', 'Uninstall.cmd', 'Scripts', 'tools', 'pak-source')
foreach ($it in $items) {
    $p = Join-Path $root $it
    if (Test-Path $p) { Copy-Item $p -Destination $dest -Recurse -Force }
}

if ($keep) {
    $cfgNew = Join-Path $dest 'Scripts\config.lua'
    [System.IO.File]::WriteAllText($cfgNew, $keep, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host 'Kept your existing config.lua.'
}

Write-Host ''
Write-Host 'Installed to:'
Write-Host "  $dest"
Write-Host ''
Write-Host 'Start the game and load a save. Check ue4ss\UE4SS.log for [PBZPerfectHeal] lines.'
