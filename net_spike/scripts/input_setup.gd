extends Node
## Registers input actions at startup.

const KEYS := {
	"move_forward": [KEY_W], "move_back": [KEY_S], "move_left": [KEY_A], "move_right": [KEY_D],
	"sprint": [KEY_SHIFT], "jump": [KEY_SPACE], "interact": [KEY_E],
}


func _ready() -> void:
	for action: String in KEYS:
		InputMap.add_action(action)
		for key: Key in KEYS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)
	InputMap.add_action("throw")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_RIGHT
	InputMap.action_add_event("throw", click)
