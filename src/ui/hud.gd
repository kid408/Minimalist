extends CanvasLayer
class_name HUD

const GameData = preload("res://src/data/game_data.gd")
const LOGICAL_VIEWPORT_SIZE := Vector2(1440, 810)

var arena: Node = null

class Minimap:
	extends Control

	const _map_tex := preload("res://assets/Map.png")

	var _player_pos := Vector2.ZERO
	var _enemy_positions: Array = []
	var _merchant_positions: Array = []
	var _roads: Array = []
	var _camp_positions: Array = []
	var _boss_position := Vector2.ZERO
	var _world_size := Vector2(1280, 720)
	var _map_scale := 1.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(140, 100)
		queue_redraw()

	func update_data(player_pos: Vector2, enemies: Array, merchants: Array, world: Vector2, roads: Array = [], camps: Array = [], boss_pos: Vector2 = Vector2.ZERO) -> void:
		_player_pos = player_pos
		_enemy_positions = enemies.duplicate()
		_merchant_positions = merchants.duplicate()
		_roads = roads.duplicate()
		_camp_positions = camps.duplicate()
		_boss_position = boss_pos
		_world_size = world
		# 计算缩放：让地图适配 minimap 尺寸
		var map_w: float = size.x - 6
		var map_h: float = size.y - 6
		_map_scale = minf(map_w / maxf(world.x, 1.0), map_h / maxf(world.y, 1.0))
		queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2(3, 3), size - Vector2(6, 6))
		# 背景：与主地图使用同一张 Map.png（按世界尺寸等比适配，左上对齐，与下方点阵坐标一致）
		draw_rect(r, Color(0.02, 0.03, 0.06, 0.85), true)
		var bg_rect := Rect2(r.position, _world_size * _map_scale)
		draw_texture_rect(_map_tex, bg_rect, false)
		draw_rect(r, Color(0.3, 0.4, 0.55, 0.7), false, 1)

		# 坐标转换
		var offset := r.position
		var sc := _map_scale

		# 世界道路、精英营和 Boss 区：保持与主地图相同的探索方向感。
		for road in _roads:
			var mini_road := PackedVector2Array()
			for world_point in road:
				mini_road.append(offset + Vector2(world_point.x * sc, world_point.y * sc))
			if mini_road.size() >= 2:
				draw_polyline(mini_road, Color(0.72, 0.59, 0.30, 0.82), 1.2, true)
		for camp_pos in _camp_positions:
			var camp_point := offset + Vector2(camp_pos.x * sc, camp_pos.y * sc)
			if r.has_point(camp_point):
				draw_circle(camp_point, 1.8, Color(1.0, 0.72, 0.20, 0.9))
		var boss_point := offset + Vector2(_boss_position.x * sc, _boss_position.y * sc)
		if _boss_position != Vector2.ZERO and r.has_point(boss_point):
			draw_circle(boss_point, 3.2, Color(0.84, 0.25, 0.72, 0.95))
			draw_arc(boss_point, 4.4, 0.0, TAU, 20, Color(1.0, 0.68, 0.92, 0.9), 1.0, true)

		# 敌人（红色小点）
		for pos in _enemy_positions:
			var p: Vector2 = offset + Vector2(pos.x * sc, pos.y * sc)
			if r.has_point(p):
				draw_circle(p, 2.0, Color(1, 0.3, 0.2, 0.8))

		# 商人（金色小点）
		for pos in _merchant_positions:
			var p: Vector2 = offset + Vector2(pos.x * sc, pos.y * sc)
			if r.has_point(p):
				draw_circle(p, 2.5, Color(1, 0.8, 0.3, 0.9))

		# 玩家（蓝色亮点）
		var pp: Vector2 = offset + Vector2(_player_pos.x * sc, _player_pos.y * sc)
		if r.has_point(pp):
			draw_circle(pp, 3.0, Color(0.3, 0.7, 1.0, 1.0))
			draw_circle(pp, 3.5, Color(1, 1, 1, 0.4))


class GroundDropZone:
	extends Panel

	signal equipment_dropped(from_area: String, from_index: int)

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _can_drop_data(_pos: Vector2, data: Variant) -> bool:
		if typeof(data) != TYPE_DICTIONARY:
			return false
		var from_area := String(data.get("from_area", ""))
		return from_area == "equipment" or from_area == "warehouse"

	func _drop_data(_pos: Vector2, data: Variant) -> void:
		equipment_dropped.emit(String(data.get("from_area", "")), int(data.get("from_index", -1)))

class InventorySlot:
	extends Panel

	signal slot_drag_requested(from_area: String, from_index: int, to_area: String, to_index: int)
	signal slot_clicked(area: String, index: int)
	signal slot_discard_requested(area: String, index: int)

	var area := ""
	var index := -1
	var item: Dictionary = {}
	var draggable := false
	var slot_label: Label
	var icon_rect: TextureRect
	var cd_label: Label
	var cd_value: float = 0.0
	var tip_text := ""
	var _energy_ok: bool = true

	func setup(slot_area: String, idx: int, slot_title: String, item_data: Dictionary, can_drag: bool, mode: String = "full") -> void:
		area = slot_area
		index = idx
		item = item_data.duplicate(true)
		draggable = can_drag
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_DRAG if (can_drag and not _empty()) else Control.CURSOR_POINTING_HAND

		for child in get_children():
			child.queue_free()

		match mode:
			"host":
				_setup_host(idx)
			"mini":
				_setup_mini()
			_:
				_setup_full(slot_area, idx, slot_title)
		tooltip_text = tip_text

	# 融合单元主技能槽（76×48：键位 + 大图标 + CD/等级）
	func _setup_host(idx2: int) -> void:
		custom_minimum_size = Vector2(76, 48)
		var keys := ["1", "2", "3", "4", "5", "6"]
		slot_label = Label.new()
		slot_label.position = Vector2(4, 2)
		slot_label.size = Vector2(40, 12)
		slot_label.text = keys[idx2] if idx2 < keys.size() else str(idx2)
		slot_label.add_theme_font_size_override("font_size", 10)
		slot_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(slot_label)

		icon_rect = TextureRect.new()
		icon_rect.position = Vector2(23, 14)
		icon_rect.custom_minimum_size = Vector2(30, 30)
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(icon_rect)

		cd_label = Label.new()
		cd_label.position = Vector2(4, 18)
		cd_label.size = Vector2(68, 14)
		cd_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cd_label.add_theme_font_size_override("font_size", 11)
		cd_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cd_label.visible = false
		add_child(cd_label)

		var lvl := int(item.get("level", 1))
		if lvl > 1:
			var lvl_label := Label.new()
			lvl_label.position = Vector2(42, 2)
			lvl_label.size = Vector2(32, 12)
			lvl_label.text = "Lv.%d" % lvl
			lvl_label.add_theme_font_size_override("font_size", 9)
			lvl_label.modulate = Color(1.0, 0.9, 0.3)
			lvl_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(lvl_label)

		if _empty():
			slot_label.modulate = Color(0.5, 0.5, 0.5)
			tip_text = "空主技能槽：从仓库拖入技能"
		else:
			icon_rect.texture = _load_icon(String(item.get("icon", "")))
			tip_text = _build_tooltip()

	# 融合单元增益槽（76×22：小图标 + 名字）
	func _setup_mini() -> void:
		custom_minimum_size = Vector2(76, 22)
		icon_rect = TextureRect.new()
		icon_rect.position = Vector2(3, 2)
		icon_rect.custom_minimum_size = Vector2(18, 18)
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(icon_rect)

		slot_label = Label.new()
		slot_label.position = Vector2(25, 3)
		slot_label.size = Vector2(48, 16)
		slot_label.add_theme_font_size_override("font_size", 9)
		slot_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(slot_label)

		cd_label = Label.new()
		cd_label.visible = false
		add_child(cd_label)

		if _empty():
			slot_label.text = "+ 增益"
			slot_label.modulate = Color(0.5, 0.5, 0.5)
			tip_text = "增益槽：拖入任意技能，其效果×0.5 并入主技能"
		else:
			icon_rect.texture = _load_icon(String(item.get("icon", "")))
			var lvl := int(item.get("level", 1))
			slot_label.text = String(item.get("name", "")) + ((" Lv.%d" % lvl) if lvl > 1 else "")
			tip_text = "【增益 ×0.5】\n" + _build_tooltip()

	# 通用大槽（72×72：仓库/装备/被动）
	func _setup_full(slot_area: String, idx: int, slot_title: String) -> void:
		custom_minimum_size = Vector2(72, 72)
		var key_text := ""
		match slot_area:
			"skill": key_text = ["1", "2", "3", "4", "5", "6"][idx]
			"equipment": key_text = "E%d" % (idx + 1)
			"warehouse": key_text = "%d" % (idx + 1)

		slot_label = Label.new()
		slot_label.position = Vector2(4, 4)
		slot_label.size = Vector2(64, 16)
		slot_label.text = "%s %s" % [key_text, slot_title]
		slot_label.add_theme_font_size_override("font_size", 11)
		slot_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(slot_label)

		icon_rect = TextureRect.new()
		icon_rect.position = Vector2(8, 20)
		icon_rect.custom_minimum_size = Vector2(34, 34)
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(icon_rect)

		cd_label = Label.new()
		cd_label.position = Vector2(4, 52)
		cd_label.size = Vector2(64, 16)
		cd_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cd_label.add_theme_font_size_override("font_size", 10)
		cd_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cd_label.visible = false
		add_child(cd_label)

		# 等级标签（吃掉技能升级后显示）
		var lvl := int(item.get("level", 1))
		if lvl > 1:
			var lvl_label := Label.new()
			lvl_label.position = Vector2(42, 4)
			lvl_label.size = Vector2(28, 14)
			lvl_label.text = "Lv.%d" % lvl
			lvl_label.add_theme_font_size_override("font_size", 10)
			lvl_label.modulate = Color(1.0, 0.9, 0.3)
			lvl_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(lvl_label)

		# 类型标签
		var type_label := Label.new()
		type_label.position = Vector2(6, 36)
		type_label.size = Vector2(60, 14)
		type_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		type_label.add_theme_font_size_override("font_size", 9)
		type_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

		# tooltip
		if _empty():
			slot_label.modulate = Color(0.5, 0.5, 0.5)
			tip_text = ""
		else:
			icon_rect.texture = _load_icon(String(item.get("icon", "")))
			tip_text = _build_tooltip()
			var cast_type := String(item.get("cast_type", ""))
			if area == "equipment":
				type_label.text = "装备"
				type_label.modulate = Color(1, 0.8, 0.25)
			elif cast_type == "active":
				type_label.text = "主动"
				type_label.modulate = Color(1, 0.4, 0.3)
			elif cast_type == "passive":
				type_label.text = "被动"
				type_label.modulate = Color(0.5, 0.9, 0.6)
			elif area == "warehouse":
				type_label.text = "物品"
				type_label.modulate = Color(0.7, 0.6, 0.9)
		add_child(type_label)

		tooltip_text = tip_text

	func _build_tooltip() -> String:
		var parts: Array[String] = []
		parts.append(item.get("name", "物品"))
		var quality := String(item.get("quality", "white"))
		parts.append("品质：%s" % quality)

		var cast_type := String(item.get("cast_type", ""))
		if cast_type == "active":
			var mode := String(item.get("cast_mode", "instant"))
			parts.append("类型：%s · %s" % [_cast_mode_label(mode), _subtype_label(String(item.get("subtype", "")))])
			if float(item.get("damage", 0)) > 0.0:
				parts.append("伤害：%.0f" % float(item.get("damage", 0)))
			if mode == "channel":
				parts.append("引导：%.1fs（每 %.1fs 结算，移动打断）" % [float(item.get("duration", 0)), float(item.get("tick_interval", 0.5))])
			var fx: Dictionary = item.get("effects", {})
			if mode == "toggle" and fx.has("toggle_cost"):
				parts.append("开启消耗：%.0f 能量/秒" % float(fx.get("toggle_cost", 0)))
			if mode == "aura":
				parts.append("常驻效果：%s +%s" % [_aura_stat_label(String(fx.get("aura_stat", ""))), str(fx.get("aura_value", 0))])
			else:
				parts.append("能量消耗：%.0f" % float(item.get("energy_cost", 0)))
				parts.append("冷却：%.1fs" % float(item.get("cooldown", 0)))
		elif cast_type == "passive":
			parts.append("类型：被动（放入技能槽即常驻生效）")
		else:
			# 装备
			parts.append("类型：装备")
			parts.append("效果：%s" % item.get("effect_description", item.get("description", "")))
			var bonuses: Dictionary = item.get("stat_bonuses", {})
			if not bonuses.is_empty():
				var stats: Array[String] = []
				for k in ["str", "agi", "int", "vit", "luk"]:
					var v := int(bonuses.get(k, 0))
					if v > 0:
						stats.append("%s+%d" % [{"str":"力","agi":"敏","int":"智","vit":"体","luk":"运"}[k], v])
				if not stats.is_empty():
					parts.append("属性加成：%s" % " ".join(stats))

		parts.append(item.get("description", ""))
		return "\n".join(parts)

	func _subtype_label(st: String) -> String:
		match st:
			"aoe_self": return "自身环绕"
			"aoe_ground": return "点地范围"
			"ground": return "持续地形"
			"dash": return "方向突进"
			"projectile": return "锁定弹体"
			"summon": return "召唤物"
			"heal": return "治疗"
			"buff": return "增益"
			"target": return "单体指定"
			"channel": return "持续引导"
			"aura": return "常驻光环"
			"toggle": return "开关形态"
		return st

	# 六大施法方式
	func _cast_mode_label(mode: String) -> String:
		match mode:
			"instant": return "瞬发"
			"point": return "点地"
			"unit_target": return "单体目标"
			"channel": return "引导"
			"aura": return "光环/被动"
			"toggle": return "开关"
		return mode

	func _aura_stat_label(stat: String) -> String:
		match stat:
			"damage_pct": return "全伤害"
			"attack_speed_pct": return "攻击速度"
			"move_speed_pct": return "移动速度"
			"lifesteal": return "吸血"
			"hp_regen": return "每秒回血"
			"damage_reduce": return "伤害减免"
		return stat

	func flash(text: String) -> void:
		var tw := create_tween().set_loops(4)
		tw.tween_property(self, "modulate", Color(1.0, 0.85, 0.2), 0.16)
		tw.tween_property(self, "modulate", Color(1.0, 1.0, 1.0), 0.16)
		if not text.is_empty():
			await get_tree().create_timer(0.7).timeout
			if is_instance_valid(self):
				var fl := Label.new()
				fl.text = text
				fl.add_theme_font_size_override("font_size", 13)
				fl.position = Vector2(0, -20)
				fl.modulate = Color(1.0, 0.9, 0.3)
				fl.mouse_filter = Control.MOUSE_FILTER_IGNORE
				add_child(fl)
				var tw2 := create_tween()
				tw2.tween_property(fl, "position:y", -42, 0.8)
				tw2.parallel().tween_property(fl, "modulate:a", 0.0, 0.8)
				tw2.tween_callback(fl.queue_free)

	func set_cd(time: float) -> void:
		cd_value = time
		if time > 0.05:
			cd_label.visible = true
			cd_label.text = "%.2f" % time
			cd_label.modulate = Color(1, 0.5, 0.3)
		else:
			cd_label.visible = false

	var _color: Color = Color(0.15, 0.18, 0.22, 0.94)
	var _hovered := false

	func _draw() -> void:
		var style := StyleBoxFlat.new()
		var bg_color := _slot_bg_color()
		style.bg_color = bg_color if not _hovered else bg_color.lightened(0.18)
		var border_color := _slot_border_color()
		style.border_color = border_color
		style.border_width_left = 2
		style.border_width_top = 2
		style.border_width_right = 2
		style.border_width_bottom = 2
		style.corner_radius_top_left = 8
		style.corner_radius_top_right = 8
		style.corner_radius_bottom_right = 8
		style.corner_radius_bottom_left = 8
		draw_style_box(style, Rect2(Vector2.ZERO, size))

		# CD 遮罩（主动 / 被动 自动释放都显示冷却）
		if cd_value > 0.05 and area == "skill":
			var overlay := StyleBoxFlat.new()
			overlay.bg_color = Color(0, 0, 0, 0.45)
			overlay.corner_radius_top_left = 8
			overlay.corner_radius_top_right = 8
			overlay.corner_radius_bottom_right = 8
			overlay.corner_radius_bottom_left = 8
			draw_style_box(overlay, Rect2(Vector2.ZERO, size))
		# 能量不足遮罩
		elif not _energy_ok and area == "skill" and not _empty() and cd_value < 0.05:
			var overlay := StyleBoxFlat.new()
			overlay.bg_color = Color(0.3, 0.25, 0.05, 0.45)
			overlay.corner_radius_top_left = 8
			overlay.corner_radius_top_right = 8
			overlay.corner_radius_bottom_right = 8
			overlay.corner_radius_bottom_left = 8
			draw_style_box(overlay, Rect2(Vector2.ZERO, size))

	func _slot_bg_color() -> Color:
		if _empty():
			return Color(0.08, 0.10, 0.14, 0.85)
		var cast_type := String(item.get("cast_type", ""))
		match area:
			"skill":
				return Color(0.24, 0.08, 0.06, 0.96)
			"aug0", "aug1":
				return Color(0.16, 0.08, 0.24, 0.96)
			"equipment":
				return Color(0.22, 0.16, 0.04, 0.96)
		return Color(0.12, 0.10, 0.20, 0.96)

	func _slot_border_color() -> Color:
		if _empty():
			return Color(0.22, 0.26, 0.34, 0.5)
		var cast_type := String(item.get("cast_type", ""))
		match area:
			"skill":
				return Color(1.0, 0.30, 0.22, 1.0)
			"aug0", "aug1":
				return Color(0.72, 0.42, 1.0, 1.0)
			"equipment":
				return Color(1.0, 0.72, 0.18, 1.0)
		return Color(0.60, 0.50, 0.90, 1.0)

	func _empty() -> bool:
		return String(item.get("id", "")).is_empty()

	func _load_icon(path: String) -> Texture2D:
		if path.is_empty():
			return null
		return load(path) as Texture2D

	func _get_drag_data(_pos: Vector2) -> Variant:
		if not draggable or _empty():
			return null
		var preview := Label.new()
		preview.text = String(item.get("name", "物品"))
		set_drag_preview(preview)
		return {"from_area": area, "from_index": index, "id": item.get("id", "")}

	func _can_drop_data(_pos: Vector2, data: Variant) -> bool:
		if typeof(data) != TYPE_DICTIONARY:
			return false
		var from_area := String(data.get("from_area", ""))
		var from_idx := int(data.get("from_index", -1))
		if from_area == area and from_idx == index:
			return false
		if area == "skill":
			return from_area == "warehouse" and not GameData.get_skill(String(data.get("id", ""))).is_empty()
		if area == "aug0" or area == "aug1":
			# 增益槽：任何技能都可作增益（双用）
			return from_area == "warehouse" and not GameData.get_skill(String(data.get("id", ""))).is_empty()
		if area == "equipment":
			return from_area == "warehouse"
		if area == "warehouse":
			return (from_area == "equipment" or from_area == "aug0" or from_area == "aug1") and _empty()
		return false

	func _drop_data(_pos: Vector2, data: Variant) -> void:
		var from_area := String(data.get("from_area", ""))
		var from_idx := int(data.get("from_index", -1))
		slot_drag_requested.emit(from_area, from_idx, area, index)

	# 左键=点击（修复此前未触发的问题）；右键=直接丢弃（免去拖到指定区）
	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_LEFT:
				slot_clicked.emit(area, index)
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				if (area == "warehouse" or area == "equipment") and not _empty():
					slot_discard_requested.emit(area, index)
			accept_event()


# —— 以下节点由 hud.tscn 场景提供，脚本只负责逻辑刷新 ——
@onready var hp_bar: ProgressBar = $TopLeft/HPBar
@onready var energy_bar: ProgressBar = $TopLeft/EnergyBar
@onready var hp_label: Label = $TopLeft/HPLabel
@onready var energy_label: Label = $TopLeft/EnergyLabel
@onready var gold_label: Label = $TopLeft/GoldLabel
@onready var stats_label: Label = $TopLeft/StatsLabel
@onready var message_label: Label = $MessageLabel
@onready var warehouse_grid: HBoxContainer = $WarehousePanel/WarehouseGrid
@onready var skill_grid: HBoxContainer = $SkillPanel/SkillGrid
@onready var equip_grid: HBoxContainer = $EquipPanel/EquipGrid
@onready var level_label: Label = $ProgPanel/LevelLabel
@onready var skill_point_label: Label = $ProgPanel/SkillPointLabel
@onready var xp_bar: ProgressBar = $ProgPanel/XPBar
@onready var recovery_label: Label = $RecoveryLabel
@onready var trade_panel: Panel = $TradePanel
@onready var trade_close_button: Button = $TradePanel/CloseBtn
@onready var skill_select_panel: Panel = $SkillSelectPanel
@onready var skill_select_close_button: Button = $SkillSelectPanel/CloseBtn
@onready var replace_panel: Panel = $ReplacePanel
@onready var replace_cancel_button: Button = $ReplacePanel/CancelBtn
@onready var ground_zone_placeholder: Control = $GroundZonePlaceholder
@onready var minimap_placeholder: Control = $MinimapPlaceholder
@onready var idol_popup: Panel = $IdolPopup
@onready var idol_accept_button: Button = $IdolPopup/AcceptBtn
@onready var idol_decline_button: Button = $IdolPopup/DeclineBtn

var ground_zone: Panel
var ground_label: Label
var minimap: Minimap
var trade_buttons: Array = []
var trade_labels: Array = []
var trade_callback: Callable
var skill_select_buttons: Array = []
var skill_select_callback: Callable
var replace_buttons: Array = []
var pending_pickup_item: Dictionary = {}
var replace_callback: Callable
var sell_callback: Callable
var _trade_close_callback: Callable
var _idol_decline_callback: Callable
var _modal_blocker: ColorRect
var _modal_paused := false
var _cache_skill_slots: Array = []
var _cache_cds: Dictionary = {}
var _cache_energy: float = 100.0

# ===== 属性分配面板（T 开关，消耗 skill_points 加点） =====
var attr_panel: Panel
var attr_point_label: Label
var attr_value_labels := {}
var attr_alloc_buttons := {}

# —— M3 生存目标条 / 结算界面（代码创建，不改动 .tscn） ——
var objective_panel: Panel
var obj_time: Label
var obj_boss: Label
var obj_death: Label
var obj_threat: Label
var settlement_panel: Panel
var obj_title: Label
var obj_rating: Label
var obj_stats: Label
var obj_hint: Label

func bind_arena(a: Node) -> void:
	arena = a

func has_modal() -> bool:
	return (trade_panel != null and trade_panel.visible) or (skill_select_panel != null and skill_select_panel.visible) or (replace_panel != null and replace_panel.visible) or (idol_popup != null and idol_popup.visible)

func is_pointer_over_interactive_ui() -> bool:
	var hovered := get_viewport().gui_get_hovered_control()
	return hovered != null and is_ancestor_of(hovered)

func dismiss_top_transient() -> bool:
	if settlement_panel != null and settlement_panel.visible:
		return false
	if replace_panel != null and replace_panel.visible:
		_close_replace_popup()
		return true
	if skill_select_panel != null and skill_select_panel.visible:
		_close_skill_select_popup()
		return true
	if idol_popup != null and idol_popup.visible:
		_close_idol_popup(true)
		return true
	if trade_panel != null and trade_panel.visible:
		_close_trade_panel(true)
		return true
	if attr_panel != null and attr_panel.visible:
		attr_panel.visible = false
		return true
	return false

func _input(event: InputEvent) -> void:
	if _modal_paused and event.is_action_pressed("ui_cancel") and dismiss_top_transient():
		get_viewport().set_input_as_handled()

func _build_modal_blocker() -> void:
	_modal_blocker = ColorRect.new()
	_modal_blocker.name = "ModalBlocker"
	_modal_blocker.color = Color(0.0, 0.0, 0.0, 0.42)
	_modal_blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	_modal_blocker.z_index = 4
	_modal_blocker.visible = false
	add_child(_modal_blocker)
	_refresh_modal_blocker_size()
	get_viewport().size_changed.connect(_refresh_modal_blocker_size)

func _logical_viewport_size() -> Vector2:
	var root_window := get_tree().root
	if root_window != null:
		var configured_size := Vector2(root_window.content_scale_size)
		if configured_size.x > 10.0 and configured_size.y > 10.0:
			return configured_size
	return LOGICAL_VIEWPORT_SIZE

func _refresh_modal_blocker_size() -> void:
	if _modal_blocker == null:
		return
	_modal_blocker.position = Vector2.ZERO
	_modal_blocker.size = _logical_viewport_size()

func _refresh_modal_state() -> void:
	var active := has_modal()
	if active and attr_panel != null:
		attr_panel.visible = false
	if _modal_blocker != null:
		_modal_blocker.visible = active
	if active == _modal_paused:
		return
	_modal_paused = active
	if active:
		get_tree().paused = true
	elif settlement_panel == null or not settlement_panel.visible:
		get_tree().paused = false

func _close_replace_popup() -> void:
	if replace_panel == null:
		return
	replace_panel.visible = false
	pending_pickup_item = {}
	replace_callback = Callable()
	sell_callback = Callable()
	_refresh_modal_state()

func _close_skill_select_popup() -> void:
	if skill_select_panel == null:
		return
	skill_select_panel.visible = false
	skill_select_callback = Callable()
	_refresh_modal_state()

func _close_idol_popup(invoke_decline: bool) -> void:
	if idol_popup == null:
		return
	var decline_callback := _idol_decline_callback
	_idol_decline_callback = Callable()
	idol_popup.visible = false
	_refresh_modal_state()
	if invoke_decline and decline_callback.is_valid():
		decline_callback.call()

func _clear_trade_dynamic_buttons() -> void:
	for child in trade_panel.get_children():
		if child is Button and child != trade_close_button and child not in trade_buttons:
			child.queue_free()

func _close_trade_panel(invoke_callback: bool) -> void:
	if trade_panel == null:
		return
	_close_replace_popup()
	_close_skill_select_popup()
	var close_callback := _trade_close_callback
	_trade_close_callback = Callable()
	trade_panel.visible = false
	_clear_trade_dynamic_buttons()
	_refresh_modal_state()
	if invoke_callback and close_callback.is_valid():
		close_callback.call()

func toggle_attribute_panel() -> void:
	if attr_panel == null:
		return
	attr_panel.visible = not attr_panel.visible
	if attr_panel.visible:
		_refresh_attribute_panel()

func _refresh_attribute_panel() -> void:
	if attr_panel == null or not attr_panel.visible or arena == null:
		return
	var p = arena.player
	var stats := ["str", "agi", "int", "vit", "luk"]
	var names := {"str": "力量", "agi": "敏捷", "int": "智力", "vit": "体质", "luk": "幸运"}
	attr_point_label.text = "可分配技能点：%d" % p.skill_points
	for st in stats:
		var lbl: Label = attr_value_labels.get(st)
		if lbl != null:
			lbl.text = "%s：%d" % [names.get(st, st), int(p.call("total_" + st))]
		var btn: Button = attr_alloc_buttons.get(st)
		if btn != null:
			btn.disabled = p.skill_points <= 0

func _attr_allocate(stat: String) -> void:
	if arena == null:
		return
	if arena.allocate_stat(stat):
		set_message("分配 1 点到【%s】" % stat)
		_refresh_attribute_panel()
	else:
		set_message("技能点不足，无法分配")

func _build_attribute_panel() -> void:
	attr_panel = Panel.new()
	attr_panel.position = Vector2(20, 285)
	attr_panel.size = Vector2(250, 330)
	attr_panel.z_index = 20
	attr_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	attr_panel.add_theme_stylebox_override("panel", _panel_bg(Color(0.07, 0.09, 0.14, 0.96), Color(0.4, 0.7, 1.0, 0.9)))
	attr_panel.visible = false
	add_child(attr_panel)

	var title := Label.new()
	title.position = Vector2(12, 8)
	title.size = Vector2(230, 22)
	title.text = "属性分配（T 开关）"
	title.add_theme_font_size_override("font_size", 14)
	title.modulate = Color(0.6, 0.85, 1.0)
	attr_panel.add_child(title)

	attr_point_label = Label.new()
	attr_point_label.position = Vector2(12, 34)
	attr_point_label.size = Vector2(226, 20)
	attr_point_label.add_theme_font_size_override("font_size", 13)
	attr_point_label.text = "可分配技能点：0"
	attr_panel.add_child(attr_point_label)

	var stats := ["str", "agi", "int", "vit", "luk"]
	var names := {"str": "力量", "agi": "敏捷", "int": "智力", "vit": "体质", "luk": "幸运"}
	for i in range(stats.size()):
		var st: String = stats[i]
		var row := HBoxContainer.new()
		row.position = Vector2(12, 60 + i * 34)
		row.size = Vector2(226, 30)
		attr_panel.add_child(row)

		var lbl := Label.new()
		lbl.size = Vector2(110, 28)
		lbl.add_theme_font_size_override("font_size", 13)
		row.add_child(lbl)
		attr_value_labels[st] = lbl

		var btn := Button.new()
		btn.text = "+"
		btn.size = Vector2(40, 28)
		btn.pressed.connect(func(): _attr_allocate(st))
		row.add_child(btn)
		attr_alloc_buttons[st] = btn

	var reset_btn := Button.new()
	reset_btn.position = Vector2(12, 60 + stats.size() * 34 + 6)
	reset_btn.size = Vector2(110, 28)
	reset_btn.text = "重置加点"
	reset_btn.pressed.connect(func():
		if arena != null:
			var back: int = arena.player.reset_allocated()
			if back > 0:
				set_message("已重置 %d 点" % back)
			_refresh_attribute_panel()
	)
	attr_panel.add_child(reset_btn)

	var close_btn := Button.new()
	close_btn.position = Vector2(140, 60 + stats.size() * 34 + 6)
	close_btn.size = Vector2(98, 28)
	close_btn.text = "关闭"
	close_btn.pressed.connect(func(): attr_panel.visible = false)
	attr_panel.add_child(close_btn)

func _ready() -> void:
	# 模态打开时世界暂停，HUD 必须继续接收按钮和 Esc 输入。
	process_mode = Node.PROCESS_MODE_ALWAYS
	trade_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	skill_select_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	replace_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	idol_popup.mouse_filter = Control.MOUSE_FILTER_STOP
	_build_modal_blocker()

	# 节点树由 hud.tscn 提供，这里仅做逻辑连接与动态内容生成。
	# 小地图：内部类实例挂载到场景占位节点
	minimap = Minimap.new()
	minimap.size = minimap_placeholder.size
	minimap_placeholder.add_child(minimap)

	# 丢弃区：内部类实例挂载到场景占位节点
	ground_zone = GroundDropZone.new()
	ground_zone.position = Vector2.ZERO
	ground_zone.size = ground_zone_placeholder.size
	ground_zone.add_theme_stylebox_override("panel", _panel_bg(Color(0.10, 0.05, 0.04, 0.85), Color(0.95, 0.35, 0.25, 0.9)))
	ground_zone_placeholder.add_child(ground_zone)
	ground_label = Label.new()
	ground_label.position = Vector2(10, 10)
	ground_label.size = Vector2(480, 22)
	ground_label.text = "丢弃区：拖到这里 或 右键物品 = 丢地上（不会消失）"
	ground_label.add_theme_font_size_override("font_size", 13)
	ground_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ground_zone.add_child(ground_label)
	ground_zone.equipment_dropped.connect(func(from_area: String, idx: int):
		if _current_drag_cb.is_valid():
			_current_drag_cb.call(from_area, idx, "ground", 0)
	)

	# 弹窗（技能选择/祭坛/仓库替换/商人）的按钮信号由各自的 show_* 函数管理，
	# 这里只生成动态列表按钮的容器条目。
	for i in range(6):
		var sb := Button.new()
		sb.position = Vector2(14, 50 + i * 42)
		sb.size = Vector2(400, 36)
		sb.visible = false
		skill_select_panel.add_child(sb)
		skill_select_buttons.append(sb)
	for i in range(6):
		var rb := Button.new()
		rb.position = Vector2(14, 50 + i * 42)
		rb.size = Vector2(400, 36)
		rb.visible = false
		replace_panel.add_child(rb)
		replace_buttons.append(rb)
	for i in range(4):
		var btn := Button.new()
		btn.position = Vector2(14, 50 + i * 42)
		btn.size = Vector2(380, 36)
		btn.visible = false
		trade_panel.add_child(btn)
		trade_buttons.append(btn)
		var lbl := Label.new()
		lbl.position = Vector2(14, 88 + i * 42)
		lbl.size = Vector2(400, 18)
		lbl.add_theme_font_size_override("font_size", 12)
		lbl.visible = false
		trade_panel.add_child(lbl)
		trade_labels.append(lbl)

	_build_attribute_panel()
	_build_objective_bar()
	_build_settlement_panel()

func update_hp(hp: float, max_hp: float) -> void:
	hp_bar.max_value = maxf(max_hp, 1)
	hp_bar.value = clampf(hp, 0, max_hp)
	hp_label.text = "HP %d/%d" % [int(hp), int(max_hp)]

func update_energy(en: float) -> void:
	energy_bar.max_value = 100
	energy_bar.value = clampf(en, 0, 100)
	energy_label.text = "EN %d/100" % int(en)

func update_gold(gold: int) -> void:
	gold_label.text = "金币 %d" % gold

func update_synergy(bonuses: Dictionary) -> void:
	if message_label == null:
		return
	# 在消息行追加联动信息
	var parts: Array[String] = []
	for st in ["aoe_self", "aoe_ground", "dash", "projectile"]:
		var c := int(bonuses.get(st, 0))
		if c >= 2:
			var name := "环绕" if st == "aoe_self" else ("范围" if st == "aoe_ground" else ("突进" if st == "dash" else "弹体"))
			parts.append("%s×%d" % [name, c])
	if not parts.is_empty():
		var old := message_label.text.split("  [")[0]
		message_label.text = "%s  [联动: %s]" % [old, " ".join(parts)]

func update_minimap(player_pos: Vector2, enemy_positions: Array, merchant_positions: Array, world_size: Vector2, roads: Array = [], camps: Array = [], boss_pos: Vector2 = Vector2.ZERO) -> void:
	if minimap:
		minimap.update_data(player_pos, enemy_positions, merchant_positions, world_size, roads, camps, boss_pos)

func update_merchant_count(count: int) -> void:
	if stats_label == null:
		return
	# 在属性行末尾追加商人信息
	var base_text: String = stats_label.text.split("  商人")[0]
	if count > 0:
		stats_label.text = "%s  商人 ×%d" % [base_text, count]

func update_stats(stats_dict: Dictionary) -> void:
	var t := stats_dict
	stats_label.text = "力%d 敏%d 智%d 体%d 运%d" % [t.get("str", 0), t.get("agi", 0), t.get("int", 0), t.get("vit", 0), t.get("luk", 0)]
	var str_v := int(t.get("str", 0)); var agi_v := int(t.get("agi", 0)); var int_v := int(t.get("int", 0))
	var vit_v := int(t.get("vit", 0)); var luk_v := int(t.get("luk", 0))
	stats_label.tooltip_text = "力量 %d → 近战伤害 +%d%%\n敏捷 %d → 移速 +%d%% | 攻速 +%d%%\n智力 %d → 远程伤害 +%d%% | 回能 +%.1f/s\n生命 %d → 最大HP +%d\n幸运 %d → 掉落品质偏移 +%d%%" % [
		str_v, str_v * 3, agi_v, agi_v * 2, agi_v * 3,
		int_v, int_v * 3, 5.0 + int_v * 0.5, vit_v, vit_v * 8, luk_v, luk_v * 2
	]

func set_message(text: String) -> void:
	if message_label == null:
		return
	message_label.text = text

# ============================================================
# M3 生存目标条（倒计时 / Boss 进度 / 死亡次数 / 威胁等级）
# ============================================================
func _build_objective_bar() -> void:
	var bar_w := 560.0
	var bar_h := 30.0
	objective_panel = Panel.new()
	objective_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	objective_panel.add_theme_stylebox_override("panel", _panel_bg(Color(0.06, 0.08, 0.12, 0.92), Color(0.45, 0.7, 1.0, 0.8)))
	objective_panel.size = Vector2(bar_w, bar_h)
	var vps := _logical_viewport_size()
	objective_panel.position = Vector2((vps.x - bar_w) / 2.0, 6.0)
	add_child(objective_panel)

	var hb := HBoxContainer.new()
	hb.position = Vector2(10, 4)
	hb.size = Vector2(bar_w - 20, bar_h - 8)
	hb.add_theme_constant_override("separation", 14)
	objective_panel.add_child(hb)

	obj_time = Label.new(); obj_time.add_theme_font_size_override("font_size", 13)
	obj_boss = Label.new(); obj_boss.add_theme_font_size_override("font_size", 13)
	obj_death = Label.new(); obj_death.add_theme_font_size_override("font_size", 13)
	obj_threat = Label.new(); obj_threat.add_theme_font_size_override("font_size", 13)
	for l in [obj_time, obj_boss, obj_death, obj_threat]:
		hb.add_child(l)
	update_objective({"time": 1800.0, "boss": 0, "boss_quota": 5, "deaths": 0, "death_limit": 3, "threat": 1})

func update_objective(d: Dictionary) -> void:
	if obj_time == null:
		return
	var t: float = float(d.get("time", 0.0))
	var mm := int(t) / 60
	var ss := int(t) % 60
	obj_time.text = "时间 %02d:%02d" % [mm, ss]
	obj_boss.text = "BOSS %d/%d" % [int(d.get("boss", 0)), int(d.get("boss_quota", 5))]
	obj_death.text = "阵亡 %d/%d" % [int(d.get("deaths", 0)), int(d.get("death_limit", 3))]
	obj_threat.text = "威胁 Lv.%d" % int(d.get("threat", 1))
	# 危急反馈：死亡接近上限标红；倒计时进入最后 1 分钟标红
	obj_death.modulate = Color(1.0, 0.5, 0.4) if int(d.get("deaths", 0)) >= int(d.get("death_limit", 3)) else Color.WHITE
	obj_time.modulate = Color(1.0, 0.4, 0.3) if t <= 60.0 else Color.WHITE

# ============================================================
# M3 结算界面（胜利 / 失败）
# ============================================================
func _build_settlement_panel() -> void:
	settlement_panel = Panel.new()
	settlement_panel.process_mode = Node.PROCESS_MODE_ALWAYS  # 暂停后仍可交互
	settlement_panel.z_index = 100
	settlement_panel.visible = false
	var vps := _logical_viewport_size()
	settlement_panel.position = Vector2((vps.x - 520.0) / 2.0, (vps.y - 360.0) / 2.0)
	settlement_panel.size = Vector2(520, 360)
	settlement_panel.add_theme_stylebox_override("panel", _panel_bg(Color(0.05, 0.07, 0.11, 0.97), Color(0.5, 0.7, 1.0, 0.9)))
	add_child(settlement_panel)

	obj_title = Label.new()
	obj_title.position = Vector2(20, 16)
	obj_title.size = Vector2(480, 34)
	obj_title.add_theme_font_size_override("font_size", 22)
	obj_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	settlement_panel.add_child(obj_title)

	obj_rating = Label.new()
	obj_rating.position = Vector2(20, 56)
	obj_rating.size = Vector2(480, 30)
	obj_rating.add_theme_font_size_override("font_size", 20)
	obj_rating.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	settlement_panel.add_child(obj_rating)

	obj_stats = Label.new()
	obj_stats.position = Vector2(30, 96)
	obj_stats.size = Vector2(460, 180)
	obj_stats.add_theme_font_size_override("font_size", 15)
	settlement_panel.add_child(obj_stats)

	obj_hint = Label.new()
	obj_hint.position = Vector2(20, 282)
	obj_hint.size = Vector2(480, 28)
	obj_hint.add_theme_font_size_override("font_size", 13)
	obj_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	obj_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	settlement_panel.add_child(obj_hint)

	var btn := Button.new()
	btn.position = Vector2(180, 316)
	btn.size = Vector2(160, 36)
	btn.text = "重新开始 (R)"
	btn.pressed.connect(func():
		get_tree().paused = false
		get_tree().reload_current_scene()
	)
	settlement_panel.add_child(btn)

func show_settlement(win: bool, d: Dictionary) -> void:
	if settlement_panel == null:
		return
	var rating := _compute_rating(win, d)
	obj_title.text = "胜利！你撑过了丛林的试炼" if win else "失败 · 你倒在了丛林中"
	obj_title.modulate = Color(0.5, 1.0, 0.6) if win else Color(1.0, 0.5, 0.45)
	obj_rating.text = "评级：" + rating
	obj_rating.modulate = Color(1.0, 0.85, 0.3)
	var tu := float(d.get("time_used", 0.0))
	obj_stats.text = "击杀总数：%d\nBoss 击杀：%d / %d\n死亡次数：%d / %d\n用时：%02d:%02d / %02d:%02d\n等级：Lv.%d   金币：%d\n剩余生命：%.0f%%" % [
		int(d.get("kills", 0)),
		int(d.get("bosses", 0)), int(d.get("boss_quota", 5)),
		int(d.get("deaths", 0)), int(d.get("death_limit", 3)),
		int(tu) / 60, int(tu) % 60,
		int(float(d.get("time_total", 1800.0))) / 60, int(float(d.get("time_total", 1800.0))) % 60,
		int(d.get("level", 1)), int(d.get("gold", 0)),
		float(d.get("hp_pct", 0.0)) * 100.0
	]
	if win:
		obj_hint.text = "评价：你掌控了丛林的节奏。后续将解锁昼夜循环与交易行等更深玩法。"
	else:
		obj_hint.text = "提示：稳着打打不完配额，莽着打会超死亡上限——在「快」与「稳」间找平衡。"
	settlement_panel.visible = true

func _compute_rating(win: bool, d: Dictionary) -> String:
	if not win:
		return "F"
	var score := 0
	score += int(float(d.get("time_used", 0.0)) / 60.0)
	score -= int(d.get("deaths", 0)) * 12
	if int(d.get("deaths", 0)) == 0:
		score += 25
	if float(d.get("hp_pct", 0.0)) > 0.5:
		score += 8
	if score >= 35:
		return "S"
	if score >= 22:
		return "A"
	if score >= 10:
		return "B"
	return "C"

func refresh_inventory(skills: Array, equipments: Array, warehouse: Array, slot_clicked_cb: Callable, drag_cb: Callable, equip_click_cb: Callable, augments: Array = [], discard_cb: Callable = func(_a, _i): pass) -> void:
	_cache_skill_slots = skills.duplicate(true)
	_refill_fusion_grid(skills, augments, slot_clicked_cb, drag_cb, func(_a, _i): pass)
	_refill_grid(equip_grid, "equipment", equipments, equip_click_cb, drag_cb, discard_cb)
	_refill_grid(warehouse_grid, "warehouse", warehouse, func(a, i): pass, drag_cb, discard_cb)
	# 重新应用缓存的 CD
	_apply_cached_cds()

# ============================================================
# 融合网格：每键一个竖向融合单元（主技能大槽 + 2 个增益小槽）
# ============================================================
func _refill_fusion_grid(skills: Array, augments: Array, click_cb: Callable, drag_cb: Callable, discard_cb: Callable) -> void:
	for child in skill_grid.get_children():
		child.queue_free()
	for i in range(6):
		var host: Dictionary = skills[i] if i < skills.size() else {}
		var pair: Array = augments[i] if i < augments.size() else [{}, {}]

		var unit := VBoxContainer.new()
		unit.custom_minimum_size = Vector2(76, 96)
		unit.add_theme_constant_override("separation", 2)

		var host_slot := _make_slot("skill", i, host, false, "host", click_cb, drag_cb, func(_a, _i): pass)
		unit.add_child(host_slot)

		for j in range(2):
			var a: Variant = pair[j] if j < pair.size() else {}
			var aug: Dictionary = a if typeof(a) == TYPE_DICTIONARY else {}
			var aug_slot := _make_slot("aug%d" % j, i, aug, not String(aug.get("id", "")).is_empty(), "mini", func(_a, _i): pass, drag_cb, func(_a, _i): pass)
			unit.add_child(aug_slot)

		# 主槽 tooltip 追加融合摘要
		var summary := _fusion_summary(host, pair)
		if not summary.is_empty():
			host_slot.tooltip_text += summary

		skill_grid.add_child(unit)

func _make_slot(area: String, i: int, item: Dictionary, can_drag: bool, mode: String, click_cb: Callable, drag_cb: Callable, discard_cb: Callable) -> InventorySlot:
	var slot := InventorySlot.new()
	slot.setup(area, i, "", item, can_drag, mode)
	slot.slot_drag_requested.connect(drag_cb)
	slot.slot_clicked.connect(click_cb)
	slot.slot_discard_requested.connect(discard_cb)
	slot.mouse_entered.connect(func(): slot._hovered = true; slot.queue_redraw())
	slot.mouse_exited.connect(func(): slot._hovered = false; slot.queue_redraw())
	return slot

func _fusion_summary(host: Dictionary, pair: Array) -> String:
	if String(host.get("id", "")).is_empty():
		return ""
	var lines := ""
	for j in range(mini(2, pair.size())):
		var a: Variant = pair[j]
		if typeof(a) != TYPE_DICTIONARY or String(a.get("id", "")).is_empty():
			continue
		lines += "\n + %s（效果×0.5 并入）" % a.get("name", "增益")
	if lines.is_empty():
		return ""
	return "\n─── 融合 ───" + lines

# 取第 i 键融合单元的主技能槽
func _host_slot(i: int) -> InventorySlot:
	if i < 0 or i >= skill_grid.get_child_count():
		return null
	var unit := skill_grid.get_child(i)
	if unit is InventorySlot:
		return unit  # 兼容旧扁平结构
	if unit.get_child_count() > 0 and unit.get_child(0) is InventorySlot:
		return unit.get_child(0)
	return null

func update_cooldowns(cds: Dictionary) -> void:
	_cache_cds = cds.duplicate()
	_apply_cached_cds()

func _apply_cached_cds() -> void:
	for i in range(skill_grid.get_child_count()):
		var slot := _host_slot(i)
		if slot != null:
			var time: float = float(_cache_cds.get(str(i), 0.0))
			slot.set_cd(time)
			slot.queue_redraw()

func update_skill_slot_data(skills: Array) -> void:
	_cache_skill_slots = skills.duplicate(true)

func flash_skill_slot(idx: int, text: String) -> void:
	var s := _host_slot(idx)
	if s != null:
		s.flash(text)

func update_progression(lvl: int, xp: float, xp_to_next: float, skill_points: int) -> void:
	if level_label == null:
		return
	level_label.text = "等级 Lv.%d" % lvl
	skill_point_label.text = "技能点：%d" % skill_points
	if xp_bar != null:
		xp_bar.value = clampf(xp / maxf(xp_to_next, 0.1) * 100.0, 0.0, 100.0)
	# 属性面板随技能点实时刷新
	if attr_panel != null and attr_panel.visible:
		_refresh_attribute_panel()

func update_recovery_stone(charge: int, need: int) -> void:
	if recovery_label == null:
		return
	if charge >= need:
		recovery_label.text = "恢复石：就绪（点击装备槽 E1 使用）"
		recovery_label.modulate = Color(0.4, 1.0, 0.4)
	else:
		recovery_label.text = "恢复石充能：%d/%d 击杀" % [charge, need]
		recovery_label.modulate = Color(0.6, 0.7, 0.6)

func _on_ground_drop(data: Variant) -> void:
	# 转发给拖拽回调
	if typeof(data) == TYPE_DICTIONARY:
		var drag_cb := _current_drag_cb
		if drag_cb.is_valid():
			drag_cb.call(String(data.get("from_area", "")), int(data.get("from_index", -1)), "ground", 0)

var _current_drag_cb: Callable

func _refill_grid(grid: HBoxContainer, area: String, items: Array, click_cb: Callable, drag_cb: Callable, discard_cb: Callable) -> void:
	if area == "warehouse":
		_current_drag_cb = drag_cb
	for child in grid.get_children():
		child.queue_free()
	for i in range(6):
		var item: Dictionary = {}
		if i < items.size():
			item = items[i]
		var item_id := String(item.get("id", ""))
		# 仓库物品可拖；装备可拖（用于卸下），但恢复石只可点击使用、不可拖动
		var can_drag := (area == "warehouse") or (area == "equipment" and not item_id.is_empty() and item_id != "recovery_stone")
		var slot := InventorySlot.new()
		slot.setup(area, i, "", item, can_drag)
		slot.slot_drag_requested.connect(drag_cb)
		slot.slot_clicked.connect(click_cb)
		slot.slot_discard_requested.connect(discard_cb)
		slot.mouse_entered.connect(func(): slot._hovered = true; slot.queue_redraw())
		slot.mouse_exited.connect(func(): slot._hovered = false; slot.queue_redraw())
		grid.add_child(slot)

func show_trade_panel(merchandise: Array, upgrade_cb: Callable, delete_cb: Callable, buy_cb: Callable, sell_cb: Callable, on_close: Callable) -> void:
	# 重新打开交易时仅清理旧 UI，不提前结束当前商人会话。
	_close_trade_panel(false)
	_trade_close_callback = on_close
	trade_panel.visible = true
	trade_panel.z_index = 5
	_disconnect_one(trade_close_button, "pressed")
	trade_close_button.pressed.connect(func(): _close_trade_panel(true))

	for i in range(4):
		trade_buttons[i].visible = false
		_disconnect_one(trade_buttons[i], "pressed")
		trade_labels[i].visible = false

	for i in range(merchandise.size()):
		var equip: Dictionary = merchandise[i]
		trade_buttons[i].visible = true
		trade_buttons[i].text = "[%s] %s - %d金" % [equip.get("quality", "白"), equip.get("name", "装备"), int(equip.get("buy_price", 50))]
		var idx := i
		trade_buttons[i].pressed.connect(func(): buy_cb.call(idx))
		trade_labels[i].visible = true
		trade_labels[i].text = equip.get("effect_description", "")

	var upgrade_btn := Button.new()
	upgrade_btn.position = Vector2(14, 230)
	upgrade_btn.size = Vector2(200, 36)
	upgrade_btn.text = "升级技能"
	upgrade_btn.pressed.connect(func(): upgrade_cb.call())
	trade_panel.add_child(upgrade_btn)

	var delete_btn := Button.new()
	delete_btn.position = Vector2(226, 230)
	delete_btn.size = Vector2(200, 36)
	delete_btn.text = "删除技能"
	delete_btn.pressed.connect(func(): delete_cb.call())
	trade_panel.add_child(delete_btn)

	var sell_btn := Button.new()
	sell_btn.position = Vector2(14, 272)
	sell_btn.size = Vector2(412, 36)
	sell_btn.text = "出售物品（卖出仓库装备）"
	sell_btn.pressed.connect(func(): sell_cb.call())
	trade_panel.add_child(sell_btn)
	_refresh_modal_state()

func hide_trade_panel() -> void:
	_close_trade_panel(false)

func show_replace_popup(warehouse: Array, pickup_item: Dictionary, callback: Callable) -> void:
	_close_replace_popup()
	pending_pickup_item = pickup_item
	replace_callback = callback
	replace_panel.visible = true
	replace_panel.z_index = 20
	var rp_title := replace_panel.get_node("Title") as Label
	rp_title.text = "仓库已满 · 替换哪个物品？新物品：【%s】" % pickup_item.get("name", "物品")
	_connect_replace_cancel("放弃拾取")

	for i in range(6):
		_disconnect_one(replace_buttons[i], "pressed")
		replace_buttons[i].visible = false
		replace_buttons[i].disabled = false

	for i in range(6):
		if i >= warehouse.size():
			continue
		replace_buttons[i].visible = true
		var item: Dictionary = warehouse[i]
		if String(item.get("id", "")).is_empty():
			replace_buttons[i].text = "槽位 %d：空" % (i + 1)
			replace_buttons[i].modulate = Color(0.5, 0.5, 0.5)
		else:
			replace_buttons[i].text = "槽位 %d：【%s】%s" % [i + 1, item.get("name", "物品"), item.get("quality", "白")]
			replace_buttons[i].modulate = Color.WHITE
		var idx: int = i
		replace_buttons[i].pressed.connect(func(): _on_replace_selected(idx))
	_refresh_modal_state()

# 出售弹窗：复用替换面板的按钮组，列出仓库物品（装备可售，技能书置灰）
func show_sell_popup(warehouse: Array, callback: Callable) -> void:
	_close_replace_popup()
	sell_callback = callback
	replace_panel.visible = true
	replace_panel.z_index = max(trade_panel.z_index, 0) + 2  # 确保在交易面板上层
	var rp_title := replace_panel.get_node("Title") as Label
	rp_title.text = "出售仓库物品（点击即卖出）"
	_connect_replace_cancel("关闭")
	for i in range(6):
		_disconnect_one(replace_buttons[i], "pressed")
		replace_buttons[i].visible = false
		replace_buttons[i].disabled = false
	for i in range(6):
		if i >= warehouse.size():
			continue
		var item: Dictionary = warehouse[i]
		replace_buttons[i].visible = true
		if String(item.get("id", "")).is_empty():
			replace_buttons[i].text = "槽位 %d：空" % (i + 1)
			replace_buttons[i].modulate = Color(0.5, 0.5, 0.5)
			replace_buttons[i].disabled = true
		elif String(item.get("cast_type", "")).is_empty():
			replace_buttons[i].text = "槽位 %d：【%s】→ 售 %d 金" % [i + 1, item.get("name", "装备"), int(item.get("sell_price", 20))]
			replace_buttons[i].modulate = Color(1.0, 0.85, 0.4)
		else:
			replace_buttons[i].text = "槽位 %d：【%s】技能书不可售" % [i + 1, item.get("name", "物品")]
			replace_buttons[i].modulate = Color(0.5, 0.5, 0.5)
			replace_buttons[i].disabled = true
		var idx: int = i
		replace_buttons[i].pressed.connect(func(): _on_sell_selected(idx))
	_refresh_modal_state()

func _on_sell_selected(index: int) -> void:
	var callback := sell_callback
	_close_replace_popup()
	if callback.is_valid():
		callback.call(index)

func _connect_replace_cancel(btn_text: String) -> void:
	_disconnect_one(replace_cancel_button, "pressed")
	replace_cancel_button.text = btn_text
	replace_cancel_button.pressed.connect(func(): _close_replace_popup())

func _on_replace_selected(index: int) -> void:
	var callback := replace_callback
	_close_replace_popup()
	if callback.is_valid():
		callback.call(index)

func update_energy_for_slots(energy: float) -> void:
	_cache_energy = energy
	for i in range(skill_grid.get_child_count()):
		var slot := _host_slot(i)
		if slot != null:
			var sk: Dictionary = {}
			if i < _cache_skill_slots.size():
				sk = _cache_skill_slots[i]
			var cost := float(sk.get("energy_cost", 0))
			var can_cast := energy >= cost or String(sk.get("cast_type", "")) != "active"
			slot._energy_ok = can_cast
			slot.queue_redraw()

func show_skill_select_popup(title: String, skills: Array, callback: Callable) -> void:
	_close_skill_select_popup()
	skill_select_panel.visible = true
	skill_select_panel.z_index = max(trade_panel.z_index, 0) + 1
	skill_select_callback = callback
	_disconnect_one(skill_select_close_button, "pressed")
	skill_select_close_button.pressed.connect(func(): _close_skill_select_popup())

	var sp_title := skill_select_panel.get_node("Title") as Label
	sp_title.text = title

	for i in range(6):
		_disconnect_one(skill_select_buttons[i], "pressed")
		skill_select_buttons[i].visible = false

	for i in range(6):
		if i >= skills.size():
			continue
		var item: Dictionary = skills[i]
		if String(item.get("id", "")).is_empty():
			skill_select_buttons[i].visible = true
			skill_select_buttons[i].text = "[%s] 空槽" % ["1","2","3","4","5","6"][i]
			skill_select_buttons[i].modulate = Color(0.5, 0.5, 0.5)
		else:
			skill_select_buttons[i].visible = true
			var key: String = ["1","2","3","4","5","6"][i]
			skill_select_buttons[i].text = "[%s] %s · %s · 主动" % [key, item.get("name", "物品"), item.get("quality", "白")]
			skill_select_buttons[i].modulate = Color.WHITE
		var idx: int = i
		skill_select_buttons[i].pressed.connect(func(): _on_skill_selected(idx))
	_refresh_modal_state()

func _on_skill_selected(index: int) -> void:
	var callback := skill_select_callback
	_close_skill_select_popup()
	if callback.is_valid():
		callback.call(index)

func show_idol_popup(cost_text: String, on_accept: Callable, on_decline: Callable) -> void:
	_close_idol_popup(true)
	var popup := idol_popup
	if popup == null:
		return
	var title := popup.get_node("Title") as Label
	var desc := popup.get_node("Desc") as Label
	title.text = "远古祭坛"
	desc.text = "%s\n\n回报：传说品质主动技能书" % cost_text
	_idol_decline_callback = on_decline
	_disconnect_one(idol_accept_button, "pressed")
	_disconnect_one(idol_decline_button, "pressed")
	idol_accept_button.pressed.connect(func(): _close_idol_popup(false); on_accept.call())
	idol_decline_button.pressed.connect(func(): _close_idol_popup(true))
	popup.visible = true
	_refresh_modal_state()

func _disconnect_one(btn: Button, signal_name: String) -> void:
	for conn in btn.get_signal_connection_list(signal_name):
		btn.disconnect(signal_name, conn.callable)

func _make_bar(pos: Vector2, sz: Vector2, color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.position = pos
	bar.size = sz
	bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.corner_radius_top_left = 4
	fill.corner_radius_top_right = 4
	fill.corner_radius_bottom_right = 4
	fill.corner_radius_bottom_left = 4
	bar.add_theme_stylebox_override("fill", fill)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.03, 0.04, 0.06, 0.9)
	bg.corner_radius_top_left = 4
	bg.corner_radius_top_right = 4
	bg.corner_radius_bottom_right = 4
	bg.corner_radius_bottom_left = 4
	bar.add_theme_stylebox_override("background", bg)
	return bar

func _panel_bg(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.border_width_left = 2
	s.border_width_top = 2
	s.border_width_right = 2
	s.border_width_bottom = 2
	s.corner_radius_top_left = 10
	s.corner_radius_top_right = 10
	s.corner_radius_bottom_right = 10
	s.corner_radius_bottom_left = 10
	return s
