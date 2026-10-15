class_name World
extends Node3D
## The co-op world scene: menu, player spawning, and this machine's presentation
## (inside/outside mood, music, HUD). Game rules will live in a host-owned node (orders step).
##
## Command line (after "--"): --host | --join=<address> | --test=<host|client> --shots=<dir>

const PLAYER := preload("res://scenes/player.tscn")
const ITEM := preload("res://scenes/item.tscn")
const SHAMBLER := preload("res://scenes/shambler.tscn")
const SHOP_DOOR := Vector3(0, 2.2, -0.5)
const COLD_DAMAGE := 1.0
const COLD_INTERVAL := 3.0

static var instance: World

var _next_slot := 0
var _in_game := false
var _next_item := 0
var _cold_timer := 0.0
var freeze_monsters := false # dev tests: hold monsters still
var _env_tween: Tween

@onready var players: Node3D = $Players
@onready var items: Node3D = $Items
@onready var hud: Hud = $Hud
@onready var ambience: Ambience = $Ambience
@onready var world_env: WorldEnvironment = $WorldEnvironment
@onready var menu: CanvasLayer = $Menu
@onready var status: Label = $Menu/Status
@onready var address_field: LineEdit = $Menu/Panel/Box/Address


func _enter_tree() -> void:
	instance = self


func _ready() -> void:
	$Menu/Panel/Box/Host.pressed.connect(host)
	$Menu/Panel/Box/Join.pressed.connect(func() -> void: join(address_field.text))
	$Menu/Panel/Box/Quit.pressed.connect(get_tree().quit)
	$Menu/Pause/Box/Resume.pressed.connect(_set_paused.bind(false))
	$Menu/Pause/Box/Leave.pressed.connect(_back_to_menu.bind("You left the game."))
	$Menu/Pause/Box/QuitGame.pressed.connect(get_tree().quit)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_enter_game)
	multiplayer.connection_failed.connect(_back_to_menu.bind("Couldn't connect."))
	multiplayer.server_disconnected.connect(_back_to_menu.bind("The host left."))
	# Every machine builds spawned players with the same function + data, so who-is-who,
	# color and starting spot are identical everywhere (see _make_player).
	$PlayerSpawner.spawn_function = _make_player
	$ItemSpawner.spawn_function = _make_item
	$MonsterSpawner.spawn_function = _make_monster
	$Shop/ShopArea.body_entered.connect(func(b: Node3D) -> void: _shop_contact(b, true))
	$Shop/ShopArea.body_exited.connect(func(b: Node3D) -> void: _shop_contact(b, false))
	hud.visible = false
	_set_inside(true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	var args := OS.get_cmdline_user_args()
	if "--host" in args or "--test=host" in args:
		host()
	elif "--test=client" in args:
		join("127.0.0.1")
	for a in args:
		if a.begins_with("--join="):
			join(a.trim_prefix("--join="))
	var test := _arg("--test=")
	if test != "":
		DevTest.run(self, test, _arg("--shots="))


func _process(delta: float) -> void:
	if multiplayer.is_server() and multiplayer.has_multiplayer_peer():
		_tick_cold_pizzas(delta)
	var me := local_player()
	if me == null:
		return
	hud.set_stamina(me.stamina / me.stamina_max)
	hud.set_slots(me.inventory(), me.active_slot)
	_refresh_order_hud(me)
	# Heartbeat only for whoever is actually being chased.
	var my_id := me.name.to_int()
	var hunted := false
	for m: Shambler in $Monsters.get_children():
		if m.target_id == my_id:
			hunted = true
			break
	ambience.chasing = hunted


## Order info, team money and the compass marker, from the host-owned GameState.
func _refresh_order_hud(me: Player) -> void:
	var game := GameState.instance
	hud.money_label.text = "$%d" % game.money
	var lines := PackedStringArray()
	if game.has_order():
		lines.append("DELIVER TO: " + game.order.house)
		for entry in game.order.items:
			lines.append("- " + GameState.describe_entry(entry))
	else:
		lines.append("No order. Head back to the shop.")
	hud.order_label.text = "\n".join(lines)
	var fwd := -me.global_transform.basis.z
	hud.compass.heading = atan2(fwd.x, -fwd.z)
	if game.has_order():
		hud.compass.marker_bearing = Compass.bearing(me.global_position, game.order_house().marker_position())
		hud.compass.marker_color = Color(1, 0.85, 0.4)
	elif not me.in_shop:
		hud.compass.marker_bearing = Compass.bearing(me.global_position, SHOP_DOOR)
		hud.compass.marker_color = Color(1, 0.5, 0.3)
	else:
		hud.compass.marker_bearing = NAN
	var target = me.get_interact_target()
	hud.prompt_label.text = target.get_prompt(me) if target else ""


# --- Session -------------------------------------------------------------------

func host() -> void:
	if Net.host() != OK:
		status.text = "Couldn't host - is port %d already in use?" % Net.port
		return
	_enter_game()
	_spawn_player(1)
	GameState.instance.start()
	_spawn_monsters.call_deferred()
	status.text = ""
	hud.show_message("Hosting! Friends join with:%s%s" % ["\n", _share_addresses()], 10.0)


func join(address: String) -> void:
	if Net.join(address) != OK:
		status.text = "That address doesn't look right."
		return
	status.text = "Joining..."


## Esc in game: the pause menu (the world keeps running - it's multiplayer).
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _in_game:
		_set_paused(not $Menu/Pause.visible)


func _set_paused(paused: bool) -> void:
	menu.visible = paused
	$Menu/Panel.visible = not paused
	$Menu/Pause.visible = paused
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if paused else Input.MOUSE_MODE_CAPTURED


## This PC's addresses a friend could type to join (home network, and Tailscale if running).
func _share_addresses() -> String:
	var found := PackedStringArray()
	for a in IP.get_local_addresses():
		if a.count(".") != 3 or a.begins_with("127.") or a.begins_with("169.254."):
			continue
		found.append(a + (" (Tailscale)" if a.begins_with("100.") else ""))
	return "   ".join(found) if not found.is_empty() else "your IP address"


func local_player() -> Player:
	if players == null: # asked before the world finished setting up
		return null
	return players.get_node_or_null(str(multiplayer.get_unique_id())) as Player


func player(id: int) -> Player:
	return players.get_node_or_null(str(id)) as Player


func _enter_game() -> void:
	_in_game = true
	menu.hide()
	hud.visible = true
	if not multiplayer.is_server():
		status.text = ""


## Leaving (or losing the host) resets everything by reloading the scene.
func _back_to_menu(reason: String) -> void:
	Net.leave()
	get_tree().reload_current_scene()
	print("Back to menu: ", reason)


func _on_peer_connected(id: int) -> void:
	if multiplayer.is_server():
		_spawn_player(id)
		for station in get_tree().get_nodes_in_group("cook_stations"):
			station.resync_to(id) # show them anything already in the oven/fryer


func _on_peer_disconnected(id: int) -> void:
	if multiplayer.is_server():
		for it: Item in items.get_children():
			it.release_from(id) # don't let a leaving player take items with them
		var p := player(id)
		if p:
			p.queue_free()


## Host only. The PlayerSpawner runs _make_player with this data on every machine.
func _spawn_player(id: int) -> void:
	$PlayerSpawner.spawn({"id": id, "slot": _next_slot})
	_next_slot += 1


func _make_player(data: Dictionary) -> Player:
	var p: Player = PLAYER.instantiate()
	p.name = str(data.id)
	p.slot = data.slot
	p.position = Vector3(-1.5 + (p.slot % 4) * 1.0, 0.05, 3.5)
	p.rotation.y = PI # face the counter
	return p


# --- Items --------------------------------------------------------------------------

## Host only. Creates an item on every machine. `info` carries kind-specific look data.
func spawn_item(kind: String, at: Vector3, info := {}) -> Item:
	_next_item += 1
	return $ItemSpawner.spawn({"name": "item_%d" % _next_item, "kind": kind, "pos": at, "info": info})


func _make_item(data: Dictionary) -> Item:
	var it: Item = ITEM.instantiate()
	it.name = data.name
	it.kind = data.kind
	it.spawn_info = data.info
	it.position = data.pos
	return it


# --- Monsters ---------------------------------------------------------------------------

## Host only. Monsters spawn once at their spawn points and roam for the whole session.
func _spawn_monsters() -> void:
	var hood := get_node("Neighborhood") as Neighborhood
	for i in hood.spawn_points.size():
		$MonsterSpawner.spawn({"name": "monster_%d" % i, "pos": hood.spawn_points[i]})


func _make_monster(data: Dictionary) -> Shambler:
	var m: Shambler = SHAMBLER.instantiate()
	m.name = data.name
	m.position = data.pos
	return m


## Host only: an unboxed pizza carried outside the shop goes cold, 1% every few seconds.
## (A nudge to box it before heading out.)
func _tick_cold_pizzas(delta: float) -> void:
	_cold_timer += delta
	if _cold_timer < COLD_INTERVAL:
		return
	_cold_timer -= COLD_INTERVAL
	for it: Item in items.get_children():
		if it.kind != "pizza" or it.holder <= 0 or it.pizza().stage == Pizza.Stage.BOXED:
			continue
		var p := player(it.holder)
		if p and not is_in_shop(p.global_position):
			it.damage_pizza(COLD_DAMAGE) # quiet: just the hitmarker and flash


## Shop footprint (plus a buffer outside the door). Used by the host, e.g. monsters never enter.
static func is_in_shop(pos: Vector3) -> bool:
	return pos.x > -5.6 and pos.x < 5.6 and pos.z > -0.8 and pos.z < 8.6


# --- Inside vs. outside (this machine only) -------------------------------------

func _shop_contact(body: Node3D, entered: bool) -> void:
	# Every machine sees every player cross the doorway; only your own player sets the mood.
	if body is Player and body.is_local():
		body.in_shop = entered
		_set_inside(entered)


func _set_inside(inside: bool) -> void:
	ambience.inside = inside
	var env := world_env.environment
	if _env_tween:
		_env_tween.kill()
	_env_tween = create_tween().set_parallel()
	_env_tween.tween_property(env, "fog_density", 0.01 if inside else 0.045, 1.2)
	_env_tween.tween_property(env, "volumetric_fog_density", 0.0 if inside else 0.025, 1.2)
	_env_tween.tween_property(env, "ambient_light_energy", 0.5 if inside else 0.2, 1.2)


func _arg(prefix: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(prefix):
			return a.trim_prefix(prefix)
	return ""
