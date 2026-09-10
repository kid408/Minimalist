extends Control

const GameData = preload("res://src/data/game_data.gd")
const Arena = preload("res://src/arena.gd")
const InputBindings = preload("res://src/input_bindings.gd")

@onready var hero_card: Button = $HeroCard
@onready var hero_name: Label = $HeroCard/CardContent/HeroName
@onready var hero_desc: Label = $HeroCard/CardContent/HeroDesc
@onready var hero_stats: Label = $HeroCard/CardContent/HeroStats
@onready var hint_label: Label = $Hint
@onready var settings_button: Button = $SettingsButton

var current_arena: Arena
var _settings_overlay: ColorRect
var _settings_panel: Panel
var _keybind_panel: Panel
var _settings_page := ""
var _capturing_action := ""
var _keybind_buttons: Dictionary = {}
var _keybind_status: Label


func _ready() -> void:
	InputBindings.initialize()
	_refresh_hero_card()
	_refresh_menu_hint()
	_build_settings_windows()
	hero_card.pressed.connect(_start_game)
	settings_button.pressed.connect(_open_settings)


func _input(event: InputEvent) -> void:
	if _settings_page.is_empty() or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key_event := event as InputEventKey
	if not _capturing_action.is_empty():
		if _is_escape(key_event):
			_cancel_key_capture("已取消按键设置。")
		else:
			var result := InputBindings.bind_action(_capturing_action, key_event)
			_capturing_action = ""
			_keybind_status.text = String(result.get("message", "按键设置失败。"))
			_refresh_keybind_rows()
			_refresh_menu_hint()
		get_viewport().set_input_as_handled()
		return
	if key_event.is_action_pressed("ui_cancel"):
		_go_back()
		get_viewport().set_input_as_handled()


func _refresh_hero_card() -> void:
	var hero := GameData.get_hero("vanguard")
	if hero.is_empty():
		return
	hero_name.text = "%s · %s" % [hero.get("name", "英雄"), hero.get("role", "")]
	hero_desc.text = hero.get("description", "")
	var base := GameData.get_base_stats()
	hero_stats.text = "生命%.0f · 移速%.0f · 攻速%.2f\n力%d 敏%d 智%d 体%d 运%d" % [
		hero.get("base_hp", 0.0), hero.get("move_speed", 0.0), hero.get("attack_interval", 0.0),
		base.str, base.agi, base.int, base.vit, base.luk]


func _refresh_menu_hint() -> void:
	var skill_keys := PackedStringArray()
	for i in range(6):
		skill_keys.append(InputBindings.get_action_key_text("skill_%d" % (i + 1)))
	hint_label.text = "鼠标右键移动/攻击 · 技能[%s]\n交互：%s · 拾取：%s · F1英雄 · C全选召唤物 · X停止 · Y跟随\n掉落物靠近自动显示名字 · 仓库拖拽到技能/装备槽 · 地图上自己找商人" % [
		"/".join(skill_keys),
		InputBindings.get_action_key_text("interact"),
		InputBindings.get_action_key_text("pickup"),
	]


func _build_settings_windows() -> void:
	_settings_overlay = ColorRect.new()
	_settings_overlay.name = "SettingsOverlay"
	_settings_overlay.position = Vector2.ZERO
	_settings_overlay.size = Vector2(1440, 810)
	_settings_overlay.color = Color(0.01, 0.02, 0.04, 0.86)
	_settings_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_settings_overlay.z_index = 10
	_settings_overlay.visible = false
	add_child(_settings_overlay)

	_settings_panel = _make_panel(Vector2(470, 188), Vector2(500, 370))
	_settings_panel.name = "SettingsPanel"
	_settings_panel.z_index = 11
	_settings_panel.visible = false
	add_child(_settings_panel)
	_add_label(_settings_panel, "设置", Vector2(24, 22), Vector2(452, 38), 28, Color(0.70, 0.88, 1.0), HORIZONTAL_ALIGNMENT_CENTER)
	_add_label(_settings_panel, "在这里调整游戏选项。\n按键设置支持技能、交互和拾取的快捷键。", Vector2(44, 86), Vector2(412, 70), 16, Color(0.78, 0.84, 0.92), HORIZONTAL_ALIGNMENT_CENTER)
	var keybind_button := _make_button("按键设置", Vector2(94, 182), Vector2(312, 52))
	keybind_button.pressed.connect(_open_keybind_settings)
	_settings_panel.add_child(keybind_button)
	_add_label(_settings_panel, "Esc 返回主菜单", Vector2(44, 247), Vector2(412, 24), 13, Color(0.54, 0.64, 0.74), HORIZONTAL_ALIGNMENT_CENTER)
	var settings_back := _make_button("返回主菜单", Vector2(150, 296), Vector2(200, 42))
	settings_back.pressed.connect(_close_settings)
	_settings_panel.add_child(settings_back)

	_keybind_panel = _make_panel(Vector2(350, 70), Vector2(740, 670))
	_keybind_panel.name = "KeybindSettingsPanel"
	_keybind_panel.z_index = 12
	_keybind_panel.visible = false
	add_child(_keybind_panel)
	_add_label(_keybind_panel, "按键设置", Vector2(26, 18), Vector2(688, 36), 28, Color(0.70, 0.88, 1.0), HORIZONTAL_ALIGNMENT_CENTER)
	_add_label(_keybind_panel, "点击右侧按键后按下新键。Esc 取消当前捕获；J、T、F1、C、X、H、G、Y 与 Esc 为保留键。", Vector2(30, 58), Vector2(680, 28), 13, Color(0.70, 0.77, 0.86), HORIZONTAL_ALIGNMENT_CENTER)

	_keybind_status = _add_label(_keybind_panel, "交互与拾取默认同为 Space：交互优先，未命中交互时拾取。", Vector2(30, 94), Vector2(680, 24), 13, Color(0.62, 0.90, 0.72), HORIZONTAL_ALIGNMENT_CENTER)
	var definitions := InputBindings.get_rebindable_actions()
	for i in range(definitions.size()):
		var definition: Dictionary = definitions[i]
		var action_name := String(definition.get("action", ""))
		var label_text := String(definition.get("label", action_name))
		var y := 132.0 + i * 48.0
		_add_label(_keybind_panel, label_text, Vector2(72, y + 6), Vector2(230, 34), 17, Color(0.92, 0.95, 1.0), HORIZONTAL_ALIGNMENT_LEFT)
		var bind_button := _make_button("", Vector2(330, y), Vector2(340, 42))
		bind_button.pressed.connect(_begin_key_capture.bind(action_name))
		_keybind_panel.add_child(bind_button)
		_keybind_buttons[action_name] = bind_button

	var reset_button := _make_button("恢复默认按键", Vector2(72, 548), Vector2(250, 42))
	reset_button.pressed.connect(_reset_keybinds)
	_keybind_panel.add_child(reset_button)
	var keybind_back := _make_button("返回设置 (Esc)", Vector2(418, 548), Vector2(250, 42))
	keybind_back.pressed.connect(_return_to_settings)
	_keybind_panel.add_child(keybind_back)
	_add_label(_keybind_panel, "提示：若同一键同时绑定交互与拾取，仍保持商人 → 祭坛 → 拾取的顺序。", Vector2(45, 608), Vector2(650, 24), 12, Color(0.54, 0.64, 0.74), HORIZONTAL_ALIGNMENT_CENTER)


func _open_settings() -> void:
	_settings_page = "settings"
	_settings_overlay.visible = true
	_settings_panel.visible = true
	_keybind_panel.visible = false
	_capturing_action = ""


func _open_keybind_settings() -> void:
	_settings_page = "keybind"
	_settings_panel.visible = false
	_keybind_panel.visible = true
	_capturing_action = ""
	_keybind_status.text = "交互与拾取默认同为 Space：交互优先，未命中交互时拾取。"
	_refresh_keybind_rows()


func _return_to_settings() -> void:
	if not _capturing_action.is_empty():
		_cancel_key_capture("已取消按键设置。")
	_settings_page = "settings"
	_keybind_panel.visible = false
	_settings_panel.visible = true


func _close_settings() -> void:
	_capturing_action = ""
	_settings_page = ""
	_settings_overlay.visible = false
	_settings_panel.visible = false
	_keybind_panel.visible = false
	_refresh_menu_hint()


func _go_back() -> void:
	match _settings_page:
		"keybind": _return_to_settings()
		"settings": _close_settings()


func _begin_key_capture(action_name: String) -> void:
	_capturing_action = action_name
	_keybind_status.text = "正在设置【%s】；请按下新键，Esc 取消。" % InputBindings.get_action_label(action_name)
	_refresh_keybind_rows()


func _cancel_key_capture(message: String) -> void:
	_capturing_action = ""
	_keybind_status.text = message
	_refresh_keybind_rows()


func _reset_keybinds() -> void:
	InputBindings.reset_rebindable_to_defaults()
	_capturing_action = ""
	_keybind_status.text = "已恢复默认按键。"
	_refresh_keybind_rows()
	_refresh_menu_hint()


func _refresh_keybind_rows() -> void:
	for definition in InputBindings.get_rebindable_actions():
		var action_name := String(definition.get("action", ""))
		var bind_button := _keybind_buttons.get(action_name) as Button
		if bind_button == null:
			continue
		bind_button.disabled = not _capturing_action.is_empty()
		bind_button.text = "请按下按键…" if action_name == _capturing_action else InputBindings.get_action_key_text(action_name)
		bind_button.modulate = Color(1.0, 0.84, 0.36) if action_name == _capturing_action else Color.WHITE


func _is_escape(event: InputEventKey) -> bool:
	return event.physical_keycode == KEY_ESCAPE or event.keycode == KEY_ESCAPE


func _make_panel(position: Vector2, size: Vector2) -> Panel:
	var panel := Panel.new()
	panel.position = position
	panel.size = size
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.055, 0.08, 0.13, 0.98)
	style.border_color = Color(0.34, 0.67, 0.96, 0.92)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	panel.add_theme_stylebox_override("panel", style)
	return panel


func _make_button(text: String, position: Vector2, size: Vector2) -> Button:
	var button := Button.new()
	button.text = text
	button.position = position
	button.size = size
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 16)
	return button


func _add_label(parent: Control, text: String, position: Vector2, size: Vector2, font_size: int, color: Color, alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label := Label.new()
	label.text = text
	label.position = position
	label.size = size
	label.modulate = color
	label.horizontal_alignment = alignment
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


func _start_game() -> void:
	if current_arena and is_instance_valid(current_arena):
		return
	var host := get_tree().current_scene
	if host == null:
		host = get_parent()
	if host == null:
		push_error("无法找到战场挂载节点。")
		return
	current_arena = Arena.new()
	host.add_child(current_arena)
	queue_free()
