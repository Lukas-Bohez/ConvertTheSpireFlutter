<#
    BitPlayer code-style self-check

    Re-runs the same checks used in the audit (bitplayer_human_code_style_audit_findings.md)
    directly against your local checkout, so you can watch the counts move
    without waiting on Cline to report back. Read-only - makes no changes.

    Usage:
        cd C:\development\ConversionFlutter\my_flutter_app
        .\bitplayer_code_style_selfcheck.ps1

    Baseline (from the original audit, for comparison):
        overflow-fix comments        : 30 hits / 16 files
        templated 'X failed: $e'     : 125 hits / 52 files (of 260 total catches)
        fully silent catch (_) {}    : 212 hits
        decorative banner dashes     : 78 hits
        narrated BUG-N / FIX SUMMARY : 64 hits
        CRLF files                   : 74   LF files: 111
#>

$ErrorActionPreference = "Stop"

$libPath = Join-Path (Get-Location) "lib"
if (-not (Test-Path $libPath)) {
    Write-Host "Run this from the Flutter project root (the folder containing lib\)." -ForegroundColor Red
    exit 1
}

$dartFiles = Get-ChildItem -Path $libPath -Recurse -Filter "*.dart"
Write-Host "=== BitPlayer code-style self-check ===" -ForegroundColor Cyan
Write-Host "Dart files scanned: $($dartFiles.Count)"
Write-Host ""

# Read every file once and reuse it for all checks below.
$contents = @{}
foreach ($f in $dartFiles) {
    $contents[$f.FullName] = Get-Content -LiteralPath $f.FullName -Raw
}

function Measure-Pattern {
    param(
        [string]$Pattern,
        [switch]$IgnoreCase,
        [switch]$Multiline
    )
    $opts = [System.Text.RegularExpressions.RegexOptions]::None
    if ($IgnoreCase) { $opts = $opts -bor [System.Text.RegularExpressions.RegexOptions]::IgnoreCase }
    if ($Multiline)  { $opts = $opts -bor [System.Text.RegularExpressions.RegexOptions]::Multiline }

    $totalHits = 0
    $fileHits = 0
    foreach ($text in $contents.Values) {
        $m = [regex]::Matches($text, $Pattern, $opts)
        if ($m.Count -gt 0) {
            $totalHits += $m.Count
            $fileHits += 1
        }
    }
    New-Object PSObject -Property @{ Hits = $totalHits; Files = $fileHits }
}

function Show-Row {
    param([string]$Label, $Result, [string]$Target)
    "{0,-38} {1,5} hits in {2,3} files   ({3})" -f $Label, $Result.Hits, $Result.Files, $Target | Write-Host
}

# Audit Finding 1
Show-Row "overflow-fix comment sweep" (Measure-Pattern -Pattern 'overflow-fix') "target: 0"

# Audit Finding 3a / 3b
Show-Row "templated 'X failed: `$e' catches" (Measure-Pattern -Pattern 'catch\s*\(e[^)]*\)\s*\{\s*(debugPrint|print)\(') "target: near 0, each a deliberate choice"
Show-Row "fully silent catch (_) {}" (Measure-Pattern -Pattern 'catch\s*\(_\)\s*\{\s*\}') "target: 0, or a reason comment"

# Audit Finding 5 (box-drawing dash, built from its code point to dodge script-encoding issues)
$boxDrawingDash = [char]0x2500
Show-Row "decorative banner dashes" (Measure-Pattern -Pattern $boxDrawingDash) "target: 0"

# Audit Finding 2
Show-Row "narrated BUG-N / FIX SUMMARY" (Measure-Pattern -Pattern '(BUG\s*\d*[: ]|ROOT CAUSE|FIX SUMMARY)' -IgnoreCase) "target: 0, moved to CHANGELOG.md"

Write-Host ""
Write-Host "=== Line-ending consistency (audit Finding 4) ===" -ForegroundColor Cyan
$crlf = 0
$lf = 0
foreach ($text in $contents.Values) {
    if ($text -match "`r`n") { $crlf++ } else { $lf++ }
}
"CRLF files: {0}   LF files: {1}   (target: 0 CRLF once .gitattributes is applied and re-checked out)" -f $crlf, $lf | Write-Host

Write-Host ""
Write-Host "=== Import style - informational only, Finding 7 is NOT enforced ===" -ForegroundColor DarkGray
Show-Row "relative imports (../)" (Measure-Pattern -Pattern "^import '\.\./" -Multiline) "no target"
Show-Row "absolute self-package imports" (Measure-Pattern -Pattern "^import 'package:convert_the_spire_reborn/" -Multiline) "no target"

Write-Host ""
Write-Host "Compare against the baseline in this script's header, or against" -ForegroundColor DarkGray
Write-Host "bitplayer_human_code_style_audit_findings.md, to see progress." -ForegroundColor DarkGray
