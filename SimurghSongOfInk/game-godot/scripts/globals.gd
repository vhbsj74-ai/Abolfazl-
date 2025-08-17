extends Node
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
