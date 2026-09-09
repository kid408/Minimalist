extends Area2D
class_name MerchantNPC

const GameData = preload("res://src/data/game_data.gd")
const MOVE_SPEED := 80.0
const IDLE_DURATION := 4.0
const POST_TRADE_WAIT := 30.0
const REFRESH_INTERVAL := 60.0

# 游走边界（由生成方 WorldSystem 注入当前地图尺寸；默认值为保守下限）
var map_size := Vector2(2520.0, 1800.0)

var move_direction: Vector2 = Vector2.RIGHT
var idle_timer: float = 0.0
var post_trade_timer: float = 0.0
var refresh_timer: float = 0.0
var current_merchandise: Array = []
var player_nearby: Node2D = null
var world_layout: Node = null
var is_trading := false

func _ready() -> void:
	add_to_group("merchants")
	collision_layer = 0
	collision_mask = 1
	var collision := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 44.0
	collision.shape = shape
	add_child(collision)
	randomize()
	move_direction = Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized()
	_refresh_merchandise()
	_create_label()

func _create_label() -> void:
	var label := Label.new()
	label.name = "Nametag"
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.position = Vector2(-40, -36)
	label.size = Vector2(80, 24)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 14)
	label.modulate = Color(0.92, 0.82, 0.38, 1.0)
	label.text = "商人"
	label.visible = true
	add_child(label)

	var prompt := Label.new()
	prompt.name = "Prompt"
	prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prompt.position = Vector2(-60, -56)
	prompt.size = Vector2(120, 18)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.add_theme_font_size_override("font_size", 12)
	prompt.modulate = Color(1, 1, 0.7, 1)
	prompt.text = "按 Space 交易"
	prompt.visible = false
	add_child(prompt)

	body_entered.connect(func(b: Node): _set_nearby(b, true))
	body_exited.connect(func(b: Node): _set_nearby(b, false))

func _set_nearby(body: Node, entering: bool) -> void:
	# 只有玩家触发交易提示（敌人/召唤物/掉落物进入区域时忽略）
	if not (body is Player):
		return
	if entering:
		player_nearby = body
		var prompt := get_node("Prompt") as Label
		if prompt:
			prompt.visible = true
	else:
		player_nearby = null
		var prompt := get_node("Prompt") as Label
		if prompt:
			prompt.visible = false

func _physics_process(delta: float) -> void:
	refresh_timer += delta
	if refresh_timer >= REFRESH_INTERVAL:
		refresh_timer = 0.0
		_refresh_merchandise()

	if is_trading:
		return

	if post_trade_timer > 0.0:
		post_trade_timer -= delta
		return

	if idle_timer > 0.0:
		idle_timer -= delta
		return

	position += move_direction * MOVE_SPEED * delta

	if randf() < 0.02:
		move_direction = Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized()
	if randf() < 0.005:
		idle_timer = IDLE_DURATION + randf_range(0, 3.0)
	if randf() < 0.01:
		move_direction = move_direction.rotated(randf_range(-0.6, 0.6)).normalized()

	# 边界约束（按当前地图尺寸留 60px 内边距）
	position.x = clampf(position.x, 60, maxf(120.0, map_size.x - 60))
	position.y = clampf(position.y, 60, maxf(120.0, map_size.y - 60))
	if world_layout != null and world_layout.has_method("project_to_walkable"):
		position = world_layout.call("project_to_walkable", position)

func try_interact(player_node: Node2D) -> bool:
	if is_trading:
		return false
	var dist := global_position.distance_to(player_node.global_position)
	if dist > 100.0:
		return false
	is_trading = true
	return true

func finish_trade() -> void:
	is_trading = false
	post_trade_timer = POST_TRADE_WAIT

func get_merchandise() -> Array:
	return current_merchandise

func get_upgrade_cost(current_quality: String) -> int:
	match current_quality:
		"white": return 30
		"blue": return 60
		"purple": return 120
	return 0

func _refresh_merchandise() -> void:
	current_merchandise = []
	for i in range(4):
		var id := GameData.get_random_equipment_id()
		if not id.is_empty():
			current_merchandise.append(GameData.get_equipment(id))
