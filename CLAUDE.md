# FS25_MyTodos — Projekt-Memory

Farming Simulator 25 Mod. HUD-Overlay oben rechts das pro eigenem Feld
und jeder Tierhaltung die *nächste anstehende Aufgabe* zeigt.

Symlink: Code lebt in `OneDrive/Programming/FS25-Mods/FS25_MyTodos`,
FS25 lädt's per symlink aus dem Game-Mods-Ordner.

## Memory-Konvention

Tiefendoku zu Architektur, Samplern, PF-Phasen, Husbandry-Tabellen,
Mengen-Diagnose etc. liegt im **mempalace** (Wing `fs25_mytodos`).
**Vor jeder substantiellen Aufgabe `mempalace_search` mit passenden
Keywords aufrufen** — diese Datei hier hat nur die Punkte die immer
top-of-mind sein müssen.

Nützliche Such-Einstiege:
- `PF Phase 1 pH lime valueTransformations soilMap` — Kalk-Logik
- `PF Phase 3 N fertilize nitrogenMap fruitTypeIndexToFruitRequirement` — N-Logik
- `Schwad-Sampler Stroh Gras Heu DensityMapHeightUtil` — Windrows
- `Unkraut-Sampler weedSystem densityMap factors` — Unkraut
- `Stein-Sampler stoneSystem` — Steine
- `Tier-Husbandries spec_husbandryFood Pallets`
- `Lokalisierung l10n g_i18n MyTodos:t L10N_KEYS`
- `Ignorierte Felder ignoredFieldsAllSaves savegameIndex`
- `HUD-Anker InputHelpDisplay getHudMetrics`
- `Task-Derivation derivePrimaryVanilla cutStates Forage`
- `Settings TabbedMenu Courseplay fs25_settingsTitle` — GUI-Architektur
- `Helden Feld 29 wheat WHEAT aggregate empty` — Map-Edge-Case
- `HUD hide dialog _isAnyGuiOpen` — warum draw() drei Layer prüft
- `TODO-Snapshot` — aktuelle offene Punkte

Den **Stand**/Datums-Log und die `## Offene Themen`-Liste pflegen wir
ab jetzt im mempalace, nicht mehr hier.

## Design-Philosophie

Tool ist eine **Erinnerungs-Liste für erfahrene Spieler**, keine
Schritt-für-Schritt-Anleitung. Zielgruppe weiss bereits *wie* gespielt
wird — sie wollen nur den Überblick *was jetzt ansteht*. Daraus folgt:

- Keine Bonus-Optimierungs-Hinweise, keine Werkzeug-Empfehlungen, keine
  Tutorial-Erklärungen
- Filter ist scharf: nur wirklich actionable Tasks; passive
  Wachstumsphasen ohne Parallel-Tasks fliegen aus dem HUD

## Architektur (Kurzfassung)

- `modDesc.xml` — Mod-Manifest, registriert Lua-Files + zwei Actions
  (`MYTODOS_TOGGLE_SETTINGS` Alt+M, `MYTODOS_TOGGLE_HUD` RShift+T) +
  `<l10n filenamePrefix="l10n/l10n"/>`
- `scripts/MyTodos.lua` — Bootstrap, Lifecycle, HUD-Drawing,
  Settings-Persistenz, Hooks, Helpers (`t()`, `L10N_KEYS`,
  Ignore-API)
- `scripts/MyTodosFields.lua` — Field-Discovery, Task-Derivation
  (Vanilla + PF), alle Density-Map-Sampler (Windrow, Stone, Weed,
  pH, N, Soil), Düngen-Lockout-History
- `scripts/MyTodosHusbandry.lua` — Tier-Discovery + Task-Derivation
- `scripts/MyTodosCommands.lua` — alle `mt*`-Konsolenbefehle
- `scripts/gui/` + `config/gui/` — Settings-Menü als vollwertiges
  TabbedMenu im Stil des FS25-ESC-Menüs (3 Tabs: Allgemein, Tiere,
  Felder). Architektur orientiert an Courseplay's CpInGameMenu, Details
  im mempalace-Drawer. Alt+M publiziert `GUI_MYTODOS_OPEN` an den
  MessageCenter, der Subscriber öffnet den Screen.
- `l10n/l10n_<lang>.xml` — DE, EN, FR, IT
- Settings: `<UserProfileApp>/modSettings/MyTodos.xml` (Toggles +
  Schwellwerte + Ignore-Liste pro Save+FarmId)

**File-Split-Konvention**: alle Files erweitern dieselbe
`MyTodos`-Tabelle via `function MyTodos:foo()`. Reihenfolge in
`modDesc.xml`: `MyTodos.lua` zuerst (initialisiert die Tabelle), Rest
danach. Console-Command-Callbacks sind String-Namen, erst zur
Aufrufzeit aufgelöst → Reihenfolge dort egal.

## Workflow-Regel

**Lua-Scripts werden nur beim Spielstart geladen.** Nach jeder Code-
Änderung **FS25 komplett beenden und neu starten**, sonst läuft die
alte Version weiter. `mtRescan` reloadet nur Daten, nicht Code.

## Wichtigste Stolpersteine (bitte nicht vergessen)

1. **`fs.rollerLevel` ist INVERTIERT**: 1 = "muss gewalzt werden",
   0 = OK. Alle anderen Levels sind normal (höher = mehr getan).
2. **`field.polygonPoints` sind Engine-Node-IDs**, keine Koordinaten —
   `getWorldTranslation(nodeId)` darauf, nicht direkt verwenden.
3. **`field.fieldState` ist ein Aggregat**, das die Engine periodisch
   im Hintergrund berechnet. Hängt nach Aktionen Sekunden bis Minuten
   hinterher. Manche Maps haben auch genuinely blinde Felder (siehe
   mempalace-Drawer "Helden Feld 29") — Workaround dort ist `mtIgnore`.
4. **`fs.stoneLevel` ist nutzlos**, bleibt 0 trotz sichtbarer Steine.
   Direkt `g_currentMission.stoneSystem.densityMap` polygon-sampeln.
5. **User-facing Feldnummer ≠ Tabellen-Key**: `g_fieldManager:getFields()`-
   Key ist interne FieldManager-ID. Die Nummer auf der Karte liegt auf
   `field.farmland.name` (Zahl-String, auf modded Maps potentiell ein
   echter Name wie "North Pasture"). Cross-validated mit
   `FS25_FarmlandOverview`-Mod der dasselbe Feld benutzt.
   `getName(field.nameIndicator)` ist eine Sackgasse.
6. **Save-Identifikation**: `missionInfo.savegameIndex` (Slot-Nummer)
   nehmen, **nicht** `savegameName` — letzterer ist user-renamable
   und kann leer oder über Saves identisch sein.
7. **`fillType.textureArrayIndex`** ist das Mapping zu internem Type-
   Wert in der Density-Map (für Schwad-Sampling).
8. **Schwad-Sampling braucht Height-Check** zusätzlich zu Type, sonst
   kommen Restpixel als false positives durch.

## Konsolen-Befehle (Übersicht; Details im mempalace)

- `mtRescan` — Force-Rescan aller Felder/Husbandries
- `mtSettings` — Settings-Dialog öffnen
- `mtDump <feldNr>` — `fieldState` + Frucht-Properties dumpen
- `mtForceUpdate <feldNr>` — `field:updateState()` triggern + log
- `mtFields` / `mtListOwned` / `mtFindField <feldNr>` — Feld-Listen
- `mtIgnore <feldNr>` / `mtUnignore <feldNr>` — HUD-Filter
- `mtWhereAmI` / `mtFruitHere` — Position-/Frucht-Probe am Trecker
- `mtProbe[Windrow|WindrowAt|Stones|Weed|Husbandry|HusbandryDeep|Pf]` — Diagnose-Probes
- `mtDebugPf <feldNr>` — pH/N/Soil-Histogramm im Feld-Polygon

## Standard-Workflow für Test

1. FS25 beenden, neu starten
2. Save laden
3. `mtRescan` (oder `mtDump <feldNr>` für Detail-Diagnose)
4. Im Log nach `[MyTodos]`-Zeilen schauen
