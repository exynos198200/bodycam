extends SubViewportContainer
class_name BodycamOverlay

## Hosts the 3D SubViewport and runs the bodycam post-processing shader on the
## rendered frame (fisheye, chromatic aberration, grain, scanlines, glitches,
## vignette). Rendering the world into a SubViewport is what makes screen-space
## post processing possible on the Compatibility renderer.
##
## `stretch_shrink = 2` renders the 3D scene at half resolution and upscales it,
## which is the single biggest performance win on low-end Android devices.

@export var player_path: NodePath

var _mat: ShaderMaterial
var _fx = null  # CameraEffects (untyped: cross-script dynamic access)
var _shake := 0.0


func _ready() -> void:
	GameSettings.ensure_loaded()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	stretch = true
	# The container is always 1:1 now; the 3D resolution is controlled by
	# the SubViewport scaling so the HUD and the post FX stay crisp.
	stretch_shrink = 1
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/bodycam.gdshader")
	_mat.set_shader_parameter("grain_tex", load("res://textures/sensor_noise.png"))
	material = _mat
	set_strength(GameSettings.bodycam_strength)


## Scales every bodycam artefact at once (menu slider "Bodycam effect").
func set_strength(k: float) -> void:
	if _mat == null:
		return
	k = clampf(k, 0.0, 1.5)
	_mat.set_shader_parameter("noise_amount", 0.055 * k)
	_mat.set_shader_parameter("scanline_amount", 0.05 * k)
	_mat.set_shader_parameter("glitch_amount", 0.16 * k)
	_mat.set_shader_parameter("chroma", 0.0035 * k)
	_mat.set_shader_parameter("fisheye", 0.26 * k)
	_mat.set_shader_parameter("vignette_amount", 0.55 + 0.45 * k)


func bind_player(player) -> void:
	if player != null:
		_fx = player.get_node_or_null("Head/Camera3D/CameraEffects")


func _process(delta: float) -> void:
	if _fx == null and player_path != NodePath():
		bind_player(get_node_or_null(player_path))
	var target := 0.0
	if _fx != null and _fx.has_method("get_shake"):
		target = float(_fx.get_shake())
	_shake = lerpf(_shake, target, clampf(delta * 8.0, 0.0, 1.0))
	if _mat != null:
		_mat.set_shader_parameter("shake", _shake)
