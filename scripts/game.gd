extends Node3D
class_name Game

## Listen Server match director. The host owns the ENet server; every peer owns
## exactly one Player node and replicates its movement, aim, health and weapon.
## There is no bot path or AI in this build: a match is always human 1v1.

const SPAWNS: Array[Vector3] = [
	Vector3(-9.5, 0.2, -7.2),
	Vector3(9.2, 0.2, 6.2),
]
const MIN_SPAWN_DISTANCE := 12.0

var elapsed := 0.0
var finished := false
var _players := {}
var _target_scale := 1.0
var _sun: DirectionalLight3D = null

@onready var world: SubViewport = $ViewLayer/Bodycam/World
@onready var map_root: Node3D = $ViewLayer/Bodycam/World/MapRoot
@onready var hud = $UI
@onready var overlay = $ViewLayer/Bodycam
@onready var ambience: AudioStreamPlayer = $Ambience

func _ready() -> void:
	randomize()
	_apply_performance_profile()
	_bind_network()
	_bind_controls_later()

	var bodies := MapCollision.build(map_root)
	print("[game] generated %d collision bodies for the map" % bodies)
	Effects.world = map_root
	var textured := Texturing.apply(map_root)
	print("[game] textured %d map materials" % textured)

	ambience.stream = load("res://audio/ambience.wav")
	ambience.volume_db = -14.0
	ambience.finished.connect(func() -> void:
		if is_instance_valid(ambience):
			ambience.play())
	ambience.play()

	await get_tree().physics_frame
	await get_tree().physics_frame
	if not is_inside_tree():
		return
	if multiplayer.multiplayer_peer == null:
		# A direct F5 run is still useful during development: create a local
		# listen server without changing the Android workflow.
		var local_peer := OfflineMultiplayerPeer.new()
		multiplayer.multiplayer_peer = local_peer
	if multiplayer.is_server():
		_register_player(1)
	else:
		rpc_id(1, "request_spawn", multiplayer.get_unique_id())

func _bind_network() -> void:
	if multiplayer.peer_connected.is_connected(_on_peer_connected) == false:
		multiplayer.peer_connected.connect(_on_peer_connected)
	if multiplayer.peer_disconnected.is_connected(_on_peer_disconnected) == false:
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)

func _on_peer_connected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	for existing in _players.keys():
		rpc_id(peer_id, "spawn_player", int(existing))
	_register_player(peer_id)

func _on_peer_disconnected(peer_id: int) -> void:
	if _players.has(peer_id):
		var old = _players[peer_id]
		if is_instance_valid(old):
			old.queue_free()
		_players.erase(peer_id)
	hud.set_online_count(_players.size())

@rpc("any_peer", "reliable")
func request_spawn(peer_id: int) -> void:
	if not multiplayer.is_server() or multiplayer.get_remote_sender_id() != peer_id:
		return
	if not _players.has(peer_id):
		_register_player(peer_id)
	# The client may have changed scenes after peer_connected was emitted. Send
	# the complete roster again so no spawn RPC is lost during that transition.
	for existing in _players.keys():
		rpc_id(peer_id, "spawn_player", int(existing))

func _register_player(peer_id: int) -> void:
	if _players.has(peer_id):
		return
	_players[peer_id] = null
	rpc("spawn_player", peer_id)

@rpc("authority", "call_local", "reliable")
func spawn_player(peer_id: int) -> void:
	if _players.has(peer_id) and is_instance_valid(_players[peer_id]):
		return
	var fighter = preload("res://scenes/player.tscn").instantiate()
	fighter.name = "Player_%d" % peer_id
	fighter.set_multiplayer_authority(peer_id)
	world.add_child(fighter)
	_players[peer_id] = fighter
	var index := 0 if peer_id == 1 else 1
	var pos: Vector3 = SPAWNS[index]
	var other_pos: Vector3 = SPAWNS[1 - index]
	fighter.teleport(pos, _yaw_towards(pos, other_pos))
	if peer_id == multiplayer.get_unique_id():
		local_player = fighter
		_bind_controls(fighter)
		overlay.bind_player(fighter)
		_bind_player_signals(fighter)
	hud.set_online_count(_players.size())
	print("[game] spawned peer %d at %s" % [peer_id, pos])

var local_player = null

func _bind_controls_later() -> void:
	# spawn_player is invoked after the network handshake; controls are bound
	# there. This function intentionally keeps the scene responsive meanwhile.
	pass

func _bind_controls(fighter) -> void:
	var controls = hud.get_node_or_null("MobileControls")
	if controls == null:
		controls = get_tree().get_first_node_in_group("mobile_controls")
	if controls == null:
		push_warning("[game] on-screen controls not found")
		return
	fighter.controls = controls
	if not controls.reload_pressed.is_connected(_on_reload_pressed):
		controls.reload_pressed.connect(_on_reload_pressed)
	if not controls.weapon_pressed.is_connected(_on_weapon_pressed):
		controls.weapon_pressed.connect(_on_weapon_pressed)
	print("[game] controls bound to local player")

func _bind_player_signals(fighter) -> void:
	fighter.health_changed.connect(func(cur: float, maxv: float) -> void: hud.set_health(cur, maxv))
	fighter.hit_taken.connect(func() -> void: hud.flash_hit())
	fighter.died.connect(_on_player_died)
	var weapon = fighter.get_node_or_null("Head/Camera3D/WeaponHolder/Weapon")
	if weapon == null:
		return
	weapon.ammo_changed.connect(func(a: int, r: int) -> void: hud.set_ammo(a, r))
	weapon.weapon_changed.connect(func(_kind: int, name: String) -> void: hud.set_weapon(name))
	weapon.reload_started.connect(func(_d: float) -> void: hud.set_status("RELOADING"))
	weapon.reload_finished.connect(func() -> void: hud.set_status(""))
	hud.set_ammo(weapon.in_mag, weapon.reserve)
	hud.set_weapon("M4A1" if weapon.weapon_kind == GameSettings.WEAPON_M4 else "PBR PISTOL")
	hud.set_health(fighter.health, fighter.max_health)

func _process(delta: float) -> void:
	if not finished:
		elapsed += delta
	if Input.is_action_just_pressed("restart"):
		_restart()
	if local_player != null and not finished:
		for peer_id in _players.keys():
			var fighter = _players[peer_id]
			if fighter != local_player and is_instance_valid(fighter) and fighter.is_dead:
				finished = true
				hud.show_result(true, elapsed)
				break


func _on_reload_pressed() -> void:
	if local_player != null:
		local_player.weapon.try_reload()

func _on_weapon_pressed() -> void:
	if local_player != null:
		local_player.switch_weapon()

func _on_player_died() -> void:
	if finished:
		return
	finished = true
	await get_tree().create_timer(1.1).timeout
	if is_inside_tree():
		hud.show_result(false, elapsed)

func _restart() -> void:
	get_tree().reload_current_scene()

func _open_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/menu.tscn")

static func _yaw_towards(from: Vector3, to: Vector3) -> float:
	var d := Vector3(to.x - from.x, 0.0, to.z - from.z)
	if d.length() < 0.01:
		return 0.0
	return atan2(-d.x, -d.z)

func _apply_performance_profile() -> void:
	GameSettings.ensure_loaded()
	Engine.max_fps = 30
	Engine.physics_ticks_per_second = 30
	_target_scale = GameSettings.render_scale()
	world.msaa_3d = Viewport.MSAA_DISABLED
	world.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	world.use_debanding = false
	world.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	world.scaling_3d_scale = _target_scale
	var we := $ViewLayer/Bodycam/World/WorldEnvironment as WorldEnvironment
	if we != null and we.environment != null:
		var env: Environment = we.environment
		env.glow_enabled = false
		env.fog_enabled = false
		env.adjustment_enabled = false
		env.ssao_enabled = false
		env.ssil_enabled = false
		env.sdfgi_enabled = false
	_sun = $ViewLayer/Bodycam/World/DirectionalLight3D as DirectionalLight3D
	if _sun != null:
		_sun.shadow_enabled = GameSettings.shadows_enabled()
		_sun.light_energy = 0.95 if GameSettings.shadows_enabled() else 0.8
