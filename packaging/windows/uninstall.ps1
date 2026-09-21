$ErrorActionPreference = 'Stop'
if (Get-Process comfer_wallpaper -ErrorAction SilentlyContinue) { throw 'Quit Comfer before uninstalling.' }
Remove-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'ComferWallpaper' -ErrorAction SilentlyContinue
$Target = Join-Path $env:LOCALAPPDATA 'Programs\ComferWallpaper'
if (Test-Path $Target) { Remove-Item $Target -Recurse -Force }
Write-Output 'Removed. The active wallpaper and preferences are preserved.'
