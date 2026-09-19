"""Minimal glTF 2.0 / GLB writer (pure Python, no external 3D tools)."""
import json, struct, math


class Glb:
    def __init__(self):
        self.bin = bytearray()
        self.bufferViews = []
        self.accessors = []
        self.meshes = []
        self.nodes = []
        self.materials = []
        self._mat_cache = {}
        self._mesh_cache = {}

    def _pad(self):
        while len(self.bin) % 4 != 0:
            self.bin.append(0)

    def _view(self, data, target):
        self._pad()
        off = len(self.bin)
        self.bin.extend(data)
        self.bufferViews.append({"buffer": 0, "byteOffset": off,
                                 "byteLength": len(data), "target": target})
        return len(self.bufferViews) - 1

    def _acc_vec3(self, verts, is_position=False):
        data = b"".join(struct.pack("<3f", *v) for v in verts)
        vi = self._view(data, 34962)
        acc = {"bufferView": vi, "componentType": 5126, "count": len(verts), "type": "VEC3"}
        if is_position:
            xs = [v[0] for v in verts]; ys = [v[1] for v in verts]; zs = [v[2] for v in verts]
            acc["min"] = [min(xs), min(ys), min(zs)]
            acc["max"] = [max(xs), max(ys), max(zs)]
        self.accessors.append(acc)
        return len(self.accessors) - 1

    def _acc_idx(self, idx):
        data = b"".join(struct.pack("<H", i) for i in idx)
        vi = self._view(data, 34963)
        self.accessors.append({"bufferView": vi, "componentType": 5123,
                               "count": len(idx), "type": "SCALAR"})
        return len(self.accessors) - 1

    def material(self, name, color, roughness=0.8, metallic=0.0, emissive=None):
        key = (name, tuple(color), roughness, metallic, tuple(emissive) if emissive else None)
        if key in self._mat_cache:
            return self._mat_cache[key]
        m = {"name": name, "doubleSided": False,
             "pbrMetallicRoughness": {
                 "baseColorFactor": list(color) + ([1.0] if len(color) == 3 else []),
                 "metallicFactor": metallic, "roughnessFactor": roughness}}
        if emissive:
            m["emissiveFactor"] = list(emissive)
        self.materials.append(m)
        self._mat_cache[key] = len(self.materials) - 1
        return self._mat_cache[key]

    def mesh_from_faces(self, name, faces, material):
        verts, norms, idx = [], [], []
        for poly in faces:
            if len(poly) < 3:
                continue
            ax, ay, az = poly[0]; bx, by, bz = poly[1]; cx, cy, cz = poly[2]
            ux, uy, uz = bx - ax, by - ay, bz - az
            vx, vy, vz = cx - ax, cy - ay, cz - az
            nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
            l = math.sqrt(nx * nx + ny * ny + nz * nz) or 1.0
            nrm = (nx / l, ny / l, nz / l)
            base = len(verts)
            for p in poly:
                verts.append(p); norms.append(nrm)
            for i in range(1, len(poly) - 1):
                idx += [base, base + i, base + i + 1]
        pa = self._acc_vec3(verts, True)
        na = self._acc_vec3(norms)
        ia = self._acc_idx(idx)
        self.meshes.append({"name": name, "primitives": [
            {"attributes": {"POSITION": pa, "NORMAL": na}, "indices": ia, "material": material}]})
        return len(self.meshes) - 1

    def box_mesh(self, size, material, name="box"):
        key = (tuple(size), material)
        if key in self._mesh_cache:
            return self._mesh_cache[key]
        sx, sy, sz = size[0] / 2.0, size[1] / 2.0, size[2] / 2.0
        p = [(-sx, -sy, -sz), (sx, -sy, -sz), (sx, -sy, sz), (-sx, -sy, sz),
             (-sx, sy, -sz), (sx, sy, -sz), (sx, sy, sz), (-sx, sy, sz)]
        faces = [[p[3], p[2], p[6], p[7]], [p[1], p[0], p[4], p[5]],
                 [p[2], p[1], p[5], p[6]], [p[0], p[3], p[7], p[4]],
                 [p[7], p[6], p[5], p[4]], [p[0], p[1], p[2], p[3]]]
        mi = self.mesh_from_faces(name, faces, material)
        self._mesh_cache[key] = mi
        return mi

    def wedge_mesh(self, size, material, name="wedge"):
        sx, sy, sz = size[0] / 2.0, size[1] / 2.0, size[2] / 2.0
        b = [(-sx, -sy, -sz), (sx, -sy, -sz), (sx, -sy, sz), (-sx, -sy, sz)]
        t = [(-sx * 0.6, sy, -sz * 0.4), (sx * 0.6, sy, -sz * 0.4), (sx, sy, sz), (-sx, sy, sz)]
        faces = [[b[0], b[1], b[2], b[3]], [t[3], t[2], t[1], t[0]],
                 [b[3], b[2], t[2], t[3]], [b[1], b[0], t[0], t[1]],
                 [b[2], b[1], t[1], t[2]], [b[0], b[3], t[3], t[0]]]
        return self.mesh_from_faces(name, faces, material)

    def cyl_mesh(self, radius, height, material, sides=8, name="cyl"):
        key = ("cyl", radius, height, material, sides)
        if key in self._mesh_cache:
            return self._mesh_cache[key]
        h = height / 2.0
        rb, rt = [], []
        for i in range(sides):
            a = 2 * math.pi * i / sides
            x, z = math.cos(a) * radius, math.sin(a) * radius
            rb.append((x, -h, z)); rt.append((x, h, z))
        faces = []
        for i in range(sides):
            j = (i + 1) % sides
            faces.append([rb[i], rb[j], rt[j], rt[i]])
        faces.append(list(reversed(rt)))
        faces.append(list(rb))
        mi = self.mesh_from_faces(name, faces, material)
        self._mesh_cache[key] = mi
        return mi

    def node(self, name, mesh=None, pos=(0, 0, 0), rot_y=0.0, rot_x=0.0, rot_z=0.0,
             scale=None, children=None):
        n = {"name": name}
        if mesh is not None:
            n["mesh"] = mesh
        if pos != (0, 0, 0):
            n["translation"] = list(pos)
        if rot_x or rot_y or rot_z:
            n["rotation"] = _euler_quat(rot_x, rot_y, rot_z)
        if scale:
            n["scale"] = list(scale)
        if children:
            n["children"] = list(children)
        self.nodes.append(n)
        return len(self.nodes) - 1

    def save(self, path, root_children, scene_name="Scene"):
        self._pad()
        gltf = {"asset": {"version": "2.0", "generator": "bodycam-duel procedural generator"},
                "scene": 0,
                "scenes": [{"name": scene_name, "nodes": list(root_children)}],
                "nodes": self.nodes, "meshes": self.meshes, "materials": self.materials,
                "accessors": self.accessors, "bufferViews": self.bufferViews,
                "buffers": [{"byteLength": len(self.bin)}]}
        jdata = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
        while len(jdata) % 4 != 0:
            jdata += b" "
        bindata = bytes(self.bin)
        total = 12 + 8 + len(jdata) + 8 + len(bindata)
        with open(path, "wb") as f:
            f.write(struct.pack("<III", 0x46546C67, 2, total))
            f.write(struct.pack("<II", len(jdata), 0x4E4F534A))
            f.write(jdata)
            f.write(struct.pack("<II", len(bindata), 0x004E4942))
            f.write(bindata)
        return total


def _euler_quat(rx, ry, rz):
    cx, sx = math.cos(rx / 2), math.sin(rx / 2)
    cy, sy = math.cos(ry / 2), math.sin(ry / 2)
    cz, sz = math.cos(rz / 2), math.sin(rz / 2)
    x = sx * cy * cz + cx * sy * sz
    y = cx * sy * cz - sx * cy * sz
    z = cx * cy * sz - sx * sy * cz
    w = cx * cy * cz + sx * sy * sz
    return [x, y, z, w]
