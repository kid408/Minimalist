class_name AuraSystem
extends Node

# ============================================================
# 光环 / 常驻加成系统
# ------------------------------------------------------------
# 数据来源（全部由表驱动，无硬编码技能名）：
#   1. 技能槽中 cast_mode == "aura" 的技能：effects.aura_stat / aura_value
#   2. 处于开启状态的 toggle 技能：effects.bonus_<stat>
#
# 支持的 stat：
#   damage_pct        所有技能与普攻伤害提升
#   attack_speed_pct  普攻间隔缩短
#   move_speed_pct    移动速度提升
#   lifesteal         造成伤害按比例回复生命
#   hp_regen          每秒回复固定生命
#   damage_reduce     受到伤害减免
# ============================================================

const GameData = preload("res://src/data/game_data.gd")

const STATS := ["damage_pct", "attack_speed_pct", "move_speed_pct",
	"lifesteal", "hp_regen", "damage_reduce", "mana_regen"]

var arena: Arena
var bonuses: Dictionary = {}
var slow_aura_pct := 0.0  # 减速光环：范围内敌人减速比例
var _dirty := true
var _recheck := 0.0

func _ready() -> void:
	_reset()
	set_process(true)

func _reset() -> void:
	bonuses = {}
	for s in STATS:
		bonuses[s] = 0.0
	slow_aura_pct = 0.0

func mark_dirty() -> void:
	_dirty = true

func get_bonus(stat: String) -> float:
	return float(bonuses.get(stat, 0.0))

func recompute() -> void:
	_reset()
	if arena == null:
		return
	# 1) 技能槽中的光环
	for i in range(arena.skill_slots.size()):
		var item: Dictionary = arena.skill_slots[i]
		if typeof(item) != TYPE_DICTIONARY or String(item.get("id", "")).is_empty():
			continue
		if String(item.get("cast_mode", "")) != "aura":
			continue
		var effects: Dictionary = item.get("effects", {})
		var stat := String(effects.get("aura_stat", ""))
		if stat == "":
			continue
		if stat == "slow":
			var sv := float(effects.get("aura_value", 0.0)) * GameData.get_quality_multiplier(String(item.get("quality", "white")))
			slow_aura_pct = maxf(slow_aura_pct, sv)
			continue
		if not bonuses.has(stat):
			continue
		var val := float(effects.get("aura_value", 0.0))
		val *= GameData.get_quality_multiplier(String(item.get("quality", "white")))
		bonuses[stat] = float(bonuses[stat]) + val
		# 增益槽注入：光环也能被融合增强
		if i < arena.augment_slots.size():
			for a in arena.augment_slots[i]:
				if typeof(a) != TYPE_DICTIONARY or String(a.get("id", "")).is_empty():
					continue
				var aeff: Dictionary = GameData.get_augment(String(a.get("id", ""))).get("effects", {})
				if aeff.has("aura_value"):
					bonuses[stat] = float(bonuses[stat]) + float(aeff["aura_value"]) * 0.5

	# 2) 开启中的 toggle 技能
	if arena.skill_engine != null:
		for index in arena.skill_engine.actives.keys():
			var def: Dictionary = arena.skill_engine.actives[index]["def"]
			var fx: Dictionary = def.get("effects", {})
			for stat2 in STATS:
				var key: String = "bonus_" + String(stat2)
				if fx.has(key):
					bonuses[stat2] = float(bonuses[stat2]) + float(fx[key])
	# 3) 伤害减免同步到玩家（player.take_damage 统一读取）
	if arena.player != null and is_instance_valid(arena.player):
		arena.player.damage_reduce = clampf(float(bonuses["damage_reduce"]), 0.0, 0.9)
	_dirty = false

func _process(delta: float) -> void:
	if arena == null or arena.player == null or not is_instance_valid(arena.player):
		return
	_recheck += delta
	if _dirty or _recheck >= 0.5:
		_recheck = 0.0
		recompute()
	var regen := get_bonus("hp_regen")
	if regen > 0.0:
		arena.player.heal(regen * delta)
	var mr := get_bonus("mana_regen")
	if mr > 0.0:
		arena.player.add_energy(mr * delta)
	if slow_aura_pct > 0.0 and arena.enemies_root != null:
		for e in arena.enemies_root.get_children():
			if e is Enemy and not (e as Enemy).is_dead():
				if (e as Enemy).global_position.distance_to(arena.player.global_position) <= 220.0:
					(e as Enemy).apply_slow(slow_aura_pct, 0.5)

# 造成伤害后的吸血回调（由 CombatSystem 统一调用）
func on_damage_dealt(amount: float) -> void:
	var ls := get_bonus("lifesteal")
	if ls <= 0.0 or amount <= 0.0:
		return
	if arena.player != null and is_instance_valid(arena.player):
		arena.player.heal(amount * ls)
