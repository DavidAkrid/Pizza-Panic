class_name Player
extends CharacterBody3D
## First-person controller: walk, sprint (stamina), jump, interact, carry one pizza, punch/swing.

signal hit
signal pizza_swung ## connected a swing with the pizza; Game damages it

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
const WHOOSH := preload("res://audio/whoosh.wav")
const THUD := preload("res://audio/thud.wav")

# Empty hands: quick jab, hits the closest monster in front.
const PUNCH_RANGE := 1.8
const PUNCH_FORCE := 6.0
const PUNCH_STUN := 0.6
const PUNCH_COOLDOWN := 0.45
# Holding a pizza: slower, wider swing that hits everything in front. Costs pizza condition.
const SWING_RANGE := 2.3
const SWING_FORCE := 10.0
const SWING_STUN := 1.0
const SWING_COOLDOWN := 0.8

var held: Pizza
var stamina := STAMINA_MAX
var in_shop := false
var _exhausted := false
var _stun := 0.0
var _shake := 0.0
var _bob := 0.0
var _bob_offset := 0.0
var _was_on_floor := true
var _footsteps: AudioStreamPlayer
var _attack_cd := 0.0
var _fist: MeshInstance3D
var _hand_rest: Transform3D
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var ray: RayCast3D = $Head/Camera3D/InteractRay
@onready var flashlight: SpotLight3D = $Head/Camera3D/Flashlight
@onready var hand: Node3D = $Head/Camera3D/Hand


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var steps := AudioStreamRandomizer.new()
	for s: AudioStream in FOOTSTEPS:
		steps.add_stream(-1, s)
	steps.random_pitch = 1.12
	steps.random_volume_offset_db = 2.0
	_footsteps = AudioStreamPlayer.new()
	_footsteps.stream = steps
	_footsteps.volume_db = FOOTSTEP_VOLUME_DB
	add_child(_footsteps)

	_hand_rest = hand.transform
	var fist_mesh := BoxMesh.new()
	fist_mesh.size = Vector3(0.11, 0.11, 0.22)
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.85, 0.65, 0.5)
	fist_mesh.material = skin
	_fist = MeshInstance3D.new()
	_fist.mesh = fist_mesh
	_fist.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fist.visible = false
	camera.add_child(_fist)


## One-shot sound for things the player does. Each call gets its own player so sounds can overlap.
func play_sfx(stream: AudioStream, pitch := 1.0, volume_db := 0.0) -> void:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.pitch_scale = pitch
	p.volume_db = volume_db
	p.finished.connect(p.queue_free)
	add_child(p)
	p.play()


## Mouse look goes in _input (not _unhandled_input) so HUD controls can never swallow it.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion: Vector2 = event.screen_relative
		rotate_y(-motion.x * MOUSE_SENS)
		head.rotation.x = clampf(head.rotation.x - motion.y * MOUSE_SENS, deg_to_rad(-85), deg_to_rad(85))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("attack"):
		_attack()
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event.is_action_pressed("flashlight"):
		flashlight.visible = not flashlight.visible
	elif event.is_action_pressed("interact"):
		var target = get_interact_target()
		if target:
			target.interact(self)


## Whatever station/door the crosshair is on, or null.
func get_interact_target():
	if ray.is_colliding():
		var c := ray.get_collider()
		if c and c.has_method("interact"):
			return c
	return null


func set_held(p: Pizza) -> void:
	held = p
	refresh_held()


func refresh_held() -> void:
	for c in hand.get_children():
		c.queue_free()
	if held:
		hand.add_child(held.build_visual())


func _attack() -> void:
	if _attack_cd > 0.0 or _stun > 0.0:
		return
	var swinging := held != null
	_attack_cd = SWING_COOLDOWN if swinging else PUNCH_COOLDOWN
	play_sfx(WHOOSH, randf_range(0.8, 0.95) if swinging else randf_range(1.1, 1.3), -6.0)
	_animate_attack(swinging)

	var reach := SWING_RANGE if swinging else PUNCH_RANGE
	var forward := -global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var hits: Array[Shambler] = []
	for m: Shambler in get_tree().get_nodes_in_group("monster"):
		var to := m.global_position - global_position
		to.y = 0.0
		var d := to.length()
		if d < reach and (d < 0.6 or forward.dot(to / d) > 0.5):
			hits.append(m)
	if hits.is_empty():
		return
	if not swinging: # a punch only lands on the closest one
		hits.sort_custom(func(a: Shambler, b: Shambler) -> bool:
			return a.global_position.distance_to(global_position) < b.global_position.distance_to(global_position))
		hits.resize(1)
	for m in hits:
		var away := m.global_position - global_position
		away.y = 0.0
		m.knock_back(away.normalized() * (SWING_FORCE if swinging else PUNCH_FORCE), SWING_STUN if swinging else PUNCH_STUN)
	play_sfx(THUD, randf_range(0.9, 1.1))
	_shake = maxf(_shake, 0.15)
	if swinging:
		pizza_swung.emit()


func _animate_attack(swinging: bool) -> void:
	var tw := create_tween()
	if swinging:
		# Wind across from right to left, then settle back.
		var across := _hand_rest
		across.origin = Vector3(-0.15, -0.18, -0.8)
		across.basis = _hand_rest.basis.rotated(Vector3.FORWARD, 0.9)
		tw.tween_property(hand, "transform", across, 0.1)
		tw.tween_property(hand, "transform", _hand_rest, 0.25)
	else:
		_fist.position = Vector3(0.22, -0.28, -0.4)
		_fist.visible = true
		tw.tween_property(_fist, "position", Vector3(0.08, -0.16, -0.75), 0.06)
		tw.tween_property(_fist, "position", Vector3(0.22, -0.28, -0.4), 0.14)
		tw.tween_callback(_fist.hide)


func take_hit(from: Vector3) -> void:
	var push := global_position - from
	push.y = 0.0
	push = push.normalized() if push.length() > 0.01 else transform.basis.z
	velocity = push * 9.0 + Vector3.UP * 3.5
	_stun = 0.35
	_shake = 0.5
	hit.emit()


func _physics_process(delta: float) -> void:
	_attack_cd = maxf(_attack_cd - delta, 0.0)
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
		velocity.x = lerpf(velocity.x, 0.0, 2.0 * delta)
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
		var before := cos(_bob)
		_bob += delta * (17.0 if sprinting else 12.0)
		if before < 0.0 and cos(_bob) >= 0.0: # bottom of the bob = foot hits the ground
			_footsteps.play()
	var bob_target := sin(_bob) * 0.05 if moving else 0.0
	_bob_offset = lerpf(_bob_offset, bob_target, clampf(12.0 * delta, 0.0, 1.0))
	_shake = maxf(_shake - delta * 1.5, 0.0)
	var jitter := Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * _shake * 0.15
	camera.position = Vector3(0, _bob_offset, 0) + jitter
	camera.fov = lerpf(camera.fov, 82.0 if sprinting else 75.0, clampf(6.0 * delta, 0.0, 1.0))
