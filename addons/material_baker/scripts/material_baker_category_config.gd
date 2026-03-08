@tool class_name MaterialBakerCategoryConfig extends Resource

## For use in MaterialBakerArrays to identify which bakers should be grouped.[br]
## E.g. Albedo & Height, Normal & Roughness, Specular & Metallic.
@export var baker_category_label: String = '':
	set(value):
		if baker_category_label == value: return
		if not baker_category_label.is_empty():
			_baker_category_label_dirty = true
		baker_category_label = MaterialBaker.prop_strip_prefix(value)
		changed.emit()
var _baker_category_label_dirty: bool

## NOTE: shader blend mode must be set to premul_alpha
@export var default_shader: Shader:
	set(value):
		default_shader = value
		changed.emit()

static func _label(config: MaterialBakerCategoryConfig, i: int) -> String:
	return config.baker_category_label if config.baker_category_label else 'index %d: baker_category_label (empty)' % i

@export_group('UID')
@export_subgroup('(do not change)')
## Hard unique ID used as key for baker state and texture arrays.[br]
## E.g. 'albedo_height', 'normal_roughness'. Must be unique across all configs in a manager.
## Changing this after creating bakers will make them lose all assigned shader parameters and textures.
@export var baker_category_uid: String = ''
