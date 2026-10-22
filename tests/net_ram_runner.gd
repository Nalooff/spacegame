extends Node
## Two-process ramming test: the host's ship sits still at the origin, the client's ship is shot at it at 60 m/s.
## Prints, for every ship as each process sees it: vertex count (grows when a dent was applied), HP, position.
var role := "host"
var t := 0.0
var started := false
var done_setup := false
var next_report := 6.0

func _process(d: float) -> void:
	t += d
	if role == "host" and not started and t > 3.0 and Net.players.size() >= 2:
		started = true
		Net.start_game()
	var mine := get_tree().root.find_child(str(multiplayer.get_unique_id()), true, false) as Ship
	if mine != null and mine.is_multiplayer_authority() and not done_setup and t > 6.0:
		done_setup = true
		if role == "host":
			mine.global_position = Vector3.ZERO
			mine.rotation = Vector3.ZERO
			mine.linear_velocity = Vector3.ZERO
		else:
			mine.global_position = Vector3(-30, 0, 0)
			mine.rotation = Vector3(0, -PI / 2.0, 0)
			mine.linear_velocity = Vector3(60, 0, 0)
		print("[%s] setup done" % role)
	if t > next_report:
		next_report += 1.0
		var line := "[%s] t=%.0f" % [role, t]
		for sh in get_tree().get_nodes_in_group("ships"):
			var s := sh as Ship
			var hp := 0.0
			for h in s.module_hp: hp += h
			line += " | ship %s auth=%s verts=%d hp=%.0f x=%.1f" % [s.name, s.is_multiplayer_authority(), s.design.vertices.size(), hp, s.global_position.x]
		print(line)
	if t > 16.0:
		get_tree().quit()
