class_name Scoreboard
extends PanelContainer
## SCOREBOARD: kills, deaths, kill/death ratio, damage dealt and taken of every player (the host keeps the numbers, see Net.stats).
## Shown while Tab is held (or pinned with the HUD button). The host also finds the "let new players join" switch here.

const HEADERS := ["#", "Player", "Kills", "Deaths", "K/D", "Damage", "Taken", ""]

@onready var grid: GridContainer = %ScoreGrid
@onready var open_join: CheckBox = %OpenJoinCheck

var pinned: bool = false
var _timer: float = 0.0


func _ready() -> void:
	visible = false
	Net.stats_changed.connect(refresh)
	Net.roster_changed.connect(refresh)


func toggle_pinned() -> void:
	pinned = not pinned


func _process(dt: float) -> void:
	var want := pinned or Input.is_action_pressed("scoreboard")
	if want != visible:
		visible = want
		if want:
			refresh()
	if visible:
		_timer -= dt
		if _timer <= 0.0:
			_timer = 0.5
			refresh()


## One scoreboard line as text cells (also used by the tests). `rank` starts at 1.
static func cells(entry: Dictionary, rank: int, me: int) -> Array[String]:
	var deaths := int(entry["deaths"])
	var kd := float(entry["kills"]) if deaths == 0 else float(entry["kills"]) / float(deaths)
	return [str(rank), str(entry["name"]) + ("  (you)" if int(entry["id"]) == me else ""), str(int(entry["kills"])), str(deaths),
		"%.2f" % kd, _big(float(entry["damage"])), _big(float(entry["taken"])), "" if bool(entry["here"]) else "left"]


static func _big(v: float) -> String:
	if v >= 1.0e6:
		return "%.2f M" % (v / 1.0e6)
	if v >= 1.0e4:
		return "%.1f k" % (v / 1.0e3)
	return "%.0f" % v


func refresh() -> void:
	for c in grid.get_children():
		grid.remove_child(c)
		c.queue_free()
	for h in HEADERS:
		grid.add_child(_cell(h, true, false))
	var me := Net.my_id() if multiplayer.has_multiplayer_peer() else 1
	var rank := 1
	for e in Net.ranking():
		var mine := int(e["id"]) == me
		for t in cells(e, rank, me):
			grid.add_child(_cell(t, false, mine))
		rank += 1
	open_join.visible = Net.is_host()
	open_join.set_pressed_no_signal(Net.late_join)


func _cell(text: String, header: bool, mine: bool) -> Label:
	var l := Label.new()
	l.text = tr(text) if header else text
	if header:
		l.modulate = Color(0.6, 0.85, 1.0)
	elif mine:
		l.modulate = Color(1.0, 0.85, 0.4)
	return l


func _on_open_join_toggled(on: bool) -> void:
	Net.set_late_join(on)
