extends Control
class_name MobileControls

## Touch controls drawn with the 2D canvas API (no textures needed):
## stick side  - virtual movement joystick
## other side  - swipe to look, FIRE / RELOAD / CROUCH buttons
##
## Every widget can be dragged to a custom place in the menu
## (SETTINGS -> BUTTON LAYOUT). Positions are stored normalised (0..1 of the
## screen) in GameSettings, so they survive rotation and resolution changes.
## Set `edit_mode = true` to turn the pad into that editor.

signal reload_pressed
signal weapon_pressed

const STICK_RADIUS_BASE := 130.0
const STICK_KNOB_BASE := 52.0
const BTN_FIRE_R_BASE := 92.0
const BTN_R_BASE := 58.0

var move_vector := Vector2.ZERO
var fire_held := false
var crouch_held := false

var stick_radius := STICK_RADIUS_BASE
var stick_knob := STICK_KNOB_BASE
var btn_fire_r := BTN_FIRE_R_BASE
var btn_r := BTN_R_BASE
var mirrored := false

## Editor mode: widgets are dragged instead of used.
var edit_mode := false

var _look_delta := Vector2.ZERO
var _stick_center := Vector2.ZERO
var _stick_pos := Vector2.ZERO
var _stick_touch := -1
var _look_touch := -1
var _fire_touch := -1
var _reload_touch := -1
var _crouch_touch := -1
var _weapon_touch := -1
var _fire_center := Vector2.ZERO
var _reload_center := Vector2.ZERO
var _crouch_center := Vector2.ZERO
var _weapon_center := Vector2.ZERO
var _drag_widget := ""
var _drag_touch := -1


func _ready() -> void:
	if not edit_mode:
		add_to_group("mobile_controls")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	apply_settings()


func apply_settings() -> void:
	GameSettings.ensure_loaded()
	var s: float = clampf(GameSettings.button_scale, 0.7, 1.4)
	stick_radius = STICK_RADIUS_BASE * s
	stick_knob = STICK_KNOB_BASE * s
	btn_fire_r = BTN_FIRE_R_BASE * s
	btn_r = BTN_R_BASE * s
	mirrored = GameSettings.layout == GameSettings.LAYOUT_LEFT
	_layout_widgets()


func _mirror_x(x: float) -> float:
	return size.x - x if mirrored else x


## Default positions (used until the player moves a widget in the editor).
func _default_center(widget: String) -> Vector2:
	var s := size
	match widget:
		"stick":
			return Vector2(_mirror_x(stick_radius + 50.0), s.y - stick_radius - 50.0)
		"fire":
			return Vector2(_mirror_x(s.x - btn_fire_r - 60.0), s.y - btn_fire_r - 70.0)
		"reload":
			return Vector2(_mirror_x(s.x - btn_r - 70.0),
				s.y - btn_fire_r * 2.0 - btn_r - 70.0)
		"weapon":
			return Vector2(_mirror_x(s.x - btn_fire_r * 2.0 - btn_r - 60.0),
				s.y - btn_r * 2.0 - 76.0)
		_:
			return Vector2(_mirror_x(s.x - btn_fire_r * 2.0 - btn_r - 60.0),
				s.y - btn_r - 60.0)


func _center_for(widget: String) -> Vector2:
	var norm: Vector2 = GameSettings.widget_position(widget)
	if norm.x < 0.0 or norm.y < 0.0 or size.x < 8.0:
		return _default_center(widget)
	return Vector2(norm.x * size.x, norm.y * size.y)


func _layout_widgets() -> void:
	_stick_center = _center_for("stick")
	_stick_pos = _stick_center
	_fire_center = _center_for("fire")
	_reload_center = _center_for("reload")
	_crouch_center = _center_for("crouch")
	_weapon_center = _center_for("weapon")


## Writes the current widget positions back into the settings (editor only).
func store_layout() -> void:
	if size.x < 8.0 or size.y < 8.0:
		return
	GameSettings.set_widget_position("stick", _stick_center / size)
	GameSettings.set_widget_position("fire", _fire_center / size)
	GameSettings.set_widget_position("reload", _reload_center / size)
	GameSettings.set_widget_position("crouch", _crouch_center / size)
	GameSettings.set_widget_position("weapon", _weapon_center / size)


func reset_layout() -> void:
	GameSettings.reset_widget_positions()
	_layout_widgets()
	queue_redraw()


func _process(_delta: float) -> void:
	if edit_mode:
		queue_redraw()
		return
	if _stick_touch < 0:
		# keeps the stick anchored after any resolution change
		_stick_center = _center_for("stick")
		_stick_pos = _stick_center
		_fire_center = _center_for("fire")
		_reload_center = _center_for("reload")
		_crouch_center = _center_for("crouch")
		_weapon_center = _center_for("weapon")
	queue_redraw()


func consume_look() -> Vector2:
	var d := _look_delta
	_look_delta = Vector2.ZERO
	return d


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			_press(t.index, t.position)
		else:
			_release(t.index)
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		_drag(d.index, d.position, d.relative)


func _in_stick_zone(p: Vector2) -> bool:
	# Anywhere within a generous ring around the stick, plus the whole half of
	# the screen the stick lives on (so the thumb never misses it).
	if p.distance_to(_stick_center) <= stick_radius * 1.5:
		return true
	return p.x > size.x * 0.54 if mirrored else p.x < size.x * 0.46


# ------------------------------------------------------------------ editor
func _widget_at(p: Vector2) -> String:
	var best := ""
	var best_d := INF
	for entry in [["stick", _stick_center, stick_radius],
			["fire", _fire_center, btn_fire_r],
			["reload", _reload_center, btn_r],
			["crouch", _crouch_center, btn_r],
			["weapon", _weapon_center, btn_r]]:
		var name_str: String = String(entry[0])
		var center: Vector2 = entry[1]
		var radius: float = float(entry[2])
		var d := p.distance_to(center)
		if d <= radius * 1.15 and d < best_d:
			best_d = d
			best = name_str
	return best


func _move_widget(widget: String, p: Vector2) -> void:
	var pad := 24.0
	var q := Vector2(clampf(p.x, pad, size.x - pad), clampf(p.y, pad, size.y - pad))
	match widget:
		"stick":
			_stick_center = q
			_stick_pos = q
		"fire":
			_fire_center = q
		"reload":
			_reload_center = q
		"crouch":
			_crouch_center = q
		"weapon":
			_weapon_center = q


# ------------------------------------------------------------------ input
func _press(index: int, p: Vector2) -> void:
	if edit_mode:
		var w := _widget_at(p)
		if w != "":
			_drag_widget = w
			_drag_touch = index
			_move_widget(w, p)
		return
	if p.distance_to(_fire_center) <= btn_fire_r:
		_fire_touch = index
		fire_held = true
		return
	if p.distance_to(_reload_center) <= btn_r:
		_reload_touch = index
		reload_pressed.emit()
		return
	if p.distance_to(_crouch_center) <= btn_r:
		_crouch_touch = index
		crouch_held = not crouch_held
		return
	if p.distance_to(_weapon_center) <= btn_r:
		_weapon_touch = index
		weapon_pressed.emit()
		return
	if _in_stick_zone(p) and _stick_touch < 0:
		_stick_touch = index
		_stick_center = p
		_stick_pos = p
		return
	if _look_touch < 0:
		_look_touch = index


func _release(index: int) -> void:
	if edit_mode:
		if index == _drag_touch:
			_drag_touch = -1
			_drag_widget = ""
			store_layout()
		return
	if index == _stick_touch:
		_stick_touch = -1
		move_vector = Vector2.ZERO
		_layout_widgets()
	if index == _look_touch:
		_look_touch = -1
	if index == _fire_touch:
		_fire_touch = -1
		fire_held = false
	if index == _reload_touch:
		_reload_touch = -1
	if index == _crouch_touch:
		_crouch_touch = -1
	if index == _weapon_touch:
		_weapon_touch = -1


func _drag(index: int, p: Vector2, rel: Vector2) -> void:
	if edit_mode:
		if index == _drag_touch and _drag_widget != "":
			_move_widget(_drag_widget, p)
		return
	if index == _stick_touch:
		var off := p - _stick_center
		if off.length() > stick_radius:
			off = off.normalized() * stick_radius
		_stick_pos = _stick_center + off
		var v := off / stick_radius
		move_vector = Vector2(v.x, v.y)
	elif index == _look_touch:
		_look_delta += rel
	elif index == _fire_touch:
		if p.distance_to(_fire_center) > btn_fire_r * 1.6:
			_fire_touch = -1
			fire_held = false


# ------------------------------------------------------------------ drawing
func _draw() -> void:
	var dim := Color(1, 1, 1, 0.13)
	var bright := Color(1, 1, 1, 0.3)
	if edit_mode:
		dim = Color(1, 0.75, 0.3, 0.22)
		bright = Color(1, 0.8, 0.4, 0.55)

	draw_arc(_stick_center, stick_radius, 0.0, TAU, 40, dim, 3.0, true)
	draw_circle(_stick_pos, stick_knob, Color(1, 1, 1, 0.16))
	draw_arc(_stick_pos, stick_knob, 0.0, TAU, 28, bright, 2.0, true)
	if edit_mode:
		_label("MOVE", _stick_center, 18)

	var fire_col := Color(1.0, 0.35, 0.3, 0.32) if fire_held else Color(1, 1, 1, 0.14)
	draw_circle(_fire_center, btn_fire_r, fire_col)
	draw_arc(_fire_center, btn_fire_r, 0.0, TAU, 32, bright, 2.5, true)
	_label("FIRE", _fire_center, 22)

	draw_circle(_reload_center, btn_r, Color(1, 1, 1, 0.12))
	draw_arc(_reload_center, btn_r, 0.0, TAU, 28, bright, 2.0, true)
	_label("RELOAD", _reload_center, 16)

	var cr_col := Color(0.4, 0.8, 1.0, 0.28) if crouch_held else Color(1, 1, 1, 0.12)
	draw_circle(_crouch_center, btn_r, cr_col)
	draw_arc(_crouch_center, btn_r, 0.0, TAU, 28, bright, 2.0, true)
	_label("CROUCH", _crouch_center, 15)
	draw_circle(_weapon_center, btn_r, Color(0.75, 0.55, 0.22, 0.16))
	draw_arc(_weapon_center, btn_r, 0.0, TAU, 28, bright, 2.0, true)
	_label("WEAPON", _weapon_center, 13)


func _label(text: String, center: Vector2, font_size: int) -> void:
	var font := ThemeDB.fallback_font
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(font, center + Vector2(-w * 0.5, font_size * 0.35), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1, 1, 1, 0.66))
