extends Node
## Persistent part of the multiplayer smoke test (lives under /root so it survives scene changes).
var role := "host"
var t := 0.0
var started := false
var ordered := false
var killed := false
var next_report := 3.0

func _process(d: float) -> void:
	t += d
	if role == "host" and not started and t > 3.0 and Net.players.size() >= 2:
		started = true
		print("[host] roster: ", Net.players.keys(), " -> start")
		Net.start_game()
	var mine := get_tree().root.find_child(str(multiplayer.get_unique_id()), true, false) as Ship
	if mine != null and not ordered and mine.is_multiplayer_authority():
		ordered = true
		var target := Vector3(20, 5, -30) if role == "host" else Vector3(-25, 0, 10)
		mine.autopilot.go_to(target)
		print("[%s] my ship ready (mass %.0f), autopilot -> %s" % [role, mine.mass, target])
	if role == "client" and mine != null and mine.alive and t > 12.0 and not killed:
		killed = true
		print("[client] killing own commander")
		mine.apply_damage(mine.commander_index(), 1e6)
	if role == "host" and mine != null and mine.alive and t > 9.0 and t < 9.1:
		for sh in get_tree().get_nodes_in_group("ships"):
			if sh != mine and (sh as Ship).alive:
				mine.weapons.try_fire(sh.global_position, 1.0) # shoot the other player's ship
	if t > next_report:
		next_report += 4.0
		for sh in get_tree().get_nodes_in_group("ships"):
			var s := sh as Ship
			print("[%s] t=%.0f ship %s auth=%s alive=%s pos=%s speed=%.2f hp=%.2f cmd=%.2f" % [role, t, s.name, s.is_multiplayer_authority(),
				s.alive, s.global_position.snapped(Vector3.ONE * 0.1), s.speed(), s.hull_ratio(), s.commander_ratio()])
	if t > 24.0:
		get_tree().quit()
