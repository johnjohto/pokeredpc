extends RefCounted
class_name StudioMapAuthoringSmoke
## End-to-end gh #54 gate: real Studio controls create, paint, undo/redo, save, reopen,
## validate, and launch the edited map in a separate Engine child.


func run(shell: StudioShell, scratch: String) -> bool:
	var ok := true
	shell.select_workspace("maps")
	var new_button: Button = shell.new_map_control()
	ok = _check("Maps workspace enables the real New map control",
		new_button != null and not new_button.disabled) and ok
	new_button.pressed.emit()
	var fields: Dictionary = shell.new_map_fields()
	var name: LineEdit = fields["name"]
	var map_width: SpinBox = fields["width"]
	var map_height: SpinBox = fields["height"]
	var tileset: OptionButton = fields["tileset"]
	name.text = "StudioPaintTest"
	map_width.value = 4
	map_height.value = 4
	ok = _check("New map dialog lists project TSX tilesets", tileset.item_count == 24,
		"got %d" % tileset.item_count) and ok
	(fields["dialog"] as ConfirmationDialog).confirmed.emit()
	var workspace = shell.active_map_workspace()
	ok = _check("New map control creates and opens a 4x4 native document",
		workspace != null and workspace.document.label == "StudioPaintTest"
		and workspace.document.width == 4 and workspace.document.height == 4
		and FileAccess.file_exists(scratch.path_join("maps/StudioPaintTest.tmx"))) and ok
	if workspace == null:
		return false

	var initial: Dictionary = workspace.document.edit_state()
	var original_tile: int = workspace.document.tile_at(Vector2i.ZERO)
	var alternate: int = (original_tile + 1) % int(workspace.document.tileset.get("tile_count", 1))
	workspace.select_tile(alternate)
	workspace.select_tool("brush")
	var brush_changed: bool = workspace.paint_once(Vector2i.ZERO)
	workspace.undo()
	var brush_undo: bool = workspace.document.edit_state() == initial
	workspace.redo()
	var brush_redo: bool = workspace.document.tile_at(Vector2i.ZERO) == alternate
	workspace.undo()
	ok = _check("tile brush undo/redo is exact", brush_changed and brush_undo and brush_redo
		and workspace.document.edit_state() == initial) and ok

	workspace.select_tool("fill")
	var fill_changed: bool = workspace.paint_once(Vector2i.ZERO)
	var fill_ok: bool = true
	for y in workspace.document.height:
		for x in workspace.document.width:
			fill_ok = fill_ok and workspace.document.tile_at(Vector2i(x, y)) == alternate
	workspace.undo()
	ok = _check("fill tool paints one connected region as one undo action",
		fill_changed and fill_ok and workspace.document.edit_state() == initial) and ok

	var block_tile: int = -1
	var block_id: int = -1
	for tile_id in (workspace.document.tileset.get("tile_blocks", {}) as Dictionary):
		var member: Array = workspace.document.tileset["tile_blocks"][tile_id]
		if int(member[1]) == 0:
			block_tile = int(tile_id)
			block_id = int(member[0])
			break
	workspace.select_tile(block_tile)
	workspace.select_tool("block")
	var block_changed: bool = workspace.paint_once(Vector2i(2, 2))
	var group: Array = (workspace.document.tileset.get("block_tiles", {}) as Dictionary).get(block_id, [])
	var block_ok: bool = group.size() == 4
	for quadrant in group.size():
		block_ok = block_ok and workspace.document.tile_at(
			Vector2i(2 + quadrant % 2, 2 + quadrant / 2)) == int(group[quadrant])
	workspace.undo()
	ok = _check("optional 32px block brush paints the four reversible quadrants",
		block_changed and block_ok and workspace.document.edit_state() == initial) and ok

	workspace.select_tool("solid")
	var collision_changed: bool = workspace.paint_once(Vector2i(1, 0))
	ok = _check("collision tool marks one movement cell solid without changing its art",
		collision_changed and workspace.document.is_walkable(Vector2i.ZERO)
		and not workspace.document.is_walkable(Vector2i(1, 0))
		and workspace.document.tile_at(Vector2i(1, 0)) == original_tile) and ok
	workspace.save_control().pressed.emit()
	var reopened := MapDocument.open(scratch, "StudioPaintTest")
	ok = _check("real Save writes targeted TMX and clears dirty state",
		not workspace.is_dirty() and bool(reopened.get("ok", false))
		and (reopened.get("document") as MapDocument).is_walkable(Vector2i.ZERO)
		and not (reopened.get("document") as MapDocument).is_walkable(Vector2i(1, 0))
		and FileAccess.get_file_as_string(scratch.path_join("maps/StudioPaintTest.tmx"))
			.contains("name=\"Collision\""), str(reopened.get("error", ""))) and ok

	var child = shell.launch_playtest(true, true, "StudioPaintTest",
		[Vector2i.ZERO, Vector2i(1, 0)])
	if child == null:
		return _check("edited map child play-test launches", false) and ok
	var ack: Dictionary = await child.wait_for_handshake(shell.get_tree(), 20000)
	var exited: bool = await child.wait_for_exit(shell.get_tree(), 5000)
	var inspected: Dictionary = ack.get("inspected_cells", {})
	ok = _check("child Engine starts on the new map and consumes edited collision",
		bool(ack.get("ok", false)) and str(ack.get("start_map", "")) == "StudioPaintTest"
		and bool(inspected.get("0,0", false)) and not bool(inspected.get("1,0", true))
		and exited, str(ack.get("error", ""))) and ok
	child.cleanup_handshake()
	print("[studioauthor] %s" % ("ALL GREEN" if ok else "FAIL"))
	return ok


static func _check(name: String, good: bool, detail := "") -> bool:
	print("[studioauthor] %s: %s%s" % [name, "PASS" if good else "FAIL",
		"" if good or detail == "" else " — " + detail])
	return good
