extends SceneTree

# HUD 键位显示验证：自定义技能键后，战斗内技能槽必须展示实际映射，仓库/装备槽不得伪装为快捷键。
# 运行：godot --headless --path <项目根目录> --script res://tests/_hud_keybind_display_check.gd

const Arena = preload("res://src/arena.gd")
const InputBindings = preload("res://src/input_bindings.gd")

const TEST_CONFIG_PATH := "user://input_bindings_hud_display_test.cfg"
const TEST_KEYS := [KEY_Q, KEY_E, KEY_R, KEY_F, KEY_Z, KEY_X]


func _initialize() -> void:
	InputBindings.set_storage_path_for_testing(TEST_CONFIG_PATH)
	InputBindings.clear_storage_for_testing()
	InputBindings.initialize()

	var failures: Array[String] = []
	for i in range(TEST_KEYS.size()):
		var event := InputEventKey.new()
		event.physical_keycode = TEST_KEYS[i]
		if not bool(InputBindings.bind_action("skill_%d" % (i + 1), event).get("ok", false)):
			failures.append("技能%d自定义按键失败" % (i + 1))

	var game_root := Node.new()
	root.add_child(game_root)
	current_scene = game_root
	var arena := Arena.new()
	game_root.add_child(arena)
	await process_frame
	await process_frame

	for i in range(6):
		var slot := arena.hud._host_slot(i)
		var expected := InputBindings.get_action_key_text("skill_%d" % (i + 1))
		if slot == null or slot.slot_label.text != expected:
			failures.append("技能%d HUD 键位异常：%s，期望 %s" % [i + 1, slot.slot_label.text if slot != null else "缺失", expected])

	var warehouse_slot := arena.hud.warehouse_grid.get_child(0)
	var equipment_slot := arena.hud.equip_grid.get_child(0)
	if warehouse_slot == null or warehouse_slot.slot_label.text != "仓库":
		failures.append("仓库槽仍显示伪快捷键")
	if equipment_slot == null or equipment_slot.slot_label.text != "装备":
		failures.append("装备槽仍显示伪快捷键")

	arena.free()
	InputBindings.reset_rebindable_to_defaults()
	InputBindings.clear_storage_for_testing()
	InputBindings.restore_default_storage_path()
	if failures.is_empty():
		print("HUDKEYDISPLAY_OK")
		quit(0)
	else:
		for failure in failures:
			printerr("HUDKEYDISPLAY_ERR %s" % failure)
		quit(1)
