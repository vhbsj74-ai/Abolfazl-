extends Node2D

func _ready() -> void:
	add_to_group("spell_overlay")

var is_casting: bool = false
var points: PackedVector2Array = []
var player: CharacterBody2D

func begin_cast() -> void:
	is_casting = true
	points.clear()
	visible = true
	queue_redraw()

func _input(event: InputEvent) -> void:
	if not is_casting:
		return
	if event is InputEventScreenTouch and not event.pressed:
		_end_cast()
	elif event is InputEventMouseButton and not event.pressed:
		_end_cast()
	elif event is InputEventScreenDrag:
		points.append(event.position)
		queue_redraw()
	elif event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT != 0:
		points.append(event.position)
		queue_redraw()

func _draw() -> void:
	if points.size() < 2:
		return
	for i in range(points.size() - 1):
		draw_line(points[i], points[i+1], Color(0.1, 0.9, 1.0, 0.8), 3.0)
	draw_circle(points[0], 5.0, Color.AQUA)
	draw_circle(points[points.size()-1], 5.0, Color.SKY_BLUE)

func _end_cast() -> void:
	is_casting = false
	visible = false
	var rune = _recognize(points)
	if rune != "":
		_cast_rune(rune)
	points.clear()
	queue_redraw()

func _recognize(pts: PackedVector2Array) -> String:
	if pts.size() < 6:
		return ""
	var minv = pts[0]
	var maxv = pts[0]
	for p in pts:
		minv = Vector2(min(minv.x, p.x), min(minv.y, p.y))
		maxv = Vector2(max(maxv.x, p.x), max(maxv.y, p.y))
	var span = maxv - minv
	if span.length() < 40.0:
		return ""
	var dx = maxv.x - minv.x
	var dy = maxv.y - minv.y
	var dir = Vector2(dx, dy).normalized()
	if abs(dir.x) > abs(dir.y):
		if dir.x > 0.0:
			return "WIND"
		else:
			return "SHADOW"
	else:
		if dir.y > 0.0:
			return "FIRE"
		else:
			return "MIST"

func _cast_rune(rune: String) -> void:
	match rune:
		"WIND":
			_spawn_wind()
		"FIRE":
			_spawn_fire()
		"SHADOW":
			_shadow_cloak()
		"MIST":
			_spawn_mist()

func _spawn_wind() -> void:
	var p = GPUParticles2D.new()
	p.amount = 120
	p.lifetime = 0.6
	p.one_shot = true
	p.emitting = true
	p.position = player.global_position + Vector2(24 * player.get("facing"), -6)
	p.direction = Vector2(player.get("facing"), 0)
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = 240
	p.initial_velocity_max = 360
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.1
	p.color = Color(0.7, 0.9, 1.0, 0.9)
	get_tree().current_scene.add_child(p)

func _spawn_fire() -> void:
	var area = Area2D.new()
	var col = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = Vector2(140, 32)
	col.shape = shape
	area.add_child(col)
	area.global_position = player.global_position + Vector2(70 * player.get("facing"), 0)
	get_tree().current_scene.add_child(area)
	var t = Timer.new()
	t.wait_time = 0.15
	t.one_shot = true
	area.add_child(t)
	t.timeout.connect(func(): area.queue_free())
	t.start()
	var lines = Line2D.new()
	lines.width = 10
	lines.default_color = Color(1.0, 0.4, 0.1, 0.8)
	lines.points = PackedVector2Array([Vector2(-70, -8), Vector2(70, 8)])
	area.add_child(lines)

func _shadow_cloak() -> void:
	var l = player.get_node("Visual/Light2D")
	var old = l.color
	l.color = Color(0.2, 0.6, 1.0, 1.0)
	player.modulate = Color(1,1,1,0.55)
	await get_tree().create_timer(0.8).timeout
	player.modulate = Color(1,1,1,1)
	l.color = old

func _spawn_mist() -> void:
	var p = GPUParticles2D.new()
	p.amount = 200
	p.lifetime = 1.2
	p.one_shot = true
	p.emitting = true
	p.position = player.global_position
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = 20
	p.initial_velocity_max = 60
	p.scale_amount_min = 0.8
	p.scale_amount_max = 1.4
	p.color = Color(0.9, 0.9, 1.0, 0.7)
	get_tree().current_scene.add_child(p)
