# Configuration
$apiUrl = "https://comfer.jeerovan.com/api?view=landscape&name=jeerovan&hour=$(Get-Date -Format HH)" # Change to your API URL
$wallpaperDir = "$env:USERPROFILE\Pictures\Wallpapers"
if (-Not (Test-Path $wallpaperDir)) {
  New-Item -ItemType Directory -Path $wallpaperDir | Out-Null
}

# Fetch JSON response from API
$response = Invoke-RestMethod -Uri $apiUrl -UseBasicParsing

# Extract imageUrl
$imageUrl = $response.imageUrl
if ([string]::IsNullOrEmpty($imageUrl)) {
  Write-Error "Failed to fetch imageUrl from API response."
  exit 1
}

# Download image
$fileName = "$(Get-Date -UFormat %s).jpg"
$filePath = Join-Path $wallpaperDir $fileName
Invoke-WebRequest -Uri $imageUrl -OutFile $filePath -UseBasicParsing

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
