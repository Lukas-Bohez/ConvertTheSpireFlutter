# PowerShell helper to download libmpv binaries for Android and place them under
# android/app/src/main/jniLibs.  Run from the project root.
#
# Usage:
#   .\scripts\fetch_mpv_android.ps1
#
$releaseBase = 'https://github.com/media-kit/media-kit/releases/download/media_kit-v1.1.10'
$abis = @('android-arm64-v8a','android-armeabi-v7a')
$dest = 'android\app\src\main\jniLibs'

if (-not (Test-Path $dest)) {
    New-Item -ItemType Directory -Path $dest -Force | Out-Null
}

foreach ($abi in $abis) {
    $apk = "media_kit_test_${abi}.apk"
    Write-Host "Downloading $apk..."
    Invoke-WebRequest -Uri "$releaseBase/$apk" -OutFile $apk

    # APK files are just zip archives; PowerShell's Expand-Archive insists on a
    # .zip extension, so rename temporarily.
    $apkZip = "${apk}.zip"
    Rename-Item -Path $apk -NewName $apkZip -Force

    $temp = New-Item -ItemType Directory -Path (Join-Path $env:TEMP ([System.Guid]::NewGuid().ToString()))
    Expand-Archive -Path $apkZip -DestinationPath $temp.FullName -Force
    $so = Get-ChildItem -Path $temp.FullName -Filter libmpv.so -Recurse | Select-Object -First 1
    if (-not $so) {
        Write-Error "libmpv.so not found inside $apkZip"
        exit 1
    }
    $abiFolder = $abi -replace '^android-',''
    $target = Join-Path $dest $abiFolder
    if (-not (Test-Path $target)) {
        New-Item -ItemType Directory -Path $target -Force | Out-Null
    }
    Copy-Item -Path $so.FullName -Destination (Join-Path $target 'libmpv.so') -Force
    Write-Host "Copied libmpv.so for $abi to $target"

    # cleanup original and renamed archives
    if (Test-Path $apk) { Remove-Item -Path $apk -Force }
    if (Test-Path "${apkZip}") { Remove-Item -Path "${apkZip}" -Force }
    Remove-Item -Path $temp.FullName -Recurse -Force
}

Write-Host 'Finished.  Verify the files under android/app/src/main/jniLibs/'