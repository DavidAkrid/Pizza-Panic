class_name OrderScreen
extends Node3D
## The shop's two order screens. Builds its own look; the screen faces -Z.
## TERMINAL (out front): calls come in here. Aim at one and press E to take it.
## KITCHEN (over the counter): taken orders with their countdowns. E ticks one "ready to go".
## Each row is its own collider, so the crosshair picks the order. Text is redrawn locally from
## the synced GameState.orders, so every machine shows the same thing.

enum Mode { TERMINAL, KITCHEN }

const BEEP := preload("res://audio/terminal_beep.wav")
const GREEN := Color(0.35, 1.0, 0.45)
const AMBER := Color(1.0, 0.8, 0.35)
const RED := Color(1.0, 0.35, 0.3)
const YELLOW := Color(1.0, 0.9, 0.3)
const WHITE := Color(0.95, 0.95, 0.9)
const GREY := Color(0.45, 0.5, 0.45)
const DIM := Color(0.68, 0.68, 0.65) ## kitchen rows you're not aiming at
const WARN_TIME := 120.0 ## countdowns turn yellow under this...
const HURRY_TIME := 45.0 ## ...and red under this
const TAKEN_SHOW_TIME := 0.6 ## a taken call stays on the terminal, greyed out, this long

@export var mode := Mode.TERMINAL

var _title: Label3D
var _rows: Array[Label3D] = []
var _timers: Array[Label3D] = [] ## kitchen only: each row's countdown, colored by time left
var _bodies: Array[Row] = []
var _audio: AudioStreamPlayer3D
var _redraw_t := 0.0
# Terminal: the call you just took, greyed out in its old row for a moment (this machine only).
var _taken := {}
var _taken_row := 0
var _taken_t := 0.0


## One clickable line on the screen.
class Row extends StaticBody3D:
	var screen: OrderScreen
	var index := 0

	func get_prompt(_p: Player) -> String:
		return screen.row_prompt(index)

	func interact(_p: Player) -> void:
		screen.row_pressed(index)


func _ready() -> void:
	if mode == Mode.TERMINAL:
		_build_terminal()
	else:
		_build_kitchen()
	_audio = AudioStreamPlayer3D.new()
	_audio.stream = BEEP
	_audio.position = Vector3(0, 1.4, 0) if mode == Mode.TERMINAL else Vector3.ZERO
	add_child(_audio)
	_redraw()


func beep() -> void:
	_audio.play()


func _process(delta: float) -> void:
	_taken_t -= delta
	_redraw_t -= delta
	if _redraw_t <= 0.0:
		_redraw_t = 0.1
		_redraw()


# --- Rows ---------------------------------------------------------------------------

## The orders in row order.
func _list() -> Array:
	var game := GameState.instance
	if game == null:
		return []
	if mode == Mode.KITCHEN:
		return game.accepted()
	var list := game.pending()
	if _taken_t > 0.0 and not list.any(func(o: Dictionary) -> bool: return o.id == _taken.id):
		list.insert(mini(_taken_row, list.size()), _taken) # keep it in place while it greys out
	return list


## The order shown on row `i`, or {}.
func _order_at(i: int) -> Dictionary:
	var list := _list()
	return list[i] if i < list.size() else {}


func _is_taken(o: Dictionary) -> bool:
	return _taken_t > 0.0 and not o.is_empty() and o.id == _taken.id


func row_prompt(i: int) -> String:
	var o := _order_at(i)
	if o.is_empty() or _is_taken(o):
		return ""
	if mode == Mode.KITCHEN:
		return "[E] Not ready yet" if o.ready else "[E] Mark ready to go"
	if GameState.instance.accepted().size() >= GameState.MAX_ACCEPTED:
		return "Kitchen's full - deliver something first"
	return "[E] Take order: %s ($%d)" % [o.house, GameState.estimate_pay(o)]


func row_pressed(i: int) -> void:
	var o := _order_at(i)
	if o.is_empty() or _is_taken(o):
		return
	if mode == Mode.TERMINAL:
		if GameState.instance.accepted().size() >= GameState.MAX_ACCEPTED:
			GameState.instance.request_accept.rpc_id(1, o.id) # the host explains why not
			return
		_taken = o
		_taken_row = i
		_taken_t = TAKEN_SHOW_TIME
		_redraw()
		GameState.instance.request_accept.rpc_id(1, o.id)
	else:
		GameState.instance.request_toggle_ready.rpc_id(1, o.id)


func _redraw() -> void:
	var game := GameState.instance
	if game == null:
		return
	var me := World.instance.local_player() if World.instance else null
	var aimed: Object = me.get_interact_target() if me else null
	var list := _list()
	var count := game.pending().size() if mode == Mode.TERMINAL else list.size()
	for i in _rows.size():
		var o: Dictionary = list[i] if i < list.size() else {}
		var label := _rows[i]
		if o.is_empty():
			label.text = ""
			if mode == Mode.KITCHEN:
				_timers[i].text = ""
			continue
		var left := game.time_left(o)
		var lines := PackedStringArray()
		if mode == Mode.TERMINAL:
			# Green = waiting, white = under your crosshair, grey = you just took it.
			lines.append("%s   %dm   $%d   %s" % [o.house.to_upper(), game.distance_to(o.house), GameState.estimate_pay(o), GameState.format_time(left)])
			lines.append(GameState.describe_items(o.items))
			if o.note != "":
				lines.append("\"%s\"" % o.note)
			# Deep night specials flash red.
			var idle := GREEN if o.mult == 1 else (RED if int(game.clock * 3.0) % 2 == 0 else RED.darkened(0.4))
			if o.mult > 1:
				lines[0] = "SPECIAL x%d!  %s" % [o.mult, lines[0]]
			label.modulate = GREY if _is_taken(o) else (WHITE if aimed == _bodies[i] else idle)
		else:
			lines.append("%s   %s" % [o.house.to_upper(), "[READY]" if o.ready else "[ ]"])
			lines.append(GameState.describe_items(o.items))
			label.modulate = WHITE if aimed == _bodies[i] else DIM # white = under your crosshair
			_timers[i].text = GameState.format_time(left)
			_timers[i].modulate = time_color(left)
		label.text = "\n".join(lines)
	if mode == Mode.TERMINAL:
		var night := NightCycle.instance
		var waiting := "... waiting for calls ..."
		if night and night.phase == NightCycle.Phase.DEEP_NIGHT:
			waiting = "CLOSED\n... but the phone might still ring ..."
		elif night and not night.is_open():
			waiting = "CLOSED - see you tomorrow night"
		_title.text = "INCOMING ORDERS" if count > 0 else "INCOMING ORDERS\n\n\n" + waiting
	else:
		_title.text = "KITCHEN  -  %d/%d" % [count, GameState.MAX_ACCEPTED] if count > 0 else "KITCHEN\n\n\nNo orders taken.\nTake one at the terminal."


## Green while there's time, yellow under 2 minutes, red under 45 seconds.
static func time_color(left: float) -> Color:
	if left < HURRY_TIME:
		return RED
	return YELLOW if left < WARN_TIME else GREEN


# --- Building -----------------------------------------------------------------------

## A chunky CRT on a podium. Screen ~1.4m up, facing -Z.
func _build_terminal() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	add_child(body)
	_box(body, Vector3(0.7, 1.0, 0.55), Vector3(0, 0.5, 0), _mat(Color(0.25, 0.22, 0.2))) # podium
	_box(body, Vector3(0.8, 0.05, 0.65), Vector3(0, 1.025, 0), _mat(Color(0.15, 0.13, 0.12)))
	_box(body, Vector3(1.05, 0.8, 0.6), Vector3(0, 1.45, 0.05), _mat(Color(0.75, 0.72, 0.62))) # CRT
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.05, 1.85, 0.65)
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = Vector3(0, 0.925, 0)
	body.add_child(col)
	var glass := _mat(Color(0.02, 0.07, 0.03))
	glass.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_quad(Vector2(0.92, 0.68), Vector3(0, 1.45, -0.26), glass)
	var glow := OmniLight3D.new()
	glow.light_color = GREEN
	glow.light_energy = 0.4
	glow.omni_range = 2.0
	glow.position = Vector3(0, 1.45, -0.6)
	add_child(glow)
	_title = _label(Vector3(0, 1.78, -0.27), 0.002, 30, 430)
	_title.modulate = GREEN
	_title.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_add_rows(GameState.MAX_PENDING, Vector3(0, 1.70, -0.27), 0.19, 0.9, 0.0015, 26, 573)


## A dark screen hung over the kitchen counter (replaces the old chalkboard), facing -Z.
func _build_kitchen() -> void:
	var frame := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(2.8, 1.5, 0.06)
	box.material = _mat(Color(0.1, 0.1, 0.1))
	frame.mesh = box
	add_child(frame)
	var screen := _mat(Color(0.03, 0.03, 0.04))
	screen.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_quad(Vector2(2.66, 1.36), Vector3(0, 0, -0.035), screen)
	_title = _label(Vector3(0, 0.64, -0.04), 0.0045, 32, 560)
	_title.modulate = AMBER
	_title.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_add_rows(GameState.MAX_ACCEPTED, Vector3(0, 0.46, -0.04), 0.28, 2.6, 0.0032, 32, 800)


## `count` rows going down from `top` (the first row's top edge), each `step` tall.
func _add_rows(count: int, top: Vector3, step: float, hit_width: float, pixel: float, font: int, width_px: int) -> void:
	for i in count:
		var at := top - Vector3(0, i * step, 0)
		var label := _label(at, pixel, font, width_px)
		label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		_rows.append(label)
		if mode == Mode.KITCHEN:
			# The countdown sits on the row's right edge (local -X, since the screen faces -Z).
			var timer := _label(at + Vector3(-hit_width / 2.0, 0, 0), pixel, roundi(font * 1.4), 0)
			timer.autowrap_mode = TextServer.AUTOWRAP_OFF
			timer.offset.x = 0.0
			timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			timer.vertical_alignment = VERTICAL_ALIGNMENT_TOP
			_timers.append(timer)
		var row := Row.new()
		row.screen = self
		row.index = i
		row.collision_layer = 2 # the interact ray finds it; nothing bumps into it
		row.collision_mask = 0
		row.position = at - Vector3(0, step / 2.0, 0)
		var shape := BoxShape3D.new()
		shape.size = Vector3(hit_width, step * 0.95, 0.04)
		var col := CollisionShape3D.new()
		col.shape = shape
		row.add_child(col)
		add_child(row)
		_bodies.append(row)


func _label(pos: Vector3, pixel: float, font: int, width_px: int) -> Label3D:
	var l := Label3D.new()
	l.position = pos
	l.rotation.y = PI # read from -Z
	l.pixel_size = pixel
	l.font_size = font
	l.outline_size = 0
	l.width = width_px
	l.offset.x = -width_px / 2.0 # left-aligned text starts at the origin: shift it to the left edge
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(l)
	return l


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = mat
	mi.mesh = mesh
	mi.position = pos
	parent.add_child(mi)
	return mi


func _quad(size: Vector2, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = size
	q.material = mat
	mi.mesh = q
	mi.position = pos
	mi.rotation.y = PI # faces -Z
	add_child(mi)


func _mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	return m
