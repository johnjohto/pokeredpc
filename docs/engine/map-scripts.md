# Engine: per-map scripts

One **map-script adapter** per scripted map — `game/scripts/maps/<MapLabel>.gd`, 1:1 with
pokered's `scripts/<Map>.asm` state machines. `MapScripts.gd` is the base: eight hooks Main
consults at fixed touchpoints, plus the helper vocabulary adapters are written in. Unscripted
maps (most of the 223) have no file and share a cached no-op base instance.

Decided in ADR-010 (see [decisions.md](../decisions.md)); migration tracked in **gh #53**.

## Discovery & lifecycle

- `Main.map_script(label)` lazily `load()`s `res://scripts/maps/<label>.gd` (else the base),
  injects `main`, and caches the instance per label for the session.
- **Adapters are stateless.** Durable state lives in `main.story_events` (saved); anything an
  adapter kept in a member variable would silently miss the save — don't.
- Dispatch is by **map label**. For `object_shown` that label can be a **neighbor** of the
  center map (objects spawn for every placed map in the world).

## The eight hooks

| Hook | Called from | Contract |
|---|---|---|
| `on_enter()` | `_on_map_loaded` (after the cutscene/modal guard) | lay script-placed blocks (doors, gates) |
| `on_battle_end()` | `Cutscene.trainer_battle`, after a **won** map-trainer battle | re-run the map's load callback — see the rule below |
| `on_step(cell) -> bool` | `_on_player_moved`, **after** spin tiles, **before** rebase / warps / trainer sight | `true` = trigger fired, step consumed (no warp/sight/poison/encounter) |
| `on_interact(front, npc) -> bool` | top of `interact` | `true` = handled; `false` falls through to generic handling (hidden items, Cut, item balls, NPC text). `npc` is the faced NPC, **including** across-counter resolution (shop/Center clerks) |
| `on_warp(w, dest_const, dest_label) -> bool` | `_do_warp`, after dest resolution, before the fade + load | `true` = warp consumed (blocked or replaced by a beat) |
| `object_shown(k) -> Variant` | `_object_shown`, after the generic Snorlax/boulder rules | `true`/`false` decides visibility; `null` falls through (default: shown) |
| `boulder_hole(cell) -> bool` | `try_push_boulder`, before the shove | `true` = a boulder may be shoved into this (unwalkable) cell — a Seafoam hole |
| `on_boulder(cell, npc)` | `try_push_boulder`, after the slide starts | per-map boulder effects: floor switches, hole falls |

**Post-battle rule (faithfulness):** pokered's `EndTrainerBattle` (`home/trainers.asm`) sets
`BIT_CUR_MAP_LOADED_1`, so the map's load callback runs again the moment a trainer battle ends.
A door that callback places therefore opens **on the spot** when its last guard falls — not on the
next visit. Any adapter whose `on_enter` is gated on a trainer fought on that same map must
override `on_battle_end()` to re-run it (`func on_battle_end(): on_enter()`), or the map reads as
a softlock: Rocket Hideout B1F/B4F's guard doors and the Lorelei/Bruno/Agatha exit seals all
depend on this.

The same hook covers the other shape a beaten trainer can take: **the trainer is himself the door.**
pokered's `GameCornerRocketBattleScript` walks the Game Corner grunt off his tile and
`GameCornerRocketExitScript` then `HideObject`s him — and he STAYs on (9,5), the one walkable cell
adjacent to the poster at (9,4). An adapter for a trainer who stands on a chokepoint pairs
`object_shown(k) -> not defeated(x, y)` (he stays gone across reloads) with
`on_battle_end() -> hide_object(k)` (he goes the instant he loses). The walk-off is animation; freeing
the cell is the state that matters. Skipping it sealed the Rocket Hideout — and with it the SILPH
SCOPE and the rest of the game — behind a sprite that never moved (gh #89). Before assuming a switch,
sign, ball or door is reachable, run `python tools/audit_chokepoints.py`, which checks exactly this
across every map and gates at zero.

**Ordering rule (faithfulness):** pokered runs the map's `*_Script` first each overworld frame —
`CheckFightingMapTrainers` (trainer sight) is invoked *from* map scripts, not before them. So
`on_step` fires **before** trainer sight. The pre-seam code ran gate/current checks *after*
sight; migrating a map to `on_step` can therefore change priority on cells where both could
fire — check each migrated map against its asm (the family's `--flag` selftest must stay green).

## The script vocabulary (base helpers)

`has_event / set_event / clear_event`, `say`, `set_block`, `sfx`,
`face_player(npc)` (call before NPC dialogue — the generic flow's `face_to`
doesn't run when an adapter handles the interaction), `defeated(x, y)` (trainer's home cell),
(`bounce_back` / `step_back_down` / `thirsty_guard` are gone — they migrated into the Event
VM's command vocabulary with their maps, gh #40),
`show_object(k)` / `hide_object(k)` (pokered's `ShowObject`/`HideObject` predefs — flip a
toggleable object's visibility mid-map, where `object_shown` only decides it at load),
and shared gimmick mechanisms (`place_silph_doors`, `silph_door_interact`). Adapters also hold
`main` directly — full access, the way pokered scripts address WRAM; the helpers are the
documented idiom, not a wall.

## Writing a new adapter

1. `game/scripts/maps/<MapLabel>.gd`, `extends MapScript`, doc-comment citing the asm source.
2. Overload only the hooks the map needs; keep per-map data (`const` tables of coords/blocks)
   in the adapter, next to the logic that uses them.
3. Event names are the save format — when migrating existing behaviour, keep them **byte-exact**.
4. Cutscene beats stay in `Cutscene.gd`; adapters trigger them (`main.cutscene.<beat>()`).
5. Run the map's `--flag` selftest; add one for new story beats.

## Migration status

**Adapters are dissolving into authored events (gh #40, ADR-019).** Maps whose story is
authored event records (`game/events/*.json`, byte-copied into the project) are served by the
generic `EventMapScript` — `map_script()` returns it when the project carries events for the
label and no hand-written `.gd` exists (a leftover `.gd` wins, with a warning: that's a
half-finished wave). Migrated so far, by mechanism family: the LAST_MAP connectors
(UndergroundPath*/DiglettsCave*), Cycling Road's forced bike (Route16/17/18 + both gate
houses), the interact→beat forwarders (aides, rod gurus, gift NPCs, Daycare, BikeShop,
prize/vending counters, VermilionDock's departure, …), the Saffron thirsty guards
(Route5–8 gates, fully authored — no native mechanism left), the badge/bag bounce-backs
(Route22Gate, Route23's seven checkpoints, ViridianCity, CinnabarIsland), and the Silph Co
card-key doors + story floors (SilphCo1F–11F; the elevator remains an adapter). The sections
below describe the adapters that remain.

**Complete** (gh #53): all ~80 scripted maps live behind the seam; Main's dispatchers are one
adapter call each, and every remaining `center_label ==` in Main.gd is a test-harness assertion.
Shared mechanisms on the base: `place_silph_doors`/`silph_door_interact`, `guard_door`,
`thirsty_guard`, `e4_exit`, `mansion_blocks`/`mansion_switch`, `switch_doors_enter`/
`boulder_switch`, `hole_at`/`boulder_falls`, and `elevator_enter`/`elevator_panel` (the
three elevators — engine/events/elevator.asm: the door warps lead back to the boarding
floor until the panel picks a floor, which retargets them live off `main.warped_from` and
runs `Main.shake_elevator`; the asm floor tables' warp numbers are 0-based, +1 in the
adapters' `FLOORS`).

**Stays generic in Main by design** (data-keyed mechanisms, not map scripts): `BENCH_GUY_TEXT` +
the Pokécenter PC/bench, `GIFT_NPCS` (text-id keyed), `HIDDEN_EVENTS` (kind-dispatched, incl.
the Cinnabar quiz machines), the gym-guide/`_GYM_BADGE` line, fishing tables (bag flow),
`FLY_DESTS`/`DARK_MAPS` (global), and the Snorlax/fallen-boulder visibility rules. New story
beats (gh #22) land directly as adapters.
