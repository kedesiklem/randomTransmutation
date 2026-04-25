# Random Transmutation

A Noita mod that adds a new spell : **Random Transmutation**.

When the spell is spawned, it randomly selects a material transmutation (e.g. Water into Blood) and keeps it for its entire lifetime. The spell behaves like a standard transmutation modifier.

## How it works

- On spawn, two distinct materials groups are picked at random from a pool, then one element is picked at random from the second group to fix the output ; all the element of the first will be used as input. The selection is fixed via a `VariableStorageComponent` on the spell card entity, so it persists across casts and wand edits.

- When the spell is cast, the chosen `from` and `to` materials are injected into the projectile via `SpellDatat` — a library that smuggles arbitrary data through `ProjectileComponent.config.action_description`. The projectile's `MagicConvertMaterialComponent` is then configured at runtime from these values, applying the correct transmutation.
 
- The spell name displayed in the inventory is dynamically set via `ItemComponent.ui_name` and `always_use_item_name_in_ui`, showing the actual material names (e.g. `Water -> Blood`) rather than a generic label.

- The sprites are pre-generated from the groups and labeled as "groupFromKey_to_groupToKey".

## Compatibility

This mod uses **SpellDatat**, a library for passing arbitrary data from spell actions to their projectiles. SpellDatat is designed to be compatible with other mods using the same tech (Copi, Apoth).

If you are a modder and want to use SpellDatat in your own mod, namespace your keys with your mod name (e.g. `"myMod:myKey"`) to avoid conflicts.

## TODO

Better sprite (currently just generated from material color)