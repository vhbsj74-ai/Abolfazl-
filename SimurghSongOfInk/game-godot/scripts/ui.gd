extends CanvasLayer

@onready var hp_bar: TextureProgressBar = $Margin/HBox/HP
@onready var ink_label: Label = $Margin/HBox/Ink
var player: CharacterBody2D

func initialize(p: CharacterBody2D) -> void:
	player = p
	set_process(true)

func _process(_dt: float) -> void:
	if player:
		hp_bar.value = float(player.health) / float(player.max_health) * 100.0
		ink_label.text = "Ink: %d" % Globals.ink_dust
