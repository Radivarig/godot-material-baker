@tool class_name Terrain3DMaterialBaker extends MaterialBakerManager

# NOTE: to stop focus loss comment out terrain3d asset_dock.gd:668 # plugin.select_terrain()
@export var terrain3d: Node # Terrain3D

var albedo_height_category: MaterialBakerCategoryConfig
var normal_roughness_category: MaterialBakerCategoryConfig

func _init() -> void:
	if category_configs.size() == 0:
		var categories_dir: String = get_script().resource_path.get_base_dir() + '/../../categories/'
		albedo_height_category = load(categories_dir + 'albedo_height_category.tres')
		normal_roughness_category = load(categories_dir + 'normal_roughness_category.tres')
		category_configs = [albedo_height_category, normal_roughness_category]

func _ready() -> void:
	if not terrain3d:
		var terrain3d_nodes := get_tree().root.find_children('*', 'Terrain3D', true, false)
		if terrain3d_nodes.is_empty(): push_error('No Terrain3D node found in the scene.')
		else: terrain3d = terrain3d_nodes[0]

func baker_rendered(baker: MaterialBaker, c: MaterialBakerCategoryConfig = null) -> void:
	update_terrain3d_textures(baker, c)

func regenerate() -> void:
	for baker in connected_bakers:
		update_terrain3d_textures(baker, null)

func update_terrain3d_textures(baker: MaterialBaker, c: MaterialBakerCategoryConfig = null) -> void:
	if not terrain3d or not terrain3d.assets or not terrain3d.assets.texture_list: return
	if baker.array_index < 0 or baker.array_index >= terrain3d.assets.texture_list.size(): return

	var terrain_texture: Variant = terrain3d.assets.texture_list[baker.array_index]

	for config in baker.category_configs:
		if c != null and config != c: continue # this updates for a single baker_category_label if passed
		# print('Updating Terrain3D texture for baker: ', baker.name, ' (', config.baker_category_label, ')')

		var category_state := baker.get_category_state(config)
		if not category_state or not category_state.image: continue

		match config.baker_category_uid:
			albedo_height_category.baker_category_uid: 
				terrain_texture.albedo_texture = ImageTexture.create_from_image(category_state.image)
			normal_roughness_category.baker_category_uid: 
				terrain_texture.normal_texture = ImageTexture.create_from_image(category_state.image)
