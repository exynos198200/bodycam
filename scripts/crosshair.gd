extends Node
class_name Crosshair

## Shared crosshair renderer used by the HUD and by the settings preview, so
## both always look identical. Styles / size / colour come from GameSettings.

static func draw_on(canvas: CanvasItem, center: Vector2) -> void:
	GameSettings.ensure_loaded()
	var style := GameSettings.crosshair_style
	if style == GameSettings.CROSS_NONE:
		return
	var s: float = clampf(GameSettings.crosshair_size, 0.5, 2.0)
	var col: Color = GameSettings.cross_color()
	var shadow := Color(0, 0, 0, 0.6)
	var gap := 9.0 * s
	var length := 16.0 * s
	var width := 2.0 * s

	match style:
		GameSettings.CROSS_DOT:
			canvas.draw_circle(center, 4.0 * s, shadow)
			canvas.draw_circle(center, 2.6 * s, col)
		GameSettings.CROSS_CIRCLE:
			canvas.draw_arc(center, gap + 5.0 * s, 0.0, TAU, 32, shadow, width + 2.0, true)
			canvas.draw_arc(center, gap + 5.0 * s, 0.0, TAU, 32, col, width, true)
			canvas.draw_circle(center, 3.4 * s, shadow)
			canvas.draw_circle(center, 2.0 * s, col)
		GameSettings.CROSS_T:
			_line(canvas, center, Vector2(gap, 0), Vector2(gap + length, 0), col, shadow, width)
			_line(canvas, center, -Vector2(gap + length, 0), -Vector2(gap, 0), col, shadow, width)
			_line(canvas, center, Vector2(0, gap), Vector2(0, gap + length), col, shadow, width)
			canvas.draw_circle(center, 2.2 * s, col)
		_:
			_line(canvas, center, Vector2(gap, 0), Vector2(gap + length, 0), col, shadow, width)
			_line(canvas, center, -Vector2(gap + length, 0), -Vector2(gap, 0), col, shadow, width)
			_line(canvas, center, Vector2(0, gap), Vector2(0, gap + length), col, shadow, width)
			_line(canvas, center, -Vector2(0, gap + length), -Vector2(0, gap), col, shadow, width)
			canvas.draw_circle(center, 2.6 * s, shadow)
			canvas.draw_circle(center, 1.7 * s, col)


static func _line(canvas: CanvasItem, center: Vector2, a: Vector2, b: Vector2,
		col: Color, shadow: Color, width: float) -> void:
	var o := Vector2(1, 1)
	canvas.draw_line(center + a + o, center + b + o, shadow, width + 1.5)
	canvas.draw_line(center + a, center + b, col, width)
