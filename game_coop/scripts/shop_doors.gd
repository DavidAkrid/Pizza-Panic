class_name ShopDoors
extends Node3D
## The shop's front double doors, built in code. They swing open on their own when anyone comes
## near (away from whoever's walking through) and fall shut behind them. Every machine works it
## out locally from the synced player positions, so nothing needs to be sent.
## Origin = floor, center of the doorway; outside is -Z.

const WIDTH := 1.6 ## the doorway
const HEIGHT := 2.35
const OPEN_ANGLE := 1.45 ## radians
const TRIGGER_RANGE := 2.2 ## a player this close opens them
const SPEED := 6.0

var _left: Node3D # hinge on the left (-X) side
var _right: Node3D
var _open := 0.0 # -1 = swung outward, 0 = shut, 1 = swung inward


func _ready() -> void:
	var frame := StandardMaterial3D.new()
	frame.albedo_color = Color(0.45, 0.12, 0.08)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.6, 0.75, 0.8, 0.35)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.metallic = 0.4
	glass.roughness = 0.1
	_left = _door(-1.0, frame, glass)
	_right = _door(1.0, frame, glass)


## One door: hinged at x = side * WIDTH/2, the panel reaching toward the middle.
func _door(side: float, frame: Material, glass: Material) -> Node3D:
	var hinge := Node3D.new()
	hinge.position = Vector3(side * WIDTH / 2.0, 0, 0)
	add_child(hinge)
	var w := WIDTH / 2.0 - 0.02
	var mid := -side * w / 2.0
	# A frame around a glass pane, so you can see out (and in).
	_box(hinge, Vector3(w, 0.9, 0.05), Vector3(mid, 0.45, 0), frame) # kick plate
	_box(hinge, Vector3(w, 0.2, 0.05), Vector3(mid, HEIGHT - 0.1, 0), frame) # top rail
	_box(hinge, Vector3(0.1, HEIGHT - 1.1, 0.05), Vector3(side * -0.05, 0.9 + (HEIGHT - 1.1) / 2.0, 0), frame)
	_box(hinge, Vector3(0.1, HEIGHT - 1.1, 0.05), Vector3(-side * (w - 0.05), 0.9 + (HEIGHT - 1.1) / 2.0, 0), frame)
	_box(hinge, Vector3(w - 0.2, HEIGHT - 1.1, 0.02), Vector3(mid, 0.9 + (HEIGHT - 1.1) / 2.0, 0), glass)
	_box(hinge, Vector3(0.04, 0.3, 0.12), Vector3(-side * (w - 0.12), 1.05, 0), frame) # push bar
	return hinge


func _process(delta: float) -> void:
	# Open away from the nearest player in range; shut when nobody's there.
	var target := 0.0
	var best := TRIGGER_RANGE
	if World.instance:
		for p: Player in World.instance.players.get_children():
			var d := p.global_position.distance_to(global_position)
			if d < best:
				best = d
				target = 1.0 if to_local(p.global_position).z < 0.0 else -1.0
	# Once swinging one way, keep going that way until shut (no slamming through a person).
	if _open != 0.0 and target != 0.0 and signf(target) != signf(_open):
		target = signf(_open)
	_open = move_toward(_open, target, SPEED * delta * (0.6 if target == 0.0 else 1.0))
	var a := OPEN_ANGLE * _open
	_left.rotation.y = -a # inward = +Z: the left door turns clockwise from above
	_right.rotation.y = a


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	parent.add_child(mi)
