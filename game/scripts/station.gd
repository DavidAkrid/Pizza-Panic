extends StaticBody3D
## Simple kitchen station: dough, a topping bin, the box stack, or the trash.

enum Kind { DOUGH, TOPPING, BOX, TRASH }

const PICKUP := preload("res://audio/pickup.wav")

@export var kind: Kind = Kind.DOUGH
@export var topping := ""


func get_prompt(p: Player) -> String:
	match kind:
		Kind.DOUGH:
			return "[E] Grab dough" if p.held == null else "Dough (hands full)"
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
			return "[E] Toss it" if p.held else "Trash"
	return ""


func interact(p: Player) -> void:
	match kind:
		Kind.DOUGH:
			if p.held == null:
				p.set_held(Pizza.new())
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
			if p.held:
				p.set_held(null)
