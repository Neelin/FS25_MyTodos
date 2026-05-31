# MyTodos — Console Commands

MyTodos ships a set of `mt*` console commands for live diagnostics. They are
the recommended way to debug a wrong or missing task — especially on modded
maps, where field/husbandry edge cases are common.

**Notes**

- The commands require the **developer console** to be enabled (in
  `game.xml`; open the console with `~`). Normal players never see them.
- Command output goes to the **log file**:
  `Documents\My Games\FarmingSimulator2025\log.txt` — look for `[MyTodos]`
  lines. Most commands only log; they don't print to the HUD.
- `<fieldNumber>` is always the **field number shown on the map**
  (internally `field.farmland.name`), *not* the internal table key.
- Commands reload **data only**, never code. After changing a Lua file you
  must fully restart FS25.

For a quick "send me the output" support workflow: ask the user to run the
relevant command and paste the `[MyTodos]` lines from `log.txt`.

---

## Everyday / general

| Command | Purpose |
|---|---|
| `mtRescan` | Force an immediate re-scan of all fields and husbandries. |
| `mtSettings` | Open / close the settings panel (same as Alt+M). |
| `mtIgnore <fieldNumber>` | Hide a field from the HUD (scoped per save + farm). |
| `mtUnignore <fieldNumber>` | Show a previously ignored field again. |

## Field diagnostics

| Command | Purpose |
|---|---|
| `mtFields` | List all fields with ID / number / name candidates. |
| `mtListOwned` | List all owned fields with their current fruit + state. |
| `mtFindField <fieldNumber>` | List all field instances carrying that farmland number. |
| `mtDump <fieldNumber>` | Dump a field's `fieldState` and fruit properties. |
| `mtForceUpdate <fieldNumber>` | Run `field:updateState()` and log before/after. |
| `mtWhereAmI` | Probe farmland / field / fruit at your current world position. |
| `mtFruitHere` | Sample every fruit index in the registry at your current position. |

## Density-map probes (field sampling)

| Command | Purpose |
|---|---|
| `mtProbeWindrowAt <fieldNumber>` | Sample windrows (straw / grass / hay) on a field. |
| `mtProbeWeed <fieldNumber>` | Sample weed density on a field. |
| `mtProbeStones <fieldNumber>` | Sample stone density on a field. |

## Precision Farming

| Command | Purpose |
|---|---|
| `mtProbePf [fieldNumber]` | Probe the Precision Farming API surface. |
| `mtDebugPf <fieldNumber>` | Histogram of pH / N / soil density-map values inside a field polygon. |

## API exploration probes (development)

These dump raw engine tables to the log — used while developing/extending the
mod, rarely needed for normal support.

| Command | Purpose |
|---|---|
| `mtProbe [fieldNumber]` | Probe the FS25 field API surface. |
| `mtProbeWindrow` | Probe the FS25 windrow / fillType API. |
| `mtProbeHusbandry` | Probe the FS25 husbandry placeable API. |
| `mtProbeHusbandryDeep` | Deep-probe husbandry inner spec tables. |
| `mtProbeIcons` | Dump fillType / fruitType / animal icon paths. |
