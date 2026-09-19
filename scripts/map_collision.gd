extends Node
class_name MapCollision

## Builds collision bodies for every visual mesh of the imported GLB map.
## The GLB files contain no collision data, so all collision shapes are
## generated at load time from each mesh's local AABB. Box shapes are used on
## purpose: cheapest option on mobile, and all map geometry is box shaped.

const LAYER_WORLD := 1

static func build(root: Node3D) -> int:
	var created := 0
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.push_back(child)
		if node is MeshInstance3D:
			if _add_body(node as MeshInstance3D):
				created += 1
	return created


static func _add_body(mi: MeshInstance3D) -> bool:
	if mi.mesh == null:
		return false
	for c in mi.get_children():
		if c is StaticBody3D:
			return false
	var aabb: AABB = mi.mesh.get_aabb()
	var size: Vector3 = aabb.size
	if size.x <= 0.0005 or size.y <= 0.0005 or size.z <= 0.0005:
		return false

	var body := StaticBody3D.new()
	body.name = "Body_" + str(mi.name)
	body.collision_layer = LAYER_WORLD
	body.collision_mask = 0

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.transform.origin = aabb.position + size * 0.5
	body.add_child(shape)
	mi.add_child(body)
	return true
