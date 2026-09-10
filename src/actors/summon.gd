extends CharacterBody2D
class_name Summon

# 召唤物：轻 RTS 单位
# - 默认 AI：跟随英雄，攻击英雄的集火目标 / 附近最近敌人
# - 仅当玩家用左键选中、右键下令时才进入“受控”状态
# 测试阶段召唤物免疫伤害（不实现 take_damage），避免被英雄/敌人弹道误伤。

var arena: Node2D = null        # Arena 引用
var owner_player: Node2D = null # 英雄引用

# 属性
var hp: float = 120.0
var max_hp: float = 120.0
var speed: float = 210.0
var damage: float = 15.0
var attack_interval: float = 0.8
var attack_timer: float = 0.0
var attack_range: float = 44.0
var follow_leash: float = 130.0  # 跟随半径

# 指令（由 arena 的右键下达）
var command_target_pos: Vector2 = Vector2.ZERO  # 移动指令（世界坐标）
var command_attack_target: Node2D = null        # 集火指令（敌人）
var selected: bool = false
var _path_points: PackedVector2Array = PackedVector2Array()
var _path_index := 0
var _path_goal := Vector2.ZERO
var _path_repath_remaining := 0.0

# 护盾（吸收，限时）
var shield: float = 0.0
var shield_timer: float = 0.0

var _health_bar: ColorRect
var _health_bar_bg: ColorRect
var _flash_timer: float = 0.0
var _body_color: Color = Color(0.4, 0.9, 1.0)


func _ready() -> void:
	collision_layer = 4
	# 召唤物不阻挡英雄移动，仍与敌人和世界阻挡物碰撞。
	collision_mask = 2 | 8

	var collision := CollisionShape2D.new()
	collision.name = "BodyCollision"
	var shape := CircleShape2D.new()
	shape.radius = 13.0
	collision.shape = shape
	add_child(collision)

	# 血条
	_health_bar_bg = ColorRect.new()
	_health_bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_health_bar_bg.color = Color(0.1, 0.1, 0.1, 0.85)
	_health_bar_bg.size = Vector2(30, 4)
	_health_bar_bg.position = Vector2(-15, -30)
	add_child(_health_bar_bg)
	_health_bar = ColorRect.new()
	_health_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_health_bar.color = Color(0.3, 1.0, 0.5)
	_health_bar.size = Vector2(30, 4)
	_health_bar.position = Vector2(-15, -30)
	add_child(_health_bar)
	queue_redraw()


func _physics_process(delta: float) -> void:
	attack_timer = maxf(attack_timer - delta, 0.0)
	if shield_timer > 0.0:
		shield_timer -= delta
		if shield_timer <= 0.0:
			shield = 0.0
	if _flash_timer > 0.0:
		_flash_timer -= delta
		if _flash_timer <= 0.0:
			_body_color = Color(0.4, 0.9, 1.0)
			queue_redraw()
	_update_health_bar()
	_think(delta)


func _think(delta: float) -> void:
	var target_enemy: Enemy = null
	var move_pos: Vector2 = Vector2.ZERO
	var need_move := false

	# 1) 显式集火指令优先
	if command_attack_target != null and is_instance_valid(command_attack_target) and not command_attack_target.is_dead():
		target_enemy = command_attack_target
	# 2) 显式移动指令
	elif command_target_pos != Vector2.ZERO:
		move_pos = command_target_pos
		need_move = true
		if global_position.distance_to(command_target_pos) < 12.0:
			command_target_pos = Vector2.ZERO
	# 3) 默认 AI：跟随英雄 + 打英雄集火目标 / 附近最近敌人
	else:
		var focus: Enemy = null
		if arena != null and arena.mark_target != null and is_instance_valid(arena.mark_target) and not arena.mark_target.is_dead():
			focus = arena.mark_target
		if focus == null:
			focus = _nearest_enemy_to(global_position, 380.0)
		if focus != null:
			target_enemy = focus
		elif owner_player != null and global_position.distance_to(owner_player.global_position) > follow_leash:
			move_pos = owner_player.global_position
			need_move = true

	# 计算期望速度：遇到阻挡时按世界路径绕行。
	var desired := Vector2.ZERO
	if target_enemy != null:
		var dist := global_position.distance_to(target_enemy.global_position)
		if dist > attack_range or not _has_line_of_sight(target_enemy.global_position):
			desired = _path_direction_to(target_enemy.global_position, delta) * speed
		elif attack_timer <= 0.0:
			_attack(target_enemy)
	elif need_move:
		desired = _path_direction_to(move_pos, delta) * speed

	# 分离力：避免召唤物互相重叠堆叠
	var sep := _separation()
	var final_vel: Vector2
	if desired != Vector2.ZERO:
		final_vel = desired + sep * speed * 0.6
	else:
		final_vel = sep * speed * 0.9
	velocity = final_vel
	move_and_slide()

func _path_direction_to(destination: Vector2, delta: float) -> Vector2:
	if global_position.distance_to(destination) <= 4.0:
		return Vector2.ZERO
	_path_repath_remaining = maxf(_path_repath_remaining - delta, 0.0)
	if arena != null and arena.world != null:
		if _path_points.is_empty() or _path_repath_remaining <= 0.0 or _path_goal.distance_to(destination) > 72.0:
			_path_points = arena.world.get_path_for_unit(global_position, destination)
			_path_index = 0
			_path_goal = destination
			_path_repath_remaining = 0.35
	while _path_index < _path_points.size() and global_position.distance_to(_path_points[_path_index]) <= 18.0:
		_path_index += 1
	var waypoint := destination
	if _path_index < _path_points.size():
		waypoint = _path_points[_path_index]
	return global_position.direction_to(waypoint)

func _has_line_of_sight(target_position: Vector2) -> bool:
	return arena == null or arena.world == null or arena.world.has_line_of_sight(global_position, target_position)


func _separation() -> Vector2:
	if arena == null:
		return Vector2.ZERO
	var push := Vector2.ZERO
	var sep_r := 24.0
	for s in arena.summons:
		if s == self or not is_instance_valid(s):
			continue
		var d := global_position.distance_to(s.global_position)
		if d < sep_r and d > 0.001:
			push += (global_position - s.global_position).normalized() * (1.0 - d / sep_r)
	return push


func _attack(enemy: Enemy) -> void:
	attack_timer = attack_interval
	var dir := global_position.direction_to(enemy.global_position)
	enemy.take_damage(damage, dir, 30.0)
	if arena != null and arena.has_method("_spawn_damage_number"):
		arena._spawn_damage_number(enemy.global_position, damage, false)
	if enemy.is_dead() and arena != null and arena.has_method("_on_enemy_killed"):
		arena._on_enemy_killed(enemy)
	command_attack_target = null  # 目标已死，回到默认 AI


func _nearest_enemy_to(from: Vector2, max_dist: float) -> Enemy:
	if arena == null:
		return null
	var best: Enemy = null
	var best_d := max_dist * max_dist
	for e in arena.enemies_root.get_children():
		if e is Enemy and not e.is_dead():
			var d := from.distance_squared_to(e.global_position)
			if d < best_d:
				best_d = d
				best = e
	return best


func _update_health_bar() -> void:
	if _health_bar == null:
		return
	var ratio := clampf(hp / maxf(max_hp, 1.0), 0.0, 1.0)
	_health_bar.size.x = 30.0 * ratio


func set_selected(v: bool) -> void:
	selected = v
	queue_redraw()

func heal(amount: float) -> void:
	hp = minf(hp + amount, max_hp)

func add_shield(amount: float, dur: float) -> void:
	shield = maxf(shield, amount)
	shield_timer = maxf(shield_timer, dur)


func _draw() -> void:
	# 身体
	draw_circle(Vector2.ZERO, 14.0, _body_color)
	draw_circle(Vector2.ZERO, 14.0, Color(0, 0, 0, 0))  # 占位，保证轮廓
	draw_arc(Vector2.ZERO, 14.0, 0.0, TAU, 28, Color(0.1, 0.4, 0.6), 2.0)
	# 选中环
	if selected:
		draw_arc(Vector2.ZERO, 22.0, 0.0, TAU, 36, Color(0.3, 1.0, 0.5), 2.5)
