class_name UpgradeStation
extends StaticBody3D
## A plaque on the shop wall selling one upgrade (see GameState.UPGRADES). Builds its own look.
## Upgrades are personal; the team's money pays. Prices shown are YOUR next level.
## Faces -X: meant to hang on the shop's right wall.

@export var upgrade_id := "shoes"

var _label: Label3D


func _ready() -> void:
	collision_layer = 3
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.12, 0.8, 0.8)
	var col := CollisionShape3D.new()
	col.shape = shape
	add_child(col)

	var board := BoxMesh.new()
	board.size = Vector3(0.05, 0.8, 0.8)
	board.material = _mat(Color(0.3, 0.18, 0.1))
	_add(board, Vector3.ZERO)
	_build_icon()

	_label = Label3D.new()
	_label.pixel_size = 0.0035
	_label.font_size = 32
	_label.outline_size = 6
	_label.position = Vector3(-0.04, -0.24, 0)
	_label.rotation.y = -PI / 2.0 # face into the room (-X)
	add_child(_label)
	_refresh()


func get_prompt(p: Player) -> String:
	var game := GameState.instance
	var info: Dictionary = GameState.UPGRADES[upgrade_id]
	var cost := game.upgrade_cost(p, upgrade_id)
	if cost < 0:
		return "%s - maxed out" % info.name
	var line := "%s %d - $%d (%s)" % [info.name, game.upgrade_level(p, upgrade_id) + 1, cost, info.effect]
	return "[E] Buy " + line if game.money >= cost else line


func interact(_p: Player) -> void:
	_request_buy.rpc_id(1)


## Host: team money pays, the upgrade is the buyer's own.
@rpc("any_peer", "call_local", "reliable")
func _request_buy() -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	var p := World.instance.player(id if id != 0 else 1)
	if p and p.global_position.distance_to(global_position) < 3.5:
		GameState.instance.buy_upgrade(p, upgrade_id)


func _process(_delta: float) -> void:
	_refresh() # prices are per player, so show this machine's player's levels


func _refresh() -> void:
	var info: Dictionary = GameState.UPGRADES[upgrade_id]
	var me := World.instance.local_player() if World.instance else null
	var level := GameState.instance.upgrade_level(me, upgrade_id) if me and GameState.instance else 0
	var costs: Array = info.costs
	var price := "MAX" if level >= costs.size() else "$%d" % costs[level]
	_label.text = "%s\n%s  (%d/%d)" % [info.name, price, level, costs.size()]


## A simple prop that hints at what the upgrade is.
func _build_icon() -> void:
	var at := Vector3(-0.06, 0.12, 0)
	match upgrade_id:
		"shoes":
			var shoe := BoxMesh.new()
			shoe.size = Vector3(0.1, 0.1, 0.28)
			shoe.material = _mat(Color(0.8, 0.15, 0.15))
			_add(shoe, at)
			var sole := BoxMesh.new()
			sole.size = Vector3(0.11, 0.03, 0.3)
			sole.material = _mat(Color(0.95, 0.95, 0.95))
			_add(sole, at + Vector3(0, -0.06, 0))
		"bag":
			var bag := BoxMesh.new()
			bag.size = Vector3(0.12, 0.28, 0.24)
			bag.material = _mat(Color(0.45, 0.32, 0.18))
			_add(bag, at)
		"knuckles":
			var ring := TorusMesh.new()
			ring.inner_radius = 0.02
			ring.outer_radius = 0.04
			ring.material = _mat(Color(0.85, 0.7, 0.25), 0.6)
			for i in 4:
				var mi := _add(ring, at + Vector3(0, 0, -0.12 + i * 0.08))
				mi.rotation.z = PI / 2.0
		"flashlight":
			var body := CylinderMesh.new()
			body.top_radius = 0.035
			body.bottom_radius = 0.035
			body.height = 0.26
			body.material = _mat(Color(0.9, 0.75, 0.1))
			var mi := _add(body, at)
			mi.rotation.x = PI / 2.0
			var lens := CylinderMesh.new()
			lens.top_radius = 0.05
			lens.bottom_radius = 0.04
			lens.height = 0.05
			var glass := _mat(Color(1, 1, 0.8))
			glass.emission_enabled = true
			glass.emission = Color(1, 1, 0.8)
			lens.material = glass
			var lens_mi := _add(lens, at + Vector3(0, 0, 0.15))
			lens_mi.rotation.x = PI / 2.0
		"energy":
			var can := CylinderMesh.new()
			can.top_radius = 0.05
			can.bottom_radius = 0.05
			can.height = 0.2
			can.material = _mat(Color(0.2, 0.85, 0.3), 0.5)
			_add(can, at)


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
