extends RefCounted
class_name FormWidgetRegistry
## Deliberately small override seam for schema forms (ADR-020 d3, gh #49).
## A factory is keyed by content type + JSON-pointer field path and receives
## (schema, current_value, changed_callback). It returns a Control and calls the
## callback with a replacement value whenever the creator edits it.

var _factories := {}


func register(content_type: String, field_path: String, factory: Callable) -> void:
	_factories[_key(content_type, field_path)] = factory


func build(content_type: String, field_path: String, schema: Dictionary, value,
		changed: Callable) -> Control:
	var factory: Callable = _factories.get(_key(content_type, field_path), Callable())
	if not factory.is_valid():
		return null
	var widget = factory.call(schema, value, changed)
	if widget is Control:
		return widget
	push_error("[studio] custom widget %s %s did not return a Control"
		% [content_type, field_path])
	return null


static func _key(content_type: String, field_path: String) -> String:
	return content_type + "\u001f" + field_path
