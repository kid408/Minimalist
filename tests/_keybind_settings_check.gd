extends SceneTree

# 按键设置验证：检查设置页层级返回、按键捕获、冲突拦截、交互/拾取拆分和持久化。
# 运行：godot --headless --path <项目根目录> --script res://tests/_keybind_settings_check.gd

const MainMenu = preload("res://scenes/ui/main_menu.tscn")
const InputBindings = preload("res://src/input_bindings.gd")

const TEST_CONFIG_PATH := "user://input_bindings_settings_test.cfg"


func _initialize() -> void:
	InputBindings.set_storage_path_for_testing(TEST_CONFIG_PATH)
	InputBindings.clear_storage_for_testing()

	var game_root := Node.new()
	root.add_child(game_root)
	current_scene = game_root
	var menu = MainMenu.instantiate()
	game_root.add_child(menu)
	await process_frame

	var failures: Array[String] = []
	_expect_event_key("interact", KEY_SPACE, "交互默认键", failures)
	_expect_event_key("pickup", KEY_SPACE, "拾取默认键", failures)

	menu.settings_button.emit_signal("pressed")
	if not menu._settings_panel.visible or menu._keybind_panel.visible:
		failures.append("设置主页未正确打开")
	_expect_panel_in_bounds(menu._settings_panel, "设置主页", failures)
	menu._open_keybind_settings()
	if menu._settings_page != "keybind" or not menu._keybind_panel.visible:
		failures.append("按键设置页未正确打开")
	_expect_panel_in_bounds(menu._keybind_panel, "按键设置页", failures)

	menu._begin_key_capture("skill_1")
	menu._input(_key_event(KEY_Q))
	_expect_event_key("skill_1", KEY_Q, "技能1重绑", failures)
	if not menu.hint_label.text.contains("Q"):
		failures.append("主菜单未刷新重绑后的技能提示")

	menu._begin_key_capture("skill_2")
	menu._input(_key_event(KEY_Q))
	_expect_event_key("skill_2", KEY_2, "冲突键拦截", failures)

	menu._begin_key_capture("interact")
	menu._input(_key_event(KEY_E))
	menu._begin_key_capture("pickup")
	menu._input(_key_event(KEY_F))
	_expect_event_key("interact", KEY_E, "交互拆分重绑", failures)
	_expect_event_key("pickup", KEY_F, "拾取拆分重绑", failures)

	InputBindings.initialize()
	_expect_event_key("skill_1", KEY_Q, "技能1持久化", failures)
	_expect_event_key("interact", KEY_E, "交互持久化", failures)
	_expect_event_key("pickup", KEY_F, "拾取持久化", failures)

	menu._begin_key_capture("skill_3")
	menu._input(_key_event(KEY_ESCAPE))
	if not menu._capturing_action.is_empty() or menu._settings_page != "keybind":
		failures.append("Esc 未取消按键捕获")
	menu._input(_key_event(KEY_ESCAPE))
	if menu._settings_page != "settings":
		failures.append("Esc 未返回设置主页")
	menu._input(_key_event(KEY_ESCAPE))
	if not menu._settings_page.is_empty():
		failures.append("Esc 未返回主菜单")

	InputBindings.reset_rebindable_to_defaults()
	_expect_event_key("skill_1", KEY_1, "恢复默认技能1", failures)
	_expect_event_key("interact", KEY_SPACE, "恢复默认交互", failures)
	_expect_event_key("pickup", KEY_SPACE, "恢复默认拾取", failures)

	InputBindings.clear_storage_for_testing()
	InputBindings.restore_default_storage_path()
	menu.free()

	if failures.is_empty():
		print("KEYBINDSETTINGS_OK")
		quit(0)
	else:
		for failure in failures:
			printerr("KEYBINDSETTINGS_ERR %s" % failure)
		quit(1)


func _expect_panel_in_bounds(panel: Control, title: String, failures: Array[String]) -> void:
	if panel == null:
		failures.append("%s缺失" % title)
		return
	var rect := Rect2(panel.position, panel.size)
	var bounds := Rect2(Vector2.ZERO, Vector2(1440, 810))
	if not bounds.encloses(rect):
		failures.append("%s越出逻辑画布：%s" % [title, rect])


func _key_event(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.pressed = true
	event.physical_keycode = keycode
	return event


func _expect_event_key(action_name: String, expected: Key, title: String, failures: Array[String]) -> void:
	var event := InputBindings.get_primary_key_event(action_name)
	if event == null or event.physical_keycode != expected:
		failures.append("%s异常：%s" % [title, InputBindings.get_action_key_text(action_name)])
