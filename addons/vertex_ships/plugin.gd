@tool
extends EditorPlugin
## VERTEX SHIPS editor plugin: a dock to manage the premade ships (res://ships/*.json) without leaving the editor.
##
##   Open in builder   runs the ship builder (scenes/ship_builder.tscn) with the selected ship loaded
##   New ship          runs the builder with a fresh starter ship
##   Validate all      runs ShipDesign.validate() on every ship file and lists the problems
##
## Inside the builder (started from here) the extra button "Save as PREMADE" writes to res://ships/ so the ship ships with
## the game; the normal "Save" writes to the player folder (user://ships/).
## Handing the ship over to the builder goes through user://open_in_builder.txt (both processes share user://).

const SHIP_DIR := "res://ships/"
const BUILDER_SCENE := "res://scenes/ship_builder.tscn"
const OPEN_FILE := "user://open_in_builder.txt"

var _dock: VBoxContainer
var _list: ItemList
var _report: Label


func _enter_tree() -> void:
	_dock = VBoxContainer.new()
	_dock.name = "Vertex Ships"
	var title := Label.new()
	title.name = "ShipsTitle"
	title.text = "Premade ships (res://ships)"
	_dock.add_child(title)
	_list = ItemList.new()
	_list.name = "ShipList"
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.custom_minimum_size = Vector2(0, 120)
	_list.item_activated.connect(func(_i: int) -> void: _open_selected())
	_dock.add_child(_list)
	for spec in [["Open in builder", _open_selected], ["New ship", _new_ship], ["Validate all", _validate_all], ["Refresh list", _refresh]]:
		var b := Button.new()
		b.name = (spec[0] as String).replace(" ", "") + "Button"
		b.text = spec[0]
		b.pressed.connect(spec[1])
		_dock.add_child(b)
	_report = Label.new()
	_report.name = "ReportLabel"
	_report.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dock.add_child(_report)
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)
	_refresh()


func _exit_tree() -> void:
	if _dock != null:
		remove_control_from_docks(_dock)
		_dock.queue_free()


func _refresh() -> void:
	_list.clear()
	for f in DirAccess.get_files_at(SHIP_DIR):
		if f.ends_with(".json") or f.ends_with(".ship"):
			_list.add_item(f)


func _open_selected() -> void:
	var sel := _list.get_selected_items()
	if sel.is_empty():
		_report.text = "Select a ship first."
		return
	var f := FileAccess.open(OPEN_FILE, FileAccess.WRITE)
	f.store_string(SHIP_DIR + _list.get_item_text(sel[0]))
	f.close()
	EditorInterface.play_custom_scene(BUILDER_SCENE)


func _new_ship() -> void:
	if FileAccess.file_exists(OPEN_FILE):
		DirAccess.remove_absolute(OPEN_FILE)
	EditorInterface.play_custom_scene(BUILDER_SCENE)


func _validate_all() -> void:
	var lines: Array[String] = []
	var bad := 0
	for i in _list.item_count:
		var path := SHIP_DIR + _list.get_item_text(i)
		var d := ShipDesign.load_file(path)
		if d == null:
			lines.append("%s: cannot be read" % path)
			bad += 1
			continue
		var errors := d.validate()
		if not errors.is_empty():
			bad += 1
			lines.append("%s: %s" % [_list.get_item_text(i), errors[0]] + (" (+%d more)" % (errors.size() - 1) if errors.size() > 1 else ""))
	_report.text = "All %d ships are valid." % _list.item_count if bad == 0 else "\n".join(lines)
