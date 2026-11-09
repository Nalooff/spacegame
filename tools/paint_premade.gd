extends Node
## Auto-paints every small premade ship (the Dreadnought has its own generator) and saves it back. Run once.
const STYLES := {"Dart": 1, "Brick": 3, "Scrap Hauler": 4, "Twin Hull": 2}
func _ready() -> void:
	for s in ShipDesign.list_ships():
		if not s["premade"]:
			continue
		var d := ShipDesign.load_file(s["path"])
		if d == null or not STYLES.has(d.ship_name):
			print("skip ", s["path"])
			continue
		d.clear_details()
		var n := AutoPaint.apply(d, {"style": STYLES[d.ship_name], "seed": 11, "density": 1.0, "wear": 0.35})
		print(d.ship_name, ": ", n, " details -> ", error_string(d.save_premade()))
	get_tree().quit()
