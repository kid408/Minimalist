extends Node
class_name InventorySystem

# 库存系统：槽位初始化、HUD 连接、拖拽/装备/卸下、拾取、仓库管理等。
# 从 arena.gd 拆出，挂在 Arena 下。Arena 持有的状态与共享工具均通过 `arena.` 访问；
# 本系统内方法互相调用不加前缀。

const Arena = preload("res://src/arena.gd")
const GameData = preload("res://src/data/game_data.gd")
const SkillDrop = preload("res://src/systems/skill_drop.gd")

var arena: Arena


func _init_slots() -> void:
	arena.skill_slots = arena._empty_array(arena.ACTIVE_SLOT_COUNT)
	arena.equipment_slots = arena._empty_array(arena.EQUIPMENT_SLOT_COUNT)
	arena.warehouse_slots = arena._empty_array(arena.WAREHOUSE_SLOT_COUNT)
	arena.augment_slots = []
	for i in range(arena.ACTIVE_SLOT_COUNT):
		arena.augment_slots.append([{}, {}])

	# 开局：2范围主动(AOE) + 2被动 + 1装备 → 仓库
	var slot_idx := 0
	for i in range(2):
		var sid := arena._random_skill_by_subtypes(["aoe_self", "aoe_ground"])
		if not sid.is_empty():
			arena.warehouse_slots[slot_idx] = GameData.get_skill(sid)
			slot_idx += 1
	for i in range(2):
		var sid := arena._random_skill_by_type("active")
		if not sid.is_empty():
			arena.warehouse_slots[slot_idx] = GameData.get_skill(sid)
			slot_idx += 1
	arena.warehouse_slots[slot_idx] = GameData.get_equipment(GameData.get_random_equipment_id())

	# 恢复石 → 装备槽第1格
	arena.equipment_slots[0] = GameData.get_equipment("recovery_stone")
	arena.player.set_equipment(0, arena.equipment_slots[0])

func _connect_hud() -> void:
	var drag_cb := func(from_area: String, from_index: int, to_area: String, to_index: int):
		_handle_drag(from_area, from_index, to_area, to_index)
	var equip_click_cb := func(area: String, index: int):
		_on_equipment_clicked(area, index)
	var skill_click_cb := func(area: String, index: int):
		pass
	var discard_cb := func(area: String, index: int):
		_on_discard(area, index)
	arena.hud.refresh_inventory(arena.skill_slots, arena.equipment_slots, arena.warehouse_slots, skill_click_cb, drag_cb, equip_click_cb, arena.augment_slots, discard_cb)
	arena.hud.update_hp(arena.player.hp, arena.player.max_hp_calc())
	arena.hud.update_energy(arena.player.energy)
	arena.hud.update_gold(arena.gold)
	arena.hud.update_stats({
		"str": arena.player.total_str(), "agi": arena.player.total_agi(),
		"int": arena.player.total_int(), "vit": arena.player.total_vit(), "luk": arena.player.total_luk()
	})
	arena.hud.set_message("进入丛林。WASD移动，1-6 释放技能，Space 交互/拾取，J 召唤，T 属性加点；左键框选召唤物，右键下令或标记敌人。")

func _handle_drag(from_area: String, from_index: int, to_area: String, to_index: int) -> void:
	# 装备/仓库→丢弃区
	if (from_area == "equipment" or from_area == "warehouse") and to_area == "ground":
		if from_area == "equipment":
			var equip: Dictionary = arena.equipment_slots[from_index]
			if not arena._is_empty(equip):
				_drop_equipment_to_ground(from_index)
		else:
			var item: Dictionary = arena.warehouse_slots[from_index]
			if not arena._is_empty(item):
				var drop := SkillDrop.new(item)
				var drop_pos := arena.player.global_position + Vector2(randf_range(-50, 50), randf_range(-50, 50))
				drop.position = arena.world_layout.project_to_walkable(drop_pos) if arena.world_layout != null else drop_pos
				arena.drops_root.add_child(drop)
				arena.warehouse_slots[from_index] = {}
				arena.hud.set_message("已丢弃【%s】到地上" % item.get("name", "物品"))
				_refresh_hud_slots()
		return

	var from_slots := arena._slots_for(from_area)
	var to_slots := arena._slots_for(to_area)
	if from_index < 0 or from_index >= from_slots.size():
		return
	if to_index < 0 or to_index >= to_slots.size():
		return

	var id: String = String(from_slots[from_index].get("id", ""))
	if id.is_empty():
		return

	match from_area + "->" + to_area:
		"warehouse->skill":
			_equip_skill_from_warehouse(from_index, to_index, "skill")
		"warehouse->aug0":
			_equip_augment_from_warehouse(from_index, to_index, 0)
		"warehouse->aug1":
			_equip_augment_from_warehouse(from_index, to_index, 1)
		"aug0->warehouse":
			_unequip_augment_to_warehouse(0, from_index, to_index)
		"aug1->warehouse":
			_unequip_augment_to_warehouse(1, from_index, to_index)
		"warehouse->equipment":
			_equip_equipment_from_warehouse(from_index, to_index)
		"equipment->warehouse":
			_unequip_to_warehouse(from_index, to_index)
		"warehouse->warehouse":
			var tmp: Variant = arena.warehouse_slots[from_index]
			arena.warehouse_slots[from_index] = arena.warehouse_slots[to_index]
			arena.warehouse_slots[to_index] = tmp
		_:
			return

	_refresh_hud_slots()

func _drop_equipment_to_ground(eq_index: int) -> void:
	var equip: Dictionary = arena.equipment_slots[eq_index]
	arena.equipment_slots[eq_index] = {}
	arena.player.set_equipment(eq_index, {})
	arena.player.refresh_max_hp()
	arena.player.refresh_max_energy()
	var drop := SkillDrop.new(equip)
	var drop_pos := arena.player.global_position + Vector2(randf_range(-50, 50), randf_range(-50, 50))
	drop.position = arena.world_layout.project_to_walkable(drop_pos) if arena.world_layout != null else drop_pos
	arena.drops_root.add_child(drop)
	arena.hud.set_message("已丢弃【%s】到地上" % equip.get("name", "装备"))
	_refresh_hud_slots()

func _on_discard(area: String, index: int) -> void:
	# 右键直接丢弃：复用拖到地面的逻辑
	if area == "equipment" or area == "warehouse":
		_handle_drag(area, index, "ground", 0)

func _on_equipment_clicked(area: String, index: int) -> void:
	if area != "equipment":
		return
	var equip: Dictionary = arena.equipment_slots[index]
	if String(equip.get("id", "")) != "recovery_stone":
		return
	if arena.recovery_stone_charge < arena.recovery_stone_need:
		arena.hud.set_message("恢复石充能中… %d/%d 击杀" % [arena.recovery_stone_charge, arena.recovery_stone_need])
		return
	arena.recovery_stone_charge = 0
	var heal_hp := arena.player.max_hp_calc() * 0.3
	var heal_en := arena.ENERGY_MAX * 0.3
	arena.player.heal(heal_hp)
	arena.player.add_energy(heal_en)
	arena.hud.set_message("使用恢复石！恢复 %.0f HP + %.0f 能量" % [heal_hp, heal_en])
	_refresh_hud_slots()

func _equip_skill_from_warehouse(wh_idx: int, target_idx: int, area: String) -> void:
	var skill: Dictionary = arena.warehouse_slots[wh_idx]
	var id := String(skill.get("id", ""))
	if id.is_empty():
		return
	if area == "skill" and GameData.get_skill(id).is_empty():
		arena.hud.set_message("技能槽只能放技能")
		return
	if arena._skill_id_exists(id):
		arena.hud.set_message("【%s】已在技能槽中，不能重复装备" % skill.get("name", "技能"))
		return
	var slots := arena.skill_slots
	var old: Variant = slots[target_idx]
	slots[target_idx] = skill
	arena.warehouse_slots[wh_idx] = old
	arena.cooldowns[arena.skill_actions[target_idx]] = 0.0
	arena.hud.set_message("装备【%s】到主动槽" % skill.get("name", ""))

# 仓库 → 增益槽（融合单元的第 j 个增益位）：任何技能都可作增益（双用）
func _equip_augment_from_warehouse(wh_idx: int, key_idx: int, j: int) -> void:
	var skill: Dictionary = arena.warehouse_slots[wh_idx]
	var id := String(skill.get("id", ""))
	if id.is_empty():
		return
	if String(skill.get("cast_type", "")).is_empty():
		arena.hud.set_message("增益槽只能放技能")
		return
	if arena._skill_id_exists(id):
		arena.hud.set_message("【%s】已在其他槽中，不能重复装备" % skill.get("name", "技能"))
		return
	var old: Variant = arena.augment_slots[key_idx][j]
	arena.augment_slots[key_idx][j] = skill
	arena.warehouse_slots[wh_idx] = old if typeof(old) == TYPE_DICTIONARY else {}
	arena.hud.set_message("【%s】作为增益强化 %s 键" % [skill.get("name", ""), arena.skill_key_names[key_idx] if key_idx < arena.skill_key_names.size() else str(key_idx)])

# 增益槽 → 仓库（卸下）
func _unequip_augment_to_warehouse(j: int, key_idx: int, wh_idx: int) -> void:
	if not arena._is_empty(arena.warehouse_slots[wh_idx]):
		return
	var a: Variant = arena.augment_slots[key_idx][j]
	if typeof(a) != TYPE_DICTIONARY or arena._is_empty(a):
		return
	arena.warehouse_slots[wh_idx] = a
	arena.augment_slots[key_idx][j] = {}

func _equip_equipment_from_warehouse(wh_idx: int, eq_idx: int) -> void:
	var equip: Dictionary = arena.warehouse_slots[wh_idx]
	var bonuses: Dictionary = equip.get("stat_bonuses", {})
	if bonuses.is_empty() and String(equip.get("id", "")) != "recovery_stone":
		return
	var old: Variant = arena.equipment_slots[eq_idx]
	arena.equipment_slots[eq_idx] = equip
	arena.warehouse_slots[wh_idx] = old
	arena.player.set_equipment(eq_idx, equip)
	arena.player.refresh_max_hp()
	arena.player.refresh_max_energy()

func _unequip_to_warehouse(eq_idx: int, wh_idx: int) -> void:
	if not arena._is_empty(arena.warehouse_slots[wh_idx]):
		return
	var equip: Dictionary = arena.equipment_slots[eq_idx]
	arena.equipment_slots[eq_idx] = {}
	arena.warehouse_slots[wh_idx] = equip
	arena.player.set_equipment(eq_idx, {})
	arena.player.refresh_max_hp()
	arena.player.refresh_max_energy()

func _try_pickup() -> void:
	var nearest: Node = null
	var nearest_dist := arena.PICKUP_RANGE
	for drop in arena.drops_root.get_children():
		var dist := arena.player.global_position.distance_to(drop.global_position)
		if dist < nearest_dist:
			nearest = drop
			nearest_dist = dist
	if nearest == null:
		return

	var item_data: Dictionary = nearest.item_data

	# 任务1：捡到已学习的技能 → 直接吃掉并自动升级（不进仓库）
	var cid := String(item_data.get("id", ""))
	var ctype := String(item_data.get("cast_type", ""))
	if cid != "" and ctype in ["active"] and arena._is_skill_learned(cid):
		var info: Array = arena._learned_skill_index(cid)
		arena._upgrade_skill_from_pickup(info[0], info[1])
		nearest.queue_free()
		var nm: String = item_data.get("name", "技能")
		var lvl := int(arena._slot_ref(info[0], info[1]).get("level", 1))
		arena.hud.set_message("吃掉【%s】→ 自动升级至 Lv.%d！" % [nm, lvl])
		_refresh_hud_slots()
		return

	var empty_slot := _first_empty_warehouse()
	if empty_slot >= 0:
		arena.warehouse_slots[empty_slot] = item_data.duplicate(true)
		nearest.queue_free()
		arena.hud.set_message("拾取【%s】→ 仓库" % item_data.get("name", "物品"))
		_refresh_hud_slots()
		return

	# 仓库满：允许选择一个槽位替换，原物品落回地面而不是直接删除。
	var drop_ref := nearest
	var pickup_copy := item_data.duplicate(true)
	arena.hud.show_replace_popup(arena.warehouse_slots, pickup_copy, func(index: int):
		if index < 0 or index >= arena.warehouse_slots.size() or not is_instance_valid(drop_ref):
			return
		var replaced: Dictionary = arena.warehouse_slots[index]
		if not arena._is_empty(replaced):
			var displaced := SkillDrop.new(replaced)
			var displaced_pos := arena.player.global_position + Vector2(randf_range(-36, 36), randf_range(-36, 36))
			displaced.position = arena.world_layout.project_to_walkable(displaced_pos) if arena.world_layout != null else displaced_pos
			arena.drops_root.add_child(displaced)
		arena.warehouse_slots[index] = pickup_copy
		drop_ref.queue_free()
		arena.hud.set_message("拾取【%s】并替换仓库槽位 %d" % [pickup_copy.get("name", "物品"), index + 1])
		_refresh_hud_slots()
	)

func _first_empty_warehouse() -> int:
	for i in range(arena.warehouse_slots.size()):
		if arena._is_empty(arena.warehouse_slots[i]):
			return i
	return -1

func _refresh_hud_slots() -> void:
	var drag_cb := func(from_area: String, from_index: int, to_area: String, to_index: int):
		_handle_drag(from_area, from_index, to_area, to_index)
	var equip_click_cb := func(area: String, index: int):
		_on_equipment_clicked(area, index)
	var skill_click_cb := func(area: String, index: int):
		pass
	var discard_cb := func(area: String, index: int):
		_on_discard(area, index)
	arena.hud.refresh_inventory(arena.skill_slots, arena.equipment_slots, arena.warehouse_slots, skill_click_cb, drag_cb, equip_click_cb, arena.augment_slots, discard_cb)
