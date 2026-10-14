class_name Pizza
extends RefCounted
## One pizza's state as it goes dough -> oven -> box -> customer.

enum Stage { RAW, BAKED, BOXED }

const TOPPINGS := {
	"Pepperoni": Color(0.7, 0.12, 0.08),
	"Mushroom": Color(0.78, 0.7, 0.55),
	"Olive": Color(0.06, 0.06, 0.06),
	"Pepper": Color(0.2, 0.6, 0.15),
}

const CRUST_COLORS := {
	"": Color(0.93, 0.85, 0.65),
	"undercooked": Color(0.92, 0.8, 0.6),
	"perfect": Color(0.86, 0.58, 0.28),
	"overdone": Color(0.55, 0.33, 0.15),
	"burnt": Color(0.15, 0.1, 0.06),
}

var toppings: Array[String] = []
var stage := Stage.RAW
var bake_quality := 0.0
var bake_label := ""
var condition := 100.0


func describe() -> String:
	var what := ""
	match stage:
		Stage.RAW: what = "Raw pizza"
		Stage.BAKED: what = "%s pizza" % bake_label.capitalize()
		Stage.BOXED: what = "Boxed pizza"
	if not toppings.is_empty():
		what += " (" + ", ".join(PackedStringArray(toppings)) + ")"
	if condition < 100.0:
		what += " - %d%% intact" % int(condition)
	return what


## Simple low-poly model of this pizza, for the player's hands.
func build_visual() -> Node3D:
	var root := Node3D.new()
	if stage == Stage.BOXED:
		var box := BoxMesh.new()
		box.size = Vector3(0.44, 0.07, 0.44)
		var cardboard := Color(0.72, 0.55, 0.35).darkened(0.6 * (1.0 - condition / 100.0))
		root.add_child(_mesh(box, cardboard, Vector3.ZERO))
		return root

	var crust := CylinderMesh.new()
	crust.top_radius = 0.2
	crust.bottom_radius = 0.2
	crust.height = 0.03
	crust.radial_segments = 12
	root.add_child(_mesh(crust, CRUST_COLORS[bake_label], Vector3.ZERO))

	var sauce := CylinderMesh.new()
	sauce.top_radius = 0.16
	sauce.bottom_radius = 0.16
	sauce.height = 0.01
	sauce.radial_segments = 12
	root.add_child(_mesh(sauce, Color(0.6, 0.1, 0.05), Vector3(0, 0.018, 0)))

	for i in toppings.size():
		var piece := CylinderMesh.new()
		piece.top_radius = 0.025
		piece.bottom_radius = 0.025
		piece.height = 0.012
		piece.radial_segments = 6
		for k in 4:
			var angle := i * 0.8 + k * TAU / 4.0
			var r := 0.06 if i % 2 == 0 else 0.11
			var pos := Vector3(cos(angle) * r, 0.026, sin(angle) * r)
			root.add_child(_mesh(piece, TOPPINGS[toppings[i]], pos))
	return root


func _mesh(mesh: PrimitiveMesh, color: Color, pos: Vector3) -> MeshInstance3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi
