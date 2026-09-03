extends Node2D
class_name Arena

const FogOfWar = preload("res://src/systems/fog_of_war.gd")
const WorldSystem = preload("res://src/systems/world_system.gd")
const CombatSystem = preload("res://src/systems/combat_system.gd")
const SurvivalSystem = preload("res://src/systems/survival_system.gd")
const InventorySystem = preload("res://src/systems/inventory_system.gd")
const SkillEngine = preload("res://src/systems/skill_engine.gd")
const AuraSystem = preload("res://src/systems/aura_system.gd")

const GameData = preload("res://src/data/game_data.gd")
const HUD = preload("res://src/ui/hud.gd")
const HUDScene = preload("res://scenes/ui/hud.tscn")
const Projectile = preload("res://src/actors/projectile.gd")
const SkillDrop = preload("res://src/systems/skill_drop.gd")
const ACTIVE_SLOT_COUNT := 6
const EQUIPMENT_SLOT_COUNT := 6
const WAREHOUSE_SLOT_COUNT := 6
const ENERGY_MAX := 100.0
const ENERGY_REGEN_BASE := 5.0
const PICKUP_RANGE := 60.0
const DROP_DETECT_RANGE := 360.0

# 子系统（世界 / 战斗 / 库存），实际逻辑在各自脚本中
var world: WorldSystem
var combat: CombatSystem
var survival: SurvivalSystem
var inventory: InventorySystem
var skill_engine: SkillEngine   # 技能施放引擎（六大施法方式）
var aura: AuraSystem            # 光环 / 常驻加成

var player: Player
var hud: HUD
var drops_root: Node2D

# 槽位
var skill_slots: Array = []      # 6 格（主动，按键释放）
var equipment_slots: Array = []  # 6 格
var warehouse_slots: Array = []  # 6 格
var augment_slots: Array = []     # 6 格 × [增益1, 增益2]（融合单元的两个增益槽）

# 状态
var gold := 0
var kills := 0
var recovery_stone_charge := 15  # 开局满充能
var recovery_stone_need := 15
var agent: NavigationAgent2D
var attack_timer: float = 0.0
var mark_target: Enemy = null
var last_message := ""
var message_timer: float = 0.0
var cooldowns := {}
var skill_actions := ["skill_1", "skill_2", "skill_3", "skill_4", "skill_5", "skill_6"]
var skill_key_names := ["1", "2", "3", "4", "5", "6"]
var _camera: Camera2D
# 技能预览：按下技能键显示范围遮罩，松开才真正释放
var _preview_index: int = -1
var _preview_node: Node2D = null
# Warcraft 式点击移动：右键设置移动目标，玩家走向该点后停下
var _player_move_target: Vector2 = Vector2.ZERO
var _player_moving: bool = false
var _preview_uses_mouse: bool = false
var _preview_radius: float = 0.0
var _preview_is_directional: bool = false
var _bounce_phase: float = 0.0  # 移动弹动

# 召唤物（轻 RTS：左键选/框选，右键下令）
var summons_root: Node2D
var summons: Array = []
var selected_summons: Array = []
var summon_limit: int = 8
var _is_dragging: bool = false
var _drag_start_screen: Vector2 = Vector2.ZERO
var _drag_start_world: Vector2 = Vector2.ZERO
var _selection_box: Rect2 = Rect2()
var _left_was_pressed: bool = false
var _right_was_pressed: bool = false
# 框选遮罩绘制层（独立 CanvasLayer，避免被 HUD 层盖住）
var selection_layer: CanvasLayer
var selection_drawer: Node2D

# 敌人
const MAP_WIDTH := 6000.0
const MAP_HEIGHT := 4200.0
const MAP_CENTER := Vector2(3000, 2100)
const FOG_RADIUS := 700.0  # 战争迷雾外缘半径（也是小地图视野揭示半径）
const INITIAL_ENEMIES := 80
const INITIAL_ELITES := 12
const RESPAWN_DELAY := 18.0
const BOSS_RESPAWN_DELAY := 150.0

var enemies_root: Node2D
var _is_dead := false
var player_invuln := 0.0  # M3：死亡复活后的无敌时间（秒）
var dead_queue: Array = []  # [{type, behavior, pos, time}]
var boss_alive := false
var boss_death_time: float = -999.0
var elapsed_time: float = 0.0

# 商人 + 祭坛
var merchants: Array = []
var idols: Array = []

# 掉落生成队列
var pending_skill_drop: Dictionary = {}


func _ready() -> void:
	randomize()
	# 背景图（平铺覆盖整张地图）
	var bg_tex := load("res://assets/Map.png") as Texture2D
	if bg_tex:
		var bg_root := Node2D.new()
		bg_root.name = "Background"
		bg_root.z_index = -100
		add_child(bg_root)
		var tile := bg_tex.get_size()
		var origin := MAP_CENTER - Vector2(MAP_WIDTH, MAP_HEIGHT) * 0.5
		var cols := int(ceil(MAP_WIDTH / tile.x))
		var rows := int(ceil(MAP_HEIGHT / tile.y))
		for r in rows:
			for c in cols:
				var s := Sprite2D.new()
				s.texture = bg_tex
				s.centered = false
				s.position = origin + Vector2(c * tile.x, r * tile.y)
				bg_root.add_child(s)

	player = Player.new()
	player.init_from_hero(GameData.get_hero("vanguard"))
	player.position = Vector2(640, 400)
	add_child(player)

	# 子系统：世界 / 战斗 / 库存（必须在调用其方法前实例化）
	world = WorldSystem.new(); world.arena = self; add_child(world)
	combat = CombatSystem.new(); combat.arena = self; add_child(combat)
	inventory = InventorySystem.new(); inventory.arena = self; add_child(inventory)
	# 技能引擎（六大施法方式分发）与光环系统（常驻加成）
	aura = AuraSystem.new(); aura.arena = self; add_child(aura)
	skill_engine = SkillEngine.new(); skill_engine.arena = self; skill_engine.combat = combat; add_child(skill_engine)

	survival = SurvivalSystem.new()
	survival.arena = self
	survival.start()
	survival.set_process(false)  # M3：由 arena._process 手动驱动，避免 Godot 自动回调重复计时

	drops_root = Node2D.new()
	drops_root.name = "Drops"
	add_child(drops_root)

	enemies_root = Node2D.new()
	enemies_root.name = "Enemies"
	add_child(enemies_root)

	summons_root = Node2D.new()
	summons_root.name = "Summons"
	add_child(summons_root)

	# 框选遮罩：独立高 layer 的 CanvasLayer，绘制在 HUD 之上，用屏幕坐标画
	selection_layer = CanvasLayer.new()
	selection_layer.layer = 100
	selection_layer.name = "SelectionLayer"
	add_child(selection_layer)
	selection_drawer = preload("res://src/ui/selection_box.gd").new()
	selection_drawer.arena = self
	selection_drawer.name = "SelectionDrawer"
	selection_layer.add_child(selection_drawer)

	hud = HUDScene.instantiate()
	add_child(hud)
	hud.bind_arena(self)

	_init_camera()

	agent = NavigationAgent2D.new()
	player.add_child(agent)

	_init_slots()
	_connect_hud()
	_init_world_enemies()
	_init_central_boss()
	_init_ancient_idols()

	# 加入player组，方便掉落物寻找
	# 战争迷雾
	var fog := FogOfWar.new()
	add_child(fog)
	fog.init(player, FOG_RADIUS)
	fog.z_index = 50

	player.add_to_group("player")


func _process(delta: float) -> void:
	# 活动计时由 world._process_respawns 负责递增（刷怪 / Boss 重生依赖它）
	# 摄像机跟随
	if _camera and is_instance_valid(_camera):
		_camera.global_position = player.global_position
	_process_movement(delta)
	_process_attack(delta)
	_process_energy(delta)
	_process_cooldowns(delta)
	_process_input()
	_update_skill_preview()
	_process_merchants(delta)
	_process_enemy_attacks(delta)
	_process_enemy_detection()
	_process_respawns(delta)

	# 无敌时间递减（死亡复活后短暂无敌）
	if player_invuln > 0.0:
		player_invuln -= delta
		if player_invuln < 0.0:
			player_invuln = 0.0
		player.modulate = Color(0.6, 0.8, 1.0, 0.75)
	else:
		player.modulate = Color.WHITE

	survival._process(delta)  # M3：生存倒计时 / 威胁等级 / 胜负判定
	_process_drop_proximity(delta)
	_update_hud()

func _physics_process(_delta: float) -> void:
	pass

# ============================================================
# 移动
# ============================================================
func _process_movement(delta: float) -> void:
	# 键盘移动（备用兼容，按住时取消点击移动）
	var kdir := Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_up", "move_down")
	)
	var speed_mult := player.move_speed_mult()
	if aura != null:
		speed_mult *= 1.0 + aura.get_bonus("move_speed_pct")
	var speed := player.base_move_speed * speed_mult
	var sprite := player.get_node_or_null("BodySprite") as Sprite2D

	if kdir.length() > 0.01:
		_player_moving = false
		player.position += kdir.normalized() * speed * delta
		if sprite:
			_bounce_phase += delta * 12.0
			sprite.scale = Vector2(0.5, 0.5) + Vector2(0.02, 0.02) * sin(_bounce_phase * 2.0)
	elif _player_moving:
		# Warcraft 式：走向右键设定的目标点，到达后停下
		var to_t := _player_move_target - player.position
		var d := to_t.length()
		if d <= speed * delta or d < 4.0:
			player.position = _player_move_target
			_player_moving = false
		else:
			player.position += to_t.normalized() * speed * delta
		if sprite:
			_bounce_phase += delta * 12.0
			sprite.scale = Vector2(0.5, 0.5) + Vector2(0.02, 0.02) * sin(_bounce_phase * 2.0)
	else:
		if sprite:
			sprite.scale = sprite.scale.move_toward(Vector2(0.5, 0.5), delta * 4.0)
			_bounce_phase = 0.0

	# 范围约束（匹配放大后的地图）
	player.position.x = clampf(player.position.x, 40, MAP_WIDTH - 40)
	player.position.y = clampf(player.position.y, 40, MAP_HEIGHT - 40)

# ============================================================
# 能量回复
# ============================================================
func _process_energy(delta: float) -> void:
	player.add_energy(player.energy_regen_rate() * delta)

# ============================================================
# 输入处理
# ============================================================
func _handle_left_release(world_pos: Vector2) -> void:
	# 单体目标技能选取态：左键点击单位完成施放，不做框选
	if skill_engine != null and skill_engine.is_targeting():
		skill_engine.try_pick_target(get_global_mouse_position())
		return
	if _selection_box.has_area():
		_clear_selection()
		var box := _selection_box
		for s in summons:
			if box.has_point(s.global_position):
				_select(s)
	else:
		var s := _summon_at(world_pos)
		if s:
			_clear_selection()
			_select(s)

func _handle_right_click(world_pos: Vector2) -> void:
	# 选取态/引导态：右键先用于取消，不触发移动
	if skill_engine != null:
		if skill_engine.is_targeting():
			skill_engine.cancel_targeting()
			return
		if skill_engine.is_channeling():
			skill_engine.interrupt_channel("引导已取消。")
			return
	# Warcraft 式点击移动：右键移动玩家；点敌人则走向并设为焦点目标
	var enemy_at = _enemy_at(world_pos)
	if enemy_at:
		_player_move_target = enemy_at.global_position
		mark_target = enemy_at
	else:
		_player_move_target = world_pos
	_player_moving = true
	# 同时指挥已选中的召唤物（攻击敌人 / 移动到该点）
	if not selected_summons.is_empty():
		if enemy_at:
			for s in selected_summons:
				s.attack_target = enemy_at
		else:
			for s in selected_summons:
				s.move_to = world_pos

func _process_input() -> void:
	# 鼠标右键：下令
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		_handle_right_click(get_global_mouse_position())
	# 左键：框选/选中（按下时记录，松开时结算）
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		if not _left_was_pressed:
			_drag_start_world = get_global_mouse_position()
			_drag_start_screen = get_viewport().get_mouse_position()
			_selection_box = Rect2(_drag_start_world, Vector2.ZERO)
			_left_was_pressed = true
	else:
		if _left_was_pressed:
			_handle_left_release(_drag_start_world)
			_left_was_pressed = false
			_selection_box = Rect2()
	# 技能按键：按下进入预览（显示范围遮罩），松开才真正释放
	for i in range(skill_actions.size()):
		if Input.is_action_just_pressed(skill_actions[i]):
			_start_skill_preview(i)
		elif Input.is_action_just_released(skill_actions[i]):
			if _preview_index == i:
				_release_skill(i)
	# 交互键
	if Input.is_action_just_pressed("interact"):
		if _try_merchant_interact():
			return
		if _try_idol_interact():
			return
		_try_pickup()
	# 属性分配面板开关（T）
	if Input.is_action_just_pressed("attributes"):
		hud.toggle_attribute_panel()

# ============================================================
# 技能预览：按下显示遮罩，松开释放
# ============================================================
func _start_skill_preview(index: int) -> void:
	# 已有其它技能预览中时，先取消旧的
	if _preview_index >= 0 and _preview_index != index:
		_cancel_skill_preview()
	var host: Dictionary = skill_slots[index] if index < skill_slots.size() else {}
	if String(host.get("id", "")).is_empty():
		return
	# 冷却 / 能量预检查：冷却中或能量不足时不显示可释放遮罩，仅提示
	if cooldowns.get(skill_actions[index], 0.0) > 0.0:
		hud.set_message("【%s】冷却中 %.2f秒" % [host.get("name", "技能"), cooldowns[skill_actions[index]]])
		return
	var cost := float(host.get("energy_cost", 20))
	if player.energy < cost:
		hud.set_message("【%s】能量不足！" % host.get("name", "技能"))
		return
	var info := combat._compute_preview(index)
	if not info.get("valid", false):
		return
	_preview_index = index
	_preview_uses_mouse = info.get("uses_mouse", true)
	_preview_radius = info.get("radius", 0.0)
	_preview_is_directional = info.get("directional", false)
	_preview_node = combat._make_preview_visual(_preview_radius, info.get("color", Color(0.3, 0.8, 1.0, 0.45)))
	_update_skill_preview()

func _update_skill_preview() -> void:
	if _preview_node == null or not is_instance_valid(_preview_node) or _preview_index < 0:
		return
	var anchor := player.global_position
	if _preview_uses_mouse:
		anchor = get_global_mouse_position()
	_preview_node.global_position = anchor
	if _preview_is_directional:
		var mouse := get_global_mouse_position()
		var line := _preview_node.get_node_or_null("AimLine") as Line2D
		if line != null:
			line.visible = true
			line.clear_points()
			line.add_point(Vector2.ZERO)
			var dir := mouse - anchor
			if dir.length() > 1.0:
				dir = dir.normalized() * 220.0
			else:
				dir = Vector2(220.0, 0.0)
			line.add_point(dir)

func _release_skill(index: int) -> void:
	_cast_skill(index)
	_cancel_skill_preview()

func _cancel_skill_preview() -> void:
	if _preview_node != null and is_instance_valid(_preview_node):
		_preview_node.queue_free()
	_preview_node = null
	_preview_index = -1
	_preview_radius = 0.0
	_preview_is_directional = false

func _cancel_skill_preview_if(index: int) -> void:
	if _preview_index == index:
		_cancel_skill_preview()

# ============================================================
# 战斗系统（委托 CombatSystem）
# ============================================================
func _process_attack(delta: float) -> void: combat._process_attack(delta)
func _cast_skill(index: int) -> void: combat._cast_skill(index)
func _skill_aoe_self(dmg: float, skill: Dictionary) -> void: combat._skill_aoe_self(dmg, skill)
func _skill_aoe_ground(pos: Vector2, dmg: float, skill: Dictionary) -> void: combat._skill_aoe_ground(pos, dmg, skill)
func _skill_dash(mouse_pos: Vector2, dmg: float, skill: Dictionary) -> void: combat._skill_dash(mouse_pos, dmg, skill)
func _skill_projectile(mouse_pos: Vector2, dmg: float, skill: Dictionary) -> void: combat._skill_projectile(mouse_pos, dmg, skill)
func _deal_to_enemy(enemy: Enemy, dmg: float, effects: Dictionary, from_pos: Vector2) -> void: combat._deal_to_enemy(enemy, dmg, effects, from_pos)
func _spawn_ground_effect(pos: Vector2, radius: float, dmg: float, skill: Dictionary) -> void: combat._spawn_ground_effect(pos, radius, dmg, skill)
func _skill_summon(_dmg: float, skill: Dictionary) -> void: combat._skill_summon(_dmg, skill)
func _show_aoe_indicator(pos: Vector2, radius: float, color: Color) -> void: combat._show_aoe_indicator(pos, radius, color)
func _refund_if_multi_hit(hit_count: int) -> void: combat._refund_if_multi_hit(hit_count)
func _summon_at(world_pos: Vector2) -> Summon: return combat._summon_at(world_pos)
func _enemy_at(world_pos: Vector2) -> Enemy: return combat._enemy_at(world_pos)
func _select(s: Summon) -> void: combat._select(s)
func _clear_selection() -> void: combat._clear_selection()
func _spawn_summon() -> void: combat._spawn_summon()
func _remove_summon(s: Summon) -> void: combat._remove_summon(s)
func _update_hud() -> void: combat._update_hud()

# ============================================================
# 世界系统（委托 WorldSystem）
# ============================================================
func _try_merchant_interact() -> bool: return world._try_merchant_interact()
func _open_merchant_trade(merchant: MerchantNPC) -> void: world._open_merchant_trade(merchant)
func _do_upgrade(merchant: MerchantNPC, idx: int) -> void: world._do_upgrade(merchant, idx)
func _do_delete(merchant: MerchantNPC, idx: int) -> void: world._do_delete(merchant, idx)
func _merchant_buy(merchant: MerchantNPC, idx: int) -> void: world._merchant_buy(merchant, idx)
func _init_world_enemies() -> void: world._init_world_enemies()
func _init_central_boss() -> void: world._init_central_boss()
func _spawn_world_enemy(behavior: int, enemy_type: int, pos: Vector2) -> void: world._spawn_world_enemy(behavior, enemy_type, pos)
func _create_enemy(behavior: int, enemy_type: int, pos: Vector2) -> Enemy: return world._create_enemy(behavior, enemy_type, pos)
func _random_enemy_behavior() -> int: return world._random_enemy_behavior()
func _random_map_pos() -> Vector2: return world._random_map_pos()
func _set_enemy_texture(enemy: Enemy) -> void: world._set_enemy_texture(enemy)
func _set_enemy_size(enemy: Enemy) -> void: world._set_enemy_size(enemy)
func _set_enemy_stats(enemy: Enemy) -> void: world._set_enemy_stats(enemy)
func _process_enemy_attacks(delta: float) -> void: world._process_enemy_attacks(delta)
func _process_enemy_detection() -> void: world._process_enemy_detection()
func _process_respawns(delta: float) -> void: world._process_respawns(delta)
func _handle_player_death() -> void:
	# 被动：重生（优先于常规死亡结算，无金币惩罚）
	var pc := get_passive_combat()
	if pc.get("reincarnate", 0) > 0 and player.reincarnate_charges > 0:
		player.reincarnate_charges -= 1
		player.hp = player.max_hp_calc() * 0.6
		player.shield = 0.0
		player_invuln = 3.0
		_is_dead = false
		hud.set_message("重生！恢复60%生命。")
		return
	# M3：玩家死亡 = 复活 + 计数，而非直接 game over
	var res := survival.register_death()
	if res == "lose":
		return  # 失败结算由 survival 触发
	# 复活惩罚：损失 30% 金币，全部技能进入 5 秒统一冷却，回到出生点并短暂无敌
	var penalty := int(gold * 0.3)
	gold -= penalty
	for k in skill_actions:
		cooldowns[k] = 5.0
	player.hp = player.max_hp_calc()
	player.position = Vector2(MAP_CENTER.x, MAP_CENTER.y + 180)
	player_invuln = 3.0
	_is_dead = false
	hud.set_message("你阵亡了！损失 %d 金币，复活继续（死亡 %d / %d）" % [penalty, survival.deaths, survival.DEATH_LIMIT])

func _show_settlement(res: String) -> void:
	var win := res == "win"
	var elapsed := survival.SURVIVAL_TIME - survival.time_remaining
	hud.show_settlement(win, {
		"kills": kills,
		"bosses": survival.bosses_killed,
		"boss_quota": survival.BOSS_QUOTA,
		"deaths": survival.deaths,
		"death_limit": survival.DEATH_LIMIT,
		"time_used": elapsed,
		"time_total": survival.SURVIVAL_TIME,
		"level": player.level,
		"gold": gold,
		"hp_pct": player.hp / maxf(player.max_hp_calc(), 1.0)
	})
	get_tree().paused = true

func _on_enemy_killed(enemy: Enemy) -> void: world._on_enemy_killed(enemy)
func _spawn_drop(enemy: Enemy) -> void: world._spawn_drop(enemy)
func _apply_luck_quality(item: Dictionary) -> void: world._apply_luck_quality(item)
func _process_merchants(_delta: float) -> void: world._process_merchants(_delta)
func _init_ancient_idols() -> void: world._init_ancient_idols()
func _try_idol_interact() -> bool: return world._try_idol_interact()
func _accept_idol(idol: AncientIdol) -> void: world._accept_idol(idol)
func _spawn_merchant() -> void: world._spawn_merchant()

# ============================================================
# 库存系统（委托 InventorySystem）
# ============================================================
func _init_slots() -> void: inventory._init_slots()
func _connect_hud() -> void: inventory._connect_hud()
func _handle_drag(from_area: String, from_index: int, to_area: String, to_index: int) -> void: inventory._handle_drag(from_area, from_index, to_area, to_index)
func _drop_equipment_to_ground(eq_index: int) -> void: inventory._drop_equipment_to_ground(eq_index)
func _on_equipment_clicked(area: String, index: int) -> void: inventory._on_equipment_clicked(area, index)
func _equip_skill_from_warehouse(wh_idx: int, target_idx: int, area: String) -> void: inventory._equip_skill_from_warehouse(wh_idx, target_idx, area)
func _equip_equipment_from_warehouse(wh_idx: int, eq_idx: int) -> void: inventory._equip_equipment_from_warehouse(wh_idx, eq_idx)
func _unequip_to_warehouse(eq_idx: int, wh_idx: int) -> void: inventory._unequip_to_warehouse(eq_idx, wh_idx)
func _try_pickup() -> void: inventory._try_pickup()
func _first_empty_warehouse() -> int: return inventory._first_empty_warehouse()
func _refresh_hud_slots() -> void: inventory._refresh_hud_slots()
func allocate_stat(stat: String) -> bool:
	var ok := player.allocate_stat(stat)
	if ok:
		_refresh_hud_slots()  # vit 影响 max_hp，刷新血条
	return ok

func _has_equip(id: String) -> bool:
	for eq in equipment_slots:
		if String(eq.get("id", "")) == id:
			return true
	return false

# 已学技能查询（主动槽 + 增益槽，共 18 槽）
func _is_skill_learned(id: String) -> bool:
	return _learned_skill_index(id)[1] >= 0

func _learned_skill_index(id: String) -> Array:  # 返回 [area, idx]
	for i in range(ACTIVE_SLOT_COUNT):
		if String(skill_slots[i].get("id", "")) == id:
			return ["skill", i]
	for i in range(augment_slots.size()):
		for j in range(2):
			var a: Variant = augment_slots[i][j]
			if typeof(a) == TYPE_DICTIONARY and String(a.get("id", "")) == id:
				return ["aug%d" % j, i]
	return ["", -1]

# 同一技能不能在任何槽（主动/被动/增益）重复出现
func _skill_id_exists(id: String) -> bool:
	return _is_skill_learned(id)

# 通过 [area, idx] 取槽内技能字典引用（aug0/aug1 = 融合增益槽）
func _slot_ref(area: String, idx: int) -> Dictionary:
	match area:
		"skill": return skill_slots[idx]
		"aug0": return augment_slots[idx][0] if typeof(augment_slots[idx][0]) == TYPE_DICTIONARY else {}
		"aug1": return augment_slots[idx][1] if typeof(augment_slots[idx][1]) == TYPE_DICTIONARY else {}
	return {}

# 吃掉已学技能 → 升级（等级+1，品质提升一阶，数值成长）
func _upgrade_skill_from_pickup(area: String, idx: int) -> void:
	var s: Dictionary = _slot_ref(area, idx)
	if s.is_empty():
		return
	var lvl: int = int(s.get("level", 1)) + 1
	s["level"] = lvl
	var q := String(s.get("quality", "white"))
	if q == "white":
		s["quality"] = "blue"
	elif q == "blue":
		s["quality"] = "purple"
	elif q == "purple":
		s["quality"] = "legendary"
	var dmg: float = float(s.get("damage", 0)) * 1.15
	s["damage"] = dmg
	if area == "skill":
		hud.flash_skill_slot(idx, "Lv.%d" % lvl)
	else:
		hud.set_message("增益【%s】升级 Lv.%d" % [s.get("name", "技能"), lvl])

# ============================================================
# 技能冷却
# ============================================================
func _process_cooldowns(delta: float) -> void:
	var keys := cooldowns.keys()
	for k in keys:
		cooldowns[k] = maxf(cooldowns[k] - delta, 0.0)

# 技能联动：统计主动技能子类型
func _get_synergy_bonuses() -> Dictionary:
	var counts := {"aoe_self": 0, "aoe_ground": 0, "dash": 0, "projectile": 0}
	for item in skill_slots:
		if String(item.get("cast_type", "")) == "active":
			var st: String = String(item.get("subtype", ""))
			if counts.has(st):
				counts[st] += 1
	return counts

func _apply_synergy_to_cd(skill_data: Dictionary) -> float:
	var st: String = String(skill_data.get("subtype", ""))
	var bonuses := _get_synergy_bonuses()
	var count: int = int(bonuses.get(st, 0))
	if count >= 2:
		match st:
			"aoe_self": return 0.80
			"aoe_ground": return 1.0
			"dash": return 1.0
			"projectile": return 1.0
	return 1.0

func _has_equipment(equip_id: String) -> bool:
	for eq in equipment_slots:
		if String(eq.get("id", "")) == equip_id:
			return true
	return false

func get_player() -> Player:
	return player

# ============================================================
# 摄像机跟随
# ============================================================
func _init_camera() -> void:
	_camera = Camera2D.new()
	_camera.zoom = Vector2(0.9, 0.9)  # 拉近视角，单位更可读（仍只显示地图局部，保留探索感）
	_camera.position_smoothing_enabled = true
	_camera.position_smoothing_speed = 8.0
	add_child(_camera)
	_camera.make_current()

func _owned_ids() -> Array:
	var ids: Array = []
	for item in skill_slots:
		var item_id := String(item.get("id", ""))
		if not item_id.is_empty():
			ids.append(item_id)
	for item in equipment_slots:
		var item_id := String(item.get("id", ""))
		if not item_id.is_empty():
			ids.append(item_id)
	for item in warehouse_slots:
		var item_id := String(item.get("id", ""))
		if not item_id.is_empty():
			ids.append(item_id)
	return ids

# ============================================================
# 靠近显示掉落名
# ============================================================
func _process_drop_proximity(_delta: float) -> void:
	# skill_drop.gd 自己处理了距离显示
	pass

# ============================================================
# 工具函数
# ============================================================
func _find_nearest_enemy() -> Enemy:
	var best: Enemy = null
	var best_dist := 99999.0
	for enemy in enemies_root.get_children():
		if enemy is Enemy and not enemy.is_dead():
			var dist := player.global_position.distance_squared_to(enemy.global_position)
			if dist < best_dist:
				best_dist = dist
				best = enemy
	return best

func _empty_array(count: int) -> Array:
	var arr: Array = []
	for i in range(count):
		arr.append({})
	return arr

func _is_empty(item: Dictionary) -> bool:
	return String(item.get("id", "")).is_empty()

func _slots_for(area: String) -> Array:
	match area:
		"skill": return skill_slots
		"equipment": return equipment_slots
		"warehouse": return warehouse_slots
		"aug0", "aug1":
			# 增益槽列快照（只读用途：拖拽边界与 id 检查）
			var j := 0 if area == "aug0" else 1
			var out: Array = []
			for pair in augment_slots:
				var a: Variant = pair[j]
				out.append(a if typeof(a) == TYPE_DICTIONARY else {})
			return out
	return []

func _random_skill_by_type(cast_type: String) -> String:
	var pool: Array[String] = []
	for id in GameData.get_skill_id_list():
		var s := GameData.get_skill(id)
		if String(s.get("cast_type", "")) == cast_type:
			pool.append(id)
	if pool.is_empty():
		return ""
	return pool[randi() % pool.size()]

func _random_skill_by_subtypes(subtypes: Array) -> String:
	var pool: Array[String] = []
	for id in GameData.get_skill_id_list():
		var s := GameData.get_skill(id)
		if subtypes.has(String(s.get("subtype", ""))):
			pool.append(id)
	if pool.is_empty():
		return ""
	return pool[randi() % pool.size()]

# 按施法方式随机抽技能（"aura" = 全部光环/被动，供掉落池使用）
func _random_skill_by_cast_mode(cast_mode: String) -> String:
	var pool: Array[String] = []
	for id in GameData.get_skill_id_list():
		var s := GameData.get_skill(id)
		if String(s.get("cast_mode", "")) == cast_mode:
			pool.append(id)
	if pool.is_empty():
		return ""
	return pool[randi() % pool.size()]

# ============================================================
# 技能特效辅助函数（P0：手感三件套 — 弹道线 / 伤害数字 / Hitstop）
# ============================================================
func _get_nearest_enemies_in_dir(dir: Vector2, count: int, max_dist: float) -> Array:
	var candidates: Array = []
	for enemy in enemies_root.get_children():
		if enemy is Enemy and not enemy.is_dead():
			var rel: Vector2 = enemy.global_position - player.global_position
			if rel.dot(dir) > 0 and rel.length() < max_dist:
				candidates.append(enemy)
	candidates.sort_custom(func(a: Enemy, b: Enemy):
		return player.global_position.distance_squared_to(a.global_position) < player.global_position.distance_squared_to(b.global_position))
	return candidates.slice(0, count)

func _spawn_persistent_damage(pos: Vector2, radius: float, damage_per_tick: float, duration: float, interval: float) -> void:
	var zone := Node2D.new()
	zone.position = pos
	add_child(zone)

	var sprite := Sprite2D.new()
	var tex := GradientTexture2D.new()
	tex.width = int(radius * 2)
	tex.height = int(radius * 2)
	tex.fill = GradientTexture2D.FILL_RADIAL
	var grad := Gradient.new()
	grad.colors = [Color(1, 0.25, 0.1, 0.25), Color(1, 0.25, 0.1, 0.0)]
	tex.gradient = grad
	sprite.texture = tex
	zone.add_child(sprite)

	var tick_count := int(duration / interval)
	for i in range(tick_count):
		var tw := create_tween()
		tw.tween_interval(interval)
		var d := damage_per_tick
		var r := radius
		tw.tween_callback(func():
			if not is_instance_valid(zone):
				return
			for enemy in enemies_root.get_children():
				if enemy is Enemy and not enemy.is_dead():
					if enemy.global_position.distance_to(zone.global_position) < r:
						enemy.take_damage(d, Vector2.ZERO, 0)
						if enemy.is_dead():
							_on_enemy_killed(enemy)
		)

	var fade := create_tween()
	fade.tween_interval(duration)
	fade.tween_property(zone, "modulate:a", 0.0, 0.3)
	fade.tween_callback(zone.queue_free)

func _get_cd_dict() -> Dictionary:
	var result := {}
	for i in range(ACTIVE_SLOT_COUNT):
		result[str(i)] = cooldowns.get(skill_actions[i], 0.0)
	return result

# 被动战斗键缓存（闪避/暴击/分裂/重生），由带 passive 标签的已装备技能聚合
var _passive_combat: Dictionary = {}
var _passive_dirty := true

func mark_passives_dirty() -> void:
	_passive_dirty = true

func get_passive_combat() -> Dictionary:
	if _passive_dirty:
		_recompute_passives()
	return _passive_combat

func _recompute_passives() -> void:
	var pc := {"evasion": 0.0, "crit_chance": 0.0, "crit_mult": 2.0, "cleave": 0.0, "reincarnate": 0}
	for i in range(skill_slots.size()):
		var item = skill_slots[i]
		if typeof(item) != TYPE_DICTIONARY or String(item.get("id","")).is_empty():
			continue
		if not ("passive" in item.get("tags", [])):
			continue
		_merge_passive(pc, item.get("effects", {}))
		if i < augment_slots.size():
			for a in augment_slots[i]:
				if typeof(a) == TYPE_DICTIONARY and not String(a.get("id","")).is_empty():
					_merge_passive(pc, a.get("effects", {}))
	if player != null and is_instance_valid(player):
		player.reincarnate_charges = int(pc["reincarnate"])
	_passive_combat = pc
	_passive_dirty = false

func _merge_passive(pc: Dictionary, fx: Dictionary) -> void:
	pc["evasion"] = maxf(pc["evasion"], float(fx.get("evasion", 0.0)))
	pc["crit_chance"] = maxf(pc["crit_chance"], float(fx.get("crit_chance", 0.0)))
	pc["crit_mult"] = maxf(pc["crit_mult"], float(fx.get("crit_mult", 2.0)))
	pc["cleave"] = maxf(pc["cleave"], float(fx.get("cleave", 0.0)))
	pc["reincarnate"] = maxi(pc["reincarnate"], int(fx.get("reincarnate", 0)))

func _get_skill_full_datas() -> Array:
	return skill_slots

func _show_attack_line(from: Vector2, to: Vector2) -> void:
	var line := Line2D.new()
	line.width = 2.5
	line.default_color = Color(1.0, 0.85, 0.3, 0.8)
	line.add_point(from - global_position)
	line.add_point(to - global_position)
	add_child(line)

	var tw := create_tween()
	tw.tween_property(line, "modulate:a", 0.0, 0.15)
	tw.tween_callback(line.queue_free)

func _spawn_damage_number(pos: Vector2, dmg: float, is_crit: bool = false) -> void:
	var label := Label.new()
	label.text = str(int(dmg))
	label.add_theme_font_size_override("font_size", 16 if not is_crit else 21)
	label.modulate = Color.YELLOW if not is_crit else Color.ORANGE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = Vector2(-20, -8)

	var node := Control.new()
	node.position = pos + Vector2(randf_range(-12, 12), randf_range(-20, -5))
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.add_child(label)
	add_child(node)

	var tw := create_tween().set_parallel(true)
	tw.tween_property(node, "position:y", node.position.y - 45, 0.7).set_ease(Tween.EASE_OUT)
	tw.tween_property(node, "modulate:a", 0.0, 0.55).set_delay(0.2)
	tw.tween_callback(node.queue_free).set_delay(0.75)

func _hitstop(duration: float) -> void:
	Engine.time_scale = 0.2
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = duration * 0.2
	timer.timeout.connect(func():
		Engine.time_scale = 1.0
		timer.queue_free()
	)
	add_child(timer)
	timer.start()
