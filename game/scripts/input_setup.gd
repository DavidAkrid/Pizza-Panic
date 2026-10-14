extends Node
## Registers input actions at startup so the bindings live in one readable place.

const KEYS := {
	"move_forward": [KEY_W, KEY_UP],
	"move_back": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"sprint": [KEY_SHIFT],
	"jump": [KEY_SPACE],
	"interact": [KEY_E],
	"flashlight": [KEY_F],
	"slot_1": [KEY_1], "slot_2": [KEY_2], "slot_3": [KEY_3],
	"slot_4": [KEY_4], "slot_5": [KEY_5], "slot_6": [KEY_6],
}


func _ready() -> void:
	for action: String in KEYS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key: Key in KEYS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)
	for pair in [["attack", MOUSE_BUTTON_LEFT], ["throw", MOUSE_BUTTON_RIGHT],
			["slot_next", MOUSE_BUTTON_WHEEL_DOWN], ["slot_prev", MOUSE_BUTTON_WHEEL_UP]]:
		InputMap.add_action(pair[0])
		var click := InputEventMouseButton.new()
		click.button_index = pair[1]
		InputMap.action_add_event(pair[0], click)
