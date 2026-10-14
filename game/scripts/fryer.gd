extends StaticBody3D
## Takes any frozen fried food from the freezer. Pull it at the ding. Faster than the oven, burns faster too.

## Fry timings per food: [golden from, golden until, burnt at] in seconds.
const FRY_TIMES := {
	"sticks": [5.0, 7.0, 10.0],
}
const DEFAULT_TIMES := [5.0, 7.0, 10.0]
const DING := preload("res://audio/ding.wav")
const PICKUP := preload("res://audio/pickup.wav")
const SIZZLE := preload("res://audio/fryer_sizzle.wav")

var _food: Throwable # what's in the oil, or null
var _t := 0.0
var _dinged := false
var _ding_player: AudioStreamPlayer3D
var _sizzle_player: AudioStreamPlayer3D

@onready var label: Label3D = $Status
@onready var glow: OmniLight3D = $Glow
@onready var basket: Node3D = $Basket


func _ready() -> void:
	_ding_player = AudioStreamPlayer3D.new()
	_ding_player.stream = DING
	_ding_player.volume_db = -4.0
	_ding_player.pitch_scale = 1.25 # a little higher than the oven so you can tell them apart
	add_child(_ding_player)
	var sizzle: AudioStreamWAV = SIZZLE.duplicate()
	sizzle.loop_mode = AudioStreamWAV.LOOP_FORWARD
	sizzle.loop_end = int(sizzle.get_length() * sizzle.mix_rate)
	_sizzle_player = AudioStreamPlayer3D.new()
	_sizzle_player.stream = sizzle
	_sizzle_player.volume_db = -12.0
	_sizzle_player.unit_size = 3.0
	add_child(_sizzle_player)
	basket.visible = false


func _process(delta: float) -> void:
	if _food == null:
		label.text = ""
		glow.light_energy = 0.0
		return
	_t += delta
	if _t >= _times()[0] and not _dinged:
		_dinged = true
		_ding_player.play()
	var s := _status()
	label.text = s[0]
	label.modulate = s[1]
	glow.light_energy = 1.0 + sin(_t * 9.0) * 0.25
	basket.position.y = 0.52 + sin(_t * 30.0) * 0.004 # bubbling


func get_prompt(p: Player) -> String:
	if _food == null:
		if p.held_item and p.held_item.is_frozen():
			return "[E] Fry " + p.held_item.item_name
		return "Fryer (needs something frozen)"
	return "[E] Pull the basket" if p.has_room() else "Fryer (inventory full)"


func interact(p: Player) -> void:
	if _food == null:
		if p.held_item and p.held_item.is_frozen():
			_food = p.held_item
			p.take(_food)
			_t = 0.0
			_dinged = false
			basket.visible = true
			_sizzle_player.play()
	elif p.has_room():
		_food.cook(_label(), _quality())
		p.give(_food)
		p.play_sfx(PICKUP, 0.8)
		_food = null
		basket.visible = false
		_sizzle_player.stop()


func _times() -> Array:
	return FRY_TIMES.get(_food.kind, DEFAULT_TIMES)


func _status() -> Array:
	var times := _times()
	if _t < times[0]:
		return ["Frying... %d%%" % int(_t / times[0] * 100.0), Color(1, 0.9, 0.6)]
	if _t < times[1]:
		return ["GOLDEN! Pull it!", Color(0.4, 1, 0.4)]
	if _t < times[2]:
		return ["Overdone...", Color(1, 0.6, 0.2)]
	return ["BURNT", Color(1, 0.2, 0.2)]


func _label() -> String:
	var times := _times()
	if _t < times[0]:
		return "undercooked"
	if _t < times[1]:
		return "golden"
	if _t < times[2]:
		return "overdone"
	return "burnt"


func _quality() -> float:
	var times := _times()
	if _t < times[0]:
		return lerpf(0.2, 0.75, _t / times[0])
	if _t < times[1]:
		return 1.0
	if _t < times[2]:
		return lerpf(1.0, 0.5, (_t - times[1]) / (times[2] - times[1]))
	return 0.2
