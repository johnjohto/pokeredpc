# pokeredpc v1.1.0

A native PC port of Pokémon Red (pret/pokered) in Godot 4.7 — not an emulator.

**Multiplayer is here. The Cable Club works.**

Talk to the receptionist in any Pokémon Center: one of you hosts (your address is shown
while you wait, and the game asks your router to open the port), the other types it on the
Gen-1 naming keyboard. From link-up, everything follows the original — the save warning,
the "Please wait.", TRADE CENTER or COLOSSEUM, your friend across the table.

- **Trading**: pick, see your friend's pick, both confirm, and the full animation plays —
  the ball rolling down the cable, your friend's real name. Trade evolutions finally work:
  send a Kadabra, an Alakazam arrives. Nicknames and OTs are preserved, and a dropped
  connection can never duplicate or lose a Pokémon — a trade completes on both sides or
  neither.
- **Battling**: the full engine, link-style — no badge boosts, nothing at stake, and both
  players provably watch the *identical* battle: the games run in lockstep from a shared
  seed, and the test suite asserts their turn records are byte-for-byte the same. Your
  opponent appears as the rival, as on cartridge.
- **The dupe glitch lives** — as an easter egg, only if *both* players enable it.
- Mismatched copies are refused with a message naming exactly what differs.

Gated like 1.0: automated two-instance suites (a desync soak, a cable-pull matrix), then a
real remote session — trades, evolutions, battles both ways, genuine disconnects.

Known limits: no items in link battles yet, no NAT traversal (LAN or direct IP), and
reconnecting mid-session is on the list. Next: the fan-game toolkit (v2).

Personal-use project; assets and builds aren't distributed — your friend builds their own
copy, and the handshake keeps everyone honest. Thanks for following along.
