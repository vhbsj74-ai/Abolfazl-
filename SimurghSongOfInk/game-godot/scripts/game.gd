extends Node2D

@onready var ui: CanvasLayer = $UI
@onready var overlay: Node2D = $SpellOverlay
@onready var level_root: Node2D = $Level

var player: CharacterBody2D

func _ready() -> void:
	_spawn_level()
	_spawn_player()
	ui.call_deferred("initialize", player)

func _spawn_level() -> void:
	var lvl = load("res://scenes/level.tscn").instantiate()
	level_root.add_child(lvl)

func _spawn_player() -> void:
	player = load("res://scenes/player.tscn").instantiate()
	player.global_position = Vector2(128, 0)
	add_child(player)
	overlay.set("player", player)
