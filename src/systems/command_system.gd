extends Node
class_name CommandSystem

const Arena = preload("res://src/arena.gd")
const Enemy = preload("res://src/actors/enemy.gd")
const Summon = preload("res://src/actors/summon.gd")
const GameData = preload("res://src/data/game_data.gd")

enum OrderKind { NONE, MOVE, ATTACK_TARGET, ATTACK_MOVE, HOLD, STOP }

const DRAG_THRESHOLD := 12.0
const HERO_STOP_DISTANCE := 8.0
const HERO_ATTACK_PADDING := 34.0
const HERO_ATTACK_LEASH := 800.0
const ACQUISITION_RANGE := 280.0
const REPATH_INTERVAL := 0.25

var arena: Arena
var hero_selected := true
var selected_summons: Array = []
var selected_enemy: Enemy = null

var hero_order_kind: int = OrderKind.NONE
var hero_destination := Vector2.ZERO
var hero_resume_destination := Vector2.ZERO
var hero_target: Enemy = null
var hero_hold_anchor := Vector2.ZERO
var hero_path := PackedVector2Array()
var hero_path_index := 0
var hero_path_goal := Vector2.ZERO
var hero_repath_remaining := 0.0


func setup(owner: Arena) -> void:
	arena = owner
	arena.selected_summons = selected_summons
	select_hero()


func select_hero(additive: bool = false) -> void:
	if arena == null or arena.player == null:
		return
	if not additive:
		_clear_unit_selection()
	hero_selected = true
	arena.player.set_selected(true)
	selected_enemy = null


func select_all_summons() -> void:
	_clear_unit_selection()
	hero_selected = false
	for summon in arena.summons:
		if is_instance_valid(summon):
			_select_summon(summon as Summon)
	selected_enemy = null


func clear_selection() -> void:
	_clear_unit_selection()
	hero_selected = false
	selected_enemy = null


func begin_selection(world_pos: Vector2) -> void:
	if arena == null:
		return
	arena._drag_start_world = world_pos
	arena._drag_start_screen = arena.get_viewport().get_mouse_position()
	arena._selection_box = Rect2(world_pos, Vector2.ZERO)
	arena._is_dragging = true
	if arena.selection_drawer != null:
		arena.selection_drawer.queue_redraw()


func update_selection(world_pos: Vector2) -> void:
	if arena == null or not arena._is_dragging:
		return
	arena._selection_box = Rect2(arena._drag_start_world, world_pos - arena._drag_start_world).abs()
	if arena.selection_drawer != null:
		arena.selection_drawer.queue_redraw()


func finish_selection(world_pos: Vector2, additive: bool = false) -> void:
	if arena == null:
		return
	var box := Rect2(arena._drag_start_world, world_pos - arena._drag_start_world).abs()
	var is_box := box.size.length() >= DRAG_THRESHOLD
	if not additive:
		_clear_unit_selection()
		selected_enemy = null

	if is_box:
		if box.has_point(arena.player.global_position):
			hero_selected = true
			arena.player.set_selected(true)
		for summon in arena.summons:
			if is_instance_valid(summon) and box.has_point(summon.global_position):
				_select_summon(summon as Summon)
	else:
		var summon := _summon_at(world_pos)
		if summon != null:
			hero_selected = false if not additive else hero_selected
			_select_summon(summon)
		elif arena.player.global_position.distance_to(world_pos) <= 30.0:
			hero_selected = true
			arena.player.set_selected(true)
		elif _enemy_at(world_pos) != null:
			selected_enemy = _enemy_at(world_pos)

	arena._is_dragging = false
	arena._selection_box = Rect2()
	if arena.selection_drawer != null:
		arena.selection_drawer.queue_redraw()


func issue_context_order(world_pos: Vector2) -> void:
	if arena == null:
		return
	var target := _enemy_at(world_pos)
	var issue_hero := hero_selected or selected_summons.is_empty()
	if issue_hero:
		if target != null:
			issue_hero_attack_target(target)
		else:
			issue_hero_move(world_pos)
	if not selected_summons.is_empty():
		if target != null:
			for summon in selected_summons:
				if is_instance_valid(summon):
					(summon as Summon).issue_attack_target(target)
		else:
			_issue_summon_formation(world_pos, OrderKind.MOVE)
	_show_order_marker(world_pos, Color(0.35, 0.95, 0.55, 0.9) if target == null else Color(1.0, 0.42, 0.30, 0.9))


func issue_attack_move(world_pos: Vector2) -> void:
	if arena == null:
		return
	var destination := _walkable(world_pos)
	if hero_selected or selected_summons.is_empty():
		_cancel_hero_attack_windup()
		hero_order_kind = OrderKind.ATTACK_MOVE
		hero_destination = destination
		hero_resume_destination = destination
		hero_target = null
		arena.mark_target = null
		_rebuild_hero_path(destination)
	if not selected_summons.is_empty():
		_issue_summon_formation(destination, OrderKind.ATTACK_MOVE)
	_show_order_marker(destination, Color(1.0, 0.78, 0.26, 0.92))


func issue_stop() -> void:
	if hero_selected or selected_summons.is_empty():
		stop_hero()
	for summon in selected_summons:
		if is_instance_valid(summon):
			(summon as Summon).issue_stop()


func issue_hold() -> void:
	if arena == null:
		return
	if hero_selected or selected_summons.is_empty():
		_cancel_hero_attack_windup()
		hero_order_kind = OrderKind.HOLD
		hero_hold_anchor = arena.player.global_position
		hero_target = null
		arena.mark_target = null
		_clear_hero_path()
	for summon in selected_summons:
		if is_instance_valid(summon):
			(summon as Summon).issue_hold()


func issue_follow() -> void:
	if arena == null:
		return
	for i in range(selected_summons.size()):
		var summon = selected_summons[i]
		if is_instance_valid(summon):
			(summon as Summon).issue_follow(_formation_offset(i, selected_summons.size()))


func issue_hero_move(world_pos: Vector2) -> void:
	_cancel_hero_attack_windup()
	hero_order_kind = OrderKind.MOVE
	hero_destination = _walkable(world_pos)
	hero_resume_destination = Vector2.ZERO
	hero_target = null
	arena.mark_target = null
	_rebuild_hero_path(hero_destination)


func issue_hero_attack_target(target: Enemy) -> void:
	if not _is_enemy_valid(target):
		return
	_cancel_hero_attack_windup()
	hero_order_kind = OrderKind.ATTACK_TARGET
	hero_target = target
	hero_destination = target.global_position
	arena.mark_target = target
	_rebuild_hero_path(target.global_position)


func stop_hero() -> void:
	if arena == null:
		return
	_cancel_hero_attack_windup()
	hero_order_kind = OrderKind.STOP
	hero_target = null
	hero_destination = Vector2.ZERO
	hero_resume_destination = Vector2.ZERO
	arena.mark_target = null
	_clear_hero_path()
	arena.player.velocity = Vector2.ZERO


func physics_tick(delta: float) -> void:
	if arena == null or arena.player == null or not is_instance_valid(arena.player):
		return
	var desired_velocity := Vector2.ZERO
	match hero_order_kind:
		OrderKind.MOVE:
			desired_velocity = _velocity_to_destination(delta, hero_destination, HERO_STOP_DISTANCE)
			if desired_velocity == Vector2.ZERO and arena.player.global_position.distance_to(hero_destination) <= HERO_STOP_DISTANCE:
				hero_order_kind = OrderKind.STOP
		OrderKind.ATTACK_TARGET:
			if not _is_enemy_valid(hero_target) or not _is_enemy_visible(hero_target):
				stop_hero()
			elif arena.player.global_position.distance_to(hero_target.global_position) > HERO_ATTACK_LEASH:
				stop_hero()
			elif not _hero_can_attack(hero_target):
				desired_velocity = _velocity_to_target(delta, hero_target)
		OrderKind.ATTACK_MOVE:
			_update_attack_move_target()
			if _is_enemy_valid(hero_target) and _is_enemy_visible(hero_target):
				if not _hero_can_attack(hero_target):
					desired_velocity = _velocity_to_target(delta, hero_target)
			else:
				desired_velocity = _velocity_to_destination(delta, hero_destination, HERO_STOP_DISTANCE)
				if desired_velocity == Vector2.ZERO and arena.player.global_position.distance_to(hero_destination) <= HERO_STOP_DISTANCE:
					hero_order_kind = OrderKind.HOLD
					hero_hold_anchor = arena.player.global_position
		OrderKind.HOLD, OrderKind.STOP, OrderKind.NONE:
			pass

	arena.player.velocity = desired_velocity
	arena.player.move_and_slide()
	if arena.world_layout != null:
		arena.player.global_position = arena.world_layout.clamp_to_world(arena.player.global_position)
	else:
		arena.player.position.x = clampf(arena.player.position.x, 40, arena.MAP_WIDTH - 40)
		arena.player.position.y = clampf(arena.player.position.y, 40, arena.MAP_HEIGHT - 40)
	_update_player_visual(desired_velocity, delta)


func get_hero_combat_target() -> Enemy:
	if arena == null or hero_order_kind in [OrderKind.MOVE, OrderKind.STOP]:
		return null
	if _is_enemy_valid(hero_target) and _is_enemy_visible(hero_target):
		return hero_target
	if hero_order_kind == OrderKind.ATTACK_MOVE:
		return _find_visible_enemy(arena.player.global_position, ACQUISITION_RANGE)
	if hero_order_kind in [OrderKind.HOLD, OrderKind.NONE]:
		return _find_visible_enemy(arena.player.global_position, arena.player.base_attack_range + HERO_ATTACK_PADDING)
	return null


func get_order_snapshot() -> Dictionary:
	var order_name := "待命"
	match hero_order_kind:
		OrderKind.MOVE: order_name = "移动"
		OrderKind.ATTACK_TARGET: order_name = "攻击目标"
		OrderKind.ATTACK_MOVE: order_name = "攻击移动"
		OrderKind.HOLD: order_name = "原地驻守"
		OrderKind.STOP: order_name = "停止"
	return {"hero_order": order_name, "summon_count": selected_summons.size(), "hero_selected": hero_selected}


func get_selection_snapshot() -> Dictionary:
	var hero_name := "英雄" if hero_selected else ""
	var summon_count := selected_summons.size()
	var text := hero_name
	if summon_count > 0:
		text += (" + " if not text.is_empty() else "") + "召唤物×%d" % summon_count
	if text.is_empty():
		text = "未选中单位"
	return {"text": text, "hero_selected": hero_selected, "summon_count": summon_count}


func has_inspected_target() -> bool:
	return _is_enemy_valid(selected_enemy)


func clear_inspected_target() -> void:
	selected_enemy = null


func get_target_snapshot() -> Dictionary:
	var target: Enemy = null
	if _is_enemy_valid(selected_enemy):
		if _is_enemy_visible(selected_enemy):
			target = selected_enemy
		else:
			selected_enemy = null
	if target == null and _is_enemy_valid(hero_target) and _is_enemy_visible(hero_target):
		target = hero_target
	if target == null:
		return {}
	return {
		"name": _enemy_name(target),
		"hp": target.hp,
		"max_hp": target.max_hp,
		"distance": arena.player.global_position.distance_to(target.global_position),
	}


func notify_enemy_removed(enemy: Enemy) -> void:
	if enemy == hero_target:
		hero_target = null
		if hero_order_kind == OrderKind.ATTACK_TARGET:
			hero_order_kind = OrderKind.NONE
	if enemy == selected_enemy:
		selected_enemy = null


func _update_attack_move_target() -> void:
	if _is_enemy_valid(hero_target) and _is_enemy_visible(hero_target):
		if arena.player.global_position.distance_to(hero_target.global_position) <= ACQUISITION_RANGE * 1.35:
			arena.mark_target = hero_target
			return
	hero_target = _find_visible_enemy(arena.player.global_position, ACQUISITION_RANGE)
	arena.mark_target = hero_target


func _velocity_to_target(delta: float, target: Enemy) -> Vector2:
	var target_pos := _walkable(target.global_position)
	if hero_repath_remaining <= 0.0 or target_pos.distance_to(hero_path_goal) > 48.0:
		_rebuild_hero_path(target_pos)
	# 被树林/岩石遮挡时不能在攻击距离外缘停下，继续绕到可见位置。
	var stop_distance := HERO_ATTACK_PADDING if _has_hero_line_of_sight(target) else HERO_STOP_DISTANCE
	return _velocity_to_path(delta, target_pos, stop_distance)


func _velocity_to_destination(delta: float, destination: Vector2, stop_distance: float) -> Vector2:
	if arena.player.global_position.distance_to(destination) <= stop_distance:
		return Vector2.ZERO
	if hero_repath_remaining <= 0.0 or destination.distance_to(hero_path_goal) > 8.0:
		_rebuild_hero_path(destination)
	return _velocity_to_path(delta, destination, stop_distance)


func _velocity_to_path(delta: float, destination: Vector2, final_stop_distance: float) -> Vector2:
	const WAYPOINT_REACH := 18.0
	hero_repath_remaining = maxf(hero_repath_remaining - delta, 0.0)
	while hero_path_index < hero_path.size() and arena.player.global_position.distance_to(hero_path[hero_path_index]) <= WAYPOINT_REACH:
		hero_path_index += 1
	if hero_path_index < hero_path.size():
		var waypoint := hero_path[hero_path_index]
		var reach_distance := final_stop_distance if hero_path_index == hero_path.size() - 1 else WAYPOINT_REACH
		if arena.player.global_position.distance_to(waypoint) <= reach_distance:
			return Vector2.ZERO
		return arena.player.global_position.direction_to(waypoint) * _hero_speed()
	if arena.player.global_position.distance_to(destination) <= final_stop_distance:
		return Vector2.ZERO
	return arena.player.global_position.direction_to(destination) * _hero_speed()


func _hero_can_attack(target: Enemy) -> bool:
	return _hero_in_attack_range(target) and _has_hero_line_of_sight(target)


func _has_hero_line_of_sight(target: Enemy) -> bool:
	return arena.world_layout == null or not arena.world_layout.is_segment_blocked(arena.player.global_position, target.global_position, 2.0)


func _rebuild_hero_path(destination: Vector2) -> void:
	hero_path.clear()
	hero_path_index = 0
	hero_path_goal = destination
	hero_repath_remaining = REPATH_INTERVAL
	if arena.world_layout != null:
		hero_path = arena.world_layout.find_path(arena.player.global_position, destination)
	if hero_path.is_empty():
		hero_path.append(destination)


func _clear_hero_path() -> void:
	hero_path.clear()
	hero_path_index = 0
	hero_path_goal = Vector2.ZERO
	hero_repath_remaining = 0.0


func _hero_speed() -> float:
	var mult := arena.player.move_speed_mult()
	if arena.aura != null:
		mult *= 1.0 + arena.aura.get_bonus("move_speed_pct")
	return arena.player.base_move_speed * mult


func _hero_in_attack_range(target: Enemy) -> bool:
	return arena.player.global_position.distance_to(target.global_position) <= arena.player.base_attack_range + HERO_ATTACK_PADDING


func _find_visible_enemy(origin: Vector2, radius: float) -> Enemy:
	var best: Enemy = null
	var best_dist := radius * radius
	for candidate in arena.enemies_root.get_children():
		if candidate is Enemy and _is_enemy_valid(candidate as Enemy) and _is_enemy_visible(candidate as Enemy):
			var dist := origin.distance_squared_to((candidate as Enemy).global_position)
			if dist < best_dist:
				best_dist = dist
				best = candidate as Enemy
	return best


func _summon_at(world_pos: Vector2) -> Summon:
	for summon in arena.summons:
		if is_instance_valid(summon) and summon.global_position.distance_to(world_pos) <= 28.0:
			return summon as Summon
	return null


func _enemy_at(world_pos: Vector2) -> Enemy:
	if arena.combat == null:
		return null
	return arena.combat._enemy_at(world_pos)


func _is_enemy_valid(enemy: Enemy) -> bool:
	return enemy != null and is_instance_valid(enemy) and not enemy.is_dead()


func _is_enemy_visible(enemy: Enemy) -> bool:
	return arena.fog == null or arena.fog.is_position_visible(enemy.global_position)


func _walkable(world_pos: Vector2) -> Vector2:
	return arena.world_layout.project_to_walkable(world_pos) if arena.world_layout != null else world_pos


func _select_summon(summon: Summon) -> void:
	if summon == null or not is_instance_valid(summon) or selected_summons.has(summon):
		return
	summon.set_selected(true)
	selected_summons.append(summon)


func _clear_unit_selection() -> void:
	if arena == null:
		return
	if arena.player != null:
		arena.player.set_selected(false)
	for summon in selected_summons:
		if is_instance_valid(summon):
			(summon as Summon).set_selected(false)
	selected_summons.clear()
	hero_selected = false


func _issue_summon_formation(world_pos: Vector2, kind: int) -> void:
	var anchor := _walkable(world_pos)
	for i in range(selected_summons.size()):
		var summon = selected_summons[i]
		if not is_instance_valid(summon):
			continue
		var slot_pos := _walkable(anchor + _formation_offset(i, selected_summons.size()))
		match kind:
			OrderKind.ATTACK_MOVE:
				(summon as Summon).issue_attack_move(slot_pos)
			_:
				(summon as Summon).issue_move(slot_pos)


func _formation_offset(index: int, count: int) -> Vector2:
	if count <= 1:
		return Vector2.ZERO
	var angle := TAU * float(index) / float(count) - PI * 0.5
	var radius: float = 34.0 + 10.0 * floor(float(index) / 5.0)
	return Vector2(cos(angle), sin(angle)) * radius


func _show_order_marker(world_pos: Vector2, color: Color) -> void:
	var marker := Node2D.new()
	marker.global_position = world_pos
	marker.z_index = 8
	var ring := Line2D.new()
	ring.width = 2.0
	ring.default_color = color
	var points := PackedVector2Array()
	for i in range(17):
		var angle := TAU * float(i) / 16.0
		points.append(Vector2(cos(angle), sin(angle)) * 16.0)
	ring.points = points
	marker.add_child(ring)
	arena.add_child(marker)
	var tween := create_tween()
	tween.tween_property(marker, "scale", Vector2(1.55, 1.55), 0.34)
	tween.parallel().tween_property(marker, "modulate:a", 0.0, 0.34)
	tween.tween_callback(marker.queue_free)


func _update_player_visual(velocity: Vector2, delta: float) -> void:
	var sprite := arena.player.get_node_or_null("BodySprite") as Sprite2D
	if sprite == null:
		return
	if velocity.length_squared() > 1.0:
		arena._bounce_phase += delta * 12.0
		sprite.scale = GameData.get_player_visual_scale() + GameData.get_player_bounce_scale() * sin(arena._bounce_phase * 2.0)
	else:
		sprite.scale = sprite.scale.move_toward(GameData.get_player_visual_scale(), delta * 4.0)
		arena._bounce_phase = 0.0


func _cancel_hero_attack_windup() -> void:
	if arena.attack_system != null:
		arena.attack_system.cancel_for_order()


func _enemy_name(enemy: Enemy) -> String:
	match enemy.enemy_type:
		Enemy.EnemyType.BOSS: return "丛林首领"
		Enemy.EnemyType.ELITE: return "精英敌人"
	return "丛林敌人"
