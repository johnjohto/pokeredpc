# pokeredpc v1.1.0

A native PC port of Pokémon Red (pret/pokered) in Godot 4.7 — not an emulator. The data is
extracted from the disassembly and the engine reimplemented natively.

**Multiplayer is here. The Cable Club works.**

Gen 1 was designed around the link cable — trading is why version exclusives exist, four
Pokémon can't evolve without it, and battling a friend was the whole endgame. So v1.1 is
the Cable Club, exactly where the cartridge put it: walk up to the receptionist in any
Pokémon Center, and instead of plugging in a cable, one of you hosts and the other types
their address on the Gen-1 naming-screen keyboard (the host's own address is shown while
they wait, and the game asks your router to open the port for you). From the moment the
link is up, everything follows the original — the save warning, the "Please wait.", the
TRADE CENTER / COLOSSEUM choice, your friend appearing across the table.

- **Trading**: pick a Pokémon, see your friend's pick, both confirm, and the full trade
  animation plays — the ball rolling down the link cable, the farewell, your friend's
  actual name on their Game Boy. Trade evolutions finally work: send a Kadabra, an
  Alakazam arrives. Nicknames and original trainers are preserved, and a dropped
  connection can never duplicate or lose a Pokémon — a trade completes on both sides or
  on neither.
- **Battling**: the full battle engine, link-style — no badge boosts, nothing at stake,
  and both players provably watch the *identical* battle: the two games simulate in
  lockstep from a shared seed, and the test suite asserts their turn-by-turn records are
  byte-for-byte the same. Your opponent appears as the rival, just like on cartridge.
- **The dupe glitch lives** — on purpose, as an easter egg. If (and only if) *both*
  players enable it, the classic cable-pull duplication works at the same moment it did
  in 1998. One-sided attempts are refused at the handshake.
- Mismatched copies (different version, or data extracted from a different pokered) are
  politely turned away with a message naming exactly what differs — under lockstep,
  silent drift would mean desyncs, so the door is strict.

All of it was gated the way 1.0 was: automated two-instance suites first (a desync soak
running seeded battles until the streams prove identical, and a "cable pull" matrix that
kills the connection at every dangerous moment), then a real remote session between two
humans — trades, trade evolutions, battles both directions, and genuine disconnects.

Known limits, documented: items can't be used in link battles yet, link MIMIC copies a
random technique, and there's no NAT traversal — it's LAN or a directly reachable address,
between two people who trust each other. Reconnecting into an interrupted session is on
the list.

What's next: the fan-game creation toolkit (v2), built on this engine — the trade record
and the lockstep contract this release shipped are its foundation.

Personal-use project; extracted assets and builds aren't distributed — your friend builds
their own copy from their own disassembly, and the handshake keeps everyone honest.
Thanks for following along.
