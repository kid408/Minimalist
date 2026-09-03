extends Node

const MainMenu = preload("res://scenes/ui/main_menu.tscn")


func _ready() -> void:
	randomize()
	ensure_input_map()
	var menu := MainMenu.instantiate()
	add_child(menu)


func ensure_input_map() -> void:
	_ensure_key_action("move_up", KEY_W)
	_ensure_key_action("move_down", KEY_S)
	_ensure_key_action("move_left", KEY_A)
	_ensure_key_action("move_right", KEY_D)
	_ensure_key_action("skill_1", KEY_1)
	_ensure_key_action("skill_2", KEY_2)
	_ensure_key_action("skill_3", KEY_3)
	_ensure_key_action("skill_4", KEY_4)
	_ensure_key_action("skill_5", KEY_5)
	_ensure_key_action("skill_6", KEY_6)
	_ensure_key_action("interact", KEY_SPACE)
	_ensure_key_action("summon_spawn", KEY_J)
	_ensure_key_action("attributes", KEY_T)

	if not InputMap.has_action("ui_cancel"):
		InputMap.add_action("ui_cancel")
	var esc := InputEventKey.new()
	esc.physical_keycode = KEY_ESCAPE
	if InputMap.action_get_events("ui_cancel").is_empty():
		InputMap.action_add_event("ui_cancel", esc)


func _ensure_key_action(action_name: String, keycode: Key, allow_existing: bool = false) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	if allow_existing and not InputMap.action_get_events(action_name).is_empty():
		return
	if not allow_existing:
		for event in InputMap.action_get_events(action_name):
			InputMap.action_erase_event(action_name, event)
	var physical_event := InputEventKey.new()
	physical_event.physical_keycode = keycode
	InputMap.action_add_event(action_name, physical_event)
	var logical_event := InputEventKey.new()
	logical_event.keycode = keycode
	InputMap.action_add_event(action_name, logical_event)
