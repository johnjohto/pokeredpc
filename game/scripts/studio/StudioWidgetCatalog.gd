extends RefCounted
class_name StudioWidgetCatalog
## The complete Phase-4 custom-widget catalog (ADR-020 d3, gh #50). These are exact
## registry entries for fields whose editing semantics benefit from more than the generic
## recursive form; moves and items intentionally need no bespoke controls.

const Support := preload("res://scripts/studio/widgets/WidgetSupport.gd")
const SpritePicker := preload("res://scripts/studio/widgets/SpritePicker.gd")
const TypeSelector := preload("res://scripts/studio/widgets/TypeSelector.gd")
const LearnsetTable := preload("res://scripts/studio/widgets/LearnsetTable.gd")
const PartyBuilder := preload("res://scripts/studio/widgets/PartyBuilder.gd")


static func register_defaults(registry: RefCounted, project_dir: String,
		id_registry: Dictionary) -> void:
	var type_ids := Support.ids_for(id_registry, "type")
	var move_ids := Support.ids_for(id_registry, "move")
	var species_ids := Support.ids_for(id_registry, "species")
	registry.register("species", "/sprites",
		func(_schema: Dictionary, value, changed: Callable) -> Control:
			var widget := SpritePicker.new()
			widget.setup(project_dir, value, changed)
			return widget)
	registry.register("species", "/types",
		func(schema: Dictionary, value, changed: Callable) -> Control:
			var widget := TypeSelector.new()
			widget.setup(schema, value, type_ids, changed)
			return widget)
	registry.register("species", "/level_moves",
		func(schema: Dictionary, value, changed: Callable) -> Control:
			var widget := LearnsetTable.new()
			widget.setup(schema, value, move_ids, changed)
			return widget)
	registry.register("trainers", "/parties",
		func(schema: Dictionary, value, changed: Callable) -> Control:
			var widget := PartyBuilder.new()
			widget.setup(schema, value, species_ids, changed)
			return widget)
	# gh #67: HatchScript sources edit in a monospace multiline field. Diagnostics need
	# no widget code — every keystroke re-runs the generic draft validation, whose
	# /source-addressed parse error lands in the standard gh #61 label + danger border.
	registry.register("scripts", "/source",
		func(_schema: Dictionary, value, changed: Callable) -> Control:
			var editor := TextEdit.new()
			editor.text = str(value)
			editor.custom_minimum_size.y = 240
			var mono := SystemFont.new()
			mono.font_names = PackedStringArray(["Consolas", "Menlo",
				"DejaVu Sans Mono", "Liberation Mono", "monospace"])
			editor.add_theme_font_override("font", mono)
			editor.text_changed.connect(func() -> void: changed.call(editor.text))
			return editor)
