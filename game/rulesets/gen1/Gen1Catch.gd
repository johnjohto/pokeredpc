extends RulesetCatch
class_name Gen1Catch
## The Gen-1 catch module (gh #34, ADR-018 §1): one ball attempt is ItemUseBall's
## byte-exact algorithm — the arithmetic lives in the formula layer (Gen1Formulas.
## catch_attempt); this module is the seam the engine's catch flow calls through.
## Safari bait/rock CATCH-RATE transitions live here too (safari_zone.asm): bait
## halves the working rate, a rock doubles it (cap 255).

var rset: Ruleset   # the owning ruleset, set by Gen1Ruleset.configure


func attempt(ball: String, status: String, rate: int, hp: int, maxhp: int,
		ri: Callable) -> Dictionary:
	return rset.formulas.catch_attempt(ball, status, rate, hp, maxhp, ri)


func bait_rate(catch_rate: int) -> int:
	return catch_rate >> 1                 # bait halves the catch rate


func rock_rate(catch_rate: int) -> int:
	return mini(255, catch_rate * 2)       # a rock doubles the catch rate