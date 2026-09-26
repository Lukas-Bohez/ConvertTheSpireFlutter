# Checks the version resources that Windows code signing restricts on
# (docs/signing/signpath.md): product name and product version on the app and
# on Setup.exe. SignPath rejects a signing request whose files do not match,
# so a mismatch fails the build here first.
#
# It also guards the app's CompanyName: path_provider builds the data folder
# from CompanyName and ProductName (%APPDATA%\Oroka Conner\Convert the Spire
# Reborn), so changing either would lose everyone's settings and library.
#
#   pwsh tools/check_windows_metadata.ps1 -App <path to exe> -Setup <path to Setup.exe>
param(
  [Parameter(Mandatory = $true)] [string] $App,
  [Parameter(Mandatory = $true)] [string] $Setup
)
$ErrorActionPreference = 'Stop'

$full = (Select-String -Path pubspec.yaml -Pattern '^version:\s*(\S+)').Matches[0].Groups[1].Value
$short = $full -replace '\+.*$', ''
$expected = @(
  @{ File = $App; ProductVersion = $full; CompanyName = 'Oroka Conner' },
  @{ File = $Setup; ProductVersion = $short; CompanyName = $null }
)

$failed = $false
foreach ($e in $expected) {
  $vi = (Get-Item $e.File).VersionInfo
  $name = Split-Path $e.File -Leaf
  foreach ($key in 'ProductName', 'ProductVersion', 'FileVersion', 'CompanyName', 'LegalCopyright') {
    # Brackets show any padding: Inno Setup pads some of its strings.
    Write-Host ("{0}: {1} = [{2}]" -f $name, $key, $vi.$key)
  }
  $checks = @(
    @('ProductName', 'Convert The Spire Reborn'),
    @('ProductVersion', $e.ProductVersion)
  )
  if ($e.CompanyName) { $checks += , @('CompanyName', $e.CompanyName) }
  foreach ($c in $checks) {
    $actual = "$($vi.($c[0]))".Trim()
    if ($actual -ne $c[1]) {
      Write-Host "::error::$name $($c[0]) is '$actual', expected '$($c[1])'"
      $failed = $true
    }
  }
  if ([string]::IsNullOrWhiteSpace($vi.FileVersion)) {
    Write-Host "::error::$name has no FileVersion"
    $failed = $true
  }
}
if ($failed) { exit 1 }
Write-Host "Version metadata OK."
