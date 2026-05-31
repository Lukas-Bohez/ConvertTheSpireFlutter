$ErrorActionPreference = 'Continue'
$aab = Resolve-Path "c:\development\ConversionFlutter\my_flutter_app\aab\bitplayer-v12.1.8+1218-play-release.aab"
Write-Host "Resolved AAB: $aab"

$tmp = Join-Path $env:TEMP ("aab_" + [guid]::NewGuid())
New-Item -ItemType Directory $tmp | Out-Null
Write-Host "Temp extraction dir: $tmp"

Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::ExtractToDirectory($aab, $tmp)

$bannerFiles = @(
  (Join-Path $tmp 'base\res\drawable\banner.png'),
  (Join-Path $tmp 'base\res\drawable-xhdpi-v4\banner.png')
)

$missing = $bannerFiles | Where-Object { -not (Test-Path $_) }
Write-Host '=== AAB RESOURCE CHECK ==='
Write-Host "banner resources present: $($missing.Count -eq 0)"
Write-Host "base/res/drawable/banner.png:         $([bool](Test-Path $bannerFiles[0]))"
Write-Host "base/res/drawable-xhdpi-v4/banner.png: $([bool](Test-Path $bannerFiles[1]))"

if ($missing.Count -gt 0) {
  Write-Host 'VERIFICATION FAILED - DO NOT PROCEED' -ForegroundColor Red
  exit 1
}

Write-Host 'ALL CHECKS PASSED' -ForegroundColor Green
