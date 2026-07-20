extends RefCounted
class_name RulesetBattle
## The battle-module interface (ADR-018 §1): `battle state + chosen actions → an ordered
## stream of battle events` — v1's ADR-009 message/marker queue is this contract already;
## the engine's presentation consumes the stream and never computes mechanics. The Gen-1
## trainer AI lives INSIDE gen1's battle module (ADR-018 §2) — no separate AI interface
## until a second sample demands one. gh #33 migrates turn structure, action order,
## status + residuals, forced moves, and the AI behind this interface, pinning the
## method signatures as they land (link battles run through the seam on both peers).
