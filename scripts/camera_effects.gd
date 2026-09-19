extends Node
class_name CameraEffects

## Bodycam camera rig: head bob, breathing sway, trauma based shake, recoil
## kick, dynamic FOV and slow handheld drift. Everything is applied as a local
## offset on the Camera3D so the player's aim direction stays exact.

const BASE_FOV := 96.0
const SPRINT_FOV := 101.0
const BOB_FREQ := 8.4
const BOB_AMP := 0.028
const SWAY_AMP := 0.012

var _time := 0.0
var _trauma := 0.0
var _speed_ratio := 0.0
var _crouching := false
var _recoil := Vector2.ZERO
var _recoil_vel := Vector2.ZERO
var _dead := false
var _death_t := 0.0
var _cam: Camera3D
var _base_pos := Vector3.ZERO


func _ready() -> void:
	_cam = get_parent() as Camera3D
	if _cam != null:
		_base_pos = _cam.transform.origin
		_cam.fov = BASE_FOV
		_cam.near = 0.05
		_cam.far = 60.0


func set_motion(speed_ratio: float, crouching: bool) -> void:
	_speed_ratio = clampf(speed_ratio, 0.0, 1.4)
	_crouching = crouching


func add_shake(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.6)


func add_recoil(kick: Vector2) -> void:
	_recoil_vel += Vector2(kick.x, kick.y) * 26.0


func start_death() -> void:
	_dead = true
	_death_t = 0.0


func get_shake() -> float:
	return _trauma


func _process(delta: float) -> void:
	if _cam == null:
		return
	_time += delta

	_recoil_vel -= _recoil * 220.0 * delta
	_recoil_vel *= 1.0 - clampf(12.0 * delta, 0.0, 0.95)
	_recoil += _recoil_vel * delta

	_trauma = maxf(0.0, _trauma - delta * 1.7)
	var shake := _trauma * _trauma

	var amp: float = BOB_AMP * (0.45 if _crouching else 1.0)
	var bob_y := sin(_time * BOB_FREQ) * amp * _speed_ratio
	var bob_x := cos(_time * BOB_FREQ * 0.5) * amp * 1.3 * _speed_ratio
	var drift_x := sin(_time * 0.7) * SWAY_AMP + sin(_time * 1.9) * SWAY_AMP * 0.4
	var drift_y := cos(_time * 0.53) * SWAY_AMP * 0.8

	var shake_off := Vector3(
		randf_range(-1.0, 1.0) * 0.035 * shake,
		randf_range(-1.0, 1.0) * 0.035 * shake,
		randf_range(-1.0, 1.0) * 0.012 * shake)

	var pos := _base_pos + Vector3(bob_x + drift_x, bob_y + drift_y, 0.0) + shake_off

	var roll := sin(_time * BOB_FREQ * 0.5) * 0.013 * _speed_ratio
	roll += sin(_time * 0.9) * 0.006
	roll += randf_range(-1.0, 1.0) * 0.03 * shake
	var pitch := _recoil.y + randf_range(-1.0, 1.0) * 0.02 * shake
	var yaw := _recoil.x + randf_range(-1.0, 1.0) * 0.02 * shake

	if _dead:
		_death_t += delta
		var k := clampf(_death_t / 1.4, 0.0, 1.0)
		roll += k * 1.25
		pos.y -= k * 0.9
		pitch -= k * 0.35

	_cam.transform.origin = pos
	_cam.rotation = Vector3(pitch, yaw, roll)

	var target_fov := BASE_FOV + (SPRINT_FOV - BASE_FOV) * clampf(_speed_ratio, 0.0, 1.0)
	target_fov += shake * 2.5
	_cam.fov = lerpf(_cam.fov, target_fov, clampf(delta * 6.0, 0.0, 1.0))
