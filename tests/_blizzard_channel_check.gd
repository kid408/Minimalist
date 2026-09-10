extends SceneTree

# 暴风雪验证：点地确认、施法距离、锁定落点、站桩中断与固定波次数。
# 运行：godot --headless --path <项目根目录> --script res://tests/_blizzard_channel_check.gd

const Arena = preload("res://src/arena.gd")
const CommandSystem = preload("res://src/systems/command_system.gd")
const GameData = preload("res://src/data/game_data.gd")
const SkillChannel = preload("res://src/systems/skill_channel.gd")


func _initialize() -> void:
	var game_root := Node.new()
	root.add_child(game_root)
	current_scene = game_root
	var arena := Arena.new()
	game_root.add_child(arena)
	await process_frame

	var failures: Array[String] = []
	var field := GameData.get_skill("blizzard")
	var blizzard := GameData.get_skill("blizzard_channel")
	if String(field.get("name", "")) != "冰霜领域" or String(field.get("cast_mode", "")) != "point":
		failures.append("非引导冰系地面技能命名或施法类型异常")
	if String(blizzard.get("name", "")) != "暴风雪" or String(blizzard.get("cast_mode", "")) != "channel":
		failures.append("引导暴风雪数据异常")

	arena.skill_slots[0] = blizzard
	arena.player.energy = 1000.0
	arena.cooldowns[arena.skill_actions[0]] = 0.0
	var initial_energy := arena.player.energy
	var valid_point := arena.player.global_position + Vector2(180, 0)
	var out_of_range := arena.player.global_position + Vector2(700, 0)

	arena._start_skill_preview(0)
	arena._release_skill(0)
	if not arena.skill_engine.is_ground_targeting() or arena.skill_engine.is_channeling():
		failures.append("暴风雪未进入点地选取状态")
	if arena._preview_node == null or not is_instance_valid(arena._preview_node):
		failures.append("暴风雪点地选取时未保留鼠标范围预览")
	if arena.player.energy != initial_energy:
		failures.append("点地确认前错误消耗能量")

	arena.skill_engine.try_pick_target(out_of_range)
	if not arena.skill_engine.is_ground_targeting() or arena.skill_engine.is_channeling():
		failures.append("超距地面点未被正确拒绝")

	arena.skill_engine.try_pick_target(valid_point)
	if arena.skill_engine.is_ground_targeting() or not arena.skill_engine.is_channeling():
		failures.append("有效地面点未开始暴风雪引导")
	if arena.skill_engine.channel.point.distance_to(valid_point) > 0.1:
		failures.append("暴风雪未锁定确认时的地面位置")
	if arena.skill_engine.channel_visual == null or not is_instance_valid(arena.skill_engine.channel_visual):
		failures.append("暴风雪持续区域视觉未创建")

	# 鼠标右键应在同一次命令中打断暴风雪并建立英雄移动订单。
	arena._handle_right_click(valid_point + Vector2(80, 0))
	if arena.skill_engine.is_channeling():
		failures.append("移动命令未立即打断暴风雪")
	if arena.skill_engine.channel_visual != null:
		failures.append("引导中断后暴风雪视觉未清理")
	if arena.command_system.hero_order_kind != CommandSystem.OrderKind.MOVE:
		failures.append("右键未同时打断暴风雪并执行移动命令")
	arena.stop_player_movement()

	arena.cooldowns[arena.skill_actions[0]] = 0.0
	arena.player.energy = 1000.0
	arena.skill_engine.request_cast(0)
	arena.skill_engine.try_pick_target(valid_point)
	for _tick in range(8):
		arena.skill_engine._process_channel(0.5)
	if arena.skill_engine.is_channeling() or arena.skill_engine.channel_index != -1 or arena.skill_engine.channel_visual != null:
		failures.append("暴风雪自然完成后状态未清理")
	arena.cooldowns[arena.skill_actions[0]] = 0.0
	arena.skill_engine.request_cast(0)
	if not arena.skill_engine.is_ground_targeting():
		failures.append("暴风雪自然完成后无法再次施放")
	arena.skill_engine.cancel_targeting("")
	arena._cancel_skill_preview()

	var channel := SkillChannel.new()
	var pulse_state := {"count": 0}
	channel.start({"name": "波次测试", "duration": 4.0, "tick_interval": 0.5}, 1.0, Vector2.ZERO, Vector2.ZERO, func(_def, _dmg, _point, _unit): pulse_state["count"] += 1)
	for _tick in range(8):
		channel.update(0.5, Vector2.ZERO)
	if int(pulse_state["count"]) != 8 or channel.is_active():
		failures.append("4秒/0.5秒引导波次异常：%d" % int(pulse_state["count"]))

	var zone_enemy := Enemy.new()
	zone_enemy.global_position = valid_point
	zone_enemy.setup(1000.0, 0.0, 0.0, 1.0)
	zone_enemy.set_physics_process(false)
	arena.enemies_root.add_child(zone_enemy)
	await process_frame
	var hp_before := zone_enemy.hp
	arena._spawn_persistent_damage(valid_point, 80.0, 10.0, 1.0, 0.5, {}, "ice")
	await create_timer(0.25).timeout
	if zone_enemy.hp != hp_before:
		failures.append("冰霜领域在首个间隔前提前结算")
	await create_timer(0.35).timeout
	if zone_enemy.hp > hp_before - 9.9:
		failures.append("冰霜领域首个间隔未结算伤害")
	await create_timer(0.50).timeout
	if zone_enemy.hp > hp_before - 19.9:
		failures.append("冰霜领域未按后续间隔持续结算伤害")

	arena.free()
	if failures.is_empty():
		print("BLIZZARDCHANNEL_OK")
		quit(0)
	else:
		for failure in failures:
			printerr("BLIZZARDCHANNEL_ERR %s" % failure)
		quit(1)
