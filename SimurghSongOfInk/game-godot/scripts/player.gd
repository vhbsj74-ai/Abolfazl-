extends CharacterBody2D

@export var move_speed: float = 280.0
@export var acceleration: float = 1600.0
@export var friction: float = 1600.0
@export var dash_speed: float = 560.0
@export var dash_time: float = 0.2
@export var dash_cooldown: float = 0.6
@export var max_health: int = 100

var health: int
var dash_timer: float = 0.0
var dash_cd_timer: float = 0.0
var facing: int = 1

@onready var hitbox: Area2D = $Hitbox
@onready var sprite: Node2D = $Visual
@onready var light: Light2D = $Visual/Light2D

func _ready() -> void:
	health = max_health
	hitbox.monitoring = false

func _physics_process(delta: float) -> void:
	var input_vec = Vector2(
		(int(Input.is_action_pressed("move_right")) - int(Input.is_action_pressed("move_left"))),
		(int(Input.is_action_pressed("move_down")) - int(Input.is_action_pressed("move_up")))
	)
	input_vec = input_vec.normalized()

	if dash_timer > 0.0:
		dash_timer -= delta
		if dash_timer <= 0.0:
			velocity = Vector2.ZERO
	else:
		var target_vel = input_vec * move_speed
		velocity = velocity.move_toward(target_vel, (acceleration if input_vec != Vector2.ZERO else friction) * delta)

	move_and_slide()

	if input_vec.x != 0:
		facing = sign(input_vec.x)
		sprite.scale.x = facing

	if Input.is_action_just_pressed("dash") and dash_cd_timer <= 0.0 and input_vec != Vector2.ZERO:
		velocity = input_vec * dash_speed
		dash_timer = dash_time
		dash_cd_timer = dash_cooldown
		light.energy = 1.6
		$DashFx.emitting = true

	if dash_cd_timer > 0.0:
		dash_cd_timer -= delta
		light.energy = mix(light.energy, 0.9, 0.15)

	if Input.is_action_just_pressed("attack"):
		_perform_attack()

	if Input.is_action_just_pressed("cast"):
		get_tree().call_group("spell_overlay", "begin_cast")

func _perform_attack() -> void:
	hitbox.monitoring = true
	$AttackFx.emitting = true
	await get_tree().create_timer(0.08).timeout
	hitbox.monitoring = false

func apply_damage(amount:int) -> void:
	health -= amount
	if health <= 0:
		_queue_death()

func _queue_death() -> void:
	queue_free()
