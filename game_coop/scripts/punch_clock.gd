class_name PunchClock
extends StationBase
## The punch clock (the ready check) and the shop's wall clock above it. Builds its own look;
## faces +Z (meant for the shop's front wall, inside). In the deep night everyone punches in;
## once the whole crew is in, the night ends (NightCycle).

var _hour_hand: Node3D
var _minute_hand: Node3D
var _cards: Label3D


func _ready() -> void:
	collision_layer = 3
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.45, 0.6, 0.3)
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = Vector3(0, 1.3, 0.15)
	add_child(col)

	# The machine: a boxy steel clock with a card slot, and a card rack next to it.
	_box(Vector3(0.4, 0.55, 0.25), Vector3(0, 1.3, 0.13), _mat(Color(0.55, 0.57, 0.6), 0.5))
	_box(Vector3(0.22, 0.03, 0.05), Vector3(0, 1.45, 0.27), _mat(Color(0.05, 0.05, 0.05)))
	_box(Vector3(0.3, 0.12, 0.02), Vector3(0, 1.22, 0.26), _mat(Color(0.9, 0.85, 0.7)))
	_box(Vector3(0.3, 0.5, 0.06), Vector3(0.45, 1.3, 0.03), _mat(Color(0.35, 0.25, 0.15)))
	for i in 4:
		_box(Vector3(0.08, 0.14, 0.01), Vector3(0.36 + i % 2 * 0.17 * 0.6, 1.42 - (i / 2) * 0.2, 0.07), _mat(Color(0.95, 0.93, 0.85)))
	var tag := Label3D.new()
	tag.text = "PUNCH CLOCK"
	tag.pixel_size = 0.003
	tag.font_size = 32
	tag.outline_size = 6
	tag.position = Vector3(0, 1.65, 0.1)
	add_child(tag)
	_cards = Label3D.new()
	_cards.pixel_size = 0.0025
	_cards.font_size = 32
	_cards.outline_size = 6
	_cards.position = Vector3(0, 0.95, 0.15)
	add_child(_cards)

	# The wall clock: a white face with an hour and a minute hand.
	var face := CylinderMesh.new()
	face.top_radius = 0.32
	face.bottom_radius = 0.32
	face.height = 0.05
	face.material = _mat(Color(0.95, 0.93, 0.85))
	var rim := CylinderMesh.new()
	rim.top_radius = 0.35
	rim.bottom_radius = 0.35
	rim.height = 0.04
	rim.material = _mat(Color(0.15, 0.12, 0.1))
	_add(rim, Vector3(0, 2.6, 0.02)).rotation.x = PI / 2.0
	_add(face, Vector3(0, 2.6, 0.03)).rotation.x = PI / 2.0
	var tick := _mat(Color(0.1, 0.1, 0.1))
	for i in 12:
		var a := TAU * i / 12.0
		_box(Vector3(0.02, 0.05 if i % 3 == 0 else 0.03, 0.01), Vector3(sin(a) * 0.27, 2.6 + cos(a) * 0.27, 0.06), tick).rotation.z = -a
	_hour_hand = _hand(0.16, 0.035, Color(0.1, 0.1, 0.1))
	_minute_hand = _hand(0.25, 0.022, Color(0.1, 0.1, 0.1))


func _process(_delta: float) -> void:
	var night := NightCycle.instance
	if night == null:
		return
	var h := night.hour()
	_hour_hand.rotation.z = -TAU * fmod(h, 12.0) / 12.0
	_minute_hand.rotation.z = -TAU * fmod(h, 1.0)
	if night.phase == NightCycle.Phase.DEEP_NIGHT:
		_cards.text = "%d/%d clocked in" % [night.clocked_in.size(), night.crew_size()]
	else:
		_cards.text = ""


func get_prompt(p: Player) -> String:
	var night := NightCycle.instance
	match night.phase:
		NightCycle.Phase.DEEP_NIGHT:
			var count := "(%d/%d)" % [night.clocked_in.size(), night.crew_size()]
			if p.name.to_int() in night.clocked_in:
				return "Clocked in %s - waiting for the crew" % count
			return "[E] Clock in %s" % count
		NightCycle.Phase.TIME_SKIP:
			return ""
	return "Punch clock - clock in after closing (2 AM)"


## Host: punch this player's card.
func _use(p: Player, _held: Item, _slot: int) -> void:
	NightCycle.instance.clock_in(p)


func _hand(length: float, width: float, color: Color) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = Vector3(0, 2.6, 0.07)
	add_child(pivot)
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(width, length, 0.01)
	mesh.material = _mat(color)
	mi.mesh = mesh
	mi.position = Vector3(0, length / 2.0 - 0.03, 0)
	pivot.add_child(mi)
	return pivot


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
