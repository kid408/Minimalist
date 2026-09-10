extends SceneTree

# 扩展版 headless 自动 playtest：
# 进入战斗后预装各 subtype 主动技能 + 被动，模拟移动/施放/鼠标/交互，
# 并直接驱动商人交易、祭坛、拾取、拖拽等路径，覆盖输入相关逻辑。
# 用法：godot --headless --path <项目> --script res://tests/_playtest.gd

const MainMenu = preload("res://scenes/ui/main_menu.tscn")
const GameData = preload("res://src/data/game_data.gd")
const SkillDrop = preload("res://src/systems/skill_drop.gd")

var _merchant_done := false
var _idol_done := false
var _pickup_done := false
var _drag_done := false
var _attr_done := false


func _initialize() -> void:
	_setup_input()
	var game_root := Node.new()
	game_root.name = "GameRoot"
	root.add_child(game_root)
	current_scene = game_root

	var menu = MainMenu.instantiate()
	game_root.add_child(menu)
	await process_frame
	menu._start_game()
	var arena = menu.current_arena
	await process_frame
	if arena == null or not is_instance_valid(arena):
		printerr("PLAYTEST_FAIL: arena not created")
		quit()
		return

	_equip_coverage_skills(arena)
	arena._spawn_merchant()
	await process_frame
	var boss_path: PackedVector2Array = arena.world_layout.find_path(arena.player.global_position, arena.MAP_CENTER)
	var enemy_count_before: int = arena.enemies_root.get_child_count()
	var respawn_pos: Vector2 = arena.world_layout.project_to_walkable(arena.player.global_position + Vector2(620, 0))
	arena.dead_queue.append({
		"type": Enemy.EnemyType.NORMAL,
		"behavior": Enemy.Behavior.MELEE,
		"pos": respawn_pos,
		"time": arena.elapsed_time - arena.RESPAWN_DELAY - 0.1,
	})
	arena._process_respawns(0.0)
	var respawn_ok: bool = arena.enemies_root.get_child_count() == enemy_count_before + 1
	printerr("PLAYTEST_INFO: world layout path nodes=", boss_path.size(), " camps=", arena.world_layout.get_elite_camps().size(), " respawn=", respawn_ok)
	printerr("PLAYTEST_INFO: skills equipped, starting drive loop")

	# 低频驱动：覆盖技能和输入路径，避免每帧生成大批临时效果拖慢测试。
	var max_frames := 300
	var frames := 0

	while frames < max_frames and is_instance_valid(arena):
		frames += 1
		# 玩家设为无敌，避免死亡触发场景重载打断测试
		arena.player.hp = 100000.0

		# 鼠标右键移动订单（替代已删除的 WASD 直控）。
		if frames % 45 == 1:
			var move_target: Vector2 = arena.world_layout.project_to_walkable(arena.player.global_position + Vector2(160, 80))
			arena._handle_right_click(move_target)

		# 直接施放每个主动技能（清冷却 + 保证能量）
		if frames % 60 == 1:
			arena.player.energy = 1000.0
			for i in range(arena.skill_slots.size()):
				var s = arena.skill_slots[i]
				if typeof(s) == TYPE_DICTIONARY and not String(s.get("id", "")).is_empty() and String(s.get("cast_type", "")) == "active":
					arena.cooldowns[arena.skill_actions[i]] = 0.0
					arena._cast_skill(i)

		# 触发输入分发路径（按键施放）
		if frames % 90 == 1:
			for a in arena.skill_actions:
				Input.action_press(a)

		# 鼠标事件：右键下令 / 左键框选
		if frames % 90 == 1:
			_emit_mouse_motion()
			_emit_mouse(MOUSE_BUTTON_RIGHT, true)
			_emit_mouse(MOUSE_BUTTON_LEFT, true)

		# 商人、祭坛和拾取由下方里程碑直接驱动，避免自动交互在暂停窗口上重复触发。

		# 覆盖里程碑（条件触发，避免依赖固定帧数）
		if not _merchant_done and arena.merchants.size() > 0:
			_merchant_done = true
			var m = arena.merchants[0]
			arena.player.global_position = m.global_position
			arena.gold = 9999
			arena._open_merchant_trade(m)
			arena._do_upgrade(m, 0)
			arena._do_delete(m, 0)
			arena._merchant_buy(m, 0)
			var merchant_modal: bool = arena.hud.has_modal()
			var merchant_closed := false
			while arena.hud.dismiss_top_transient():
				merchant_closed = true
			printerr("PLAYTEST_INFO: merchant covered modal=", merchant_modal, " closed=", merchant_closed, " paused=", paused)
		if not _idol_done and arena.idols.size() > 0:
			_idol_done = true
			var idl = arena.idols[0]
			arena.player.global_position = idl.global_position
			arena.hud.show_idol_popup(idl.get_cost_description(), func(): pass, func(): pass)
			var idol_modal: bool = arena.hud.has_modal()
			var idol_closed: bool = arena.hud.dismiss_top_transient()
			arena._accept_idol(idl)
			printerr("PLAYTEST_INFO: idol covered modal=", idol_modal, " closed=", idol_closed, " paused=", paused)
		if not _pickup_done:
			_pickup_done = true
			var item = GameData.get_skill(GameData.get_random_skill_id([]))
			var drop = SkillDrop.new(item)
			drop.position = arena.player.global_position
			arena.drops_root.add_child(drop)
			arena._try_pickup()
			printerr("PLAYTEST_INFO: pickup covered")
		if not _drag_done:
			_drag_done = true
			arena._handle_drag("warehouse", 0, "skill", 0)
			arena._on_equipment_clicked("equipment", 0)
			printerr("PLAYTEST_INFO: drag covered")
			# 增益槽覆盖：装入 → 卸下 → 再装入 → 重复装拦截 → 拾取升级
			var free_id := ""
			for sid in GameData.get_skill_id_list():
				if not arena._skill_id_exists(sid):
					free_id = sid
					break
			if free_id != "":
				arena.warehouse_slots[1] = GameData.get_skill(free_id)
				arena._handle_drag("warehouse", 1, "aug0", 1)   # 仓库→键1增益0
				arena._handle_drag("aug0", 1, "warehouse", 1)   # 卸回仓库
				arena._handle_drag("warehouse", 1, "aug1", 1)   # 仓库→键1增益1
				arena.warehouse_slots[1] = GameData.get_skill(free_id)
				arena._handle_drag("warehouse", 1, "aug0", 2)   # 重复装 → 应被拦截
				arena.warehouse_slots[1] = {}
				var drop2 = SkillDrop.new(GameData.get_skill(free_id))
				drop2.position = arena.player.global_position
				arena.drops_root.add_child(drop2)
				arena._try_pickup()                             # 已在增益槽 → 自动升级
			printerr("PLAYTEST_INFO: augment covered id=", free_id,
				" lv=", arena._slot_ref("aug1", 1).get("level", 1))

			# 属性分配覆盖：分配全部点数 → 越界拦截 → 面板开关 → 重置
		if not _attr_done:
			_attr_done = true
			var sp0: int = arena.player.skill_points
			var str0: int = arena.player.total_str()
			var ok1: bool = arena.allocate_stat("str")
			var ok2: bool = arena.allocate_stat("vit")
			var ok3: bool = arena.allocate_stat("agi")
			var ok4: bool = arena.allocate_stat("int")
			var ok5: bool = arena.allocate_stat("luk")
			var ok6: bool = arena.allocate_stat("str")   # 第 6 点
			var sp1: int = arena.player.skill_points
			var str1: int = arena.player.total_str()
			var over: bool = arena.allocate_stat("str")  # 点数耗尽 → 应拦截
			arena.hud.toggle_attribute_panel()
			var panel_visible: bool = arena.hud.attr_panel.visible
			arena.hud.toggle_attribute_panel()
			var back: int = arena.player.reset_allocated()
			printerr("PLAYTEST_INFO: attr covered sp0=", sp0, " ok=", ok1 and ok2 and ok3 and ok4 and ok5 and ok6,
				" sp1=", sp1, " str+", str1 - str0, " over_blocked=", not over,
				" panel_toggle=", panel_visible, " reset_back=", back, " final_sp=", arena.player.skill_points)

		await process_frame

		# 释放本帧技能与鼠标输入。
		for a in arena.skill_actions:
			Input.action_release(a)
		_emit_mouse(MOUSE_BUTTON_RIGHT, false)
		_emit_mouse(MOUSE_BUTTON_LEFT, false)

	printerr("PLAYTEST_DONE frames=", frames)
	if is_instance_valid(arena):
		arena.free()
	quit()


func _equip_coverage_skills(arena) -> void:
	var list := GameData.get_skill_id_list()
	var by_sub := {}
	for sid in list:
		var s := GameData.get_skill(sid)
		if String(s.get("cast_type", "")) != "active":
			continue
		var st := String(s.get("subtype", ""))
		if not by_sub.has(st):
			by_sub[st] = sid
	var plan := ["aoe_self", "aoe_ground", "projectile", "summon", "heal", "buff"]
	for i in range(min(plan.size(), arena.skill_slots.size())):
		var st: String = plan[i]
		if by_sub.has(st):
			arena.skill_slots[i] = GameData.get_skill(by_sub[st])
	# 融合演示：键0(霜冻新星) 叠加 震荡爆(击退) + 睡眠(弱化)
	if arena.augment_slots.size() >= 1:
		arena.augment_slots[0] = [GameData.get_skill("shock_burst"), GameData.get_skill("sleep")]


func _emit_mouse(button: int, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = pressed
	ev.position = Vector2(400, 300)
	Input.parse_input_event(ev)


func _emit_mouse_motion() -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = Vector2(400, 300)
	Input.parse_input_event(ev)


func _setup_input() -> void:
	for a in ["skill_1", "skill_2", "skill_3", "skill_4", "skill_5", "skill_6",
			"interact", "pickup", "summon_spawn", "attributes", "select_hero", "select_all_summons",
			"order_stop", "order_hold", "order_attack_move", "order_follow"]:
		if not InputMap.has_action(a):
			InputMap.add_action(a)
