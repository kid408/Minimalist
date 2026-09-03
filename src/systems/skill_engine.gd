class_name SkillEngine
extends Node2D

# ============================================================
# 通用技能施放引擎（数据驱动）
# ------------------------------------------------------------
# 六大施法方式由 skill_def.cast_mode 决定「怎么放」：
#   instant     瞬发   —— 松开即结算
#   point       点地   —— 在鼠标落点结算
#   unit_target 单体   —— 进入选取态，点击单位后结算
#   channel     引导   —— 站桩持续结算，移动/再次按键打断
#   aura        光环   —— 装备即常驻（由 AuraSystem 处理，不可主动释放）
#   toggle      开关   —— 切换开/关，开启期间每秒耗能
#
# shape 决定「打哪里」：self_ring / circle / line / projectile / target / summon / none
# 具体伤害与效果原语仍复用 CombatSystem 中的 _skill_* 实现。
#
# 新增技能 = 在 src/data/skills/*.tsv 加一行，无需改本文件。
# ============================================================

const GameData = preload("res://src/data/game_data.gd")
const SkillEffects = preload("res://src/systems/skill_effects.gd")
const SkillChannel = preload("res://src/systems/skill_channel.gd")

var arena: Arena
var combat: Node   # CombatSystem

# ---- 单体目标选取态 ----
var targeting_index: int = -1
var targeting_def: Dictionary = {}

# ---- 引导态（逻辑在 SkillChannel 状态机中）----
var channel_index: int = -1
var channel := SkillChannel.new()

# ---- 开关态：index -> {def, dmg, timer} ----
var actives: Dictionary = {}

func _ready() -> void:
	set_process(true)

# ============================================================
# 入口：由 CombatSystem._cast_skill 转发
# ============================================================
func request_cast(index: int) -> void:
	if arena == null or index < 0 or index >= arena.skill_slots.size():
		return
	var host: Dictionary = arena.skill_slots[index]
	if String(host.get("id", "")).is_empty():
		return

	var mode := String(host.get("cast_mode", "instant"))

	# 引导中：任何技能键先打断当前引导
	if channel_index >= 0:
		var same_key := (channel_index == index)
		interrupt_channel("引导被打断")
		if same_key:
			return

	match mode:
		"aura":
			arena.hud.set_message("【%s】是光环，装备即生效。" % host.get("name", "技能"))
			return
		"toggle":
			_toggle(index, host)
			return
		"unit_target":
			_enter_targeting(index, host)
			return

	if arena.cooldowns.get(arena.skill_actions[index], 0.0) > 0.0:
		arena.hud.set_message("【%s】冷却中 %.2f秒" % [host.get("name", "技能"), arena.cooldowns[arena.skill_actions[index]]])
		return

	var prep := _prepare(index)
	if prep.is_empty():
		return

	if mode == "channel":
		_start_channel(index, prep)
	else:
		_execute(prep["resolved"], prep["damage"], get_global_mouse_position(), null)

# ============================================================
# 通用前置：冷却 / 能量 / 融合 / 品质 / 装备加成
# 返回 {resolved, damage}；失败返回 {}
# ============================================================
func _prepare(index: int) -> Dictionary:
	var host: Dictionary = arena.skill_slots[index]
	var cost := float(host.get("energy_cost", 20))
	if cost > 0.0 and not arena.player.consume_energy(cost):
		arena.hud.set_message("能量不足！")
		return {}

	var augments: Array = []
	if index < arena.augment_slots.size():
		augments = arena.augment_slots[index]
	var resolved: Dictionary = combat._merge_fused_unit(host, augments)
	if resolved.is_empty():
		return {}

	var effects: Dictionary = resolved.get("effects", {})
	var cd := float(host.get("cooldown", 5.0))
	cd *= arena._apply_synergy_to_cd(resolved)
	arena.cooldowns[arena.skill_actions[index]] = cd

	var dmg := float(resolved.get("damage", 30))

	# 法力爆破：消耗全部能量（由 effects 驱动）
	if bool(effects.get("consume_all_energy", false)):
		dmg = arena.player.energy * float(effects.get("energy_dmg_ratio", 1.0))
		arena.player.energy = 0

	# 装备：毁灭者印记（对范围类加成）
	if arena._has_equip("destroyer_mark") and String(resolved.get("subtype", "")) in ["aoe_self", "aoe_ground", "ground"]:
		dmg *= 1.3

	dmg *= GameData.get_quality_multiplier(String(host.get("quality", "white")))
	dmg *= 1.0 + _bonus("damage_pct")

	# 融合提示（让组合被看见）
	var tag := "融合【%s】" % host.get("name", "技能")
	for a in augments:
		if a != null and typeof(a) == TYPE_DICTIONARY and not String(a.get("id", "")).is_empty():
			tag += " +【%s】" % a.get("name", "增益")
	arena.hud.set_message(tag + "！")

	return {"resolved": resolved, "damage": dmg}

# ============================================================
# 形态分发：把「一次结算」交给对应的效果原语
# ============================================================
func _execute(resolved: Dictionary, dmg: float, point: Vector2, unit: Node) -> void:
	var shape := String(resolved.get("shape", "none"))
	var side := String(resolved.get("target_side", "enemy"))
	match shape:
		"self_ring", "cone":
			if side == "ally":
				combat._skill_heal(arena.player.global_position, dmg, resolved)
			else:
				combat._skill_aoe_self(dmg, resolved)
		"circle":
			combat._skill_aoe_ground(point, dmg, resolved)
		"line":
			combat._skill_dash(point, dmg, resolved)
		"projectile":
			combat._skill_projectile(point, dmg, resolved)
		"summon":
			combat._skill_summon(dmg, resolved)
		"target":
			combat._skill_unit_target(unit, dmg, resolved)
		_:
			combat._skill_buff(point, dmg, resolved)
	# 施法者侧增益（治疗/护盾/属性增益/反伤）统一交给 SkillEffects 执行
	if String(resolved.get("cast_mode", "instant")) != "unit_target":
		var ctx := {
			"arena": arena, "caster": arena.player, "dmg": dmg,
			"from_pos": point, "effects": resolved.get("effects", {}), "include_summons": true,
		}
		SkillEffects.apply_to_caster(resolved.get("effects", {}), ctx)

# ============================================================
# 单体目标（Unit Target）
# ============================================================
func _enter_targeting(index: int, host: Dictionary) -> void:
	if arena.cooldowns.get(arena.skill_actions[index], 0.0) > 0.0:
		arena.hud.set_message("【%s】冷却中 %.2f秒" % [host.get("name", "技能"), arena.cooldowns[arena.skill_actions[index]]])
		return
	targeting_index = index
	targeting_def = host
	var side := String(host.get("target_side", "enemy"))
	var who := "友军单位" if side == "ally" else "敌方单位"
	arena.hud.set_message("【%s】请点击一个%s（右键取消）" % [host.get("name", "技能"), who])

func is_targeting() -> bool:
	return targeting_index >= 0

func cancel_targeting(msg := "已取消选取") -> void:
	if targeting_index < 0:
		return
	targeting_index = -1
	targeting_def = {}
	if msg != "":
		arena.hud.set_message(msg)

# 由 arena 左键松开时调用；返回 true 表示本次点击被技能消耗
func try_pick_target(world_pos: Vector2) -> bool:
	if targeting_index < 0:
		return true
	var index := targeting_index
	var side := String(targeting_def.get("target_side", "enemy"))
	var target: Node = null
	if side == "ally":
		target = _ally_at(world_pos)
	else:
		target = combat._enemy_at(world_pos)
	if target == null:
		arena.hud.set_message("目标无效，请点击一个%s。" % ("友军单位" if side == "ally" else "敌方单位"))
		return true

	var max_range := float(targeting_def.get("range", 600.0))
	if max_range > 0.0 and arena.player.global_position.distance_to(target.global_position) > max_range:
		arena.hud.set_message("目标超出施法距离。")
		return true

	targeting_index = -1
	targeting_def = {}
	var prep := _prepare(index)
	if prep.is_empty():
		return true
	_execute(prep["resolved"], prep["damage"], target.global_position, target)
	return true

func _ally_at(world_pos: Vector2) -> Node:
	var s: Node = combat._summon_at(world_pos)
	if s != null:
		return s
	if arena.player != null and is_instance_valid(arena.player):
		if arena.player.global_position.distance_to(world_pos) <= 48.0:
			return arena.player
	return null

# ============================================================
# 引导（Channel）
# ============================================================
func _start_channel(index: int, prep: Dictionary) -> void:
	channel_index = index
	channel.on_interrupt = _on_channel_interrupt
	channel.start(prep["resolved"], prep["damage"], get_global_mouse_position(),
		arena.player.global_position, _on_channel_pulse)
	arena._player_moving = false
	arena.hud.set_message("引导中【%s】…（移动会打断）" % prep["resolved"].get("name", "技能"))

func _on_channel_pulse(def: Dictionary, dmg: float, point: Vector2, unit: Node) -> void:
	_execute(def, dmg, point, unit)

func _on_channel_interrupt(msg: String) -> void:
	if msg != "":
		arena.hud.set_message(msg)

func is_channeling() -> bool:
	return channel.is_active()

func interrupt_channel(msg := "") -> void:
	channel_index = -1
	channel.interrupt(msg)

func _process_channel(delta: float) -> void:
	if arena.player == null or not is_instance_valid(arena.player):
		interrupt_channel()
		return
	channel.update(delta, arena.player.global_position)

# ============================================================
# 开关（Toggle）
# ============================================================
func _toggle(index: int, host: Dictionary) -> void:
	if actives.has(index):
		actives.erase(index)
		arena.hud.set_message("【%s】关闭。" % host.get("name", "技能"))
		_notify_aura()
		return
	if arena.cooldowns.get(arena.skill_actions[index], 0.0) > 0.0:
		return
	var augments: Array = []
	if index < arena.augment_slots.size():
		augments = arena.augment_slots[index]
	var resolved: Dictionary = combat._merge_fused_unit(host, augments)
	if resolved.is_empty():
		return
	var dmg := float(resolved.get("damage", 0.0)) * GameData.get_quality_multiplier(String(host.get("quality", "white")))
	actives[index] = {"def": resolved, "damage": dmg, "timer": 0.0}
	arena.cooldowns[arena.skill_actions[index]] = float(host.get("cooldown", 2.0))
	arena.hud.set_message("【%s】开启！" % host.get("name", "技能"))
	_notify_aura()

func is_toggle_on(index: int) -> bool:
	return actives.has(index)

func _process_toggles(delta: float) -> void:
	if actives.is_empty():
		return
	var to_close: Array = []
	for index in actives.keys():
		var st: Dictionary = actives[index]
		var def: Dictionary = st["def"]
		# 槽位已被换掉/丢弃时自动关闭
		if index >= arena.skill_slots.size() or String(arena.skill_slots[index].get("id", "")) != String(def.get("id", "")):
			to_close.append(index)
			continue
		var effects: Dictionary = def.get("effects", {})
		var cps := float(effects.get("toggle_cost", 5.0))
		if cps > 0.0:
			if arena.player.energy < cps * delta:
				to_close.append(index)
				continue
			arena.player.energy = maxf(0.0, arena.player.energy - cps * delta)
		# 周期性伤害脉冲（shape 非 none 时才有意义）
		if String(def.get("shape", "none")) != "none" and float(st["damage"]) > 0.0:
			st["timer"] = float(st["timer"]) + delta
			var interval := maxf(0.1, float(def.get("tick_interval", 0.5)))
			while float(st["timer"]) >= interval:
				st["timer"] = float(st["timer"]) - interval
				_execute(def, float(st["damage"]), arena.player.global_position, null)
	for index in to_close:
		var nm := String(actives[index]["def"].get("name", "技能"))
		actives.erase(index)
		arena.hud.set_message("能量耗尽，【%s】关闭。" % nm)
		_notify_aura()

# 槽位变更时（换技能/丢技能）清理失效的开关与选取态
func on_slots_changed() -> void:
	var to_close: Array = []
	for index in actives.keys():
		if index >= arena.skill_slots.size():
			to_close.append(index)
			continue
		var cur := String(arena.skill_slots[index].get("id", ""))
		if cur != String(actives[index]["def"].get("id", "")):
			to_close.append(index)
	for index in to_close:
		actives.erase(index)
	if targeting_index >= 0:
		cancel_targeting("")
	if channel_index >= 0:
		interrupt_channel()
	arena.mark_passives_dirty()
	_notify_aura()

func _notify_aura() -> void:
	if arena != null and arena.aura != null:
		arena.aura.mark_dirty()

func _bonus(stat: String) -> float:
	if arena == null or arena.aura == null:
		return 0.0
	return arena.aura.get_bonus(stat)

func _process(delta: float) -> void:
	if arena == null or arena.player == null or not is_instance_valid(arena.player):
		return
	_process_channel(delta)
	_process_toggles(delta)
