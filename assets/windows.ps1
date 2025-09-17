# Configuration
$downloadsDir = [Environment]::GetFolderPath("UserProfile") + "\Downloads"
$wallpaperFileNamePath = Join-Path $downloadsDir "wallpaper_file_name.txt"

if (-Not (Test-Path $wallpaperFileNamePath)) {
  Write-Error "wallpaper_file_name.txt not found in Downloads directory."
  exit 1
}

# Read the current wallpaper file name from the text file
$wallpaperFileName = Get-Content $wallpaperFileNamePath -ErrorAction Stop

# Construct the full file path to the wallpaper image
$filePath = Join-Path $downloadsDir $wallpaperFileName

if (-Not (Test-Path $filePath)) {
  Write-Error "Wallpaper image file not found: $filePath"
  exit 1
}

# Set wallpaper using Windows API through COM object
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Wallpaper {
    [DllImport("user32.dll",SetLastError=true)]
    public static extern bool SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
}
"@

$SPI_SETDESKWALLPAPER = 0x0014
$SPIF_UPDATEINIFILE = 0x01
$SPIF_SENDWININICHANGE = 0x02

[Wallpaper]::SystemParametersInfo($SPI_SETDESKWALLPAPER, 0, $filePath, $SPIF_UPDATEINIFILE -bor $SPIF_SENDWININICHANGE) | Out-Null

Write-Output "Wallpaper set to $filePath"
