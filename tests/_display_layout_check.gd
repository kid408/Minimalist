extends SceneTree

# 多分辨率 UI 验证：以 `--resolution` 启动时检查固定逻辑画布、关键 HUD 面板和弹窗均在内容区域内。
# 示例：godot --windowed --resolution 1280x720 --path <项目根目录> --script res://tests/_display_layout_check.gd

const Arena = preload("res://src/arena.gd")
const LOGICAL_SIZE := Vector2(1440, 810)


func _expect_size(control: Control, expected: Vector2, title: String, failures: Array[String]) -> void:
	if control == null or control.size != expected:
		failures.append("%s尺寸异常：%s，期望 %s" % [title, control.size if control != null else Vector2.ZERO, expected])


func _validate_compact_grid(grid: HBoxContainer, expected_count: int, expected_slot_size: Vector2, title: String, failures: Array[String]) -> void:
	if grid == null or grid.get_child_count() != expected_count:
		failures.append("%s数量异常" % title)
		return
	if grid.size.y < expected_slot_size.y:
		failures.append("%s容器高度不足：%s" % [title, grid.size])
	for child in grid.get_children():
		if child is Control and (child as Control).custom_minimum_size != expected_slot_size:
			failures.append("%s尺寸异常：%s" % [title, (child as Control).custom_minimum_size])


func _validate_fusion_grid(grid: HBoxContainer, failures: Array[String]) -> void:
	if grid == null or grid.get_child_count() != 6:
		failures.append("技能融合单元数量异常")
		return
	for unit in grid.get_children():
		if not (unit is VBoxContainer) or (unit as VBoxContainer).custom_minimum_size != Vector2(56, 68):
			failures.append("技能融合单元尺寸异常")
			continue
		if unit.get_child_count() != 3:
			failures.append("技能融合子槽数量异常")


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
		hud.pause_menu,
	]
	for panel in panels:
		if panel == null:
			failures.append("HUD 面板缺失")
			continue
		var rect := Rect2(panel.position, panel.size)
		if rect.position.x < -0.5 or rect.position.y < -0.5 or rect.end.x > LOGICAL_SIZE.x + 0.5 or rect.end.y > LOGICAL_SIZE.y + 0.5:
			failures.append("HUD 越界：%s %s" % [panel.name, rect])

	_expect_size(hud.get_node("WarehousePanel") as Control, Vector2(380, 82), "仓库面板", failures)
	_expect_size(hud.get_node("EquipPanel") as Control, Vector2(380, 82), "装备面板", failures)
	_expect_size(hud.get_node("SkillPanel") as Control, Vector2(380, 102), "技能面板", failures)
	_expect_size(hud.get_node("GroundZonePlaceholder") as Control, Vector2(380, 44), "丢弃区", failures)
	_expect_size(hud.get_node("MinimapPlaceholder") as Control, Vector2(112, 80), "小地图", failures)
	_expect_size(hud.objective_panel, Vector2(480, 26), "目标条", failures)
	_expect_size(hud.pause_menu, Vector2(360, 260), "暂停菜单", failures)
	_validate_compact_grid(hud.warehouse_grid, 6, Vector2(56, 56), "仓库槽", failures)
	_validate_compact_grid(hud.equip_grid, 6, Vector2(56, 56), "装备槽", failures)
	_validate_fusion_grid(hud.skill_grid, failures)

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
