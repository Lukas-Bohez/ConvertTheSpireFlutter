<#
.SYNOPSIS
  Makes everything for a Microsoft Store submission in .\microsoft-upload:
  the MSIX package, the screenshots and app tile, and the Store listing in
  all 18 languages. With -ListingCsv, also a filled listing CSV to import.

.DESCRIPTION
  Run it from the repository on a Windows PC with Flutter and Visual Studio
  (the same as for "flutter build windows"). It does what the "Microsoft
  Store package" workflow does on GitHub:

    1. flutter build windows with MS_STORE_BUILD=true (the Store build)
    2. puts FFmpeg, yt-dlp and Deno next to the exe (the Store version does
       not download them; they are cached in microsoft-upload\.tools)
    3. dart run msix:create --store, with the identity from Partner Center
    4. checks the package's identity and contents

  The identity values (Partner Center > the app > Product management >
  Product identity) are saved in microsoft-upload\identity.json the first
  time, so later runs need none.

  microsoft-upload\ then holds:
    ConvertTheSpireReborn.msix     the package to upload (Packages)
    screenshots\                   1920x1080 screenshots (Store listings)
    app-tile-300.png               the 1:1 app tile icon (Store listings)
    listings\<language>.md         each language's texts, field by field
    store-import\                  with -ListingCsv: the folder to import (filled CSV,
                                   screenshots and app tile for every language)
    HOW-TO-UPLOAD.txt              what goes where

.EXAMPLE
  .\scripts\make_store_upload.cmd -IdentityName 12345OrokaConner.ConvertTheSpireReborn -Publisher "CN=1A2B3C4D-..." -PublisherDisplayName "Oroka Conner"

  The first run: builds everything. Later runs: .\scripts\make_store_upload.cmd

.EXAMPLE
  .\scripts\make_store_upload.cmd -ListingsOnly -ListingCsv "%USERPROFILE%\Downloads\listings.csv"

  No build: fills the listing CSV exported from Partner Center (submission >
  Store listings > Import/export > Export listings) with all 18 languages.
#>
param(
  [string]$IdentityName,
  [string]$Publisher,
  [string]$PublisherDisplayName,
  # The name reserved in Partner Center, exactly.
  [string]$DisplayName,
  # A listing CSV exported from Partner Center, to fill with every language.
  [string]$ListingCsv,
  [string]$OutDir = 'microsoft-upload',
  # Package the last build again instead of building.
  [switch]$SkipBuild,
  # Only the screenshots and listing texts (and -ListingCsv), no package.
  [switch]$ListingsOnly,
  # Download FFmpeg, yt-dlp and Deno again even if the cached copies are new.
  [switch]$RefreshTools
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
# Windows PowerShell 5.1 does not offer TLS 1.2 by default.
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
$out = Join-Path $root $OutDir
New-Item -ItemType Directory -Force $out | Out-Null
$listingDir = Join-Path $root 'docs/publishing/store-listing'

function Step($text) { Write-Host ''; Write-Host "== $text" -ForegroundColor Cyan }

# ---------------------------------------------------------------------------
# Listing texts, screenshots, tile
# ---------------------------------------------------------------------------
Step 'Store listing files'
$listings = Get-Content (Join-Path $listingDir 'listings.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$languages = @($listings.languages.PSObject.Properties.Name)

$listingOut = New-Item -ItemType Directory -Force (Join-Path $out 'listings')
Copy-Item (Join-Path $listingDir '*.md') $listingOut -Force
$shotOut = New-Item -ItemType Directory -Force (Join-Path $out 'screenshots')
Copy-Item (Join-Path $root 'docs/screenshots/store/*.png') $shotOut -Force
Move-Item (Join-Path $shotOut 'app-tile-300.png') (Join-Path $out 'app-tile-300.png') -Force
Write-Host "$($languages.Count) languages in $listingOut"
Write-Host "Screenshots in $shotOut"

# Our language key for one of Partner Center's language columns, such as
# "nl-nl", or $null for a column we have no texts for.
function LanguageFor([string]$header) {
  $h = $header.Trim().ToLowerInvariant()
  if ($languages -contains $h) { return $h }
  $base = $h.Split('-')[0]
  if ($base -eq 'zh') { return 'zh-cn' }
  if ($base -eq 'pt') { return 'pt-br' }
  if ($base -eq 'en') { return 'en-us' }
  if ($languages -contains $base) { return $base }
  return $null
}

# The text for a row of Partner Center's CSV, or $null to keep what it has.
function ValueFor([string]$field, $lang) {
  $key = ($field.ToLowerInvariant() -replace '[^a-z0-9]', '')
  if ($key -match '^(feature|searchterm|keyword)(\d+)$') {
    $items = if ($Matches[1] -eq 'feature') { @($lang.features) } else { @($lang.searchTerms) }
    $index = [int]$Matches[2] - 1
    if ($index -ge 0 -and $index -lt $items.Count) { return $items[$index] }
    return ''
  }
  switch ($key) {
    'description' { return $lang.description }
    'shortdescription' { return $lang.shortDescription }
    'releasenotes' { return $lang.releaseNotes }
    'whatsnew' { return $lang.releaseNotes }
    'title' { return $listings.common.name }
    'additionallicenseterms' { return $listings.common.licenseTerms }
  }
  if ($key.StartsWith('copyright')) { return $listings.common.copyright }
  return $null
}

if ($ListingCsv) {
  Step 'Filling the listing CSV'
  # Import-Csv cannot read the export as it is: its "ID" column and
  # Indonesian's "id" column are the same name to PowerShell. Read the rows
  # with numbered columns instead and write the header line back unchanged.
  $text = [IO.File]::ReadAllText((Resolve-Path $ListingCsv), [Text.Encoding]::UTF8)
  $newline = $text.IndexOf("`n")
  if ($newline -lt 0) { throw "$ListingCsv has no rows" }
  $headerLine = $text.Substring(0, $newline).TrimEnd("`r")
  $headers = @($headerLine.Split(',') | ForEach-Object { $_.Trim().Trim('"') })
  $names = @(for ($i = 0; $i -lt $headers.Count; $i++) { "c$i" })
  $bodyFile = Join-Path ([IO.Path]::GetTempPath()) 'cts-listing-rows.csv'
  [IO.File]::WriteAllText($bodyFile, $text.Substring($newline + 1), (New-Object Text.UTF8Encoding($false)))
  $rows = @(Import-Csv -Path $bodyFile -Header $names -Encoding UTF8)
  Remove-Item $bodyFile
  if ($rows.Count -eq 0) { throw "$ListingCsv has no rows" }

  # Field, ID, Type and default come first; every column after them is a
  # language (Indonesian's is "id").
  $used = @{}
  for ($i = 4; $i -lt $headers.Count; $i++) {
    $code = LanguageFor $headers[$i]
    if ($code) { $used["c$i"] = $code }
  }
  if ($used.Count -eq 0) { throw "No language columns in $ListingCsv ($($headers -join ', '))" }

  # New images can only come in with "Import folder": one folder with the
  # CSV (the only one in it) and the images, which the CSV names as
  # <folder>/<path>. They go in the default column, which every language
  # without its own uses, so one set of screenshots serves all languages.
  $importName = 'store-import'
  $importDir = Join-Path $out $importName
  if (Test-Path $importDir) { Remove-Item $importDir -Recurse -Force }
  $importShots = New-Item -ItemType Directory -Force (Join-Path $importDir 'screenshots')
  $shots = @(Get-ChildItem (Join-Path $out 'screenshots') -Filter *.png | Sort-Object Name)
  foreach ($shot in $shots) { Copy-Item $shot.FullName $importShots.FullName }
  Copy-Item (Join-Path $out 'app-tile-300.png') $importDir
  $images = @{}
  for ($n = 0; $n -lt $shots.Count; $n++) {
    $images["DesktopScreenshot$($n + 1)"] = "$importName/screenshots/$($shots[$n].Name)"
  }
  $images['StoreLogo300x300'] = "$importName/app-tile-300.png"

  $filled = 0
  foreach ($row in $rows) {
    $field = $row.c0
    if ($images.ContainsKey($field)) { $row.c3 = $images[$field]; $filled++; continue }
    foreach ($column in $used.Keys) {
      $value = ValueFor $field ($listings.languages.($used[$column]))
      if ($null -ne $value) { $row.$column = $value; $filled++ }
    }
  }

  # UTF-8 with a byte order mark and CRLF, as Partner Center exports it.
  $csvLines = @($headerLine) + @($rows | ConvertTo-Csv -NoTypeInformation | Select-Object -Skip 1)
  $csvOut = Join-Path $importDir 'listings-filled.csv'
  [IO.File]::WriteAllText($csvOut, ($csvLines -join "`r`n") + "`r`n", (New-Object Text.UTF8Encoding($true)))
  Write-Host "$filled fields filled for $(@($used.Values | Sort-Object -Unique) -join ', ')"
  Write-Host "$($shots.Count) screenshots and the app tile, for every language"
  $missing = @($languages | Where-Object { @($used.Values) -notcontains $_ })
  if ($missing.Count -gt 0) {
    Write-Host "Not in the export yet (they appear once the package is uploaded): $($missing -join ', ')" -ForegroundColor Yellow
  }
  Write-Host "Partner Center > Store listings > Import listings > Import folder, and pick: $importDir" -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# The package
# ---------------------------------------------------------------------------
$identityFile = Join-Path $out 'identity.json'
$msixPath = Join-Path $out 'ConvertTheSpireReborn.msix'

if (-not $ListingsOnly) {
  Step 'Package identity'
  $saved = $null
  if (Test-Path $identityFile) { $saved = Get-Content $identityFile -Raw -Encoding UTF8 | ConvertFrom-Json }
  if (-not $IdentityName -and $saved) { $IdentityName = $saved.identityName }
  if (-not $Publisher -and $saved) { $Publisher = $saved.publisher }
  if (-not $PublisherDisplayName -and $saved) { $PublisherDisplayName = $saved.publisherDisplayName }
  if (-not $DisplayName -and $saved) { $DisplayName = $saved.displayName }
  if (-not $DisplayName) { $DisplayName = $listings.common.name }
  if (-not $IdentityName -or -not $Publisher -or -not $PublisherDisplayName) {
    throw ('Give -IdentityName, -Publisher and -PublisherDisplayName once: Partner Center > ' +
      'the app > Product management > Product identity (Package/Identity/Name, ' +
      'Package/Identity/Publisher, Package/Properties/PublisherDisplayName).')
  }
  if ($Publisher -notmatch '^CN=') { throw '-Publisher starts with CN= (copy Package/Identity/Publisher exactly)' }
  [ordered]@{
    identityName = $IdentityName
    publisher = $Publisher
    publisherDisplayName = $PublisherDisplayName
    displayName = $DisplayName
  } | ConvertTo-Json | Set-Content -Path $identityFile -Encoding UTF8
  $version = (Select-String -Path (Join-Path $root 'pubspec.yaml') -Pattern '^version:\s*([0-9]+\.[0-9]+\.[0-9]+)').Matches[0].Groups[1].Value
  $msixVersion = "$version.0"
  Write-Host "$DisplayName $msixVersion / $IdentityName / $Publisher / $PublisherDisplayName"

  if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) { throw 'flutter is not on PATH' }
  $release = Join-Path $root 'build/windows/x64/runner/Release'

  if (-not $SkipBuild) {
    Step 'Building the Store build (takes a while)'
    $env:CXXFLAGS = '-D_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS'
    $env:CMAKE_CXX_FLAGS = '-D_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS'
    flutter pub get
    if ($LASTEXITCODE -ne 0) { throw 'flutter pub get failed' }
    # The same flutter_inappwebview fix as the release workflow.
    $pubCache = if ($env:PUB_CACHE) { $env:PUB_CACHE } else { Join-Path $env:LOCALAPPDATA 'Pub\Cache' }
    foreach ($file in @(
        (Join-Path $pubCache 'hosted\pub.dev\flutter_inappwebview_windows-0.6.0\windows\custom_platform_view\custom_platform_view.cc'),
        (Join-Path $root 'windows\flutter\ephemeral\.plugin_symlinks\flutter_inappwebview_windows\windows\custom_platform_view\custom_platform_view.cc'))) {
      if (Test-Path $file) {
        $text = Get-Content -Raw $file
        $patched = $text -replace '\bwebview_\b', 'view'
        if ($patched -ne $text) { Set-Content -Path $file -Value $patched -NoNewline; Write-Host "Patched $file" }
      }
    }
    flutter build windows --release --no-tree-shake-icons --dart-define=MS_STORE_BUILD=true
    if ($LASTEXITCODE -ne 0) { throw 'flutter build windows failed' }
  }
  if (-not (Test-Path (Join-Path $release 'convert_the_spire_reborn.exe'))) {
    throw "No build in ${release}: run without -SkipBuild"
  }

  Step 'FFmpeg, yt-dlp and Deno'
  $tools = New-Item -ItemType Directory -Force (Join-Path $out '.tools')
  function Fresh($path) {
    return (-not $RefreshTools) -and (Test-Path $path) -and
      ((Get-Item $path).LastWriteTime -gt (Get-Date).AddDays(-7))
  }
  function Download($url, $file) {
    for ($i = 1; $i -le 4; $i++) {
      try { Invoke-WebRequest -Uri $url -OutFile $file -UseBasicParsing; return }
      catch { Write-Host "Download failed ($i): $_"; Start-Sleep -Seconds (2 * $i) }
    }
    throw "Could not download $url"
  }
  $ffmpegZip = Join-Path $tools 'ffmpeg.zip'
  if (-not (Fresh $ffmpegZip)) { Download 'https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip' $ffmpegZip }
  $ytDlp = Join-Path $tools 'yt-dlp.exe'
  if (-not (Fresh $ytDlp)) { Download 'https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe' $ytDlp }
  $denoZip = Join-Path $tools 'deno.zip'
  if (-not (Fresh $denoZip)) { Download 'https://github.com/denoland/deno/releases/latest/download/deno-x86_64-pc-windows-msvc.zip' $denoZip }
  $licenses = Join-Path $tools 'licenses'
  New-Item -ItemType Directory -Force $licenses | Out-Null
  if (-not (Fresh (Join-Path $licenses 'yt-dlp.txt'))) { Download 'https://raw.githubusercontent.com/yt-dlp/yt-dlp/master/LICENSE' (Join-Path $licenses 'yt-dlp.txt') }
  if (-not (Fresh (Join-Path $licenses 'deno.txt'))) { Download 'https://raw.githubusercontent.com/denoland/deno/main/LICENSE.md' (Join-Path $licenses 'deno.txt') }

  $unpacked = Join-Path $tools 'ffmpeg'
  if (Test-Path $unpacked) { Remove-Item $unpacked -Recurse -Force }
  Expand-Archive $ffmpegZip $unpacked -Force
  $ffmpegExe = Get-ChildItem $unpacked -Recurse -Filter ffmpeg.exe | Select-Object -First 1
  $ffmpegDir = New-Item -ItemType Directory -Force (Join-Path $release 'ffmpeg')
  Copy-Item $ffmpegExe.FullName $ffmpegDir -Force
  Copy-Item (Join-Path $ffmpegExe.DirectoryName 'ffprobe.exe') $ffmpegDir -Force
  $ffmpegLicense = Get-ChildItem $unpacked -Recurse -Filter 'LICENSE*' | Select-Object -First 1
  if ($ffmpegLicense) { Copy-Item $ffmpegLicense.FullName (Join-Path $ffmpegDir 'LICENSE.txt') -Force }

  $ytDir = New-Item -ItemType Directory -Force (Join-Path $release 'yt-dlp')
  Copy-Item $ytDlp $ytDir -Force
  Copy-Item (Join-Path $licenses 'yt-dlp.txt') (Join-Path $ytDir 'LICENSE.txt') -Force

  $denoDir = New-Item -ItemType Directory -Force (Join-Path $release 'deno')
  Expand-Archive $denoZip $denoDir -Force
  Copy-Item (Join-Path $licenses 'deno.txt') (Join-Path $denoDir 'LICENSE.txt') -Force

  foreach ($run in @(@((Join-Path $ffmpegDir 'ffmpeg.exe'), '-version'),
                     @((Join-Path $ytDir 'yt-dlp.exe'), '--version'),
                     @((Join-Path $denoDir 'deno.exe'), '--version'))) {
    $output = & $run[0] $run[1]
    if ($LASTEXITCODE -ne 0) { throw "$($run[0]) does not run" }
    Write-Host "$(Split-Path -Leaf $run[0]): $(@($output)[0])"
  }
  @(
    'Programs that come with Convert The Spire Reborn (Microsoft Store version)',
    '',
    'FFmpeg (ffmpeg\) - GPL v3. Build by gyan.dev: https://www.gyan.dev/ffmpeg/builds/',
    '  Source code: https://ffmpeg.org/download.html and https://github.com/FFmpeg/FFmpeg',
    'yt-dlp (yt-dlp\) - The Unlicense. https://github.com/yt-dlp/yt-dlp',
    'Deno (deno\) - MIT. https://github.com/denoland/deno',
    '',
    'Each folder holds the program''s licence. They are separate programs that',
    'the app runs; the app''s own source: https://github.com/Lukas-Bohez/ConvertTheSpireFlutter'
  ) | Set-Content -Path (Join-Path $release 'THIRD-PARTY-PROGRAMS.txt') -Encoding UTF8

  Step 'Making the MSIX'
  if (Test-Path $msixPath) { Remove-Item $msixPath -Force }
  dart run msix:create --store `
    --identity-name $IdentityName `
    --publisher $Publisher `
    --publisher-display-name $PublisherDisplayName `
    --display-name $DisplayName `
    --version $msixVersion `
    --output-path $out
  if ($LASTEXITCODE -ne 0) { throw 'msix:create failed' }
  if (-not (Test-Path $msixPath)) { throw "No package at $msixPath" }

  Step 'Checking the package'
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $zip = [IO.Compression.ZipFile]::OpenRead($msixPath)
  try {
    $names = @($zip.Entries | ForEach-Object { $_.FullName })
    foreach ($need in @('convert_the_spire_reborn.exe', 'dll/flutter_windows.dll',
                        'ffmpeg/ffmpeg.exe', 'yt-dlp/yt-dlp.exe', 'deno/deno.exe',
                        'AppxManifest.xml')) {
      if ($names -notcontains $need) { throw "$need is not in the package" }
    }
    $reader = New-Object IO.StreamReader($zip.GetEntry('AppxManifest.xml').Open())
    [xml]$manifest = $reader.ReadToEnd()
    $reader.Close()
  } finally { $zip.Dispose() }
  $id = $manifest.Package.Identity
  if ($id.Name -ne $IdentityName -or $id.Publisher -ne $Publisher -or $id.Version -ne $msixVersion) {
    throw "The package identity ($($id.Name), $($id.Publisher), $($id.Version)) is not the one asked for"
  }
  Write-Host ('{0}: {1:N1} MB, {2} {3}' -f (Split-Path -Leaf $msixPath), ((Get-Item $msixPath).Length / 1MB), $id.Name, $id.Version) -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# What goes where
# ---------------------------------------------------------------------------
@"
Microsoft Store upload - Convert The Spire Reborn
(made by scripts\make_store_upload.ps1; the full guide is
docs\publishing\windows-store.md)

Packages
  Upload ConvertTheSpireReborn.msix. Device families: Windows 10/11 Desktop only.

Store listings (18 languages)
  Fastest: Store listings > Import/export Store listings > Export listings,
  then run
    .\scripts\make_store_upload.cmd -ListingsOnly -ListingCsv <the exported csv>
  and Import listings > Import folder > store-import (the CSV, the screenshots
  and the app tile, for every language). The other languages appear in the
  export once the package is uploaded (it declares all 18).
  By hand: listings\<language>.md has every field, ready to copy.

  Screenshots: screenshots\*.png (1920x1080). App tile icon: app-tile-300.png.

Submission options > Restricted capabilities (runFullTrust):
  Convert The Spire Reborn is a Win32 desktop app (Flutter). It needs full
  trust to run the FFmpeg, yt-dlp and Deno programs that come in the package
  as separate processes (to download and convert media), to accept incoming
  BitTorrent connections, to run a local media server for casting to TVs on
  the user's network, and to read and write media in the folders the user
  picks.

Add-on: Durable, product ID get_all_themes (exactly), 2.99, "All colours".
"@ | Set-Content -Path (Join-Path $out 'HOW-TO-UPLOAD.txt') -Encoding UTF8

Step 'Done'
Write-Host "Everything is in $out" -ForegroundColor Green
