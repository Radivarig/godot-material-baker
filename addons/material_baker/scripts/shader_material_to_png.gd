@tool class_name ShaderToPNG extends MaterialBakerCategory

@export var bake_material: ShaderMaterial:
	set(value):
		bake_material = value
		_sync_state()

@export var size: Vector2i = Vector2i(1024, 1024):
	set(value):
		size = value
		_sync_config()

func _ready() -> void:
	super._ready()
	_sync_config()
	_sync_state()

func _sync_config() -> void:
	if not config: config = MaterialBakerCategoryConfig.new()
	if not image_settings: image_settings = MaterialBakerImageSettings.new()

func _sync_state() -> void:
	if not state: state = MaterialBakerCategoryState.new()
	state.material = bake_material

@export var output_png_path: String = 'res://material_baker_result.png'

## Optional: a PNG file whose .import settings will be used for the generated file.
@export_file('*.png') var use_import_settings_from: String = ''

@export_tool_button('Save as PNG', 'Save') var save_as_png := func() -> void:
	var image := await bake()
	if not image:
		push_error('ImageToPNG: bake() returned null — make sure config and state are set.')
		return

	var path := output_png_path.strip_edges()
	if path.begins_with("uid://"):
		path = ResourceUID.get_id_path(ResourceUID.text_to_id(path))
	if path.is_empty():
		push_error('ImageToPNG: output_png_path is empty.')
		return

	var err: int = image.save_png(path)
	if err != OK:
		push_error('ImageToPNG: failed to save PNG to "%s" (error %d).' % [path, err])
		return

	# Snapshot before scan() so Godot's UID remapping cannot overwrite this value.
	var ref_path := use_import_settings_from.strip_edges()
	if ref_path.begins_with('uid://'):
		ref_path = ResourceUID.get_id_path(ResourceUID.text_to_id(ref_path))

	if not ref_path.is_empty() and Engine.is_editor_hint():
		var ref_import := ProjectSettings.globalize_path(ref_path) + '.import'
		var dst_import := ProjectSettings.globalize_path(path) + '.import'
		if FileAccess.file_exists(ref_import):
			var src_file := FileAccess.open(ref_import, FileAccess.READ)
			var content := src_file.get_as_text()
			src_file.close()

			var dst_filename := path.get_file()                   # e.g. "result.png"
			var dst_res_path := path                              # e.g. "res://result.png"

			# Strip the uid so Godot assigns a fresh one on reimport,
			# preventing the reference file's UID from being remapped to the new path.
			var uid_regex := RegEx.new()
			uid_regex.compile('uid="uid://[a-z0-9]+"')
			content = uid_regex.sub(content, 'uid=""')

			# Rewrite the cached .ctex path — it encodes the source filename and a hash.
			# Replace it with just the destination filename; Godot will regenerate the full path.
			var ctex_regex := RegEx.new()
			ctex_regex.compile('path="res://\\.godot/imported/[^"]*\\.ctex"')
			content = ctex_regex.sub(content, 'path="res://.godot/imported/%s.ctex"' % dst_filename)

			# Rewrite dest_files array similarly.
			var dest_regex := RegEx.new()
			dest_regex.compile('dest_files=\\["res://\\.godot/imported/[^"]*\\.ctex"\\]')
			content = dest_regex.sub(content, 'dest_files=["res://.godot/imported/%s.ctex"]' % dst_filename)

			# Rewrite source_file to the destination res:// path.
			var src_regex := RegEx.new()
			src_regex.compile('source_file="[^"]*"')
			content = src_regex.sub(content, 'source_file="%s"' % dst_res_path)

			var dst_file := FileAccess.open(dst_import, FileAccess.WRITE)
			if dst_file:
				dst_file.store_string(content)
				dst_file.close()
			else:
				push_error('ImageToPNG: could not write import file "%s".' % dst_import)
		else:
			push_warning('ImageToPNG: use_import_settings_from has no .import file at "%s".' % ref_import)

	if Engine.is_editor_hint():
		Engine.get_singleton(&'EditorInterface').get_resource_filesystem().scan()
