extends Node
class_name Texturing

## Applies the procedurally generated textures (textures/*.png) to the imported
## GLB materials by material name.
##
## Triplanar mapping is used on purpose: the generated GLB geometry has no UV
## layout, and world triplanar needs none while still giving every surface a
## proper tiling texture. All textures are shared, so this costs a handful of
## small resources in total.

const MAP := {
	"FloorConcrete": {"tex": "concrete", "scale": 0.35, "rough": 0.95},
	"FloorTile": {"tex": "tile", "scale": 0.5, "rough": 0.55},
	"WallPlaster": {"tex": "plaster", "scale": 0.35, "rough": 0.92},
	"WallAccent": {"tex": "plaster", "scale": 0.4, "rough": 0.88},
	"Ceiling": {"tex": "plaster", "scale": 0.3, "rough": 0.95},
	"CrateWood": {"tex": "wood", "scale": 1.4, "rough": 0.85},
	"TableTop": {"tex": "wood", "scale": 1.1, "rough": 0.7},
	"Metal": {"tex": "metal", "scale": 1.2, "rough": 0.45},
	"BarrelPaint": {"tex": "metal", "scale": 1.0, "rough": 0.6},
	"Pipe": {"tex": "metal", "scale": 1.6, "rough": 0.4},
	"DoorFrame": {"tex": "metal", "scale": 1.0, "rough": 0.55},
}

static var _cache: Dictionary = {}


static func texture(name: String) -> Texture2D:
	if _cache.has(name):
		return _cache[name]
	var tex: Texture2D = load("res://textures/%s.png" % name)
	_cache[name] = tex
	return tex


## Walks the imported map and textures every surface whose material name is
## known. Returns the number of materials that were textured.
static func apply(root: Node) -> int:
	if root == null:
		return 0
	var done := {}
	var count := 0
	for node in _all_meshes(root):
		var mesh: Mesh = node.mesh
		if mesh == null:
			continue
		for i in range(mesh.get_surface_count()):
			var mat = mesh.surface_get_material(i)
			if mat == null or not (mat is StandardMaterial3D):
				continue
			var std: StandardMaterial3D = mat
			var key := std.resource_name
			if key == "" or not MAP.has(key):
				continue
			if done.has(key):
				continue
			done[key] = true
			var cfg: Dictionary = MAP[key]
			var tex: Texture2D = texture(String(cfg["tex"]))
			if tex == null:
				continue
			std.albedo_texture = tex
			std.uv1_triplanar = true
			std.uv1_world_triplanar = true
			var s: float = float(cfg["scale"])
			std.uv1_scale = Vector3(s, s, s)
			std.roughness = float(cfg["rough"])
			std.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			count += 1
	return count


static func _all_meshes(root: Node) -> Array:
	var out: Array = []
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			out.append(n)
		for c in n.get_children():
			stack.append(c)
	return out
