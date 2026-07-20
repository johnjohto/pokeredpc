# pokeredpc v1.2.0

A native PC port of Pokémon Red (pret/pokered) in Godot 4.7 — not an emulator.

**A Wi-Fi blip no longer ends your trade or battle.**

Since 1.1 the Cable Club has been faithful but fragile the way the real cable was: if the
connection hiccuped mid-session, the link died — battles ended with nothing at stake,
trades rolled safely back or forward, and you both walked back to the attendant. Now the
game rides it out. If the connection drops at the table, you see "Link lost — waiting for
your partner…" while your game holds the session open and your friend's game quietly
redials. When it comes back — usually in seconds — the two games compare notes and pick up
exactly where they left off: a battle continues on the same turn (the move that was in
flight is re-delivered, and the test suite proves the battle records stay byte-for-byte
identical across the outage), a trade that hadn't committed restarts at the pick screens,
and a trade caught mid-commit completes on **both** sides — the one gap 1.1 documented but
couldn't close is now closed. You can always press B to give up, and after ~2 minutes the
game gives up for you, exactly as before.

- **The dupe glitch is untouched** — it still wants its ritual power-cut (kill the game in
  the ack window and relaunch, both players opted in). A lag spike can never fork a
  Pokémon; resume reconciles honestly.
- **Victory Road works again** — a subtle timing divergence from the cartridge (the boulder
  dust animation locks input the instant a shove starts, one detail the port missed) made
  multi-tile STRENGTH pushes fail, which had quietly broken the endgame for our automated
  player. Fixed against the disassembly, and the full NEW GAME → Hall of Fame verification
  run is green again on both test seeds.
- **A playable build** — `tools/export.ps1` now produces a double-clickable
  `pokeredpc.exe` with the game data beside it, so you can play without the toolchain
  installed. (Build your own from your own extraction, as always.)
- Also faithful, it turns out: items being refused in link battles is what the cartridge
  does too (we'd listed it as a limitation — the disassembly says otherwise).

Gated like everything here: an automated injection suite that severs the connection at
every dangerous moment — mid-turn, every trade phase, the ack window, and a soak that cuts
the line every second turn of a whole battle — then a real remote session with genuine
Wi-Fi drops.

Known limits: link MIMIC still picks its copied move deterministically (the one remaining
documented divergence), and there's still no NAT traversal (LAN or direct IP). Next: the
fan-game creation toolkit (v2).

Personal-use project; assets and builds aren't distributed — your friend builds their own
copy, and the handshake keeps everyone honest. Thanks for following along.
