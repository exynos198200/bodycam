extends RefCounted
class_name ModelMaterials

## Applies the external texture set shipped with the replacement character and M4.
## The GLBs remain untouched; this keeps imports stable on the Compatibility renderer.

static func apply_character(root: Node) -> int:
	return _apply(root, "res://models/player/a_lowpoly_diffuse.png", "res://models/player/hair.png", "res://models/player/shoes.png", "")

static func apply_m4(root: Node) -> int:
	return _apply(root, "res://models/gun/M4A1Textures/Albedo.png", "", "", "res://models/gun/M4A1Textures/Roughness.png")

static func _texture(path: String) -> Texture2D:
	if path == "":
		return null
	return load(path) as Texture2D

static func _apply(root: Node, body_path: String, hair_path: String, shoes_path: String, rough_path: String) -> int:
	if root == null:
		return 0
	var body: Texture2D = _texture(body_path)
	var hair: Texture2D = _texture(hair_path)
	var shoes: Texture2D = _texture(shoes_path)
	var rough: Texture2D = _texture(rough_path)
	var count := 0
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if mesh_node == null or mesh_node.mesh == null:
			continue
		var texture: Texture2D = body
		var name_lower := String(mesh_node.name).to_lower()
		if name_lower.contains("hair"):
			texture = hair
		elif name_lower.contains("shoe"):
			texture = shoes
		for surface in range(mesh_node.mesh.get_surface_count()):
			var material := mesh_node.mesh.surface_get_material(surface)
			var standard: StandardMaterial3D = StandardMaterial3D.new()
			if material is StandardMaterial3D:
				standard = material.duplicate() as StandardMaterial3D
			if texture != null:
				standard.albedo_texture = texture
			if rough != null:
				standard.roughness_texture = rough
				standard.roughness = 0.72
			standard.cull_mode = BaseMaterial3D.CULL_DISABLED
			mesh_node.set_surface_override_material(surface, standard)
			count += 1
	return count
