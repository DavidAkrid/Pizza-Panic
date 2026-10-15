class_name World
extends Node3D
## The co-op world scene: menu, player spawning, and this machine's presentation
## (inside/outside mood, music, HUD). Game rules will live in a host-owned node (orders step).
##
## Command line (after "--"): --host | --join=<address> | --test=<host|client> --shots=<dir>

const PLAYER := preload("res://scenes/player.tscn")
const SHOP_DOOR := Vector3(0, 2.2, -0.5)

static var instance: World

var _next_slot := 0
var _env_tween: Tween

@onready var players: Node3D = $Players
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
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_enter_game)
	multiplayer.connection_failed.connect(_back_to_menu.bind("Couldn't connect."))
	multiplayer.server_disconnected.connect(_back_to_menu.bind("The host left."))
	# Every machine builds spawned players with the same function + data, so who-is-who,
	# color and starting spot are identical everywhere (see _make_player).
	$PlayerSpawner.spawn_function = _make_player
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


func _process(_delta: float) -> void:
	var me := local_player()
	if me == null:
		return
	hud.set_stamina(me.stamina / Player.STAMINA_MAX)
	var fwd := -me.global_transform.basis.z
	hud.compass.heading = atan2(fwd.x, -fwd.z)
	if me.in_shop:
		hud.compass.marker_bearing = NAN
	else:
		hud.compass.marker_bearing = Compass.bearing(me.global_position, SHOP_DOOR)
		hud.compass.marker_color = Color(1, 0.5, 0.3)
	var target = me.get_interact_target()
	hud.prompt_label.text = target.get_prompt(me) if target else ""


# --- Session -------------------------------------------------------------------

func host() -> void:
	if Net.host() != OK:
		status.text = "Couldn't host - is port %d already in use?" % Net.port
		return
	_enter_game()
	_spawn_player(1)
	status.text = ""


func join(address: String) -> void:
	if Net.join(address) != OK:
		status.text = "That address doesn't look right."
		return
	status.text = "Joining..."


func local_player() -> Player:
	return players.get_node_or_null(str(multiplayer.get_unique_id())) as Player


func player(id: int) -> Player:
	return players.get_node_or_null(str(id)) as Player


func _enter_game() -> void:
	menu.hide()
	hud.visible = true
	hud.order_label.text = "Co-op build in progress: no orders yet."
	hud.money_label.text = ""
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


func _on_peer_disconnected(id: int) -> void:
	if multiplayer.is_server():
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
