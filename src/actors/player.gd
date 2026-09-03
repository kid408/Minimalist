extends CharacterBody2D
class_name Player

const GameData = preload("res://src/data/game_data.gd")
const MAX_ENERGY := 100.0
const ENERGY_REGEN_BASE := 5.0

func _ready() -> void:
	var hero_tex := load("res://assets/players/Player_1.png") as Texture2D
	if hero_tex:
		var sprite := Sprite2D.new()
		sprite.name = "BodySprite"
		sprite.texture = hero_tex
		sprite.scale = Vector2(0.5, 0.5)
		add_child(sprite)

var hp: float = 140.0
var max_hp: float = 140.0
var energy: float = 100.0
var base_energy_max: float = MAX_ENERGY

# 护盾（吸收伤害，限时）
var shield: float = 0.0
var reincarnate_charges: int = 0  # 重生被动剩余次数（由 arena._recompute_passives 注入）
var shield_timer: float = 0.0
# 临时增益（来自技能 effects.buff_stat）
var temp_buffs: Dictionary = {}        # stat -> {"mult": float, "remaining": float}
# 反伤（来自技能 effects.reflect）
var reflect_ratio: float = 0.0
var reflect_remaining: float = 0.0
var reflect_school: String = "physical"
# 光环伤害减免（由 AuraSystem 同步，0.0~0.9，take_damage 统一读取）
var damage_reduce: float = 0.0
# 过载核心：连杀计数 / 回能翻倍剩余时间
var kill_streak: int = 0
var overload_remaining: float = 0.0
var base_move_speed: float = 300.0
var base_attack_damage: float = 24.0
var base_attack_interval: float = 0.46
var base_attack_range: float = 72.0

# 等级 / 经验 / 技能点
var xp: float = 0.0
var level: int = 1
var xp_to_next: float = 10.0
var skill_points: int = 6  # 初始 6 点（设计文档 L1）

# 击杀获得经验，返回是否升级（升级 +1 技能点）
func gain_xp(amount: float) -> bool:
	var leveled := false
	xp += amount
	while xp >= xp_to_next:
		xp -= xp_to_next
		level += 1
		skill_points += 1
		xp_to_next = 10.0 + level * 8.0
		leveled = true
	return leveled

# 五大基础属性
var base_stats := {"str": 5, "agi": 5, "int": 5, "vit": 10, "luk": 0}

# 玩家自由分配的加点（消耗 skill_points）
var allocated_stats := {"str": 0, "agi": 0, "int": 0, "vit": 0, "luk": 0}

# 装备加成后的总值（含自由加点）
func total_str() -> int: return base_stats.str + _equipment_bonus("str") + allocated_stats.str
func total_agi() -> int: return base_stats.agi + _equipment_bonus("agi") + allocated_stats.agi
func total_int() -> int: return base_stats.int + _equipment_bonus("int") + allocated_stats.int
func total_vit() -> int: return base_stats.vit + _equipment_bonus("vit") + allocated_stats.vit
func total_luk() -> int: return base_stats.luk + _equipment_bonus("luk") + allocated_stats.luk

# 按属性名取总值（供召唤随属性成长等外部系统读取）
func total_stat(stat: String) -> int:
	match stat:
		"str": return total_str()
		"agi": return total_agi()
		"int": return total_int()
		"vit": return total_vit()
		"luk": return total_luk()
		_: return 0

# 消耗 1 技能点分配 1 点属性；成功返回 true
func allocate_stat(stat: String) -> bool:
	if skill_points <= 0 or not allocated_stats.has(stat):
		return false
	allocated_stats[stat] += 1
	skill_points -= 1
	if stat == "vit":
		refresh_max_hp()
	return true

# 重置所有自由加点并返还技能点
func reset_allocated() -> int:
	var back := 0
	for k in allocated_stats.keys():
		back += allocated_stats[k]
		allocated_stats[k] = 0
	skill_points += back
	if back > 0:
		refresh_max_hp()
	return back

# 衍生属性
func melee_damage_mult() -> float: return 1.0 + total_str() * 0.03
func ranged_damage_mult() -> float: return 1.0 + total_int() * 0.03
func attack_speed_mult() -> float: return (1.0 + total_agi() * 0.03) * temp_buff_mult("attack_speed_pct")
func move_speed_mult() -> float: return (1.0 + total_agi() * 0.02) * temp_buff_mult("move_speed_pct")
func energy_regen_rate() -> float:
	var base := ENERGY_REGEN_BASE + total_int() * 0.5
	if has_equip("focus_pendant"): base *= 1.8
	if overload_remaining > 0.0: base *= 2.0   # 过载核心：回能翻倍
	return base

func refresh_max_energy() -> void:
	base_energy_max = MAX_ENERGY * 0.7 if has_equip("focus_pendant") else MAX_ENERGY
	energy = minf(energy, base_energy_max)

func drop_quality_bias() -> float:
	var bias := total_luk() * 0.02
	if has_equip("power_badge"): bias *= 2.0            # 赌徒脚链 ×2
	return bias

func max_hp_calc() -> float:
	var hp_val := 100.0 + total_vit() * 8.0
	if has_equip("power_badge"): hp_val *= 0.75         # 赌徒脚链 -25%
	return hp_val

var equipment_slots: Array = []  # 6格，Dictionary或{}
var _equipment_cache_valid := false
var _cached_equipment_bonuses := {}

func set_equipment(index: int, item: Dictionary) -> void:
	if index < 0 or index >= 6:
		return
	while equipment_slots.size() < 6:
		equipment_slots.append({})
	equipment_slots[index] = item.duplicate(true)
	_invalidate_equipment_cache()

func remove_equipment(index: int) -> Dictionary:
	if index < 0 or index >= equipment_slots.size():
		return {}
	var removed: Variant = equipment_slots[index]
	equipment_slots[index] = {}
	_invalidate_equipment_cache()
	return removed as Dictionary

func _equipment_bonus(stat_name: String) -> int:
	_refresh_equipment_cache()
	return _cached_equipment_bonuses.get(stat_name, 0)

func _invalidate_equipment_cache() -> void:
	_equipment_cache_valid = false

func _refresh_equipment_cache() -> void:
	if _equipment_cache_valid:
		return
	_cached_equipment_bonuses = {"str": 0, "agi": 0, "int": 0, "vit": 0, "luk": 0}
	for item in equipment_slots:
		var bonuses: Dictionary = item.get("stat_bonuses", {})
		for key in _cached_equipment_bonuses:
			_cached_equipment_bonuses[key] += int(bonuses.get(key, 0))
	_equipment_cache_valid = true

func get_equipment_ids() -> Array:
	var ids: Array = []
	for item in equipment_slots:
		var equip_id := String(item.get("id", ""))
		if not equip_id.is_empty():
			ids.append(equip_id)
	return ids

func init_from_hero(hero_data: Dictionary) -> void:
	base_stats = GameData.get_base_stats()
	hp = hero_data.get("base_hp", 140.0)
	max_hp = hp
	energy = MAX_ENERGY
	base_move_speed = hero_data.get("move_speed", 290.0)
	base_attack_damage = hero_data.get("attack_damage", 24.0)
	base_attack_interval = hero_data.get("attack_interval", 0.46)
	base_attack_range = hero_data.get("attack_range", 72.0)

func refresh_max_hp() -> void:
	var new_max := max_hp_calc()
	var ratio := hp / maxf(max_hp, 1.0)
	max_hp = new_max
	hp = clampf(ratio * max_hp, 1.0, max_hp)

func has_equip(id: String) -> bool:
	for item in equipment_slots:
		if String(item.get("id", "")) == id:
			return true
	return false

func take_damage(amount: float, knockback_dir: Vector2 = Vector2.ZERO, kb_strength: float = 0.0, attacker: Node = null) -> void:
	# 光环伤害减免（硬化光环 / 法力护盾 toggle 等，上限 90%）
	amount *= 1.0 - clampf(damage_reduce, 0.0, 0.9)
	# 护盾吸收
	if shield > 0.0:
		var absorbed := minf(shield, amount)
		shield -= absorbed
		amount -= absorbed
	if amount <= 0.0:
		return
	# 魔法盾护符：能量>50%时伤害从能量抵扣
	if has_equip("iron_guard") and energy > base_energy_max * 0.5:
		var energy_deduct: float = minf(amount, energy)
		energy -= energy_deduct
		amount -= energy_deduct
	if amount > 0:
		hp = maxf(hp - amount, 0.0)
	# 反伤：将部分伤害反弹给攻击者（技能 effects.reflect）
	if reflect_remaining > 0.0 and attacker != null and is_instance_valid(attacker) and attacker.has_method("take_damage"):
		attacker.take_damage(amount * reflect_ratio, Vector2.ZERO, 0.0)

func try_reflect_damage(dmg_amount: float) -> float:
	# 荆棘甲
	for item in equipment_slots:
		if String(item.get("id", "")) == "thorn_mail" and randf() < 0.4:
			return dmg_amount * 0.5
	return 0.0

func heal(amount: float) -> void:
	hp = minf(hp + amount, max_hp)

func add_energy(amount: float) -> void:
	energy = minf(energy + amount, base_energy_max)

func consume_energy(amount: float) -> bool:
	if energy < amount:
		return false
	energy -= amount
	return true

func is_alive() -> bool:
	return hp > 0.0

func add_shield(amount: float, dur: float) -> void:
	shield = maxf(shield, amount)
	shield_timer = maxf(shield_timer, dur)

# 临时属性增益（技能 effects.buff_stat）：限时取最强倍率
func add_temp_buff(stat: String, mult: float, dur: float) -> void:
	if dur <= 0.0:
		return
	var cur: Dictionary = temp_buffs.get(stat, {"mult": 1.0, "remaining": 0.0})
	cur["mult"] = maxf(cur.get("mult", 1.0), mult)
	cur["remaining"] = maxf(cur.get("remaining", 0.0), dur)
	temp_buffs[stat] = cur

func temp_buff_mult(stat: String) -> float:
	var b: Dictionary = temp_buffs.get(stat, {})
	if not b.is_empty() and b.get("remaining", 0.0) > 0.0:
		return float(b.get("mult", 1.0))
	return 1.0

# 反伤（技能 effects.reflect）：限时取最强比例
func add_reflect(ratio: float, dur: float, school: String = "physical") -> void:
	if dur <= 0.0:
		return
	reflect_ratio = maxf(reflect_ratio, ratio)
	reflect_remaining = maxf(reflect_remaining, dur)
	reflect_school = school

func _physics_process(delta: float) -> void:
	# 过载核心计时
	if overload_remaining > 0.0:
		overload_remaining = maxf(overload_remaining - delta, 0.0)
	if shield_timer > 0.0:
		shield_timer -= delta
		if shield_timer <= 0.0:
			shield = 0.0
	# 反伤计时
	if reflect_remaining > 0.0:
		reflect_remaining -= delta
		if reflect_remaining <= 0.0:
			reflect_ratio = 0.0
	# 临时增益计时
	for key in temp_buffs.keys():
		temp_buffs[key]["remaining"] -= delta
		if temp_buffs[key]["remaining"] <= 0.0:
			temp_buffs.erase(key)
