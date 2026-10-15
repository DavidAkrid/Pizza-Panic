class_name GameState
extends Node
## Host-owned game rules: the current order, the team's money, and deliveries.
## Its Sync node sends `money` and `order` to everyone. Clients only READ them (HUD, order board,
## porch lights, chevrons, door prompts); every change happens on the host.
##
## order = {} when there's no order, else {"house": "<address>", "items": [{"kind": ..., "toppings": [...]}, ...]}
## (items = what's still owed). Always reassign `order`, never mutate it: the Sync only notices reassignment.

const PAY := {"pizza": 20.0, "sticks": 8.0, "soda": 3.0} # base pay per item before quality
const PERFECT_TIP := 10
const ITEM_WEIGHTS := {"pizza": 6.0, "sticks": 3.0, "soda": 2.0} # how often each shows up in orders
const MAX_ORDER_ITEMS := 2
## Everyone within this distance of the door when it opens hands over what they're carrying.
const DELIVERY_RANGE := 4.5

static var instance: GameState

var money := 0
var order := {}:
	set(value):
		order = value
		if is_node_ready():
			_show_order()
var _last_house := ""


func _enter_tree() -> void:
	instance = self


func _ready() -> void:
	set_multiplayer_authority(1)
	_show_order()


## Host: called when the game starts.
func start() -> void:
	_new_order(true)


func _process(_delta: float) -> void:
	if not multiplayer.is_server() or not multiplayer.has_multiplayer_peer():
		return
	# A new order comes in once somebody is back at the shop.
	if order.is_empty() and _anyone_in_shop():
		_new_order(false)
		announce.rpc("New order on the board!", 3.0)


# --- Orders ---------------------------------------------------------------------------

func has_order() -> bool:
	return not order.is_empty()


func order_house() -> House:
	return _house(order.get("house", ""))


func is_order_house(house: House) -> bool:
	return has_order() and order.house == house.address


## Human-readable line for one order entry.
static func describe_entry(entry: Dictionary) -> String:
	match entry.kind:
		"pizza":
			return "Pizza: " + " + ".join(PackedStringArray(entry.toppings))
		"sticks":
			return "Mozzarella Sticks"
	return "Soda"


func _new_order(first: bool) -> void:
	var items: Array = []
	if first:
		items.append(_random_entry("pizza")) # first order is always just a pizza, next door
	else:
		var kinds: Array[String] = []
		for i in randi_range(1, MAX_ORDER_ITEMS):
			var k := _weighted_kind()
			while k in kinds:
				k = _weighted_kind()
			kinds.append(k)
		for k in kinds:
			items.append(_random_entry(k))
	var houses := _hood().houses
	var house: House = houses[0] if first else houses.pick_random()
	while not first and house.address == _last_house:
		house = houses.pick_random()
	order = {"house": house.address, "items": items}


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


func _random_entry(kind: String) -> Dictionary:
	var entry := {"kind": kind, "toppings": []}
	if kind == "pizza":
		var names: Array = Pizza.TOPPINGS.keys()
		names.shuffle()
		entry.toppings = names.slice(0, randi_range(1, 2))
	return entry


## Every machine: porch lights, chevrons, and the kitchen order board follow the order.
func _show_order() -> void:
	var world := World.instance
	if world == null or _hood() == null:
		return
	for h in _hood().houses:
		h.set_active(is_order_house(h))
	var board: Label3D = world.get_node("Shop/OrderBoard/Text")
	if not has_order():
		board.text = "No orders right now."
		return
	var lines := PackedStringArray(["ORDER UP!"])
	for entry in order.items:
		lines.append(describe_entry(entry))
	lines.append("Deliver to " + order.house)
	board.text = "\n".join(lines)


# --- Delivery ---------------------------------------------------------------------------

## Does this item fill this order entry?
static func matches(entry: Dictionary, it: Item) -> bool:
	if it.kind != entry.kind:
		return false
	if it.kind == "pizza":
		return it.pizza().stage == Pizza.Stage.BOXED
	if it.kind == "sticks":
		return not it.is_frozen()
	return true


## Prompt for a house door, worked out locally.
func door_prompt(house: House, p: Player) -> String:
	if is_order_house(house):
		for entry in order.items:
			for it in p.inventory():
				if it and matches(entry, it):
					return "[E] Deliver to %s" % house.address
	return "[E] Knock"


## Host: the customer has the door open. Takes what they ordered from everyone near the door.
func deliver(house: House, door_position: Vector3) -> void:
	if not is_order_house(house):
		return
	var offered: Array[Item] = []
	for p: Player in World.instance.players.get_children():
		if p.global_position.distance_to(door_position) <= DELIVERY_RANGE:
			for it in p.inventory():
				if it:
					offered.append(it)
	var remaining: Array = order.items.duplicate(true)
	var lines := PackedStringArray()
	var total := 0
	for entry in order.items:
		for it in offered:
			if matches(entry, it):
				var result := _score(entry, it)
				total += result[0]
				lines.append(result[1])
				offered.erase(it)
				remaining.erase(entry)
				it.queue_free() # handed over: gone for everyone
				break
	if lines.is_empty():
		var wanted := PackedStringArray()
		for entry in order.items:
			wanted.append(describe_entry(entry) + (" (boxed)" if entry.kind == "pizza" else ""))
		announce.rpc("They ordered:\n" + "\n".join(wanted), 3.5)
		return
	money += total
	lines.insert(0, "Delivered! +$%d" % total)
	if remaining.is_empty():
		_last_house = house.address
		order = {}
		lines.append("Order complete. Head back to the shop.")
	else:
		order = {"house": order.house, "items": remaining}
		var left := PackedStringArray()
		for entry in remaining:
			left.append(describe_entry(entry))
		lines.append("Still waiting on: " + ", ".join(left))
	announce.rpc("\n".join(lines), 6.0)


## [pay, summary line] for handing over `it` to fill `entry`.
func _score(entry: Dictionary, it: Item) -> Array:
	match entry.kind:
		"pizza":
			var pizza := it.pizza()
			var correct := 0
			for t in entry.toppings:
				if t in pizza.toppings:
					correct += 1
			var missing: int = entry.toppings.size() - correct
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
			var pay := int(round(PAY.sticks * float(it.state.get("fry_quality", 0.2))))
			return [pay, "Mozzarella Sticks $%d: %s" % [pay, it.state.get("fry", "?")]]
	return [int(PAY.soda), "Soda $%d" % int(PAY.soda)]


## A message on everyone's screen.
@rpc("authority", "call_local", "reliable")
func announce(text: String, duration: float) -> void:
	World.instance.hud.show_message(text, duration)


func _anyone_in_shop() -> bool:
	for p: Player in World.instance.players.get_children():
		if World.is_in_shop(p.global_position):
			return true
	return false


func _hood() -> Neighborhood:
	return World.instance.get_node_or_null("Neighborhood") as Neighborhood


func _house(address: String) -> House:
	for h in _hood().houses:
		if h.address == address:
			return h
	return null
