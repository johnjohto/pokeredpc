# Engine: NPCs

NPCs come from each map's `object_events` (extracted). Implemented in `game/scripts/NPC.gd`
with spawning/occupancy/interaction in `Main.gd`.

## Sprites

- All 66 overworld sprite sheets are extracted to `game/assets/sprites/<file>.png` (same
  white→transparent treatment as the player). Walking sprites are 16×96 (6 frames, same
  layout as the player); static objects (poké balls, boulders, …) are 16×16 (1 frame).
- `game/assets/sprites/index.json` maps `SPRITE_* -> {file, frames}`. Built from three
  pokered files: `SpriteSheetPointerTable` (id → label) ⋈ `gfx/sprites.asm` (label → file)
  ⋈ `constants/sprite_constants.asm` (id → `SPRITE_*` name).

## object_events (from `data/maps/objects/<Map>.asm`)

```
object_event x, y, SPRITE_OAK, STAY, NONE, TEXT_PALLETTOWN_OAK
object_event x, y, SPRITE_GIRL, WALK, ANY_DIR, TEXT_PALLETTOWN_GIRL
```

Extracted as `{x, y, sprite, args:[movement, dir_or_range, text, ...]}` (cell units). The
engine reads:
- **movement** `STAY` ($FF) / `WALK` ($FE).
- For `STAY`, arg 2 is a **facing**: `DOWN/UP/LEFT/RIGHT` (and `NONE`/boulder → down).
- For `WALK`, arg 2 is a **range**: `ANY_DIR` (all 4), `UP_DOWN`, `LEFT_RIGHT`.
- **text** = the first `TEXT_*` arg (used by interaction; M9 will render it).
- For **trainers** (an `OPP_*` class + party number follow the text arg) the extractor also
  attaches `sight` (line-of-sight range, tiles) and the resolved `battle_text` / `end_text` /
  `after_text` strings — see *Trainers* below.

## Trainers (line of sight)

A trainer object_event carries an `OPP_*` class + party number. Three extra fields come from the
map's **script** trainer headers (`trainer flag, range, TextBefore, TextEnd, TextAfter` in
`scripts/<Map>.asm`), zipped onto the trainer object_events in declaration order by the extractor:
`sight` (view range), `battle_text` (before the fight), `end_text` (on the player's win), and
`after_text` (re-talking a beaten trainer).

- **Detection** (`Main._trainer_seeing_player`, mirrors `home/trainers.asm` `CheckFightingMap-
  Trainers` + `engine/overworld/trainer_sight.asm`): on each step, an undefeated trainer engages
  if the player is lined up on its facing axis, **in front** of it, within `sight` tiles. Like
  pokered there is **no obstacle check** (maps are laid out so sight lines are clear).
- **Engage** (`Cutscene.trainer_spotted` → `trainer_battle`): the `!` bubble (`emote_shock.png`)
  pops over the trainer, the pre-battle music plays (evil/female/male via the
  `encounter_types.asm` lists), the trainer marches straight up to the player, then `battle_text`
  → battle → `end_text` on a win. Manual interaction reuses `trainer_battle(npc, false)` (no
  walk-up); a defeated trainer just shows `after_text`.
- **Defeat tracking**: `Main.defeated_trainers` keyed by `Main.trainer_id(npc)` = the trainer's
  **home** cell (stable across the walk-up, which moves `npc.cell`).

Verified by `--sighttest` (Route 3: negatives rejected, `!` bubble, walk-up, before/end/after
text, defeat persisted).

## Gym leaders & badges

Gym leaders are trainer object_events but use the gym's own `text_asm` script rather than the
generic `trainer` header, so their dialogue is **hardcoded** in `Cutscene._GYM_LEADERS` (keyed by
`OPP_*` class), like the other scripted story beats. `Main.interact` routes a leader to
`Cutscene.gym_leader_battle` *before* the generic trainer branch: pre-battle text → battle → on a
win, the badge (`sound`+text), the badge info, and the gym's TM (added to `player_bag`); a
re-challenge after `event` is set just replays the post-battle line. Earned badges live in
`Main.badges` (saved) and grant their Gen-1 stat boost (see [battle.md](battle.md)). Adding a leader
is one `_GYM_LEADERS` entry — `tm_get` ("Wait! Take this!") is optional, and names are filled only
where a `%s` appears (`Cutscene._fmt`). **Pewter / Brock** (Boulder + TM34), **Cerulean / Misty**
(Cascade + TM11), and **Vermilion / Lt. Surge** (Thunder + TM24) are wired. The gym guide's line
(`Main._gym_guide_text`, keyed by `_GYM_BADGE`) branches on that gym's badge. Ordinary gym trainers
engage via the sight system above. Verified by `--gymtest`.

**Vermilion's trash-can puzzle** gates Lt. Surge (scripts/.../vermilion_gym_trash.asm). The motorized
door is block (2,2) — the `.blk` ships it *open*, so `Main._on_map_loaded` closes it (`set_block` to
the door block `0x24`, whose top half is solid) and resets the puzzle whenever the gym loads
unsolved. Pressing A on a trash can (`_trash_can_index`, the 5×3 grid at x∈{1,3,5,7,9}, y∈{7,9,11})
runs `_trash_check`: find the random 1st switch, then the 2nd (a neighbour from the `_TRASH_NEIGHBORS`
table) — a wrong 2nd guess resets both. Solving sets `VERMILION_2ND_LOCK` and `set_block`s the door
open (`0x05`). `Main.set_block` is the reusable runtime block swap (updates the 4 collision tiles +
redraw). Verified by `--surgetest`.

## Behavior

- **Spawn**: `Main._spawn_npcs()` runs on every `load_world` (NPCs belong to the **center**
  map; rebuilt on warp/connection rebase). Sprites unknown to the index are skipped.
- **Wander**: `WALK` NPCs pick a random allowed direction on a 0.8–2.6 s timer and step if the
  target is free and within `TETHER` (4) tiles of home. `STAY` NPCs hold their facing.
- **Collision (solid)**: NPCs occupy their `cell` (reserved at step start, like the player).
  - `Main.player_can_enter(cell)` = passable **and** no NPC there → the player uses this.
  - `Main.npc_can_enter(cell, npc)` = passable, not the player's cell, not another NPC.
- **Interaction**: pressing **Enter/Space** (`ui_accept`) calls `Main.interact(player)`,
  which finds the NPC in `player.front_cell()`, turns it to face the player (`NPC.face_to`),
  and (for now) prints its `text_id`. M9 replaces the print with a text box.

Verified by `--npctest` (3 NPCs in Pallet Town; Oak solid + faces player on interact;
the Girl wanders).

## Not yet done

- NPCs only render/update on the **center** map (not across connection seams).
- No Y-sorting between player and NPCs (player added first → NPCs draw on top).
- Arbitrary scripted NPC movement paths (`MoveSprite` RLE) are still ad-hoc per cutscene.

## HM field moves (Cut)

HMs teach field moves (`Main.HM_MOVES`: HM01→CUT …). Using an HM from the bag opens a "teach to
which mon" list (`_teach`); only species whose extracted **`tmhm`** list includes the move can learn
it (HMs aren't consumed). **Cut**: facing a cuttable overworld tree (a `CUT_TREE_BLOCKS` block whose
faced cell tile is `CUT_TREE_TILE` `$3d`) and pressing A — with a party mon that knows CUT **and**
the Cascade Badge (`FIELD_MOVE_BADGE`) — swaps the block to its cut version
(`data/tilesets/cut_tree_blocks.asm`, via `Main.set_block`) and plays `cut`; without the means it
just hints "This tree looks like it can be CUT down!". Verified by `--cuttest`. (Fly/Surf/Strength/
Flash share the data tables but aren't wired yet; HM01 itself is obtained later on the S.S. Anne.)

## Pokémon storage PC

Facing the Pokémon Center PC (tile (13,3), facing UP — `OpenPokemonCenterPC`) opens WITHDRAW /
DEPOSIT / SEE YA (`Main._open_pc`, `turn_on_pc` sfx). Stored mons live in `Main.pc_box` (full mon
dicts, **saved**). DEPOSIT lists the party (can't deposit your **last** mon); WITHDRAW lists the box
(needs a free party slot, party < 6); blocked actions play `denied`, successful ones
`withdraw_deposit`, and the lists reopen until empty/CANCEL. This relieves a full party so you can
keep catching. Verified by `--pctest`.

## Usable items (overworld bag)

`Main._bag_select`/`_bag_use_on` cover the common items (tables `POTIONS`, `STATUS_HEALS`, `REVIVES`,
`REPELS`, plus `RARE CANDY` and the evolution stones): potions heal a set/full amount (FULL RESTORE
also clears status), status heals cure the matching ailment (FULL HEAL any), Revive restores a
fainted mon to half/full HP, Rare Candy adds a level, and the field items use without a target —
**Repel** sets `Main.repel_steps` (counts down per step, suppresses wild encounters; saved) and
**Escape Rope** warps you **outside**, to the town you last healed in, on its `FlyWarpData` tile
(`_escape_warp()` → `FLY_DESTS[_RESPAWN_TOWN[respawn_map]]`), mirroring pokered's `BIT_ESCAPE_WARP` path
(`PrepareForSpecialWarp` → `.usedFlyWarp` on `wLastBlackoutMap`). Wrong targets (outdoors, Agatha's room)
say "It won't have any effect." **Blacking out shares that exact destination and additionally halves your
money** (`whiteout()`, gh #101). DIG and TELEPORT will reuse `_escape_warp()` when added (gh #102).
Verified by `--itemusetest` and `--whiteouttest`.

## Hidden items

Invisible items (`build_hidden_items` → `assets/hidden_items.json`, `map → [{x,y,item const}]` from
the `HiddenItems` hidden-events) are found by pressing A facing their tile (`Main._try_hidden_item`):
add to the bag, "RED found …!", one-shot via `Main.found_hidden` (saved). No Itemfinder needed — the
spot just yields nothing once taken. Verified by `--hiddentest`.

## Poké Marts

Talking to a mart's clerk (`SPRITE_CLERK` on a map in `assets/marts.json`) opens a BUY / SELL / SEE
YA menu (`Main._open_mart`). `build_marts` extracts each mart's stock (`map → [item const]` from
`data/items/marts.asm`) and `build_items` also emits `assets/item_prices.json` (display name → buy
price from the BCD `ItemPrices`). BUY lists the stock as "NAME $price"; selecting buys one if
affordable (`purchase` sfx, else `denied`) and stays open. SELL lists the bag and gives **half** the
buy price (items with no price are unsellable). Selecting an item opens a **quantity picker**
(`Menu.open_qty`: up/down change the count 1..max with a running total; BUY caps at what you can
afford, SELL at how many you hold), then the purchase/sale applies and the list reopens; CANCEL/B
steps back. Verified by `--marttest`.

## Overworld item balls

A `SPRITE_POKE_BALL` object_event with an **item-const arg** (e.g. `…, TEXT_…, POTION`) is a pickup.
`build_items` extracts `assets/items.json` (item const → display name; TMs/HMs become `TMnn`/`HMnn`),
and `_spawn_npcs` sets `npc.item` to the display name. Facing one and pressing A runs
`Main._pick_up_item`: add to `player_bag`, "RED found …!" (with `get_item1`), then the ball is hidden
and recorded in `Main.picked_items` (keyed `map:x,y`, **saved**) so it stays gone across reloads.
Verified by `--itemtest`.
