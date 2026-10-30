$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
. (Join-Path $root 'tools\common.ps1')

$game = Find-GameRoot
if (-not $game) { Write-Host 'ERROR: game folder not found.'; exit 1 }

$dest = Join-Path $game 'platform\steam\ue4ss\Mods\PBZPerfectHealAccessory'
if (Test-Path $dest) {
    Remove-Item $dest -Recurse -Force
    Write-Host 'Removed:'
    Write-Host "  $dest"
} else {
    Write-Host 'Not installed (folder not found).'
}
