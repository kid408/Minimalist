extends Area2D
class_name Projectile

const SkillEffects = preload("res://src/systems/skill_effects.gd")

var speed: float = 600.0
var damage: float = 30.0
var direction: Vector2 = Vector2.RIGHT
var lifetime: float = 3.0
var pierce_count: int = 3
var knockback: float = 80.0
var hit_targets: Array = []
var effects: Dictionary = {}          # 命中时施加的状态效果

var _elapsed: float = 0.0

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= lifetime:
		queue_free()
		return
	position += direction * speed * delta

func _on_body_entered(body: Node2D) -> void:
	if body == null:
		return
	if hit_targets.has(body):
		return
	hit_targets.append(body)
	if body.has_method("take_damage"):
		body.take_damage(damage, direction, knockback)
	# 命中时把所有控制/减益原语交给 SkillEffects 统一施加（与近战结算一致）
	if body.has_method("apply_status"):
		SkillEffects.apply_to_target(body, effects, {"caster": null, "arena": null, "dmg": damage, "from_pos": global_position, "effects": effects})
	if hit_targets.size() >= pierce_count:
		queue_free()
