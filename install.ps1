# Installs or updates Convert The Spire Reborn on Windows, for your account
# only, with no administrator rights.
#
#   irm https://raw.githubusercontent.com/Lukas-Bohez/ConvertTheSpireFlutter/main/install.ps1 | iex
#
# What it does, and nothing else:
#   1. Asks GitHub for the latest release.
#   2. Downloads ConvertTheSpireReborn-windows-x64.zip and the release's
#      SHA256SUMS.txt, and stops if the zip does not match its checksum.
#   3. Unpacks it to %LOCALAPPDATA%\Programs\ConvertTheSpireReborn, replacing
#      an older version there. Your settings and downloads live elsewhere and
#      are kept.
#   4. Adds the app to the Start menu and starts it.
#
# To uninstall, delete that folder and the Start menu entry.
#
# Keep this file ASCII and compatible with Windows PowerShell 5.1, the
# PowerShell every Windows 10 and 11 PC has.

& {
    $ErrorActionPreference = 'Stop'
    $ProgressPreference = 'SilentlyContinue'  # the progress bar makes downloads crawl on 5.1

    $repo = 'Lukas-Bohez/ConvertTheSpireFlutter'
    $zipName = 'ConvertTheSpireReborn-windows-x64.zip'
    $exeName = 'convert_the_spire_reborn.exe'
    $appName = 'Convert The Spire Reborn'
    $installDir = Join-Path $env:LOCALAPPDATA 'Programs\ConvertTheSpireReborn'

    function Step($text) { Write-Host "  $text" }

    try {
        # GitHub only speaks TLS 1.2+, which older .NET does not offer by default.
        [Net.ServicePointManager]::SecurityProtocol =
            [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

        Write-Host ''
        Write-Host "Installing $appName" -ForegroundColor Cyan

        $release = Invoke-RestMethod -UseBasicParsing `
            -Uri "https://api.github.com/repos/$repo/releases/latest" `
            -Headers @{ 'User-Agent' = 'ConvertTheSpire-installer' }
        $zipAsset = $release.assets | Where-Object { $_.name -eq $zipName } | Select-Object -First 1
        $sumAsset = $release.assets | Where-Object { $_.name -eq 'SHA256SUMS.txt' } | Select-Object -First 1
        if (-not $zipAsset -or -not $sumAsset) {
            throw "Release $($release.tag_name) has no $zipName or SHA256SUMS.txt."
        }
        Step "Version $($release.tag_name)"

        $work = Join-Path ([IO.Path]::GetTempPath()) ('cts-install-' + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $work | Out-Null
        $unpacked = $null
        try {
            $zip = Join-Path $work $zipName
            Step ("Downloading ({0:N0} MB)..." -f ($zipAsset.size / 1MB))
            Invoke-WebRequest -UseBasicParsing -Uri $zipAsset.browser_download_url -OutFile $zip
            $sums = (Invoke-WebRequest -UseBasicParsing -Uri $sumAsset.browser_download_url).Content
            if ($sums -is [byte[]]) { $sums = [Text.Encoding]::UTF8.GetString($sums) }

            # Lines look like "<sha256>  ./windows-x64/ConvertTheSpireReborn-windows-x64.zip".
            $expected = $null
            foreach ($line in ($sums -split "`r?`n")) {
                $parts = $line.Trim() -split '\s+', 2
                if ($parts.Count -eq 2 -and ($parts[1] -split '[\\/]')[-1] -eq $zipName) {
                    $expected = $parts[0].ToLowerInvariant()
                }
            }
            if (-not $expected) { throw "SHA256SUMS.txt has no line for $zipName." }
            $actual = (Get-FileHash -Algorithm SHA256 -Path $zip).Hash.ToLowerInvariant()
            if ($actual -ne $expected) {
                throw "The download does not match its checksum (got $actual, expected $expected). Nothing was installed; try again."
            }
            Step 'Checksum OK'

            # Unpack next to the install folder, so the swap below is a
            # rename on the same drive.
            $parent = Split-Path $installDir -Parent
            if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent | Out-Null }
            $unpacked = "$installDir.new-" + [Guid]::NewGuid().ToString('N')
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            [IO.Compression.ZipFile]::ExtractToDirectory($zip, $unpacked)
            if (-not (Test-Path (Join-Path $unpacked $exeName))) {
                throw "$exeName is missing from the download."
            }

            # The files of a running copy are locked; wait for it to close.
            $exePath = Join-Path $installDir $exeName
            while (Get-Process -Name ([IO.Path]::GetFileNameWithoutExtension($exeName)) -ErrorAction SilentlyContinue |
                    Where-Object { $_.Path -eq $exePath }) {
                Read-Host "  $appName is open. Close it, then press Enter" | Out-Null
            }

            # Swap the new version in. The folder belongs to this installer
            # alone, so replacing it whole is safe; the old copy is only
            # removed once the new one is in place.
            $old = $null
            if (Test-Path $installDir) {
                $old = "$installDir.old-" + [Guid]::NewGuid().ToString('N')
                Move-Item -LiteralPath $installDir -Destination $old
            }
            try {
                Move-Item -LiteralPath $unpacked -Destination $installDir
            } catch {
                if ($old) { Move-Item -LiteralPath $old -Destination $installDir }
                throw
            }
            if ($old) { Remove-Item -LiteralPath $old -Recurse -Force -ErrorAction SilentlyContinue }
            Step "Installed to $installDir"
        } finally {
            Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
            if ($unpacked -and (Test-Path -LiteralPath $unpacked)) {
                Remove-Item -LiteralPath $unpacked -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        try {
            $programs = [Environment]::GetFolderPath('Programs')
            $shell = New-Object -ComObject WScript.Shell
            $link = $shell.CreateShortcut((Join-Path $programs "$appName.lnk"))
            $link.TargetPath = $exePath
            $link.WorkingDirectory = $installDir
            $link.Description = $appName
            $link.Save()
            Step 'Added to the Start menu'
        } catch {
            Write-Warning "Could not add a Start menu entry: $($_.Exception.Message)"
        }

        Write-Host "Done. Starting $appName..." -ForegroundColor Green
        Start-Process -FilePath $exePath -WorkingDirectory $installDir
    } catch {
        Write-Host ''
        Write-Host "Install failed: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "You can still download the zip from https://github.com/$repo/releases/latest"
        # A window opened just for this (Win+R) would close before the
        # message could be read.
        Read-Host 'Press Enter to close' | Out-Null
    }
}
