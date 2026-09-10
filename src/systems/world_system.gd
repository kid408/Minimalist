extends Node
class_name WorldSystem

# 世界系统：负责敌人/世界的生成、检测、刷新、难度、商人、祭坛、掉落与击杀结算。
# 从 arena.gd 拆出，作为独立子系统挂在 Arena 下。所有 Arena 持有的状态与共享工具
# 均通过 `arena.` 访问；本系统内方法互相调用不加前缀。

const Arena = preload("res://src/arena.gd")
const GameData = preload("res://src/data/game_data.gd")
const Enemy = preload("res://src/actors/enemy.gd")
const AncientIdol = preload("res://src/actors/ancient_idol.gd")
const MerchantNPC = preload("res://src/actors/merchant_npc.gd")
const SkillDrop = preload("res://src/systems/skill_drop.gd")

var arena: Arena


# ============================================================
# 商人交互
# ============================================================
func _try_merchant_interact() -> bool:
	for merchant in arena.merchants:
		if merchant.try_interact(arena.player):
			_open_merchant_trade(merchant)
			return true
	return false

func _open_merchant_trade(merchant: MerchantNPC) -> void:
	arena.hud.show_trade_panel(
		merchant.get_merchandise(),
		func(): arena.hud.show_skill_select_popup("选择要升级的技能", arena.skill_slots, func(idx: int): _do_upgrade(merchant, idx)),
		func(): arena.hud.show_skill_select_popup("选择要删除的技能", arena.skill_slots, func(idx: int): _do_delete(merchant, idx)),
		func(idx: int): _merchant_buy(merchant, idx),
		func(): _open_merchant_sell(),
		func(): merchant.finish_trade()
	)

# 出售仓库物品（装备按 sell_price 回金币；技能书不可出售）
func _open_merchant_sell() -> void:
	arena.hud.show_sell_popup(arena.warehouse_slots, func(wh_idx: int): _merchant_sell(wh_idx))

func _merchant_sell(wh_idx: int) -> void:
	if wh_idx < 0 or wh_idx >= arena.warehouse_slots.size():
		return
	var item: Dictionary = arena.warehouse_slots[wh_idx]
	if arena._is_empty(item):
		arena.hud.set_message("这个槽位是空的。")
		return
	if not String(item.get("cast_type", "")).is_empty():
		arena.hud.set_message("技能书不可出售，只能丢弃。")
		_open_merchant_sell()
		return
	var price := int(item.get("sell_price", 20))
	arena.warehouse_slots[wh_idx] = {}
	arena.gold += price
	arena.hud.set_message("出售【%s】 +%d 金" % [item.get("name", "装备"), price])
	arena.inventory._refresh_hud_slots()
	_open_merchant_sell()  # 出售后重新打开列表，方便连续出售

func _do_upgrade(merchant: MerchantNPC, idx: int) -> void:
	if idx < 0 or idx >= arena.skill_slots.size():
		return
	var s: Dictionary = arena.skill_slots[idx]
	if String(s.get("id", "")).is_empty():
		arena.hud.set_message("这个槽位是空的。")
		return
	if not GameData.is_active_skill(String(s.get("id", ""))):
		arena.hud.set_message("被动技能不能升级。")
		return
	var cost := merchant.get_upgrade_cost(String(s.get("quality", "white")))
	if arena.gold < cost:
		arena.hud.set_message("金币不足！需要%d金" % cost)
		return
	arena.gold -= cost
	var new_quality := "blue"
	if s.get("quality", "white") == "purple":
		new_quality = "legendary"
	elif s.get("quality", "white") == "blue":
		new_quality = "purple"
	arena.skill_slots[idx]["quality"] = new_quality
	arena.on_loadout_changed(PackedInt32Array([idx]))
	arena.hud.set_message("升级【%s】→ %s！" % [s.get("name", "技能"), new_quality])
	arena.inventory._refresh_hud_slots()
	_open_merchant_trade(merchant)  # 重新打开交易面板，玩家可继续操作

func _do_delete(merchant: MerchantNPC, idx: int) -> void:
	if idx < 0 or idx >= arena.skill_slots.size():
		return
	if arena._is_empty(arena.skill_slots[idx]):
		arena.hud.set_message("这个槽位已经是空的。")
		return
	if arena.gold < 15:
		arena.hud.set_message("金币不足！删除需要15金")
		return
	arena.gold -= 15
	arena.hud.set_message("已删除【%s】" % arena.skill_slots[idx].get("name", "技能"))
	arena.skill_slots[idx] = {}
	arena.on_loadout_changed(PackedInt32Array([idx]))
	arena.inventory._refresh_hud_slots()
	_open_merchant_trade(merchant)  # 重新打开交易面板，玩家可继续操作

func _merchant_buy(merchant: MerchantNPC, idx: int) -> void:
	var merchandise := merchant.get_merchandise()
	if idx < 0 or idx >= merchandise.size():
		return
	var equip: Dictionary = merchandise[idx]
	var cost := int(equip.get("buy_price", 50))
	if arena.gold < cost:
		arena.hud.set_message("金币不足！需要%d金" % cost)
		return
	var slot := arena.inventory._first_empty_warehouse()
	if slot < 0:
		arena.hud.set_message("仓库满了！")
		return
	arena.gold -= cost
	arena.warehouse_slots[slot] = equip.duplicate(true)
	arena.hud.set_message("购买【%s】→ 仓库" % equip.get("name", "装备"))
	arena.inventory._refresh_hud_slots()

# ============================================================
# 开放世界：敌人生成 / 检测 / 刷新 / 难度
# ============================================================
func _init_world_enemies() -> void:
	# 开局固定遭遇点保证首屏始终有可交战目标，避免全随机导致空图。
	_spawn_starter_encounter()
	var roaming_count := maxi(arena.INITIAL_ENEMIES - arena.STARTER_ENEMY_COUNT, 0)
	for i in range(roaming_count):
		_spawn_world_enemy(_random_enemy_behavior(), Enemy.EnemyType.NORMAL, _random_map_pos(720.0))

	# 每个精英营固定落在道路节点，保证探索目标和战斗密度可预期。
	var camps: Array = arena.world_layout.get_elite_camps() if arena.world_layout != null else []
	for i in range(arena.INITIAL_ELITES):
		var camp: Dictionary = camps[i] if i < camps.size() else {"center": _random_map_pos(900.0)}
		_spawn_elite_camp(camp, i)

func _spawn_starter_encounter() -> void:
	var positions: Array = arena.world_layout.get_starter_spawn_positions() if arena.world_layout != null else []
	if positions.is_empty():
		positions = [
			arena.player.global_position + Vector2(300, 20), arena.player.global_position + Vector2(360, 130),
			arena.player.global_position + Vector2(430, 250), arena.player.global_position + Vector2(260, 280),
			arena.player.global_position + Vector2(500, 90), arena.player.global_position + Vector2(500, 330),
			arena.player.global_position + Vector2(170, 390), arena.player.global_position + Vector2(330, 440),
		]
	for i in range(positions.size()):
		var behavior := Enemy.Behavior.MELEE
		if i >= 5 and i < 7:
			behavior = Enemy.Behavior.RANGED
		elif i >= 7:
			behavior = Enemy.Behavior.CHARGER
		_spawn_world_enemy(behavior, Enemy.EnemyType.NORMAL, positions[i])

func _spawn_elite_camp(camp: Dictionary, camp_index: int) -> void:
	var center: Vector2 = camp.get("center", _random_map_pos(900.0))
	_spawn_world_enemy(_random_enemy_behavior(), Enemy.EnemyType.ELITE, center)
	for i in range(3):
		var angle := TAU * float(i) / 3.0 + float(camp_index) * 0.37
		var pos := center + Vector2(cos(angle), sin(angle)) * 112.0
		if arena.world_layout != null:
			pos = arena.world_layout.project_to_walkable(pos)
		_spawn_world_enemy(Enemy.Behavior.MELEE if i != 2 else Enemy.Behavior.RANGED, Enemy.EnemyType.NORMAL, pos)

func _init_central_boss() -> void:
	arena.boss_alive = true
	var boss_pos := arena.world_layout.get_boss_spawn_position() if arena.world_layout != null else arena.MAP_CENTER
	var enemy := _create_enemy(Enemy.Behavior.MELEE, Enemy.EnemyType.BOSS, boss_pos)
	enemy.detection_range = 500.0
	enemy.home_leash = 700.0
	enemy.reengage_range = 460.0
	arena.enemies_root.add_child(enemy)

func _spawn_world_enemy(behavior: int, enemy_type: int, pos: Vector2) -> void:
	if arena.world_layout != null:
		pos = arena.world_layout.project_to_walkable(pos)
	var enemy := _create_enemy(behavior, enemy_type, pos)
	arena.enemies_root.add_child(enemy)

func _create_enemy(behavior: int, enemy_type: int, pos: Vector2) -> Enemy:
	var enemy := Enemy.new()
	enemy.position = pos
	enemy.enemy_type = enemy_type
	enemy.behavior = behavior
	enemy._set_enemy_type_bar_color(enemy_type)

	_set_enemy_texture(enemy)
	_set_enemy_size(enemy)
	_set_enemy_stats(enemy)
	enemy.home_leash = 520.0 if enemy_type == Enemy.EnemyType.NORMAL else 620.0
	enemy.reengage_range = 340.0 if enemy_type == Enemy.EnemyType.NORMAL else 420.0
	enemy.chase_target = null
	enemy.world_ref = self
	return enemy

func _random_enemy_behavior() -> int:
	var roll := randf()
	if roll < 0.6:  return Enemy.Behavior.MELEE
	if roll < 0.8:  return Enemy.Behavior.RANGED
	if roll < 0.95: return Enemy.Behavior.CHARGER
	return Enemy.Behavior.EXPLODER

func _random_map_pos(min_distance_from_player: float = 0.0) -> Vector2:
	if arena.world_layout != null:
		return arena.world_layout.get_random_walkable_position(arena.player.global_position, min_distance_from_player)
	for _attempt in range(24):
		var pos := Vector2(randf_range(100, arena.MAP_WIDTH - 100), randf_range(100, arena.MAP_HEIGHT - 100))
		if min_distance_from_player <= 0.0 or pos.distance_to(arena.player.global_position) >= min_distance_from_player:
			return pos
	return Vector2(arena.MAP_WIDTH - 160, arena.MAP_HEIGHT - 160)

func get_path_for_unit(from: Vector2, to: Vector2) -> PackedVector2Array:
	if arena.world_layout != null:
		return arena.world_layout.find_path(from, to)
	var direct := PackedVector2Array()
	direct.append(to)
	return direct

func has_line_of_sight(from: Vector2, to: Vector2) -> bool:
	return arena.world_layout == null or not arena.world_layout.is_segment_blocked(from, to, 2.0)

func _set_enemy_texture(enemy: Enemy) -> void:
	match enemy.enemy_type:
		Enemy.EnemyType.ELITE:
			var pool := ["res://assets/enemies/Enemy_6.png", "res://assets/enemies/Enemy_7.png", "res://assets/enemies/Enemy_Glutton_03.png", "res://assets/enemies/Enemy_Glutton_04.png"]
			enemy._update_texture(pool[randi_range(0, pool.size() - 1)])
		Enemy.EnemyType.BOSS:
			var pool := ["res://assets/enemies/Enemy_Glutton_05.png", "res://assets/enemies/Enemy_7.png"]
			enemy._update_texture(pool[randi_range(0, pool.size() - 1)])
		_:
			var pool := ["res://assets/enemies/enemy_1.png", "res://assets/enemies/enemy_2.png", "res://assets/enemies/enemy_3.png", "res://assets/enemies/Enemy_4.png", "res://assets/enemies/Enemy_5.png", "res://assets/enemies/Enemy_Glutton_01.png", "res://assets/enemies/Enemy_Glutton_02.png"]
			enemy._update_texture(pool[randi_range(0, pool.size() - 1)])

func _set_enemy_size(enemy: Enemy) -> void:
	match enemy.enemy_type:
		Enemy.EnemyType.ELITE: enemy.visual_scale = GameData.get_enemy_visual_scale("elite")
		Enemy.EnemyType.BOSS: enemy.visual_scale = GameData.get_enemy_visual_scale("boss")
		_: enemy.visual_scale = GameData.get_enemy_visual_scale("normal")
	var sprite := enemy.get_node_or_null("BodySprite") as Sprite2D
	if sprite:
		sprite.scale = enemy.visual_scale

func _set_enemy_stats(enemy: Enemy) -> void:
	# 类型差异强调追击压力而不是单发秒杀，适配当前 2D 直控与单位碰撞。
	var scale := arena.survival.stat_scale() if arena.survival != null else 1.0
	if enemy.enemy_type == Enemy.EnemyType.BOSS:
		scale = arena.survival.boss_scale() if arena.survival != null else 1.25
	enemy.set_meta("threat_scale", scale)
	var base_hp := 50.0
	var move_speed := 195.0
	var atk_damage := 10.0
	match enemy.enemy_type:
		Enemy.EnemyType.ELITE:
			base_hp = 150.0
			move_speed = 235.0
			atk_damage = 13.0
		Enemy.EnemyType.BOSS:
			base_hp = 600.0
			move_speed = 290.0
			atk_damage = 8.0
	enemy.setup(base_hp * scale, move_speed, atk_damage * scale, 1.5)

func _process_enemy_attacks(delta: float) -> void:
	for enemy in arena.enemies_root.get_children():
		if not (enemy is Enemy) or enemy.is_dead():
			continue
		if enemy.attack_timer <= 0.0:
			continue
		enemy.attack_timer -= delta
		if enemy.attack_timer > 0.0:
			continue
		var e := enemy as Enemy
		var target := e.chase_target
		if target == null or not is_instance_valid(target):
			continue
		var reach := 52.0
		if e.behavior == Enemy.Behavior.RANGED:
			reach = e.ranged_attack_range
		if e.global_position.distance_to(target.global_position) < reach and has_line_of_sight(e.global_position, target.global_position):
			_deal_damage_to_friendly(target, e.damage, e)

func _resolve_enemy_projectile_hit(body: Node2D, projectile) -> void:
	if body == arena.player or body.is_in_group("summon"):
		_deal_damage_to_friendly(body, float(projectile.damage), projectile.attacker)

func _deal_damage_to_friendly(target: Node2D, amount: float, attacker: Node = null) -> void:
	if target == arena.player:
		_deal_damage_to_player(amount, attacker)
		return
	if target is Summon and is_instance_valid(target):
		target.take_damage(amount, Vector2.ZERO, 0.0, attacker)
		arena._spawn_damage_number(target.global_position, amount, false)

func _deal_damage_to_player(amount: float, attacker: Node = null) -> void:
	if amount <= 0.0 or arena.player_invuln > 0.0 or arena._is_dead:
		return
	var pc := arena.get_passive_combat()
	if pc.get("evasion", 0.0) > 0.0 and randf() < float(pc["evasion"]):
		arena.hud.set_message("闪避！")
		return
	arena.player.take_damage(amount, Vector2.ZERO, 0.0, attacker)
	arena._spawn_damage_number(arena.player.global_position, amount, false)
	if arena.player.hp <= 0.0 and not arena._is_dead:
		arena._is_dead = true
		arena._handle_player_death()

func _process_enemy_detection() -> void:
	for enemy in arena.enemies_root.get_children():
		if not (enemy is Enemy) or enemy.is_dead():
			continue
		var e := enemy as Enemy
		var target: Node2D = null
		if arena.threat != null:
			target = arena.threat.choose_target(e)
		if target == null and arena.player.global_position.distance_to(e.global_position) <= e.detection_range:
			target = arena.player
		if target != null:
			e.chase_target = target

func _process_respawns(delta: float) -> void:
	arena.elapsed_time += delta

	# 普通/精英刷新
	var to_remove: Array = []
	for i in range(arena.dead_queue.size()):
		var entry: Dictionary = arena.dead_queue[i]
		if arena.elapsed_time - entry.time > arena.RESPAWN_DELAY:
			to_remove.append(i)
			_spawn_world_enemy(entry.behavior, entry.type, entry.pos)

	# 必须倒序删除：正序 remove_at 会让后续索引前移，导致误删与越界
	for i in range(to_remove.size() - 1, -1, -1):
		arena.dead_queue.remove_at(to_remove[i])

	# Boss 刷新
	if not arena.boss_alive and arena.elapsed_time - arena.boss_death_time > arena.BOSS_RESPAWN_DELAY:
		_init_central_boss()

# 难度 / 威胁缩放已迁移至 SurvivalSystem（由 arena._process 驱动 survival._process）
# 原 _process_difficulty 在此移除，避免重复计时与重复缩放。

# ============================================================
# 击杀
# ============================================================
func _on_enemy_killed(enemy: Enemy) -> void:
	if enemy == null or not is_instance_valid(enemy) or enemy.get_meta("kill_resolved", false):
		return
	enemy.set_meta("kill_resolved", true)
	if arena.threat != null:
		arena.threat.clear_enemy(enemy)
	if arena.command_system != null:
		arena.command_system.notify_enemy_removed(enemy)
	arena.kills += 1

	# 经验与升级（升级获得 1 技能点）
	var xp_gain := 3.0
	if enemy.enemy_type == Enemy.EnemyType.ELITE:
		xp_gain = 15.0
	elif enemy.enemy_type == Enemy.EnemyType.BOSS:
		xp_gain = 60.0
	if arena.player.gain_xp(xp_gain):
		arena.hud.set_message("升级！Lv.%d · 获得 1 技能点（共 %d）" % [arena.player.level, arena.player.skill_points])

	# 恢复石充能
	arena.recovery_stone_charge = min(arena.recovery_stone_charge + 1, arena.recovery_stone_need)

	# 荆棘甲反弹（简化：击杀时无）

	var gold_drop := randi_range(1, 3)
	if enemy.enemy_type == Enemy.EnemyType.ELITE:
		gold_drop = randi_range(8, 15)
	elif enemy.enemy_type == Enemy.EnemyType.BOSS:
		gold_drop = randi_range(30, 50)
	arena.gold += gold_drop

	# 掉落（幸运影响品质）
	var drop_chance := 0.15
	if enemy.enemy_type == Enemy.EnemyType.ELITE:
		drop_chance = 0.5
	elif enemy.enemy_type == Enemy.EnemyType.BOSS:
		drop_chance = 1.0
	if randf() < drop_chance:
		_spawn_drop(enemy)

	# 装备：虹吸戒指（击杀回能）/ 过载核心（连杀 5 怪 → 回能翻倍 3 秒）
	for eq in arena.equipment_slots:
		var eq_id := String(eq.get("id", ""))
		if eq_id == "siphon_ring":
			arena.player.add_energy(5.0)
		elif eq_id == "overload_core":
			arena.player.kill_streak += 1
			if arena.player.kill_streak >= 5:
				arena.player.kill_streak = 0
				arena.player.overload_remaining = 3.0
				arena.hud.set_message("过载核心触发：能量回复翻倍 3 秒！")

	# 加入刷新队列（Boss 除外）
	if enemy.enemy_type != Enemy.EnemyType.BOSS:
		arena.dead_queue.append({
			"type": enemy.enemy_type,
			"behavior": enemy.behavior,
			"pos": enemy.spawn_origin,
			"time": arena.elapsed_time
		})
	else:
		arena.boss_alive = false
		arena.boss_death_time = arena.elapsed_time
		# M3：Boss 击杀上报生存系统（计入配额 / 提前胜利判定）
		if arena.survival != null:
			arena.survival.register_boss_kill()

	# P1-1: 死亡动画
	enemy.play_death_animation()

func _spawn_drop(enemy: Enemy) -> void:
	var item: Dictionary
	var is_elite := enemy.enemy_type != Enemy.EnemyType.NORMAL
	var is_boss := enemy.enemy_type == Enemy.EnemyType.BOSS

	if is_boss:
		# Boss: 40%紫技能，40%紫装备，20%金币大礼包
		var roll := randf()
		if roll < 0.4:
			item = GameData.get_skill(GameData.get_random_skill_id(arena._owned_ids(), "purple"))
		elif roll < 0.8:
			item = GameData.get_equipment(GameData.get_random_equipment_id())
		else:
			arena.gold += randi_range(40, 60)
			return
	elif is_elite:
		# 精英: 40%主动技能/30%被动(光环)技能/30%装备
		var roll := randf()
		if roll < 0.4:
			item = GameData.get_skill(arena._random_skill_by_type("active"))
		elif roll < 0.7:
			item = GameData.get_skill(arena._random_skill_by_cast_mode("aura"))
		else:
			item = GameData.get_equipment(GameData.get_random_equipment_id())
	else:
		# 普通: 60%主动技能/20%被动(光环)技能/20%装备
		var roll := randf()
		if roll < 0.6:
			item = GameData.get_skill(arena._random_skill_by_type("active"))
		elif roll < 0.8:
			item = GameData.get_skill(arena._random_skill_by_cast_mode("aura"))
		else:
			item = GameData.get_equipment(GameData.get_random_equipment_id())

	# 幸运提升品质
	_apply_luck_quality(item)

	var drop := SkillDrop.new(item)
	var drop_pos := enemy.global_position + Vector2(randf_range(-30, 30), randf_range(-30, 30))
	drop.position = arena.world_layout.project_to_walkable(drop_pos) if arena.world_layout != null else drop_pos
	arena.drops_root.add_child(drop)

func _apply_luck_quality(item: Dictionary) -> void:
	var bias := arena.player.drop_quality_bias()  # 0.0 ~ 0.30
	if bias <= 0 or randf() > bias:
		return
	var quality := String(item.get("quality", "white"))
	if quality == "white":
		item["quality"] = "blue"
	elif quality == "blue":
		item["quality"] = "purple"

# ============================================================
# 商人管理
# ============================================================
func _process_merchants(_delta: float) -> void:
	if arena.elapsed_time > 5.0 and arena.merchants.is_empty():
		for i in range(2):
			_spawn_merchant()

func _init_ancient_idols() -> void:
	const IDOL_COUNT := 2
	for i in range(IDOL_COUNT):
		var idol := AncientIdol.new()
		var pos := _random_map_pos(900.0)
		for _attempt in range(24):
			var overlaps_existing := false
			for existing in arena.idols:
				if is_instance_valid(existing) and pos.distance_to(existing.global_position) < 700.0:
					overlaps_existing = true
					break
			if not overlaps_existing:
				break
			pos = _random_map_pos(900.0)
		idol.position = pos
		arena.add_child(idol)
		arena.idols.append(idol)

func _try_idol_interact() -> bool:
	for idol in arena.idols:
		if not is_instance_valid(idol):
			continue
		if idol._player_near and not idol.used:
			arena.hud.show_idol_popup(
				idol.get_cost_description(),
				func(): _accept_idol(idol),
				func(): pass  # 拒绝，什么都不做
			)
			return true
	return false

func _accept_idol(idol: AncientIdol) -> void:
	# 随机一件传说品质主动技能
	var subtype_pool := ["aoe_self", "aoe_ground", "dash", "projectile"]
	var subtype: String = subtype_pool[randi_range(0, subtype_pool.size() - 1)]
	var candidates: Array = []
	for sid in GameData.get_skill_id_list():
		var s := GameData.get_skill(sid)
		if String(s.get("cast_type", "")) == "active" and String(s.get("subtype", "")) == subtype:
			candidates.append(sid)
	if candidates.is_empty():
		candidates = GameData.get_skill_id_list()
	var skill := GameData.get_skill(candidates[randi_range(0, candidates.size() - 1)])
	skill["quality"] = "legendary"

	# 放进仓库（如果满则替换最后一个）
	var empty := arena.inventory._first_empty_warehouse()
	if empty >= 0:
		arena.warehouse_slots[empty] = skill
	else:
		arena.warehouse_slots[arena.WAREHOUSE_SLOT_COUNT - 1] = skill

	idol.apply_cost(arena.player)
	arena.hud.set_message("接受祭坛代价！获得传说技能【%s】" % skill.get("name", "技能"))
	arena.inventory._refresh_hud_slots()

func _spawn_merchant() -> void:
	var merchant := MerchantNPC.new()
	merchant.map_size = Vector2(arena.MAP_WIDTH, arena.MAP_HEIGHT)
	merchant.world_layout = arena.world_layout
	merchant.position = _random_map_pos(760.0)
	arena.add_child(merchant)
	arena.merchants.append(merchant)

# ============================================================
# 空间网格：将分离向量从 O(n^2) 降为 O(n + k)
# （每个敌人只与邻近格子内的敌人计算斥力，k 为邻居数）
# ============================================================
const _GRID_CELL := 64.0
var _enemy_grid: Dictionary = {}

func _physics_process(_delta: float) -> void:
	# 在敌人物理之前重建网格（world 节点先于 enemies_root 添加，保证执行顺序）
	_rebuild_enemy_grid()

func _rebuild_enemy_grid() -> void:
	_enemy_grid.clear()
	for e in arena.enemies_root.get_children():
		if e is Enemy and not e.is_dead():
			var cx := int(floor(e.global_position.x / _GRID_CELL))
			var cy := int(floor(e.global_position.y / _GRID_CELL))
			var key := str(cx) + "," + str(cy)
			if not _enemy_grid.has(key):
				_enemy_grid[key] = []
			_enemy_grid[key].append(e)

func query_nearby_enemies(pos: Vector2, radius: float) -> Array:
	var result: Array = []
	var r := maxf(radius, _GRID_CELL)
	var min_cx := int(floor((pos.x - r) / _GRID_CELL))
	var max_cx := int(floor((pos.x + r) / _GRID_CELL))
	var min_cy := int(floor((pos.y - r) / _GRID_CELL))
	var max_cy := int(floor((pos.y + r) / _GRID_CELL))
	for cx in range(min_cx, max_cx + 1):
		for cy in range(min_cy, max_cy + 1):
			var arr: Array = _enemy_grid.get(str(cx) + "," + str(cy), [])
			for e in arr:
				result.append(e)
	return result
