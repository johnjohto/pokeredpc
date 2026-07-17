# pokeredpc v1.0.0

A native PC port of Pokémon Red (pret/pokered) in Godot 4.7 — not an emulator. The data is
extracted from the disassembly and the engine reimplemented natively.

**1.0 is here. The 1:1 recreation is complete.**

"1.0" was always defined as two things, and both closed today:

- **Audited parity**: every system in the game's engine — battle formulas, catching, EXP,
  status effects, trainer AI, encounters, every map script and hidden event, menus, the
  Pokédex, animations, audio, the overworld's movement/warp/collision rules — has been read
  line-by-line against the original disassembly and reimplemented to match, Gen-1 quirks and
  glitches included. A super-effective hit rounds like the cartridge rounds; Blaine wastes
  potions at full HP; the Leech Seed/Toxic counter glitch drains extra; AGILITY cures
  paralysis slowness.
- **The playthrough sign-off**: an automated bot first played the whole game legitimately —
  one unbroken run from NEW GAME to the HALL OF FAME, real battles, real grinding, real
  money — and then a complete human playthrough followed, filing bug waves (~60 issues)
  that were fixed batch by batch until the tracker hit zero.

The final stretch (0.9.38–0.9.43) brought the Pokémon Center's frame-real healing ceremony,
the in-game trade movie with the ball crawling the link cable, the DIPLOMA, Oak's 16-tier
Pokédex rating, boulder dust, and the title screen's Up+Select+B save clear.

Deliberately out of scope: link-cable play, Super Game Boy colors (this is DMG-green), and
raw-memory glitches like Missingno (no memory emulation).

What's next: multiplayer (v1.1) is the next conversation, and after that a fan-game creation
toolkit (v2) built on this engine.

Personal-use project; extracted assets and builds aren't distributed. Thanks for following
along.
