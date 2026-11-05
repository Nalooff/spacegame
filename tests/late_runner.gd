extends Node
var role := "host"
var t := 0.0
var started := false
var max_players := 0
func _process(d: float) -> void:
	t += d
	max_players = maxi(max_players, Net.players.size())
	if role == "host" and not started and t > 2.0:
		started = true
		print("[host] start_game -> ", Net.start_game())
	if int(t * 2) % 4 == 0 and fmod(t, 0.5) < d:
		var ships: Array = get_tree().get_nodes_in_group("ships")
		print("[%s] t=%.0f game_running=%s in_game=%s ships=%d players=%d" % [role, t, Net.game_running, Net.in_game, ships.size(), Net.players.size()])
	if role == "late" and t > 7.0:
		var ok: bool = Net.in_game and is_instance_valid(Data.local_ship)
		print("[late] RESULT: ", "PASS" if ok else "FAIL")
		get_tree().quit()
	if role == "host" and t > 15.0:
		print("[host] RESULT: ", "PASS" if max_players >= 2 else "FAIL")
		get_tree().quit()
