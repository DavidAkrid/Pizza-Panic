extends StationBase
## Simple kitchen stations: dough, topping bins, the box stack, the trash, the soda cooler, the freezer.

enum Kind { DOUGH, TOPPING, BOX, TRASH, SODA, FREEZER }

@export var kind: Kind = Kind.DOUGH
@export var topping := ""
@export var food := "sticks" ## freezer: which frozen food it hands out


func get_prompt(p: Player) -> String:
	var held := p.held_item()
	var pizza := held.pizza() if held else null
	match kind:
		Kind.DOUGH:
			return "[E] Grab dough" if p.has_room() else "Dough (inventory full)"
		Kind.TOPPING:
			if pizza and pizza.stage == Pizza.Stage.RAW:
				return "%s (already on)" % topping if topping in pizza.toppings else "[E] Add %s" % topping
			return topping
		Kind.BOX:
			return "[E] Box it" if pizza and pizza.stage == Pizza.Stage.BAKED else "Pizza boxes"
		Kind.TRASH:
			return "[E] Toss it" if held else "Trash"
		Kind.SODA:
			return "[E] Grab a soda" if p.has_room() else "Soda (inventory full)"
		Kind.FREEZER:
			return "[E] Grab frozen food" if p.has_room() else "Freezer (inventory full)"
	return ""


func _use(p: Player, held: Item, slot: int) -> void:
	var pizza := held.pizza() if held else null
	match kind:
		Kind.DOUGH:
			if p.has_room():
				World.instance.spawn_item("pizza", global_position + Vector3.UP).give_to(p, slot)
				play_sound.rpc(PICKUP.resource_path, 0.85)
		Kind.TOPPING:
			if pizza and pizza.stage == Pizza.Stage.RAW and topping not in pizza.toppings:
				var toppings := pizza.toppings.duplicate()
				toppings.append(topping)
				held.set_state({"toppings": toppings})
				play_sound.rpc(PICKUP.resource_path, randf_range(0.95, 1.15))
		Kind.BOX:
			if pizza and pizza.stage == Pizza.Stage.BAKED:
				held.set_state({"stage": Pizza.Stage.BOXED})
		Kind.TRASH:
			if held:
				held.queue_free() # the ItemSpawner removes it everywhere
		Kind.SODA:
			if p.has_room():
				World.instance.spawn_item("soda", global_position + Vector3.UP, {"color": randi() % 4}).give_to(p, slot)
				play_sound.rpc(PICKUP.resource_path, 1.2)
		Kind.FREEZER:
			if p.has_room():
				World.instance.spawn_item(food, global_position + Vector3.UP, {}).give_to(p, slot)
				play_sound.rpc(PICKUP.resource_path, 0.7)
