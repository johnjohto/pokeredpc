extends RefCounted
## Small shared mechanics for the four Studio content widgets (gh #50). The widgets own
## presentation; this helper only keeps ID-picker and external-project asset behavior exact.


static func ids_for(registry: Dictionary, prefix: String) -> Array:
	var ids := (registry.get(prefix, {}) as Dictionary).keys()
	ids.sort()
	return ids


static func fill_id_picker(picker: OptionButton, ids: Array, current: String) -> void:
	picker.clear()
	var found := false
	for id in ids:
		picker.add_item(str(id))
		picker.set_item_metadata(picker.item_count - 1, str(id))
		if str(id) == current:
			picker.select(picker.item_count - 1)
			found = true
	if not found:
		picker.add_item("[missing] " + current)
		picker.set_item_metadata(picker.item_count - 1, current)
		picker.select(picker.item_count - 1)


static func png_paths(project_dir: String, relative_dir: String) -> Array:
	var result := []
	var dir := DirAccess.open(project_dir.path_join(relative_dir))
	if dir == null:
		return result
	for file in dir.get_files():
		if str(file).get_extension().to_lower() == "png":
			result.append(relative_dir.path_join(str(file)).replace("\\", "/"))
	result.sort()
	return result


static func external_texture(project_dir: String, relative_path: String) -> Texture2D:
	var absolute := project_dir.path_join(relative_path)
	if not FileAccess.file_exists(absolute):
		return null
	var image := Image.load_from_file(absolute)
	if image == null or image.is_empty():
		return null
	return ImageTexture.create_from_image(image)
