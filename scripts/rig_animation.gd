extends Node3D
class_name RigAnimation

## Lightweight runtime animation for the supplied rig. No editor or animation
## files are required: walking, aiming, recoil and death are driven by bones.
var _skeleton: Skeleton3D = null
var _rest := {}
var _time := 0.0
var _speed := 0.0
var _aiming := false
var _dead := false
var _recoil := 0.0

func _ready() -> void:
	rebind()

func rebind() -> void:
	_skeleton = null
	for node in find_children("*", "Skeleton3D", true, false):
		_skeleton = node as Skeleton3D
		break
	_rest.clear()
	if _skeleton == null:
		return
	for bone in ["thigh_l", "thigh_r", "calf_l", "calf_r", "arm_l", "arm_r", "forearm_l", "forearm_r", "spine_01", "head", "hand_l", "hand_r", "index_01_l", "index_01_r", "fingers_01_l", "fingers_01_r", "thumb_01_l", "thumb_01_r"]:
		var index := _skeleton.find_bone(bone)
		if index >= 0:
			_rest[bone] = _skeleton.get_bone_pose_rotation(index)

func set_motion(speed: float, aiming: bool, dead: bool = false) -> void:
	_speed = clampf(speed, 0.0, 1.0)
	_aiming = aiming
	_dead = dead

func add_recoil() -> void:
	_recoil = minf(1.0, _recoil + 1.0)

func _process(delta: float) -> void:
	_time += delta
	_recoil = maxf(0.0, _recoil - delta * 7.0)
	_apply_pose()

func _apply_pose() -> void:
	if _skeleton == null:
		return
	var walk := sin(_time * 8.0) * _speed
	var walk2 := sin(_time * 8.0 + PI) * _speed
	var aim := 1.0 if _aiming else 0.0
	var drop := 1.25 if _dead else 0.0
	_set_bone("thigh_l", Vector3(walk * 0.55 + drop, 0.0, 0.0))
	_set_bone("thigh_r", Vector3(walk2 * 0.55 + drop, 0.0, 0.0))
	_set_bone("calf_l", Vector3(maxf(0.0, -walk) * 0.35, 0.0, 0.0))
	_set_bone("calf_r", Vector3(maxf(0.0, -walk2) * 0.35, 0.0, 0.0))
	_set_bone("arm_l", Vector3(-0.35 - aim * 0.45 + walk2 * 0.12, 0.0, 0.0))
	_set_bone("arm_r", Vector3(-0.55 - aim * 0.62 + walk * 0.12 - _recoil * 0.22, 0.0, 0.0))
	_set_bone("forearm_l", Vector3(-0.15 - aim * 0.22, 0.0, 0.0))
	_set_bone("forearm_r", Vector3(-0.2 - aim * 0.26 - _recoil * 0.18, 0.0, 0.0))
	_set_bone("spine_01", Vector3(0.0, 0.0, sin(_time * 2.0) * 0.025 * _speed + drop * 0.15))
	_set_bone("head", Vector3(0.0, sin(_time * 1.7) * 0.035 * _speed, 0.0))
	# Grip animation: curl fingers around weapon
	var grip := 0.55 + aim * 0.3 + _recoil * 0.15
	_set_bone("index_01_l", Vector3(grip * 0.7, 0.0, 0.0))
	_set_bone("index_01_r", Vector3(grip * 0.7, 0.0, 0.0))
	_set_bone("fingers_01_l", Vector3(grip * 0.8, 0.0, 0.0))
	_set_bone("fingers_01_r", Vector3(grip * 0.8, 0.0, 0.0))
	_set_bone("thumb_01_l", Vector3(0.0, grip * 0.45, 0.0))
	_set_bone("thumb_01_r", Vector3(0.0, -grip * 0.45, 0.0))
	_set_bone("hand_l", Vector3(0.0, 0.0, walk * 0.08))
	_set_bone("hand_r", Vector3(0.0, 0.0, walk2 * 0.08))

func _set_bone(name: String, offset: Vector3) -> void:
	if not _rest.has(name):
		return
	var index := _skeleton.find_bone(name)
	if index < 0:
		return
	_skeleton.set_bone_pose_rotation(index, _rest[name] * Quaternion.from_euler(offset))
