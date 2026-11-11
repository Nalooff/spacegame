extends Node
## Every premade ship loads, passes the builder's validation, and the new classes have the sizes they should.
var fails := 0
func check(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c: fails += 1

func _ready() -> void:
	var len_of := {}
	for s in ShipDesign.list_ships():
		if not s["premade"]:
			continue
		var d := ShipDesign.load_file(s["path"])
		check(d != null, "%s loads" % s["name"])
		if d == null:
			continue
		var errs := d.validate()
		check(errs.is_empty(), "%s has no design problems %s" % [s["name"], str(errs.slice(0, 2))])
		len_of[d.ship_name] = d.extent_length()
	for n in ["Quadwing", "Orb Interceptor", "Hammerhead", "Nautilus", "Spearhead"]:
		check(len_of.has(n), "%s is a premade ship" % n)
	check(len_of["Quadwing"] < 25.0 and len_of["Orb Interceptor"] < 25.0, "the two fighters are the smallest")
	check(len_of["Spearhead"] > len_of["Hammerhead"] and len_of["Spearhead"] > len_of["Nautilus"], "the Spearhead is the biggest of the new ships")
	check(absf(len_of["Spearhead"] / len_of["Dreadnought"] - 0.75) < 0.1, "the Spearhead is about 75%% of the Dreadnought (%.0f%%)" % (100.0 * len_of["Spearhead"] / len_of["Dreadnought"]))
	check(len_of["Hammerhead"] > 500.0 and len_of["Nautilus"] > 500.0, "the Hammerhead and the Nautilus are big")
	print("FAILS: %d" % fails)
	get_tree().quit(1 if fails > 0 else 0)
