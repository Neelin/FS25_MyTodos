# FS25 MyTodos

Ein **Erinnerungs-HUD** für Farming Simulator 25. Zeigt rechts oben pro
eigenem Feld und pro eigener Tierhaltung die *nächste anstehende Aufgabe* —
damit du beim Hofrundgang nicht vergisst, was wo dran ist.

> Status: **0.0.1** — in aktiver Entwicklung. Vanilla wird voll unterstützt,
> Precision Farming fällt aktuell auf Vanilla-Logik zurück.

---

## Was es macht

MyTodos ist eine **Erinnerungs-Liste für erfahrene Spieler**, kein Tutorial.
Es geht davon aus, dass du weißt *wie* gespielt wird — das HUD sagt dir nur
*was* gerade ansteht.

Konkret schaut der Mod regelmäßig auf jedes deiner Felder und jede deiner
Tierhaltungen und leitet daraus eine **aktuelle Aufgabe** ab. Passive
Wachstumsphasen ohne Parallel-Tasks werden bewusst **ausgeblendet** —
nur was du jetzt tun *könntest* erscheint im HUD.

### Felder

Erkannt werden u.a.:

- **Pflügen / Grubbern / Säen** (im richtigen Zustand)
- **Ernten** — inkl. Wurzelfrüchte mit Krautschlag-Stadium (Zuckerrübe,
  Zwiebel) und Mehrfach-Ernte (Spinat)
- **Mais: Forage** (Häckseln) vs. **Mais: Ernten** (Trockenernte)
- **Düngen** mit Lockout (verhindert Spam von "Düngen 2/2" direkt nach Erhöhung)
- **Walzen** nur im sicheren Fenster (frisch gesät oder direkt nach Mähen) —
  vermeidet versehentliche Wachstums-Resets
- **Mulchen / Kalken**
- **Steine** via Density-Map-Sampling (nicht via Aggregat — das ist in
  FS25 nutzlos)
- **Unkraut** stufen-aware: "wachsend" / "klein (X%)" / "groß (X%)" inkl.
  Density-Map-Sampling für verlässliche Werte
- **Schwadläden** auf dem Feld: "Stroh aufnehmen", "Gras-Schwad aufnehmen",
  "Heu aufnehmen"

### Tierhaltungen

Erkannt werden u.a.:

- **Futter / Wasser / Weide** unter konfigurierbarer Schwelle (Default 20%)
- **Mist / Gülle / Milch** über konfigurierbarer Schwelle (Default 80%) —
  abfahren
- **Paletten** im Spawn-Bereich (Wolle, Ziegenmilch, …) inkl. `(voll)`-Hinweis
  wenn die Produktion gestoppt ist

Wasser-Tasks werden nur angezeigt, wenn die Tränke *nicht* automatisch
versorgt wird (Pasture-Varianten und ältere Ställe).

---

## Installation

1. Repo als ZIP herunterladen (Code → Download ZIP) — Dateiname *muss*
   `FS25_MyTodos.zip` heißen (der Ordnername im ZIP zählt).
2. ZIP in den FS25-Mods-Ordner kopieren — typisch:
   `C:\Users\<DU>\Documents\My Games\FarmingSimulator2025\mods\`
3. Im Spiel-Modmenü aktivieren, Save laden.

Für Entwickler/Tester: per **Symlink** direkt aus dem Repo-Klon arbeiten:
```powershell
# Repo z.B. nach C:\Users\<DU>\Programming\FS25_MyTodos
New-Item -ItemType Junction `
  -Path  "$env:USERPROFILE\Documents\My Games\FarmingSimulator2025\mods\FS25_MyTodos" `
  -Value "C:\Users\<DU>\Programming\FS25_MyTodos"
```

**Wichtig:** Lua-Scripts werden nur **beim Spielstart** geladen. Nach
Code-Änderungen FS25 komplett beenden+neustarten, sonst läuft alte Version.

---

## Bedienung

| Aktion | Tastenkombi |
|---|---|
| HUD ein/aus | **RShift + T** (umbelegbar im FS-Eingabe-Menü) |
| Settings öffnen / schließen | **Alt + M** (umbelegbar im FS-Eingabe-Menü) |

Die Position des HUD wird nicht manuell gesetzt — es ankert sich
automatisch direkt rechts neben Giants' F1-Hilfepanel (das `InputHelpDisplay`
links oben) und folgt dessen Position. Das HUD bleibt an derselben Stelle
kleben auch wenn du das F1-Hilfepanel via F1 ausblendest.

### Settings-Menü

Im Settings-Dialog kannst du:

- **HUD anzeigen** an/aus — derselbe Toggle wie RShift+T, hier nur als
  Fallback wenn dir die Tastenkombi nicht mehr einfällt
- **Schwellwerte** für Tier-Tasks (Futter, Wasser, Stroh, Weide / Mist,
  Gülle, Milch) in 5%-Schritten anpassen

Toggles werden in `<UserProfileApp>/modSettings/MyTodos.xml` persistiert.

---

## Multiplayer

`multiplayer="true"` ist gesetzt — der Mod liest nur, schreibt nichts ins
Save. Jeder Client sieht *seine eigenen* Felder/Tierhaltungen.

---

## Konsolen-Befehle (Diagnose)

Falls eine Aufgabe falsch oder gar nicht erscheint, helfen folgende Befehle
in der FS-Konsole (mit `~` öffnen, muss in `game.xml` ggf. aktiviert sein):

| Befehl | Zweck |
|---|---|
| `mtRescan` | Sofortiger Re-Scan aller Felder/Tierhaltungen |
| `mtDump <feldNr>` | `fieldState` + Frucht-Properties dumpen |
| `mtForceUpdate <feldNr>` | `field:updateState()` triggern, Vorher/Nachher loggen |
| `mtFields` | Alle Felder mit IDs/Namen auflisten |
| `mtProbeStones <feldNr>` | Stein-Density-Map sampeln |
| `mtProbeWeed <feldNr>` | Unkraut-Density-Map sampeln |
| `mtProbeWindrowAt <feldNr>` | Schwad-Density-Map sampeln |
| `mtProbeHusbandry` / `mtProbeHusbandryDeep` | Tierhaltungs-API dumpen |
| `mtSettings` | Settings-Dialog öffnen (Alternative zu Alt+M) |

`<feldNr>` ist immer die **Feldnummer wie auf der Karte zu sehen** (intern:
`field.farmland.name`).

---

## Bekannte Einschränkungen

- **`fieldState` ist ein Aggregat**, das die Engine periodisch im Hintergrund
  aktualisiert. Direkt nach einer Aktion kann das HUD bis zu mehrere
  (Spiel-)Minuten hinterherhängen — das ist kein Bug, sondern FS25-Verhalten.
- **Precision Farming**: aktuell läuft alles über die Vanilla-Logik. Ein
  echtes PF-Modell (N-Bedarf pro Stufe, pH-basiertes Kalken) ist geplant,
  aber noch nicht gebaut.
- **Düngen-Lockout** ist nur in-memory, nicht persistiert über Save-Reload.

---

## Lizenz / Credits

Privater Mod, Autor: Tobias.

Verwendet ausschließlich FS25-Vanilla-APIs (keine externen
Mod-Abhängigkeiten). Cross-validiert gegen
[`FS25_FarmlandOverview`](https://github.com/) für Feldnummern-Auflösung.
