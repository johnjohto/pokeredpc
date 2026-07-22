extends Control
class_name StudioShell
## The Studio MVP shell (ADR-020 d1/d2, gh #47): one binary, two faces — Main defers here
## on `--studio`. This increment is the project browser + the content-type sidebar: open a
## project folder (never the extractor-owned game/project in place — the dev/test flows
## copy Kanto to a scratch dir first, by convention), list the four Phase-4 content types,
## and edit their records through the schema-driven form engine. The four focused gh #50
## widgets register over that engine without creating parallel editor models.

## The Phase-4 content types (ADR-020 d3): species/moves/items/trainers. Phase 5 adds
## native Tiled maps as a specialized workspace; events get their own GUI later in it.
const CONTENT_TYPES := ["species", "moves", "items", "trainers"]
const WORKSPACES := ["species", "moves", "items", "trainers", "maps"]
const RECENTS_CFG := "user://studio.cfg"
const DEFAULT_WINDOW_SIZE := Vector2i(1280, 800)
const MIN_WINDOW_SIZE := Vector2i(900, 600)
const DEFAULT_UI_SCALE := 1.25
const MIN_UI_SCALE := 0.80
const MAX_UI_SCALE := 2.00

var project_dir := ""
var _path_label: Label
var _status: Label
var _playtest_button: Button
var _ui_scale_slider: HSlider
var _ui_scale_label: Label
var _sidebar: ItemList
var _records: ItemList
var _new_map_button: Button
var _editor_host: ScrollContainer
var _editor_panel: VBoxContainer
var _dialog: FileDialog
var _new_map_dialog: ConfirmationDialog
var _new_map_name: LineEdit
var _new_map_width: SpinBox
var _new_map_height: SpinBox
var _new_map_tileset: OptionButton
var _record_names := {}          # kind -> sorted basenames (the sidebar's data)
var _active_kind := ""
var _active_form: Control = null
var _active_map_workspace = null
var _ui_scale := DEFAULT_UI_SCALE


func _ready() -> void:
	_configure_window()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = preload("res://scripts/studio/StudioTheme.gd").build()
	_build_ui()
	if "--studiomapsweeptest" in OS.get_cmdline_user_args():
		_studio_map_sweep_test()
		return
	if "--studiotest" in OS.get_cmdline_user_args():
		_studiotest()
		return
	if "--studio-map-fixture" in OS.get_cmdline_user_args():
		_sidebar.add_item("Maps  1")
		_sidebar.select(0)
		_records.add_item("TestTown")
		_records.select(0)
		preview_map("res://core/fixtures/valid_tmx", "TestTown")
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


## Studio shares a Godot project with the game, but it must not share the game's
## 160x144 pixel-art viewport. Rendering desktop controls into that tiny canvas and
## stretching it 3x clips the project browser to a handful of giant controls (gh #59).
## Disable content scaling before building the UI and give the standalone editor a
## practical, resizable native window; game mode retains project.godot's faithful size.
func _configure_window() -> void:
	var window := get_window()
	window.title = "pokeredpc Studio"
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	window.content_scale_size = Vector2i.ZERO
	_ui_scale = _load_ui_scale()
	window.content_scale_factor = _ui_scale
	window.min_size = MIN_WINDOW_SIZE
	if window.mode == Window.MODE_WINDOWED:
		window.size = DEFAULT_WINDOW_SIZE


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
	_record_names["maps"] = ProjectData.map_labels()
	_refresh_sidebar()
	_clear_editor()
	_save_recent(dir_path)
	_playtest_button.disabled = false
	_status.text = "project open — %s (%s)" % [
		str(ProjectData.manifest.get("name", "?")), str(ProjectData.manifest.get("ruleset", "?"))]
	return ""


func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = StudioTheme.WINDOW
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var top_panel := PanelContainer.new()
	root.add_child(top_panel)
	var top := HBoxContainer.new()
	top_panel.add_child(top)
	var brand := Label.new()
	brand.text = "POKEREDPC  /  STUDIO"
	brand.add_theme_font_size_override("font_size", 17)
	brand.add_theme_color_override("font_color", StudioTheme.TEXT)
	top.add_child(brand)
	var brand_gap := Control.new()
	brand_gap.custom_minimum_size.x = 10
	top.add_child(brand_gap)
	var open_btn := Button.new()
	open_btn.text = "Open project…"
	open_btn.pressed.connect(func() -> void: _dialog.popup_centered_ratio(0.7))
	top.add_child(open_btn)
	_playtest_button = Button.new()
	_playtest_button.text = "Play-test"
	_playtest_button.disabled = true
	_playtest_button.pressed.connect(_on_playtest_pressed)
	top.add_child(_playtest_button)
	_path_label = Label.new()
	_path_label.text = "(no project)"
	_path_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_path_label)
	_ui_scale_label = Label.new()
	top.add_child(_ui_scale_label)
	_ui_scale_slider = HSlider.new()
	_ui_scale_slider.min_value = MIN_UI_SCALE
	_ui_scale_slider.max_value = MAX_UI_SCALE
	_ui_scale_slider.step = 0.05
	_ui_scale_slider.value = _ui_scale
	_ui_scale_slider.custom_minimum_size.x = 130
	_ui_scale_slider.tooltip_text = "Studio interface scale"
	_ui_scale_slider.value_changed.connect(_set_ui_scale)
	top.add_child(_ui_scale_slider)
	_refresh_ui_scale_label()
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(split)
	_sidebar = ItemList.new()
	_sidebar.custom_minimum_size = Vector2(160, 0)
	_sidebar.item_selected.connect(_on_type_selected)
	split.add_child(_sidebar)
	var records_column := VBoxContainer.new()
	records_column.custom_minimum_size = Vector2(190, 0)
	split.add_child(records_column)
	_new_map_button = Button.new()
	_new_map_button.text = "New map…"
	_new_map_button.disabled = true
	_new_map_button.pressed.connect(_show_new_map_dialog)
	records_column.add_child(_new_map_button)
	_records = ItemList.new()
	_records.custom_minimum_size = Vector2(190, 0)
	_records.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_records.item_selected.connect(_on_record_selected)
	records_column.add_child(_records)
	_editor_host = ScrollContainer.new()
	_editor_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_editor_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(_editor_host)
	_editor_panel = VBoxContainer.new()
	_editor_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_editor_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_editor_host.add_child(_editor_panel)
	_status = Label.new()
	_status.text = "open a project folder"
	_status.add_theme_color_override("font_color", StudioTheme.MUTED)
	root.add_child(_status)
	_dialog = FileDialog.new()
	_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_dialog.dir_selected.connect(func(d: String) -> void:
		var err := open_project(d)
		if err != "":
			_status.text = "REFUSED: " + err)
	add_child(_dialog)
	_build_new_map_dialog()


func _refresh_sidebar() -> void:
	_sidebar.clear()
	_records.clear()
	for kind in WORKSPACES:
		_sidebar.add_item("%s  %d" % [kind.capitalize(), (_record_names[kind] as Array).size()])
	if _sidebar.item_count > 0:
		_sidebar.select(0)
		_on_type_selected(0)


func _on_type_selected(idx: int) -> void:
	_active_kind = WORKSPACES[idx]
	_new_map_button.disabled = _active_kind != "maps" \
		or int(ProjectData.manifest.get("format", 1)) < 2
	_records.clear()
	for n in _record_names[_active_kind]:
		_records.add_item(str(n))
	_clear_editor()


func _build_new_map_dialog() -> void:
	_new_map_dialog = ConfirmationDialog.new()
	_new_map_dialog.title = "Create native map"
	_new_map_dialog.ok_button_text = "Create"
	var fields := GridContainer.new()
	fields.columns = 2
	_new_map_dialog.add_child(fields)
	fields.add_child(_dialog_label("Map name"))
	_new_map_name = LineEdit.new()
	_new_map_name.placeholder_text = "MyTown"
	fields.add_child(_new_map_name)
	fields.add_child(_dialog_label("Width (cells)"))
	_new_map_width = SpinBox.new()
	_new_map_width.min_value = 1
	_new_map_width.max_value = 256
	_new_map_width.value = 20
	fields.add_child(_new_map_width)
	fields.add_child(_dialog_label("Height (cells)"))
	_new_map_height = SpinBox.new()
	_new_map_height.min_value = 1
	_new_map_height.max_value = 256
	_new_map_height.value = 18
	fields.add_child(_new_map_height)
	fields.add_child(_dialog_label("Tileset"))
	_new_map_tileset = OptionButton.new()
	_new_map_tileset.custom_minimum_size.x = 240
	fields.add_child(_new_map_tileset)
	_new_map_dialog.confirmed.connect(_create_map_from_dialog)
	add_child(_new_map_dialog)


func _show_new_map_dialog() -> void:
	_new_map_tileset.clear()
	var files := PackedStringArray()
	for file in DirAccess.get_files_at(project_dir.path_join("tilesets")):
		if file.to_lower().ends_with(".tsx"):
			files.append(file)
	files.sort()
	for file in files:
		_new_map_tileset.add_item(file)
	if files.is_empty():
		_status.text = "REFUSED: project has no TSX tilesets"
		return
	_new_map_name.text = ""
	_new_map_dialog.popup_centered(Vector2i(480, 300))


func _create_map_from_dialog():
	if _new_map_tileset.item_count == 0:
		return null
	var label := _new_map_name.text.strip_edges()
	var created := MapDocument.create(project_dir, label, int(_new_map_width.value),
		int(_new_map_height.value), _new_map_tileset.get_item_text(_new_map_tileset.selected))
	if not bool(created.get("ok", false)):
		_status.text = "REFUSED: " + str(created.get("error", "cannot create map"))
		return null
	_record_names["maps"] = ProjectData.map_labels()
	var map_workspace_index := WORKSPACES.find("maps")
	_sidebar.select(map_workspace_index)
	_on_type_selected(map_workspace_index)
	var record_index := (_record_names["maps"] as Array).find(label)
	if record_index >= 0:
		_records.select(record_index)
	var workspace = preview_map(project_dir, label)
	_status.text = "created map/%s — %dx%d cells" % [label,
		int(_new_map_width.value), int(_new_map_height.value)]
	return workspace


func new_map_control() -> Button:
	return _new_map_button


func new_map_fields() -> Dictionary:
	return {"dialog": _new_map_dialog, "name": _new_map_name, "width": _new_map_width,
		"height": _new_map_height, "tileset": _new_map_tileset}


func select_workspace(kind: String) -> void:
	var index := WORKSPACES.find(kind)
	if index >= 0:
		_sidebar.select(index)
		_on_type_selected(index)


func active_map_workspace():
	return _active_map_workspace


func _on_record_selected(idx: int) -> void:
	if _active_kind == "" or idx < 0 or idx >= (_record_names[_active_kind] as Array).size():
		return
	var basename := str((_record_names[_active_kind] as Array)[idx])
	if _active_kind == "maps":
		edit_map(basename)
	else:
		edit_record(_active_kind, basename)


## Open a map from the active project. Format-1 JSON remains playable but is kept
## read-only here until the Kanto migration in gh #53; format-2 TMX crosses the same
## MapDocument seam used by Engine and the validator.
func edit_map(map_label: String):
	# A build may replace this Project in place while Studio remains open. ProjectData's
	# exact-manifest cache makes this a cheap no-op normally and refreshes format/data when
	# the build identity changes (gh #63).
	var refresh_error := ProjectData.open(project_dir)
	if refresh_error != "":
		_status.text = "REFUSED: " + refresh_error
		return null
	if int(ProjectData.manifest.get("format", 1)) < 2:
		_clear_editor()
		var note := Label.new()
		note.text = "%s is a legacy format-1 map.\n\nNative TMX preview becomes available when this project is migrated to format 2 (Phase 5.2)." % map_label
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.add_theme_color_override("font_color", StudioTheme.MUTED)
		_editor_panel.add_child(note)
		_status.text = "legacy map selected — format-2 preview unavailable"
		return null
	return preview_map(project_dir, map_label)


## Direct preview seam used by the fixture smoke as well as edit_map. It deliberately
## accepts a project root so a focused native-map fixture need not masquerade as a
## complete, engine-bootable game project.
func preview_map(project_root: String, map_label: String):
	var opened := MapDocument.open(project_root, map_label)
	if not bool(opened.get("ok", false)):
		_status.text = "REFUSED: " + str(opened.get("error", "cannot open map"))
		return null
	_clear_editor()
	var workspace := preload("res://scripts/studio/StudioMapWorkspace.gd").new()
	workspace.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_editor_panel.add_child(workspace)
	var world = null
	var world_path := ProjectSettings.globalize_path(project_root).path_join("data/world.json")
	if FileAccess.file_exists(world_path):
		var world_opened := preload("res://core/WorldDocument.gd").open(project_root)
		if not bool(world_opened.get("ok", false)):
			_status.text = "REFUSED: " + str(world_opened.get("error", "cannot open world graph"))
			return null
		world = world_opened["document"]
	var map_labels: Array = []
	for map_file in DirAccess.get_files_at(ProjectSettings.globalize_path(project_root).path_join("maps")):
		if map_file.to_lower().ends_with(".tmx"):
			map_labels.append(map_file.get_basename())
	map_labels.sort()
	var error: String = workspace.bind_document(opened["document"], world, map_labels)
	if error != "":
		_status.text = "REFUSED: " + error
		return null
	workspace.document_saved.connect(func(saved_path: String) -> void:
		_status.text = "saved " + saved_path)
	workspace.playtest_requested.connect(_on_map_playtest_requested)
	_active_map_workspace = workspace
	_status.text = "previewing map/%s — native TMX" % map_label
	return workspace


func status_text() -> String:
	return _status.text


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
	var widget_registry := preload("res://scripts/studio/FormWidgetRegistry.gd").new()
	preload("res://scripts/studio/StudioWidgetCatalog.gd").register_defaults(
		widget_registry, project_dir, context.get("ids", {}))
	form.bind_record(content_type, basename, record, context, widget_registry)
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
	_active_map_workspace = null
	if _editor_panel == null:
		return
	for child in _editor_panel.get_children():
		child.queue_free()


func playtest_control() -> Button:
	return _playtest_button


func ui_scale_control() -> HSlider:
	return _ui_scale_slider


func _set_ui_scale(value: float) -> void:
	_ui_scale = snappedf(clampf(value, MIN_UI_SCALE, MAX_UI_SCALE), 0.05)
	get_window().content_scale_factor = _ui_scale
	_refresh_ui_scale_label()
	var cfg := ConfigFile.new()
	cfg.load(RECENTS_CFG)
	cfg.set_value("studio", "ui_scale", _ui_scale)
	cfg.save(RECENTS_CFG)


func _refresh_ui_scale_label() -> void:
	if _ui_scale_label != null:
		_ui_scale_label.text = "UI %d%%" % roundi(_ui_scale * 100.0)


## Public launch seam used by the button and --studiotest. The Engine is always a child
## process; `probe` asks it to quit after proving readiness, and is test-only.
func launch_playtest(probe := false, headless := false, start_map := "", inspect_cells: Array = [],
		traverse: Dictionary = {}):
	if project_dir == "":
		_status.text = "REFUSED: open a project before play-testing"
		return null
	if _active_form != null and _active_form.is_dirty():
		_status.text = "REFUSED: save or revert the current record before play-testing"
		return null
	if _active_map_workspace != null and _active_map_workspace.is_dirty():
		_status.text = "REFUSED: save or revert the current map before play-testing"
		return null
	var report := ProjectValidator.validate_project(project_dir)
	if not bool(report.get("ok", false)):
		_status.text = "REFUSED: " + "; ".join(PackedStringArray(report.get("errors", [])))
		return null
	var child := preload("res://scripts/studio/StudioPlaytest.gd").new()
	var error: String = child.launch(project_dir, probe, headless, start_map, inspect_cells, traverse)
	if error != "":
		_status.text = "REFUSED: " + error
		return null
	_status.text = "launching play-test…"
	return child


func _on_playtest_pressed() -> void:
	var start_map := str(_active_map_workspace.document.label) if _active_map_workspace != null else ""
	var child = launch_playtest(false, false, start_map)
	if child == null:
		return
	var ack: Dictionary = await child.wait_for_handshake(get_tree())
	_status.text = ("play-test ready — isolated save %s" % str(ack.get("save_slot", ""))) \
		if bool(ack.get("ok", false)) else "REFUSED: " + str(ack.get("error", "handshake failed"))
	child.cleanup_handshake()


func _on_map_playtest_requested(map_label: String) -> void:
	var child = launch_playtest(false, false, map_label)
	if child == null:
		return
	var ack: Dictionary = await child.wait_for_handshake(get_tree())
	_status.text = ("play-test ready on %s" % map_label) if bool(ack.get("ok", false)) \
		else "REFUSED: " + str(ack.get("error", "handshake failed"))
	child.cleanup_handshake()


# ---- the recents list (user://studio.cfg) -------------------------------------------

func _load_recents() -> Array:
	var cfg := ConfigFile.new()
	if cfg.load(RECENTS_CFG) != OK:
		return []
	return cfg.get_value("studio", "recent_projects", [])


func _load_ui_scale() -> float:
	var cfg := ConfigFile.new()
	if cfg.load(RECENTS_CFG) != OK:
		return DEFAULT_UI_SCALE
	return clampf(float(cfg.get_value("studio", "ui_scale", DEFAULT_UI_SCALE)),
		MIN_UI_SCALE, MAX_UI_SCALE)


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

func _studio_map_sweep_test() -> void:
	await get_tree().process_frame
	var ok := true
	var migration_scratch := OS.get_user_data_dir().path_join(
		"studio_map_migration_%d" % OS.get_process_id())
	var error := _copy_dir("res://project", migration_scratch)
	ok = _st_check("map migration test copies the Kanto project", error == "", error) and ok
	var manifest_path := migration_scratch.path_join("manifest.json")
	var native_manifest := FileAccess.get_file_as_string(manifest_path)
	if error == "":
		var legacy_manifest = JSON.parse_string(native_manifest)
		legacy_manifest["format"] = 1
		error = CanonJSON.write_file(manifest_path, legacy_manifest)
		ok = _st_check("migration test exposes the project as format 1",
			error == "", error) and ok
	if error == "":
		error = open_project(migration_scratch)
		ok = _st_check("Studio opens the pre-migration project", error == "", error) and ok
	if error == "":
		var manifest_out := FileAccess.open(manifest_path, FileAccess.WRITE)
		if manifest_out == null:
			error = "cannot restore " + manifest_path
		else:
			manifest_out.store_string(native_manifest)
			manifest_out.close()
		ok = _st_check("project is rebuilt to format 2 while Studio stays open",
			error == "", error) and ok
	if error == "":
		var migrated_workspace = edit_map("PalletTown")
		ok = _st_check("the open Studio refreshes a project rebuilt to native TMX",
			migrated_workspace != null, status_text()) and ok
	if ok:
		ok = preload("res://scripts/studio/StudioMapSmoke.gd").new().sweep_all(self)
	if DirAccess.dir_exists_absolute(migration_scratch):
		OS.move_to_trash(migration_scratch)
	get_tree().quit(0 if ok else 1)

## Headless: copy the repo's Kanto project to a scratch dir (the ADR-020 d2 convention —
## Studio never touches the extractor-owned tree), open it, and assert the sidebar knows
## the four content types with the real counts. Later sub-issues grow this suite
## (write-through, refusal, play-test).
func _studiotest() -> void:
	await get_tree().process_frame
	var ok := true
	var window := get_window()
	ok = _st_check("Studio uses a native resizable desktop window",
		window.content_scale_mode == Window.CONTENT_SCALE_MODE_DISABLED
		and window.content_scale_size == Vector2i.ZERO
		and window.min_size == MIN_WINDOW_SIZE
		and window.size.x >= MIN_WINDOW_SIZE.x and window.size.y >= MIN_WINDOW_SIZE.y
		and Vector2i(size) == Vector2i(window.get_visible_rect().size)
		and is_equal_approx(window.content_scale_factor, _ui_scale)
		and _ui_scale_slider != null and _ui_scale_slider.min_value == MIN_UI_SCALE
		and _ui_scale_slider.max_value == MAX_UI_SCALE,
		"size=%s visible=%s root=%s ui-scale=%.2f min=%s scale-mode=%d scale-size=%s" % [
			str(window.size), str(window.get_visible_rect().size), str(size), _ui_scale,
			str(window.min_size), window.content_scale_mode,
			str(window.content_scale_size)]) and ok
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
	# gh #48/#51 (ADR-020 d2/d7) — canonical write-through: parse + ACTUALLY re-save every
	# record in the scratch copy, then compare against the extractor's raw bytes.
	# BYTE-identical or the writer is wrong; the first mismatch names file + offset.
	var swept := 0
	var bad := ""
	for kind in CONTENT_TYPES:
		var kdir := scratch.path_join("data").path_join(kind)
		for f in DirAccess.get_files_at(kdir):
			if not f.ends_with(".json"):
				continue
			var path := kdir.path_join(f)
			var raw := FileAccess.get_file_as_string(path)
			var write_error := CanonJSON.write_file(path, JSON.parse_string(raw))
			if write_error != "":
				bad = write_error
				break
			var reser := FileAccess.get_file_as_string(path)
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
	ok = _st_check("canonical write-through: %d records load/re-save byte-identical" % swept,
		bad == "", bad) and ok
	ok = preload("res://scripts/studio/StudioFormSmoke.gd").new().run(self, scratch) and ok
	ok = preload("res://scripts/studio/StudioEditorSmoke.gd").new().run(self, scratch) and ok
	ok = preload("res://scripts/studio/StudioMapSmoke.gd").new().run(self) and ok
	ok = await preload("res://scripts/studio/StudioMapAuthoringSmoke.gd").new().run(self, scratch) and ok
	ok = await preload("res://scripts/studio/StudioWorldAuthoringSmoke.gd").new().run(self, scratch) and ok
	ok = await preload("res://scripts/studio/StudioPlaytestSmoke.gd").new().run(self, scratch) and ok
	print("[studiotest] %s" % ("ALL GREEN" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)


func _st_check(name: String, good: bool, detail := "") -> bool:
	print("[studiotest] %s: %s%s" % [name, "PASS" if good else "FAIL",
		"" if good or detail == "" else " — " + detail])
	return good


static func _dialog_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label


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
