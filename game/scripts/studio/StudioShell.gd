extends Control
class_name StudioShell
## The Studio MVP shell (ADR-020 d1/d2, gh #47): one binary, two faces — Main defers here
## on `--studio`. This increment is the project browser + the content-type sidebar: open a
## project folder (never the extractor-owned game/project in place — the dev/test flows
## copy Kanto to a scratch dir first, by convention), list the four Phase-4 content types,
## and edit their records through the schema-driven form engine. The four focused custom
## widgets land in gh #50; their registry seam is live here already.

## The Phase-4 content types (ADR-020 d3): species/moves/items/trainers; maps stay
## Tiled-external (Phase 5) and events get their own GUI (Phase 5).
const CONTENT_TYPES := ["species", "moves", "items", "trainers"]
const RECENTS_CFG := "user://studio.cfg"

var project_dir := ""
var _path_label: Label
var _status: Label
var _sidebar: ItemList
var _records: ItemList
var _editor_host: ScrollContainer
var _editor_panel: VBoxContainer
var _dialog: FileDialog
var _record_names := {}          # kind -> sorted basenames (the sidebar's data)
var _active_kind := ""
var _active_form: Control = null
var _widget_registry := preload("res://scripts/studio/FormWidgetRegistry.gd").new()


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
	_clear_editor()
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
	_records.custom_minimum_size = Vector2(180, 0)
	_records.item_selected.connect(_on_record_selected)
	split.add_child(_records)
	_editor_host = ScrollContainer.new()
	_editor_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_editor_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(_editor_host)
	_editor_panel = VBoxContainer.new()
	_editor_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_editor_host.add_child(_editor_panel)
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
	_active_kind = CONTENT_TYPES[idx]
	_records.clear()
	for n in _record_names[_active_kind]:
		_records.add_item(str(n))
	_clear_editor()


func _on_record_selected(idx: int) -> void:
	if _active_kind == "" or idx < 0 or idx >= (_record_names[_active_kind] as Array).size():
		return
	edit_record(_active_kind, str((_record_names[_active_kind] as Array)[idx]))


## Public shell seam used by record selection and the Studio smoke suite. Returns the
## mounted SchemaForm, or null after a loud non-fatal refusal.
func edit_record(content_type: String, basename: String):
	if not CONTENT_TYPES.has(content_type):
		_status.text = "REFUSED: unknown content type " + content_type
		return null
	var context := ProjectValidator.editor_context(project_dir, content_type)
	if not bool(context.get("ok", false)):
		_status.text = "REFUSED: " + "; ".join(PackedStringArray(context.get("errors", [])))
		return null
	var path := project_dir.path_join("data").path_join(content_type).path_join(basename + ".json")
	var record = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (record is Dictionary):
		_status.text = "REFUSED: cannot parse " + path
		return null
	_clear_editor()
	var title := Label.new()
	title.text = "%s / %s" % [content_type, basename]
	_editor_panel.add_child(title)
	var actions := HBoxContainer.new()
	_editor_panel.add_child(actions)
	var save := Button.new()
	save.text = "Save"
	actions.add_child(save)
	var revert := Button.new()
	revert.text = "Revert"
	actions.add_child(revert)
	var form := preload("res://scripts/studio/SchemaForm.gd").new()
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_editor_panel.add_child(form)
	form.bind_record(content_type, basename, record, context, _widget_registry)
	form.dirty_changed.connect(func(dirty: bool) -> void:
		title.text = "%s / %s%s" % [content_type, basename, " *" if dirty else ""])
	save.pressed.connect(func() -> void:
		var errors: Array = form.save_record(path)
		_status.text = ("saved %s/%s" % [content_type, basename]) if errors.is_empty() \
			else "REFUSED: " + "; ".join(PackedStringArray(errors)))
	revert.pressed.connect(func() -> void:
		form.revert_record()
		_status.text = "reverted %s/%s" % [content_type, basename])
	_active_form = form
	_status.text = "editing %s/%s" % [content_type, basename]
	return form


func _clear_editor() -> void:
	_active_form = null
	if _editor_panel == null:
		return
	for child in _editor_panel.get_children():
		child.queue_free()


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
	ok = preload("res://scripts/studio/StudioFormSmoke.gd").new().run(self, scratch) and ok
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
