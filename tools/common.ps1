function Get-SteamLibraries {
    $libs = @()
    $steam = $null
    try { $steam = (Get-ItemProperty -Path 'HKCU:\Software\Valve\Steam' -ErrorAction Stop).SteamPath } catch {}
    if (-not $steam) {
        try { $steam = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam' -ErrorAction Stop).InstallPath } catch {}
    }
    if ($steam) {
        $steam = $steam -replace '/', '\'
        $libs += $steam
        $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
        if (Test-Path $vdf) {
            Get-Content $vdf | ForEach-Object {
                if ($_ -match '"path"\s+"([^"]+)"') {
                    $p = $matches[1] -replace '\\', '\'
                    if (-not ($libs -contains $p)) { $libs += $p }
                }
            }
        }
    }
    return $libs
}

function Find-GameRoot {
    foreach ($lib in (Get-SteamLibraries)) {
        foreach ($name in @('PBZ', 'Phantom Blade Zero', 'PhantomBladeZero')) {
            $p = Join-Path $lib ("steamapps\common\" + $name)
            if (Test-Path (Join-Path $p 'platform\steam\PBZ.exe')) { return $p }
        }
    }
    Add-Type -AssemblyName System.Windows.Forms | Out-Null
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = "Select the Phantom Blade Zero folder (the one containing 'platform' and 'ProjectPBZ')"
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { return $dlg.SelectedPath }
    return $null
}
