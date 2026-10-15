class_name PlayerCombat
extends Node
## Charged punch / swing / throw for one player. Every player gets one as a child named "Combat".
##
## Runs on the attacker's machine. Hits are delivered to whoever owns the target:
##   - other players  -> their own machine (Player.receive_shove). Friends only get SHOVED:
##                        no damage to them or anything they carry.
##   - loose items    -> the host (Item.request_knock).
##   - monsters       -> the host (monsters step).
## Other machines see the strike animation and hear the whoosh via show_attack().

enum Charging { NONE, ATTACK, THROW }

# Hold a mouse button to charge (punch/swing on left, throw on right). Tap = 0, full = 1.
const CHARGE_TIME := 1.0
const CHARGE_FORCE_MULT := 2.6
const CHARGE_STUN_MULT := 2.0
const CHARGE_RANGE_BONUS := 0.4
const CHARGE_BLEND := 0.12 # first part of a wind-up eases in from wherever the hand was
## Fists. Held items bring their own stats (Item.weapon()).
## "arc" = degrees either side of straight ahead the attack can hit.
const PUNCH := {"range": 1.8, "arc": 60.0, "force": 6.0, "stun": 0.6, "hits_all": false}
const PLAYER_SHOVE_MULT := 0.6 # friends get a softer shove than monsters will
const PROP_KNOCK_MULT := 0.5 # how hard loose items get batted around
const THROW_SPEED := Vector2(6.0, 16.0) # tap lob -> full charge

# Poses (position + rotation in radians), relative to the head.
const FIST_REST := Vector3(0.22, -0.28, -0.4)
const FIST_REST_ROT := Vector3.ZERO
const FIST_WOUND := Vector3(0.34, -0.24, -0.32)
const FIST_WOUND_ROT := Vector3(0.15, -0.5, -0.35)
const FIST_STRIKE := Vector3(-0.02, -0.15, -0.75)
const FIST_STRIKE_ROT := Vector3(-0.05, 0.35, 0.7)
const HAND_WOUND_THROW := Vector3(0.38, -0.02, -0.3)
const HAND_WOUND_THROW_ROT := Vector3(0.8, 0.0, 0.0)

const WHOOSH := preload("res://audio/whoosh.wav")
const THUD := preload("res://audio/thud.wav")

var player: Player
var charge := 0.0 ## 0..1 while winding up
var _charging := Charging.NONE
var _attack_cd := 0.0 ## next attack allowed once the current strike lands
var _anim_tween: Tween
var _charge_from_hand: Transform3D # where the hand/fist were when this wind-up started,
var _charge_from_fist: Transform3D # so interrupting a return blends instead of snapping
var _hand_rest: Transform3D
var _fist: MeshInstance3D


func setup(p: Player) -> void:
	player = p
	_hand_rest = p.hand.transform
	var fist_mesh := BoxMesh.new()
	fist_mesh.size = Vector3(0.11, 0.11, 0.22)
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.85, 0.65, 0.5)
	fist_mesh.material = skin
	_fist = MeshInstance3D.new()
	_fist.mesh = fist_mesh
	_fist.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fist.visible = false
	p.head.add_child(_fist) # under the head (not the camera) so other players see it too


func is_charging() -> bool:
	return _charging != Charging.NONE


# --- Input (local player only) ------------------------------------------------------

func button_pressed(kind: Charging) -> void:
	if _charging != Charging.NONE:
		if _charging != kind:
			cancel() # the other button cancels
		return
	if _attack_cd > 0.0 or player.is_stunned():
		return
	if kind == Charging.THROW and player.hands_free():
		return
	_charging = kind
	charge = 0.0
	if _anim_tween:
		_anim_tween.kill() # cut the previous swing's return short
	_charge_from_hand = player.hand.transform
	_charge_from_fist = _fist.transform if _fist.visible else _pose(FIST_REST, FIST_REST_ROT)
	if kind == Charging.ATTACK and player.hands_free():
		_fist.transform = _charge_from_fist
		_fist.visible = true


func button_released(kind: Charging) -> void:
	if _charging != kind:
		return
	var power := charge
	_charging = Charging.NONE
	charge = 0.0
	if kind == Charging.THROW:
		_throw(power)
	else:
		_attack(power)


func cancel() -> void:
	_charging = Charging.NONE
	charge = 0.0
	_fist.visible = false
	player.hand.transform = _hand_rest


## Called every physics tick on the local player.
func tick(delta: float) -> void:
	_attack_cd = maxf(_attack_cd - delta, 0.0)
	if _charging == Charging.NONE:
		return
	charge = minf(charge + delta / CHARGE_TIME, 1.0)
	var tremble := Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * 0.008 * charge
	var blend := clampf(charge / CHARGE_BLEND, 0.0, 1.0)
	if _charging == Charging.ATTACK and player.hands_free():
		var target := _pose(FIST_REST.lerp(FIST_WOUND, charge), FIST_REST_ROT.lerp(FIST_WOUND_ROT, charge))
		_fist.transform = _charge_from_fist.interpolate_with(target, blend)
		_fist.position += tremble
	else:
		var target: Transform3D
		if _charging == Charging.ATTACK:
			target = _hand_pose(FIST_REST.lerp(FIST_WOUND, charge) - FIST_REST, FIST_REST_ROT.lerp(FIST_WOUND_ROT, charge))
		else:
			target = _hand_pose((HAND_WOUND_THROW - _hand_rest.origin) * charge, HAND_WOUND_THROW_ROT * charge)
		player.hand.transform = _charge_from_hand.interpolate_with(target, blend)
		player.hand.position += tremble


# --- Attacks ---------------------------------------------------------------------------

func _attack(power: float) -> void:
	var item := player.held_item()
	var w: Dictionary = item.weapon() if item else PUNCH
	_attack_cd = _animate_strike(item != null)
	show_attack.rpc(item != null)
	player.play_sfx(WHOOSH, lerpf(1.3 if item == null else 0.95, 0.8, power), lerpf(-8.0, -2.0, power))

	var targets := _targets_in_front(w.range + CHARGE_RANGE_BONUS * power, w.arc)
	if targets.is_empty():
		return
	if not w.hits_all: # small things only land on the closest target
		targets.sort_custom(func(a: Node3D, b: Node3D) -> bool:
			return _dist(a) < _dist(b))
		targets.resize(1)
	var force: float = w.force * lerpf(1.0, CHARGE_FORCE_MULT, power)
	if item == null:
		force *= player.punch_mult # brass knuckles
	var stun: float = w.stun * lerpf(1.0, CHARGE_STUN_MULT, power)
	for t in targets:
		var away := t.global_position - player.global_position
		away.y = 0.0
		away = away.normalized()
		if t is Player:
			t.receive_shove.rpc_id(t.name.to_int(), away * force * PLAYER_SHOVE_MULT, stun * 0.5)
		elif t is Item:
			t.request_knock.rpc_id(1, away * force * PROP_KNOCK_MULT + Vector3.UP * 1.5)
		elif t is Shambler:
			t.request_hit.rpc_id(1, away * force, stun) # monsters get the full force
	player.play_sfx(THUD, lerpf(1.1, 0.75, power), lerpf(-3.0, 3.0, power))
	player.shake(lerpf(0.15, 0.45, power))
	if item:
		item.request_swung.rpc_id(1) # pizzas get hurt by being used as a weapon


func _throw(power: float) -> void:
	var item := player.held_item()
	if item == null:
		return
	player.hand.transform = _hand_rest
	item.request_throw.rpc_id(1, -player.camera.global_transform.basis.z, power)
	show_attack.rpc(true)
	player.play_sfx(WHOOSH, lerpf(1.5, 1.1, power), lerpf(-12.0, -5.0, power))


## Other players, and items lying loose, within reach and inside the arc.
func _targets_in_front(reach: float, arc_degrees: float) -> Array[Node3D]:
	var forward := -player.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var candidates: Array[Node3D] = []
	for p: Player in player.get_tree().get_nodes_in_group("players"):
		if p != player:
			candidates.append(p)
	for it: Item in player.get_tree().get_nodes_in_group("items"):
		if it.holder == 0:
			candidates.append(it)
	for m: Shambler in player.get_tree().get_nodes_in_group("monster"):
		candidates.append(m)
	var found: Array[Node3D] = []
	var min_dot := cos(deg_to_rad(arc_degrees))
	for c in candidates:
		var to := c.global_position - player.global_position
		to.y = 0.0
		var d := to.length()
		if d < reach and (d < 0.6 or forward.dot(to / d) > min_dot):
			found.append(c)
	return found


func _dist(n: Node3D) -> float:
	return n.global_position.distance_to(player.global_position)


# --- What everyone else sees -----------------------------------------------------------

## Plays the strike on other machines: the hand/fist animation and a whoosh from your spot.
@rpc("any_peer", "call_remote", "unreliable")
func show_attack(with_item: bool) -> void:
	_animate_strike(with_item)
	var a := AudioStreamPlayer3D.new()
	a.stream = WHOOSH
	a.unit_size = 4.0
	a.finished.connect(a.queue_free)
	player.add_child(a)
	a.play()


## Strike, then an interruptible return to rest. Returns how long the strike takes.
func _animate_strike(with_item: bool) -> float:
	if _anim_tween:
		_anim_tween.kill()
	_anim_tween = create_tween()
	if not with_item:
		_fist.visible = true
		_anim_tween.tween_property(_fist, "transform", _pose(FIST_STRIKE, FIST_STRIKE_ROT), 0.07)
		_anim_tween.tween_property(_fist, "transform", _pose(FIST_REST, FIST_REST_ROT), 0.16)
		_anim_tween.tween_callback(_fist.hide)
		return 0.07
	_anim_tween.tween_property(player.hand, "transform", _hand_pose(FIST_STRIKE - FIST_REST, FIST_STRIKE_ROT), 0.08)
	_anim_tween.tween_property(player.hand, "transform", _hand_rest, 0.22)
	return 0.08


func _pose(pos: Vector3, rot: Vector3) -> Transform3D:
	return Transform3D(Basis.from_euler(rot), pos)


## The hand's rest pose, moved by `offset` and turned by `rot`.
func _hand_pose(offset: Vector3, rot: Vector3) -> Transform3D:
	return Transform3D(Basis.from_euler(rot) * _hand_rest.basis, _hand_rest.origin + offset)
