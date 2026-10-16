class_name GameState
extends Node
## Host-owned game rules: orders, the team's money, and deliveries.
## Its Sync node sends `money`, `orders`, `upgrades` and `clock` to everyone. Clients only READ them
## (screens, HUD, porch lights, chevrons, door prompts); every change happens on the host.
##
## Orders come in on the order terminal (pending), someone takes one (accepted: it shows on the
## kitchen screen, the house lights up), then it's delivered or the customer gives up.
## orders = [{"id", "house", "items": [{"kind", "toppings"}...] (what's still owed), "fee", "note",
##   "accepted", "ready", "deadline" (on `clock`; -1 = no rush), "time" (seconds it was given)}]
## Always reassign `orders`, never mutate it: the Sync only notices reassignment.

const PAY := {"pizza": 20.0, "sticks": 8.0, "soda": 3.0} # base pay per item before quality
const PERFECT_TIP := 10
const ITEM_WEIGHTS := {"pizza": 6.0, "sticks": 3.0, "soda": 2.0} # how often each shows up in orders
const MAX_ORDER_ITEMS := 2
const MAX_PENDING := 3 ## rows on the terminal
const MAX_ACCEPTED := 4 ## rows on the kitchen screen
const PENDING_TIME := 60.0 ## how long an order waits on the terminal before the caller hangs up
const ORDER_GAP := Vector2(25, 40) ## seconds between new orders (solo; more players = faster)
const DELIVERY_TIME := 100.0 ## base time to deliver once taken...
const DELIVERY_TIME_PER_M := 1.5 ## ...plus this per meter from the shop
const FEE_PER_M := 0.1 ## delivery fee: farther = pays more
const SPEED_TIP_MAX := 8 ## the faster the delivery, the better the odds of a big tip
const NOTE_CHANCE := 0.35
const NOTES := [
	"BABY IS SLEEPING. knock quietly",
	"extra olives or else",
	"please hurry, it's getting closer",
	"don't look in the windows",
	"if a man answers, do not give him the pizza",
	"knock 3 times. not 4. NEVER 4.",
	"I can hear you. hurry up.",
	"cut it into 9 slices. there are 9 of us.",
	"my last delivery guy never came back. no pressure",
	"bring a flashlight, our porch bulb is out",
	"hot. HOT. HOOOOT.",
	"cash is under the mat. don't count it.",
	"is it still night out there? just checking",
	"the dog is friendly. the other dog is not.",
]
## Everyone within this distance of the door when it opens hands over what they're carrying.
const DELIVERY_RANGE := 4.5
## Shop wall upgrades: personal, paid from team money. One price per level; effects live in
## Player.apply_upgrades.
const UPGRADES := {
	"shoes": {"name": "Running Shoes", "effect": "+10% move speed", "costs": [30, 60, 100]},
	"bag": {"name": "Bigger Bag", "effect": "+1 inventory slot", "costs": [50, 100, 150, 200]},
	"knuckles": {"name": "Brass Knuckles", "effect": "+30% punch power", "costs": [40, 80, 120]},
	"flashlight": {"name": "Better Flashlight", "effect": "brighter, wider, further", "costs": [25, 60]},
	"energy": {"name": "Energy Drink", "effect": "+30% stamina", "costs": [30, 60, 90]},
}
const KACHING := preload("res://audio/kaching.wav")

static var instance: GameState

var money := 0
var orders: Array = []:
	set(value):
		orders = value
		if is_node_ready():
			_show_orders()
## Seconds since the host started. Synced constantly; order deadlines are on this clock.
var clock := 0.0
## Each player's upgrade levels: {"<peer id>": {"shoes": 1, ...}}. Synced; every machine applies
## everyone's levels (so you see a friend's brighter flashlight). Reassign, never mutate.
var upgrades := {}:
	set(value):
		upgrades = value
		if is_node_ready():
			apply_all_upgrades()
var _next_id := 0
var _next_order_in := 0.0 # host: countdown to the next call


func _enter_tree() -> void:
	instance = self


func _ready() -> void:
	set_multiplayer_authority(1)
	_show_orders()


## Host: called when the game starts. The first call is always one pizza, next door, no rush.
func start() -> void:
	_add_order(true)
	_next_order_in = ORDER_GAP.x


func _process(delta: float) -> void:
	clock += delta # clients tick too, between syncs, so countdowns run smoothly
	if not multiplayer.is_server() or not multiplayer.has_multiplayer_peer():
		return
	_expire_orders()
	if pending().size() < MAX_PENDING:
		_next_order_in -= delta
		if _next_order_in <= 0.0:
			_add_order(false)
			var players := World.instance.players.get_child_count()
			_next_order_in = randf_range(ORDER_GAP.x, ORDER_GAP.y) / (0.7 + 0.3 * players)


# --- Orders ---------------------------------------------------------------------------

## Orders waiting on the terminal.
func pending() -> Array:
	return orders.filter(func(o: Dictionary) -> bool: return not o.accepted)


## Orders someone took: on the kitchen screen, houses lit.
func accepted() -> Array:
	return orders.filter(func(o: Dictionary) -> bool: return o.accepted)


## The taken order for this house, or {}.
func order_for(house: House) -> Dictionary:
	for o in orders:
		if o.accepted and o.house == house.address:
			return o
	return {}


func is_order_house(house: House) -> bool:
	return not order_for(house).is_empty()


## Seconds until this order's deadline (INF when there's no rush).
func time_left(o: Dictionary) -> float:
	return INF if o.deadline < 0.0 else o.deadline - clock


static func format_time(seconds: float) -> String:
	if seconds == INF:
		return ""
	var s := maxi(ceili(seconds), 0)
	return "%d:%02d" % [s / 60, s % 60]


## Everything on one line, for screens and the HUD.
static func describe_items(items: Array) -> String:
	var parts := PackedStringArray()
	for entry in items:
		parts.append(describe_entry(entry))
	return ", ".join(parts)


## What the order pays before quality: items at full marks + the delivery fee.
static func estimate_pay(o: Dictionary) -> int:
	var total: int = o.fee
	for entry in o.items:
		total += int(PAY[entry.kind])
	return total


## Meters from the shop door to the house (as the crow flies).
func distance_to(address: String) -> int:
	var h := find_house(address)
	return roundi(World.SHOP_DOOR.distance_to(h.marker_position())) if h else 0


## Anyone: take an order off the terminal.
@rpc("any_peer", "call_local", "reliable")
func request_accept(id: int) -> void:
	if not multiplayer.is_server() or not _sender_in_shop():
		return
	if accepted().size() >= MAX_ACCEPTED:
		_tell.rpc_id(_sender(), "The kitchen's full. Deliver something first!", false)
		return
	var all := orders.duplicate(true)
	for o in all:
		if o.id == id and not o.accepted:
			o.accepted = true
			o.time = DELIVERY_TIME + DELIVERY_TIME_PER_M * distance_to(o.house)
			o.deadline = clock + o.time
			orders = all
			announce.rpc("Order taken: %s" % o.house, 2.5)
			return


## Anyone: tick an order "ready to go" on the kitchen screen (or untick it).
@rpc("any_peer", "call_local", "reliable")
func request_toggle_ready(id: int) -> void:
	if not multiplayer.is_server() or not _sender_in_shop():
		return
	var all := orders.duplicate(true)
	for o in all:
		if o.id == id and o.accepted:
			o.ready = not o.ready
			orders = all
			return


## Host: ignored calls hang up quietly. Taken orders that run out hurt (rep penalty: Phase C).
func _expire_orders() -> void:
	var kept: Array = []
	var gave_up := PackedStringArray()
	for o in orders:
		if time_left(o) > 0.0:
			kept.append(o)
		elif o.accepted:
			gave_up.append(o.house)
	if kept.size() == orders.size():
		return
	orders = kept
	for house in gave_up:
		announce.rpc("%s got tired of waiting and cancelled." % house, 4.0)


## Human-readable line for one order entry.
static func describe_entry(entry: Dictionary) -> String:
	match entry.kind:
		"pizza":
			return "Pizza: " + " + ".join(PackedStringArray(entry.toppings))
		"sticks":
			return "Mozzarella Sticks"
	return "Soda"


## Host: a new call comes in on the terminal, from a house that isn't already waiting.
func _add_order(first: bool) -> void:
	var busy := orders.map(func(o: Dictionary) -> String: return o.house)
	var free := _hood().houses.filter(func(h: House) -> bool: return not h.address in busy)
	if free.is_empty():
		return
	var items: Array = []
	if first:
		items.append(_random_entry("pizza"))
	else:
		var kinds: Array[String] = []
		for i in randi_range(1, MAX_ORDER_ITEMS):
			var k := _weighted_kind()
			while k in kinds:
				k = _weighted_kind()
			kinds.append(k)
		for k in kinds:
			items.append(_random_entry(k))
	var house: House = _hood().houses[0] if first else free.pick_random()
	_next_id += 1
	var all := orders.duplicate(true)
	all.append({
		"id": _next_id,
		"house": house.address,
		"items": items,
		"fee": roundi(distance_to(house.address) * FEE_PER_M),
		"note": NOTES.pick_random() if not first and randf() < NOTE_CHANCE else "",
		"accepted": false,
		"ready": false,
		"deadline": -1.0 if first else clock + PENDING_TIME,
		"time": 0.0,
	})
	orders = all
	_order_arrived.rpc()


## Every machine: the terminal beeps.
@rpc("authority", "call_local", "reliable")
func _order_arrived() -> void:
	var terminal := World.instance.get_node_or_null("Shop/OrderTerminal") as OrderScreen
	if terminal:
		terminal.beep()


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


## Every machine: porch lights and chevrons follow the taken orders. (The screens redraw themselves.)
func _show_orders() -> void:
	if World.instance == null or _hood() == null:
		return
	for h in _hood().houses:
		h.set_active(is_order_house(h))


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
	var order := order_for(house)
	if not order.is_empty():
		for entry in order.items:
			for it in p.inventory():
				if it and matches(entry, it):
					return "[E] Deliver to %s" % house.address
	return "[E] Knock"


## Host: the customer has the door open. Takes what they ordered from everyone near the door.
func deliver(house: House, door_position: Vector3) -> void:
	var order := order_for(house)
	if order.is_empty():
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
	var all := orders.duplicate(true)
	var index := orders.find(order)
	if remaining.is_empty():
		# Delivery fee, plus a tip: random, but the faster you were the bigger it can be.
		var hurry := clampf(time_left(order) / order.time, 0.0, 1.0) if order.time > 0.0 else 1.0
		var tip := randi_range(0, roundi(SPEED_TIP_MAX * hurry))
		total += order.fee + tip
		lines.append("Delivery fee $%d%s" % [order.fee, ", speed tip $%d!" % tip if tip > 0 else ""])
		all.remove_at(index)
		lines.append("Order complete!")
	else:
		all[index].items = remaining
		lines.append("Still waiting on: " + describe_items(remaining))
	orders = all
	money += total
	lines.insert(0, "Delivered! +$%d" % total)
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


# --- Upgrades ------------------------------------------------------------------------

func upgrade_level(p: Player, id: String) -> int:
	if p == null:
		return 0
	return upgrades.get(str(p.name), {}).get(id, 0)


## Price of this player's next level, or -1 if maxed out.
func upgrade_cost(p: Player, id: String) -> int:
	var costs: Array = UPGRADES[id].costs
	var level := upgrade_level(p, id)
	return costs[level] if level < costs.size() else -1


## Host: team money pays, the level is the buyer's.
func buy_upgrade(p: Player, id: String) -> void:
	var cost := upgrade_cost(p, id)
	if cost < 0:
		return
	var buyer := p.name.to_int()
	if money < cost:
		_tell.rpc_id(buyer, "The team needs $%d more." % (cost - money), false)
		return
	money -= cost
	var all := upgrades.duplicate(true)
	var mine: Dictionary = all.get(str(p.name), {})
	mine[id] = mine.get(id, 0) + 1
	all[str(p.name)] = mine
	upgrades = all
	_tell.rpc_id(buyer, "Bought %s!%s%s" % [UPGRADES[id].name, "\n", UPGRADES[id].effect], true)


## Every machine: push the synced levels onto each player copy.
func apply_all_upgrades() -> void:
	if World.instance == null:
		return
	for p: Player in World.instance.players.get_children():
		p.apply_upgrades(upgrades.get(str(p.name), {}))


@rpc("authority", "call_local", "reliable")
func _tell(text: String, purchased: bool) -> void:
	World.instance.hud.show_message(text, 2.5)
	var me := World.instance.local_player()
	if purchased and me:
		me.play_sfx(KACHING, 1.0, -4.0)


## A message on everyone's screen.
@rpc("authority", "call_local", "reliable")
func announce(text: String, duration: float) -> void:
	World.instance.hud.show_message(text, duration)


## Host, inside an RPC: who sent it (the host calling itself reports 0).
func _sender() -> int:
	var id := multiplayer.get_remote_sender_id()
	return id if id != 0 else 1


## Host, inside an RPC: the screens are in the shop, so the sender has to be too.
func _sender_in_shop() -> bool:
	var p := World.instance.player(_sender())
	return p != null and World.is_in_shop(p.global_position)


func _hood() -> Neighborhood:
	return World.instance.get_node_or_null("Neighborhood") as Neighborhood


func find_house(address: String) -> House:
	for h in _hood().houses:
		if h.address == address:
			return h
	return null
