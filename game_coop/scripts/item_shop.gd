class_name ItemShop
extends StationBase
## A wall display that sells one item (team money pays). The item goes straight into your bag.
## Builds its own look; faces -X (meant for the shop's right wall, like the upgrade plaques).

@export var item_kind := "bat"
@export var item_name := "Baseball Bat"
@export var price := 100


func _ready() -> void:
	collision_layer = 3
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.12, 1.0, 0.8)
	var col := CollisionShape3D.new()
	col.shape = shape
	add_child(col)

	var board := BoxMesh.new()
	board.size = Vector3(0.05, 1.0, 0.8)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.2, 0.25, 0.35)
	board.material = wood
	var mi := MeshInstance3D.new()
	mi.mesh = board
	add_child(mi)
	_build_display()

	var label := Label3D.new()
	label.text = "%s\n$%d" % [item_name.to_upper(), price]
	label.pixel_size = 0.0035
	label.font_size = 32
	label.outline_size = 6
	label.position = Vector3(-0.04, -0.36, 0)
	label.rotation.y = -PI / 2.0 # face into the room (-X)
	add_child(label)


func get_prompt(p: Player) -> String:
	if not p.has_room() and p.held_item() == null:
		return "%s - $%d (bag full)" % [item_name, price]
	var line := "%s - $%d" % [item_name, price]
	if not p.has_room():
		line += " (drops your %s)" % p.held_item().short_name()
	return "[E] Buy " + line if GameState.instance.money >= price else line


## Host: the team pays, the buyer gets it in hand (a full bag drops what you're holding).
func _use(p: Player, held: Item, slot: int) -> void:
	var game := GameState.instance
	var id := p.name.to_int()
	if not p.has_room() and held == null:
		game.notify(id, "No room in your bag.")
		return
	if game.money < price:
		game.notify(id, "The team needs $%d more." % (price - game.money))
		return
	game.money -= price
	World.instance.spawn_item(item_kind, global_position + Vector3.UP * 0.5).give_to(p, slot, true)
	game.notify(id, "Bought a %s!" % item_name, true)


## The goods, mounted on the board.
func _build_display() -> void:
	match item_kind:
		"bat":
			var wood := StandardMaterial3D.new()
			wood.albedo_color = Color(0.72, 0.5, 0.28)
			var bat := CylinderMesh.new()
			bat.top_radius = 0.045
			bat.bottom_radius = 0.018
			bat.height = 0.78
			bat.radial_segments = 10
			bat.material = wood
			var mi := MeshInstance3D.new()
			mi.mesh = bat
			mi.position = Vector3(-0.07, 0.12, 0)
			mi.rotation.x = 0.9 # hung diagonally
			add_child(mi)
