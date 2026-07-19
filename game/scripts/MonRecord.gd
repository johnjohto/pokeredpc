extends RefCounted
## The MON RECORD codec (gh #4, ADR-014): the versioned wire schema for one exchanged
## Pokémon. Translation to/from the engine's internal index-based mon dict happens ONLY
## here, at the link boundary — engine internals are untouched, and v2's Core inherits this
## record as its serialized state model (ADR-013). Stable string IDs (`species:…`, `move:…`),
## explicit fields, and a format version; a fixture dict is a valid peer message by
## construction, so the codec is fully testable single-process (--monrecordtest).
## Field-by-field spec: docs/data-formats/mon-record.md.

const SCHEMA := "mon/1"
const STATUSES := ["", "psn", "par", "slp", "brn", "frz"]

var main                       # Main: mon_base / mon_moves / make_mon / recompute_stats


## Internal mon dict -> wire record. The hp DV is not sent: Gen 1 derives it from the low
## bits of the other four, and decode re-derives it — an illegal combination can't travel.
func encode(mon: Dictionary) -> Dictionary:
	var moves: Array = []
	for mv in mon["moves"]:
		moves.append({"id": "move:" + str(mv["move"]), "pp": int(mv["pp"]),
			"maxpp": int(mv["maxpp"])})
	var dvs: Dictionary = mon["dvs"]
	var sexp: Dictionary = mon["sexp"]
	return {
		"schema": SCHEMA,
		"species": "species:" + str(mon["species"]),
		"nickname": str(mon["name"]),
		"level": int(mon["level"]),
		"exp": int(mon["exp"]),
		"hp": int(mon["hp"]),
		"status": str(mon["status"]),
		"sleep": int(mon["sleep"]),
		"dvs": {"atk": int(dvs["atk"]), "def": int(dvs["def"]),
			"spd": int(dvs["spd"]), "spc": int(dvs["spc"])},
		"stat_exp": {"hp": int(sexp["hp"]), "atk": int(sexp["atk"]), "def": int(sexp["def"]),
			"spd": int(sexp["spd"]), "spc": int(sexp["spc"])},
		"moves": moves,
		"ot": str(mon.get("ot", main.player_name)),
		"trainer_id": int(mon.get("otid", main.player_id)),
	}


## Wire record -> {"ok": true, "mon": <internal dict>} or {"ok": false, "error": <why>}.
## Every failure is a clean refusal naming the field — a malformed peer message must never
## crash the receiving game. Stats are rebuilt from base stats + level + DVs + stat exp
## (never trusted off the wire); hp is clamped to the rebuilt maxhp.
func decode(rec) -> Dictionary:
	if not rec is Dictionary:
		return _err("record is not a dictionary")
	if str(rec.get("schema", "")) != SCHEMA:
		return _err("unknown mon record schema '%s' (ours: %s)" % [rec.get("schema", "?"), SCHEMA])
	# species
	var sid := str(rec.get("species", ""))
	if not sid.begins_with("species:"):
		return _err("species id '%s' is not a species:… id" % sid)
	var species := sid.substr(8)
	if not main.mon_base.has(species):
		return _err("unknown species '%s'" % species)
	# scalars
	var level = _int_in(rec, "level", 1, 100)
	var exp = _int_in(rec, "exp", 0, 0x7fffffff)
	var hp = _int_in(rec, "hp", 0, 999)
	var sleep = _int_in(rec, "sleep", 0, 7)
	var tid = _int_in(rec, "trainer_id", 0, 65535)
	for e in [level, exp, hp, sleep, tid]:
		if e is String:
			return _err(e)
	if not rec.get("nickname") is String or str(rec["nickname"]) == "" \
			or (str(rec["nickname"]) as String).length() > 10:
		return _err("nickname must be a 1-10 character string")
	if not rec.get("ot") is String or str(rec["ot"]) == "" \
			or (str(rec["ot"]) as String).length() > 10:
		return _err("ot must be a 1-10 character string")
	if not str(rec.get("status", "?")) in STATUSES:
		return _err("unknown status '%s'" % rec.get("status", "?"))
	# dvs / stat exp
	if not rec.get("dvs") is Dictionary:
		return _err("dvs missing")
	var dvs: Dictionary = {}
	for k in ["atk", "def", "spd", "spc"]:
		var v = _int_in(rec["dvs"], k, 0, 15)
		if v is String:
			return _err("dvs." + v)
		dvs[k] = v
	# the Gen-1 derived hp DV: low bit of each of atk/def/spd/spc
	dvs["hp"] = ((int(dvs["atk"]) & 1) << 3) | ((int(dvs["def"]) & 1) << 2) \
		| ((int(dvs["spd"]) & 1) << 1) | (int(dvs["spc"]) & 1)
	if not rec.get("stat_exp") is Dictionary:
		return _err("stat_exp missing")
	var sexp: Dictionary = {}
	for k in ["hp", "atk", "def", "spd", "spc"]:
		var v = _int_in(rec["stat_exp"], k, 0, 65535)
		if v is String:
			return _err("stat_exp." + v)
		sexp[k] = v
	# moves
	if not rec.get("moves") is Array:
		return _err("moves missing")
	var mlist: Array = rec["moves"]
	if mlist.size() < 1 or mlist.size() > 4:
		return _err("moves must hold 1-4 entries (got %d)" % mlist.size())
	var move_ids: Array = []
	var pps: Array = []
	var maxpps: Array = []
	for m in mlist:
		if not m is Dictionary or not str(m.get("id", "")).begins_with("move:"):
			return _err("move entry without a move:… id")
		var mc := str(m["id"]).substr(5)
		if not main.mon_moves.has(mc):
			return _err("unknown move '%s'" % mc)
		if move_ids.has(mc):
			return _err("duplicate move '%s'" % mc)
		# maxpp travels EXPLICITLY: a real save's maxpp can legitimately differ from the
		# current move table (a move taught under an older extraction; PP Ups, if ever
		# modelled) — deriving it refused real parties (the VAPOREON/BLIZZARD playtest
		# bug). Bounded by Gen 1's absolute ceiling: 40 base + 3 PP Ups = 64.
		var maxpp = _int_in(m, "maxpp", 1, 64)
		if maxpp is String:
			return _err("move %s: %s" % [mc, maxpp])
		var pp = _int_in(m, "pp", 0, maxpp)
		if pp is String:
			return _err("move %s: %s" % [mc, pp])
		move_ids.append(mc)
		pps.append(pp)
		maxpps.append(maxpp)
	# rebuild the internal mon: stats always recomputed from base+level+DVs+stat exp —
	# never trusted off the wire (a tampered record can't carry impossible stats).
	var mon: Dictionary = main.make_mon(species, level, move_ids, dvs)
	mon["exp"] = exp
	mon["sexp"] = sexp
	mon["status"] = str(rec["status"])
	mon["sleep"] = sleep if str(rec["status"]) == "slp" else 0
	mon["name"] = str(rec["nickname"])
	mon["ot"] = str(rec["ot"])
	mon["otid"] = tid
	for i in pps.size():
		mon["moves"][i]["pp"] = pps[i]
		mon["moves"][i]["maxpp"] = maxpps[i]
	main.recompute_stats(mon)          # folds the stat-exp sqrt term into the stats
	mon["hp"] = clampi(hp, 0, int(mon["maxhp"]))
	return {"ok": true, "mon": mon}


## Decode a raw wire string (the fixture-message form): JSON parse + decode.
func decode_json(text: String) -> Dictionary:
	var parsed = JSON.parse_string(text)
	if parsed == null:
		return _err("not valid JSON")
	return decode(parsed)


func _err(why: String) -> Dictionary:
	return {"ok": false, "error": why}


## rec[key] as an int within [lo, hi] — JSON numbers arrive as floats, so integral floats
## are accepted. Returns the int, or a String describing the refusal.
func _int_in(rec: Dictionary, key: String, lo: int, hi: int):
	var v = rec.get(key)
	if v is float and v == floorf(v):
		v = int(v)
	if not v is int:
		return "%s must be an integer" % key
	if v < lo or v > hi:
		return "%s out of range (%d not in %d..%d)" % [key, v, lo, hi]
	return v
