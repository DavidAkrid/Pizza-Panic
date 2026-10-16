class_name Hud
extends CanvasLayer
## Minimal HUD built in code. Positions assume the 640x360 base viewport.

var order_label: Label ## top left: taken orders
var hands_label: Label ## bottom right, above the slots: details of the selected slot
var money_label: Label
var night_label: Label ## top right, under the money: night, time, phase
var prompt_label: Label
var message_label: Label
var compass: Compass
var stamina_bar: ColorRect
var health_bar: ColorRect
var _health_back: ColorRect
var _down_overlay: ColorRect
var _down_label: Label
var _message_time := 0.0
var _slot_boxes: Array[Panel] = []
var _slot_flash: Array[float] = []
var _marker: Control
var _marker_t := 0.0

const MARKER_TIME := 0.3
const FLASH_TIME := 0.3
var _slot_labels: Array[Label] = []

const SLOT_SIZE := Vector2(72, 20)
const SLOT_GAP := 4.0


func _ready() -> void:
	order_label = _label(Vector2(8, 6), Vector2(190, 150), 10, HORIZONTAL_ALIGNMENT_LEFT)
	order_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hands_label = _label(Vector2(392, 268), Vector2(240, 56), 10, HORIZONTAL_ALIGNMENT_RIGHT)
	hands_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	hands_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	money_label = _label(Vector2(432, 6), Vector2(200, 20), 14, HORIZONTAL_ALIGNMENT_RIGHT)
	money_label.modulate = Color(0.6, 1, 0.6)
	night_label = _label(Vector2(392, 26), Vector2(240, 30), 10, HORIZONTAL_ALIGNMENT_RIGHT)
	prompt_label = _label(Vector2(120, 205), Vector2(400, 20), 10, HORIZONTAL_ALIGNMENT_CENTER)
	message_label = _label(Vector2(70, 70), Vector2(500, 90), 12, HORIZONTAL_ALIGNMENT_CENTER)
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	compass = Compass.new()
	compass.position = Vector2(200, 2)
	compass.size = Vector2(240, 26)
	compass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(compass)

	var dot := ColorRect.new()
	dot.color = Color(1, 1, 1, 0.6)
	dot.position = Vector2(319, 179)
	dot.size = Vector2(2, 2)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dot)

	_marker = Control.new()
	_marker.position = Vector2(320, 180)
	_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marker.draw.connect(_draw_marker)
	add_child(_marker)

	# You're down: the screen goes red, with what to do about it.
	_down_overlay = ColorRect.new()
	_down_overlay.color = Color(0.6, 0.0, 0.0, 0.35)
	_down_overlay.size = Vector2(640, 360)
	_down_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_down_overlay.visible = false
	add_child(_down_overlay)
	move_child(_down_overlay, 0) # under everything else
	_down_label = _label(Vector2(120, 140), Vector2(400, 60), 14, HORIZONTAL_ALIGNMENT_CENTER)
	_down_label.modulate = Color(1, 0.8, 0.8)

	# Health: bottom left, only once you're hurt.
	_health_back = ColorRect.new()
	_health_back.color = Color(0, 0, 0, 0.5)
	_health_back.position = Vector2(8, 340)
	_health_back.size = Vector2(102, 6)
	_health_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_health_back)
	health_bar = ColorRect.new()
	health_bar.color = Color(0.9, 0.2, 0.2)
	health_bar.position = Vector2(9, 341)
	health_bar.size = Vector2(100, 4)
	health_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(health_bar)

	stamina_bar = ColorRect.new()
	stamina_bar.color = Color(0.9, 0.9, 0.9, 0.7)
	stamina_bar.position = Vector2(270, 318)
	stamina_bar.size = Vector2(100, 3)
	stamina_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stamina_bar)


func _process(delta: float) -> void:
	if _marker_t > 0.0:
		_marker_t -= delta
		_marker.queue_redraw()
	for i in _slot_flash.size():
		_slot_flash[i] = maxf(_slot_flash[i] - delta, 0.0)
	if _message_time > 0.0:
		_message_time -= delta
		message_label.modulate.a = clampf(_message_time / 0.5, 0.0, 1.0)


func show_message(text: String, duration := 3.5) -> void:
	message_label.text = text
	message_label.modulate.a = 1.0
	_message_time = duration


## Small red X around the crosshair: something you care about just took damage.
func hit_marker() -> void:
	_marker_t = MARKER_TIME
	_marker.queue_redraw()


func flash_slot(i: int) -> void:
	if i >= 0 and i < _slot_flash.size():
		_slot_flash[i] = FLASH_TIME


func _draw_marker() -> void:
	if _marker_t <= 0.0:
		return
	var c := Color(1, 0.25, 0.2, clampf(_marker_t / MARKER_TIME, 0.0, 1.0))
	for d: Vector2 in [Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1)]:
		_marker.draw_line(d * 3.0, d * 7.0, c, 1.5)


func set_health(ratio: float) -> void:
	var hurt := ratio < 0.999
	health_bar.visible = hurt
	_health_back.visible = hurt
	health_bar.size.x = 100.0 * ratio


## "" hides the red screen.
func set_down(text: String) -> void:
	_down_overlay.visible = text != ""
	_down_label.text = text


func set_stamina(ratio: float) -> void:
	stamina_bar.visible = ratio < 0.999
	stamina_bar.size.x = 100.0 * ratio
	stamina_bar.position.x = 320.0 - 50.0 * ratio # centered under the crosshair, above the slots


## Inventory row in the bottom right; the selected slot is highlighted.
func set_slots(slots: Array, active: int) -> void:
	if _slot_boxes.size() != slots.size():
		_build_slots(slots.size())
	for i in slots.size():
		_slot_labels[i].text = "%d  %s" % [i + 1, _short_name(slots[i])]
		var box := _slot_boxes[i]
		var style := box.get_theme_stylebox("panel") as StyleBoxFlat
		style.border_color = Color(1, 0.85, 0.4) if i == active else Color(1, 1, 1, 0.15)
		style.bg_color = Color(0, 0, 0, 0.55) if i == active else Color(0, 0, 0, 0.3)
		style.bg_color = style.bg_color.lerp(Color(0.8, 0.1, 0.05, 0.8), _slot_flash[i] / FLASH_TIME)
		_slot_labels[i].modulate.a = 1.0 if i == active else 0.6
	var thing = slots[active]
	hands_label.text = "Fists" if thing == null else thing.describe()


func _build_slots(count: int) -> void:
	for b in _slot_boxes:
		b.queue_free()
	_slot_boxes.clear()
	_slot_labels.clear()
	_slot_flash.clear()
	var slot_size := SLOT_SIZE if count <= 3 else Vector2(52, SLOT_SIZE.y) # narrower once upgraded
	var x := 632.0 - count * slot_size.x - (count - 1) * SLOT_GAP
	for i in count:
		var box := Panel.new()
		box.position = Vector2(x + i * (slot_size.x + SLOT_GAP), 330)
		box.size = slot_size
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var style := StyleBoxFlat.new()
		style.set_border_width_all(1)
		box.add_theme_stylebox_override("panel", style)
		add_child(box)
		var l := Label.new()
		l.size = slot_size
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.add_theme_font_size_override("font_size", 9)
		box.add_child(l)
		_slot_boxes.append(box)
		_slot_labels.append(l)
		_slot_flash.append(0.0)


func _short_name(thing: Variant) -> String:
	if thing == null:
		return "-"
	if thing is Pizza:
		match thing.stage:
			Pizza.Stage.RAW: return "Raw Pizza"
			Pizza.Stage.BOXED: return "Boxed Pizza"
		return "Pizza"
	return thing.short_name() if thing.has_method("short_name") else str(thing.get("item_name"))


func _label(pos: Vector2, size: Vector2, font_size: int, align: HorizontalAlignment) -> Label:
	var l := Label.new()
	l.position = pos
	l.size = size
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_constant_override("outline_size", 3)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	add_child(l)
	return l
