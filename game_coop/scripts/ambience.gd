class_name Ambience
extends Node
## Placeholder procedural audio until real music exists:
## a warm chord pad in the shop, a low drone + wind outside, a heartbeat while something chases you.

const RATE := 22050.0
const CHORD_LENGTH := 4.0
const CHORDS := [
	[220.0, 277.18, 329.63, 415.30], # Amaj7
	[185.0, 220.0, 277.18, 329.63], # F#m7
	[146.83, 220.0, 261.63, 329.63], # Dmaj9-ish
	[164.81, 207.65, 246.94, 329.63], # E
]

var inside := true
var chasing := false
var dread := false ## deep night: the outside drone turns sour and rumbles
var _shop_mix := 1.0
var _out_mix := 0.0
var _tension := 0.0
var _dread := 0.0
var _time := 0.0
var _brown := 0.0
var _playback: AudioStreamGeneratorPlayback


func _ready() -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = RATE
	gen.buffer_length = 0.25
	var player := AudioStreamPlayer.new()
	player.stream = gen
	player.volume_db = -6.0
	add_child(player)
	player.play()
	_playback = player.get_stream_playback()


func _process(delta: float) -> void:
	_shop_mix = move_toward(_shop_mix, 1.0 if inside else 0.0, delta / 1.5)
	_out_mix = move_toward(_out_mix, 0.0 if inside else 1.0, delta / 1.5)
	_tension = move_toward(_tension, 1.0 if chasing else 0.0, delta / 2.0)
	_dread = move_toward(_dread, 1.0 if dread else 0.0, delta / 4.0)
	_fill()


func _fill() -> void:
	var step := 1.0 / RATE
	for i in _playback.get_frames_available():
		var t := _time
		var s := 0.0
		if _shop_mix > 0.001:
			var chord: Array = CHORDS[int(t / CHORD_LENGTH) % CHORDS.size()]
			var local := fmod(t, CHORD_LENGTH)
			var env := minf(local * 1.5, 1.0) * minf((CHORD_LENGTH - local) * 1.5, 1.0)
			var pad := 0.0
			for f: float in chord:
				pad += sin(TAU * f * t) + 0.3 * sin(TAU * f * 2.0 * t)
			s += pad * 0.035 * env * _shop_mix
		if _out_mix > 0.001:
			_brown = clampf(_brown * 0.998 + randf_range(-1.0, 1.0) * 0.03, -1.0, 1.0)
			var swell := 0.6 + 0.4 * sin(TAU * t / 9.0)
			var drone := sin(TAU * 55.0 * t) * 0.2 + sin(TAU * 58.27 * t) * 0.1
			if _dread > 0.001: # a sour tritone and a slow sub rumble
				drone += (sin(TAU * 77.78 * t) * 0.12 + sin(TAU * 36.7 * t) * 0.25 * (0.5 + 0.5 * sin(TAU * t / 3.0))) * _dread
			s += (drone * swell + _brown * 0.4) * _out_mix
			if _tension > 0.001:
				var beat := fmod(t, 0.75)
				var thump := exp(-beat * 30.0) * sin(TAU * 48.0 * beat)
				if beat > 0.2:
					thump += exp(-(beat - 0.2) * 30.0) * sin(TAU * 44.0 * (beat - 0.2)) * 0.7
				s += thump * 0.8 * _tension * _out_mix
		_playback.push_frame(Vector2(s, s))
		_time += step
