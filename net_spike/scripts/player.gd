class_name NetPlayer
extends CharacterBody3D
## A networked first-person player. Every peer has a copy of every player; only the copy whose
## authority matches this peer reads input and moves. Its Sync node sends position, rotation
## and head pitch to everyone else.

const WALK := 4.0
const SPRINT := 6.8
const JUMP := 4.2
const SENS := 0.0025
const THROW_SPEED := 12.0
const COLORS := [Color(0.9, 0.3, 0.25), Color(0.25, 0.55, 0.9), Color(0.3, 0.8, 0.35), Color(0.9, 0.75, 0.2)]

## Join order (0 = host). Assigned by the host at spawn and synced once; drives color and name.
var slot := 0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var ray: RayCast3D = $Head/Camera3D/Ray
@onready var hand: Node3D = $Head/Hand


func _enter_tree() -> void:
	# The node is named after the peer that controls it. Runs on every peer, so all agree.
	set_multiplayer_authority(name.to_int())


func _ready() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = COLORS[slot % COLORS.size()]
	$Body.material_override = mat
	$NameTag.text = "Host" if slot == 0 else "Player %d" % (slot + 1)
	if is_multiplayer_authority():
		camera.current = true
		$Body.visible = false # don't render yourself
		$Head/Nose.visible = false
		$NameTag.visible = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## The can this player is holding, or null. (Holding is host-owned state on the can itself.)
func held_can() -> SpikeCan:
	for can: SpikeCan in get_tree().get_nodes_in_group("cans"):
		if can.holder == name.to_int():
			return can
	return null


func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion: Vector2 = event.screen_relative
		rotate_y(-motion.x * SENS)
		head.rotation.x = clampf(head.rotation.x - motion.y * SENS, deg_to_rad(-85), deg_to_rad(85))
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event.is_action_pressed("interact"):
		try_pickup()
	elif event.is_action_pressed("throw"):
		try_throw()


## Ask the host to give us the can we're looking at.
func try_pickup() -> void:
	if held_can():
		return
	var target := ray.get_collider() as SpikeCan
	if target:
		target.request_pickup.rpc_id(1)


## Ask the host to throw the can we're holding, in the direction we're looking.
func try_throw() -> void:
	var can := held_can()
	if can:
		can.request_throw.rpc_id(1, -camera.global_transform.basis.z)


func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return
	if not is_on_floor():
		velocity.y -= _gravity * delta
	elif Input.is_action_just_pressed("jump"):
		velocity.y = JUMP
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := (transform.basis * Vector3(input.x, 0, input.y)).normalized()
	var speed := SPRINT if Input.is_action_pressed("sprint") else WALK
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	move_and_slide()
