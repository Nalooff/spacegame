extends Node
## WALKTHROUGH SCREENSHOTS: makes a special thruster and a special weapon in the real editor, one step at a time, and
## saves a picture of every step into docs/img/.  Run:  xvfb-run -a -s "-screen 0 1600x900x24" godot --path . res://tests/shot_module_demo.tscn
const OUT := "res://docs/img/"

func _snap(file: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.4).timeout
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT + file + ".png"))
	print("saved ", file)


func _ready() -> void:
	var b: ShipBuilder = load("res://scenes/ship_builder.tscn").instantiate()
	add_child(b)
	await get_tree().create_timer(1.0).timeout
	var ui: BuilderUI = b.get_node("UI/BuilderUI")
	var tabs: TabContainer = b.get_node("UI/BuilderUI/SidePanel/SidePanelMargin/SideTabs")
	b.new_ship("starter")
	await get_tree().process_frame
	# ---- A SPECIAL THRUSTER -------------------------------------------------------------------------------------
	tabs.current_tab = 0
	ui._on_create_mode_pressed("module")
	ui._on_type_button_pressed(ModuleCatalog.THRUSTER)
	ui.new_preset_picker.select(1)                   # "Ion drive": weak but cold
	ui._on_new_preset_selected(1)
	await _snap("1_thruster_choose_type_and_preset")
	ui._on_shape_button_pressed("cone")              # the SHAPE is the engine: a long nozzle
	ui.new_radius_spin.value = 0.45                  # base radius and height; it points forward, so the round base is the exhaust end
	ui.new_height_spin.value = 2.8
	ui.new_axis_picker.select(1)
	await _snap("2_thruster_shape_and_size")
	b.camera_rig.pivot = Vector3(0, 0, 3)
	ui._on_add_module_pressed()
	b.camera_rig.focus_on(b.design.module_centroid(b.active_module), 5.0)
	await _snap("3_thruster_added")
	tabs.current_tab = 1                              # Properties: tune the one main number
	b.set_active_main_stat(60000.0)                   # ion drive pushed to 60 000 N per m3
	await _snap("4_thruster_tuned")
	ui.preset_name_edit.text = "Hot ion"
	ui._on_save_preset_pressed()
	await _snap("5_thruster_saved_as_preset")
	# ---- A SPECIAL WEAPON ----------------------------------------------------------------------------------------
	tabs.current_tab = 0
	ui._on_create_mode_pressed("module")
	ui._on_type_button_pressed(ModuleCatalog.BARREL)
	ui.new_preset_picker.select(1)                   # railgun
	ui._on_new_preset_selected(1)
	ui._on_shape_button_pressed("cylinder")
	ui.new_radius_spin.value = 0.12
	ui.new_height_spin.value = 3.2
	ui.new_axis_picker.select(1)
	b.camera_rig.pivot = Vector3(2, 1.5, 0)
	await _snap("6_weapon_choose")
	ui._on_add_module_pressed()
	b.camera_rig.focus_on(b.design.module_centroid(b.active_module), 5.0)
	tabs.current_tab = 1
	await _snap("7_weapon_added_and_stats")
	get_tree().quit()
