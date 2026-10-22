class_name HullRenderer
extends Node3D
## Draws a ship's hull. Every module is cut into spatial CHUNKS (about FACES_PER_CHUNK faces each),
## one MeshInstance3D per chunk. Why:
##   * the GPU only draws chunks that are on screen, and a dent only rebuilds the 1-3 chunks around it
##   * a 2-million-vertex ship is hundreds of small meshes instead of one giant mesh to rebuild
## The meshes hold only positions + indices (colour and flat shading come from shaders/hull.gdshader,
## one material per module). The chunk MeshInstance3D nodes are created in code on purpose: how many
## there are depends on the ship.
##
## Usage (see Ship):
##   var prepared := HullRenderer.prepare(design)     # heavy, may run in a worker thread
##   hull.attach(design, prepared)                    # main thread; meshes appear a few per frame
##   hull.set_health(ratios)                          # tint / hide destroyed modules
##   hull.rebuild(changed_faces)                      # after a dent

const FACES_PER_CHUNK := 8000
const MESHES_PER_FRAME := 6

@export var shader: Shader

var design: ShipDesign
## per module: {chunks: Array[Dictionary], face_chunk: PackedInt32Array, lo: Vector3, size: Vector3, dims: int, cells: Dictionary, material}
var _mods: Array = []
var _queue: Array = []     # [module, chunk index] waiting for its mesh to be created
var _health: PackedFloat32Array = PackedFloat32Array()
var _scratch := PackedInt32Array()   # vertex id -> local index while building one chunk (all -1 between uses)


# =====================================================================
#  Heavy part: split into chunks and build the mesh arrays (thread safe, creates no nodes)
# =====================================================================
static func prepare(d: ShipDesign) -> Array:
	var out: Array = []
	var map := PackedInt32Array()
	map.resize(d.vertices.size())
	map.fill(-1)
	for mi in d.modules.size():
		var fs: FaceSet = d.modules[mi]["fs"]
		# bounding box of the module
		var lo := Vector3(INF, INF, INF)
		var hi := Vector3(-INF, -INF, -INF)
		for fi in fs.count():
			if fs.sizes[fi] > 0:
				var v := d.vertices[fs.ids[fs.starts[fi]]]
				lo = lo.min(v)
				hi = hi.max(v)
		if lo.x == INF:
			out.append({"chunk_faces": [], "face_chunk": PackedInt32Array(), "lo": Vector3.ZERO, "size": Vector3.ONE, "dims": 1, "arrays": []})
			continue
		var size := (hi - lo).max(Vector3.ONE * 0.001)
		var dims := clampi(int(ceil(pow(fs.alive_count() / float(FACES_PER_CHUNK), 1.0 / 3.0))), 1, 8)
		var cell_chunk := {}
		var chunk_faces: Array = []   # Array of Array (plain arrays append by reference)
		var face_chunk := PackedInt32Array()
		face_chunk.resize(fs.count())
		face_chunk.fill(-1)
		for fi in fs.count():
			if fs.sizes[fi] == 0:
				continue
			var v := d.vertices[fs.ids[fs.starts[fi]]]
			var cell := _cell_of(v, lo, size, dims)
			var ci: int = cell_chunk.get(cell, -1)
			if ci < 0:
				ci = chunk_faces.size()
				cell_chunk[cell] = ci
				chunk_faces.append([])
			(chunk_faces[ci] as Array).append(fi)
			face_chunk[fi] = ci
		var arrays: Array = []
		for ci in chunk_faces.size():
			arrays.append(build_arrays(d, mi, PackedInt32Array(chunk_faces[ci]), map))
		out.append({"chunk_faces": chunk_faces, "face_chunk": face_chunk, "lo": lo, "size": size, "dims": dims,
			"cells": cell_chunk, "arrays": arrays})
	return out


static func _cell_of(v: Vector3, lo: Vector3, size: Vector3, dims: int) -> int:
	var r := ((v - lo) / size * dims).floor()
	var x := clampi(int(r.x), 0, dims - 1)
	var y := clampi(int(r.y), 0, dims - 1)
	var z := clampi(int(r.z), 0, dims - 1)
	return x + y * dims + z * dims * dims


## Mesh arrays (positions + indices) for the given faces. `map` is a scratch array of -1 (size = vertex count),
## returned to -1 afterwards.
static func build_arrays(d: ShipDesign, mi: int, faces: PackedInt32Array, map: PackedInt32Array) -> Array:
	var fs: FaceSet = d.modules[mi]["fs"]
	var verts := PackedVector3Array()
	var indices := PackedInt32Array()
	var used := PackedInt32Array()
	for fi in faces:
		var n := fs.sizes[fi]
		if n < 3:
			continue
		var s := fs.starts[fi]
		var first := -1
		var prev := -1
		for k in n:
			var id := fs.ids[s + k]
			var li := map[id]
			if li < 0:
				li = verts.size()
				map[id] = li
				verts.append(d.vertices[id])
				used.append(id)
			if k == 0:
				first = li
			elif k >= 2:
				indices.append(first)
				indices.append(prev)
				indices.append(li)
			prev = li
	for id in used:
		map[id] = -1
	if indices.is_empty():
		return []
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = indices
	return arrays


# =====================================================================
#  Main thread: nodes, materials, health
# =====================================================================
func attach(d: ShipDesign, prepared: Array) -> void:
	design = d
	for mi in prepared.size():
		var info: Dictionary = prepared[mi]
		var chunks: Array = []
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("base_color", ModuleCatalog.color_of(d.modules[mi]["type"]))
		var cell_chunk: Dictionary = info.get("cells", {})
		for ci in info["chunk_faces"].size():
			chunks.append({"faces": PackedInt32Array(info["chunk_faces"][ci]), "node": null, "arrays": info["arrays"][ci]})
			_queue.append([mi, ci])
		_mods.append({"chunks": chunks, "face_chunk": info["face_chunk"], "lo": info["lo"], "size": info["size"],
			"dims": info["dims"], "cells": cell_chunk, "material": mat})
	set_process(true)


## Create meshes now (small ships) instead of spreading them over frames.
func flush() -> void:
	while not _queue.is_empty():
		_make_next()


func _process(_dt: float) -> void:
	for i in MESHES_PER_FRAME:
		if _queue.is_empty():
			set_process(false)
			return
		_make_next()


func _make_next() -> void:
	var job: Array = _queue.pop_front()
	var chunk: Dictionary = _mods[job[0]]["chunks"][job[1]]
	var arrays: Array = chunk["arrays"]
	chunk["arrays"] = []
	if arrays.is_empty():
		return
	var node := MeshInstance3D.new()
	node.name = "Module%d_Chunk%d" % [job[0], job[1]]
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	node.mesh = mesh
	node.material_override = _mods[job[0]]["material"]
	node.visible = job[0] >= _health.size() or _health[job[0]] > 0.0
	chunk["node"] = node
	add_child(node)


## ratios[i] = module health 0..1. A destroyed module (0) disappears.
func set_health(ratios: PackedFloat32Array) -> void:
	_health = ratios
	for mi in _mods.size():
		var r := ratios[mi] if mi < ratios.size() else 1.0
		(_mods[mi]["material"] as ShaderMaterial).set_shader_parameter("damage", 1.0 - clampf(r, 0.0, 1.0))
		for chunk in _mods[mi]["chunks"]:
			if chunk["node"] != null:
				(chunk["node"] as MeshInstance3D).visible = r > 0.0


## After a dent: `changed` = {module: PackedInt32Array of faces whose shape changed or that are new}.
## Rebuilds only the chunks those faces belong to.
func rebuild(changed: Dictionary) -> void:
	var map := _scratch
	var old_size := map.size()
	map.resize(design.vertices.size())          # grows when a dent added vertices
	if old_size == 0:
		map.fill(-1)
	else:
		for i in range(old_size, map.size()):
			map[i] = -1
	_scratch = map
	for mi in changed:
		var info: Dictionary = _mods[mi]
		var fs: FaceSet = design.modules[mi]["fs"]
		var face_chunk: PackedInt32Array = info["face_chunk"]
		if face_chunk.size() < fs.count():
			var old := face_chunk.size()
			face_chunk.resize(fs.count())
			for i in range(old, face_chunk.size()):
				face_chunk[i] = -1
		var dirty := {}
		for fi in changed[mi]:
			if face_chunk[fi] < 0: # a face made by a dent: put it in the chunk of its place
				var v := design.vertices[fs.ids[fs.starts[fi]]]
				var cell := _cell_of(v, info["lo"], info["size"], info["dims"])
				var ci: int = info["cells"].get(cell, -1)
				if ci < 0:
					ci = info["chunks"].size()
					info["cells"][cell] = ci
					info["chunks"].append({"faces": PackedInt32Array(), "node": null, "arrays": []})
				var list: PackedInt32Array = info["chunks"][ci]["faces"]
				list.append(fi)
				info["chunks"][ci]["faces"] = list
				face_chunk[fi] = ci
			dirty[face_chunk[fi]] = true
		info["face_chunk"] = face_chunk
		for ci in dirty:
			var chunk: Dictionary = info["chunks"][ci]
			# drop dead faces from the list while we are here
			var alive := PackedInt32Array()
			for fi in (chunk["faces"] as PackedInt32Array):
				if fs.sizes[fi] > 0:
					alive.append(fi)
			chunk["faces"] = alive
			var arrays := build_arrays(design, mi, alive, map)
			var node: MeshInstance3D = chunk["node"]
			if node == null:
				node = MeshInstance3D.new()
				node.name = "Module%d_Chunk%d" % [mi, ci]
				node.material_override = info["material"]
				chunk["node"] = node
				add_child(node)
			var mesh := ArrayMesh.new()
			if not arrays.is_empty():
				mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			node.mesh = mesh
