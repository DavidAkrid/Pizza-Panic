class_name Throwable
extends RigidBody3D
## Something you can pick up (E) and throw (right click). A thrown pizza becomes one of these too.

const LAYER := 2 | 16 # interactable + props: the interact ray finds it, the player walks through it
const MASK := 1 | 8 | 16 # bounces off the world, monsters, and other props
const CLINK := preload("res://audio/clink.wav")
const THUD := preload("res://audio/thud.wav")
const PIZZA_IMPACT_DAMAGE := Vector2(3.0, 15.0) # tap throw -> full charge
const HIT_SPEED := 4.0 # minimum speed for a throw to count as a hit
const SODA_COLORS := [Color(0.75, 0.1, 0.1), Color(0.1, 0.3, 0.75), Color(0.15, 0.6, 0.2), Color(0.85, 0.55, 0.1)]

@export var item_name := "Soda"
@export_group("Swung")
@export var swing_force := 5.0
@export var swing_stun := 0.5
@export var swing_range := 1.9
@export var swing_arc := 60.0 ## degrees either side of straight ahead
@export var swing_hits_all := false ## big items hit everything in the arc, small ones only the closest
@export_group("Thrown")
@export var throw_force := 7.0
@export var throw_stun := 1.0

var pizza: Pizza ## set when this is a thrown pizza
var _live := false # thrown and hasn't hit anything yet
var _charge := 0.0 # how charged the throw was, 0..1
# Last few frames of velocity. Contacts can be reported a frame after the bounce already
# slowed us down, so impacts are judged by the fastest recent sample.
var _recent_velocities: Array[Vector3] = []
var _sound_cd := 0.0
var _audio: AudioStreamPlayer3D


## Wraps the player's pizza in a physics body so it can fly.
static func from_pizza(p: Pizza) -> Throwable:
	var t := Throwable.new()
	t.pizza = p
	t.item_name = "pizza"
	t.mass = 0.8
	t.throw_force = 8.0
	t.throw_stun = 1.0
	var shape := BoxShape3D.new()
	# Match the visual: a box is 7cm tall, a bare pizza is just the 3cm crust.
	shape.size = Vector3(0.42, 0.07 if p.stage == Pizza.Stage.BOXED else 0.03, 0.42)
	var col := CollisionShape3D.new()
	col.shape = shape
	t.add_child(col)
	t._rebuild_pizza_visual()
	return t


func _ready() -> void:
	collision_layer = LAYER
	collision_mask = MASK
	contact_monitor = true
	max_contacts_reported = 4
	continuous_cd = true
	body_entered.connect(_on_body_entered)
	_audio = AudioStreamPlayer3D.new()
	_audio.stream = THUD if pizza else CLINK
	add_child(_audio)
	if pizza == null:
		var mesh := get_node_or_null("Mesh") as MeshInstance3D
		if mesh and mesh.material_override == null:
			var mat := StandardMaterial3D.new()
			mat.albedo_color = SODA_COLORS.pick_random()
			mat.metallic = 0.6
			mat.roughness = 0.35
			mesh.material_override = mat


func get_prompt(p: Player) -> String:
	var what := pizza.describe() if pizza else item_name
	return "[E] Pick up %s" % what if p.hands_free() else "%s (hands full)" % what


func interact(p: Player) -> void:
	p.pick_up(self)


## Copy of this object's look for the player's hand.
func held_visual() -> Node3D:
	if pizza:
		return pizza.build_visual()
	var v: Node3D = get_node("Mesh").duplicate()
	v.transform = Transform3D.IDENTITY
	v.scale = Vector3.ONE * 1.6 # the hand node is scaled down for pizzas
	return v


## `charge_amount` (0 = tap, 1 = full) scales how hard it hits and how much a pizza suffers.
func thrown(charge_amount: float) -> void:
	_live = true
	_charge = charge_amount
	_recent_velocities.clear() # forget velocities from before it was picked up


func _physics_process(delta: float) -> void:
	_sound_cd -= delta
	_recent_velocities.push_back(linear_velocity)
	if _recent_velocities.size() > 3:
		_recent_velocities.pop_front()


func _impact_velocity() -> Vector3:
	var best := linear_velocity
	for v in _recent_velocities:
		if v.length() > best.length():
			best = v
	return best


func _on_body_entered(body: Node) -> void:
	var impact := _impact_velocity()
	var speed := impact.length()
	if speed > 1.5 and _sound_cd <= 0.0:
		_audio.pitch_scale = randf_range(0.9, 1.2)
		_audio.volume_db = linear_to_db(clampf(speed / 10.0, 0.15, 1.0))
		_audio.play()
		_sound_cd = 0.12
	if not _live or speed < HIT_SPEED:
		return
	_live = false # one hit per throw

	if body is Shambler:
		var push := impact
		push.y = 0.0
		var force_mult := lerpf(1.0, Player.CHARGE_FORCE_MULT, _charge)
		var stun_mult := lerpf(1.0, Player.CHARGE_STUN_MULT, _charge)
		(body as Shambler).knock_back(push.normalized() * throw_force * force_mult, throw_stun * stun_mult)

	if pizza:
		pizza.condition -= lerpf(PIZZA_IMPACT_DAMAGE.x, PIZZA_IMPACT_DAMAGE.y, _charge)
		if pizza.condition <= 0.0:
			Game.instance.hud.show_message("The pizza splattered!\nBack to the shop to make another.", 4.0)
			queue_free()
		else:
			_rebuild_pizza_visual()


func _rebuild_pizza_visual() -> void:
	var old := get_node_or_null("Mesh")
	if old:
		remove_child(old)
		old.queue_free()
	var v := pizza.build_visual()
	v.name = "Mesh"
	add_child(v)
