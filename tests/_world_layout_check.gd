extends SceneTree

# 世界布局体检：验证道路、营地、Boss 区与可通行网格的基本连通性。
# 运行：godot --headless --path <项目根目录> --script res://tests/_world_layout_check.gd

const WorldLayout = preload("res://src/systems/world_layout.gd")

const WORLD_SIZE := Vector2(6000, 4200)
const START_POSITION := Vector2(800, 600)
const BOSS_POSITION := Vector2(3000, 2100)


func _initialize() -> void:
	var layout := WorldLayout.new()
	root.add_child(layout)
	layout.build(WORLD_SIZE, START_POSITION, BOSS_POSITION)
	await process_frame

	var failures: Array[String] = []
	if not layout.is_walkable(START_POSITION):
		failures.append("出生点不可通行")
	if not layout.is_walkable(BOSS_POSITION):
		failures.append("Boss 点不可通行")

	var boss_path := layout.find_path(START_POSITION, BOSS_POSITION)
	if boss_path.is_empty():
		failures.append("出生点无法到达 Boss 区")

	var camps := layout.get_elite_camps()
	if camps.size() != 12:
		failures.append("精英营数量异常：%d" % camps.size())
	for camp in camps:
		var center: Vector2 = camp.get("center", Vector2.ZERO)
		if not layout.is_walkable(center):
			failures.append("营地不可通行：%s" % camp.get("id", "unknown"))
		elif layout.find_path(START_POSITION, center).is_empty():
			failures.append("出生点无法到达营地：%s" % camp.get("id", "unknown"))

	var projected := layout.project_to_walkable(Vector2(1080, 1380))
	if not layout.is_walkable(projected):
		failures.append("障碍投影未落在可通行格")

	if failures.is_empty():
		print("WORLDLAYOUT_OK camps=%d boss_path=%d" % [camps.size(), boss_path.size()])
		quit(0)
	else:
		for failure in failures:
			printerr("WORLDLAYOUT_ERR %s" % failure)
		quit(1)
