# Engine: wild encounters

Each map's grass/water encounter table is extracted by `build_wild` from
`data/wild/maps/<MapLabel>.asm` into `assets/wild.json`:

```
{ "slots": [50,101,140,165,190,215,228,241,252,255],   # cumulative slot thresholds (0-255)
  "maps": { "Route1": { "grass_rate": 25, "grass": [[3,"pidgey"],[3,"rattata"], …10],
                        "water_rate": 0, "water": [] }, … } }
```

`_RED`/`_BLUE` conditional blocks resolve to the **Red** version. 56 maps have encounters.

## Encounter check (`Main._try_wild_encounter`)

On each step onto a tall-grass cell (`_on_player_moved`):

1. **Rate** — `randi() % 256 < grass_rate` (e.g. Route 1's 25 ≈ 9.8 %/step). No table or a
   0 rate (towns, interiors) → no encounters.
2. **Slot** — roll `r = randi() % 256`, pick the first slot whose cumulative threshold `>= r`
   (the fixed Gen-1 distribution: ~20/20/15/10/10/10/5/5/4/1 %).
3. Spawn that slot's `(level, species)` via `start_battle`.

So each area produces its authentic species and levels. Verified by `--wildtest` (Route 1:
~10 % rate, only pidgey/rattata, weighted by slot).

## Not yet modelled

Water encounters (need surfing), the fishing rods (`good_rod`/`super_rod` tables are not
extracted), repels, and the "no encounters on the first step after a battle" nuance.
