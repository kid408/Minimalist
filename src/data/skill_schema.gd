class_name SkillSchema
extends RefCounted

# ============================================================
# 技能表字段规范：列名、枚举、类型、默认值、校验、legacy 兼容派生
# 所有技能数据从此 schema 出发，由 SkillLoader 解析 res://src/data/skills/*.tsv
#
# 设计原则：
#   1. 列只保留「所有技能都可能用到」的通用字段，稀有参数一律写进 effects。
#   2. cast_mode 决定「怎么放」（六大施法方式），shape 决定「打哪里」（几何形态）。
#   3. 新增技能 = 加一行表；只有全新行为原语才需要动代码。
# ============================================================

# 列顺序即 TSV 表头顺序（21 列）
const COLUMNS := [
	"id", "name", "icon", "quality", "school",
	"cast_type", "cast_mode", "shape", "target_side",
	"damage", "radius", "range", "duration", "ground", "tick_interval",
	"cooldown", "energy_cost",
	"effects", "augment_effects", "tags", "description"
]

# 六大施法方式
const CAST_MODES := ["instant", "point", "unit_target", "channel", "aura", "toggle"]
const CAST_TYPES := ["active", "passive"]
# 几何形态：自身环 / 落点圆 / 直线突进 / 扇形 / 弹体 / 单体 / 无 / 召唤
const SHAPES := ["self_ring", "circle", "line", "cone", "projectile", "target", "none", "summon"]
# both = 对敌伤害且对友治疗
const TARGET_SIDES := ["enemy", "ally", "self", "both", "ground"]
const SCHOOLS := ["fire", "ice", "lightning", "nature", "shadow", "holy", "physical", "arcane", "summon", "lifesteal"]
const QUALITIES := ["white", "blue", "purple", "orange", "red"]

# 各列类型：bool / int / float / kv(dict) / list / string
const COL_TYPES := {
	"id": "string", "name": "string", "icon": "string", "quality": "string",
	"school": "string", "cast_type": "string", "cast_mode": "string",
	"shape": "string", "target_side": "string", "description": "string",
	"ground": "bool",
	"damage": "float", "radius": "float", "range": "float", "duration": "float",
	"tick_interval": "float", "cooldown": "float", "energy_cost": "float",
	"effects": "kv", "augment_effects": "kv", "tags": "list"
}

const DEFAULTS := {
	"quality": "white", "school": "physical", "cast_type": "active",
	"cast_mode": "instant", "shape": "none", "target_side": "enemy",
	"icon": "res://assets/skills/skill_icon_00.png", "description": "",
	"ground": false,
	"damage": 0.0, "radius": 0.0, "range": 600.0, "duration": 0.0,
	"tick_interval": 0.5, "cooldown": 5.0, "energy_cost": 20.0,
	"effects": {}, "augment_effects": {}, "tags": []
}

# ------------------------------------------------------------
# 校验：返回错误字符串数组（空数组 = 通过）
# ------------------------------------------------------------
static func validate(def: Dictionary) -> Array:
	var errs: Array = []
	if String(def.get("id", "")).is_empty():
		errs.append("missing id")
	if not (String(def.get("cast_mode", "")) in CAST_MODES):
		errs.append("bad cast_mode: %s" % def.get("cast_mode", ""))
	if not (String(def.get("cast_type", "")) in CAST_TYPES):
		errs.append("bad cast_type: %s" % def.get("cast_type", ""))
	if not (String(def.get("shape", "")) in SHAPES):
		errs.append("bad shape: %s" % def.get("shape", ""))
	if not (String(def.get("target_side", "")) in TARGET_SIDES):
		errs.append("bad target_side: %s" % def.get("target_side", ""))
	if not (String(def.get("quality", "")) in QUALITIES):
		errs.append("bad quality: %s" % def.get("quality", ""))
	var mode := String(def.get("cast_mode", ""))
	var fx: Dictionary = def.get("effects", {})
	if mode == "aura" and def.get("cast_type", "") == "active" and not fx.has("aura_stat"):
		errs.append("aura skill missing effects.aura_stat")
	if mode == "channel" and float(def.get("duration", 0.0)) <= 0.0:
		errs.append("channel skill needs duration > 0")
	if mode == "point" and float(def.get("radius", 0.0)) <= 0.0:
		errs.append("point skill needs radius > 0")
	return errs

# ------------------------------------------------------------
# legacy 兼容：由 cast_mode + shape + target_side 派生旧字段
# 旧代码（hud / world_system / arena 联动 / 存档）仍读 subtype、target_mode。
# ------------------------------------------------------------
static func derive_subtype(def: Dictionary) -> String:
	var mode := String(def.get("cast_mode", "instant"))
	match mode:
		"channel": return "channel"
		"aura": return "aura"
		"toggle": return "toggle"
		"unit_target": return "target"
	var shape := String(def.get("shape", "none"))
	match shape:
		"self_ring":
			return "heal" if String(def.get("target_side", "")) == "ally" else "aoe_self"
		"circle":
			return "ground" if bool(def.get("ground", false)) else "aoe_ground"
		"line": return "dash"
		"projectile": return "projectile"
		"summon": return "summon"
		"cone": return "aoe_self"
		_: return "buff"

static func derive_target_mode(def: Dictionary) -> String:
	var side := String(def.get("target_side", "enemy"))
	match side:
		"both": return "both"
		"self": return "ally"
		"ground": return "enemy"
		_: return side
