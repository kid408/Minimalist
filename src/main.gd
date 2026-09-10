extends Node

const MainMenu = preload("res://scenes/ui/main_menu.tscn")
const InputBindings = preload("res://src/input_bindings.gd")


func _ready() -> void:
	randomize()
	ensure_input_map()
	var menu := MainMenu.instantiate()
	add_child(menu)


func ensure_input_map() -> void:
	InputBindings.initialize()
