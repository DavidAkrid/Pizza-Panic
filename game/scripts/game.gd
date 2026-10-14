class_name Game
extends Node
## Runs the loop: orders, delivery + payment, shop-vs-outside mood, monster spawns.

const SHAMBLER := preload("res://scenes/shambler.tscn")
const BASE_PAY := 20.0
const PERFECT_TIP := 10
const HIT_DAMAGE := 34.0 # monster bite
const SWING_DAMAGE := 15.0 # using the pizza as a weapon
## Shop footprint on the XZ plane (plus a buffer outside the door). Monsters never enter it.
const SHOP_MIN := Vector2(-5.6, -0.8)
const SHOP_MAX := Vector2(5.6, 8.6)
const SHOP_DOOR := Vector3(0, 2.2, -0.5)

class Order:
	var toppings: Array[String] = []
	var house: House

static var instance: Game

@export var player: Player
@export var hud: Hud
@export var neighborhood: Neighborhood
@export var world_env: WorldEnvironment
@export var ambience: Ambience
@export var order_board: Label3D

var money := 0
var order: Order
var freeze_monsters := false
var _last_house: House
var _env_tween: Tween


static func is_in_shop(pos: Vector3) -> bool:
	return pos.x > SHOP_MIN.x and pos.x < SHOP_MAX.x and pos.z > SHOP_MIN.y and pos.z < SHOP_MAX.y


func _enter_tree() -> void:
	instance = self


func _ready() -> void:
	player.hit.connect(_on_player_hit)
	player.pizza_swung.connect(_on_pizza_swung)
	_spawn_monsters.call_deferred()
	_set_inside(true)
	_new_order()
	hud.show_message("Welcome to Pizza Panic.\nCheck the order board, make the pizza, deliver it.", 6.0)
	var shot_dir := _arg("--shots=")
	if shot_dir != "":
		_run_shots(shot_dir)


func _process(_delta: float) -> void:
	var chasing := false
	for m in get_tree().get_nodes_in_group("monster"):
		if (m as Shambler).is_chasing():
			chasing = true
			break
	ambience.chasing = chasing
	_refresh_hud()


# --- Orders & delivery -------------------------------------------------------

func _new_order() -> void:
	var o := Order.new()
	var names: Array = Pizza.TOPPINGS.keys()
	names.shuffle()
	for i in randi_range(1, 2):
		o.toppings.append(names[i])
	var houses := neighborhood.houses
	if _last_house == null:
		o.house = houses[0] # first delivery is always the close one
	else:
		o.house = houses.pick_random()
		while o.house == _last_house:
			o.house = houses.pick_random()
	order = o
	for h in houses:
		h.set_active(h == o.house)
	order_board.text = "ORDER UP!\n%s\nDeliver to %s" % [" + ".join(PackedStringArray(o.toppings)), o.house.address]


func door_prompt(house: House, p: Player) -> String:
	if order and order.house == house:
		if p.held and p.held.stage == Pizza.Stage.BOXED:
			return "[E] Deliver to %s" % house.address
		return "%s is waiting for a boxed pizza" % house.address
	return "%s - nobody ordered" % house.address


func try_deliver(house: House, p: Player) -> void:
	if order == null or order.house != house:
		hud.show_message("Nobody here ordered a pizza.", 2.0)
		return
	var pizza := p.held
	if pizza == null or pizza.stage != Pizza.Stage.BOXED:
		hud.show_message("You need a boxed pizza.", 2.0)
		return

	var correct := 0
	for t in order.toppings:
		if t in pizza.toppings:
			correct += 1
	var missing := order.toppings.size() - correct
	var extra := pizza.toppings.size() - correct
	var accuracy := clampf(1.0 - 0.35 * missing - 0.2 * extra, 0.1, 1.0)
	var pay := int(round(BASE_PAY * accuracy * pizza.bake_quality * pizza.condition / 100.0))
	var tip := 0
	if missing == 0 and extra == 0 and pizza.bake_label == "perfect" and pizza.condition >= 100.0:
		tip = PERFECT_TIP
	money += pay + tip

	p.set_held(null)
	house.set_active(false)
	_last_house = house
	order = null
	order_board.text = "No orders right now."

	var lines := PackedStringArray(["Delivered! +$%d" % (pay + tip)])
	if missing == 0 and extra == 0:
		lines.append("Toppings: correct")
	else:
		lines.append("Toppings: %d missing, %d extra" % [missing, extra])
	lines.append("Bake: %s   Condition: %d%%" % [pizza.bake_label, int(pizza.condition)])
	if tip > 0:
		lines.append("Perfect pizza! +$%d tip" % tip)
	lines.append("Head back to the shop.")
	hud.show_message("\n".join(lines), 6.0)


func _on_player_hit() -> void:
	_damage_pizza(HIT_DAMAGE, "They got the pizza!")


func _on_pizza_swung() -> void:
	_damage_pizza(SWING_DAMAGE, "Pizza to the face!")


func _damage_pizza(amount: float, what: String) -> void:
	var p := player.held
	if p == null:
		return
	p.condition -= amount
	if p.condition <= 0.0:
		player.set_held(null)
		hud.show_message("The pizza is destroyed!\nBack to the shop to make another.", 4.0)
	else:
		player.refresh_held()
		hud.show_message("%s %d%% left" % [what, int(p.condition)], 2.0)


## Monsters spawn once and stay in the world; ones that lose you shamble back home.
func _spawn_monsters() -> void:
	for pos in neighborhood.spawn_points:
		var m: Node3D = SHAMBLER.instantiate()
		m.position = pos
		neighborhood.add_child(m)


# --- Shop vs. outside ---------------------------------------------------------

func _on_shop_area_body_entered(body: Node3D) -> void:
	if body != player:
		return
	_set_inside(true)
	if order == null:
		_new_order()
		hud.show_message("New order on the board!", 3.0)


func _on_shop_area_body_exited(body: Node3D) -> void:
	if body == player:
		_set_inside(false)


func _set_inside(inside: bool) -> void:
	player.in_shop = inside
	ambience.inside = inside
	var env := world_env.environment
	if _env_tween:
		_env_tween.kill()
	_env_tween = create_tween().set_parallel()
	_env_tween.tween_property(env, "fog_density", 0.01 if inside else 0.045, 1.2)
	_env_tween.tween_property(env, "volumetric_fog_density", 0.0 if inside else 0.025, 1.2)
	_env_tween.tween_property(env, "ambient_light_energy", 0.5 if inside else 0.2, 1.2)


# --- HUD ---------------------------------------------------------------------

func _refresh_hud() -> void:
	var lines := PackedStringArray()
	if order:
		lines.append("ORDER: " + " + ".join(PackedStringArray(order.toppings)))
		lines.append("DELIVER TO: " + order.house.address)
	else:
		lines.append("No order. Head back to the shop.")
	var hands := "empty"
	if player.held:
		hands = player.held.describe()
	elif player.held_item:
		hands = player.held_item.item_name
	lines.append("HANDS: " + hands)
	hud.order_label.text = "\n".join(lines)
	hud.money_label.text = "$%d" % money
	hud.set_stamina(player.stamina / Player.STAMINA_MAX)

	var target = player.get_interact_target()
	hud.prompt_label.text = target.get_prompt(player) if target else ""

	var fwd := -player.global_transform.basis.z
	hud.compass.heading = atan2(fwd.x, -fwd.z)
	if order:
		hud.compass.marker_bearing = Compass.bearing(player.global_position, order.house.marker_position())
		hud.compass.marker_color = Color(1, 0.85, 0.4)
	elif not player.in_shop:
		hud.compass.marker_bearing = Compass.bearing(player.global_position, SHOP_DOOR)
		hud.compass.marker_color = Color(1, 0.5, 0.3)
	else:
		hud.compass.marker_bearing = NAN


# --- Dev test harness: run with `-- --shots=<dir>` -----------------------------
# Scratch space for checking new work: screenshots and scripted checks. Once a feature is
# verified, delete its checks from here so runs stay fast.

func _arg(prefix: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(prefix):
			return a.trim_prefix(prefix)
	return ""


func _run_shots(_dir: String) -> void:
	freeze_monsters = true
	await get_tree().create_timer(1.5).timeout
	# (no pending checks)
	get_tree().quit()


## Saves the current frame as <dir>/<name>.png.
func _capture(dir: String, name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(dir.path_join(name + ".png"))


## Puts the player at `pos`, facing yaw/pitch in degrees, and lets the scene settle.
func _pose(pos: Vector3, yaw: float, pitch := 0.0) -> void:
	player.global_position = pos
	player.velocity = Vector3.ZERO
	player.rotation.y = deg_to_rad(yaw)
	player.head.rotation.x = deg_to_rad(pitch)
	await get_tree().create_timer(1.0).timeout


## Stands the player `dist` meters south of a monster, facing it.
func _face(m: Node3D, dist: float) -> void:
	await _pose(m.global_position + Vector3(0, 0, dist), 0.0, -5.0)
