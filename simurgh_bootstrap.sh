#!/usr/bin/env bash
set -euo pipefail

ROOT="/workspace/SimurghSongOfInk"
GODOT_DIR="$ROOT/game-godot"
CHAIN_DIR="$ROOT/chain-hardhat"
WEB_DIR="$ROOT/web-claim"

mkdir -p "$GODOT_DIR" "$GODOT_DIR/scenes" "$GODOT_DIR/scripts" "$GODOT_DIR/shaders" "$GODOT_DIR/resources" "$GODOT_DIR/ui" "$CHAIN_DIR/contracts" "$CHAIN_DIR/scripts" "$WEB_DIR/public"

wfile() {
	target="$1"; shift
	mkdir -p "$(dirname "$target")"
	cat > "$target" <<'EOF'
$CONTENT$
EOF
}

write_file() {
	target="$1"; content="$2"
	mkdir -p "$(dirname "$target")"
	printf "%s" "$content" > "$target"
}

# Godot project.godot
content='[application]
config/name="Simurgh: Song of Ink"
run/main_scene="res://scenes/main.tscn"
config/version="0.1.0"

[display]
window/size/viewport_width=1920
window/size/viewport_height=1080
window/stretch/mode="canvas_items"
window/stretch/aspect="expand"

[rendering]
textures/canvas_textures/default_texture_filter=3
2d/snapping/use_gpu_pixel_snap=true

[autoload]
Globals="*res://scripts/globals.gd"
'
write_file "$GODOT_DIR/project.godot" "$content"

# Shaders
content='shader_type canvas_item;
render_mode blend_mix, unshaded;

uniform vec4 rim_color : hint_color = vec4(0.04, 0.04, 0.05, 1.0);
uniform float rim_strength : hint_range(0.0, 4.0) = 1.2;
uniform float vignette : hint_range(0.0, 2.0) = 0.35;

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float dist = length(uv);
	float rim = smoothstep(0.2, 1.0, dist);
	float v = smoothstep(1.0, vignette, dist);
	vec4 base = texture(TEXTURE, UV);
	COLOR = mix(base, base + rim_color * rim_strength, rim * 0.35) * (1.0 - v * 0.15);
}
'
write_file "$GODOT_DIR/shaders/ink_rim.gdshader" "$content"

content='shader_type canvas_item;
render_mode blend_mix, unshaded;

uniform vec4 sand_tint : hint_color = vec4(0.85, 0.76, 0.60, 1.0);
uniform float speed = 0.15;
uniform float density = 35.0;

float hash(vec2 p){
	p = fract(p*vec2(123.34, 345.45));
	p += dot(p, p+34.345);
	return fract(p.x*p.y);
}

void fragment(){
	vec2 p = FRAGCOORD.xy / 256.0;
	float t = TIME * speed;
	float n = 0.0;
	for(int i=0;i<3;i++){
		vec2 q = p * (density * float(i+1));
		n += hash(q + t);
	}
	n /= 3.0;
	vec4 base = sand_tint * (0.85 + 0.15 * n);
	COLOR = base;
}
'
write_file "$GODOT_DIR/shaders/sand.gdshader" "$content"

# Globals
globals='extends Node
class_name Globals

var rng: RandomNumberGenerator = RandomNumberGenerator.new()

var ink_dust:int = 0
var sim_claimable:int = 0

func _ready() -> void:
	rng.randomize()
	_ensure_input_map()

func _ensure_input_map() -> void:
	var actions = {
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"move_up": [KEY_W, KEY_UP],
		"move_down": [KEY_S, KEY_DOWN],
		"jump": [KEY_SPACE],
		"dash": [KEY_K, MOUSE_BUTTON_RIGHT],
		"attack": [KEY_J, MOUSE_BUTTON_LEFT],
		"cast": [KEY_C],
		"pause": [KEY_ESCAPE]
	}
	for action in actions.keys():
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for code in actions[action]:
			var ev
			if typeof(code) == TYPE_INT and code > 10:
				ev = InputEventKey.new()
				ev.physical_keycode = code
			else:
				ev = InputEventMouseButton.new()
				ev.button_index = code
			InputMap.action_add_event(action, ev)

func add_ink(amount:int) -> void:
	ink_dust += max(0, amount)

func grant_sim(amount:int) -> void:
	sim_claimable += max(0, amount)
'
write_file "$GODOT_DIR/scripts/globals.gd" "$globals"

# game.gd
game='extends Node2D

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
'
write_file "$GODOT_DIR/scripts/game.gd" "$game"

# player.gd
player='extends CharacterBody2D

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
'
write_file "$GODOT_DIR/scripts/player.gd" "$player"

# spell_overlay.gd
overlay='extends Node2D

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
'
write_file "$GODOT_DIR/scripts/spell_overlay.gd" "$overlay"

# boss.gd
boss='extends Node2D

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
'
write_file "$GODOT_DIR/scripts/boss.gd" "$boss"

# ui.gd
ui='extends CanvasLayer

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
'
write_file "$GODOT_DIR/scripts/ui.gd" "$ui"

# level.gd
write_file "$GODOT_DIR/scripts/level.gd" "extends Node2D
"

# Scenes
main='[gd_scene load_steps=3 format=3]

[ext_resource type="Script" path="res://scripts/game.gd" id=1]
[ext_resource type="Script" path="res://scripts/spell_overlay.gd" id=2]
[ext_resource type="Script" path="res://scripts/ui.gd" id=3]

[node name="Main" type="Node2D"]
script = ExtResource(1)

[node name="CanvasModulate" type="CanvasModulate" parent="."]
color = Color(0.98, 0.96, 0.93, 1)

[node name="Level" type="Node2D" parent="."]

[node name="SpellOverlay" type="Node2D" parent="."]
script = ExtResource(2)
visible = false
z_index = 100

[node name="UI" type="CanvasLayer" parent="."]
script = ExtResource(3)
'
write_file "$GODOT_DIR/scenes/main.tscn" "$main"

player_scene='[gd_scene load_steps=5 format=3]

[ext_resource type="Script" path="res://scripts/player.gd" id=1]
[ext_resource type="Shader" path="res://shaders/ink_rim.gdshader" id=2]

[sub_resource type="RectangleShape2D" id=1]
size = Vector2(16, 32)

[sub_resource type="Gradient" id=2]
colors = PackedColorArray(1, 1, 1, 1, 0, 0, 0, 0)
offsets = PackedFloat32Array(0, 1)

[sub_resource type="GradientTexture2D" id=3]
gradient = SubResource(2)
width = 128
height = 128
use_hdr = false

[node name="Player" type="CharacterBody2D"]
script = ExtResource(1)

[node name="Visual" type="Node2D" parent="."]

[node name="Body" type="Polygon2D" parent="Visual"]
color = Color(0.15, 0.16, 0.18, 1)
polygon = PackedVector2Array(-8, -16, 8, -16, 8, 16, -8, 16)

[node name="Light2D" type="Light2D" parent="Visual"]
texture = SubResource(3)
color = Color(1, 0.93, 0.75, 1)
energy = 0.9

[node name="CollisionShape2D" type="CollisionShape2D" parent="."]
shape = SubResource(1)
position = Vector2(0, 0)

[node name="Hitbox" type="Area2D" parent="."]
monitoring = false

[node name="HitboxShape" type="CollisionShape2D" parent="Hitbox"]
position = Vector2(18, 0)
shape = SubResource(1)

[node name="AttackFx" type="GPUParticles2D" parent="."]
amount = 40
one_shot = true
lifetime = 0.15

[node name="DashFx" type="GPUParticles2D" parent="."]
amount = 80
one_shot = true
lifetime = 0.2
'
write_file "$GODOT_DIR/scenes/player.tscn" "$player_scene"

boss_scene='[gd_scene load_steps=3 format=3]

[ext_resource type="Script" path="res://scripts/boss.gd" id=1]

[sub_resource type="RectangleShape2D" id=1]
size = Vector2(24, 24)

[node name="Boss" type="Node2D"]
script = ExtResource(1)
position = Vector2(680, -40)

[node name="Body" type="Polygon2D" parent="."]
color = Color(0.2, 0.05, 0.05, 1)
polygon = PackedVector2Array(-20, -20, 20, -20, 20, 20, -20, 20)

[node name="Telegraph" type="Polygon2D" parent="."]
color = Color(1, 0.3, 0.2, 0.5)
polygon = PackedVector2Array(0, -6, 160, -6, 160, 6, 0, 6)
visible = false

[node name="TelegraphTimer" type="Timer" parent="."]
wait_time = 1.8
one_shot = true

[node name="AttackTimer" type="Timer" parent="."]
wait_time = 0.35
one_shot = true
'
write_file "$GODOT_DIR/scenes/boss.tscn" "$boss_scene"

ui_scene='[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/ui.gd" id=1]

[node name="UI" type="CanvasLayer"]
script = ExtResource(1)

[node name="Margin" type="MarginContainer" parent="."]
offset_right = 1920.0
offset_bottom = 1080.0

[node name="HBox" type="HBoxContainer" parent="Margin"]
anchor_right = 1.0
anchor_bottom = 0.0
offset_left = 16.0
offset_top = 16.0
offset_right = -16.0
offset_bottom = 80.0

[node name="HP" type="TextureProgressBar" parent="Margin/HBox"]
value = 100.0
size_flags_horizontal = 3

[node name="Ink" type="Label" parent="Margin/HBox"]
text = "Ink: 0"
size_flags_horizontal = 1
'
write_file "$GODOT_DIR/ui/ui.tscn" "$ui_scene"

level_scene='[gd_scene load_steps=4 format=3]

[ext_resource type="Script" path="res://scripts/level.gd" id=1]
[ext_resource type="PackedScene" path="res://scenes/boss.tscn" id=2]
[ext_resource type="Shader" path="res://shaders/sand.gdshader" id=3]

[sub_resource type="RectangleShape2D" id=1]
size = Vector2(1600, 24)

[node name="LevelRoot" type="Node2D"]
script = ExtResource(1)

[node name="Background" type="ColorRect" parent="."]
color = Color(0.96, 0.94, 0.90, 1)
anchor_right = 1.0
anchor_bottom = 1.0
material = ShaderMaterial { shader = ExtResource(3) }

[node name="Ground" type="StaticBody2D" parent="."]
position = Vector2(0, 80)

[node name="Collision" type="CollisionShape2D" parent="Ground"]
shape = SubResource(1)

[node name="Boss" parent="." instance=ExtResource(2)]
position = Vector2(640, -20)
'
write_file "$GODOT_DIR/scenes/level.tscn" "$level_scene"

# swap main to instance UI
main_with_ui='[gd_scene load_steps=4 format=3]

[ext_resource type="Script" path="res://scripts/game.gd" id=1]
[ext_resource type="Script" path="res://scripts/spell_overlay.gd" id=2]
[ext_resource type="PackedScene" path="res://ui/ui.tscn" id=3]

[node name="Main" type="Node2D"]
script = ExtResource(1)

[node name="CanvasModulate" type="CanvasModulate" parent="."]
color = Color(0.98, 0.96, 0.93, 1)

[node name="Level" type="Node2D" parent="."]

[node name="SpellOverlay" type="Node2D" parent="."]
script = ExtResource(2)
visible = false
z_index = 100

[node name="UI" parent="." instance=ExtResource(3)]
'
write_file "$GODOT_DIR/scenes/main.tscn" "$main_with_ui"

# Godot README
write_file "$GODOT_DIR/README.md" $'# Simurgh: Song of Ink (Vertical Slice)\n\n- Engine: Godot 4.x\n- Run: Open this folder in Godot, run main scene `res://scenes/main.tscn`.\n- Controls: WASD/Arrows to move, J attack, K dash, C hold-draw to cast (drag mouse), ESC pause.\n- Mobile: Drag on screen to cast (basic support).\n\nExport to Android: install Godot Android export templates, set your SDK/NDK, then create an export preset. This vertical slice uses only built-in shapes and particles.\n'

# Hardhat
write_file "$CHAIN_DIR/package.json" $'{\n  "name": "simurgh-sim-token",\n  "version": "0.1.0",\n  "private": true,\n  "scripts": {\n    "build": "hardhat compile",\n    "deploy": "hardhat run scripts/deploy.js --network localhost || true"\n  },\n  "devDependencies": {\n    "@nomicfoundation/hardhat-toolbox": "^5.0.0",\n    "hardhat": "^2.22.0"\n  },\n  "dependencies": {\n    "@openzeppelin/contracts": "^5.0.2"\n  }\n}'

write_file "$CHAIN_DIR/hardhat.config.js" $'require("@nomicfoundation/hardhat-toolbox");\n\nmodule.exports = {\n  solidity: "0.8.24",\n  networks: {\n    hardhat: {}\n  }\n};\n'

write_file "$CHAIN_DIR/contracts/SIMToken.sol" $'// SPDX-License-Identifier: MIT\npragma solidity ^0.8.24;\n\nimport "@openzeppelin/contracts/token/ERC20/ERC20.sol";\nimport "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";\nimport "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";\nimport "@openzeppelin/contracts/access/AccessControl.sol";\n\ncontract SIMToken is ERC20, ERC20Burnable, ERC20Permit, AccessControl {\n    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");\n\n    constructor(address admin, uint256 initialTreasury)\n        ERC20("Simurgh", "SIM")\n        ERC20Permit("Simurgh")\n    {\n        _grantRole(DEFAULT_ADMIN_ROLE, admin);\n        _grantRole(MINTER_ROLE, admin);\n        if (initialTreasury > 0) {\n            _mint(admin, initialTreasury);\n        }\n    }\n\n    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {\n        _mint(to, amount);\n    }\n}\n'

write_file "$CHAIN_DIR/scripts/deploy.js" $'const hre = require("hardhat");\n\nasync function main() {\n  const [deployer] = await hre.ethers.getSigners();\n  console.log("Deploying with:", deployer.address);\n  const SIM = await hre.ethers.getContractFactory("SIMToken");\n  const sim = await SIM.deploy(deployer.address, hre.ethers.parseEther("1000000"));\n  await sim.waitForDeployment();\n  console.log("SIM deployed:", await sim.getAddress());\n}\n\nmain().catch((e) => { console.error(e); process.exit(1); });\n'

write_file "$CHAIN_DIR/README.md" $'# SIMToken (ERC-20)\n\n- Build: `npm i && npm run build`\n- Local deploy (anvil or hardhat node): `npx hardhat node` then `npm run deploy`\n- Configure real networks as needed.\n'

# Web claim
write_file "$WEB_DIR/package.json" $'{\n  "name": "simurgh-claim",\n  "version": "0.1.0",\n  "private": true,\n  "scripts": {\n    "start": "node server.js"\n  },\n  "dependencies": {\n    "ethers": "^6.11.1",\n    "express": "^4.19.2"\n  }\n}'

write_file "$WEB_DIR/server.js" $'const express = require(\'express\');\nconst path = require(\'path\');\nconst app = express();\napp.use(express.json());\napp.use(express.static(path.join(__dirname, \"public\")));\napp.get(\'/health\', (_, res) => res.json({ ok: true }));\nconst port = process.env.PORT || 8080;\napp.listen(port, () => console.log(`Claim web listening on :${port}`));\n'

write_file "$WEB_DIR/public/index.html" $'<!doctype html>\n<html lang="fa">\n<head>\n  <meta charset="utf-8">\n  <meta name="viewport" content="width=device-width, initial-scale=1" />\n  <title>Simurgh Claim</title>\n  <style>\n    body {font-family: sans-serif; background:#0f0f13; color:#eee; margin:0; padding:2rem}\n    .card {max-width:720px; margin:auto; background:#14151b; border:1px solid #2b2d36; border-radius:12px; padding:1.5rem}\n    button {background:#3b82f6; color:#fff; border:none; padding:0.6rem 1rem; border-radius:8px; cursor:pointer}\n    button:disabled {background:#2b2d36; cursor:not-allowed}\n  </style>\n</head>\n<body>\n  <div class="card">\n    <h2>Simurgh: Claim SIM</h2>\n    <p>برای دریافت پاداش هفتگی، کیف‌پول را متصل کنید و مقدار قابل‌دریافت را ادعا کنید.</p>\n    <div>\n      <button id="connect">Connect Wallet</button>\n      <button id="claim" disabled>Claim</button>\n    </div>\n    <pre id="log"></pre>\n  </div>\n  <script type="module" src="/app.js"></script>\n</body>\n</html>\n'

cat > "$WEB_DIR/public/app.js" << 'APPJS'
import { BrowserProvider, Contract, parseEther } from 'https://esm.sh/ethers@6.11.1';

const log = (...a) => (document.querySelector('#log').textContent += a.join(' ') + "\n");

let provider, signer, account;
const abi = [
  "function balanceOf(address owner) view returns (uint256)",
  "function mint(address to, uint256 amount)"
];
let contractAddress = localStorage.getItem('sim_address') || "";

async function connect() {
  if (!window.ethereum) return log('No wallet');
  provider = new BrowserProvider(window.ethereum);
  await provider.send("eth_requestAccounts", []);
  signer = await provider.getSigner();
  account = await signer.getAddress();
  log('Connected:', account);
}

async function claim() {
  if (!contractAddress) return log('Set SIM address in localStorage: sim_address');
  const c = new Contract(contractAddress, abi, signer);
  try {
    const tx = await c.mint(account, parseEther('1'));
    log('Mint sent:', tx.hash);
    await tx.wait();
    const bal = await c.balanceOf(account);
    log('Balance:', bal.toString());
  } catch(e) { log('Error:', e.message); }
}

const btnConnect = document.querySelector('#connect');
const btnClaim = document.querySelector('#claim');
btnConnect.onclick = connect;
btnClaim.onclick = claim;
window.addEventListener('load', () => { btnClaim.disabled = false; });
APPJS

# Root README
write_file "$ROOT/README.md" $'# Simurgh: Song of Ink — Vertical Slice + On-chain Skeleton\n\nGenerated folders:\n- `game-godot/` (Godot 4 vertical slice)\n- `chain-hardhat/` (ERC-20 SIM token)\n- `web-claim/` (minimal claim web)\n\nOpen the Godot project and run `scenes/main.tscn`.\n'

chmod +x "/workspace/simurgh_bootstrap.sh"
echo "Project scaffolded at $ROOT"