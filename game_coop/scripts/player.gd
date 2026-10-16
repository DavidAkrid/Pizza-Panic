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
const HEALTH_MAX := 100.0
const SHOP_HEAL := 4.0 ## health per second while inside the shop
const CRAWL_SPEED := 0.9
const BLEED_TIME := 30.0 ## down this long without a revive -> the bathroom stall
const BLEED_TIME_SOLO := 8.0
const REVIVE_TIME := 3.0 ## a friend holds E this long
const REVIVE_HEALTH := 35.0
const GIVE_UP_TIME := 1.5 ## hold E while down to skip the wait

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
# Upgradable stats (GameState.UPGRADES); set by apply_upgrades on every machine.
var stamina_max := STAMINA_MAX
var speed_mult := 1.0
var punch_mult := 1.0
var in_shop := false # local player only; set by the world
## Owned by this player's machine (hits arrive as `hurt` RPCs from the host). Synced.
var health := HEALTH_MAX
## At 0 health you go down: crawl, wait for a friend, or bleed out to the stall. Synced.
var downed := false:
	set(value):
		var fell := value and not downed
		downed = value
		if is_node_ready():
			_show_downed()
			if fell and not is_local():
				World.instance.hud.show_message("%s is DOWN! Hold [E] on them to revive." % display_name(), 3.5)
var bleed_left := 0.0 # owner only
var combat: PlayerCombat
var _hold_e := 0.0 # local: how long E has been held on a downed friend (or to give up)
var _respawning := false # owner: asked the host for the stall, waiting
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

	if GameState.instance:
		apply_upgrades(GameState.instance.upgrades.get(str(name), {}))

	combat = PlayerCombat.new()
	combat.name = "Combat" # same path on every machine, so its RPCs line up
	add_child(combat)
	combat.setup(self)
	ray.add_exception(self) # never "aim at" your own body (it's interactable while you're down)
	_show_downed()


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
	elif downed:
		pass # on the floor: no fighting, grabbing or juggling slots (hold E to give up: see _tick_hold)
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


# --- Upgrades ---------------------------------------------------------------------------

## Applies this player's upgrade levels (called on every machine whenever they change).
func apply_upgrades(levels: Dictionary) -> void:
	speed_mult = 1.0 + 0.06 * levels.get("shoes", 0)
	punch_mult = 1.0 + 0.3 * levels.get("knuckles", 0)
	var fl: int = levels.get("flashlight", 0)
	flashlight.spot_range = 20.0 + 8.0 * fl
	flashlight.spot_angle = 28.0 + 4.0 * fl
	flashlight.light_energy = 3.0 + 0.6 * fl
	var new_max: float = STAMINA_MAX * (1.0 + 0.3 * levels.get("energy", 0))
	if new_max > stamina_max:
		stamina = new_max # topped up on purchase
	stamina_max = new_max
	if is_local(): # slot_count syncs from the owner
		slot_count = 2 + levels.get("bag", 0)


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


## Any pizza or fried food on you lets monsters smell you from further away.
func carrying_food() -> bool:
	for it in inventory():
		if it and (it.kind == "pizza" or it.kind == "sticks"):
			return true
	return false


## The pizza a monster bite hits: the one in your hand, else any in your bag. Null if none.
func exposed_pizza() -> Item:
	var held := held_item()
	if held and held.kind == "pizza":
		return held
	for it in inventory():
		if it and it.kind == "pizza":
			return it
	return null


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


## Sent by the host when you get a new item: it goes in your hand.
@rpc("any_peer", "call_local", "reliable")
func hold_slot(i: int) -> void:
	if is_local() and multiplayer.get_remote_sender_id() <= 1:
		select_slot(i)


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


# --- Health, going down, revive ----------------------------------------------------------

## Sent by the host (a monster bite). Runs on YOUR machine because you own your health.
@rpc("any_peer", "call_local", "reliable")
func hurt(amount: float) -> void:
	if not is_local() or multiplayer.get_remote_sender_id() > 1 or downed or _respawning:
		return
	health = maxf(health - amount, 0.0)
	World.instance.hud.hit_marker()
	if health <= 0.0:
		_go_down()


func _go_down() -> void:
	downed = true
	combat.cancel()
	bleed_left = BLEED_TIME_SOLO if World.instance.players.get_child_count() <= 1 else BLEED_TIME
	play_sfx(THUD_SFX, 0.6, 0.0)
	shake(0.6)


## Sent by the friend who revived you.
@rpc("any_peer", "call_local", "reliable")
func revive() -> void:
	if not is_local() or not downed or _respawning:
		return
	downed = false
	health = REVIVE_HEALTH
	World.instance.hud.show_message("Back on your feet!", 2.0)


## Every machine: a downed player lies on the floor with a red HELP! over them (seen through
## walls), and can be aimed at so friends can revive them.
func _show_downed() -> void:
	$Body.rotation.x = -PI / 2.0 if downed else 0.0
	$Body.position.y = 0.35 if downed else 0.875
	head.position.y = 0.45 if downed else 1.6
	collision_layer = 4 | 2 if downed else 4
	var tag: Label3D = $NameTag
	tag.text = "HELP!\n" + display_name() if downed else display_name()
	tag.modulate = Color(1, 0.3, 0.25) if downed else Color.WHITE
	tag.no_depth_test = downed
	tag.visible = not is_local()
	tag.position.y = 1.2 if downed else 2.15


## Prompt when a friend aims at you.
func get_prompt(p: Player) -> String:
	if not downed:
		return ""
	return "Hold [E] to revive %s (%d%%)" % [display_name(), int(p._hold_e / REVIVE_TIME * 100.0)]


func interact(_p: Player) -> void:
	pass # reviving is a hold, handled by the reviver's _tick_hold


## Local player, every frame: holding E either revives the downed friend in your crosshair or,
## if you're the one down, gives up and heads for the stall.
func _tick_hold(delta: float) -> void:
	var target = get_interact_target()
	var reviving: bool = not downed and target is Player and target.downed
	if not Input.is_action_pressed("interact") or not (reviving or downed):
		_hold_e = 0.0
		return
	_hold_e += delta
	if reviving and _hold_e >= REVIVE_TIME:
		_hold_e = 0.0
		target.revive.rpc_id(target.name.to_int())
	elif downed and _hold_e >= GIVE_UP_TIME:
		_hold_e = 0.0
		_bleed_out()


## Owner: health comes back in the shop; down too long -> the stall.
func _tick_health(delta: float) -> void:
	if downed:
		bleed_left -= delta
		if bleed_left <= 0.0:
			_bleed_out()
	elif in_shop and health < HEALTH_MAX:
		health = minf(health + SHOP_HEAL * delta, HEALTH_MAX)


func _bleed_out() -> void:
	if _respawning:
		return
	_respawning = true
	World.instance.request_respawn.rpc_id(1)


## Sent by the host once your stuff is gone and the bill is paid: step out of the stall.
@rpc("any_peer", "call_local", "reliable")
func respawn_at(pos: Vector3, yaw: float) -> void:
	if not is_local() or multiplayer.get_remote_sender_id() > 1:
		return
	global_position = pos
	velocity = Vector3.ZERO
	rotation.y = yaw
	head.rotation.x = 0.0
	health = HEALTH_MAX
	downed = false
	_respawning = false
	_hold_e = 0.0


func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


func _physics_process(delta: float) -> void:
	if is_local():
		combat.tick(delta)
		_tick_hold(delta)
		_tick_health(delta)
		_move(delta)
	else:
		_puppet_footsteps(delta)


func _move(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	elif Input.is_action_just_pressed("jump") and _stun <= 0.0 and not downed:
		velocity.y = JUMP_VELOCITY

	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := (transform.basis * Vector3(input.x, 0, input.y)).normalized()

	if stamina <= 0.0:
		_exhausted = true
	elif stamina >= STAMINA_RECOVER_AT:
		_exhausted = false
	var sprinting := Input.is_action_pressed("sprint") and input != Vector2.ZERO and not _exhausted and not downed
	if sprinting:
		stamina = maxf(stamina - delta, 0.0)
	else:
		stamina = minf(stamina + STAMINA_REGEN * delta, stamina_max)

	if _stun > 0.0:
		_stun -= delta
		velocity.x = lerpf(velocity.x, 0.0, 2.0 * delta) # slide out of the shove
		velocity.z = lerpf(velocity.z, 0.0, 2.0 * delta)
	else:
		var speed := CRAWL_SPEED if downed else (SPRINT_SPEED if sprinting else WALK_SPEED) * speed_mult
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
