extends RefCounted
class_name StudioFormLayout
## Presentation-only grouping of top-level record fields into titled sections (gh #61).
## The schema remains the single source of field shape and order; this map only buckets
## root fields for hierarchy. Fields not listed fall into an "Other" section in schema
## order, so a schema addition can never hide a field behind the layout.

const SECTIONS := {
	"species": [
		["Identity", ["id", "name", "dex", "icon", "sprites", "cry"]],
		["Battle", ["stats", "types", "catch_rate", "base_exp", "growth"]],
		["Moves", ["start_moves", "level_moves", "tmhm"]],
		["Evolution", ["evolutions"]],
		["Advanced", ["custom"]],
	],
	"moves": [
		["Identity", ["id", "name", "type"]],
		["Battle", ["power", "accuracy", "pp", "effect", "sfx"]],
		["Advanced", ["num", "custom"]],
	],
	"items": [
		["Identity", ["id", "name"]],
		["Details", ["price", "key_item", "tm_move"]],
		["Advanced", ["num", "custom"]],
	],
	"trainers": [
		["Identity", ["id", "name", "pic"]],
		["Battle", ["money", "ai", "ai_count", "ai_mods", "parties"]],
		["Advanced", ["num", "custom"]],
	],
	"scripts": [
		["Script", ["id", "source"]],
		["Advanced", ["custom"]],
	],
}


## Returns [[title, [field, ...]], ...] with every schema property assigned exactly
## once, in layout order then schema order for leftovers. Empty sections drop out.
static func sections_for(content_type: String, properties: Dictionary) -> Array:
	var out: Array = []
	var claimed := {}
	for entry in SECTIONS.get(content_type, []):
		var fields: Array = []
		for field in entry[1]:
			if properties.has(field):
				fields.append(field)
				claimed[field] = true
		if not fields.is_empty():
			out.append([entry[0], fields])
	var rest: Array = []
	for field in properties:
		if not claimed.has(field):
			rest.append(field)
	if not rest.is_empty():
		out.append(["Other", rest])
	return out
