extends Control
## MODULE PRESET CREATOR. Make your own weapon / thruster / armor / radar ... presets with every number typed by hand
## (damage type, shots per second, thrust per m3 ...). They are saved in user://presets.json and show up in the preset
## list of the ship builder (see ModulePresets). The built-in presets are read only: "New preset from this one" copies them.

const MAX_VALUE := 1.0e9

@onready var type_picker: OptionButton = %TypePicker
@onready var preset_list: ItemList = %PresetList
@onready var name_edit: LineEdit = %PresetNameEdit
@onready var kind_picker: OptionButton = %KindPicker
@onready var damage_picker: OptionButton = %DamageTypePicker
@onready var stat_rows: VBoxContainer = %StatRows
@onready var summary_label: Label = %SummaryLabel
@onready var help_edit: TextEdit = %HelpEdit
@onready var message: Label = %MessageLabel

var _types: Array[String] = []
var _ids: Array[String] = []
var _kinds: Array[String] = []
var _spins: Dictionary = {}          # stat key -> SpinBox
var _loading: bool = false


func _ready() -> void:
	_types = ModulePresets.creatable_types()
	for t in _types:
		type_picker.add_item(str(t).capitalize().replace("_", " "))
	for id in DamageRegistry.WEAPON_TYPES:
		damage_picker.add_item(DamageRegistry.get_type(id).display_name)
	_select_type(0)


func current_type() -> String:
	return _types[type_picker.selected] if type_picker.selected >= 0 and type_picker.selected < _types.size() else ""


func current_kind() -> String:
	return _kinds[kind_picker.selected] if kind_picker.selected >= 0 and kind_picker.selected < _kinds.size() else ""


func _select_type(index: int) -> void:
	type_picker.select(index)
	var type := current_type()
	_kinds = ModulePresets.kinds_of(type)
	kind_picker.clear()
	for k in _kinds:
		kind_picker.add_item(k.capitalize())
	kind_picker.get_parent().visible = not _kinds.is_empty()
	damage_picker.get_parent().visible = type == ModuleCatalog.BARREL
	_refresh_list()
	if not _ids.is_empty():
		preset_list.select(0)
		_load_preset(_ids[0])


func _refresh_list() -> void:
	var type := current_type()
	_ids = ModulePresets.preset_ids(type)
	preset_list.clear()
	for id in _ids:
		var label := str(ModulePresets.preset(type, id).get("label", id))
		preset_list.add_item(label + ("" if ModulePresets.is_builtin(type, id) else "   (yours)"))


## Fill the form from a preset.
func _load_preset(id: String) -> void:
	var type := current_type()
	var p := ModulePresets.preset(type, id)
	if p.is_empty():
		return
	_loading = true
	name_edit.text = str(p.get("label", id))
	help_edit.text = str(p.get("help", ""))
	var kind := str(p.get("kind", ""))
	var ki := _kinds.find(kind)
	if ki >= 0:
		kind_picker.select(ki)
	damage_picker.select(DamageRegistry.weapon_index(StringName(str(p.get("damage_type", "")))))
	_build_stat_rows(kind, p.get("stats", {}))
	_loading = false
	_update_summary()


func _build_stat_rows(kind: String, values: Dictionary) -> void:
	for c in stat_rows.get_children():
		c.queue_free()
		stat_rows.remove_child(c)
	_spins.clear()
	for d in ModulePresets.defs_of(current_type(), kind):
		var row := HBoxContainer.new()
		var l := Label.new()
		l.text = "%s  (%s)" % [d["label"], d["unit"]] if str(d.get("unit", "")) != "" else str(d["label"])
		l.custom_minimum_size.x = 330
		var sp := SpinBox.new()
		sp.min_value = 0.0
		sp.max_value = MAX_VALUE
		sp.step = 0.001
		sp.allow_greater = true
		sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sp.value = float(values.get(d["key"], 0.0))
		sp.value_changed.connect(func(_v: float) -> void: _update_summary())
		row.add_child(l)
		row.add_child(sp)
		stat_rows.add_child(row)
		_spins[d["key"]] = sp


func _stats_from_form() -> Dictionary:
	var out := {}
	for key in _spins:
		out[key] = (_spins[key] as SpinBox).value
	return out


func _update_summary() -> void:
	summary_label.text = ModulePresets.summary(current_type(), current_kind(), _stats_from_form())


func _on_type_selected(index: int) -> void:
	_select_type(index)


func _on_preset_selected(index: int) -> void:
	if index >= 0 and index < _ids.size():
		_load_preset(_ids[index])
		message.text = ""


func _on_kind_selected(_index: int) -> void:
	if _loading:
		return
	var old := _stats_from_form()
	_build_stat_rows(current_kind(), old)
	_update_summary()


## "New preset from this one": same numbers, empty name, ready to be changed.
func _on_new_pressed() -> void:
	name_edit.text = ""
	name_edit.grab_focus()
	message.text = "Type a name, change the numbers and press Save."


func _on_save_pressed() -> void:
	var err := save_form()
	message.text = err if err != "" else "Saved. It is in the preset list of the ship builder now."


## Save what the form says. Returns "" or the reason it was refused.
func save_form() -> String:
	var type := current_type()
	var dmg := ""
	if type == ModuleCatalog.BARREL:
		dmg = str(DamageRegistry.weapon_type_id(damage_picker.selected))
	var err := ModulePresets.save_definition(type, name_edit.text, current_kind(), dmg, _stats_from_form(), help_edit.text)
	if err == "":
		var id := ModulePresets.id_of_label(name_edit.text)
		_refresh_list()
		var at := _ids.find(id)
		if at >= 0:
			preset_list.select(at)
	return err


func _on_delete_pressed() -> void:
	var sel := preset_list.get_selected_items()
	if sel.is_empty():
		return
	var id := _ids[sel[0]]
	if ModulePresets.is_builtin(current_type(), id):
		message.text = "Built-in presets cannot be deleted. Use \"New preset from this one\" to make your own."
		return
	ModulePresets.delete_custom(current_type(), id)
	message.text = "Deleted."
	_refresh_list()
	if not _ids.is_empty():
		preset_list.select(0)
		_load_preset(_ids[0])


func _on_back_pressed() -> void:
	Game.go_to(Game.MENU_SCENE)
