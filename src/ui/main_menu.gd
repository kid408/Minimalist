extends Control

const GameData = preload("res://src/data/game_data.gd")
const Arena = preload("res://src/arena.gd")

@onready var hero_card: Button = $HeroCard
@onready var hero_name: Label = $HeroCard/CardContent/HeroName
@onready var hero_desc: Label = $HeroCard/CardContent/HeroDesc
@onready var hero_stats: Label = $HeroCard/CardContent/HeroStats

var current_arena: Arena


func _ready() -> void:
	_refresh_hero_card()
	hero_card.pressed.connect(_start_game)


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


func _start_game() -> void:
	if current_arena and is_instance_valid(current_arena):
		return
	current_arena = Arena.new()
	get_tree().current_scene.add_child(current_arena)
	queue_free()
