class_name FlickerLight
extends OmniLight3D
## Cuts out at random like a dying street lamp.

var _base_energy := 1.0
var _timer := 0.0


func _ready() -> void:
	_base_energy = light_energy


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	if light_energy > 0.0 and randf() < 0.35:
		light_energy = 0.0
		_timer = randf_range(0.05, 0.4)
	else:
		light_energy = _base_energy * randf_range(0.7, 1.0)
		_timer = randf_range(0.1, 2.5)
