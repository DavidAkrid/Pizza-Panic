class_name StationBase
extends StaticBody3D
## Shared plumbing for kitchen stations. Pressing E asks the HOST to use the station; the host
## checks you're close enough and calls _use() with your player. Prompts are worked out locally
## from synced data, so they're instant.

const USE_RANGE := 3.0
const PICKUP := preload("res://audio/pickup.wav")


func get_prompt(_p: Player) -> String:
	return ""


func interact(p: Player) -> void:
	_request_use.rpc_id(1, p.active_slot)


@rpc("any_peer", "call_local", "reliable")
func _request_use(active_slot: int) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		id = multiplayer.get_unique_id()
	var p := World.instance.player(id)
	if p == null or p.global_position.distance_to(global_position) > USE_RANGE:
		return
	# Use the slot the player had selected when they pressed E (their synced value may lag).
	var held: Item = p.inventory()[active_slot] if active_slot < p.slot_count else null
	_use(p, held, active_slot)


## Host only. `held` is what the player had in their hand (or null).
func _use(_p: Player, _held: Item, _slot: int) -> void:
	pass


## Plays a sound at this station for everyone.
@rpc("authority", "call_local", "unreliable")
func play_sound(stream_path: String, pitch: float) -> void:
	var a := AudioStreamPlayer3D.new()
	a.stream = load(stream_path)
	a.pitch_scale = pitch
	a.finished.connect(a.queue_free)
	add_child(a)
	a.play()
