@tool class_name TextureHotReloader extends Node

signal texture_changed(mat: ShaderMaterial)

## See MaterialBaker for usage in script, or set material references here
@export var materials: Array[ShaderMaterial] = []:
	set(value):
		for mat in materials:
			if not value.has(mat): unregister_material(mat)
		materials = value
		for mat in materials: register_material(mat)

## Register a ShaderMaterial so that its Texture2D parameters are watched for external file changes
func register_material(mat: ShaderMaterial) -> void:
	if not mat or not mat.shader: return
	var shader_params := RenderingServer.get_shader_parameter_list(mat.shader.get_rid())

	for param in shader_params:
		if param.hint != PROPERTY_HINT_RESOURCE_TYPE or param.hint_string != 'Texture2D': continue
		var texture: Variant = mat.get_shader_parameter(param.name)
		if texture is not Texture2D: continue
		var resource_path: String = texture.resource_path
		if not resource_path.begins_with('res://'): continue
		var old_path: String = _mat_param_path.get(mat, {}).get(param.name, '')
		if old_path == resource_path: continue
		if not _mat_param_path.has(mat): _mat_param_path[mat] = {}

		_mat_param_path[mat][param.name] = resource_path
		_update_modified_time(resource_path)

func unregister_material(mat: ShaderMaterial) -> void:
	if not _mat_param_path.has(mat): return
	_mat_param_path.erase(mat)

var _mat_param_path: Dictionary = {} # [ShaderMaterial, [param_name, resource_path]]
var _modified_times: Dictionary = {} # [resource_path, time]
var _timer: Timer
var _had_focus := false
var _hotswapped_resources: Dictionary = {} # [resource_path, bool] - track which resources were hot-swapped

# cannot use EditorInterface directly as it does not exist in build and breaks
func getEditorInterface() -> Variant: return Engine.get_singleton(&'EditorInterface')

func get_current_focus() -> bool:
	return getEditorInterface().get_editor_main_screen().get_window().has_focus()

func _enter_tree() -> void:
	if not Engine.is_editor_hint(): return
	getEditorInterface().get_resource_filesystem().resources_reimported.connect(_on_resources_reimported)
	_timer = Timer.new()
	_timer.wait_time = 0.3
	_timer.timeout.connect(_check_for_changes)
	add_child(_timer)
	_had_focus = get_current_focus()

func _exit_tree() -> void:
	if not Engine.is_editor_hint(): return
	getEditorInterface().get_resource_filesystem().resources_reimported.disconnect(_on_resources_reimported)

func _process(_delta: float) -> void:
	if not Engine.is_editor_hint(): return
	_handle_focus_change()

func _handle_focus_change() -> void:
	var has_focus: bool = get_current_focus()

	if has_focus != _had_focus:
		if has_focus:
			_timer.stop()
			_modified_times.clear()
			if not _hotswapped_resources.is_empty():
				_check_and_reimport_if_needed.call_deferred()
		else:
			# Re-register materials to pick up any path changes from reimports
			for mat: ShaderMaterial in _mat_param_path.keys():
				register_material(mat)
			# Initialize modified times for all tracked paths
			for mat: ShaderMaterial in _mat_param_path:
				for param: String in _mat_param_path[mat]:
					var resource_path: String = _mat_param_path[mat][param]
					var absolute_path := ProjectSettings.globalize_path(resource_path)
					if FileAccess.file_exists(absolute_path):
						_update_modified_time(resource_path)
			_timer.start()
		_had_focus = has_focus

func _check_for_changes() -> void:
	if get_current_focus(): return
	var changed := _get_changed_resources()
	if changed.is_empty(): return
	_reload_changed_textures(changed)

func _check_and_reimport_if_needed() -> void:
	await get_tree().create_timer(0.5).timeout
	if _hotswapped_resources.is_empty(): return

	print('[TextureHotReloader] Godot did not reimport ', _hotswapped_resources.size(), ' resources, forcing reimport')
	var filesystem: Variant = getEditorInterface().get_resource_filesystem()
	for resource_path in _hotswapped_resources.keys():
		filesystem.reimport_files(PackedStringArray([resource_path]))

func _on_resources_reimported(resources: PackedStringArray) -> void:
	var affected_materials: Array[ShaderMaterial] = []
	var processed_path_textures: Dictionary = {}  # [path, Texture2D]

	for path in resources:
		if processed_path_textures.has(path): continue
		if _hotswapped_resources.has(path): _hotswapped_resources.erase(path)

		var tex := ResourceLoader.load(path, '', ResourceLoader.CACHE_MODE_REPLACE)
		processed_path_textures[path] = tex

		for mat: ShaderMaterial in _mat_param_path:
			for param: String in _mat_param_path[mat]:
				if _mat_param_path[mat][param] != path: continue
				mat.set_shader_parameter(param, tex)
				if not affected_materials.has(mat):
					affected_materials.append(mat)

	for mat in affected_materials: texture_changed.emit(mat)

func _update_modified_time(resource_path: String) -> void:
	var absolute_path := ProjectSettings.globalize_path(resource_path)
	if not FileAccess.file_exists(absolute_path): return
	_modified_times[resource_path] = FileAccess.get_modified_time(absolute_path)

func _get_changed_resources() -> Array[String]:
	var changed: Array[String] = []
	var seen: Dictionary = {}
	for mat: ShaderMaterial in _mat_param_path:
		for param: String in _mat_param_path[mat]:
			var resource_path: String = _mat_param_path[mat][param]
			if seen.has(resource_path): continue
			seen[resource_path] = true
			var absolute_path := ProjectSettings.globalize_path(resource_path)
			if not FileAccess.file_exists(absolute_path):
				_modified_times.erase(resource_path) # File was moved/deleted
				continue
			var current_time := FileAccess.get_modified_time(absolute_path)
			if current_time != _modified_times.get(resource_path, 0):
				_update_modified_time(resource_path)
				changed.append(resource_path)
	return changed

func _reload_changed_textures(changed_resources: Array[String]) -> void:
	for resource_path in changed_resources:
		var absolute_path := ProjectSettings.globalize_path(resource_path)
		var img := Image.new()
		var load_result := img.load(absolute_path)
		if load_result != OK:
			push_warning('[TextureHotReloader] Failed to load image: "%s" (%d).' % [absolute_path, load_result])
			continue
		_hotswapped_resources[resource_path] = true

		for mat: ShaderMaterial in _mat_param_path:
			for param: String in _mat_param_path[mat]:
				if _mat_param_path[mat][param] != resource_path: continue
				var existing_tex: Variant = mat.get_shader_parameter(param)
				if existing_tex is ImageTexture: existing_tex.set_image(img)
				else:
					var image_tex := ImageTexture.create_from_image(img)
					mat.set_shader_parameter(param, image_tex)
				texture_changed.emit(mat)
