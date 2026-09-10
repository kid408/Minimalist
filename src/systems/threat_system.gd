extends Node
class_name ThreatSystem

const Arena = preload("res://src/arena.gd")
const Enemy = preload("res://src/actors/enemy.gd")

const THREAT_DECAY_PER_SECOND := 0.72
const TARGET_STICKINESS := 1.20
const HERO_BASE_THREAT := 1.0

var arena: Arena
var _tables: Dictionary = {}


func setup(owner: Arena) -> void:
	arena = owner


func report_damage(enemy: Enemy, source: Node2D, amount: float) -> void:
	if enemy == null or source == null or not is_instance_valid(enemy) or not is_instance_valid(source):
		return
	var enemy_id := enemy.get_instance_id()
	if not _tables.has(enemy_id):
		_tables[enemy_id] = {}
	var table: Dictionary = _tables[enemy_id]
	var source_id := source.get_instance_id()
	var entry: Dictionary = table.get(source_id, {"ref": weakref(source), "value": 0.0})
	entry["value"] = float(entry.get("value", 0.0)) + maxf(amount, 0.0)
	table[source_id] = entry
	_tables[enemy_id] = table


func choose_target(enemy: Enemy) -> Node2D:
	if arena == null or enemy == null or not is_instance_valid(enemy):
		return null
	var candidates: Array = []
	if arena.player != null and is_instance_valid(arena.player):
		candidates.append(arena.player)
	for summon in arena.summons:
		if is_instance_valid(summon):
			candidates.append(summon)
	if candidates.is_empty():
		return null

	var table: Dictionary = _tables.get(enemy.get_instance_id(), {})
	var best: Node2D = null
	var best_score := -INF
	for candidate in candidates:
		var distance := enemy.global_position.distance_to(candidate.global_position)
		if distance > enemy.detection_range * 1.35:
			continue
		var entry: Dictionary = table.get(candidate.get_instance_id(), {})
		var score := float(entry.get("value", 0.0))
		if candidate == arena.player:
			score += HERO_BASE_THREAT
		if candidate == enemy.chase_target:
			score *= TARGET_STICKINESS
		if score <= 0.0:
			score = 0.05 / maxf(distance, 1.0)
		if score > best_score:
			best_score = score
			best = candidate
	return best


func process_tick(delta: float) -> void:
	var remove_enemy_ids: Array = []
	for enemy_id in _tables.keys():
		var table: Dictionary = _tables[enemy_id]
		var remove_source_ids: Array = []
		for source_id in table.keys():
			var entry: Dictionary = table[source_id]
			var source_ref: WeakRef = entry.get("ref", null)
			var source = source_ref.get_ref() if source_ref != null else null
			if source == null or not is_instance_valid(source):
				remove_source_ids.append(source_id)
				continue
			entry["value"] = maxf(0.0, float(entry.get("value", 0.0)) - THREAT_DECAY_PER_SECOND * delta)
			if float(entry["value"]) <= 0.001:
				remove_source_ids.append(source_id)
			else:
				table[source_id] = entry
		for source_id in remove_source_ids:
			table.erase(source_id)
		if table.is_empty():
			remove_enemy_ids.append(enemy_id)
		else:
			_tables[enemy_id] = table
	for enemy_id in remove_enemy_ids:
		_tables.erase(enemy_id)


func clear_enemy(enemy: Enemy) -> void:
	if enemy != null:
		_tables.erase(enemy.get_instance_id())
