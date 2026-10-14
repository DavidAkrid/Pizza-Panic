class_name House
extends Node3D
## A house on the map. The active delivery target lights its porch.

var address := ""
var porch_light: OmniLight3D
var bulb_material: StandardMaterial3D
var idle_energy := 0.0


func set_active(active: bool) -> void:
	var energy := 3.0 if active else idle_energy
	porch_light.light_energy = energy
	porch_light.visible = energy > 0.0
	bulb_material.emission_energy_multiplier = energy * 2.0


## Where the HUD waypoint points.
func marker_position() -> Vector3:
	return to_global(Vector3(0, 2.0, 5.0))
