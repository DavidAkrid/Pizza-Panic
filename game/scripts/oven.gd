extends StaticBody3D
## Put a raw pizza in, pull it out at the right time.

const PERFECT_START := 8.0
const PERFECT_END := 11.0
const BURN_AT := 15.0

const DING := preload("res://audio/ding.wav")

var _pizza: Pizza
var _t := 0.0
var _dinged := false
var _ding_player: AudioStreamPlayer3D

@onready var label: Label3D = $Status
@onready var glow: OmniLight3D = $Glow


func _ready() -> void:
	_ding_player = AudioStreamPlayer3D.new()
	_ding_player.stream = DING
	_ding_player.volume_db = -4.0
	add_child(_ding_player)


func _process(delta: float) -> void:
	if _pizza == null:
		label.text = ""
		glow.light_energy = 0.0
		return
	_t += delta
	if _t >= PERFECT_START and not _dinged:
		_dinged = true
		_ding_player.play()
	var s := _status()
	label.text = s[0]
	label.modulate = s[1]
	glow.light_energy = 1.5 + sin(_t * 6.0) * 0.3


func get_prompt(p: Player) -> String:
	if _pizza == null:
		if p.held and p.held.stage == Pizza.Stage.RAW:
			return "[E] Bake pizza"
		return "Oven"
	return "[E] Take pizza out" if p.held == null else "Oven (hands full)"


func interact(p: Player) -> void:
	if _pizza == null:
		if p.held and p.held.stage == Pizza.Stage.RAW:
			_pizza = p.held
			_t = 0.0
			_dinged = false
			p.set_held(null)
	elif p.held == null:
		_pizza.stage = Pizza.Stage.BAKED
		_pizza.bake_quality = _quality()
		_pizza.bake_label = _label()
		p.set_held(_pizza)
		_pizza = null


func _status() -> Array:
	if _t < PERFECT_START:
		return ["Baking... %d%%" % int(_t / PERFECT_START * 100.0), Color(1, 0.9, 0.6)]
	if _t < PERFECT_END:
		return ["PERFECT! Pull it!", Color(0.4, 1, 0.4)]
	if _t < BURN_AT:
		return ["Overdone...", Color(1, 0.6, 0.2)]
	return ["BURNT", Color(1, 0.2, 0.2)]


func _label() -> String:
	if _t < PERFECT_START:
		return "undercooked"
	if _t < PERFECT_END:
		return "perfect"
	if _t < BURN_AT:
		return "overdone"
	return "burnt"


func _quality() -> float:
	if _t < PERFECT_START:
		return lerpf(0.2, 0.75, _t / PERFECT_START)
	if _t < PERFECT_END:
		return 1.0
	if _t < BURN_AT:
		return lerpf(1.0, 0.5, (_t - PERFECT_END) / (BURN_AT - PERFECT_END))
	return 0.2
