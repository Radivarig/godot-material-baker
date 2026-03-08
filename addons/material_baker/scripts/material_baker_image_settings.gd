@tool class_name MaterialBakerImageSettings extends Resource

@export var is_size_square: bool = true:
	set(value):
		if is_size_square == value: return
		if not is_size_square and value: # if enabling
			size = Vector2i(size.x, size.x)
		is_size_square = value
		# do not emit change here, size setter will do it

@export var size: Vector2i = Vector2i(1024, 1024):
	set(value):
		if size == value: return
		if value.x < 1: value.x = 1
		if value.y < 1: value.y = 1
		if compress_mode != Image.COMPRESS_MAX:
			value.x = int(ceil(value.x / 4.0)) * 4
			value.y = int(ceil(value.y / 4.0)) * 4
		if is_size_square:
			if value.x == size.x:
				size = Vector2i(value.y, value.y)
			else: size = Vector2i(value.x, value.x)
		else: size = value
		changed.emit()

@export var use_mipmaps: bool = true:
	set(value):
		if use_mipmaps == value: return
		use_mipmaps = value
		changed.emit()

## Compression adds a performance hit so it's disabled on edit.
## After you're done editing click the Compress button on the Arrays node.
@export_enum('S3TC', 'ETC', 'ETC2', 'BPTC', 'ASTC', 'None')
var compress_mode: int = Image.COMPRESS_BPTC:
	set(value):
		if compress_mode == value: return
		compress_mode = value
		var _s := size; size = Vector2i(-1, -1); size = _s # re-apply size constraints for new compress_mode
		changed.emit()
