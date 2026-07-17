# pokeredpc

Native PC port of pret/pokered (Pokémon Red) in Godot 4.7. This glossary pins the
**port's own working vocabulary** — chiefly the release/verification process. The Pokémon
game-domain terms are pokered's own and well known; only port-specific coinages are recorded here.

## Language

### Release & verification

**Audit parity**:
The `0.9.x` bar — every system verified *in isolation* against the disassembly (the `--<flag>test`
selftest suite). Proves systems, not the game.
_Avoid_: feature-complete, done

**Sign-off run**:
The `1.0` gate — proving the game *as a whole*, not one system. Two-stage (hybrid): the automated
[[legit-play run]] must pass first, then the human playthrough.
_Avoid_: final test, QA pass

**Critical path**:
The mandatory main-quest spine the sign-off must complete: NEW GAME → the eight badges → Elite
Four → Champion → Hall of Fame → end credits.
_Avoid_: main story, happy path

**Progression gate**:
Anything that must be traversed to advance the [[critical path]] — a warp, a map-script trigger, a
puzzle (trash-can switches, Silph doors, boulder switches), an item/badge lock, or a required
battle. The [[legit-play run]] must pass through every one.
_Avoid_: blocker

**Legit-play run**:
The automated half of the sign-off — a headless, **seeded** bot that plays *on merit* (real
grinding, battles won and money earned, no injected levels or items). Its only failure modes are a
[[dead-end]], a softlock, or a crash; a single lost battle is not a failure (the bot heals, grinds,
and retries like a persistent player). Contrast the rejected *gate-traversal smoke test*.
_Avoid_: bot test, smoke test

**Play policy**:
The [[legit-play run]] bot's decision rules — party choice, move selection, and when to grind, heal,
or retry. A property of the bot, not the game; a weak policy is not a game bug.

**Dead-end**:
A state from which the [[critical path]] cannot be advanced by *any* play. The [[legit-play run]]'s
failure condition, alongside softlocks and crashes.

**Side-system checklist**:
The set of optional systems the human playthrough must exercise at least once in real context
(legendaries, all three rods, Safari Zone, Game Corner, in-game trades, Day Care, fossils, gift
Pokémon, PC storage, vending, bike, every HM field move, marts). Touch-once, not 100% completion.
