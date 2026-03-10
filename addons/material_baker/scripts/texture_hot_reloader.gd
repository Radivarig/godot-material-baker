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

# cannot use EditorInterface directly as it does not exist in build and breaks
func getEditorInterface() -> Variant: return Engine.get_singleton(&'EditorInterface')

func _enter_tree() -> void:
	if not Engine.is_editor_hint(): return
	getEditorInterface().get_resource_filesystem().resources_reimported.connect(_on_resources_reimported)
	_timer = Timer.new()
	_timer.wait_time = 0.3
	_timer.timeout.connect(_resource_changed_handler)
	add_child(_timer)
	_timer.start()

func _exit_tree() -> void:
	if not Engine.is_editor_hint(): return
	getEditorInterface().get_resource_filesystem().resources_reimported.disconnect(_on_resources_reimported)

func _resource_changed_handler() -> void:
	if getEditorInterface().get_editor_main_screen().get_window().has_focus(): return
	var changed := _get_changed_resources()
	if changed.is_empty(): return
	_reload_changed_textures(changed)

func _on_resources_reimported(resources: PackedStringArray) -> void:
	var affected_materials: Array[ShaderMaterial] = []
	for path in resources:
		for mat: ShaderMaterial in _mat_param_path:
			for param: String in _mat_param_path[mat]:
				if _mat_param_path[mat][param] != path: continue
				var tex := ResourceLoader.load(path, '', ResourceLoader.CACHE_MODE_REPLACE)
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
			if not FileAccess.file_exists(absolute_path): continue
			var current_time := FileAccess.get_modified_time(absolute_path)
			if current_time != _modified_times.get(resource_path, 0):
				_update_modified_time(resource_path)
				changed.append(resource_path)
	return changed

func _reload_changed_textures(changed_resources: Array[String]) -> void:
	for resource_path in changed_resources:
		var absolute_path := ProjectSettings.globalize_path(resource_path)
		var img := Image.new()
		if img.load(absolute_path) != OK: continue

		for mat: ShaderMaterial in _mat_param_path:
			for param: String in _mat_param_path[mat]:
				if _mat_param_path[mat][param] != resource_path: continue
				var existing_tex: Variant = mat.get_shader_parameter(param)
				if existing_tex is ImageTexture: existing_tex.set_image(img)
				else:
					var image_tex := ImageTexture.create_from_image(img)
					mat.set_shader_parameter(param, image_tex)
				texture_changed.emit(mat)
