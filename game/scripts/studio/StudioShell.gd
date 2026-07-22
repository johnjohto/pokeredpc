extends Control
class_name StudioShell
## The Studio MVP shell (ADR-020 d1/d2, gh #47): one binary, two faces — Main defers here
## on `--studio`. This increment is the project browser + the content-type sidebar: open a
## project folder (never the extractor-owned game/project in place — the dev/test flows
## copy Kanto to a scratch dir first, by convention), list the four Phase-4 content types,
## and show each type's records. The schema-driven editors land in gh #49/#50; genuine
## dockable panels arrive with them — this shell is the split layout they dock into.

## The Phase-4 content types (ADR-020 d3): species/moves/items/trainers; maps stay
## Tiled-external (Phase 5) and events get their own GUI (Phase 5).
const CONTENT_TYPES := ["species", "moves", "items", "trainers"]
const RECENTS_CFG := "user://studio.cfg"

var project_dir := ""
var _path_label: Label
var _status: Label
var _sidebar: ItemList
var _records: ItemList
var _dialog: FileDialog
var _record_names := {}          # kind -> sorted basenames (the sidebar's data)


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	if "--studiotest" in OS.get_cmdline_user_args():
		_studiotest()
		return
	var want := _project_arg()
	if want != "":
		var err := open_project(want)
		if err != "":
			_status.text = "REFUSED: " + err
			print("[studio] REFUSED: " + err)
	else:
		var recents := _load_recents()
		if not recents.is_empty() and open_project(recents[0]) == "":
			return
		_dialog.popup_centered_ratio(0.7)


## Open a project folder through the same Core loader + refusal path the engine boots with
## (refuse-newer manifest, missing dirs named). Returns "" or the error (shown, never fatal
## — the shell stays up so the creator can pick another folder).
func open_project(dir_path: String) -> String:
	var err := ProjectData.open(dir_path)
	if err != "":
		return err
	project_dir = dir_path
	_path_label.text = dir_path
	_record_names.clear()
	for kind in CONTENT_TYPES:
		var names := ProjectData.records(kind).keys()
		names.sort()
		_record_names[kind] = names
	_refresh_sidebar()
	_save_recent(dir_path)
	_status.text = "project open — %s (%s)" % [
		str(ProjectData.manifest.get("name", "?")), str(ProjectData.manifest.get("ruleset", "?"))]
	return ""


func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var top := HBoxContainer.new()
	root.add_child(top)
	var open_btn := Button.new()
	open_btn.text = "Open project…"
	open_btn.pressed.connect(func() -> void: _dialog.popup_centered_ratio(0.7))
	top.add_child(open_btn)
	_path_label = Label.new()
	_path_label.text = "(no project)"
	_path_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_path_label)
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(split)
	_sidebar = ItemList.new()
	_sidebar.custom_minimum_size = Vector2(180, 0)
	_sidebar.item_selected.connect(_on_type_selected)
	split.add_child(_sidebar)
	_records = ItemList.new()
	_records.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(_records)
	_status = Label.new()
	_status.text = "open a project folder"
	root.add_child(_status)
	_dialog = FileDialog.new()
	_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_dialog.dir_selected.connect(func(d: String) -> void:
		var err := open_project(d)
		if err != "":
			_status.text = "REFUSED: " + err)
	add_child(_dialog)


func _refresh_sidebar() -> void:
	_sidebar.clear()
	_records.clear()
	for kind in CONTENT_TYPES:
		_sidebar.add_item("%s (%d)" % [kind, (_record_names[kind] as Array).size()])
	if _sidebar.item_count > 0:
		_sidebar.select(0)
		_on_type_selected(0)


func _on_type_selected(idx: int) -> void:
	_records.clear()
	for n in _record_names[CONTENT_TYPES[idx]]:
		_records.add_item(str(n))


# ---- the recents list (user://studio.cfg) -------------------------------------------

func _load_recents() -> Array:
	var cfg := ConfigFile.new()
	if cfg.load(RECENTS_CFG) != OK:
		return []
	return cfg.get_value("studio", "recent_projects", [])


func _save_recent(dir_path: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(RECENTS_CFG)
	var recents: Array = cfg.get_value("studio", "recent_projects", [])
	recents.erase(dir_path)
	recents.push_front(dir_path)
	while recents.size() > 8:
		recents.pop_back()
	cfg.set_value("studio", "recent_projects", recents)
	cfg.save(RECENTS_CFG)


func _project_arg() -> String:
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with("--studio-project="):
			return str(a).substr(17)
	return ""


# ---- the gh #47 smoke leg of --studiotest -------------------------------------------

## Headless: copy the repo's Kanto project to a scratch dir (the ADR-020 d2 convention —
## Studio never touches the extractor-owned tree), open it, and assert the sidebar knows
## the four content types with the real counts. Later sub-issues grow this suite
## (write-through, refusal, play-test).
func _studiotest() -> void:
	var ok := true
	var scratch := OS.get_user_data_dir().path_join("studio_scratch")
	if DirAccess.dir_exists_absolute(scratch):
		OS.move_to_trash(scratch)
	var cerr := _copy_dir("res://project", scratch)
	ok = _st_check("scratch copy of the Kanto project", cerr == "", cerr) and ok
	var err := open_project(scratch)
	ok = _st_check("shell opens the scratch project", err == "", err) and ok
	var want := {"species": 151, "moves": 165, "items": 152, "trainers": 47}
	for kind in CONTENT_TYPES:
		var got: int = (_record_names.get(kind, []) as Array).size()
		ok = _st_check("sidebar lists %s = %d" % [kind, want[kind]], got == int(want[kind]),
			"got %d" % got) and ok
	# The refusal path: a bad folder is named, never fatal — the shell stays up.
	var rerr := open_project(scratch.path_join("no_such_dir"))
	ok = _st_check("a bad folder refuses loudly and the shell survives",
		rerr != "" and project_dir == scratch) and ok
	# gh #48 (ADR-020 d2) — canonical write-through: parse + re-serialize every record of
	# the four kinds through CanonJSON and compare against the extractor's raw bytes.
	# BYTE-identical or the writer is wrong; the first mismatch names file + offset.
	var swept := 0
	var bad := ""
	for kind in CONTENT_TYPES:
		var kdir := scratch.path_join("data").path_join(kind)
		for f in DirAccess.get_files_at(kdir):
			if not f.ends_with(".json"):
				continue
			var raw := FileAccess.get_file_as_string(kdir.path_join(f))
			var reser: String = CanonJSON.serialize(JSON.parse_string(raw)) + "\n"
			if reser != raw:
				var at := 0
				while at < mini(raw.length(), reser.length()) and raw[at] == reser[at]:
					at += 1
				bad = "%s/%s differs at offset %d (raw %s vs re %s)" % [kind, f, at,
					raw.substr(maxi(0, at - 12), 24).json_escape(),
					reser.substr(maxi(0, at - 12), 24).json_escape()]
				break
			swept += 1
		if bad != "":
			break
	ok = _st_check("canonical write-through: %d records re-serialize byte-identical" % swept,
		bad == "", bad) and ok
	print("[studiotest] %s" % ("ALL GREEN" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)


func _st_check(name: String, good: bool, detail := "") -> bool:
	print("[studiotest] %s: %s%s" % [name, "PASS" if good else "FAIL",
		"" if good or detail == "" else " — " + detail])
	return good


static func _copy_dir(from: String, to: String) -> String:
	var da := DirAccess.open(from)
	if da == null:
		return "cannot open %s" % from
	DirAccess.make_dir_recursive_absolute(to)
	da.list_dir_begin()
	var f := da.get_next()
	while f != "":
		var src := from.path_join(f)
		var dst := to.path_join(f)
		if da.current_is_dir():
			var e := _copy_dir(src, dst)
			if e != "":
				return e
		else:
			var b := FileAccess.get_file_as_bytes(src)
			var out := FileAccess.open(dst, FileAccess.WRITE)
			if out == null:
				return "cannot write %s" % dst
			out.store_buffer(b)
			out.close()
		f = da.get_next()
	da.list_dir_end()
	return ""
