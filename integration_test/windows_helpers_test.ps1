# Run with: pwsh -NoProfile -File integration_test/windows_helpers_test.ps1
# Registry calls are mocked; filesystem operations use an isolated temporary root.
$ErrorActionPreference = 'Stop'
$global:comferTestRegistry = @{}
$script:previousLocalAppData = $env:LOCALAPPDATA
$script:testRoot = Join-Path ([IO.Path]::GetTempPath()) ('comfer-helpers-' + [guid]::NewGuid())
New-Item -ItemType Directory -Path $script:testRoot | Out-Null
$env:LOCALAPPDATA = Join-Path $script:testRoot 'User data with spaces'
New-Item -ItemType Directory -Path $env:LOCALAPPDATA | Out-Null

function New-Item {
    param($Path, $ItemType, [switch]$Force)
    if ($Path -like 'HKCU:*') { return }
    Microsoft.PowerShell.Management\New-Item -Path $Path -ItemType $ItemType -Force:$Force
}
function New-ItemProperty {
    param($Path, $Name, $Value, $PropertyType, [switch]$Force)
    $global:comferTestRegistry["$Path|$Name"] = $Value
}
function Get-ItemPropertyValue {
    param($Path, $Name, $ErrorAction)
    $global:comferTestRegistry["$Path|$Name"]
}
function Remove-ItemProperty {
    param($Path, $Name, $ErrorAction)
    $global:comferTestRegistry.Remove("$Path|$Name")
}
function Remove-Item {
    param($LiteralPath, [switch]$Recurse, [switch]$Force, $ErrorAction)
    if ($LiteralPath -like 'HKCU:*') {
        foreach ($key in @($global:comferTestRegistry.Keys)) {
            if ($key.StartsWith($LiteralPath + '|')) { $global:comferTestRegistry.Remove($key) }
        }
        return
    }
    Microsoft.PowerShell.Management\Remove-Item -LiteralPath $LiteralPath -Recurse:$Recurse -Force:$Force
}
function Assert($Condition, $Message) { if (-not $Condition) { throw $Message } }

try {
    $source = Join-Path $script:testRoot 'release'
    New-Item -ItemType Directory -Path (Join-Path $source 'data/flutter_assets') -Force | Out-Null
    foreach ($name in @('comfer_wallpaper.exe', 'flutter_windows.dll', 'data/icudtl.dat')) {
        Set-Content -LiteralPath (Join-Path $source $name) -Value 'fixture'
    }
    $installer = Join-Path $PSScriptRoot '../packaging/windows/install.ps1'
    $uninstaller = Join-Path $PSScriptRoot '../packaging/windows/uninstall.ps1'
    & $installer -Source $source -NoLaunch
    $target = Join-Path $env:LOCALAPPDATA 'Programs/ComferWallpaper'
    $run = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run|ComferWallpaper'
    Assert ($global:comferTestRegistry[$run] -eq ('"' + (Join-Path $target 'comfer_wallpaper.exe') + '" --background')) 'Login command must quote paths and request background startup.'
    Assert (Test-Path -LiteralPath (Join-Path $target 'uninstall.ps1')) 'Uninstaller must be installed.'
    $global:comferTestRegistry.Remove($run)
    & $installer -Source $source -NoLaunch
    Assert (-not $global:comferTestRegistry.ContainsKey($run)) 'Upgrade must preserve disabled login startup.'
    $data = Join-Path $env:LOCALAPPDATA 'active-wallpaper.jpg'
    Set-Content -LiteralPath $data -Value 'preserve'
    & $uninstaller
    Assert (-not (Test-Path -LiteralPath $target)) 'Uninstall must remove binaries.'
    Assert (Test-Path -LiteralPath $data) 'Uninstall must preserve user data.'
    Assert ($global:comferTestRegistry.Count -eq 0) 'Uninstall must remove registration.'
    Write-Output 'PASS: install, quoted startup, disabled upgrade, uninstall, data preservation'
} finally {
    $env:LOCALAPPDATA = $script:previousLocalAppData
    $resolved = [IO.Path]::GetFullPath($script:testRoot)
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if (-not $resolved.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe test cleanup path' }
    Microsoft.PowerShell.Management\Remove-Item -LiteralPath $resolved -Recurse -Force
}

