extends RefCounted
class_name GameData

const SkillLoader = preload("res://src/data/skill_loader.gd")

const ACTIVE_SLOT_COUNT := 6
const EQUIPMENT_SLOT_COUNT := 6
const WAREHOUSE_SLOT_COUNT := 6

# ============================================================
# 0. 视觉模型调参
# ------------------------------------------------------------
# 修改 MODEL_SCALE_MULTIPLIER 可统一放大/缩小所有单位模型；各档基础值保留识别层级。
const MODEL_SCALE_MULTIPLIER := 1.0
const PLAYER_MODEL_SCALE := 0.36
const PLAYER_BOUNCE_SCALE := 0.015
const ENEMY_NORMAL_MODEL_SCALE := 0.38
const ENEMY_ELITE_MODEL_SCALE := 0.42
const ENEMY_BOSS_MODEL_SCALE := 0.52

static func get_player_visual_scale() -> Vector2:
	return Vector2.ONE * PLAYER_MODEL_SCALE * MODEL_SCALE_MULTIPLIER

static func get_player_bounce_scale() -> Vector2:
	return Vector2.ONE * PLAYER_BOUNCE_SCALE * MODEL_SCALE_MULTIPLIER

static func get_enemy_visual_scale(tier: String) -> Vector2:
	var base_scale := ENEMY_NORMAL_MODEL_SCALE
	match tier:
		"elite": base_scale = ENEMY_ELITE_MODEL_SCALE
		"boss": base_scale = ENEMY_BOSS_MODEL_SCALE
	return Vector2.ONE * base_scale * MODEL_SCALE_MULTIPLIER

# ============================================================
# 1. 英雄数据
# ============================================================
static func get_heroes() -> Array:
	return [
		{
			"id": "vanguard",
			"name": "极锋",
			"role": "近战压制",
			"base_hp": 180.0,
			"move_speed": 235.0,
			"attack_damage": 24.0,
			"attack_interval": 0.46,
			"attack_range": 72.0,
			"description": "均衡型。"
		}
	]

static func get_hero(id: String) -> Dictionary:
	for h in get_heroes():
		if h.id == id:
			return h
	return get_heroes()[0]

# 五大基础属性
static func get_base_stats() -> Dictionary:
	return {"str": 5, "agi": 5, "int": 5, "vit": 10, "luk": 0}

# ============================================================
# 2. 技能数据（已外置为配置表，不再硬编码）
# ------------------------------------------------------------
# 表位置：res://src/data/skills/*.tsv
#   skills_instant.tsv      瞬发（自身环 / 突进 / 弹体 / 召唤 / 增益）
#   skills_point.tsv        点地
#   skills_unit_target.tsv  单体目标
#   skills_channel.tsv      引导
#   skills_aura.tsv         光环 / 被动
#   skills_toggle.tsv       开关
#
# 字段规范见 src/data/skill_schema.gd，解析见 src/data/skill_loader.gd。
# 核心字段：
#   cast_mode    : instant / point / unit_target / channel / aura / toggle（六大施法方式）
#   shape        : self_ring / circle / line / cone / projectile / target / none / summon（几何形态）
#   target_side  : enemy / ally / self / both / ground
#   effects      : 通用效果字典，施放层统一解释
#   subtype / target_mode 由 schema 自动派生，仅供旧代码兼容使用。
#
# 新增技能 = 在对应表里加一行，无需改任何代码。
# ============================================================
static func get_all_skills() -> Dictionary:
	return SkillLoader.get_all_skills()

# 热重载：运行中改表后调用即可生效（调试用）
static func reload_skills() -> void:
	SkillLoader.reload()

# 返回副本，避免调用方（槽位/升级/掉落）就地修改污染全局表数据
static func get_skill(id: String) -> Dictionary:
	var s: Dictionary = get_all_skills().get(id, {})
	if s.is_empty():
		return {}
	return s.duplicate(true)

# ============================================================
# 2.6 召唤随属性成长配置表
# ------------------------------------------------------------
# 表位置：res://src/data/summon_scaling.tsv
# 列：id(召唤技能 id 或 default) / stat(str|agi|int|vit|luk) /
#     hp_per / dmg_per / speed_per / desc
# 召唤物最终属性 = 技能 effects 固定值 + Σ( 属性总值 × per )。
# 一个召唤技能可配多行（不同属性分别加成）；未单独配置的技能回退到 default 行。
# ============================================================
static var _summon_scaling: Dictionary = {}
static var _summon_scaling_loaded := false

# 返回某召唤技能的缩放条目数组 [{stat, hp_per, dmg_per, speed_per}]，缺省回退 default
static func get_summon_scaling(skill_id: String) -> Array:
	_ensure_summon_scaling()
	var entries: Array = _summon_scaling.get(skill_id, [])
	if entries.is_empty():
		entries = _summon_scaling.get("default", [])
	return entries

static func reload_summon_scaling() -> void:
	_reload_summon_scaling()

static func _ensure_summon_scaling() -> void:
	if not _summon_scaling_loaded:
		_reload_summon_scaling()

static func _reload_summon_scaling() -> void:
	_summon_scaling = {}
	var path := "res://src/data/summon_scaling.tsv"
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("GameData: cannot open %s" % path)
		_summon_scaling_loaded = true
		return
	var header: PackedStringArray = []
	var line_no := 0
	while not f.eof_reached():
		var line := f.get_line()
		line_no += 1
		if line.begins_with("#") or line.strip_edges() == "":
			continue
		var parts := line.split("\t")
		if header.is_empty():
			header = parts
			continue
		if parts.size() != header.size():
			push_error("GameData: summon_scaling.tsv line %d has %d fields, expect %d" % [line_no, parts.size(), header.size()])
			continue
		var row := {}
		for i in header.size():
			row[header[i]] = parts[i].strip_edges()
		var id := String(row.get("id", ""))
		if id == "":
			continue
		var entry := {
			"stat": String(row.get("stat", "agi")),
			"hp_per": float(row.get("hp_per", "0")),
			"dmg_per": float(row.get("dmg_per", "0")),
			"speed_per": float(row.get("speed_per", "0")),
		}
		if not _summon_scaling.has(id):
			_summon_scaling[id] = []
		_summon_scaling[id].append(entry)
	f.close()
	_summon_scaling_loaded = true
	print("[GameData] summon scaling loaded %d profiles" % _summon_scaling.size())

static func is_active_skill(id: String) -> bool:
	return String(get_skill(id).get("cast_type", "")) == "active"

# ============================================================
# 2.5 融合系统：技能作为"增益"时注入主技能的效果
# ------------------------------------------------------------
# 每个技能双用：作主技能=完整效果(host 顶层字段)；作增益=注入弱化效果。
# 衰减系数 AUGMENT_DECAY(0.5)：增益效果写满值，运行时 ×0.5（方案 B 无封顶）。
# 表里填了 augment_effects 列的技能用显式值，否则由 _derive_augment 安全推导。
static func get_augment(id: String) -> Dictionary:
	var s := get_skill(id)
	if s.has("augment"):
		return s["augment"]
	return _derive_augment(s)

static func _derive_augment(skill: Dictionary) -> Dictionary:
	var out := {"effects": {}}
	var src: Dictionary = skill.get("effects", {})
	var safe := ["freeze", "stun", "slow", "slow_dur", "root", "sleep", "hex",
		"silence", "banish", "dot_pct_maxhp", "ground_dps_mult", "ground_secs",
		"heal", "heal_amount", "shield", "buff_secs", "knockback",
		"chain", "core_multiplier", "projectile_mult", "trail_dps_mult",
		"trail_secs", "line_stun", "self_heal_pct", "energy_dmg_ratio", "stun_dur",
		"lifesteal", "aura_value"]
	for k in safe:
		if src.has(k):
			out["effects"][k] = src[k]
	return out

# ============================================================
# 3. 装备数据
# ============================================================
static func get_all_equipment() -> Dictionary:
	return {
		"recovery_stone": {
			"id": "recovery_stone", "name": "恢复石",
			"icon": "res://assets/icons/tactic/tactic1.png",
			"quality": "blue", "effect_type": "active_use",
			"effect_description": "点击使用：恢复30%HP+30%EN。击杀15怪充能。可售30金。",
			"stat_bonuses": {"str": 0, "agi": 0, "int": 0, "vit": 0, "luk": 0},
			"sell_price": 30, "buy_price": 50
		},
		"iron_guard": {
			"id": "iron_guard", "name": "魔法盾护符",
			"icon": "res://assets/items/attribute/Icon1.png",
			"quality": "white", "effect_type": "trigger",
			"effect_description": "能量>50%时伤害从能量抵扣而非HP。",
			"stat_bonuses": {"str": 0, "agi": 0, "int": 0, "vit": 2, "luk": 0},
			"sell_price": 15
		},
		"swift_boots": {
			"id": "swift_boots", "name": "火行者之靴",
			"icon": "res://assets/items/attribute/Icon2.png",
			"quality": "white", "effect_type": "trigger",
			"effect_description": "点地范围技能命中后地面燃烧3秒(每秒30%伤害)。",
			"stat_bonuses": {"str": 0, "agi": 2, "int": 0, "vit": 0, "luk": 0},
			"sell_price": 15
		},
		"power_badge": {
			"id": "power_badge", "name": "赌徒脚链",
			"icon": "res://assets/items/attribute/Icon3.png",
			"quality": "blue", "effect_type": "trigger",
			"effect_description": "掉落品质偏移×2，但最大生命-25%。",
			"stat_bonuses": {"str": 0, "agi": 0, "int": 0, "vit": 0, "luk": 0},
			"sell_price": 25
		},
		"focus_pendant": {
			"id": "focus_pendant", "name": "法力泉",
			"icon": "res://assets/items/attribute/Icon4.png",
			"quality": "blue", "effect_type": "stat",
			"effect_description": "能量回复+80%，最大能量-30%。",
			"stat_bonuses": {"str": 0, "agi": 0, "int": 3, "vit": 0, "luk": 0},
			"sell_price": 25
		},
		"lucky_charm": {
			"id": "lucky_charm", "name": "幸运兔脚",
			"icon": "res://assets/items/attribute/Icon5.png",
			"quality": "blue", "effect_type": "stat",
			"effect_description": "+3幸运",
			"stat_bonuses": {"str": 0, "agi": 0, "int": 0, "vit": 0, "luk": 3},
			"sell_price": 25
		},
		"thorn_mail": {
			"id": "thorn_mail", "name": "荆棘甲",
			"icon": "res://assets/items/attribute/Icon6.png",
			"quality": "purple", "effect_type": "trigger",
			"effect_description": "反弹伤害+30%",
			"stat_bonuses": {"str": 0, "agi": 0, "int": 0, "vit": 2, "luk": 0},
			"sell_price": 40
		},
		"siphon_ring": {
			"id": "siphon_ring", "name": "虹吸戒指",
			"icon": "res://assets/items/magic/Icon7.png",
			"quality": "purple", "effect_type": "trigger",
			"effect_description": "击杀回复5%能量",
			"stat_bonuses": {"str": 0, "agi": 0, "int": 2, "vit": 0, "luk": 0},
			"sell_price": 40
		},
		"destroyer_mark": {
			"id": "destroyer_mark", "name": "毁灭者印记",
			"icon": "res://assets/icons/weapon_shotgun_icon.png",
			"quality": "purple", "effect_type": "synergy",
			"effect_description": "范围技能伤害+30%",
			"stat_bonuses": {"str": 2, "agi": 0, "int": 0, "vit": 0, "luk": 0},
			"sell_price": 40
		},
		"overload_core": {
			"id": "overload_core", "name": "过载核心",
			"icon": "res://assets/items/relics/relic_dual_eyes.png",
			"quality": "purple", "effect_type": "trigger",
			"effect_description": "连杀5怪后能量回复翻倍3秒",
			"stat_bonuses": {"str": 0, "agi": 2, "int": 0, "vit": 0, "luk": 0},
			"sell_price": 40
		}
	}

static func get_equipment(id: String) -> Dictionary:
	return get_all_equipment().get(id, {})

# ============================================================
# 4. 辅助函数
# ============================================================
static func get_random_skill_id(exclude_ids: Array = [], quality_filter := "") -> String:
	var pool: Array[String] = []
	for id in get_all_skills():
		if exclude_ids.has(id):
			continue
		if not quality_filter.is_empty() and String(get_all_skills()[id].get("quality", "")) != quality_filter:
			continue
		pool.append(id)
	if pool.is_empty():
		return get_skill_id_list().pick_random()
	return pool.pick_random()

static func get_random_equipment_id(exclude_ids: Array = []) -> String:
	var pool: Array[String] = []
	for id in get_all_equipment():
		if id == "recovery_stone":
			continue
		if exclude_ids.has(id):
			continue
		pool.append(id)
	if pool.is_empty():
		return "iron_guard"
	return pool.pick_random()

static func get_skill_id_list() -> Array:
	return get_all_skills().keys()

static func get_equipment_id_list() -> Array:
	var ids: Array = []
	for id in get_all_equipment():
		if id != "recovery_stone":
			ids.append(id)
	return ids

# 品质到伤害倍率的映射
static func get_quality_multiplier(quality: String) -> float:
	match quality:
		"white": return 1.0
		"blue": return 1.25
		"purple": return 1.6
		"legendary": return 2.1
		_: return 1.0
