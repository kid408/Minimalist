extends SceneTree

# 多分辨率 UI 验证：以 `--resolution` 启动时检查固定逻辑画布、关键 HUD 面板和弹窗均在内容区域内。
# 示例：godot --windowed --resolution 1280x720 --path <项目根目录> --script res://tests/_display_layout_check.gd

const Arena = preload("res://src/arena.gd")
const LOGICAL_SIZE := Vector2(1440, 810)


func _initialize() -> void:
	var game_root := Node.new()
	game_root.name = "LayoutCheckRoot"
	root.add_child(game_root)
	current_scene = game_root

	var arena := Arena.new()
	game_root.add_child(arena)
	await process_frame
	await process_frame

	var failures: Array[String] = []
	var physical_size := DisplayServer.window_get_size()
	var content_size := Vector2(root.content_scale_size)
	var is_headless: bool = DisplayServer.get_name() == "headless"
	if not is_headless and (physical_size.x <= 0 or physical_size.y <= 0):
		failures.append("窗口物理尺寸无效：%s" % physical_size)
	if content_size != LOGICAL_SIZE:
		failures.append("逻辑画布异常：%s，期望 %s" % [content_size, LOGICAL_SIZE])

	var hud := arena.hud
	var panels: Array[Control] = [
		hud.get_node("TopLeft") as Control,
		hud.get_node("ProgPanel") as Control,
		hud.get_node("WarehousePanel") as Control,
		hud.get_node("SkillPanel") as Control,
		hud.get_node("EquipPanel") as Control,
		hud.get_node("GroundZonePlaceholder") as Control,
		hud.get_node("MinimapPlaceholder") as Control,
		hud.get_node("TradePanel") as Control,
		hud.get_node("SkillSelectPanel") as Control,
		hud.get_node("IdolPopup") as Control,
		hud.get_node("ReplacePanel") as Control,
		hud.attr_panel,
		hud.objective_panel,
		hud.settlement_panel,
	]
	for panel in panels:
		if panel == null:
			failures.append("HUD 面板缺失")
			continue
		var rect := Rect2(panel.position, panel.size)
		if rect.position.x < -0.5 or rect.position.y < -0.5 or rect.end.x > LOGICAL_SIZE.x + 0.5 or rect.end.y > LOGICAL_SIZE.y + 0.5:
			failures.append("HUD 越界：%s %s" % [panel.name, rect])

	var window_mode: int = int(DisplayServer.window_get_mode())
	var stretch_mode := String(ProjectSettings.get_setting("display/window/stretch/mode", ""))
	var stretch_aspect := String(ProjectSettings.get_setting("display/window/stretch/aspect", ""))
	print("DISPLAYLAYOUT_INFO physical=%s content=%s aspect=%.4f mode=%d stretch=%s/%s" % [physical_size, content_size, float(physical_size.x) / maxf(float(physical_size.y), 1.0), window_mode, stretch_mode, stretch_aspect])
	if failures.is_empty():
		print("DISPLAYLAYOUT_OK")
		arena.free()
		quit(0)
	else:
		for failure in failures:
			printerr("DISPLAYLAYOUT_ERR %s" % failure)
		arena.free()
		quit(1)
