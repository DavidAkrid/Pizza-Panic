extends StationBase
## The oven or the fryer. The host owns what's inside; every machine runs its own countdown from
## when it went in, so everyone sees the same status, hears the hum/sizzle and the ding.

@export_enum("oven", "fryer") var mode := "oven"

## [ready from, ready until, burnt at] in seconds.
const TIMES := {"oven": [8.0, 11.0, 15.0], "fryer": [5.0, 7.0, 10.0]}
const READY_WORD := {"oven": "perfect", "fryer": "golden"}
const DING := preload("res://audio/ding.wav")
const LOOPS := {"oven": preload("res://audio/oven_hum.wav"), "fryer": preload("res://audio/fryer_sizzle.wav")}

var _item_name := "" # what's cooking (synced by _sync), "" = empty
var _t := 0.0 # seconds cooking, counted on every machine
var _dinged := false
var _loop: AudioStreamPlayer3D
var _ding: AudioStreamPlayer3D

@onready var label: Label3D = $Status
@onready var glow: OmniLight3D = $Glow
@onready var basket: Node3D = get_node_or_null("Basket")


func _ready() -> void:
	add_to_group("cook_stations")
	_ding = AudioStreamPlayer3D.new()
	_ding.stream = DING
	_ding.volume_db = -4.0
	_ding.pitch_scale = 1.25 if mode == "fryer" else 1.0 # tell them apart by ear
	add_child(_ding)
	var loop: AudioStreamWAV = LOOPS[mode].duplicate()
	loop.loop_mode = AudioStreamWAV.LOOP_FORWARD
	loop.loop_end = int(loop.get_length() * loop.mix_rate)
	_loop = AudioStreamPlayer3D.new()
	_loop.stream = loop
	_loop.volume_db = -12.0 if mode == "fryer" else -14.0
	_loop.unit_size = 3.0
	add_child(_loop)
	if basket:
		basket.visible = false


func _process(delta: float) -> void:
	if _item_name == "":
		label.text = ""
		glow.light_energy = 0.0
		return
	_t += delta
	var times: Array = TIMES[mode]
	if _t >= times[0] and not _dinged:
		_dinged = true
		_ding.play()
	var s := _status()
	label.text = s[0]
	label.modulate = s[1]
	glow.light_energy = 1.2 + sin(_t * 7.0) * 0.3
	if basket:
		basket.position.y = 0.52 + sin(_t * 30.0) * 0.004 # bubbling


func get_prompt(p: Player) -> String:
	var held := p.held_item()
	if _item_name == "":
		if _accepts(held):
			return "[E] Bake pizza" if mode == "oven" else "[E] Fry %s" % held.describe().trim_prefix("Frozen ")
		return "Oven" if mode == "oven" else "Fryer (needs something frozen)"
	if not p.has_room():
		return "%s (inventory full)" % ("Oven" if mode == "oven" else "Fryer")
	return "[E] Take pizza out" if mode == "oven" else "[E] Pull the basket"


func _accepts(item: Item) -> bool:
	if item == null:
		return false
	if mode == "oven":
		return item.kind == "pizza" and item.pizza().stage == Pizza.Stage.RAW
	return item.is_frozen()


func _use(p: Player, held: Item, slot: int) -> void:
	if _item_name == "":
		if _accepts(held):
			held.stash_in_station()
			_sync.rpc(held.name, 0.0)
		return
	var it: Item = World.instance.items.get_node_or_null(_item_name)
	if it == null:
		_sync.rpc("", 0.0)
		return
	if not p.has_room():
		return
	var word := _result_word()
	if mode == "oven":
		it.set_state({"stage": Pizza.Stage.BAKED, "bake_label": word, "bake_quality": _quality()})
	else:
		it.set_state({"fry": word, "fry_quality": _quality()})
	it.give_to(p, slot)
	play_sound.rpc(PICKUP.resource_path, 0.8)
	_sync.rpc("", 0.0)


## Host -> everyone: what's inside now and how long it's been cooking.
@rpc("authority", "call_local", "reliable")
func _sync(item_name: String, elapsed: float) -> void:
	_item_name = item_name
	_t = elapsed
	_dinged = elapsed >= TIMES[mode][0]
	if item_name == "":
		_loop.stop()
	elif not _loop.playing:
		_loop.play()
	if basket:
		basket.visible = item_name != ""


## Host only: bring a player who just joined up to date.
func resync_to(peer_id: int) -> void:
	_sync.rpc_id(peer_id, _item_name, _t)


func _status() -> Array:
	var times: Array = TIMES[mode]
	if _t < times[0]:
		return ["%s... %d%%" % ["Baking" if mode == "oven" else "Frying", int(_t / times[0] * 100.0)], Color(1, 0.9, 0.6)]
	if _t < times[1]:
		return ["%s! Pull it!" % READY_WORD[mode].to_upper(), Color(0.4, 1, 0.4)]
	if _t < times[2]:
		return ["Overdone...", Color(1, 0.6, 0.2)]
	return ["BURNT", Color(1, 0.2, 0.2)]


func _result_word() -> String:
	var times: Array = TIMES[mode]
	if _t < times[0]:
		return "undercooked"
	if _t < times[1]:
		return READY_WORD[mode]
	if _t < times[2]:
		return "overdone"
	return "burnt"


func _quality() -> float:
	var times: Array = TIMES[mode]
	if _t < times[0]:
		return lerpf(0.2, 0.75, _t / times[0])
	if _t < times[1]:
		return 1.0
	if _t < times[2]:
		return lerpf(1.0, 0.5, (_t - times[1]) / (times[2] - times[1]))
	return 0.2
