class_name Player
extends CharacterBody3D
## A networked first-person player.
##
## Every machine has a copy of every player. The copy this machine controls (is_local()) reads
## input, moves, and drives the camera; its Sync node sends position, facing, head pitch and
## flashlight state to everyone else. The other copies are "puppets": they just show that, and
## play footsteps based on how far they moved.

const WALK_SPEED := 4.0
const SPRINT_SPEED := 6.8
const JUMP_VELOCITY := 4.2
const ACCEL := 10.0
const MOUSE_SENS := 0.0025
const STAMINA_MAX := 5.0
const STAMINA_REGEN := 0.7
const STAMINA_RECOVER_AT := 1.5 # after running dry, no sprinting until refilled this much
const FOOTSTEP_VOLUME_DB := -20.0
const FOOTSTEPS := [
	preload("res://audio/footstep_1.wav"), preload("res://audio/footstep_2.wav"),
	preload("res://audio/footstep_3.wav"), preload("res://audio/footstep_4.wav"),
]
const PICKUP_SFX := preload("res://audio/pickup.wav")
const THUD_SFX := preload("res://audio/thud.wav")
const COLORS := [Color(0.9, 0.3, 0.25), Color(0.25, 0.55, 0.9), Color(0.3, 0.8, 0.35), Color(0.9, 0.75, 0.2)]

## Join order (0 = host). Comes in with the spawn data (World._make_player). Drives color and name.
var slot := 0
## Synced so everyone sees your beam.
var flashlight_on := true:
	set(value):
		flashlight_on = value
		if is_node_ready():
			flashlight.visible = value
## Inventory size (upgrades will raise it). Synced so the host knows how much room you have.
var slot_count := 2
## Which slot is in your hand. Synced so everyone sees what you're holding.
var active_slot := 0
var stamina := STAMINA_MAX
var in_shop := false # local player only; set by the world
var combat: PlayerCombat
var _exhausted := false
var _stun := 0.0 # staggered by a shove: no control for a moment
var _shake := 0.0
var _bob := 0.0
var _bob_offset := 0.0
var _was_on_floor := true
var _last_position := Vector3.ZERO # puppets: for working out footsteps
var _footsteps # AudioStreamPlayer for yourself, AudioStreamPlayer3D for everyone else
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var ray: RayCast3D = $Head/Camera3D/InteractRay
@onready var flashlight: SpotLight3D = $Head/Camera3D/Flashlight
@onready var hand: Node3D = $Head/Hand


func _enter_tree() -> void:
	# Named after the peer that controls it; runs on every machine, so they all agree.
	set_multiplayer_authority(name.to_int())


func is_local() -> bool:
	return is_multiplayer_authority()


func display_name() -> String:
	return "Host" if slot == 0 else "Player %d" % (slot + 1)


func _ready() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = COLORS[slot % COLORS.size()]
	$Body.material_override = mat
	$NameTag.text = display_name()
	flashlight.visible = flashlight_on
	_last_position = global_position

	var steps := AudioStreamRandomizer.new()
	for s: AudioStream in FOOTSTEPS:
		steps.add_stream(-1, s)
	steps.random_pitch = 1.12
	steps.random_volume_offset_db = 2.0
	if is_local():
		_footsteps = AudioStreamPlayer.new()
		camera.current = true
		$Body.visible = false # don't see your own body
		$Head/Nose.visible = false
		$NameTag.visible = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		_footsteps = AudioStreamPlayer3D.new() # hear your friends walking around
		_footsteps.unit_size = 4.0
	_footsteps.stream = steps
	_footsteps.volume_db = FOOTSTEP_VOLUME_DB
	add_child(_footsteps)

	combat = PlayerCombat.new()
	combat.name = "Combat" # same path on every machine, so its RPCs line up
	add_child(combat)
	combat.setup(self)


func _input(event: InputEvent) -> void:
	# Mouse look in _input so HUD controls can never swallow it.
	if is_local() and event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion: Vector2 = event.screen_relative
		rotate_y(-motion.x * MOUSE_SENS)
		head.rotation.x = clampf(head.rotation.x - motion.y * MOUSE_SENS, deg_to_rad(-85), deg_to_rad(85))


func _unhandled_input(event: InputEvent) -> void:
	if not is_local():
		return
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event.is_action_pressed("flashlight"):
		flashlight_on = not flashlight_on
	elif event.is_action_pressed("slot_next"):
		select_slot(wrapi(active_slot + 1, 0, slot_count))
	elif event.is_action_pressed("slot_prev"):
		select_slot(wrapi(active_slot - 1, 0, slot_count))
	elif event.is_action_pressed("attack"):
		combat.button_pressed(PlayerCombat.Charging.ATTACK)
	elif event.is_action_released("attack"):
		combat.button_released(PlayerCombat.Charging.ATTACK)
	elif event.is_action_pressed("throw"):
		combat.button_pressed(PlayerCombat.Charging.THROW)
	elif event.is_action_released("throw"):
		combat.button_released(PlayerCombat.Charging.THROW)
	elif event.is_action_pressed("interact"):
		var target = get_interact_target()
		if target:
			target.interact(self)
		else:
			drop_held()
	else:
		for i in 6:
			if event.is_action_pressed("slot_%d" % (i + 1)):
				select_slot(i)


# --- Inventory --------------------------------------------------------------------
# The items themselves record who holds them (see Item), so this reads the same everywhere.

## This player's items by slot; null = empty slot.
func inventory() -> Array:
	var slots := []
	slots.resize(slot_count)
	var my_id := name.to_int()
	for it: Item in get_tree().get_nodes_in_group("items"):
		if it.holder == my_id and it.holder_slot < slot_count:
			slots[it.holder_slot] = it
	return slots


## What's in the selected slot, or null (fists).
func held_item() -> Item:
	return inventory()[active_slot]


func hands_free() -> bool:
	return held_item() == null


func has_room() -> bool:
	return inventory().has(null)


## The slot a new item should go in: the preferred one if empty, else the first empty, else -1.
func free_slot(preferred: int) -> int:
	var slots := inventory()
	if preferred >= 0 and preferred < slots.size() and slots[preferred] == null:
		return preferred
	return slots.find(null)


func select_slot(i: int) -> void:
	if i >= 0 and i < slot_count and i != active_slot:
		combat.cancel()
		active_slot = i


## E with nothing in front of you: set the held item down at your feet.
func drop_held() -> void:
	var item := held_item()
	if item == null:
		return
	var forward := -global_transform.basis.z
	forward.y = 0.0
	item.request_drop.rpc_id(1, global_position + forward.normalized() * 0.5 + Vector3.UP * 0.25, rotation.y)


## One-shot sound only this player hears (UI-ish feedback).
func play_sfx(stream: AudioStream, pitch := 1.0, volume_db := 0.0) -> void:
	var a := AudioStreamPlayer.new()
	a.stream = stream
	a.pitch_scale = pitch
	a.volume_db = volume_db
	a.finished.connect(a.queue_free)
	add_child(a)
	a.play()


## Whatever the crosshair is on that can be interacted with, or null.
func get_interact_target():
	if ray.is_colliding():
		var c := ray.get_collider()
		if c and c.has_method("interact"):
			return c
	return null


# --- Getting shoved ---------------------------------------------------------------------

## Sent by whoever hit you (a friend's punch, a thrown can). Runs on YOUR machine because you
## own your movement. Friendly fire is a shove only: no damage to you or what you carry.
@rpc("any_peer", "call_local", "reliable")
func receive_shove(push: Vector3, stun: float) -> void:
	if not is_local():
		return
	velocity = push + Vector3.UP * minf(push.length() * 0.3, 3.5)
	_stun = maxf(_stun, stun)
	shake(0.3)
	combat.cancel()
	play_sfx(THUD_SFX, randf_range(0.9, 1.1), -4.0)


func is_stunned() -> bool:
	return _stun > 0.0


func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


func _physics_process(delta: float) -> void:
	if is_local():
		combat.tick(delta)
		_move(delta)
	else:
		_puppet_footsteps(delta)


func _move(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	elif Input.is_action_just_pressed("jump") and _stun <= 0.0:
		velocity.y = JUMP_VELOCITY

	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := (transform.basis * Vector3(input.x, 0, input.y)).normalized()

	if stamina <= 0.0:
		_exhausted = true
	elif stamina >= STAMINA_RECOVER_AT:
		_exhausted = false
	var sprinting := Input.is_action_pressed("sprint") and input != Vector2.ZERO and not _exhausted
	if sprinting:
		stamina = maxf(stamina - delta, 0.0)
	else:
		stamina = minf(stamina + STAMINA_REGEN * delta, STAMINA_MAX)

	if _stun > 0.0:
		_stun -= delta
		velocity.x = lerpf(velocity.x, 0.0, 2.0 * delta) # slide out of the shove
		velocity.z = lerpf(velocity.z, 0.0, 2.0 * delta)
	else:
		var speed := SPRINT_SPEED if sprinting else WALK_SPEED
		var w := clampf(ACCEL * delta, 0.0, 1.0)
		velocity.x = lerpf(velocity.x, dir.x * speed, w)
		velocity.z = lerpf(velocity.z, dir.z * speed, w)
	move_and_slide()

	if is_on_floor() and not _was_on_floor:
		_footsteps.play() # landing
	_was_on_floor = is_on_floor()
	_update_camera(delta, input != Vector2.ZERO and is_on_floor(), sprinting)


func _update_camera(delta: float, moving: bool, sprinting: bool) -> void:
	if moving:
		_step_cycle(delta * (17.0 if sprinting else 12.0))
	var bob_target := sin(_bob) * 0.05 if moving else 0.0
	_bob_offset = lerpf(_bob_offset, bob_target, clampf(12.0 * delta, 0.0, 1.0))
	_shake = maxf(_shake - delta * 1.5, 0.0)
	var jitter := Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * _shake * 0.15
	camera.position = Vector3(0, _bob_offset, 0) + jitter
	var fov := (82.0 if sprinting else 75.0) - 6.0 * combat.charge # tunnel in while winding up
	camera.fov = lerpf(camera.fov, fov, clampf(6.0 * delta, 0.0, 1.0))


## Puppets don't know the owner's input, so infer walking from how far they moved.
func _puppet_footsteps(delta: float) -> void:
	var moved := global_position - _last_position
	_last_position = global_position
	moved.y = 0.0
	var speed := moved.length() / maxf(delta, 0.0001)
	if speed > 1.0 and speed < 20.0: # ignore teleports
		_step_cycle(delta * (17.0 if speed > 5.0 else 12.0))


## Advances the walk cycle; a footstep plays at the bottom of each bob.
func _step_cycle(amount: float) -> void:
	var before := cos(_bob)
	_bob += amount
	if before < 0.0 and cos(_bob) >= 0.0:
		_footsteps.play()
