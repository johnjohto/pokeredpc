extends RulesetBattle
class_name Gen1Battle
## The Gen-1 battle module (gh #33, ADR-018 §1, §2). Owns the BATTLE STATE and (as the
## migration proceeds) the mechanics: turn structure, action order, move execution,
## status + residuals, the trainer AI — everything that computes; the Battle host keeps
## presentation (drawing, HUD, animations, the message pump) and consumes the ordered
## event stream the mechanics append (v1's ADR-009 queue is the contract). Battle.gd
## forwards these fields via properties, so presentation, the test harness, and the link
## plumbing read/write the same state they always did. One session at a time (the host
## node is a singleton); a session object can split out when a second sample demands it.

var b        # the Battle host (presentation + the message pump) — set by bind()


func bind(battle) -> void:
	b = battle


# ---- battle state (moved verbatim from Battle.gd, comments riding along) ----

var p_stages: Dictionary
var e_stages: Dictionary
var p_vol: Dictionary
var e_vol: Dictionary
var _eff_re := RegEx.new()

var base_stats: Dictionary
var moves_db: Dictionary

var party: Array = []
var active := 0
var participants: Array = []   # party indices that fought the current enemy (for EXP split)
var learn_move := ""           # move pending the "delete a move?" prompt
var player_mon: Dictionary
var enemy_mon: Dictionary
var enemy_party: Array = []   # trainer battles: enemy's whole team
var enemy_active := 0
var is_trainer := false
var is_safari := false         # Safari Zone battle: BALL/BAIT/ROCK/RUN, no fighting, the mon may flee
var run_attempts := 0          # wNumRunAttempts: each failed try adds 30 to the next escape roll
var newly_caught := false      # this catch is a first-time species (dex entry shows after)
var doll_escape := false       # fled via POKé DOLL: wBattleResult stays 0 (the MAROWAK trick)
# Gen-1 trainer AI (engine/battle/trainer_ai.asm): the class's move-choice modification
# layers, its item/switch handler, and how many uses it gets per mon (wAICount).
var ai_mods: Array = []
var ai_kind := "Generic"
var ai_count_max := 3
var _ai_uses := 0
var _ai_turn := 0              # enemy moves taken (wAILayer2Encouragement)
var ghost := false             # unidentified GHOST (Pokémon Tower, no SILPH SCOPE): can't be fought
var unveil := false            # the scripted MAROWAK: appears as GHOST until the SILPH SCOPE reveal
var safari_bait := 0           # "eating" counter (less likely to flee)
var safari_escape := 0         # "angry" counter (more likely to flee)
var safari_catch := 0          # current (bait/rock-modified) catch rate
var trainer_name := ""
var prize := 0
var won := false              # true once the battle is won (vs blackout)
var caught := false           # true once the enemy mon is caught (a ball succeeded)
var blacked_out := false      # true if the player ran out of usable mons
var no_blackout := false      # story battles (first rival) that heal + continue instead of whiting out
var _flee_pending := false    # Teleport/Whirlwind used in a wild battle
var can_evolve: Array = []   # party indices that leveled this battle (wCanEvolveFlags, gh #67)

# ---- determinism oracle (gh #2, ADR-014) -----------------------------------
# Link battles run deterministic lockstep: both peers simulate the identical battle from a
# shared seed and exchange only chosen actions, so every battle-LOGIC random draw must come
# from this battle-local generator — never the global RNG, which the overworld (NPC wander,
# encounter rolls) advances at frame rate. Each turn appends a canonical event line (turn,
# both actions, the RNG cursor, a state digest) to `det_stream`; byte-equality of two peers'
# streams is the DEFINITION of "in sync" (ADR-014). Verified by --battledettest.
var rng := RandomNumberGenerator.new()
var rng_cursor := 0            # logic draws since battle start (the lockstep "RNG cursor")
var battle_seed := 0           # this battle's seed (a link session fixes it at establishment)
var next_seed := -1            # set before start*() to force the seed (tests/link); -1 = derive
var det_stream: Array = []     # canonical event lines (docs/engine/battle.md "Determinism")
var det_log := false           # echo events to stdout as [battledet] lines (the link soak reads logs)
var turn_no := 0
var _det_paction := "-"        # the player action driving the current turn, canonical form
var _det_eaction := "-"        # the enemy action (in a link battle: the peer's choice)

# ---- link battle (gh #7, ADR-014): deterministic lockstep ------------------
# Both peers run the FULL simulation, each with itself as the "player" side (mirrored, as
# pokered's link battles do), from a shared seed fixed at the table; only chosen actions
# cross the wire. See Battle.gd's link section for the neutralization notes.
var link_battle := false
var link_host := false
var peer_name := ""            # the partner's player name (their trainer label)
var link_actions: Array = []   # the peer's col_act actions, in turn order (fed by Cutscene)
var link_swaps: Array = []     # the peer's col_swap faint replacements, in order
var _link_wait := ""           # "" | "act" (their turn action) | "swap" (their replacement)
var _link_pact := {}           # our pending action while waiting for theirs
var _link_pact_turn := -1      # the turn it was submitted for (gh #13: resume retransmit)
var _link_lswap := -1          # our last faint replacement sent as col_swap, and its turn
var _link_lswap_turn := -1
var _link_elapsed := 0.0
var link_over := false         # set when the link died mid-battle (stakeless end)
