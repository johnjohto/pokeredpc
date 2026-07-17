# Data format: Pokémon & battle data

> Extracted and used by the battle engine — see **[../engine/battle.md](../engine/battle.md)**
> for the JSON outputs, stat/damage formulas, and battle flow. This page documents the
> source formats.

## Base stats (`pokered/data/pokemon/base_stats/<name>.asm`)

```
db DEX_BULBASAUR              ; pokedex id
db  45, 49, 49, 45, 65        ; hp, atk, def, spd, spc
db GRASS, POISON              ; types (type1, type2; same = mono-type)
db 45                         ; catch rate
db 64                         ; base exp
INCBIN "gfx/pokemon/front/bulbasaur.pic", 0, 1  ; sprite dimensions byte
dw BulbasaurPicFront, BulbasaurPicBack          ; sprite pointers
db TACKLE, GROWL, NO_MOVE, NO_MOVE              ; level-1 learnset
db GROWTH_MEDIUM_SLOW         ; growth rate (exp curve)
tmhm ...                      ; TM/HM compatibility bitfield
db 0                          ; padding
```

## Related tables

- `data/moves/moves.asm` — `move CONST, effect, power, type, accuracy, pp` (extracted).
- `data/types/type_matchups.asm` — `TypeEffects`: `db ATK, DEF, mult` (extracted).
- `data/pokemon/evos_moves.asm` — evolution methods + level-up learnsets (not yet extracted;
  the engine uses only the base level-1 learnset so far).
- `data/pokemon/names.asm` — names in **internal index order** (≠ Pokédex number). We sidestep
  the index/dex mapping by keying everything on the **species name** (the base_stats filename,
  e.g. `charmander`), which also matches the sprite filenames.

## Formulas

The Gen-1 stat and damage formulas are captured (and implemented in `Battle.gd`) in
**[../engine/battle.md](../engine/battle.md#formulas-gen-1-with-dv0--ev0)**. Catch and EXP
formulas are still TODO (no catching/leveling yet).
