# Custom accessory assets (pak) - notes

This mod currently implements the **effect** only: perfect deflect / perfect dodge -> heal.

To turn it into a real inventory accessory (name, icon, item row, equippable), add a pak built from assets such as:

```
ProjectPBZ/Content/...
├── <item data asset or DataTable row>   # item ID, display name, icon, type = accessory
├── <icon Texture2D>                     # UI icon
└── <GameplayEffect> (optional)          # if the effect should run through GAS
```

## Constraints

- Assets must be cooked with **UE 5.7.4** (same version as the game), or they will not load.
- The item ID must match `carrier_item_id` in `Scripts/config.lua`.
- Pack into a `z<Name>_999_P.pak/.utoc/.ucas` trio and place it in:

```
PBZ\ProjectPBZ\Content\Paks\~mods\
```

## Packing command (repak)

```sh
repak pack --version V3 --mount-point ../../../ pak-source zPBZPerfectHeal_999_P.pak
```

The matching `.utoc/.ucas` can reuse the empty companion files from an existing community pak; they do not need to be rebuilt when only scripts/assets change.

## Before the assets exist

Use `carrier_item_id` in `config.lua` to bind the effect to an **existing** accessory (for example one the player already wears), so the "heal while wearing it" behavior works without new assets.
