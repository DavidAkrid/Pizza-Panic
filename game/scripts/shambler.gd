class_name Shambler
extends CharacterBody3D
## Mindless pizza-sniffer. Wanders near its spawn; chases if it smells pizza or sees you up close.

enum State { WANDER, CHASE }

const WANDER_SPEED := 1.1
const CHASE_SPEED := 4.4 # faster than walking, slower than sprinting
const SMELL_RANGE := 14.0 # when you're carrying food
const SIGHT_RANGE := 6.0 # empty-handed
const GIVE_UP_RANGE := 24.0
const HIT_RANGE := 1.3
const STOP_RANGE := 1.0 # stand off this far instead of walking into/through the player
const HIT_COOLDOWN := 1.6
const RECOVER_TIME := 0.9 # pause after a hit so you can get away

var state := State.WANDER
var home: Vector3
var _wander_target: Vector3
var _wander_timer := 0.0
var _cooldown := 0.0
var _recover := 0.0
var _t := 0.0
var _knock := Vector3.ZERO
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var visual: Node3D = $Visual
@onready var player: Player = get_tree().get_first_node_in_group("player")


func _ready() -> void:
	home = global_position
	_t = randf() * 10.0
	_pick_wander()


func is_chasing() -> bool:
	return state == State.CHASE


## Shoved by the player: slides away, staggers, and gets angry.
func knock_back(force: Vector3, stun: float) -> void:
	_knock = force
	_recover = maxf(_recover, stun)
	if is_on_floor():
		velocity.y = 2.5
	if not player.in_shop:
		state = State.CHASE


func _physics_process(delta: float) -> void:
	_t += delta
	_cooldown = maxf(_cooldown - delta, 0.0)
	_recover = maxf(_recover - delta, 0.0)
	if not is_on_floor():
		velocity.y -= _gravity * delta

	var to_player := player.global_position - global_position
	to_player.y = 0.0
	var dist := to_player.length()
	var detect := SMELL_RANGE if player.carrying_food() else SIGHT_RANGE

	if state == State.WANDER and not player.in_shop and dist < detect:
		state = State.CHASE
	elif state == State.CHASE and (player.in_shop or dist > GIVE_UP_RANGE):
		state = State.WANDER
		_pick_wander()

	var dir := Vector3.ZERO
	var speed := 0.0
	if state == State.CHASE:
		dir = to_player / maxf(dist, 0.001)
		speed = CHASE_SPEED if dist > STOP_RANGE else 0.0 # still faces you while standing off
		if dist < HIT_RANGE and _cooldown <= 0.0 and _recover <= 0.0:
			player.take_hit(global_position)
			_cooldown = HIT_COOLDOWN
			_recover = RECOVER_TIME
	else:
		_wander_timer -= delta
		var to_target := _wander_target - global_position
		to_target.y = 0.0
		if to_target.length() < 0.5 or _wander_timer <= 0.0:
			_pick_wander()
		else:
			dir = to_target.normalized()
			speed = WANDER_SPEED

	if _recover > 0.0 or Game.instance.freeze_monsters:
		speed = 0.0
	if Game.is_in_shop(global_position + dir * 0.6):
		speed = 0.0 # the shop is safe ground

	velocity.x = dir.x * speed + _knock.x
	velocity.z = dir.z * speed + _knock.z
	_knock = _knock.move_toward(Vector3.ZERO, 20.0 * delta)
	move_and_slide()

	if dir != Vector3.ZERO:
		rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), 6.0 * delta)
	var gait := speed / CHASE_SPEED
	var cycle := sin(_t * (3.0 + 6.0 * gait))
	visual.rotation.z = cycle * (0.08 + 0.1 * gait)
	visual.position.y = absf(cycle) * 0.08 * gait
	visual.rotation.x = lerpf(visual.rotation.x, 0.5 if _knock.length() > 1.0 else 0.0, 10.0 * delta) # rock back when hit


func _pick_wander() -> void:
	_wander_target = home + Vector3(randf_range(-6, 6), 0, randf_range(-6, 6))
	_wander_timer = randf_range(3.0, 7.0)
