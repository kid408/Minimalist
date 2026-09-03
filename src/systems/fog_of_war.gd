extends Node2D
class_name FogOfWar

# 战争迷雾系统：整张地图盖一层灰色雾，玩家周围按半径挖空。
# 抽离自 arena.gd，作为独立的渲染系统，降低 Arena 上帝对象的耦合。

const Arena = preload("res://src/arena.gd")

var _player_ref: Node2D
var _fog_rect: ColorRect
var _mat: ShaderMaterial

func init(player_node: Node2D, fog_radius: float) -> void:
	_player_ref = player_node
	z_index = 50
	# 着色器：整张地图盖灰色雾，玩家周围挖空
	var shader := Shader.new()
	shader.code = _fog_shader_code()
	_mat = ShaderMaterial.new()
	_mat.shader = shader
	_mat.set_shader_parameter("player_pos", player_node.global_position)
	_mat.set_shader_parameter("radius", fog_radius)
	_mat.set_shader_parameter("map_center", Arena.MAP_CENTER)
	_mat.set_shader_parameter("map_size", Vector2(Arena.MAP_WIDTH, Arena.MAP_HEIGHT))
	_mat.set_shader_parameter("fog_color", Color(0.16, 0.17, 0.2, 1.0))
	# 铺满整张地图的雾面（ColorRect 不需要贴图，避免贴图创建失败）
	_fog_rect = ColorRect.new()
	_fog_rect.color = Color(1, 1, 1, 1)
	_fog_rect.position = Arena.MAP_CENTER - Vector2(Arena.MAP_WIDTH, Arena.MAP_HEIGHT) * 0.5
	_fog_rect.size = Vector2(Arena.MAP_WIDTH, Arena.MAP_HEIGHT)
	_fog_rect.material = _mat
	_fog_rect.z_index = 50
	add_child(_fog_rect)

func _process(_delta: float) -> void:
	if _player_ref == null or not is_instance_valid(_player_ref):
		return
	_mat.set_shader_parameter("player_pos", _player_ref.global_position)

func _fog_shader_code() -> String:
	return """shader_type canvas_item;
uniform vec2 player_pos;
uniform float radius;
uniform vec2 map_center;
uniform vec2 map_size;
uniform vec4 fog_color;

void fragment() {
	vec2 world = map_center + (UV - vec2(0.5)) * map_size;
	float d = distance(world, player_pos);
	// 中心清晰，外圈渐变为灰色迷雾（内 18% 完全清晰，半径除零保护）
	float a = smoothstep(0.18, 1.0, d / max(radius, 1.0));
	COLOR = vec4(fog_color.rgb, fog_color.a * a);
}
"""
