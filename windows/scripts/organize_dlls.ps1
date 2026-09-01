#Requires -Version 5.1
param(
    [Parameter(Mandatory = $true)]
    [string]$BundleRoot,

    [Parameter(Mandatory = $true)]
    [string]$BinaryName
)

$ErrorActionPreference = 'Stop'

$dllsDir = Join-Path $BundleRoot 'dlls'
New-Item -ItemType Directory -Force -Path $dllsDir | Out-Null

$exe = Join-Path $BundleRoot "$BinaryName.exe"
$keep = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
[void]$keep.Add("$BinaryName.exe")

# Always keep the Flutter engine and the Visual C++ runtime DLLs in the root.
# These are either direct imports of the executable or required by the engine.
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

if (Test-Path $exe) {
    $dumpbin = $null
    try { $dumpbin = (Get-Command dumpbin -ErrorAction Stop).Source } catch {}

    if (-not $dumpbin) {
        $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
        if (Test-Path $vswhere) {
            $installPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath -errorAction SilentlyContinue | Select-Object -First 1
            if ($installPath) {
                $candidates = Get-ChildItem -Path (Join-Path $installPath 'VC\Tools\MSVC') -Filter 'dumpbin.exe' -Recurse -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName
                $dumpbin = $candidates | Select-Object -First 1
            }
        }
    }

    if ($dumpbin) {
        $output = & $dumpbin /imports $exe 2>$null
        foreach ($line in $output) {
            if ($line -match '^  ([^ ]+\.dll)\s*$') {
                [void]$keep.Add($Matches[1])
            }
        }
    } else {
        Write-Warning "dumpbin.exe not found; relying on the static keep list for root DLLs."
    }
}

foreach ($file in Get-ChildItem -Path $BundleRoot -Filter '*.dll' -File) {
    if (-not $keep.Contains($file.Name)) {
        Move-Item -Path $file.FullName -Destination (Join-Path $dllsDir $file.Name) -Force
    }
}

Write-Output "Organized plugin DLLs into $dllsDir"
