extends Node3D
class_name Weapon

## Player pistol: hitscan fire, magazine/ammo/reload, fire rate, spread,
## recoil, slide animation, muzzle flash, shell ejection and impact effects.

signal fired(recoil: Vector2)
signal ammo_changed(in_mag: int, reserve: int)
signal reload_started(duration: float)
signal reload_finished
signal weapon_changed(kind: int, display_name: String)

const PISTOL := 0
const M4 := 1
const PISTOL_MAG := 12
const PISTOL_RESERVE := 48
const PISTOL_DAMAGE := 27.0
const PISTOL_INTERVAL := 0.22
const PISTOL_RELOAD := 1.05
const M4_MAG := 30
const M4_RESERVE := 90
const M4_DAMAGE := 19.0
const M4_INTERVAL := 0.105
const M4_RELOAD := 1.55
const RANGE := 75.0
const SPREAD_BASE := 0.006
const SPREAD_PER_SHOT := 0.011
const SPREAD_MAX := 0.055

var weapon_kind := PISTOL
var mag_size := PISTOL_MAG
var damage := PISTOL_DAMAGE
var fire_interval := PISTOL_INTERVAL
var reload_time := PISTOL_RELOAD
var in_mag := PISTOL_MAG
var reserve := PISTOL_RESERVE
var reloading := false
var _cooldown := 0.0
var _spread := 0.0
var _owner_node = null
var _camera: Camera3D = null
var _slide: Node3D = null
var _slide_rest := Vector3.ZERO
var _active_model: Node3D = null
var _slide_kick := 0.0
var _rest_pos := Vector3.ZERO
var _rest_rot := Vector3.ZERO
var _kick := 0.0
var _reload_t := 0.0

@onready var muzzle: Node3D = $Muzzle
@onready var flash_light: OmniLight3D = $Muzzle/FlashLight
@onready var flash_mesh: MeshInstance3D = $Muzzle/FlashMesh
@onready var shot_player: AudioStreamPlayer3D = $ShotPlayer
@onready var reload_player: AudioStreamPlayer3D = $ReloadPlayer
@onready var dry_player: AudioStreamPlayer3D = $DryPlayer
@onready var model_root: Node3D = $Model
@onready var pistol_model: Node3D = $Model/Pistol
@onready var m4_model: Node3D = $Model/M4A1


func _ready() -> void:
	_rest_pos = transform.origin
	_rest_rot = rotation
	shot_player.stream = load("res://audio/gunshot.wav")
	reload_player.stream = load("res://audio/reload.wav")
	dry_player.stream = load("res://audio/dry_fire.wav")
	flash_light.visible = false
	flash_mesh.visible = false
	_setup_flash_mesh()
	set_weapon(GameSettings.weapon, false)
	ammo_changed.emit(in_mag, reserve)


func setup(owner_node, camera: Camera3D, _shooter_layer: int = 1) -> void:
	_owner_node = owner_node
	_camera = camera


func _setup_flash_mesh() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(0.28, 0.28)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.02
	var tex = load("res://textures/muzzle_flash.png")
	if tex != null:
		mat.albedo_texture = tex
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	flash_mesh.mesh = quad
	flash_mesh.material_override = mat
	flash_light.light_color = Color(1.0, 0.9, 0.72)
	flash_light.light_energy = 3.2
	flash_light.omni_range = 4.5
	flash_light.shadow_enabled = false


static func _find_node(root: Node, target_name: String) -> Node3D:
	if root == null:
		return null
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if String(n.name) == target_name and n is Node3D:
			return n as Node3D
		for c in n.get_children():
			stack.push_back(c)
	return null


func _process(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	_spread = maxf(0.0, _spread - delta * 0.05)
	_kick = maxf(0.0, _kick - delta * 5.5)
	_slide_kick = maxf(0.0, _slide_kick - delta * 7.0)

	var t := Time.get_ticks_msec()
	var sway := Vector3(sin(t * 0.0011) * 0.0025, cos(t * 0.0009) * 0.0022, 0.0)
	var reload_dip := 0.0
	var reload_roll := 0.0
	if reloading:
		_reload_t += delta
		var k: float = sin(clampf(_reload_t / reload_time, 0.0, 1.0) * PI)
		reload_dip = -0.075 * k
		reload_roll = 0.55 * k
	transform.origin = _rest_pos + sway + Vector3(0.0, reload_dip - _kick * 0.012, _kick * 0.055)
	rotation = _rest_rot + Vector3(_kick * 0.16, 0.0, reload_roll)

	if _slide != null:
		_slide.transform.origin = _slide_rest + Vector3(0, 0, _slide_kick * 0.045)


func switch_weapon() -> void:
	set_weapon(M4 if weapon_kind == PISTOL else PISTOL, true)

func set_weapon(kind: int, reset_ammo: bool = true) -> void:
	weapon_kind = M4 if kind == M4 else PISTOL
	var is_m4 := weapon_kind == M4
	mag_size = M4_MAG if is_m4 else PISTOL_MAG
	reserve = M4_RESERVE if is_m4 else PISTOL_RESERVE
	damage = M4_DAMAGE if is_m4 else PISTOL_DAMAGE
	fire_interval = M4_INTERVAL if is_m4 else PISTOL_INTERVAL
	reload_time = M4_RELOAD if is_m4 else PISTOL_RELOAD
	if pistol_model != null:
		pistol_model.visible = not is_m4
	if m4_model != null:
		m4_model.visible = is_m4
		if is_m4:
			ModelMaterials.apply_m4(m4_model)
	_active_model = m4_model if is_m4 else pistol_model
	_slide = _find_node(_active_model, "Bolt")
	if _slide == null:
		_slide = _find_node(_active_model, "Slide")
	if _slide != null:
		_slide_rest = _slide.transform.origin
	if reset_ammo:
		in_mag = mag_size
		reloading = false
		_spread = 0.0
	ammo_changed.emit(in_mag, reserve)
	weapon_changed.emit(weapon_kind, "M4A1" if is_m4 else "PBR PISTOL")


func try_fire() -> bool:
	if reloading or _cooldown > 0.0:
		return false
	if in_mag <= 0:
		if not dry_player.playing:
			dry_player.play()
			try_reload()
		return false
	_cooldown = fire_interval
	in_mag -= 1
	ammo_changed.emit(in_mag, reserve)
	_spread = minf(_spread + SPREAD_PER_SHOT, SPREAD_MAX)
	_kick = 1.0
	_slide_kick = 1.0

	shot_player.pitch_scale = randf_range(0.96, 1.05)
	shot_player.play()
	_flash()
	_eject_shell()
	_do_hitscan()

	var recoil := Vector2(randf_range(-0.004, 0.004), 0.016 + randf_range(0.0, 0.006))
	fired.emit(recoil)
	return true


func try_reload() -> bool:
	if reloading or in_mag >= mag_size or reserve <= 0:
		return false
	reloading = true
	_reload_t = 0.0
	reload_player.play()
	reload_started.emit(reload_time)
	await get_tree().create_timer(reload_time).timeout
	if not is_inside_tree():
		return false
	var need: int = mag_size - in_mag
	var take: int = mini(need, reserve)
	in_mag += take
	reserve -= take
	reloading = false
	_spread = 0.0
	ammo_changed.emit(in_mag, reserve)
	reload_finished.emit()
	return true


func _flash() -> void:
	flash_light.visible = true
	flash_mesh.visible = true
	flash_mesh.rotation.z = randf_range(0.0, TAU)
	var s := randf_range(0.85, 1.3)
	flash_mesh.scale = Vector3(s, s * randf_range(0.7, 1.0), 1.0)
	get_tree().create_timer(0.04).timeout.connect(_hide_flash)


func _hide_flash() -> void:
	if is_instance_valid(flash_light):
		flash_light.visible = false
	if is_instance_valid(flash_mesh):
		flash_mesh.visible = false


func _eject_shell() -> void:
	# Physics-driven shells are skipped on mobile: a RigidBody3D plus mesh,
	# material and collision shape per shot is pure overhead on a low-end phone.
	if OS.has_feature("mobile"):
		return
	var shell := RigidBody3D.new()
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.012, 0.012, 0.028)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.78, 0.62, 0.25)
	mat.metallic = 0.9
	mat.roughness = 0.35
	mi.mesh = box
	mi.material_override = mat
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box.size
	cs.shape = shape
	shell.add_child(mi)
	shell.add_child(cs)
	shell.collision_layer = 8
	shell.collision_mask = 1
	shell.mass = 0.02
	get_tree().current_scene.add_child(shell)
	shell.global_position = muzzle.global_position + Vector3(0, -0.05, 0)
	var b := global_transform.basis
	shell.apply_impulse((b.x * 0.9 + b.y * 0.7 + b.z * 0.2).normalized() * 0.035)
	shell.angular_velocity = Vector3(randf_range(-9, 9), randf_range(-9, 9), randf_range(-9, 9))
	get_tree().create_timer(3.0).timeout.connect(func() -> void:
		if is_instance_valid(shell):
			shell.queue_free())


func _do_hitscan() -> void:
	if _camera == null:
		return
	var space := _camera.get_world_3d().direct_space_state
	var from := _camera.global_position
	var dir := -_camera.global_transform.basis.z
	dir = dir.rotated(Vector3.UP, randf_range(-1.0, 1.0) * (SPREAD_BASE + _spread))
	dir = dir.rotated(_camera.global_transform.basis.x.normalized(),
		randf_range(-1.0, 1.0) * (SPREAD_BASE + _spread))
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * RANGE, 1 | 2)
	if _owner_node is CollisionObject3D:
		q.exclude = [(_owner_node as CollisionObject3D).get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return
	var collider: Object = hit.get("collider")
	var point: Vector3 = hit.get("position", from)
	var normal: Vector3 = hit.get("normal", Vector3.UP)
	var target := _resolve_damageable(collider)
	if target != null:
		target.take_damage(damage, from)
		Effects.spawn_blood(get_tree().current_scene, point, normal)
	else:
		Effects.spawn_impact(get_tree().current_scene, point, normal)


static func _resolve_damageable(collider: Object) -> Node:
	var node := collider as Node
	while node != null:
		if node.has_method("take_damage"):
			return node
		node = node.get_parent()
	return null
