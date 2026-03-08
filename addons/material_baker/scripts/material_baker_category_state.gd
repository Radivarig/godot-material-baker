@tool class_name MaterialBakerCategoryState extends Resource

@export var material: ShaderMaterial = ShaderMaterial.new()
@export var shader: Shader:
	set(value):
		shader = value
		material.shader = shader
		changed.emit()

# cache
var image: Image
var compressed_image: Image
