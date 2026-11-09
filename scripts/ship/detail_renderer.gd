class_name DetailRenderer
extends Node3D
## Draws the DETAIL layer of a ship (see DetailCatalog): a handful of meshes (details grouped by place) with
## shaders/detail.gdshader, plus a Label3D for each piece of text. Used by the game (HullRenderer) and by the builder.
##   var r := DetailRenderer.new();  parent.add_child(r);  r.setup(design);  r.flush()   # small ships: all at once
##   r.set_states(health_ratios)      # a module that is gone (ratio < 0) takes its details with it

const PER_MESH := 3000
const MESHES_PER_FRAME := 2
const SHADER := preload("res://shaders/detail.gdshader")
const CUSTOM_FORMAT := (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) \
	| (Mesh.ARRAY_CUSTOM_RG_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)

var _mat: ShaderMaterial
var _img: Image
var _tex: ImageTexture
var _jobs: Array = []                  # arrays of detail indexes, one per mesh still to create
var _design: ShipDesign
var _texts: Array = []                 # [Label3D, module]
var _nodes: Array = []


func setup(d: ShipDesign, selected: int = -1) -> void:
	clear()
	_design = d
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.set_shader_parameter("selected", float(selected) + 0.25 if selected >= 0 else -1.0)
	var n := maxi(d.modules.size(), 1)
	_img = Image.create(n, 1, false, Image.FORMAT_RG8)
	_img.fill(Color(1, 0, 0))
	_tex = ImageTexture.create_from_image(_img)
	_mat.set_shader_parameter("state_tex", _tex)
	_mat.set_shader_parameter("state_count", n)
	if d.details.is_empty():
		return
	var cell := maxf(d.extent_length() / 6.0, 8.0)
	var groups := {}
	var text_count := 0
	for i in d.details.size():
		var dt: Dictionary = d.details[i]
		if int(dt["k"]) == DetailCatalog.TEXT:
			if text_count < DetailCatalog.MAX_TEXTS:
				_add_text(dt)
				text_count += 1
			continue
		var p: Vector3 = dt["p"]
		var key := Vector3i(floori(p.x / cell), floori(p.y / cell), floori(p.z / cell))
		if not groups.has(key):
			groups[key] = []
		var list: Array = groups[key]
		list.append(i)
		if list.size() >= PER_MESH:
			_jobs.append(list)
			groups[key] = []
	for key in groups:
		if not (groups[key] as Array).is_empty():
			_jobs.append(groups[key])
	set_process(not _jobs.is_empty())


func clear() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	for t in _texts:
		if is_instance_valid(t[0]):
			(t[0] as Node).queue_free()
	_nodes.clear()
	_texts.clear()
	_jobs.clear()
	set_process(false)


func flush() -> void:
	while not _jobs.is_empty():
		_make_next()


func _process(_dt: float) -> void:
	for i in MESHES_PER_FRAME:
		if _jobs.is_empty():
			set_process(false)
			return
		_make_next()


func _make_next() -> void:
	var idx: Array = _jobs.pop_back()
	var arrays := build_arrays(_design.details, idx)
	if arrays.is_empty():
		return
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, CUSTOM_FORMAT)
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = _mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	_nodes.append(node)


## ratios[i] = health of module i (< 0 gone, 0 wreck, 1 new).
func set_states(ratios: PackedFloat32Array) -> void:
	if _img == null:
		return
	for i in _img.get_width():
		var r := ratios[i] if i < ratios.size() else 1.0
		_img.set_pixel(i, 0, Color(1.0 if r >= 0.0 else 0.0, 1.0 - clampf(r, 0.0, 1.0), 0))
	_tex.update(_img)
	for t in _texts:
		var m: int = t[1]
		(t[0] as Label3D).visible = m < 0 or m >= ratios.size() or ratios[m] >= 0.0


func set_night(v: float) -> void:
	if _mat:
		_mat.set_shader_parameter("night", v)


func _add_text(dt: Dictionary) -> void:
	var l := Label3D.new()
	l.text = str(dt["t"])
	var fnt := FontCatalog.get_font(int(dt.get("f", 0)))
	if fnt != null:
		l.font = fnt
	l.font_size = 64
	l.outline_size = 0
	l.double_sided = true
	l.modulate = dt["c"]
	l.shaded = true
	l.pixel_size = float(dt["h"]) / 64.0
	l.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
	add_child(l)
	var wid := l.get_aabb().size.x
	if wid > float(dt["w"]) and wid > 0.0:
		l.pixel_size *= float(dt["w"]) / wid
	var n: Vector3 = dt["n"]
	var b := DetailCatalog.frame(n, float(dt["a"]))
	l.transform = Transform3D(b, (dt["p"] as Vector3) + n * (0.03 + float(dt["h"]) * 0.01))
	_texts.append([l, int(dt["m"])])


# =====================================================================
#  Mesh arrays (pure function: thread safe)
# =====================================================================
static func build_arrays(details: Array, idx: Array) -> Array:
	var vs := PackedVector3Array()
	var ns := PackedVector3Array()
	var cs := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var c0 := PackedFloat32Array()
	var c1 := PackedFloat32Array()
	var ix := PackedInt32Array()
	for i in idx:
		var dt: Dictionary = details[i]
		var k: int = dt["k"]
		var b := DetailCatalog.frame(dt["n"], float(dt["a"]))
		var p: Vector3 = dt["p"]
		var w: float = dt["w"]
		var h: float = dt["h"]
		var col: Color = dt["c"]
		var c2: Color = dt["c2"]
		var dseed := float(i) + 0.25
		var aspect := w / maxf(h, 0.001)
		var mi := float(dt["m"])
		var opt: float = dt["g"]
		var faces: Array = []     # each: [normal, [4 corner points]]
		if k == DetailCatalog.CYLINDER:
			var rad := Vector2(w, h) * 0.5
			var tops: Array = []
			var base := p - b.z * float(dt["d"]) * 0.1
			var top := p + b.z * float(dt["d"])
			for s in 8:
				var a0 := TAU * s / 8.0
				var a1 := TAU * (s + 1) / 8.0
				var d0 := b.x * cos(a0) * rad.x + b.y * sin(a0) * rad.y
				var d1 := b.x * cos(a1) * rad.x + b.y * sin(a1) * rad.y
				var nm := (d0 + d1).normalized()
				faces.append([nm, [base + d0, base + d1, top + d1, top + d0]])
				tops.append(top + d0)
			# lid as 8 thin quads folded to the centre (keeps one code path)
			for s in 8:
				faces.append([b.z, [tops[s], tops[(s + 1) % 8], top, top]])
		elif DetailCatalog.is_solid(k):
			var hx := b.x * w * 0.5
			var hy := b.y * h * 0.5
			var lo := -b.z * float(dt["d"]) * 0.1
			var hi := b.z * float(dt["d"])
			var q := [p + lo - hx - hy, p + lo + hx - hy, p + lo + hx + hy, p + lo - hx + hy]
			var t := [p + hi - hx - hy, p + hi + hx - hy, p + hi + hx + hy, p + hi - hx + hy]
			faces.append([b.z, [t[0], t[1], t[2], t[3]]])
			faces.append([-b.y, [q[0], q[1], t[1], t[0]]])
			faces.append([b.x, [q[1], q[2], t[2], t[1]]])
			faces.append([b.y, [q[2], q[3], t[3], t[2]]])
			faces.append([-b.x, [q[3], q[0], t[0], t[3]]])
		else:
			var hx2 := b.x * w * 0.5
			var hy2 := b.y * h * 0.5
			faces.append([b.z, [p - hx2 - hy2, p + hx2 - hy2, p + hx2 + hy2, p - hx2 + hy2]])
		for f in faces:
			var base_i := vs.size()
			var corners: Array = f[1]
			var uvs := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
			for c in 4:
				vs.append(corners[c])
				ns.append(f[0])
				cs.append(col)
				uv.append(uvs[c])
				uv2.append(Vector2(float(k), dseed))
				c0.append_array([c2.r, c2.g, c2.b, aspect])
				c1.append_array([mi, opt])
			ix.append_array([base_i, base_i + 1, base_i + 2, base_i, base_i + 2, base_i + 3])
	if vs.is_empty():
		return []
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vs
	arrays[Mesh.ARRAY_NORMAL] = ns
	arrays[Mesh.ARRAY_COLOR] = cs
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	arrays[Mesh.ARRAY_CUSTOM0] = c0
	arrays[Mesh.ARRAY_CUSTOM1] = c1
	arrays[Mesh.ARRAY_INDEX] = ix
	return arrays
