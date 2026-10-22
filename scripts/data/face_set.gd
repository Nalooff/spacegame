class_name FaceSet
extends RefCounted
## All polygon faces of ONE module, stored flat so millions of faces stay cheap.
##   ids    every face's vertex ids one after another  [a0 a1 a2 a3  b0 b1 b2  ...]
##   sizes  how many ids each face has                 [4 3 ...]
##   starts where each face begins inside `ids`
## A face index never changes while the ship flies: a replaced face is only "killed" (size 0) and
## the new faces are appended at the end. compact() removes the dead ones (done when saving).
## Faces are kept wound OUTWARD (see ShipDesign.fix_winding), so triangulating = fanning.

var ids: PackedInt32Array = PackedInt32Array()
var sizes: PackedInt32Array = PackedInt32Array()
var starts: PackedInt32Array = PackedInt32Array()
var dead: int = 0


func count() -> int:
	return sizes.size()


func alive_count() -> int:
	return sizes.size() - dead


func is_alive(fi: int) -> bool:
	return sizes[fi] > 0


## Append a face, returns its index.
func append(loop: PackedInt32Array) -> int:
	starts.append(ids.size())
	sizes.append(loop.size())
	ids.append_array(loop)
	return sizes.size() - 1


func face(fi: int) -> PackedInt32Array:
	var s := starts[fi]
	return ids.slice(s, s + sizes[fi])


func kill(fi: int) -> void:
	if sizes[fi] > 0:
		sizes[fi] = 0
		dead += 1


## Overwrite a face with a loop of the SAME length (in place).
func overwrite(fi: int, loop: PackedInt32Array) -> void:
	var s := starts[fi]
	for k in loop.size():
		ids[s + k] = loop[k]


func reverse(fi: int) -> void:
	var s := starts[fi]
	var n := sizes[fi]
	for k in n >> 1:
		var t := ids[s + k]
		ids[s + k] = ids[s + n - 1 - k]
		ids[s + n - 1 - k] = t


func duplicate() -> FaceSet:
	var c := FaceSet.new()
	c.ids = ids.duplicate()
	c.sizes = sizes.duplicate()
	c.starts = starts.duplicate()
	c.dead = dead
	return c


## Drop dead faces (face indices change!). Call only when nothing holds face indices.
func compact() -> void:
	if dead == 0:
		return
	var nids := PackedInt32Array()
	var nsizes := PackedInt32Array()
	var nstarts := PackedInt32Array()
	for fi in sizes.size():
		var n := sizes[fi]
		if n == 0:
			continue
		nstarts.append(nids.size())
		nsizes.append(n)
		nids.append_array(ids.slice(starts[fi], starts[fi] + n))
	ids = nids
	sizes = nsizes
	starts = nstarts
	dead = 0


static func from_array(faces: Array) -> FaceSet:
	var fs := FaceSet.new()
	for f in faces:
		fs.append(f as PackedInt32Array)
	return fs


## Alive faces as an array of loops (what the builder's editing code works with).
func to_array() -> Array[PackedInt32Array]:
	var out: Array[PackedInt32Array] = []
	for fi in sizes.size():
		if sizes[fi] > 0:
			out.append(face(fi))
	return out


## Rebuild `starts` from `sizes` (after loading).
func rebuild_starts() -> void:
	starts.resize(sizes.size())
	var s := 0
	for fi in sizes.size():
		starts[fi] = s
		s += sizes[fi]
