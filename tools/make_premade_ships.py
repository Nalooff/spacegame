#!/usr/bin/env python3
"""Generates res://ships/*.json (the premade ships) in the readable format ShipDesign.to_pretty_json() writes.
Coincident vertices of different modules are welded = 'linked'. Forward is -Z.
Primitive vertex/face layouts must match scripts/data/primitives.gd."""
import json, os, math

BOX = [(-1 if not i & 1 else 1, -1 if not i & 2 else 1, -1 if not i & 4 else 1) for i in range(8)]
BOX_FACES = [[0,1,3,2],[4,5,7,6],[0,1,5,4],[2,3,7,6],[0,2,6,4],[1,3,7,5]]
WEDGE = [(-1,-1,-1),(1,-1,-1),(-1,1,-1),(-1,-1,1),(1,-1,1),(-1,1,1)]
WEDGE_FACES = [[0,1,2],[3,4,5],[0,1,4,3],[1,2,5,4],[2,0,3,5]]
PYR = [(-1,-1,-1),(1,-1,-1),(1,-1,1),(-1,-1,1),(0,1,0)]
PYR_FACES = [[0,1,2,3],[0,1,4],[1,2,4],[2,3,4],[3,0,4]]

def cylinder(n):
    v = [(math.cos(math.tau*i/n), -1.0 + 2.0*r, math.sin(math.tau*i/n)) for r in range(2) for i in range(n)]
    f = [[i, (i+1)%n, n+(i+1)%n, n+i] for i in range(n)] + [list(range(n)), list(range(n, 2*n))]
    return v, f

def dome(n):
    steps = max(n//2, 4); steps += steps % 2; rows = steps//2
    v = [(0.0, 1.0, 0.0)]
    for r in range(1, rows+1):
        lat = math.pi*r/steps
        for i in range(n):
            a = math.tau*i/n; v.append((math.sin(lat)*math.cos(a), math.cos(lat), math.sin(lat)*math.sin(a)))
    f = [[0, 1+i, 1+(i+1)%n] for i in range(n)]
    for r in range(rows-1):
        for i in range(n):
            a = 1+r*n+i; b = 1+r*n+(i+1)%n; f.append([a, a+n, b+n, b])
    f.append([1+(rows-1)*n+i for i in range(n)])
    return v, f

class B:
    def __init__(s, name, reactor=1.0, gyro=1.0):
        s.name, s.v, s.m, s.reactor, s.gyro = name, [], [], reactor, gyro
    def _add(s, typ, pts, faces, d=None, power=None, crew=None, material=None, extra=None):
        ids = []
        for p in pts:
            key = tuple(round(c, 4) for c in p)
            if key in s.v: ids.append(s.v.index(key))      # same position = welded = linked
            else: s.v.append(key); ids.append(len(s.v)-1)
        m = {"type": typ, "faces": [[ids[i] for i in f] for f in faces]}
        if typ == "thruster": m["dir"] = list(d or (0,0,-1)); m["power"] = power or 2000.0
        if typ == "turret": m["dir"] = list(d or (0,1,0)); m["power"] = 0.0     # dir = mount axis ("up" of the swivel)
        if extra: m.update(extra)
        if crew: m["crew"] = crew
        if material: m["material"] = material
        s.m.append(m)
    def prim(s, typ, verts, faces, c, h, **k):
        s._add(typ, [(c[0]+a*h[0], c[1]+b*h[1], c[2]+d*h[2]) for a,b,d in verts], faces, **k)
    def box(s, typ, c, h, **k): s.prim(typ, BOX, BOX_FACES, c, h, **k)
    def wedge(s, typ, c, h, **k): s.prim(typ, WEDGE, WEDGE_FACES, c, h, **k)
    def pyr(s, typ, c, h, **k): s.prim(typ, PYR, PYR_FACES, c, h, **k)
    def cyl(s, typ, c, h, **k): v, f = cylinder(12); s.prim(typ, v, f, c, h, **k)
    def dome(s, typ, c, h, **k): v, f = dome(12); s.prim(typ, v, f, c, h, **k)
    def cyl_z(s, typ, c, h, **k):
        v, f = cylinder(12); s.prim(typ, [(a, d, b) for a, b, d in v], f, c, h, **k)   # cylinder along Z (barrels)
    def turret(s, c, h=(0.28, 0.25, 0.28), flip=False, yaw=(-180.0, 180.0), pitch=(-10.0, 85.0), speed=90.0, blen=0.4):
        """Dual-part turret: a dome base at c (mounted on a surface; flip = hanging below) and a barrel along -Z."""
        sgn = -1.0 if flip else 1.0
        base = len(s.m)
        ex = {"barrel": base + 1, "yaw_min": yaw[0], "yaw_max": yaw[1], "pitch_min": pitch[0] if not flip else -pitch[1], "pitch_max": pitch[1] if not flip else -pitch[0], "turn_speed": speed}
        s.dome("turret", c, (h[0], h[1] * sgn, h[2]), d=(0, sgn, 0), extra=ex)
        s.cyl_z("turret_barrel", (c[0], c[1] + sgn * 0.375 * h[1], c[2] + 0.1 - blen), (0.06, 0.06, blen))
    def pyr_pts(s, typ, pts, **k): s._add(typ, pts, PYR_FACES, **k)
    def save(s):
        out = {"name": s.name, "reactor_scale": s.reactor, "gyro_scale": s.gyro, "vertices": [list(v) for v in s.v], "modules": s.m}
        path = os.path.join(os.path.dirname(__file__), "..", "ships", s.name + ".json")
        L = ["{", f'\t"name": {json.dumps(s.name)},', f'\t"reactor_scale": {s.reactor},', f'\t"gyro_scale": {s.gyro},', '\t"vertices": [']
        L.append(",\n".join("\t\t[%s, %s, %s]" % tuple(round(c, 4) for c in v) for v in s.v)); L.append("\t],"); L.append('\t"modules": [')
        blocks = []
        for m in s.m:
            b = "\t\t{\n\t\t\t\"type\": %s,\n" % json.dumps(m["type"])
            if "material" in m: b += "\t\t\t\"material\": %s,\n" % json.dumps(m["material"])
            if "crew" in m: b += "\t\t\t\"crew\": %d,\n" % m["crew"]
            if "dir" in m: b += "\t\t\t\"dir\": %s,\n\t\t\t\"power\": %s,\n" % (json.dumps([round(c, 4) for c in m["dir"]]), m["power"])
            for k in ("barrel", "yaw_min", "yaw_max", "pitch_min", "pitch_max", "turn_speed"):
                if k in m: b += "\t\t\t\"%s\": %s,\n" % (k, m[k])
            b += "\t\t\t\"faces\": [\n" + ",\n".join("\t\t\t\t" + json.dumps(f) for f in m["faces"]) + "\n\t\t\t]\n\t\t}"
            blocks.append(b)
        L.append(",\n".join(blocks)); L.append("\t]"); L.append("}")
        open(path, "w").write("\n".join(L) + "\n")
        print("wrote", path, len(s.v), "vertices,", len(s.m), "modules")

def dart():
    b = B("Dart")
    b.box("hull", (0,0,0.2), (0.6,0.4,1.3))
    b.box("commander", (0,0.65,-0.3), (0.4,0.25,0.5), crew=2)
    z = -1.1
    b.pyr_pts("armor", [(-0.6,-0.4,z),(0.6,-0.4,z),(0.6,0.4,z),(-0.6,0.4,z),(0,0,-2.6)])
    b.box("armor", (-1.2,0,-0.9), (0.6,0.08,0.7)); b.box("armor", (1.2,0,-0.9), (0.6,0.08,0.7))   # wings sit ahead of the side thrusters (their exhaust cone must stay clear)
    b.cyl("thruster", (-0.4,0,1.65), (0.22,0.22,0.22), d=(0,0,-1), power=3200.0)
    b.cyl("thruster", (0.4,0,1.65), (0.22,0.22,0.22), d=(0,0,-1), power=3200.0)
    b.box("thruster", (-1.2,0,-1.72), (0.12,0.12,0.12), d=(0,0,1), power=1400.0)   # braking thrusters sit on the wing tips: exhaust goes forward into free space
    b.box("thruster", (1.2,0,-1.72), (0.12,0.12,0.12), d=(0,0,1), power=1400.0)
    for sx in (-1,1):
        b.box("thruster", (sx*0.72,0,0.6), (0.12,0.12,0.12), d=(-sx,0,0), power=900.0)
    b.box("thruster", (0,0.52,0.9), (0.12,0.1,0.12), d=(0,-1,0), power=900.0)
    b.box("thruster", (0,-0.52,0.9), (0.12,0.1,0.12), d=(0,1,0), power=900.0)
    b.turret((-1.25,0.08,-0.9), yaw=(-150.0, 150.0)); b.turret((1.25,0.08,-0.9), yaw=(-150.0, 150.0))
    b.save()

def brick():
    b = B("Brick", reactor=1.3, gyro=1.5)
    b.box("hull", (0,0,0), (1.1,0.8,2.0))
    b.box("armor", (0,0,-2.1), (1.1,0.8,0.12))
    b.box("armor", (0,0.92,0), (1.1,0.12,2.0))
    b.box("commander", (0,0.8+0.24+0.4,-0.6), (0.5,0.4,0.6), crew=3)
    for sx in (-1,1):
        for sy in (-1,1):
            b.cyl("thruster", (sx*0.7,sy*0.5,2.3), (0.3,0.3,0.3), d=(0,0,-1), power=4500.0)
    for sx in (-1,1):
        b.box("thruster", (sx*1.25,0,-1.6), (0.15,0.15,0.15), d=(0,0,1), power=1800.0)
        b.box("thruster", (sx*1.25,0,1.6), (0.15,0.15,0.15), d=(-sx,0,0), power=1100.0)
    b.box("thruster", (0,0.9,1.6), (0.15,0.1,0.15), d=(0,-1,0), power=1100.0)
    b.box("thruster", (0,-0.9,1.6), (0.15,0.1,0.15), d=(0,1,0), power=1100.0)
    b.turret((-0.6,1.04,1.2), (0.35,0.3,0.35), speed=70.0); b.turret((0.6,1.04,1.2), (0.35,0.3,0.35), speed=70.0)
    b.turret((0,-0.8,-0.5), (0.35,0.3,0.35), flip=True, speed=70.0)
    b.save()

def scrap():
    """Asymmetric ship with thrusters at odd angles -> exercises torque handling."""
    b = B("Scrap Hauler", reactor=1.2, gyro=1.4)
    b.box("hull", (0,0,0), (0.8,0.5,1.4))
    b.wedge("hull", (0.0,0,-1.9), (0.8,0.5,0.5))
    b.box("commander", (-0.3,0.7,-0.2), (0.35,0.2,0.4), crew=4)
    b.box("armor", (1.15,-0.1,0.3), (0.35,0.3,0.8))
    def unit(v):
        l = math.sqrt(sum(c*c for c in v)); return tuple(c/l for c in v)
    b.cyl("thruster", (-0.5,0.3,1.6), (0.2,0.2,0.2), d=unit((0.2,0.1,-1)), power=3600.0)
    b.cyl("thruster", (0.7,-0.4,1.6), (0.2,0.2,0.2), d=unit((-0.1,0.2,-1)), power=2400.0)
    b.box("thruster", (1.6,0.3,0.9), (0.15,0.15,0.15), d=unit((-1,-0.3,0.2)), power=1200.0)
    b.box("thruster", (-0.9,0.0,-0.9), (0.15,0.15,0.15), d=unit((0.5,0.5,0.8)), power=1500.0)
    b.box("thruster", (0.3,-0.6,-0.6), (0.15,0.1,0.15), d=unit((0,1,0.4)), power=1000.0)
    b.box("thruster", (-0.6,0.62,0.6), (0.15,0.1,0.15), d=unit((0.1,-1,-0.2)), power=1000.0)
    b.turret((0.5,0.5,-0.8))
    b.save()

def twin():
    """Two hulls joined by a thin bridge, a Commander on each: cut the bridge and it becomes TWO ships."""
    b = B("Twin Hull", reactor=1.2, gyro=1.2)
    for sx in (-1, 1):
        b.box("hull", (sx*1.6, 0, 0), (0.7, 0.4, 1.2))
    b.box("armor", (0, 0, 0), (0.9, 0.15, 0.5))                                   # the bridge (the weak link)
    for sx in (-1, 1):
        b.box("commander", (sx*1.6, 0.65, -0.3), (0.3, 0.25, 0.4), crew=2)
        b.cyl("thruster", (sx*1.6, 0, 1.42), (0.22, 0.22, 0.22), d=(0, 0, -1), power=2500.0)
        b.box("thruster", (sx*1.6, 0, -1.32), (0.12, 0.12, 0.12), d=(0, 0, 1), power=1200.0)
        b.box("thruster", (sx*2.42, 0, 0.5), (0.12, 0.12, 0.12), d=(-sx, 0, 0), power=800.0)
        b.box("thruster", (sx*1.6, -0.52, 0.2), (0.12, 0.12, 0.12), d=(0, 1, 0), power=800.0)
        b.box("thruster", (sx*2.2, 0.52, 0.2), (0.12, 0.12, 0.12), d=(0, -1, 0), power=800.0)
        b.turret((sx*1.6, 0.4, 0.7))
    b.save()

dart(); brick(); scrap(); twin()
