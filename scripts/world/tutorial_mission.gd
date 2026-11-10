class_name TutorialMission
extends Node
## THE TUTORIAL (solo game from the main menu): a few steps against a target drone. The current step is written to
## Data.tutorial_text and shown by the HintBar. Runs on the host (= the only player).

var step: int = 0
var _start: Vector3 = Vector3.ZERO
var _have_start: bool = false
var _drone_id: int = 0
var _drone_timer: float = 2.0
var _timer: float = 0.0
var _opened: Dictionary = {}

const STEPS := 9


func _ready() -> void:
	name = "TutorialMission"


func _drone() -> Ship:
	return get_parent().get_node_or_null("Ships/drone%d" % _drone_id) as Ship


func _process(dt: float) -> void:
	var ship := Data.local_ship
	if not is_instance_valid(ship) or not ship.alive:
		return
	if not _have_start:
		_start = ship.global_position
		_have_start = true
	_drone_timer -= dt
	if _drone() == null and _drone_timer <= 0.0 and step < STEPS - 1:
		_drone_id += 1
		_drone_timer = 3.0
		var fwd := -ship.global_transform.basis.z
		get_parent().spawn_drone(ship.global_position + fwd * 220.0 + Vector3(0, 10, 0), "drone%d" % _drone_id)
	_timer += dt
	if _timer < 0.2:
		return
	_timer = 0.0
	for a in ["toggle_crew", "toggle_plan"]:
		if Input.is_action_pressed(a):
			_opened[a] = true
	var drone := _drone()
	var done := false
	match step:
		0: done = ship.global_position.distance_to(_start) > 40.0
		1: done = drone != null and not ship.detection.find_contact(drone).is_empty()
		2: done = drone != null and ship.detection.locked == drone
		3: done = drone != null and _hp_fraction(drone) < 0.9
		4: done = ship.detection.target_module >= 0
		5: done = drone == null or not drone.alive
		6: done = not ship.lodges.is_empty()
		7: done = _opened.has("toggle_crew") or _opened.has("toggle_plan")
	if done and step < STEPS - 1:
		step += 1
		BusEvent.notify.emit(tr("Tutorial: step done!"))
	Data.tutorial_text = _text()


func _hp_fraction(s: Ship) -> float:
	var hp := 0.0
	var mx := 0.0
	for i in s.module_hp.size():
		hp += maxf(s.module_hp[i], 0.0)
		mx += s.module_max_hp[i]
	return hp / maxf(mx, 1.0)


static func key(action: String) -> String:
	var evs := InputMap.action_get_events(action)
	return evs[0].as_text().replace(" (Physical)", "") if not evs.is_empty() else "?"


func _text() -> String:
	var head := tr("TUTORIAL %d / %d") % [step + 1, STEPS]
	match step:
		0: return head + "\n" + tr("Fly around: use the keys listed at the bottom of the screen. X brakes. Move about 40 m.")
		1: return head + "\n" + tr("A target drone is ahead of you. Turn towards it: it shows as a red marker.")
		2: return head + "\n" + tr("Press %s to lock the drone.") % key("lock_target")
		3: return head + "\n" + tr("Click your ship and choose Weapons free (or press H) to fire at it. The guns follow the lock; the circle shows where to aim.")
		4: return head + "\n" + tr("Press %s to aim at one of its modules (near enough to see it), and keep firing.") % key("target_module")
		5: return head + "\n" + tr("Destroy the drone.")
		6: return head + "\n" + tr("A new drone is coming. Ram it hard: fly into it fast. Your hull lodges in it and leaves a hole.")
		7: return head + "\n" + tr("Open the crew panel (%s) and the exploded plan (%s): crew, fires, air and doors are there.") % [key("toggle_crew"), key("toggle_plan")]
	return tr("TUTORIAL DONE") + "\n" + tr("Build your own ship in the creation tool, then play with friends. Leave with the Leave button (top right).")
