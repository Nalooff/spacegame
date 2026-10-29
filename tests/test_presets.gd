extends Node
## Preset creator, weapon damage types, armor stats: godot --headless --path . res://tests/test_presets.tscn
var fails := 0
func check(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c: fails += 1


func _ready() -> void:
	ModulePresets.custom_file = "user://test_presets.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ModulePresets.custom_file))
	_damage_types()
	_definitions()
	_armor()
	await _screen()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ModulePresets.custom_file))
	print("RESULT: PASS" if fails == 0 else "RESULT: %d FAILED" % fails)
	get_tree().quit(0 if fails == 0 else 1)


func _hit(type: StringName, hardness: float) -> DamageResult:
	var h := DamageHit.weapon(type, 0, 100.0, Vector3.ZERO, null, Vector3(0, 0, -1))
	return DamageRegistry.get_type(type).resolve(h, {"hardness": hardness})


func _damage_types() -> void:
	print("damage types")
	for id in DamageRegistry.WEAPON_TYPES:
		check(DamageRegistry.get_type(id) != null, "registered: %s" % id)
	var kin := _hit(&"kinetic", 100.0).hp_damage
	var ene := _hit(&"energy", 100.0).hp_damage
	var pie := _hit(&"piercing", 100.0).hp_damage
	check(kin == 50.0 and ene > kin and pie > ene * 0.9, "armor stops kinetic best, energy less (%.0f), piercing ignores most of it (%.0f)" % [ene, pie])
	var ex := _hit(&"explosive", 50.0)
	check(ex.dent_depth > 0.0 and ex.dent_direction.z < 0.0, "explosive shells dent the hull in the direction they travelled")
	check(_hit(&"kinetic", 50.0).dent_depth == 0.0, "bullets do not dent")
	check(DamageRegistry.weapon_type_id(DamageRegistry.weapon_index(&"piercing")) == &"piercing", "index round trip (what travels on the network)")
	check(DamageRegistry.weapon_type_id(99) == DamageRegistry.WEAPON_TYPES.back() and DamageRegistry.weapon_type_id(-3) == &"kinetic", "bad indexes are clamped")
	var d := ShipDesign.new()
	d.add_module("turret", "dome", Vector3.ZERO, Vector3(0.5, 0.5, 0.5))
	d.add_module("turret_barrel", "cylinder", Vector3(0, 0, -2), Vector3(0.2, 0.2, 1.0), 12, "railgun")
	d.add_module("turret_barrel", "cylinder", Vector3(0, 0, -5), Vector3(0.2, 0.2, 1.0), 12, "beam")
	d.add_module("turret_barrel", "cylinder", Vector3(0, 0, -8), Vector3(0.2, 0.2, 1.0), 12, "cannon")
	check(d.damage_type_id(1) == &"piercing" and d.damage_type_id(2) == &"energy" and d.damage_type_id(3) == &"kinetic", "built-in weapons carry their damage type")
	d.cfg(3).erase("damage_type")
	check(d.damage_type_id(3) == &"kinetic", "old ships without a damage type: bullets are kinetic")
	var back := ShipDesign.from_json(d.to_json())
	check(back != null and back.damage_type_id(1) == &"piercing", "the damage type survives saving and loading")


func _definitions() -> void:
	print("presets saved by the player")
	var stats := {"damage_per_m3": 500.0, "cooldown": 0.1, "muzzle_speed": 400.0, "spread_deg": 0.5, "elec_per_dmg": 20.0, "heat_per_dmg": 10.0}
	check(ModulePresets.save_definition(ModuleCatalog.BARREL, "Rapid Plasma", "projectile", "energy", stats, "Fast.") == "", "a weapon preset is saved")
	check(ModulePresets.preset_ids(ModuleCatalog.BARREL).has("rapid_plasma") and ModulePresets.is_custom(ModuleCatalog.BARREL, "rapid_plasma"), "it appears in the list of barrel presets")
	var cfg := ModulePresets.make_cfg(ModuleCatalog.BARREL, "rapid_plasma")
	check(cfg["damage_type"] == "energy" and cfg["kind"] == "projectile" and float(cfg["stats"]["cooldown"]) == 0.1, "a module made from it has the type, kind and numbers")
	var d := ShipDesign.new()
	d.add_module("turret_barrel", "cylinder", Vector3.ZERO, Vector3(0.2, 0.2, 1.0), 12, "rapid_plasma")
	check(d.damage_type_id(0) == &"energy" and d.stat(0, "cooldown") == 0.1, "a barrel added with it uses it")
	check(ModulePresets.summary(ModuleCatalog.BARREL, "projectile", stats).begins_with("10.0 shots/s"), "summary tells the shots per second (%s)" % ModulePresets.summary(ModuleCatalog.BARREL, "projectile", stats))
	check(ModulePresets.save_definition(ModuleCatalog.BARREL, "Cannon", "projectile", "kinetic", stats) != "", "a built-in name is refused")
	check(ModulePresets.save_definition(ModuleCatalog.BARREL, "  ", "projectile", "kinetic", stats) != "", "an empty name is refused")
	var bad := stats.duplicate()
	bad["cooldown"] = -1.0
	check(ModulePresets.save_definition(ModuleCatalog.BARREL, "Bad", "projectile", "kinetic", bad) != "", "negative numbers are refused")
	bad = stats.duplicate()
	bad.erase("muzzle_speed")
	check(ModulePresets.save_definition(ModuleCatalog.BARREL, "Bad2", "projectile", "kinetic", bad) != "", "a missing number is refused")
	check(not ModulePresets.preset_ids(ModuleCatalog.BARREL).has("bad"), "nothing refused was saved")
	check(ModulePresets.save_definition(ModuleCatalog.THRUSTER, "Mega Ion", "", "", {"thrust_per_m3": 20000.0, "elec_per_n": 30.0, "heat_per_n": 1.0}) == "", "a thruster preset is saved")
	check(ModulePresets.delete_custom(ModuleCatalog.BARREL, "rapid_plasma") and not ModulePresets.preset_ids(ModuleCatalog.BARREL).has("rapid_plasma"), "a preset of the player can be deleted")
	check(not ModulePresets.delete_custom(ModuleCatalog.BARREL, "cannon"), "a built-in preset cannot be deleted")
	check(ModulePresets.preset_ids(ModuleCatalog.THRUSTER).has("mega_ion"), "the other preset is still there")


func _armor() -> void:
	print("armor presets")
	var d := ShipDesign.new()
	d.add_module("commander", "box", Vector3.ZERO, Vector3(1.0, 1.0, 1.0))
	d.add_module("armor", "box", Vector3(2.5, 0, 0), Vector3(0.5, 0.5, 0.5), 12, "standard")
	d.add_module("armor", "box", Vector3(-2.5, 0, 0), Vector3(0.5, 0.5, 0.5), 12, "composite")
	var a := _armor_numbers(d, 1)
	var b := _armor_numbers(d, 2)
	check(b[0] > a[0] * 1.5 and b[1] > a[1] * 1.4, "composite plating has more HP (%.0f vs %.0f) and weighs more (%.0f vs %.0f kg)" % [b[0], a[0], b[1], a[1]])


func _armor_numbers(d: ShipDesign, mi: int) -> Array:
	var mod_info: Array = d.compute_props()["modules"]
	return [float(mod_info[mi]["hp"]), float(mod_info[mi]["mass"])]


func _screen() -> void:
	print("the preset creator screen")
	var sc: Control = load("res://scenes/preset_creator.tscn").instantiate()
	add_child(sc)
	await get_tree().process_frame
	var types: Array = sc._types
	check(types.has(ModuleCatalog.BARREL) and types.has(ModuleCatalog.THRUSTER) and types.has(ModuleCatalog.ARMOR), "weapons, thrusters and armor can be given presets")
	sc._select_type(types.find(ModuleCatalog.BARREL))
	check(sc.damage_picker.get_parent().visible, "weapons show the damage type")
	check(sc._spins.has("damage_per_m3") and sc._spins.has("cooldown"), "every number of the weapon can be typed")
	sc.name_edit.text = "Screen Test Gun"
	(sc._spins["cooldown"] as SpinBox).value = 0.5
	sc.damage_picker.select(DamageRegistry.weapon_index(&"explosive"))
	check(sc.save_form() == "", "the form saves")
	var d := ShipDesign.new()
	d.add_module("turret_barrel", "cylinder", Vector3.ZERO, Vector3(0.2, 0.2, 1.0), 12, "screen_test_gun")
	check(d.damage_type_id(0) == &"explosive" and d.stat(0, "cooldown") == 0.5, "the builder can use what the screen saved")
	sc._select_type(types.find(ModuleCatalog.THRUSTER))
	check(not sc.damage_picker.get_parent().visible, "thrusters do not show a damage type")
	sc._select_type(types.find(ModuleCatalog.BARREL))
	var at: int = sc._ids.find("screen_test_gun")
	check(at >= 0, "the saved preset is in the list")
	sc.preset_list.select(at)
	sc._on_preset_selected(at)
	sc._on_delete_pressed()
	check(not ModulePresets.preset_ids(ModuleCatalog.BARREL).has("screen_test_gun"), "delete button removes it")
	sc.queue_free()
