extends Node
## SHIP COMMAND LINE: create, copy, inspect and check ships WITHOUT starting the game or the builder. The editor plugin
## (addons/vertex_ships) runs it in a background Godot, so you manage ships from the editor without any scene starting.
##   godot --headless --path . res://tools/ship_cli.tscn -- list
##   ... -- new "My Ship"            a starter ship (hull + bridge + engine) in res://ships/
##   ... -- copy "Dart" "Dart 2"     a copy under a new name
##   ... -- info "Dart"              modules, mass, seats, thrust, problems
##   ... -- validate ["Dart"]        every ship (or one) must be valid
##   ... -- delete "Dart 2"
## Prints plain lines; the last line is "OK" or "ERROR: reason". Exit code 0 / 1.
const DIR := "res://ships/"


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var msg := _run(a)
	print(msg)
	get_tree().quit(0 if not msg.contains("ERROR:") else 1)


func _file_of(ship: String) -> String:
	for ext in [".json", ".ship"]:
		if FileAccess.file_exists(DIR + ship + ext):
			return DIR + ship + ext
	return ""


func _run(a: PackedStringArray) -> String:
	if a.is_empty():
		return "ERROR: no command (list, new, copy, info, validate, delete)"
	match a[0]:
		"list":
			var out: Array[String] = []
			for f in DirAccess.get_files_at(DIR):
				if f.ends_with(".json") or f.ends_with(".ship"):
					out.append(f.get_basename())
			out.sort()
			return "\n".join(out) + "\nOK"
		"new":
			if a.size() < 2 or a[1].strip_edges() == "":
				return "ERROR: give the ship a name"
			var name_ := a[1].strip_edges().validate_filename()
			if _file_of(name_) != "":
				return "ERROR: a ship called '%s' already exists" % name_
			var d := ShipDesign.starter(name_)
			var errs := d.validate()
			if not errs.is_empty():
				return "ERROR: the starter ship is invalid: " + errs[0]
			if d.save_premade() != OK:
				return "ERROR: could not write into res://ships/"
			return "Created '%s' (%d modules).\nOK" % [name_, d.modules.size()]
		"copy":
			if a.size() < 3:
				return "ERROR: copy <from> <to>"
			var src := _file_of(a[1])
			if src == "":
				return "ERROR: no ship called '%s'" % a[1]
			var to := a[2].strip_edges().validate_filename()
			if to == "" or _file_of(to) != "":
				return "ERROR: '%s' is empty or already exists" % to
			var d2 := ShipDesign.load_file(src)
			if d2 == null:
				return "ERROR: cannot read '%s'" % a[1]
			d2.ship_name = to
			if d2.save_premade() != OK:
				return "ERROR: could not write into res://ships/"
			return "Copied '%s' to '%s'.\nOK" % [a[1], to]
		"info":
			if a.size() < 2 or _file_of(a[1]) == "":
				return "ERROR: no such ship"
			var d3 := ShipDesign.load_file(_file_of(a[1]))
			if d3 == null:
				return "ERROR: cannot read it"
			var props := d3.compute_props()
			var types := {}
			for m in d3.modules:
				types[m["type"]] = int(types.get(m["type"], 0)) + 1
			var errs3 := d3.validate()
			return "%s: %d modules %s\nmass %.0f kg, %d seats, %d thrusters, %d turrets\n%s\nOK" % [
				d3.ship_name, d3.modules.size(), str(types), float(props["mass"]), d3.crew_capacity(),
				(props["thrusters"] as Array).size(), (props["turrets"] as Array).size(),
				"valid" if errs3.is_empty() else "problems: " + "; ".join(errs3)]
		"validate":
			var names: Array[String] = []
			if a.size() > 1:
				names.append(a[1])
			else:
				for f in DirAccess.get_files_at(DIR):
					if f.ends_with(".json") or f.ends_with(".ship"):
						names.append(f.get_basename())
			var bad: Array[String] = []
			for n in names:
				var f2 := _file_of(n)
				var d4 := ShipDesign.load_file(f2) if f2 != "" else null
				if d4 == null:
					bad.append("%s: cannot be read" % n)
					continue
				var e := d4.validate()
				if not e.is_empty():
					bad.append("%s: %s%s" % [n, e[0], " (+%d more)" % (e.size() - 1) if e.size() > 1 else ""])
			if bad.is_empty():
				return "All %d ships are valid.\nOK" % names.size()
			return "\n".join(bad) + "\nERROR: %d invalid" % bad.size()
		"delete":
			if a.size() < 2 or _file_of(a[1]) == "":
				return "ERROR: no such ship"
			DirAccess.remove_absolute(_file_of(a[1]))
			return "Deleted '%s'.\nOK" % a[1]
	return "ERROR: unknown command '%s'" % a[0]
