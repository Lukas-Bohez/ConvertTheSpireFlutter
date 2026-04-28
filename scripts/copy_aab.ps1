$ErrorActionPreference='Stop'
$env:JAVA_HOME='C:\Program Files\Android\Android Studio\jbr'
$env:PATH = $env:JAVA_HOME + '\\bin;' + $env:PATH
$src='C:\development\ConversionFlutter\my_flutter_app\build\app\outputs\bundle\playRelease\app-play-release.aab'
if (-not (Test-Path $src)) {
    Write-Host 'SOURCE_MISSING'
    exit 2
}
Remove-Item 'c:\development\ConversionFlutter\my_flutter_app\aab\*.aab' -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force 'c:\development\ConversionFlutter\my_flutter_app\aab' | Out-Null
Copy-Item $src -Destination 'c:\development\ConversionFlutter\my_flutter_app\aab\bitplayer-v10.5.4+1054-play-release.aab' -Force
$it = Get-Item 'c:\development\ConversionFlutter\my_flutter_app\aab\bitplayer-v10.5.4+1054-play-release.aab'
$mb = [math]::Round($it.Length/1MB,2)
Write-Host "COPIED Name: $($it.Name) SizeMB: $mb"
