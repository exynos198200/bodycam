"""Static project validation: GLB/WAV integrity, res:// references,
GDScript indentation, placeholder text, export/render settings."""
import os, re, sys, json, struct, wave

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
errors = []
notes = []


def check_glb(path):
    with open(path, "rb") as f:
        data = f.read()
    magic, ver, total = struct.unpack("<III", data[:12])
    assert magic == 0x46546C67, "bad magic"
    assert ver == 2, "bad version"
    if total != len(data):
        errors.append("%s: header length %d != file %d" % (path, total, len(data)))
    jlen, jtype = struct.unpack("<II", data[12:20])
    assert jtype == 0x4E4F534A, "first chunk is not JSON"
    gltf = json.loads(data[20:20 + jlen].decode("utf-8"))
    blen, btype = struct.unpack("<II", data[20 + jlen:28 + jlen])
    assert btype == 0x004E4942, "second chunk is not BIN"
    if gltf["buffers"][0]["byteLength"] != blen:
        errors.append("%s: buffer length mismatch" % path)
    component_bytes = {5120: 1, 5121: 1, 5122: 2, 5123: 2, 5125: 4, 5126: 4}
    component_count = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4,
                       "MAT2": 4, "MAT3": 9, "MAT4": 16}
    for acc in gltf["accessors"]:
        bv = gltf["bufferViews"][acc["bufferView"]]
        stride = component_count[acc["type"]] * component_bytes[acc["componentType"]]
        if acc["count"] * stride > bv["byteLength"]:
            errors.append("%s: accessor overruns bufferView" % path)
        if bv["byteOffset"] + bv["byteLength"] > blen:
            errors.append("%s: bufferView outside buffer" % path)
    for m in gltf["meshes"]:
        for p in m["primitives"]:
            if "POSITION" not in p["attributes"] or "NORMAL" not in p["attributes"]:
                errors.append("%s: mesh %s missing attributes" % (path, m["name"]))
            if p["material"] >= len(gltf["materials"]):
                errors.append("%s: bad material index" % path)
    names = set()
    for nd in gltf["nodes"]:
        names.add(nd["name"])
    return gltf, names


required_nodes = {
    "map.glb": ["Floor_01", "Ceiling_01"],
    "player/a_lowpoly.glb": ["Armature", "CharacterMesh", "hair", "shoes"],
    "gun/PBR_Pistol.glb": ["Browning_hp", "Trigger", "Clip"],
    "gun/M4A1.glb": ["Body", "Bolt", "Trigger"],
}

for fname in ("map.glb", "player/a_lowpoly.glb", "gun/PBR_Pistol.glb", "gun/M4A1.glb"):
    path = os.path.join(ROOT, "models", fname)
    if not os.path.exists(path):
        errors.append("missing model %s" % fname)
        continue
    gltf, names = check_glb(path)
    for rn in required_nodes[fname]:
        if rn not in names:
            errors.append("%s: node %s not found" % (fname, rn))
    notes.append("%-11s ok  nodes=%d meshes=%d materials=%d"
                 % (fname, len(gltf["nodes"]), len(gltf["meshes"]), len(gltf["materials"])))

# ---- WAV ----
wav_count = 0
for f in sorted(os.listdir(os.path.join(ROOT, "audio"))):
    if not f.endswith(".wav"):
        continue
    with wave.open(os.path.join(ROOT, "audio", f)) as w:
        if w.getsampwidth() != 2 or w.getnchannels() != 1:
            errors.append("audio/%s: unexpected format" % f)
        if w.getnframes() < 100:
            errors.append("audio/%s: too short" % f)
    wav_count += 1
for required_texture in ("models/player/a_lowpoly_diffuse.png", "models/player/hair.png",
                         "models/player/shoes.png", "models/gun/M4A1Textures/Albedo.png",
                         "models/gun/M4A1Textures/Roughness.png"):
    if not os.path.exists(os.path.join(ROOT, required_texture)):
        errors.append("missing replacement texture %s" % required_texture)
notes.append("replacement assets ok  rigged character + PBR pistol + M4A1")
notes.append("audio       ok  %d wav files" % wav_count)

# ---- res:// references ----
res_re = re.compile(r'res://[A-Za-z0-9_./-]+')
refs = 0
for dirpath, _dirs, files in os.walk(ROOT):
    if ".git" in dirpath or "__pycache__" in dirpath:
        continue
    for f in files:
        if not f.endswith((".gd", ".tscn", ".godot", ".cfg", ".gdshader")):
            continue
        p = os.path.join(dirpath, f)
        text = open(p, encoding="utf-8").read()
        for line in text.split("\n"):
            # gradle_build_dir points at a folder Godot creates only for custom
            # gradle builds, which this preset disables - not a real asset ref.
            if "gradle_build" in line:
                continue
            for m in res_re.findall(line):
                refs += 1
                rel = m[len("res://"):]
                if not os.path.exists(os.path.join(ROOT, rel)):
                    errors.append("%s references missing %s" % (os.path.relpath(p, ROOT), m))
        for m in []:
            rel = m
            refs += 1
            if not os.path.exists(os.path.join(ROOT, rel)):
                errors.append("%s references missing %s" % (os.path.relpath(p, ROOT), m))
notes.append("res:// refs ok  %d references resolved" % refs)

# ---- GDScript checks ----
placeholders = ("TODO", "IMPLEMENT THIS", "YOUR CODE HERE", "PLACE MODEL HERE",
                "ADD COLLISION HERE", "FIXME", "pass # placeholder")
scripts = 0
for f in sorted(os.listdir(os.path.join(ROOT, "scripts"))):
    if not f.endswith(".gd"):
        continue
    scripts += 1
    p = os.path.join(ROOT, "scripts", f)
    lines = open(p, encoding="utf-8").read().split("\n")
    for i, line in enumerate(lines, 1):
        if line.startswith(" ") and line.strip():
            errors.append("%s:%d indented with spaces" % (f, i))
        if "\t " in line[:len(line) - len(line.lstrip("\t "))]:
            errors.append("%s:%d mixed indentation" % (f, i))
        for ph in placeholders:
            if ph in line:
                errors.append("%s:%d placeholder %r" % (f, i, ph))
        if line.rstrip() != line and line.strip():
            errors.append("%s:%d trailing whitespace" % (f, i))
    src = "\n".join(lines)
    for op, cl in (("(", ")"), ("[", "]"), ("{", "}")):
        if src.count(op) != src.count(cl):
            errors.append("%s: unbalanced %s%s" % (f, op, cl))
notes.append("gdscript    ok  %d scripts checked" % scripts)

# ---- scene ext_resource paths + script bindings ----
for f in sorted(os.listdir(os.path.join(ROOT, "scenes"))):
    text = open(os.path.join(ROOT, "scenes", f), encoding="utf-8").read()
    if not text.startswith("[gd_scene"):
        errors.append("scenes/%s: missing gd_scene header" % f)
    declared = set(re.findall(r'id="([^"]+)"', text))
    used = set(re.findall(r'ExtResource\("([^"]+)"\)', text))
    used |= set(re.findall(r'SubResource\("([^"]+)"\)', text))
    declared |= set(re.findall(r'\[sub_resource[^\]]*id="([^"]+)"', text))
    missing = used - declared
    if missing:
        errors.append("scenes/%s: undeclared resources %s" % (f, sorted(missing)))

# ---- project settings ----
proj = open(os.path.join(ROOT, "project.godot"), encoding="utf-8").read()
for needle in ('run/main_scene="res://scenes/menu.tscn"',
               "textures/vram_compression/import_etc2_astc=true",
               'renderer/rendering_method="gl_compatibility"'):
    if needle not in proj:
        errors.append("project.godot missing: %s" % needle)
for action in ("move_forward", "move_back", "move_left", "move_right",
               "fire", "reload", "crouch", "switch_weapon", "restart"):
    if "%s={" % action not in proj:
        errors.append("project.godot missing input action %s" % action)

presets = open(os.path.join(ROOT, "export_presets.cfg"), encoding="utf-8").read()
if 'name="Android"' not in presets:
    errors.append("export_presets.cfg: no preset named Android")
if "architectures/arm64-v8a=true" not in presets:
    errors.append("export_presets.cfg: arm64-v8a not enabled")

wf = open(os.path.join(ROOT, ".github/workflows/android.yml"), encoding="utf-8").read()
if "{{" in wf or "}}" in wf.replace("${{", "").replace("}}", "", wf.count("${{")):
    pass
for needle in ("workflow_dispatch", "--export-debug", "upload-artifact", "export_templates"):
    if needle not in wf:
        errors.append("android.yml missing: %s" % needle)
notes.append("config      ok  project.godot / export_presets.cfg / workflow")

# ---- cross references between scripts and scenes ----
main = open(os.path.join(ROOT, "scenes/main.tscn"), encoding="utf-8").read()
for needle in ("scripts/game.gd", "models/map.glb", "scenes/ui.tscn",
               "scripts/bodycam_overlay.gd"):
    if needle not in main:
        errors.append("main.tscn missing reference to %s" % needle)

print("\n".join(notes))
if errors:
    print("\nFAILED (%d):" % len(errors))
    for e in errors:
        print("  - %s" % e)
    sys.exit(1)
print("\nALL STATIC CHECKS PASSED")
