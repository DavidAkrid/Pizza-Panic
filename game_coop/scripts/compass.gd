class_name Compass
extends Control
## Skyrim-style compass strip: cardinal directions plus one chevron for where you're headed.
## Bearings are radians, 0 = north (-Z), increasing clockwise (east = +X).

const STRIP_WIDTH := 220.0
const SPAN := PI ## how much of the circle the strip shows, edge to edge

var heading := 0.0
var marker_bearing := NAN ## NAN = no marker
var marker_color := Color(1, 0.85, 0.4)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var cx := size.x / 2.0
	draw_rect(Rect2(cx - STRIP_WIDTH / 2.0, 15, STRIP_WIDTH, 1), Color(1, 1, 1, 0.2))
	for i in 8:
		var rel := _relative(i * PI / 4.0)
		if absf(rel) > SPAN / 2.0:
			continue
		var x := _x(rel)
		var fade := 1.0 - absf(rel) / (SPAN / 2.0)
		if i % 2 == 0:
			var letter: String = ["N", "E", "S", "W"][i / 2]
			draw_string(font, Vector2(x - 10, 12), letter, HORIZONTAL_ALIGNMENT_CENTER, 20, 10, Color(1, 1, 1, 0.85 * fade))
		else:
			draw_line(Vector2(x, 10), Vector2(x, 15), Color(1, 1, 1, 0.4 * fade))

	if is_nan(marker_bearing):
		return
	var rel := _relative(marker_bearing)
	var off_strip := absf(rel) > SPAN / 2.0
	var x := _x(clampf(rel, -SPAN / 2.0, SPAN / 2.0))
	var color := marker_color
	if off_strip:
		color.a = 0.5 # pinned to the edge: "turn this way"
	draw_polyline(PackedVector2Array([Vector2(x - 4, 18), Vector2(x, 22), Vector2(x + 4, 18)]), color, 2.0)


func _relative(bearing: float) -> float:
	return wrapf(bearing - heading, -PI, PI)


func _x(rel: float) -> float:
	return size.x / 2.0 + rel / (SPAN / 2.0) * STRIP_WIDTH / 2.0


## Bearing from one world position to another.
static func bearing(from: Vector3, to: Vector3) -> float:
	return atan2(to.x - from.x, -(to.z - from.z))
