param(
  [Parameter(Mandatory = $true)]
  [string]$KeystorePath,

  [Parameter(Mandatory = $true)]
  [string]$StorePassword,

  [Parameter(Mandatory = $true)]
  [string]$KeyAlias,

  [Parameter(Mandatory = $true)]
  [string]$KeyPassword
)

$ErrorActionPreference = 'Stop'

$expectedSha1 = '31:31:FD:AE:97:6D:00:A0:14:13:48:75:DE:27:19:38:BF:20:3F:38'

function Resolve-Keytool {
  $candidates = @(
    'keytool',
    'C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe',
    'C:\Program Files\Android\openjdk\jdk-21.0.8\bin\keytool.exe'
  )

  foreach ($candidate in $candidates) {
    try {
      if ($candidate -eq 'keytool') {
        $cmd = Get-Command keytool -ErrorAction Stop
        return $cmd.Source
      }
      if (Test-Path $candidate) {
        return $candidate
      }
    } catch {
      continue
    }
  }

  throw 'keytool was not found. Install Java/Android Studio and ensure keytool is available.'
}

function Get-CertSha1FromKeystore {
  param(
    [string]$Keytool,
    [string]$StoreFile,
    [string]$StorePass,
    [string]$Alias
  )

  $tmp = Join-Path $env:TEMP ('keystore_verify_' + [guid]::NewGuid().ToString())
  New-Item -ItemType Directory -Path $tmp | Out-Null

  try {
    $stdout = Join-Path $tmp 'stdout.txt'
    $stderr = Join-Path $tmp 'stderr.txt'
    $process = Start-Process -FilePath $Keytool -ArgumentList @(
      '-list', '-v', '-keystore', $StoreFile, '-storepass', $StorePass, '-alias', $Alias
    ) -NoNewWindow -Wait -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr

    $output = @()
    if (Test-Path $stdout) { $output += Get-Content $stdout }
    if (Test-Path $stderr) { $output += Get-Content $stderr }

    if ($process.ExitCode -ne 0) {
      throw 'Could not read keystore. Check path/password/alias.'
    }
  } finally {
    if (Test-Path $tmp) {
      Remove-Item -Recurse -Force $tmp
    }
  }

  foreach ($line in $output) {
    if ($line -match 'SHA1:\s*(.+)$') {
      return $Matches[1].Trim().ToUpper()
    }
  }

  throw 'SHA1 fingerprint was not found in keytool output.'
}

function Get-CertSha1FromAab {
  param(
    [string]$Keytool,
    [string]$AabPath
  )

  $tmp = Join-Path $env:TEMP ('aab_verify_' + [guid]::NewGuid().ToString())
  New-Item -ItemType Directory -Path $tmp | Out-Null

  try {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory((Resolve-Path $AabPath), $tmp)
    $sig = Get-ChildItem -Path (Join-Path $tmp 'META-INF') -File |
      Where-Object { $_.Extension -in '.RSA', '.DSA', '.EC' } |
      Select-Object -First 1

    if (-not $sig) {
      throw 'No signature block file found in AAB META-INF.'
    }

    $stdout = Join-Path $tmp 'stdout.txt'
    $stderr = Join-Path $tmp 'stderr.txt'
    $process = Start-Process -FilePath $Keytool -ArgumentList @(
      '-printcert', '-file', $sig.FullName
    ) -NoNewWindow -Wait -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr

    $certOut = @()
    if (Test-Path $stdout) { $certOut += Get-Content $stdout }
    if (Test-Path $stderr) { $certOut += Get-Content $stderr }

    if ($process.ExitCode -ne 0) {
      throw 'Failed to read cert from AAB signature block.'
    }

    foreach ($line in $certOut) {
      if ($line -match 'SHA1:\s*(.+)$') {
        return $Matches[1].Trim().ToUpper()
      }
    }

    throw 'SHA1 fingerprint was not found in AAB cert output.'
  } finally {
    if (Test-Path $tmp) {
      Remove-Item -Recurse -Force $tmp
    }
  }
}

if (-not (Test-Path $KeystorePath)) {
  throw "Keystore not found: $KeystorePath"
}

$keytool = Resolve-Keytool
Write-Host "Using keytool: $keytool"

$keystoreSha1 = Get-CertSha1FromKeystore -Keytool $keytool -StoreFile $KeystorePath -StorePass $StorePassword -Alias $KeyAlias
Write-Host "Keystore SHA1: $keystoreSha1"

if ($keystoreSha1 -ne $expectedSha1) {
  throw "Wrong upload key. Expected $expectedSha1 but got $keystoreSha1"
}

$keyPropertiesPath = Join-Path $PSScriptRoot '..\android\key.properties'
$keyStoreTarget = Join-Path $PSScriptRoot '..\android\app\release.keystore'

if ((Resolve-Path $KeystorePath).Path -ne (Resolve-Path $keyStoreTarget).Path) {
  Copy-Item -Force $KeystorePath $keyStoreTarget
}
@"
storePassword=$StorePassword
keyPassword=$KeyPassword
keyAlias=$KeyAlias
storeFile=release.keystore
"@ | Set-Content -Path $keyPropertiesPath

Push-Location (Join-Path $PSScriptRoot '..')
try {
  flutter clean
  if ($LASTEXITCODE -ne 0) { throw 'flutter clean failed' }

  flutter pub get
  if ($LASTEXITCODE -ne 0) { throw 'flutter pub get failed' }

  flutter build appbundle --flavor play --release --dart-define=PLAY_STORE_BUILD=true
  if ($LASTEXITCODE -ne 0) { throw 'flutter build appbundle failed' }

  $builtAab = 'build\app\outputs\bundle\playRelease\app-play-release.aab'
  if (-not (Test-Path $builtAab)) {
    throw 'Built AAB not found at expected path.'
  }

  $builtSha1 = Get-CertSha1FromAab -Keytool $keytool -AabPath $builtAab
  Write-Host "Built AAB SHA1: $builtSha1"

  if ($builtSha1 -ne $expectedSha1) {
    throw "Built AAB signature mismatch. Expected $expectedSha1 but got $builtSha1"
  }

  New-Item -ItemType Directory -Force -Path 'aab' | Out-Null
  Copy-Item -Force $builtAab 'aab\bitplayer-v12.2.1+1222-play-release.aab'
  Write-Host 'SUCCESS: aab\bitplayer-v12.2.1+1222-play-release.aab is signed with the expected key.'
} finally {
  Pop-Location
}
