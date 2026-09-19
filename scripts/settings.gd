extends Node
class_name GameSettings

## Player preferences shared by the menu, the HUD, the touch pad and the game
## director. Values live in static vars so any script can read them without an
## autoload, and they are persisted to user://settings.cfg.

const PATH := "user://settings.cfg"

# ---- quality ----
const QUALITY_LOW := 0
const QUALITY_MEDIUM := 1
const QUALITY_HIGH := 2
const QUALITY_NAMES := ["LOW (fastest)", "MEDIUM", "HIGH"]

# ---- crosshair ----
const CROSS_CROSS := 0
const CROSS_DOT := 1
const CROSS_CIRCLE := 2
const CROSS_T := 3
const CROSS_NONE := 4
const CROSS_NAMES := ["Cross", "Dot", "Circle + dot", "T-shape", "Hidden"]
const CROSS_COLORS := [
	Color(1, 1, 1),
	Color(0.3, 1.0, 0.45),
	Color(1.0, 0.3, 0.28),
	Color(1.0, 0.85, 0.25),
	Color(0.35, 0.8, 1.0),
]
const CROSS_COLOR_NAMES := ["White", "Green", "Red", "Amber", "Cyan"]

# ---- layout ----
const LAYOUT_RIGHT := 0  # stick left, FIRE right (default)
const LAYOUT_LEFT := 1   # mirrored for left-handed players
const LAYOUT_NAMES := ["Right-handed", "Left-handed"]

# Weapons available in a match. The choice is local and is replicated to the opponent.
const WEAPON_PISTOL := 0
const WEAPON_M4 := 1
const WEAPON_NAMES := ["PBR PISTOL", "M4A1"]

static var sensitivity := 1.0        # 0.3 .. 3.0 multiplier
static var invert_look := false
static var crosshair_style := CROSS_CROSS
static var crosshair_size := 1.0     # 0.5 .. 2.0
static var crosshair_color := 0
static var layout := LAYOUT_RIGHT
static var button_scale := 1.0       # 0.7 .. 1.4
static var quality := QUALITY_MEDIUM
static var bodycam_strength := 1.0   # 0.0 .. 1.5
static var weapon := WEAPON_PISTOL

## Custom on-screen widget positions, normalised to the screen (0..1).
## A negative value means "use the default place for this widget".
static var widget_positions := {
	"stick": Vector2(-1.0, -1.0),
	"fire": Vector2(-1.0, -1.0),
	"reload": Vector2(-1.0, -1.0),
	"crouch": Vector2(-1.0, -1.0),
	"weapon": Vector2(-1.0, -1.0),
}

static var _loaded := false


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	sensitivity = clampf(float(cfg.get_value("input", "sensitivity", sensitivity)), 0.3, 3.0)
	invert_look = bool(cfg.get_value("input", "invert_look", invert_look))
	layout = int(cfg.get_value("input", "layout", layout))
	button_scale = clampf(float(cfg.get_value("input", "button_scale", button_scale)), 0.7, 1.4)
	crosshair_style = int(cfg.get_value("hud", "crosshair_style", crosshair_style))
	crosshair_size = clampf(float(cfg.get_value("hud", "crosshair_size", crosshair_size)), 0.5, 2.0)
	crosshair_color = int(cfg.get_value("hud", "crosshair_color", crosshair_color))
	quality = clampi(int(cfg.get_value("video", "quality", quality)), 0, 2)
	weapon = clampi(int(cfg.get_value("game", "weapon", weapon)), 0, WEAPON_NAMES.size() - 1)
	bodycam_strength = clampf(float(cfg.get_value("video", "bodycam", bodycam_strength)), 0.0, 1.5)
	for key in widget_positions.keys():
		var stored = cfg.get_value("pad", String(key), widget_positions[key])
		if stored is Vector2:
			widget_positions[key] = stored


static func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("input", "sensitivity", sensitivity)
	cfg.set_value("input", "invert_look", invert_look)
	cfg.set_value("input", "layout", layout)
	cfg.set_value("input", "button_scale", button_scale)
	cfg.set_value("hud", "crosshair_style", crosshair_style)
	cfg.set_value("hud", "crosshair_size", crosshair_size)
	cfg.set_value("hud", "crosshair_color", crosshair_color)
	cfg.set_value("video", "quality", quality)
	cfg.set_value("video", "bodycam", bodycam_strength)
	cfg.set_value("game", "weapon", weapon)
	for key in widget_positions.keys():
		cfg.set_value("pad", String(key), widget_positions[key])
	cfg.save(PATH)


## Normalised position of an on-screen widget ("stick", "fire", "reload",
## "crouch"). Negative components mean the widget uses its default spot.
static func widget_position(widget: String) -> Vector2:
	ensure_loaded()
	if widget_positions.has(widget):
		return widget_positions[widget]
	return Vector2(-1.0, -1.0)


static func set_widget_position(widget: String, norm: Vector2) -> void:
	widget_positions[widget] = Vector2(clampf(norm.x, 0.02, 0.98), clampf(norm.y, 0.04, 0.96))


static func reset_widget_positions() -> void:
	for key in widget_positions.keys():
		widget_positions[key] = Vector2(-1.0, -1.0)


static func cross_color() -> Color:
	var i := clampi(crosshair_color, 0, CROSS_COLORS.size() - 1)
	return CROSS_COLORS[i]


## 3D render scale used inside the SubViewport (1.0 = native).
static func render_scale() -> float:
	match quality:
		QUALITY_LOW:
			return 0.55
		QUALITY_HIGH:
			return 1.0
		_:
			return 0.8


static func shadows_enabled() -> bool:
	return quality == QUALITY_HIGH
