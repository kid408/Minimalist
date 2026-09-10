extends Node2D
class_name CombatSystem

# 战斗系统：玩家普攻、技能施放（各 subtype）、冷却、被动自动施放、召唤物控制、
# 伤害结算、AOE 指示、HUD 刷新等。从 arena.gd 拆出，挂在 Arena 下。
# Arena 持有的状态与共享工具均通过 `arena.` 访问；本系统内方法互相调用不加前缀。

const Arena = preload("res://src/arena.gd")
const GameData = preload("res://src/data/game_data.gd")
const Enemy = preload("res://src/actors/enemy.gd")
const Projectile = preload("res://src/actors/projectile.gd")
const Summon = preload("res://src/actors/summon.gd")
const SkillEffects = preload("res://src/systems/skill_effects.gd")

var arena: Arena


# ============================================================
# 自动普攻
# ============================================================
func _process_attack(delta: float) -> void:
	if arena.attack_system != null:
		arena.attack_system.process_tick(delta)


func resolve_basic_attack(attacker: Node2D, target: Enemy, damage: float) -> void:
	if attacker == null or target == null or not is_instance_valid(attacker) or not is_instance_valid(target):
		return
	_show_attack_line(attacker.global_position, target.global_position)
	_deal_to_enemy(target, damage, {"knockback": 40.0}, attacker.global_position, attacker)
	_spawn_hit_effect(target.global_position, Color(1.0, 0.84, 0.35, 0.9))


func resolve_summon_attack(attacker: Summon, target: Enemy, damage: float) -> void:
	if attacker == null or target == null or not is_instance_valid(attacker) or not is_instance_valid(target):
		return
	_deal_to_enemy(target, damage, {"knockback": 30.0}, attacker.global_position, attacker, false)
	_spawn_hit_effect(target.global_position, Color(0.35, 1.0, 0.58, 0.8))


func _show_attack_line(from: Vector2, to: Vector2) -> void:
	var line := Line2D.new()
	line.width = 2.4
	line.default_color = Color(1.0, 0.85, 0.3, 0.78)
	line.add_point(from)
	line.add_point(to)
	arena.add_child(line)
	var tween := create_tween()
	tween.tween_property(line, "modulate:a", 0.0, 0.12)
	tween.tween_callback(line.queue_free)


func _spawn_hit_effect(pos: Vector2, color: Color) -> void:
	var effect := Node2D.new()
	effect.global_position = pos
	effect.z_index = 15
	var ring := Line2D.new()
	ring.width = 2.0
	ring.default_color = color
	var points := PackedVector2Array()
	for i in range(13):
		var angle := TAU * float(i) / 12.0
		points.append(Vector2(cos(angle), sin(angle)) * 10.0)
	ring.points = points
	effect.add_child(ring)
	arena.add_child(effect)
	var tween := create_tween()
	tween.tween_property(effect, "scale", Vector2(1.8, 1.8), 0.16)
	tween.parallel().tween_property(effect, "modulate:a", 0.0, 0.16)
	tween.tween_callback(effect.queue_free)

# ============================================================
# 技能施放
# ============================================================
const AUGMENT_DECAY := 0.5   # 增益衰减系数（方案 B 无封顶，仅衰减单个增益强度）

# 施放入口：统一委托给 SkillEngine（按 cast_mode 分发六大施法方式）
func _cast_skill(index: int) -> void:
	if arena.skill_engine == null:
		return
	arena.skill_engine.request_cast(index)


# ============================================================
# 技能预览（按下技能键显示范围遮罩，松开才释放）
# ============================================================
# 计算技能槽的预览参数（不消耗冷却/能量，仅用于展示）
func _compute_preview(index: int) -> Dictionary:
	if index < 0 or index >= arena.skill_slots.size():
		return {"valid": false}
	var host: Dictionary = arena.skill_slots[index]
	if String(host.get("id", "")).is_empty():
		return {"valid": false}
	var augments: Array = []
	if index < arena.augment_slots.size():
		augments = arena.augment_slots[index]
	var resolved := _merge_fused_unit(host, augments)
	if resolved.is_empty():
		return {"valid": false}
	# 预览完全由 cast_mode（怎么放）+ shape（打哪里）驱动，新增技能无需改这里
	var mode := String(resolved.get("cast_mode", "instant"))
	var shape := String(resolved.get("shape", "none"))
	var side := String(resolved.get("target_side", "enemy"))
	var school := String(resolved.get("school", "physical"))
	var radius := float(resolved.get("radius", 0.0))
	var color := Color(0.3, 0.8, 1.0, 0.45)
	var uses_mouse := false
	var directional := false

	match shape:
		"self_ring", "cone":
			uses_mouse = false
			if radius <= 0.0:
				radius = 140.0
			color = Color(0.3, 1.0, 0.5, 0.45) if side == "ally" else Color(0.3, 0.8, 1.0, 0.45)
		"circle":
			uses_mouse = true
			if radius <= 0.0:
				radius = 130.0
			color = Color(0.38, 0.78, 1.0, 0.45) if school == "ice" else Color(1.0, 0.5, 0.2, 0.45)
		"line", "projectile":
			uses_mouse = true
			directional = true
			radius = 0.0
			color = Color(1.0, 0.9, 0.3, 0.6)
		"target":
			uses_mouse = false
			radius = 0.0
			color = Color(1.0, 0.4, 0.4, 0.5)
		_:
			uses_mouse = false
			radius = 60.0
			color = Color(0.5, 0.7, 1.0, 0.4)

	# 施法方式对预览的修正
	match mode:
		"aura":
			radius = 40.0
			uses_mouse = false
			directional = false
			color = Color(0.9, 0.8, 0.3, 0.35)
		"toggle":
			uses_mouse = false
			color = Color(1.0, 0.6, 0.2, 0.35)
		"channel":
			color = Color(0.48, 0.82, 1.0, 0.48) if school == "ice" else Color(0.6, 0.4, 1.0, 0.45)

	return {
		"valid": true,
		"subtype": String(resolved.get("subtype", "")),
		"cast_mode": mode,
		"shape": shape,
		"radius": radius,
		"color": color,
		"uses_mouse": uses_mouse,
		"directional": directional,
	}

# 创建持续存在的预览视觉节点（需手动 queue_free），返回 Node2D
func _make_preview_visual(radius: float, color: Color) -> Node2D:
	var indicator := Node2D.new()
	indicator.name = "SkillPreview"
	indicator.z_index = 5
	if radius > 0.0:
		var sprite := Sprite2D.new()
		sprite.name = "RangeSprite"
		var tex := GradientTexture2D.new()
		tex.width = int(radius * 2)
		tex.height = int(radius * 2)
		tex.fill = GradientTexture2D.FILL_RADIAL
		var grad := Gradient.new()
		grad.colors = [color, Color(color.r, color.g, color.b, 0.0)]
		tex.gradient = grad
		sprite.texture = tex
		sprite.scale = Vector2.ONE
		indicator.add_child(sprite)
	var line := Line2D.new()
	line.name = "AimLine"
	line.width = 3.0
	line.default_color = color
	line.visible = false
	indicator.add_child(line)
	arena.add_child(indicator)
	return indicator


# ============================================================
# 融合单元合并（主技能 + 两个增益）→ resolved 字典
# ============================================================
func _merge_fused_unit(host: Dictionary, augments: Array) -> Dictionary:
	if host == null or host.is_empty():
		return {}
	var resolved := host.duplicate(true)
	if not resolved.has("effects"):
		resolved["effects"] = {}
	else:
		resolved["effects"] = resolved["effects"].duplicate(true)

	for aug in augments:
		if aug == null or typeof(aug) != TYPE_DICTIONARY or String(aug.get("id", "")).is_empty():
			continue
		var aeff: Dictionary = GameData.get_augment(String(aug.get("id", "")))
		var eff: Dictionary = aeff.get("effects", {})
		if eff.is_empty():
			continue
		var override: Dictionary = aug.get("augment_override", {})
		var decay := float(override.get("decay", AUGMENT_DECAY))
		for k in eff.keys():
			if _is_bool_flag(k):
				resolved["effects"][k] = true
			else:
				var v := float(eff[k]) * decay
				var cur := float(resolved["effects"].get(k, 0.0))
				resolved["effects"][k] = cur + v
	return resolved

func _is_bool_flag(k: String) -> bool:
	return k in ["blink_only", "consume_all_energy", "stun_double_if_frozen", "chain_dir", "explosion"]

func _skill_aoe_self(dmg: float, skill: Dictionary) -> void:
	var effects: Dictionary = skill.get("effects", {})
	var radius := float(skill.get("radius", 140.0))
	_show_aoe_indicator(arena.player.global_position, radius, Color(0.3, 0.8, 1.0, 0.35))

	var hit_count := 0
	var hit_enemies: Array = []
	for enemy in arena.enemies_root.get_children():
		if enemy is Enemy and not (enemy as Enemy).is_dead():
			var e := enemy as Enemy
			if e.global_position.distance_to(arena.player.global_position) <= radius:
				_deal_to_enemy(e, dmg, effects, arena.player.global_position)
				hit_enemies.append(e)
				hit_count += 1

	# 连锁弹射
	var chain := int(effects.get("chain", 0))
	if chain > 0:
		var remaining := chain - hit_count
		var chained: Array = hit_enemies.duplicate()
		for i in range(remaining):
			var src: Enemy = hit_enemies[randi_range(0, hit_enemies.size() - 1)] if not hit_enemies.is_empty() else null
			if src == null or not is_instance_valid(src) or src.is_dead():
				break
			var best: Enemy = null
			var best_d := 180.0 * 180.0
			for enemy in arena.enemies_root.get_children():
				if enemy is Enemy and not (enemy as Enemy).is_dead() and not chained.has(enemy):
					var d := src.global_position.distance_squared_to((enemy as Enemy).global_position)
					if d < best_d:
						best_d = d
						best = enemy as Enemy
			if best == null:
				break
			_deal_to_enemy(best, dmg * 0.6, effects, src.global_position)
			chained.append(best)
			hit_count += 1

	# 守御场：按伤害回血（自身）
	if effects.has("self_heal_pct"):
		if arena.player != null and is_instance_valid(arena.player):
			arena.player.hp = minf(arena.player.max_hp, arena.player.hp + dmg * float(effects.get("self_heal_pct", 0.0)))

	# 双效治疗（对友：玩家+召唤物）由 SkillEngine 结算后统一交给 SkillEffects 施加

	# 地面持续区域
	if bool(skill.get("ground", false)) or String(skill.get("subtype", "")) == "ground":
		_spawn_ground_effect(arena.player.global_position, radius, dmg, skill)

	_refund_if_multi_hit(hit_count)

func _skill_aoe_ground(pos: Vector2, dmg: float, skill: Dictionary) -> void:
	var effects: Dictionary = skill.get("effects", {})
	var radius := float(skill.get("radius", 130.0))
	if not bool(skill.get("radius_locked", false)) and arena._get_synergy_bonuses().get("aoe_ground", 0) >= 2:
		radius *= 1.2
	var indicator_color := Color(1.0, 0.5, 0.2, 0.35)
	match String(skill.get("school", "physical")):
		"ice": indicator_color = Color(0.38, 0.78, 1.0, 0.38)
		"lightning": indicator_color = Color(0.75, 0.62, 1.0, 0.35)
		"shadow": indicator_color = Color(0.68, 0.34, 0.90, 0.35)
	_show_aoe_indicator(pos, radius, indicator_color)

	var is_ground := bool(skill.get("ground", false)) or String(skill.get("subtype", "")) == "ground"

	# 地面型技能：只生成持续区域，不做瞬发
	if not is_ground:
		var hit_count := 0
		for enemy in arena.enemies_root.get_children():
			if enemy is Enemy and not (enemy as Enemy).is_dead():
				var e := enemy as Enemy
				var dist: float = e.global_position.distance_to(pos)
				if dist < radius:
					var fd := dmg
					if effects.has("dot_pct_maxhp"):
						fd = e.max_hp * float(effects.get("dot_pct_maxhp", 0.06))
					elif effects.has("core_multiplier") and dist < radius * 0.4:
						fd *= float(effects.get("core_multiplier", 2.0))
					_deal_to_enemy(e, fd, effects, pos)
					hit_count += 1
		if String(skill.get("id", "")) == "ember_rain":
			arena._spawn_persistent_damage(pos, radius, dmg * 0.4, 3.0, 0.6)
		if arena._has_equip("swift_boots"):
			arena._spawn_persistent_damage(pos, radius, dmg * 0.3, 3.0, 0.6)
		_refund_if_multi_hit(hit_count)
		return

	# 地面持续区域
	_spawn_ground_effect(pos, radius, dmg, skill)

func _skill_dash(mouse_pos: Vector2, dmg: float, skill: Dictionary) -> void:
	var effects: Dictionary = skill.get("effects", {})
	var dash_dist := 100.0
	# 联动：突进距离+30%
	if arena._get_synergy_bonuses().get("dash", 0) >= 2:
		dash_dist *= 1.3
	var origin := arena.player.global_position
	var dir := origin.direction_to(mouse_pos)
	if dir.length_squared() <= 0.001:
		return
	# 闪烁可越过阻挡，但最终落点必须是可通行位置。
	if bool(effects.get("blink_only", false)):
		var blink_target := origin + dir * (dash_dist + 60.0)
		arena.player.global_position = arena.world_layout.project_to_walkable(blink_target) if arena.world_layout != null else blink_target
		arena.player.position.x = clampf(arena.player.position.x, 40, arena.MAP_WIDTH - 40)
		arena.player.position.y = clampf(arena.player.position.y, 40, arena.MAP_HEIGHT - 40)
		return

	# 突进穿过单位，但会被树林和岩石截断。
	var original_mask := arena.player.collision_mask
	arena.player.collision_mask = 8
	arena.player.move_and_collide(dir * dash_dist)
	arena.player.collision_mask = original_mask
	arena.player.position.x = clampf(arena.player.position.x, 40, arena.MAP_WIDTH - 40)
	arena.player.position.y = clampf(arena.player.position.y, 40, arena.MAP_HEIGHT - 40)

	var traveled := arena.player.global_position - origin
	var travel_length := traveled.length()
	var travel_dir := traveled.normalized() if travel_length > 0.01 else dir
	var hit_count := 0
	for enemy_node in arena.enemies_root.get_children():
		if enemy_node is Enemy and not (enemy_node as Enemy).is_dead():
			var e := enemy_node as Enemy
			var rel := e.global_position - origin
			if abs(rel.cross(travel_dir)) < 50.0 and rel.dot(travel_dir) > 0.0 and rel.dot(travel_dir) <= travel_length + 56.0:
				_deal_to_enemy(e, dmg, effects, origin)
				hit_count += 1
	# 裂地冲：留下持续裂痕
	if effects.has("trail_dps_mult"):
		arena._spawn_persistent_damage(arena.player.global_position, 60.0, dmg * float(effects.get("trail_dps_mult", 0.4)), float(effects.get("trail_secs", 3.0)), 0.6)

func _skill_projectile(mouse_pos: Vector2, dmg: float, skill: Dictionary) -> void:
	var effects: Dictionary = skill.get("effects", {})
	var dir := arena.player.global_position.direction_to(mouse_pos)

	# 方向连锁（魂链/闪电链）
	if int(effects.get("chain", 0)) > 0 and bool(effects.get("chain_dir", false)):
		var targets := arena._get_nearest_enemies_in_dir(dir, int(effects.get("chain", 3)), 500)
		for enemy in targets:
			_deal_to_enemy(enemy, dmg, effects, arena.player.global_position)
		return

	var proj := Projectile.new()
	proj.position = arena.player.global_position
	proj.damage = dmg * float(effects.get("projectile_mult", 1.0))
	proj.direction = dir
	proj.lifetime = 3.0
	proj.pierce_count = 4
	proj.effects = effects
	proj.faction = Projectile.Faction.PLAYER
	proj.attacker = arena.player
	proj.collision_layer = 0
	proj.collision_mask = 2 | 8
	proj.hit_resolver = Callable(self, "_resolve_player_projectile_hit")
	# 联动：弹体速度+40%
	if arena._get_synergy_bonuses().get("projectile", 0) >= 2:
		proj.speed *= 1.4

	var collision := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 12.0
	collision.shape = shape
	proj.add_child(collision)

	var sprite := Sprite2D.new()
	var tex := load("res://assets/projectiles/projectile_1.png") as Texture2D
	if tex:
		sprite.texture = tex
		sprite.scale = Vector2(0.3, 0.3)
		proj.add_child(sprite)

	proj.body_entered.connect(proj._on_body_entered)
	arena.add_child(proj)

func _resolve_player_projectile_hit(body: Node2D, proj: Projectile) -> void:
	if body is Enemy:
		_deal_to_enemy(body as Enemy, proj.damage, proj.effects, arena.player.global_position)

# 统一的敌人伤害结算：伤害 + 击退 + 控制/减益 + 仇恨 + 击杀回调。
func _deal_to_enemy(enemy: Enemy, dmg: float, effects: Dictionary, from_pos: Vector2, source: Node2D = null, allow_player_crit: bool = true) -> void:
	if enemy == null or not is_instance_valid(enemy) or enemy.is_dead():
		return
	var actual_source := source if source != null and is_instance_valid(source) else arena.player
	var dir := (enemy.global_position - from_pos).normalized()
	var pc := arena.get_passive_combat()
	var final_dmg := dmg
	if allow_player_crit and pc.get("crit_chance", 0.0) > 0.0 and randf() < float(pc["crit_chance"]):
		final_dmg *= float(pc.get("crit_mult", 2.0))
	enemy.take_damage(final_dmg, dir, float(effects.get("knockback", 0.0)))
	if final_dmg > 0.0:
		arena._spawn_damage_number(enemy.global_position, final_dmg)
		if arena.threat != null:
			arena.threat.report_damage(enemy, actual_source, final_dmg)
	if arena.aura != null:
		arena.aura.on_damage_dealt(final_dmg)
	# 目标侧控制/减益原语统一交给 SkillEffects 执行。
	var ctx := {"arena": arena, "caster": arena.player, "dmg": final_dmg, "from_pos": from_pos, "skill": null, "effects": effects}
	SkillEffects.apply_to_target(enemy, effects, ctx)
	if allow_player_crit and pc.get("cleave", 0.0) > 0.0:
		_apply_cleave(enemy, final_dmg * float(pc["cleave"]), enemy)
	if enemy.is_dead():
		arena.world._on_enemy_killed(enemy)


# 被动：分裂 —— 走统一结算，避免绕过仇恨、飘字和击杀回调。
func _apply_cleave(src: Enemy, dmg: float, exclude: Enemy) -> void:
	if dmg <= 0.0 or arena.enemies_root == null:
		return
	for e in arena.enemies_root.get_children():
		if e is Enemy and e != exclude and not (e as Enemy).is_dead():
			var en := e as Enemy
			if en.global_position.distance_to(src.global_position) <= 70.0:
				_deal_to_enemy(en, dmg, {}, src.global_position, arena.player, false)


# ground 类技能：生成持续伤害区域（dps 由 effects.ground_dps_mult 缩放）
func _spawn_ground_effect(pos: Vector2, radius: float, dmg: float, skill: Dictionary) -> void:
	var effects: Dictionary = skill.get("effects", {})
	var secs := float(effects.get("ground_secs", float(skill.get("duration", 3.0))))
	var interval := maxf(0.1, float(skill.get("tick_interval", 0.6)))
	var dps: float
	if effects.has("ground_dps_mult"):
		dps = dmg * float(effects.get("ground_dps_mult", 1.0))
	else:
		dps = dmg
	arena._spawn_persistent_damage(pos, radius, dps, secs, interval, effects, String(skill.get("school", "fire")))

# 治疗型技能：范围内治疗自己与召唤物
# 治疗/护盾数值由 SkillEngine 在结算后统一交给 SkillEffects 施加
func _skill_heal(pos: Vector2, dmg: float, skill: Dictionary) -> void:
	var effects: Dictionary = skill.get("effects", {})
	var radius := float(skill.get("radius", 200.0))
	_show_aoe_indicator(pos, radius, Color(0.3, 1.0, 0.5, 0.35))
	arena.hud.set_message("【%s】治疗" % skill.get("name", "技能"))

# 单体目标型技能：对选中的单位结算（敌人=伤害+控制，友军=治疗/护盾）
func _skill_unit_target(target: Node, dmg: float, skill: Dictionary) -> void:
	if target == null or not is_instance_valid(target):
		return
	var effects: Dictionary = skill.get("effects", {})
	var nm := String(skill.get("name", "技能"))
	if target is Enemy:
		_show_aoe_indicator(target.global_position, 46.0, Color(1.0, 0.4, 0.4, 0.4))
		_deal_to_enemy(target, dmg, effects, arena.player.global_position)
		arena.hud.set_message("【%s】命中目标！" % nm)
		return
	# 友军：玩家或召唤物
	_show_aoe_indicator(target.global_position, 46.0, Color(0.3, 1.0, 0.5, 0.4))
	var amount := float(effects.get("heal_amount", dmg))
	if amount > 0.0 and target.has_method("heal"):
		target.heal(amount)
	if effects.has("shield") and target.has_method("add_shield"):
		target.add_shield(float(effects.get("shield", 100.0)), float(effects.get("buff_secs", 8.0)))
	arena.hud.set_message("【%s】治疗 %.0f" % [nm, amount])

# 增益型技能：为自身与召唤物附加护盾等 buff
# 护盾数值由 SkillEngine 在结算后统一交给 SkillEffects 施加
func _skill_buff(_pos: Vector2, _dmg: float, skill: Dictionary) -> void:
	arena.hud.set_message("【%s】增益！" % skill.get("name", "技能"))

# 召唤型技能：生成召唤物（属性由 effects 指定）
func _skill_summon(_dmg: float, skill: Dictionary) -> void:
	var effects: Dictionary = skill.get("effects", {})
	var available := arena.summon_limit - arena.summons.size()
	if available <= 0:
		arena.hud.set_message("召唤物已达上限(%d)" % arena.summon_limit)
		return
	var count := mini(int(effects.get("count", 1)), available)
	# 召唤随属性成长：基础数值 + 各属性总值 × per（来自 summon_scaling.tsv）
	var hp := float(effects.get("hp", 120.0))
	var dmg := float(effects.get("dmg", 15.0))
	var speed := float(effects.get("speed", 210.0))
	for e in GameData.get_summon_scaling(String(skill.get("id", ""))):
		var sv := arena.player.total_stat(String(e.get("stat", "agi")))
		hp += sv * float(e.get("hp_per", 0.0))
		dmg += sv * float(e.get("dmg_per", 0.0))
		speed += sv * float(e.get("speed_per", 0.0))
	for i in range(count):
		var s := Summon.new()
		s.arena = arena
		s.owner_player = arena.player
		s.max_hp = hp
		s.hp = s.max_hp
		s.damage = dmg
		s.speed = speed
		s.attack_interval = 0.8
		s.attack_range = 70.0
		var ang := TAU * arena.summons.size() / float(maxf(arena.summon_limit, 1))
		s.global_position = arena.player.global_position + Vector2(cos(ang), sin(ang)) * 48.0
		arena.summons_root.add_child(s)
		arena.summons.append(s)
		# 召唤物寿命（数据 effects.summon_secs，默认 30 秒）
		var lifetime := float(effects.get("summon_secs", 30.0))
		if lifetime > 0.0:
			var ref := s
			get_tree().create_timer(lifetime).timeout.connect(func(): _remove_summon(ref))
	arena.hud.set_message("召唤【%s】！" % skill.get("name", "召唤物"))

func _show_aoe_indicator(pos: Vector2, radius: float, color: Color) -> void:
	var indicator := Node2D.new()
	indicator.position = pos
	var life := 0.6
	var sprite := Sprite2D.new()
	var tex := GradientTexture2D.new()
	tex.width = int(radius * 2)
	tex.height = int(radius * 2)
	tex.fill = GradientTexture2D.FILL_RADIAL
	var grad := Gradient.new()
	grad.colors = [color, Color(color.r, color.g, color.b, 0.0)]
	tex.gradient = grad
	sprite.texture = tex
	sprite.scale = Vector2.ONE
	indicator.add_child(sprite)
	arena.add_child(indicator)
	# 自动移除
	var tween := create_tween()
	tween.tween_property(indicator, "modulate:a", 0.0, life)
	tween.tween_callback(indicator.queue_free)

func _refund_if_multi_hit(hit_count: int) -> void:
	if hit_count >= 3:
		arena.player.add_energy(5.0)

# ============================================================
# 召唤物选择 / 指令
# ============================================================
func _summon_at(world_pos: Vector2) -> Summon:
	for s in arena.summons:
		if is_instance_valid(s) and s.global_position.distance_to(world_pos) < 28.0:
			return s
	return null

func _enemy_at(world_pos: Vector2) -> Enemy:
	for e in arena.enemies_root.get_children():
		if e is Enemy and not e.is_dead() and (arena.fog == null or arena.fog.is_position_visible(e.global_position)) and e.global_position.distance_to(world_pos) < 40.0:
			return e
	return null

func _select(s: Summon) -> void:
	if arena.command_system == null or s == null or not is_instance_valid(s):
		return
	if not arena.command_system.selected_summons.has(s):
		s.set_selected(true)
		arena.command_system.selected_summons.append(s)

func _clear_selection() -> void:
	if arena.command_system != null:
		arena.command_system.clear_selection()

func _spawn_summon() -> void:
	if arena.summons.size() >= arena.summon_limit:
		arena.hud.set_message("召唤物已达上限(%d)" % arena.summon_limit)
		return
	var s := Summon.new()
	s.arena = arena
	s.owner_player = arena.player
	var ang := TAU * arena.summons.size() / float(maxf(arena.summon_limit, 1))
	s.global_position = arena.player.global_position + Vector2(cos(ang), sin(ang)) * 48.0
	arena.summons_root.add_child(s)
	arena.summons.append(s)
	arena.hud.set_message("召唤物已生成(%d/%d)。默认跟随英雄；左键选中，右键下令。" % [arena.summons.size(), arena.summon_limit])

func _remove_summon(s: Summon) -> void:
	arena.summons.erase(s)
	arena.selected_summons.erase(s)
	if is_instance_valid(s):
		s.set_selected(false)
		s.queue_free()

# ============================================================
# 战斗 HUD 刷新
# ============================================================
func _update_hud() -> void:
	arena.hud.update_hp(arena.player.hp, arena.player.max_hp_calc())
	arena.hud.update_energy(arena.player.energy)
	arena.hud.update_gold(arena.gold)
	arena.hud.update_stats({
		"str": arena.player.total_str(), "agi": arena.player.total_agi(),
		"int": arena.player.total_int(), "vit": arena.player.total_vit(), "luk": arena.player.total_luk()
	})
	arena.hud.update_cooldowns(arena._get_cd_dict())
	arena.hud.update_skill_slot_data(arena.skill_slots)
	arena.hud.update_energy_for_slots(arena.player.energy)
	arena.hud.update_progression(arena.player.level, arena.player.xp, arena.player.xp_to_next, arena.player.skill_points)
	arena.hud.update_recovery_stone(arena.recovery_stone_charge, arena.recovery_stone_need)
	arena.hud.update_merchant_count(arena.merchants.size())
	arena.hud.update_synergy(arena._get_synergy_bonuses())
	# 小地图和目标信息遵守真实战争迷雾，而非仅按与英雄的直线距离筛选。
	var enemy_positions: Array = []
	for enemy in arena.enemies_root.get_children():
		if enemy is Enemy and not enemy.is_dead() and (arena.fog == null or arena.fog.is_position_visible(enemy.global_position)):
			enemy_positions.append(enemy.global_position)
	var merchant_positions: Array = []
	for merchant in arena.merchants:
		if is_instance_valid(merchant) and (arena.fog == null or arena.fog.is_position_visible(merchant.global_position)):
			merchant_positions.append(merchant.global_position)
	var layout_roads: Array = []
	var camp_positions: Array = []
	var boss_position := Vector2.ZERO
	if arena.world_layout != null:
		layout_roads = arena.world_layout.get_roads()
		camp_positions = arena.world_layout.get_camp_positions()
		boss_position = arena.world_layout.get_boss_spawn_position()
	var camera_rect: Rect2 = arena.camera_controller.get_world_view_rect() if arena.camera_controller != null else Rect2()
	var fog_texture: Texture2D = arena.fog.get_minimap_fog_texture() if arena.fog != null else null
	arena.hud.update_minimap(arena.player.global_position, enemy_positions, merchant_positions, Vector2(arena.MAP_WIDTH, arena.MAP_HEIGHT), layout_roads, camp_positions, boss_position, camera_rect, fog_texture)
	if arena.command_system != null:
		arena.hud.update_selection(arena.command_system.get_selection_snapshot())
		arena.hud.update_order(arena.command_system.get_order_snapshot())
		arena.hud.update_target(arena.command_system.get_target_snapshot())
	# M3：刷新生存目标条（倒计时 / Boss 进度 / 死亡次数 / 威胁等级）
	if arena.survival != null and is_instance_valid(arena.survival):
		arena.hud.update_objective({
			"time": arena.survival.time_remaining,
			"boss": arena.survival.bosses_killed,
			"boss_quota": arena.survival.BOSS_QUOTA,
			"deaths": arena.survival.deaths,
			"death_limit": arena.survival.DEATH_LIMIT,
			"threat": arena.survival.threat_tier
		})
