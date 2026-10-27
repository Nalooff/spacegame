@tool
extends EditorPlugin
## VERTEX SHIPS editor plugin. Adds a "Ships" tab to the top of the editor (next to 2D / 3D / Script / Game):
##
##   list of the premade ships (res://ships/*), Open in builder, New ship, Validate all, Refresh.
##
## "Open in builder" / "New ship" run the ship builder (scenes/ship_builder.tscn) as a game window. A builder started from
## here (and only from here) shows the extra button "Save as PREMADE", which writes into res://ships/.
## The hand-over is two small files in user:// that the builder reads and deletes at start:
##   open_in_builder.txt  (ship to load)     premade_mode.txt  (switches the PREMADE button on for that one run)

const SHIP_DIR := "res://ships/"
const BUILDER_SCENE := "res://scenes/ship_builder.tscn"
const OPEN_FILE := "user://open_in_builder.txt"
const PREMADE_FLAG := "user://premade_mode.txt"

var _screen: VBoxContainer
var _list: ItemList
var _report: Label


func _has_main_screen() -> bool:
	return true


func _get_plugin_name() -> String:
	return "Ships"


func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_editor_theme().get_icon("Node3D", "EditorIcons")


func _make_visible(visible: bool) -> void:
	if _screen != null:
		_screen.visible = visible


func _enter_tree() -> void:
	_screen = VBoxContainer.new()
	_screen.name = "VertexShipsScreen"
	_screen.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var title := Label.new()
	title.name = "ShipsTitle"
	title.text = "Vertex Ships  -  premade ships (res://ships)"
	_screen.add_child(title)
	_list = ItemList.new()
	_list.name = "ShipList"
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_activated.connect(func(_i: int) -> void: _open_selected())
	_screen.add_child(_list)
	var row := HBoxContainer.new()
	row.name = "ButtonRow"
	_screen.add_child(row)
	for spec in [["Open in builder", _open_selected], ["New ship", _new_ship], ["Validate all", _validate_all], ["Refresh list", _refresh]]:
		var b := Button.new()
		b.name = (spec[0] as String).replace(" ", "") + "Button"
		b.text = spec[0]
		b.pressed.connect(spec[1])
		row.add_child(b)
	_report = Label.new()
	_report.name = "ReportLabel"
	_report.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_screen.add_child(_report)
	EditorInterface.get_editor_main_screen().add_child(_screen)
	_screen.visible = false
	_refresh()


func _exit_tree() -> void:
	if _screen != null:
		_screen.queue_free()


func _refresh() -> void:
	_list.clear()
	for f in DirAccess.get_files_at(SHIP_DIR):
		if f.ends_with(".json") or f.ends_with(".ship"):
			_list.add_item(f)


func _start_builder() -> void:
	var f := FileAccess.open(PREMADE_FLAG, FileAccess.WRITE)
	f.store_string("1")
	f.close()
	EditorInterface.play_custom_scene(BUILDER_SCENE)


func _open_selected() -> void:
	var sel := _list.get_selected_items()
	if sel.is_empty():
		_report.text = "Select a ship first."
		return
	var f := FileAccess.open(OPEN_FILE, FileAccess.WRITE)
	f.store_string(SHIP_DIR + _list.get_item_text(sel[0]))
	f.close()
	_start_builder()


func _new_ship() -> void:
	if FileAccess.file_exists(OPEN_FILE):
		DirAccess.remove_absolute(OPEN_FILE)
	_start_builder()


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
