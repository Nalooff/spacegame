"""Tiny .tscn writer used to generate the scenes in this project (so every UI control,
spawner, synchronizer, etc. is a real node in the scene tree instead of being created in code)."""

class N:
    def __init__(s, name, type=None, props=None, kids=None, unique=False, script=None, groups=None, instance=None):
        s.name, s.type, s.props = name, type, dict(props or {})
        s.kids = list(kids or [])
        s.unique, s.script, s.groups, s.instance = unique, script, groups, instance

class Scene:
    def __init__(s, root):
        s.root = root
        s.ext = {}      # key -> (type, path)
        s.subs = []     # (id, type, [lines])
        s.conns = []    # (signal, from_path, method, binds)
    def ext_res(s, key, type, path):
        s.ext[key] = (type, path); return f'ExtResource("{key}")'
    def sub(s, id, type, **props):
        s.subs.append((id, type, [f"{k} = {v}" for k, v in props.items()])); return f'SubResource("{id}")'
    def connect(s, signal, from_path, method, binds=None, to="."):
        s.conns.append((signal, from_path, method, binds, to))
    def dump(s):
        out = []
        steps = len(s.ext) + len(s.subs) + 1
        out.append(f"[gd_scene load_steps={steps} format=3]\n")
        for k, (t, p) in s.ext.items():
            out.append(f'[ext_resource type="{t}" path="{p}" id="{k}"]')
        if s.ext: out.append("")
        for id, t, lines in s.subs:
            out.append(f'[sub_resource type="{t}" id="{id}"]')
            out.extend(lines); out.append("")
        def emit(n, parent):
            hdr = f'[node name="{n.name}"'
            if n.type: hdr += f' type="{n.type}"'
            if parent is not None: hdr += f' parent="{parent}"'
            if n.instance: hdr += f' instance={n.instance}'
            if n.groups: hdr += ' groups=[' + ", ".join(f'"{g}"' for g in n.groups) + ']'
            hdr += "]"
            out.append(hdr)
            if n.unique: out.append("unique_name_in_owner = true")
            if n.script: out.append(f"script = {n.script}")
            for k, v in n.props.items(): out.append(f"{k} = {v}")
            out.append("")
            child_parent = "." if parent is None else (n.name if parent == "." else f"{parent}/{n.name}")
            for c in n.kids: emit(c, child_parent)
        emit(s.root, None)
        def find(n, target, prefix):
            if n is target: return prefix
            for c in n.kids:
                r = find(c, target, (prefix + "/" + c.name) if prefix != "." else c.name)
                if r is not None: return r
            return None
        for sig, frm, m, binds, to in s.conns:
            if isinstance(frm, N): frm = find(s.root, frm, ".")
            if isinstance(to, N): to = find(s.root, to, ".")
            b = f" binds= [{binds}]" if binds else ""
            out.append(f'[connection signal="{sig}" from="{frm}" to="{to}" method="{m}"{b}]')
        return "\n".join(out) + "\n"

def path_of(*names):
    return "/".join(names)

# ---- small property helpers
def full_rect():
    return {"layout_mode": 3, "anchors_preset": 15, "anchor_right": 1.0, "anchor_bottom": 1.0,
            "grow_horizontal": 2, "grow_vertical": 2}

def s(text):  # quoted string
    return '"' + str(text).replace('\\', '\\\\').replace('"', '\\"').replace("\n", "\\n") + '"'

# ---- UI node factories (layout_mode 2 = child of a container)
def label(text, name="Label", unique=False, wrap=False, **extra):
    p = {"layout_mode": 2, "text": s(text)}
    if wrap: p["autowrap_mode"] = 3
    p.update(extra)
    return N(name, "Label", p, unique=unique)

def button(text, name, unique=False, **extra):
    p = {"layout_mode": 2, "text": s(text)}; p.update(extra)
    return N(name, "Button", p, unique=unique)

def hbox(name, kids, **extra):
    p = {"layout_mode": 2}; p.update(extra)
    return N(name, "HBoxContainer", p, kids)

def vbox(name, kids, unique=False, **extra):
    p = {"layout_mode": 2}; p.update(extra)
    return N(name, "VBoxContainer", p, kids, unique=unique)

def spin(name, mn, mx, step, val, unique=True, expand=True, **extra):
    p = {"layout_mode": 2, "min_value": mn, "max_value": mx, "step": step, "value": val}
    if expand: p["size_flags_horizontal"] = 3
    p.update(extra)
    return N(name, "SpinBox", p, unique=unique)

def line(name, text="", unique=True, **extra):
    p = {"layout_mode": 2, "text": s(text), "size_flags_horizontal": 3}; p.update(extra)
    return N(name, "LineEdit", p, unique=unique)

def sep(name="Sep"):
    return N(name, "HSeparator", {"layout_mode": 2})
