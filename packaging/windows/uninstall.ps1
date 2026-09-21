$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
$Target = Get-ComferInstallDirectory
Stop-Comfer $Target
if (Test-Path -LiteralPath $Target) {
    $links = Get-ChildItem -LiteralPath $Target -Recurse -Force | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }
    if ($links) { throw 'The installation contains links; refusing recursive removal.' }
    Remove-Item -LiteralPath $Target -Recurse -Force
}
Remove-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'ComferWallpaper' -ErrorAction SilentlyContinue
Remove-Item -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\ComferWallpaper' -ErrorAction SilentlyContinue
Write-Output 'Removed Comfer and its login entry. Active wallpaper and preferences are preserved.'
