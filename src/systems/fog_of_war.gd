extends Node2D
class_name FogOfWar

const CELL_SIZE := 64.0
const UPDATE_INTERVAL := 0.12
const DEFAULT_SUMMON_VISION := 420.0

var _player_ref: Node2D
var _layout: Node
var _fog_rect: ColorRect
var _mat: ShaderMaterial
var _world_size := Vector2.ZERO
var _grid_size := Vector2i.ZERO
var _explored := PackedByteArray()
var _visible := PackedByteArray()
var _explored_image: Image
var _visible_image: Image
var _minimap_image: Image
var _explored_texture: ImageTexture
var _visible_texture: ImageTexture
var _minimap_fog_texture: ImageTexture
var _update_left := 0.0


func init(player_node: Node2D, fog_radius: float, _clear_ratio: float = 0.45, layout: Node = null, world_size: Vector2 = Vector2(6000, 4200)) -> void:
	_player_ref = player_node
	_layout = layout
	_world_size = world_size
	_grid_size = Vector2i(int(ceili(_world_size.x / CELL_SIZE)), int(ceili(_world_size.y / CELL_SIZE)))
	var cell_count := _grid_size.x * _grid_size.y
	_explored.resize(cell_count)
	_visible.resize(cell_count)
	_explored_image = Image.create(_grid_size.x, _grid_size.y, false, Image.FORMAT_RGBA8)
	_visible_image = Image.create(_grid_size.x, _grid_size.y, false, Image.FORMAT_RGBA8)
	_minimap_image = Image.create(_grid_size.x, _grid_size.y, false, Image.FORMAT_RGBA8)
	_explored_texture = ImageTexture.create_from_image(_explored_image)
	_visible_texture = ImageTexture.create_from_image(_visible_image)
	_minimap_fog_texture = ImageTexture.create_from_image(_minimap_image)

	if _player_ref != null:
		_player_ref.add_to_group("vision_source")
		_player_ref.set_meta("vision_radius", fog_radius)

	z_index = 50
	var shader := Shader.new()
	shader.code = _fog_shader_code()
	_mat = ShaderMaterial.new()
	_mat.shader = shader
	_mat.set_shader_parameter("explored_tex", _explored_texture)
	_mat.set_shader_parameter("visible_tex", _visible_texture)
	_mat.set_shader_parameter("fog_color", Color(0.045, 0.06, 0.09, 0.94))

	_fog_rect = ColorRect.new()
	_fog_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fog_rect.color = Color.WHITE
	_fog_rect.position = Vector2.ZERO
	_fog_rect.size = _world_size
	_fog_rect.material = _mat
	_fog_rect.z_index = 50
	add_child(_fog_rect)
	_rebuild_visibility()


func _process(delta: float) -> void:
	_update_left -= delta
	if _update_left <= 0.0:
		_update_left = UPDATE_INTERVAL
		_rebuild_visibility()


func is_position_visible(world_pos: Vector2) -> bool:
	var index := _world_to_index(world_pos)
	return index >= 0 and _visible[index] > 0


func is_explored(world_pos: Vector2) -> bool:
	var index := _world_to_index(world_pos)
	return index >= 0 and _explored[index] > 0


func get_minimap_fog_texture() -> Texture2D:
	return _minimap_fog_texture


func get_grid_size() -> Vector2i:
	return _grid_size


func _rebuild_visibility() -> void:
	if _grid_size.x <= 0 or _grid_size.y <= 0:
		return
	for i in range(_visible.size()):
		_visible[i] = 0
	for source in get_tree().get_nodes_in_group("vision_source"):
		if source is Node2D and is_instance_valid(source):
			_reveal_from(source as Node2D)
	_update_textures()


func _reveal_from(source: Node2D) -> void:
	var radius := float(source.get_meta("vision_radius", DEFAULT_SUMMON_VISION))
	if radius <= 0.0:
		return
	var min_cell := _world_to_cell(source.global_position - Vector2.ONE * radius)
	var max_cell := _world_to_cell(source.global_position + Vector2.ONE * radius)
	min_cell.x = maxi(min_cell.x, 0)
	min_cell.y = maxi(min_cell.y, 0)
	max_cell.x = mini(max_cell.x, _grid_size.x - 1)
	max_cell.y = mini(max_cell.y, _grid_size.y - 1)
	var radius_sq := radius * radius
	for y in range(min_cell.y, max_cell.y + 1):
		for x in range(min_cell.x, max_cell.x + 1):
			var world_pos := _cell_to_world(Vector2i(x, y))
			if source.global_position.distance_squared_to(world_pos) > radius_sq:
				continue
			if _layout != null and _layout.has_method("is_segment_blocked") and _layout.is_segment_blocked(source.global_position, world_pos, 2.0):
				continue
			var index := y * _grid_size.x + x
			_visible[index] = 255
			_explored[index] = 255


func _update_textures() -> void:
	for y in range(_grid_size.y):
		for x in range(_grid_size.x):
			var index := y * _grid_size.x + x
			var explored_value := float(_explored[index]) / 255.0
			var visible_value := float(_visible[index]) / 255.0
			_explored_image.set_pixel(x, y, Color(explored_value, explored_value, explored_value, 1.0))
			_visible_image.set_pixel(x, y, Color(visible_value, visible_value, visible_value, 1.0))
			var minimap_color := Color(0.0, 0.0, 0.0, 0.92)
			if visible_value > 0.0:
				minimap_color = Color(0.0, 0.0, 0.0, 0.0)
			elif explored_value > 0.0:
				minimap_color = Color(0.02, 0.04, 0.07, 0.58)
			_minimap_image.set_pixel(x, y, minimap_color)
	_explored_texture.update(_explored_image)
	_visible_texture.update(_visible_image)
	_minimap_fog_texture.update(_minimap_image)


func _world_to_index(world_pos: Vector2) -> int:
	var cell := _world_to_cell(world_pos)
	if cell.x < 0 or cell.y < 0 or cell.x >= _grid_size.x or cell.y >= _grid_size.y:
		return -1
	return cell.y * _grid_size.x + cell.x


func _world_to_cell(world_pos: Vector2) -> Vector2i:
	return Vector2i(int(floor(world_pos.x / CELL_SIZE)), int(floor(world_pos.y / CELL_SIZE)))


func _cell_to_world(cell: Vector2i) -> Vector2:
	return Vector2((float(cell.x) + 0.5) * CELL_SIZE, (float(cell.y) + 0.5) * CELL_SIZE)


func _fog_shader_code() -> String:
	return """shader_type canvas_item;
uniform sampler2D explored_tex : filter_nearest;
uniform sampler2D visible_tex : filter_nearest;
uniform vec4 fog_color;

void fragment() {
	float explored = texture(explored_tex, UV).r;
	float visible = texture(visible_tex, UV).r;
	float alpha = 0.0;
	if (visible < 0.5) {
		alpha = explored > 0.5 ? 0.56 : 0.96;
	}
	COLOR = vec4(fog_color.rgb, fog_color.a * alpha);
}
"""
