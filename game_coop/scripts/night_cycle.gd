class_name NightCycle
extends Node
## Host-owned shift clock: NIGHT -> LAST CALL -> DEEP NIGHT -> (everyone clocks in) -> TIME SKIP
## -> next NIGHT. Its Sync node sends `night`, `phase`, `phase_start`, `clocked_in` and `skip_from`
## to everyone; each machine shows the phase itself (sign, sky, wall clock, HUD) from those.
## One-off moments (bell, radio lines, sign buzz) are RPCs so late joiners don't replay them.
## Times are on GameState.clock.

enum Phase { NIGHT, LAST_CALL, DEEP_NIGHT, TIME_SKIP }

const NIGHT_LENGTH := 13.0 * 60.0 ## normal play
const LAST_CALL_LENGTH := 120.0 ## warning before the deep night
const SKIP_LENGTH := 6.0 ## the wall clock spinning to the next night
# The wall clock: NIGHT + LAST CALL run 8 PM -> 2 AM. In the deep night it creeps to 3 AM and stops.
const OPEN_HOUR := 20.0
const CLOSE_HOUR := 26.0
const STUCK_HOUR := 27.0
const DEEP_CREEP := 180.0 ## seconds from 2 AM to 3 AM

const BELL := preload("res://audio/bell.wav")
const PUNCH := preload("res://audio/punch_clock.wav")
const STATIC := preload("res://audio/radio_static.wav")

const RADIO_OPEN := [
	"Gooood evening, Monsterville! It's night %d, and the moon's still stuck. Order up!",
	"Night %d, folks. Still dark. Still hungry. The pizza place is OPEN.",
	"This is Monsterville radio on night %d. Lock your doors... but not too tight. Pizza's coming.",
	"Night %d! Weather: dark, with a chance of screaming. Pizza Panic is open for business.",
]
const RADIO_LAST_CALL := [
	"That's last call, Monsterville! Get indoors. The deep night's coming.",
	"Bell's ringing, folks. Two minutes. Whatever's out there is waking up.",
	"Last call! Delivery crew - wrap it up and get back to the shop!",
]
const RADIO_DEEP := [
	"It's the deep night. Doors locked, lights off. Pizza crew... you're on your own.",
	"Deep night, Monsterville. If someone orders now, they REALLY want that pizza.",
	"...the clock's stopped again. Stay inside. Clock in when you're ready.",
]

static var instance: NightCycle

var night := 1
var phase := Phase.NIGHT:
	set(value):
		phase = value
		if is_node_ready():
			_show_phase()
var phase_start := 0.0
## Peer ids of everyone who's punched in (deep night only). Reassign, never mutate.
var clocked_in: Array = []
var skip_from := STUCK_HOUR ## the wall clock spins forward from here during the time skip


func _enter_tree() -> void:
	instance = self


func _ready() -> void:
	set_multiplayer_authority(1)


## Host: the first night starts when the game does.
func start() -> void:
	_set_phase(Phase.NIGHT)
	_radio.rpc(RADIO_OPEN.pick_random() % night)


func elapsed() -> float:
	return GameState.instance.clock - phase_start


## 0 at opening, 1 at last call: how far into the night we are.
func progress() -> float:
	match phase:
		Phase.NIGHT:
			return clampf(elapsed() / NIGHT_LENGTH, 0.0, 1.0)
		Phase.TIME_SKIP:
			return 0.0
	return 1.0


## How mean the monsters are right now. Ramps through the night; later nights start meaner.
func danger() -> float:
	if phase == Phase.DEEP_NIGHT:
		return 1.5
	if phase == Phase.TIME_SKIP:
		return 0.0
	return clampf(progress() + 0.1 * (night - 1), 0.0, 1.0)


func is_open() -> bool:
	return phase == Phase.NIGHT


## The wall clock's time in hours (20 = 8 PM, 26 = 2 AM...).
func hour() -> float:
	match phase:
		Phase.NIGHT:
			return OPEN_HOUR + (CLOSE_HOUR - 0.5 - OPEN_HOUR) * progress()
		Phase.LAST_CALL:
			return CLOSE_HOUR - 0.5 + 0.5 * clampf(elapsed() / LAST_CALL_LENGTH, 0.0, 1.0)
		Phase.DEEP_NIGHT:
			return minf(CLOSE_HOUR + elapsed() / DEEP_CREEP, STUCK_HOUR)
	# Time skip: spin forward to 8 PM tomorrow.
	var t := clampf(elapsed() / SKIP_LENGTH, 0.0, 1.0)
	return lerpf(skip_from, OPEN_HOUR + 24.0, t * t * (3.0 - 2.0 * t))


static func format_hour(h: float) -> String:
	var minutes := int(h * 60.0) % (24 * 60)
	var h24 := minutes / 60
	var h12 := h24 % 12
	return "%d:%02d %s" % [12 if h12 == 0 else h12, minutes % 60, "AM" if h24 < 12 else "PM"]


func _process(_delta: float) -> void:
	if not multiplayer.is_server() or not multiplayer.has_multiplayer_peer():
		return
	match phase:
		Phase.NIGHT:
			if elapsed() >= NIGHT_LENGTH:
				_set_phase(Phase.LAST_CALL)
				GameState.instance.clear_pending()
				_bell.rpc()
				_radio.rpc(RADIO_LAST_CALL.pick_random())
		Phase.LAST_CALL:
			if elapsed() >= LAST_CALL_LENGTH:
				_set_phase(Phase.DEEP_NIGHT)
				_radio.rpc(RADIO_DEEP.pick_random())
		Phase.DEEP_NIGHT:
			_check_clocked_in()
		Phase.TIME_SKIP:
			if elapsed() >= SKIP_LENGTH:
				night += 1
				clocked_in = []
				_set_phase(Phase.NIGHT)
				GameState.instance.new_night()
				_radio.rpc(RADIO_OPEN.pick_random() % night)


func _set_phase(p: Phase) -> void:
	phase_start = GameState.instance.clock
	phase = p


# --- Punch clock -------------------------------------------------------------------------

## Players who count for the ready check (everyone connected).
func crew_size() -> int:
	return World.instance.players.get_child_count()


## Host: someone punched their card at the punch clock (it already checked they're in range).
func clock_in(p: Player) -> void:
	var id := p.name.to_int()
	if phase != Phase.DEEP_NIGHT or id in clocked_in:
		return
	var all := clocked_in.duplicate()
	all.append(id)
	clocked_in = all
	_punched.rpc(id)


## Host: anyone who leaves the shop (or the game) is clocked back out. Everyone in -> time skip.
func _check_clocked_in() -> void:
	var still: Array = clocked_in.filter(func(id: int) -> bool:
		var p := World.instance.player(id)
		return p != null and World.is_in_shop(p.global_position))
	if still.size() != clocked_in.size():
		clocked_in = still
	if clocked_in.size() > 0 and clocked_in.size() >= crew_size():
		skip_from = hour()
		GameState.instance.end_night()
		_set_phase(Phase.TIME_SKIP)


# --- What everyone sees and hears ------------------------------------------------------

## Every machine: steady-state looks for the phase (also runs for late joiners).
func _show_phase() -> void:
	if World.instance:
		World.instance.show_phase(phase)


@rpc("authority", "call_local", "reliable")
func _bell() -> void:
	_play(BELL, 0.0)


@rpc("authority", "call_local", "reliable")
func _radio(text: String) -> void:
	_play(STATIC, -8.0)
	World.instance.hud.show_message("RADIO: \"%s\"" % text, 7.0)


@rpc("authority", "call_local", "reliable")
func _punched(id: int) -> void:
	var clock := World.instance.get_node_or_null("Shop/PunchClock") as Node3D
	if clock:
		var a := AudioStreamPlayer3D.new()
		a.stream = PUNCH
		a.finished.connect(a.queue_free)
		clock.add_child(a)
		a.play()
	var me := World.instance.local_player()
	if me and me.name.to_int() == id:
		World.instance.hud.show_message("Clocked in. Waiting for the rest of the crew...", 3.0)


func _play(stream: AudioStream, volume_db: float) -> void:
	var a := AudioStreamPlayer.new()
	a.stream = stream
	a.volume_db = volume_db
	a.finished.connect(a.queue_free)
	add_child(a)
	a.play()
