# Engine: warps & map switching

Implemented in `game/scripts/Main.gd` (`load_map`, `_warp_at`, `_on_player_moved`,
`_do_warp`). Source data comes from `data/maps/objects/<Map>.asm` (see
[../data-formats/maps.md](../data-formats/maps.md)).

## Warp data (per map JSON)

```json
"warps": [ { "x": 5, "y": 5, "dest_const": "REDS_HOUSE_1F", "dest_warp": 1,
             "dest_map": "RedsHouse1F" } ]
```

- `x,y` are in **cell units** (16px grid) — they index the collision/movement grid directly.
- `dest_warp` is **1-based** into the destination map's warp list (engine subtracts 1).
- `dest_map` is the resolved label of `dest_const` (added by the extractor). For
  `dest_const == "LAST_MAP"` (`$ff`) there is no fixed label — see below.

## Rules (mirrors pokered)

1. **A warp fires only under pokered's conditions, not on any step onto its square** (gh #80,
   `CheckWarpsNoCollision` + `ExtraWarpCheck`; `_warp_should_fire` in Main.gd). Standing on a warp
   square, it fires when either:
   - the tile under you is a **door/warp tile** for the tileset (`data/tilesets/{warp,door}_tile_ids.asm`,
     ported into `_WARP_DOOR_TILES`) — doors, ladders, stairs, and the Silph warp pads (`$20`): these
     warp on step, immediately; **or**
   - **ExtraWarpCheck** passes for a held direction — *fn1* `IsPlayerFacingEdgeOfMap` (you're stepping
     toward the map edge; most maps), or *fn2* `IsWarpTileInFrontOfPlayer` (the faced tile is a warp
     tile; OVERWORLD/SHIP/SHIP_PORT/PLATEAU tilesets + Rock Tunnel 1F + Rocket Hideout basements).
   So a warp on a plain floor tile that isn't at an edge never fires (Silph 11F's president mat, a
   Center mat you arrive standing on). Edge warps also fire on a step *toward* the edge while standing
   on the warp (walking into the map boundary to leave a building) — Player.gd, not just on arrival.
   `warp_armed` still disarms warps the instant you arrive on one so you don't bounce straight back.
   - **fn2 at a map edge reads the border block.** `IsWarpTileInFrontOfPlayer` looks at the tile *in
     front*; when you face off the map edge that tile is the map's **border block** (pokered fills the
     screen margin with it in `LoadCurrentMapView`), so `_feet_tile_or_border` returns the border tile
     rather than "off-map". This is how the S.S. Anne / cabin exits and the Vermilion Dock north exit
     fire — their border tile is `$01`/`$5C`, which is a fn2 warp-in-front tile. Without it, every
     SHIP/SHIP_PORT-tileset "walk off the edge to leave" warp is dead (gh #80).
   - **`SS_ANNE_BOW` is a fn2 exception:** `IsWarpTileInFrontOfPlayer` jumps to
     `IsSSAnneBowWarpTileInFrontOfPlayer`, which fires iff the faced tile is `$15` (the stairs) for
     *any* facing — it ignores the per-direction `WarpTileListPointers` list the rest of the SHIP
     tileset uses. `_warp_should_fire` special-cases `center_label == "SSAnneBow"` accordingly, so the
     bow's two exit warps fire only facing RIGHT into the stairs, not facing DOWN as the generic list
     would over-fire (gh #130). (`SS_ANNE_3F` is a fn1 exception the other way — see `_extra_warp_fn2`.)
2. **Warp tiles are always walkable.** `is_walkable` returns true for any warp tile so the
   player can step onto doors regardless of the tile's passability.
3. **`LAST_MAP` returns to the last *outside* map.** `last_outside_map` is updated **only
   when leaving a map whose tileset is `overworld`/`plateau`** — exactly pokered's
   `wLastMap` behavior (set only when `CheckIfInOutsideMap`). This makes multi-floor
   buildings exit back outdoors correctly (1F→2F→1F→door still goes outside).

## Verified

`--warptest` round-trips PalletTown → (door) → RedsHouse1F → (exit mat / LAST_MAP) →
PalletTown. Run via `pwsh tools/run.ps1 -- --warptest`.

## Not yet done

- Door open/close animation and the auto step-out on arrival.
- Connections (seamless route scrolling) — data is extracted (`connections`), engine is M7.
- Special warps (e.g. `LAST_MAP` from an outdoor map, fly/dungeon warp pads, holes).
