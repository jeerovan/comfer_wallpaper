function Get-ComferInstallDirectory {
    $root = [IO.Path]::GetFullPath($env:LOCALAPPDATA)
    $target = [IO.Path]::GetFullPath((Join-Path $root 'Programs\ComferWallpaper'))
    if (-not $target.StartsWith($root.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Installation path escapes LocalAppData.'
    }
    $current = $target
    while ($current) {
        if (Test-Path -LiteralPath $current) {
            if ((Get-Item -LiteralPath $current -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw "Installation path contains a link: $current"
            }
        }
        $current = [IO.Path]::GetDirectoryName($current)
    }
    return $target
}

function Stop-Comfer([string]$Target) {
    $exe = Join-Path $Target 'comfer_wallpaper.exe'
    $processes = @(Get-Process -Name comfer_wallpaper -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $exe })
    if ($processes.Count -eq 0) { return }
    $request = Start-Process -FilePath $exe -ArgumentList '--quit' -WindowStyle Hidden -PassThru
    if (-not $request.WaitForExit(10000)) { throw 'Quit request timed out. Quit Comfer from its tray icon, then retry.' }
    foreach ($process in $processes) {
        if (-not $process.WaitForExit(15000)) {
            throw 'Comfer is still running. Quit from its tray icon, then retry. No files were removed.'
        }
    }
}
