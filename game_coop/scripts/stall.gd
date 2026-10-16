class_name BathroomStall
extends Node3D
## The shop's bathroom stall, built in code: where you come back after bleeding out. The door
## faces local -X and sits flush with the shop wall (the stall is set into it: the wall has a
## doorway cut out, and the stall brings its own back wall, roof and floor). On a respawn the
## toilet flushes, the door swings open, and you step out. Origin = floor, center of the stall.

const FLUSH := preload("res://audio/flush.wav")
const SIZE := Vector3(1.2, 2.1, 1.4) # depth (x), height, width (z)
const DOOR_WIDTH := 0.8
const DOOR_OPEN := -1.4 # radians: swings out into the shop

var _hinge: Node3D
var _audio: AudioStreamPlayer3D


## The toilet itself: E flushes it (for everyone to hear). Purely for fun.
class Toilet extends StaticBody3D:
	var stall: BathroomStall

	func get_prompt(_p: Player) -> String:
		return "" if stall.is_flushing() else "[E] Flush"

	func interact(_p: Player) -> void:
		stall.request_flush.rpc_id(1)


func _ready() -> void:
	var wall_mat := _mat(Color(0.55, 0.7, 0.68))
	var body := StaticBody3D.new()
	add_child(body)
	var half := SIZE / 2.0
	# Two side partitions and the bits of front wall either side of the door.
	_wall(body, Vector3(SIZE.x, SIZE.y, 0.05), Vector3(0, half.y, -half.z), wall_mat)
	_wall(body, Vector3(SIZE.x, SIZE.y, 0.05), Vector3(0, half.y, half.z), wall_mat)
	var side := (SIZE.z - DOOR_WIDTH) / 2.0
	_wall(body, Vector3(0.05, SIZE.y, side), Vector3(-half.x, half.y, -half.z + side / 2.0), wall_mat)
	_wall(body, Vector3(0.05, SIZE.y, side), Vector3(-half.x, half.y, half.z - side / 2.0), wall_mat)
	# Back wall, roof and a tiled floor: the stall pokes out past the shop.
	_wall(body, Vector3(0.05, SIZE.y, SIZE.z), Vector3(half.x, half.y, 0), wall_mat)
	_wall(body, Vector3(SIZE.x, 0.05, SIZE.z), Vector3(0, SIZE.y + 0.025, 0), wall_mat)
	_wall(body, Vector3(SIZE.x, 0.1, SIZE.z), Vector3(0, -0.03, 0), _mat(Color(0.85, 0.85, 0.8)))
	var bulb := OmniLight3D.new()
	bulb.light_color = Color(1, 0.95, 0.85)
	bulb.light_energy = 0.6
	bulb.omni_range = 2.0
	bulb.position = Vector3(0, SIZE.y - 0.2, 0)
	add_child(bulb)

	# The door (no collider: you walk straight out of it).
	_hinge = Node3D.new()
	_hinge.position = Vector3(-half.x, 0, -DOOR_WIDTH / 2.0)
	add_child(_hinge)
	var door := _box(Vector3(0.04, SIZE.y - 0.25, DOOR_WIDTH), Vector3(0, SIZE.y / 2.0 + 0.05, DOOR_WIDTH / 2.0), _mat(Color(0.45, 0.6, 0.58)))
	door.reparent(_hinge, false)
	var knob := _box(Vector3(0.06, 0.06, 0.06), Vector3(-0.04, 1.0, DOOR_WIDTH - 0.1), _mat(Color(0.8, 0.8, 0.75), 0.7))
	knob.reparent(_hinge, false)

	# The toilet, against the back (the shop wall).
	var porcelain := _mat(Color(0.95, 0.95, 0.93))
	var bowl := CylinderMesh.new()
	bowl.top_radius = 0.22
	bowl.bottom_radius = 0.16
	bowl.height = 0.42
	bowl.material = porcelain
	_add(bowl, Vector3(half.x - 0.32, 0.21, 0))
	_box(Vector3(0.18, 0.4, 0.45), Vector3(half.x - 0.1, 0.62, 0), porcelain)
	var toilet := Toilet.new()
	toilet.stall = self
	toilet.collision_layer = 2 # the interact ray finds it
	toilet.collision_mask = 0
	toilet.position = Vector3(half.x - 0.25, 0.42, 0)
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.5, 0.84, 0.45)
	var col := CollisionShape3D.new()
	col.shape = shape
	toilet.add_child(col)
	add_child(toilet)

	var tag := Label3D.new()
	tag.text = "RESTROOM"
	tag.pixel_size = 0.003
	tag.font_size = 32
	tag.outline_size = 6
	tag.position = Vector3(-half.x - 0.03, SIZE.y + 0.15, 0)
	tag.rotation.y = -PI / 2.0 # reads from -X
	add_child(tag)

	_audio = AudioStreamPlayer3D.new()
	_audio.stream = FLUSH
	_audio.position = Vector3(half.x - 0.3, 0.6, 0)
	add_child(_audio)


## Where a respawning player stands (in front of the toilet, facing the door).
func spawn_position() -> Vector3:
	return to_global(Vector3(-0.2, 0.05, 0))


func spawn_yaw() -> float:
	return global_rotation.y + PI / 2.0 # facing -X


func is_flushing() -> bool:
	return _audio.playing


## Anyone: flush the toilet. The host checks you're actually in there.
@rpc("any_peer", "call_local", "reliable")
func request_flush() -> void:
	if not multiplayer.is_server() or _audio.playing:
		return
	var id := multiplayer.get_remote_sender_id()
	var p := World.instance.player(id if id != 0 else 1)
	if p and p.global_position.distance_to(to_global(Vector3.ZERO)) < 2.5:
		_flush.rpc()


@rpc("authority", "call_local", "reliable")
func _flush() -> void:
	_audio.play()


## Every machine: flush, door swings open, then shut again.
@rpc("authority", "call_local", "reliable")
func play_respawn() -> void:
	_audio.play()
	var tw := create_tween()
	tw.tween_interval(0.5)
	tw.tween_property(_hinge, "rotation:y", DOOR_OPEN, 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_interval(2.5)
	tw.tween_property(_hinge, "rotation:y", 0.0, 0.5).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_QUAD)


func _wall(body: StaticBody3D, size: Vector3, pos: Vector3, mat: Material) -> void:
	_box(size, pos, mat)
	var shape := BoxShape3D.new()
	shape.size = size
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = pos
	body.add_child(col)


func _box(size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = mat
	return _add(mesh, pos)


func _add(mesh: Mesh, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	add_child(mi)
	return mi


func _mat(color: Color, metallic := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	return m
