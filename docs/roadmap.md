# Roadmap & status

**Living document** — update the table when a milestone lands; add sub-tasks as discovered.

**After 1.0 (direction):** **v1.1 = multiplayer** — the extended design conversation was **held
2026-07-17** and its eight decisions are pinned in **ADR-014**: the faithful **Cable Club only**
(link trades + link battles, trade evolutions included), trusted peers over direct connect,
**deterministic lockstep**, a versioned **mon record** wire schema, a strict version+content-hash
**link identity** handshake, the attendant as the HOST/JOIN seam, atomic trades (the dupe glitch as
a mutual opt-in easter egg), and an ADR-011-style **two-stage 1.1 gate** (bot-vs-bot desync soak →
real remote human session). **v2** is the fan-game creation toolkit (standalone Studio editor +
generic engine + shareable projects) — see [v2/plan.md](v2/plan.md) and ADR-013. Sequence:
**1.0 → v1.1 multiplayer → v2**. v2 work stays gated on 1.1 *shipping*, not just on the design.

**Post-v2 possibility (deferred; not current scope):** once Studio v2 and its genericity sample
have shipped, use faithful Kanto as the basis for an optional **modernized Kanto showcase**. The
faithful project remains the default reference build and regression oracle; the modernized build is
a separate project/profile on the **same Engine + Core**, never an engine fork. Its purpose would be
to demonstrate reusable Studio capabilities such as scalable presentation, accessibility and input
options, richer battle/overworld effects, and modern save conveniences. See
[v2/plan.md](v2/plan.md) §9.

**Versioning:** SemVer where **`0.9.x` = full audited parity** (every system verified against the
disassembly) and **`1.0.0` additionally requires a complete playthrough sign-off** — audits prove
systems in isolation; only a full run proves the game — a **two-stage hybrid gate** (an automated
seeded legit-play run → the human playthrough; see [decisions.md](decisions.md) ADR-011). (MINOR = content/feature milestones,
PATCH = fixes/polish). The version lives in `VERSION` + `project.godot`
(`application/config/version`, shown on the title screen) and is git-tagged `vX.Y.Z`; see
`CHANGELOG.md`. **Current: `1.0.0` — SHIPPED 2026-07-17.** The ADR-011 two-stage gate is closed:
Stage 1 (the seeded legit-play bot, NEW GAME → HALL OF FAME, seeds 1+2 GREEN) and Stage 2 (the
complete human playthrough, signed off after ~60 fixed playtest issues and the full audit
campaigns gh #19–#22/#176/#185). Every engine system maps to a completed audit; the tracker is
at zero open bugs. **v1.1.0 — SHIPPED 2026-07-20**: the faithful Cable Club (link trades +
lockstep link battles) built and gated in two days — Stage 1 (the automated `linktest` /
`linksoak` / `linkdrop` suites, byte-identical lockstep streams across real instances) and
Stage 2 (a real remote human session, 2026-07-19: trades incl. trade evolutions, battles
both directions, genuine disconnects) both closed. Remaining multiplayer follow-ups: gh #13
(session resume — **SHIPPED as v1.2.0, 2026-07-20**: ADR-016 implemented in full — the
lost-state transport (host listens, joiner redials, ~120 s player-cancellable grace, session
token), the battle reconcile (turn+cursor+digest reports carrying the in-flight action), and
the trade journal-phase reconcile whose max-phase rule **closed the two-generals residue**;
the dupe egg stays relaunch-only. The two-stage gate closed same-day: Stage 1
(`tools/linkblip.py`'s `--blipat`/`--blipevery` matrix, ALL GREEN twice consecutively with
`linktest`/`linkdrop`/`linksoak` still green) and Stage 2 (a real human session with genuine
Wi-Fi drops, signed off 2026-07-20). v1.2.0 also carries the gh #28/#29/#30 endgame fixes
and the `tools/export.ps1` playable Windows build),
and the last mile of gh #12 (cross-platform, ready-for-human), whose automatable half closed
2026-07-20: the engine build joined link identity (a differing Godot build refuses naming both
builds), the toolchain runs per-OS (`POKEREDPC_GODOT`, per-OS user dirs, Linux/macOS setup in
build-and-run.md), and the dispatchable **`determinism` workflow** built the project from
scratch on Linux + macOS GitHub runners — both produced battle streams **byte-identical to the
Windows baseline** (all four `--battledettest` md5s equal) with `linktest.py` + `linksoak.py`
ALL GREEN on each; what remains is one live two-machine Windows↔Linux session
(ready-for-human). **Next: v2** (the fan-game toolkit, ADR-013), **kicked off
2026-07-20**: the build-out is tracked as **gh #14 (epic)** with phase issues **#15–#21** — Core &
project format → ruleset seam + `gen1` → Event VM → Studio MVP → map/event editors → sandboxed
scripting + config UI → packaging + the second sample, each phase gated by the bot + the audits +
the determinism suites (see [v2/plan.md](v2/plan.md) §7). **Phase 1's design is pinned
(ADR-017, 2026-07-20)**: JSON + JSON Schema in canonical form, hybrid per-record granularity, the
reserved `custom` bag, format-speaks-IDs with the loader resolving, interim map JSON until the
Phase-5 TMX bridge, the extractor *emitting* the project (the importer born, not a converter),
and `format: 1` + linear migrations. Sub-issues **gh #22–#25** (schemas/Core → manifest+identity
→ extractor emission → runtime loading, which carries the phase gate). **Phase 1 closed
2026-07-20** (all four sub-issues landed; component evidence + the gh #27/#28/#29 gate-run
fixes below). **Phase 2's design is pinned (ADR-018, 2026-07-20)**: five Core interfaces
(Battle = `state + actions → ordered event stream`, Types, Formulas, Catch, Progression) with
a registry resolving the manifest's `ruleset` field; the Gen-1 trainer AI stays inside gen1's
battle module; the formula layer is interface + **native** gen1 (asm-faithful under the md5
oracle) with the integer-exact expression evaluator landing *beside* it, proven by an
equivalence sweep; config-first knobs are **only what is already data** (`data/ruleset.json`,
additive under `format: 1`); extraction is strangler-fig with `--battledettest` between every
move. Sub-issues **gh #31–#35** (interfaces+registry → types+formulas → battle+link →
catch/progression/config → expression evaluator, which carries the phase gate).
**PHASE 2 COMPLETE — gh #16 closed 2026-07-20.** The last piece, **gh #35**: `FormulaExpr`
(Core) — the integer-exact expression evaluator (named variables, operators with int/float
promotion, comparisons + and/or, min/max/floor/ceil/sqrt/int/abs/if) — and `Gen1ExprFormulas`,
the alternate provider authoring stat_calc / the growth curves / damage_core (its /4
byte-overflow branch via if()) as expressions, proven by `--exprtest`'s **1,264-vector
equivalence sweep** against the native kernels (every value equal; never on gen1's hot path).
**The phase gate:** `--playthrough --seed 1` and `--seed 2` each ran NEW GAME → **HALL OF
FAME** in one unbroken process — all 21 checkpoints in order, `validate_gate.py` → **GATE
GREEN** on both (Champion at L70/L73) — *the bot beats the game through the seam*; the three
audits report 0 findings; all four `--battledettest` md5s **byte-identical to the pre-phase
baseline at every step and at the end**; `linktest`/`linksoak`/`linkdrop` ALL GREEN (a
`linkdrop` red herring traced to stale test-slot journals — gh #36, fixed 2026-07-21: the
suites' scenario slots now self-isolate); and the cross-OS
`determinism` workflow: Linux + macOS both reproduce the four md5s byte-for-byte with
`linksoak` 8/8 in sync (one macOS-runner `linktest` colosseum failure **bisected to
pre-Phase-2 code** — environmental, gh #37; gh #38 tracked a once-seen silent surge-stage
wedge in the bot — closed 2026-07-21: `--playthrough` now runs a progress watchdog that fails
loudly on a frozen run, proven on a full seed-1 GATE GREEN). Kanto's mechanics are now a plug-in: the engine core knows five
interfaces, `gen1` implements them asm-faithfully, and the config knobs are live data.
**Next: Phase 3 — the Event VM (gh #17). Phase 3's design is pinned (ADR-019, 2026-07-21)**:
three tiers (story beats + **all** event-shaped data-keyed mechanisms become authored events —
the design conversation widened this beyond story-path-only; ceremonies stay native, invoked by
commands); per-record `data/events/<id>.json` with nested-block branching; FormulaExpr as the
one condition language; triggers declared by the event record (map files stay geometry-only;
`visible_when` is a query, not a VM run; `(map, kind, cell)`-indexed dispatch); a coroutine VM,
one event at a time, flags + a saved vars store, event names byte-exact, events save-atomic;
commands only on a beat's demand; the extractor byte-copies authored events into the project;
strangler-fig with a tracer bullet. Sub-issues **gh #39–#43** (Core schemas + VM + dispatcher +
tracer → adapter waves by mechanism family → Cutscene beats by questline → extractor emission +
event lints → the phase gate).
**Landed: gh #39** (2026-07-21): **the Event VM exists and the tracer bullet is through it** —
`core/schemas/event.schema.json` (trigger + nested-block command grammar as anyOf branches,
recursion via `$defs`; `data/events/*.json` joins the format-1 layout, additive), `EventVM`
(load-time compilation: unknown trigger kinds/commands and unparseable conditions refuse at
BOOT naming the record; FormulaExpr is the condition language, bare identifiers reading story
flags + the new saved `event_vars` store), and the generic `EventMapScript` adapter that
`map_script()` serves for event-carrying maps — Main's eight hook touchpoints unchanged, so
the map-scripts.md ordering rules hold by construction. The tracer: **BluesHouse.gd is
deleted**; Daisy's TOWN MAP beat + both `visible` toggles are authored records in
`game/events/`, byte-copied into the project by the extractor (identity: **15 parts** now).
Gate: the new `--eventtest` ALL GREEN (boot refusals, the gift flow incl. the full-bag abort,
the `visible` query), `--blueshousetest`/`--townmaptest`/`--selftest` green through the
generic adapter, `--schematest` grew event fixtures (valid + `broken_bad_command`),
`--validate` 0 errors (1284 files, 3 event ids), double extraction byte-identical, and all
four `--battledettest` md5s **byte-identical to the Phase-2 baseline** (f426d037 / bd9ec91d /
36c598d7 / 25fcd316 — but see gh #44: on the wave-B machine the same commit reproduces
018610cf / bd9ec91d / 86180e61 / 25fcd316, stable and replay-identical; wave B gates against
that locally reproduced baseline).
**Wave B COMPLETE (gh #40, closed 2026-07-21)** — the adapter migration, ten family waves
(**all 98 adapter files deleted; `scripts/maps/` is empty — the whole overworld is authored
events**). B10 was OaksLab, the last one (same session as the gh #45 fix, which unblocked it):
15 records — the two row-6 step regions (don't-go-away / the rival challenge), the three
starter-ball interacts (`choose_starter` via the `@npc` beat arg), Oak's full OaksLabOak1Text
branch tree (parcel → dex rating → the one-time 5-ball gift → the story lines), the rival's
lines, and seven visibles incl. the untaken-ball rule via the new
`player_starter_<id>`/`rival_starter_<id>` condition identifiers; `oak_dex_rating` +
`oak_give_balls` moved into Cutscene (the award_diploma precedent); the harnesses' _oak_text
dependency became Main._oak_line_preview. Gate: `--eventtest` ALL GREEN, `--validate` 0 errors
(275 events, semantics pass), `--parceltest` green, `--oaktest` completes END TO END windowed
(its rival-challenge hang fell to the gh #45 wipe-gap fix), the four `--battledettest` md5s
unchanged, double extraction byte-identical (1557 files), and a fresh `--playthrough --seed 1`
NEW GAME → HALL OF FAME **GATE GREEN** through the event-driven lab.
The waves as landed: nine family waves first — the trigger grammar grew `enter` / `step`
((map, cell)-indexed, `when` gates, non-consuming pokes, regions) / `battle_end` / front-cell
+ facing interacts, and the command library grew exactly what each family demanded
(`set_last_map`, `mount_bike`/`set_force_bike`, `beat` — the strangler-fig call into a native
Cutscene beat, validated at boot — `notice` vs `say` (the non-blocking one-shot vs the
dialogue page; a blocking say in a guard record held `cutscene_active` and swallowed the next
trigger — caught by three suites), `take_item`, `bounce_back`/`step_back_down`/`walk_player`,
`set_block`, `vending`, `fall_hole`, `elevator_retarget`/`elevator_panel`; conditions grew
`item_<id>`/`badge_<name>`/`badge_count`/`force_bike`). Migrated so far: **B1** the LAST_MAP
connectors + Cycling Road (10 maps); **B2** the interact→beat forwarders (23 maps: aides, rod
gurus, gift balls, Daycare, BikeShop + FanClub, prize/vending counters, VermilionDock's
departure, Tower 7F + Fuji's house…); **B3** the guards (the four Saffron thirsty gates FULLY
authored — the native mechanism is deleted — both Cycling gate houses, Route22Gate's gh #87
re-pick, Route23's seven badge checkpoints, ViridianCity, CinnabarIsland); **B4** Silph Co
(all 11 floors: per-door card-key records + the story beats); **B5** the Mansion switch doors
+ 3F holes, Cinnabar Gym's quiz gates, and the three elevators (as VM ceremony commands). Waves B6–B8 (2026-07-21, same session): the E4 rooms + Indigo lobby (`defeated_<x>_<y>`
conditions resolved against the record's map, `block_cell`/`unblock_cell`, `trainer_battle`
for LANCE's coordinate trigger, `reset_elite4`, and the **`rerun_enter` battle_end field** —
pokered's EndTrainerBattle re-running the load callback as a declarative trigger, which also
carries the Rocket Hideout guard doors); the boulder/hole family (the `boulder_hole`/`boulder`
trigger kinds + `boulder_fall`, Seafoam B1–B4F with the currents as `walk_forward` runs,
Victory Road 1F–3F); and the story/city wave (PalletTown, Pewter's drags, Cerulean incl. the
TM28 rocket, Vermilion's sailor, Saffron's occupation visibles enumerated per object, Route22's
two rival battles, Tower 2F/6F, S.S. Anne's deck, Bill's house incl. the separator PC,
Museum 1F via the new `player_x`/`player_y` conditions, Celadon Mansion 3F's diploma —
`award_diploma` moved into Cutscene — Viridian Mart, Rocket Hideout B1F/B4F; beats that read
deleted adapters' consts now carry their own data). The
per-wave gate held throughout: family `--flag` suites green, `--eventtest` grown per wave
(16 checks), audits at zero, `--validate` 0 errors, double extraction byte-identical, the four
`--battledettest` md5s never moved. Fallout tracked honestly: gh #44 (the md5 baseline
discrepancy above) and gh #45 (pre-existing test drift found by baselining every failure
against HEAD: fishtest/towertest/snorlaxtest/crivaltest crash on a 'species' key, flytest
hangs headless, oaktest/diplomatest hang, route22test's 400-frame budget is marginal,
parceltest calls an `_oak_text()` that no adapter ever had, and exitwarptest + hideouttest
never awaited `_do_warp` — those two now fixed with the documented `battle.fast_hp` idiom,
which also revived the only elevator gate; gymtest's gh #109 leg, surgetest's post-puzzle
section, and mtmoontest's `party_shift` battle wedge joined the list, all byte-identical on
HEAD — and the whole 'species'/party_shift/md5 family looks like ONE battle-data-shape drift
worth chasing together). Wave B9 (2026-07-21, same session) took the last mechanism maps:
the `warp` trigger kind (SafariZoneGate, with `@warp_dest_label`/`@warp_index0` beat args +
the `in_safari` condition), `at` interact cells (the player's own cell — slot seats),
`set_var` (the saved vars store's first use: Tower 5F's purified-zone re-arm, with four
complement-region leave records), `set_npc_text` (the Mt. Moon nerd's map-script lines),
`show_object`/`hide_object`, `lucky_slot`/`play_slots` (GameCorner; the machine stays a
native modal), `club_enter`/`club_leave` (the Cable Club room pair's doormat rows), and
`trash_reset`/`trash_can` (Vermilion Gym; the random switch pair moved to Main as transient
RAM-like state, the `--surgetest` harness rewired). A real VM bug was caught by
`--fossilguardtest`: an UNAWAITED async native inside run() (trainer_battle, fall_hole) let
the wrapper's cutscene_active restore trample the beat's own flag on the same frame — both
are awaited now. (OaksLab.gd — then the last remaining adapter — landed as wave B10 above,
closing gh #40.) **Wave D (gh #42) closed 2026-07-21**: `--validate` grew the event-semantics
pass (every object a trigger/command names must exist on the record's map; every
cell/front/at/region in bounds — the real project's 260 records verify clean, an independent
cross-check of the whole migration), `--schematest` grew two broken-event fixtures (12/12),
and `audit_chokepoints` gates on the nine EVENT_BACKED doors (a record must name both the
map and the object; a hidden record fails the audit loud — proven by a negative test). (Both
of gh #40's then-remaining items — OaksLab and the wave-E gate — closed later the same day;
see the wave-B10 and wave-E entries.)
**Wave E probing (2026-07-21, same session):** four full seed-1 attempts against the fully
event-driven build. The migration held everywhere the bot went — a checkpoint-resume chain
ran erika → blaine → three E4 gauntlet loops (the lobby-reset/LANCE-door/Champion records
under real fire) → **beat the CHAMPION**, and `--elite4stage` completes the Hall of Fame end
to end. Three latent bot-driver gaps fell out and are fixed (all reproduce on the gh #39
commit): the BATTLE STYLE SHIFT prompt was never handled (the fallback pressed A into
party_shift forever — the mtmoontest wedge), THE END's held credits screen was never pressed
(the run died at HallOfFame (4,2) with the game beaten), and the catch loop could force a new
encounter over an unsettled battle — `battle.start()` reuses the battle object, so the
half-done ceremony smeared onto the new enemy and caught mons landed in the party as the NEXT
encounter's species (very likely the root of gh #45's 'species'-crash family; the bot now
guards + retries instead of corrupting). **The "ceremony race" is root-caused and fixed
(2026-07-21, gh #45):** it was never a queue race — `Main.start_battle` (and the
trainer/safari variants) set `modal = battle` but ran `battle.start()` only after the awaited
battle wipe, so through that multi-frame gap every reader of `battle.*` saw the PREVIOUS
battle's terminal state. The hunt evaluated the enemy one battle behind (catching random mons,
KO'ing real growlithes — the tell: a try that read "clefairy" on Route 7), stale `caught=true`
broke `_pt_catch` instantly on the next encounter and left it undriven at its menu (the
"never settled" wedge verbatim), and harnesses reading `enemy_mon` right after starting an
encounter crashed on an empty dict's 'species'. The fix splits the starters into a synchronous
`prime*()` (full state install, atomic with `modal = battle`, BEFORE the wipe) + a
`begin_*intro()` after it; the battle's message pump is also generation-checked now (a stale
tween/coroutine continuation drops loudly — `[qrace]` — instead of pumping a queue it never
belonged to; optiontest caught a real one). The whole gh #45 red family went green on the fix:
fishtest/towertest/snorlaxtest/crivaltest (the 'species' crashes), mtmoontest, gymtest's
gh #109 leg, surgetest's post-puzzle section — with all four `--battledettest` md5s
byte-identical and `--erikastage` catching the FIRST growlithe in 3/3 runs. (oaktest /
diplomatest / flytest headless hangs are the separate frame_post_draw screenshot class —
wipetest/moveanimtest hang headless the same way on HEAD and pass windowed — and
route22test's budget stays marginal; those legs remain open on gh #45.)
**The wave-E two-seed gate is GREEN (2026-07-21, same session, on the fix commit):**
`--playthrough --seed 1` and `--seed 2` each ran NEW GAME → **HALL OF FAME** in one unbroken
process on the fully event-driven build (~21/22 min), `validate_gate.py` → **GATE GREEN** on
both — all 21 checkpoints in order, zero anomaly lines (no `[qrace]` drops, no guard trips,
no watchdog). Same-commit battery: the four `--battledettest` md5s byte-identical,
`--validate=project` 0 errors (1541 files, 260 event records), `linktest` ALL GREEN /
`linksoak` 8/8 / `linkdrop` ALL GREEN, the three audits at zero (the nine EVENT_BACKED doors
9/9); the cross-OS `determinism` workflow ran green on the commit — Linux fully green, macOS
reproducing all four md5s byte-for-byte with `linksoak` 8/8 (its linktest 1/0-events flake
recurred — gh #37, environmental). gh #40 then closed with OaksLab (wave B10 above).
**Next: wave C (gh #41)** — dissolving Cutscene's story beats into authored events by
questline — is all that stands between here and the gh #17 Phase-3 close (gh #42 and #43 are
done; the strangler-fig `beat` seam is exactly where wave C picks up).
**Wave C questline 1 (opening/Oak) COMPLETE (2026-07-21, same session, four gated
increments):** every opening story beat is deleted from Cutscene and authored —
oak_dont_go_away (the first dissolution; `face_object` arrives), the 5-ball gift
(`give_item` count), rival_challenge (the choreography set: `face_player`/`play_song`/
`wait`/`walk_object_to` with player-relative targets/`class_battle` with per-starter
branches + `no_blackout`/`heal_party`, and the `battle_won` condition), choose_starter +
rival_takes_starter (each ball record fully static: `ask`/`pic`/`show_dex_entry`/
`set_starter`/`give_mon` + the counterpart grab), and finally oak_intercept + lab_intro as
ONE cross-map record (`show_text`/`close_text` held text, `emote`'s 60-frame hold,
`walk_object`/`walk_player` counts, `walk_together_to`, `warp_to` — and the wave-D lint
learned that a record's command stream crosses maps exactly at `warp_to`, walking objects
against a current-map context). `oak_dex_rating` stays as the one ceremony invoker (ADR-019
§1). Per-increment gates held: `--eventtest` grew wave-C checks (19 total), `--schematest`,
`--rivallosstest`/`--starterballtest` (both now drive the records' real triggers),
`--oaktest` end to end windowed after every increment, `--validate` 0 errors, the four md5s
never moved — and the finale: a fresh `--playthrough --seed 1` NEW GAME → **HALL OF FAME**,
`validate_gate.py` → **GATE GREEN**, through the fully authored opening.
**Questline 2 (parcel/dex) COMPLETE (same session):** the whole errand authored — the mart
call-over/counter-walk/hand-over, and the delivery + full Pokédex receipt (the rival's
teleport re-entry via the one new command `place_object`, the handout, the taunt, the
walk-out) inline in Oak's interact record; Cutscene's errand section is empty. Gate:
`--parceltest` fully green through the authored errand, the suites green, md5s unchanged,
and another fresh seed-1 **GATE GREEN** through both authored questlines (an E4 loss +
lobby reset + retry exercised en route).
**Questline 3 (Bill / S.S. Anne) COMPLETE (same session):** bill_intro / bill_separator /
bill_ticket / ss_anne_captain / ss_anne_rival dissolved — `give_item`'s full-bag abort IS
pokered's GiveItem .BagFull re-offer (the gh #174 billtest legs ride it unchanged), and the
gh #117 rival-exit choreography authored on the existing `player_x` condition; two trivial
vocabulary additions (`face_object` dir "player", `play_map_music`); board_ss_anne +
ss_anne_departs stay native (ADR-019 §1). `--billtest`/`--ssannetest` fully green, md5s
unchanged, and a third fresh seed-1 **GATE GREEN**. The command library is converging hard:
questlines needed 20 → 1 → 2 new commands.
**Questline 4 (gyms) COMPLETE (same session):** the eight leaders' scripts (one parameterized
beat over `_GYM_LEADERS`) dissolved into eight per-leader interact records — pre text →
`class_battle` → the sound_level_up badge quirk → badge_get → the BEAT_ flag → badge_info →
Brock's tm_get → the TM → tm_received/tm_info, post line once beaten; `give_item`'s full-bag
abort IS the Gen-1 TM forfeit (gh #174: badge stands, no re-offer). Two new commands as scoped
(`give_badge`, `defeat_gym_trainers` = the gh #109 SetEvents, leader included); `_GYM_LEADERS`
trimmed to the `{class: party}` wGymLeaderNo identity table (PlayBattleMusic's gym-leader theme
still keys off `is_gym_leader_battle`), and Main's interact special-case is gone — the whole
`gym_leader_battle`/`_fmt`/`_mark_gym_trainers_defeated` machinery left Cutscene. Gate:
`--eventtest` 22 checks ALL GREEN, `--gymtest` all seven gyms end to end through the records
(re-talk lines, gh #109, Giovanni party 3), `--surgetest` (Vermilion), `--validate` 0 errors
(283 records), double extraction byte-identical, md5s unchanged, and a fourth fresh seed-1
NEW GAME → HALL OF FAME **GATE GREEN** (Champion at L71). Command-library convergence:
20 → 1 → 2 → 2.
**Questline 5 (Silph/Rocket) COMPLETE (same session):** the seven hideout/Silph beats
dissolved — the 7F rival (both triggers; the talk-up drops the approach walk the retired beat
always clamped to zero; parties keyed by the RIVAL's starter; the y-keyed exit), the Lapras
gift (the full-party box branch via the new `party_count` condition, gh #157), the 9F nurse's
white-flash heal, Giovanni #2 (flag → parting line → the fade-black `refresh_objects` rocket
exodus, gh #158), the president's MASTER BALL, hideout Giovanni (→ the SILPH SCOPE ball), and
the lift-key drop (ball only after the text). New vocabulary: `fade_out`/`fade_in`
(black|white = the two home/fade.asm pairs), `refresh_objects`, `party_count`;
project-format.md's condition list synced to `EventVM._ident_value`. One accepted delta: the
retired empty-rival_starter counterpart fallback (unreachable in any real save) is not
reproduced. Gate: `--eventtest` 26 checks, `--silphtest`/`--hideouttest`/`--rockettest`/
`--cardkeytest` green, `--validate` 0 errors, double extraction byte-identical, md5s
unchanged, `--silphstage --seed 1` PASS, and a fifth fresh seed-1 NEW GAME → HALL OF FAME
**GATE GREEN** (Champion at L74). Convergence: 20 → 1 → 2 → 2 → 3.
**Questline 6 (gifts/fossils/museum) COMPLETE (2026-07-22, same session):** seven beats
authored — the Eevee ball, both Dojo Hitmon prizes, the MAGIKARP salesman (MONEY_BOX up before
the pitch; give before the ¥500 leaves), both Mt. Moon fossils, the museum OLD AMBER, and the
Museum1F receptionist's ¥50 ticket + back-way amber chat. `revive_fossil` stays native (the
bag-computed picker — this questline's ADR-019 §1 ceremony invoker, the oak_dex_rating
precedent); the static legendaries stay engine mechanism (object-data-keyed like item balls —
the scoping call is noted on gh #41). New vocabulary: `offer_nickname`,
`show_money`/`hide_money`/`take_money`, and the `money`/`box_count` conditions; `give_mon`
gained `_receive_mon`'s both-full refusal + abort (pokered's GivePokemon failure — now also
capping the Lapras record, pokered-faithful). Gate: `--eventtest` 30 checks,
`--gifttest`/`--fossiltest`/`--museumtest`/`--moneyboxtest`/`--legendtest` green, `--validate`
0 errors, double extraction byte-identical, md5s unchanged, and a sixth fresh seed-1 NEW GAME →
HALL OF FAME **GATE GREEN** (Champion at L74; a first attempt wedged in Victory Road under a
zombie test engine's load — the known gh #30/#38 class — and the clean rerun went straight
through). Convergence: 20 → 1 → 2 → 2 → 3 → 4.
**Questline 7 (endgame) COMPLETE (same session):** champion_entrance / champion_battle /
champions_room_oak dissolved into the champions_room_battle/_entrance records — the reversed
RLE march, OPP_RIVAL3 by the rival's starter, BEAT_CHAMPION before the two gh #179 laments,
Oak's full arrival choreography (the congrats naming the player's starter authored as three
static branches), and the walk onto the door — ending in `beat: hall_of_fame` (the credits +
League-reset ceremony stays native, ADR-019 §1). **Zero new commands** — the library needed
nothing. Gate: `--eventtest` 30 checks, `--champwalktest`/`--e4test`/`--elitetest`/`--hoftest`
green (elitetest's output byte-identical to HEAD), md5s unchanged, double extraction
byte-identical, and a seventh fresh seed-1 NEW GAME → HALL OF FAME **GATE GREEN** through the
authored champion chain (Champion at L71). Convergence: 20 → 1 → 2 → 2 → 3 → 4 → 0.
**The mop-up questline COMPLETE (2026-07-22, same session) — WAVE C IS DONE (gh #41).**
21 beats dissolved in one wave: the Tower arc (the MAROWAK ghost via the new `wild_battle`
command — SILPH SCOPE gate, unveil, the win-or-doll-escape rule; Fuji's rescue + the POKé
FLUTE; the purified zone; the 2F rival's two L-path exits), the Cerulean and both Route 22
rival ambushes, the Pewter escort drags (the new `walk_both_to` over `Cutscene.walk_both`),
viridian_oldman_block, and the gift-item NPCs (HM02/HM03/HM04 incl. the GOLD TEETH trade,
COIN CASE, BIKE VOUCHER → BICYCLE, the three rods, the Game Corner coin clerk + gift via
`give_coins` + the `coins` condition). Staying native as ADR-019 §1 ceremonies:
hall_of_fame, oak_dex_rating, revive_fossil, award_diploma, oldman_demo, daycare_man,
prize_vendor, safari_gate/safari_game_over, board_ss_anne/ss_anne_departs, the two link
tables, and the computed-count oaks_aide pair. Vocabulary close: 3 commands + 2 conditions
(convergence 20 → 1 → 2 → 2 → 3 → 4 → 0 → 3). The boot refusal caught an over-cut deletion
of the trainer-engagement keeper block before anything ran (restored byte-identical). Gate:
`--eventtest` 33 checks, the nine affected suites green, `--validate` 0 errors, double
extraction byte-identical, md5s unchanged, audits at zero (9/9 event-backed doors), and an
eighth fresh seed-1 NEW GAME → HALL OF FAME **GATE GREEN** on the fully dissolved build
(Champion at L67). Every story beat in the game is now an authored event record; Cutscene.gd
holds only engine ceremonies and primitives.
**PHASE 3 COMPLETE — gh #17 closed 2026-07-22.** The close battery on the final commit:
the eighth seed-1 GATE GREEN, md5s byte-identical to the pre-phase baseline, `--validate`
0 errors (283 records), audits at zero, `linktest`/`linksoak` 8/8/`linkdrop` ALL GREEN, and
the cross-OS `determinism` workflow fully green on both runners (the gh #37 macOS flake did
not recur). **Next: Phase 4 — Studio MVP (gh #18)**. **Phase 4's design is pinned (ADR-020,
2026-07-22)**: one Godot project with a `--studio` launch mode (the packaging split is
Phase 7's); Studio never edits the extractor-owned project — the browser opens any folder,
dev/test copies Kanto to scratch, and the invariant with teeth is **canonical
write-through** (a Core GDScript writer matching the extractor's emitter byte-for-byte:
load + re-save = byte-identical); forms auto-generate from the validator's own schemas with
x-ref ID pickers and a custom-widget *registry* (sprite picker / learnset table / type
selector / party builder — only what the four editors demand); **refuse-loud at edit time**
(an invalid record cannot be saved); live play-test as a separate child process
(`--project=` — already live) with per-project save isolation; explicit Save/Revert, no
undo stack until Phase 5; the gate is `--studiotest` headless + the full-project re-save
identity sweep + a seed-1 GATE GREEN on a Studio-round-tripped project. Sub-issues
**gh #47–#51** (shell/browser → canonical writer → form engine → the four editors →
play-test + gate). Out by decision: event editing (Phase 5), importer GUI (Phase 7).
**Landed: gh #47** (2026-07-22): the `--studio` launch seam (one binary, two faces; Main
inert beside the shell), StudioShell with the project browser + recents, the four-type
sidebar/record list, `ProjectData.records(kind)`, and `--studiotest` (scratch-copies Kanto,
asserts the counts 151/165/152/47, proves the loud non-fatal refusal). **Landed: gh #48**
(same day): `CanonJSON` — the GDScript twin of the extractor's `_pj_write` (code-point key
sort, Python's escape set, whole-float→int re-emission) — proven by `--studiotest`'s sweep:
all 515 records of the four kinds re-serialize **byte-identical** against the extractor's
raw tree. **Landed: gh #49** (same day): the validator now exposes the exact schema + ID
registry context Studio consumes; `SchemaForm` recursively generates scalar, enum,
boolean, nested-object, array, and `x-ref` picker controls from those schemas (including
optional-field and array add/remove), reports CoreSchema/reference errors inline, tracks
dirty state, and validates before canonical Save so an invalid draft never touches the
last good bytes; malformed records retain repair controls (including nested required
containers), unmapped failures have a form-level diagnostic, free-form `custom` objects use
an editable JSON control, and explicit Revert restores the last save. `FormWidgetRegistry` is the tiny
`(content-type, JSON-pointer path)` override seam for #50's sprite/learnset/type/party
widgets, including whole object/array overrides, and the shell's record pane now mounts
the real generated form with Save/Revert. `--studiotest` drives the real controls through
valid canonical save, invalid local + dangling-ref refusal, add/remove/revert, and custom
scalar + collection overrides; the saved scratch project returns to `--validate` clean.
**Landed: gh #50** (same day): `StudioWidgetCatalog` fills exactly ADR-020's four registry
slots — the species sprite picker lists and previews front/back PNGs from the opened project,
the bounded type selector uses validator-owned type IDs, the ordered learnset table edits and
reorders level/move rows, and the trainer party builder edits ordered party variants and their
species/level members. Moves and items stay intentionally schema-only. `--studiotest` drives
real add/remove/edit controls, canonical species + trainer saves, custom-widget Revert, and a
final full-project validation.
**Landed: gh #51** (same day): Studio's Play-test button refuses an unsaved active record,
validates the project, then `StudioPlaytest` re-invokes the Engine as a separate child with
`--project=<dir>` and a stable normalized-path-derived `--saveslot`; a unique tokened file
handshake proves which project loaded and which isolated save path the child owns. Source runs
re-invoke Godot with `--path`; exported builds re-invoke themselves. `--studiotest` now performs
the full **write-to-disk** 515-record identity sweep, restores its edited fixtures byte-for-byte,
and verifies a headless child handshake + clean exit. **PHASE 4 COMPLETE — gh #18:** the restored
scratch tree matched Kanto across all 1,565 files, then `--playthrough --seed=1` on that exact
Studio-round-tripped project cleared all 21 checkpoints, beat the Champion, and entered the Hall
of Fame. **Landed: gh #59** (same day): Studio now breaks away from the game's 160×144 pixel-art
viewport before it builds any controls, opening as a native resizable 1280×800 desktop window
(900×600 minimum); the game keeps its faithful 3× stretch, and `--studiotest` asserts that the two
window profiles cannot drift back together. Next: Phase 5 — map + event editors (gh #19).
**Studio polish follow-up: gh #61** records the hands-on review that the schema-driven data
editor is usable but still needs the map workspace's stronger hierarchy, spacing, grouping,
record browsing, and visual finish. It may proceed independently without replacing the
shared form/schema model or delaying Phase 5.
**Phase 5 activated** (2026-07-22) as approved tracer-bullet issues **gh #52–#58** (native
TMX tracer → Kanto cutover → painting → objects/world graph → event editor → softlock
lints → phase gate). **Landed: gh #52** (same day; ADR-021): Project format 2 claims
`maps/*.tmx` + external `tilesets/*.tsx` while format 1 remains loadable; one deep
`MapDocument` seam serves ProjectData, ProjectValidator, Engine, Studio, and tests with a
canonical 16×16 cell model, project-contained raw imagery, typed Tiled gameplay objects,
newer/malformed refusal, and byte-identical no-op source preservation. Main renders native
cells and consumes TSX walkability through its existing world/collision seam; `--tmxtest`
proves the adapter. Studio gained a Maps workspace whose action bar, tool rail, dominant
canvas, inspector/layers, charcoal surfaces, and mint/cyan/magenta states follow the two
user-supplied reference boards now pinned in `docs/assets/studio/` and
`docs/v2/studio-visual-direction.md`; `--studiotest` drives its preview and Save. The Engine
and Studio tracer PNGs are SHA-256-identical. **Landed: gh #53** (same day; ADR-023): the
extractor now deterministically emits all 223 Kanto maps as native TMX, 24 external TSX atlases,
and the connection graph as `data/world.json`; no map JSON remains in a format-2 project. Each
legacy 32×32 block is represented by four reversible 16×16 cells, while typed Tiled objects and
an owned legacy payload preserve the exact runtime record through one `MapDocument` seam. Main
renders, collides, animates water/flowers, applies Cut and dynamic block replacement, and resolves
connections from the native documents. Two consecutive extractions produced the same full-tree
SHA-256 (`EF5FE5CCB3A1209D17A0407B06606DB2F5A2374136D8BF733C6C538625F90F9D`);
validation covered 1,613 files with zero errors; parity covered all 223 maps and all 24 TSX atlas
mappings/pixels; schema, self, map, warp, event, sight, Cut, TMX, and Studio gates passed; the four
battle stream hashes remained unchanged; and `--playthrough --seed=1 --ptwatchdog=120` cleared all
21 checkpoints and entered the Hall of Fame with a level-71 lead.
**Fixed: gh #63** (same day): Studio no longer keeps a stale format-1 manifest when the opened
project directory is rebuilt in place. `ProjectData` caches by directory plus exact manifest
bytes, map selection performs the lightweight refresh check, and `--studiomapsweeptest`
reproduces the live format cutover before mounting all 223 Kanto maps.
**Landed: gh #54** (same day; ADR-024): Studio's native map workspace now creates maps and
provides a project-atlas palette, tile/optional 32×32 block/erase/fill brushes, per-cell
walkable/solid editing, collision overlay, pan/zoom, grouped map-level undo/redo, Save/Revert,
and direct play-test of the active map. `MapDocument` owns the editable state and patches only
the `Ground` CSV plus an optional hidden `Collision` override layer; no-op saves remain
byte-identical and targeted saves preserve unrelated TMX and exact TSX bytes. The automated
Studio gate creates and edits a scratch map through the real controls, proves exact history,
reopens the saved document, and verifies one walkable and one solid cell in a separate Engine
child. Project parity, all 223 Studio map mounts, TMX, schema, self, warp, and Cut gates remain
green; all four battle-determinism hashes are unchanged; and the final no-resume
`--playthrough --seed=1 --ptwatchdog=120` cleared all 21 checkpoints, beat the Champion,
and entered the Hall of Fame with a level-74 lead.
**Landed: gh #55** (same day; ADR-025): the Studio map workspace now places and edits typed
warps, NPCs, signs, and rectangular trigger regions through stable-ID/property inspectors;
imported Kanto objects with exact legacy payloads remain visibly read-only. A project-level
world inspector creates, updates, and removes cardinal links as one exact reciprocal pair,
and map plus graph changes share a single undo/redo and Save/Revert history. `MapDocument`
targets only Studio-owned Tiled objects by private numeric anchor while preserving unrelated
TMX; `WorldDocument` canonically writes `data/world.json` and rejects duplicate directions,
missing/incorrect reciprocals, and edges with no geometric overlap. Project validation also
checks map/event references and destination-warp bounds. `--schematest` covers object and
graph mutation/refusal; `--studiotest` creates two maps through the real controls, places all
four object kinds, saves/reopens without drift, then a child Engine walks through the authored
warp and back across the authored seamless edge. Kanto still validates all 1,613 files with
zero errors; all 223 maps mount in Studio and retain semantic parity; all four battle stream
hashes are unchanged; and the final no-resume `--playthrough --seed=1 --ptwatchdog=120`
cleared all 21 checkpoints and entered the Hall of Fame with a level-71 lead. Next: gh #56 —
the event command/trigger editor.
**Landed: gh #34** (2026-07-20): Catch + Progression are behind the seam and the
**config-first knobs are real** — `Gen1Catch` (`attempt` over the byte-exact kernel + the
safari `bait_rate`/`rock_rate` transitions, which moved out of the host's input handler),
`Gen1Progression` (`badge_for_stat` = BadgeStatBoosts' mapping, `badge_for_field_move` = the
HM badge gates; `Main` consults it instead of its own tables), and the schema'd
**`data/ruleset.json`** record ({base, config}; base must match the manifest's selector;
additive under `format: 1`) carrying only what was already data — badge boosts, field-move
gates, both stat-stage tables, the high-crit list — emitted by the extractor with the
faithful gen1 values (project identity: **14 parts** now). Gate: `--schematest` +
`--validate` (1281 files, 0 errors) green, **double extraction byte-identical**, all four
`--battledettest` md5s unchanged, `--rulesettest` grew the module + config checks incl.
"a knob actually turns", `--movefxtest`/`--selftest`/`--projparitytest` green.
**Landed: gh #33** (2026-07-20): the battle module is behind the seam — `Gen1Battle` owns
the battle STATE (61 vars: mons/party/stages/volatiles, stored stats, AI state, safari,
catch/flee outcomes, the determinism RNG + stream, the lockstep link state) and the
mechanics, moved verbatim in four gated waves: turn resolution (`_resolve`/`_player_act`/
`_enemy_act`/`_end_of_turn`), the full move-execution chain, status + residuals, the
complete Gen-1 trainer AI, the lockstep link resolution (incl. resume send/reconcile),
safari turns, escapes, and the EXP/level/learn chain. `Battle.gd` is the HOST now —
presentation, menus, the message pump — forwarding state via get/set properties and
delegating mechanics with unchanged signatures, so the test harness and Cutscene/link
plumbing never noticed. Boot gained a fail-fast for a ruleset module that fails to load.
Gate: the four `--battledettest` md5s byte-identical through every wave; `--rulesettest` /
`--movefxtest` / `--selftest` / `--projparitytest` green; `linktest` ALL GREEN, `linksoak`
8/8 in sync, `linkdrop` ALL GREEN (dupe egg intact).
**Landed: gh #32** (2026-07-20): the formula layer is behind the seam — `Gen1Formulas`
carries the pure kernels moved verbatim (`stat_calc` with the sexp sqrt term, the four
growth curves + inverse, `crit_roll` incl. the Focus Energy bug, `damage_core` =
GetDamageVars' /4 byte-overflow scale + CalculateDamage's floored pipeline,
`randomize_damage`, `accuracy_roll` with the 1/256 sure-miss, `stage_apply`,
`special_damage`, and ItemUseBall's byte-exact `catch_attempt`); RNG-drawing kernels take
the battle's draw helpers as Callables so draw ORDER never moved. Stat *selection*
(unmodified-on-crit, screens, EXPLODE halving) stays with the battle state for gh #33.
`Battle.gd`/`Main.gd` delegate; the stage tables + HIGH_CRIT left them. Verified: the four
`--battledettest` md5s unchanged again, `--rulesettest` grew nine formula ground-truth
checks (exp book values, Mew's 298/403, the crit byte, MASTER BALL...), `--movefxtest`
fully green (wobble spread, CalcStat, badges), `--selftest` + `linktest.py` ALL GREEN.
**Landed: gh #31** (2026-07-20): the seam exists — `game/core/ruleset/` (the five interface
classes + `RulesetRegistry`, which now actually consumes the manifest's `ruleset` field: boot
refuses an unknown name naming both sides) and `game/rulesets/gen1/`, with **Types routed
through the seam as the tracer bullet** (`Gen1Types` owns the chart verbatim — `eff`/`mult`/
`row`, the table-ordered row accessor the damage loop's per-entry floors need; `type_chart`
left `Battle.gd` entirely). Verified by the new `--rulesettest` (registry + refusal + a
3375-combo cross-product equivalence vs the raw chart) with the oracle clean: all four
`--battledettest` md5s byte-identical to the pre-phase baseline, `--selftest` /
`--projparitytest` green, `linktest.py` ALL GREEN (lockstep still byte-identical).
**Landed: gh #22**
(2026-07-20): `core/schemas/` (JSON Schema per content type + the `format.json` layout
contract), `CoreSchema` (a subset validator that errors on unknown keywords) and
`ProjectValidator` (claims, record-id registration, dangling-reference resolution, the
refuse-newer manifest gate) — verified by `--schematest` (valid fixture clean; seven broken
fixtures each one named error) and `--validate=<dir>`; format spec in
[v2/project-format.md](v2/project-format.md). **Landed: gh #24** (2026-07-20): `build_project()`
is extraction's last stage — the full **Kanto project** emitted to `game/project/` (151 species /
165 moves / 152 items / 47 trainers / 15 types / 223 maps / 496 assets, 1255 files), records
consolidated + every reference prefixed, interim maps byte-copied, `.gdignore` at the root.
Gates: `--validate` **0 errors** with all six id sets registered; **byte-identical trees across
two extractions**; `--schematest` + `--selftest` green. The clean run took two honest rounds —
the validator caught 2189 real mismatches first (row-array blocks, string cry keys, numeric
ai_mods, empty unused parties, dead mart stock, Mew's UNUSED TM padding). **Landed: gh #23** (2026-07-20): `manifest.identity` — 13 per-part hashes over the emitted
canonical bytes + a `content_hash` by the generalized link-manifest rule — and the **v1.1 link
manifest is now a derived view of it** (`species`/`moves`/`types`, schema 2), so link refusals
and project identity can never drift apart; `Link.gd` unchanged (parts compare generically),
full linktest ALL GREEN. **Landed: gh #25** (2026-07-20): **`ProjectData`** opens the project at
boot (`--project=<dir>`; refuse-newer manifest gate) and rebuilds every v1-shaped table, so all
~35 load sites across `Main`/`Battle`/`TradeMovie`/`TitleScreen` now read the **project**, not
`res://assets`. Proven by the new **`--projparitytest`** (every table + all 223 maps deep-equal
vs the legacy files) *and* by `--battledettest`, which caught what parity structurally cannot:
**dict iteration order is behavior** (Metronome/Mimic pick over the move table's order), so
move/item/trainer records carry **`num`**, the canonical Gen-1 table index. **Phase 1 closed on component
evidence, not the end-to-end run** — see below. The gate run surfaced **gh #27**, three latent
navigator traps, all pre-existing since v1.1 and all fixed: Route 7's solid gate door unmodeled
by the planner; Cinnabar's locked-Gym push-back reading as *progress* (burning a whole walk
budget in silence); and the FLY cursor **double-stepping** — `Player._process` already dispatches
to `modal.handle_input()`, so the bot's own extra call advanced the Town Map cursor twice per
press, making a town on the other parity unreachable forever inside an unbounded loop (54 CPU
minutes, zero output; flying home to Pallet hid it because Pallet is the cursor's own start).
The bot now reaches **all eight badges** and Victory Road's door, where it failed on the 1F
boulder shove — **gh #28**, also pre-existing (`--victorytest` passes standalone). **Fixed**
(2026-07-20): the port was missing pokered's `BIT_BOULDER_DUST` — a shove's slide + dust puff
are one atomic beat that ignores further pushes, and without it the bot's next-tile press armed
mid-slide then vanished into the dust input lock, refusing tile 2 of every multi-tile shove
(the routes themselves were legal all along; see `docs/notes/gh105-victory-road.md`). With the
flag ported — plus the saffron stage gaining the standard retry loop it was missing (**gh #29**:
both seeds' first full runs died to a transient wander-RNG blockage on the Celadon Mart
approach) — the **ADR-011 Stage-1 artifact is GREEN again**: `--playthrough --seed 1` and
`--seed 2` each run NEW GAME → **HALL OF FAME** in one unbroken process (all 21 checkpoints in
order, `validate_gate.py` → **GATE GREEN** on both logs, Champion beaten at L67/L71). The
recovery-path weakness the failed runs exposed (a stage failure *inside* Victory Road strands
the retry loop) is split out to **gh #30**. (The *v1.1* work had been broken down as
gh #1 (spec) with sub-issues #2–#10.) **Landed: gh #2 — the battle determinism
oracle** (2026-07-19): every battle-logic random draw now comes from a battle-local seeded RNG
(never the frame-paced global RNG), each battle emits a canonical per-turn event stream (turn,
both actions, RNG cursor, state digest — `det_stream`/`[battledet]`), and `--battledettest`
replays scenario battles twice per seed asserting byte-identical streams (plus a
different-seed divergence check and cross-process-stable per-scenario md5s). See
[engine/battle.md](engine/battle.md) "Determinism". **Landed: gh #3 — the link tracer
bullet** (2026-07-19): `Link.gd` is the one networking module (low-level ENet, two reliable
channels, no awaits — every wait state times out cleanly), the extractor writes
`link_manifest.json` (md5s over base_stats/moves/types — the ADR-014 link identity), and
`--host`/`--join <ip>` script the whole connect flow headlessly: hello both ways, each side
validates version + per-part hashes, refusals NAME the differing part and are delivered
before the graceful drop (`peer_disconnect_later`), and the session records the mutual-only
dupe flag. `python tools/linktest.py` drives four two-instance scenarios (clean + round-trip,
tampered part, tampered version, no-host timeout) — ALL GREEN. See
[engine/link.md](engine/link.md). **Landed: gh #4 — the mon record codec** (2026-07-19):
`MonRecord.gd` maps one mon between the internal dict and the versioned **`mon/1`** wire
schema (stable `species:`/`move:` ids, explicit fields, hp DV re-derived, stats rebuilt —
never trusted off the wire), refusing unknown versions and malformed records with
field-naming errors; `--monrecordtest` round-trips four mon shapes + rejects ~24 bad
fixtures single-process. See [data-formats/mon-record.md](data-formats/mon-record.md).
**Landed: gh #5 — the Cable Club attendant** (2026-07-19): talking to any Center's link
receptionist runs `CableClubNPC` faithfully — HOST/JOIN/CANCEL as the modern cable, the
naming screen's new **address mode** (digits + dot, last-used address saved as the ED
default), refusals surfacing in-dialogue naming the differing part, the asm's save-warning →
save → "Please wait." sync → LinkMenu (first press wins, host arbitrates), and the special
warp onto the TradeCenter/Colosseum floor (host (3,4), partner (6,4)). Every wait/dead-end
path returns to the attendant cleanly. Verified by `--clubtest` + two new `linktest.py`
scenarios (full two-instance flow to the Trade Center floor; tampered joiner turned away on
both sides). **Landed: gh #6 — the Trade Center** (2026-07-19): parties exchange as mon
records at the table, pick + partner's pick + mutual confirm, a **two-phase atomic commit**
(records → journal → both acks → apply + save; a drop applies on neither side), the in-game
trade-movie ceremony, nickname/OT/trainer-ID preserved, party-full overflow to the box, and
**trade evolutions firing on arrival** — the `linktest.py` trade scenario swaps kadabra ↔
machoke and reads ALAKAZAM/MACHAMP with foreign OTs back out of **both save files**. Room
behavior (partner avatar opposite, doormat exit, link-death kick-out) lives in the
TradeCenter/Colosseum adapters. Also: gh #12 filed (cross-platform link) and its first fix
landed — the identity manifest hashes newline-normalized bytes, so a Windows↔Linux pair
can't refuse over line endings. **Landed: gh #7 — the Colosseum lockstep battle**
(2026-07-19): both engines run the full battle from the host's shared seed, mirrored
(each peer is its own "player"), with only chosen actions crossing (`col_act`/`col_swap`);
the asm's link special-cases are faithful (no badge boosts, no hidden stat-down miss, no
EXP, stakeless party restore, no SHIFT prompt), speed ties break on the shared coin read
canonically ("heads = host first"), and the event stream is role-canonical — the
`linktest.py` colosseum scenario asserts **byte-identical `[battledet]` streams across two
real networked instances** (ADR-014's definition of "in sync"), agreeing winners, and
restored parties. Non-link battles untouched (`--battledettest` md5s unchanged).
Documented divergence: link MIMIC picks deterministically (the item refusal in link battles
turned out to be the cartridge's own rule — core.asm's BagWasSelected guard — so it is
faithful, not a divergence; corrected 2026-07-20).
**Landed: gh #8 — the desync soak** (2026-07-19): `python tools/linksoak.py` runs a
configurable battery of seeded two-instance link battles over the `--colsoak` fast path —
six varied parties (status/locks/multi-hit/crit/confusion/Transform/Mimic/Metronome/REST,
legal fixed DVs, a mirror match that speed-ties every turn), deterministic varied move
policies — and gates green only on byte-identical streams in every battle, naming the
battle/turn/first-diff on failure. The first battery caught three real lockstep bugs
(illegal fixture DVs; forced-continuation PP spent on one sim only; the one-sided
Transform/Mimic backup+revert) — all fixed; **8/8 in sync, repeatedly**. **Landed: gh #9 —
drop-injection + the dupe easter egg** (2026-07-19): `--killat` cable pulls at scripted
points, the phased trade journal (`ready` → rollback, `acked` = the point of no return →
roll-forward on the next load, silent trade evo included), and `python tools/linkdrop.py`
proving the matrix — battle drops stakeless, pick/confirm/commit pulls leave both saves
untraded, ack-window pulls leave both traded; the dupe egg reproduces the cartridge's
duplication **only** under mutual opt-in (asymmetric opt-in refuses the session). ALL
GREEN. **All automatable v1.1 work is done — what remains is gh #10: the Stage-2 real
remote human session, then the v1.1.0 release** (and gh #12 cross-platform, which needs a
second platform's build). Next: gh #10.
Earlier: the playthrough bug waves (gh #23–#52, 27 issues) are fully fixed across 0.9.1–0.9.12:
and the playthrough bug waves (gh #23–#52, 27 issues) are fully fixed across 0.9.1–0.9.12:
options/start/yes-no boxes, party + summary + battle-item screens, Pokédex (with working
DATA/CRY/AREA/QUIT), the mart rebuilt as its own modal, nurse heal ceremony, catch-flow
presentation, the GB's off-centre camera, test-save isolation, and white emote bubbles — each
verified against the user's reference screenshots (`build/preview/bugs/`).
Engine sweeps (July 3): the move-effect table is at 100% coverage (RAGE was the last gap), the
full Gen-1 trainer AI is in (move-choice layers + all 19 item/switch handlers), and stat
experience (Gen-1 EVs) landed — GainExperience + CalcStat's sqrt term. The crit formula was
audited asm-exact (all four focus/high-crit paths).
Remaining: the low-traffic map beat passes (gh #22), then the playthrough continues → 1.0. The
**Stage-1 legit-play bot** (gh #76, ADR-011) now plays **the whole game from NEW GAME to the HALL OF
FAME**, and as of 2026-07-10 **all 21 stages are green** on seed 1 (`opening → parcel → brock → misty →
bill → ssanne → surge → rocktunnel → erika → silphscope → pokeflute → snorlax → koga → safari → saffron →
silph → sabrina → blaine → giovanni → victoryroad → elite4`) — `tools/validate_gate.py` on the assembled
run reports **GATE GREEN** (21 checkpoints in order, HALL OF FAME entered, no `FAIL(`/`stayed put`/
`SCRIPT ERROR`/teleport tells). The Champion fell at L65. This was first proven as a chain of
`--from=<stage>` segments; the **single unbroken process** was blocked on **gh #98** — the
`Engine.time_scale = 25` clobber that had never taken effect, so a full run at real time was 90+ minutes,
past the background-job ceiling. **gh #98 is now fixed** (2026-07-11): a driver owns the clock, 25× is
live everywhere, and the runs stay faithful (nav budgets already scaled by the live time scale, and the
battle RNG never depended on it). Verified — `--surgenavtest --route9` (nav+whiteout+warps) 3 s,
`--erikastage` (catch + gym leader) 41 s, `--elite4stage --gauntlet` (the tightest battle loop, ~40 min
before) **21 s**, and `--from=misty` chained through **14 stages** at speed. A full seeded run now reaches
Mt. Moon in ~82 s, so the single-process sign-off run became feasible — and, after gh #131, **green**.
That first full continuous run surfaced a systemic robustness gap the chained `--from` segments had hidden:
the early stages (unlike Misty onward) challenged their gyms/gauntlets with **no potions and no whiteout
retry**, so an RNG-unlucky faint whited out to Pallet's default respawn and ended the run — and at 25× the
frame-timing-shifted RNG makes those winnable fights lose often enough to matter (Brock, then Nugget Bridge,
then Mt. Moon each surfaced in turn). The `brock`, `misty` (Mt. Moon), and `bill` legs now heal at the town
Center (registering it as the respawn), carry potions so the mid-battle heal can fire, and retry a lost leg —
exactly what the later stages and a real player do (gh #131). **`--playthrough --seed 1` now runs green
NEW GAME → HALL OF FAME in one unbroken process** — all 21 checkpoints in order, `validate_gate.py` → GATE
GREEN, Champion beaten on Elite Four attempt 4 at L73, ~21 min wall-clock. The textbook single-process
Stage-1 sign-off is done; the human playthrough (ADR-011 Stage 2) is what remains to gate 1.0.

## Milestones

| # | Milestone | State | Notes |
|---|---|---|---|
| 0 | Asset extraction pipeline | ✅ done | overworld tileset + Pallet Town |
| 1 | Map rendering (block→tile) | ✅ done | custom 2D draw in `Main.gd` |
| 2 | Collision | ✅ done | bottom-left-tile (feet) passability rule |
| 3 | Grid-walking player + camera | ✅ done | placeholder sprite → real sprite in M4 |
| 4 | Real player sprite + walk animation | ✅ done | `gfx/sprites/red.png`, 6 frames |
| 5 | All maps + tilesets extracted | ✅ done | 223 maps, 24 tilesets |
| 6 | Warps / doors (enter buildings) | ✅ done | round-trip verified |
| 7 | Map connections (seamless routes) | ✅ done | offsets verified (incl. non-zero) |
| — | Ledge hops + tall-grass overlap | ✅ done | overworld polish (pre-M8) |
| 8 | NPCs (sprites + movement + collision) | ✅ done | wander, solid, interaction hook |
| 9 | Text boxes + font | ✅ done | typewriter, pages, signs+NPCs; 653/1209 ids |
| 10 | Menus (start menu, yes/no, lists) | ✅ done | reusable cursor menu; modal input model |
| 11 | Battle engine (complete) | ✅ done | all move effects, status, evolution, trainers, items |
| 12 | Save system + Pokécenter heal + overworld poison | ✅ done | JSON slot, continue on launch; see [engine/save.md](engine/save.md) |
| 13 | Audio — music | ✅ done | GB 4-channel synth of pokered song data; see [engine/audio.md](engine/audio.md) |
| 14 | Audio — SFX / cries | ✅ done | 151 SFX (both banks) + 151 cries; menu blip, cry, and per-action battle SFX wired |

## Current focus

The **main quest is completable end-to-end** (0.6.0) and most **side content** is now in too.
Landed since 0.6.0 (all `--<flag>` tested): Saffron drink-gate; the **Game Corner** (faithful slot
machines + coins + prize room); **Good/Super rods**; **static legendaries** (Articuno/Zapdos/Moltres/
Mewtwo + Power Plant Voltorbs); **gift Pokémon** (Eevee, Hitmon choice, Magikarp salesman);
**fossils** (Mt. Moon pick → museum amber → Cinnabar revival); the **Pokémon Mansion switches** +
**Cinnabar Gym** SECRET KEY lock; and the **Victory Road** boulder-switch door puzzle. In-game
trades, the Safari Zone, fishing, Day Care, the PC, and remappable controls were already in.

**Remaining toward 1.0:** a broader faithfulness audit. The two previously-deferred items — the
**Seafoam B4F strong current** and the **Silph Co card-key door lock** — are now both implemented
(see below).

**Map-script faithfulness campaign (gh #22):** the story-critical sweep is done — Pallet, Oak's
Lab, Viridian (+ the old-man catching demo), Pewter (+ the two escort drags & east gate),
Cerulean, Routes 22/24/25 + Bill, Vermilion + S.S. Anne, Lavender/Pokémon Tower (+ the
unidentified-GHOST battle system), Celadon (+ spin tiles, also Viridian Gym's), Saffron/Silph
(+ the 7F corridor ambush), Cinnabar (+ the quiz doors). Each map was beat-audited against its
asm (emotes, music cues, no-wait text, walk choreography, object toggles). Remaining: the
lower-traffic maps and small deferred deltas — see the #22 checklist.

**Menus/options audit:** the **OPTION menu is in** (`OptionsScreen.gd`, faithful to
`DisplayOptionMenu`): text speed drives both text boxes, BATTLE ANIMATION OFF plays the 30-frame
beat, and **BATTLE STYLE SHIFT** adds the missing "Will ⟨PLAYER⟩ change POKéMON?" free-switch
prompt before a trainer's next mon; saved with the game, reachable from the start + main menus.
The start menu gained its conditional POKéDEX / player-name / EXIT entries. Audited-and-OK:
the Pokédex list (owned dots, SEEN/OWN, DATA/CRY/AREA side menu + entry pages), party menu
(icons/HP rows + STATS/SWITCH submenu), the PC family (Bill's/player's/Oak's-rating/item PC with
TOSS), marts + quantity picker, save screen, the trainer badge card, bag capacity/TOSS, the
League PC. Verified by `--optiontest` / `--menutest`.

**Music-engine audit (gh #73, v0.9.27):** songs **loop at their real `sound_loop` points** —
each channel walks its intro then one loop body, and the wav loops over
`[max intro end, + lcm(bodies)]`, so intros never replay, unequal channels keep cycling (the
title screen's drums roll on under the ended melody), and jingles play once. The audit also
landed: **vibrato** / **toggle_perfect_pitch** / **duty_cycle_pattern** / **pitch_slide**
(previously parsed-and-dropped), the real **channel-3 wavetables** (incl. the per-bank glitch
wave 5 — Lavender Town's lead) at the correct **half-rate frequency** (basslines were an
octave high), **drums as the real noise instruments** through a Gen-1 **LFSR** (the poly
register was ignored — every drum and noise SFX was the same white hiss),
finalbattle's cross-channel `sound_call`s (silently skipped bars), and `PlayBattleMusic`'s
picks (gym leaders + Lance → gym-leader theme, the Champion → finalbattle). See
[engine/audio.md](engine/audio.md); verified by `--audiotest` / `--presynthtest`; listen
artifacts in `build/preview/audio/`.

**Menu-stack + item-list audit (gh #66, v0.9.26):** menus now stack like pokered's shared
tilemap — the START menu stays under the bag (hollow ▷ parked on ITEM), the bag under
USE/TOSS, and the toss ×NN picker + YES/NO confirm pile on top (`Menu.push_under`/`under`);
the item list is the faithful ITEMLISTMENU (16×11 box at (4,2), names col 6 rows 4-10, ×NN
quantities below-right — none for key items — the ▼ at (18,11), the 3-row cursor window +
scroll rule), the USE/TOSS box sits at its real (13,10), and bag messages overdraw the stack's
bottom rows (textbox z-bump). See [engine/menus.md](engine/menus.md); verified by `--bagtest`
/ `--keybindtest` / `--uishot` (usetoss/tossqty/tossconfirm shots).

**Item-menu behavior audit (gh #56/#57/#58, v0.9.19):** using or tossing an item returns to the
bag with the cursor kept (`ItemMenuLoop` + `wBagSavedMenuItem`); only a successful escape rope /
itemfinder / flute / rod / bicycle closes the menu (`UsableItems_CloseMenu`), and the bicycle
skips USE/TOSS. SELECT-swap now matches `HandleItemListSwapping` on every ITEMLISTMENU (bag,
PC item lists, battle bag, mart SELL) with the hollow-▷ held marker, and SELECT reorders moves
in the battle FIGHT menu (`SwapMovesInMenu`). Verified by `--bagtest` / `--keybindtest` /
`--movefxtest`.

**Audit fallout batch (gh #59–#64, v0.9.20):** B backs out of every start-menu screen to the
START menu (`RedisplayStartMenu`); TM/HM use plays the "Booted up" confirm and runs the
LearnMove forget flow (abandon loop, HM moves can't be deleted, TM consumed only on learn);
ESCAPE ROPE is gated to the EscapeRopeTilesets; bag stacks cap at 99 (AddItemToInventory_)
and an emptied slot resets the bag cursor; Transform/Mimic act on a battle-only copy that
reverts on switch-out/battle end with pokered's PP quirks (`DecrementPP`); `--stonetest`
repaired (it drove the start menu by stale index and relied on the debug default bag).

**Boot-intro audit is done** (splash.asm/intro.asm/title.asm): the third audio bank (the intro SFX)
is now extracted, and the whole boot plays faithfully — copyright 3 s, the silent letterboxed beat,
the shooting star + logo flash + falling stars with their sounds, the Gengar/Nidorino fight with
its hip/hop/raise/crash/lunge cues and full 80-frame entrance, and the title's logo-bounce crash →
beat → version whoosh → only then the music, with the shown mon's cry on START. Posed by
`--introshot`; regression `--titletest`.

**Battle transitions + warp fade are in** (see [engine/battle.md](engine/battle.md)
"Presentation"): pokered's full 8-wipe system (flash + circle sweeps / spirals / stripe combs /
shrink & split, picked by the trainer/level/dungeon bits with `dungeon_maps.json`) replaces the
placeholder blinds, and warps fade to black with the map-change sound (`GBFadeOutToBlack`).
Verified by `--wipetest`.

**Battle-screen faithfulness pass** (the audit's first area, see [engine/battle.md](engine/battle.md)
"Presentation"): the HUD is rebuilt from the real HUD tiles at pokered's exact coords; the full
Gen-1 **start intro** is in and audited line-by-line against the asm — auto-advancing intro texts,
the faithful wild order (cry → balls → "appeared!" → HUD → 40-frame beat), the complete **trainer
intro** (trainer silhouette slide-in, sting, both ball brackets, slide-off, the sent-out mon
growing in + cry, reused for mid-battle send-outs), and the safari variant (no send-out, the
player's pic stays); the **HP bar drains** (`UpdateHPBar2`) on every HP change;
the **faint** slides the pic down (`SlideDownFaintedMonPic`); and level-up shows the real **stats
box** (`PrintStatsBox`). Move-effect message ordering was verified faithful. **Per-move attack
animations are in (issue #19,** all four phases**):** `build_move_anims` extracts the full
`DrawFrameBlock` system (203 anim scripts, 86 subanimations, 122 frame blocks, 177 base coords + the
`move_anim_0/1` tile sheets) into `move_anims.json` — see
[data-formats/battle-anims.md](data-formats/battle-anims.md); `Battle._build_move_anim` compiles any
anim into timed shadow-OAM steps (faithful write-pointer/mode semantics, enemy-turn transforms,
per-subanim SFX) played by a `{"moveanim"}` queue marker; the common **special effects** are native
(screen flash/palettes, BG-only shake, pic hide/show/blink, lunges, slides); and `_do_move` queues
the real animation followed by the faithful **hit reaction** then the HP drain
(`PlayApplyingAttackAnimation`: sting + target blink / light/heavy/vertical shake by
`AnimationTypePointerTable`; slow silent shake for status moves; a miss plays neither animation nor
sound). Verified
by `tools/preview_move_anims.py` (data-only composite) + `--moveanimtest` (in-engine: counts,
transforms, timed markers, a real fight turn, posed shots). **The special-effect routines are in
(gh #20, DONE):** every `SpecialEffectPointers` entry is handled in `Battle._do_special_effect`
(commit `bb96418`) — spiral balls, water droplets, wavy screen, squish/minimize/transform pic warps,
falling leaves/petals, the ball fountains, slides/blinks/shakes — and the per-anim frame-block hooks
(`AnimationIdSpecialEffects`: Mega Punch's per-block flash, the Blizzard/Thunderbolt/Hyper Beam flash
cadences, Explosion's vanish, Growl's note trail, Rock Slide's shakes) are wired in `Battle._anim_hook`
(commit `3377c8f`). Verified by `--moveanimtest` (all 203 anims build; every SE smoke-plays and cleans
up its render state; the hooks fire). **`wavy_screen` is now the faithful per-scanline raster** (Psychic/
Confusion/Psywave/Night Shade): `_do_wavy_screen` freezes the 160×144 frame to a texture and `_draw`
redraws it row-by-row shifted by pokered's `WavyScreenLineOffsets` table (±2px, the wave advancing one
row per frame for 255 frames), replacing the earlier whole-screen sine shake. The capture's
`frame_post_draw` is headless-guarded (gh #103; headless keeps the faithful duration with no visual).
Posed by `--moveanimtest` (`moveanim_wavy.png`). **The last stylised particle effects are now
per-OAM exact** (the gh #22 closeout): spiral balls trail the real `SpiralBallAnimationCoordinates`
pairs (3 balls, 5-frame steps, the ending screen flash), the water droplets replay
`AnimationWaterDropletsEverywhere`'s byte-wraparound rain (64 one-frame screens), and Razor Leaf /
Petal Dance run `AnimationFallingObjects`' movement bytes verbatim (2px falls, the delta-X pendulum,
the 104-termination). The one divergence is documented in code: the two `$09/$89`-seeded petals
overread the delta table into code bytes on cartridge; the port clamps to the max delta instead of
emulating raw memory.

**Frame-timing audit** is done (see [engine/timing.md](engine/timing.md)): pokered's overworld loop
ticks at **30 Hz** (two V-blanks per iteration) while battle/text `DelayFrames` are 1/60 s — the port
keeps its high render framerate but paces everything by the faithful domain. Fixed: NPC walk speed
(0.536 s/tile + the 4-phase step cycle and original wander delays), the ledge hop (0.536 s), boulder
slides, the sight `!` bubble (1.0 s), text speed (Gen-1 MEDIUM, 3 V-blanks/letter), and the battle
hit blink / decaying shakes / sway / lunge / slide frame counts. Player walk & bike were already
faithful.

**Fly / Surf / ship transitions** are in: **Fly** now fades through with the fly SFX
(`Cutscene.fly_transition`) instead of snapping; **Surf** glides onto the water (`Player.surf_hop`)
rather than teleporting; and the **S.S. Anne departure** fades out with the horn as it pulls away
(`ss_anne_departs`). Verified by `--flytest` / `--surftest` / `--ssannetest`.

**End credits** are the real roll now (gh #22, v0.9.29, faithful to engine/movie/credits.asm):
`build_credits` parses `data/credits` into `credits.json` — 35 pages of staff text, each line
keeping its **column-offset byte** (base col 9, `#`→`POKé`), plus per-page `fade`/`mon`/`copyright`
flags and the 15-entry `CreditsMons` order. `Cutscene.run_credits` draws the Gen-1 layout: black
**letterbox bars** over a white text band, left-aligned staff lines at their real columns, and at
each `*_MON` page a **Pokémon front sprite scrolls left across the band as a black silhouette**
(DisplayCreditsMon) — the transition between sections. The **© page** reuses the boot copyright
tiles and **THE END** is the real spaced letter graphic (`credits_the_end.png`). Tests run a fast
path (audio off). Verified by `--creditstest` (35 pages / 15 mon slides / 1 © page); posed by
`--creditshot` (text/mon/copyright/end in `build/preview/credits/`).

**Dark-cave palette swap** is in: dark maps (`DARK_MAPS`) render the Gen-1 dark palette — a uniform
full-screen darkening, **not** a spotlight (gh #127). Entering Rock Tunnel pokered sets
`wMapPalOffset = $06`, so `LoadGBPal` loads `FadePal2` (`BGP/OBP0 = 3,3,3,2`): the lightest of the
four DMG shades maps to shade 2, every darker shade to shade 3 (black). `shaders/cave_dark.gdshader`
on the `darkness` overlay remaps the rendered screen's shades to that palette; FLASH hides it entirely
(`_update_darkness`). Rendered by `--caveshot`.

**Town Map** is in: the extractor (`build_town_map`) composites the RLE tilemap + tile sheet into a
160×144 `town_map.png`, extracts the cursor, and emits `town_map.json` (the TownMapOrder cycle of
`{x, y, name}` + a map-label→index start table). `TownMap.gd` is the viewer (`Audio` tink + a
blinking cursor; UP/DOWN cycle locations, A/B close), opened from the bag's **TOWN MAP** — given by
Daisy in Blue's house once you hold the Pokédex (`Cutscene.daisy_town_map`). Verified by
`--townmaptest`; rendered by `--townmapshot`.

**Per-move attack SFX** are in: the extractor emits `move_sfx.json` (`build_move_sfx` from
`data/moves/sfx.asm`'s MoveSoundTable — `MOVE_CONST -> [sfx_key, pitch]`), and `Battle._do_move`
plays each move's sound (with its pitch modifier via `Audio.play_sfx(key, pitch)`) when the move is
used, before the effectiveness hit cue. Verified by `--sfxtest`.

**Wild encounters now key by map label** (`build_wild`): the extractor resolves `WildDataPointers`
positionally against the map-constant order, so shared tables map to every map that uses them — e.g.
the surf-only **SeaRoutes** Tentacool table now covers Route 19 + Route 20 (previously dropped). In
Red only Route 19/20/21 have water (surf) encounters; every other table is `def_water_wildmons 0`.

**Story scripting** (in progress): a cutscene runner (`Cutscene.gd`) with event flags, player/
rival identity, and starter tracking (saved/loaded); a GB-style **naming screen** (preset list +
keyboard, ornate frame); and **Oak's speech** on NEW GAME (Oak → flipped Nidorino → name yourself
→ name your rival → "your legend is about to unfold"). All boxes now use the shared `Frame.gd`
helper for the Gen-1 double-line border.

The **Pallet Town → Oak's Lab opening quest** is in (faithful to scripts/PalletTown.asm +
scripts/OaksLab.asm): the player wakes in their room at pokered's NewGameWarp; trying to leave
Pallet north without a POKéMON triggers **Oak's intercept** (he appears, walks up, "It's unsafe!",
leads you to the lab); the **lab entrance + choose-a-mon speech**; **picking a level-5 starter**
from the three balls; the **rival taking the counterpart** and the **first rival battle**
(OPP_RIVAL1, party by your pick), with party-heal + the rival walking out afterward. Built on
scripted movement: `Player`/`NPC.step()/face()`, a BFS `find_path()`, cutscene `walk()` helpers,
and event-driven object visibility (`NPC.set_shown` / `Main._object_shown`). Verified by
`--oaktest`.

The **Oak's Parcel errand** is in (faithful to scripts/ViridianMart.asm + scripts/OaksLab.asm +
scripts/ViridianCity.asm): entering **Viridian Mart** after getting a starter, the clerk calls you
to the counter and hands over **OAK's PARCEL** (`Main._on_map_loaded` → `Cutscene.viridian_mart_
parcel`); the road north out of **Viridian City** is blocked by the sleepy old man until you have
the POKéDEX (`viridian_oldman_block` at X==19,Y==9); **delivering** the parcel to Oak triggers the
**POKéDEX receipt** — the rival rushes back in, Oak gives you both the POKéDEX (the two desk-shelf
POKéDEX sprites disappear), and the rival leaves (`Cutscene.deliver_parcel` → `pokedex_receipt`,
fired from the Oak interaction). Events: `GOT_OAKS_PARCEL`, `OAK_GOT_PARCEL`, `GOT_POKEDEX`,
`RIVAL_GOT_POKEDEX`. Verified by `--parceltest`.

**Trainer line-of-sight** is in (faithful to `home/trainers.asm` + `engine/overworld/trainer_
sight.asm`): an undefeated trainer facing the player, lined up within its view range, engages on a
step — the `!` bubble pops, the trainer marches up, and battles with before/after dialogue. View
range + before/end/after-battle text are extracted from the script trainer headers into the map
JSON; the `!` bubble is the extracted `shock` emote. Defeat is keyed by the trainer's home cell.
See [engine/npcs.md](engine/npcs.md); verified by `--sighttest`.

**All eight gyms** are in (one `_GYM_LEADERS` data entry each): **Brock** (Boulder+TM34),
**Misty** (Cascade+TM11), **Lt. Surge** (Thunder+TM24), **Erika** (Rainbow+TM21), **Koga**
(Soul+TM06), **Sabrina** (Marsh+TM46), **Blaine** (Volcano+TM38), and **Giovanni** (Earth+TM27,
Viridian Gym party 3 — distinct from the Rocket Hideout Giovanni, which is special-cased). All
verified by `--gymtest`. The earlier per-gym mechanics: the gym's ordinary trainers engage via the
sight system; talking to the leader runs the pre-battle speech → battle → badge + TM on a win, with
a re-challenge line once beaten. Adding a leader is one `Cutscene._GYM_LEADERS` entry. Vermilion's
**trash-can switch puzzle** gates Surge (a runtime door via `Main.set_block`). Badges are tracked in
`Main.badges` (saved). See [engine/npcs.md](engine/npcs.md); verified by `--gymtest` / `--surgetest`.

**Battle SFX** are wired (engine-2 SFX bank now extracted too): per-action cues fire in sync with
their message via queue markers — the hit sting by type effectiveness, faint, level-up, ball
toss + caught, and run. See [engine/audio.md](engine/audio.md); verified by `--sfxtest`.

**Badge stat boosts** are in (`Battle._battle_stat`, faithful to `BadgeStatBoosts`): each badge
raises one of the player's in-battle stats by ×9/8 (BOULDER→Atk, CASCADE→Def, THUNDER→Spd,
SOUL→Spc). See [engine/battle.md](engine/battle.md); verified by `--badgetest`.

**Overworld item balls** are in: a `SPRITE_POKE_BALL` with an item-const arg is a pickup —
`build_items` extracts `items.json` (const → display name, TMs as `TMnn`), and facing + A adds it to
the bag, then the ball is gone for good (`Main.picked_items`, saved). See [engine/npcs.md](engine/npcs.md);
verified by `--itemtest`.

**Poké Marts** are in: a mart clerk opens BUY / SELL — `build_marts` extracts each mart's stock and
`build_items` the BCD prices (`item_prices.json`); a **quantity picker** (`Menu.open_qty`) handles
buying/selling N at once (capped by money / stock). See [engine/npcs.md](engine/npcs.md); verified
by `--marttest`.

**Pokémon storage PC** is in: the Pokémon Center PC opens WITHDRAW / DEPOSIT (`Main.pc_box`, saved)
with last-mon / full-party guards, so a full party no longer blocks catching. Verified by `--pctest`.

**HM field moves** are started with **Cut**: HMs teach a field move from the bag (compatibility from
the extracted `tmhm` list, HM not consumed), and facing a cuttable tree with a CUT-knowing mon + the
Cascade Badge swaps the tree block away (`Main.set_block`, faithful to `cut_tree_blocks.asm`). The
data tables cover Fly/Surf/Strength/Flash too; those (and obtaining HM01 on the S.S. Anne) are next.
See [engine/npcs.md](engine/npcs.md); verified by `--cuttest`.

**Hidden items** are in: facing their tile and pressing A yields the item (`Main.found_hidden`,
saved), no Itemfinder needed. Verified by `--hiddentest`.

**Usable bag items** are filled out: potions (incl. Super/Hyper/Max/Full Restore), status heals,
Revive, Rare Candy, plus field items **Repel** (suppresses wild encounters, `Main.repel_steps`,
saved) and **Escape Rope** (warp to the respawn map). Verified by `--itemusetest`.

**Cerulean rival battle** (the 2nd story rival fight) is in: crossing the north bridge
((20,6)/(21,6)) triggers the rival to appear, battle (OPP_RIVAL1, a tougher party by starter), and
leave with the hint to thank BILL (`Cutscene.cerulean_rival`). Verified by `--crivaltest`.

**S.S. Anne chain (in progress, full faithful):** **Bill's house** is done — talk to Bill-as-a-
POKéMON, agree to help, he enters the teleporter; run the **cell-separator PC** (separation jingle);
the real Bill steps out and gives the **S.S.TICKET** with the nudge to board the S.S. Anne
(`Cutscene.bill_intro`/`bill_separator`/`bill_ticket`, `_object_shown` toggles). Verified by
`--billtest`. **Boarding + captain done**: the Vermilion dock warp is gated on the S.S.TICKET
(sailor flashes you aboard, else "you need a TICKET"; `_do_warp` gate + `Cutscene.board_ss_anne`),
and the seasick **captain** in his cabin gives **HM01 (CUT)** after you rub his back
(`Cutscene.ss_anne_captain`). So Cut is now obtainable → teachable → cuts trees. The ship's maps,
trainers (sight), and item balls already work via the generic systems. The **2F deck rival battle**
(OPP_RIVAL2, party by starter, `Cutscene.ss_anne_rival`) and the **ship departing** when you step
off the ship after HM01 (`Cutscene.ss_anne_departs` → `SS_ANNE_LEFT`, a one-time area) are also in.
**The whole S.S. Anne chain is complete** — Bill → ticket → board → deck rival → captain's HM01 →
leave → ship sails. Verified by `--ssannetest`. The departure is the **real animation** (gh #22,
v0.9.28, faithful to VermilionDock.asm): MUSIC_SURFING + the horn, the ship band (the LY 80-127
raster window) sliding west 128 px at 1 px per 8 frames with white smoke puffs popping above the
smokestack every 16 px and drifting east, the erase to open water, the second horn, and the
scripted walk north off the dock — no dialogue, as on the cartridge. Posed by `--anneshot`.

**Legit-play bot (gh #76) — Rock Tunnel leg to Lavender:** the `rocktunnel` stage (Vermilion →
Cerulean → Route 9/10 → Rock Tunnel → Lavender) is in `_PT_STAGES_WIP`. The **Rock Tunnel 1F/B1F
ladder maze** is derived (`--rtprobe` connectivity probe) and **verified** end-to-end
(`--rocktunneltest --tunnel` → Lavender; no FLASH needed — cave darkness is a render-only overlay).
Entering Route 9 from Cerulean drops you in a small grassy pocket gated eastward by a **CUT tree**
(block 0x35 at (5,8) — the same Cut gate as the Vermilion Gym); the bot cuts it with the HM01 mon
earned in the `ssanne` stage (`_pt_cut_route9_tree`). The **`erika` stage** crosses Lavender → Route 8 →
the Route 7-8 Underground Path → Route 7 → Celadon (bypassing the drink-gated Saffron gates), catches a
**Growlithe** on Route 7 (Fire — resists Erika's grass, hits it 2×, the coverage answer like Diglett
vs Surge), cuts the tree gating the gym plaza (block 0x32 at (35,32)) **and** the tree gating Erika's
platform *inside* the gym, and beats **Erika** for the RAINBOWBADGE (`--erikastage` PASS end-to-end,
with the persistent-player whiteout-retry). This surfaced + fixed a real **engine bug**: the cut
mechanic dropped the GYM-tileset cut tree (tile 0x50) + half of pokered's `CutTreeBlockSwaps` — the
Celadon Gym was unbeatable on foot for the human playthrough too. Now `_try_cut` handles OVERWORLD
(0x3D) + GYM (0x50) with the full block-swap table. The **`silphscope` stage** (Celadon Game Corner
poster → Rocket Hideout → Giovanni → SILPH SCOPE) is **complete** (`--silphscopetest` PASS from Celadon,
now including the poster leg it used to skip — see gh #89 below): the bot beats the ROCKET standing on
the poster's stand cell, then the full **B1F→B4F descent** works on foot via **spin-aware pathfinding**
(`_pt_plan`/`_pt_walk_dungeon` model a step onto an arrow as landing on its stop tile; verified
`--spinnavtest`/`--silphdescent` across the B2F/B3F arrow mazes). This surfaced + fixed a second bug:
the **spinner tile coords were transposed** in `build_spinners` (`map_coord_movement` is (x,y), read
as (y,x)) — the spin mazes (Rocket Hideout, Viridian Gym) were never walkable on foot. **B4F is two
disconnected regions**: the B3F stairs land in the west wing (Rocket 3 + the LIFT KEY); Giovanni, the
SILPH SCOPE, his two door grunts and the elevator are all in the east one. The only crossing is the
**LIFT-KEY elevator**, boarded from **B2F** (B1F's elevator door sits behind its own guard door), so
the leg is: take the key, climb out, ride back down (`_pt_hideout_lift_key`/`_pt_hideout_ride_to_b4f`).
The door grunts have **view range 0** — walking past never engages them — so the bot talks them into
their fights (`_pt_talk_npc`/`_pt_fight_trainer`).

The **`pokeflute` stage** follows it (`--pokeflutetest [--tower]` PASS from Celadon): back east through
the Route 7-8 Underground Path to Lavender (`_pt_celadon_to_lavender`, the mirror of the `erika`
crossing), then up the **Pokémon Tower** — the 2F rival ambush and 6F's MAROWAK are *coordinate*
triggers rather than doors, and both sit on cells you cannot walk around ((15,5) is the only link
between 2F's halves; (10,16) is the only cell leading to the 7F stairs) — past the three Rockets holding
**MR.FUJI** on 7F, who sends you home for the **POKé FLUTE**. This taught the navigator one new trick:
**an item ball is a solid sprite, so a ball left in a corridor is a door whose key is the item**. Tower
6F's **RARE CANDY (6,8)** sits on the single-tile passage into the entire southern half of the floor
(verified: our blocks match pokered's `.blk` byte-for-byte, and `object_event 6, 8, SPRITE_POKE_BALL`),
so a real player *must* take it to reach 7F. `_pt_walk_dungeon` now clears a blocking ball the same way
it clears a blocking guard (`_pt_take_blocking_item`), and when it truly gives up it names the objects in
the way (`_pt_report_blocked`) instead of just printing a cell — see [decisions.md](decisions.md) ADR-012
for why the bot clears obstacles *by kind* rather than proving which one is the articulation point. The
climb runs under the persistent-player whiteout-retry, like Erika's.

The **`snorlax` stage** spends that flute (`--snorlaxstage` PASS): Lavender → Route 12 → wake and beat
the **SNORLAX** asleep across the road (10,62) → Routes 13/14/15 → **Fuchsia**, the next gym town. Two
new navigation facts came out of it, both of which bite a human the same way:
- **A gate house can be the road.** Route 12's north wall and Route 15's midpoint are sealed; the only
  way past is *through* the building, in one door and out the other. Both doors are `LAST_MAP`, so
  `_pt_warp_out`'s "first matching warp" walks straight back out the way it came — `_pt_warp_via` steps
  onto one **specific** warp cell instead.
- **Not every row of a map connection leads anywhere.** Route 13's west edge lines up with Route 14's
  **row-6 pocket**: a one-tile corridor with a BIRD KEEPER standing in it who faces *down*, so his sight
  line never touches you and he never steps aside. Walk straight across and you can only back out.
  `_pt_cross(dir, budget, prefer)` now names the row to leave by. `--rtprobe` gained a matching report —
  for each edge it lists the cells that are actually **crossable** (the cell beyond, on the neighbour,
  is walkable) and which of those the flood reached, which is what distinguishes "I reached the edge"
  from "I can leave by it".

The **`koga` stage** takes the fifth badge (`--kogastage` PASS): Fuchsia Gym's *invisible walls* turn out
to be ordinary collision, so the guard-aware walk threads the maze, clears its six sight-trainers, and
beats **KOGA** at (4,10) for the **SOULBADGE** (+ TM06) — the badge that lets SURF be used outside battle.
Walking to a named door now sets `avoid_warps`, since Fuchsia's doors share a row and a plain walk to the
gym trips the Pokémon Center's first. (`--gymtest` teleports to each leader, so it never exercised gym
navigation on foot; this is the first time Koga's maze has been walked.)

The **`safari` stage** buys both remaining field HMs (`--safaristage` PASS): pay the ¥500, wind through
the park to the **SECRET HOUSE** for **HM03 (SURF)**, take the **GOLD TEETH** (West, 19,7), and trade them
to the **WARDEN** for **HM04 (STRENGTH)**; both are then taught. Three things it settled:
- **The park's areas are a loop, not a hub** (`--rtprobe`). From the Center's entrance only the **East**
  door is reachable; East reaches North, North reaches West. The Center's *own* west door opens into a
  126-cell pocket that leads nowhere but back into West — so the way out is to retrace, not to take the
  nearest door.
- **Encounters inside the park are BALL/BAIT/ROCK/RUN**, so the battle policy runs rather than fighting
  (a safari mon never holds you — `TryRunningFromBattle`). Running out of the park's 500 steps only costs
  another ¥500, and every leg is guarded on what's already held, so a cut-short trip resumes.
- **Only the Squirtle line can carry SURF here.** Charizard learns CUT and STRENGTH but not SURF or FLY
  in Gen 1, and the run's starter is SQUIRTLE (`_pt_stage_opening`) — so Blastoise takes both HMs.
  `_pt_teach_cut` generalised into `_pt_teach_hm(hm, move)`.

The **`saffron` stage** walks back north and through the drink gate (`--saffronstage` PASS; `--drink` runs
just the Celadon half): Fuchsia → Route 15's gate → Routes 14/13 climbed north (leaving Route 14 by row 8)
→ Route 12's gate → Lavender → the Underground Path → **Celadon**, five flights up the Mart to the
**rooftop vending machines** for a drink, then east to **Route 7's gate**, whose thirsty guard takes it —
one drink opens all four — and out into **Saffron**. Route 7's east edge is walled but for that gate house,
and both its doors are `LAST_MAP`, so the east one drops you back onto Route 7 *past* the wall. The vending
machine reopens itself for another can (`_vending_buy`), so the bot has to cancel out of it; otherwise the
modal never clears and every later walk stalls waiting on it.

The **`silph` stage** liberates Silph Co and opens Saffron Gym (`--silphstage` PASS; `--card` runs just the
key leg). Silph Co is a **teleport-pad maze**, not an elevator ride: the lift serves every floor without a
key (`SilphCoElevatorFloors`) and reaches **neither** place that matters. The route was derived on the real
collision + object data with every trainer treated as a permanent wall — a beaten one stays where it
stopped, so it never frees the cell it was blocking — which means the leg needs no luck:
- The **CARD KEY** (5F, ball at 21,16) sits in a row-16 corridor whose west door is held by a **range-1**
  ROCKET (8,16) — sight 1 means he never marches, so he is a wall forever — and whose east end is the
  one-wide column 28, with another ROCKET at (28,4) plugging it. You cannot walk in from either side. The
  way in is to **arrive**: ride to **9F**, take its pad at (17,15), and it drops you on **5F (9,15)**,
  *inside* the corridor. A warp you land on is inert until you leave it, so you step south off it, walk
  east to (20,16), and face the ball. Stepping back north onto (9,15) — armed again — returns you to 9F.
- **11F's elevator landing (13,0) does not reach GIOVANNI.** It reaches 52 cells: the top corridor and
  the 10F stairs (9,0). Giovanni (6,9) is behind the floor's one card-key door, block **(3,6)** (locked
  `0x20`, open `0x3`), whose wall cells are (6,13)/(7,13) — face it from (6,14).
- The only way into that half is the pad **`7F (5,7) → 11F (3,2)`**, and **7F's pad room is sealed off
  from the rest of 7F** (its walls hold no door). You land in it from **3F's pad (11,11)**, which is
  itself behind 3F's card-key door, block (8,4). Crossing the room trips the **rival ambush** at (3,3),
  exactly as `SilphCo7F.asm` intends.

So the route is: 1F → lift **9F** → pad → 5F **CARD KEY** → pad back → lift **3F** → open (8,4) → pad →
**7F** → pad → **11F** → open (3,6) → **GIOVANNI**. Each floor's door table lives in its adapter, and
`_pt_walk_dungeon` opens the doors itself once the key is in the bag — the **third obstacle kind**
alongside guards and item balls (ADR-012). A door is a *block*, not a sprite, and **which of its four
cells is the wall differs per floor** (`facility` `0x54` walls its top pair, `0x5F` its right pair;
`interior` `0x20` its bottom pair), so the bot looks it up rather than assuming.

That leg surfaced **two more engine bugs**, both of which a human would have hit — and one of them was a
hard softlock on the critical path:
- **Silph Co could not be entered on foot** (gh #79, fixed). Its Saffron door (18,21) has exactly one
  approach cell, (18,22), and `SAFFRONCITY_ROCKET8` stands on it. pokered clears him on the **Pokémon
  Tower rescue** — `PokemonTower7FMrFujiText` hides ROCKET8 and shows the sleeping ROCKET9 one cell east
  — not on Giovanni. The port ran neither toggle and kept every Rocket until `BEAT_SILPH_CO_GIOVANNI`,
  who is *inside*. Saffron Gym is gated the same way (ROCKET3 stands on (34,4), its doorway), so
  everything from Sabrina onward was walled off. `--silphtest` warps straight in, so it never surfaced.
- **The Rocket Hideout could not be reached on foot** (gh #89, fixed). `bg_event 9, 4` is the Game Corner
  poster — a **wall tile** whose only walkable neighbour is (9,5) — and `object_event 9, 5, SPRITE_ROCKET,
  STAY, UP, …, OPP_ROCKET, 7` stands on it, facing the poster, so he never engages on sight and must be
  talked to. `toggleable_objects.asm` ships him ON; `GameCornerRocketBattleScript` walks him off and
  `GameCornerRocketExitScript` hides him, both only after his battle. The port's `GameCorner.gd` modelled
  the poster switch, the hidden staircase, the slots and the coin clerks — and nothing about him — so
  `EVENT_FOUND_ROCKET_HIDEOUT` was unsettable and the SILPH SCOPE, the Pokémon Tower and everything past
  them were sealed. Fixed through the existing `object_shown` / `on_battle_end` hooks. `--silphscopetest`
  never saw it because it **pre-set `FOUND_ROCKET_HIDEOUT`**: the gh #84 pattern one level up — a setup
  line that hands a stage its own goal state makes every assertion after it vacuous. Found by the first
  continuous seeded run to ever walk this leg.
- **Cerulean Cave was sealed forever** (gh #90, fixed). `CERULEANCITY_SUPER_NERD3` STAYs on (4,12), the
  only land cell touching the cave door at (4,11) (you SURF up to him). `HallOfFame.asm` hides him
  (`HideObject TOGGLE_CERULEAN_CAVE_GUY`) once you are recorded as CHAMPION; the port never did, so MEWTWO
  was unreachable. One clause in `CeruleanCity.gd`, keyed on the `HALL_OF_FAME` event the ceremony already
  sets. **`tools/audit_chokepoints.py`** makes that whole family a permanent check, the way
  `tools/audit_places.py` did for `place()`: for every warp, sign and item ball on every map it reports
  when *all* the walkable cells adjacent to it are occupied by a solid sprite, and separately when a
  sprite is a cut vertex sealing off a whole region. It re-derives gh #79 and gh #89 from scratch and
  found gh #90; reviewed hits (Mt. Moon's fossils, both SNORLAX, the Victory Road boulders, the Warden's
  boulder, Silph 5F's CARD KEY corridor) are silenced by name with a reason, so it exits 0 and can gate.
- **Warps fire on any step** (gh #80, **FIXED** — landed with #105 on `feature/gh105-tile-pair-collisions`).
  `_warp_should_fire` mirrors `CheckWarpsNoCollision`: warp immediately only on a tileset door/warp tile
  (`IsPlayerStandingOnDoorTileOrWarpTile`, ported from `{warp,door}_tile_ids.asm`), else require
  `ExtraWarpCheck` (fn1 facing the map edge / fn2 warp-tile-in-front per map/tileset). So Silph 11F's plain
  `(5,5)` mat no longer ejects you (the president + MASTER BALL are reachable on foot), and a Center mat you
  arrive on doesn't bounce you. fn2 at a map edge reads the **border block** (`_feet_tile_or_border`), which
  is how the S.S. Anne / cabin / Vermilion Dock edge-exits fire; horizontal gate houses and the Silph
  elevator fire from the door-facing cell, and the bot turns to that facing on arrival. Full chained gate
  re-verify (NEW GAME → HALL OF FAME, seed 1) stayed green.
- **Tile-pair (elevation) collisions** (gh #105, #128, **FIXED**). `_tile_pair_blocked`
  (`CheckForTilePairCollisions`, `data/tilesets/pair_collision_tile_ids.asm`) blocks a step between two
  walkable cells at different elevations (cavern floor↔ledge, water↔shore surfing); boulder pushes get
  pokered's own push check (`CheckForCollisionWhenPushingBoulder`, player-tile↔destination + stairs). Caves
  fracture into ladder-linked pockets; the bot's dungeon routes were re-derived (Victory Road became a real
  multi-floor boulder/switch/hole puzzle solved by `tools/vrdyn.py`). See
  [engine/collision.md](engine/collision.md) and `docs/notes/gh105-victory-road.md`.

The **`sabrina` stage** takes the sixth badge (`--sabrinastage` PASS; `--pads` runs just the pad chain).
Saffron Gym is nine sealed rooms in a 3×3 grid, and its **entire warp table is 30 self-warps**
(`data/maps/objects/SaffronGym.asm`) — the only way between rooms is a teleport pad. Its door is clear
only once GIOVANNI has fallen (`SAFFRONCITY_ROCKET3` stands on (34,4)), so `silph` gates it. SABRINA has
**view range 0**, so she is talked to, not walked into. Derived on the real pad graph with every trainer
a permanent wall: from the door at (8,17), the pads `(11,15) → (15,15) → (15,5) → (1,5)` land on
**(11,11)**, the one pad inside her room. `_pt_take_pad` reads each landing off the map's own warp table
rather than a second copy, and steps onto the pad from a neighbouring cell — a pad warps *within* the
map, so no map change fires to signal arrival.

**Next up — the sea, and `blaine`.** The bot can now **SURF**: `_pt_use_field_move` drives the real party
field-move submenu (so the badge gate and the "It can't be used here." refusal run for real),
`_pt_surf_on` mounts from a shore cell, and `--surfnavtest` PASSes Fuchsia → Route 19 → **across the
connection into Route 20, still afloat**. Two facts fell out while deriving it:
- **Route 20's sea is split in two.** Walls at column 43 (rows 2–13) and column 62 (rows 10–16) fence the
  Seafoam Islands landmass across the middle, and the halves share no water (our `.blk` is byte-identical
  to pokered's). The only crossing is the islands' two Route-20 doors — and on **Seafoam 1F those doors
  sit in disconnected regions**, so it descends into B1F. Seafoam is on the road to Cinnabar, not beside it.
- **The open-water approach is Pallet Town → Route 21**, a single water component end to end. That is the
  `blaine` route, and it is **walked**: `_pt_fly_to` drives the two menus FLY needs (party submenu → the
  `visited_fly` town list), and `_pt_reach_cinnabar` flies home, mounts Pallet's beach at (4,13), and
  swims Route 21's 90 cells to Cinnabar's north shore (`--cinnabarnavtest` PASS).

**The SECRET KEY is walked (gh #85, fixed).** `--secretkeytest` PASSes: from Cinnabar's street, in the
front door, 1F → 2F → 3F, flip 3F's panel, **fall through the western balcony** into 1F's sealed south,
down to B1F, flip its south panel then its north one, take the key, and out by the back door. The route
was derived on the real collision + warp + **hole** graph with the switch state carried through, and the
panels turn out **not to be interchangeable** — B1F's north one seals B1F's own staircase, so the walk out
is not the walk in (`_pt_mansion_flip_for` presses a panel, looks, and presses it back if it did not
help).

The **`blaine` stage** then takes the seventh badge (`--blainestage` PASS; `--gym` skips the mansion).
Cinnabar Gym is six rooms that snake back on themselves, each sealed by a **quiz gate** — the machines are
`hidden_events.asm` wall panels, pressed from below facing UP. A right answer opens that room's gate for
good; a wrong one and the room's trainer jumps you. Because the rooms snake, the order is forced: the only
machine you can reach is the next one. The bot answers off the same `HIDDEN_EVENTS` row the engine reads,
as a player with a guide would, and `_pt_answer_quiz` wins the fight anyway if an answer ever misses.

Two bugs sat between the bot and the VOLCANOBADGE:
- The Pokémon Mansion's switches were **unpressable** (gh #83, fixed). Each is a **wall panel**, keyed off
  the *faced* tile per `hidden_events.asm`'s `SPRITE_FACING_UP`, but all four adapters tested the player's
  own cell — and every switch cell is solid. `--mansiontest` teleported the player *inside the wall* to
  press them, so it passed.
- **Hole tiles were not implemented at all** (gh #85, fixed). Gen 1 drops you a floor when you step on a
  hole — a **dungeon warp**. They are *not* found by scanning tiles: each map's script carries an explicit
  coord list and picks the destination floor from the matched index (`PokemonMansion3FDefaultScript`'s
  `.holeCoords` + `IsPlayerOnDungeonWarp`), with the landing cell in `DungeonWarpData`
  (`data/maps/special_warps.asm`). 3F's **western balcony drops to 1F (16,14)**, and that is the *only*
  entrance to 1F's southern half, which holds the Scientist, the CARBOS and the **stairs down to B1F**.
  Verified in-engine before the fix: with the switch OFF *and* with it ON, the flood from the front door
  never reached (21,23). So the SECRET KEY was unobtainable, the Cinnabar Gym door never unlocked, and
  BLAINE's badge could not be won. Now: `Cutscene.fall_down_hole` + a `dungeon_hole` adapter helper, wired
  on `PokemonMansion3F.on_step`; verified by `--holetest` (both drops, plus "a non-hole burnt tile does
  nothing"). **Still to wire:** `DungeonWarpList` also covers Seafoam Islands B1F–B4F — the port has
  those only as the boulder-drop special case, never as something the *player* falls through. (Victory
  Road 3F's hole is wired now — see the `victoryroad` stage below.)

`--rtprobe` gained **`--event NAME`**, which sets a story event before the map loads, so a floor whose
`on_enter` lays blocks from an event (a mansion switch, a Silph card-key door) can be probed in both
states. That is what settled the question above.

And it surfaced the worst engine bug so far:
- **Surfing across a map connection was impossible** (gh #82, fixed). `_is_water` only consulted the
  **center** map — `_tile_at` returns `-1` off it — while `_cell_walkable` resolves a neighbour's
  collision, where water is solid. So the sea ended at every map edge. `load_world` also cleared
  `surfing` unconditionally, though it runs on a connection rebase too. **Cinnabar Island has no dry
  connection**, so BLAINE's badge, the Pokémon Mansion, the SECRET KEY and the fossil lab were all
  unreachable — a critical-path softlock. `--surftest` mounts and dismounts inside one map and
  `--seafoamtest` moves by warp, so nothing had ever surfed across a connection.

The **`giovanni` stage** takes the eighth badge (`--giovannistage` PASS). Viridian Gym is badge-locked:
`ViridianCityCheckGymOpenScript` keeps the door shut until you hold every *other* badge, then
`VIRIDIAN_GYM_OPEN` latches for good — the port had no check at all, so the EARTHBADGE could be taken
before Brock (gh #86, fixed). The turn-away is a **simulated PAD_DOWN**, and the tile below the door
step is a **down-ledge**, so the refusal hops you back onto the street — `MapScripts.step_back_down`
now reproduces that idiom (Route 23's checkpoints use it too). Inside, the gym is a spin-tile maze
(`spin_aware`), and GIOVANNI has view range 0 — talked to, not walked into.

The **`victoryroad` stage** climbs to the League (`--victoryroadtest [--r23|--cave]` PASS end-to-end).
Route 23 is a river with a footpath at each end — walk, SURF the middle 32 rows, walk — and its only
door is **Route22Gate**, which surfaced its own softlock (gh #87, fixed): it is the one gate house in
Kanto entered from two *different* maps, and all four of its doors are `LAST_MAP` warps, so pokered
re-picks `wLastMap` by which half of the building you stand in (`wYCoord < 4` → ROUTE_23). The port
had no such rule — both doors led back where you came from, and Route 23, Victory Road, and the whole
League were unreachable on foot. Victory Road itself is a figure-of-eight: 2F's ladder lands you in a
sealed 71-cell west pocket whose only exit is the door its switch1 opens (the lone boulder in the
pocket is the answer — `_pt_push_boulder`, the **fourth obstacle kind** after guards, item balls and
card-key doors, but *aimed* rather than merely cleared); 2F's exit pair sits in a 13-cell pocket
reachable only from **3F's east pocket**, itself reachable only from 2F's (25,14) ladder
(`_pt_take_ladder` pins each leg to its intended landing — four ladders per floor means "the map
changed" is not "arrived"). Faithfulness that landed with it: **Route 23 re-arms the boulder puzzle**
on entry (`Route23SetVictoryRoadBoulders` — switches cleared, 3F's boulder restored, 2F's hidden
again), 2F clears 1F's switch on load, **3F's hole** now drops the *player* to 2F (22,16) — the
`cavern $22` dungeon warp, previously boulder-only — and a boulder shoved into it vanishes and
reappears on 2F one row below (the toggleable-boulder pair).

The **`elite4` stage** ends the run (`--elite4stage [--gauntlet]` PASS): lobby → LORELEI → BRUNO →
AGATHA → LANCE → the CHAMPION → the **HALL OF FAME**. The gauntlet rule is real, not a mood:
`IndigoPlateauLobby_Script` wipes the whole Indigo Plateau event range the moment you walk back down
mid-challenge (`BIT_STARTED_ELITE_4`, armed when Lorelei's room loads), so all four stand back up —
the bot heals and shops *once* on the way in, runs the five fights without leaving, and on a whiteout
restarts from LORELEI as a player would. It also surfaced the port's last walled-off softlock
(gh #88, fixed): **Lance's room ships its entrance doorway closed** in the static `.blk` —
`LanceShowOrHideEntranceBlocks` opens it on every load until `EVENT_LANCES_ROOM_LOCK_DOOR` latches
(stepping into the hall slams it behind you) — so LANCE, the CHAMPION and the HALL OF FAME were
unreachable on foot; `--elitetest` never saw it because it `place()`s beside each opponent (the
gh #84 pattern again). Two more walk-arounds closed with it: LANCE engages by **coordinate** (view
range 0 — (5,1)/(6,2) start the fight), and beating AGATHA arms `SCRIPT_CHAMPIONSROOM_PLAYER_ENTERS`,
so the Champion's room now marches you into the final battle as you enter — without those, both could
simply be walked past to the stairs.

**Stage seams are their own bug class (gh #76).** A stage verified in isolation proves nothing about the
seam from the *previous* stage's checkpoint end-state: the isolated tests start the bot outdoors, but a
real stage ends wherever its last milestone happened — usually inside a gym, behind a CUT tree the next
map load regrows. Five seams broke this way and are fixed. `surge` and `erika` end inside their gyms, so
the plaza trees now cut from either side; the `erika` checkpoint puts the bot on Erika's platform behind
the gym's *interior* tree at (5,7), a 16-cell pocket holding no door at all; `sabrina` ends in her
pad-sealed room, so `blaine` rides the derived exit chain out (pads are **directed** — the way out is not
the way in reversed); and `giovanni` ends on Viridian Gym's arrow floor, so `_pt_warp_out` now always
plans spin-aware. **Cerulean City is cut in two by a one-way ledge:** the gym side — Pokécenter, mart,
gym door, the Route 4 and Route 24 edges — is *entered* over the down-ledges at (32..34,18) and can never
be left that way, and it reaches neither Route 5 nor Route 9. A Rock Tunnel whiteout respawns in that
Pokécenter, so the retry has to cross back through the Rocket-trashed house (27,11 → the back-wall hole →
27,9) exactly as a player would. `--surgenavtest --route9` drives that recovery off a real `whiteout()`,
with no `place()` past the geometry.

**Everything the isolated tests were quietly handing the stages (gh #91, #92, #94, #95).** The continuous
run is the only thing that has ever held the real state, and it found six softlocks in a row that way — a
`place()` past the geometry (gh #84), a pre-set event (gh #89), a hand-made bag (gh #91), a Blastoise with
a spare move slot (gh #92), a hand-made team and wallet (gh #94), and a party that already knew FLY
(gh #95). Concretely: pokered's bag holds **20 distinct items** and a 21st ball is refused on the floor, so
the hoarding bot never got the GOLD TEETH; the only mon in its party that can carry SURF or STRENGTH is a
Blastoise whose four slots are full by L40, so `_pt_teach_hm` has to drive the real LearnMove forget prompt;
**nothing ever went for HM02**, whose Route 16 house is walled off behind a single **CUT tree at (34,9)**
(the fence is solid, the gate house's two passages are disconnected inside, and the SNORLAX and BICYCLE are
both red herrings); and the bot routes *around* trainers, so it arrives at Silph Co at L41 and at Route 22's
**second rival ambush** — six mons, a L53 Venusaur, armed by the eighth badge — at L53, and loses both. It
now grinds on Route 7 and on **Route 18** (418 exp a fight; most route grass turns out to be fenced off from
its own entrance, Route 15's included), never switches a L19 bench mon into a L40 leader, and buys HYPER
POTIONs rather than 50-HP SUPER POTIONs for a lead with 205 HP.

**The headless gate could never have passed (gh #99 #103).** `Cutscene.ss_anne_departs` sets
`cutscene_active = true`, then awaits `RenderingServer.frame_post_draw` so it can screen-grab the strip of
water it sails the ship across. Under `--headless` nothing draws, that signal is never emitted, and the
coroutine **suspends forever** — the ship never leaves, the gangway steps and the warp into Vermilion never
run, and the player stands on the dock at (14,2). Nothing is printed: a suspended coroutine is not a crash,
so there is no `SCRIPT ERROR` to grep for. This is the long-standing "S.S. Anne dock strand", blamed twice
on other things (gh #96, then RNG) because every `--from=ssanne` replay that *passed* was run windowed
through `tools/run.ps1`. **The ADR-011 Stage-1 gate is headless by definition**, so no continuous run has
ever got past `ssanne`. `tools/audit_headless.py` now forbids the pattern outside the `*test`/`*shot`
debug drivers, and is verified red on the offending commit. The general lesson, and it is not confined to
this project: *an `await` on a signal the main loop never emits is an invisible softlock*, and the
absence of an error message is not evidence of health.

**Two bugs in the bot's own walking verbs (gh #99), both hidden by a retry loop.** `_pt_step` budgets its
waits in *frames*, at counts written for a 60 fps game — but `_playthrough` runs at `Engine.max_fps = 500`,
where the 0.08 s turn-in-place tween takes exactly the 40 frames the turn budget allowed, so the key was
released mid-turn and the step never happened. And `_pt_walk_to` returned `true` on `player.cell == goal`
*above* its `if modal == battle` branch, so a step that lands on the goal returns with a wild battle still
on screen. Neither is visible through `_pt_walk_to`, which has a stuck-counter and simply retries.
`_pt_cross` takes exactly **one** step to cross a map edge — no retry, no diagnostic — so whether a
crossing worked came down to which way the walk's last step happened to face, and whether the edge cell's
grass rolled an encounter. Route 1's south edge is grass, and the first two NEW GAME runs died on it two
stages in. The budgets scale with the frame rate now, `_pt_settle()` clears the screen before a crossing,
and `_pt_cross` retries and *reports*. The lesson generalises past the bot: **a `--from=<stage>` replay
that passes where the continuous run failed has exonerated nothing** — it rolled the encounter elsewhere.

The `sabrina` leg surfaced a third bug, this one cosmetic but glaring:
- **Mr. Mime had no sprite** (gh #81, fixed). He is SABRINA's second Pokémon (`SabrinaData`), so the
  sixth gym leader has always sent out an invisible mon. pokered stores his artwork as `mr.mime.png` /
  `mr.mimeb.png` — the only files under `gfx/pokemon/` that aren't a bare species key — and
  `build_battle()`'s `if f.exists()` guard turned the mismatch into a **silent skip**, shipping 150 of
  151 sprites. The extractor now maps the name and **raises** if any species lacks a front or back
  sprite. `--gymtest` fights Sabrina and still passed, because a null texture is only a *draw* error:
  Godot logs it every frame and runs on.

An earlier leg surfaced **two more engine bugs**, both of which a human would have hit:
- **Script-placed doors didn't reopen until you left and came back.** pokered's `EndTrainerBattle`
  (`home/trainers.asm`) sets `BIT_CUR_MAP_LOADED_1`, re-running the map's load callback the instant a
  trainer battle ends. The port only ran `on_enter` on map load, so the Rocket Hideout B1F/B4F guard
  doors and the **Lorelei/Bruno/Agatha exit seals** stayed shut after their guard fell — and those E4
  rooms have no other exit, so it read as a softlock. Fixed with an eighth map-script hook,
  `on_battle_end()` (see [engine/map-scripts.md](engine/map-scripts.md)); verified by `--rockettest`
  / `--e4test`.
- **The B4F LIFT KEY and SILPH SCOPE balls were visible from the start.** `toggleable_objects.asm`
  ships both **OFF**: the LIFT KEY appears only when the beaten Rocket 3 admits he dropped it
  (`ROCKET_DROPPED_LIFT_KEY` → `ShowObject`), the SILPH SCOPE only when Giovanni steps aside. The port
  showed both on load, so either could be pocketed without the fight that gates it. Fixed in
  `RocketHideoutB4F.gd` + `Cutscene.giovanni_hideout`, with `show_object`/`hide_object` added to the
  adapter vocabulary; verified by `--rockettest`.

**Pokédex tracking** is in: enemies are marked *seen* when they appear in battle, and the party +
PC box fold into *owned* (`Main.pokedex_seen`/`pokedex_owned`, saved); the POKéDEX start-menu entry
shows a **scrolling list** of all 151 in dex order (name once seen, `*` once owned, `----` unseen;
`build_dex` → `dex_order.json`). Verified by `--dextest`.

The reusable cursor **menu now scrolls** (`Menu.MAX_VISIBLE` window with ^/v arrows), so long lists
— bag, mart, PC box, party, the dex — no longer overflow the screen. Verified by `--scrolltest`.

The start-menu name entry now shows a **trainer card** (`Main._trainer_card`: name, money, badge
count, Pokédex tally) — the one place gym badges surface to the player.

**The Day Care** is in: the Route 5 Day-Care man takes a party mon (`Cutscene.daycare_man` →
`Main._daycare_deposit`); it earns 1 EXP per overworld step, and withdrawal recomputes its level/stats
from EXP and charges `(levels_grown + 1) × ¥100` (`level_for_exp`). Saved. (The Gen-1 daycare
move-learning quirk is intentionally omitted.) Verified by `--daycaretest`.

**TM teaching** is in: selecting a TM in the bag teaches its move (`Main.tm_moves`, the
ordered `add_tm` map from `extract.py`) to a compatible party mon — `tmhm`-checked like HMs, but
**single-use** (the TM is consumed). The gym TMs (TM34/TM11/TM24/TM21) are now usable.
Verified by `--tmtest`.

**Game Corner slots** are in: the Celadon Game Corner slot machines (`Main.SLOT_SEATS`; three seats
are out of order / out to lunch / someone's keys) run a faithful minigame (`SlotMachine.gd`) — bet
1-3 coins for 1/3/5 paylines, stop three reels with A, win on a line of matching symbols
(7=300, BAR=100, cherry=8, Pokémon=15). Each spin is rigged before it runs (SlotMachine_SetFlags:
mostly no-win, sometimes a normal match, rarely a 7/BAR jackpot), and the third reel rolls to the
rigged outcome. Coins (`player_coins`, capped 9999, saved) come from the coin clerk (50 for ¥1000),
the fishing guru (10 once), and wins; the COIN CASE is from the Celadon Diner gambler. Verified by
`--slottest`; rendered by `--slotshot`.

**Game Corner prize room** is in: the three prize counters (`GameCornerPrizeRoom`, bg_events at
(2,2)/(4,2)/(6,2)) exchange coins for the RED prizes (`Cutscene._PRIZES` from data/events/prizes.asm
+ prize_mon_levels.asm) — two Pokémon counters (ABRA/CLEFAIRY/NIDORINA, DRATINI/SCYTHER/PORYGON at
their fixed levels) and a TM counter (DRAGON RAGE/HYPER BEAM/SUBSTITUTE). Prizes overflow to the box
when the party is full; broke buyers are refused (`Cutscene.prize_vendor`/`give_prize`). Verified by
`--prizetest`.

**Saffron drink-gate** is in: the four Saffron gate buildings (Route5/6/7/8 Gate, which the routes'
walled edges force you through) have a thirsty guard at fixed coords (`Main.SAFFRON_GATES`) who
blocks + pushes you back until handed a Celadon drink (FRESH WATER / SODA POP / LEMONADE); one drink
sets `GAVE_SAFFRON_GUARDS_DRINK` and opens all four (`_saffron_guard`). Verified by `--saffrontest`.

**Safari Zone** is in: the gate (`Cutscene.safari_gate`, gating the `SAFARI_ZONE_CENTER` warp) charges
¥500 for **30 SAFARI BALLs + a 500-step game** (`in_safari`/`safari_balls`/`safari_steps`, saved);
encounters become a dedicated **BALL/BAIT/ROCK/RUN** battle (`Battle.start_safari` — bait halves the
catch rate & reduces flee, rock doubles it & raises flee, the mon may run, no fighting). The menu is
the faithful `SAFARI_BATTLE_MENU_TEMPLATE` (gh #169): **one full-width box** (0,12..19,17) reading
`BALL×nn     BAIT` / `THROW ROCK  RUN` with the ball count printed *inside the menu* at tile (7,14)
(core.asm `.safariLeftColumn`), cursor columns x=1/x=13 — no separate on-screen counter; the step
counter ticks down (`_on_player_moved`) and time-out ends the game (`Cutscene.safari_game_over`).
Time-out is a *sequence*, not a teleport (gh #171): `SafariZoneGameOver` rings the PA jingle and reads
the announcement out, and only then sets `wSafariZoneGameOver` — the flag that makes `OverworldLoop`
take `WarpFound2` — so the eject is the closing beat. "Time's up!" is skipped when no BALLs remain.
Running out of BALLs ends the game too (gh #180): the last BALL ends the encounter on the spot
(`.outOfSafariBallsText`), and the same ceremony fires the moment you're back on the overworld
(`SafariZoneCheck`, farcalled every `OverworldLoop` iteration).
At the gate, `SafariZoneGateLeavingSafariScript` lands you at the park-side door facing down, the
worker signs you out, your BALLs go back, and you're walked 3 south.
Verified by `--safaritest` + `--safaribattletest`.

**Silph Co** is in: the **Card Key** (5F item ball); the **Saffron rival** on 7F (`Cutscene.silph_rival`,
OPP_RIVAL2 party 7/8/9); a grateful worker's **Lapras** gift (7F); **Giovanni #2** on 11F
(`giovanni_silph`, OPP_GIOVANNI party 2, flees when beaten); and the **president's MASTER BALL**
(`silph_president`, after Giovanni). Verified by `--silphtest`. Also fixed: **rival battle parties are
now keyed by the rival's starter** (the counterpart of the player's), matching `wRivalStarter`
(`_rival_st()`) — the SS Anne/Cerulean/Tower/Champion fights previously used the player's starter.
**Card-key doors are now in** (the earlier "dead-end" was wrong): the doors aren't in the static
`.blk` at all — each floor's `GateCallbackScript` *places* them on load with `ReplaceTileBlock`
(blocks `0x54`/`0x5F`, whose feet tiles are the `0x18`/`0x24` walls), keyed by **block** coords.
`Main.SILPH_DOORS` reproduces every floor's door placements; the load hook lays the locked blocks
(unless the door's `SILPH_DOOR_<floor>_<bx>_<by>` event is set), and facing one with the CARD KEY
swaps it for open floor (`0xE`, or `0x3` on 11F) and sets the event so it stays open
(`_is_silph_door` + the interact handler). Verified by `--cardkeytest`.

**Fly** is in (completing all five HMs): **HM02** from the Route 16 house girl
(`Cutscene.fly_house_girl`); using FLY (party menu, Thunder-gated, outdoors) opens a menu of the
towns you've **visited** (`visited_fly`, tracked on map load; `FLY_DESTS` spawn coords from
`FlyWarpDataPtr`) and warps you there (`Main._open_fly_menu`/`_fly_to`), with the full BIRD
animation (gh #144, `Cutscene.fly_transition` — `player_animations.asm`'s flap-in-place, the
top-right swoop, the high right-to-left pass, and the arrival dive, on pokered's own screen-coord
lists at Delay3 cadence; the map music waits for the landing). Verified by `--flytest`.

**The Elite Four + Champion** are in: the four members (Lorelei/Bruno/Agatha/Lance) battle through
the generic trainer system as you walk up to them in their rooms; the **Champion** is the rival
(the authored `event:champions_room_battle`/`_entrance` records since wave C questline 7,
OPP_RIVAL3 party by starter). Beating him runs the full ceremony
(gh #179, `ChampionsRoom.asm` + `HallOfFame.asm`): the rival's two defeat texts, **OAK arrives**
(voice first, then ShowObject at the south door + the UP×5 walk to the pair), congratulates the
player naming the **starter**, scolds the rival, "Come with me!", exits north and the player
follows up the left column around the rival (the sim-joypad RLE plays in reverse, gh #182) onto the (3,0) door —
into the **HALL_OF_FAME map**, up beside Oak at the machine for the Er-hem speech (the Cerulean
cave guard stands down here, gh #90), then the team registration (`Cutscene.hall_of_fame` — each
mon's sprite/name/level + the HoF theme) and the staff-credits roll. Post-credits, faithfully:
the League **resets for a rematch** (`Main.reset_elite4_gauntlet(true)` — champion included),
`respawn_map` becomes Pallet, the game **saves itself**, THE END holds for a button, and the boot
replays to the **title screen** — CONTINUE resumes on the Hall of Fame floor. **The game is
completable end-to-end.** Verified by `--elitetest` / `--elite4stage`.

**Strength** is in: the Fuchsia **Warden** trades the **GOLD TEETH** (a Safari Zone item ball) for
**HM04** (`Cutscene.warden_strength`); using STRENGTH (party menu, Rainbow-gated) sets
`strength_active`, and then walking into a **boulder** shoves it one tile if the space beyond is
clear (`Main.try_push_boulder`, hooked into `Player`). Verified by `--strengthtest`. Surf + Strength
make Victory Road navigable.

**Surf** is in: **HM03** comes from the Safari Zone secret-house guru (`Cutscene.safari_surf_guru`);
teaching SURF and using it (party field-move menu) while facing water hops the player onto the water
(`surfing`, Soul-Badge-gated) — `is_walkable` makes water passable only while surfing, stepping onto
land dismounts, and wild encounters use the per-map **water** table while surfing. While afloat the
player wears the **SEEL sheet** (gh #170) — `LoadSurfingPlayerSpriteGraphics` loads `SeelSprite`, Gen
1's actual surfing player — via the same `Player._sheet` swap as the BICYCLE (gh #161); dismounting
reloads the walking sheet on the spot (`.stopSurfing` calls `LoadPlayerSpriteGraphics`). Verified by
`--surftest`. (Water tables verified complete against pokered by the gh #176 parity audit — the sea routes share
the TENTACOOL table, everything else genuinely has none.)

**Snorlax** is in: using the **POKé FLUTE** while facing a road-blocking SNORLAX wakes it into a
catchable L30 battle (`Cutscene.wake_snorlax`); beating/catching it clears the route
(`BEAT_SNORLAX_<map>`, generic `_object_shown`). Used elsewhere the flute cures party sleep.
Verified by `--snorlaxtest`. This opens the routes south to Fuchsia.

**Pokémon Tower → Poké Flute** is in: the restless **MAROWAK ghost** on 6F (coord 10,16) is gated by
the SILPH SCOPE — with it you fight MAROWAK L30 (`Cutscene.marowak_ghost`), without it the ghost
blocks you; **Mr. Fuji** on 7F is rescued and warps you to his house (`mr_fuji_tower`), where he
hands over the **POKé FLUTE** (`mr_fuji_flute`; he's hidden at home until rescued). Verified by
`--towerghosttest`.

**Rocket Hideout → Silph Scope** is in: the Celadon Game Corner **poster switch** (`interact` at
(9,4)) reveals the hidden staircase (`set_block` + a `_blocked_cells` guard so the warp can't be
reached while walled); the B1F-B4F floors are navigable (spin-tile arrows are walkable) with Rocket
grunts via the trainer system; **Giovanni** (`Cutscene.giovanni_hideout`) guards the **SILPH SCOPE**
and steps aside when beaten; the Silph Scope + Lift Key are picked up as ordinary item balls. Verified
by `--hideouttest`. The once-deferred refinements have all landed since: the spin-tile arrow floors
(`--spintest`), the guard doors (B1F single-grunt with its every-entry-clunk asm bug, B4F two-grunt
with the one-shot unlock event), and the **elevators** (v0.9.22) — all three (Rocket Hideout with
the LIFT-KEY gate, Celadon Mart, Silph Co) run pokered's real system: the door warps lead back to
the boarding floor until the panel's floor list retargets them, with the ShakeElevator ride (camera
judder + collision clacks + the Safari-PA ding). The Silph elevator's static map data ships broken
(UNUSED_MAP_ED) doors, so the runtime retarget is what makes it usable at all.

**Playtest fixes (faithfulness pass):** the lab rival now shows his line on contact (the battle is
positional); the **item PC** (`<PLAYER>'s PC`) is in via a faithful two-level PC menu; Oak now leads
the player to his lab in **lockstep** (`Cutscene.walk_together`); the **starter's sprite** shows
during selection (`pic()`); mart/Center clerks are **talk-across-counter** (extracted `counter_tiles`
per tileset) and the parcel script stands the player in front of the counter, not on it. In-battle
ANTIDOTE/POTION confirmed (antidote cures, potion = flat 20). Hidden items + item balls verified
complete in extraction (53 + 104; gift-mon balls like Eevee/Hitmons remain bespoke future events).

**In-battle item use** is in: the battle ITEM menu now handles the full set faithfully —
healing potions (all tiers; FULL RESTORE also cures status), status heals (per-status + FULL HEAL),
and X-stat boosters (+1 stage) — each consuming the turn, with ineffective uses refused without
consuming (`Battle._use_item`). Verified by `--battleitemtest`.

**The Bicycle** is in: the Vermilion Pokémon Fan Club chairman gives the **BIKE VOUCHER**
(`Cutscene.fan_club_chairman`), the Cerulean **Bike Shop** trades it for the **BICYCLE**
(`bike_shop_clerk`), and using it outdoors toggles 2x movement (`Main._toggle_bike`,
`Player.step_scale`; cleared indoors). Verified by `--biketest`.

**Celadon vending machines** are in: facing a roof vending machine opens a drink-buy menu
(FRESH WATER / SODA POP / LEMONADE, `Main._open_vending`) — the drinks the Saffron gate guards want.
Verified by `--vendingtest`.

**Fishing** is in (all three rods): the Vermilion guru gives the **OLD ROD**
(`Cutscene.old_rod_guru`), the Fuchsia guru's older brother the **GOOD ROD** (`good_rod_guru`), and
the Route 12 brother the **SUPER ROD** (`super_rod_guru`). Using a rod from the bag while facing a
water/shore tile (`Main._use_rod` / `_rod_encounter`, mirroring `item_effects.asm`) hooks a wild mon:
OLD ROD always MAGIKARP L5; GOOD ROD ~⅓ bite, GOLDEEN/POLIWAG L10; SUPER ROD per-map fishing groups
(`Main.SUPER_ROD_GROUPS`/`SUPER_ROD_MAPS` from data/wild/super_rod.asm). Verified by `--fishtest` +
`--rodtest`.

**Seafoam Islands** are fully in: a STRENGTH boulder shoved onto a hole cell (`Main.SEAFOAM_HOLES`,
per floor) falls to the floor below — removed for good (`FELL_<key>` flag) and setting the floor's
`*_DOWN_HOLE` event (`try_push_boulder`). Once those events are set, the **B4F strong currents**
(`SEAFOAM_CURRENTS`) sweep a surfing player along the original forced routes (`_seafoam_current` →
`Cutscene.walk_forward`, dir/count sequences from the RLE lists): the B2F-boulder landing current
pushes you up out of the fall spot, the B3F-boulder crossing current carries you up-and-right toward
Articuno. `walk_forward` respects walls so a current can never strand you. Verified by `--seafoamtest`
+ `--seafoamcurrenttest`.

**Route 22 rival** is in (bug fix — he was appearing prematurely): the rival objects at (25,5) are
hidden (`_object_shown`) until his battle is armed and the player reaches the trigger (29,4/29,5) —
battle 1 while `GOT_POKEDEX && !BEAT_BROCK`, battle 2 at 8 badges (`_on_player_moved` →
`Cutscene.route22_rival`). He walks in from the west, battles (OPP_RIVAL1/2, party by rival starter),
and leaves. Verified by `--route22test`. Also: the **ledge hop** now cycles the walk frames across the
whole arc (`Player._ledge_jump`) instead of holding one frame.

**UI audit** (rendered every menu vs Gen 1): start menu / PC menu / battle are faithful. Fixed: the
**POKéMON menu** now draws HP-bar rows (name/level + HP bar + cur/max HP + status) via a party mode
on `Menu` (`open_party`/`_draw_party`), used by all four party flows; the **bag** gained its `CANCEL`
entry. Verified by `--partytest`; rendered by `--uishot`. Still stylised vs Gen 1 (noted for later):
the Pokédex is a flat list (no ● caught markers / entry pages), the trainer card is a textbox rather
than a badge card, party menu icons aren't drawn, and the mon submenu lacks SWITCH.

**Rocket Hideout guard doors** are in (audit fix): the B1F door (`Main.ROCKET_DOORS`) stays a wall
until Rocket 5 falls, and the B4F door guarding Giovanni until *both* its guards do
(`DoorCallbackScript`, gated on `defeated_trainers`). The static `.blk` left both open, so the grunt
gates were skippable. Verified by `--rockettest`.

**Elite Four exit seals** are in (a faithfulness-audit fix): each of Lorelei/Bruno/Agatha's rooms
seals its forward exit (`Main.E4_EXITS` — a locked door block + the exit-warp cells added to
`_blocked_cells`) until that member is beaten (`defeated_trainers`), then opens it — mirroring each
room's `ShowOrHideExitBlock`. This was **missing** because the doors are script-placed, not in the
`.blk`: the static defaults left **Lorelei softlocked** (exit walled even after winning) and **Bruno
skippable** (exit open without fighting). Lance's forward path is guarded by Lance himself. Verified
by `--e4test`.

**Route 23 badge gate** is in: the seven `Main.ROUTE23_GATES` checkpoints (cell-row Y → badge) block
you northward toward the Indigo Plateau unless you hold the matching badge (Cascade at the south end
through Earth at the north), turning you back south with the original text (`_on_player_moved`); Y=35
only gates the west side (X<14), per `scripts/Route23.asm`. Verified by `--route23test`.

**Victory Road boulder switches** are in: each floor has a floor switch (`Main.VICTORY_SWITCHES`)
that, when a STRENGTH boulder is shoved onto it (`try_push_boulder`), sets an event and opens that
floor's door block (`set_block`) — re-applied on load so it stays open. This is the puzzle that
gates the path to the Indigo Plateau. Verified by `--victorytest`. (The cross-floor switch reset and
the secondary boulder-holes are simplified to per-floor permanent opens.)

**Pokémon Mansion + Cinnabar Gym** are in: the mansion's switches (`Main.MANSION_SWITCHES`, faced
UP) toggle a shared `MANSION_SWITCH_ON` flag that swaps each floor's gate/floor blocks on load and on
press (`MANSION_BLOCKS` / `_apply_mansion_blocks` / `_mansion_switch`, mirroring
PokemonMansion*.asm). The **SECRET KEY** is the B1F item ball; the Cinnabar Gym door warp is gated on
it (`_do_warp`, "The door is locked..."). Verified by `--mansiontest`.

**Fossils** are in: take one of the Mt. Moon B2F fossils (DOME or HELIX — `Cutscene.mtmoon_fossil`,
the other becomes unreachable) and the Pewter Museum **OLD AMBER** (`give_old_amber`); the Cinnabar
Lab fossil scientist (`revive_fossil`) takes a fossil, then — after you leave to Cinnabar Island and
return (which clears `LAB_STILL_REVIVING_FOSSIL`) — revives it into KABUTO/OMANYTE/AERODACTYL L30
(`Main.fossil_mon`, saved). Verified by `--fossiltest`.

**Gift Pokémon** are in: the **Eevee** ball on the Celadon Mansion roof (`gift_mon_ball`, L25), the
Fighting Dojo's **Hitmonlee/Hitmonchan** prize (`hitmon_gift` — pick one, the other vanishes, no
seconds), and the Mt. Moon Pokécenter **Magikarp salesman** (`magikarp_salesman`, L5 for ¥500). All
add to the party or overflow to the box (`Cutscene._receive_mon`). Verified by `--gifttest`.

**Static legendaries** are in: Articuno (Seafoam B4F), Zapdos (Power Plant), Moltres (Victory Road
2F) and Mewtwo (Cerulean Cave B1F) spawn from their map's `object_event` species+level args — the
generic stationary-mon path (`NPC.wild_species`/`wild_level`, set in `Main._spawn_npcs` when an
object's "opp" arg is a species rather than `OPP_*`). Interacting starts a catchable wild battle
(`Cutscene.static_encounter`); defeating or catching it sets `CAUGHT_STATIC_<map>_<x>_<y>` (keyed by
position, so per-sprite) and it never respawns (`Battle.caught` now also flags a successful ball). The
same path enables the Power Plant's disguised **Voltorbs/Electrodes** (6×VOLTORB L40, 2×ELECTRODE
L43). Verified by `--legendtest`.

**Pokémon Tower rival battle** (4th story rival fight) is in: the rival stands on Tower 2F and
stepping beside him ((15,5)/(14,6)) starts the battle (OPP_RIVAL2, party 4/5/6 by starter), then he
leaves (`Cutscene.tower_rival`). Verified by `--towertest`.

**Flash** is in: dark caves (Rock Tunnel etc., `Main.DARK_MAPS`) render under a dim overlay
(`darkness` ColorRect); a party **field-move menu** (`_open_mon_menu`) lets a mon use **FLASH**
(badge-gated) to light the area (`flash_lit`, reset on leaving), or **CUT** a tree in front — the tree
plays the Gen-1 collapse animation (`_cut_tree_anim`, `AnimCut`) before it's gone. **HM05**
comes from the Route 2 Oak's Aide at ≥10 species (`Cutscene.oaks_aide_flash`). Verified by
`--flashtest`.

Remaining: the later gym leaders (Fuchsia/Koga onward — gated by Cycling Road/Snorlax/Surf and the
Saffron/Silph web), the Silph Scope → Pokémon Tower ghosts / Mr. Fuji → Poké Flute → Snorlax chain,
Surf/Strength traversal, per-move attack SFX, low-HP alarm, the spotlight-vs-dim nicety.

**Map-script seam (gh #53) — complete:** all ~80 scripted maps live behind `MapScripts.gd`'s
seven-hook interface — one adapter per scripted map in `game/scripts/maps/`, 1:1 with pokered's
`scripts/<Map>.asm` (see [engine/map-scripts.md](engine/map-scripts.md), ADR-010). Main's
per-map dispatch chains and all ~24 gimmick tables are gone (one adapter call per touchpoint);
every family migration was guarded by its `--flag` selftests. The sweep also surfaced and fixed
two pre-existing harness stalls (oaktest's StarterDex screen, _drive_bill's naming screen) —
gifttest/fossiltest now pass for the first time since the nickname-offer wave. New #22 beats
land directly as adapters.

## Backlog / discovered sub-tasks

- **Faithful battle-screen polish** (current battle UI is a functional approximation, not a
  pixel-accurate match of pokered): bordered HUD boxes, the ground platforms under each mon,
  "HP:" label + colored/length-accurate HP bar, name/level placement at pokered's tile coords,
  the FIGHT/PKMN/ITEM/RUN box split + move/PP/type sub-window, and battle animations
  (sprite slide-in, attack FX, HP-bar drain tween, the encounter intro transition).


- ~~Extractor: 2 maps skipped~~ ✅ fixed — all **223** maps extract now. `UndergroundPathNorthSouth`'s
  header fudges the height (declares 4×24, blk is 4×23), so the extractor trusts the blk when it's a
  clean multiple of the width; `UndergroundPathRoute7Copy` shares the base map's `.blk` (Copy-suffix
  fallback). This restores the Cerulean↔Vermilion underground link. Verified by `--maptest`.
- Engine: door open/close animation + auto step-out on warp arrival.
- Engine: tile-pair collisions (water/land edges) and ledges (one-way jumps).
- Engine: clamp/letterbox camera on maps smaller than the screen (border fills for now).
- Battle (M11): extract moves/types/learnsets and capture Gen-1 formulas in pokemon.md.
