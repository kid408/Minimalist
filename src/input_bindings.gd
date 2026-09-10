extends RefCounted
class_name InputBindings

const CONFIG_SECTION := "keybindings"
const DEFAULT_CONFIG_PATH := "user://input_bindings.cfg"

const DEFAULT_ACTIONS := {
	"move_up": KEY_W,
	"move_down": KEY_S,
	"move_left": KEY_A,
	"move_right": KEY_D,
	"skill_1": KEY_1,
	"skill_2": KEY_2,
	"skill_3": KEY_3,
	"skill_4": KEY_4,
	"skill_5": KEY_5,
	"skill_6": KEY_6,
	"interact": KEY_SPACE,
	"pickup": KEY_SPACE,
	"summon_spawn": KEY_J,
	"attributes": KEY_T,
	"ui_cancel": KEY_ESCAPE,
}

const REBINDABLE_ACTIONS := [
	{"action": "skill_1", "label": "技能 1"},
	{"action": "skill_2", "label": "技能 2"},
	{"action": "skill_3", "label": "技能 3"},
	{"action": "skill_4", "label": "技能 4"},
	{"action": "skill_5", "label": "技能 5"},
	{"action": "skill_6", "label": "技能 6"},
	{"action": "interact", "label": "交互"},
	{"action": "pickup", "label": "拾取"},
]

const RESERVED_KEYS := [KEY_W, KEY_A, KEY_S, KEY_D, KEY_J, KEY_T]

static var _config_path := DEFAULT_CONFIG_PATH


static func initialize() -> void:
	for action_name in DEFAULT_ACTIONS:
		_ensure_action_exists(action_name)

	var config := ConfigFile.new()
	var has_saved_bindings := config.load(_config_path) == OK
	for action_name in DEFAULT_ACTIONS:
		var saved_event: InputEventKey = null
		if has_saved_bindings and config.has_section_key(CONFIG_SECTION, action_name):
			saved_event = _event_from_data(config.get_value(CONFIG_SECTION, action_name))
		if saved_event != null:
			_replace_action_event(action_name, saved_event)
		elif InputMap.action_get_events(action_name).is_empty():
			_replace_action_event(action_name, _make_key_event(int(DEFAULT_ACTIONS[action_name])))


static func get_rebindable_actions() -> Array:
	return REBINDABLE_ACTIONS.duplicate(true)


static func get_action_label(action_name: String) -> String:
	for definition in REBINDABLE_ACTIONS:
		if String(definition.get("action", "")) == action_name:
			return String(definition.get("label", action_name))
	return action_name


static func get_action_key_text(action_name: String) -> String:
	var event := get_primary_key_event(action_name)
	return get_event_text(event) if event != null else "未设置"


static func get_primary_key_event(action_name: String) -> InputEventKey:
	if not InputMap.has_action(action_name):
		return null
	for event in InputMap.action_get_events(action_name):
		if event is InputEventKey:
			return event as InputEventKey
	return null


static func get_event_text(event: InputEventKey) -> String:
	if event == null:
		return "未设置"
	var keycode := _event_keycode(event)
	if keycode == KEY_NONE:
		return "未设置"
	var parts := PackedStringArray()
	if event.ctrl_pressed:
		parts.append("Ctrl")
	if event.alt_pressed:
		parts.append("Alt")
	if event.shift_pressed:
		parts.append("Shift")
	if event.meta_pressed:
		parts.append("Meta")
	parts.append(OS.get_keycode_string(keycode))
	return "+".join(parts)


static func bind_action(action_name: String, source_event: InputEventKey) -> Dictionary:
	if not _is_rebindable(action_name):
		return {"ok": false, "message": "该动作不支持修改。"}
	if source_event == null:
		return {"ok": false, "message": "请按下一个有效键。"}

	var event := _clone_key_event(source_event)
	var keycode := _event_keycode(event)
	if keycode == KEY_NONE:
		return {"ok": false, "message": "请按下一个有效键。"}
	if keycode == KEY_ESCAPE:
		return {"ok": false, "message": "Esc 用于取消设置，不能绑定。"}
	if RESERVED_KEYS.has(keycode):
		return {"ok": false, "message": "%s 为保留操作键，暂不支持绑定。" % get_event_text(event)}

	var conflict_action := _find_conflicting_action(action_name, event)
	if not conflict_action.is_empty() and not _can_share_binding(action_name, conflict_action):
		return {
			"ok": false,
			"message": "%s 已绑定给【%s】。" % [get_event_text(event), get_action_label(conflict_action)],
		}

	_replace_action_event(action_name, event)
	_save_rebindable_bindings()
	return {"ok": true, "message": "【%s】已设为 %s。" % [get_action_label(action_name), get_event_text(event)]}


static func reset_rebindable_to_defaults() -> void:
	for definition in REBINDABLE_ACTIONS:
		var action_name := String(definition.get("action", ""))
		_replace_action_event(action_name, _make_key_event(int(DEFAULT_ACTIONS[action_name])))
	_save_rebindable_bindings()


static func set_storage_path_for_testing(path: String) -> void:
	_config_path = path


static func clear_storage_for_testing() -> void:
	var absolute_path := ProjectSettings.globalize_path(_config_path)
	if FileAccess.file_exists(_config_path):
		DirAccess.remove_absolute(absolute_path)


static func restore_default_storage_path() -> void:
	_config_path = DEFAULT_CONFIG_PATH


static func _ensure_action_exists(action_name: String) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)


static func _replace_action_event(action_name: String, event: InputEventKey) -> void:
	_ensure_action_exists(action_name)
	for old_event in InputMap.action_get_events(action_name):
		InputMap.action_erase_event(action_name, old_event)
	InputMap.action_add_event(action_name, event)


static func _make_key_event(keycode: int) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	return event


static func _clone_key_event(source: InputEventKey) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = source.physical_keycode
	event.keycode = source.keycode
	event.ctrl_pressed = source.ctrl_pressed
	event.alt_pressed = source.alt_pressed
	event.shift_pressed = source.shift_pressed
	event.meta_pressed = source.meta_pressed
	return event


static func _event_keycode(event: InputEventKey) -> int:
	return int(event.physical_keycode) if event.physical_keycode != KEY_NONE else int(event.keycode)


static func _is_rebindable(action_name: String) -> bool:
	for definition in REBINDABLE_ACTIONS:
		if String(definition.get("action", "")) == action_name:
			return true
	return false


static func _find_conflicting_action(action_name: String, event: InputEventKey) -> String:
	for definition in REBINDABLE_ACTIONS:
		var other_action := String(definition.get("action", ""))
		if other_action == action_name:
			continue
		var other_event := get_primary_key_event(other_action)
		if other_event != null and _events_match(event, other_event):
			return other_action
	return ""


static func _can_share_binding(first_action: String, second_action: String) -> bool:
	return (first_action == "interact" and second_action == "pickup") or (first_action == "pickup" and second_action == "interact")


static func _events_match(left: InputEventKey, right: InputEventKey) -> bool:
	return _event_keycode(left) == _event_keycode(right) \
		and left.ctrl_pressed == right.ctrl_pressed \
		and left.alt_pressed == right.alt_pressed \
		and left.shift_pressed == right.shift_pressed \
		and left.meta_pressed == right.meta_pressed


static func _event_to_data(event: InputEventKey) -> Dictionary:
	return {
		"physical_keycode": int(event.physical_keycode),
		"keycode": int(event.keycode),
		"ctrl_pressed": event.ctrl_pressed,
		"alt_pressed": event.alt_pressed,
		"shift_pressed": event.shift_pressed,
		"meta_pressed": event.meta_pressed,
	}


static func _event_from_data(data: Variant) -> InputEventKey:
	if typeof(data) != TYPE_DICTIONARY:
		return null
	var values := data as Dictionary
	var physical_keycode := int(values.get("physical_keycode", KEY_NONE))
	var keycode := int(values.get("keycode", KEY_NONE))
	if physical_keycode == KEY_NONE and keycode == KEY_NONE:
		return null
	var event := InputEventKey.new()
	event.physical_keycode = physical_keycode
	event.keycode = keycode
	event.ctrl_pressed = bool(values.get("ctrl_pressed", false))
	event.alt_pressed = bool(values.get("alt_pressed", false))
	event.shift_pressed = bool(values.get("shift_pressed", false))
	event.meta_pressed = bool(values.get("meta_pressed", false))
	return event


static func _save_rebindable_bindings() -> void:
	var config := ConfigFile.new()
	for definition in REBINDABLE_ACTIONS:
		var action_name := String(definition.get("action", ""))
		var event := get_primary_key_event(action_name)
		if event != null:
			config.set_value(CONFIG_SECTION, action_name, _event_to_data(event))
	config.save(_config_path)
