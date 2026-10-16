class_name Shambler
extends CharacterBody3D
## Host-controlled monster: a mindless pizza-sniffer.
##
## The HOST runs the brain and the physics. Its Sync node sends position, facing, who it's chasing
## (`target_id`) and whether it's reeling from a hit (`staggered`) to everyone. Other machines only
## animate what they see. Hits from players arrive as requests (request_hit) to the host.

enum State { WANDER, CHASE }

const WANDER_SPEED := 1.1
const CHASE_SPEED := 4.4 # faster than walking, slower than sprinting
const SMELL_RANGE := 14.0 # target carries food (pizza or sticks)
const SIGHT_RANGE := 6.0 # target is empty-handed
const GIVE_UP_RANGE := 24.0
const HIT_RANGE := 1.3
const STOP_RANGE := 1.0 # stand off this far instead of walking into/through players
const HIT_COOLDOWN := 1.6
const RECOVER_TIME := 0.9 # pause after a bite so the player can get away
const BITE_PUSH := 9.0
const BITE_STUN := 0.35
const BITE_DAMAGE := 34.0 # % off the victim's pizza
const BITE_HURT := 25.0 # off the victim's health (100): four bites and you're down

## Peer id of the player being chased, 0 = nobody. Synced: drives each player's heartbeat.
var target_id := 0
## True while reeling from a hit. Synced: everyone sees it rock back.
var staggered := false
## Dozing: early in the night only some monsters are up. Synced: everyone sees it slumped over.
var asleep := false

# Host-only brain state.
var state := State.WANDER
var home: Vector3
var _wander_target: Vector3
var _wander_timer := 0.0
var _cooldown := 0.0
var _recover := 0.0
var _knock := Vector3.ZERO
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
# Animation (every machine).
var _t := 0.0
var _last_position := Vector3.ZERO

@onready var visual: Node3D = $Visual


func _ready() -> void:
	set_multiplayer_authority(1)
	home = global_position
	_last_position = global_position
	_t = randf() * 10.0
	_pick_wander()


func is_chasing() -> bool:
	return target_id != 0


func _physics_process(delta: float) -> void:
	if multiplayer.is_server():
		_think(delta)
	_animate(delta)


# --- Brain (host only) ---------------------------------------------------------------

func _think(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	_recover = maxf(_recover - delta, 0.0)
	if not is_on_floor():
		velocity.y -= _gravity * delta

	# The night ramps up: more of them awake, and the awake ones faster with sharper noses.
	var danger := NightCycle.instance.danger()
	asleep = not _is_awake(danger)
	var target: Player = null if asleep else _choose_target(1.0 + 0.3 * danger)
	if target:
		state = State.CHASE
		target_id = target.name.to_int()
	elif state == State.CHASE:
		state = State.WANDER
		target_id = 0
		_pick_wander() # shamble back home

	var dir := Vector3.ZERO
	var speed := 0.0
	if target:
		var to := target.global_position - global_position
		to.y = 0.0
		var dist := to.length()
		dir = to / maxf(dist, 0.001)
		speed = CHASE_SPEED * (1.0 + 0.2 * danger) if dist > STOP_RANGE else 0.0 # still faces you while standing off
		if dist < HIT_RANGE and _cooldown <= 0.0 and _recover <= 0.0:
			_bite(target)
	elif not asleep:
		_wander_timer -= delta
		var to_target := _wander_target - global_position
		to_target.y = 0.0
		if to_target.length() < 0.5 or _wander_timer <= 0.0:
			_pick_wander()
		else:
			dir = to_target.normalized()
			speed = WANDER_SPEED

	if _recover > 0.0 or World.instance.freeze_monsters:
		speed = 0.0
	if World.is_in_shop(global_position + dir * 0.6):
		speed = 0.0 # the shop is safe ground

	velocity.x = dir.x * speed + _knock.x
	velocity.z = dir.z * speed + _knock.z
	_knock = _knock.move_toward(Vector3.ZERO, 20.0 * delta)
	staggered = _knock.length() > 1.0
	move_and_slide()
	if dir != Vector3.ZERO:
		rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), 6.0 * delta)


## Keep chasing the current target while it's still fair game; otherwise pick the closest player
## it can smell (carrying food) or see (close by). Nobody inside the shop counts, and it loses
## interest in anyone already down (the kidnapper won't, later).
func _choose_target(senses: float) -> Player:
	var current := World.instance.player(target_id) if target_id != 0 else null
	if current and not current.downed and not World.is_in_shop(current.global_position) \
			and _flat_dist(current) < GIVE_UP_RANGE:
		return current
	var best: Player = null
	var best_d := INF
	for p: Player in World.instance.players.get_children():
		if p.downed or World.is_in_shop(p.global_position):
			continue
		var d := _flat_dist(p)
		var detect := (SMELL_RANGE if p.carrying_food() else SIGHT_RANGE) * senses
		if d < detect and d < best_d:
			best = p
			best_d = d
	return best


## Knock the player back (on their machine) and take a bite out of their pizza (host decides).
func _bite(victim: Player) -> void:
	_cooldown = HIT_COOLDOWN
	_recover = RECOVER_TIME
	var push := victim.global_position - global_position
	push.y = 0.0
	push = push.normalized() if push.length() > 0.01 else Vector3.FORWARD
	victim.receive_shove.rpc_id(victim.name.to_int(), push * BITE_PUSH, BITE_STUN)
	victim.hurt.rpc_id(victim.name.to_int(), BITE_HURT)
	var pizza := victim.exposed_pizza()
	if pizza:
		pizza.damage_pizza(BITE_DAMAGE, "They got the pizza!")


## Host only: shoved by a player's punch/swing or a thrown item. Slides away, staggers, gets angry.
func knock_back(force: Vector3, stun: float) -> void:
	_knock = force
	_recover = maxf(_recover, stun)
	if is_on_floor():
		velocity.y = 2.5


## A player's attack landed (sent from the attacker's machine).
@rpc("any_peer", "call_local", "reliable")
func request_hit(force: Vector3, stun: float) -> void:
	if multiplayer.is_server():
		knock_back(force, stun)


## A third of them are up at opening, all of them by last call. Monsters already chasing stay up.
func _is_awake(danger: float) -> bool:
	if target_id != 0:
		return true
	var total := get_parent().get_child_count()
	var index := name.trim_prefix("monster_").to_int()
	return index < ceili(total * clampf(0.35 + 0.65 * danger, 0.0, 1.0))


func _pick_wander() -> void:
	_wander_target = home + Vector3(randf_range(-6, 6), 0, randf_range(-6, 6))
	_wander_timer = randf_range(3.0, 7.0)


func _flat_dist(n: Node3D) -> float:
	return Vector2(n.global_position.x - global_position.x, n.global_position.z - global_position.z).length()


# --- Animation (every machine, from what it sees) ---------------------------------------

func _animate(delta: float) -> void:
	_t += delta
	var moved := global_position - _last_position
	_last_position = global_position
	moved.y = 0.0
	var gait := clampf(moved.length() / maxf(delta, 0.0001) / CHASE_SPEED, 0.0, 1.0)
	var cycle := sin(_t * (3.0 + 6.0 * gait))
	visual.rotation.z = cycle * (0.08 + 0.1 * gait)
	visual.position.y = absf(cycle) * 0.08 * gait
	# Rock back when hit; slump forward, barely swaying, while dozing.
	var lean := 0.5 if staggered else (-0.45 + sin(_t * 0.8) * 0.04 if asleep else 0.0)
	visual.rotation.x = lerpf(visual.rotation.x, lean, (10.0 if not asleep else 2.0) * delta)
