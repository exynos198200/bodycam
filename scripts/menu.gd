extends Control
class_name MainMenu

## Main menu: corridor background, animated bodycam bits and a settings panel
## (sensitivity, crosshair, layout, video). The whole UI is built in code.
##
## The background is drawn twice over: a procedural corridor painted with the
## 2D API (so there is always an image, even if a texture import fails on the
## device) and, on top of it, the generated menu_bg.png when it loads.
## The settings panel is created the first time it is opened - building a
## hidden Control makes its anchors resolve against a zero-sized parent, which
## is why the panel came up empty before.

const TITLE := "BODYCAM DUEL"

var _bg: Control
var _bg_tex: Texture2D = null
var _rec_dot: Control
var _time_label: Label
var _root_box: VBoxContainer
var _settings_panel: Control = null
var _preview: Control = null
var _layout_page: Control = null
var _pad = null       # MobileControls in editor mode (untyped on purpose)
var _blink := 0.0
var _clock := 0.0
var _ip_edit: LineEdit
var _network_status: Label
var _menu_view: SubViewport


func _ready() -> void:
	# Returning from a previous match must release the old ENet peer; otherwise
	# pressing CREATE GAME again can silently hit an already-used socket.
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	GameSettings.ensure_loaded()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	Engine.max_fps = 30
	_build_background()
	_build_main()


# ------------------------------------------------------------------ background
func _build_background() -> void:
	_build_3d_background()
	_bg_tex = load("res://textures/menu_bg.png") as Texture2D
	print("[menu] background texture loaded: %s" % [_bg_tex != null])

	_bg = Control.new()
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.clip_contents = false
	add_child(_bg)
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg.draw.connect(_draw_background)
	_bg.resized.connect(func() -> void: _bg.queue_redraw())
	# The old 2D corridor remains as a safe fallback asset, but the visible
	# menu background is now the supplied GLB character, weapon and smoke.
	_bg.visible = false

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.025, 0.03, 0.34)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# REC block, same visual language as the in-game HUD
	_rec_dot = Control.new()
	_rec_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rec_dot.position = Vector2(34, 30)
	_rec_dot.custom_minimum_size = Vector2(24, 24)
	_rec_dot.draw.connect(func() -> void:
		var a: float = 1.0 if _blink < 0.6 else 0.15
		_rec_dot.draw_circle(Vector2(8, 12), 8.0, Color(0.95, 0.12, 0.1, a)))
	add_child(_rec_dot)
	_label("REC", Vector2(54, 20), 22, Color(1.0, 0.35, 0.3), self)
	_label("CAM 01  •  STANDBY", Vector2(34, 54), 15,
		Color(0.85, 0.88, 0.92, 0.8), self)
	_time_label = _label("00:00:00", Vector2(34, 76), 17,
		Color(0.9, 0.93, 0.96, 0.9), self)


func _build_3d_background() -> void:
	var container := SubViewportContainer.new()
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.stretch = true
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(container)
	_menu_view = SubViewport.new()
	_menu_view.own_world_3d = true
	_menu_view.msaa_3d = Viewport.MSAA_DISABLED
	_menu_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(_menu_view)
	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.012, 0.016, 0.022)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.32, 0.37, 0.48)
	environment.ambient_light_energy = 0.7
	env.environment = environment
	_menu_view.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-28.0, -35.0, 0.0)
	key.light_color = Color(0.78, 0.84, 1.0)
	key.light_energy = 1.35
	key.shadow_enabled = false
	_menu_view.add_child(key)
	var fill := OmniLight3D.new()
	fill.position = Vector3(-2.0, 2.3, 2.0)
	fill.light_color = Color(1.0, 0.45, 0.22)
	fill.light_energy = 4.0
	fill.omni_range = 6.0
	_menu_view.add_child(fill)
	var camera := Camera3D.new()
	camera.position = Vector3(2.6, 1.55, 4.6)
	camera.fov = 47.0
	_menu_view.add_child(camera)
	camera.look_at(Vector3(0.0, 1.0, 0.0), Vector3.UP)

	var floor := MeshInstance3D.new()
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(20.0, 20.0)
	floor.mesh = floor_mesh
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.07, 0.065, 0.06)
	floor_mat.roughness = 0.92
	floor.material_override = floor_mat
	_menu_view.add_child(floor)

	var character := Node3D.new()
	character.name = "MenuCharacter"
	character.rotation.y = 0.35
	_menu_view.add_child(character)
	var rig := RigAnimation.new()
	character.add_child(rig)
	var model_scene := preload("res://models/player/a_lowpoly.glb")
	var model = model_scene.instantiate()
	rig.add_child(model)
	ModelMaterials.apply_character(model)
	rig.rebind()
	rig.set_motion(0.08, true)

	var weapon = preload("res://models/gun/M4A1.glb").instantiate()
	weapon.name = "MenuM4A1"
	weapon.scale = Vector3(0.043, 0.043, 0.043)
	weapon.rotation_degrees = Vector3(0.0, 0.0, 5.0)
	weapon.position = Vector3(0.34, 1.22, -0.48)
	character.add_child(weapon)
	ModelMaterials.apply_m4(weapon)

	var smoke := CPUParticles3D.new()
	smoke.amount = 18
	smoke.lifetime = 5.5
	smoke.preprocess = 3.0
	smoke.emitting = true
	smoke.position = Vector3(0.0, 0.9, 0.25)
	smoke.direction = Vector3(0.0, 1.0, 0.0)
	smoke.spread = 24.0
	smoke.initial_velocity_min = 0.15
	smoke.initial_velocity_max = 0.42
	smoke.scale_amount_min = 0.35
	smoke.scale_amount_max = 0.85
	var puff := SphereMesh.new()
	puff.radius = 0.42
	puff.height = 0.84
	var smoke_mat := StandardMaterial3D.new()
	smoke_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smoke_mat.albedo_color = Color(0.48, 0.5, 0.54, 0.13)
	smoke_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smoke_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	puff.material = smoke_mat
	smoke.mesh = puff
	_menu_view.add_child(smoke)


func _draw_background() -> void:
	var s := _bg.size
	if s.x < 8.0 or s.y < 8.0:
		return
	var w := s.x
	var h := s.y

	# ---- procedural low-poly corridor in perspective ----
	_bg.draw_rect(Rect2(Vector2.ZERO, s), Color(0.028, 0.03, 0.034))
	var vp := Vector2(w * 0.52, h * 0.54)          # vanishing point
	var fw := w * 0.10
	var fh := h * 0.15
	var fl := vp.x - fw
	var fr := vp.x + fw
	var ft := vp.y - fh
	var fb := vp.y + fh

	_poly(PackedVector2Array([Vector2(0, h), Vector2(w, h), Vector2(fr, fb), Vector2(fl, fb)]),
		Color(0.10, 0.098, 0.094))                                  # floor
	_poly(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(fr, ft), Vector2(fl, ft)]),
		Color(0.058, 0.062, 0.070))                                 # ceiling
	_poly(PackedVector2Array([Vector2(0, 0), Vector2(fl, ft), Vector2(fl, fb), Vector2(0, h)]),
		Color(0.150, 0.153, 0.163))                                 # left wall
	_poly(PackedVector2Array([Vector2(w, 0), Vector2(fr, ft), Vector2(fr, fb), Vector2(w, h)]),
		Color(0.120, 0.124, 0.134))                                 # right wall
	_bg.draw_rect(Rect2(Vector2(fl, ft), Vector2(fr - fl, fb - ft)), Color(0.03, 0.033, 0.038))
	_bg.draw_rect(Rect2(Vector2(fl, ft), Vector2(fr - fl, fb - ft)),
		Color(0.26, 0.27, 0.29), false, 3.0)

	# floor lines receding towards the vanishing point
	for i in range(1, 15):
		var t: float = pow(i / 15.0, 2.1)
		var y: float = lerpf(h, fb, 1.0 - t)
		var xl: float = lerpf(0.0, fl, 1.0 - t)
		var xr: float = lerpf(w, fr, 1.0 - t)
		var sh: float = lerpf(0.22, 0.10, 1.0 - t)
		_bg.draw_line(Vector2(xl, y), Vector2(xr, y), Color(sh, sh * 0.98, sh * 0.94), 2.0)
	for i in range(-6, 7):
		var x_near: float = vp.x + i * w * 0.16
		var x_far: float = lerpf(vp.x, x_near, 0.12)
		_bg.draw_line(Vector2(x_near, h), Vector2(x_far, fb), Color(0.17, 0.165, 0.158), 2.0)

	# wall seams + ceiling lamp panels
	for i in range(1, 9):
		var t: float = pow(i / 9.0, 1.6)
		var xl: float = lerpf(0.0, fl, t)
		var xr: float = lerpf(w, fr, t)
		var yt: float = lerpf(0.0, ft, t)
		var yb: float = lerpf(h, fb, t)
		_bg.draw_line(Vector2(xl, yt), Vector2(xl, yb), Color(0.21, 0.215, 0.23), 2.0)
		_bg.draw_line(Vector2(xr, yt), Vector2(xr, yb), Color(0.19, 0.195, 0.21), 2.0)
		var lw: float = lerpf(w * 0.09, fw * 0.5, t)
		var ly: float = lerpf(h * 0.10, ft + 4.0, t)
		var lh: float = lerpf(9.0, 3.0, t)
		var glow: float = lerpf(0.95, 0.45, t)
		_bg.draw_rect(Rect2(Vector2(vp.x - lw, ly - lh), Vector2(lw * 2.0, lh * 2.0)),
			Color(glow, glow * 0.96, glow * 0.88))
		# soft pool of light under each lamp
		for k in range(6, 0, -1):
			var r: float = lerpf(w * 0.16, fw * 0.4, t) * (k / 6.0)
			_bg.draw_circle(Vector2(vp.x, ly + lh), r,
				Color(1.0, 0.92, 0.78, 0.02 * (1.0 - k / 7.0) * (1.0 - t)))

	# crates / cover boxes
	for b in [Vector3(0.16, 0.82, 0.17), Vector3(0.76, 0.88, 0.20),
			Vector3(0.34, 0.70, 0.10), Vector3(0.64, 0.72, 0.11)]:
		_crate(Vector2(w * b.x, h * b.y), w * b.z)

	# ---- generated photo layer on top (when the texture is available) ----
	if _bg_tex != null:
		_bg.draw_texture_rect(_bg_tex, Rect2(Vector2.ZERO, s), false, Color(1, 1, 1, 0.85))

	# ---- bodycam grade: scanlines + vignette ----
	var y2 := 0.0
	while y2 < h:
		_bg.draw_line(Vector2(0, y2), Vector2(w, y2), Color(0, 0, 0, 0.10), 1.0)
		y2 += 3.0
	for i in range(18):
		var f := i / 18.0
		var inset := Vector2(w, h) * 0.5 * f * 0.9
		_bg.draw_rect(Rect2(inset, s - inset * 2.0), Color(0, 0, 0, 0.055), false,
			maxf(2.0, h * 0.03))


func _poly(points: PackedVector2Array, color: Color) -> void:
	_bg.draw_colored_polygon(points, color)


func _crate(base: Vector2, w: float) -> void:
	var hh := w * 0.72
	var wood := Color(0.30, 0.235, 0.16)
	_poly(PackedVector2Array([base, base + Vector2(w, -hh * 0.18),
		base + Vector2(w, -hh * 0.9), base + Vector2(0, -hh * 0.72)]), wood)
	_poly(PackedVector2Array([base + Vector2(0, -hh * 0.72), base + Vector2(w, -hh * 0.9),
		base + Vector2(w * 0.62, -hh * 1.12), base + Vector2(-w * 0.35, -hh * 0.92)]),
		wood * 1.4)
	_poly(PackedVector2Array([base, base + Vector2(0, -hh * 0.72),
		base + Vector2(-w * 0.35, -hh * 0.92), base + Vector2(-w * 0.35, -hh * 0.2)]),
		wood * 0.68)


# ------------------------------------------------------------------ main page
func _build_main() -> void:
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_PASS
	margin.add_theme_constant_override("margin_left", 90)
	margin.add_theme_constant_override("margin_top", 52)
	margin.add_theme_constant_override("margin_bottom", 18)
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_root_box = VBoxContainer.new()
	_root_box.add_theme_constant_override("separation", 6)
	_root_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	_root_box.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	margin.add_child(_root_box)

	var title := Label.new()
	title.text = TITLE
	title.add_theme_font_size_override("font_size", 42)
	title.add_theme_color_override("font_color", Color(0.96, 0.97, 1.0))
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	title.add_theme_constant_override("shadow_offset_x", 3)
	title.add_theme_constant_override("shadow_offset_y", 3)
	_root_box.add_child(title)

	var sub := Label.new()
	sub.text = "1v1 PISTOL DUEL  •  BODY UNIT FOOTAGE"
	sub.add_theme_font_size_override("font_size", 15)
	sub.add_theme_color_override("font_color", Color(0.8, 0.84, 0.9, 0.9))
	_root_box.add_child(sub)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 4)
	_root_box.add_child(spacer)
	_root_box.add_child(_option("LOADOUT", GameSettings.WEAPON_NAMES, GameSettings.weapon,
		func(i: int) -> void:
			GameSettings.weapon = i
			GameSettings.save()))
	_ip_edit = LineEdit.new()
	_ip_edit.placeholder_text = "Friend IP address (default 127.0.0.1)"
	_ip_edit.text = "127.0.0.1"
	_ip_edit.custom_minimum_size = Vector2(320, 42)
	_ip_edit.add_theme_font_size_override("font_size", 18)
	_root_box.add_child(_ip_edit)
	_root_box.add_child(_button("CREATE GAME", _on_host))
	_root_box.add_child(_button("JOIN GAME", _on_join))
	_root_box.add_child(_button("SETTINGS", _on_settings))
	_network_status = _label("LISTEN SERVER  •  PORT 8910", Vector2.ZERO, 14,
		Color(0.55, 0.8, 0.92), _root_box)
	if not OS.has_feature("web"):
		_root_box.add_child(_button("QUIT", _on_quit))


# ------------------------------------------------------------------ settings
func _build_settings() -> void:
	_settings_panel = Control.new()
	_settings_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_settings_panel)
	_settings_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.025, 0.03, 0.88)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_settings_panel.add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 34)
	_settings_panel.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 26)
	margin.add_child(columns)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_child(left)

	var head := Label.new()
	head.text = "SETTINGS"
	head.add_theme_font_size_override("font_size", 32)
	left.add_child(head)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(scroll)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)

	# ---- loadout ----
	box.add_child(_section("LOADOUT"))
	box.add_child(_option("Weapon", GameSettings.WEAPON_NAMES, GameSettings.weapon,
		func(i: int) -> void:
			GameSettings.weapon = i
			GameSettings.save()))

	# ---- look ----
	box.add_child(_slider("Look sensitivity", 0.3, 3.0, 0.05, GameSettings.sensitivity,
		func(v: float) -> void:
			GameSettings.sensitivity = v,
		func(v: float) -> String: return "%.2fx" % v))
	box.add_child(_check("Invert vertical look", GameSettings.invert_look,
		func(on: bool) -> void:
			GameSettings.invert_look = on))

	# ---- crosshair ----
	box.add_child(_section("CROSSHAIR"))
	box.add_child(_option("Style", GameSettings.CROSS_NAMES, GameSettings.crosshair_style,
		func(i: int) -> void:
			GameSettings.crosshair_style = i
			_refresh_preview()))
	box.add_child(_option("Color", GameSettings.CROSS_COLOR_NAMES, GameSettings.crosshair_color,
		func(i: int) -> void:
			GameSettings.crosshair_color = i
			_refresh_preview()))
	box.add_child(_slider("Size", 0.5, 2.0, 0.05, GameSettings.crosshair_size,
		func(v: float) -> void:
			GameSettings.crosshair_size = v
			_refresh_preview(),
		func(v: float) -> String: return "%.2fx" % v))

	# ---- layout ----
	box.add_child(_section("CONTROLS LAYOUT"))
	box.add_child(_option("Handedness", GameSettings.LAYOUT_NAMES, GameSettings.layout,
		func(i: int) -> void:
			GameSettings.layout = i))
	box.add_child(_slider("Button size", 0.7, 1.4, 0.05, GameSettings.button_scale,
		func(v: float) -> void:
			GameSettings.button_scale = v
			if _pad != null:
				_pad.apply_settings(),
		func(v: float) -> String: return "%.2fx" % v))
	box.add_child(_button("BUTTON LAYOUT…", _on_edit_layout))

	# ---- video ----
	box.add_child(_section("VIDEO"))
	box.add_child(_option("Quality", GameSettings.QUALITY_NAMES, GameSettings.quality,
		func(i: int) -> void:
			GameSettings.quality = i))
	box.add_child(_slider("Bodycam effect", 0.0, 1.5, 0.05, GameSettings.bodycam_strength,
		func(v: float) -> void:
			GameSettings.bodycam_strength = v,
		func(v: float) -> String: return "%d%%" % int(v * 100.0)))

	var note := Label.new()
	note.text = "30 FPS is held automatically: if the frame rate drops, the 3D\nresolution is lowered one step at a time."
	note.add_theme_font_size_override("font_size", 14)
	note.add_theme_color_override("font_color", Color(0.75, 0.8, 0.86, 0.8))
	box.add_child(note)

	left.add_child(_button("BACK", _on_back))

	# ---- right column: live crosshair preview ----
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(300, 0)
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_child(right)

	_preview = Control.new()
	_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview.custom_minimum_size = Vector2(300, 240)
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview.draw.connect(_draw_preview)
	right.add_child(_preview)


func _refresh_preview() -> void:
	if _preview != null:
		_preview.queue_redraw()


func _draw_preview() -> void:
	var r := Rect2(Vector2.ZERO, _preview.size)
	_preview.draw_rect(r, Color(0.06, 0.07, 0.08, 0.92))
	_preview.draw_rect(r, Color(1, 1, 1, 0.18), false, 2.0)
	Crosshair.draw_on(_preview, r.size * 0.5)
	_preview.draw_string(ThemeDB.fallback_font, Vector2(12, 26), "CROSSHAIR PREVIEW",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.55))


# ------------------------------------------------------------------ widgets
func _label(text: String, pos: Vector2, fsize: int, color: Color, parent: Node) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fsize)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	l.position = pos
	return l


func _button(text: String, handler: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 22)
	b.custom_minimum_size = Vector2(320, 50)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	b.focus_mode = Control.FOCUS_ALL
	b.pressed.connect(handler)
	return b


func _section(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", Color(1.0, 0.6, 0.35))
	return l


func _slider(text: String, minv: float, maxv: float, step: float, value: float,
		on_change: Callable, fmt: Callable) -> Control:
	var row := VBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var head := Label.new()
	head.text = "%s:  %s" % [text, fmt.call(value)]
	head.add_theme_font_size_override("font_size", 18)
	row.add_child(head)
	var s := HSlider.new()
	s.min_value = minv
	s.max_value = maxv
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(240, 40)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.value_changed.connect(func(v: float) -> void:
		head.text = "%s:  %s" % [text, fmt.call(v)]
		on_change.call(v))
	row.add_child(s)
	return row


func _option(text: String, names: Array, selected: int, on_change: Callable) -> Control:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 18)
	l.custom_minimum_size = Vector2(170, 0)
	row.add_child(l)
	var o := OptionButton.new()
	o.add_theme_font_size_override("font_size", 18)
	for i in range(names.size()):
		o.add_item(String(names[i]), i)
	o.selected = clampi(selected, 0, names.size() - 1)
	o.custom_minimum_size = Vector2(230, 52)
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	o.item_selected.connect(func(i: int) -> void: on_change.call(i))
	row.add_child(o)
	return row


func _check(text: String, value: bool, on_change: Callable) -> Control:
	var c := CheckButton.new()
	c.text = text
	c.button_pressed = value
	c.add_theme_font_size_override("font_size", 18)
	c.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	c.toggled.connect(func(on: bool) -> void: on_change.call(on))
	return c


# ------------------------------------------------------------------ actions
func _on_play() -> void:
	_on_host()

func _on_host() -> void:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(8910, 1)
	if err != OK:
		_network_status.text = "CREATE FAILED: %s" % error_string(err)
		return
	multiplayer.multiplayer_peer = peer
	GameSettings.save()
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _on_join() -> void:
	var address := "127.0.0.1"
	if _ip_edit != null and _ip_edit.text.strip_edges() != "":
		address = _ip_edit.text.strip_edges()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, 8910)
	if err != OK:
		_network_status.text = "JOIN FAILED: %s" % error_string(err)
		return
	multiplayer.multiplayer_peer = peer
	_network_status.text = "CONNECTING TO %s…" % address
	if multiplayer.connected_to_server.is_connected(_on_connected_to_server) == false:
		multiplayer.connected_to_server.connect(_on_connected_to_server)
	if multiplayer.connection_failed.is_connected(_on_connection_failed) == false:
		multiplayer.connection_failed.connect(_on_connection_failed)

func _on_connected_to_server() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _on_connection_failed() -> void:
	_network_status.text = "CONNECTION FAILED  •  CHECK IP / PORT"


func _on_settings() -> void:
	# Built lazily, while visible, so every anchor resolves against the real
	# screen size.
	if _settings_panel == null:
		_build_settings()
	_settings_panel.visible = true
	_root_box.get_parent().visible = false
	_refresh_preview()


# ------------------------------------------------------------ layout editor
## Drag-and-drop editor for the on-screen controls: every widget can be moved
## anywhere on the screen and the positions are stored per screen fraction.
func _on_edit_layout() -> void:
	if _layout_page == null:
		_build_layout_page()
	_settings_panel.visible = false
	_layout_page.visible = true
	_pad.apply_settings()


func _build_layout_page() -> void:
	_layout_page = Control.new()
	_layout_page.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_layout_page)
	_layout_page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.025, 0.03, 0.82)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layout_page.add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_pad = MobileControls.new()
	_pad.edit_mode = true
	_layout_page.add_child(_pad)

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 14)
	_layout_page.add_child(bar)
	bar.position = Vector2(26, 22)

	var hint := Label.new()
	hint.text = "Drag any control to move it"
	hint.add_theme_font_size_override("font_size", 20)
	hint.add_theme_color_override("font_color", Color(1.0, 0.8, 0.45))
	bar.add_child(hint)

	var reset := Button.new()
	reset.text = "RESET"
	reset.add_theme_font_size_override("font_size", 20)
	reset.custom_minimum_size = Vector2(150, 56)
	reset.pressed.connect(func() -> void: _pad.reset_layout())
	bar.add_child(reset)

	var done := Button.new()
	done.text = "DONE"
	done.add_theme_font_size_override("font_size", 20)
	done.custom_minimum_size = Vector2(150, 56)
	done.pressed.connect(_on_layout_done)
	bar.add_child(done)


func _on_layout_done() -> void:
	_pad.store_layout()
	GameSettings.save()
	_layout_page.visible = false
	_settings_panel.visible = true


func _on_back() -> void:
	GameSettings.save()
	_settings_panel.visible = false
	_root_box.get_parent().visible = true


func _on_quit() -> void:
	GameSettings.save()
	get_tree().quit()


func _process(delta: float) -> void:
	_blink = fmod(_blink + delta, 1.0)
	_clock += delta
	_rec_dot.queue_redraw()
	var total := int(_clock)
	_time_label.text = "%02d:%02d:%02d" % [total / 3600, (total / 60) % 60, total % 60]
	# Subtle sensor drift so the still background feels like live footage.
	if _bg != null:
		_bg.position = Vector2(sin(_clock * 0.7) * 3.0, cos(_clock * 0.53) * 2.0)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_WM_GO_BACK_REQUEST:
		GameSettings.save()
