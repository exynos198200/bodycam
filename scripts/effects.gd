extends Node
class_name Effects

## Static helpers for bullet impacts, blood puffs and tracers.
##
## Everything here is allocation-conscious: meshes, materials, the bullet-hole
## texture and audio players are created once and reused. Creating a new
## ImageTexture / ParticleProcessMaterial / AudioStreamPlayer3D per shot was
## what made the game run out of RAM on low-end Android devices.
##
## `world` must point at a node inside the 3D SubViewport, because everything
## spawned here (decals, puffs, positional audio) has to live in the same
## World3D as the map, otherwise it is neither visible nor audible.

const MAX_DECALS := 10
const AUDIO_POOL := 6

static var world: Node = null

static var _decals: Array = []
static var _hole_tex: Texture2D = null
static var _hole_mats: Dictionary = {}
static var _puff_mats: Dictionary = {}
static var _quad_mesh: QuadMesh = null
static var _tracer_mesh: BoxMesh = null
static var _tracer_mat: StandardMaterial3D = null
static var _streams: Dictionary = {}
static var _audio_pool: Array = []
static var _audio_next := 0


static func _host(scene: Node) -> Node:
	if world != null and is_instance_valid(world) and world.is_inside_tree():
		return world
	return scene


static func spawn_impact(scene: Node, point: Vector3, normal: Vector3) -> void:
	if scene == null:
		return
	_spawn_decal(scene, point, normal, Color(0.05, 0.05, 0.06, 0.9), 0.16)
	_spawn_puff(scene, point, normal, Color(0.65, 0.63, 0.58, 0.85))
	_play_oneshot(scene, point, "res://audio/impact_wall.wav", 0.9)


static func spawn_blood(scene: Node, point: Vector3, normal: Vector3) -> void:
	if scene == null:
		return
	_spawn_puff(scene, point, normal, Color(0.55, 0.05, 0.06, 0.9))
	_play_oneshot(scene, point, "res://audio/impact_flesh.wav", 1.0)


static func spawn_tracer(scene: Node, from: Vector3, to: Vector3) -> void:
	if scene == null:
		return
	var dist := from.distance_to(to)
	if dist < 0.05:
		return
	if _tracer_mesh == null:
		_tracer_mesh = BoxMesh.new()
		_tracer_mesh.size = Vector3(0.012, 0.012, 1.0)
		_tracer_mat = StandardMaterial3D.new()
		_tracer_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_tracer_mat.albedo_color = Color(1.0, 0.85, 0.5, 0.65)
		_tracer_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var mi := MeshInstance3D.new()
	mi.mesh = _tracer_mesh
	mi.material_override = _tracer_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_host(scene).add_child(mi)
	mi.global_position = (from + to) * 0.5
	mi.look_at(to, Vector3.UP)
	mi.scale = Vector3(1.0, 1.0, dist)
	_free_later(scene, mi, 0.05)


static func _spawn_decal(scene: Node, point: Vector3, normal: Vector3,
		color: Color, size: float) -> void:
	# Bullet holes are quads, not Decal nodes: decals are not rendered by the
	# Compatibility renderer used on low-end Android GPUs.
	if _quad_mesh == null:
		_quad_mesh = QuadMesh.new()
		_quad_mesh.size = Vector2(1.0, 1.0)
	var hole := MeshInstance3D.new()
	hole.mesh = _quad_mesh
	hole.material_override = _hole_material(color)
	hole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_host(scene).add_child(hole)
	hole.global_position = point + normal * 0.012
	var up: Vector3 = Vector3.UP if absf(normal.dot(Vector3.UP)) < 0.95 else Vector3.FORWARD
	hole.look_at(hole.global_position - normal, up)
	hole.rotate_object_local(Vector3.FORWARD, randf_range(0.0, TAU))
	hole.scale = Vector3(size, size, 1.0)
	_decals.append(hole)
	while _decals.size() > MAX_DECALS:
		var old = _decals.pop_front()
		if is_instance_valid(old):
			old.queue_free()


static func _hole_material(color: Color) -> StandardMaterial3D:
	var key := str(color)
	if _hole_mats.has(key):
		return _hole_mats[key]
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.albedo_texture = _hole_texture()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_hole_mats[key] = mat
	return mat


static func _hole_texture() -> Texture2D:
	if _hole_tex != null:
		return _hole_tex
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in range(32):
		for x in range(32):
			var d := Vector2(x - 15.5, y - 15.5).length() / 15.5
			var a := clampf(1.0 - d * d * 1.25, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	_hole_tex = ImageTexture.create_from_image(img)
	return _hole_tex


static func _puff_material(color: Color) -> StandardMaterial3D:
	var key := str(color)
	if _puff_mats.has(key):
		return _puff_mats[key]
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.albedo_texture = _hole_texture()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_puff_mats[key] = mat
	return mat


static func _spawn_puff(scene: Node, point: Vector3, normal: Vector3,
		color: Color) -> void:
	# A GPU particle system per impact was far too heavy: this is a single
	# billboarded quad that expands and fades out with a tween.
	if _quad_mesh == null:
		_quad_mesh = QuadMesh.new()
		_quad_mesh.size = Vector2(1.0, 1.0)
	var puff := MeshInstance3D.new()
	puff.mesh = _quad_mesh
	puff.material_override = _puff_material(color)
	puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_host(scene).add_child(puff)
	puff.global_position = point + normal * 0.06
	puff.scale = Vector3(0.1, 0.1, 0.1)
	if not puff.is_inside_tree():
		puff.queue_free()
		return
	var tw := puff.create_tween()
	tw.set_parallel(true)
	tw.tween_property(puff, "scale", Vector3(0.42, 0.42, 0.42), 0.28)
	tw.tween_property(puff, "transparency", 1.0, 0.28)
	tw.chain().tween_callback(puff.queue_free)


static func _play_oneshot(scene: Node, point: Vector3, path: String, volume_scale: float) -> void:
	var stream = _streams.get(path)
	if stream == null:
		stream = load(path)
		if stream == null:
			return
		_streams[path] = stream
	var host := _host(scene)
	if host == null or not host.is_inside_tree():
		return
	# Round-robin pool: no node is allocated per impact.
	_audio_pool = _audio_pool.filter(func(p) -> bool: return is_instance_valid(p))
	var player: AudioStreamPlayer3D = null
	if _audio_pool.size() < AUDIO_POOL:
		player = AudioStreamPlayer3D.new()
		player.max_distance = 30.0
		host.add_child(player)
		_audio_pool.append(player)
	else:
		_audio_next = (_audio_next + 1) % _audio_pool.size()
		player = _audio_pool[_audio_next]
	player.stream = stream
	player.unit_size = 6.0 * volume_scale
	player.pitch_scale = randf_range(0.92, 1.1)
	player.global_position = point
	player.play()


static func _free_later(scene: Node, node: Node, delay: float) -> void:
	var tree := scene.get_tree()
	if tree == null:
		return
	tree.create_timer(delay).timeout.connect(func() -> void:
		if is_instance_valid(node):
			node.queue_free())
