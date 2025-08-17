extends Node2D

@export var max_health:int = 400
var health:int
var facing:int = -1

func _ready() -> void:
	health = max_health
	$TelegraphTimer.timeout.connect(_telegraph_attack)
	$AttackTimer.timeout.connect(_attack)
	$TelegraphTimer.start()

func apply_damage(amount:int) -> void:
	health -= amount
	if health <= 0:
		queue_free()

func _telegraph_attack() -> void:
	$Telegraph.visible = true
	$AttackTimer.start()

func _attack() -> void:
	$Telegraph.visible = false
	var area = Area2D.new()
	var cs = CollisionShape2D.new()
	var sh = RectangleShape2D.new()
	sh.size = Vector2(200, 24)
	cs.shape = sh
	area.add_child(cs)
	area.global_position = global_position + Vector2(facing * 120, 0)
	get_parent().add_child(area)
	var t = Timer.new()
	t.wait_time = 0.2
	t.one_shot = true
	area.add_child(t)
	t.timeout.connect(func(): area.queue_free())
	t.start()
