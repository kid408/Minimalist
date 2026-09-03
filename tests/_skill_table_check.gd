extends SceneTree

# 技能表体检：校验 src/data/skills/*.tsv 能被正确解析
# 运行：godot --headless --path . --script res://tests/_skill_table_check.gd

const SkillLoader = preload("res://src/data/skill_loader.gd")
const SkillSchema = preload("res://src/data/skill_schema.gd")
const GameData = preload("res://src/data/game_data.gd")

func _initialize() -> void:
	var db := SkillLoader.get_all_skills()
	if db.is_empty():
		print("SKILLCHECK_FAIL: 技能表为空")
		quit(1)
		return

	var by_mode := {}
	for m in SkillSchema.CAST_MODES:
		by_mode[m] = 0
	var errors: Array = []

	for id in db.keys():
		var d: Dictionary = db[id]
		var mode := String(d.get("cast_mode", ""))
		if by_mode.has(mode):
			by_mode[mode] += 1
		var errs := SkillSchema.validate(d)
		if not errs.is_empty():
			errors.append("%s: %s" % [id, errs])
		# 主动技能必须有可执行的形态
		if mode in ["instant", "point", "unit_target", "channel"]:
			if String(d.get("shape", "")) == "":
				errors.append("%s: 缺少 shape" % id)
		if mode == "point" and float(d.get("radius", 0.0)) <= 0.0:
			errors.append("%s: point 技能 radius 必须 > 0" % id)

	print("SKILLCHECK_TOTAL %d" % db.size())
	for m in SkillSchema.CAST_MODES:
		print("SKILLCHECK_MODE %s=%d" % [m, by_mode[m]])

	if errors.is_empty():
		print("SKILLCHECK_OK")
	else:
		for e in errors:
			print("SKILLCHECK_ERR %s" % e)
		print("SKILLCHECK_FAIL")
		quit(1)

	# 校验召唤随属性成长配置表（不阻断技能校验结果，仅报告）
	GameData.reload_summon_scaling()
	var s_profiles := 0
	for id in ["serpent_ward", "skeleton_minion", "default"]:
		var entries: Array = GameData.get_summon_scaling(id)
		s_profiles += entries.size()
		print("SUMMONSCALE %s=%d" % [id, entries.size()])
	print("SUMMONSCALE_TOTAL %d" % s_profiles)
	quit(0)
