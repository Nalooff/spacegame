extends Node
## Team deathmatch with N teams: godot --headless --path . res://tests/test_teams.tscn
var fails := 0
func check(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c: fails += 1


func _ready() -> void:
	Net.host_lobby("team test", false, "")
	Net.nat.message = ""
	for i in range(2, 8):
		Net.players[i] = Net._new_entry("P%d" % i)
		Net.srv_register_stats(i)
	Net.srv_register_stats(1)
	Net.set_game_options("teams", 3, 2)
	check(Net.game_mode == "teams" and Net.team_count == 3 and Net.kill_limit == 2, "options are set")
	var counts := {1: 0, 2: 0, 3: 0}
	for id in Net.players:
		var t := int(Net.players[id]["team"])
		check(t >= 1 and t <= 3, "player %d is in a valid team (%d)" % [id, t])
		counts[t] += 1
	check(counts[1] >= 2 and counts[2] >= 2 and counts[3] >= 2, "teams are balanced %s" % str(counts))
	Net.set_game_options("teams", 99, 0)
	check(Net.team_count == Net.TEAM_MAX, "at most %d teams" % Net.TEAM_MAX)
	Net.set_game_options("teams", 3, 2)
	# kills: find an enemy pair and a friend pair
	var a := 1
	var foe := 0
	var friend := 0
	for id in Net.players:
		if id == a: continue
		if Net.are_friends(a, id): friend = id
		else: foe = id
	Net.srv_add_damage(a, foe, 50.0)
	Net.srv_record_death(foe)
	var ta := int(Net.players[a]["team"])
	check(int(Net.team_kills.get(ta, 0)) == 1, "a kill counts for the killer's team")
	Net.srv_add_damage(a, friend, 50.0)
	Net.srv_record_death(friend)
	check(int(Net.team_kills.get(ta, 0)) == 1, "killing a friend scores nothing")
	Net.srv_add_damage(a, foe, 50.0)
	Net.srv_record_death(foe)
	check(Net.team_kills.is_empty() and int(Net.stats[a]["kills"]) == 0, "reaching the kill limit ends the round and resets the scores")
	# free for all
	Net.set_game_options("ffa", 2, 0)
	check(Net.game_mode == "ffa", "back to free for all")
	print("FAILS: %d" % fails)
	get_tree().quit(fails)
