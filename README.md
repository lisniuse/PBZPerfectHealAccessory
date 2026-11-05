# PBZ Perfect Heal Accessory

A UE4SS mod for **Phantom Blade Zero**: whenever the player lands a **perfect deflect** or a **perfect dodge**, restore **10% of maximum HP**.

## Features

- Perfect deflect (parry cue) -> heal
- Perfect dodge -> heal
- Heal percentage, cooldown and master switch are configurable
- Optional: only active while the player owns a specific accessory (`carrier_item_id`)
- Reads/writes only the player's own health value; does not modify saves or game files

## Requirements

**UE4SS for Phantom Blade Zero** (the community UE4SS package that ships the PBZ-specific signatures and mem-ber layout). Without it, Lua mods cannot load.

## Installation

1. Fully close Phantom Blade Zero.
2. Install **UE4SS for Phantom Blade Zero** if you have not already.

**Option A (recommended):** double-click `Install.cmd`.
It finds the game through Steam, checks that UE4SS is installed, and copies
the mod into `ue4ss\Mods\`. An existing `config.lua` is preserved.

**Option B (manual):** copy the whole `PBZPerfectHealAccessory` folder into:
   ```
   PBZ\platform\steam\ue4ss\Mods\
   ```

3. Start the game and load a save.
4. Check `PBZ\platform\steam\ue4ss\UE4SS.log` for:
   ```
   [PBZPerfectHeal] loaded
   [PBZPerfectHeal] base hooks installed
   [PBZPerfectHeal] dodge hooks installed: N
   ```

## Configuration

Settings live in:

```
PBZPerfectHealAccessory\Scripts\config.lua
```

**Easiest for players:** double-click `Configure Heal Percent.cmd` and type a number (for example `10` for 10%).

**Manual edit:** open `Scripts\config.lua` in Notepad and change:

```lua
heal_percent = 10,
```

Full settings:

```lua
return {
    enabled = true,             -- master switch
    heal_percent = 10,          -- percent of maximum HP (10 = 10%)
    cooldown_seconds = 0.3,     -- minimum seconds between heals
    boss_only = false,          -- only heal on perfect deflect/dodge vs a boss
    require_carrier = false,    -- require a specific accessory
    carrier_item_id = "",       -- accessory item ID, e.g. AC_ModKraken
    debug = true,               -- write detailed log lines
}
```

`boss_only` uses the attacker's `Difficulty Tag` from its `Actor Config` asset
(MiniBoss / NormalBoss / GreatBoss / UltimateBoss). If the attacker cannot be
identified for a given event, the heal is allowed and the log says so.

Changes apply within about 3 seconds even while the game is running. The log shows:

```
[PBZPerfectHeal] config reloaded: heal=15% cooldown=0.3s
```

If nothing changes, press **Ctrl+R** in game (hot reload) or restart the game.

Optional console command (if the UE console is enabled):

```
perfectheal status | on | off | test
```

## How it works

- **Perfect deflect (parry cue):** hooks `LGAAction_CheckParry:NotifyParrayResultDetermine` and checks for `EParryResult.Perfect` (3).
- **Perfect dodge:** hooks every blueprint function named `Do Perfect Dodge`.
- **Fallback:** hooks `DeflectComponent:GetSelfResultData` and checks the result tag (the game reports e.g. `Deflect.Result.Perfect`).
- **Healing:** prefers the game's own `GM_SetHealth` path and falls back to writing
  the player's `AttributeSetBase` health value directly, capped at maximum HP.
  The game's `Health Post Func(NewValue, OldValue)` is then called so the HUD
  bar, damage vignette and character material update immediately instead of
  waiting for the next hit.

## About a real inventory accessory

This release implements the **effect**. To become a true inventory accessory (name, icon, item row, equippable), it needs a pak containing cooked assets (item row, icon texture, optional GameplayEffect) built with **UE 5.7.4**. `pak-source/README.md` describes the required layout.

Until those assets exist, you can bind the effect to an existing accessory with `carrier_item_id`.

## Distribution

Ship the whole `PBZPerfectHealAccessory` folder. Required files:

```
PBZPerfectHealAccessory\
├── enabled.txt
├── Scripts\main.lua
├── Scripts\config.lua
├── tools\set-heal.ps1
├── tools\common.ps1
├── tools\install.ps1
├── tools\uninstall.ps1
├── Configure Heal Percent.cmd
├── Install.cmd
├── Uninstall.cmd
├── LICENSE
└── README.md
```

`pak-source\` is optional documentation, not required at runtime.

Notes:

- Do not redistribute game assets or encryption keys.
- Default heal percentage on a fresh install is 10%.
- Other mods that change perfect-deflect/perfect-dodge behavior may stack with this one.

## Uninstall

Close the game and run `Uninstall.cmd`, or delete
`PBZ\platform\steam\ue4ss\Mods\PBZPerfectHealAccessory\` manually.
No save restoration is needed.

## Log

All output is prefixed with `[PBZPerfectHeal]` and written to:

```
PBZ\platform\steam\ue4ss\UE4SS.log
```

## Compatibility

- Game updates can rename the hooked UFunctions; if healing stops after an update, the hook paths need updating.
- No network access, no save writes beyond the current health value.

## Changelog

### 1.3.0
- **Fixed (for real this time):** the heal was being undone by the next attribute
  update, because only `CurrentValue` was written. `BaseValue` is written as well now,
  so the healed value sticks.
- **Fixed:** the bar did not move on a heal. `Health Post Func` turned out not to be
  what drives it; the HUD now calls the bar widget's own `OnHeathChanged(NewValue, OldValue)`
  (`WB_PlayerHPBar_V1_C`), which is the function the game's attribute binding uses.
- Do **not** apply the game's `HealGameplayEffect_SetByCaller` to force a refresh: it is a
  SetByCaller effect and crashes the game without a spec.
- Defaults: `heal_percent = 10`, `cooldown_seconds = 0.1`.
- `debug` ships as `false` (no log lines, no `F9` test key); set `debug = true`
  in `config.lua` only when troubleshooting.
- Cheat manager is resolved before the fight (the first heal used to cost ~500 ms).
- Added an `F9` test key and a `perfectheal` console command (`Ctrl+O`).

### 1.2.0
- **Fixed:** the health bar did not refresh after a heal until the player was hit
  again. The mod now calls the game's own `Health Post Func(NewValue, OldValue)`
  right after healing, so the HUD updates on the same frame.
- Healing now tries the game's cheat-manager setter (`GM_SetHealth`) first and
  verifies the result by reading the attribute back, falling back to a direct
  attribute write when the setter is unavailable.
- Added `readback=` / `cheat=` fields to the heal log line for diagnostics.

### 1.1.0
- Added one-click `Install.cmd` / `Uninstall.cmd` / `Configure Heal Percent.cmd`.
- Added `boss_only` option.

### 1.0.0
- Initial release: heal on perfect deflect / perfect dodge.

## Source

https://github.com/lisniuse/PBZPerfectHealAccessory
