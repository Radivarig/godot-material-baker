@tool class_name RuntimeShaderMapper extends Node

## Emitted after shader parameters have been updated with textures.
## Connect this to any method that needs to rebuild geometry, e.g. spawn_quads in Texture2DArrayPreview.
signal mapping_applied

static func _is_external_res(path: String) -> bool:
	return path.begins_with('res://') and path.ends_with('.tres') and '::' not in path

## Maps baker_category_uid -> shader parameter name.
@export_storage var category_uid_to_param: Dictionary[String, String] = {}

@export var source: Node:
	set(value):
		source = value
		if source and material and not is_material_valid():
			_clear_mapped_params_for_material(material)
		notify_property_list_changed()

@export_storage var material: ShaderMaterial:
	set(value):
		var old_material := material
		var old_was_invalid := old_material and not _is_external_res(old_material.resource_path)

		material = value
		var is_now_valid := is_material_valid()
		update_configuration_warnings()

		# If the old material is being replaced or removed, clear its refs and save if external.
		if old_material and old_material != value:
			_clear_mapped_params_for_material(old_material)

		# Clear params immediately if material is not saved to disk
		if material and not is_now_valid:
			_clear_mapped_params_for_material(material)
		# Apply textures whenever we now have a valid material and a source
		elif is_now_valid and source:
			_apply_existing_textures()

func _get_source_configs() -> Array[MaterialBakerCategoryConfig]:
	if source is MaterialBaker: return source.category_configs
	if source is MaterialBakerArrays: return source.category_configs
	return []

func _get_property_list() -> Array[Dictionary]:
	var props: Array[Dictionary] = []
	var configs := _get_source_configs()

	if not configs.is_empty():
		props.append({
			'name': 'Category Shader Params',
			'type': TYPE_NIL,
			'usage': PROPERTY_USAGE_CATEGORY,
			'hint_string': MaterialBaker.prop_prefix(1),
		})
		for config in configs:
			if not config or config.baker_category_uid.is_empty(): continue
			props.append({
				'name': MaterialBaker.prop_encode(1, config.baker_category_uid),
				'type': TYPE_STRING,
				'usage': PROPERTY_USAGE_DEFAULT,
				'hint_string': config.baker_category_label,
			})

	props.append({
		'name': 'Shader Material',
		'type': TYPE_NIL,
		'usage': PROPERTY_USAGE_CATEGORY,
	})
	props.append({
		'name': 'material',
		'type': TYPE_OBJECT,
		'usage': PROPERTY_USAGE_DEFAULT,
		'hint': PROPERTY_HINT_RESOURCE_TYPE,
		'hint_string': 'ShaderMaterial',
	})

	return props

func _get(property: StringName) -> Variant:
	var parsed := MaterialBaker.prop_decode(str(property), 1)
	if parsed.is_empty(): return null
	var uid: String = parsed[1]
	var default_value := uid + '_array' if source is MaterialBakerArrays else uid
	return category_uid_to_param.get(uid, default_value)

func _set(property: StringName, value: Variant) -> bool:
	var parsed := MaterialBaker.prop_decode(str(property), 1)
	if parsed.is_empty(): return false
	var uid: String = parsed[1]
	category_uid_to_param[uid] = str(value)
	return true

func is_material_valid() -> bool:
	return material and _is_external_res(material.resource_path)

func _populate_default_param_mappings() -> void:
	for config in _get_source_configs():
		if config and not config.baker_category_uid.is_empty():
			var uid := config.baker_category_uid
			if not category_uid_to_param.has(uid):
				var default_value := uid + '_array' if source is MaterialBakerArrays else uid
				category_uid_to_param[uid] = default_value

func _apply_existing_textures() -> void:
	if not source: return
	if source is MaterialBaker:
		var baker := source as MaterialBaker
		on_baker_rendered(baker, baker.category_configs)
	elif source is MaterialBakerArrays:
		var arrays := source as MaterialBakerArrays
		on_arrays_changed(arrays.get_current_arrays())

func _clear_mapped_params_for_material(mat: ShaderMaterial) -> void:
	if not mat: return

	for uid: String in category_uid_to_param.keys():
		var param: String = category_uid_to_param.get(uid, uid)
		mat.set_shader_parameter(param, null)

func _clear_shader_params(configs_or_pairs: Array) -> void:
	if not material: return
	for item: Variant in configs_or_pairs:
		var uid: String
		if item is MaterialBakerCategoryConfig:
			uid = item.baker_category_uid
		elif item is Array and item.size() >= 1:
			var config := item[0] as MaterialBakerCategoryConfig
			if not config: continue
			uid = config.baker_category_uid
		else:
			continue

		var param: String = category_uid_to_param.get(uid, '')
		if param.is_empty():
			var default_value := uid + '_array' if source is MaterialBakerArrays else uid
			param = default_value
		material.set_shader_parameter(param, null)

func _ready() -> void:
	_populate_default_param_mappings()

	# Manually connect to source signals if source is set
	if source:
		if source is MaterialBaker:
			var baker := source as MaterialBaker
			if not baker.baker_rendered.is_connected(on_baker_rendered):
				baker.baker_rendered.connect(on_baker_rendered)
		elif source is MaterialBakerArrays:
			var arrays := source as MaterialBakerArrays
			if not arrays.arrays_changed.is_connected(on_arrays_changed):
				arrays.arrays_changed.connect(on_arrays_changed)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_clear_mapped_params_for_material(material)

	elif what == NOTIFICATION_EDITOR_PRE_SAVE:
		_clear_mapped_params_for_material(material)
		_prune_stale_param_mappings()

	elif what == NOTIFICATION_EDITOR_POST_SAVE:
		_apply_existing_textures()

## Call this with MaterialBakerArrays.arrays_changed signal: (Array[Array])
func on_arrays_changed(category_arrays: Array) -> void:
	if not material:
		return

	# Only apply textures if material is saved to disk
	if not is_material_valid():
		_clear_shader_params(category_arrays)
		return

	for pair: Variant in category_arrays:
		var config := pair[0] as MaterialBakerCategoryConfig
		var tex_array := pair[1] as Texture2DArray
		if not config or not tex_array: continue
		var uid := config.baker_category_uid
		var param := category_uid_to_param.get(uid, uid + '_array')
		material.set_shader_parameter(param, tex_array)
	mapping_applied.emit()

## Call this with MaterialBaker.baker_rendered signal: (MaterialBaker, Array[MaterialBakerCategoryConfig])
func on_baker_rendered(_baker: MaterialBaker, configs: Array[MaterialBakerCategoryConfig]) -> void:
	if not material: return

	# Only apply textures if material is saved to disk
	if not is_material_valid():
		_clear_shader_params(configs)
		return

	for config in configs:
		if not config: continue
		var uid := config.baker_category_uid
		var category_state := _baker.get_category_state(config)
		if not category_state or not category_state.image:
			continue

		var texture := ImageTexture.create_from_image(category_state.image)
		var param: String = category_uid_to_param.get(uid, uid)
		material.set_shader_parameter(param, texture)
	mapping_applied.emit()

func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = []
	var material_path := material.resource_path if material else ''
	if not _is_external_res(material_path):
		warnings.append('ShaderMaterial needs to be saved to disk as an external .tres file.\n\
		After saving it to disk, also save the scene!')
	return warnings

func _prune_stale_param_mappings() -> void:
	for uid in category_uid_to_param.keys():
		var param_value := category_uid_to_param.get(uid, "")
		if param_value.is_empty():
			category_uid_to_param.erase(uid)
			continue
		var found := false
		for config in _get_source_configs():
			if config and config.baker_category_uid == uid:
				found = true
				break
		if not found:
			category_uid_to_param.erase(uid)
