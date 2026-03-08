@tool class_name MaterialBakerManager extends Node

## Override in subclass
func baker_rendered(_baker: MaterialBaker, _config: MaterialBakerCategoryConfig) -> void: pass
func bakers_structure_changed() -> void: pass # on add/remove/reorder of bakers
func regenerate() -> void: pass
func category_configs_changed() -> void: pass # called after category_configs is assigned
func generate_at_runtime_changed() -> void: pass

## this will use sibling order for array indexing
var auto_index_by_order: bool

# TODO: adding image_settings requires scene restart before material can be added
## E.g. Ground, Grass, Rock.[br]
## This will add a new Node in the hierarchy where you can start adjusting properties.
@export_tool_button('Create Material Baker', 'Add') var btn := func _btn() -> void:
	if not Engine.is_editor_hint(): return
	var baker := MaterialBaker.new()
	baker.set_meta('_custom_type_script', baker.get_script())
	baker.name = 'MaterialBaker_%s' % str(randi() % 9999 + 1)
	var editor_interface := Engine.get_singleton(&'EditorInterface')
	var undo_redo: Object = editor_interface.get_editor_undo_redo()
	undo_redo.create_action('Add Material Baker')
	undo_redo.add_do_method(self, 'add_child', baker)
	undo_redo.add_do_method(baker, 'set_owner', get_tree().edited_scene_root)
	undo_redo.add_do_method(self, 'debounce_refresh_connections')
	undo_redo.add_undo_method(self, 'remove_child', baker)
	undo_redo.add_undo_method(self, 'debounce_refresh_connections')
	undo_redo.commit_action()

## Shared configs array that all bakers reference
@export_storage var category_configs: Array[MaterialBakerCategoryConfig] = []:
	set(value):
		var mapped: Array[MaterialBakerCategoryConfig] = []
		var seen := []
		for c in value:
			if not c: c = MaterialBakerCategoryConfig.new()
			if c in seen: c = c.duplicate()
			mapped.append(c)
			seen.append(c)
		category_configs = mapped
		category_configs_changed()
		_ensure_category_image_settings()
		_assign_bakers_configs()
		notify_property_list_changed()

## Ensures category_image_settings has exactly the keys from current configs, preserving existing values.
func _ensure_category_image_settings() -> void:
	var valid_uids: Array[String] = []
	for config in category_configs:
		valid_uids.append(config.baker_category_uid)
	for uid: String in category_image_settings.keys():
		if uid not in valid_uids:
			category_image_settings.erase(uid)
	for config in category_configs:
		var uid := config.baker_category_uid
		if not category_image_settings.has(uid):
			category_image_settings[uid] = MaterialBakerImageSettings.new()

## Disconnects ALL image_settings signals, then reconnects only the ones that are active.
## Call this whenever share_image_settings, image_settings, or category_image_settings changes.
func _rebind_image_settings_signals() -> void:
	# Disconnect everything first
	if image_settings and image_settings.changed.is_connected(_throttle_render_all_bakers):
		image_settings.changed.disconnect(_throttle_render_all_bakers)
	for s: MaterialBakerImageSettings in category_image_settings.values():
		if s and s.changed.is_connected(_throttle_render_all_bakers):
			s.changed.disconnect(_throttle_render_all_bakers)
	# Reconnect only what is active
	if share_image_settings:
		if image_settings and not image_settings.changed.is_connected(_throttle_render_all_bakers):
			image_settings.changed.connect(_throttle_render_all_bakers)
	else:
		for s: MaterialBakerImageSettings in category_image_settings.values():
			if s and not s.changed.is_connected(_throttle_render_all_bakers):
				s.changed.connect(_throttle_render_all_bakers)

func _set_category_image_settings(uid: String, value: MaterialBakerImageSettings) -> void:
	var s: MaterialBakerImageSettings = value if value else MaterialBakerImageSettings.new()
	category_image_settings[uid] = s
	_rebind_image_settings_signals()

## When true, one MaterialBakerImageSettings is applied to all categories as an override.[br]
## When false, each category slot below can have its own override (or leave empty to use the config's default).
@export_storage var share_image_settings: bool = true:
	set(value):
		share_image_settings = value
		notify_property_list_changed()
		_rebind_image_settings_signals()
		if is_inside_tree(): _throttle_render_all_bakers()

## Shared MaterialBakerImageSettings override applied to all categories when share_image_settings is true.
@export_storage var image_settings: MaterialBakerImageSettings = MaterialBakerImageSettings.new():
	set(value):
		if not value: value = MaterialBakerImageSettings.new()
		image_settings = value
		notify_property_list_changed()
		_rebind_image_settings_signals()
		if is_inside_tree(): _throttle_render_all_bakers()
## Per-category MaterialBakerImageSettings overrides, keyed by baker_category_uid.[br]
## Null entry means use the config's own image_settings.
@export_storage var category_image_settings: Dictionary[String, MaterialBakerImageSettings] = {}

## Returns the effective MaterialBakerImageSettings for a config.
## If share_image_settings, returns the shared one. Otherwise returns the per-category override.
func get_image_settings(config: MaterialBakerCategoryConfig) -> MaterialBakerImageSettings:
	if share_image_settings: return image_settings if image_settings else MaterialBakerImageSettings.new()
	var s: MaterialBakerImageSettings = category_image_settings.get(config.baker_category_uid, null)
	return s if s else MaterialBakerImageSettings.new()

var connected_bakers: Array[MaterialBaker] = []

## When true, bakers will render and arrays will be built at runtime too.
@export_storage var generate_at_runtime: bool = true:
	set(value):
		generate_at_runtime = value
		generate_at_runtime_changed()

func _enter_tree() -> void:
	if not Engine.is_editor_hint() and not generate_at_runtime: return
	if not child_entered_tree.is_connected(_on_child_changed): child_entered_tree.connect(_on_child_changed)
	if not child_exiting_tree.is_connected(_on_child_changed): child_exiting_tree.connect(_on_child_changed)
	if not child_order_changed.is_connected(_on_child_changed): child_order_changed.connect(_on_child_changed)
	_ensure_category_image_settings()
	_rebind_image_settings_signals()
	debounce_refresh_connections()

func _assign_bakers_configs() -> void:
	for baker in connected_bakers: baker.category_configs = category_configs

func _on_child_changed(_child: Node = null) -> void:
	debounce_refresh_connections()

var _prev_baker_ids: Array = []
func refresh_connections() -> void:
	if not is_inside_tree(): return
	_reconnect_bakers()
	_assign_bakers_indices()
	_assign_bakers_configs()
	_assign_bakers_shaders()
	_detect_bakers_structure_changes()

func _detect_bakers_structure_changes() -> void:
	var new_baker_ids := connected_bakers.map(func(b: MaterialBaker) -> int: return b.get_instance_id())
	if new_baker_ids != _prev_baker_ids:
		bakers_structure_changed()
	_prev_baker_ids = new_baker_ids

func _assign_bakers_shaders() -> void:
	for baker in connected_bakers:
		for config in category_configs:
			if not config.default_shader: continue
			var category_state: MaterialBakerCategoryState = baker.get_category_state(config)
			if not category_state or category_state.shader: continue
			category_state.shader = config.default_shader

func _reconnect_bakers() -> void:
	for baker in connected_bakers:
		if not is_instance_valid(baker): continue
		if baker.baker_rendered.is_connected(baker_rendered):
			baker.baker_rendered.disconnect(baker_rendered)
	connected_bakers.clear()
	connected_bakers.assign(find_children('*', 'MaterialBaker', true, false))
	for baker in connected_bakers:
		if baker is MaterialBaker: baker.generate_at_runtime = generate_at_runtime
		baker.baker_rendered.connect(baker_rendered)

func _assign_bakers_indices() -> void:
	if not auto_index_by_order: return
	var baker_index := 0
	for baker: MaterialBaker in connected_bakers:
		baker.array_index = baker_index
		baker_index += 1

var _render_pending: bool = false
var _pending_renders: Dictionary[MaterialBaker, Dictionary] = {} # inner: [String, MaterialBakerCategoryConfig]

func _throttle_render_category_bakers(baker: MaterialBaker, configs: Array[MaterialBakerCategoryConfig]) -> void:
	if not _render_pending:
		_render_pending = true
		_render_bakers.call_deferred()

	if configs.is_empty():
		_pending_renders[baker] = {}
	else:
		if not _pending_renders.has(baker):
			_pending_renders[baker] = {}
		for config in configs:
			_pending_renders[baker][config.baker_category_uid] = config

func _throttle_render_all_bakers() -> void:
	_pending_renders.clear()
	if not _render_pending:
		_render_pending = true
		_render_bakers.call_deferred()

func _render_bakers() -> void:
	_render_pending = false
	var renders := _pending_renders.duplicate()
	_pending_renders.clear()

	if renders.is_empty():
		for baker in connected_bakers:
			if is_instance_valid(baker):
				baker.render_category_bakers()
		return

	for baker: MaterialBaker in renders:
		if not is_instance_valid(baker): continue
		var config_map: Dictionary = renders[baker]
		var configs: Array[MaterialBakerCategoryConfig] = []
		configs.assign(config_map.values())
		if configs.is_empty(): baker.render_category_bakers()
		else: baker.render_category_bakers(configs)

func rebake_all() -> void:
	_throttle_render_all_bakers()

var _refresh_timer: SceneTreeTimer
func debounce_refresh_connections() -> void:
	if not is_inside_tree(): return
	if _refresh_timer and _refresh_timer.timeout.is_connected(refresh_connections):
		_refresh_timer.timeout.disconnect(refresh_connections)
	_refresh_timer = get_tree().create_timer(0.1)
	_refresh_timer.timeout.connect(refresh_connections)

var _regenerate_timer: SceneTreeTimer
func debounce_regenerate() -> void:
	if not is_inside_tree(): return
	if _regenerate_timer and _regenerate_timer.timeout.is_connected(regenerate):
		_regenerate_timer.timeout.disconnect(regenerate)
	_regenerate_timer = get_tree().create_timer(0.1)
	_regenerate_timer.timeout.connect(regenerate)

func _property_can_revert(property: StringName) -> bool:
	# Return true so Godot uses _property_get_revert instead of
	# PropertyUtils::get_property_default_value (which shows the revert button).
	if property == &'image_settings': return true
	if property == &'category_configs': return true
	return false

func _property_get_revert(property: StringName) -> Variant:
	# NOTE: I've added a cache to prevent loss of baker data when category is removed
	# but cache is not stored on purpose and closing the scene will lose it, so hide the undos
	if property == &'image_settings': return image_settings
	if property == &'category_configs': return category_configs
	return null

func _get(property: StringName) -> Variant:
	var prop_str := String(property)
	if prop_str == 'rebake_all': return Callable(self, 'rebake_all')
	if prop_str == 'category_configs': return category_configs
	if prop_str.begins_with('image_settings/'):
		var uid := prop_str.substr('image_settings/'.length())
		return category_image_settings.get(uid, null)
	var parsed := MaterialBaker.prop_decode(prop_str, 1)
	if parsed.is_empty(): return null
	var baker_category_label: String = parsed[1]
	for config in category_configs:
		if config and config.baker_category_label == baker_category_label:
			return config
	return null

func _set(property: StringName, value: Variant) -> bool:
	var prop_str := String(property)
	if prop_str == 'category_configs':
		category_configs = value
		return true
	if prop_str.begins_with('image_settings/'):
		var uid := prop_str.substr('image_settings/'.length())
		_set_category_image_settings(uid, value)
		return true
	var parsed := MaterialBaker.prop_decode(prop_str, 1)
	if parsed.is_empty(): return false
	var baker_category_label: String = parsed[1]
	for i in category_configs.size():
		if category_configs[i] and category_configs[i].baker_category_label == baker_category_label:
			category_configs[i] = value
			notify_property_list_changed()
			return true
	return false

func _get_property_list() -> Array[Dictionary]:
	var props: Array[Dictionary] = []

	props.append({'name': 'Image Settings', 'type': TYPE_NIL, 'usage': PROPERTY_USAGE_CATEGORY})
	props.append({'name': 'share_image_settings', 'type': TYPE_BOOL, 'usage': PROPERTY_USAGE_DEFAULT})
	if share_image_settings:
		props.append({
			'name': 'image_settings',
			'type': TYPE_OBJECT,
			'usage': PROPERTY_USAGE_DEFAULT,
			'hint': PROPERTY_HINT_RESOURCE_TYPE,
			'hint_string': 'MaterialBakerImageSettings'
		})
	else:
		for config in category_configs:
			props.append({
				'name': 'image_settings/' + config.baker_category_uid,
				'type': TYPE_OBJECT,
				'usage': PROPERTY_USAGE_DEFAULT,
				'hint': PROPERTY_HINT_RESOURCE_TYPE,
				'hint_string': 'MaterialBakerImageSettings'
			})

	props.append({'name': 'Material Baker Categories', 'type': TYPE_NIL, 'usage': PROPERTY_USAGE_CATEGORY})
	props.append({
		'name': 'category_configs',
		'type': TYPE_ARRAY,
		'usage': PROPERTY_USAGE_DEFAULT,
		'hint': PROPERTY_HINT_ARRAY_TYPE,
		'hint_string': 'MaterialBakerCategoryConfig'
	})
	props.append({
		'name': 'rebake_all',
		'type': TYPE_CALLABLE,
		'usage': PROPERTY_USAGE_EDITOR,
		'hint': PROPERTY_HINT_TOOL_BUTTON,
		'hint_string': 'Manual Rebake,Reload',
	})
	props.append({
		'name': 'generate_at_runtime',
		'type': TYPE_BOOL,
		'usage': PROPERTY_USAGE_DEFAULT,
	})
	return props
