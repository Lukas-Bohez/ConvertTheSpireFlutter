<#
  Puts a finished store build in upload\new and archives replaced files in
  upload\old.

    .\scripts\publish_local.ps1 -Store androidPlayStore -File aab\bitplayer-v16.1.0+1306-play-release.aab
    .\scripts\publish_local.ps1 -Store windowsMicrosoftStore -File microsoft-upload\ConvertTheSpireReborn.msix
    .\scripts\publish_local.ps1 -Store windowsMicrosoftStore -File microsoft-upload\whats-new-16.1.0.csv

  Files of the kind already in the folder (.aab; .msix; .csv) are moved to
  upload\old first. The file given is copied, not moved.
#>
param(
  [Parameter(Mandatory)][ValidateSet('androidPlayStore', 'windowsMicrosoftStore')]
  [string]$Store,
  [Parameter(Mandatory)][string]$File
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$source = Resolve-Path (Join-Path $root $File) -ErrorAction SilentlyContinue
if (-not $source) { $source = Resolve-Path $File }
$ext = [IO.Path]::GetExtension($source.Path)

$newest = Join-Path $root "upload\new\$Store"
$older = Join-Path $root "upload\old\$Store"
New-Item -ItemType Directory -Force $newest, $older | Out-Null

Get-ChildItem $newest -File -Filter "*$ext" | ForEach-Object {
  $target = Join-Path $older $_.Name
  if (Test-Path $target) {
    $target = Join-Path $older ('{0}-{1:yyyyMMdd-HHmmss}{2}' -f $_.BaseName, $_.LastWriteTime, $_.Extension)
  }
  $resolvedSource = [IO.Path]::GetFullPath($_.FullName)
  $resolvedTarget = [IO.Path]::GetFullPath($target)
  if (!$resolvedSource.StartsWith($newest + [IO.Path]::DirectorySeparatorChar) -or
      !$resolvedTarget.StartsWith($older + [IO.Path]::DirectorySeparatorChar)) {
    throw 'Archive paths must stay inside the upload directories.'
  }
  Move-Item -LiteralPath $resolvedSource -Destination $resolvedTarget
}

Copy-Item $source.Path $newest
Write-Host "In $newest :"
Get-ChildItem $newest | ForEach-Object { '  {0}  ({1:N1} MB)' -f $_.Name, ($_.Length / 1MB) }
