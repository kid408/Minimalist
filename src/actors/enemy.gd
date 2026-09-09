extends CharacterBody2D
class_name Enemy

const GameData = preload("res://src/data/game_data.gd")

enum EnemyType { NORMAL, ELITE, BOSS }
enum Behavior { MELEE, RANGED, CHARGER, EXPLODER }

# -- 基础属性
var hp: float = 50.0
var max_hp: float = 50.0
var speed: float = 270.0
var damage: float = 10.0
var detection_range: float = 340.0
var attack_interval: float = 1.2
var attack_timer: float = 0.0

var enemy_type: int = EnemyType.NORMAL
var behavior: int = Behavior.MELEE

# -- 领地（出生点）
var spawn_origin: Vector2 = Vector2.ZERO

# -- 追踪 / 脱战
var chase_target: Node2D = null
var chase_range: float = 600.0   # 冲撞者冲刺最大半径
var home_leash: float = 520.0
var reengage_range: float = 340.0
var returning_home := false
var hit_stun_remaining: float = 0.0
var _path_points: PackedVector2Array = PackedVector2Array()
var _path_index := 0
var _path_goal := Vector2.ZERO
var _path_repath_remaining := 0.0

# -- 状态效果（控制/减益通用）：二进制状态名 -> 剩余秒数
var statuses: Dictionary = {}        # "root"/"sleep"/"hex"/"silence"/"banish" -> 剩余秒
var slow_mult: float = 1.0           # 减速系数（1.0=无减速）
var slow_remaining: float = 0.0

# -- 护甲破碎：受到伤害倍率（>1 = 易伤），限时
var armor_break_mult: float = 1.0
var armor_break_remaining: float = 0.0
# -- 持续伤害（DoT）
var dot_dps: float = 0.0
var dot_remaining: float = 0.0
var dot_accum: float = 0.0
var dot_school: String = "physical"

# -- 特殊行为计时器
var charger_cooldown: float = 0.0
var charger_dash_speed: float = 410.0
var charger_dashing: bool = false
var ranged_cooldown: float = 0.0
var ranged_attack_range: float = 350.0

# -- 视觉
const KNOCKBACK_DECAY: float = 6.0
const COLOR_FLASH_DURATION: float = 0.08
const MELEE_ATTACK_RANGE: float = 52.0
var flash_timer: float = 0.0
var original_modulate: Color = Color.WHITE
var health_bar: ColorRect
var visual_texture_path := "res://assets/enemies/enemy_1.png"
var visual_scale := GameData.get_enemy_visual_scale("normal")
var health_bar_color := Color(1, 0.2, 0.2)

# -- 难度缩放（由 arena 设置）
var difficulty_scale: float = 1.0

# -- 空间网格查询引用（由 WorldSystem 注入，用于 O(n+k) 邻近分离）
var world_ref: Node = null

func _ready() -> void:
	original_modulate = modulate
	add_to_group("enemy")
	collision_layer = 2
	collision_mask = 1 | 4 | 8

	var collision := CollisionShape2D.new()
	collision.name = "BodyCollision"
	var shape := CircleShape2D.new()
	shape.radius = _collision_radius()
	collision.shape = shape
	add_child(collision)

	var tex := load(visual_texture_path) as Texture2D
	if tex:
		var sprite := Sprite2D.new()
		sprite.name = "BodySprite"
		sprite.texture = tex
		sprite.scale = visual_scale
		add_child(sprite)

	var bar_bg := ColorRect.new()
	bar_bg.name = "HealthBarBg"
	bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_bg.color = Color(0.15, 0.05, 0.05, 0.8)
	bar_bg.size = Vector2(32, 4)
	bar_bg.position = Vector2(-16, -30)
	add_child(bar_bg)

	health_bar = ColorRect.new()
	health_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	health_bar.size = Vector2(32, 4)
	health_bar.position = Vector2(-16, -30)
	health_bar.color = health_bar_color
	add_child(health_bar)

func _collision_radius() -> float:
	match enemy_type:
		EnemyType.ELITE: return 16.0
		EnemyType.BOSS: return 20.0
	return 14.0

func _set_enemy_type_bar_color(new_enemy_type: int) -> void:
	match new_enemy_type:
		EnemyType.ELITE: health_bar_color = Color(1, 0.55, 0.15)
		EnemyType.BOSS: health_bar_color = Color(0.8, 0.2, 0.9)
		_: health_bar_color = Color(1, 0.2, 0.2)
	if health_bar:
		health_bar.color = health_bar_color

func _update_texture(texture_path: String) -> void:
	visual_texture_path = texture_path
	var tex := load(texture_path) as Texture2D
	if not tex:
		return
	var sprite := get_node_or_null("BodySprite") as Sprite2D
	if sprite:
		sprite.texture = tex

func setup(base_hp: float, move_speed: float, atk_damage: float, atk_interval: float) -> void:
	hp = base_hp
	max_hp = base_hp
	speed = move_speed
	damage = atk_damage
	attack_interval = atk_interval
	spawn_origin = global_position

func take_damage(amount: float, knockback_dir: Vector2 = Vector2.ZERO, kb_strength: float = 0.0) -> void:
	amount *= armor_break_mult
	hp -= amount
	flash_timer = COLOR_FLASH_DURATION
	modulate = Color.RED
	if health_bar:
		var base_w := 32.0
		var ratio := clampf(hp / maxf(max_hp, 1.0), 0.0, 1.0)
		health_bar.size.x = base_w * ratio
	if kb_strength > 0.0 and knockback_dir.length_squared() > 0.01:
		velocity += knockback_dir * kb_strength
		hit_stun_remaining = 0.18

func is_dead() -> bool:
	return hp <= 0.0

func _path_direction_to(destination: Vector2, delta: float) -> Vector2:
	if global_position.distance_to(destination) <= 4.0:
		return Vector2.ZERO
	_path_repath_remaining = maxf(_path_repath_remaining - delta, 0.0)
	if world_ref != null and world_ref.has_method("get_path_for_unit"):
		if _path_points.is_empty() or _path_repath_remaining <= 0.0 or _path_goal.distance_to(destination) > 72.0:
			var result: Variant = world_ref.call("get_path_for_unit", global_position, destination)
			if result is PackedVector2Array:
				_path_points = result
				_path_index = 0
				_path_goal = destination
				_path_repath_remaining = 0.35
	while _path_index < _path_points.size() and global_position.distance_to(_path_points[_path_index]) <= 20.0:
		_path_index += 1
	var waypoint := destination
	if _path_index < _path_points.size():
		waypoint = _path_points[_path_index]
	return global_position.direction_to(waypoint)

func _has_line_of_sight(target_position: Vector2) -> bool:
	if world_ref != null and world_ref.has_method("has_line_of_sight"):
		return bool(world_ref.call("has_line_of_sight", global_position, target_position))
	return true

# ============================================================
# 状态效果系统
# ============================================================
func apply_status(name: String, dur: float) -> void:
	if dur <= 0.0:
		return
	statuses[name] = maxf(statuses.get(name, 0.0), dur)

func apply_slow(pct: float, dur: float) -> void:
	if dur <= 0.0:
		return
	slow_mult = minf(slow_mult, 1.0 - pct)   # 取最强减速
	slow_remaining = maxf(slow_remaining, dur)

# 护甲破碎：受到伤害倍率（>1 = 易伤），限时取最强
func apply_armor_break(mult: float, dur: float) -> void:
	if dur <= 0.0:
		return
	armor_break_mult = maxf(armor_break_mult, mult)
	armor_break_remaining = maxf(armor_break_remaining, dur)

# 持续伤害（DoT）：每秒 dps，持续 dur 秒
func apply_dot(dps: float, dur: float, school: String = "physical") -> void:
	if dur <= 0.0 or dps <= 0.0:
		return
	dot_dps = maxf(dot_dps, dps)
	dot_remaining = maxf(dot_remaining, dur)
	dot_school = school

func has_status(name: String) -> bool:
	return statuses.get(name, 0.0) > 0.0

func _tick_statuses(delta: float) -> void:
	if slow_remaining > 0.0:
		slow_remaining -= delta
		if slow_remaining <= 0.0:
			slow_mult = 1.0
	if armor_break_remaining > 0.0:
		armor_break_remaining -= delta
		if armor_break_remaining <= 0.0:
			armor_break_mult = 1.0
	# 持续伤害（DoT）
	if dot_remaining > 0.0:
		dot_remaining -= delta
		dot_accum += dot_dps * delta
		var tick := int(dot_accum)
		if tick > 0:
			dot_accum -= tick
			hp -= tick
			if health_bar:
				var base_w := 32.0
				var ratio := clampf(hp / maxf(max_hp, 1.0), 0.0, 1.0)
				health_bar.size.x = base_w * ratio
		if dot_remaining <= 0.0:
			dot_dps = 0.0
			dot_accum = 0.0
	for name in statuses.keys():
		statuses[name] -= delta
		if statuses[name] <= 0.0:
			statuses.erase(name)
	_refresh_status_tint()

func _is_fully_disabled() -> bool:
	return has_status("sleep") or has_status("hex") or has_status("banish") or has_status("polymorph")

func _refresh_status_tint() -> void:
	if flash_timer > 0.0:
		return  # 受击闪红优先
	if _is_fully_disabled():
		modulate = Color(0.6, 0.4, 1.0)      # 紫：完全失能
	elif has_status("root"):
		modulate = Color(1.0, 0.9, 0.4)      # 黄：定身
	elif has_status("silence"):
		modulate = Color(0.5, 0.9, 0.9)      # 青：沉默
	elif slow_mult < 1.0:
		modulate = Color(0.5, 0.7, 1.0)      # 蓝：减速
	else:
		modulate = original_modulate

# ============================================================
# AI 主循环
# ============================================================
func _physics_process(delta: float) -> void:
	if hp <= 0.0:
		return

	# 受击硬直
	if hit_stun_remaining > 0.0:
		hit_stun_remaining -= delta
		velocity = velocity.move_toward(Vector2.ZERO, KNOCKBACK_DECAY * 100.0 * delta)
		move_and_slide()
		return

	# 状态效果计时（减速/定身/睡眠/妖术/放逐/沉默）
	_tick_statuses(delta)
	# 完全失能：睡眠/妖术/放逐，原地不动不攻击
	if _is_fully_disabled():
		velocity = velocity.move_toward(Vector2.ZERO, speed * 4.0 * delta)
		move_and_slide()
		return

	# 闪红恢复
	if flash_timer > 0.0:
		flash_timer -= delta
		if flash_timer <= 0.0:
			modulate = original_modulate

	# 特殊行为冷却
	charger_cooldown = maxf(charger_cooldown - delta, 0.0)
	ranged_cooldown = maxf(ranged_cooldown - delta, 0.0)

	# 探测玩家与营地边界：越过领地后先完整回巢，玩家进入回接区才重新接战。
	var target := chase_target
	if target == null or not is_instance_valid(target):
		_brain_return_to_origin(delta)
		return
	if returning_home:
		if target.global_position.distance_to(spawn_origin) <= reengage_range:
			returning_home = false
		else:
			_brain_return_to_origin(delta)
			return
	if global_position.distance_to(spawn_origin) > home_leash:
		returning_home = true
		_brain_return_to_origin(delta)
		return

	var dist := global_position.distance_to(target.global_position)
	if dist <= detection_range:
		_brain_chase(delta, target, dist)
		return
	_brain_return_to_origin(delta)


# ============================================================
# 单位分离（Warcraft 式：避免敌人叠堆成一坨）
# ============================================================
func _separation_vector() -> Vector2:
	var push := Vector2.ZERO
	# 优先使用 WorldSystem 的空间网格做邻近查询（避免 O(n^2) 全表遍历）
	var others: Array = []
	if world_ref != null and world_ref.has_method("query_nearby_enemies"):
		others = world_ref.query_nearby_enemies(global_position, 34.0)
	var parent := get_parent()
	if others.is_empty() and parent != null:
		others = parent.get_children()
	for other in others:
		if other == self or not (other is Enemy) or other.is_dead():
			continue
		var d := global_position.distance_to(other.global_position)
		if d > 0.01 and d < 34.0:
			push += (global_position - other.global_position).normalized() * (34.0 - d)
	return push * 8.0

# ============================================================
# 巡逻 / 待机
# ============================================================
func _brain_return_to_origin(delta: float) -> void:
	var sep := _separation_vector()
	# 定身：无法移动，仅衰减速度
	if has_status("root"):
		velocity = velocity.move_toward(Vector2.ZERO, speed * 2.0 * delta) + sep
		move_and_slide()
		return

	var dist := global_position.distance_to(spawn_origin)
	if dist > 8.0:
		var dir := _path_direction_to(spawn_origin, delta)
		velocity = dir * speed * 0.6 * slow_mult + sep
	else:
		returning_home = false
		_path_points.clear()
		_path_index = 0
		velocity = velocity.move_toward(Vector2.ZERO, speed * 2.0 * delta) + sep
	move_and_slide()


# ============================================================
# 追击 + 攻击
# ============================================================
func _brain_chase(delta: float, target: Node2D, dist: float) -> void:
	var direction := _path_direction_to(target.global_position, delta)

	match behavior:
		Behavior.MELEE:
			_chase_melee(delta, direction, dist)
		Behavior.RANGED:
			_chase_ranged(delta, direction, dist)
		Behavior.CHARGER:
			_chase_charger(delta, direction, dist)
		Behavior.EXPLODER:
			_chase_charger(delta, direction, dist)  # 冲向玩家


# --- 近战 ---
func _chase_melee(delta: float, dir: Vector2, dist: float) -> void:
	var spd := speed * slow_mult
	var sep := _separation_vector()
	# 定身：不能移动，但仍可攻击
	if has_status("root"):
		velocity = velocity.move_toward(Vector2.ZERO, spd * 4.0 * delta) + sep
		move_and_slide()
		if dist <= MELEE_ATTACK_RANGE and _has_line_of_sight(chase_target.global_position) and attack_timer <= 0.0:
			attack_timer = attack_interval
		return
	if dist > MELEE_ATTACK_RANGE:
		velocity = dir * spd + sep
		move_and_slide()
	else:
		velocity = velocity.move_toward(Vector2.ZERO, spd * 4.0 * delta) + sep
		move_and_slide()
		if _has_line_of_sight(chase_target.global_position) and attack_timer <= 0.0:
			attack_timer = attack_interval


# --- 远程 ---
func _chase_ranged(delta: float, dir: Vector2, dist: float) -> void:
	var spd := speed * slow_mult
	var sep := _separation_vector()
	# 定身：不移动；沉默：不发射特殊弹道
	if has_status("root"):
		velocity = velocity.move_toward(Vector2.ZERO, spd * 3.0 * delta) + sep
		move_and_slide()
		if (not has_status("silence")) and dist <= ranged_attack_range and _has_line_of_sight(chase_target.global_position) and ranged_cooldown <= 0.0:
			_fire_ranged_projectile(global_position.direction_to(chase_target.global_position))
		return
	var ideal_dist := ranged_attack_range * 0.7
	if dist > ideal_dist + 20:
		velocity = dir * spd + sep          # 接近到射程
	elif dist < ideal_dist - 20:
		velocity = -dir * spd * 0.6 + sep   # 太近则后撤（风筝）
	else:
		velocity = velocity.move_toward(Vector2.ZERO, spd * 3.0 * delta) + sep
	# Warcraft 式：只要在射程内就持续开火（即便后撤中也打）
	if dist <= ranged_attack_range and _has_line_of_sight(chase_target.global_position) and ranged_cooldown <= 0.0 and not has_status("silence"):
		_fire_ranged_projectile(global_position.direction_to(chase_target.global_position))
	move_and_slide()


func _fire_ranged_projectile(dir: Vector2) -> void:
	ranged_cooldown = attack_interval
	var proj := Projectile.new()
	proj.position = global_position
	proj.damage = damage
	proj.direction = dir
	proj.lifetime = 2.5
	proj.speed *= 0.7
	proj.pierce_count = 1
	proj.faction = Projectile.Faction.ENEMY
	proj.attacker = self
	proj.collision_layer = 0
	proj.collision_mask = 1 | 8
	if world_ref != null and world_ref.has_method("_resolve_enemy_projectile_hit"):
		proj.hit_resolver = Callable(world_ref, "_resolve_enemy_projectile_hit")
	var collision := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 8.0
	collision.shape = shape
	proj.add_child(collision)
	var tex := load("res://assets/projectiles/projectile_1.png") as Texture2D
	if tex:
		var sprite := Sprite2D.new()
		sprite.texture = tex; sprite.scale = Vector2(0.3, 0.3)
		proj.add_child(sprite)
	proj.body_entered.connect(proj._on_body_entered)
	get_parent().add_child(proj)


# --- 冲撞者 ---
func _chase_charger(delta: float, dir: Vector2, dist: float) -> void:
	var sep := _separation_vector()
	# 定身/沉默：无法冲刺
	if has_status("root") or has_status("silence"):
		velocity = velocity.move_toward(Vector2.ZERO, speed * slow_mult * 4.0 * delta) + sep
		move_and_slide()
		return
	if charger_dashing:
		# 冲刺中
		velocity = velocity.move_toward(dir * charger_dash_speed, charger_dash_speed * 2.0 * delta) + sep
		move_and_slide()
		charger_dashing = global_position.distance_to(spawn_origin) < chase_range
		return

	# 靠近 → 蓄力冲刺
	if dist < 200.0 and charger_cooldown <= 0.0:
		charger_cooldown = 3.0 + randf_range(0, 2.0)
		charger_dashing = true
		modulate = Color.ORANGE
		return

	if dist > MELEE_ATTACK_RANGE:
		velocity = dir * speed + sep
	else:
		velocity = velocity.move_toward(Vector2.ZERO, speed * 4.0 * delta) + sep
		if _has_line_of_sight(chase_target.global_position) and attack_timer <= 0.0:
			attack_timer = attack_interval
	move_and_slide()


# ============================================================
# 死亡动画
# ============================================================
func play_death_animation() -> void:
	set_physics_process(false)
	collision_layer = 0
	collision_mask = 0
	var body_collision := get_node_or_null("BodyCollision") as CollisionShape2D
	if body_collision:
		body_collision.set_deferred("disabled", true)
	velocity = Vector2.ZERO
	hit_stun_remaining = 0.0
	if health_bar: health_bar.visible = false
	var bar_bg := get_node_or_null("HealthBarBg")
	if bar_bg: bar_bg.visible = false

	# 自爆虫：在英雄附近死亡时走统一受伤管线，避免伤害到同阵营敌人。
	if behavior == Behavior.EXPLODER and world_ref != null and world_ref.has_method("_deal_damage_to_player"):
		if chase_target != null and is_instance_valid(chase_target) and chase_target.global_position.distance_to(global_position) < 80.0:
			world_ref.call("_deal_damage_to_player", damage * 2.0, self)

	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "modulate", Color.WHITE, 0.06)
	tw.tween_property(self, "scale", Vector2(1.3, 1.3), 0.1)
	var tw_seq := create_tween()
	tw_seq.tween_interval(0.1)
	tw_seq.set_parallel(true)
	tw_seq.tween_property(self, "modulate:a", 0.0, 0.35)
	tw_seq.tween_property(self, "scale", Vector2(0.2, 0.2), 0.35)
	tw_seq.tween_callback(queue_free)


func set_chase_target(target: Node2D) -> void:
	chase_target = target
