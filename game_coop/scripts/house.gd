class_name House
extends Node3D
## A house on the map. The active delivery target lights its porch.

var address := ""
var porch_light: OmniLight3D
var bulb_material: StandardMaterial3D
var idle_energy := 0.0
var chevron: Node3D ## floating marker over the porch, shown while this house has the order

const CHEVRON_POS := Vector3(0, 3.45, 4.6)
var _t := 0.0


func set_active(active: bool) -> void:
	var energy := 3.0 if active else idle_energy
	porch_light.light_energy = energy
	porch_light.visible = energy > 0.0
	bulb_material.emission_energy_multiplier = energy * 2.0
	if chevron:
		chevron.visible = active
	set_process(active and chevron != null)


func _process(delta: float) -> void:
	# Bob gently and turn to face the camera so the V always reads.
	_t += delta
	chevron.position = CHEVRON_POS + Vector3(0, sin(_t * 2.0) * 0.12, 0)
	var cam := get_viewport().get_camera_3d()
	if cam:
		var to := cam.global_position - chevron.global_position
		chevron.global_rotation = Vector3(0, atan2(to.x, to.z), 0)


## Where the HUD waypoint points.
func marker_position() -> Vector3:
	return to_global(Vector3(0, 2.0, 5.0))
