extends RefCounted
class_name ProjectData
## v2 Core (gh #25, ADR-017 d4): loads a PROJECT directory and serves the engine the exact
## v1-shaped dictionaries it has always consumed — the runtime's data source becomes the
## project, while the internals keep their positional/const forms until the Phase-2
## ruleset seam migrates them. `open()` runs once at boot: the manifest gate (integer
## `format`, linear migrations, refuse-newer NAMING both versions), then every record
## collection is read and reconstructed. `legacy(name)` answers by the old asset filename
## ("moves.json", "tilesets/gym.json", ...), `map_json`/`map_exists` serve the interim
## maps. Reconstruction is the exact inverse of build_project() in tools/extract.py —
## verified field-for-field by `--projparitytest` against the legacy files, with two
## documented exceptions (emission filters dead pokered data: Mew's UNUSED TM padding,
## the UnusedMart/UnusedBikeShop stock).

const SUPPORTED_FORMAT := 1

static var dir := ""                  # the opened project directory ("" = not opened)
static var manifest: Dictionary = {}
static var _legacy := {}              # old asset filename -> reconstructed data


static func open(project_dir: String) -> String:
	## Returns "" on success, else the error to show. Idempotent per dir.
	if dir == project_dir and not _legacy.is_empty():
		return ""
	var m = _read_json(project_dir.path_join("manifest.json"))
	if not (m is Dictionary) or m.is_empty():
		return "no project at '%s' (manifest.json missing or unreadable — run tools/build.ps1)" % project_dir
	var fmt := int(m.get("format", 0))
	if fmt > SUPPORTED_FORMAT:
		return "project format %d; this build supports format %d — update the engine" % [fmt, SUPPORTED_FORMAT]
	if fmt < 1:
		return "project manifest has no valid integer format"
	# (linear migrations 1->2->... apply here once format 2 exists; format 1 loads as-is)
	dir = project_dir
	manifest = m
	_legacy = {}
	_build_legacy()
	return ""


static func legacy(name: String):
	## The data that res://assets/<name> used to hold, rebuilt from the project.
	## Returns a DEEP COPY: v1's _load_json parsed fresh per call site, so two consumers
	## of the same table never shared a dict — mutation semantics must not change (gh #25).
	if not _legacy.has(name):
		push_error("[project] no legacy data '%s'" % name)
		return {}
	var v = _legacy[name]
	return v.duplicate(true) if (v is Dictionary or v is Array) else v


static func ruleset_config() -> Dictionary:
	## The data/ruleset.json record (ADR-018 §4, gh #34): {base, config}. Absent file ->
	## {} (the ruleset falls back to its built-in faithful defaults).
	var rc = _read_json(dir.path_join("data/ruleset.json"))
	return rc if rc is Dictionary else {}


static func map_exists(label: String) -> bool:
	return FileAccess.file_exists(dir.path_join("maps/%s.json" % label))


static func map_json(label: String):
	## Fresh parse per call, exactly like the res://assets _load_json it replaces — a
	## reload must reset any runtime mutation of the map dict (set_block doors etc.).
	return _read_json(dir.path_join("maps/%s.json" % label))


# --- reconstruction (the inverse of build_project) ----------------------------------

static func _build_legacy() -> void:
	var species := _read_records("data/species")
	var moves := _read_records("data/moves")
	var items := _read_records("data/items")
	var trainers := _read_records("data/trainers")

	var base := {}
	var dex_entries := {}
	var cries := {}
	var icons := {}
	for key in _ordered_keys(species):
		var r: Dictionary = species[key]
		var types: Array = []
		for t in r["types"]:
			types.append(_type_const(t))
		if types.size() == 1:
			types.append(types[0])            # v1 stores Gen-1 mono-type doubled
		var evos: Array = []
		for e in r.get("evolutions", []):
			match str(e["method"]):
				"level":
					evos.append(["EVOLVE_LEVEL", str(int(e["level"])), _bare(e["into"]).to_upper()])
				"stone":
					evos.append(["EVOLVE_ITEM", _bare(e["item"]).to_upper(), "1",
						_bare(e["into"]).to_upper()])
				"trade":
					evos.append(["EVOLVE_TRADE", "1", _bare(e["into"]).to_upper()])
		var lm: Array = []
		for x in r.get("level_moves", []):
			lm.append([x["level"], _bare(x["move"]).to_upper()])
		base[key] = {"hp": r["stats"]["hp"], "atk": r["stats"]["atk"], "def": r["stats"]["def"],
			"spd": r["stats"]["spd"], "spc": r["stats"]["spc"], "types": types,
			"catch": r["catch_rate"], "base_exp": r["base_exp"],
			"learnset": _bare_upper_list(r.get("start_moves", [])),
			"growth": "GROWTH_" + str(r["growth"]).to_upper(),
			"level_moves": lm, "evolutions": evos,
			"tmhm": _bare_upper_list(r.get("tmhm", []))}
		var d: Dictionary = r["dex"]
		dex_entries[key] = {"cat": d["cat"], "ft": d["height_ft"], "in": d["height_in"],
			"wt": d["weight"], "desc": d["desc"]}
		cries[key] = r["cry"]
		icons[key] = r["icon"]
	var extra_cries := _pres_or_empty("cries_extra.json")
	for k in extra_cries:
		cries[k] = extra_cries[k]
	var order := species.keys()
	order.sort_custom(func(a, b) -> bool:
		return int(species[a]["dex"]["num"]) < int(species[b]["dex"]["num"]))
	_legacy["pokemon/base_stats.json"] = base
	_legacy["dex_entries.json"] = dex_entries
	_legacy["cries.json"] = cries
	_legacy["mon_icons.json"] = icons
	_legacy["dex_order.json"] = order

	var mv := {}
	var msfx := {}
	for key in _ordered_keys(moves):
		var r: Dictionary = moves[key]
		var k: String = str(key).to_upper()
		mv[k] = {"name": r["name"], "effect": r["effect"], "power": r["power"],
			"type": _type_const(r["type"]), "accuracy": r["accuracy"], "pp": r["pp"]}
		if r.has("sfx"):
			msfx[k] = [r["sfx"]["key"], r["sfx"]["pitch"]]
	_legacy["moves.json"] = mv
	_legacy["move_sfx.json"] = msfx

	var names := {}
	var prices := {}
	var tm_moves := {}
	for key in _ordered_keys(items):
		var r: Dictionary = items[key]
		names[key.to_upper()] = r["name"]
		if r.has("price"):
			prices[r["name"]] = r["price"]
		if r.has("tm_move") and str(r["name"]).begins_with("TM"):
			tm_moves[r["name"]] = _bare(r["tm_move"]).to_upper()
	_legacy["items.json"] = names
	_legacy["item_prices.json"] = prices
	_legacy["tm_moves.json"] = tm_moves

	var trs := {}
	var pics := {}
	for key in _ordered_keys(trainers):
		var r: Dictionary = trainers[key]
		var parties: Array = []
		for party in r["parties"]:
			var p: Array = []
			for mon in party:
				p.append({"species": _bare(mon["species"]), "level": mon["level"]})
			parties.append(p)
		trs[key.to_upper()] = {"name": r["name"], "money": r["money"],
			"ai_mods": r.get("ai_mods", []), "ai": r.get("ai", ""),
			"ai_count": r.get("ai_count", 0), "parties": parties}
		if r.has("pic"):
			pics[key.to_upper()] = r["pic"]
	_legacy["trainers.json"] = trs
	_legacy["trainer_pics.json"] = pics

	var ty: Dictionary = _read_json(dir.path_join("data/types.json"))
	var chart := {}
	for atk in ty["chart"]:
		var row := {}
		for d in ty["chart"][atk]:
			row[_type_const(d)] = ty["chart"][atk][d]
		chart[_type_const(atk)] = row
	_legacy["types.json"] = chart

	var enc: Dictionary = _read_json(dir.path_join("data/encounters.json"))
	var wmaps := {}
	for mref in enc["maps"]:
		var w: Dictionary = enc["maps"][mref]
		wmaps[_bare(mref)] = {"grass_rate": w["grass_rate"], "water_rate": w["water_rate"],
			"grass": _enc_pairs(w["grass"]), "water": _enc_pairs(w["water"])}
	_legacy["wild.json"] = {"slots": enc["slots"], "maps": wmaps}

	var mrt: Dictionary = _read_json(dir.path_join("data/marts.json"))
	var marts := {}
	for mref in mrt:
		marts[_bare(mref)] = _bare_upper_list(mrt[mref])
	_legacy["marts.json"] = marts

	var hid: Dictionary = _read_json(dir.path_join("data/hidden_items.json"))
	var hidden := {}
	for mref in hid:
		var spots: Array = []
		for s in hid[mref]:
			spots.append({"x": s["x"], "y": s["y"], "item": _bare(s["item"]).to_upper()})
		hidden[_bare(mref)] = spots
	_legacy["hidden_items.json"] = hidden

	var tr: Dictionary = _read_json(dir.path_join("data/trades.json"))
	var trades: Array = []
	for t in tr["trades"]:
		trades.append({"give": _bare(t["give"]), "get": _bare(t["get"]),
			"nick": t["nick"], "dialogset": t["dialogset"]})
	_legacy["trades.json"] = {"trades": trades, "text_trades": tr["text_trades"]}

	_legacy["text.json"] = _read_json(dir.path_join("data/text.json"))

	# presentation passthroughs keep their v1 names (incl. subdir metadata)
	for name in ["audio.json", "sfx.json", "charmap.json", "credits.json",
			"dungeon_maps.json", "map_music.json", "move_anims.json", "spinners.json",
			"title_intro.json", "title_mons.json", "town_map.json", "trade_gfx.json",
			"warp_rules.json", "sprites/index.json"]:
		_legacy[name] = _read_json(dir.path_join("presentation").path_join(name))
	var tsdir := DirAccess.open(dir.path_join("presentation/tilesets"))
	if tsdir != null:
		tsdir.list_dir_begin()
		var f := tsdir.get_next()
		while f != "":
			if f.ends_with(".json"):
				_legacy["tilesets/" + f] = _read_json(dir.path_join("presentation/tilesets").path_join(f))
			f = tsdir.get_next()
		tsdir.list_dir_end()


## Dict iteration ORDER is behavior (Metronome/Mimic pick over the move table's order —
## the copycat battledet md5 proves it), so records with a `num` (the canonical Gen-1
## table index) reconstruct in num order; without one, sorted by key (v1's base_stats
## order is its alphabetical source-file glob).
static func _ordered_keys(records: Dictionary) -> Array:
	var ks := records.keys()
	ks.sort_custom(func(a, b) -> bool:
		var na = (records[a] as Dictionary).get("num", null)
		var nb = (records[b] as Dictionary).get("num", null)
		if na != null and nb != null:
			return int(na) < int(nb)
		return str(a) < str(b))
	return ks


static func _enc_pairs(pairs: Array) -> Array:
	var out: Array = []
	for p in pairs:
		out.append([p[0], _bare(p[1])])
	return out


static func _bare(id: String) -> String:
	return id.substr(id.find(":") + 1)


static func _bare_upper_list(ids: Array) -> Array:
	var out: Array = []
	for i in ids:
		out.append(_bare(i).to_upper())
	return out


static func _type_const(tid: String) -> String:
	var t := _bare(tid).to_upper()
	return "PSYCHIC_TYPE" if t == "PSYCHIC" else t


static func _pres_or_empty(name: String) -> Dictionary:
	var p := dir.path_join("presentation").path_join(name)
	if not FileAccess.file_exists(p):
		return {}
	return _read_json(p)


static func _read_records(rel: String) -> Dictionary:
	## data/<kind>/*.json -> {basename: record}
	var out := {}
	var da := DirAccess.open(dir.path_join(rel))
	if da == null:
		push_error("[project] missing record dir %s" % rel)
		return out
	da.list_dir_begin()
	var f := da.get_next()
	while f != "":
		if f.ends_with(".json"):
			out[f.get_basename()] = _read_json(dir.path_join(rel).path_join(f))
		f = da.get_next()
	da.list_dir_end()
	return out


static func _read_json(path: String):
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	return JSON.parse_string(f.get_as_text())
