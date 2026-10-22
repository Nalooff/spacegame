class_name UndoStack
extends RefCounted
## Undo / redo by snapshots: before each edit the builder pushes the whole design as a blob
## (ShipDesign.to_blob: JSON text for small ships, compressed binary for big ones).
## Simple and cannot get out of sync (no per-tool undo code). Memory is capped: the oldest steps are
## dropped when the snapshots add up to more than MAX_BYTES, so a huge ship keeps only a few steps.
##   undo.push(design.to_blob())                 before changing something
##   var blob := undo.undo(design.to_blob())     -> previous design (empty array if none)

const MAX_STEPS := 100
const MAX_BYTES := 256 * 1024 * 1024

var _undo: Array[PackedByteArray] = []
var _redo: Array[PackedByteArray] = []
var _bytes: int = 0


func push(snapshot: PackedByteArray) -> void:
	_undo.append(snapshot)
	_bytes += snapshot.size()
	while _undo.size() > MAX_STEPS or (_bytes > MAX_BYTES and _undo.size() > 1):
		_bytes -= _undo.pop_front().size()
	_redo.clear()


## Forget the newest snapshot (used when a move was cancelled).
func drop_last() -> void:
	if not _undo.is_empty():
		_bytes -= _undo.pop_back().size()


func can_undo() -> bool:
	return not _undo.is_empty()


func can_redo() -> bool:
	return not _redo.is_empty()


func undo(current: PackedByteArray) -> PackedByteArray:
	if _undo.is_empty():
		return PackedByteArray()
	_redo.append(current)
	var s: PackedByteArray = _undo.pop_back()
	_bytes -= s.size()
	return s


func redo(current: PackedByteArray) -> PackedByteArray:
	if _redo.is_empty():
		return PackedByteArray()
	_undo.append(current)
	_bytes += current.size()
	return _redo.pop_back()


func clear() -> void:
	_undo.clear()
	_redo.clear()
	_bytes = 0
