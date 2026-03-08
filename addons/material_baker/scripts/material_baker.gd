@tool class_name MaterialBaker extends ResourceWatcher

signal baker_rendered(baker: MaterialBaker, config: MaterialBakerCategoryConfig)

## Depends on the implementation of the manager script.[br]
## E.g. Terrain3D example uses it to define which texture list asset to modify.
@export_storage var array_index: int = -1

## Used to update shader textures when their images change in external programs
var _texture_hot_reloader: TextureHotReloader = TextureHotReloader.new()
func _enter_tree() -> void:
	super._enter_tree()
	if Engine.is_editor_hint():
		if not _texture_hot_reloader.get_parent():
			add_child(_texture_hot_reloader)
		if not _texture_hot_reloader.texture_changed.is_connected(on_resource_changed):
			_texture_hot_reloader.texture_changed.connect(on_resource_changed)
	_ensure_category_image_settings()
	_rebind_image_settings_signals()

func _exit_tree() -> void:
	super._exit_tree()
	if Engine.is_editor_hint() and _texture_hot_reloader:
		_texture_hot_reloader.texture_changed.disconnect(on_resource_changed)

## Per baker_category_label shader overrides, [baker_category_uid, MaterialBakerCategoryState]
@export_storage var category_states_dict: Dictionary[String, MaterialBakerCategoryState] = {}

## cache for store values, so that removing a category and undoing does not lose all material values
var _states_cache: Dictionary[String, MaterialBakerCategoryState] = {}

## Per-category MaterialBakerImageSettings when not under a manager, keyed by baker_category_uid.
@export_storage var category_image_settings: Dictionary[String, MaterialBakerImageSettings] = {}

@export_storage var share_image_settings: bool = true:
	set(value):
		share_image_settings = value
		notify_property_list_changed()
		_rebind_image_settings_signals()
		if is_inside_tree(): _throttle_render(null)

@export_storage var image_settings: MaterialBakerImageSettings = MaterialBakerImageSettings.new():
	set(value):
		image_settings = value if value else MaterialBakerImageSettings.new()
		notify_property_list_changed()
		_rebind_image_settings_signals()
		if is_inside_tree(): _throttle_render(null)

func _ensure_category_image_settings() -> void:
	var valid_uids := category_configs.map(func(c: MaterialBakerCategoryConfig) -> String: return c.baker_category_uid)
	for uid: String in category_image_settings.keys():
		if uid not in valid_uids: category_image_settings.erase(uid)
	for uid: String in valid_uids:
		if not category_image_settings.has(uid):
			category_image_settings[uid] = MaterialBakerImageSettings.new()
	_rebind_image_settings_signals()

func _set_category_image_settings(uid: String, value: MaterialBakerImageSettings) -> void:
	var s: MaterialBakerImageSettings = value if value else MaterialBakerImageSettings.new()
	category_image_settings[uid] = s
	_rebind_image_settings_signals()

## Disconnects ALL image_settings signals then reconnects only the active ones.
func _rebind_image_settings_signals() -> void:
	if image_settings and image_settings.changed.is_connected(_on_baker_image_settings_changed):
		image_settings.changed.disconnect(_on_baker_image_settings_changed)
	for s: MaterialBakerImageSettings in category_image_settings.values():
		if s and s.changed.is_connected(_on_baker_image_settings_changed):
			s.changed.disconnect(_on_baker_image_settings_changed)
	if share_image_settings:
		if image_settings and not image_settings.changed.is_connected(_on_baker_image_settings_changed):
			image_settings.changed.connect(_on_baker_image_settings_changed)
	else:
		for s: MaterialBakerImageSettings in category_image_settings.values():
			if s and not s.changed.is_connected(_on_baker_image_settings_changed):
				s.changed.connect(_on_baker_image_settings_changed)

func _on_baker_image_settings_changed() -> void:
	_throttle_render(null)

@export_storage var category_configs: Array[MaterialBakerCategoryConfig] = []:
	set(value):
		_disconnect_baker_signals()
		var old_uids := category_configs.map(func(c: MaterialBakerCategoryConfig) -> String: return c.baker_category_uid)
		category_configs = value
		_shader_param_cache.clear()
		_sync_category_states()
		_sync_category_bakers()
		_connect_baker_signals()
		_ensure_category_image_settings()
		for config in category_configs:
			watch_resource(config)
		notify_property_list_changed()
		for config in category_configs:
			if config.baker_category_uid not in old_uids:
				_throttle_render_category_baker(config)

var _category_bakers: Dictionary[String, MaterialBakerCategory] = {}
var _shader_param_cache: Dictionary = {}

## Returns a prefix string of `depth` '+' characters.
static func prop_prefix(depth: int) -> String:
	return '+'.repeat(depth)

## Encodes a prefixed property name: `depth` '+' chars followed by `param`.
static func prop_encode(depth: int, param: String) -> String:
	return '+'.repeat(depth) + param

## Decodes a prefixed property name. Returns [index, param_name] or [] if invalid.
## A value equal to `max_depth` means it is a shader-slot property.
static func prop_decode(prop_str: String, max_depth: int) -> Array:
	var stripped := prop_strip_prefix(prop_str)
	var depth := prop_str.length() - stripped.length()
	if depth == 0 or depth > max_depth + 1: return []
	var param := stripped
	if param.is_empty() or param == 'category': return []
	return [depth - 1, param]

## Strips any leading '+' characters from a string.
static func prop_strip_prefix(s: String) -> String:
	return s.lstrip('+')

var scene_loaded := false
@export_storage var generate_at_runtime: bool = false

func _ready() -> void:
	_make_states_unique()
	_sync_category_bakers()
	_connect_baker_signals()

	await get_tree().process_frame # ensure scene fully loaded
	scene_loaded = true
	if generate_at_runtime and not is_parent_manager():
		render_category_bakers() # manager handles its own bakers in its _ready

func _make_states_unique() -> void:
	for key in category_states_dict:
		var state: MaterialBakerCategoryState = category_states_dict[key]
		if state and state.get_reference_count() > 1:
			var unique := state.duplicate(true)
			category_states_dict[key] = unique
			_states_cache[key] = unique

## If for whatever reason you need a manual update, otherwise rebakes automatically
func rebake_all() -> void:
	render_category_bakers()

func _disconnect_baker_signals() -> void:
	for config in category_configs:
		if config.changed.is_connected(_on_baker_config_changed):
			config.changed.disconnect(_on_baker_config_changed)

func _connect_baker_signals() -> void:
	for config in category_configs:
		if not config.changed.is_connected(_on_baker_config_changed):
			config.changed.connect(_on_baker_config_changed.bind(config))

func _sync_category_states() -> void:
	# Merge stored states into cache on first use
	for uid in category_states_dict:
		if not _states_cache.has(uid):
			_states_cache[uid] = category_states_dict[uid]

	var new_dict: Dictionary[String, MaterialBakerCategoryState] = {}
	for config in category_configs:
		var uid := config.baker_category_uid
		var state: MaterialBakerCategoryState = _states_cache.get(uid, null)
		if not state: state = MaterialBakerCategoryState.new()
		if not state.shader and config.default_shader:
			state.shader = config.default_shader
		_states_cache[uid] = state
		new_dict[uid] = state

	category_states_dict = new_dict
	for state: MaterialBakerCategoryState in category_states_dict.values():
		if state: watch_resource(state)

func get_bake_material(config: MaterialBakerCategoryConfig) -> ShaderMaterial:
	var category_state := get_category_state(config)
	return category_state.material if category_state else null

func get_category_state(config: MaterialBakerCategoryConfig) -> MaterialBakerCategoryState:
	return category_states_dict.get(config.baker_category_uid, null)

func _on_baker_config_changed(config: MaterialBakerCategoryConfig) -> void:
	if not category_states_dict.has(config.baker_category_uid):
		_sync_category_states()

	var category_state: MaterialBakerCategoryState = get_category_state(config)
	if category_state and not category_state.shader and config.default_shader:
		category_state.shader = config.default_shader
		notify_property_list_changed()

	_throttle_render_category_baker(config)

func _sync_category_bakers() -> void:
	# Remove category bakers whose baker_category_uid is no longer present
	var current_ids := category_configs.map(func(c: MaterialBakerCategoryConfig) -> String: return c.baker_category_uid)
	for id: String in _category_bakers.keys():
		if id not in current_ids:
			_category_bakers[id].queue_free()
			_category_bakers.erase(id)

	# Add category bakers for new configs
	for config in category_configs:
		if not _category_bakers.has(config.baker_category_uid):
			var sb := MaterialBakerCategory.new()
			add_child(sb)
			_category_bakers[config.baker_category_uid] = sb

	# Sync config and state
	for config in category_configs:
		_category_bakers[config.baker_category_uid].config = config
		_category_bakers[config.baker_category_uid].state = get_category_state(config)

	for category_state: MaterialBakerCategoryState in category_states_dict.values():
		if category_state and category_state.material:
			_texture_hot_reloader.register_material(category_state.material)

func on_resource_changed(changed_resource: Resource = null) -> void:
	if not scene_loaded: return # discard initial changes on scene open

	var affected_configs: Array[MaterialBakerCategoryConfig] = []
	if changed_resource:
		for config in category_configs:
			var category_state := get_category_state(config)
			if not category_state or not category_state.material: continue
			if category_state.material == changed_resource:
				affected_configs.append(config)
				continue # skip param scan, material itself matched

			if category_state.material.shader:
				var shader_rid := category_state.material.shader.get_rid()
				if not _shader_param_cache.has(shader_rid):
					_shader_param_cache[shader_rid] = RenderingServer.get_shader_parameter_list(shader_rid)
				for param: Variant in _shader_param_cache[shader_rid]:
					var param_value: Variant = category_state.material.get_shader_parameter(param.name)
					if param_value is Resource and param_value == changed_resource:
						affected_configs.append(config)
						break

	if get_parent() is MaterialBakerManager:
		get_parent()._throttle_render_category_bakers(self, affected_configs)
		return

	if affected_configs.is_empty():
		render_category_bakers()
	else:
		render_category_bakers(affected_configs)

func is_parent_manager() -> bool:
	return get_parent() is MaterialBakerManager

func _validate_property(property: Dictionary) -> void:
	if property.name == 'array_index':
		var hide := is_parent_manager() and (get_parent() as MaterialBakerManager).auto_index_by_order
		property.usage = PROPERTY_USAGE_STORAGE if hide else PROPERTY_USAGE_DEFAULT
	if is_parent_manager() and property.name == 'category_configs':
		property.usage = PROPERTY_USAGE_STORAGE | PROPERTY_USAGE_NO_EDITOR

func _get_property_list() -> Array[Dictionary]:
	var props: Array[Dictionary] = []

	for i in category_configs.size():
		var config := category_configs[i]

		var label := MaterialBakerCategoryConfig._label(config, i)
		props.append({'name': label, 'type': TYPE_NIL, 'usage': PROPERTY_USAGE_CATEGORY, 'hint_string': label})

		var bake_material := get_bake_material(config)
		if bake_material and bake_material.shader:
			var shader_rid := bake_material.shader.get_rid()
			if not _shader_param_cache.has(shader_rid):
				_shader_param_cache[shader_rid] = RenderingServer.get_shader_parameter_list(shader_rid)
			for param: Variant in _shader_param_cache[shader_rid]:
				var prop := {
					'name': prop_encode(i + 1, param.name), # depth i+1: +, ++, +++
					'type': param.type,
					'usage': PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_STORAGE,
				}
				if param.has('hint'): prop['hint'] = param.hint
				if param.has('hint_string'): prop['hint_string'] = param.hint_string
				props.append(prop)

	props.append({'name': 'Bake Shaders', 'type': TYPE_NIL, 'usage': PROPERTY_USAGE_CATEGORY})

	for i in category_configs.size():
		var config := category_configs[i]
		var label := MaterialBakerCategoryConfig._label(config, i)
		props.append({
			'name': prop_encode(category_configs.size() + 1, label), # shader-slot depth
			'type': TYPE_OBJECT,
			'usage': PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_STORAGE,
			'hint': PROPERTY_HINT_RESOURCE_TYPE,
			'hint_string': 'Shader'
		})

	if not is_parent_manager():
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
		props.append({
			'name': 'Material Baker Categories',
			'type': TYPE_NIL,
			'usage': PROPERTY_USAGE_CATEGORY,
		})
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
		props.append({'name': 'Baker States', 'type': TYPE_NIL, 'usage': PROPERTY_USAGE_CATEGORY})
		props.append({
			'name': 'category_states_dict',
			'type': TYPE_DICTIONARY,
			'usage': PROPERTY_USAGE_DEFAULT,
		})
		props.append({
			'name': 'generate_at_runtime',
			'type': TYPE_BOOL,
			'usage': PROPERTY_USAGE_DEFAULT,
		})
	return props

## Parses a prefixed property name. Returns [index, param_name] or [] if invalid.
## index == category_configs.size() means it's a bake-shader property.
func _parse_prop(prop_str: String) -> Array:
	return prop_decode(prop_str, category_configs.size())

func _get(property: StringName) -> Variant:
	if property == 'rebake_all': return Callable(self, 'rebake_all')
	var prop_str := String(property)
	if prop_str == 'image_settings': return image_settings
	if prop_str.begins_with('image_settings/'):
		var uid := prop_str.substr('image_settings/'.length())
		return category_image_settings.get(uid, null)
	var parsed := _parse_prop(prop_str)
	if parsed.is_empty(): return null
	var index: int = parsed[0]
	var param_name: String = parsed[1]

	# Bake-shader property (one extra underscore level)
	if index == category_configs.size():
		for i in category_configs.size():
			var cfg := category_configs[i]
			if cfg and MaterialBakerCategoryConfig._label(cfg, i) == param_name:
				var category_state := get_category_state(cfg)
				return category_state.shader if category_state else null
		return null

	var config := category_configs[index]
	var bake_material := get_bake_material(config)
	return bake_material.get_shader_parameter(param_name) if bake_material else null

func _set(property: StringName, value: Variant) -> bool:
	var prop_str := String(property)
	if prop_str == 'image_settings':
		image_settings = value
		return true
	if prop_str.begins_with('image_settings/'):
		var uid := prop_str.substr('image_settings/'.length())
		_set_category_image_settings(uid, value)
		return true
	var parsed := _parse_prop(prop_str)
	if parsed.is_empty(): return false
	var index: int = parsed[0]
	var param_name: String = parsed[1]

	# Bake-shader property
	if index == category_configs.size():
		for i in category_configs.size():
			var cfg := category_configs[i]
			if cfg and MaterialBakerCategoryConfig._label(cfg, i) == param_name:
				var category_state := get_category_state(cfg)
				if not category_state: return false
				if category_state.shader == value: return true # or it triggers change on node ctrl+C

				if category_state.shader: _shader_param_cache.erase(category_state.shader.get_rid())
				category_state.shader = value
				watch_resource(category_state)
				notify_property_list_changed()
				_throttle_render_category_baker(cfg)
				return true
		return false

	var config := category_configs[index]
	var bake_material := get_bake_material(config)
	if not bake_material: return false

	bake_material.set_shader_parameter(param_name, value)
	if value is Resource:
		watch_resource(value)
		if value is Texture2D:
			_texture_hot_reloader.register_material(bake_material)
	_throttle_render_category_baker(config)
	return true

func _property_can_revert(property: StringName) -> bool:
	var parsed := _parse_prop(String(property))
	if parsed.is_empty() or parsed[0] == category_configs.size(): return false
	var config := category_configs[parsed[0]]
	var bake_material := get_bake_material(config) if config else null
	return bake_material.property_can_revert('shader_parameter/' + parsed[1]) if bake_material else false

func _property_get_revert(property: StringName) -> Variant:
	var parsed := _parse_prop(String(property))
	if parsed.is_empty() or parsed[0] == category_configs.size(): return null
	var config := category_configs[parsed[0]]
	var bake_material := get_bake_material(config) if config else null
	return bake_material.property_get_revert('shader_parameter/' + parsed[1]) if bake_material else null

## Enabled by MaterialBakerManager to keep editing fast, use Compress button to apply explicitly.
var ignore_compression: bool = false

func _resolve_image_settings(config: MaterialBakerCategoryConfig) -> MaterialBakerImageSettings:
	if get_parent() is MaterialBakerManager:
		var manager_settings := (get_parent() as MaterialBakerManager).get_image_settings(config)
		return manager_settings if manager_settings else MaterialBakerImageSettings.new()
	if share_image_settings: return image_settings if image_settings else MaterialBakerImageSettings.new()
	var per_cat: MaterialBakerImageSettings = category_image_settings.get(config.baker_category_uid, null)
	return per_cat if per_cat else MaterialBakerImageSettings.new()

func _apply_image_settings(image: Image, config: MaterialBakerCategoryConfig) -> void:
	var settings := _resolve_image_settings(config)
	if settings.use_mipmaps:
		image.generate_mipmaps()
	if Engine.is_editor_hint() and not ignore_compression and settings.compress_mode != Image.COMPRESS_MAX:
		image.compress(settings.compress_mode)

func render_category_bakers(configs: Array[MaterialBakerCategoryConfig] = []) -> void:
	if category_configs.is_empty(): return

	var filter_set: Dictionary = {}
	for c in configs: filter_set[c.baker_category_uid] = true

	_sync_category_bakers()

	for config in category_configs:
		if not filter_set.is_empty() and not filter_set.has(config.baker_category_uid): continue
		var category_state := get_category_state(config)
		if not category_state: continue
		var baker_node: MaterialBakerCategory = _category_bakers[config.baker_category_uid]
		baker_node.image_settings = _resolve_image_settings(config)
		var image: Image = await baker_node.bake()
		if not image: continue
		_apply_image_settings(image, config)
		category_state.image = image
		category_state.compressed_image = null
		# print('[MaterialBaker] rendered baker=%s config=%s' % [name, config.baker_category_uid])
		baker_rendered.emit(self, config)

var _throttle_active: Dictionary = {}
var _throttle_trailing: Dictionary = {}

func _throttle_render_category_baker(config: MaterialBakerCategoryConfig) -> void:
	_throttle_render(config)

func _throttle_render(config: MaterialBakerCategoryConfig = null) -> void:
	var filter: Array[MaterialBakerCategoryConfig] = []
	if config: filter.append(config)
	if config:
		await _throttle(config.baker_category_uid, func() -> void: await render_category_bakers(filter))
	else:
		await _throttle(null, func() -> void: await render_category_bakers(filter))

func _throttle(key: Variant, callback: Callable) -> void:
	if not is_inside_tree(): return
	if _throttle_active.get(key, false):
		_throttle_trailing[key] = true
		return
	_throttle_active[key] = true
	_throttle_trailing[key] = false

	await callback.call()

	if not is_inside_tree():
		_throttle_active.erase(key)
		_throttle_trailing.erase(key)
		return
	get_tree().create_timer(0.05).timeout.connect(func() -> void:
		if not is_inside_tree(): return
		var trailing: bool = _throttle_trailing.get(key, false)
		_throttle_active.erase(key)
		_throttle_trailing.erase(key)
		if trailing: await _throttle(key, callback)
	)
