# FS25 MyTodos

A **reminder HUD** for Farming Simulator 25. Shows the *next pending task*
for each of your fields and animal husbandries, top-right — so you don't
forget what's due where while making the rounds.

> Status: **0.0.1** — under active development. Vanilla is fully supported,
> Precision Farming is supported for soil pH (lime) and nitrogen (fertilizer).
> Available in **English** and **German**.

---

## What it does

MyTodos is a **reminder list for experienced players**, not a tutorial.
It assumes you know *how* to play — the HUD only tells you *what* needs
doing right now.

The mod periodically inspects each of your fields and husbandries and
derives a **current task** for each. Passive growth phases without any
parallel work are deliberately **hidden** — only what you could actually
*act on* shows up in the HUD.

### Fields

Detected (among others):

- **Plow / Cultivate / Sow** at the right stage
- **Harvest** — including root crops with a topping stage (sugar beet,
  onion) and multi-harvest crops (spinach)
- **Corn: Forage** (chopping) vs. **Corn: Harvest** (dry grain)
- **Fertilize** with lockout — prevents "Fertilize 2/2" spam right after
  bumping the spray level
- **Roll** only inside the safe window (freshly sown or right after
  mowing) — avoids accidental growth resets
- **Mulch / Lime**
- **Stones** via density-map sampling (not via the aggregate — that's
  useless in FS25)
- **Weeds** stage-aware: "emerging" / "small (X%)" / "large (X%)" with
  density-map sampling for reliable values
- **Windrows** on the field: "Pick up straw", "Pick up grass windrow",
  "Pick up hay"

### Precision Farming (optional)

If the Precision Farming mod is loaded **and** at least one PF-capable
sprayer exists in the world, MyTodos switches to PF-aware tasks:

- **Lime**: `Lime: pH 5.8 / 6.5 (Loam)` — reads the current pH per soil
  type from `pHMap` and compares against the per-soil target from
  `valueTransformations`. Reports the soil type with the largest deficit;
  adds `, strongly acidic` if the gap is heavy.
- **Fertilize**: `N: 35/85 kg/ha (Wheat, Loam)` — reads nitrogen per
  soil type from `nitrogenMap` and compares against the per-soil
  target from `fruitTypeIndexToFruitRequirement`. Triggers when below
  PF's own "Reduced Rate" threshold (i.e. when PF would auto-apply).
  Adds `, N deficit` for heavy under-supply.

Without PF, lime/fertilize fall back to the vanilla `limeLevel == 0` /
`sprayLevel < max` heuristic.

### Husbandries

Detected (among others):

- **Food / Water / Pasture / Straw** below a configurable threshold
  (default 20%)
- **Manure / Slurry / Milk** above a configurable threshold (default
  80%) — time to haul it off
- **Pallets** in the spawn area (wool, goat milk, …) including a
  `(full)` hint when production has stopped

Water tasks are only shown when the trough is *not* on automatic supply
(pasture variants and older barns).

---

## Installation

1. Download the repo as a ZIP (Code → Download ZIP) — the file *must*
   be named `FS25_MyTodos.zip` (the folder name inside the ZIP matters).
2. Drop the ZIP into your FS25 mods folder — typically:
   `C:\Users\<YOU>\Documents\My Games\FarmingSimulator2025\mods\`
3. Enable the mod in the in-game mod manager, load your save.

For developers/testers: work directly from a repo clone via a
**symlink**:
```powershell
# Repo cloned to e.g. C:\Users\<YOU>\Programming\FS25_MyTodos
New-Item -ItemType Junction `
  -Path  "$env:USERPROFILE\Documents\My Games\FarmingSimulator2025\mods\FS25_MyTodos" `
  -Value "C:\Users\<YOU>\Programming\FS25_MyTodos"
```

**Important:** Lua scripts are loaded **only at game start**. After any
code change, fully quit and relaunch FS25 — otherwise the old version
keeps running.

---

## Usage

| Action | Default key |
|---|---|
| Toggle HUD | **RShift + T** (rebindable in the FS input menu) |
| Open / close settings | **Alt + M** (rebindable in the FS input menu) |

The HUD position is not set manually — it anchors itself automatically
right next to Giants' F1 help panel (the `InputHelpDisplay`, top-left)
and follows its position. The HUD stays in the same screen location
even if you hide the F1 help panel via F1.

### Settings menu

In the settings dialog you can:

- Toggle **Show HUD** — same as RShift+T, kept here as a fallback if
  you forget the key combo
- Adjust **thresholds** for husbandry tasks (food, water, straw,
  pasture / manure, slurry, milk) in 5% steps
- **Ignore individual fields** — every owned field appears as a
  toggleable row at the bottom. Useful when you've built a barn on
  top of a field, leased it out, or just want it gone from the HUD.
  Ignored fields are scoped per save + farm, so different saves don't
  bleed into each other.

Toggles are persisted to `<UserProfileApp>/modSettings/MyTodos.xml`.

---

## Localization

The mod ships with **English** and **German** translations. All
player-facing strings live in `l10n/l10n_<lang>.xml` and are picked up
automatically based on your FS25 language setting.

Want to contribute a new language? Just copy `l10n/l10n_en.xml` to
`l10n/l10n_<code>.xml` (e.g. `l10n_fr.xml`), translate the `text=`
attributes, and you're done — no code change required. Pull requests
welcome.

---

## Multiplayer

`multiplayer="true"` is set — the mod is read-only, never writes to the
save. Each client sees *their own* fields and husbandries.

---

## Console commands (diagnostics)

If a task is wrong or missing, these commands in the FS console
(open with `~`, may need to be enabled in `game.xml`) help debug:

| Command | Purpose |
|---|---|
| `mtRescan` | Force an immediate re-scan of all fields/husbandries |
| `mtDump <fieldNo>` | Dump `fieldState` and fruit properties |
| `mtForceUpdate <fieldNo>` | Trigger `field:updateState()`, log before/after |
| `mtFields` | List all fields with their IDs/names |
| `mtProbeStones <fieldNo>` | Sample the stone density map |
| `mtProbeWeed <fieldNo>` | Sample the weed density map |
| `mtProbeWindrowAt <fieldNo>` | Sample the windrow density map |
| `mtProbePf [fieldNo]` | Dump the Precision Farming API surface |
| `mtDebugPf <fieldNo>` | Histogram of pH/N/soil density-map values in field polygon |
| `mtProbeHusbandry` / `mtProbeHusbandryDeep` | Dump the husbandry API |
| `mtIgnore <fieldNo>` / `mtUnignore <fieldNo>` | Hide / show a field in the HUD |
| `mtSettings` | Open the settings dialog (alternative to Alt+M) |

`<fieldNo>` is always the **field number as shown on the map**
(internally: `field.farmland.name`).

---

## Known limitations

- **`fieldState` is an aggregate** the engine refreshes periodically in
  the background. Right after an action, the HUD can lag by up to a few
  (in-game) minutes — that's FS25 behavior, not a bug.
- **Fertilize lockout** is in-memory only, not persisted across
  save-reload. Right after loading, "Fertilize 1/2" may briefly show
  even when a lockout would normally suppress it.
- **PF per-soil sampling** uses the dominant soil type for the *task
  label*, but the per-soil deficit detection itself respects all soil
  types in the field. Patches under 10% area / 50 pixels are ignored
  to avoid edge-pixel noise.

---

## License / credits

Personal mod by Tobias.

Uses only FS25 vanilla APIs (no external mod dependencies).
