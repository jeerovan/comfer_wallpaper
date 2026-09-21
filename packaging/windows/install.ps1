param([string]$Source = (Join-Path $PSScriptRoot '..\..\build\windows\x64\runner\Release'), [switch]$NoLaunch)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
$Source = (Resolve-Path -LiteralPath $Source).Path
foreach ($required in @('comfer_wallpaper.exe', 'flutter_windows.dll', 'data\icudtl.dat', 'data\flutter_assets')) {
    if (-not (Test-Path -LiteralPath (Join-Path $Source $required))) { throw "Incomplete release bundle: $required" }
}
$Target = Get-ComferInstallDirectory
if ($Source -eq $Target -or $Source.StartsWith($Target + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'The source must be outside the installation directory.'
}
$Installed = Test-Path -LiteralPath (Join-Path $Target 'comfer_wallpaper.exe')
foreach ($directory in @($Source, $Target)) {
    if (Test-Path -LiteralPath $directory) {
        $links = Get-ChildItem -LiteralPath $directory -Recurse -Force | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }
        if ($links) { throw 'A release or installation contains links; refusing to copy through them.' }
    }
}
Stop-Comfer $Target
New-Item -ItemType Directory -Force -Path $Target | Out-Null
foreach ($item in Get-ChildItem -LiteralPath $Source) {
    Copy-Item -LiteralPath $item.FullName -Destination $Target -Recurse -Force
}
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'common.ps1'), (Join-Path $PSScriptRoot 'uninstall.ps1') -Destination $Target -Force
$Exe = Join-Path $Target 'comfer_wallpaper.exe'
$RunKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$Existing = Get-ItemPropertyValue -Path $RunKey -Name 'ComferWallpaper' -ErrorAction SilentlyContinue
# Preserve removed Run entries on upgrades; Windows owns StartupApproved.
if (-not $Installed -or $null -ne $Existing) {
    New-Item -Path $RunKey -Force | Out-Null
    New-ItemProperty -Path $RunKey -Name 'ComferWallpaper' -Value ('"' + $Exe + '" --background') -PropertyType String -Force | Out-Null
}
$UninstallKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\ComferWallpaper'
New-Item -Path $UninstallKey -Force | Out-Null
$UninstallCommand = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $Target 'uninstall.ps1') + '"'
foreach ($entry in @{ DisplayName = 'Comfer Wallpaper'; Publisher = 'Jeerovan'; InstallLocation = $Target; DisplayIcon = $Exe; UninstallString = $UninstallCommand }.GetEnumerator()) {
    New-ItemProperty -Path $UninstallKey -Name $entry.Key -Value $entry.Value -PropertyType String -Force | Out-Null
}
if (-not $NoLaunch) { Start-Process -FilePath $Exe -ArgumentList '--background' -WindowStyle Hidden }
Write-Output "Installed: $Target"
