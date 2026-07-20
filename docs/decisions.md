# Architecture decision records

Newest first. Each entry: context → decision → consequences.

## ADR-016 — Link session resume: live-transport reconnect + reconcile (2026-07-20)

**Context:** v1.1 tears down any dead link — battles end stakeless, trades resolve via the phased
journal, players walk back to the attendant — which is correct but unfriendly, and it leaves
ADR-015's documented two-generals residue: an ack lost in transit at the instant of a drop can
strand the peers on opposite sides of the trade decision. Only a reconnect + reconcile
conversation can close that window (gh #13). Design conversation held 2026-07-20; six decisions.
**Decision:** (1) **Scope: transport blips only** — both game processes still alive, the socket
died (Wi-Fi drop, cable pull). A process death keeps today's teardown + journal-recovery story;
persisting battle state for relaunch-resume is out of scope. (2) **Grace window: ~120 s,
player-cancellable** — the survivor shows "Link lost — waiting for your partner…", B gives up
immediately into today's teardown; the host keeps listening on the session port, the joiner
auto-redials with backoff. (ADR-015's human/machine-paced rule doesn't apply: during an outage
there is no liveness to bind to, so this wait gets its own bound.) (3) **Resume identity: a
session token** minted by the host at link-up rides the normal identity handshake on
reconnection; a wrong or absent token takes the ordinary fresh-session path, so a stranger can
never join into a half-open session. (4) **Reconcile rules by state:** *mid-battle* — compare
last-acknowledged turn + RNG cursor + state digest from the lockstep stream: equal → continue,
one action in flight → retransmit it, digests differ → a determinism bug by definition, void
stakeless as today, loudly logged; *trade pre-commit* — restart at the pick screens (parties
re-exchanged; nothing at stake, keeps the reconcile protocol tiny); *trade commit* — exchange
journal phases: `acked`+`acked` → both apply, `acked`+`ready` → roll the ready side forward
(**the two-generals closure**), `ready`+`ready` → roll back to picks; *pre-table states*
(attendant flow, save beat, LinkMenu) — teardown as today. (5) **The dupe easter egg is
relaunch-only:** resume reconciles honestly even for opted-in sessions — the glitch keeps its
faithful power-cut ritual (kill the game in the ack window and relaunch), and a lag spike can
never fork a mon. (6) **Ships as v1.2.0** (a player-visible capability + a new protocol surface
= a feature milestone), with the milestone kept pure: ADR-015's parked faithfulness item
(link MIMIC's real pick menu; the items half of the pair turned out to be faithful already —
see the ADR-015 correction) stays parked. **The gate is the house
two-stage:** Stage 1 — a `--blipat` injection mode that resets the ENet connection *without*
killing the process, scripted across mid-battle turns, every trade phase, and the ack window,
plus a blip-soak, asserting resume + byte-identical streams and every commit-phase case ending
consistent on both saves; Stage 2 — a real remote human session with genuine Wi-Fi drops.
**Consequences:** the two-generals residue is closed for live processes — the only case a
reconcile can reach, since a relaunch already resolves correctly (and deliberately, for the
egg) via the journal; teardown remains the universal fallback wherever resume doesn't prove
itself; the wire grows a session token and a small `resume`/reconcile vocabulary but the
lockstep and journal semantics are unchanged — reconcile only *reads* them.

## ADR-015 — Lockstep implementation: mirrored sims, canonical streams, presumed-commit trades (2026-07-19)

**Context:** Building ADR-014 (gh #2–#9) forced implementation-level choices the design left open, several
of them non-obvious and one a deliberate divergence pair.
**Decision:** (1) **Mirrored simulations with canonical labels** — each peer simulates with itself as the
"player" side (as pokered's link battles do) rather than one side rendering a flipped "host view". The
asymmetric rules are neutralized exactly as the asm neutralizes them for `LINK_STATE_BATTLING` (no badge
boosts, no hidden stat-down miss, no EXP), speed ties read the shared coin canonically ("heads = the HOST
acts first"), the opponent presents as **OPP_RIVAL1** (cable_club.asm), and the lockstep oracle emits
role-canonical lines (host side first on both peers) so byte-equality still defines "in sync". (2) **The
mon record carries `maxpp` explicitly** — deriving it from the current move table refused real saves whose
PP history predates a table fix; what the save says is what travels, bounded only by Gen 1's 64 ceiling.
(3) **Trades are presumed-commit past the ack** — the journal phases `ready` (roll back) and `acked`
(written before the ack leaves; recovery rolls forward, silent trade evo included). The un-closable
residue — an ack lost in transit at the instant of a real cable pull — is the two-generals bound,
documented in engine/link.md; closing it needs the gh #13 reconnect conversation. The dupe easter egg is
implemented as a deliberate `acked`-rollback under mutual opt-in; an asymmetric opt-in refuses the whole
session. (4) **Two documented divergences** keep both sims trivially identical until a later faithfulness
pass: items are refused in link battles (the cartridge allows them; enemy-side application of every bag
item is deferred), and link MIMIC copies a deterministic random technique (a mid-turn menu pick can't
cross the wire mid-resolution). *[Correction 2026-07-20: the items half was wrong — the cartridge
refuses items in link battles too (`core.asm` BagWasSelected's `LINK_STATE_BATTLING` guard,
`ItemsCantBeUsedHereText`), so the refusal is faithful, not a divergence; the port now refuses at
menu selection with the faithful text. Only the MIMIC pick remains a documented divergence.]* (5) **Human-paced waits are liveness-bound** — only machine-paced protocol
replies keep timers, and a machine timeout actively closes the link; a friend thinking for a minute is the
game working, not a drop (the first playtest's "frequent disconnects" were a 30 s timer).
**Consequences:** the desync soak (gh #8) validates the whole construction at volume (its first battery
caught three real lockstep bugs); every divergence and the two-generals bound are documented rather than
silent; gh #13 (session resume) and the items/Mimic faithfulness pass are the recorded follow-ups.

## ADR-014 — v1.1 multiplayer is the faithful Cable Club over deterministic lockstep (2026-07-17)

**Context:** ADR-013 committed multiplayer as a v1.1 feature whose extended design conversation happens
immediately after 1.0 — it gates v2 because it pins the requirements v2's Core would otherwise guess at
(deterministic/serializable battle state, a portable mon/state model, project identity). 1.0 shipped
2026-07-17; the conversation was held the same day. The personal-use constraint frames everything: builds
and extracted assets are never distributed, so the other player has always built pokeredpc themselves
from their own `pokered/` clone.
**Decision:** (1) **Audience: trusted peers, direct connect** — you plus friends running their own
builds, over LAN or direct IP (Godot high-level multiplayer / ENet); no servers, accounts, matchmaking,
or anti-cheat. (2) **Scope: the faithful Cable Club only** — link trades and link battles through the
Pokémon Center upstairs, asm-faithful semantics including trade evolutions; no overworld presence in 1.1
(a candidate for later). (3) **Authority: deterministic lockstep**, the cartridge's own model — a shared
RNG seed at link-up, only the players' chosen actions cross the wire, both engines simulate and must
agree; a desync is by definition a determinism bug. This ships v2 §4.7's "seed + action log → reproducible
battle" contract as tested reality. (4) **Wire format: a versioned mon-record schema** with stable string
IDs (`species:…`, `move:…`) and explicit fields, translated at the link boundary — v1 internals stay
index-based; the schema is the mon record v2's Core inherits, formalized once. (5) **Handshake: strict
identity** — exact `VERSION` match plus a content hash over link-relevant extracted data (written at
extraction time); any mismatch refuses the session naming the differing part. Lockstep turns silent data
drift into an undebuggable mid-battle desync, so refusal is the only sane failure mode; this prototypes
v2's project-identity manifest. (6) **Connect UX: the Cable Club attendant is the seam** — she offers
HOST / JOIN (IP entered on the Gen-1 naming-screen keyboard); everything after link-up follows the asm.
`--host` / `--join <ip>` debug flags exist for automation. (7) **Disconnects: atomic trades with the dupe
glitch as a mutual opt-in easter egg** — a trade commits two-phase (a drop completes on both sides or
neither; a battle drop is stakeless, as on cartridge), but the classic cable-pull duplication glitch is
deliberately preserved behind an opt-in flag that is **symmetric**: advertised in the handshake and active
only when *both* peers enabled it, refused otherwise, so the two saves can never disagree about what a
trade did. (8) **The 1.1 gate is a two-stage hybrid**, rhyming with ADR-011 — Stage 1: headless bot-vs-bot
over localhost (a seeded desync soak asserting byte-identical battle event streams every turn; a scripted
trade round-trip including a trade evolution with both saves verified; drop-injection proving no dupe and
no loss, and that the easter egg fires only under mutual opt-in). Stage 2: a real remote human session —
trades, battles both directions, at least one genuine disconnect — under ADR-011's log-and-continue policy.
**Consequences:** The battle engine must be strictly deterministic on every code path (no
frame-rate-dependent RNG draws, no float drift) — an audit v2 needed anyway, now forced early with the
soak as its permanent oracle. The no-dupe default is a **documented divergence** from cartridge behavior
(like the credits table-read clamp): the dupe is a hardware save-timing accident, not authored asm, and an
accidental Wi-Fi blip forking a friend's mon is the worst outcome 1.1 could produce — hence safe by
default, glitch by mutual consent. Three v2 Core requirements are now pinned artifacts instead of open
questions: the reproducible-battle contract, the mon-record schema, and the content-hash identity. v2 work
remains gated on 1.1 shipping, not merely on this design existing.

## ADR-013 — v2 is a generic monster-RPG creation toolkit, not just a moddable port (2026-07-12)

**Context:** Beyond 1.0, the project's direction is to become **a toolkit others use to build and ship
their own fan games** — a visual map editor (Tiled-based), graphical content editors (species, trainers,
moves, …), and in-map event/script authoring, with *every system extensible and easily modifiable*. That
goal forks four ways at the foundation, each of which reshapes the whole architecture: how far to
generalize beyond Gen-1; how creators author logic; where the editors live; and how v2 relates to v1's
hard-won, asm-faithful codebase. The full design is in [v2/plan.md](v2/plan.md).
**Decision:** (1) **A generic, module-based monster-RPG engine** — battle, catching, types, formulas,
and progression are pluggable/configurable modules ("rulesets"), not hardcoded Gen-1; the engine knows
the *interfaces*, a built-in `gen1` ruleset supplies faithful implementations. (2) **Layered event
authoring** — a GUI command-list event system for the common 90%, with a *sandboxed* scripting hatch for
the rest (not raw GDScript — shared games must not run arbitrary code). (3) **A standalone editor app**
(its own `.exe`; creators never open Godot) with the **Tiled TMX format** as the native map format. (4)
**v1 becomes the flagship sample** built on the v2 engine — rebuilding faithful Kanto as a v2 project
(and the legit-play bot still beating it) is the toolkit's acceptance test. The unifying reframe:
separate the **Engine** (code) from the **Project** (a portable, shareable folder of data + maps +
events + a ruleset), joined by a shared **Core** (schema + interfaces) so the runtime and editor cannot
drift.
**Consequences:** This is the ambitious path on every axis, so the plan is explicitly **phased and
gated**. **Multiplayer is a committed v1.1 feature that lands *before* v2** (the extended design
conversation is deferred to immediately after 1.0) — and it gates the start of v2, because it sets the
requirements for the very Core v2's Phase 1 would formalize (deterministic/serializable battle state, a
portable state/save model, project identity for compatibility). So the sequence is **1.0 → v1.1
multiplayer → v2 phases** (Core/project format → ruleset seam → event VM → Studio MVP → map/event editors
→ scripting + config → second sample), each independently shippable and regression-gated by the bot + the
audits. Platforms are asymmetric: **Studio stays desktop; finished games export as widely as feasible**
(desktop/web/mobile), which is a portability budget on the runtime + scripting sandbox. Two hard
constraints fall out immediately: a **sandboxed scripting layer** must be designed up front (security of
shared games *and* web/mobile export), and the **project format is a public API** the day people build
games (version + migrate it from the start). And a legal one: v1's
extracted Nintendo assets are personal-use, so the distributable toolkit **never ships them** — the
faithful Kanto pack is delivered as the **pokered importer** (v1's `extract.py` generalized), so each
creator supplies their own `pokered/` clone and extracts locally for personal use, exactly as v1 does;
a small **CC/original placeholder pack** ships for an out-of-box start. The guardrail against becoming "a
worse Godot" is *no speculative generality* — every abstraction must be demanded by reproducing v1 or a
second sample.

## ADR-012 — The legit-play bot clears obstacles by kind, not by proof (2026-07-09)

**Context:** `_pt_walk_dungeon` plans around NPCs, because a real player cannot walk through them.
When no NPC-free path to the goal exists, *something standing on the floor* is the door. Three kinds
occur: an undefeated sight-trainer holding a corridor (it marches off its tile to intercept); an
**item ball**, which is a solid sprite — Pokémon Tower 6F's RARE CANDY (6,8) sits on the single-tile
passage into the whole southern half of the floor, so the 7F stairs are unreachable until you take it;
and a **locked card-key door** on a Silph Co floor, which is a *block*, not a sprite, laid on load by
the floor's `GateCallbackScript`. Deciding *which* object is the articulation point is a graph problem;
the bot only has "no path".
**Decision:** On a dead plan, try the kinds in order — trip the nearest reachable guard
(`_pt_trigger_guard`), take the nearest reachable item ball (`_pt_take_blocking_item`), then open the
nearest reachable card-key door (`_pt_open_blocking_door`) — each attempted at most once per walk, then
re-plan. None is proven to be the blocker; all are ranked by path length. If all are exhausted,
`_pt_report_blocked` names every standing object and every still-locked door before failing.
**Consequences:** Simple, bounded, and terminating (a beaten trainer, a taken ball and an opened door
all stop blocking, so progress is monotone). The cost is that a stuck floor may clear a bystander first
— a one-time overworld item and a `picked_items` write, or a door it did not need — before it reaches
the real blocker. That only ever happens on a leg that had no legal move left, so it buys a dead-end
where it would otherwise report one. Proving the articulation point would be strictly better and is not
worth it on the critical path. A give-up now names the things in the way, which is what actually debugs
the leg. Doors are tried last for two reasons: the check is free to rule out (it needs the CARD KEY and
a Silph Co floor, so it returns immediately everywhere else, leaving every previously-tuned floor's
behaviour untouched), and a guard standing between us and a door makes that door unreachable anyway —
so clearing guards first never wastes a re-plan on a door the walk could not have reached.

## ADR-011 — The 1.0 sign-off is a two-stage hybrid gate (2026-07-07)

**Context:** Versioning treats `0.9.x` as **audit parity** — every system verified in isolation by
the `--<flag>test` suite — and reserves `1.0.0` for a "complete playthrough sign-off", on the
principle that audits prove systems but only a full run proves the game. That sign-off was
otherwise undefined: what proves the game, who plays, what a "pass" is, and how a mid-run bug is
handled were all open. See the glossary in `CONTEXT.md`.
**Decision:** The sign-off is a **two-stage hybrid gate**. **Stage 1 — automated legit-play run:**
a headless, **seeded** bot (a new `--seed N` hook replaces `Main.gd`'s `randomize()` for
determinism) plays the critical path *on merit* — real grinding, battles won, money earned, no
injected levels or items — as a **persistent player** (on a whiteout it heals, grinds, retries). It
runs as one continuous process from NEW GAME to credits, autosaving at each town/milestone with a
progress log, so a failing leg is debugged by resuming from the last autosave. It asserts
**completability**: the only failures are a **dead-end** (the critical path is unadvanceable by any
play), a softlock, or a crash — a lost battle is never a failure. **Stage 2 — human playthrough:**
complete the critical path plus the **side-system checklist** (each optional system touched once in
real context), on a **different starter** than the auto-run for branch coverage, under a
**log-and-continue, two-tier** bug policy — blocking bugs (softlock/crash/save-corruption) stop the
run and are fixed then resumed from the last autosave; non-blocking bugs (cosmetic/text/audio/nits)
are filed and batch-fixed. Every finding is a GitHub issue. During a sign-off run, save-schema
changes are **additive-only** (JSON tolerates missing keys → defaults); a semantic change means
reload + re-verify the affected area (no migration layer — the auto-run is NEW-GAME-immune anyway).
**To tag 1.0**, on the tagged commit: the auto-run is green, the full selftest suite is green, there
are zero open blocking bugs, all non-blocking bugs are triaged (fixed or deferred with a rationale),
and the human has spot-checked the fixed areas — **no full replay**. The sign-off is tracked in one
"1.0 sign-off" GitHub issue (checklist + auto-run seed/log + human notes + bug links + the final
gate checklist); on sign-off, bump `VERSION` + `project.godot` (`application/config/version`) to
`1.0.0`, tag `v1.0.0`, update `CHANGELOG.md` + `CHANGELOG-forum.md`, and close the issue.
**Considered alternatives:** a *sole human gate* (no automated run) — rejected: a permanent
end-to-end smoke run is wanted as a cheap pre-flight before sinking hours into a human run. A
*gate-traversal smoke* (inject levels/items, force battle outcomes, assert only that gates fire) —
rejected in favour of legit-play so the run earns its way through on merit. *Making a lost battle a
failure* — rejected: it would couple the release gate to bot-skill tuning; the persistent-retry
policy asserts completability instead.
**Consequences:** Stage 1 is a substantial build — a competent **play policy** (party management,
winning Gen-1 move choice, grind/heal/retry loops), `find_path` navigation across the 223 maps, the
`--seed` determinism hook, and milestone autosave — comparable to a mid-size game system, worth its
own milestone/issue before the sign-off begins. A weak play policy is a *bot* problem, not a game
bug, and must never block 1.0 (only dead-ends/softlocks/crashes do).

## ADR-010 — Per-map script adapters behind the MapScripts seam (2026-07-03)

**Context:** Per-map behaviour had accumulated in `Main.gd` as three flat dispatch chains
(`interact` ~380 lines, `_on_player_moved` ~155, `_on_map_loaded`), the `_object_shown`
visibility match, four warp gates inside `_do_warp`, and ~24 hand-authored gimmick tables —
while `MapScripts.gd`, the seam designed for exactly this, was instantiated and never called.
Issue #22's remaining beats would have kept growing those chains.
**Decision:** `MapScripts.gd` becomes the `MapScript` base class with five hooks — `on_enter`,
`on_step(cell)`, `on_interact(front, npc)`, `on_warp(w, dest_const, dest_label)`,
`object_shown(k)` — one adapter per scripted map at `scripts/maps/<MapLabel>.gd` (1:1 with
pokered's `scripts/<Map>.asm`), discovered by naming convention, cached per label, **stateless**
(durable state stays in `story_events`; event names/save format unchanged). Adapters own their
map's triggers + gimmick-table rows; Cutscene keeps the beat coroutines; engine-generic
machinery (sight, warp fade, encounters, ticks, spin-tile data) stays in Main. `on_step` runs
**early** — before rebase/warps/sight — restoring pokered's script-runs-first frame order (the
old sight-before-gates priority was the unfaithful one). Adapters hold `main` (as pokered
scripts hold WRAM) plus the base-helper vocabulary; see
[engine/map-scripts.md](engine/map-scripts.md).
**Consequences:** one map = one module; Main's dispatchers shrink to one call per touchpoint;
remaining #22 beats land as adapters. Migration is family-by-family (gh #53), each guarded by
its `--flag` selftest, with a per-family asm check for step-priority changes. Counter-indirect
NPCs aren't passed to `on_interact` yet (generic flow still resolves them) — revisit when the
mart-like maps migrate.
*Post-migration (same day):* the sweep grew the interface to **seven hooks** — the counter
resolution moved ahead of `on_interact` (mart-like maps), and `try_push_boulder` needed
`boulder_hole` (pre-shove hole query) + `on_boulder` (switch/fall effects). Data-keyed
mechanisms (bench guys, text-id gifts, hidden events, gym guides, fishing) stay generic in
Main by design — see [engine/map-scripts.md](engine/map-scripts.md).

## ADR-009 — Battle presentation via message-queue markers + a displayed-HP mirror (2026-07-01)

**Context:** The battle narrates a turn through a **message queue** (strings + marker dicts) that
`_next_msg` walks, one item per input/tween. New Gen-1 sequences (HP-bar drain `UpdateHPBar2`,
faint slide `SlideDownFaintedMonPic`, send-out `POOF_ANIM`, level-up `PrintStatsBox`) each need to
fire at a **specific point** in that narration, and HP changes happen up front in the turn logic
(before any message shows), so the HUD can't just read `mon.hp`.
**Decision:** Extend the same queue: animation steps are marker dicts (`{"hp"}`, `{"faint"}`,
`{"intro"}`, `{"levelstats"}`) inserted where they should play; each sets `state="anim"`, runs a
tween, and calls `_next_msg` on finish. The HUD reads a per-side **`_shown_hp`** mirror that
`_set_hp` drains toward the real value via an `{"hp"}` marker (2 frames/pixel); a `_process` sync
snaps it when a mon is (re)sent-out or between actions. A **`battle.fast_hp`** flag (set for every
test via the cmdline-user-args check) skips these animations so logic tests stay fast and their
`while state == "msg"`-style loops don't stall on `"anim"`.
**Consequences:** animations compose with the existing text flow with no separate scheduler; every
in-battle HP change routes through `_set_hp` for a consistent drain. Cost: tests must advance past
`"anim"` states (or set `fast_hp`), and render tests **pose** stages (`_intro_stage`/`_faint_who`/
`_shown_hp`) for still captures. Per-move attack animations (issue #19) will reuse this marker model.

## ADR-008 — Text resolution follows script indirection (2026-07-01)

**Context:** `build_text` mapped each `TEXT_id` to its script label's **first** `text_far` string.
Any NPC/sign whose dialogue isn't a direct `text_far` — `text_asm` handlers that `PrintText` via
`ld hl, <Label>`, trainers that `TalkToTrainer <Header>`, and shared labels defined in `home/`
or `engine/` (Poké Center/Mart signs) — resolved to nothing, leaving **~550** references blank
(≈41% of all map text). Talking to those NPCs showed an empty box (e.g. the Cable Club receptionist).
**Decision:** Resolve a `TEXT_id` by following indirection: direct `text_far`, else the trainer
header's before-battle text, else the first `ld hl, <Label>` reference — scanning `scripts/`,
`home/` and `engine/` and matching exported `Label::`. `parse_text_strings` also reads `data/text/`.
**Consequences:** text ids resolved went 666 → 1036. Trainers already carried before/after text via
ADR-007, so this mainly restores **non-trainer NPC chatter and signs**. The `ld hl` heuristic picks
the first referenced text, so an event-branched NPC may show a different-state (but valid) line; the
handful of remaining blanks are pure script NPCs already covered by engine handlers (trades, prize
vendors, elevators). Run `audit_text.py` to re-check coverage after extractor changes.

## ADR-007 — Trainer sight data folded into the map JSON (2026-06-30)

**Context:** A trainer's view range and before/end/after-battle text live in the per-map
**script** (`scripts/<Map>.asm` `trainer` headers), separate from the `object_event` it belongs
to (`data/maps/objects/<Map>.asm`). The engine only consumes the extracted map JSON.
**Decision:** At extract time, parse the ordered `trainer` headers and **zip** them onto the
trainer `object_event`s (declaration order — pokered numbers trainer sprites consecutively), so
each trainer carries `sight` + resolved `battle_text`/`end_text`/`after_text` in one record.
Detection mirrors `trainer_sight.asm` (lined up, in front, within range, **no** obstacle check);
defeat is keyed by the trainer's **home** cell since the trainer moves during the walk-up.
**Consequences:** The engine needs no separate trainer-header asset and no asm at runtime; all
trainer data is in the map JSON. Couples to pokered's convention that trainer object_events are
consecutive. The `!` indicator reuses the extracted `shock` emote (`emote_shock.png`).

> Correction (2026-07-03, gh #55): headers bind to consecutive **absolute sprite indices**
> starting at `def_trainers N`, not to trainer objects in filtered order. Gyms use
> `def_trainers 2` because the leader (sprite 1) has **no header** — leaders are talk-only;
> the filtered zip had been giving every gym leader the first trainer's sight range and battle
> text. Static-encounter mons (Voltorbs, legendaries) whose headers point at species objects
> get nothing attached (they engage on interact), reported by the extractor as `!` warnings.

## ADR-006 — Tall-grass transparency via shader, not a baked asset (2026-06-29)

**Context:** The grass leg-overlay drew the opaque grass tile, hiding legs under a solid
block. GB shows the sprite behind the blades (BG colors 1-3) but in front of the gaps (color
0). **Decision:** Apply a tiny `canvas_item` shader to the overlay sprites that discards the
grass tile's lightest shade, instead of extracting a separate transparent grass asset.
**Consequences:** No new assets; works for any tileset's grass tile automatically; the rule
("lightest shade = gap") lives in one place. Couples to the GB green palette in `extract.py`.

## ADR-005 — Overworld tile effects driven by extracted data (2026-06-29)

**Context:** Ledges and tall grass are tile-property mechanics in pokered (`LedgeTiles`,
the tileset `grass_tile`). **Decision:** Extract those tables into the tileset JSON and have
the engine apply them generically, rather than hardcoding tile ids in GDScript.
**Consequences:** Mechanics work across every applicable map/tileset from data; adding a new
effect = extract a table + a small engine rule. See `engine/ledges-and-grass.md`.

## ADR-004 — Connections as a multi-map "world" + rebase (2026-06-28)

**Context:** Maps connect seamlessly (routes ↔ towns); pokered streams a 3-block border
strip and switches maps at a threshold. **Decision:** Load the active map plus its neighbors
into a `placed[]` "world" (each at a block offset, own tileset + collision), render/collide
across the seam, and **rebase** the active map when the player steps onto a neighbor.
**Consequences:** Simple and seamless (camera-follow hides the rebase); neighbors are drawn
in full rather than as a strip (fine — drawn once per load). See `engine/connections.md`.

> Note: collision sampling was corrected from top-left to **bottom-left** of each cell
> mid-project (see `engine/collision.md` history) — a bugfix, not an ADR.

## ADR-003 — Custom `_draw()` instead of TileMap (2026-06-28)

**Context:** Need to render block-based maps; authoring scenes by hand (no editor GUI).
**Decision:** Render the overworld with a custom `Node2D._draw()` blitting 8×8 tile regions.
**Consequences:** Full control, text-authorable, trivial to map pokered's block/tile model.
May revisit `TileMapLayer` if maps get large/animated or need built-in Y-sort.

## ADR-002 — Godot 4.7, portable binary (2026-06-28)

**Context:** Need a 2D engine that exports a native Windows `.exe` with minimal toolchain
friction; user had no C compiler but did have a 2D-friendly path available.
**Decision:** Godot 4.7, GDScript. Engine binary kept **portable** in `tools/godot/` rather
than installed system-wide.
**Consequences:** No system install; self-contained repo. CLI/headless via the `_console`
build. Export to native `.exe` later via Godot export templates.

## ADR-001 — Data-driven reimplementation, not emulation or asm→C (2026-06-28)

**Context:** "Port pokered to PC." Options: (a) build ROM + emulator [rejected: user wants a
real native port], (b) static recompile asm→C, (c) reimplement the engine on extracted data.
**Decision:** (c) — extract pokered's data to PNG+JSON, reimplement the engine natively.
**Consequences:** Clean, modifiable, genuinely-native result; most *content* comes for free
via extraction. Engine logic must be hand-written against the disassembly as spec. Avoids
(b)'s unmaintainable blob that would still need PPU/APU/timing emulation. Larger up-front
engine effort, but incremental and finishable.

> Legal note: the disassembly is code, but a playable result needs Nintendo's copyrighted
> assets. Personal use only; do not distribute extracted assets or builds.
