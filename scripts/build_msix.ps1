param(
  [string]$CertPath = "windows/certificates/codesign.pfx",
  [string]$CertSubject = "CN=Oroka Conner",
  [switch]$UseTestCert
)

$ErrorActionPreference = "Stop"

function Ensure-TestCert {
  param(
    [string]$Subject,
    [string]$OutPath
  )

  if (Test-Path $OutPath) {
    Write-Host "Using existing test certificate at $OutPath"
    return
  }

  Write-Host "Creating self-signed test certificate (NOT for distribution)..."
  $cert = New-SelfSignedCertificate -Subject $Subject -Type CodeSigningCert -CertStoreLocation Cert:\CurrentUser\My
  $password = Read-Host "Enter a password to protect the test PFX" -AsSecureString
  $outDir = Split-Path -Parent $OutPath
  if (-not (Test-Path $outDir)) {
    New-Item -ItemType Directory -Path $outDir | Out-Null
  }
  Export-PfxCertificate -Cert $cert -FilePath $OutPath -Password $password | Out-Null
  Write-Host "Test certificate created at $OutPath"
}

if ($UseTestCert) {
  Ensure-TestCert -Subject $CertSubject -OutPath $CertPath
}

if (-not (Test-Path $CertPath)) {
  Write-Error "Code-signing certificate not found at $CertPath. Provide a valid .pfx or run with -UseTestCert for testing."
}

$certPassword = $null
if ([IO.Path]::GetExtension($CertPath).ToLowerInvariant() -eq ".pfx") {
  $securePassword = Read-Host "Enter the PFX password" -AsSecureString
  $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
  $certPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
  [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
}

Write-Host "Running flutter pub get..."
flutter pub get

Write-Host "Building Windows release..."
flutter build windows --release

Write-Host "Creating MSIX (uses msix_config in pubspec.yaml)..."
if ($certPassword) {
  dart run msix:create --certificate-path="$CertPath" --certificate-password="$certPassword"
} else {
  dart run msix:create --certificate-path="$CertPath"
}

Write-Host "MSIX build complete. Look for the .msix file under build\windows\runner\Release or build\windows\runner\Release\*.msix."
