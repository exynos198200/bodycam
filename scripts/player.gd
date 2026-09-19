extends CharacterBody3D
class_name Player

## First person player: touch/keyboard movement, crouch, bodycam camera rig
## and a pistol held in front of the camera.

signal health_changed(current: float, maximum: float)
signal died
signal hit_taken

const SPEED_WALK := 4.1
const SPEED_CROUCH := 2.0
const ACCEL := 14.0
const DEACCEL := 16.0
const GRAVITY := 18.0
const LOOK_SENS_TOUCH := 0.0032
const LOOK_SENS_MOUSE := 0.0022
const PITCH_LIMIT := 1.4311
const STAND_HEIGHT := 1.75
const CROUCH_HEIGHT := 1.15
const HEAD_STAND := 1.58
const HEAD_CROUCH := 1.02

@export var max_health: float = 100.0

var health: float = 100.0
var is_dead := false
var crouching := false
var controls = null                 # MobileControls, injected by game.gd
var _yaw := 0.0
var _pitch := 0.0
var _step_accum := 0.0
var _mouse_captured := false
var _net_pos := Vector3.ZERO
var _net_yaw := 0.0
var _net_pitch := 0.0
var _net_health := 100.0
var _net_dead := false
var _net_weapon := GameSettings.WEAPON_PISTOL
var _net_t := 0.0

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var fx = $Head/Camera3D/CameraEffects
@onready var weapon = $Head/Camera3D/WeaponHolder/Weapon
@onready var body_shape: CollisionShape3D = $CollisionShape3D
@onready var step_player: AudioStreamPlayer3D = $StepPlayer
@onready var voice_player: AudioStreamPlayer3D = $VoicePlayer
@onready var character_visual: Node3D = $CharacterVisual
@onready var rig: RigAnimation = $CharacterVisual
@onready var character_model: Node3D = $CharacterVisual/Character
@onready var remote_pistol: Node3D = $CharacterVisual/RemotePistol
@onready var remote_m4: Node3D = $CharacterVisual/RemoteM4A1


func _ready() -> void:
	GameSettings.ensure_loaded()
	health = max_health
	_yaw = rotation.y
	step_player.stream = load("res://audio/footstep.wav")
	voice_player.stream = load("res://audio/hurt.wav")
	weapon.setup(self, camera, 1)
	weapon.set_weapon(GameSettings.weapon, false)
	weapon.fired.connect(_on_weapon_fired)
	weapon.weapon_changed.connect(_on_weapon_changed)
	ModelMaterials.apply_character(character_model)
	character_visual.visible = not is_multiplayer_authority()
	ModelMaterials.apply_m4(remote_m4)
	_on_weapon_changed(weapon.weapon_kind, "")
	_net_pos = global_position
	_net_yaw = rotation.y
	health_changed.emit(health, max_health)
	if not DisplayServer.is_touchscreen_available() and OS.has_feature("pc"):
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		_mouse_captured = true



func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority() or is_dead:
		return
	if event is InputEventMouseMotion and _mouse_captured:
		var mm := event as InputEventMouseMotion
		var ms := LOOK_SENS_MOUSE * GameSettings.sensitivity
		var minv := -1.0 if GameSettings.invert_look else 1.0
		_apply_look(-mm.relative.x * ms, -mm.relative.y * ms * minv)
	elif event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and k.keycode == KEY_ESCAPE and _mouse_captured:
			_mouse_captured = false
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and OS.has_feature("pc") and not _mouse_captured \
				and not DisplayServer.is_touchscreen_available():
			_mouse_captured = true
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


## Spawn helper: keeps the look state in sync with the placed transform.
func teleport(pos: Vector3, yaw: float) -> void:
	global_position = pos
	_yaw = yaw
	rotation.y = yaw
	velocity = Vector3.ZERO


func _apply_look(dyaw: float, dpitch: float) -> void:
	_yaw = wrapf(_yaw + dyaw, -PI, PI)
	_pitch = clampf(_pitch + dpitch, -PITCH_LIMIT, PITCH_LIMIT)


func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		global_position = global_position.lerp(_net_pos, clampf(delta * 12.0, 0.0, 1.0))
		rotation.y = lerp_angle(rotation.y, _net_yaw, clampf(delta * 12.0, 0.0, 1.0))
		head.rotation.x = lerpf(head.rotation.x, _net_pitch, clampf(delta * 12.0, 0.0, 1.0))
		update_rig_motion(delta)
		return
	if controls == null:
		# Self-healing binding: never depend on the director alone, or a
		# failure elsewhere in setup leaves the on-screen pad dead.
		controls = get_tree().get_first_node_in_group("mobile_controls")
	if is_dead:
		velocity = velocity.move_toward(Vector3.ZERO, 30.0 * delta)
		move_and_slide()
		return

	# ---------------- look ----------------
	if controls != null:
		var look: Vector2 = controls.consume_look()
		if look != Vector2.ZERO:
			var sens := LOOK_SENS_TOUCH * GameSettings.sensitivity
			var inv := -1.0 if GameSettings.invert_look else 1.0
			_apply_look(-look.x * sens, -look.y * sens * inv)
	var kb_look := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if kb_look != Vector2.ZERO:
		_apply_look(-kb_look.x * 2.2 * delta, -kb_look.y * 1.8 * delta)
	rotation.y = _yaw
	head.rotation.x = _pitch

	# ---------------- movement ----------------
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if controls != null:
		var stick: Vector2 = controls.move_vector
		if stick.length() > 0.08:
			input_dir = stick
	input_dir = input_dir.limit_length(1.0)

	var want_crouch := Input.is_action_pressed("crouch")
	if controls != null and controls.crouch_held:
		want_crouch = true
	_set_crouch(want_crouch, delta)

	var dir := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	var target_speed: float = SPEED_CROUCH if crouching else SPEED_WALK
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if dir.length() > 0.01:
		horizontal = horizontal.move_toward(dir * target_speed * input_dir.length(), ACCEL * delta)
	else:
		horizontal = horizontal.move_toward(Vector3.ZERO, DEACCEL * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = -0.1
	move_and_slide()

	# ---------------- footsteps + bodycam motion ----------------
	var speed_flat := Vector3(velocity.x, 0.0, velocity.z).length()
	if fx != null:
		fx.set_motion(speed_flat / SPEED_WALK, crouching)
	update_rig_motion(delta)
	if speed_flat > 0.6 and is_on_floor():
		_step_accum += speed_flat * delta
		var step_len: float = 2.6 if crouching else 1.9
		if _step_accum >= step_len:
			_step_accum = 0.0
			step_player.pitch_scale = randf_range(0.9, 1.12)
			step_player.play()
			if fx != null:
				fx.add_shake(0.06)
	else:
		_step_accum = 0.0

	# ---------------- weapon ----------------
	# Godot emulates mouse clicks from touches, so on Android the "fire"
	# action fired on ANY tap (joystick, empty screen space...). On mobile
	# the on-screen FIRE button is therefore the only source of fire input.
	var fire_held: bool = controls != null and controls.fire_held
	if not OS.has_feature("mobile"):
		fire_held = fire_held or Input.is_action_pressed("fire")
	if fire_held:
		weapon.try_fire()
	if Input.is_action_just_pressed("reload"):
		weapon.try_reload()
	if Input.is_action_just_pressed("switch_weapon"):
		switch_weapon()
	_net_t -= delta
	if _net_t <= 0.0:
		_net_t = 0.07
		rpc("net_state", global_position, rotation.y, head.rotation.x, health, is_dead, weapon.weapon_kind)


func _set_crouch(want: bool, delta: float) -> void:
	if want != crouching and (want or not _blocked_above()):
		crouching = want
	_lerp_body(delta)


func _lerp_body(delta: float) -> void:
	var capsule := body_shape.shape as CapsuleShape3D
	var target_h: float = CROUCH_HEIGHT if crouching else STAND_HEIGHT
	var target_head: float = HEAD_CROUCH if crouching else HEAD_STAND
	capsule.height = lerpf(capsule.height, target_h, clampf(delta * 10.0, 0.0, 1.0))
	body_shape.transform.origin.y = capsule.height * 0.5
	head.transform.origin.y = lerpf(head.transform.origin.y, target_head, clampf(delta * 10.0, 0.0, 1.0))


func _blocked_above() -> bool:
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3(0, 0.8, 0)
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(0, 1.1, 0), 1)
	q.exclude = [get_rid()]
	return not space.intersect_ray(q).is_empty()


func _on_weapon_fired(recoil: Vector2) -> void:
	if rig != null:
		rig.add_recoil()
	_pitch = clampf(_pitch + recoil.y, -PITCH_LIMIT, PITCH_LIMIT)
	_yaw += recoil.x
	if fx != null:
		fx.add_shake(0.55)
		fx.add_recoil(recoil)


func eye_position() -> Vector3:
	return camera.global_position


func take_damage(amount: float, from_pos: Vector3 = Vector3.ZERO) -> void:
	if not is_multiplayer_authority():
		rpc_id(get_multiplayer_authority(), "remote_damage", amount, from_pos)
		return
	_apply_damage(amount, from_pos)

@rpc("any_peer", "reliable")
func remote_damage(amount: float, from_pos: Vector3) -> void:
	if multiplayer.get_remote_sender_id() != get_multiplayer_authority():
		return
	_apply_damage(amount, from_pos)

func _apply_damage(amount: float, from_pos: Vector3 = Vector3.ZERO) -> void:
	if is_dead:
		return
	health = maxf(0.0, health - amount)
	health_changed.emit(health, max_health)
	hit_taken.emit()
	if fx != null:
		fx.add_shake(1.0)
		var dir := 1.0
		if from_pos != Vector3.ZERO:
			var local := to_local(from_pos)
			if absf(local.x) > 0.01:
				dir = signf(local.x)
		fx.add_recoil(Vector2(0.02 * dir, 0.035))
	if not voice_player.playing:
		voice_player.pitch_scale = randf_range(0.95, 1.1)
		voice_player.play()
	if health <= 0.0:
		_die()


func switch_weapon() -> void:
	if not is_multiplayer_authority() or is_dead:
		return
	weapon.switch_weapon()
	_net_weapon = weapon.weapon_kind
	rpc("net_state", global_position, rotation.y, head.rotation.x, health, is_dead, weapon.weapon_kind)

func _on_weapon_changed(kind: int, _display_name: String) -> void:
	_net_weapon = kind
	if remote_pistol != null:
		remote_pistol.visible = kind == GameSettings.WEAPON_PISTOL
	if remote_m4 != null:
		remote_m4.visible = kind == GameSettings.WEAPON_M4

func update_rig_motion(_delta: float) -> void:
	if rig == null:
		return
	var speed := Vector3(velocity.x, 0.0, velocity.z).length() / SPEED_WALK
	rig.set_motion(speed, weapon.weapon_kind == GameSettings.WEAPON_M4, is_dead)

@rpc("authority", "unreliable")
func net_state(pos: Vector3, yaw: float, pitch: float, hp: float, dead: bool, selected_weapon: int) -> void:
	if is_multiplayer_authority():
		return
	_net_pos = pos
	_net_yaw = yaw
	_net_pitch = pitch
	_net_health = hp
	_net_dead = dead
	if absf(health - hp) > 0.01:
		health = hp
		health_changed.emit(health, max_health)
	if selected_weapon != weapon.weapon_kind:
		weapon.set_weapon(selected_weapon, false)
	is_dead = dead


func _die() -> void:
	is_dead = true
	if fx != null:
		fx.start_death()
	if _mouse_captured:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		_mouse_captured = false
	died.emit()
