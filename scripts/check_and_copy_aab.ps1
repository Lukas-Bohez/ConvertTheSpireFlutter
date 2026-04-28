$ErrorActionPreference = 'Stop'
$env:JAVA_HOME = 'C:\Program Files\Android\Android Studio\jbr'
$env:PATH = $env:JAVA_HOME + '\\bin;' + $env:PATH
Write-Host "JAVA_HOME = $env:JAVA_HOME"
try { & java -version } catch { Write-Host "java not runnable: $_" }
$aab = 'build\\app\\outputs\\bundle\\playRelease\\app-play-release.aab'
if (-not (Test-Path $aab)) {
    Write-Host "AAB_MISSING"
    exit 2
}
# Ensure aab directory
Remove-Item aab\\*.aab -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force aab | Out-Null
Copy-Item $aab -Destination "aab\\bitplayer-v10.5.4+1054-play-release.aab" -Force
Get-Item "aab\\bitplayer-v10.5.4+1054-play-release.aab" | Select-Object Name,@{N='MB';E={[math]::Round($_.Length/1MB,2)}} | Format-List
Write-Host "COPIED"
exit 0
