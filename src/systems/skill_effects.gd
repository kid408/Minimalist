class_name SkillEffects
extends RefCounted

# ============================================================
# 技能效果原语执行库（计划 §6）
# ------------------------------------------------------------
# effects 字典的每个 key 对应一个「原语」，由下面的分发器交给对应函数执行。
# 新增行为原语 = 在下面加一个 _eff_xxx 并在分发器注册，其它代码零改动。
#
# 处理函数签名统一为： _eff_xxx(unit: Node, effects: Dictionary, ctx: Dictionary)
#   unit    ：受影响单位（敌人或施法者）
#   effects ：完整 effects 字典（原语可读取 companion 键，如 slow_dur / buff_secs）
#   ctx     ：{arena, caster, dmg, from_pos, effects, include_summons}
# ============================================================

# 目标侧（敌人）控制 / 减益原语
const TARGET_KEYS := [
	"stun", "freeze", "slow", "root", "sleep", "hex", "banish", "silence",
	"polymorph", "armor_break", "dot", "pull",
]

# 施法者侧（玩家 / 召唤物）增益原语
const CASTER_KEYS := [
	"heal", "heal_amount", "shield", "lifesteal", "buff_stat", "reflect",
]


# 把 effects 中的目标侧原语施加到单位（敌人）
static func apply_to_target(unit: Node, effects: Dictionary, ctx: Dictionary) -> void:
	if unit == null or not is_instance_valid(unit) or not unit.has_method("apply_status"):
		return
	for key in effects.keys():
		if key in TARGET_KEYS:
			_dispatch_target(key, unit, effects, ctx)


# 把 effects 中的施法者侧原语施加到 caster（玩家 / 召唤物）
static func apply_to_caster(effects: Dictionary, ctx: Dictionary) -> void:
	var caster = ctx.get("caster", null)
	if caster == null or not is_instance_valid(caster):
		return
	for key in effects.keys():
		if key in CASTER_KEYS:
			_dispatch_caster(key, caster, effects, ctx)


static func _dispatch_target(key: String, unit: Node, effects: Dictionary, ctx: Dictionary) -> void:
	match key:
		"stun": _eff_stun(unit, effects, ctx)
		"freeze": _eff_freeze(unit, effects, ctx)
		"slow": _eff_slow(unit, effects, ctx)
		"root": _eff_root(unit, effects, ctx)
		"sleep": _eff_sleep(unit, effects, ctx)
		"hex": _eff_hex(unit, effects, ctx)
		"banish": _eff_banish(unit, effects, ctx)
		"silence": _eff_silence(unit, effects, ctx)
		"polymorph": _eff_polymorph(unit, effects, ctx)
		"armor_break": _eff_armor_break(unit, effects, ctx)
		"dot": _eff_dot(unit, effects, ctx)
		"pull": _eff_pull(unit, effects, ctx)


static func _dispatch_caster(key: String, caster: Node, effects: Dictionary, ctx: Dictionary) -> void:
	match key:
		"heal": _eff_heal(caster, effects, ctx)
		"heal_amount": _eff_heal_amount(caster, effects, ctx)
		"shield": _eff_shield(caster, effects, ctx)
		"lifesteal": _eff_lifesteal(caster, effects, ctx)
		"buff_stat": _eff_buff_stat(caster, effects, ctx)
		"reflect": _eff_reflect(caster, effects, ctx)


# ---------------- 目标侧：控制 / 减益 ----------------
static func _eff_stun(unit, effects, _ctx) -> void:
	var dur := float(effects.get("stun", 0.0))
	if dur <= 0.0:
		return
	if bool(effects.get("stun_double_if_frozen", false)) and unit.hit_stun_remaining > 0.0:
		dur *= 2.0
	unit.hit_stun_remaining = maxf(unit.hit_stun_remaining, dur)


static func _eff_freeze(unit, effects, _ctx) -> void:
	var dur := float(effects.get("freeze", 0.0))
	if dur <= 0.0:
		return
	unit.hit_stun_remaining = maxf(unit.hit_stun_remaining, dur)


static func _eff_slow(unit, effects, _ctx) -> void:
	var pct := float(effects.get("slow", 0.0))
	if pct <= 0.0:
		return
	var dur := float(effects.get("slow_dur", 2.0))
	unit.apply_slow(pct, dur)


static func _eff_root(unit, effects, _ctx) -> void:
	var dur := float(effects.get("root", 0.0))
	if dur <= 0.0:
		return
	unit.apply_status("root", dur)


static func _eff_sleep(unit, effects, _ctx) -> void:
	var dur := float(effects.get("sleep", 0.0))
	if dur <= 0.0:
		return
	unit.apply_status("sleep", dur)


static func _eff_hex(unit, effects, _ctx) -> void:
	var dur := float(effects.get("hex", 0.0))
	if dur <= 0.0:
		return
	unit.apply_status("hex", dur)


static func _eff_banish(unit, effects, _ctx) -> void:
	var dur := float(effects.get("banish", 0.0))
	if dur <= 0.0:
		return
	unit.apply_status("banish", dur)


static func _eff_silence(unit, effects, _ctx) -> void:
	var dur := float(effects.get("silence", 0.0))
	if dur <= 0.0:
		return
	unit.apply_status("silence", dur)


static func _eff_polymorph(unit, effects, _ctx) -> void:
	var dur := float(effects.get("polymorph", 0.0))
	if dur <= 0.0:
		return
	unit.apply_status("polymorph", dur)


static func _eff_armor_break(unit, effects, _ctx) -> void:
	var parts: Array = _nums(effects.get("armor_break"))
	if parts.size() < 1 or parts[0] <= 0.0:
		return
	var mult: float = parts[0]
	var dur: float = parts[1] if parts.size() > 1 else 5.0
	unit.apply_armor_break(mult, dur)


static func _eff_dot(unit, effects, _ctx) -> void:
	var parts: Array = _nums(effects.get("dot"))
	if parts.size() < 2:
		return
	var dps: float = parts[0]
	var dur: float = parts[1]
	if dps <= 0.0 or dur <= 0.0:
		return
	var school := "physical"
	if effects.get("dot") is String:
		var sp := String(effects.get("dot")).split(",")
		if sp.size() > 2:
			school = sp[2].strip_edges()
	unit.apply_dot(dps, dur, school)


static func _eff_pull(unit, effects, ctx) -> void:
	var dist := float(effects.get("pull", 0.0))
	if dist <= 0.0:
		return
	var caster: Node = ctx.get("caster", null)
	if caster == null or not is_instance_valid(caster):
		return
	var to_caster: Vector2 = caster.global_position - unit.global_position
	if to_caster.length() > 0.001:
		var step := minf(dist, to_caster.length())
		unit.global_position += to_caster.normalized() * step


# ---------------- 施法者侧：治疗 / 增益 ----------------
static func _eff_heal(caster, effects, ctx) -> void:
	# 按伤害比例治疗（both 类技能）：heal = dmg * 比例
	var ratio := float(effects.get("heal", 0.0))
	if ratio <= 0.0:
		return
	var amt := ratio * float(ctx.get("dmg", 0.0))
	if amt <= 0.0:
		return
	_heal_unit(caster, amt)
	_loop_summons_heal(ctx, amt)


static func _eff_heal_amount(caster, effects, ctx) -> void:
	var amt := float(effects.get("heal_amount", 0.0))
	if amt <= 0.0:
		return
	_heal_unit(caster, amt)
	_loop_summons_heal(ctx, amt)


static func _eff_shield(caster, effects, ctx) -> void:
	var amt := float(effects.get("shield", 0.0))
	if amt <= 0.0:
		return
	var secs := float(effects.get("buff_secs", 8.0))
	_shield_unit(caster, amt, secs)
	_loop_summons_shield(ctx, amt, secs)


static func _eff_lifesteal(caster, effects, ctx) -> void:
	var ratio := float(effects.get("lifesteal", 0.0))
	if ratio <= 0.0:
		return
	var dmg := float(ctx.get("dmg", 0.0))
	if dmg <= 0.0:
		return
	_heal_unit(caster, dmg * ratio)


static func _eff_buff_stat(caster, effects, _ctx) -> void:
	var sp := String(effects.get("buff_stat", "")).split(",")
	if sp.size() < 3:
		return
	var stat := sp[0].strip_edges()
	var mult := float(sp[1])
	var dur := float(sp[2])
	if caster.has_method("add_temp_buff"):
		caster.add_temp_buff(stat, mult, dur)


static func _eff_reflect(caster, effects, _ctx) -> void:
	var parts: Array = _nums(effects.get("reflect"))
	if parts.size() < 1:
		return
	var ratio: float = parts[0]
	var dur: float = parts[1] if parts.size() > 1 else 6.0
	if caster.has_method("add_reflect"):
		caster.add_reflect(ratio, dur)


# ---------------- helpers ----------------
static func _heal_unit(u, amt) -> void:
	if u != null and is_instance_valid(u) and u.has_method("heal"):
		u.heal(amt)


static func _shield_unit(u, amt, secs) -> void:
	if u != null and is_instance_valid(u) and u.has_method("add_shield"):
		u.add_shield(amt, secs)


static func _loop_summons_heal(ctx, amt) -> void:
	var arena = ctx.get("arena", null)
	if arena == null or not bool(ctx.get("include_summons", false)):
		return
	for s in arena.summons:
		if is_instance_valid(s) and s.has_method("heal"):
			_heal_unit(s, amt)


static func _loop_summons_shield(ctx, amt, secs) -> void:
	var arena = ctx.get("arena", null)
	if arena == null or not bool(ctx.get("include_summons", false)):
		return
	for s in arena.summons:
		if is_instance_valid(s) and s.has_method("add_shield"):
			_shield_unit(s, amt, secs)


static func _nums(raw) -> Array:
	if raw is String:
		var out := []
		for p in String(raw).split(","):
			var s := p.strip_edges()
			if s != "":
				out.append(float(s))
		return out
	if raw is float or raw is int:
		return [float(raw)]
	return []
