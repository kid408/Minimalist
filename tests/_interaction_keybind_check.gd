extends SceneTree

# 交互/拾取按键验证：默认共享 Space 时保持交互优先，拆分绑定后互不串联。
# 运行：godot --headless --path <项目根目录> --script res://tests/_interaction_keybind_check.gd

const Arena = preload("res://src/arena.gd")
const InputBindings = preload("res://src/input_bindings.gd")
const SkillDrop = preload("res://src/systems/skill_drop.gd")
const GameData = preload("res://src/data/game_data.gd")

const TEST_CONFIG_PATH := "user://input_bindings_interaction_test.cfg"


func _initialize() -> void:
	InputBindings.set_storage_path_for_testing(TEST_CONFIG_PATH)
	InputBindings.clear_storage_for_testing()
	InputBindings.initialize()

	var game_root := Node.new()
	root.add_child(game_root)
	current_scene = game_root
	var arena := Arena.new()
	game_root.add_child(arena)
	await process_frame
	arena.set_process(false)

	var failures: Array[String] = []
	var merchant = arena.merchants[0] if not arena.merchants.is_empty() else null
	if merchant == null:
		arena._spawn_merchant()
		merchant = arena.merchants[0]
	merchant.position = arena.player.global_position

	var priority_drop := _make_drop(arena)
	_press_actions(arena, true, true)
	if not arena.hud.trade_panel.visible:
		failures.append("默认共享键未优先触发商人交互")
	if not is_instance_valid(priority_drop):
		failures.append("交互优先时错误拾取了掉落物")
	while arena.hud.dismiss_top_transient():
		pass
	await process_frame

	merchant.position = Vector2(5000, 3900)
	for idol in arena.idols:
		idol._player_near = false
	arena.player.global_position = arena.world_layout.project_to_walkable(Vector2(5200, 3600))
	var shared_pickup_drop := _make_drop(arena)
	_press_actions(arena, true, true)
	if not shared_pickup_drop.is_queued_for_deletion():
		failures.append("默认共享键在无交互目标时未拾取")
	await process_frame
	arena.warehouse_slots[arena.WAREHOUSE_SLOT_COUNT - 1] = {}

	var interact_event := InputEventKey.new()
	interact_event.physical_keycode = KEY_E
	var pickup_event := InputEventKey.new()
	pickup_event.physical_keycode = KEY_F
	if not bool(InputBindings.bind_action("interact", interact_event).get("ok", false)):
		failures.append("交互键拆分设置失败")
	if not bool(InputBindings.bind_action("pickup", pickup_event).get("ok", false)):
		failures.append("拾取键拆分设置失败")

	var split_drop := _make_drop(arena)
	_press_actions(arena, true, false)
	if split_drop.is_queued_for_deletion():
		failures.append("仅交互键时错误拾取")
	await process_frame
	_press_actions(arena, false, true)
	if not split_drop.is_queued_for_deletion():
		failures.append("仅拾取键时未拾取")
	await process_frame

	InputBindings.reset_rebindable_to_defaults()
	InputBindings.clear_storage_for_testing()
	InputBindings.restore_default_storage_path()
	arena.free()

	if failures.is_empty():
		print("INTERACTIONKEYBIND_OK")
		quit(0)
	else:
		for failure in failures:
			printerr("INTERACTIONKEYBIND_ERR %s" % failure)
		quit(1)


func _make_drop(arena) -> SkillDrop:
	var item := GameData.get_skill(GameData.get_random_skill_id([]))
	var drop := SkillDrop.new(item)
	drop.position = arena.player.global_position
	arena.drops_root.add_child(drop)
	return drop


func _press_actions(arena, interact_pressed: bool, pickup_pressed: bool) -> void:
	if interact_pressed:
		Input.action_press("interact")
	if pickup_pressed:
		Input.action_press("pickup")
	# 通过 Arena 输入分发而非直接调用拾取函数，验证按键优先级。
	arena._process_input()
	Input.action_release("interact")
	Input.action_release("pickup")
