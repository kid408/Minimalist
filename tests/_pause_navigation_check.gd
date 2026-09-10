extends SceneTree

# 暂停导航验证：从真实 Main 场景进入战场，再通过暂停菜单返回主菜单。
# 运行：godot --headless --path <项目根目录> --script res://tests/_pause_navigation_check.gd

const MainScene = preload("res://scenes/main.tscn")


func _initialize() -> void:
	var main = MainScene.instantiate()
	root.add_child(main)
	current_scene = main
	await process_frame

	var menu = main.get_node_or_null("MainMenu")
	if menu == null:
		printerr("PAUSENAV_ERR 初始主菜单缺失")
		quit(1)
		return
	menu._start_game()
	var arena = menu.current_arena
	await process_frame
	if arena == null or not is_instance_valid(arena):
		printerr("PAUSENAV_ERR 未能进入战场")
		quit(1)
		return

	if not arena.hud.open_pause_menu():
		printerr("PAUSENAV_ERR 未能打开暂停菜单")
		quit(1)
		return
	arena.hud.return_to_main_menu()
	await process_frame
	await process_frame

	var returned_menu = current_scene.get_node_or_null("MainMenu") if current_scene != null else null
	if returned_menu == null or paused or Engine.time_scale != 1.0:
		printerr("PAUSENAV_ERR 返回主菜单状态异常")
		quit(1)
		return

	print("PAUSENAV_OK")
	quit(0)
