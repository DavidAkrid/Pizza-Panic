class_name Item
extends RigidBody3D
## A networked, host-owned item: soda cans, pizzas, fried food.
##
## Inventory lives HERE, not on players: an item knows who holds it (`holder`) and in which slot
## (`holder_slot`). A player's inventory is just "the items whose holder is me", so it's the same
## on every machine for free. Only the host changes holder/slot/state; its Sync node sends them out.
##
## `holder`:  > 0 = a player's peer id,  0 = lying in the world,  IN_STATION = inside an oven/fryer.
## `state`:   kind-specific data that changes (pizza toppings/stage/bake/condition, fry result).
##            Always REPLACE it with a new Dictionary - the synchronizer only notices reassignment.
##
## Physics: only the host simulates. Clients keep items frozen and show the synced position.
## Held items follow the holder's hand on every machine (using that player's synced head pitch).

const IN_STATION := -1
const SODA_COLORS := [Color(0.75, 0.1, 0.1), Color(0.1, 0.3, 0.75), Color(0.15, 0.6, 0.2), Color(0.85, 0.55, 0.1)]
const STICK_COLORS := {
	"frozen": Color(0.9, 0.92, 0.88), "undercooked": Color(0.95, 0.88, 0.6),
	"golden": Color(0.9, 0.6, 0.2), "overdone": Color(0.55, 0.32, 0.12), "burnt": Color(0.15, 0.1, 0.06),
}
const PICKUP_RANGE := 3.5 # host-side sanity check
const DROP_RANGE := 2.5
const HIT_SPEED := 4.0 # a thrown item must be going at least this fast to count as a hit
const PIZZA_THROW_DAMAGE := Vector2(3.0, 15.0) # % lost when a thrown pizza lands: tap -> full charge
const PIZZA_SWING_DAMAGE := 15.0 # % lost when you hit something with it
const FIRST_PERSON_SCALE := 0.6 # held items look smaller in your own hands, like the POC
const CLINK := preload("res://audio/clink.wav")
const THUD := preload("res://audio/thud.wav")
const HITMARKER := preload("res://audio/hitmarker.wav")

## "soda", "pizza", "sticks". Set at spawn (spawn data), never changes.
var kind := "soda"
## Kind-specific look settings from the spawn data (e.g. soda color). Never changes.
var spawn_info := {}
## Peer id of the player holding it, 0 = in the world, IN_STATION = in an oven/fryer. Host-owned, synced.
var holder := 0:
	set(value):
		var picked_up_by_me := is_inside_tree() and value > 0 and value != holder and value == multiplayer.get_unique_id()
		holder = value
		_apply_held_state()
		if picked_up_by_me and World.instance.local_player():
			World.instance.local_player().play_sfx(Player.PICKUP_SFX, 0.9)
## Which of the holder's inventory slots it's in. Host-owned, synced.
var holder_slot := 0
## Changing data (see top). Host-owned, synced. Reassign, never mutate in place.
var state := {}:
	set(value):
		state = value
		if _visual:
			_rebuild()

var _visual: Node3D
var _shape: CollisionShape3D
# Host only: thrown-item hit tracking.
var _live := false # thrown and hasn't hit anything yet
var _charge := 0.0
var _recent_velocities: Array[Vector3] = [] # contacts can arrive a frame after the bounce
var _sound_cd := 0.0
var _thrower: Player # so a throw can't hit the person who threw it


func _ready() -> void:
	set_multiplayer_authority(1)
	collision_layer = 2 | 16 # interactable + prop: the interact ray finds it, players walk through it
	collision_mask = 1 | 4 | 8 | 16 # world, players, monsters, other props
	contact_monitor = true
	max_contacts_reported = 4
	continuous_cd = true
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	body_entered.connect(_on_body_entered)
	_visual = Node3D.new()
	add_child(_visual)
	_shape = CollisionShape3D.new()
	add_child(_shape)
	_rebuild()
	_apply_held_state()


# --- Kinds: what it is, looks like, and does ------------------------------------------

func pizza() -> Pizza:
	return Pizza.from_state(state) if kind == "pizza" else null


func is_frozen() -> bool:
	return kind == "sticks" and state.get("fry", "frozen") == "frozen"


func describe() -> String:
	match kind:
		"pizza":
			return pizza().describe()
		"sticks":
			return "Frozen Mozzarella Sticks" if is_frozen() else "Mozzarella Sticks (%s)" % state.fry
	return "Soda"


## Short label for the inventory slots.
func short_name() -> String:
	match kind:
		"pizza":
			match int(state.get("stage", Pizza.Stage.RAW)):
				Pizza.Stage.RAW: return "Raw Pizza"
				Pizza.Stage.BOXED: return "Boxed Pizza"
			return "Pizza"
		"sticks":
			return "Frozen Sticks" if is_frozen() else "Mozz Sticks"
	return "Soda"


## How it works as a melee weapon (left click while holding it). Same keys as PlayerCombat.PUNCH.
func weapon() -> Dictionary:
	match kind:
		"pizza": # a wide flat swipe that hits everything in front of you (and hurts the pizza)
			return {"range": 2.3, "arc": 80.0, "force": 8.0, "stun": 1.0, "hits_all": true}
		"sticks":
			return {"range": 1.8, "arc": 60.0, "force": 3.0, "stun": 0.4, "hits_all": false}
	return {"range": 1.9, "arc": 60.0, "force": 5.0, "stun": 0.5, "hits_all": false}


## How hard it hits when thrown: [force, stun] before charge.
func throw_stats() -> Array:
	match kind:
		"pizza":
			return [8.0, 1.0]
		"sticks":
			return [5.0, 0.8]
	return [7.0, 1.0]


func _rebuild() -> void:
	for c in _visual.get_children():
		c.queue_free()
	match kind:
		"pizza":
			mass = 0.8
			var p := pizza()
			_visual.add_child(p.build_visual())
			var box := BoxShape3D.new()
			box.size = Vector3(0.42, 0.07 if p.stage == Pizza.Stage.BOXED else 0.03, 0.42)
			_shape.shape = box
		"sticks":
			mass = 0.3
			_build_sticks()
			var box := BoxShape3D.new()
			box.size = Vector3(0.2, 0.08, 0.13)
			_shape.shape = box
		_:
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
			_add_mesh(mesh, Vector3.ZERO)
			var cyl := CylinderShape3D.new()
			cyl.radius = 0.04
			cyl.height = 0.13
			_shape.shape = cyl


## A red paper boat of four mozzarella sticks, colored by how cooked they are.
func _build_sticks() -> void:
	var boat := BoxMesh.new()
	boat.size = Vector3(0.2, 0.05, 0.13)
	var boat_mat := StandardMaterial3D.new()
	boat_mat.albedo_color = Color(0.85, 0.15, 0.12)
	boat.material = boat_mat
	_add_mesh(boat, Vector3(0, -0.015, 0))
	var stick := CylinderMesh.new()
	stick.top_radius = 0.016
	stick.bottom_radius = 0.016
	stick.height = 0.17
	stick.radial_segments = 6
	var stick_mat := StandardMaterial3D.new()
	stick_mat.albedo_color = STICK_COLORS.get(state.get("fry", "frozen"), STICK_COLORS.golden)
	stick.material = stick_mat
	for i in 4:
		var mi := _add_mesh(stick, Vector3(0, 0.022 + (i % 2) * 0.012, -0.045 + i * 0.03))
		mi.rotation.z = PI / 2.0


func _add_mesh(mesh: Mesh, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	_visual.add_child(mi)
	return mi


# --- Held vs. in the world ---------------------------------------------------------

func _apply_held_state() -> void:
	if not is_inside_tree() or _shape == null: # synced values can arrive before _ready
		return
	var out_of_world := holder != 0
	freeze = out_of_world or not multiplayer.is_server() # clients never simulate
	_shape.set_deferred("disabled", out_of_world)
	if holder == IN_STATION:
		visible = false
	elif holder == 0:
		visible = true
		_visual.scale = Vector3.ONE


func _process(_delta: float) -> void:
	if holder <= 0:
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


# --- Host: giving, stashing, changing ------------------------------------------------

## Host only. Puts this item in a player's inventory (preferred slot if free). False if no room.
func give_to(p: Player, preferred_slot: int) -> bool:
	var slot := p.free_slot(preferred_slot)
	if slot == -1:
		return false
	holder_slot = slot
	holder = p.name.to_int()
	return true


## Host only. Hides it inside an oven/fryer.
func stash_in_station() -> void:
	holder = IN_STATION


## Host only. Merges `changes` into state (as a new Dictionary, so it syncs).
func set_state(changes: Dictionary) -> void:
	var s := state.duplicate()
	s.merge(changes, true)
	state = s


## Host only. Pizza loses condition; whoever is holding it gets feedback. Destroyed at 0.
func damage_pizza(amount: float, message := "") -> void:
	if kind != "pizza":
		return
	var condition: float = state.get("condition", 100.0) - amount
	if holder > 0:
		_feedback.rpc_id(holder, condition <= 0.0, message, int(maxf(condition, 0.0)))
	if condition <= 0.0:
		queue_free() # the ItemSpawner removes it everywhere
	else:
		set_state({"condition": condition})


## Runs on the holder's machine: hitmarker, tick, red flash, shake, and maybe a message.
@rpc("authority", "call_local", "reliable")
func _feedback(destroyed: bool, message: String, condition: int) -> void:
	var hud := World.instance.hud
	hud.hit_marker()
	hud.flash_slot(holder_slot)
	var me := World.instance.local_player()
	if me:
		me.play_sfx(HITMARKER, randf_range(0.95, 1.05), -6.0)
	if destroyed:
		hud.show_message("The pizza is destroyed!\nBack to the shop to make another.", 4.0)
		return
	if me and me.active_slot == holder_slot:
		_flash()
	if message != "":
		hud.show_message("%s %d%% left" % [message, condition], 2.0)


## Quick red tint + shake of the visual (it's in your hand, so you see it).
func _flash() -> void:
	var red := StandardMaterial3D.new()
	red.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	red.albedo_color = Color(1, 0.1, 0.05, 0.6)
	red.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var meshes := _visual.find_children("*", "MeshInstance3D", true, false)
	for mi: MeshInstance3D in meshes:
		mi.material_overlay = red
	var tw := create_tween()
	for i in 4:
		tw.tween_property(_visual, "position", Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * 0.03, 0.03)
	tw.tween_property(_visual, "position", Vector3.ZERO, 0.04)
	tw.tween_callback(func() -> void:
		for mi in meshes: # untyped: some may have been freed by a rebuild
			if is_instance_valid(mi):
				mi.material_overlay = null)


# --- Requests to the host -----------------------------------------------------------

@rpc("any_peer", "call_local", "reliable")
func request_pickup(preferred_slot: int) -> void:
	if not multiplayer.is_server() or holder != 0:
		return # someone else got there first
	var p := World.instance.player(_sender())
	if p and p.global_position.distance_to(global_position) <= PICKUP_RANGE:
		give_to(p, preferred_slot)


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


## `charge` 0 = tap lob, 1 = full-power throw.
@rpc("any_peer", "call_local", "reliable")
func request_throw(direction: Vector3, charge: float) -> void:
	if not multiplayer.is_server() or _sender() != holder:
		return
	var p := World.instance.player(holder)
	holder = 0
	if p:
		global_position = p.hand.global_position
	var speed := lerpf(PlayerCombat.THROW_SPEED.x, PlayerCombat.THROW_SPEED.y, clampf(charge, 0.0, 1.0))
	linear_velocity = direction.normalized() * speed + Vector3.UP * 1.5
	angular_velocity = Vector3(randf_range(-8, 8), randf_range(-8, 8), randf_range(-8, 8))
	_live = true
	_charge = clampf(charge, 0.0, 1.0)
	_recent_velocities.clear()
	_thrower = p


## Someone punched or swung at it while it was lying around.
@rpc("any_peer", "call_local", "reliable")
func request_knock(velocity_change: Vector3) -> void:
	if not multiplayer.is_server() or holder != 0:
		return
	linear_velocity = velocity_change
	angular_velocity = Vector3(randf_range(-10, 10), randf_range(-10, 10), randf_range(-10, 10))


## The holder hit something with this item (pizzas get hurt by being swung).
@rpc("any_peer", "call_local", "reliable")
func request_swung() -> void:
	if multiplayer.is_server() and _sender() == holder:
		damage_pizza(PIZZA_SWING_DAMAGE, "Pizza to the face!")


# --- Host: impacts -------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	_sound_cd -= delta
	_recent_velocities.push_back(linear_velocity)
	if _recent_velocities.size() > 3:
		_recent_velocities.pop_front()


func _impact_velocity() -> Vector3:
	var best := linear_velocity
	for v in _recent_velocities:
		if v.length() > best.length():
			best = v
	return best


func _on_body_entered(body: Node) -> void:
	if not multiplayer.is_server():
		return
	var impact := _impact_velocity()
	var speed := impact.length()
	if speed > 1.5 and _sound_cd <= 0.0:
		play_impact.rpc(clampf(speed / 10.0, 0.15, 1.0))
		_sound_cd = 0.12
	if not _live or speed < HIT_SPEED or body == _thrower:
		return
	_live = false # one hit per throw
	var stats := throw_stats()
	var push := impact
	push.y = 0.0
	push = push.normalized() * stats[0] * lerpf(1.0, PlayerCombat.CHARGE_FORCE_MULT, _charge)
	var stun: float = stats[1] * lerpf(1.0, PlayerCombat.CHARGE_STUN_MULT, _charge)
	if body is Player:
		body.receive_shove.rpc_id(body.name.to_int(), push * PlayerCombat.PLAYER_SHOVE_MULT, stun * 0.5)
	# Monsters plug in here (monsters step).
	damage_pizza(lerpf(PIZZA_THROW_DAMAGE.x, PIZZA_THROW_DAMAGE.y, _charge))


## Everyone hears it land, from where it hit.
@rpc("authority", "call_local", "unreliable")
func play_impact(loudness: float) -> void:
	var a := AudioStreamPlayer3D.new()
	a.stream = THUD if kind == "pizza" else CLINK
	a.volume_db = linear_to_db(loudness)
	a.pitch_scale = randf_range(0.9, 1.2)
	a.finished.connect(a.queue_free)
	add_child(a)
	a.play()


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
