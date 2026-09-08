param(
  [switch]$SkipBuildWindows
)

$ErrorActionPreference = "Stop"

Write-Host "Running flutter pub get..."
flutter pub get

if (-not $SkipBuildWindows) {
  Write-Host "Building Windows release..."
  flutter build windows --release
}

Write-Host "Creating unsigned MSIX (will be signed by Microsoft Store)..."
dart run msix:create

Write-Host ""
Write-Host "✓ MSIX build complete!"
Write-Host "  Location: build\windows\runner\Release\Convert the Spire Reborn.msix"
Write-Host ""
Write-Host "Next steps:"
Write-Host "  1. Go to https://partner.microsoft.com/en-us/dashboard"
Write-Host "  2. Create a new app and register your app name"
Write-Host "  3. Upload this MSIX file"
Write-Host "  4. Microsoft will sign it and list it in the Store"
