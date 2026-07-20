# pokeredpc v1.2.0

A native PC port of Pokémon Red (pret/pokered) in Godot 4.7 — not an emulator.

**A Wi-Fi blip no longer ends your trade or battle.**

Since 1.1, a connection hiccup killed the link session. Now the game rides it out: you see
"Link lost — waiting for your partner…" while your game holds the session open and your
friend's game quietly redials. When it comes back — usually in seconds — the two games
compare notes and pick up where they left off: a battle continues on the same turn (the
move that was in flight is re-delivered; the suite proves the battle records stay
byte-for-byte identical across the outage), an uncommitted trade restarts at the picks,
and a trade caught mid-commit completes on **both** sides — the one gap 1.1 documented but
couldn't close. B gives up any time; after ~2 minutes the game gives up for you.

- **The dupe glitch is untouched** — it still wants its ritual power-cut, both players
  opted in. A lag spike can never fork a Pokémon.
- **Victory Road works again** — a timing detail the port missed (boulder dust locks input
  the instant a shove starts) broke multi-tile STRENGTH pushes. Fixed against the
  disassembly; the NEW GAME → Hall of Fame verification is green on both seeds.
- **A playable build** — `tools/export.ps1` makes a double-clickable `pokeredpc.exe` with
  the game data beside it. (Built from your own extraction, as always.)
- Also faithful, it turns out: items refused in link battles is cartridge behavior too.

Gated as always: an injection suite severs the connection at every dangerous moment —
mid-turn, every trade phase, the ack window, a soak cutting the line every second turn —
then a real remote session with genuine Wi-Fi drops.

Known limits: link MIMIC picks its copied move deterministically; no NAT traversal. Next:
the fan-game toolkit (v2).

Personal-use project; assets and builds aren't distributed. Thanks for following along.
