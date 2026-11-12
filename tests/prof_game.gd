extends Node
## Where the per-frame script time goes in a real game (headless ok).
func _ready() -> void:
	get_tree().current_scene = null
	Data.tutorial = false
	Net.start_solo("res://ships/Dreadnought.ship", "star_cluster")
	await get_tree().create_timer(8.0).timeout
	Prof.acc.clear()
	var f0 := Engine.get_process_frames()
	await get_tree().create_timer(6.0).timeout
	var n := float(Engine.get_process_frames() - f0)
	var keys := Prof.acc.keys()
	keys.sort_custom(func(a, b): return Prof.acc[a] > Prof.acc[b])
	for k in keys.slice(0, 14):
		print("%-40s %.3f ms/frame" % [k, Prof.acc[k] / 1000.0 / n])
	get_tree().quit()
