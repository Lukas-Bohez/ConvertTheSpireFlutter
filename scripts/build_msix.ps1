# Builds the Microsoft Store package (MSIX) on a Windows PC: the same steps
# as .github/workflows/msstore.yml, which is the usual way to make it (see
# docs/publishing/windows-store.md). Microsoft signs the package, so it is
# not signed here.
#
#   .\scripts\build_msix.ps1 -IdentityName <Package/Identity/Name> `
#       -Publisher "CN=..." -PublisherDisplayName "<...>"
#
# The three values are in Partner Center > the app > Product identity.
# Put ffmpeg\ffmpeg.exe, yt-dlp\yt-dlp.exe and deno\deno.exe next to the exe
# in build\windows\x64\runner\Release before packaging (-SkipBuildWindows),
# or the Store version has no FFmpeg, yt-dlp or Deno.
param(
  [Parameter(Mandatory = $true)][string]$IdentityName,
  [Parameter(Mandatory = $true)][string]$Publisher,
  [Parameter(Mandatory = $true)][string]$PublisherDisplayName,
  [string]$DisplayName = "Convert The Spire Reborn",
  [switch]$SkipBuildWindows
)

$ErrorActionPreference = "Stop"

flutter pub get

if (-not $SkipBuildWindows) {
  flutter build windows --release --no-tree-shake-icons --dart-define=MS_STORE_BUILD=true
}

$release = "build\windows\x64\runner\Release"
foreach ($tool in @("ffmpeg\ffmpeg.exe", "yt-dlp\yt-dlp.exe", "deno\deno.exe")) {
  if (-not (Test-Path (Join-Path $release $tool))) {
    Write-Warning "$tool is missing from $release; the package will not have it."
  }
}

$version = (Select-String -Path pubspec.yaml -Pattern '^version:\s*([0-9]+\.[0-9]+\.[0-9]+)').Matches[0].Groups[1].Value
dart run msix:create --store `
  --identity-name $IdentityName `
  --publisher $Publisher `
  --publisher-display-name $PublisherDisplayName `
  --display-name $DisplayName `
  --version "$version.0" `
  --output-path build\msix

Write-Host ""
Write-Host "Done: build\msix\ConvertTheSpireReborn.msix"
Write-Host "Upload it in Partner Center (docs/publishing/windows-store.md)."
