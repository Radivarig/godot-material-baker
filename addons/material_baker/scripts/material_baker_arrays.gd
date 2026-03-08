@tool class_name MaterialBakerArrays extends MaterialBakerManager

signal arrays_changed(category_arrays: Array)

static func _is_external_res(path: String) -> bool:
	return path.begins_with('res://') and path.ends_with('.res') and '::' not in path

var _pending_arrays_changed: Dictionary[String, MaterialBakerCategoryConfig] = {}
var _arrays_changed_pending := false

func _emit_arrays_changed_deferred(configs: Array[MaterialBakerCategoryConfig]) -> void:
	for c in configs: _pending_arrays_changed[c.baker_category_uid] = c
	if _arrays_changed_pending: return
	_arrays_changed_pending = true
	_emit_arrays_changed.call_deferred()

func _emit_arrays_changed() -> void:
	_arrays_changed_pending = false
	if _pending_arrays_changed.is_empty(): return
	var configs: Array[MaterialBakerCategoryConfig] = []
	configs.assign(_pending_arrays_changed.values())
	_pending_arrays_changed.clear()
	arrays_changed.emit(configs.map(func(c: MaterialBakerCategoryConfig) -> Array: return [c, _get_texture_array(c)]))

func _notification(what: int) -> void:
	if what == NOTIFICATION_EDITOR_PRE_SAVE:
		# Populate texture2d_arrays_res with external resources only so Godot serialises
		# them as UID references (path-independent). Unsaved arrays are cleared so they
		# are never inlined into the scene file.
		for config in category_configs:
			var uid := config.baker_category_uid
			var arr: Texture2DArray = _texture2d_arrays.get(uid, null)
			if arr and _is_external_res(arr.resource_path):
				texture2d_arrays_res[uid] = load(arr.resource_path)
			else:
				texture2d_arrays_res.erase(uid)
	if what == NOTIFICATION_EDITOR_POST_SAVE:
		# TODO: find a way to be able to modify baker_category_label without losing focus of
		# 	the input, then notify_property_list_changed can be called from there.
		for config in category_configs: config._baker_category_label_dirty = false
		# Restore runtime cache from saved resource references so the live arrays
		# remain usable after saving.
		for config in category_configs:
			var uid := config.baker_category_uid
			var saved := texture2d_arrays_res.get(uid, null)
			if saved:
				_texture2d_arrays[uid] = saved
		update_configuration_warnings()
		notify_property_list_changed()

func category_configs_changed() -> void:
	_sync_texture2d_arrays()

func generate_at_runtime_changed() -> void:
	update_configuration_warnings()

func _enter_tree() -> void:
	super._enter_tree()
	auto_index_by_order = true
	_sync_texture2d_arrays()

func refresh_connections() -> void:
	super.refresh_connections()
	_sync_texture2d_arrays()
	for baker in connected_bakers:
		baker.ignore_compression = true
	for config in category_configs:
		if not config.changed.is_connected(update_configuration_warnings):
			config.changed.connect(update_configuration_warnings)

func _bake_unsaved_arrays() -> void:
	if not generate_at_runtime: return
	var configs_to_bake: Array[MaterialBakerCategoryConfig] = []
	for config in category_configs:
		if not texture2d_arrays_res.has(config.baker_category_uid):
			configs_to_bake.append(config)
	if not configs_to_bake.is_empty():
		for baker in connected_bakers:
			_throttle_render_category_bakers(baker, configs_to_bake)

var _initial_bake_done := false
func bakers_structure_changed() -> void:
	if not _initial_bake_done:
		_initial_bake_done = true
		_bake_unsaved_arrays()
		return
	_throttle_render_all_bakers.call_deferred()

## Stores Texture2DArray resources keyed by baker_category_uid.
## Godot serializes these by UID so paths remain valid after files are moved.
## On PRE_SAVE only external (.res) resources are written here; unsaved arrays are
## cleared so they are never inlined into the scene file.
@export_storage var texture2d_arrays_res: Dictionary[String, Texture2DArray] = {}

## Runtime cache, not saved to scene.
var _texture2d_arrays: Dictionary[String, Texture2DArray] = {}

func _get_texture_array(config: MaterialBakerCategoryConfig) -> Texture2DArray:
	var uid := config.baker_category_uid
	if not _texture2d_arrays.has(uid):
		var saved := texture2d_arrays_res.get(uid, null)
		_texture2d_arrays[uid] = saved if saved else Texture2DArray.new()
	return _texture2d_arrays.get(uid, null)

func _set_texture_array(uid: String, arr: Texture2DArray) -> void:
	_texture2d_arrays[uid] = arr
	if arr and _is_external_res(arr.resource_path):
		texture2d_arrays_res[uid] = arr
	else:
		texture2d_arrays_res.erase(uid)

func _sync_texture2d_arrays() -> void:
	for config in category_configs:
		if config and not config.baker_category_uid.is_empty():
			# Populate cache entry if not already there
			if not _texture2d_arrays.has(config.baker_category_uid):
				_get_texture_array(config) # triggers load-or-create via getter

func _exit_tree() -> void:
	_cancel_save_timer()
	_save_all_arrays()

func _get_configuration_warnings() -> PackedStringArray:
	var dirty: Array[String] = []
	for i in category_configs.size():
		var config := category_configs[i]
		if config and config._baker_category_label_dirty:
			dirty.append(MaterialBakerCategoryConfig._label(config, i))
	var invalid: Array[String] = []
	var seen_categories: Dictionary = {}
	for i in category_configs.size():
		var config := category_configs[i]
		if not config: continue
		if config.baker_category_label.is_empty():
			invalid.append(MaterialBakerCategoryConfig._label(config, i))
		elif seen_categories.has(config.baker_category_label):
			invalid.append('%s (duplicate)' % MaterialBakerCategoryConfig._label(config, i))
		else:
			seen_categories[config.baker_category_label] = true
	var unsaved: Array[String] = []
	var uncompressed: Array[String] = []
	for i in category_configs.size():
		var config := category_configs[i]
		var texture_array := _get_texture_array(config)
		if not texture_array: continue
		var label := MaterialBakerCategoryConfig._label(config, i)
		var saved_res: Texture2DArray = texture2d_arrays_res.get(config.baker_category_uid, null)
		if not saved_res or saved_res.resource_path.is_empty() or '.tscn::' in saved_res.resource_path:
			unsaved.append(label)
		elif not saved_res.resource_path.ends_with('.res'):
			unsaved.append(label + ' (must be .res)')
		var settings: MaterialBakerImageSettings = get_image_settings(config)
		if settings and settings.compress_mode != Image.COMPRESS_MAX \
				and saved_res and _is_external_res(saved_res.resource_path):
			var probe := Image.create(4, 4, false, Image.FORMAT_RGBA8)
			probe.compress(settings.compress_mode)
			if texture_array.get_format() != probe.get_format():
				uncompressed.append(label)
	var warnings: PackedStringArray = []
	if not dirty.is_empty():
		warnings.append('baker_category_label changed, refocus node or save the scene to apply:\n' + '\n'.join(dirty))
	if not invalid.is_empty():
		warnings.append('baker_category_label must be unique and not empty:\n' + '\n'.join(invalid))
	if not unsaved.is_empty() and not generate_at_runtime:
		warnings.append('Texture2DArray resources not saved to disk (use .res):\n' + '\n'.join(unsaved))
	if not uncompressed.is_empty():
		warnings.append('Arrays get uncompressed during edit, click the Compress button:\n' + '\n'.join(uncompressed))
	return warnings

var _suppress_baker_rendered := false
func baker_rendered(baker: MaterialBaker, config: MaterialBakerCategoryConfig) -> void:
	if _suppress_baker_rendered: return
	var uid := config.baker_category_uid
	if not uid.is_empty() and not _texture2d_arrays.has(uid):
		_get_texture_array(config) # triggers load-or-create

	var texture_array := _get_texture_array(config)
	if texture_array and texture_array.get_layers() > connected_bakers.size():
		debounce_regenerate()
		return

	_update_array_layer(baker, config)

func _update_array_layer(baker: MaterialBaker, config: MaterialBakerCategoryConfig) -> void:
	if baker.array_index < 0:
		return

	var texture_array := _get_texture_array(config)
	if not texture_array:
		_regenerate_arrays([config])
		return

	# Get the image from this baker's category_state
	var category_state := baker.get_category_state(config)
	if not category_state or not category_state.image:
		return

	var current_layers := texture_array.get_layers()

	# If array_index is beyond current size, we need to rebuild the entire array
	if baker.array_index >= current_layers:
		_regenerate_arrays([config])
		return

	var existing_size := Vector2i(texture_array.get_width(), texture_array.get_height())
	var new_size := Vector2i(category_state.image.get_width(), category_state.image.get_height())

	if existing_size != new_size:
		debounce_regenerate()
		return

	var existing_has_mipmaps := texture_array.has_mipmaps()
	var new_has_mipmaps := category_state.image.has_mipmaps()

	var existing_format := texture_array.get_format()
	var new_format := category_state.image.get_format()

	# If the array is compressed but the incoming image is not, decompress all layers first.
	if existing_format != new_format or existing_has_mipmaps != new_has_mipmaps:
		# Probe whether decompression will yield the expected format before mutating.
		var probe := texture_array.get_layer_data(0)
		if probe.is_compressed(): probe.decompress()
		if probe.get_format() != new_format or probe.has_mipmaps() != new_has_mipmaps:
			debounce_regenerate()
			return

		var layers: Array[Image] = []
		for i in texture_array.get_layers():
			var layer := texture_array.get_layer_data(i)
			if layer.is_compressed(): layer.decompress()
			layers.append(layer)
		texture_array.create_from_images(layers)

	texture_array.update_layer(category_state.image, baker.array_index)
	texture_array.emit_changed()
	_emit_arrays_changed_deferred([config])
	update_configuration_warnings()

	debounce_save_arrays()

func regenerate() -> void:
	_regenerate_arrays()

func _regenerate_arrays(configs: Array[MaterialBakerCategoryConfig] = []) -> void:
	var filter_set: Dictionary[String, bool] = {}
	for c in configs: filter_set[c.baker_category_uid] = true

	var images_by_uid: Dictionary[String, Dictionary] = {}  # baker_category_uid -> {array_index -> Image}
	var config_by_uid: Dictionary[String, MaterialBakerCategoryConfig] = {}  # baker_category_uid -> config

	for baker in connected_bakers:
		for config in baker.category_configs:
			var uid := config.baker_category_uid
			if not filter_set.is_empty() and not filter_set.has(uid): continue
			if not config_by_uid.has(uid):
				config_by_uid[uid] = config
				images_by_uid[uid] = {}

			var category_state := baker.get_category_state(config)
			if category_state and category_state.image and baker.array_index >= 0:
				images_by_uid[uid][baker.array_index] = category_state.image

	var changed_configs: Array[MaterialBakerCategoryConfig] = []
	for uid in images_by_uid:
		var images_dict: Dictionary = images_by_uid[uid]
		if images_dict.is_empty():
			continue

		var indices: Array = images_dict.keys()
		indices.sort()

		var images: Array[Image] = []
		for idx: int in indices:
			images.append(images_dict[idx])

		var config := config_by_uid[uid]
		var texture_array := _get_texture_array(config)
		if not images.is_empty():
			texture_array.create_from_images(images)
			texture_array.emit_changed()
			changed_configs.append(config)

	if not changed_configs.is_empty():
		_emit_arrays_changed_deferred(changed_configs)
	if not images_by_uid.is_empty():
		debounce_save_arrays()
	update_configuration_warnings()

var _save_timer: SceneTreeTimer
func _cancel_save_timer() -> void:
	if _save_timer and _save_timer.timeout.is_connected(_save_all_arrays):
		_save_timer.timeout.disconnect(_save_all_arrays)
	_save_timer = null
func debounce_save_arrays() -> void:
	if not is_inside_tree(): return
	_cancel_save_timer()
	_save_timer = get_tree().create_timer(2.0)
	_save_timer.timeout.connect(_save_all_arrays)

func _save_all_arrays() -> void:
	for texture_array: Texture2DArray in _texture2d_arrays.values():
		if not texture_array or texture_array.resource_path.is_empty(): continue
		ResourceSaver.save(texture_array, texture_array.resource_path)
		for uid in _texture2d_arrays:
			if _texture2d_arrays[uid] == texture_array:
				_set_texture_array(uid, texture_array)

var _compress_cancelled := false

func _compress_abort() -> void:
	_compress_cancelled = true
	_suppress_baker_rendered = false

func compress_arrays() -> void:
	if not Engine.is_editor_hint(): return
	var popup := Window.new()
	popup.title = 'Compressing Arrays'
	popup.size = Vector2i(300, 50)
	popup.unresizable = true
	_compress_cancelled = false
	popup.close_requested.connect(func() -> void:
		_compress_abort()
		popup.queue_free())

	var label_prefix := 'Compressing: '
	var label := Label.new()
	label.text = label_prefix
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	popup.add_child(label)
	Engine.get_singleton(&'EditorInterface').get_base_control().add_child(popup)
	popup.popup_centered()
	await RenderingServer.frame_post_draw
	if _compress_cancelled: return

	var configs_to_rebuild: Array[MaterialBakerCategoryConfig] = []
	for config in category_configs:
		var texture_array := _get_texture_array(config)
		if not texture_array or texture_array.get_layers() == 0: continue
		var settings: MaterialBakerImageSettings = get_image_settings(config)
		var probe := Image.create(4, 4, settings.use_mipmaps, Image.FORMAT_RGBA8)
		if settings.use_mipmaps: probe.generate_mipmaps()
		if settings.compress_mode != Image.COMPRESS_MAX: probe.compress(settings.compress_mode)

		var format_mismatch := texture_array.get_format() != probe.get_format()
		var mipmap_mismatch := texture_array.has_mipmaps() != probe.has_mipmaps()
		if format_mismatch or mipmap_mismatch: configs_to_rebuild.append(config)

	if configs_to_rebuild.is_empty():
		if is_instance_valid(popup): popup.queue_free()
		return

	_suppress_baker_rendered = true

	var total := connected_bakers.size() * configs_to_rebuild.size()
	var current := 0
	var images_by_uid: Dictionary[String, Dictionary] = {}  # baker_category_uid -> {array_index -> Image}
	var config_by_uid: Dictionary[String, MaterialBakerCategoryConfig] = {}  # baker_category_uid -> config

	for config in configs_to_rebuild:
		var images: Dictionary = {}
		for baker: MaterialBaker in connected_bakers:
			if _compress_cancelled: _compress_abort(); return

			var category_state := baker.get_category_state(config)
			if not category_state or baker.array_index < 0: continue

			if not category_state.compressed_image:
				await baker.render_category_bakers([config])
				if not category_state.image: continue
				var img := category_state.image.duplicate()
				var settings: MaterialBakerImageSettings = get_image_settings(config)
				if settings.use_mipmaps and not img.has_mipmaps(): img.generate_mipmaps()
				if settings.compress_mode != Image.COMPRESS_MAX: img.compress(settings.compress_mode)
				category_state.compressed_image = img

				current += 1
				label.text = label_prefix + '%d / %d' % [current, total]
				await RenderingServer.frame_post_draw
				if _compress_cancelled: _compress_abort(); return

			images[baker.array_index] = category_state.compressed_image

		var uid := config.baker_category_uid
		config_by_uid[uid] = config
		images_by_uid[uid] = images

	var changed_configs: Array[MaterialBakerCategoryConfig] = []
	for uid in images_by_uid:
		var images_dict: Dictionary = images_by_uid[uid]
		if images_dict.is_empty(): continue

		var config := config_by_uid[uid]
		var texture_array := _get_texture_array(config)
		if not texture_array: continue

		var indices: Array = images_dict.keys()
		indices.sort()

		var images: Array[Image] = []
		for idx: int in indices: images.append(images_dict[idx])
		if images.is_empty(): continue

		var mipmaps_match := texture_array.has_mipmaps() == images[0].has_mipmaps()
		var format_match := texture_array.get_format() == images[0].get_format()
		if format_match and mipmaps_match: continue

		texture_array.create_from_images(images)
		texture_array.emit_changed()
		changed_configs.append(config)

	_cancel_save_timer()
	_save_all_arrays()
	_suppress_baker_rendered = false
	if not changed_configs.is_empty():
		_emit_arrays_changed_deferred(changed_configs)
	update_configuration_warnings()
	if is_instance_valid(popup): popup.queue_free()

func _get_property_list() -> Array[Dictionary]:
	var properties: Array[Dictionary] = []

	for i in category_configs.size():
		var config := category_configs[i]
		var baker_category_label := MaterialBakerCategoryConfig._label(config, i)
		properties.append({
			'name': MaterialBaker.prop_encode(1, baker_category_label),
			'type': TYPE_OBJECT,
			'usage': PROPERTY_USAGE_EDITOR,
			'hint': PROPERTY_HINT_RESOURCE_TYPE,
			'hint_string': 'Texture2DArray'
		})
	properties.append({
		'name': 'compress_arrays',
		'type': TYPE_CALLABLE,
		'usage': PROPERTY_USAGE_EDITOR,
		'hint': PROPERTY_HINT_TOOL_BUTTON,
		'hint_string': 'Compress,AssetLib',
	})
	return properties

func _get(property: StringName) -> Variant:
	var prop_str := String(property)
	if prop_str == 'compress_arrays': return compress_arrays
	var parsed := MaterialBaker.prop_decode(prop_str, 1)
	if parsed.is_empty(): return null
	var baker_category_label: String = parsed[1]
	for config in category_configs:
		if config and config.baker_category_label == baker_category_label:
			return _get_texture_array(config)
	return null

func _set(property: StringName, value: Variant) -> bool:
	var prop_str := String(property)
	var parsed := MaterialBaker.prop_decode(prop_str, 1)
	if parsed.is_empty(): return false
	var baker_category_label: String = parsed[1]
	for config in category_configs:
		if config and config.baker_category_label == baker_category_label:
			_set_texture_array(config.baker_category_uid, value)
			update_configuration_warnings()
			return true
	return false
