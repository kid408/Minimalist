extends SceneTree

# 聚焦验证：重构后新增的 6 个原语（polymorph/dot/armor_break/pull/buff_stat/reflect）
# 能否通过 SkillEffects 正确执行并改变单位状态。直接调用静态原语函数，
# 避免依赖鼠标/选敌管线。运行：godot --headless --path . --script res://tests/_playtest_newprimitives.gd

const MainMenu = preload("res://scenes/ui/main_menu.tscn")
const GameData = preload("res://src/data/game_data.gd")
const SkillEffects = preload("res://src/systems/skill_effects.gd")

func _initialize() -> void:
	var out := FileAccess.open("d:/Godot/Minimalist/newprim_out.txt", FileAccess.WRITE)
	var menu = MainMenu.instantiate()
	root.add_child(menu)
	await process_frame
	menu._start_game()
	var arena = menu.current_arena
	await process_frame
	if arena == null or not is_instance_valid(arena):
		out.store_line("NECPRIM_FAIL: no arena"); out.close(); quit(); return

	var enemy = null
	for e in arena.enemies_root.get_children():
		if e is Enemy and not e.is_dead():
			enemy = e
			break
	if enemy == null or not is_instance_valid(enemy):
		out.store_line("NECPRIM_FAIL: no enemy"); out.close(); quit(); return

	var player = arena.player
	var base_pos: Vector2 = enemy.global_position
	var ctx_t := {
		"arena": arena, "caster": player, "dmg": 50.0,
		"from_pos": player.global_position, "effects": {}, "include_summons": true,
	}

	var p1 = GameData.get_skill("polymorph")
	SkillEffects.apply_to_target(enemy, p1.get("effects", {}), ctx_t)
	out.store_line("polymorph has_status=%s" % enemy.has_status("polymorph"))

	var p2 = GameData.get_skill("corruption")
	SkillEffects.apply_to_target(enemy, p2.get("effects", {}), ctx_t)
	out.store_line("dot remaining=%.2f dps=%.2f" % [enemy.dot_remaining, enemy.dot_dps])

	var p3 = GameData.get_skill("shatter_armor")
	SkillEffects.apply_to_target(enemy, p3.get("effects", {}), ctx_t)
	out.store_line("armor_break_mult=%.2f" % enemy.armor_break_mult)

	var p4 = GameData.get_skill("void_pull")
	SkillEffects.apply_to_target(enemy, p4.get("effects", {}), ctx_t)
	out.store_line("pull moved=%.2f" % enemy.global_position.distance_to(base_pos))

	var p5 = GameData.get_skill("battle_frenzy")
	var eff5 = p5.get("effects", {})
	SkillEffects.apply_to_caster(eff5, {"arena": arena, "caster": player, "dmg": 50.0, "effects": eff5, "include_summons": true})
	out.store_line("buff_stat damage_pct=%.2f" % player.temp_buff_mult("damage_pct"))

	var p6 = GameData.get_skill("thorns_ward")
	var eff6 = p6.get("effects", {})
	SkillEffects.apply_to_caster(eff6, {"arena": arena, "caster": player, "dmg": 50.0, "effects": eff6, "include_summons": true})
	out.store_line("reflect_ratio=%.2f" % player.reflect_ratio)

	out.store_line("NECPRIM_DONE")
	out.close()
	quit()
