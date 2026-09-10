extends SceneTree

# Esc 暂停验证：优先关闭临时弹窗或取消当前操作；无操作时打开暂停菜单并可恢复。
# 运行：godot --headless --path <项目根目录> --script res://tests/_pause_menu_check.gd

const Arena = preload("res://src/arena.gd")


func _initialize() -> void:
	var game_root := Node.new()
	root.add_child(game_root)
	current_scene = game_root
	var arena := Arena.new()
	game_root.add_child(arena)
	await process_frame

	var failures: Array[String] = []
	var esc := _escape_event()
	arena._unhandled_input(esc)
	if not arena.hud.is_pause_menu_open() or not paused:
		failures.append("Esc 未打开暂停菜单")
	if arena.hud.pause_menu == null or arena.hud.pause_menu.get_node_or_null("ResumeButton") == null or arena.hud.pause_menu.get_node_or_null("MainMenuButton") == null or arena.hud.pause_menu.get_node_or_null("QuitButton") == null:
		failures.append("暂停菜单按钮不完整")

	arena.hud._input(_escape_event())
	if arena.hud.is_pause_menu_open() or paused:
		failures.append("Esc 未从暂停菜单继续游戏")

	arena._preview_index = 0
	arena._unhandled_input(_escape_event())
	if arena._preview_index >= 0 or arena.hud.is_pause_menu_open():
		failures.append("Esc 未优先取消技能预览")

	arena.hud.toggle_attribute_panel()
	arena.hud._input(_escape_event())
	if arena.hud.attr_panel.visible or arena.hud.is_pause_menu_open() or paused:
		failures.append("Esc 未优先关闭属性面板")

	arena.hud.show_idol_popup("测试代价", func(): pass, func(): pass)
	if not arena.hud.has_modal() or not paused:
		failures.append("祭坛弹窗未进入模态暂停")
	arena.hud._input(_escape_event())
	if arena.hud.has_modal() or arena.hud.is_pause_menu_open() or paused:
		failures.append("Esc 关闭弹窗后暂停状态异常")

	arena.stop_player_movement()
	arena._set_player_move_target(arena.player.global_position + Vector2(300, 0))
	arena.hud.open_pause_menu()
	if arena._player_moving or arena._player_chase_target != null:
		failures.append("打开暂停菜单未清理英雄移动订单")
	arena.hud.close_pause_menu()

	arena.free()
	if failures.is_empty():
		print("PAUSEMENU_OK")
		quit(0)
	else:
		for failure in failures:
			printerr("PAUSEMENU_ERR %s" % failure)
		quit(1)


func _escape_event() -> InputEventKey:
	var event := InputEventKey.new()
	event.pressed = true
	event.physical_keycode = KEY_ESCAPE
	return event
