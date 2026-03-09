@tool class_name Texture2DArrayPreview extends MultiMeshInstance3D

@export_range(0.0, 0.5) var spacing: float = 0.1:
	set(value):
		spacing = value
		spawn_quads()

@export_range(0.1, 2.0) var quad_size: float = 1.0:
	set(value):
		quad_size = value
		spawn_quads()

@export_range(1, 64) var subdivision: int = 32:
	set(value):
		subdivision = value
		spawn_quads()

@export var base_material: ShaderMaterial:
	set(value):
		base_material = value
		spawn_quads()

var array_param: String = 'albedo_height_array'

func _init() -> void:
	multimesh = MultiMesh.new()

func spawn_quads() -> void:
	if not base_material: return

	var tex_array := base_material.get_shader_parameter(array_param) as Texture2DArray
	var array_length := tex_array.get_layers() if tex_array else 0
	if array_length == 0:
		material_override = null
		return

	material_override = base_material
	var columns := ceili(sqrt(array_length))

	if array_length == 0: return

	var quad_mesh := QuadMesh.new()
	quad_mesh.size = Vector2(quad_size, quad_size)
	quad_mesh.subdivide_width = subdivision
	quad_mesh.subdivide_depth = subdivision

	var new_multimesh := MultiMesh.new()
	new_multimesh.mesh = quad_mesh
	new_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	new_multimesh.use_custom_data = true
	new_multimesh.instance_count = array_length

	for i in range(array_length):
		var row := int(float(i) / float(columns))
		var col := i % columns

		var _transform := Transform3D()
		_transform = _transform.rotated(Vector3(1, 0, 0), -PI / 2.0)
		var offset := quad_size / 2.0
		_transform.origin = Vector3(col * (quad_size + spacing) + offset, 0, row * (quad_size + spacing) + offset)

		new_multimesh.set_instance_transform(i, _transform)
		new_multimesh.set_instance_custom_data(i, Color(float(i), 0, 0, 0))

	multimesh = new_multimesh
