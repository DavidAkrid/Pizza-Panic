class_name Hud
extends CanvasLayer
## Minimal HUD built in code. Positions assume the 640x360 base viewport.

var order_label: Label
var money_label: Label
var prompt_label: Label
var message_label: Label
var compass: Compass
var stamina_bar: ColorRect
var _message_time := 0.0


func _ready() -> void:
	order_label = _label(Vector2(8, 300), Vector2(360, 56), 10, HORIZONTAL_ALIGNMENT_LEFT)
	money_label = _label(Vector2(432, 6), Vector2(200, 20), 14, HORIZONTAL_ALIGNMENT_RIGHT)
	money_label.modulate = Color(0.6, 1, 0.6)
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

	stamina_bar = ColorRect.new()
	stamina_bar.color = Color(0.9, 0.9, 0.9, 0.7)
	stamina_bar.position = Vector2(270, 340)
	stamina_bar.size = Vector2(100, 3)
	stamina_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stamina_bar)


func _process(delta: float) -> void:
	if _message_time > 0.0:
		_message_time -= delta
		message_label.modulate.a = clampf(_message_time / 0.5, 0.0, 1.0)


func show_message(text: String, duration := 3.5) -> void:
	message_label.text = text
	message_label.modulate.a = 1.0
	_message_time = duration


func set_stamina(ratio: float) -> void:
	stamina_bar.visible = ratio < 0.999
	stamina_bar.size.x = 100.0 * ratio
	stamina_bar.position.x = 320.0 - 50.0 * ratio


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
