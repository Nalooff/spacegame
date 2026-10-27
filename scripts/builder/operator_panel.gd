class_name OperatorPanel
extends PanelContainer
## The popup with the numbers of an adjustable operation (bevel width, extrude distance, mirror axis...), like Blender's
## "Adjust Last Operation" panel. It only shows what ShipBuilder.op_name / op_params say and sends changes back with
## builder.set_operator_param(); the operation re-runs from its snapshot each time (see ShipBuilder "ADJUSTABLE OPERATIONS").
## The rows come from BuilderTools.OPERATORS, so a new operation needs no change here.

@onready var title_label: Label = %OperatorTitle
@onready var params_box: VBoxContainer = %OperatorParams
@onready var hint_label: Label = %OperatorHint
@onready var apply_button: Button = %OperatorApplyButton
@onready var cancel_button: Button = %OperatorCancelButton

var builder: ShipBuilder
var _shown_op := ""


func setup(b: ShipBuilder) -> void:
	builder = b
	builder.operator_changed.connect(_on_operator_changed)
	apply_button.pressed.connect(func(): builder.confirm_operator())
	cancel_button.pressed.connect(func(): builder.cancel_operator())
	visible = false


func _on_operator_changed() -> void:
	if builder.op_name == "":
		visible = false
		_shown_op = ""
		return
	if builder.op_name != _shown_op:
		_rebuild()
	else:
		_sync_values()                       # parameters can also be set from code / keyboard
	visible = true


## Push the current parameter values into the already-built fields without re-triggering them.
func _sync_values() -> void:
	for row in params_box.get_children():
		var key: String = row.name.trim_prefix("Row_")
		if not builder.op_params.has(key):
			continue
		var spin := row.get_node_or_null("Spin") as SpinBox
		if spin != null:
			spin.set_value_no_signal(float(builder.op_params[key]))


func _rebuild() -> void:
	_shown_op = builder.op_name
	var def: Dictionary = BuilderTools.OPERATORS[_shown_op]
	title_label.text = str(def["title"]).to_upper()
	hint_label.text = "Change a number and press Enter. Apply keeps it, Cancel (Esc) undoes it."
	for c in params_box.get_children():
		c.queue_free()
	for p in def["params"]:
		var row := HBoxContainer.new()
		row.name = "Row_" + str(p["key"])
		var lab := Label.new()
		lab.name = "Label"
		lab.text = str(p["label"])
		lab.custom_minimum_size.x = 110
		row.add_child(lab)
		if p["type"] == "option":
			var opt := OptionButton.new()
			opt.name = "Option"
			opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			for o in p["options"]:
				opt.add_item(str(o))
			opt.select(int(builder.op_params[p["key"]]))
			opt.item_selected.connect(func(i: int): builder.set_operator_param(p["key"], i))
			row.add_child(opt)
		else:
			var spin := SpinBox.new()
			spin.name = "Spin"
			spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			spin.min_value = float(p["min"])
			spin.max_value = float(p["max"])
			spin.step = float(p["step"])
			spin.suffix = str(p.get("suffix", ""))
			spin.set_value_no_signal(float(builder.op_params[p["key"]]))
			var is_int: bool = p["type"] == "int"
			spin.value_changed.connect(func(v: float):
				if is_int:
					builder.set_operator_param(p["key"], int(v))
				else:
					builder.set_operator_param(p["key"], v))
			row.add_child(spin)
		params_box.add_child(row)
