@tool class_name RuntimeShaderArrays extends Node

## Emitted after shader parameters have been updated with the latest arrays.
## Connect this to any method that needs to rebuild geometry, e.g. spawn_quads in Texture2DArrayPreview.
signal arrays_applied

@export var material: ShaderMaterial:
	set(value):
		material = value
		_apply_all_arrays()

@export var arrays_node: MaterialBakerArrays:
	set(value):
		_disconnect_arrays_node()
		arrays_node = value
		_connect_arrays_node()
		notify_property_list_changed()
		if arrays_node and is_inside_tree():
			_apply_all_arrays()

## Maps baker_category_uid -> shader parameter name.
## Populated dynamically from arrays_node category configs.
var category_uid_to_param: Dictionary[String, String] = {}

func _get_property_list() -> Array[Dictionary]:
	var props: Array[Dictionary] = []
	if not arrays_node: return props
	props.append({
		'name': 'Category Shader Params',
		'type': TYPE_NIL,
		'usage': PROPERTY_USAGE_CATEGORY,
		'hint_string': 'param_',
	})
	for config in arrays_node.category_configs:
		if not config or config.baker_category_uid.is_empty(): continue
		props.append({
			'name': 'param_' + config.baker_category_uid,
			'type': TYPE_STRING,
			'usage': PROPERTY_USAGE_DEFAULT,
		})
	return props

func _get(property: StringName) -> Variant:
	var s := str(property)
	if s.begins_with('param_'):
		var uid := s.substr(6)
		return category_uid_to_param.get(uid, uid + '_array')
	return null

func _set(property: StringName, value: Variant) -> bool:
	var s := str(property)
	if s.begins_with('param_'):
		var uid := s.substr(6)
		category_uid_to_param[uid] = str(value)
		_apply_for_uid(uid)
		return true
	return false

func _ready() -> void:
	_connect_arrays_node()
	if arrays_node:
		_apply_all_arrays()

func _notification(what: int) -> void:
	if what == NOTIFICATION_EDITOR_PRE_SAVE:
		# Before saving: replace runtime arrays with their saved .res counterparts
		# (or null) so they are never inlined into the scene file.
		if not material or not arrays_node: return
		for config in arrays_node.category_configs:
			if not config or config.baker_category_uid.is_empty(): continue
			var uid := config.baker_category_uid
			var param: String = category_uid_to_param.get(uid, uid + '_array')
			var saved_res: Texture2DArray = arrays_node.texture2d_arrays_res.get(uid, null)
			var value: Texture2DArray = null
			if saved_res and ResourceLoader.exists(saved_res.resource_path):
				value = load(saved_res.resource_path)
			material.set_shader_parameter(param, value)

	elif what == NOTIFICATION_EDITOR_POST_SAVE:
		# After saving: restore the live runtime arrays.
		_apply_all_arrays.call_deferred()


func _all_arrays_ready() -> bool:
	if not material or not arrays_node: return false
	for config in arrays_node.category_configs:
		if not config or config.baker_category_uid.is_empty(): continue
		var param := category_uid_to_param.get(config.baker_category_uid, config.baker_category_uid + '_array')
		var arr := material.get_shader_parameter(param) as Texture2DArray
		if not arr or arr.get_layers() == 0: return false
	return true

func _connect_arrays_node() -> void:
	if not arrays_node: return
	if not arrays_node.arrays_changed.is_connected(_on_arrays_changed):
		arrays_node.arrays_changed.connect(_on_arrays_changed)

func _disconnect_arrays_node() -> void:
	if not arrays_node: return
	if arrays_node.arrays_changed.is_connected(_on_arrays_changed):
		arrays_node.arrays_changed.disconnect(_on_arrays_changed)

func _on_arrays_changed(category_arrays: Array) -> void:
	if not material: return
	for pair: Variant in category_arrays:
		var config := pair[0] as MaterialBakerCategoryConfig
		var tex_array := pair[1] as Texture2DArray
		if not config or not tex_array: continue
		var uid := config.baker_category_uid
		var param := category_uid_to_param.get(uid, uid + '_array')
		material.set_shader_parameter(param, tex_array)
	if _all_arrays_ready(): arrays_applied.emit()

func _apply_for_uid(uid: String) -> void:
	if not material or not arrays_node: return
	var param := category_uid_to_param.get(uid, uid + '_array')
	for config in arrays_node.category_configs:
		if config and config.baker_category_uid == uid:
			var tex_array := arrays_node._get_texture_array(config)
			if tex_array and tex_array.get_layers() > 0:
				material.set_shader_parameter(param, tex_array)
			return

func _apply_all_arrays() -> void:
	if not material or not arrays_node: return
	for config in arrays_node.category_configs:
		if config and not config.baker_category_uid.is_empty():
			_apply_for_uid(config.baker_category_uid)
	if _all_arrays_ready(): arrays_applied.emit()
