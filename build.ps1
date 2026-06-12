<#
    build.ps1 — packt ein sauberes ModHub-Zip aus FS25_MyTodos.

    Whitelist-Ansatz: NUR die unten in $include gelisteten Dateien/Ordner
    landen im Zip. Alles andere (.git, .claude, *.md, LICENSE, icon.png,
    entities.json, mempalace.yaml, das Build-Skript selbst, das Zip selbst)
    bleibt automatisch draussen — genau die Dateien, die der GIANTS
    TestRunner sonst als ObsoleteFiles anmeckert.

    Gepackt wird via `git archive` aus HEAD — NICHT Compress-Archive:
    PS5.1/Compress-Archive schreibt Entry-Pfade mit BACKSLASH statt der
    ZIP-spec-konformen Forward-Slashes; FS25/manche Reader erkennen die
    Unterordner (scripts/gui, config/gui/pages) dann nicht und der Mod
    laedt nicht. Empirisch bestaetigt am 31.05. und erneut am 12.06.2026.

    KONSEQUENZ: Es wird der COMMITTETE Stand (HEAD) gepackt. Vor dem
    Bauen also committen — uncommittete Aenderungen landen NICHT im Zip.

    modDesc.xml liegt im Zip-Root (FS25-Pflicht), nicht in einem Unterordner.

    Aufruf:  powershell -ExecutionPolicy Bypass -File build.ps1
#>
$ErrorActionPreference = 'Stop'
$root    = Split-Path -Parent $MyInvocation.MyCommand.Path
$modName = 'FS25_MyTodos'

# Auszuliefernde Inhalte. Neue Shippable-Dateien hier ergaenzen.
# (Muessen in git getrackt sein — git archive packt nur HEAD-Inhalte.)
$include = @('modDesc.xml', 'icon_MyTodos.dds', 'scripts', 'l10n', 'config')

$zip = Join-Path $root ($modName + '.zip')
if (Test-Path $zip) { Remove-Item -Force $zip }

Push-Location $root
try {
    git archive --format=zip -o $zip HEAD @include
    if ($LASTEXITCODE -ne 0) { throw "git archive failed (exit $LASTEXITCODE)" }
} finally {
    Pop-Location
}

# Sanity-Check: keine Backslash-Entry-Pfade im Zip (siehe Header-Kommentar).
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::OpenRead($zip)
$badEntries = $archive.Entries | Where-Object { $_.FullName -match '\\' }
$archive.Dispose()
if ($badEntries) {
    throw "Zip enthaelt Backslash-Entry-Pfade: $($badEntries.FullName -join ', ')"
}

Write-Host "Built: $zip (aus git HEAD, Entry-Pfade verifiziert)"
Get-ChildItem $zip | Select-Object Name, Length
