class_name Game
extends Node
## Runs the loop: orders, delivery + payment, shop-vs-outside mood, monster spawns.

const SHAMBLER := preload("res://scenes/shambler.tscn")
const HITMARKER_SFX := preload("res://audio/hitmarker.wav")
const KACHING := preload("res://audio/kaching.wav")
## Shop wall upgrades. Costs list one price per level; effects live in Player.apply_upgrade.
const UPGRADES := {
	"shoes": {"name": "Running Shoes", "effect": "+10% move speed", "costs": [30, 60, 100]},
	"bag": {"name": "Bigger Bag", "effect": "+1 inventory slot", "costs": [50, 100, 150, 200]},
	"knuckles": {"name": "Brass Knuckles", "effect": "+30% punch power", "costs": [40, 80, 120]},
	"flashlight": {"name": "Better Flashlight", "effect": "brighter, wider, further", "costs": [25, 60]},
	"energy": {"name": "Energy Drink", "effect": "+30% stamina", "costs": [30, 60, 90]},
}
const PAY := {"pizza": 20.0, "sticks": 8.0, "soda": 3.0} # base pay per item before quality
const PERFECT_TIP := 10
## Chance weights for what an order item is.
const ITEM_WEIGHTS := {"pizza": 6.0, "sticks": 3.0, "soda": 2.0}
const HIT_DAMAGE := 34.0 # monster bite
const SWING_DAMAGE := 15.0 # using the pizza as a weapon
## An unboxed pizza outside the shop slowly goes cold: a nudge to box it before heading out.
const COLD_DAMAGE := 1.0
const COLD_INTERVAL := 3.0
## Shop footprint on the XZ plane (plus a buffer outside the door). Monsters never enter it.
const SHOP_MIN := Vector2(-5.6, -0.8)
const SHOP_MAX := Vector2(5.6, 8.6)
const SHOP_DOOR := Vector3(0, 2.2, -0.5)

class OrderItem:
	var kind: String ## "pizza", "sticks", or "soda"
	var toppings: Array[String] = [] ## pizza only

	func describe() -> String:
		match kind:
			"pizza": return "Pizza: " + " + ".join(PackedStringArray(toppings))
			"sticks": return "Mozzarella Sticks"
		return "Soda"


class Order:
	var items: Array[OrderItem] = [] ## what's still owed
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
var upgrade_levels := {} ## id -> levels bought
var _last_house: House
var _env_tween: Tween
var _cold_timer := 0.0


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
	hud.show_message("Welcome to Pizza Panic.\nCheck the order board, make the order, deliver it.", 6.0)
	var shot_dir := _arg("--shots=")
	if shot_dir != "":
		_run_shots(shot_dir)


func _process(delta: float) -> void:
	_tick_cold(delta)
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
	if _last_house == null:
		o.items.append(_random_item("pizza")) # first order is always just a pizza
	else:
		# 1-2 different things, never more than the player can carry.
		var kinds: Array[String] = []
		for i in randi_range(1, mini(2, player.slots.size())):
			var k := _weighted_kind()
			while k in kinds:
				k = _weighted_kind()
			kinds.append(k)
		for k in kinds:
			o.items.append(_random_item(k))
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
	_update_order_board()


func _weighted_kind() -> String:
	var total := 0.0
	for w: float in ITEM_WEIGHTS.values():
		total += w
	var roll := randf() * total
	for k: String in ITEM_WEIGHTS:
		roll -= ITEM_WEIGHTS[k]
		if roll <= 0.0:
			return k
	return "pizza"


func _random_item(kind: String) -> OrderItem:
	var item := OrderItem.new()
	item.kind = kind
	if kind == "pizza":
		var names: Array = Pizza.TOPPINGS.keys()
		names.shuffle()
		for i in randi_range(1, 2):
			item.toppings.append(names[i])
	return item


func _update_order_board() -> void:
	if order == null:
		order_board.text = "No orders right now."
		return
	var lines := PackedStringArray(["ORDER UP!"])
	for item in order.items:
		lines.append(item.describe())
	lines.append("Deliver to " + order.house.address)
	order_board.text = "\n".join(lines)


## The inventory thing that would fill this order item, or null.
func _find_in_inventory(item: OrderItem, p: Player) -> Variant:
	for thing in p.slots:
		if item.kind == "pizza" and thing is Pizza and thing.stage == Pizza.Stage.BOXED:
			return thing
		if thing is Throwable and thing.kind == item.kind and not thing.is_frozen():
			return thing
	return null


func is_order_house(house: House) -> bool:
	return order != null and order.house == house


func door_prompt(house: House, p: Player) -> String:
	if is_order_house(house):
		for item in order.items:
			if _find_in_inventory(item, p) != null:
				return "[E] Deliver to %s" % house.address
	return "[E] Knock"


## Hands over every ordered thing you're carrying. Partial deliveries are fine;
## the order stays open until everything has arrived.
func try_deliver(house: House, p: Player) -> void:
	if order == null or order.house != house:
		hud.show_message("Nobody here ordered anything.", 2.0)
		return
	var lines := PackedStringArray()
	var total := 0
	for item in order.items.duplicate():
		var thing: Variant = _find_in_inventory(item, p)
		if thing == null:
			continue
		var result := _score(item, thing)
		total += result[0]
		lines.append(result[1])
		p.take(thing)
		if thing is Throwable:
			thing.queue_free()
		order.items.erase(item)
	if lines.is_empty():
		var wanted := PackedStringArray()
		for item in order.items:
			wanted.append(item.describe() + (" (boxed)" if item.kind == "pizza" else ""))
		hud.show_message("They ordered:\n" + "\n".join(wanted), 3.0)
		return
	money += total
	lines.insert(0, "Delivered! +$%d" % total)
	if order.items.is_empty():
		house.set_active(false)
		_last_house = house
		order = null
		lines.append("Order complete. Head back to the shop.")
	else:
		var left := PackedStringArray()
		for item in order.items:
			left.append(item.describe())
		lines.append("Still waiting on: " + ", ".join(left))
	_update_order_board()
	hud.show_message("\n".join(lines), 6.0)


## [pay, summary line] for handing over `thing` to fill `item`.
func _score(item: OrderItem, thing: Variant) -> Array:
	match item.kind:
		"pizza":
			var pizza: Pizza = thing
			var correct := 0
			for t in item.toppings:
				if t in pizza.toppings:
					correct += 1
			var missing := item.toppings.size() - correct
			var extra := pizza.toppings.size() - correct
			var accuracy := clampf(1.0 - 0.35 * missing - 0.2 * extra, 0.1, 1.0)
			var pay := int(round(PAY.pizza * accuracy * pizza.bake_quality * pizza.condition / 100.0))
			var toppings := "toppings right" if missing == 0 and extra == 0 else "%d missing, %d extra" % [missing, extra]
			var line := "Pizza $%d: %s, %s, %d%% intact" % [pay, toppings, pizza.bake_label, int(pizza.condition)]
			if missing == 0 and extra == 0 and pizza.bake_label == "perfect" and pizza.condition >= 100.0:
				pay += PERFECT_TIP
				line += " (+$%d tip!)" % PERFECT_TIP
			return [pay, line]
		"sticks":
			var sticks: Throwable = thing
			var pay := int(round(PAY.sticks * sticks.fry_quality))
			return [pay, "Mozzarella Sticks $%d: %s" % [pay, sticks.fry_label]]
	return [int(PAY.soda), "Soda $%d" % int(PAY.soda)]


# --- Upgrades -----------------------------------------------------------------

func upgrade_level(id: String) -> int:
	return upgrade_levels.get(id, 0)


## Price of the next level, or -1 if maxed out.
func upgrade_cost(id: String) -> int:
	var costs: Array = UPGRADES[id].costs
	var level := upgrade_level(id)
	return costs[level] if level < costs.size() else -1


func buy_upgrade(id: String) -> void:
	var cost := upgrade_cost(id)
	if cost < 0:
		return
	if money < cost:
		hud.show_message("Need $%d more." % (cost - money), 2.0)
		return
	money -= cost
	var level := upgrade_level(id) + 1
	upgrade_levels[id] = level
	player.apply_upgrade(id, level)
	player.play_sfx(KACHING, 1.0, -4.0)
	hud.show_message("Bought %s!\n%s" % [UPGRADES[id].name, UPGRADES[id].effect], 2.5)


func _on_player_hit() -> void:
	var p := player.exposed_pizza()
	if p:
		_damage_pizza(p, HIT_DAMAGE, "They got the pizza!")


func _on_pizza_swung() -> void:
	if player.held:
		_damage_pizza(player.held, SWING_DAMAGE, "Pizza to the face!")


func _tick_cold(delta: float) -> void:
	var exposed: Array[Pizza] = []
	if not player.in_shop:
		for thing in player.slots:
			if thing is Pizza and thing.stage != Pizza.Stage.BOXED:
				exposed.append(thing)
	if exposed.is_empty():
		_cold_timer = 0.0
		return
	_cold_timer += delta
	if _cold_timer >= COLD_INTERVAL:
		_cold_timer -= COLD_INTERVAL
		for p in exposed:
			_damage_pizza(p, COLD_DAMAGE, "") # quiet: just the flash and hitmarker


## Damages a carried pizza with feedback: hitmarker, red flash, and a message if `what` is set.
func _damage_pizza(p: Pizza, amount: float, what: String) -> void:
	p.condition -= amount
	hud.hit_marker()
	player.play_sfx(HITMARKER_SFX, randf_range(0.95, 1.05), -6.0)
	hud.flash_slot(player.slots.find(p))
	if p.condition <= 0.0:
		player.take(p)
		hud.show_message("The pizza is destroyed!\nBack to the shop to make another.", 4.0)
		return
	player.refresh_held()
	if p == player.held:
		player.flash_held()
	if what != "":
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
		lines.append("DELIVER TO: " + order.house.address)
		for item in order.items:
			lines.append("- " + item.describe())
	else:
		lines.append("No order. Head back to the shop.")
	hud.order_label.text = "\n".join(lines)
	hud.set_slots(player.slots, player.active_slot)
	hud.money_label.text = "$%d" % money
	hud.set_stamina(player.stamina / player.stamina_max)

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
