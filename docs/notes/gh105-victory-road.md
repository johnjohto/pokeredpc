# gh #105 — Victory Road under tile-pair collisions (WIP analysis)

Branch: `feature/gh105-tile-pair-collisions`. This note captures the solved VR1F puzzle and the
remaining work so the next session resumes without re-deriving it.

## The problem tile-pairs create

On `main` (no tile-pairs) the bot climbs VR trivially: `_pt_climb_victory_road` walks straight to the
`(1,1)` ladder → 2F, never touching the 1F switch. Adding the cavern tile-pairs
(`floor $05 ↔ ledge $20/$2A/$21`) **partitions VR1F into 3 pockets**:

- **pocket 0** (106 cells): the up-ladder `(1,1)` + boulders `(14,2)`,`(2,10)`.
- **pocket 1** (69 cells): the **entrance** `(8,16)` + the **switch `(17,13)`** + boulders `(5,15)`,`(2,10)`.
- pocket 2 (9 cells): boulder `(14,2)`.

The entrance is cut off from the ladder by exactly **three `$05→$20` crossings**. So the intended
route must press the `(17,13)` switch — which pokered's `VictoryRoad1FDefaultScript` (`CheckBoulderCoords`)
requires a boulder on — and that opens block **`(4,6)`** (`.next`: `ReplaceTileBlock $1d @ lb bc,6,4`),
which bridges pocket 1 → the `(1,1)` ladder pocket (verified: opening `(4,6)` grows the entrance region
69 → 180 cells and reaches `(2,1)`, adjacent to `(1,1)`).

## The key that unblocks it: entrance warps are STANDABLE (gh #80)

The Sokoban first reported **NO SOLUTION** because it treated the entrance warps `(8,17)`,`(9,17)` as
solid. They aren't. VR1F uses `ExtraWarpCheck` **function 1** (`IsPlayerFacingEdgeOfMap`): a warp fires
only when you step **toward the map edge** (facing south). You can stand on `(8,17)` facing **north** and
push a boulder up without warping out. This is exactly **gh #80** — the port currently fires warps on any
step onto a warp tile, so it would eject you here. **#80 must be fixed for VR (and it's the same fix the
Silph/mat problems need).**

With entrance warps standable, `tools/sokoban.py` finds the real StrategyWiki route:

**Boulder `(5,15)` → switch `(17,13)`, 18 pushes (9 legs):**
```
[Vector2i(5,15), DOWN,  1]
[Vector2i(5,16), RIGHT, 3]
[Vector2i(8,16), UP,    1]
[Vector2i(8,15), RIGHT, 1]
[Vector2i(9,15), UP,    1]
[Vector2i(9,14), RIGHT, 7]
[Vector2i(16,14),UP,    2]
[Vector2i(16,12),RIGHT, 1]
[Vector2i(17,12),DOWN,  1]
```
(dir enum: DOWN=0 UP=1 LEFT=2 RIGHT=3). Then walk to `(1,1)` (now bridged) → 2F.

## Remaining work

1. **gh #80 engine fix** — warps fire only when facing the map edge (`ExtraWarpCheck` fn1 for edge
   warps; fn2 / warp-tile-in-front for the listed maps). Broad change (every building exit/mat) — needs
   its own careful verification pass. **VR depends on it.**
2. **`_pt_vr1f_open_switch`** — drive the 18-push sequence above (boulder push is tile-pair-exempt), then
   `_pt_take_ladder((1,1), VictoryRoad2F, …)`.
3. **VR2F / VR3F** — re-derive the cross-floor routes under tile-pairs the same way (2F switches at
   `(1,16)`→opens `(4,3)`, `(9,16)`→opens `(7,11)`; 3F switch+hole `lb bc,5,3`; note VR2F **resets** the 1F
   switch event on load — Gen-1 boulders reset on floor reload, so a floor's switch must be solved within
   one visit). Use `tools/sokoban.py` (retarget SWITCH/START/ALLB/map) + `--tpprobe --maps=…`.
4. **Seafoam Islands** — 5 fragmented floors + surfing water-pairs + the current/boulder puzzle.
5. **Full chained Stage-1 gate re-verify** under tile-pairs, then land on `main` (close #105/#128, and #80).

## VR1F + #80: DONE and verified (commit 53bee80)

- **#80 warp fix** landed: `_warp_should_fire` (Main.gd) replicates pokered's `CheckWarpsNoCollision` —
  fire immediately only on a tileset warp-tile/door-tile (ported from `{warp,door}_tile_ids.asm`),
  else require `ExtraWarpCheck` (fn1 facing edge / fn2 warp-tile-in-front, dispatched per map/tileset).
  Verified `--warptest` (door round-trip) + `--mtmoontest` (cave ladders) still pass.
- **VR1F climb** landed: `_pt_vr1f_open_switch` runs `_PT_VR1F_PUSHES` (the 18-push sokoban route for
  boulder (5,15) → switch (17,13)); `_pt_climb_victory_road` calls it first. `--victoryroadtest --cave`
  confirms: 1F climbs to 2F **and** 2F switch1 (push (4,14)→(1,16)) presses. It then FAILS at the old
  2F→3F ladder `(25,14)` (which needs BOTH 2F switches) — that's the next leg to reroute.

## VR2F/3F: a multi-floor Sokoban — static model insufficient (blocker)

`tools/vrsolve.py` is a general per-floor push solver (map/start/boulder/target/opened-blocks). Structure
so far (dest_warp is 1-based → land = `warps[dest_warp-1]`):
- 2F: land (0,8) in the west pocket; switch1 (1,16, opens block (3,4)) reaches ladder **(23,7)→3F(23,7)**
  (the reachable up-ladder — not the old (25,14)). switch2 (9,16, opens (7,11)) needs boulder (23,16),
  which only appears after a 3F boulder falls through the 3F hole.
- 3F: land (23,7) in pocket0; switch1 (3,5, opens (3,5)) connects pocket0→pocket1 (a **27-push** move of
  boulder (22,3)); pocket1 has the hole (23,15) + its boulders; the player-hole drops to 2F(22,16).
- Cross-floor ladders: 2F(23,7)↔3F(23,7); 2F(25,14)↔3F(27,15); 2F(27,7)↔3F(26,8); 2F(1,1)↔3F(2,0).

**Unresolved contradiction:** the 2F exit pocket `{(29,7)→Route23, (27,7)→3F(26,8)}` stays disconnected
from the 1F-landing cluster even with **both** 2F switches opened and the hole used — my static
pocket model (boulders = fixed obstacles) can't reach it, yet the game is winnable. The missing piece is
almost certainly that **pushing a boulder OUT of a chokepoint opens a corridor** (dynamic connectivity a
static flood misses), and/or a subtlety in which cells the switch blocks bridge. Cracking 2F/3F needs a
**dynamic cross-floor Sokoban** (state = floor + all boulder positions + switch/hole flags, connectivity
recomputed per state) or in-engine trial-and-error (~5 min/cycle). The port's own map-script docs
(`VictoryRoad2F.gd`/`3F.gd`) say the 3F switch/hole "gate items and a shortcut," so the main exit route
may be shorter than the analysis suggests — re-read them against the walkthrough
(StrategyWiki/GameFAQs: "push a block across 3F, loop to the bottom, push the next down the hole to 2F to
open the final switch").

## VR2F/3F: the exit is reached ONLY via 3F, and it's a true multi-floor Sokoban

Findings (verified by flood experiments):
- The 2F exit pocket `{(29,7)→Route23, (27,7)→3F(26,8)}` is **sealed from the 1F-landing on 2F** even with
  both 2F switches opened and all boulders removed. The only way in is **down from 3F(26,8)** (→2F(27,7)).
- 3F(26,8)/(27,15) form pocket2. From the 3F landing (23,7), pocket2 is reachable only if boulders are
  *removed*, but **pushing can't replicate removal here**: (24,10) sits in a 1-wide chokepoint at the
  pocket2 entrance with walls above/below and the pocket (goal side, unreachable) to its right — there is
  **no cell to park it in**. So the naive "push (13,12)+(24,10) aside" route is INVALID (2-boulder solver:
  NO SOLUTION).
- ⇒ The real route must involve the **3F switch (3,5)** and/or the **hole (23,15)** (boulder falls to
  2F(23,16); player falls to 2F(22,16)) in a specific order, likely: reach 3F pocket1 via switch1, push a
  boulder into the hole, drop through, push the 2F boulder onto **switch2 (9,16)** whose block `(7,11)`
  opening finally bridges to pocket2/the exit. The static per-step analyses each hit a wall because the
  puzzle is **holistic** — boulder positions on every floor + switch/hole flags interact.

**Next tool to build:** a dynamic cross-floor Sokoban — state = `(player floor+pocket, boulder positions
on all 3 floors, switch flags, hole-boulder flag)`, transitions = pushes (tile-pair-exempt), ladders
(land = `warps[dest_warp-1]`), the hole (boulder→2F(23,16), player→2F(22,16)), and switch-block opens.
Search from the 1F entrance to the Route 23 exit. That yields the authoritative push/ladder sequence to
wire into `_pt_climb_victory_road`. (VR1F's isolated push + the #80 fix are already done and verified.)

## RESOLVED — Victory Road is fully navigated (commit 7f85dad)

The dynamic solver (`tools/vrdyn.py`) found the route; `_pt_climb_victory_road` drives it end to end.
`--victoryroadtest --cave --seed 1` PASSES (climbed=true, map=Route23). Route:
1F push (5,15)→(17,13) → (1,1)↑2F; 2F push (4,14)→switch1 (1,16) → (23,7)↑3F; 3F push (22,3)→switch1
(3,5) [27 pushes] → push (22,15) into the hole (23,15) → drop to 2F(22,16); 2F push the fallen (23,16)
→ switch2 (9,16) → (25,14)↑3F(27,15) → (26,8)↓2F(27,7) → out to Route 23. `_pt_push_boulder` now settles
cave-floor wild encounters between shoves.

## Seafoam is NOT on the critical path — no work needed

The bot reaches Cinnabar via **Pallet → Route 21** open water (`_pt_reach_cinnabar`), a single water
component; it never enters Seafoam's interior. So Seafoam's tile-pairs/currents don't affect the gate.

## All tile-pair-affected critical-path maps are handled

Mt Moon (`--mtmoontest`), Rock Tunnel (`--rocktunneltest`), Victory Road (this work) — done. Viridian
Forest is one pocket. Diglett's Cave fragments into 2 pockets but both entrances share the connected
166-cell one, so the crossing + the DIGLETT catch both work. (Cerulean Cave is post-game.)

## CORRECTION — boulder pushes are NOT fully tile-pair-exempt (the WIP notes above overstate it)

The solver work above (and an early `try_push_boulder`/`Player.gd` comment) assumed a STRENGTH shove ignores
tile-pairs entirely. That's wrong. pokered's `CheckForCollisionWhenPushingBoulder`
(`engine/overworld/player_state.asm`) calls `CheckForTilePairCollisions2` against `TilePairCollisionsLand`,
comparing the **player's** feet tile (screen 8,9) to the tile **two steps ahead** (the boulder's destination,
via `GetTileTwoStepsInFrontOfPlayer`), and also refuses a destination of stairs `$15`. So a push *is* blocked
across an elevation edge — just measured player↔destination (two apart), which is looser than the adjacent
player-step rule (that's why boulders can still be maneuvered where the player alone can't step).

`try_push_boulder` now enforces this faithfully. **The VR route did not change:** a direct check of all 65
route pushes (`tools/vr_push_check.py`) shows every shove happens on the ledge tiles `$20`/`$2a`/`$21` and the
`$2d` switches — none crosses a `$05`(floor)↔ledge boundary, the only thing the cavern pairs catch — so 0/65
are newly blocked. The pockets/switch bridging are unaffected (switches open *blocks* elsewhere; the boulder
never has to cross a pocket boundary itself).

## Remaining for #105

Just the **full chained gate re-verify** (NEW GAME → HALL OF FAME, seed 1, on this branch — which also
validates the game-wide #80 warp change), then land on main + close #105/#128/#80.
