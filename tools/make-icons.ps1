# Regenerates package/DSM icons from the master icon.png (repo root) using
# System.Drawing (no external tools needed). High-quality bicubic resample.
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

$root = Split-Path -Parent $PSScriptRoot
$master = Join-Path $root "icon.png"
$imgDir = Join-Path $root "src\package\ui\images"
New-Item -ItemType Directory -Force $imgDir | Out-Null

if (-not (Test-Path $master)) {
    throw "master icon not found: $master"
}
$orig = [System.Drawing.Image]::FromFile($master)

function Save-Resized([int]$size, [string]$path) {
    $bmp = New-Object System.Drawing.Bitmap($size, $size)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
    $g.DrawImage($orig, (New-Object System.Drawing.Rectangle(0, 0, $size, $size)))
    $g.Dispose()
    $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    Write-Host "created $path ($size x $size)"
}

foreach ($sz in 16, 24, 32, 48, 64, 72, 256) {
    Save-Resized $sz (Join-Path $imgDir "icon_$sz.png")
}
Save-Resized 72  (Join-Path $root "src\PACKAGE_ICON.PNG")
Save-Resized 256 (Join-Path $root "src\PACKAGE_ICON_256.PNG")

$orig.Dispose()
