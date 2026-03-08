@tool class_name MaterialBakerCategory extends Node

var config: MaterialBakerCategoryConfig = MaterialBakerCategoryConfig.new()
var state: MaterialBakerCategoryState = MaterialBakerCategoryState.new()
var image_settings: MaterialBakerImageSettings = MaterialBakerImageSettings.new()

var _viewport: SubViewport
var _color_rect: ColorRect

func _ready() -> void:
	_viewport = SubViewport.new()
	_viewport.transparent_bg = true
	add_child(_viewport)

	_color_rect = ColorRect.new()
	_color_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_viewport.add_child(_color_rect)

func bake() -> Image:
	_color_rect.material = state.material
	if _viewport.size != image_settings.size:
		_viewport.size = image_settings.size
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

	await RenderingServer.frame_post_draw

	return _viewport.get_texture().get_image()
