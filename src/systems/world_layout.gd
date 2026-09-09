extends Node2D
class_name WorldLayout

const GRID_SIZE := 64.0
const WORLD_BLOCKER_LAYER := 8
const ROAD_WIDTH := 144.0
const ROAD_OUTER_WIDTH := 176.0
const START_SAFE_RADIUS := 620.0
const CAMP_CLEAR_RADIUS := 220.0
const BOSS_ARENA_RADIUS := 420.0
const WALKABLE_MARGIN := 64.0
const BLOCKER_PADDING := 30.0

var map_size := Vector2.ZERO
var start_position := Vector2.ZERO
var boss_position := Vector2.ZERO
var world_seed := 230917

var _grid: AStarGrid2D
var _grid_size := Vector2i.ZERO
var _roads: Array[PackedVector2Array] = []
var _blockers: Array[Dictionary] = []
var _elite_camps: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()


func build(world_size: Vector2, start: Vector2, boss: Vector2, seed_value: int = world_seed) -> void:
	map_size = world_size
	start_position = start
	boss_position = boss
	world_seed = seed_value
	_rng.seed = world_seed
	z_index = -40
	_roads = _make_roads()
	_elite_camps = _make_elite_camps()
	_blockers = _make_blockers()
	_build_path_grid()
	_create_blocker_bodies()
	queue_redraw()


func _make_roads() -> Array[PackedVector2Array]:
	var main_road := PackedVector2Array([
		start_position,
		Vector2(1300, 720),
		Vector2(1820, 1000),
		Vector2(2360, 1500),
		boss_position,
	])
	return [
		main_road,
		PackedVector2Array([Vector2(1300, 720), Vector2(1500, 420)]),
		PackedVector2Array([Vector2(1820, 1000), Vector2(1600, 1450)]),
		PackedVector2Array([Vector2(1820, 1000), Vector2(2350, 650)]),
		PackedVector2Array([Vector2(2360, 1500), Vector2(2400, 2700)]),
		PackedVector2Array([boss_position, Vector2(3600, 1050)]),
		PackedVector2Array([boss_position, Vector2(3900, 1800)]),
		PackedVector2Array([boss_position, Vector2(3950, 2800)]),
		PackedVector2Array([Vector2(2400, 2700), Vector2(3000, 3400)]),
		PackedVector2Array([Vector2(1600, 1450), Vector2(1900, 3200)]),
		PackedVector2Array([Vector2(3600, 1050), Vector2(4700, 900)]),
		PackedVector2Array([Vector2(3900, 1800), Vector2(5000, 2100)]),
		PackedVector2Array([Vector2(3950, 2800), Vector2(5100, 3200)]),
	]


func _make_elite_camps() -> Array[Dictionary]:
	var centers := [
		Vector2(1500, 420), Vector2(1600, 1450), Vector2(2350, 650),
		Vector2(2400, 2700), Vector2(3600, 1050), Vector2(3900, 1800),
		Vector2(3950, 2800), Vector2(3000, 3400), Vector2(1900, 3200),
		Vector2(4700, 900), Vector2(5000, 2100), Vector2(5100, 3200),
	]
	var camps: Array[Dictionary] = []
	for i in range(centers.size()):
		camps.append({"id": "elite_camp_%02d" % (i + 1), "center": centers[i]})
	return camps


func _make_blockers() -> Array[Dictionary]:
	var candidates := [
		{"center": Vector2(1080, 1380), "radius": 108.0},
		{"center": Vector2(1880, 300), "radius": 112.0},
		{"center": Vector2(2570, 250), "radius": 96.0},
		{"center": Vector2(3220, 520), "radius": 118.0},
		{"center": Vector2(4300, 440), "radius": 122.0},
		{"center": Vector2(5350, 700), "radius": 106.0},
		{"center": Vector2(5400, 1500), "radius": 128.0},
		{"center": Vector2(5520, 2570), "radius": 116.0},
		{"center": Vector2(4570, 2820), "radius": 122.0},
		{"center": Vector2(3650, 3620), "radius": 106.0},
		{"center": Vector2(2260, 3650), "radius": 124.0},
		{"center": Vector2(1000, 3100), "radius": 126.0},
		{"center": Vector2(760, 2180), "radius": 104.0},
		{"center": Vector2(1300, 2370), "radius": 108.0},
		{"center": Vector2(3150, 3100), "radius": 90.0},
		{"center": Vector2(4450, 1450), "radius": 100.0},
	]
	var blockers: Array[Dictionary] = []
	for candidate in candidates:
		var center: Vector2 = candidate.get("center", Vector2.ZERO)
		var radius: float = float(candidate.get("radius", 96.0))
		if _can_place_blocker(center, radius):
			blockers.append({"center": center, "radius": radius})
	return blockers


func _can_place_blocker(center: Vector2, radius: float) -> bool:
	if center.x < radius + WALKABLE_MARGIN or center.y < radius + WALKABLE_MARGIN:
		return false
	if center.x > map_size.x - radius - WALKABLE_MARGIN or center.y > map_size.y - radius - WALKABLE_MARGIN:
		return false
	if center.distance_to(start_position) < START_SAFE_RADIUS + radius:
		return false
	if center.distance_to(boss_position) < BOSS_ARENA_RADIUS + radius + 40.0:
		return false
	for camp in _elite_camps:
		var camp_center: Vector2 = camp.get("center", Vector2.ZERO)
		if center.distance_to(camp_center) < CAMP_CLEAR_RADIUS + radius + 64.0:
			return false
	return _distance_to_roads(center) >= ROAD_OUTER_WIDTH * 0.5 + radius + 36.0


func _build_path_grid() -> void:
	_grid_size = Vector2i(int(ceil(map_size.x / GRID_SIZE)), int(ceil(map_size.y / GRID_SIZE)))
	_grid = AStarGrid2D.new()
	_grid.region = Rect2i(Vector2i.ZERO, _grid_size)
	_grid.cell_size = Vector2(GRID_SIZE, GRID_SIZE)
	_grid.offset = Vector2(GRID_SIZE * 0.5, GRID_SIZE * 0.5)
	_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ALWAYS
	_grid.update()

	for x in range(_grid_size.x):
		for y in range(_grid_size.y):
			var cell := Vector2i(x, y)
			var pos := _cell_to_world(cell)
			if pos.x < WALKABLE_MARGIN or pos.y < WALKABLE_MARGIN or pos.x > map_size.x - WALKABLE_MARGIN or pos.y > map_size.y - WALKABLE_MARGIN:
				_grid.set_point_solid(cell, true)

	for blocker in _blockers:
		_mark_blocker_on_grid(blocker.get("center", Vector2.ZERO), float(blocker.get("radius", 0.0)))


func _mark_blocker_on_grid(center: Vector2, radius: float) -> void:
	var padded_radius := radius + BLOCKER_PADDING
	var min_cell := _world_to_cell(center - Vector2.ONE * padded_radius)
	var max_cell := _world_to_cell(center + Vector2.ONE * padded_radius)
	for x in range(maxi(min_cell.x, 0), mini(max_cell.x, _grid_size.x - 1) + 1):
		for y in range(maxi(min_cell.y, 0), mini(max_cell.y, _grid_size.y - 1) + 1):
			var cell := Vector2i(x, y)
			if _cell_to_world(cell).distance_to(center) <= padded_radius:
				_grid.set_point_solid(cell, true)


func _create_blocker_bodies() -> void:
	for child in get_children():
		child.queue_free()
	for i in range(_blockers.size()):
		var blocker_data: Dictionary = _blockers[i]
		var blocker := StaticBody2D.new()
		blocker.name = "TreeGrove_%02d" % (i + 1)
		blocker.position = blocker_data.get("center", Vector2.ZERO)
		blocker.collision_layer = WORLD_BLOCKER_LAYER
		blocker.collision_mask = 0
		blocker.add_to_group("world_blocker")
		var collision := CollisionShape2D.new()
		var shape := CircleShape2D.new()
		shape.radius = float(blocker_data.get("radius", 96.0))
		collision.shape = shape
		blocker.add_child(collision)
		add_child(blocker)


func get_elite_camps() -> Array:
	return _elite_camps.duplicate(true)

func get_roads() -> Array:
	return _roads.duplicate()

func get_camp_positions() -> Array:
	var positions: Array = []
	for camp in _elite_camps:
		positions.append(camp.get("center", Vector2.ZERO))
	return positions


func get_starter_spawn_positions() -> Array:
	var offsets := [
		Vector2(300, 20), Vector2(360, 130), Vector2(430, 250), Vector2(260, 280),
		Vector2(500, 90), Vector2(500, 330), Vector2(170, 390), Vector2(330, 440),
	]
	var positions: Array = []
	for offset in offsets:
		positions.append(project_to_walkable(start_position + offset))
	return positions


func get_boss_spawn_position() -> Vector2:
	return boss_position


func get_respawn_position() -> Vector2:
	return start_position


func get_random_walkable_position(reference: Vector2, min_distance_from_reference: float = 0.0, avoid_landmarks: bool = true) -> Vector2:
	for _attempt in range(96):
		var pos := Vector2(
			_rng.randf_range(WALKABLE_MARGIN, map_size.x - WALKABLE_MARGIN),
			_rng.randf_range(WALKABLE_MARGIN, map_size.y - WALKABLE_MARGIN)
		)
		if min_distance_from_reference > 0.0 and pos.distance_to(reference) < min_distance_from_reference:
			continue
		if not is_walkable(pos):
			continue
		if avoid_landmarks and _is_reserved_landmark_space(pos, 0.0):
			continue
		return pos
	return project_to_walkable(Vector2(map_size.x - 160.0, map_size.y - 160.0))


func _is_reserved_landmark_space(pos: Vector2, padding: float) -> bool:
	if pos.distance_to(start_position) < START_SAFE_RADIUS + padding:
		return true
	if pos.distance_to(boss_position) < BOSS_ARENA_RADIUS + padding:
		return true
	for camp in _elite_camps:
		var camp_center: Vector2 = camp.get("center", Vector2.ZERO)
		if pos.distance_to(camp_center) < CAMP_CLEAR_RADIUS + padding:
			return true
	return false


func project_to_walkable(position: Vector2) -> Vector2:
	var clamped := Vector2(
		clampf(position.x, WALKABLE_MARGIN, map_size.x - WALKABLE_MARGIN),
		clampf(position.y, WALKABLE_MARGIN, map_size.y - WALKABLE_MARGIN)
	)
	if is_walkable(clamped):
		return clamped
	var cell := _nearest_walkable_cell(clamped)
	return _cell_to_world(cell) if cell.x >= 0 else clamped


func is_walkable(position: Vector2) -> bool:
	if _grid == null:
		return true
	var cell := _world_to_cell(position)
	return _is_valid_cell(cell) and not _grid.is_point_solid(cell)


func find_path(from: Vector2, to: Vector2) -> PackedVector2Array:
	if _grid == null:
		var direct := PackedVector2Array()
		direct.append(to)
		return direct
	var start_cell := _nearest_walkable_cell(from)
	var end_cell := _nearest_walkable_cell(to)
	if start_cell.x < 0 or end_cell.x < 0:
		return PackedVector2Array()
	var path := _grid.get_point_path(start_cell, end_cell)
	if path.is_empty():
		return PackedVector2Array()
	var projected_target := project_to_walkable(to)
	if path[path.size() - 1].distance_to(projected_target) > 8.0:
		path.append(projected_target)
	return path


func is_segment_blocked(from: Vector2, to: Vector2, padding: float = 0.0) -> bool:
	for blocker in _blockers:
		var center: Vector2 = blocker.get("center", Vector2.ZERO)
		var radius := float(blocker.get("radius", 0.0)) + padding
		if _distance_to_segment(center, from, to) <= radius:
			return true
	return false


func _nearest_walkable_cell(position: Vector2) -> Vector2i:
	var origin := _world_to_cell(position)
	if _is_valid_cell(origin) and not _grid.is_point_solid(origin):
		return origin
	for radius in range(1, 16):
		for x in range(origin.x - radius, origin.x + radius + 1):
			for y in range(origin.y - radius, origin.y + radius + 1):
				if abs(x - origin.x) != radius and abs(y - origin.y) != radius:
					continue
				var cell := Vector2i(x, y)
				if _is_valid_cell(cell) and not _grid.is_point_solid(cell):
					return cell
	return Vector2i(-1, -1)


func _world_to_cell(position: Vector2) -> Vector2i:
	return Vector2i(int(floor(position.x / GRID_SIZE)), int(floor(position.y / GRID_SIZE)))


func _cell_to_world(cell: Vector2i) -> Vector2:
	return Vector2((float(cell.x) + 0.5) * GRID_SIZE, (float(cell.y) + 0.5) * GRID_SIZE)


func _is_valid_cell(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < _grid_size.x and cell.y < _grid_size.y


func _distance_to_roads(point: Vector2) -> float:
	var best := INF
	for road in _roads:
		for i in range(road.size() - 1):
			best = minf(best, _distance_to_segment(point, road[i], road[i + 1]))
	return best


func _distance_to_segment(point: Vector2, from: Vector2, to: Vector2) -> float:
	var segment := to - from
	var length_sq := segment.length_squared()
	if length_sq <= 0.001:
		return point.distance_to(from)
	var t := clampf((point - from).dot(segment) / length_sq, 0.0, 1.0)
	return point.distance_to(from + segment * t)


func _draw() -> void:
	for road in _roads:
		draw_polyline(road, Color(0.13, 0.17, 0.10, 0.90), ROAD_OUTER_WIDTH, true)
		draw_polyline(road, Color(0.43, 0.34, 0.19, 0.92), ROAD_WIDTH, true)
		draw_polyline(road, Color(0.58, 0.48, 0.28, 0.45), 5.0, true)

	for camp in _elite_camps:
		var camp_center: Vector2 = camp.get("center", Vector2.ZERO)
		draw_circle(camp_center, CAMP_CLEAR_RADIUS, Color(0.08, 0.06, 0.03, 0.10))
		draw_arc(camp_center, CAMP_CLEAR_RADIUS, 0.0, TAU, 48, Color(0.86, 0.64, 0.20, 0.55), 2.0, true)
		draw_arc(camp_center, CAMP_CLEAR_RADIUS - 18.0, 0.0, TAU, 48, Color(0.22, 0.16, 0.06, 0.85), 3.0, true)

	draw_circle(start_position, 155.0, Color(0.12, 0.30, 0.23, 0.16))
	draw_arc(start_position, 155.0, 0.0, TAU, 40, Color(0.34, 0.82, 0.60, 0.65), 2.0, true)

	draw_circle(boss_position, BOSS_ARENA_RADIUS, Color(0.26, 0.05, 0.07, 0.18))
	draw_arc(boss_position, BOSS_ARENA_RADIUS, 0.0, TAU, 64, Color(0.74, 0.20, 0.28, 0.90), 4.0, true)
	draw_arc(boss_position, BOSS_ARENA_RADIUS - 28.0, 0.0, TAU, 64, Color(0.43, 0.08, 0.13, 0.90), 3.0, true)
	draw_arc(boss_position, 110.0, 0.0, TAU, 40, Color(0.96, 0.45, 0.24, 0.75), 2.0, true)

	for blocker in _blockers:
		_draw_tree_grove(blocker.get("center", Vector2.ZERO), float(blocker.get("radius", 96.0)))


func _draw_tree_grove(center: Vector2, radius: float) -> void:
	draw_circle(center + Vector2(10, 14), radius * 0.92, Color(0.03, 0.07, 0.04, 0.45))
	var tree_count := clampi(int(radius / 22.0), 4, 7)
	for i in range(tree_count):
		var angle := TAU * float(i) / float(tree_count) + 0.45
		var ring_radius := radius * (0.34 if i % 2 == 0 else 0.56)
		var tree_pos := center + Vector2(cos(angle), sin(angle)) * ring_radius
		var crown_radius := radius * (0.22 if i % 2 == 0 else 0.18)
		draw_circle(tree_pos + Vector2(3, 7), crown_radius, Color(0.04, 0.10, 0.05, 0.72))
		draw_circle(tree_pos, crown_radius, Color(0.06, 0.25, 0.10, 1.0))
		draw_circle(tree_pos - Vector2(4, 5), crown_radius * 0.62, Color(0.16, 0.42, 0.17, 0.92))
		draw_arc(tree_pos, crown_radius, 0.0, TAU, 20, Color(0.02, 0.09, 0.03, 0.95), 2.0, true)
