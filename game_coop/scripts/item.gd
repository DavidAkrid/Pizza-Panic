class_name Item
extends RigidBody3D
## A networked, host-owned item: soda cans now; pizzas and fried food later.
##
## Inventory lives HERE, not on players: an item knows who holds it (`holder`) and in which slot
## (`holder_slot`). A player's inventory is just "the items whose holder is me", so it's the same
## on every machine for free. Only the host changes holder/slot/state; its Sync node sends them out.
##
## Physics: only the host simulates. Clients keep items frozen and show the synced position.
## Held items follow the holder's hand on every machine (using that player's synced head pitch).

const SODA_COLORS := [Color(0.75, 0.1, 0.1), Color(0.1, 0.3, 0.75), Color(0.15, 0.6, 0.2), Color(0.85, 0.55, 0.1)]
const PICKUP_RANGE := 3.5 # host-side sanity check
const DROP_RANGE := 2.5
const THROW_SPEED := 12.0
const FIRST_PERSON_SCALE := 0.6 # held items look smaller in your own hands, like the POC

## "soda", "pizza", "sticks". Set at spawn (spawn data), never changes.
var kind := "soda"
## Kind-specific look/settings from the spawn data (e.g. soda color). Never changes.
var spawn_info := {}
## Peer id of the player holding it, 0 = in the world. Host-owned, synced.
var holder := 0:
	set(value):
		var picked_up_by_me := is_inside_tree() and value != 0 and value != holder and value == multiplayer.get_unique_id()
		holder = value
		_apply_held_state()
		if picked_up_by_me and World.instance.local_player():
			World.instance.local_player().play_sfx(Player.PICKUP_SFX, 0.9)
## Which of the holder's inventory slots it's in. Host-owned, synced.
var holder_slot := 0

var _visual: Node3D
var _shape: CollisionShape3D


func _ready() -> void:
	set_multiplayer_authority(1)
	collision_layer = 2 | 16 # interactable + prop: the interact ray finds it, players walk through it
	collision_mask = 1 | 4 | 8 | 16 # world, players, monsters, other props
	contact_monitor = true
	max_contacts_reported = 4
	continuous_cd = true
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	_build()
	_apply_held_state()


# --- What it looks like -----------------------------------------------------------

func _build() -> void:
	_visual = Node3D.new()
	add_child(_visual)
	_shape = CollisionShape3D.new()
	add_child(_shape)
	match kind:
		"soda":
			mass = 0.35
			var mesh := CylinderMesh.new()
			mesh.top_radius = 0.04
			mesh.bottom_radius = 0.04
			mesh.height = 0.13
			mesh.radial_segments = 10
			var mat := StandardMaterial3D.new()
			mat.albedo_color = SODA_COLORS[int(spawn_info.get("color", 0)) % SODA_COLORS.size()]
			mat.metallic = 0.6
			mat.roughness = 0.35
			mesh.material = mat
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			_visual.add_child(mi)
			var shape := CylinderShape3D.new()
			shape.radius = 0.04
			shape.height = 0.13
			_shape.shape = shape


func describe() -> String:
	match kind:
		"soda":
			return "Soda"
	return kind.capitalize()


func short_name() -> String:
	return describe()


# --- Held vs. in the world ---------------------------------------------------------

func _apply_held_state() -> void:
	if not is_inside_tree() or _shape == null: # synced values can arrive before _ready
		return
	var held := holder != 0
	freeze = held or not multiplayer.is_server() # clients never simulate; they show the host's result
	_shape.set_deferred("disabled", held)
	if not held:
		visible = true
		_visual.scale = Vector3.ONE


func _process(_delta: float) -> void:
	if holder == 0:
		return
	var p := World.instance.player(holder)
	if p == null:
		return
	# Only the item in the holder's selected slot is out; the rest are "in the bag".
	visible = p.active_slot == holder_slot
	global_transform = p.hand.global_transform.orthonormalized()
	_visual.scale = Vector3.ONE * (FIRST_PERSON_SCALE if p.is_local() else 1.0)


# --- Interaction (called on the machine of the player who pressed E) -------------------

func get_prompt(p: Player) -> String:
	if holder != 0:
		return ""
	return "[E] Pick up %s" % describe() if p.has_room() else "%s (inventory full)" % describe()


func interact(p: Player) -> void:
	if holder == 0:
		request_pickup.rpc_id(1, p.active_slot)


# --- Requests to the host -----------------------------------------------------------

@rpc("any_peer", "call_local", "reliable")
func request_pickup(preferred_slot: int) -> void:
	if not multiplayer.is_server() or holder != 0:
		return # someone else got there first
	var p := World.instance.player(_sender())
	if p == null or p.global_position.distance_to(global_position) > PICKUP_RANGE:
		return
	var slot := p.free_slot(preferred_slot)
	if slot == -1:
		return
	holder_slot = slot
	holder = p.name.to_int()


@rpc("any_peer", "call_local", "reliable")
func request_drop(at: Vector3, yaw: float) -> void:
	if not multiplayer.is_server() or _sender() != holder:
		return
	var p := World.instance.player(holder)
	if p and p.global_position.distance_to(at) > DROP_RANGE:
		at = p.global_position + Vector3.UP * 0.25 # don't trust far-away drop spots
	holder = 0
	global_position = at
	global_rotation = Vector3(0, yaw, 0)
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO


@rpc("any_peer", "call_local", "reliable")
func request_throw(direction: Vector3) -> void:
	if not multiplayer.is_server() or _sender() != holder:
		return
	var p := World.instance.player(holder)
	holder = 0
	if p:
		global_position = p.hand.global_position
	linear_velocity = direction.normalized() * THROW_SPEED + Vector3.UP * 1.5
	angular_velocity = Vector3(randf_range(-8, 8), randf_range(-8, 8), randf_range(-8, 8))


## Host only: someone left the game while holding this. Drop it where they were.
func release_from(id: int) -> void:
	if holder != id:
		return
	var p := World.instance.player(id)
	var at := p.global_position + Vector3.UP * 0.4 if p else global_position
	holder = 0
	global_position = at


func _sender() -> int:
	var id := multiplayer.get_remote_sender_id()
	return id if id != 0 else multiplayer.get_unique_id() # 0 when the host calls itself
