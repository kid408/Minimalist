extends Node
class_name AttackSystem

const Arena = preload("res://src/arena.gd")
const Enemy = preload("res://src/actors/enemy.gd")
const GameData = preload("res://src/data/game_data.gd")

enum Phase { IDLE, WINDUP, BACKSWING }

const DEFAULT_ATTACK_POINT := 0.16
const MIN_BACKSWING := 0.08

var arena: Arena
var phase: int = Phase.IDLE
var phase_left := 0.0
var pending_target: Enemy = null
var attack_point := DEFAULT_ATTACK_POINT
var backswing := MIN_BACKSWING


func setup(owner: Arena) -> void:
	arena = owner
	if arena.player != null:
		attack_point = arena.player.attack_point
		backswing = arena.player.backswing


func process_tick(delta: float) -> void:
	if arena == null or arena.player == null or not is_instance_valid(arena.player):
		return
	if arena.skill_engine != null and arena.skill_engine.is_channeling():
		cancel_for_order()
		return

	var target := arena.command_system.get_hero_combat_target() if arena.command_system != null else null
	match phase:
		Phase.IDLE:
			if _can_attack(target):
				_begin_attack(target)
		Phase.WINDUP:
			if not _can_attack(pending_target):
				cancel_for_order()
				return
			phase_left -= delta
			if phase_left <= 0.0:
				_resolve_attack_point()
		Phase.BACKSWING:
			phase_left -= delta
			if phase_left <= 0.0:
				_finish_attack()


func cancel_for_order() -> void:
	if phase == Phase.IDLE:
		return
	phase = Phase.IDLE
	phase_left = 0.0
	pending_target = null
	_set_attack_visual(false)


func is_winding_up() -> bool:
	return phase == Phase.WINDUP


func get_phase_name() -> String:
	match phase:
		Phase.WINDUP: return "攻击前摇"
		Phase.BACKSWING: return "攻击后摇"
	return "待命"


func _begin_attack(target: Enemy) -> void:
	pending_target = target
	var attack_speed := maxf(0.05, arena.player.attack_speed_mult())
	if arena.aura != null:
		attack_speed *= 1.0 + arena.aura.get_bonus("attack_speed_pct")
	var interval := arena.player.base_attack_interval / attack_speed
	var scaled_point := minf(interval * 0.72, attack_point / attack_speed)
	phase = Phase.WINDUP
	phase_left = maxf(0.04, scaled_point)
	backswing = maxf(MIN_BACKSWING, interval - phase_left)
	_set_attack_visual(true)


func _resolve_attack_point() -> void:
	if not _can_attack(pending_target):
		cancel_for_order()
		return
	var damage := arena.player.base_attack_damage * arena.player.melee_damage_mult()
	if arena.aura != null:
		damage *= 1.0 + arena.aura.get_bonus("damage_pct")
	damage *= arena.player.temp_buff_mult("damage_pct")
	arena.combat.resolve_basic_attack(arena.player, pending_target, damage)
	phase = Phase.BACKSWING
	phase_left = backswing
	_set_attack_visual(false)


func _finish_attack() -> void:
	phase = Phase.IDLE
	phase_left = 0.0
	pending_target = null
	_set_attack_visual(false)


func _can_attack(target: Enemy) -> bool:
	if target == null or not is_instance_valid(target) or target.is_dead():
		return false
	if arena.fog != null and not arena.fog.is_position_visible(target.global_position):
		return false
	if arena.player.global_position.distance_to(target.global_position) > arena.player.base_attack_range + 34.0:
		return false
	if arena.world_layout != null and arena.world_layout.is_segment_blocked(arena.player.global_position, target.global_position, 2.0):
		return false
	return true


func _set_attack_visual(winding_up: bool) -> void:
	if arena == null or arena.player == null:
		return
	var sprite := arena.player.get_node_or_null("BodySprite") as Sprite2D
	if sprite == null:
		return
	var base_scale := GameData.get_player_visual_scale()
	if winding_up:
		sprite.modulate = Color(1.0, 0.88, 0.62)
		sprite.scale = base_scale * Vector2(1.08, 0.92)
	else:
		sprite.modulate = Color.WHITE
		sprite.scale = base_scale
