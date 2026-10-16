class_name Neighborhood
extends Node3D
## Builds the greybox neighborhood in code.
## The shop sits at the origin, door facing -Z onto Main St. Elm Ave runs north from Main;
## Hollow Rd crosses the far north end. A dark park fills the middle (shortcut, but scary).

const GRASS := Color(0.07, 0.09, 0.06)
const ASPHALT := Color(0.08, 0.08, 0.09)
const SIDEWALK := Color(0.25, 0.25, 0.27)
const LINE := Color(0.55, 0.45, 0.1)
const ROOF := Color(0.15, 0.1, 0.1)
const WOOD := Color(0.3, 0.18, 0.1)
const TRUNK := Color(0.2, 0.13, 0.08)
const LEAVES := Color(0.06, 0.16, 0.08)
const METAL := Color(0.15, 0.15, 0.16)
const WINDOW_DARK := Color(0.04, 0.05, 0.07)
const WINDOW_LIT := Color(1.0, 0.75, 0.4)
const LAMP_COLOR := Color(1.0, 0.62, 0.3)
const HOUSE_COLORS := [
	Color(0.45, 0.42, 0.35), Color(0.3, 0.38, 0.42), Color(0.42, 0.3, 0.3),
	Color(0.35, 0.4, 0.3), Color(0.5, 0.48, 0.45),
]
const CAR_COLORS := [
	Color(0.35, 0.08, 0.08), Color(0.1, 0.15, 0.3), Color(0.3, 0.3, 0.32), Color(0.2, 0.25, 0.15),
]

## All houses (every one can order); the first is the tutorial delivery.
var houses: Array[House] = []
var spawn_points: Array[Vector3] = []
var _rng := RandomNumberGenerator.new()
var _mats := {}


func _ready() -> void:
	_rng.seed = 1337
	spawn_points.assign([
		Vector3(-30, 0.5, -45), Vector3(-8, 0.5, -60), Vector3(-50, 0.5, -70), # park
		Vector3(36, 0.5, -45), Vector3(52, 0.5, -52), # Elm Ave + warehouse alley
		Vector3(-5, 0.5, -92), Vector3(-35, 0.5, -90), # Hollow Rd
		Vector3(-60, 0.5, -8), Vector3(60, 0.5, -10), # far ends of Main St
	])
	_build_ground()
	_build_shop_row()
	_build_houses()
	_build_park()
	_build_east_side()
	_build_props()
	_build_signs()
	_build_bounds()


# --- Layout ---------------------------------------------------------------

func _build_ground() -> void:
	# Road/sidewalk/line layers sit a few cm above the grass and have their own collision,
	# so dropped items rest on the surface you see instead of sinking into it.
	# (_surface gives them a deep collider: thin ones let resting objects sink in.)
	_box(Vector3(0, -0.5, -40), Vector3(160, 1, 140), GRASS)
	_surface(Vector3(0, 0.01, -6.5), Vector3(156, 0.02, 7), ASPHALT) # Main St
	_surface(Vector3(29.5, 0.01, -51.5), Vector3(7, 0.02, 83), ASPHALT) # Elm Ave
	_surface(Vector3(-3.5, 0.01, -89.5), Vector3(73, 0.02, 7), ASPHALT) # Hollow Rd
	_surface(Vector3(0, 0.02, -1.5), Vector3(156, 0.02, 3), SIDEWALK)
	_surface(Vector3(-26, 0.02, -11.5), Vector3(104, 0.02, 3), SIDEWALK)
	_surface(Vector3(55.5, 0.02, -11.5), Vector3(45, 0.02, 3), SIDEWALK)
	for x in range(-74, 76, 8):
		_surface(Vector3(x, 0.025, -6.5), Vector3(3, 0.01, 0.2), LINE)
	for z in range(-16, -86, -8):
		_surface(Vector3(29.5, 0.025, z), Vector3(0.2, 0.01, 3), LINE)


func _build_shop_row() -> void:
	# Storefronts on the south side of Main St, flanking the pizza shop.
	var row := [
		[-62.0, 30.0, 8.0, Color(0.22, 0.2, 0.24)],
		[-36.5, 21.0, 5.0, Color(0.3, 0.15, 0.1)],
		[-15.65, 18.5, 6.0, Color(0.33, 0.28, 0.2)], # stops short of the shop's bathroom stall
		[15.2, 19.4, 8.0, Color(0.2, 0.24, 0.28)],
		[39.0, 14.0, 6.0, Color(0.3, 0.15, 0.1)],
		[62.0, 30.0, 7.0, Color(0.25, 0.25, 0.22)],
	]
	for b in row:
		var x: float = b[0]
		var w: float = b[1]
		var h: float = b[2]
		_box(Vector3(x, h / 2.0, 5.0), Vector3(w, h, 10.0), b[3])
		var wx := x - w / 2.0 + 2.0
		while wx < x + w / 2.0 - 1.5:
			for wy: float in [1.6, 4.4]:
				if wy < h - 1.0:
					_window(Vector3(wx, wy, -0.03), Vector3(1.6, 1.2, 0.08), 0.2, self)
			wx += 3.5


func _build_houses() -> void:
	# Every house can order. The first one listed is the tutorial delivery (nearest the shop).
	_house(Vector3(-20, 0, -20.5), Vector3.BACK, "12 Main St")
	_house(Vector3(20.5, 0, -48), Vector3.RIGHT, "48 Elm Ave")
	_house(Vector3(-20, 0, -98.5), Vector3.BACK, "7 Hollow Rd")
	_house(Vector3(-42, 0, -20.5), Vector3.BACK, "18 Main St")
	_house(Vector3(-62, 0, -20.5), Vector3.BACK, "24 Main St")
	_house(Vector3(4, 0, -20.5), Vector3.BACK, "6 Main St")
	_house(Vector3(20.5, 0, -30), Vector3.RIGHT, "30 Elm Ave")
	_house(Vector3(20.5, 0, -66), Vector3.RIGHT, "66 Elm Ave")
	_house(Vector3(38.5, 0, -32), Vector3.LEFT, "31 Elm Ave")
	_house(Vector3(38.5, 0, -60), Vector3.LEFT, "61 Elm Ave")
	_house(Vector3(2, 0, -98.5), Vector3.BACK, "3 Hollow Rd")
	_house(Vector3(-40, 0, -98.5), Vector3.BACK, "11 Hollow Rd")


func _build_park() -> void:
	for gx in range(-70, 13, 8):
		for gz in range(-30, -86, -8):
			if _rng.randf() > 0.7:
				continue
			var pos := Vector3(gx + _rng.randf_range(-3, 3), 0, gz + _rng.randf_range(-3, 3))
			if _near_spawn(pos, 2.5):
				continue
			_tree(pos)
	# Tree line along the north and west edges so the map fades into woods.
	for x in range(-76, 77, 5):
		_tree(Vector3(x + _rng.randf_range(-1.5, 1.5), 0, -106 + _rng.randf_range(-1.5, 1.5)))
	for z in range(-26, -104, -5):
		_tree(Vector3(-75 + _rng.randf_range(-1.5, 1.5), 0, z))


func _build_east_side() -> void:
	_box(Vector3(60, 4, -32), Vector3(30, 8, 30), Color(0.18, 0.18, 0.2)) # warehouse
	_box(Vector3(60, 3, -75), Vector3(30, 6, 34), Color(0.2, 0.17, 0.15)) # warehouse
	_box(Vector3(50, 0.7, -50), Vector3(1.8, 1.4, 3.5), Color(0.12, 0.2, 0.15)) # dumpster in the alley
	_box(Vector3(28, 0.7, 3), Vector3(1.8, 1.4, 3.5), Color(0.12, 0.2, 0.15)) # dumpster behind Main


func _build_props() -> void:
	for lamp in [
		[Vector3(-64, 0, -2.7), "on"], [Vector3(-46, 0, -2.7), "dead"],
		[Vector3(-28, 0, -2.7), "flicker"], [Vector3(-10, 0, -2.7), "on"],
		[Vector3(10, 0, -2.7), "on"], [Vector3(28, 0, -2.7), "on"],
		[Vector3(46, 0, -2.7), "on"], [Vector3(64, 0, -2.7), "flicker"],
		[Vector3(25.3, 0, -25), "on"], [Vector3(25.3, 0, -55), "flicker"],
		[Vector3(-8, 0, -93.3), "flicker"], [Vector3(14, 0, -93.3), "dead"],
	]:
		_lamp(lamp[0], lamp[1])
	_car(Vector3(-40, 0, -4.3), true)
	_car(Vector3(18, 0, -4.3), true)
	_car(Vector3(-58, 0, -8.7), true)
	_car(Vector3(27.3, 0, -38), false)
	_car(Vector3(31.7, 0, -72), false)
	_car(Vector3(-10, 0, -91.5), true)


func _build_signs() -> void:
	# Corner signs: first name runs along X (east-west streets), second along Z (north-south).
	_street_sign(Vector3(25, 0, -12.8), ["MAIN ST", "ELM AVE"])
	_street_sign(Vector3(34.5, 0, -12.8), ["MAIN ST", "ELM AVE"])
	_street_sign(Vector3(25, 0, -85), ["HOLLOW RD", "ELM AVE"])
	_street_sign(Vector3(7, 0, -2.8), ["MAIN ST"])
	_street_sign(Vector3(-50, 0, -2.8), ["MAIN ST"])
	_street_sign(Vector3(-36, 0, -93.5), ["HOLLOW RD"])
	_park_sign(Vector3(-8, 0, -14.5), "WEXLEY PARK")


func _street_sign(pos: Vector3, names: Array) -> void:
	# Blades sit on top of the pole (not threaded onto it) so the pole never covers the text.
	var top := 2.85
	var pole_height := top - 0.15 - (names.size() - 1) * 0.3
	_box(pos + Vector3(0, pole_height / 2.0, 0), Vector3(0.08, pole_height, 0.08), METAL)
	for i in names.size():
		var blade := Node3D.new()
		blade.position = pos + Vector3(0, top - i * 0.3, 0)
		blade.rotation.y = 0.0 if i == 0 else PI / 2.0
		add_child(blade)
		# Faint glow so they read at night like reflective signs.
		_box(Vector3.ZERO, Vector3(1.5, 0.28, 0.04), Color(0.05, 0.32, 0.14), false, blade, 0.25)
		for side in [1.0, -1.0]:
			blade.add_child(_sign_label(names[i], Vector3(0, 0, 0.025 * side), 0.0 if side > 0 else PI, 0.005))


func _park_sign(pos: Vector3, text: String) -> void:
	# Board is mounted on the street-facing side of its posts, so the posts sit behind it.
	for x in [-1.0, 1.0]:
		_box(pos + Vector3(x, 0.7, 0), Vector3(0.12, 1.4, 0.12), WOOD)
	var board_z := 0.12
	_box(pos + Vector3(0, 1.2, board_z), Vector3(2.4, 0.7, 0.1), Color(0.35, 0.22, 0.12))
	add_child(_sign_label(text, pos + Vector3(0, 1.2, board_z + 0.055), 0.0, 0.007))


func _sign_label(text: String, pos: Vector3, yaw: float, pixel_size: float) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = 48
	l.pixel_size = pixel_size
	l.outline_size = 0
	l.modulate = Color(0.92, 0.95, 0.9)
	l.double_sided = false
	l.position = pos
	l.rotation.y = yaw
	return l


func _build_bounds() -> void:
	_wall(Vector3(-79, 5, -40), Vector3(1, 10, 140))
	_wall(Vector3(79, 5, -40), Vector3(1, 10, 140))
	_wall(Vector3(0, 5, 11), Vector3(160, 10, 1))
	_wall(Vector3(0, 5, -109), Vector3(160, 10, 1))


# --- Builders ---------------------------------------------------------------

func _house(root_pos: Vector3, facing: Vector3, address: String) -> void:
	var h := House.new()
	h.name = address.replace(" ", "")
	h.address = address
	h.position = root_pos
	h.rotation.y = atan2(facing.x, facing.z)
	add_child(h)

	# Local space: front of the house faces +Z.
	_box(Vector3(0, 2, 0), Vector3(8, 4, 7), HOUSE_COLORS[_rng.randi() % HOUSE_COLORS.size()], true, h)
	var prism := PrismMesh.new()
	prism.size = Vector3(8.8, 2.2, 7.6)
	prism.material = _mat(ROOF)
	var roof := MeshInstance3D.new()
	roof.mesh = prism
	roof.position = Vector3(0, 5.1, 0)
	h.add_child(roof)
	_surface(Vector3(0, 0.04, 4.5), Vector3(3, 0.08, 2), WOOD, h) # porch
	for wx: float in [-2.4, 2.4]:
		_window(Vector3(wx, 2.0, 3.52), Vector3(1.4, 1.1, 0.06), 0.25, h)

	var door := HouseDoor.new()
	door.name = "Door" # fixed name: knock RPCs must find the same node on every machine
	door.house = h
	door.position = Vector3(0, 1.05, 3.56)
	door.build(_mat(Color(0.25, 0.12, 0.08)))
	h.add_child(door)

	var sign := Label3D.new()
	sign.text = address
	sign.font_size = 40
	sign.pixel_size = 0.008
	sign.outline_size = 8
	sign.modulate = Color(0.85, 0.85, 0.75)
	sign.position = Vector3(0, 2.6, 3.6)
	h.add_child(sign)

	var bulb_mat := StandardMaterial3D.new()
	bulb_mat.albedo_color = Color(1, 0.85, 0.6)
	bulb_mat.emission_enabled = true
	bulb_mat.emission = Color(1, 0.8, 0.5)
	var bulb_mesh := SphereMesh.new()
	bulb_mesh.radius = 0.1
	bulb_mesh.height = 0.2
	bulb_mesh.material = bulb_mat
	var bulb := MeshInstance3D.new()
	bulb.mesh = bulb_mesh
	bulb.position = Vector3(0.9, 2.3, 3.62)
	h.add_child(bulb)

	var light := OmniLight3D.new()
	light.light_color = Color(1, 0.78, 0.45)
	light.omni_range = 7.0
	light.position = Vector3(0, 2.4, 4.6)
	h.add_child(light)

	h.porch_light = light
	h.bulb_material = bulb_mat
	h.chevron = _chevron()
	h.chevron.position = House.CHEVRON_POS
	h.chevron.scale = Vector3.ONE * 1.3
	h.add_child(h.chevron)
	if _rng.randf() < 0.4:
		h.idle_energy = 0.8 # some porches are lit anyway, so a lit porch alone isn't a giveaway
	h.set_active(false)
	houses.append(h)


## Glowing "V" that floats over the active delivery's porch.
func _chevron() -> CSGPolygon3D:
	var c := CSGPolygon3D.new()
	c.polygon = PackedVector2Array([
		Vector2(-0.4, 0.35), Vector2(0, -0.15), Vector2(0.4, 0.35),
		Vector2(0.22, 0.35), Vector2(0, 0.08), Vector2(-0.22, 0.35),
	])
	c.depth = 0.08
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1, 0.85, 0.4) # same gold as the compass marker
	c.material = mat
	c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return c


func _tree(pos: Vector3) -> void:
	var height := _rng.randf_range(4.0, 7.0)
	_cylinder(pos + Vector3(0, 0.75, 0), 0.25, 1.5, TRUNK, true)
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = _rng.randf_range(1.4, 2.0)
	cone.height = height
	cone.radial_segments = 6
	cone.material = _mat(LEAVES)
	var mi := MeshInstance3D.new()
	mi.mesh = cone
	mi.position = pos + Vector3(0, 1.2 + height / 2.0, 0)
	add_child(mi)


func _lamp(pos: Vector3, state: String) -> void:
	_box(pos + Vector3(0, 2.25, 0), Vector3(0.15, 4.5, 0.15), METAL)
	var lit := state != "dead"
	_box(pos + Vector3(0, 4.5, 0), Vector3(0.5, 0.15, 0.3), LAMP_COLOR if lit else METAL, false, null, 3.0 if lit else 0.0)
	if not lit:
		return
	var light: OmniLight3D
	if state == "flicker":
		light = FlickerLight.new()
	else:
		light = OmniLight3D.new()
	light.light_color = LAMP_COLOR
	light.light_energy = 1.8
	light.omni_range = 11.0
	light.position = pos + Vector3(0, 4.2, 0)
	add_child(light)


func _car(pos: Vector3, along_x: bool) -> void:
	var color: Color = CAR_COLORS[_rng.randi() % CAR_COLORS.size()]
	var body := Vector3(4.2, 0.8, 1.8) if along_x else Vector3(1.8, 0.8, 4.2)
	var cab := Vector3(2.2, 0.6, 1.6) if along_x else Vector3(1.6, 0.6, 2.2)
	_box(pos + Vector3(0, 0.6, 0), body, color)
	_box(pos + Vector3(0, 1.3, 0), cab, color.darkened(0.4))


func _window(pos: Vector3, size: Vector3, lit_chance: float, parent: Node3D) -> void:
	var lit := _rng.randf() < lit_chance
	_box(pos, size, WINDOW_LIT if lit else WINDOW_DARK, false, parent, 1.2 if lit else 0.0)


# --- Primitives ---------------------------------------------------------------

func _box(pos: Vector3, size: Vector3, color: Color, collide := true, parent: Node3D = null, emission := 0.0) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = _mat(color, emission)
	var shape := BoxShape3D.new()
	shape.size = size
	_place(mesh, shape if collide else null, pos, parent)


## A thin walkable layer (road, sidewalk, porch). The mesh is as thin as it looks, but the
## collider extends well below it, so objects can't sink into or slip through it.
func _surface(pos: Vector3, size: Vector3, color: Color, parent: Node3D = null) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = _mat(color)
	var depth := 0.5
	var shape := BoxShape3D.new()
	shape.size = Vector3(size.x, size.y + depth, size.z)
	if parent == null:
		parent = self
	var body := StaticBody3D.new()
	body.position = pos
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position.y = -depth / 2.0 # keep the top flush with the mesh
	body.add_child(col)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	body.add_child(mi)
	parent.add_child(body)


func _cylinder(pos: Vector3, radius: float, height: float, color: Color, collide: bool) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 6
	mesh.material = _mat(color)
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	_place(mesh, shape if collide else null, pos, null)


func _wall(pos: Vector3, size: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	_place(null, shape, pos, null)


## Adds a mesh (optional) with a static collider (optional) at pos under parent.
func _place(mesh: Mesh, shape: Shape3D, pos: Vector3, parent: Node3D) -> void:
	if parent == null:
		parent = self
	var root: Node3D
	if shape:
		root = StaticBody3D.new()
		var col := CollisionShape3D.new()
		col.shape = shape
		root.add_child(col)
	else:
		root = Node3D.new()
	if mesh:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		root.add_child(mi)
	root.position = pos
	parent.add_child(root)


func _mat(color: Color, emission := 0.0) -> StandardMaterial3D:
	var key := "%s_%s" % [color.to_html(), emission]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 1.0
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	_mats[key] = m
	return m


func _near_spawn(pos: Vector3, radius: float) -> bool:
	for p in spawn_points:
		if Vector2(p.x - pos.x, p.z - pos.z).length() < radius:
			return true
	return false
