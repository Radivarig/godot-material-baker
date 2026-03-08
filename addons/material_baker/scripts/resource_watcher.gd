@tool class_name ResourceWatcher extends Node

## Override in subclass
func on_resource_changed(_res: Resource = null) -> void: pass
## Call this whenever a resource property on this Node is assigned a new value
func watch_resource(res: Resource) -> void: _connect_resource(res)

var _watched: Dictionary[Resource, bool] = {}
const _WATCH_USAGE = PROPERTY_USAGE_SCRIPT_VARIABLE | PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_STORAGE
const _IGNORED_PROPS: Array[String] = [
	'resource_path', 'resource_name', 'resource_local_to_scene', 'resource_scene_unique_id', 'script']

func _rescan_resources() -> void:
	for prop in get_property_list():
		if prop.usage & _WATCH_USAGE:
			_scan_value(get(prop.name))

func _enter_tree() -> void: if Engine.is_editor_hint(): _rescan_resources()
func _exit_tree() -> void: if Engine.is_editor_hint(): _disconnect_all()

func _scan_value(value: Variant) -> void:
	if value is Resource: _connect_resource(value)
	elif value is Array: for item: Variant in value: _scan_value(item)
	elif value is Dictionary: for item: Variant in value.values(): _scan_value(item)

func _connect_resource(res: Resource) -> void:
	if not res or _watched.has(res): return
	_watched[res] = true # recursion guard
	res.changed.connect(_on_watched_resource_changed.bind(res))

	for prop in res.get_property_list(): # recurse own sub-resources
		if not _IGNORED_PROPS.has(prop.name) and prop.usage & _WATCH_USAGE:
			_scan_value(res.get(prop.name))

var _notify_pending: bool = false
var _pending_resources: Dictionary[Resource, bool] = {}

func _disconnect_resource(res: Resource) -> void:
	if not res or not _watched.has(res): return
	_watched.erase(res)
	res.changed.disconnect(_on_watched_resource_changed)

func _on_watched_resource_changed(res: Resource) -> void:
	_disconnect_all()
	_rescan_resources()
	if not _notify_pending:
		_notify_pending = true
		_deferred_notify.call_deferred()
	_pending_resources[res] = true

func _deferred_notify() -> void:
	_notify_pending = false
	var resources := _pending_resources.keys()
	_pending_resources.clear()
	for res: Resource in resources:
		on_resource_changed(res)

func _disconnect_all() -> void:
	for res: Resource in _watched:
		res.changed.disconnect(_on_watched_resource_changed)
	_watched.clear()
