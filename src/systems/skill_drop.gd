extends Area2D
class_name SkillDrop

const GameData = preload("res://src/data/game_data.gd")
const DISPLAY_NAME_RANGE := 360.0

var item_data: Dictionary = {}
var item_type: String = ""
var _player_near: bool = false
var _next_redraw: float = 0.0

func _init(data: Dictionary) -> void:
	item_data = data.duplicate(true)
	var cast_type := String(data.get("cast_type", ""))
	item_type = "equipment" if cast_type.is_empty() else "skill"

func _ready() -> void:
	var tex := _load_icon(String(item_data.get("icon", "")))
	if tex:
		var sprite := Sprite2D.new()
		sprite.texture = tex
		sprite.scale = Vector2(0.6, 0.6)
		add_child(sprite)

	var collision := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 32.0
	collision.shape = circle
	add_child(collision)

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	queue_redraw()

func _load_icon(path: String) -> Texture2D:
	if path.is_empty():
		return null
	return load(path) as Texture2D

func _draw() -> void:
	var quality := String(item_data.get("quality", "white"))
	var cast_type := String(item_data.get("cast_type", ""))
	var is_equip := item_type == "equipment"

	var color: Color
	if is_equip:
		color = Color(0.92, 0.70, 0.22, 0.4)
	else:
		color = Color(0.92, 0.35, 0.25, 0.4)

	match quality:
		"purple":
			color = color.lightened(0.3)
			color.a = 0.55
		"blue":
			color = color.lightened(0.15)
			color.a = 0.45

	draw_circle(Vector2.ZERO, 22, color)

	# 距离近时显示名字
	if _player_near:
		var name_txt: String = item_data.get("name", "物品")
		var type_txt: String
		if is_equip:
			type_txt = "装备"
		else:
			type_txt = "主动"
		var font := ThemeDB.fallback_font
		draw_string(font, Vector2(-50, -30), "%s · %s" % [name_txt, type_txt], HORIZONTAL_ALIGNMENT_CENTER, 100, 12)

func _on_body_entered(_body: Node2D) -> void:
	_player_near = true
	queue_redraw()

func _on_body_exited(_body: Node2D) -> void:
	_player_near = false
	queue_redraw()

func _process(delta: float) -> void:
	# 距离兜底：不用 body_entered 也检测玩家距离
	_next_redraw -= delta
	if _next_redraw > 0:
		return
	_next_redraw = 0.25

	var player := _find_player()
	if player == null:
		return
	var dist: float = global_position.distance_to(player.global_position)
	if dist <= 60.0 and not _player_near:
		_player_near = true
		queue_redraw()
	elif dist > 80.0 and _player_near:
		_player_near = false
		queue_redraw()

func _find_player() -> Node2D:
	var parent := get_parent()
	if parent and parent.has_method("get_player"):
		return parent.get_player()
	var tree := get_tree()
	if tree:
		for node in tree.get_nodes_in_group("player"):
			return node as Node2D
	return null

func can_pickup(_player_pos: Vector2) -> bool:
	return true
