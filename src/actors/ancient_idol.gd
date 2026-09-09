extends Node2D
class_name AncientIdol

# 祭坛状态
var used := false
var cost_type := ""
var cost_magnitude := 0.0
var cost_label := ""
var _player_near := false
var _sprite: Sprite2D
var _label: Label

const DEMANDS := [
	{"type": "max_hp", "label": "最大生命", "min_pct": 0.35, "max_pct": 0.55, "desc": "最大生命永久降低 %.0f%%"},
	{"type": "max_energy", "label": "最大能量", "min_pct": 0.40, "max_pct": 0.60, "desc": "最大能量永久降低 %.0f%%"},
	{"type": "move_speed", "label": "基础移速", "min_pct": 0.30, "max_pct": 0.45, "desc": "基础移速永久降低 %.0f%%"},
	{"type": "base_str", "label": "基础力量", "min_pct": 4.0, "max_pct": 8.0, "desc": "基础力量永久 -%d"},
	{"type": "base_int", "label": "基础智力", "min_pct": 4.0, "max_pct": 8.0, "desc": "基础智力永久 -%d"},
]

func _init() -> void:
	_roll_cost()

func _roll_cost() -> void:
	var demand: Dictionary = DEMANDS[randi_range(0, DEMANDS.size() - 1)]
	cost_type = demand.type
	cost_label = demand.label
	if demand.type in ["max_hp", "max_energy", "move_speed"]:
		cost_magnitude = randf_range(demand.min_pct, demand.max_pct)
	else:
		cost_magnitude = randi_range(int(demand.min_pct), int(demand.max_pct))

func _ready() -> void:
	# 视觉：暗红色光柱 + 符文
	var glow := GradientTexture2D.new()
	glow.width = 64; glow.height = 64
	glow.fill = GradientTexture2D.FILL_RADIAL
	var grad := Gradient.new()
	grad.colors = [Color(0.85, 0.2, 0.1, 0.7), Color(0.5, 0.05, 0.0, 0.0)]
	glow.gradient = grad

	_sprite = Sprite2D.new()
	_sprite.texture = glow
	_sprite.scale = Vector2(1.5, 1.5)
	add_child(_sprite)

	# 文本标签
	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.position = Vector2(-80, -40)
	_label.size = Vector2(160, 28)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 12)
	_label.modulate = Color(1, 0.35, 0.2)
	_label.text = "远古祭坛"
	_label.visible = false
	add_child(_label)

	# 交互区域
	var area := Area2D.new()
	area.name = "InteractArea"
	area.collision_layer = 0
	area.collision_mask = 1
	var collision := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 48.0
	collision.shape = circle
	area.add_child(collision)
	area.body_entered.connect(func(b: Node2D): _player_near = true; _label.visible = true)
	area.body_exited.connect(func(b: Node2D): _player_near = false; _label.visible = false)
	add_child(area)


func try_interact(player: Player, on_accept: Callable, on_decline: Callable) -> bool:
	if used: return false
	if not _player_near: return false

	var desc_text := ""
	if cost_type in ["max_hp", "max_energy", "move_speed"]:
		desc_text = "索要代价：%s 永久降低 %.0f%%
回报：传说品质主动技能书" % [cost_label, cost_magnitude * 100]
	else:
		desc_text = "索要代价：%s 永久 -%d
回报：传说品质主动技能书" % [cost_label, int(cost_magnitude)]

	# 弹窗确认（由 arena 处理 UI）
	on_accept.call()
	return true


func apply_cost(player: Player) -> void:
	match cost_type:
		"max_hp":
			player.base_stats.vit = max(0, player.base_stats.vit - int(cost_magnitude * 0.7))
		"max_energy":
			player.base_energy_max = player.MAX_ENERGY * (1.0 - cost_magnitude)
		"move_speed":
			player.base_move_speed *= (1.0 - cost_magnitude)
		"base_str":
			player.base_stats.str = max(0, player.base_stats.str - int(cost_magnitude))
		"base_int":
			player.base_stats.int = max(0, player.base_stats.int - int(cost_magnitude))
	player.refresh_max_hp()
	used = true

	# 碎裂动画
	if _sprite:
		var tw := create_tween().set_parallel(true)
		tw.tween_property(_sprite, "scale", Vector2.ZERO, 0.5)
		tw.tween_property(_sprite, "modulate:a", 0.0, 0.5)
		tw.tween_callback(func(): if _sprite: _sprite.queue_free())
	_label.visible = false


func get_cost_description() -> String:
	if cost_type in ["max_hp", "max_energy", "move_speed"]:
		return "索要代价：%s 永久降低 %.0f%%" % [cost_label, cost_magnitude * 100]
	return "索要代价：%s 永久 -%d" % [cost_label, int(cost_magnitude)]
