class_name SpikeCan
extends RigidBody3D
## A host-owned physics prop. Only the host simulates it; clients just show the position the
## host syncs. Picking up and throwing are requests to the host, which validates and applies them.

## Peer id of whoever is holding it, 0 = lying in the world. Synced from the host.
var holder := 0:
	set(value):
		holder = value
		_apply_holder()


func _ready() -> void:
	set_multiplayer_authority(1)
	_apply_holder()


func _apply_holder() -> void:
	if not is_inside_tree():
		return
	var held := holder != 0
	# Clients never simulate: they display the host's synced transform (kinematic = smooth moves).
	freeze = held or not multiplayer.is_server()
	$Shape.set_deferred("disabled", held)


func _process(_delta: float) -> void:
	# Held cans follow the holder's hand. Every peer does this locally, using the holder's synced
	# head rotation, so it looks right everywhere without syncing the can every frame.
	if holder != 0:
		var p := _holder_player()
		if p:
			global_transform = p.hand.global_transform


@rpc("any_peer", "call_local", "reliable")
func request_pickup() -> void:
	if not multiplayer.is_server() or holder != 0:
		return
	var who := _sender()
	var p := _holder_player(who)
	if p == null or p.held_can() != null:
		return
	if p.global_position.distance_to(global_position) > 3.5:
		return # host-side sanity check: no grabbing from across the map
	holder = who


@rpc("any_peer", "call_local", "reliable")
func request_throw(direction: Vector3) -> void:
	if not multiplayer.is_server() or _sender() != holder:
		return
	var p := _holder_player()
	holder = 0
	if p:
		global_position = p.hand.global_position
	linear_velocity = direction.normalized() * NetPlayer.THROW_SPEED + Vector3.UP * 1.5
	angular_velocity = Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6))


## Host only: release the can where its holder is (used when a player disconnects).
func drop_from(id: int) -> void:
	if holder == id:
		holder = 0


func _sender() -> int:
	var id := multiplayer.get_remote_sender_id()
	return id if id != 0 else multiplayer.get_unique_id() # 0 when the host calls itself


func _holder_player(id := -1) -> NetPlayer:
	if id == -1:
		id = holder
	return get_node_or_null("../Players/%d" % id) as NetPlayer
