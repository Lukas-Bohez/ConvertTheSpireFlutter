$ErrorActionPreference='Stop'
$aab='c:\development\ConversionFlutter\my_flutter_app\aab\bitplayer-v12.2.1+1221-play-release.aab'
$dest='c:\development\ConversionFlutter\my_flutter_app\build\aab_extracted'
if (-not (Test-Path $aab)) { Write-Host 'AAB_MISSING'; exit 2 }
Remove-Item $dest -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $dest | Out-Null
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::ExtractToDirectory($aab,$dest)
# find manifest file
$manifest = Get-ChildItem $dest -Recurse -Filter 'AndroidManifest.xml' | Select-Object -First 1 -ExpandProperty FullName
if (-not $manifest) { Write-Host 'MANIFEST_NOT_FOUND'; exit 3 }
Write-Host "Manifest: $manifest"
$text = Get-Content $manifest -Raw -Encoding UTF8
Write-Host '=== CHECKS ==='
Write-Host 'leanback feature:    ' ($text -match 'android.software.leanback')
Write-Host 'LEANBACK_LAUNCHER:   ' ($text -match 'LEANBACK_LAUNCHER')
Write-Host 'touchscreen present: ' ($text -match 'android.hardware.touchscreen')
Write-Host 'touchscreen=false:   ' ($text -match 'touchscreen[^>]+required="false"')
Write-Host 'tv_banner:           ' ($text -match 'tv_banner')
Write-Host 'AdMob ID:            ' ($text -match '8418485814964449~3826434673')
# Save manifest_copy
$text | Out-File "c:\development\ConversionFlutter\my_flutter_app\manifest_extracted.txt" -Encoding utf8
