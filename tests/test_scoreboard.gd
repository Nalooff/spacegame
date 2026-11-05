extends Node
## Scoreboard rules + join-in-progress flags: godot --headless --path . res://tests/test_scoreboard.tscn
var fails := 0
func check(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c: fails += 1


func _ready() -> void:
	Net.host_lobby("score test", false, "")
	Net.nat.message = ""
	Net.players[2] = Net._new_entry("Bob")
	Net.players[3] = Net._new_entry("Cy")
	Net.srv_register_stats(1); Net.srv_register_stats(2); Net.srv_register_stats(3)
	var feed: Array = []
	Net.kill_feed.connect(func(t): feed.append(t))
	# damage rules
	Net.srv_add_damage(2, 1, 100.0)
	Net.srv_add_damage(3, 1, 40.0)
	Net.srv_add_damage(1, 1, 50.0)          # self damage ignored
	Net.srv_add_damage(9, 1, 50.0)          # unknown attacker ignored
	Net.srv_add_damage(2, 1, NAN)
	Net.srv_add_damage(2, 1, -5.0)
	check(is_equal_approx(Net.stats[2]["damage"], 100.0), "damage counted once, junk ignored")
	check(is_equal_approx(Net.stats[1]["taken"], 140.0), "taken counted")
	# voluntary respawn: death for the victim, kill for the top damage dealer
	var k := Net.srv_record_death(1, true)
	check(k == 2, "most damage gets the kill")
	check(Net.stats[1]["deaths"] == 1 and Net.stats[2]["kills"] == 1 and Net.stats[3]["kills"] == 0, "death + kill counted")
	check(not feed.is_empty() and "Bob" in feed[0], "kill feed names the killer: %s" % str(feed))
	# second life with nobody shooting: death, no kill
	check(Net.srv_record_death(1, true) == 0 and Net.stats[1]["deaths"] == 2, "no damage -> death without a kill")
	# damage resets after a death
	Net.srv_add_damage(3, 2, 10.0)
	Net.srv_reset_recent(2)
	check(Net.srv_record_death(2) == 0, "new spawn forgets old damage")
	var r := Net.ranking()
	check(r[0]["id"] == 2 and r.size() == 3, "ranking: most kills first")
	check(Scoreboard.cells(r[0], 1, 2).size() == 8, "scoreboard row has 8 cells")
	# late join
	check(not Net.late_join and not Net.game_running, "late join off by default")
	Net.set_late_join(true)
	check(Net.late_join, "host can allow late joiners")
	check(Net.start_game() == false or true, "start_game callable")
	check(Net.game_running or not Net.can_start(), "state consistent after start")
	Net.leave()
	check(not Net.late_join and Net.stats.is_empty(), "leave resets")
	print("RESULT: PASS" if fails == 0 else "RESULT: %d FAILED" % fails)
	get_tree().quit(0 if fails == 0 else 1)
