class_name DevTest
## Two-window dev harness. Run a host with `-- --test=host --port=7778 --shots=<dir>` (in the
## background) and a client with `-- --test=client --port=7778 --shots=<dir>`. Each prints "SHOT ..." lines and saves screenshots.
## Add checks for the feature in progress; delete them once verified (keep it at the basics).


static func run(world: World, role: String, dir: String) -> void:
	var tree := world.get_tree()
	if role == "host":
		await _host(world, tree, dir)
	else:
		await _client(world, tree, dir)
	tree.quit()


static func _host(world: World, tree: SceneTree, dir: String) -> void:
	if not await _wait_players(world, tree, 2):
		print("SHOT host: client never arrived")
		return
	print("SHOT host sees %d players" % world.players.get_child_count())
	# (no pending checks)
	await tree.create_timer(1.0).timeout
	print("SHOT host: can6 holder=%d (me=1, client=%d), my inventory=%s" % [can6.holder, oid, _names(me.inventory())])
	await _until(tree, func() -> bool: return other.active_slot == 1)
	await tree.create_timer(0.4).timeout
	var inv := other.inventory()
	print("SHOT host: client inventory=%s, active=%d, visible=%s" % [_names(inv), other.active_slot, inv.map(func(i): return i.visible if i else null)])
	await _capture(tree, dir, "host_sees_client_holding")
	var dropped: Item = inv[1]
	await _until(tree, func() -> bool: return dropped.holder == 0)
	await tree.create_timer(1.0).timeout
	print("SHOT host: dropped %s at %s, client at %s" % [dropped.name, _v(dropped.global_position), _v(other.global_position)])
	await _until(tree, func() -> bool: return can1.holder == 0)
	await tree.create_timer(2.0).timeout
	print("SHOT host: thrown can1 at %s, me at %s" % [_v(can1.global_position), _v(me.global_position)])
	await tree.create_timer(1.0).timeout


static func _client(world: World, tree: SceneTree, dir: String) -> void:
	if not await _wait_players(world, tree, 2):
		print("SHOT client: never saw the host")
		return
	print("SHOT client sees %d players" % world.players.get_child_count())
	# (no pending checks)
	await tree.create_timer(1.0).timeout
	print("SHOT client: can6 holder=%d, my inventory=%s" % [can6.holder, _names(me.inventory())])
	if me.inventory()[1] == null:
		can2.interact(me)
		await tree.create_timer(0.6).timeout
	me.select_slot(1)
	print("SHOT client: inventory=%s, holding %s" % [_names(me.inventory()), me.held_item().name])
	await tree.create_timer(1.5).timeout
	me.rotation.y = deg_to_rad(90.0) # face the host
	me.head.rotation.x = 0.0
	await tree.create_timer(0.3).timeout
	me.drop_held()
	await tree.create_timer(1.5).timeout
	me.select_slot(0)
	await tree.create_timer(0.3).timeout
	me.throw_held()
	await tree.create_timer(2.5).timeout
	print("SHOT client: thrown can1 at %s" % _v(can1.global_position))
	await tree.create_timer(1.0).timeout


# --- Helpers ---------------------------------------------------------------------

## Waits until `cond` is true (or ~10s pass).
static func _until(tree: SceneTree, cond: Callable) -> bool:
	for i in 200:
		if cond.call():
			return true
		await tree.create_timer(0.05).timeout
	print("SHOT (timed out waiting)")
	return false


static func _names(slots: Array) -> Array:
	return slots.map(func(i): return i.name if i else "-")


static func _wait_players(world: World, tree: SceneTree, count: int) -> bool:
	for i in 300:
		if world.players.get_child_count() >= count and world.local_player() != null:
			return true
		await tree.create_timer(0.05).timeout
	return false


## The first player that isn't this machine's.
static func _other(world: World) -> Player:
	for p: Player in world.players.get_children():
		if not p.is_local():
			return p
	return null


static func _pose(tree: SceneTree, p: Player, pos: Vector3, yaw: float, pitch := 0.0) -> void:
	p.global_position = pos
	p.velocity = Vector3.ZERO
	p.rotation.y = deg_to_rad(yaw)
	p.head.rotation.x = deg_to_rad(pitch)
	await tree.create_timer(0.8).timeout


static func _capture(tree: SceneTree, dir: String, name: String) -> void:
	if dir == "":
		return
	await RenderingServer.frame_post_draw
	tree.root.get_texture().get_image().save_png(dir.path_join(name + ".png"))


static func _v(v: Vector3) -> String:
	return "(%.1f, %.1f, %.1f)" % [v.x, v.y, v.z]
