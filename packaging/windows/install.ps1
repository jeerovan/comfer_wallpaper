param([string]$Source = 'build\windows\x64\runner\Release')
$ErrorActionPreference = 'Stop'
if (Get-Process comfer_wallpaper -ErrorAction SilentlyContinue) { throw 'Quit Comfer before installing/upgrading.' }
if (-not (Test-Path (Join-Path $Source 'comfer_wallpaper.exe'))) { throw 'Build the Windows release first.' }
$Target = Join-Path $env:LOCALAPPDATA 'Programs\ComferWallpaper'
New-Item -ItemType Directory -Force $Target | Out-Null
Copy-Item (Join-Path $Source '*') $Target -Recurse -Force
$Exe = Join-Path $Target 'comfer_wallpaper.exe'
$RunKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
New-Item -Path $RunKey -Force | Out-Null
New-ItemProperty -Path $RunKey -Name 'ComferWallpaper' -Value ('"' + $Exe + '"') -PropertyType String -Force | Out-Null
Start-Process $Exe
Write-Output "Installed: $Target"
