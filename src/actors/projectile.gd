extends Area2D
class_name Projectile

enum Faction { PLAYER, ENEMY }

var speed: float = 600.0
var damage: float = 30.0
var direction: Vector2 = Vector2.RIGHT
var lifetime: float = 3.0
var pierce_count: int = 3
var knockback: float = 80.0
var faction: int = Faction.PLAYER
var attacker: Node2D = null
var hit_resolver: Callable
var hit_targets: Array = []
var effects: Dictionary = {}

var _elapsed: float = 0.0

func _physics_process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= lifetime:
		queue_free()
		return
	position += direction * speed * delta

func _on_body_entered(body: Node2D) -> void:
	if body == null or not is_instance_valid(body):
		return
	if body.is_in_group("world_blocker"):
		queue_free()
		return
	if not _can_hit(body) or hit_targets.has(body):
		return
	hit_targets.append(body)
	if hit_resolver.is_valid():
		hit_resolver.call(body, self)
	if hit_targets.size() >= pierce_count:
		queue_free()

func _can_hit(body: Node2D) -> bool:
	match faction:
		Faction.PLAYER:
			return body.is_in_group("enemy")
		Faction.ENEMY:
			return body.is_in_group("player")
	return false
