extends SceneTree

# 鼠标 RTS 操作回归：无 WASD、持续攻击追击、独立召唤物命令、镜头、战争迷雾和技能栏点击。
# 运行：godot --headless --path <项目根目录> --script res://tests/_command_system_check.gd

const Arena = preload("res://src/arena.gd")
const CommandSystem = preload("res://src/systems/command_system.gd")
const Enemy = preload("res://src/actors/enemy.gd")
const GameData = preload("res://src/data/game_data.gd")
const Summon = preload("res://src/actors/summon.gd")


func _initialize() -> void:
	var game_root := Node.new()
	root.add_child(game_root)
	current_scene = game_root
	var arena := Arena.new()
	game_root.add_child(arena)
	await process_frame

	var failures: Array[String] = []
	arena.player.hp = 100000.0
	if InputMap.has_action("move_up") or InputMap.has_action("move_down") or InputMap.has_action("move_left") or InputMap.has_action("move_right"):
		failures.append("WASD 移动动作仍存在")

	var enemy := Enemy.new()
	enemy.global_position = arena.player.global_position + Vector2(190, 0)
	enemy.setup(500.0, 0.0, 0.0, 1.0)
	enemy.world_ref = arena.world
	arena.enemies_root.add_child(enemy)
	await process_frame
	enemy.set_physics_process(false)
	arena.fog._rebuild_visibility()

	arena.command_system.issue_hero_attack_target(enemy)
	arena.command_system.physics_tick(0.10)
	enemy.global_position += Vector2(120, 0)
	arena.command_system.physics_tick(0.10)
	if arena.command_system.hero_order_kind != CommandSystem.OrderKind.ATTACK_TARGET or arena.command_system.hero_target != enemy:
		failures.append("攻击目标订单未持续追踪移动敌人")
	if arena.command_system.hero_path_goal.distance_to(arena.world_layout.project_to_walkable(enemy.global_position)) > 1.0:
		failures.append("攻击目标移动后未重建追击路径")
	# 中间 A* 节点在攻击停距内时仍必须前进，不能误判为已到达攻击位置。
	var path_origin := arena.player.global_position
	arena.command_system.hero_path = PackedVector2Array([path_origin + Vector2(24, 0), path_origin + Vector2(120, 0)])
	arena.command_system.hero_path_index = 0
	var path_velocity := arena.command_system._velocity_to_path(0.0, path_origin + Vector2(120, 0), 34.0)
	if path_velocity.length_squared() <= 0.001:
		failures.append("攻击追击在中间路径节点提前停车")
	arena.command_system.stop_hero()
	if arena.command_system.hero_order_kind != CommandSystem.OrderKind.STOP or arena.command_system.get_hero_combat_target() != null:
		failures.append("停止命令未阻止英雄自动普攻")

	enemy.global_position = arena.player.global_position + Vector2(1500, 0)
	arena.command_system.selected_enemy = enemy
	arena.fog._rebuild_visibility()
	if not arena.command_system.get_target_snapshot().is_empty():
		failures.append("不可见检查目标仍泄漏 HUD 信息")
	arena.command_system.clear_inspected_target()

	var summon_a := _make_summon(arena, arena.player.global_position + Vector2(-36, 52))
	var summon_b := _make_summon(arena, arena.player.global_position + Vector2(36, 52))
	await process_frame
	summon_a.set_physics_process(false)
	summon_b.set_physics_process(false)
	arena.command_system.select_all_summons()
	var formation_target := arena.world_layout.project_to_walkable(arena.player.global_position + Vector2(240, 120))
	arena.command_system.issue_context_order(formation_target)
	if arena.command_system.hero_order_kind != CommandSystem.OrderKind.STOP:
		failures.append("只选中召唤物时右键错误移动了英雄")
	if summon_a.order_kind != Summon.OrderKind.MOVE or summon_b.order_kind != Summon.OrderKind.MOVE:
		failures.append("召唤物右键移动订单未下达")
	if summon_a.order_destination.distance_to(summon_b.order_destination) < 4.0:
		failures.append("召唤物移动订单未分配队形落点")
	arena.command_system.issue_hold()
	if summon_a.order_kind != Summon.OrderKind.HOLD or summon_b.order_kind != Summon.OrderKind.HOLD:
		failures.append("召唤物驻守订单未下达")
	arena.command_system.issue_follow()
	if summon_a.order_kind != Summon.OrderKind.FOLLOW or summon_b.order_kind != Summon.OrderKind.FOLLOW:
		failures.append("召唤物跟随订单未下达")
	arena.command_system.issue_stop()
	if summon_a.order_kind != Summon.OrderKind.STOP or summon_b.order_kind != Summon.OrderKind.STOP:
		failures.append("召唤物停止订单未下达")
	summon_a.issue_hold()
	var hold_anchor := summon_a.hold_anchor
	summon_a.global_position = hold_anchor + Vector2(72, 0)
	summon_a._think(0.1)
	if summon_a.velocity.length_squared() <= 0.001:
		failures.append("驻守召唤物离开锚点后未返回")

	var distant_pos := arena.world_layout.project_to_walkable(arena.player.global_position + Vector2(1100, 0))
	arena.fog._rebuild_visibility()
	if arena.fog.is_position_visible(distant_pos):
		failures.append("未探索远处区域错误显示为可见")
	var scout := _make_summon(arena, distant_pos)
	await process_frame
	scout.set_physics_process(false)
	arena.fog._rebuild_visibility()
	if not arena.fog.is_position_visible(distant_pos):
		failures.append("召唤物未提供战争迷雾视野")

	arena.camera_controller.jump_to(arena.MAP_CENTER)
	var camera_rect := arena.camera_controller.get_world_view_rect()
	if not camera_rect.has_point(arena.MAP_CENTER):
		failures.append("自由镜头未跳转到小地图目标位置")
	arena.camera_controller.follow_hero()
	if arena.camera_controller.get_mode_name() != "跟随英雄":
		failures.append("镜头未恢复英雄跟随模式")
	var edge_motion := InputEventMouseMotion.new()
	edge_motion.position = Vector2(1, 400)
	arena.camera_controller.handle_input(edge_motion)
	arena.camera_controller.process_tick(0.1, false)
	if arena.camera_controller.get_mode_name() != "自由镜头":
		failures.append("镜头边缘滚动未从跟随模式切换为自由镜头")
	arena.camera_controller.follow_hero(false)

	arena.skill_slots[0] = GameData.get_skill("blizzard_channel")
	arena.player.energy = 1000.0
	arena.cooldowns[arena.skill_actions[0]] = 0.0
	arena.request_skill_from_hud(0)
	if not arena.skill_engine.is_ground_targeting():
		failures.append("技能栏点击未进入暴风雪点地选择")
	arena.skill_engine.cancel_targeting("")
	arena._cancel_skill_preview()

	# 拖入重复技能被拒绝时，不应取消已经进入的点地施法状态。
	arena.warehouse_slots[0] = GameData.get_skill("blizzard_channel")
	arena.cooldowns[arena.skill_actions[0]] = 0.0
	arena.skill_engine.request_cast(0)
	arena.inventory._handle_drag("warehouse", 0, "skill", 2)
	if not arena.skill_engine.is_ground_targeting():
		failures.append("失败的重复技能拖拽错误取消了当前施法")
	arena.skill_engine.cancel_targeting("")

	# 重生充能与开关技能必须在死亡后清理，且换槽重算不能补回已消耗次数。
	arena.skill_slots[0] = GameData.get_skill("mana_shield")
	arena.skill_slots[1] = GameData.get_skill("rebirth_passive")
	arena.on_loadout_changed()
	arena.get_passive_combat()
	arena.player.energy = 1000.0
	arena.cooldowns[arena.skill_actions[0]] = 0.0
	arena.skill_engine.request_cast(0)
	if not arena.skill_engine.is_toggle_on(0):
		failures.append("测试用法力护盾未开启")
	if arena.player.reincarnate_charges != 1:
		failures.append("重生被动未正确提供初始充能")
	arena.player.hp = 0.0
	arena._handle_player_death()
	if arena.skill_engine.is_toggle_on(0):
		failures.append("死亡后开关技能未关闭")
	arena.on_loadout_changed()
	arena.get_passive_combat()
	if arena.player.reincarnate_charges != 0:
		failures.append("已消耗的重生充能被换槽重算恢复")

	# DoT 致死必须走 WorldSystem 的经验、掉落、仇恨清理与死亡动画管线。
	var dot_enemy := Enemy.new()
	dot_enemy.global_position = arena.player.global_position + Vector2(96, 0)
	dot_enemy.setup(1.0, 0.0, 0.0, 1.0)
	dot_enemy.world_ref = arena.world
	arena.enemies_root.add_child(dot_enemy)
	await process_frame
	dot_enemy.apply_dot(1000.0, 1.0)
	var dot_killed := false
	for _tick in range(6):
		await physics_frame
		if not is_instance_valid(dot_enemy) or bool(dot_enemy.get_meta("kill_resolved", false)):
			dot_killed = true
			break
	if not dot_killed:
		failures.append("持续伤害致死未进入统一击杀流程（HP=%.1f）" % dot_enemy.hp)

	arena.free()
	if failures.is_empty():
		print("COMMANDSYSTEM_OK")
		quit(0)
	else:
		for failure in failures:
			printerr("COMMANDSYSTEM_ERR %s" % failure)
		quit(1)


func _make_summon(arena: Arena, position: Vector2) -> Summon:
	var summon := Summon.new()
	summon.arena = arena
	summon.owner_player = arena.player
	summon.global_position = position
	arena.summons_root.add_child(summon)
	arena.summons.append(summon)
	return summon
