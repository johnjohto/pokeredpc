# Engine: text & dialogue

Font + dialogue extraction (`extract.py: build_text`) and the in-game box
(`game/scripts/TextBox.gd`, wired through `Main.interact`).

## Font & charmap

- `gfx/font/font.png` → `game/assets/font.png` as RGBA: ink = dark GB shade, paper =
  **transparent** (so it composites onto the box). 16×8 = 128 tiles.
- `constants/charmap.asm` maps characters to bytes. Printable glyphs are `$80..$ff`, so the
  **font tile index = byte − 0x80** (e.g. `A`=$80→0, `9`=$ff→127, `é`=$ba→58). Space (`$7f`)
  renders blank. Emitted as `game/assets/charmap.json` (`char -> tile index`).

## Dialogue extraction (`game/assets/text.json` : `TEXT_* -> string`)

Resolution chain: `object_event`/`bg_event` give a `TEXT_*` id →
`scripts/<Map>.asm` text-pointer table (`dw_const ScriptLabel, TEXT_id`) → the script's
first `text_far _Str` → the string in `text/*.asm`.

Strings are decoded from the `text`/`line`/`cont`/`para` macro args:
- `line`/`cont`/`next` → `\n`; `para`/`page` → `\f` (page break); `@` ends the string.
- token expansion: `#`→`POKé`, `<PLAYER>`→`RED`, `<RIVAL>`→`BLUE`, `<PKMN>`→`PKMN`; other
  `<...>` tokens are stripped to their inner text.

**~653 / 1209** text ids resolve this way. The rest are `text_asm` scripts (conditional /
computed text) with no simple `text_far`; the engine shows `(TEXT_ID)` as a fallback for
those. Resolving them needs a small script interpreter (future work).

## Text box (`TextBox.gd`, a `Control` under a `CanvasLayer`)

- Bottom-screen panel (rows 12-17, full width); draws glyphs from `font.png` via the charmap.
  Its border is the Gen-1 ornate double-line frame (font_extra tiles `┌─┐│└┘`, extracted to
  `assets/frame.png`) drawn by the shared **`Frame.gd`** helper — also used by the menus and
  naming screen so every box matches the GB look.
- **Typewriter**: reveals `SPEED` glyphs/sec. **Word-wrap + pagination**: split on `\f`,
  word-wrap each line to the box width (`MAXCHARS`), then chunk into **≤2 visible lines** per
  page — so long lines (e.g. after `#`→`POKé` expansion) never run off the right edge.
  `Battle.gd` wraps its constructed messages the same way.
- `advance()`: finish typing → next page → close (emits `closed`).
- **Input is centralized in `Player._process`** via the modal dispatcher (see
  [menus.md](menus.md)): when a box/menu is open, `game.modal.handle_input()` consumes the
  frame's input; otherwise the overworld handles it. Exactly one action per press, so the
  keypress that *closes* a box can't also re-open it on the same frame (this was an infinite
  loop, since `TextBox` processes before `Player`). The box only animates the typewriter;
  `TextBox.handle_input()` advances on A.

`Main.interact(player)` checks the faced cell for an NPC (turns it to face the player) or a
`bg_event` (sign), looks up the text, and calls `textbox.show_text`. Verified by
`--texttest` (Oak single page; the Girl's 2-page text paginates and closes).

## Not yet done

- `text_asm` (scripted/conditional) text; name/number substitution beyond the defaults.
- Sound on advance; the blinking ▼ is currently static.
