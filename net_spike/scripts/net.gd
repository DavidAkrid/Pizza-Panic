extends Node3D
## Networking test: host or join over ENet, one player per connected peer.
##
## Authority model (the thing this spike is proving out):
##   - The HOST owns the world: physics props and who is holding what.
##   - Each PLAYER owns their own movement; their MultiplayerSynchronizer sends it to everyone.
##   - Clients change world state by asking the host via RPC; the host decides and syncs the result.
##
## Command line (after "--"):  --host   |   --join=<ip>   |   --test=<host|client> --shots=<dir>

const PORT := 7777
const MAX_PLAYERS := 4
const PLAYER := preload("res://scenes/player.tscn")

var _next_slot := 0

@onready var players: Node3D = $Players
@onready var lobby: Control = $UI/Lobby
@onready var ip_field: LineEdit = $UI/Lobby/IP
@onready var status: Label = $UI/Status


func _ready() -> void:
	$UI/Lobby/Host.pressed.connect(host)
	$UI/Lobby/Join.pressed.connect(func() -> void: join(ip_field.text))
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(func() -> void:
		status.text = "Connected as player %d" % multiplayer.get_unique_id())
	multiplayer.connection_failed.connect(func() -> void:
		status.text = "Couldn't connect."
		lobby.show())
	multiplayer.server_disconnected.connect(func() -> void:
		status.text = "Host left."
		lobby.show())

	for a in OS.get_cmdline_user_args():
		if a == "--host" or a == "--test=host":
			host()
		elif a.begins_with("--join="):
			join(a.trim_prefix("--join="))
		elif a == "--test=client":
			join("127.0.0.1")
	var test := _arg("--test=")
	if test != "":
		SpikeTest.run(self, test, _arg("--shots="))


func host() -> void:
	var peer := ENetMultiplayerPeer.new()
	if peer.create_server(PORT, MAX_PLAYERS) != OK:
		status.text = "Couldn't host - is port %d already in use?" % PORT
		return
	multiplayer.multiplayer_peer = peer
	lobby.hide()
	status.text = "Hosting on port %d. Friends join with your IP." % PORT
	_spawn_player(1)


func join(ip: String) -> void:
	if ip.strip_edges() == "":
		ip = "127.0.0.1"
	var peer := ENetMultiplayerPeer.new()
	if peer.create_client(ip, PORT) != OK:
		status.text = "Bad address."
		return
	multiplayer.multiplayer_peer = peer
	lobby.hide()
	status.text = "Joining %s..." % ip


func player(id: int) -> NetPlayer:
	return players.get_node_or_null(str(id)) as NetPlayer


func _on_peer_connected(id: int) -> void:
	if multiplayer.is_server():
		_spawn_player(id)


func _on_peer_disconnected(id: int) -> void:
	if not multiplayer.is_server():
		return
	for can in get_tree().get_nodes_in_group("cans"):
		if can.holder == id:
			can.drop_from(id) # don't let a disconnect take a can with it
	var p := player(id)
	if p:
		p.queue_free()


## Host only. The MultiplayerSpawner copies the new player to every client automatically.
func _spawn_player(id: int) -> void:
	var p: NetPlayer = PLAYER.instantiate()
	p.name = str(id)
	p.slot = _next_slot
	_next_slot += 1
	p.position = Vector3(randf_range(-2.0, 2.0), 0.1, 4.0)
	players.add_child(p, true)


func _arg(prefix: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(prefix):
			return a.trim_prefix(prefix)
	return ""
