class_name Player
extends CharacterBody3D
## First-person controller: walk, sprint (stamina), jump, interact, carry one thing,
## charged punch / pizza swing (left click), throw (right click).

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
const PICKUP := preload("res://audio/pickup.wav")

# Hold a mouse button to charge (punch/swing on left, throw on right). Tap = power 0, full = 1.
# Charge scales knockback/stun from 1x up to these multipliers. Press the other button to cancel.
const CHARGE_TIME := 1.0
const CHARGE_FORCE_MULT := 2.6
const CHARGE_STUN_MULT := 2.0
const CHARGE_RANGE_BONUS := 0.4
const CHARGE_BLEND := 0.12 # first part of a wind-up eases in from wherever the hand was
# Base (tap) stats for the two things that aren't world items. Items carry their own (see Throwable).
# "arc" = degrees either side of straight ahead that the attack can hit.
const PUNCH := {"range": 1.8, "arc": 60.0, "force": 6.0, "stun": 0.6, "hits_all": false}
const PIZZA_SWING := {"range": 2.3, "arc": 80.0, "force": 8.0, "stun": 1.0, "hits_all": true}
const THROW_SPEED := Vector2(6.0, 16.0) # tap lob -> full charge

# Fist poses (position + rotation in radians). Cosmetic: wind up out to the right with the
# knuckles turning outward, then hook across to the left with a corkscrew twist.
const FIST_REST := Vector3(0.22, -0.28, -0.4)
const FIST_REST_ROT := Vector3.ZERO
const FIST_WOUND := Vector3(0.34, -0.24, -0.32)
const FIST_WOUND_ROT := Vector3(0.15, -0.5, -0.35)
const FIST_STRIKE := Vector3(-0.02, -0.15, -0.75)
const FIST_STRIKE_ROT := Vector3(-0.05, 0.35, 0.7)
# Pizza swipe: flat sweep right -> left, offsets from the hand's rest pose (rotation in radians).
const PIZZA_WOUND := Vector3(0.3, 0.02, 0.12)
const PIZZA_WOUND_ROT := Vector3(0.0, -0.7, 0.0)
const PIZZA_MID := Vector3(-0.2, 0.05, -0.22)
const PIZZA_MID_ROT := Vector3(0.0, 0.2, 0.0)
const PIZZA_STRIKE := Vector3(-0.65, 0.03, -0.05)
const PIZZA_STRIKE_ROT := Vector3(0.0, 0.9, 0.0)
const HAND_WOUND_THROW := Vector3(0.38, -0.02, -0.3) # cocked up by the shoulder
const HAND_WOUND_THROW_ROT := Vector3(0.8, 0.0, 0.0) # tipped back, front edge up

enum Charging { NONE, ATTACK, THROW }

## Inventory. Each slot holds a Pizza (data), a Throwable (a picked-up world object), or null.
## Starts with 2 slots; upgrades will add more (keys 1-6 are already bound).
var slots: Array = [null, null]
var active_slot := 0
## The pizza in the selected slot, or null.
var held: Pizza:
	get:
		return slots[active_slot] as Pizza
	set(value):
		slots[active_slot] = value
## The world object in the selected slot, or null.
var held_item: Throwable:
	get:
		return slots[active_slot] as Throwable
	set(value):
		slots[active_slot] = value
var stamina := STAMINA_MAX
# Upgradable stats (see Game.UPGRADES / apply_upgrade).
var stamina_max := STAMINA_MAX
var speed_mult := 1.0
var punch_mult := 1.0
var in_shop := false
var charge := 0.0 ## 0..1 while winding up
var _charging := Charging.NONE
var _exhausted := false
var _stun := 0.0
var _shake := 0.0
var _bob := 0.0
var _bob_offset := 0.0
var _was_on_floor := true
var _footsteps: AudioStreamPlayer
var _attack_cd := 0.0 ## next attack allowed once the current strike lands
var _anim_tween: Tween
var _charge_from_hand: Transform3D # where the hand/fist were when this wind-up started,
var _charge_from_fist: Transform3D # so interrupting a return blends instead of snapping
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
	for i in 6:
		if event.is_action_pressed("slot_%d" % (i + 1)):
			select_slot(i)
			return
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("attack"):
		_button_pressed(Charging.ATTACK)
	elif event.is_action_released("attack"):
		_button_released(Charging.ATTACK)
	elif event.is_action_pressed("throw"):
		_button_pressed(Charging.THROW)
	elif event.is_action_released("throw"):
		_button_released(Charging.THROW)
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event.is_action_pressed("slot_next"):
		select_slot(wrapi(active_slot + 1, 0, slots.size()))
	elif event.is_action_pressed("slot_prev"):
		select_slot(wrapi(active_slot - 1, 0, slots.size()))
	elif event.is_action_pressed("flashlight"):
		flashlight.visible = not flashlight.visible
	elif event.is_action_pressed("interact"):
		var target = get_interact_target()
		if target:
			target.interact(self)
		else:
			drop()


## Whatever station/door/item the crosshair is on, or null.
func get_interact_target():
	if ray.is_colliding():
		var c := ray.get_collider()
		if c and c.has_method("interact"):
			return c
	return null


# --- Upgrades -----------------------------------------------------------------

## Applies an upgrade the player just bought; `level` is the new level (1 = first purchase).
func apply_upgrade(id: String, level: int) -> void:
	match id:
		"shoes":
			speed_mult = 1.0 + 0.1 * level
		"bag":
			slots.append(null)
		"knuckles":
			punch_mult = 1.0 + 0.3 * level
		"flashlight":
			flashlight.spot_range = 20.0 + 8.0 * level
			flashlight.spot_angle = 28.0 + 6.0 * level
			flashlight.light_energy = 3.0 + 1.0 * level
		"energy":
			stamina_max = STAMINA_MAX * (1.0 + 0.3 * level)
			stamina = stamina_max


# --- Holding things -----------------------------------------------------------

## True when the selected slot is empty (fists out).
func hands_free() -> bool:
	return slots[active_slot] == null


## True when any slot is empty.
func has_room() -> bool:
	return slots.has(null)


func select_slot(i: int) -> void:
	if i < 0 or i >= slots.size() or i == active_slot:
		return
	_cancel_charge()
	if _anim_tween:
		_anim_tween.kill()
	hand.transform = _hand_rest
	_fist.visible = false
	active_slot = i
	refresh_held()


## Puts something in the selected slot if it's empty, otherwise the first empty slot.
## Returns false if the inventory is full.
func give(thing: Variant) -> bool:
	var i := active_slot if slots[active_slot] == null else slots.find(null)
	if i == -1:
		return false
	slots[i] = thing
	refresh_held()
	return true


## Removes a specific thing from whichever slot holds it.
func take(thing: Variant) -> void:
	var i := slots.find(thing)
	if i != -1:
		slots[i] = null
		refresh_held()


## Any pizza or fried food on you makes monsters smell you from further away.
func carrying_food() -> bool:
	for thing in slots:
		if thing is Pizza or (thing is Throwable and thing.kind == "sticks"):
			return true
	return false


## The pizza monsters will go after: the one in your hand, else any you're carrying.
func exposed_pizza() -> Pizza:
	if held:
		return held
	for thing in slots:
		if thing is Pizza:
			return thing
	return null


func set_held(p: Pizza) -> void:
	held = p
	refresh_held()


## Shakes whatever is in your hand and tints it red for a moment (damage feedback).
func flash_held() -> void:
	var red := StandardMaterial3D.new()
	red.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	red.albedo_color = Color(1, 0.1, 0.05, 0.6)
	red.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Quick shake of the held thing (its visual, so it doesn't fight swing/charge poses on the hand).
	var visual := hand.get_child(hand.get_child_count() - 1) as Node3D if hand.get_child_count() > 0 else null
	if visual:
		var tw := visual.create_tween()
		for i in 4:
			tw.tween_property(visual, "position", Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.03, 0.03)
		tw.tween_property(visual, "position", Vector3.ZERO, 0.04)
	var meshes := hand.find_children("*", "MeshInstance3D", true, false)
	for mi: MeshInstance3D in meshes:
		mi.material_overlay = red
	get_tree().create_timer(0.15).timeout.connect(func() -> void:
		for mi in meshes: # untyped: some may have been freed by a newer refresh_held()
			if is_instance_valid(mi):
				mi.material_overlay = null)


func refresh_held() -> void:
	for c in hand.get_children():
		c.queue_free()
	if held:
		hand.add_child(held.build_visual())
	elif held_item:
		hand.add_child(held_item.held_visual())


func pick_up(item: Throwable) -> void:
	# A thrown pizza goes back to being pizza data; other objects are stored as-is.
	var thing: Variant = item.pizza if item.pizza else item
	if not give(thing):
		return
	if item.pizza:
		item.queue_free()
	else:
		item.get_parent().remove_child(item)
	play_sfx(PICKUP, 0.9)


## Whatever you're holding goes in the trash.
func discard_held() -> void:
	if held_item:
		held_item.queue_free()
	held = null
	held_item = null
	refresh_held()


## Takes whatever is in your hands out as a world object, or null if hands are empty.
func _release_held() -> Throwable:
	if hands_free():
		return null
	var item: Throwable
	if held:
		item = Throwable.from_pizza(held)
		held = null
	else:
		item = held_item
		held_item = null
	refresh_held()
	hand.transform = _hand_rest
	get_tree().current_scene.add_child(item)
	return item


func _throw(charge_amount: float) -> void:
	var item := _release_held()
	if item == null:
		return
	var aim := -camera.global_transform.basis.z
	item.global_position = camera.global_position + aim * 0.6 + Vector3.DOWN * 0.15
	item.linear_velocity = aim * lerpf(THROW_SPEED.x, THROW_SPEED.y, charge_amount) + Vector3.UP * 1.5 + velocity * 0.5
	item.angular_velocity = Vector3(randf_range(-8, 8), randf_range(-8, 8), randf_range(-8, 8))
	item.thrown(charge_amount)
	play_sfx(WHOOSH, lerpf(1.5, 1.1, charge_amount), lerpf(-12.0, -5.0, charge_amount))


## Set it down at your feet. Gentle, so it can't hurt anything (including the pizza).
func drop() -> void:
	var item := _release_held()
	if item == null:
		return
	var forward := -global_transform.basis.z
	forward.y = 0.0
	item.global_position = global_position + forward.normalized() * 0.5 + Vector3.UP * 0.25
	item.global_rotation = Vector3(0, rotation.y, 0)
	item.linear_velocity = velocity * 0.5


# --- Fighting -----------------------------------------------------------------

func _button_pressed(kind: Charging) -> void:
	if _charging != Charging.NONE:
		if _charging != kind:
			_cancel_charge() # other button = cancel
		return
	if _attack_cd > 0.0 or _stun > 0.0:
		return
	if kind == Charging.THROW and hands_free():
		return
	_charging = kind
	charge = 0.0
	if _anim_tween:
		_anim_tween.kill() # cut the previous swing's return short
	_charge_from_hand = hand.transform
	_charge_from_fist = _fist.transform if _fist.visible else Transform3D(Basis.from_euler(FIST_REST_ROT), FIST_REST)
	if kind == Charging.ATTACK and hands_free():
		_fist.transform = _charge_from_fist
		_fist.visible = true


func _button_released(kind: Charging) -> void:
	if _charging != kind:
		return
	var power := charge
	_charging = Charging.NONE
	charge = 0.0
	if kind == Charging.THROW:
		_throw(power)
	else:
		_attack(power)


func _cancel_charge() -> void:
	_charging = Charging.NONE
	charge = 0.0
	_fist.visible = false
	hand.transform = _hand_rest


## Stats for whatever is in your hands right now.
func _weapon() -> Dictionary:
	if held:
		return PIZZA_SWING
	if held_item:
		return {
			"range": held_item.swing_range, "arc": held_item.swing_arc, "force": held_item.swing_force, "stun": held_item.swing_stun,
			"hits_all": held_item.swing_hits_all,
		}
	return PUNCH


func _attack(power: float) -> void:
	var w := _weapon()
	var fist := hands_free()
	play_sfx(WHOOSH, lerpf(1.3 if fist else 0.95, 0.8, power), lerpf(-8.0, -2.0, power))
	_attack_cd = _animate_attack()

	var targets := _monsters_in_front(w.range + CHARGE_RANGE_BONUS * power, w.arc)
	if targets.is_empty():
		return
	if not w.hits_all: # small things only land on the closest monster
		targets.sort_custom(func(a: Shambler, b: Shambler) -> bool:
			return a.global_position.distance_to(global_position) < b.global_position.distance_to(global_position))
		targets.resize(1)
	var force: float = w.force * lerpf(1.0, CHARGE_FORCE_MULT, power)
	if hands_free():
		force *= punch_mult
	var stun: float = w.stun * lerpf(1.0, CHARGE_STUN_MULT, power)
	for m in targets:
		var away := m.global_position - global_position
		away.y = 0.0
		m.knock_back(away.normalized() * force, stun)
	play_sfx(THUD, lerpf(1.1, 0.75, power), lerpf(-3.0, 3.0, power))
	_shake = maxf(_shake, lerpf(0.15, 0.45, power))
	if held:
		pizza_swung.emit()


## Plays the strike, then an interruptible return to rest. Returns how long the strike takes.
func _animate_attack() -> float:
	if _anim_tween:
		_anim_tween.kill()
	_anim_tween = create_tween()
	var tw := _anim_tween
	if hands_free():
		_fist.visible = true
		tw.tween_property(_fist, "transform", Transform3D(Basis.from_euler(FIST_STRIKE_ROT), FIST_STRIKE), 0.07)
		tw.tween_property(_fist, "transform", Transform3D(Basis.from_euler(FIST_REST_ROT), FIST_REST), 0.16)
		tw.tween_callback(_fist.hide)
		return 0.07
	if held:
		# Pizza: flat swipe through the middle and out to the left.
		tw.tween_property(hand, "transform", _hand_pose(PIZZA_MID, PIZZA_MID_ROT), 0.05)
		tw.tween_property(hand, "transform", _hand_pose(PIZZA_STRIKE, PIZZA_STRIKE_ROT), 0.06)
		tw.tween_property(hand, "transform", _hand_rest, 0.25)
		return 0.11
	tw.tween_property(hand, "transform", _item_swing_pose(FIST_STRIKE, FIST_STRIKE_ROT), 0.08)
	tw.tween_property(hand, "transform", _hand_rest, 0.22)
	return 0.08


## The hand's rest pose, moved by `offset` and turned by `rot` (radians).
func _hand_pose(offset: Vector3, rot: Vector3) -> Transform3D:
	return Transform3D(Basis.from_euler(rot) * _hand_rest.basis, _hand_rest.origin + offset)


## Held items follow the same arc as the fist: the fist's movement away from its rest pose
## is applied on top of the hand's rest pose.
func _item_swing_pose(fist_pos: Vector3, fist_rot: Vector3) -> Transform3D:
	return _hand_pose(fist_pos - FIST_REST, fist_rot)


func _monsters_in_front(reach: float, arc_degrees: float) -> Array[Shambler]:
	var forward := -global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var found: Array[Shambler] = []
	for m: Shambler in get_tree().get_nodes_in_group("monster"):
		var to := m.global_position - global_position
		to.y = 0.0
		var d := to.length()
		if d < reach and (d < 0.6 or forward.dot(to / d) > cos(deg_to_rad(arc_degrees))):
			found.append(m)
	return found


func take_hit(from: Vector3) -> void:
	var push := global_position - from
	push.y = 0.0
	push = push.normalized() if push.length() > 0.01 else transform.basis.z
	velocity = push * 9.0 + Vector3.UP * 3.5
	_stun = 0.35
	_shake = 0.5
	_cancel_charge()
	hit.emit()


# --- Movement -----------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_attack_cd = maxf(_attack_cd - delta, 0.0)
	if _charging != Charging.NONE:
		charge = minf(charge + delta / CHARGE_TIME, 1.0)
		var tremble := Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * 0.008 * charge
		var blend := clampf(charge / CHARGE_BLEND, 0.0, 1.0)
		if _charging == Charging.ATTACK and hands_free():
			var fist_pose := Transform3D(Basis.from_euler(FIST_REST_ROT.lerp(FIST_WOUND_ROT, charge)), FIST_REST.lerp(FIST_WOUND, charge))
			_fist.transform = _charge_from_fist.interpolate_with(fist_pose, blend)
			_fist.position += tremble
		else:
			var pose: Transform3D
			if _charging == Charging.ATTACK and held:
				pose = _hand_pose(PIZZA_WOUND * charge, PIZZA_WOUND_ROT * charge)
			elif _charging == Charging.ATTACK:
				pose = _item_swing_pose(FIST_REST.lerp(FIST_WOUND, charge), FIST_REST_ROT.lerp(FIST_WOUND_ROT, charge))
			else:
				pose = _hand_pose((HAND_WOUND_THROW - _hand_rest.origin) * charge, HAND_WOUND_THROW_ROT * charge)
			hand.transform = _charge_from_hand.interpolate_with(pose, blend)
			hand.position += tremble

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
		stamina = minf(stamina + STAMINA_REGEN * delta, stamina_max)

	if _stun > 0.0:
		_stun -= delta
		velocity.x = lerpf(velocity.x, 0.0, 2.0 * delta)
		velocity.z = lerpf(velocity.z, 0.0, 2.0 * delta)
	else:
		var speed := (SPRINT_SPEED if sprinting else WALK_SPEED) * speed_mult
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
	var fov := 82.0 if sprinting else 75.0
	fov -= 6.0 * charge # tunnel in slightly while winding up
	camera.fov = lerpf(camera.fov, fov, clampf(6.0 * delta, 0.0, 1.0))
