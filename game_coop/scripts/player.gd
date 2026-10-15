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
const COLORS := [Color(0.9, 0.3, 0.25), Color(0.25, 0.55, 0.9), Color(0.3, 0.8, 0.35), Color(0.9, 0.75, 0.2)]

## Join order (0 = host). Comes in with the spawn data (World._make_player). Drives color and name.
var slot := 0
## Synced so everyone sees your beam.
var flashlight_on := true:
	set(value):
		flashlight_on = value
		if is_node_ready():
			flashlight.visible = value
var stamina := STAMINA_MAX
var in_shop := false # local player only; set by the world
var _exhausted := false
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
	elif event.is_action_pressed("interact"):
		var target = get_interact_target()
		if target:
			target.interact(self)


## Whatever the crosshair is on that can be interacted with, or null.
func get_interact_target():
	if ray.is_colliding():
		var c := ray.get_collider()
		if c and c.has_method("interact"):
			return c
	return null


func _physics_process(delta: float) -> void:
	if is_local():
		_move(delta)
	else:
		_puppet_footsteps(delta)


func _move(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	elif Input.is_action_just_pressed("jump"):
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
	camera.position = Vector3(0, _bob_offset, 0)
	camera.fov = lerpf(camera.fov, 82.0 if sprinting else 75.0, clampf(6.0 * delta, 0.0, 1.0))


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
