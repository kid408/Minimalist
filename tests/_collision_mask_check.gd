extends SceneTree

# 单位碰撞验证：英雄只受世界阻挡物限制，敌人和召唤物不应将英雄实体推挤漂移。
# 运行：godot --headless --path <项目根目录> --script res://tests/_collision_mask_check.gd

const Arena = preload("res://src/arena.gd")


func _initialize() -> void:
	var game_root := Node.new()
	root.add_child(game_root)
	current_scene = game_root
	var arena := Arena.new()
	game_root.add_child(arena)
	await process_frame

	var failures: Array[String] = []
	if arena.player.collision_layer != 1 or arena.player.collision_mask != 8:
		failures.append("英雄实体碰撞层配置异常")
	if arena.world_layout.get_tree().get_nodes_in_group("world_blocker").is_empty():
		failures.append("世界阻挡物未创建")

	var enemy = null
	for candidate in arena.enemies_root.get_children():
		if candidate is Enemy and not candidate.is_dead():
			enemy = candidate
			break
	if enemy == null:
		failures.append("未找到测试敌人")
	else:
		if (enemy as Enemy).collision_mask & 1 != 0:
			failures.append("敌人仍与英雄发生实体碰撞")
		arena.stop_player_movement()
		arena.player.global_position = Vector2(900, 900)
		enemy.global_position = arena.player.global_position + Vector2(38, 0)
		enemy.chase_target = arena.player
		enemy.detection_range = 500.0
		var start_position := arena.player.global_position
		for _frame in range(20):
			await physics_frame
		if arena.player.global_position.distance_to(start_position) > 0.1:
			failures.append("敌人接近时英雄发生实体漂移")

	var summon = Summon.new()
	summon.arena = arena
	summon.owner_player = arena.player
	arena.summons_root.add_child(summon)
	arena.summons.append(summon)
	await process_frame
	if summon.collision_mask & 1 != 0:
		failures.append("召唤物仍与英雄发生实体碰撞")

	arena.free()
	if failures.is_empty():
		print("COLLISIONMASK_OK")
		quit(0)
	else:
		for failure in failures:
			printerr("COLLISIONMASK_ERR %s" % failure)
		quit(1)
