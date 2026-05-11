# FS25_MyTodos — Projekt-Memory

Farming Simulator 25 Mod. HUD-Overlay rechts oben das pro eigenem Feld die "nächste Aufgabe" anzeigt.
Symlink ist gesetzt: Code lebt in `OneDrive/Programming/FS25-Mods/FS25_MyTodos`,
FS25 lädt's per symlink aus dem Game-Mods-Ordner.

**Wichtig**: Lua-Scripts werden nur **beim Spielstart** geladen. Nach Code-Änderungen FS25 komplett beenden+neustarten, sonst läuft alte Version.

## Design-Philosophie

Das Tool ist eine **Erinnerungs-Liste für erfahrene Spieler**, keine Schritt-für-Schritt-Anleitung. Zielgruppe weiss bereits *wie* gespielt wird — sie wollen nur den Überblick behalten *was jetzt ansteht*. Daraus folgt:

- Bonus-Optimierungs-Hinweise (z.B. 100%-Gras-Bonus durch Saat-Walze) gehören **nicht** rein.
- Werkzeug-Empfehlungen ("Striegel" vs "Hackmaschine") werden bewusst nicht prescribed — Spieler entscheidet selbst.
- Keine Tutorial-Erklärungen wann/warum.
- Filter ist scharf: nur wirklich actionable Tasks ins HUD, passive Wachstumsphasen ohne Parallel-Tasks werden ausgeblendet.

---

## Architektur

- `modDesc.xml` — Mod-Manifest, registriert alle Lua-Files + zwei Actions:
  `MYTODOS_TOGGLE_SETTINGS` (Default `Alt+M`) oeffnet/schliesst Settings-Dialog,
  `MYTODOS_TOGGLE_HUD` (Default `RShift+T`) blendet das HUD an/aus.
- `scripts/MyTodos.lua` — Bootstrap, Lifecycle, HUD-Drawing, Settings-Persistenz, Hooks. Definiert die globale `MyTodos`-Tabelle, alle anderen Files erweitern sie.
- `scripts/MyTodosFields.lua` — Field-Discovery, Task-Derivation (vanilla), alle 3 Density-Map-Sampler (Windrow, Stone, Weed), Düngen-Lockout-History
- `scripts/MyTodosHusbandry.lua` — Tier-Husbandries. Aktuell nur Probe-Logik, echte Discovery + Tasks kommen.
- `scripts/MyTodosCommands.lua` — alle `mt*`-Konsolenbefehle
- `scripts/MyTodosSettingsScreen.lua` — minimaler ScreenElement-Subclass für das Settings-Menü als echter GUI (entkoppelt Maus von Kamera wie ESC)
- `config/MyTodosSettingsScreen.xml` — minimal-XML für den ScreenElement
- Settings-Persistence: `<UserProfileApp>/modSettings/MyTodos.xml` (nur Toggles + Schwellwerte. HUD-Position wird NICHT persistiert weil dynamisch aus InputHelp-Anker abgeleitet.)

**File-Split-Konvention**: alle Files erweitern dieselbe `MyTodos`-Tabelle via `function MyTodos:foo()`. Die Tabelle wird in `MyTodos.lua` als `MyTodos = {}` initialisiert — alle anderen Files müssen in `modDesc.xml` danach gelistet sein. Console-Commands haben Callback-Method-Namen als String, die werden erst zur Aufrufzeit aufgelöst, daher Reihenfolge dort egal.

## Hooks

- `Mission00.load` → `onMissionLoaded` (server/client flags)
- `BaseMission.loadMapFinished` → `onMapLoaded` (registriert Updateable, Actions, GUI)
- `BaseMission.draw` → HUD zeichnen
- `g_currentMission:addUpdateable(self)` → Update-Tick für Polling

## HUD-Position (Anker statt Drag)

HUD-Position wird pro Frame dynamisch aus Giants' `InputHelpDisplay`
abgeleitet (das F1-Hilfepanel oben links). Logik in `MyTodos:getHudAnchor()`:

- `g_currentMission.hud.inputHelp:getPosition()` → linke obere Ecke des
  Hilfepanels
- `inputHelp.lineBg.width` → Breite einer Hilfezeile (3-slice background,
  von Giants in `storeScaledValues` auf 330px-skaliert gesetzt)
- MyTodos linke obere Ecke = `(posX + width + HUD_ANCHOR_MARGIN_X, posY)`
- Fallback wenn inputHelp/lineBg noch nicht initialisiert: `g_hudAnchorLeft + margin, g_hudAnchorTop`
- **Kein Visibility-Check**: F1 setzt nur `setVisible(false)`, die Geometrie
  bleibt gepflegt. So springt MyTodos nicht an die linke Bildschirmkante
  wenn der Spieler die Hilfe ausblendet.

HUD an/aus wird ausschliesslich ueber `MYTODOS_TOGGLE_HUD` (Default
`RShift+T`) oder den `hudVisible`-Toggle im Settings-Dialog gesteuert.
Persistiert in `MyTodos.xml`.

## Konsolen-Befehle (zum Debuggen)

- `mtRescan` — sofort neuer Field-Scan (statt 5s Polling)
- `mtDump <fieldId>` — `field.fieldState` + Frucht-Properties + `growthStateToName` + `cutStates` ausgeben
- `mtForceUpdate <fieldId>` — `field:updateState()` triggern und Vorher/Nachher
- `mtProbe [fieldId]` — FS25-API-Surface dumpen (FieldUtil, FSDensityMapUtil, fieldGroundSystem, FieldDensityMap, field-Metatable)
- `mtProbeWindrow` — fillType / DensityMapHeightUtil API
- `mtProbeWindrowAt <fieldId>` — Live-Sampling testen (type/height channels, polygon)
- `mtProbeStones <fieldId>` — Stein-Sampling testen (`getStoneArea`, `getStoneLevelAtWorldPos`, polygon-Sweep über alle Werte 0..7)
- `mtProbeWeed <fieldId>` — Unkraut-Sampling testen (`getWeedFactor`, `weedSystem.factors`, polygon-Sweep über alle Werte 0..15)
- `mtProbeHusbandry` — Tier-Placeable-API dumpen: `g_currentMission.placeableSystem.placeables`, eigene Husbandries filtern, alle `spec_husbandry*`-Specs auf Top-Level ausgeben
- `mtProbeHusbandryDeep` — Tieferer Probe: dumpt die inneren Tabellen (fillLevels, supportedFillTypes, currentPallets, clusterHusbandry, meadow.fillLevels), listet Methoden der `PlaceableHusbandry`- und `clusterHusbandry`-Klassen via Metatable
- `mtSettings` — Settings-Dialog öffnen (statt Alt+M)

---

## Field-Discovery

- `g_fieldManager:getFields()` — Tabelle `{[internalId] = field, ...}`. Der **Schlüssel** ist eine interne ID des FieldManagers, **nicht** die User-facing-Feldnummer auf der Map!
- `field.farmland.id` → `g_farmlandManager:getFarmlandOwner(id)` → wir filtern auf `g_currentMission:getFarmId()`
- `field.fieldId`, `field.id`, `field.fieldNumber`, `field.name` existieren in FS25 alle **nicht** (alle nil)
- **User-facing Feldnummer**: liegt auf **`field.farmland.name`** (typischerweise ein Zahl-String wie `"3"`, auf modded Maps potentiell ein echter Name). In `collectOwnedFields` mit Fallback-Kette `farmland.name → farmland.id → Tabellen-Key`. Cross-validated mit `FS25_FarmlandOverview`-Mod der ebenfalls `thisFarmland.name` als Anzeige nutzt.
- `field.nameIndicator` ist NUR die Engine-Node-ID des 3D-Schild-Assets — `getName()` darauf liefert den generischen Asset-Namen `"fieldMapIndicator"`, nicht die Feldnummer. Sackgasse, nicht nutzen.
- Auf manchen Maps (z.B. highlandsFishingPack DLC) sind Tabellen-Key und farmland.name zufällig gleich. Auf Vanilla-Maps können sie deutlich auseinanderlaufen (z.B. key=30 → User sieht "3" auf der Karte = `farmland.name`).

## fieldState (FS25 Vanilla)

Ist ein **Aggregat**, kein Live-Sample — wird intern periodisch von der Engine berechnet (siehe `g_fieldManager.pendingFieldUpdates`/`fieldStateUpdateIndex`/`updateTasks`). Hängt nach Aktionen ein paar Sekunden bis zu Minuten hinterher. `field:updateState()` triggert NICHT synchron, läuft im Hintergrund.

Felder im fieldState die wir nutzen:
- `fruitTypeIndex` — 0 = leer, sonst Frucht (oder Stoppel der Frucht)
- `growthState` — frucht-spezifisch
- `lastGrowthState` — vorheriger Tick (für Detection nicht zuverlässig)
- `plowLevel` (max=1, binary)
- `limeLevel` (max=3, in Vanilla aber praktisch boolean — eine Anwendung füllt direkt auf 3)
- `sprayLevel` (max=2), `sprayType`
- `weedState` — **Aggregat**, taugt nicht zuverlässig. Quelle ist `g_currentMission.weedSystem.densityMap` direkt (siehe Unkraut-Sampler unten). Skala 0..9 (siehe Sampler-Doku).
- `weedFactor` — Aggregat, ebenfalls nicht zuverlässig (kann 0 sein obwohl Engine via `getWeedFactor` 30%+ liefert).
- `stubbleShredLevel` (0 = nicht gemulcht)
- `rollerLevel` — **INVERTIERT!** 0 = OK, 1 = muss gewalzt werden (vom User durch Cheat-Tool empirisch bestätigt — alle anderen Levels: höher = mehr getan)
- `stoneLevel` — **nutzlos!** Bleibt 0 selbst bei sichtbar vielen Big Stones (per Cheat-Tool bestätigt). `field:updateState()` ändert das nicht. Quelle ist stattdessen `g_currentMission.stoneSystem.densityMap` — siehe Stein-Sampler unten.
- `farmlandId`, `ownerFarmId` — diese stimmen NICHT immer (oft Bitmasks/Ghost-Werte beim noch-nicht-aktualisierten Aggregat). Source of truth für Ownership ist `field.farmland.id` + `g_farmlandManager:getFarmlandOwner()`.

## Frucht-Properties (`g_fruitTypeManager:getFruitTypeByIndex(i)`)

Wichtige Flags:
- `regrows` (true für Gras → Lifecycle ohne Pflug/Grubber/Saat)
- `consumesLime` (false bei Gras → Kalk bringt nichts)
- `plantsWeed` (false bei Gras → kein Unkraut)
- `needsRolling` (true bei Gras + manchen Cerealien wie Hafer)
- `firstRegrowthState` (Wert auf den growthState nach Mähen springt)
- `minHarvestingGrowthState` / `maxHarvestingGrowthState`
- `cutState` (growthState direkt nach Ernte) — bei manchen Fruechten **nur** der terminale Cut
- `cutStates` (Tabelle `{state=true, ...}`) — alle moeglichen post-cut states. Bei Mehrfach-Ernte (Spinat: `{9,10}`, `minHarvest=6 < maxHarvest=7`) ist state 9 ein Zwischen-Cut der regrowt. Bei Mais (`{9,10}`, `minHarvest=maxHarvest=7`) sind beide finale Cuts (Forage-Ende oder Koerner-Ende). Heuristik zur Unterscheidung: Multi-Cut-Regrowth nur wenn `minHarvest < maxHarvest`.
- `minForageGrowthState` / `maxForageGrowthState` — untere/obere Grenze fuer Haecksel/Forage-Ernte. Mais 5..5 hat echte Forage. Wheat 7..7 und Canola 8..8 sind nominell gesetzt aber Vanilla funktional tot (kein Haecksler nimmt was auf). Heuristik: nur als "Forage" labeln wenn `minForage + 1 < minHarvest` (echte Range vor Trockenernte). Bei Fruechten ohne Forage = 0/0.
- `rolledCutState` (Gras: nach Walzen)
- `witheredState`
- `minPreparingGrowthState` / `maxPreparingGrowthState` / `preparedGrowthState` — fuer Wurzelfruechte (Kartoffel, Zuckerruebe etc.) muss vor der Ernte eine Vorbereitungs-Aktion (Krautschlegeln/Kappen) erfolgen, die growthState in `preparedGrowthState` setzt. Bei Cerealien wie Weizen alle drei `-1`.
- `growthStateToName` (Tabelle int → string, z.B. Gras: 1=invisible, 2=greenSmall, 3=greenMiddle, 4=harvestReady, 5=cut, 6=cutRolled)

`g_fieldManager.sprayLevelMaxValue=2`, `plowLevelMaxValue=1`, `limeLevelMaxValue=3`.

## Game-Settings

- `g_currentMission.missionInfo.plowingRequiredEnabled` — Boolean. Wenn false, "Pflügen" wird nicht vorgeschlagen.

---

## Task-Derivation (Vanilla)

In `derivePrimaryVanilla(fs, fruit)` Reihenfolge:

1. Wenn Frucht da:
   - `growth == witheredState` → "X: Verwelkt" (actionable)
   - **regrowing-Pfad** (Gras, Sugarcane etc.): keine Pflug/Grubber/Saat-Logik. `growth in cut/rolledCut` → passive "X: gemäht". Erntefähig: bei Fruechten mit `minPreparingGrowthState>=1` (Sugarcane: minPrep=8, max=11) → Range `[minPrep..maxHarvest]` (Spieler kann ohne oder mit Preparing-Stadium ernten); ohne Preparing (Gras) nur bei `growth==maxHarvest`. Sonst "X: Wächst (gs/max)" passive.
   - Sonst (non-regrowing): `growth in cutStates` → wenn `minHarvest<maxHarvest` und `growth!=cutState` → "X: Wächst nach" passive (Spinat-Pattern); sonst Prep-Pfad (final cut). `growth in [minForage..minHarvest-1]` und `minForage+1<minHarvest` → "X: Forage" (Mais 5-6; Wheat/Canola gefiltert weil funktional tot). Range `[min(minPrep>0, minHarvest)..maxHarvest]` → "Ernten" (Wurzelfruechte mit Krautschlag mit drin). `weedLabel(field, fs) != nil` → "X: Unkraut klein/groß (X%)". Sonst "X: Wächst (gs/max)" passive.
2. Kein Frucht-Index: Prep-Pfad.

**Prep-Pfad** (`derivePrepTask`):
- `plowReq && plowLevel==0` → "Pflügen"
- `isSeedbedReady(fs)` (groundType in `[fieldGroundSystem.firstSowableValue..lastSowableValue]`) → "Säen"
- Sonst → "Grubbern"

**Parallel-Tasks** (`deriveParallelVanilla`):
- "Düngen X/2" wenn (non-regrowing) Frucht wächst, sprayLevel<2, und nicht im **Lockout** (siehe unten)
- "Walzen" wenn `fruit.needsRolling && rollerLevel > 0` (invertiert!) **und** im sicheren Walzen-Fenster: non-regrowing → `growth <= 1` (frisch gesät), regrowing → `growth == cutState` (frisch gemäht). Sonst zerstört Walzen das Wachstum bzw. die Frucht.
- "Mulchen" wenn (non-regrowing) atCut && stubbleShredLevel==0
- "Kalken" wenn `limeLevel == 0 && (fruit==nil || fruit.consumesLime != false)`
- "Steine" via Density-Map-Sampling auf `g_currentMission.stoneSystem.densityMap` (siehe Stein-Sampler) — `fs.stoneLevel` ist nutzlos
- Schwadläden ("Stroh aufnehmen" / "Gras-Schwad aufnehmen" / "Heu aufnehmen") via Density-Map-Sampling — siehe unten

**Filter**: passive Felder ohne Parallel-Task werden komplett aus dem HUD entfernt → nur "jetzt zu tun" wird gezeigt.

### Düngen-Lockout

In-Memory History pro Feld (`self.fieldHistory[fieldId]`): merkt sich `sprayLevel` und `sprayLockedAt` (= growthState bei letzter Spray-Erhöhung). Im Lockout wird "Düngen" nicht vorgeschlagen, bis growthState weiter springt. Reset bei `sprayLevel`-Drop (z.B. nach Ernte mit `resetsSpray=true`). **Nicht persistiert** über Save-Reload — nach Spielstart kann kurzzeitig "Düngen 1/2" erscheinen obwohl Lockout gelten würde.

---

## Schwad-Sampler (Stroh / Gras-Schwad / Heu)

Über `DensityMapHeightUtil.terrainDetailHeightId` — eine zentrale Density Map für alles was auf dem Boden liegt. Aufgeteilt:
- Type-Channels (`typeFirstChannel=0`, `typeNumChannels=6`) — welcher fillType liegt da (0-63)
- Height-Channels (`heightFirstChannel=6`, `heightNumChannels=6`) — wieviel (0-63)

**Mapping fillType → interner Type-Wert** ist `fillType.textureArrayIndex`:
- STRAW (FillType=31) → textureArrayIndex=26
- GRASS_WINDROW (FillType=28) → textureArrayIndex=24
- DRYGRASS_WINDROW (FillType=30) → textureArrayIndex=25 (= "Heu", `HAY` als separater fillType existiert nicht)

Pattern (`sampleWindrowsForField`):
1. Type-Modifier + Height-Modifier auf `terrainDetailHeightId` mit den jeweiligen Channels (cached)
2. Polygon der Feld-`polygonPoints` anwenden (Node-IDs! `getWorldTranslation(nodeId)` für Welt-Koords)
3. Erst Height-Filter `GREATER 0` — wenn `area < threshold`, leeres Ergebnis (verhindert Type-Ghosts ohne echtem Schwad)
4. Wenn ja: pro Schwadtyp Filter `EQUAL textureArrayIndex` und `area >= threshold` → Label hinzufügen

Threshold = `max(50 Pixel, 0.5% der Feldfläche)` — Restpixel werden ignoriert.

`getFillLevelAtArea` und `getFillTypeAtArea` aus `DensityMapHeightUtil` haben in Tests immer 0 zurückgegeben (Signatur unklar) — daher manuell mit `DensityMapModifier`.

`g_densityMapHeightTypeManager` existiert in FS25 nicht (FS22 hatte das).

`field.polygonPoints` ist eine flache Liste von **Engine-Node-IDs**, nicht Koordinaten. Auflösen via `getWorldTranslation(nodeId)`.

---

## Unkraut-Sampler

`g_currentMission.weedSystem` (Klasse `WeedSystem`) hat alles analog zum Stein-System:
- `densityMap` — Engine-Map-ID
- `firstChannel=0`, `numChannels=4` (Wertebereich 0..15, in der Praxis 0..9 belegt)
- `minValue=1`, `maxValue=5` — laut Engine die "lebendigen" Stein-Levels
- `denseStartState=2`, `sparseStartState=1` — startwerte beim Spawning
- `factors` — Lookup density-map-Wert → weedFactor. Bestätigt unsere empirische Tabelle 1:1: 3=0.5, 4=0.75, 5=1.0, 6=0.5, 8=0.5, 9=0.75. (1, 2, 7 fehlen → factor=0.)
- `name=weed`, `title="Unkraut"`

Map-Werte 0..9 entsprechen genau dem bekannten weedState-Enum:
- 0=sauber, 1=invisible, 2=invisible dense, 3=small alive, 4=small dense alive, 5=big alive, 6=small dense weeded alive, 7=small dead, 8=small dense dead, 9=big dead.

`fs.weedState`/`fs.weedFactor` sind **Aggregate die liegen können**: empirisch beobachtet auf Feld 2 mit Cotton — Aggregat sagte `weedState=0, weedFactor=0`, Density-Map hatte 49005 Pixel state=4 + 2832 Pixel state=5 + `getWeedFactor=0.307`. Daher ist Sampling Pflicht für verlässliches Verhalten.

Pattern (`sampleWeedForField`):
1. DensityMapModifier auf `weedSystem.densityMap` mit Polygon (cached)
2. Pro state in [1..6] Pixel-Count + Filter `EQUAL state` (gecached)
3. Höchster state mit `count >= threshold` gewinnt für Label-Größe
4. Faktor = `Σ (count[s] × factors[s]) / totalArea` über states 1..6 (tot wird ignoriert)
5. Threshold = `max(50 Pixel, 0.5% der Feldfläche)` wie beim Schwad/Stein

Die Engine-Funktion `FSDensityMapUtil.getWeedFactor(sx,sz,wx,wz)` funktioniert auch — gibt einen Bbox-basierten Wert. Polygon-Sampling ist präziser (verzackte Felder).

Spot-Sample-Funktionen `WeedSystem:getWeedStateAtWorldPos(x,y,z)` / `getWeedFactorAtWorldPos` als Punkt-Probe — fürs Feld zu unzuverlässig.

`weedLabel(field, fs)` versucht zuerst Polygon-Sampling, fällt auf Aggregat zurück wenn Sampler nicht initialisierbar (z.B. Map ohne weedSystem).

---

## Stein-Sampler

`g_currentMission.stoneSystem` (Klasse `StoneSystem`) hat alles:
- `densityMap` — Engine-Map-ID
- `firstChannel=0`, `numChannels=3` (Wertebereich 0..7)
- `minValue=2`, `maxValue=4` — aktive Stein-Levels (vermutlich small/medium/big)
- `pickedValue=5` — Marker "Steine wurden aufgesammelt", **kein** "hier sind Steine"
- `maskValue=1` — "Feld kann Steine haben" (Hintergrund)

`FSDensityMapUtil.getStoneArea(sx,sz,wx,wz,hx,hz)` liefert nur einen wenig informativen Skalar (`3` egal wie viele Steine im Feld sind) — nicht verwenden. Stattdessen direkt mit `DensityMapModifier` auf `stoneSystem.densityMap` + Polygon, dann pro Wert in `[minValue..maxValue]` mit `EQUAL`-Filter zählen und summieren. Threshold gleich wie beim Schwad-Sampler (`max(50 Pixel, 0.5% der Feldfläche)`).

Spot-Sample-Funktionen `StoneSystem:getStoneLevelAtWorldPos(x,y,z)` / `getStoneStateAtWorldPos` funktionieren auch — aber nur als Punkt-Sample, daher für Feld-Coverage zu unzuverlässig.

`fs.stoneLevel` aus dem fieldState-Aggregat ist nutzlos — bleibt 0 selbst wenn sichtbar viele Big Stones liegen. Auch `field:updateState()` korrigiert das nicht.

---

## Settings-Menü (echtes GUI für Maus-Decoupling)

Alt+M öffnet einen ScreenElement der über `g_gui:showGui("MyTodosSettingsScreen")` läuft → Engine entkoppelt Maus automatisch (wie ESC-Menü). Im Screen wird das Settings-Panel gezeichnet via `drawSettingsContent()` und Klicks via `handleSettingsClick()` an MyTodos delegiert.

Toggles:
- `hudVisible` — gleicher Effekt wie `RShift+T`. Nur als Settings-Fallback drin falls dem User die Tastenbelegung nicht mehr einfaellt.
- Schwellwerte fuer Tier-Tasks (percent, siehe `SETTING_DEFS`).

HUD-Position wird nicht persistiert — kommt dynamisch aus
`g_currentMission.hud.inputHelp`-Geometrie (siehe Abschnitt "HUD-Position
(Anker statt Drag)" oben).

---

## Tier-Husbandries

Discovery + Task-Derivation live (10. Mai 2026). HUD zeigt eine zweite Sektion "Tiere" mit Aufgaben pro eigene Husbandry. Probe-Befehle (`mtProbeHusbandry`, `mtProbeHusbandryDeep`) bleiben fuer Diagnose drin.

**Bekannte Fakten aus Surface-Probe:**

- Husbandries werden in `g_currentMission.placeableSystem.placeables` (flache Liste, Index 1..N) gehalten. Identifikation: irgendein Key auf dem Placeable beginnt mit `spec_husbandry`. Owner via `placeable:getOwnerFarmId()`, Filter auf `self.farmId`.
- Alle Husbandry-Tabellen sind als **Specs** (`spec_husbandry`, `spec_husbandryAnimals`, `spec_husbandryFood`, etc.) am Placeable. **Welche Specs vorhanden sind hängt vom Husbandry-Typ ab** — wir bauen Discovery so dass nur tatsächlich vorhandene Specs Tasks erzeugen.
- `g_animalSystem` / `g_animalManager` existieren in FS25 nicht. Stattdessen ist `AnimalSystem` als Klasse global da, Instanz vermutlich `g_currentMission.animalSystem`. `HusbandryModule*`-Globals existieren nicht — Module sind in den Specs am Placeable selbst.
- `spec_husbandryWater.automaticWaterSupply` (boolean): wenn `true` (z.B. moderner Schafstall), kümmert sich Engine selbst → kein Wasser-Task. Wenn `false` (Pasture-Cow), muss Spieler manuell befüllen.
- `spec_husbandryFood.capacity` + `fillLevels`-Tabelle (Werte pro fillType in Liter). Welche fillTypes erlaubt sind: `supportedFillTypes`-Tabelle. `litersPerHour` ist Verbrauchsrate.
- `spec_husbandryPallets`: Output-Paletten. `palletLimitReached` Boolean (alle Slots voll, Produktion gestoppt), `fillLevels` (table fillType → Liter aktuell im Spawn-Place), `maxNumPallets`/`capacities` Cap pro fillType, `activeFillTypes` welche Output-Paletten gerade produziert werden (kann mehrere sein — Schafstall mit Ziegen produziert Wolle UND Ziegenmilch).
- **Wichtige Limitation**: Husbandry-Spec trackt Pallets **nur solange sie im Spawn-Place stehen**. Sobald sie in den Abholbereich verschoben werden (Spieler hebt+setzt sie woanders ab, oder Loader-Trigger zieht sie), gehen alle `fillLevels[ft]` auf 0 zurück und `currentPallets`/`pallets` sind leer — auch wenn die Pallets als freie Game-Objects noch in der Welt stehen. `palletSpawner.spawnPlaces` sind nur Bounding-Boxes (Geometrie), keine Pallet-Refs. `palletSpawner.pallets` ist eine globale Liste aller Pallets der Map (~111 Einträge), nicht Husbandry-spezifisch. Eine "exakte Liter im Abholbereich"-Anzeige würde Position-Filter über die globale Pallet-Liste erfordern (~50-80 Zeilen Code) — bewusst nicht implementiert weil der Spieler die Pallets visuell sieht. Trigger sind: pro fillType Buffer-Liter ("Wolle 798L"), plus `(voll)` Suffix wenn `palletLimitReached`.
- `spec_husbandryAnimals`: `animalTypeIndex` (1=Cow, 3=Sheep+Ziegen — die Engine fasst Schafe+Ziegen unter SHEEP zusammen, `groupTitle="Schafe & Ziegen"`), `configMaxNumAnimals` (Soft-Cap wahrscheinlich), `baseMaxNumAnimals` (XML-Default), `maxNumAnimals` (theoretisches Max). `clusterHusbandry`/`clusterSystem` halten Tier-Daten. `infoHealth.text` ist ein vorberechneter "X %"-String der Tier-Gesundheit (sinkt wenn Futter/Wasser/Stress unzureichend) — aktuell nicht im HUD genutzt, koennte spaeter als Symptom-Indikator dazukommen.
- `spec_husbandryMeadow` nur bei Pasture-Varianten — Weide. `fillLevels` pro fruitType, `capacities`, `eatFilterMaxValue`. Tiere fressen vom Boden, Trog-Futter ergänzend.
- `spec_husbandryFence` ist nur Zaun-Customizing, kein Task-Trigger.

**User-Setup (10. Mai 2026):**
- Schafe (placeable[66], `pdlc_highlandsFishingPack.sheepHusbandryBarn`, Index 3, 32 Plätze): Specs = husbandry, Animals, Food (cap 4500), Water (auto!), Pallets. **Kein** Stroh/Mist/Milch/Gülle.
- Rinder (placeable[100], `cowHusbandryPasture`, Index 1, configMax 7): Specs = husbandry, Animals, Fence, Food (cap 11250), Meadow, Water (manuell). **Kein** Mist/Gülle/Stroh/Milch — Pasture-Variante hat keine Mist-Mechanik.

**Implementierung in `MyTodosHusbandry.lua`:**
- `collectOwnedHusbandries(farmId)` — iteriert `g_currentMission.placeableSystem.placeables`, filtert via `_isHusbandryPlaceable` + `getOwnerFarmId == farmId`
- `deriveHusbandryTask(entry)` — schaut welche `spec_husbandry*`-Tabellen am Placeable haengen und triggert den jeweiligen Task wenn die Schwelle (aus Settings, percent) ueber-/unterschritten ist:
  - **Input-Trigger** (Task wenn ratio **unter** Schwelle):
    - Food: `sum(spec.fillLevels) / spec.capacity < foodThreshold/100`
    - Water: nur wenn `spec.automaticWaterSupply == false`. Level via `placeable:getHusbandryFillLevel(water.fillType)`.
    - Straw: `getHusbandryFillLevel(straw.inputFillType) < strawThreshold/100`
    - Meadow: `sum(fillLevels)/sum(capacities) < meadowThreshold/100`, summiert ueber alle Frucht-Slots
  - **Output-Trigger** (Task wenn ratio **ueber** Schwelle, "abfahren"):
    - Manure: fillType aus `spec.husbandryStraw.outputFillType` (wenn `isManureActive`) oder `spec_husbandryManure.fillType`. Level via `getHusbandryFillLevel(ft)`.
    - LiquidManure: `spec_husbandryLiquidManure.fillType` (typisch 114). Level via `getHusbandryFillLevel(ft)`.
    - Milk: pro `spec_husbandryMilk.fillTypes[i]` einzeln. Mehrere Sorten moeglich (z.B. 39=Milch, 41=Bio-Milch). Label per `_fillTypeLabel` lokalisiert.
  - **Pallets-Spezialfall** (siehe `spec_husbandryPallets` oben): pro fillType `pal.fillLevels[ft] > 0` -> "Wolle 798L, Ziegenmilch 11L", bei `palletLimitReached` Suffix " (voll)". Buffer-basiert weil Pallets die in den Abholbereich verschoben wurden nicht mehr gespect-trackt sind.
- `_filltypeRatio(p, ft)` Helper liest `getHusbandryFillLevel(ft) / getHusbandryCapacity(ft)`. Diese API aggregiert **alle** angeschlossenen Storages (husbandry-eigene + externe User-Tanks). Empirisch bestaetigt: bei Mist (113) zeigt `storage.fillLevels[113]=0/cap=0` aber `getHusbandryFillLevel(113)=22183/cap=4000000` weil externer Tank angeschlossen.
- `scanHusbandries(verbose)` wird am Ende von `scanFields()` mitgerufen, Output landet in `self.husbandryTasks`/`self.husbandryOwnedCount`.
- HUD rendert beide Sektionen mit Sub-Header (`── Felder ──` / `── Tiere ──`) wenn beide nicht-leer sind, sonst nahtlos.

**Schwellwert-Settings** (in `MyTodos.SETTING_DEFS`, type=percent, group="Tiere"):
- Input-Schwellen (default 20%, Trigger wenn **unter**): `foodThreshold`, `waterThreshold`, `strawThreshold`, `meadowThreshold`
- Output-Schwellen (default 80%, Trigger wenn **ueber**): `manureThreshold`, `liquidManureThreshold`, `milkThreshold`
- Werte 5..95 in 5%-Schritten, Klick im Settings-Panel zyklisiert.

## Offene Themen / Was wir noch wollten

1. **PrecisionFarming-Pfad**: aktuell fällt PF auf Vanilla-Logik zurück. Echtes PF-Modell (N-Bedarf pro Wachstumsstufe via `g_precisionFarming`, pH-basiertes Kalken) noch nicht gebaut.
2. **Tier-Husbandries**: siehe oben. Probe läuft, Discovery + Tasks fehlen noch.
3. **Düngen-Lockout-Persistence**: optional, nice-to-have.
4. **`weedFactor`-Schwelle**: User hat angemerkt dass `Unkraut` ohne Prozent (weedState=1, weedFactor=0) ggf. nervt — Trigger könnte auf `weedFactor > 0` oder kleine Schwelle geschärft werden.
5. **PF-Detection**: aktuell wird nach `g_precisionFarming` und ein paar Mod-Namen geguckt — falls `mtRescan` "precision farming: no" ausgibt obwohl PF läuft, in `detectPrecisionFarming()` den korrekten Mod-Folder-Namen ergänzen.

## Stand 11. Mai 2026

- **HUD-Position dynamisch an Giants' InputHelpDisplay angehaengt** (`MyTodos:getHudAnchor` in `MyTodos.lua`). Kein Drag mehr, keine persistierte hudX/hudY. F1-Toggle blendet das Giants-Hilfepanel aus, MyTodos bleibt aber an derselben Stelle weil die Geometrie-Properties (`inputHelp.lineBg.width`, `getPosition()`) auch im invisible-State gepflegt werden.
- **Neue Action `MYTODOS_TOGGLE_HUD`** (Default `RShift+T`) blendet das HUD an/aus. Setting `hudVisible` (bool, persistiert in `MyTodos.xml`) als Fallback im Settings-Dialog.
- **Entfernt**: `hudMovable`/`playerMouse` Settings, Mouse-Drag-Handler (`MyTodos:mouseEvent`, `MyTodos:isMouseOverPanel`), `BaseMission.mouseEvent`-Hook, Konsolenbefehl `mtResetHud`, `HUD_DEFAULT_X/Y` Konstanten, `HUD_EDIT_BG_COLOR`.
- HUD-Text jetzt links-buendig (war vorher zentriert, passt zum Anker oben-links).
- `mtDump`/`mtForceUpdate`/`mtProbe*` interpretieren `<fieldNumber>` jetzt als User-facing Map-Nummer via `MyTodos:resolveFieldByUserNumber` (matched gegen `field.farmland.name`).

## Letzter Stand (10. Mai 2026)

- **Hauptfile gesplittet** in 4 Files: `MyTodos.lua` (Bootstrap/HUD/Settings/Hooks), `MyTodosFields.lua` (Discovery/Derivation/Sampler), `MyTodosHusbandry.lua` (Discovery/Task-Derivation + Probes), `MyTodosCommands.lua` (alle `mt*`-Befehle). Alle erweitern dieselbe `MyTodos`-Tabelle. modDesc-Reihenfolge: `MyTodos.lua` zuerst.
- **Tier-Husbandries Discovery + Tasks** live: Futter/Wasser/Weide/Pallets analysiert, HUD bekommt eigene Sektion "Tiere".
- **Settings-System** unterstuetzt jetzt percent-Werte (zusaetzlich zu bool). Klick im Settings-Panel zyklisiert in 5%-Schritten. Group-Header trennen visuell. Settings-Datei nutzt `getXMLInt`/`setXMLInt` fuer percent-Felder.
- **`mtProbeHusbandry`** + **`mtProbeHusbandryDeep`** als Diagnose-Befehle drin (Surface-Specs / Inner-Tables).
- Konfigurations-Konstanten (Sampler-Thresholds) jetzt in `MyTodosFields.lua` oben.

## Stand 6. Mai 2026

- Schwad-Sampling für Stroh/Gras/Heu funktioniert mit Threshold-Filter
- Walzen-Logik korrigiert (invertierter rollerLevel)
- Gras-Lifecycle korrekt (regrowing-Pfad)
- "Ernten" für regrowing nur bei `maxHarvest`, sonst "Wächst"
- Konfigurations-Konstanten (Threshold etc.) oben in `MyTodosFields.lua` sichtbar zum Justieren
- **Steine via stoneSystem.densityMap polygon-sampeln** (statt nutzlosem `fs.stoneLevel`) — Threshold gleich wie Windrows
- **Wurzelfruechte mit Krautschlag-Stadium** (Zwiebel, Zuckerruebe): `minPreparingGrowthState` zieht den "Ernten"-Trigger nach vorne, kein eigenes Label
- **Mehrfach-erntbare Fruechte** (Spinat): Zwischen-Cut-State (growth in `cutStates` aber != `cutState`) → passives "Wächst nach". Erkennung via `minHarvest<maxHarvest`.
- **Mais (Forage + Körner)**: states 5-6 → "Mais: Forage" (Häckseln/Silage), state 7 → "Mais: Ernten" (Trockenernte/Körner). cutStates={9,10} sind beide final (kein Regrowth), via `minHarvest==maxHarvest` Heuristik unterschieden.
- **Wheat/Canola Forage gefiltert**: Engine-Property nominell vorhanden aber Vanilla funktional tot (Haecksler nimmt nichts auf). Heuristik `minForage+1<minHarvest` blendet sie aus, nur Mais zeigt "Forage".
- **Sugarcane**: regrowing mit Preparing-Stadium. State 8 (harvestReady) und 11 (prepared) → "Ernten"; state 10 (cut) → "gemäht" (regrowt), state 9 (dead) → "Verwelkt".
- **Unkraut stufen-aware**: `weedLabel(fs)` aus dem 0..9-Enum. States 1/2 (wachsend, präventiv mit Striegel zu behandeln) → "Unkraut wachsend" ohne %. States 3/4/6 → "Unkraut klein (X%)". State 5 → "Unkraut groß (X%)". States 0 und 7/8/9 (sauber bzw. tot) → unterdrückt.
- **Walzen-Fenster** strikt: nur direkt nach Saat (non-regrowing, `growth<=1`) oder nach Mähen (regrowing, `growth==cutState`). Vermeidet Wachstums-Reset/Schaden bei zu spätem Walzen.
- **Unkraut-Sampling auf weedSystem.densityMap** statt `fs.weedState`/`fs.weedFactor`. Aggregat kann blind sein (auf Feld 2 mit Cotton beobachtet: Aggregat=0, Density-Map zeigt 70% Bedeckung). `weedSystem.factors` matcht 1:1 die alte empirische Tabelle.

## Standard-Workflow für Test

1. FS25 beenden, Save laden lassen, neu starten
2. Save laden
3. `mtRescan` (oder `mtDump <fieldId>` für Detail-Diagnose)
4. Im Log nach `[MyTodos]`-Zeilen schauen
