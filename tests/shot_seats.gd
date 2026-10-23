extends Node
## Needs a display: xvfb-run godot --path . res://tests/shot_seats.tscn   (writes /tmp/seats.png)
const NetClass := preload("res://scripts/autoload/net.gd")
func _ready() -> void:
	Net.players = {1: Net._new_entry("Captain")}
	var blob := ShipDesign.read_blob("res://ships/Twin Hull.json")
	var h := NetClass.hash_blob(blob)
	Net.blobs[h] = blob
	Net.players[1]["ship"] = h
	Net.players[1]["ship_name"] = "Twin Hull"
	Net._set_ship_slots(1, ShipDesign.from_blob(blob))
	var picker: Control = load("res://scenes/seat_picker.tscn").instantiate()
	add_child(picker)
	picker.open(1)
	for i in 20:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/tmp/seats.png")
	get_tree().quit()
