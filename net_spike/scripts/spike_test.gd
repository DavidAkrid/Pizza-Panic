class_name SpikeTest
## Scripted two-instance check. Run one window with `-- --test=host --shots=<dir>` and another
## with `-- --test=client --shots=<dir>`. Each prints "SHOT ..." lines and saves screenshots.


static func run(main: Node, role: String, dir: String) -> void:
	var tree := main.get_tree()
	if role == "host":
		await _host(main, tree, dir)
	else:
		await _client(main, tree, dir)
	tree.quit()


static func _host(main: Node, tree: SceneTree, dir: String) -> void:
	var me: NetPlayer = await _wait_for(main, tree, 1)
	me.global_position = Vector3(0, 0.1, 4.5)
	me.rotation.y = 0.0
	if not await _wait_players(main, tree, 2):
		print("SHOT host: client never arrived")
		return
	print("SHOT host sees %d players" % main.players.get_child_count())
	var can: SpikeCan = tree.get_nodes_in_group("cans")[0]
	# Watch the client's moves and the can, as the host sees them.
	await tree.create_timer(3.0).timeout
	var other := _other(main)
	print("SHOT host sees client at %s" % _v(other.global_position))
	print("SHOT host sees can holder = %d" % can.holder)
	await _capture(tree, dir, "host_view_client_holding")
	await tree.create_timer(3.0).timeout
	print("SHOT host sees can holder = %d, can at %s" % [can.holder, _v(can.global_position)])


static func _client(main: Node, tree: SceneTree, dir: String) -> void:
	var my_id := 0
	for i in 200:
		await tree.create_timer(0.05).timeout
		if main.multiplayer.has_multiplayer_peer() and main.multiplayer.get_unique_id() > 1:
			my_id = main.multiplayer.get_unique_id()
			break
	var me: NetPlayer = await _wait_for(main, tree, my_id)
	await _wait_players(main, tree, 2)
	print("SHOT client %d sees %d players" % [my_id, main.players.get_child_count()])
	# Walk up to the table and grab a can.
	me.global_position = Vector3(1.5, 0.1, 0.9)
	me.rotation.y = deg_to_rad(30.0)
	me.head.rotation.x = deg_to_rad(-30.0)
	await tree.create_timer(1.0).timeout
	var can: SpikeCan = tree.get_nodes_in_group("cans")[0]
	can.request_pickup.rpc_id(1)
	await tree.create_timer(1.0).timeout
	print("SHOT client at %s, holding can: %s" % [_v(me.global_position), can.holder == my_id])
	# Turn to face the host and capture what we see.
	me.rotation.y = deg_to_rad(170.0)
	me.head.rotation.x = 0.0
	await tree.create_timer(1.5).timeout
	await _capture(tree, dir, "client_view_host")
	# Throw it toward the host.
	me.try_throw()
	await tree.create_timer(2.0).timeout
	print("SHOT client sees can holder = %d, can at %s" % [can.holder, _v(can.global_position)])
	await tree.create_timer(1.0).timeout


static func _wait_for(main: Node, tree: SceneTree, id: int) -> NetPlayer:
	for i in 200:
		var p: NetPlayer = main.player(id)
		if p:
			return p
		await tree.create_timer(0.05).timeout
	return null


static func _wait_players(main: Node, tree: SceneTree, count: int) -> bool:
	for i in 200:
		if main.players.get_child_count() >= count:
			return true
		await tree.create_timer(0.05).timeout
	return false


static func _other(main: Node) -> NetPlayer:
	for p in main.players.get_children():
		if p.name != "1":
			return p
	return null


static func _capture(tree: SceneTree, dir: String, name: String) -> void:
	if dir == "":
		return
	await RenderingServer.frame_post_draw
	tree.root.get_texture().get_image().save_png(dir.path_join(name + ".png"))


static func _v(v: Vector3) -> String:
	return "(%.1f, %.1f, %.1f)" % [v.x, v.y, v.z]
