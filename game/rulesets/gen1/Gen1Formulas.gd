extends RulesetFormulas
class_name Gen1Formulas
## Gen-1's formula kernels, moved verbatim from Battle.gd / Main.gd behind the seam
## (gh #32, ADR-018 §3). NATIVE GDScript, asm-faithful — every step floors like the GB
## divides; the md5 oracle holds these to the byte. RNG-drawing kernels take the battle's
## draw helpers as Callables so the draw ORDER never moves.

# pokered's stat-stage ratio table for accuracy/evasion scaling (MoveHitTest).
const STAGE_MULT := {-6: 0.25, -5: 0.28, -4: 0.33, -3: 0.4, -2: 0.5, -1: 0.66,
	0: 1.0, 1: 1.5, 2: 2.0, 3: 2.5, 4: 3.0, 5: 3.5, 6: 4.0}

# pokered's stat-stage ratios (StatModifier n/100); the modified stat floors and lives in [1, 999].
const STAGE_NUM := {-6: 25, -5: 28, -4: 33, -3: 40, -2: 50, -1: 66,
	0: 100, 1: 150, 2: 200, 3: 250, 4: 300, 5: 350, 6: 400}

const HIGH_CRIT := ["SLASH", "KARATE_CHOP", "RAZOR_LEAF", "CRABHAMMER"]


## Gen-1 stat: floor((base + DV) * 2 * level / 100) + 5  (+ level + 10 for HP).
## CalcStat: floor(((base + DV)*2 + floor(ceil(sqrt(statExp))/4)) * level/100) + 5.
## Stat exp is Gen 1's "EV" pool: every defeated mon's raw base stats accumulate on the
## victors, picked up at the next stat recalc (level-up).
func stat_calc(base: int, level: int, dv: int, is_hp: bool, sexp := 0) -> int:
	var eb := 0
	if sexp > 0:
		eb = mini(255, int(ceilf(sqrt(float(sexp))))) / 4
	var v := int(((base + dv) * 2 + eb) * level / 100.0)
	return v + level + 10 if is_hp else v + 5


func exp_for_level(n: int, growth: String) -> int:
	match growth:
		"GROWTH_FAST": return int(4 * n * n * n / 5.0)
		"GROWTH_SLOW": return int(5 * n * n * n / 4.0)
		"GROWTH_MEDIUM_SLOW": return int(6.0 * n * n * n / 5.0 - 15 * n * n + 100 * n - 140)
		_: return n * n * n   # MEDIUM_FAST (+ unused slightly_fast/slow fallback)


## Highest level whose EXP threshold the mon has reached (inverse of exp_for_level).
func level_for_exp(xp: int, growth: String) -> int:
	var lvl := 1
	while lvl < 100 and exp_for_level(lvl + 1, growth) <= xp:
		lvl += 1
	return lvl


## Gen-1 critical-hit probability (faithful, including the Focus Energy bug).
func crit_roll(base_spd: int, focus: bool, move_name: String, rf: Callable) -> bool:
	var b := int(base_spd / 2)
	if focus:
		b = int(b / 2)                            # BUG: Focus Energy quarters crit chance
	else:
		b = mini(255, b * 2)
	if move_name.replace(" ", "_") in HIGH_CRIT:
		b = mini(255, mini(255, b * 2) * 2)
	else:
		b = int(b / 2)
	return float(rf.call()) < (b / 256.0)


## The damage pipeline's core. Stat SELECTION (crit reads unmodified, screens double,
## EXPLODE halves defense) stays with the battle state; this kernel is GetDamageVars'
## byte-overflow scaling + CalculateDamage, integer-exact: every step floors like the GB
## divides, the quotient caps at 997 and MIN_NEUTRAL_DAMAGE (+2) lands on top — max 999
## (gh #176 phase 2). (pokered can reach a 0 divisor here and freeze; the port clamps
## to 1 instead of hanging.)
func damage_core(level: int, crit: bool, power: int, a_stat: int, d_stat: int) -> int:
	if a_stat > 255 or d_stat > 255:
		a_stat = maxi(1, int(a_stat / 4))
		d_stat = maxi(1, int(d_stat / 4))
	var lvl := level * 2 if crit else level
	var dmg := int((2 * lvl) / 5) + 2
	dmg = int(dmg * power * a_stat / maxi(1, d_stat))
	return mini(int(dmg / 50), 997) + 2


## RandomizeDamage: damage below 2 is not randomized.
func randomize_damage(dmg: int, rr: Callable) -> int:
	if dmg > 1:
		dmg = maxi(1, int(dmg * int(rr.call(217, 255)) / 255.0))
	return dmg


## MoveHitTest byte math — 100% accuracy is 255, rolled against rand(256), so even a
## sure move misses 1/256 of the time (the famous Gen-1 quirk). Accuracy and evasion
## stages scale the byte sequentially, capped at 255. Returns "the move hits".
func accuracy_roll(accuracy: int, acc_stage: int, eva_stage: int, ri: Callable) -> bool:
	var acc := int(accuracy * 255 / 100.0)
	acc = int(acc * float(STAGE_MULT[clampi(acc_stage, -6, 6)]))
	acc = int(acc * float(STAGE_MULT[clampi(-eva_stage, -6, 6)]))
	acc = mini(acc, 255)
	return int(ri.call(256)) < acc


## The modified stat under a stage (StatModifier n/100), floored, clamped to [1, 999].
func stage_apply(base: int, stage: int) -> int:
	return clampi(int(base * STAGE_NUM[clampi(stage, -6, 6)] / 100), 1, 999)


## SPECIAL_DAMAGE_EFFECT's fixed damages (SEISMIC TOSS / NIGHT SHADE / DRAGON RAGE /
## SONICBOOM / PSYWAVE).
func special_damage(move: String, level: int, rr: Callable) -> int:
	match move:
		"SEISMIC_TOSS", "NIGHT_SHADE": return level
		"DRAGON_RAGE": return 40
		"SONICBOOM": return 20
		"PSYWAVE": return max(1, int(rr.call(1, int(1.5 * level))))
	return level


## ItemUseBall's catch algorithm, byte-exact: the ball picks the span and the two ball
## factors, sleep/freeze subtract 25 (other status 12), the wobble count comes from the
## x·y/255 composition. Returns {caught, shakes}.
func catch_attempt(ball: String, status: String, rate: int, hp: int, maxhp: int,
		ri: Callable) -> Dictionary:
	if ball == "MASTER BALL":
		return {"caught": true, "shakes": 3}
	var span := 256
	var bf := 12
	var bf2 := 255
	if ball == "GREAT BALL":
		span = 201; bf = 8; bf2 = 200
	elif ball in ["ULTRA BALL", "SAFARI BALL"]:
		span = 151; bf2 = 150
	var r1 := int(ri.call(span))
	r1 -= 25 if status in ["slp", "frz"] else (12 if status != "" else 0)
	if r1 < 0:
		return {"caught": true, "shakes": 3}
	var x := int(maxhp * 255 / bf) / maxi(1, int(hp / 4))
	if r1 <= rate:
		if x > 255 or int(ri.call(256)) <= x:
			return {"caught": true, "shakes": 3}
	var y := rate * 100 / bf2
	if y > 255:
		return {"caught": false, "shakes": 3}
	var z := mini(x, 255) * y / 255 + (10 if status in ["slp", "frz"] else (5 if status != "" else 0))
	return {"caught": false, "shakes": 0 if z < 10 else (1 if z < 30 else (2 if z < 70 else 3))}
