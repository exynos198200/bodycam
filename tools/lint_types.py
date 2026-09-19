"""Flags `:=` declarations whose right-hand side has no static type in GDScript.

Godot cannot infer types from Variant expressions (Object.get(), members of
untyped variables, Dictionary/Array elements), which raises
"Cannot infer the type of X variable" at parse time.
"""
import os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCRIPTS = os.path.join(ROOT, "scripts")

# Variables intentionally left untyped for cross-script dynamic access.
UNTYPED_VARS = ("_player", "_nav", "_fx", "_owner_node", "controls", "player",
                "enemy", "hud", "overlay", "weapon", "fx")

decl = re.compile(r'^\s*var\s+([A-Za-z_][A-Za-z0-9_]*)\s*:=\s*(.+?)\s*$')
problems = []

for fname in sorted(os.listdir(SCRIPTS)):
    if not fname.endswith(".gd"):
        continue
    path = os.path.join(SCRIPTS, fname)
    lines = open(path, encoding="utf-8").read().split("\n")
    for i, line in enumerate(lines, 1):
        m = decl.match(line)
        if not m:
            continue
        name, rhs = m.group(1), m.group(2)
        if ".get(" in rhs or re.search(r'\w\[', rhs):
            problems.append("%s:%d  %s := %s   (Variant source)" % (fname, i, name, rhs))
            continue
        for v in UNTYPED_VARS:
            # e.g. `var x := _player.global_position` - member of an untyped var
            if re.search(r'(^|[^A-Za-z0-9_])%s\.' % re.escape(v), rhs):
                problems.append("%s:%d  %s := %s   (member of untyped %s)"
                                % (fname, i, name, rhs, v))
                break

if problems:
    print("TYPE INFERENCE PROBLEMS (%d):" % len(problems))
    for p in problems:
        print("  - %s" % p)
    sys.exit(1)
print("type inference ok  (no `:=` declared from an untyped expression)")
