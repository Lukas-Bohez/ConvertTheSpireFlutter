$ErrorActionPreference='Stop'
$env:JAVA_HOME='C:\Program Files\Android\Android Studio\jbr'
$env:PATH = $env:JAVA_HOME + '\\bin;' + $env:PATH
$sdk = "$env:LOCALAPPDATA\Android\Sdk"
$analyzer = Get-ChildItem "$sdk\cmdline-tools" -Recurse -Filter apkanalyzer.bat -ErrorAction SilentlyContinue | Sort-Object FullName -Desc | Select-Object -First 1 -Exp FullName
if (-not $analyzer) {
    Write-Host "apkanalyzer not found in cmdline-tools, searching..."
    $analyzer = Get-ChildItem $sdk -Recurse -Filter apkanalyzer.bat -ErrorAction SilentlyContinue | Sort-Object FullName -Desc | Select-Object -First 1 -Exp FullName
}
Write-Host "Using: $analyzer"
$aab = Resolve-Path "c:\\development\\ConversionFlutter\\my_flutter_app\\aab\\bitplayer-v12.1.4+1214-play-release.aab"
$outFile = "c:\\development\\ConversionFlutter\\my_flutter_app\\manifest_check.txt"
$errFile = "c:\\development\\ConversionFlutter\\my_flutter_app\\manifest_check.err.txt"
Start-Process -FilePath $analyzer -ArgumentList @('manifest','print',$aab) -NoNewWindow -Wait -RedirectStandardOutput $outFile -RedirectStandardError $errFile
$text = Get-Content $outFile -Raw -ErrorAction SilentlyContinue
if (-not $text) { Write-Host "apkanalyzer produced no output, see $errFile"; exit 4 }
Write-Host "=== VERIFICATION ==="
Write-Host "leanback feature:    " ($text -match "android.software.leanback")
Write-Host "LEANBACK_LAUNCHER:   " ($text -match "LEANBACK_LAUNCHER")
Write-Host "touchscreen present: " ($text -match "android.hardware.touchscreen")
Write-Host "touchscreen=false:   " ($text -match 'touchscreen[^>]+required="false"')
Write-Host "tv_banner:           " ($text -match "tv_banner")
Write-Host "AdMob ID:            " ($text -match "8418485814964449~3826434673")
