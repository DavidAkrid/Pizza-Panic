extends StaticBody3D
## Simple kitchen station: dough, a topping bin, the box stack, the trash, the soda cooler, or a freezer.

enum Kind { DOUGH, TOPPING, BOX, TRASH, SODA, FREEZER }

const PICKUP := preload("res://audio/pickup.wav")
const SODA_CAN := preload("res://scenes/soda_can.tscn")

@export var kind: Kind = Kind.DOUGH
@export var topping := ""
@export var food := "sticks" ## freezer: which frozen food it hands out


func get_prompt(p: Player) -> String:
	match kind:
		Kind.DOUGH:
			return "[E] Grab dough" if p.has_room() else "Dough (inventory full)"
		Kind.TOPPING:
			if p.held and p.held.stage == Pizza.Stage.RAW:
				if topping in p.held.toppings:
					return "%s (already on)" % topping
				return "[E] Add %s" % topping
			return topping
		Kind.BOX:
			if p.held and p.held.stage == Pizza.Stage.BAKED:
				return "[E] Box it"
			return "Pizza boxes"
		Kind.TRASH:
			return "Trash" if p.hands_free() else "[E] Toss it"
		Kind.SODA:
			return "[E] Grab a soda" if p.has_room() else "Soda (inventory full)"
		Kind.FREEZER:
			return "[E] Grab frozen food" if p.has_room() else "Freezer (inventory full)"
	return ""


func interact(p: Player) -> void:
	match kind:
		Kind.DOUGH:
			if p.give(Pizza.new()):
				p.play_sfx(PICKUP, 0.85)
		Kind.TOPPING:
			if p.held and p.held.stage == Pizza.Stage.RAW and topping not in p.held.toppings:
				p.held.toppings.append(topping)
				p.refresh_held()
				p.play_sfx(PICKUP, randf_range(0.95, 1.15))
		Kind.BOX:
			if p.held and p.held.stage == Pizza.Stage.BAKED:
				p.held.stage = Pizza.Stage.BOXED
				p.refresh_held()
		Kind.TRASH:
			p.discard_held()
		Kind.SODA:
			if p.has_room():
				p.give(SODA_CAN.instantiate())
				p.play_sfx(PICKUP, 1.2)
		Kind.FREEZER:
			if p.has_room():
				p.give(Throwable.make_frozen(food))
				p.play_sfx(PICKUP, 0.7)
