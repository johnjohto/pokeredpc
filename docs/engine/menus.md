# Engine: menus & modal input

`game/scripts/Menu.gd` is a reusable cursor-list menu; `Main.gd` drives the START menu and a
yes/no submenu. Built on the same font/box as the [text box](text.md).

## Modal input model (important)

All overworld and UI input is read in **one place** — `Player._process` — exactly once per
frame:

```
if game.modal != null:        # a text box or menu is open
    game.modal.handle_input()  # the modal consumes this frame's input
else:
    # overworld: Esc -> open start menu, Enter -> interact, arrows -> move
```

`Main.modal` holds the active modal `Control` (the `TextBox`, the `Menu`) or `null`. Modals
expose `handle_input()` and never read input in their own `_process` (they only animate).
This makes a single keypress do exactly one thing, so opening a modal can't immediately close
it and closing one can't re-open it on the same frame (the dialogue-loop bug, see
[text.md](text.md)). NPC wandering also pauses while `modal != null`.

## Controls

- **Arrows** move / navigate. **Enter / Space** (`ui_accept`) = A (confirm, interact, advance
  text, choose). **Esc** (`ui_cancel`) = B / START (open the start menu in the overworld;
  cancel/back inside a menu).

## Menu component (`Menu.gd`)

- `open(items: Array, at: Vector2)` shows a bordered box of strings at a screen position,
  auto-sized to the longest item, with a ▶ cursor. `box_w`/`box_h` force a size in tiles and
  `row0` sets the first text row inside the box (the start menu and item lists use 2).
- The border is the Gen-1 ornate double-line frame, drawn by the shared `Frame.gd` helper (see
  [text.md](text.md)); box size is given in **tiles** (border + 2px-row-per-item interior).
- `handle_input()`: up/down wrap the cursor; A emits `chosen(index)`; B emits `chosen(-1)`.
- Glyphs are drawn from `font.png` via the charmap (same as the text box).

### Stacked boxes (gh #66)

Pokered draws every box into one shared tilemap, so a submenu appears **over** its parent
menu, which stays on screen with a hollow `▷` cursor (`PlaceUnfilledArrowMenuCursor`).
`Menu` reproduces this with a background stack: `push_under()` freezes the live box into
`under` (turning its cursor hollow), and an `open*(…, keep_under = true)` draws the new box
over the frozen ones. `pop_under()` restores the top layer as the live box (a closing
`TwoOptionMenu` that put back the tiles it covered). `Main._open_bag` rebuilds its stack
deterministically on every reopen: START menu (hollow ▷ on ITEM) → item list → USE/TOSS →
toss `×NN` picker → toss YES/NO.

Message layering matches pokered's draw order: a menu opened after a question (the elevator
panel, yes/no prompts) draws over the text box, but an item-menu message printed *after* the
menus overdraws their bottom rows — `TextBox.show_text` resets `z_index` to 0 and the
bag-flow helpers (`_say_bag`/`_keep_bag_shown`) bump it to 1.

### Item-list mode (`open_itemlist`)

The faithful ITEMLISTMENU (home/list_menu.asm), used by the bag: the fixed 16×11
`LIST_MENU_BOX` at (4,2)–(19,12); names at col 6 on rows 4/6/8/10 (4 per window); each
quantity printed as `×NN` on the row **below** its name at col 14 — skipped for key items
and HMs (`IsKeyItem`); CANCEL as the last row; `▼` at (18,11) while the last row is below
the window. The cursor (col 5) rides the **top 3 window rows** only (`wMaxMenuItem` = 2, the
4th row is a preview); DOWN on the 3rd row scrolls while `scroll + 3 <= item count` (the
pre-CANCEL `wListCount`), with no wraparound. Cursor *and* scroll survive reopens (`wBagSavedMenuItem` + `wListScrollOffset` →
`_bag_saved_idx`/`_bag_saved_scroll`).

## Start menu (`Main`)

- `open_start_menu()` shows `POKéDEX / POKéMON / ITEM / <PLAYER> / SAVE / OPTION / EXIT`
  (draw_start_menu.asm) — POKéDEX only once obtained, the player's own name for the trainer
  card, EXIT closes. Dispatch is by item text since the list shifts.
- The box is pokered's exactly: top-left (10,0), 10 tiles wide, 16 tall with the dex (14
  without), first item at (12,2) with 2-row spacing, cursor col 11. It stays on screen under
  the item list (you see its top border and EXIT peeking around the bag box — gh #66).
- The cursor is restored on every redisplay (`wBattleAndStartSavedMenuItem` →
  `_start_saved_idx`, saved on any press): back out of the bag and the cursor is on ITEM.
- **B backs out to the START menu** (gh #59, `RedisplayStartMenu`): leaving the bag, the
  party menu (which also abandons a pending SWITCH), the Pokédex, the trainer card, or
  OPTION redisplays the START menu; only B on the START menu itself (or EXIT/START) closes
  it. SAVE is the exception — pokered ends it with `HoldTextDisplayOpen`, back to the
  overworld.
- **SAVE** opens a `YES/NO` menu (`menu_mode = "yesno_save"`); choosing YES calls
  `save_game()` and reports success. See [save.md](save.md).
- **OPTION** opens the real options screen. Verified by `--menutest`.

## OPTION menu (`OptionsScreen.gd`)

Faithful to `DisplayOptionMenu` (engine/menus/main_menu.asm): three bordered rows —
**TEXT SPEED** FAST/MEDIUM/SLOW (letter delay 1/3/5 frames → `textbox.speed`/`battle.speed`
= 60/20/12 glyphs/s), **BATTLE ANIMATION** ON/OFF (OFF turns the `{"moveanim"}` marker into
pokered's 30-frame beat), **BATTLE STYLE** SHIFT/SET (SHIFT — the default — asks
"Will <PLAYER> change POKéMON?" with a free switch before a trainer's next mon, per
`EnemySendOutFirstMon`; tests run as SET since the prompt needs input) — plus CANCEL.
Left/right pick values (applied immediately), reachable from the start menu and the title's
main menu, and saved with the game (`Main.options`). Verified by `--optiontest`.

## Overworld item / party use

- **ITEM** opens the bag (`_open_bag`); choosing a **POTION** or an **evolution stone** then
  shows the party to pick a target (`bag` → `bag_target`). Potions heal 20 HP; a matching
  stone triggers stone evolution (`_try_stone`/`_evolve_mon`). **PKMN** lists the party.
- **Item use returns to the bag** (gh #56; start_sub_menus.asm `ItemMenuLoop`): after using
  or tossing an item — including backing out of a target pick — the item list redisplays,
  with the cursor where it was (`wBagSavedMenuItem` → `_bag_saved_idx`). The exceptions
  close the whole menu on a successful use, per `UsableItems_CloseMenu` + the BICYCLE
  special case: **ESCAPE ROPE, ITEMFINDER, POKé FLUTE, the rods, BICYCLE** (the bicycle also
  skips the USE/TOSS submenu). A *failed* use of these ("no water to fish in", "can't get on
  the bicycle here") returns to the bag like everything else. The plumbing is
  `_say_bag()` / `_text_then`, consumed when the textbox (or town map) closes.
- **ESCAPE ROPE** only works in the EscapeRopeTilesets (forest/cemetery/cavern/facility/
  interior) and never in Agatha's room (ItemUseEscapeRope, gh #61); elsewhere it fails with
  OAK's "this isn't the time" line and returns to the bag.
- **TM/HM use** (ItemUseTMHM, gh #60): USE first plays "Booted up a TM/HM! It contained X!
  Teach X to a POKéMON?" — NO returns to the bag; can't-learn / already-knows re-show the
  party pick (`.chooseMon`); a full moveset runs the LearnMove forget flow (below), and a
  TM is consumed only when the move is actually learned.
- **The LearnMove forget flow** (learn_move.asm, used by level-ups, RARE CANDY, and TMs):
  declining "Delete an older move?" asks "Abandon learning X?" — NO loops back; B on the
  "Which move should be forgotten?" list also routes to the abandon prompt; HM moves can't
  be forgotten ("HM techniques can't be deleted!").
- **RED** shows the trainer card line (name + money).

## Trainer card (`TrainerCard.gd`)

The start menu's player-name entry opens the real card (DrawTrainerInfo + draw_badges.asm):
the player's front pic upper-right, NAME/MONEY/TIME, and the 8 numbered gym slots — each
shows the **leader's face until that badge is earned, then the badge itself** (Giovanni's
face is the "?"). A/B closes. Verified by `--menutest`.

## Bag rules

- **Capacity**: 20 distinct slots, 99 per stack (`Main.add_item`, AddItemToInventory_);
  full-bag pickups leave the item ball / hidden item in place ("But <PLAYER> has no room
  for it!"), marts refuse a new slot, gift NPCs re-offer later. A stack overflow refuses
  the whole add (pokered splits the excess into a second slot, but slots here are
  name-keyed so duplicates can't exist — gh #63). Emptying a slot resets the remembered
  bag cursor (RemoveItemFromInventory_).
- **USE/TOSS**: selecting a bag item opens the submenu **over the still-visible list** (gh
  #66) — the `USE_TOSS_MENU_TEMPLATE` box at (13,10)–(19,14), text at (15,11) — and choosing
  an item also drops any SELECT-held swap (`.choseItem`). TOSS runs the quantity picker (the
  5×3 `×NN` box at (15,9), DisplayChooseQuantityMenu) + the "Is it OK to toss?" confirm (the
  YES/NO box at (14,7), TossItem_), each stacked over the previous boxes; key items refuse
  ("That's too impor- tant to toss out!"). Every toss outcome returns to the bag list
  (gh #56), and A on CANCEL exits to the START menu like B (ExitListMenu).
- **SELECT-swap** reordering (gh #57, swap_items.asm `HandleItemListSwapping`): SELECT holds
  an item (hollow `▷` on its row), a second SELECT swaps the two rows. CANCEL can't be
  swapped; re-SELECTing the held item keeps it held. Works on every ITEMLISTMENU surface —
  the bag, the player's PC item lists (players_pc.asm), the **battle** bag (core.asm), and
  the mart **SELL** list (pokemart.asm) — but not the mart BUY list (a PRICEDITEMLISTMENU).
  Verified by `--bagtest`, `--keybindtest`, `--movefxtest`.

## League PC

After entering the Hall of Fame, every PC gains the **POKéMON LEAGUE** entry
(engine/menus/pc.asm): the viewer replays each recorded team, oldest first — the mon's pic
with its name/level under the record number (league_pc.asm). Teams are recorded at the HoF
ceremony (up to 50, oldest dropped) and saved. Verified by `--hoftest`.
