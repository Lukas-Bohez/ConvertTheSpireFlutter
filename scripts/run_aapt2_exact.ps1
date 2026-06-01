$sdk  = "$env:LOCALAPPDATA\Android\Sdk\build-tools"
$aapt2 = Get-ChildItem $sdk -Recurse -Filter aapt2.exe |
         Sort-Object FullName -Desc | Select-Object -First 1 -Exp FullName
Write-Host "Using aapt2: $aapt2"

$aab = Resolve-Path "aab\bitplayer-v12.2.3+1223-play-release.aab"
$tmp = Join-Path $env:TEMP ("aab_" + [guid]::NewGuid())
New-Item -ItemType Directory $tmp | Out-Null
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::ExtractToDirectory($aab, $tmp)
$mf = Join-Path $tmp "base\manifest\AndroidManifest.xml"

$decoded = & $aapt2 dump xmltree --file $mf "$aab" 2>&1
if (-not $decoded -or $decoded -match "error") {
  $decoded = & $aapt2 dump xmltree "$mf" 2>&1
}

Write-Host "=== AAPT2 MANIFEST CHECK ==="
$leanback  = ($decoded | Out-String) -match "android.software.leanback"
$launcher  = ($decoded | Out-String) -match "LEANBACK_LAUNCHER"
$touch     = ($decoded | Out-String) -match "android.hardware.touchscreen"
$touchFalse= ($decoded | Out-String) -match "android.hardware.touchscreen" -and
             (($decoded | Where-Object { $_ -match "touchscreen" } |
               Select-Object -First 5) -join "`n") -match "0x00000000"
$banner    = ($decoded | Out-String) -match "tv_banner"
$admob     = ($decoded | Out-String) -match "8418485814964449"

Write-Host "leanback feature:    $leanback"
Write-Host "LEANBACK_LAUNCHER:   $launcher"
Write-Host "touchscreen present: $touch"
Write-Host "touchscreen=false:   $touchFalse"
Write-Host "tv_banner:           $banner"
Write-Host "AdMob App ID:        $admob"

if (-not ($leanback -and $launcher -and $touch -and $touchFalse -and $banner -and $admob)) {
  Write-Host "VERIFICATION FAILED - DO NOT PROCEED" -ForegroundColor Red
  exit 1
}
Write-Host "ALL CHECKS PASSED" -ForegroundColor Green
