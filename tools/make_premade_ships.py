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

S = 2.6          # metres per old unit: modules must be big enough to walk in (see ModuleCatalog.MIN_EXTENT)
DEFAULT_PRESET = {"thruster": "chemical", "turret": "light", "turret_barrel": "cannon", "commander": "bridge", "radar": "electronic", "antenna": "whip"}
KIND = {"cannon": "projectile", "railgun": "projectile", "beam": "beam", "electronic": "electronic", "thermal": "thermal"}

class B:
    def __init__(s, name, reactor=1.0, gyro=1.0):
        s.name, s.v, s.m, s.reactor, s.gyro = name, [], [], reactor, gyro
    def _add(s, typ, pts, faces, d=None, preset=None, stats=None, material=None, extra=None, cfg=None):
        ids = []
        for p in pts:
            key = tuple(round(c, 4) for c in p)
            if key in s.v: ids.append(s.v.index(key))      # same position = welded = linked
            else: s.v.append(key); ids.append(len(s.v)-1)
        m = {"type": typ, "faces": [[ids[i] for i in f] for f in faces]}
        if typ == "thruster": m["dir"] = list(d or (0,0,-1))
        if typ == "turret": m["dir"] = list(d or (0,1,0))     # dir = mount axis ("up" of the swivel)
        if typ in DEFAULT_PRESET:
            pid = preset or DEFAULT_PRESET[typ]
            m["cfg"] = {"preset": pid}
            if pid in KIND: m["cfg"]["kind"] = KIND[pid]
            if stats: m["cfg"]["stats"] = stats
            if cfg: m["cfg"].update(cfg)
        if extra: m.update(extra)
        if material: m["material"] = material
        s.m.append(m)
    def prim(s, typ, verts, faces, c, h, **k):
        """c and h in OLD units (multiplied by S)."""
        s.primm(typ, verts, faces, tuple(x*S for x in c), tuple(x*S for x in h), **k)
    def primm(s, typ, verts, faces, c, h, **k):
        """c and h in metres."""
        s._add(typ, [(c[0]+a*h[0], c[1]+b*h[1], c[2]+d*h[2]) for a,b,d in verts], faces, **k)
    def boxm(s, typ, c, h, **k): s.primm(typ, BOX, BOX_FACES, c, h, **k)
    def box(s, typ, c, h, **k): s.prim(typ, BOX, BOX_FACES, c, h, **k)
    def wedge(s, typ, c, h, **k): s.prim(typ, WEDGE, WEDGE_FACES, c, h, **k)
    def pyr(s, typ, c, h, **k): s.prim(typ, PYR, PYR_FACES, c, h, **k)
    def cyl(s, typ, c, h, **k): v, f = cylinder(12); s.prim(typ, v, f, c, h, **k)
    def dome(s, typ, c, h, **k): v, f = dome(12); s.prim(typ, v, f, c, h, **k)
    def cyl_z(s, typ, c, h, **k):
        v, f = cylinder(12); s.prim(typ, [(a, d, b) for a, b, d in v], f, c, h, **k)   # cylinder along Z (barrels)
    def turret(s, c, h=(0.8, 1.25, 0.8), flip=False, yaw=(-180.0, 180.0), pitch=(-10.0, 85.0), speed=None, preset="light", blen=1.8, brad=0.25, barrel="cannon", n_barrels=1):
        """Dual-part turret. c in OLD units, h in METRES (a base must be >= 1.2 m high). flip = hanging below.
        Barrels sit side by side along x; they touch the base so they can pivot."""
        sgn = -1.0 if flip else 1.0
        base = len(s.m)
        cm = tuple(x*S for x in c)
        ex = {"yaw_min": yaw[0], "yaw_max": yaw[1], "pitch_min": pitch[0] if not flip else -pitch[1], "pitch_max": pitch[1] if not flip else -pitch[0]}
        cfg = {"barrels": [base + 1 + i for i in range(n_barrels)]}
        st = {"turn_speed": speed} if speed else None
        v, f = dome(12)
        s.primm("turret", v, f, cm, (h[0], h[1] * sgn, h[2]), d=(0, sgn, 0), extra=ex, preset=preset, cfg=cfg, stats=st)
        for i in range(n_barrels):
            ox = (i - (n_barrels - 1) / 2.0) * brad * 2.4
            vv, ff = cylinder(12)
            s.primm("turret_barrel", [(a, d, b2) for a, b2, d in vv], ff, (cm[0] + ox, cm[1] + sgn * 0.375 * h[1], cm[2] + 0.26 - blen), (brad, brad, blen), preset=barrel)
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
            if "dir" in m: b += "\t\t\t\"dir\": %s,\n" % json.dumps([round(c, 4) for c in m["dir"]])
            if "cfg" in m: b += "\t\t\t\"cfg\": %s,\n" % json.dumps(m["cfg"])
            for k in ("yaw_min", "yaw_max", "pitch_min", "pitch_max"):
                if k in m: b += "\t\t\t\"%s\": %s,\n" % (k, m[k])
            b += "\t\t\t\"faces\": [\n" + ",\n".join("\t\t\t\t" + json.dumps(f) for f in m["faces"]) + "\n\t\t\t]\n\t\t}"
            blocks.append(b)
        L.append(",\n".join(blocks)); L.append("\t]"); L.append("}")
        open(path, "w").write("\n".join(L) + "\n")
        print("wrote", path, len(s.v), "vertices,", len(s.m), "modules")

def cmd(b, c, h, crew=2, preset="bridge"):
    """Commander box in metres (>= 1.9 m each way). seat_volume is set so that the box holds `crew` seats."""
    vol = 8 * h[0] * h[1] * h[2]
    b.boxm("commander", c, h, preset=preset, stats={"seat_volume": round(vol / crew * 0.98, 3)})

def dart():
    b = B("Dart")
    b.box("hull", (0,0,0.2), (0.6,0.4,1.3))
    cmd(b, (0, 0.4*S + 0.95, -0.3*S), (1.05, 0.95, 1.4), crew=2)
    z = -1.1
    b.pyr_pts("armor", [(x*S, y*S, zz*S) for x, y, zz in [(-0.6,-0.4,z),(0.6,-0.4,z),(0.6,0.4,z),(-0.6,0.4,z),(0,0,-2.6)]])
    b.box("armor", (-1.2,0,-0.9), (0.6,0.08,0.7)); b.box("armor", (1.2,0,-0.9), (0.6,0.08,0.7))   # wings sit ahead of the side thrusters (their exhaust cone must stay clear)
    b.cyl("thruster", (-0.4,0,1.65), (0.22,0.22,0.22), d=(0,0,-1))
    b.cyl("thruster", (0.4,0,1.65), (0.22,0.22,0.22), d=(0,0,-1))
    b.box("thruster", (-1.75,0,-1.72), (0.12,0.12,0.12), d=(0,0,1))   # braking thrusters sit on the wing tips: exhaust goes forward into free space
    b.box("thruster", (1.75,0,-1.72), (0.12,0.12,0.12), d=(0,0,1))
    for sx in (-1,1):
        b.box("thruster", (sx*0.72,0,0.6), (0.12,0.12,0.12), d=(-sx,0,0))
    b.box("thruster", (0,0.5,0.9), (0.12,0.1,0.12), d=(0,-1,0))
    b.box("thruster", (0,-0.5,0.9), (0.12,0.1,0.12), d=(0,1,0))
    b.turret((-0.95,0.08,-0.9)); b.turret((0.95,0.08,-0.9))
    b.cyl("antenna", (0.0,0.4+0.35,0.45), (0.1,0.35,0.1))     # communications antenna on the hull
    b.save()

def brick():
    b = B("Brick", reactor=1.3, gyro=1.5)
    b.box("hull", (0,0,0), (1.1,0.8,2.0))
    b.box("armor", (0,0,-2.1), (1.1,0.8,0.12))
    b.box("armor", (0,0.92,0), (1.1,0.12,2.0))
    cmd(b, (0, (0.8+0.24)*S + 1.0, -0.6*S), (1.3, 1.0, 1.6), crew=3)
    for sx in (-1,1):
        for sy in (-1,1):
            b.cyl("thruster", (sx*0.7,sy*0.5,2.3), (0.3,0.3,0.3), d=(0,0,-1))
    for sx in (-1,1):
        b.box("thruster", (sx*1.25,0,-1.6), (0.15,0.15,0.15), d=(0,0,1))
        b.box("thruster", (sx*1.25,0,1.6), (0.15,0.15,0.15), d=(-sx,0,0))
    b.box("thruster", (0,0.9,1.6), (0.15,0.1,0.15), d=(0,-1,0))
    b.box("thruster", (0,-0.9,1.6), (0.15,0.1,0.15), d=(0,1,0))
    b.box("radar", (0, 1.04+0.15, 0.9), (0.3, 0.15, 0.3), preset="electronic")      # big electronic radar on the roof
    # twin-barrel heavy turrets on the roof, one turret below
    b.turret((-0.6,1.04,1.2), (1.0,1.4,1.0), preset="heavy", n_barrels=2, brad=0.2)
    b.turret((0.6,1.04,1.2), (1.0,1.4,1.0), preset="heavy", n_barrels=2, brad=0.2)
    b.turret((0,-0.8,-0.5), (1.0,1.4,1.0), flip=True, preset="heavy", barrel="railgun", brad=0.22)
    b.cyl("antenna", (0.0,1.04+0.35,0.3), (0.1,0.35,0.1), preset="dish")
    b.save()

def scrap():
    """Asymmetric ship with thrusters at odd angles -> exercises torque handling."""
    b = B("Scrap Hauler", reactor=1.2, gyro=1.4)
    b.box("hull", (0,0,0), (0.8,0.5,1.4))
    b.wedge("hull", (0.0,0,-1.9), (0.8,0.5,0.5))
    cmd(b, (-0.3*S, 0.5*S + 1.0, -0.2*S), (1.2, 1.0, 1.4), crew=4, preset="cockpit")
    b.box("armor", (1.15,-0.1,0.3), (0.35,0.3,0.8))
    def unit(v):
        l = math.sqrt(sum(c*c for c in v)); return tuple(c/l for c in v)
    b.cyl("thruster", (-0.5,0.3,1.6), (0.2,0.2,0.2), d=unit((0.2,0.1,-1)))
    b.cyl("thruster", (0.7,-0.4,1.6), (0.2,0.2,0.2), d=unit((-0.1,0.2,-1)))
    b.box("thruster", (1.6,0.3,0.9), (0.15,0.15,0.15), d=unit((-1,-0.3,0.2)))
    b.box("thruster", (-0.9,0.0,-0.9), (0.15,0.15,0.15), d=unit((0.5,0.5,0.8)))
    b.box("thruster", (0.3,-0.6,-0.6), (0.15,0.1,0.15), d=unit((0,1,0.4)))
    b.box("thruster", (-0.6,0.6,0.6), (0.15,0.1,0.15), d=unit((0.1,-1,-0.2)))
    b.box("radar", (0.3, 0.5+0.15, 0.2), (0.25, 0.15, 0.25), preset="thermal")       # thermal radar: sees the heat of thrusters
    b.turret((0.5,0.5,-0.8))
    b.cyl("antenna", (0.55,0.5+0.35,0.9), (0.1,0.35,0.1))
    b.save()

def twin():
    """Two hulls joined by a thin bridge, a Commander on each: cut the bridge and it becomes TWO ships."""
    b = B("Twin Hull", reactor=1.2, gyro=1.2)
    for sx in (-1, 1):
        b.box("hull", (sx*1.6, 0, 0), (0.7, 0.4, 1.2))
    b.box("armor", (0, 0, 0), (0.9, 0.15, 0.5))                                   # the bridge (the weak link)
    for sx in (-1, 1):
        cmd(b, (sx*3.7, 0.4*S + 0.95, -0.3*S), (0.95, 0.95, 1.2), crew=2)
        b.cyl("thruster", (sx*1.6, 0, 1.42), (0.22, 0.22, 0.22), d=(0, 0, -1))
        b.box("thruster", (sx*1.6, 0, -1.32), (0.12, 0.12, 0.12), d=(0, 0, 1))
        b.box("thruster", (sx*2.42, 0, 0.5), (0.12, 0.12, 0.12), d=(-sx, 0, 0))
        b.box("thruster", (sx*1.6, -0.5, 0.2), (0.12, 0.12, 0.12), d=(0, 1, 0))
        b.box("thruster", (sx*2.3, 0.5, 0.2), (0.12, 0.1, 0.12), d=(0, -1, 0))
        b.turret((sx*1.6, 0.4, 0.7))
        b.cyl("antenna", (sx*1.6, 0.4+0.35, -0.6), (0.1, 0.35, 0.1))
    # each bridge controls the turret on ITS hull (a player only controls what their commander is linked to)
    cmds = [i for i, m in enumerate(b.m) if m["type"] == "commander"]
    guns = [i for i, m in enumerate(b.m) if m["type"] == "turret"]
    for c, g in zip(cmds, guns):
        b.m[c].setdefault("cfg", {})["links"] = [g]
    b.save()

dart(); brick(); scrap(); twin()
