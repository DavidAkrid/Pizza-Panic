class_name HouseDoor
extends StaticBody3D
## Front door of a house. Anyone can knock; at the house with the order, the door cracks open
## and the customer leans out around the frame, takes what they ordered, and ducks back in.

const KNOCK := preload("res://audio/knock.wav")
const SIZE := Vector3(1.1, 2.1, 0.12)
const SKIN_TONES := [Color(0.95, 0.8, 0.65), Color(0.78, 0.57, 0.4), Color(0.55, 0.38, 0.26), Color(0.36, 0.24, 0.16)]
const SHIRTS := [Color(0.3, 0.45, 0.7), Color(0.7, 0.3, 0.3), Color(0.35, 0.6, 0.35), Color(0.8, 0.7, 0.3), Color(0.5, 0.5, 0.5)]

var house: House
var _busy := false # mid-knock or mid-visit
var _hinge: Node3D
var _customer: Node3D
var _head: Node3D
var _arms: Array[Node3D] = []
var _flap_t := 0.0
var _flap_speed := 14.0
var _peek_pivot: Node3D # at the latch-side door frame; the customer swings out around it

const DOOR_OPEN := -0.95 # radians: about halfway
const PEEK_HIDDEN := -PI / 2.0 # pivot angle with the customer tucked inside the wall
const PEEK_LEAN := deg_to_rad(-20.0) # sideways tilt away from the door: head out past the frame
var _audio: AudioStreamPlayer3D


## Builds the door, the dark doorway behind it, and the (hidden) customer. Origin = door center.
func build(door_material: Material) -> void:
	collision_layer = 3
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = SIZE
	col.shape = shape
	add_child(col)

	# Black plane just in front of the wall: what you see through the open door.
	var dark := MeshInstance3D.new()
	var plane := QuadMesh.new()
	plane.size = Vector2(SIZE.x, SIZE.y)
	var black := StandardMaterial3D.new()
	black.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	black.albedo_color = Color(0.01, 0.01, 0.015)
	plane.material = black
	dark.mesh = plane
	dark.position.z = -0.05
	add_child(dark)

	# The door swings on a hinge at its left edge.
	_hinge = Node3D.new()
	_hinge.position.x = -SIZE.x / 2.0
	add_child(_hinge)
	var panel := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = SIZE
	box.material = door_material
	panel.mesh = box
	panel.position.x = SIZE.x / 2.0
	_hinge.add_child(panel)

	_peek_pivot = Node3D.new()
	_peek_pivot.position = Vector3(SIZE.x / 2.0, -SIZE.y / 2.0, 0)
	_peek_pivot.rotation.y = PEEK_HIDDEN
	_peek_pivot.visible = false
	add_child(_peek_pivot)
	_customer = _build_customer()
	_customer.position = Vector3(-0.5, 0, 0.15) # feet mid-doorway, relative to the pivot
	_peek_pivot.add_child(_customer)

	_audio = AudioStreamPlayer3D.new()
	_audio.stream = KNOCK
	add_child(_audio)


func _process(delta: float) -> void:
	if not _peek_pivot.visible:
		return
	# Excited little arm flap: both arms bob up and down, slightly out of sync.
	_flap_t += delta
	for i in _arms.size():
		_arms[i].rotation.x = -0.25 + sin(_flap_t * _flap_speed + i * 0.9) * 0.4
	# Head tracks the player (body keeps its lean). Eased so it turns rather than snaps.
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var to := cam.global_position - _head.global_position
	if to.length() < 0.01:
		return
	var target := Basis.looking_at(to, Vector3.UP, true) # true: +Z (the face) points at the target
	_head.global_basis = _head.global_basis.slerp(target, clampf(10.0 * delta, 0.0, 1.0))


# CO-OP TODO (orders step): prompts/deliveries come back once orders are host-owned.
func get_prompt(_p: Player) -> String:
	return "" if _busy else "[E] Knock"


func interact(p: Player) -> void:
	if _busy:
		return
	_busy = true
	_audio.play()
	await get_tree().create_timer(0.55).timeout
	# CO-OP TODO (orders step): open up and _visit() at the order house, synced to everyone.
	_busy = false


## Door cracks open, customer leans out around the frame and grabs the order straight away,
## hangs around a random moment, ducks back in. Speed and linger time vary per visit.
func _visit(p: Player) -> void:
	var pace := randf_range(0.75, 1.3) # >1 = snappier
	var linger := randf_range(0.4, 1.6)
	var lean := PEEK_LEAN + randf_range(-0.06, 0.06)
	_customer.rotation.z = 0.0
	_head.rotation = Vector3.ZERO
	_flap_t = 0.0
	_flap_speed = randf_range(12.0, 17.0)
	_peek_pivot.rotation.y = PEEK_HIDDEN
	_peek_pivot.visible = true
	var tw := create_tween().set_parallel()
	tw.tween_property(_hinge, "rotation:y", DOOR_OPEN, 0.18 / pace).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(_peek_pivot, "rotation:y", 0.0, 0.3 / pace).set_delay(0.08 / pace).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(_customer, "rotation:z", lean, 0.3 / pace).set_delay(0.08 / pace).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	await get_tree().create_timer(0.2 / pace).timeout # as soon as they're in view
	# CO-OP TODO (orders step): hand over the order here.
	await tw.finished
	await get_tree().create_timer(linger).timeout
	tw = create_tween().set_parallel()
	tw.tween_property(_peek_pivot, "rotation:y", PEEK_HIDDEN, 0.2 / pace).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(_customer, "rotation:z", 0.0, 0.2 / pace).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(_hinge, "rotation:y", 0.0, 0.2 / pace).set_delay(0.12 / pace).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	await tw.finished
	_peek_pivot.visible = false


## A simple low-poly person, feet at the origin, facing +Z (out the front door).
func _build_customer() -> Node3D:
	var root := Node3D.new()
	var shirt := StandardMaterial3D.new()
	shirt.albedo_color = SHIRTS.pick_random()
	var skin := StandardMaterial3D.new()
	skin.albedo_color = SKIN_TONES.pick_random()
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.05, 0.05, 0.05)

	var body := CapsuleMesh.new()
	body.radius = 0.22
	body.height = 1.3
	body.radial_segments = 8
	body.material = shirt
	_part(root, body, Vector3(0, 0.75, 0))
	var head := SphereMesh.new()
	head.radius = 0.14
	head.height = 0.28
	head.radial_segments = 8
	head.rings = 4
	head.material = skin
	_head = Node3D.new() # head + eyes turn together to look at the player
	_head.position = Vector3(0, 1.58, 0)
	root.add_child(_head)
	_part(_head, head, Vector3.ZERO)
	var eye := SphereMesh.new()
	eye.radius = 0.02
	eye.height = 0.04
	eye.material = dark
	_part(_head, eye, Vector3(-0.05, 0.02, 0.12))
	_part(_head, eye, Vector3(0.05, 0.02, 0.12))
	var arm := BoxMesh.new()
	arm.size = Vector3(0.09, 0.09, 0.4)
	arm.material = skin
	_arms.clear()
	for x in [-0.14, 0.14]: # arms out, reaching for the food; each swings from the shoulder
		var shoulder := Node3D.new()
		shoulder.position = Vector3(x, 1.1, 0.02)
		root.add_child(shoulder)
		_part(shoulder, arm, Vector3(0, 0, 0.18))
		_arms.append(shoulder)
	return root


func _part(root: Node3D, mesh: Mesh, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	root.add_child(mi)
