extends Node
## How players connect. This is the ONLY file that knows about the transport.
##
## Today: direct ENet connections (the host's IP address + a port). Works on the same PC, the same
## network, or over Tailscale / port forwarding.
## Later: swap these functions to create a Steam peer (GodotSteam's SteamMultiplayerPeer + lobbies).
## Everything else in the game only talks to Godot's `multiplayer` API, so nothing else changes.

const DEFAULT_PORT := 7777
const MAX_PLAYERS := 4

## Overridable with `-- --port=<n>` (the dev tests use 7778 so they never clash with a real game).
var port := DEFAULT_PORT


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--port="):
			port = a.trim_prefix("--port=").to_int()


func host() -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	return OK


func join(address: String) -> Error:
	address = address.strip_edges()
	if address == "":
		address = "127.0.0.1"
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	return OK


func leave() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
