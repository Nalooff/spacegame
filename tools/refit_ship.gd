extends Node
## Re-fits every flat detail of a premade ship to its surface and saves it. SHIP=res://ships/X.ship
func _ready() -> void:
	var path := OS.get_environment("SHIP")
	var d := ShipDesign.load_file(path)
	var n := DetailFit.fit_all(d, false, true)
	print("refit: ", n, " details changed, ", d.details.size(), " left")
	print("saved: ", error_string(d.save_premade()))
	get_tree().quit()
