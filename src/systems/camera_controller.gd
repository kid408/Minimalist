extends Node
class_name CameraController

const Arena = preload("res://src/arena.gd")

enum Mode { FOLLOW_HERO, FREE }

const EDGE_SCROLL_SIZE := 22.0
const EDGE_SCROLL_SPEED := 760.0
const ZOOM_STEP := 0.10
const MIN_ZOOM := 0.85
const MAX_ZOOM := 1.35

var arena: Arena
var camera: Camera2D
var mode: int = Mode.FOLLOW_HERO
var _dragging := false
var _edge_scroll_armed := false
var _pointer_screen := Vector2(-1.0, -1.0)
var _last_drag_screen := Vector2.ZERO


func setup(owner: Arena, controlled_camera: Camera2D) -> void:
	arena = owner
	camera = controlled_camera
	follow_hero(false)


func process_tick(delta: float, pointer_over_ui: bool) -> void:
	if arena == null or camera == null or not is_instance_valid(camera):
		return
	var direction := Vector2.ZERO
	if _edge_scroll_armed and not pointer_over_ui and not _dragging:
		direction = _edge_scroll_direction()
	if mode == Mode.FOLLOW_HERO:
		if direction.length_squared() > 0.0:
			mode = Mode.FREE
			camera.global_position += direction.normalized() * EDGE_SCROLL_SPEED * delta
			_clamp_camera()
			return
		if arena.player != null and is_instance_valid(arena.player):
			camera.global_position = arena.player.global_position
		return
	if pointer_over_ui or _dragging or direction.length_squared() <= 0.0:
		return
	camera.global_position += direction.normalized() * EDGE_SCROLL_SPEED * delta
	_clamp_camera()


func _edge_scroll_direction() -> Vector2:
	var mouse := _pointer_screen if _pointer_screen.x >= 0.0 else arena.get_viewport().get_mouse_position()
	var view_size := arena.get_viewport().get_visible_rect().size
	var direction := Vector2.ZERO
	if mouse.x <= EDGE_SCROLL_SIZE:
		direction.x -= 1.0
	elif mouse.x >= view_size.x - EDGE_SCROLL_SIZE:
		direction.x += 1.0
	if mouse.y <= EDGE_SCROLL_SIZE:
		direction.y -= 1.0
	elif mouse.y >= view_size.y - EDGE_SCROLL_SIZE:
		direction.y += 1.0
	return direction


func handle_input(event: InputEvent) -> bool:
	if camera == null or not is_instance_valid(camera):
		return false
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		_pointer_screen = mouse_event.position
		if mouse_event.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = mouse_event.pressed
			_last_drag_screen = mouse_event.position
			if mouse_event.pressed:
				mode = Mode.FREE
			return true
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_set_zoom(camera.zoom.x + ZOOM_STEP)
			return true
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_set_zoom(camera.zoom.x - ZOOM_STEP)
			return true
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		_pointer_screen = motion.position
		_edge_scroll_armed = true
		if _dragging:
			mode = Mode.FREE
			camera.global_position -= motion.relative / maxf(camera.zoom.x, 0.01)
			_clamp_camera()
			_last_drag_screen = motion.position
			return true
	return false


func jump_to(world_pos: Vector2) -> void:
	mode = Mode.FREE
	camera.global_position = world_pos
	_clamp_camera()


func follow_hero(select_hero: bool = true) -> void:
	mode = Mode.FOLLOW_HERO
	if arena != null and arena.player != null and is_instance_valid(arena.player):
		camera.global_position = arena.player.global_position
		if select_hero and arena.command_system != null:
			arena.command_system.select_hero()


func get_world_view_rect() -> Rect2:
	if camera == null or not is_instance_valid(camera) or arena == null:
		return Rect2()
	var viewport_size := arena.get_viewport().get_visible_rect().size / maxf(camera.zoom.x, 0.01)
	var rect := Rect2(camera.global_position - viewport_size * 0.5, viewport_size)
	if arena.world_layout != null:
		var world_rect := arena.world_layout.get_world_rect()
		rect.position.x = clampf(rect.position.x, world_rect.position.x, maxf(world_rect.end.x - rect.size.x, world_rect.position.x))
		rect.position.y = clampf(rect.position.y, world_rect.position.y, maxf(world_rect.end.y - rect.size.y, world_rect.position.y))
	return rect


func get_mode_name() -> String:
	return "跟随英雄" if mode == Mode.FOLLOW_HERO else "自由镜头"


func _set_zoom(next_zoom: float) -> void:
	camera.zoom = Vector2.ONE * clampf(next_zoom, MIN_ZOOM, MAX_ZOOM)
	_clamp_camera()


func _clamp_camera() -> void:
	if arena == null or camera == null:
		return
	if arena.world_layout != null:
		camera.global_position = arena.world_layout.clamp_to_world(camera.global_position)
	else:
		camera.global_position.x = clampf(camera.global_position.x, 0.0, arena.MAP_WIDTH)
		camera.global_position.y = clampf(camera.global_position.y, 0.0, arena.MAP_HEIGHT)
