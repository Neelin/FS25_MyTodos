<#
    build.ps1 — packt ein sauberes ModHub-Zip aus FS25_MyTodos.

    Whitelist-Ansatz: NUR die unten in $include gelisteten Dateien/Ordner
    landen im Zip. Alles andere (.git, .claude, *.md, LICENSE, icon.png,
    entities.json, mempalace.yaml, das Build-Skript selbst, das Zip selbst)
    bleibt automatisch draussen — genau die Dateien, die der GIANTS
    TestRunner sonst als ObsoleteFiles anmeckert.

    modDesc.xml liegt im Zip-Root (FS25-Pflicht), nicht in einem Unterordner.

    Aufruf:  powershell -ExecutionPolicy Bypass -File build.ps1
#>
$ErrorActionPreference = 'Stop'
$root    = Split-Path -Parent $MyInvocation.MyCommand.Path
$modName = 'FS25_MyTodos'

# Auszuliefernde Inhalte. Neue Shippable-Dateien hier ergaenzen.
$include = @('modDesc.xml', 'icon_MyTodos.dds', 'scripts', 'l10n', 'config')

$stage = Join-Path $env:TEMP ("build_" + $modName)
if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
New-Item -ItemType Directory -Force -Path $stage | Out-Null

foreach ($item in $include) {
    $srcPath = Join-Path $root $item
    if (-not (Test-Path $srcPath)) { throw "Shippable item fehlt: $item" }
    Copy-Item $srcPath $stage -Recurse
}

$zip = Join-Path $root ($modName + '.zip')
if (Test-Path $zip) { Remove-Item -Force $zip }
Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zip -CompressionLevel Optimal
Remove-Item -Recurse -Force $stage

Write-Host "Built: $zip"
Get-ChildItem $zip | Select-Object Name, Length
