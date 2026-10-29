@tool
extends EditorPlugin
## VERTEX SHIPS editor plugin. Adds a "Ships" tab to the top of the editor (next to 2D / 3D / Script / Game).
## You manage ships INSIDE the editor, no scene is launched for any of it:
##
##   New ship / Duplicate / Delete / Info / Validate all   -> run in a background Godot (tools/ship_cli.gd), headless,
##                                                            so they use the real game code. Nothing starts, no window opens.
##   Open in builder (shape the vertices)                  -> runs the ship builder scene. It is switched to the editor's
##                                                            EMBEDDED game view (Game tab) so it opens inside the editor,
##                                                            not as a separate window. A builder started from here (and
##                                                            only from here) shows the extra button "Save as PREMADE".
## The builder hand-over is two small files in user:// that the builder reads and deletes at start:
##   open_in_builder.txt  (ship to load)     premade_mode.txt  (switches the PREMADE button on for that one run)

const SHIP_DIR := "res://ships/"
const BUILDER_SCENE := "res://scenes/ship_builder.tscn"
const CLI_SCENE := "res://tools/ship_cli.tscn"
const OPEN_FILE := "user://open_in_builder.txt"
const PREMADE_FLAG := "user://premade_mode.txt"
const EMBED_SETTING := "run/window_placement/game_embed_mode"

var _screen: VBoxContainer
var _list: ItemList
var _report: Label
var _name_edit: LineEdit


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
	_list.item_selected.connect(func(_i: int) -> void: _info())
	_screen.add_child(_list)
	var name_row := HBoxContainer.new()
	name_row.name = "NameRow"
	var nl := Label.new()
	nl.text = "Name for New / Duplicate:"
	name_row.add_child(nl)
	_name_edit = LineEdit.new()
	_name_edit.name = "NameEdit"
	_name_edit.placeholder_text = "My Ship"
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(_name_edit)
	_screen.add_child(name_row)
	var row := HBoxContainer.new()
	row.name = "ButtonRow"
	_screen.add_child(row)
	for spec in [["New ship", _new_ship], ["Duplicate", _duplicate], ["Delete", _delete], ["Info", _info], ["Validate all", _validate_all],
			["Open in builder", _open_selected], ["Open empty builder", _open_empty], ["Refresh list", _refresh]]:
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
			_list.add_item(f.get_basename())


func _selected() -> String:
	var sel := _list.get_selected_items()
	return _list.get_item_text(sel[0]) if not sel.is_empty() else ""


## Run tools/ship_cli.tscn in a background headless Godot and return what it printed (no window, no scene of the game).
func _cli(args: Array) -> String:
	var out := []
	var full := ["--headless", "--path", ProjectSettings.globalize_path("res://"), CLI_SCENE, "--"]
	full.append_array(args)
	var code := OS.execute(OS.get_executable_path(), full, out, true)
	var lines: Array[String] = []
	for line in (out[0] if not out.is_empty() else "").split("\n"):
		if line.strip_edges() != "" and not line.begins_with("Godot Engine"):
			lines.append(line)
	if code != 0 and lines.is_empty():
		lines.append("ERROR: the background Godot did not run (exit code %d)" % code)
	return "\n".join(lines)


func _after_change(text: String) -> void:
	_report.text = text.trim_suffix("\nOK")
	EditorInterface.get_resource_filesystem().scan()
	_refresh()


func _new_ship() -> void:
	var n := _name_edit.text.strip_edges()
	_after_change(_cli(["new", n if n != "" else "My Ship"]))


func _duplicate() -> void:
	var from := _selected()
	if from == "":
		_report.text = "Select a ship first."
		return
	var n := _name_edit.text.strip_edges()
	_after_change(_cli(["copy", from, n if n != "" else from + " copy"]))


func _delete() -> void:
	var s := _selected()
	if s == "":
		_report.text = "Select a ship first."
		return
	var dlg := ConfirmationDialog.new()
	dlg.dialog_text = "Delete the ship '%s' from res://ships/ ? This cannot be undone." % s
	dlg.confirmed.connect(func() -> void:
		_after_change(_cli(["delete", s]))
		dlg.queue_free())
	dlg.canceled.connect(func() -> void: dlg.queue_free())
	EditorInterface.get_base_control().add_child(dlg)
	dlg.popup_centered()


func _info() -> void:
	var s := _selected()
	if s != "":
		_report.text = _cli(["info", s]).trim_suffix("\nOK")


func _validate_all() -> void:
	_report.text = _cli(["validate"]).trim_suffix("\nOK")


## The builder is the one thing that needs the real game running (3D editing of vertices). It opens in the editor's embedded
## game view when the editor supports it (Godot 4.4+), so it stays in the editor window.
func _start_builder() -> void:
	var f := FileAccess.open(PREMADE_FLAG, FileAccess.WRITE)
	f.store_string("1")
	f.close()
	var settings := EditorInterface.get_editor_settings()
	if settings.has_setting(EMBED_SETTING):
		settings.set_setting(EMBED_SETTING, 1)
	EditorInterface.play_custom_scene(BUILDER_SCENE)


func _open_selected() -> void:
	var s := _selected()
	if s == "":
		_report.text = "Select a ship first."
		return
	var path := SHIP_DIR + s + (".ship" if FileAccess.file_exists(SHIP_DIR + s + ".ship") else ".json")
	var f := FileAccess.open(OPEN_FILE, FileAccess.WRITE)
	f.store_string(path)
	f.close()
	_start_builder()


func _open_empty() -> void:
	if FileAccess.file_exists(OPEN_FILE):
		DirAccess.remove_absolute(OPEN_FILE)
	_start_builder()
