class_name HouseDoor
extends StaticBody3D
## Front door of a house. Knock with a boxed pizza to deliver.

var house: House


func get_prompt(p: Player) -> String:
	return Game.instance.door_prompt(house, p)


func interact(p: Player) -> void:
	Game.instance.try_deliver(house, p)
