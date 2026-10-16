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
const HOSPITAL_BILL := 25

static var instance: World

var _in_game := false
var _next_item := 0
var _cold_timer := 0.0
var freeze_monsters := false # dev tests: hold monsters still
var _env_tween: Tween
var _sky_tween: Tween
var _inside := true
var _phase := -1 # the night phase this machine is showing (-1 = not shown yet)

@onready var players: Node3D = $Players
@onready var items: Node3D = $Items
@onready var hud: Hud = $Hud
@onready var ambience: Ambience = $Ambience
@onready var world_env: WorldEnvironment = $WorldEnvironment
@onready var menu: CanvasLayer = $Menu
@onready var status: Label = $Menu/Status
@onready var address_field: LineEdit = $Menu/Panel/Box/Address
@onready var name_field: LineEdit = $Menu/Panel/Box/Name


func _enter_tree() -> void:
	instance = self


func _ready() -> void:
	$Menu/Panel/Box/Host.pressed.connect(host)
	$Menu/Panel/Box/NewTown.pressed.connect(host.bind(true))
	$Menu/Panel/Box/Join.pressed.connect(func() -> void: join(address_field.text))
	name_field.text = SaveGame.player_name()
	name_field.text_changed.connect(func(t: String) -> void: SaveGame.set_player_name(SaveGame.clean_name(t)))
	var town := SaveGame.summary()
	$Menu/Panel/Box/Host.text = "Continue town (%s)" % town if town != "" else "Host game"
	$Menu/Panel/Box/NewTown.visible = town != ""
	$Menu/Panel/Box/Quit.pressed.connect(get_tree().quit)
	$Menu/Pause/Box/Resume.pressed.connect(_set_paused.bind(false))
	$Menu/Pause/Box/Leave.pressed.connect(_back_to_menu.bind("You left the game."))
	$Menu/Pause/Box/QuitGame.pressed.connect(get_tree().quit)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_back_to_menu.bind("The host left."))
	# Every machine builds spawned players with the same function + data, so who-is-who,
	# color and starting spot are identical everywhere (see _make_player).
	$PlayerSpawner.spawn_function = _make_player
	$ItemSpawner.spawn_function = _make_item
	$MonsterSpawner.spawn_function = _make_monster
	$Shop/ShopArea.body_entered.connect(func(b: Node3D) -> void: _shop_contact(b, true))
	$Shop/ShopArea.body_exited.connect(func(b: Node3D) -> void: _shop_contact(b, false))
	hud.visible = false
	show_phase(NightCycle.instance.phase)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	var args := OS.get_cmdline_user_args()
	if _arg("--name=") != "":
		name_field.text = _arg("--name=")
	if "--test=host" in args and not "--keep-town" in args:
		SaveGame.delete_town() # tests start from a fresh (test-only) town unless told otherwise
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
	hud.set_health(me.health / Player.HEALTH_MAX)
	hud.set_down(_down_text(me))
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


## What the red "you're down" screen says ("" = you're fine).
func _down_text(me: Player) -> String:
	if not me.downed:
		return ""
	var wait := GameState.format_time(me.bleed_left)
	if players.get_child_count() <= 1:
		return "YOU'RE DOWN\nHeading for the stall in %s\nHold [E] to go now" % wait
	return "YOU'RE DOWN\nA friend can revive you (%s)\nHold [E] to give up" % wait


## Taken orders, team money and compass markers, from the host-owned GameState.
func _refresh_order_hud(me: Player) -> void:
	var game := GameState.instance
	hud.money_label.text = "$%d" % game.money
	var fwd := -me.global_transform.basis.z
	hud.compass.heading = atan2(fwd.x, -fwd.z)
	hud.compass.markers.clear()
	var lines := PackedStringArray()
	var taken := game.accepted()
	for o in taken:
		var left := game.time_left(o)
		lines.append("%s  %s%s" % [o.house, GameState.format_time(left), "  READY" if o.ready else ""])
		lines.append("  " + GameState.describe_items(o.items))
		var house := game.find_house(o.house)
		var hurry := left < OrderScreen.HURRY_TIME
		hud.compass.markers.append([Compass.bearing(me.global_position, house.marker_position()), Color(1, 0.35, 0.3) if hurry else Color(1, 0.85, 0.4)])
	for p: Player in players.get_children():
		if p.downed and p != me: # go get them
			hud.compass.markers.append([Compass.bearing(me.global_position, p.global_position), Color(1, 0.15, 0.15)])
	if taken.is_empty():
		lines.append("New orders on the terminal!" if not game.pending().is_empty() else "No orders yet.")
		if not me.in_shop:
			hud.compass.markers.append([Compass.bearing(me.global_position, SHOP_DOOR), Color(1, 0.5, 0.3)])
	hud.order_label.text = "\n".join(lines)
	_refresh_night_hud(me)


## Top right, under the money: the night, the time, and what the phase wants from you.
func _refresh_night_hud(me: Player) -> void:
	var night := NightCycle.instance
	var time := NightCycle.format_hour(night.hour()) if night.phase != NightCycle.Phase.TIME_SKIP else "..."
	var line := "NIGHT %d   %s" % [night.night, time]
	var color := Color(0.85, 0.85, 0.9)
	match night.phase:
		NightCycle.Phase.LAST_CALL:
			line += "\nLAST CALL - get back to the shop!"
			color = Color(1, 0.4, 0.3)
		NightCycle.Phase.DEEP_NIGHT:
			var mine := me.name.to_int() in night.clocked_in
			line += "\nDEEP NIGHT - %s (%d/%d)" % ["clocked in" if mine else "clock in to end the night", night.clocked_in.size(), night.crew_size()]
			color = Color(1, 0.3, 0.25)
		NightCycle.Phase.TIME_SKIP:
			line += "\nEveryone's clocked in. See you tomorrow night."
	hud.night_label.text = line
	hud.night_label.modulate = color
	var target = me.get_interact_target()
	hud.prompt_label.text = target.get_prompt(me) if target else ""


# --- Session -------------------------------------------------------------------

## Continues the saved town if there is one, unless `fresh` (the "New town" button).
func host(fresh := false) -> void:
	if Net.host() != OK:
		status.text = "Couldn't host - is port %d already in use?" % Net.port
		return
	_enter_game()
	GameState.instance.start({} if fresh else SaveGame.load_town())
	NightCycle.instance.start()
	_spawn_player(1, _my_name())
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


func _on_connection_failed() -> void:
	Net.leave()
	status.text = "Couldn't connect. The game may be full (%d players max), or the address is wrong." % Net.MAX_PLAYERS
	print("Connection failed")


## Leaving (or losing the host) resets everything by reloading the scene.
func _back_to_menu(reason: String) -> void:
	Net.leave()
	get_tree().reload_current_scene()
	print("Back to menu: ", reason)


func _on_peer_connected(id: int) -> void:
	if multiplayer.is_server():
		for station in get_tree().get_nodes_in_group("cook_stations"):
			station.resync_to(id) # show them anything already in the oven/fryer


## Joiner: connected. Tell the host who we are; it spawns us (see _hello).
func _on_connected() -> void:
	_enter_game()
	_hello.rpc_id(1, _my_name())


## Host: a joiner introduced themselves. Spawn them; the save gives back their stuff by name.
@rpc("any_peer", "reliable")
func _hello(their_name: String) -> void:
	var id := multiplayer.get_remote_sender_id()
	if multiplayer.is_server() and player(id) == null:
		_spawn_player(id, SaveGame.clean_name(their_name))


func _on_peer_disconnected(id: int) -> void:
	if multiplayer.is_server():
		var p := player(id)
		if p:
			GameState.instance.player_left(p) # remember their upgrades for when they come back
		for it: Item in items.get_children():
			it.release_from(id) # don't let a leaving player take items with them
		if p:
			p.queue_free()


func _my_name() -> String:
	return SaveGame.clean_name(name_field.text)


## Sent by a downed player who bled out or gave up. Host: whatever they carried is gone, the team
## pays the hospital bill, and they step out of the bathroom stall.
@rpc("any_peer", "call_local", "reliable")
func request_respawn() -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		id = 1
	var p := player(id)
	if p == null:
		return
	var lost := 0
	for it: Item in items.get_children():
		if it.holder == id:
			it.queue_free()
			lost += 1
	var game := GameState.instance
	var bill := mini(HOSPITAL_BILL, game.money)
	game.money -= bill
	game.announce.rpc("*FLUSH* %s is back at the shop.%s%s" % [
		p.display_name(),
		"\nHospital bill: -$%d" % bill if bill > 0 else "",
		"\nEverything they carried is gone." if lost > 0 else ""], 4.0)
	var stall: BathroomStall = $Shop/Stall
	stall.play_respawn.rpc()
	p.respawn_at.rpc_id(id, stall.spawn_position(), stall.spawn_yaw())


## Host only. The PlayerSpawner runs _make_player with this data on every machine.
## Takes the lowest free player number, so someone rejoining gets their color/spot back.
## A blank name becomes "Host"/"Player N"; a name already in the game gets " (2)".
func _spawn_player(id: int, player_name: String) -> void:
	var taken: Array[int] = []
	var names: Array[String] = []
	for p: Player in players.get_children():
		if not p.is_queued_for_deletion():
			taken.append(p.slot)
			names.append(p.display_name())
	var slot := 0
	while slot in taken:
		slot += 1
	if player_name == "":
		player_name = "Host" if id == 1 else "Player %d" % (slot + 1)
	var unique := player_name
	var n := 2
	while unique in names:
		unique = "%s (%d)" % [player_name, n]
		n += 1
	var p: Player = $PlayerSpawner.spawn({"id": id, "slot": slot, "name": unique})
	GameState.instance.player_joined(p)


func _make_player(data: Dictionary) -> Player:
	var p: Player = PLAYER.instantiate()
	p.name = str(data.id)
	p.slot = data.slot
	p.player_name = data.get("name", "")
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
	var stall := pos.x > -6.3 and pos.x <= -5.6 and pos.z > 1.15 and pos.z < 2.75 # set into the left wall
	return stall or (pos.x > -5.6 and pos.x < 5.6 and pos.z > -0.8 and pos.z < 8.6)


# --- Inside vs. outside (this machine only) -------------------------------------

func _shop_contact(body: Node3D, entered: bool) -> void:
	# Every machine sees every player cross the doorway; only your own player sets the mood.
	if body is Player and body.is_local():
		body.in_shop = entered
		_set_inside(entered)


func _set_inside(inside: bool) -> void:
	_inside = inside
	ambience.inside = inside
	var env := world_env.environment
	if _env_tween:
		_env_tween.kill()
	_env_tween = create_tween().set_parallel()
	var outside_fog := 0.06 if _phase == NightCycle.Phase.DEEP_NIGHT else 0.045
	_env_tween.tween_property(env, "fog_density", 0.01 if inside else outside_fog, 1.2)
	_env_tween.tween_property(env, "volumetric_fog_density", 0.0 if inside else 0.025, 1.2)
	_env_tween.tween_property(env, "ambient_light_energy", 0.5 if inside else 0.2, 1.2)


# --- The night's look (every machine, from the synced phase) ----------------------------

## Sky/fog/moon colors per phase: [background, fog, ambient, moon].
const SKY_NORMAL := [Color(0.02, 0.025, 0.04), Color(0.03, 0.04, 0.06), Color(0.3, 0.35, 0.5), Color(0.55, 0.65, 0.9)]
const SKY_LAST_CALL := [Color(0.3, 0.05, 0.03), Color(0.32, 0.06, 0.03), Color(0.6, 0.3, 0.28), Color(1.0, 0.4, 0.3)]
const SKY_DEEP := [Color(0.2, 0.0, 0.01), Color(0.26, 0.02, 0.01), Color(0.55, 0.15, 0.15), Color(0.9, 0.15, 0.1)]
const NEON_BUZZ := preload("res://audio/neon_buzz.wav")


## Called whenever the synced phase changes (and once for players who join mid-night).
func show_phase(phase: NightCycle.Phase) -> void:
	var was := _phase
	_phase = phase
	var sky: Array = SKY_NORMAL
	var fade := 4.0
	match phase:
		NightCycle.Phase.LAST_CALL:
			sky = SKY_LAST_CALL
		NightCycle.Phase.DEEP_NIGHT:
			sky = SKY_DEEP
		NightCycle.Phase.TIME_SKIP:
			fade = NightCycle.SKIP_LENGTH # the red drains away while the clock spins
	if _sky_tween:
		_sky_tween.kill()
	var env := world_env.environment
	_sky_tween = create_tween().set_parallel()
	_sky_tween.tween_property(env, "background_color", sky[0], fade)
	_sky_tween.tween_property(env, "fog_light_color", sky[1], fade)
	_sky_tween.tween_property(env, "ambient_light_color", sky[2], fade)
	_sky_tween.tween_property($Moon, "light_color", sky[3], fade)
	ambience.dread = phase == NightCycle.Phase.DEEP_NIGHT
	_set_inside(_inside) # deep night fog is thicker
	# The neon sign: OPEN while taking calls, CLOSED from last call until the next night.
	var open := phase == NightCycle.Phase.NIGHT
	var was_open := was == NightCycle.Phase.NIGHT
	if open != was_open or was == -1:
		_set_sign(open, was != -1)


func _set_sign(open: bool, buzz: bool) -> void:
	var neon: Label3D = $Shop/OpenSign
	var glow: OmniLight3D = $Shop/OpenSign/Glow
	neon.text = "OPEN" if open else "CLOSED"
	var color := Color(1, 0.25, 0.45) if open else Color(0.3, 0.5, 1)
	neon.modulate = color
	glow.light_color = color
	if not buzz:
		return
	var a := AudioStreamPlayer3D.new()
	a.stream = NEON_BUZZ
	a.finished.connect(a.queue_free)
	neon.add_child(a)
	a.play()
	# Stutter on like a real neon tube.
	var tw := create_tween()
	for i in 5:
		tw.tween_callback(neon.set_visible.bind(false))
		tw.tween_interval(randf_range(0.04, 0.12))
		tw.tween_callback(neon.set_visible.bind(true))
		tw.tween_interval(randf_range(0.05, 0.15))


func _arg(prefix: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(prefix):
			return a.trim_prefix(prefix)
	return ""
