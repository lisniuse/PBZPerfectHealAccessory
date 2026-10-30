# 回血百分比配置工具
# 读取/修改 Scripts/config.lua 里的 heal_percent
$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$cfgPath = Join-Path (Split-Path -Parent $root) "Scripts\config.lua"
if (!(Test-Path $cfgPath)) {
    Write-Host "ERROR: config.lua not found at $cfgPath"
    Write-Host "Run this from the PBZPerfectHealAccessory folder."
    exit 1
}

$text = Get-Content -Raw -Encoding UTF8 $cfgPath
$current = "?"
if ($text -match 'heal_percent\s*=\s*([0-9]+(?:\.[0-9]+)?)') { $current = $matches[1] }

Write-Host ""
Write-Host "PBZ Perfect Heal - config"
Write-Host "Current heal percent: $current"
Write-Host ""
$input = Read-Host "Enter new heal percent (e.g. 10), then press Enter"
$num = 0.0
if (![double]::TryParse($input, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$num)) {
    Write-Host "ERROR: not a number"
    exit 1
}
if ($num -lt 0 -or $num -gt 1000) {
    Write-Host "ERROR: out of range (0-1000)"
    exit 1
}

$inv = [System.Globalization.CultureInfo]::InvariantCulture
$value = $num.ToString($inv)
$new = [regex]::Replace($text, 'heal_percent\s*=\s*[0-9]+(?:\.[0-9]+)?', "heal_percent = $value")
[System.IO.File]::WriteAllText($cfgPath, $new, (New-Object System.Text.UTF8Encoding($false)))

Write-Host ""
Write-Host "Saved: heal_percent = $value"
Write-Host "If the game is running, it applies within about 3 seconds."
Write-Host ""
