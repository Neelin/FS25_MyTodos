# MyTodos - offene Punkte

Lose Sammlung was noch fehlt / nice-to-have ist. Reihenfolge = grobe Prio.

## Doku

- **Kurze README/Mod-Doku schreiben** mit den Erklaerungen die ein Spieler
  wissen muss damit der HUD-Vorschlag Sinn ergibt:
  - Duengen: nach jeder Anwendung muss erst die naechste Wachstumsstufe
    erreicht sein, bevor wieder geduengt werden kann. Der Mod zeigt nach
    Save/Reload kurzzeitig `Duengen 1/2` an, obwohl der Lockout greifen
    wuerde - in-memory History ist nach Reload leer. Verschwindet beim
    naechsten Wachstumstick.
  - Walzen taucht auch nach dem Saeen bei Hafer/Gras auf - keine reine
    Erntefolge.
  - Schwadlade-Tasks (Stroh / Gras / Heu) basieren auf Density-Map-Sampling
    mit Threshold (>0.5% Feldflaeche oder >50 Pixel) - Restpixel werden
    bewusst ignoriert.
  - Gras/Luzerne (regrowing) bekommt nie Pflug/Saat-Vorschlag und wird erst
    bei vollem Yield als "Ernten" markiert, frueher als "Waechst".

## Funktional

- **Duengen-Lockout persistieren** (`fieldHistory` in modSettings.xml). Wuerde
  den oben genannten "kurzzeitigen Fehlvorschlag nach Reload" beheben.
  Konservativer Workaround als Alternative: beim ersten Sehen eines Feldes
  mit `sprayLevel > 0` direkt `sprayLockedAt = growthState` setzen
  (siehe Diskussion 2026-05-06).
- **PrecisionFarming-Pfad** richtig modellieren - aktuell faellt PF auf
  Vanilla-Logik zurueck. N-Bedarf pro Wachstumsstufe via `g_precisionFarming`,
  pH-basiertes Kalken etc.
- **Tier-Husbandries**: Erstausbau live - Futter/Wasser/Weide/Pallets
  /Stroh/Mist/Guelle/Milch fuer alle bekannten Husbandry-Typen. Ausstehend:
  - **Tier-Gesundheit als Symptom-Indikator** - infoHealth.text
    zeigt z.B. "30 %", taugt als zusaetzliches HUD-Feld wenn niedrig.
    Nice-to-have, nicht actionable selbst (User behebt Symptome ueber
    die schon bestehenden Trigger Futter/Wasser/Stroh/etc.).
  - **Pallet-Position-Filter** (Variante B) - aktuell sehen wir nur
    Pallets im Spawn-Place, nicht im Abholbereich. Bewusst weggelassen,
    aber wenn jemand exakte Liter-Anzeige aller Pallets will:
    spawnPlace-Bounding-Box-Test ueber globale `palletSpawner.pallets`-
    Liste. ~50-80 Zeilen Code.
- ~~`weedFactor`-Schwelle schaerfen~~ — erledigt: weedState 0..9-Enum
  empirisch dekodiert. 0/7/8/9 unterdrueckt, 1/2 = "Unkraut wachsend"
  (praeventiver Striegel), 3/4/6 = "klein", 5 = "groß".

## UI

- **HUD-Drag mit Camera-Lock** analog Courseplay (`setCameraRotation`) -
  aktuell dreht der Kopf beim Verschieben mit. Niedrige Prio.

## Test / Diagnose

- **PF-Detection erweitern** falls `mtRescan` "precision farming: no" sagt
  obwohl PF laeuft - in `detectPrecisionFarming()` korrekten Mod-Folder-Namen
  ergaenzen.
