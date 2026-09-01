#Requires -Version 5.1
# Moves non-essential plugin DLLs out or a Flutter Windows runner/Release folder
# into a dlls/ subfolder so the app folder isn't cluttered with dozens of DLLs.
# The executable direct imports (including flutter_windows.dll, the VC++ runtimes,
# and system DLLs) stay in the root; everything else Plugins) is moved into dlls/
# and loaded at runtime via SetDllDirectory (configured in main.cpp).
#
# This script is deliberately fail-soft: it never aborts its caller. Any failure
# is logged as a warning and the script exits 0, so packaging/builds never break.

param(
    [Parameter(Mandatory = $true)]
    [string]$BundleRoot,

    [Parameter(Mandatory = $true)]
    [string]$BinaryName
)

try {
    if (-not (Test-Path -LiteralPath $BundleRoot)) {
        Write-Warning "Bundle root not found: $BundleRoot"
        exit 0
    }

    $dllsDir = Join-Path $BundleRoot 'dlls'
    New-Item -ItemType Directory -Force -Path $dllsDir | Out-Null

    $exeName = "$BinaryName.exe"
    $keep = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    [void]$keep.Add($exeName)

    # DLLs that must stay in the root: the Flutter engine and the Visual C++
    # runtime DLLs. Plugins load these from the runner folder at startup.
    $alwaysKeep = @(
        'flutter_windows.dll',
        'flutter_windows.dll.pdb',
        'msvcp140.dll',
        'msvcp140_1.dll',
        'msvcp140_2.dll',
        'msvcp140_codecvt_ids.dll',
        'vcruntime140.dll',
        'vcruntime140_1.dll',
        'ucrtbase.dll',
        'concrt140.dll',
        'kernel32.dll',
        'user32.dll',
        'gdi32.dll',
        'advapi32.dll',
        'shell32.dll',
        'ole32.dll',
        'oleaut32.dll',
        'ws2_32.dll',
        'comdlg32.dll',
        'comctl32.dll',
        'shlwapi.dll',
        'winmm.dll'
    )
    foreach ($dll in $alwaysKeep) { [void]$keep.Add($dll) }

    # Any DLL that the exe directly imports (detected via dumpbin, when available)
    # should also stay in the root. Failure to find dumpbin is non-fatal.
    $exe = Join-Path $BundleRoot $exeName
    if (Test-Path -LiteralPath $exe) {
        $dumpbin = $null
        try { $dumpbin = (Get-Command dumpbin -ErrorAction Stop).Source } catch {}
        if (-not $dumpbin) {
            try {
                $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
                if (Test-Path $vswhere) {
                    $installPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2>$null | Select-Object -First  ?1
                    if ($installPath) {
                        $candidates = Get-ChildItem -LiteralPath (Join-Path $installPath 'VC\Tools\MSVC') -Filter 'dumpbin.exe' -Recurse -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName
                        $dumpbin = $candidates | Select-Object -First 1
                    }
                }
            } catch {}
        }
        if ($dumpbin) {
            $output = & $dumpbin /imports $exe 2>$null
            foreach ($line in $output) {
                if ($line -match '^  ([^ ]+\.dll)\s*$') {
                    [void]$keep.Add($Matches[1])
                }
            }
        }
    }

    $moved = 0
    foreach ($file in Get-ChildItem -LiteralPath $BundleRoot -Filter '*.dll' -File -ErrorAction SilentlyContinue) {
        if (-not $keep.Contains($file.Name)) {
            try {
                Move-Item -LiteralPath $file.FullName -Destination (Join-Path $dllsDir $file.Name) -Force
                $moved++
            } catch {
                Write-Warning "Could not move $($file.Name): $($_.Exception.Message)"
            }
        }
    }
    Write-Output "Organized plugin DLLs into $dllsDir ($moved moved)"
} catch {
    Write-Warning "DLL reorganization skipped: $($_.Exception.Message)"
}
exit 0
