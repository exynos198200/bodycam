"""Generates all low-poly GLB models for the Bodycam Duel project.
No external 3D editor is used - geometry is written directly as glTF/GLB.
Run:  python3 tools/gen_models.py models
"""
import os, sys, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from glb import Glb

OUT = sys.argv[1] if len(sys.argv) > 1 else "models"
os.makedirs(OUT, exist_ok=True)

WALL_H = 3.0
T = 0.25


def build_map():
    g = Glb()
    m_floor = g.material("FloorConcrete", (0.30, 0.30, 0.32), 0.85)
    m_floor2 = g.material("FloorTile", (0.22, 0.23, 0.26), 0.7)
    m_wall = g.material("WallPlaster", (0.52, 0.50, 0.47), 0.9)
    m_wall2 = g.material("WallAccent", (0.34, 0.36, 0.40), 0.85)
    m_ceil = g.material("Ceiling", (0.17, 0.17, 0.19), 0.95)
    m_wood = g.material("CrateWood", (0.45, 0.31, 0.17), 0.8)
    m_metal = g.material("Metal", (0.45, 0.47, 0.50), 0.35, 0.85)
    m_table = g.material("TableTop", (0.30, 0.20, 0.13), 0.6)
    m_barrel = g.material("BarrelPaint", (0.35, 0.44, 0.30), 0.55, 0.3)
    m_pipe = g.material("Pipe", (0.36, 0.33, 0.30), 0.5, 0.6)
    m_lamp = g.material("LampPanel", (0.85, 0.87, 0.90), 0.4, 0.0, (0.65, 0.68, 0.72))
    m_door = g.material("DoorFrame", (0.25, 0.25, 0.28), 0.6, 0.4)

    kids = []
    counters = {}

    def add(prefix, mesh, pos, rot_y=0.0):
        counters[prefix] = counters.get(prefix, 0) + 1
        kids.append(g.node("%s_%02d" % (prefix, counters[prefix]), mesh, pos, rot_y=rot_y))

    def wall(x1, z1, x2, z2, h=WALL_H, t=T, mat=None, prefix="Wall"):
        mat = m_wall if mat is None else mat
        cx, cz = (x1 + x2) / 2.0, (z1 + z2) / 2.0
        lx, lz = abs(x2 - x1), abs(z2 - z1)
        add(prefix, g.box_mesh((max(lx, t), h, max(lz, t)), mat), (cx, h / 2.0, cz))

    def door_frame(x, z, horizontal, width):
        if horizontal:
            add("DoorTop", g.box_mesh((width, 0.45, T + 0.04), m_door), (x, WALL_H - 0.22, z))
        else:
            add("DoorTop", g.box_mesh((T + 0.04, 0.45, width), m_door), (x, WALL_H - 0.22, z))

    def crate(x, z, s=1.0, y=None, rot=0.0):
        y = s / 2.0 if y is None else y
        add("Crate", g.box_mesh((s, s, s), m_wood), (x, y, z), rot_y=rot)
        add("CrateBand", g.box_mesh((s * 1.02, s * 0.1, s * 0.2), m_metal),
            (x, y + s * 0.25, z), rot_y=rot)

    def table(x, z, w=1.8, d=0.9, h=0.78, rot=0.0):
        add("TableTop", g.box_mesh((w, 0.09, d), m_table), (x, h, z), rot_y=rot)
        for dx in (-w / 2 + 0.12, w / 2 - 0.12):
            for dz in (-d / 2 + 0.1, d / 2 - 0.1):
                lx = x + dx * math.cos(rot) - dz * math.sin(rot)
                lz = z + dx * math.sin(rot) + dz * math.cos(rot)
                add("TableLeg", g.box_mesh((0.09, h, 0.09), m_metal), (lx, h / 2.0, lz))

    def barrel(x, z):
        add("Barrel", g.cyl_mesh(0.34, 1.0, m_barrel, 10), (x, 0.5, z))
        add("BarrelRim", g.cyl_mesh(0.36, 0.08, m_metal, 10), (x, 0.82, z))

    def low_cover(x, z, w, d, h=1.15, mat=None):
        add("Cover", g.box_mesh((w, h, d), mat or m_wall2), (x, h / 2.0, z))
        add("CoverCap", g.box_mesh((w + 0.08, 0.08, d + 0.08), m_metal), (x, h + 0.02, z))

    def shelf(x, z, rot=0.0):
        add("ShelfBody", g.box_mesh((1.6, 2.0, 0.45), m_metal), (x, 1.0, z), rot_y=rot)
        for yy in (0.6, 1.2, 1.7):
            add("ShelfPlank", g.box_mesh((1.66, 0.06, 0.5), m_wood), (x, yy, z), rot_y=rot)

    def pillar(x, z):
        add("Pillar", g.box_mesh((0.5, WALL_H, 0.5), m_wall2), (x, WALL_H / 2.0, z))

    def ceiling_lamp(x, z):
        add("LampHousing", g.box_mesh((1.5, 0.12, 0.42), m_metal), (x, WALL_H - 0.14, z))
        add("LampPanel", g.box_mesh((1.35, 0.05, 0.3), m_lamp), (x, WALL_H - 0.22, z))

    def pipe_run(x1, x2, z, y):
        add("Pipe", g.box_mesh((abs(x2 - x1), 0.16, 0.16), m_pipe), ((x1 + x2) / 2, y, z))

    add("Floor", g.box_mesh((24.0, 0.3, 18.0), m_floor), (0, -0.15, 0))
    add("FloorInlay", g.box_mesh((7.0, 0.04, 7.0), m_floor2), (0, 0.02, 0))
    add("Ceiling", g.box_mesh((24.0, 0.3, 18.0), m_ceil), (0, WALL_H + 0.15, 0))

    wall(-12, -9, 12, -9)
    wall(-12, 9, 12, 9)
    wall(-12, -9, -12, 9)
    wall(12, -9, 12, 9)

    wall(-4.5, -9, -4.5, -3.5)
    wall(-4.5, -1.5, -4.5, 3.0)
    wall(-4.5, 5.0, -4.5, 9)
    door_frame(-4.5, -2.5, False, 2.0)
    door_frame(-4.5, 4.0, False, 2.0)

    wall(4.5, -9, 4.5, -4.5)
    wall(4.5, -2.5, 4.5, 1.5)
    wall(4.5, 3.5, 4.5, 9)
    door_frame(4.5, -3.5, False, 2.0)
    door_frame(4.5, 2.5, False, 2.0)

    wall(-12, 3.5, -9.5, 3.5)
    wall(-7.5, 3.5, -4.5, 3.5)
    door_frame(-8.5, 3.5, True, 2.0)

    wall(4.5, -3.5, 8.0, -3.5)
    wall(10.0, -3.5, 12, -3.5)
    door_frame(9.0, -3.5, True, 2.0)

    for px, pz in ((-2.0, -6.0), (2.0, -6.0), (-2.0, 6.0), (2.0, 6.0)):
        pillar(px, pz)

    low_cover(0.0, -2.0, 3.2, 0.6)
    low_cover(0.0, 2.0, 3.2, 0.6)
    low_cover(-2.6, 0.0, 0.6, 2.6)
    low_cover(2.6, 0.0, 0.6, 2.6)
    crate(-1.2, -4.6); crate(-0.2, -4.6); crate(-0.7, -4.6, 1.0, y=1.5)
    crate(1.4, 4.4, 1.2); crate(2.6, 4.4, 1.2)
    barrel(-3.2, -7.4); barrel(-2.4, -7.6); barrel(3.0, 7.4)
    table(1.0, -7.0)
    table(-1.4, 7.2, rot=math.pi / 2)

    shelf(-11.2, -6.0, rot=math.pi / 2)
    shelf(-11.2, -3.0, rot=math.pi / 2)
    crate(-7.0, -6.5); crate(-7.0, -5.5); crate(-8.2, -6.0, 1.2)
    table(-8.6, -1.0)
    low_cover(-6.2, 1.4, 2.4, 0.6)
    barrel(-11.0, 1.0)
    crate(-10.0, 6.4, 1.2); crate(-8.8, 6.4, 1.2); crate(-9.4, 6.4, 1.0, y=1.8)
    table(-6.4, 6.0, rot=math.pi / 2)
    low_cover(-7.0, 8.0, 3.0, 0.6)

    shelf(11.2, 5.4, rot=math.pi / 2)
    crate(6.6, 5.6); crate(7.6, 5.6); crate(7.1, 5.6, 1.0, y=1.5)
    table(9.6, 1.8)
    low_cover(6.4, -0.4, 0.6, 2.8)
    low_cover(9.0, 6.6, 2.6, 0.6)
    barrel(11.0, -1.2); barrel(11.0, -2.2)
    crate(6.4, -6.4, 1.2); crate(7.6, -6.4, 1.2)
    table(10.2, -6.6, rot=math.pi / 2)
    low_cover(8.6, -8.0, 3.0, 0.6)

    for lx, lz in ((-8.0, -6.0), (-8.0, 0.0), (-8.0, 6.5), (0.0, -6.0), (0.0, 0.0),
                   (0.0, 6.0), (8.0, -6.5), (8.0, -1.0), (8.0, 6.0)):
        ceiling_lamp(lx, lz)
    pipe_run(-11.5, -5.0, -8.3, WALL_H - 0.45)
    pipe_run(5.0, 11.5, 8.3, WALL_H - 0.45)
    pipe_run(-3.5, 3.5, -8.5, WALL_H - 0.6)

    for (x1, z1, x2, z2) in ((-12, -8.8, 12, -8.8), (-12, 8.8, 12, 8.8)):
        add("Trim", g.box_mesh((abs(x2 - x1), 0.14, 0.08), m_wall2), ((x1 + x2) / 2, 0.07, z1))

    return g.save(os.path.join(OUT, "map.glb"), kids, "Map"), len(g.nodes), len(g.meshes)


def build_pistol():
    g = Glb()
    m_body = g.material("GunPolymer", (0.11, 0.11, 0.12), 0.55, 0.2)
    m_slide = g.material("GunSlide", (0.17, 0.18, 0.20), 0.3, 0.9)
    m_grip = g.material("GunGrip", (0.08, 0.08, 0.09), 0.85)
    m_detail = g.material("GunDetail", (0.55, 0.52, 0.45), 0.3, 0.85)
    m_sight = g.material("SightDot", (0.9, 0.95, 1.0), 0.4, 0.0, (0.5, 0.7, 0.9))

    children = [g.node("Frame", g.box_mesh((0.075, 0.085, 0.33), m_body), (0, 0.0, -0.05))]
    slide_kids = [
        g.node("SlideBody", g.box_mesh((0.08, 0.075, 0.36), m_slide)),
        g.node("SlideTaper", g.wedge_mesh((0.081, 0.03, 0.12), m_slide), (0, 0.05, -0.12)),
        g.node("Serrations", g.box_mesh((0.084, 0.05, 0.05), m_detail), (0, 0, 0.14)),
        g.node("Sight_Rear", g.box_mesh((0.05, 0.022, 0.025), m_detail), (0, 0.05, 0.14)),
        g.node("Sight_Front", g.box_mesh((0.014, 0.024, 0.02), m_sight), (0, 0.05, -0.16)),
    ]
    children.append(g.node("Slide", None, (0, 0.085, -0.06), children=slide_kids))
    children.append(g.node("BarrelTip", g.cyl_mesh(0.016, 0.06, m_detail, 8),
                           (0, 0.085, -0.235), rot_x=math.pi / 2))
    grip_kids = [
        g.node("GripBody", g.box_mesh((0.07, 0.23, 0.1), m_grip), (0, -0.115, 0)),
        g.node("GripPlate", g.box_mesh((0.073, 0.16, 0.022), m_body), (0, -0.12, 0.05)),
        g.node("Magazine", g.box_mesh((0.055, 0.04, 0.085), m_detail), (0, -0.235, 0.0)),
    ]
    children.append(g.node("Grip", None, (0, -0.03, 0.07), rot_x=-0.22, children=grip_kids))
    children.append(g.node("TriggerGuard_Front", g.box_mesh((0.05, 0.02, 0.085), m_body), (0, -0.095, -0.02)))
    children.append(g.node("TriggerGuard_Side", g.box_mesh((0.05, 0.08, 0.018), m_body), (0, -0.06, -0.06)))
    children.append(g.node("Trigger", g.box_mesh((0.016, 0.05, 0.016), m_detail), (0, -0.055, -0.01)))
    children.append(g.node("Hammer", g.box_mesh((0.02, 0.035, 0.02), m_detail), (0, 0.055, 0.115)))
    children.append(g.node("Rail", g.box_mesh((0.05, 0.018, 0.12), m_body), (0, -0.045, -0.15)))
    children.append(g.node("Muzzle", None, (0, 0.085, -0.27)))
    children.append(g.node("ShellEject", None, (0.05, 0.1, 0.05)))

    root = g.node("Pistol", None, children=children)
    return g.save(os.path.join(OUT, "pistol.glb"), [root], "Pistol"), len(g.nodes), len(g.meshes)


def build_agent():
    g = Glb()
    m_suit = g.material("AgentSuit", (0.13, 0.15, 0.19), 0.75)
    m_vest = g.material("AgentVest", (0.20, 0.21, 0.24), 0.6)
    m_skin = g.material("AgentSkin", (0.72, 0.56, 0.44), 0.7)
    m_mask = g.material("AgentMask", (0.08, 0.08, 0.09), 0.5)
    m_boot = g.material("AgentBoot", (0.07, 0.07, 0.08), 0.85)
    m_gun = g.material("AgentGun", (0.15, 0.16, 0.18), 0.35, 0.85)
    m_eye = g.material("AgentVisor", (0.4, 0.75, 0.9), 0.2, 0.0, (0.15, 0.4, 0.5))

    head_kids = [
        g.node("Skull", g.box_mesh((0.22, 0.24, 0.23), m_skin), (0, 0.12, 0)),
        g.node("Mask", g.box_mesh((0.225, 0.1, 0.235), m_mask), (0, 0.08, 0)),
        g.node("Visor", g.box_mesh((0.2, 0.05, 0.03), m_eye), (0, 0.15, -0.115)),
        g.node("Cap", g.box_mesh((0.235, 0.05, 0.245), m_mask), (0, 0.235, 0)),
        g.node("Neck", g.box_mesh((0.1, 0.07, 0.1), m_skin)),
    ]
    head = g.node("Head", None, (0, 1.5, 0), children=head_kids)

    torso_kids = [
        g.node("Chest", g.box_mesh((0.44, 0.48, 0.26), m_suit), (0, 0.24, 0)),
        g.node("Vest", g.box_mesh((0.46, 0.34, 0.29), m_vest), (0, 0.26, 0)),
        g.node("Pouch_L", g.box_mesh((0.1, 0.1, 0.07), m_boot), (-0.14, 0.12, -0.16)),
        g.node("Pouch_R", g.box_mesh((0.1, 0.1, 0.07), m_boot), (0.14, 0.12, -0.16)),
        g.node("Hips", g.box_mesh((0.36, 0.2, 0.24), m_suit), (0, -0.06, 0)),
        g.node("Belt", g.box_mesh((0.38, 0.06, 0.26), m_boot), (0, 0.02, 0)),
    ]
    torso = g.node("Torso", None, (0, 0.98, 0), children=torso_kids)

    def arm(side):
        s = -1 if side == "L" else 1
        gun_nodes = []
        if side == "R":
            gun_nodes = [
                g.node("AgentPistol", g.box_mesh((0.06, 0.07, 0.22), m_gun), (0, -0.44, -0.12)),
                g.node("AgentPistolGrip", g.box_mesh((0.05, 0.12, 0.07), m_gun), (0, -0.5, -0.02)),
                g.node("AgentMuzzle", None, (0, -0.44, -0.24)),
            ]
        kids = [
            g.node("UpperArm_" + side, g.box_mesh((0.12, 0.26, 0.13), m_suit), (0, -0.13, 0)),
            g.node("Elbow_" + side, g.box_mesh((0.115, 0.06, 0.125), m_vest), (0, -0.26, 0)),
            g.node("ForeArm_" + side, g.box_mesh((0.11, 0.24, 0.115), m_suit), (0, -0.38, 0)),
            g.node("Hand_" + side, g.box_mesh((0.1, 0.1, 0.11), m_skin), (0, -0.53, 0)),
        ] + gun_nodes
        return g.node("Arm_" + side, None, (s * 0.28, 1.42, 0), children=kids)

    def leg(side):
        s = -1 if side == "L" else 1
        kids = [
            g.node("Thigh_" + side, g.box_mesh((0.16, 0.44, 0.18), m_suit), (0, -0.22, 0)),
            g.node("Knee_" + side, g.box_mesh((0.155, 0.06, 0.175), m_vest), (0, -0.45, 0)),
            g.node("Shin_" + side, g.box_mesh((0.14, 0.4, 0.16), m_suit), (0, -0.67, 0)),
            g.node("Boot_" + side, g.box_mesh((0.16, 0.12, 0.28), m_boot), (0, -0.92, -0.04)),
        ]
        return g.node("Leg_" + side, None, (s * 0.13, 0.92, 0), children=kids)

    arm_l, arm_r = arm("L"), arm("R")
    leg_l, leg_r = leg("L"), leg("R")
    eye = g.node("EyePoint", None, (0, 1.62, -0.14))
    root = g.node("Agent", None, children=[torso, head, arm_l, arm_r, leg_l, leg_r, eye])
    return g.save(os.path.join(OUT, "agent.glb"), [root], "Agent"), len(g.nodes), len(g.meshes)


if __name__ == "__main__":
    for name, fn in (("map.glb", build_map), ("pistol.glb", build_pistol), ("agent.glb", build_agent)):
        size, nodes, meshes = fn()
        print("%-12s %8d bytes  nodes=%-4d meshes=%d" % (name, size, nodes, meshes))
