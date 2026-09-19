extends CanvasLayer
class_name Hud

## Bodycam styled HUD: REC indicator, CAM id, running timestamp, ammo counter,
## health bar, hit vignette and the win/lose screen with a restart button.

signal restart_requested
signal menu_requested

var controls: MobileControls = null

var _rec_time := 0.0
var _blink := 0.0
var _hit_flash := 0.0
var _result_shown := false

var _rec_label: Label
var _cam_label: Label
var _time_label: Label
var _battery_label: Label
var _ammo_label: Label
var _weapon_label: Label
var _online_label: Label
var _state_label: Label
var _health_bar: ProgressBar
var _health_label: Label
var _enemy_bar: ProgressBar
var _crosshair: Control
var _hit_rect: ColorRect
var _result_panel: Control
var _result_title: Label
var _result_sub: Label
var _restart_btn: Button
var _menu_btn: Button
var _rec_dot: Control
var _cam_sfx: AudioStreamPlayer


func _ready() -> void:
	GameSettings.ensure_loaded()
	layer = 3
	controls = get_node_or_null("MobileControls")
	_build()
	_cam_sfx = AudioStreamPlayer.new()
	_cam_sfx.stream = load("res://audio/cam_beep.wav")
	_cam_sfx.volume_db = -8.0
	add_child(_cam_sfx)
	_cam_sfx.play()


func _mk_label(text: String, pos: Vector2, fsize: int, color: Color,
		anchor_right := false, anchor_bottom := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fsize)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	if anchor_right:
		l.anchor_left = 1.0
		l.anchor_right = 1.0
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		l.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	if anchor_bottom:
		l.anchor_top = 1.0
		l.anchor_bottom = 1.0
		l.grow_vertical = Control.GROW_DIRECTION_BEGIN
	l.position = pos
	return l


func _build() -> void:
	var white := Color(0.94, 0.96, 0.98)

	# ---- hit vignette ----
	_hit_rect = ColorRect.new()
	_hit_rect.color = Color(0.75, 0.03, 0.03, 0.0)
	_hit_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hit_rect)
	_hit_rect.set_anchors_preset(Control.PRESET_FULL_RECT)

	# ---- top-left REC block ----
	_rec_dot = Control.new()
	_rec_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rec_dot.position = Vector2(38, 34)
	_rec_dot.custom_minimum_size = Vector2(24, 24)
	_rec_dot.draw.connect(func() -> void:
		var a: float = 1.0 if _blink < 0.6 else 0.15
		_rec_dot.draw_circle(Vector2(8, 12), 8.0, Color(0.95, 0.12, 0.1, a)))
	add_child(_rec_dot)

	_rec_label = _mk_label("REC", Vector2(58, 24), 26, Color(1.0, 0.35, 0.3))
	_cam_label = _mk_label("CAM 01  •  BODY UNIT", Vector2(38, 60), 18, Color(0.85, 0.88, 0.92, 0.85))
	_time_label = _mk_label("00:00:00", Vector2(38, 86), 22, white)
	_battery_label = _mk_label("BATT 87%   ISO 1600   f/1.8", Vector2(-330, 26), 17,
		Color(0.85, 0.88, 0.92, 0.8), true)

	# ---- crosshair ----
	_crosshair = Control.new()
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_crosshair)
	_crosshair.set_anchors_preset(Control.PRESET_FULL_RECT)
	_crosshair.z_index = 20
	# The size of a Control parented to a CanvasLayer is not reliable on a
	# phone, so the crosshair is centred on the visible viewport rect.
	# Drawn by the shared Crosshair helper so the menu preview and the HUD
	# always match. Style / size / colour come from GameSettings.
	_crosshair.draw.connect(func() -> void:
		Crosshair.draw_on(_crosshair, _crosshair.get_viewport_rect().size * 0.5))

	# ---- ammo (bottom right, above the fire button) ----
	_weapon_label = _mk_label("PBR PISTOL", Vector2(-250, -150), 18, Color(1.0, 0.75, 0.4), true, true)
	_ammo_label = _mk_label("12 / 48", Vector2(-250, -112), 40, white, true, true)
	_state_label = _mk_label("", Vector2(-250, -78), 20, Color(1.0, 0.75, 0.4), true, true)
	_online_label = _mk_label("WAITING FOR PLAYER 2", Vector2(-390, 28), 17, Color(0.45, 0.85, 1.0, 0.9), true)

	# ---- health (bottom left, above the joystick) ----
	_health_label = _mk_label("VITALS 100", Vector2(40, -330), 20, white, false, true)
	_health_bar = ProgressBar.new()
	_health_bar.show_percentage = false
	_health_bar.min_value = 0.0
	_health_bar.max_value = 100.0
	_health_bar.value = 100.0
	_health_bar.custom_minimum_size = Vector2(300, 14)
	_health_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style_bar(_health_bar, Color(0.85, 0.22, 0.2))
	add_child(_health_bar)
	_health_bar.anchor_top = 1.0
	_health_bar.anchor_bottom = 1.0
	_health_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_health_bar.position = Vector2(40, -302)

	# ---- enemy health (top center) ----
	_enemy_bar = ProgressBar.new()
	_enemy_bar.show_percentage = false
	_enemy_bar.min_value = 0.0
	_enemy_bar.max_value = 100.0
	_enemy_bar.value = 100.0
	_enemy_bar.custom_minimum_size = Vector2(340, 10)
	_enemy_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style_bar(_enemy_bar, Color(0.95, 0.65, 0.2))
	_enemy_bar.visible = false
	add_child(_enemy_bar)
	_enemy_bar.anchor_left = 0.5
	_enemy_bar.anchor_right = 0.5
	_enemy_bar.position = Vector2(-170, 34)

	# ---- result screen ----
	_result_panel = Control.new()
	_result_panel.visible = false
	_result_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_result_panel)
	_result_panel.set_anchors_preset(Control.PRESET_FULL_RECT)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	_result_panel.add_child(dim)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)

	_result_title = Label.new()
	_result_title.text = ""
	_result_title.add_theme_font_size_override("font_size", 68)
	_result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_panel.add_child(_result_title)
	_result_title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_result_title.anchor_left = 0.0
	_result_title.anchor_right = 1.0
	_result_title.anchor_top = 0.32
	_result_title.anchor_bottom = 0.32

	_result_sub = Label.new()
	_result_sub.add_theme_font_size_override("font_size", 24)
	_result_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_sub.add_theme_color_override("font_color", Color(0.85, 0.88, 0.92))
	_result_panel.add_child(_result_sub)
	_result_sub.anchor_left = 0.0
	_result_sub.anchor_right = 1.0
	_result_sub.anchor_top = 0.44
	_result_sub.anchor_bottom = 0.44

	_restart_btn = Button.new()
	_restart_btn.text = "RESTART"
	_restart_btn.add_theme_font_size_override("font_size", 30)
	_restart_btn.custom_minimum_size = Vector2(300, 90)
	_result_panel.add_child(_restart_btn)
	_restart_btn.anchor_left = 0.5
	_restart_btn.anchor_right = 0.5
	_restart_btn.anchor_top = 0.58
	_restart_btn.anchor_bottom = 0.58
	_restart_btn.position = Vector2(-150, 0)
	_restart_btn.pressed.connect(func() -> void: restart_requested.emit())

	_menu_btn = Button.new()
	_menu_btn.text = "MAIN MENU"
	_menu_btn.add_theme_font_size_override("font_size", 24)
	_menu_btn.custom_minimum_size = Vector2(300, 70)
	_result_panel.add_child(_menu_btn)
	_menu_btn.anchor_left = 0.5
	_menu_btn.anchor_right = 0.5
	_menu_btn.anchor_top = 0.74
	_menu_btn.anchor_bottom = 0.74
	_menu_btn.position = Vector2(-150, 0)
	_menu_btn.pressed.connect(func() -> void: menu_requested.emit())


func _style_bar(bar: ProgressBar, col: Color) -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.05, 0.06, 0.07, 0.55)
	bg.border_color = Color(1, 1, 1, 0.25)
	bg.set_border_width_all(1)
	var fg := StyleBoxFlat.new()
	fg.bg_color = col
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fg)


func _process(delta: float) -> void:
	if not _result_shown:
		_rec_time += delta
	_blink = fmod(_blink + delta, 1.0)
	_rec_dot.queue_redraw()
	_crosshair.queue_redraw()
	_time_label.text = _fmt_time(_rec_time)
	var batt: int = maxi(11, 87 - int(_rec_time / 25.0))
	_battery_label.text = "BATT %d%%   ISO 1600   f/1.8" % batt
	if _hit_flash > 0.0:
		_hit_flash = maxf(0.0, _hit_flash - delta * 1.6)
		_hit_rect.color = Color(0.75, 0.03, 0.03, _hit_flash * 0.35)


static func _fmt_time(t: float) -> String:
	var total := int(t)
	return "%02d:%02d:%02d" % [total / 3600, (total / 60) % 60, total % 60]


# ---------------------------------------------------------------- api
func set_health(cur: float, maxv: float) -> void:
	_health_bar.max_value = maxv
	_health_bar.value = cur
	_health_label.text = "VITALS %d" % int(cur)


func set_enemy_health(cur: float, maxv: float) -> void:
	_enemy_bar.max_value = maxv
	_enemy_bar.value = cur


func set_ammo(in_mag: int, reserve: int) -> void:
	_ammo_label.text = "%d / %d" % [in_mag, reserve]
	if in_mag == 0:
		_state_label.text = "RELOAD"
	elif _state_label.text == "RELOAD":
		_state_label.text = ""


func set_weapon(name: String) -> void:
	_weapon_label.text = name

func set_online_count(count: int) -> void:
	_online_label.text = "ONLINE 1v1  •  %d/2" % clampi(count, 1, 2)

func set_status(text: String) -> void:
	_state_label.text = text


func flash_hit() -> void:
	_hit_flash = 1.0


func show_result(win: bool, elapsed: float) -> void:
	_result_shown = true
	_result_panel.visible = true
	_result_title.text = "TARGET DOWN" if win else "SIGNAL LOST"
	_result_title.add_theme_color_override("font_color",
		Color(0.55, 0.95, 0.6) if win else Color(0.95, 0.35, 0.3))
	_result_sub.text = ("Duel won in %s" % _fmt_time(elapsed)) if win \
		else "You were neutralized after %s" % _fmt_time(elapsed)
	if controls != null:
		controls.visible = false
		controls.fire_held = false
		controls.move_vector = Vector2.ZERO
