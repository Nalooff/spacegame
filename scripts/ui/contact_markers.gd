extends Control
## Draws the contacts of the ship's Detection module on the screen: green = friendly, red = enemy, orange = locked.
## A locked target also shows where the guns are really aiming (the LEAD point). Press R to lock the next enemy.

const FRIEND := Color(0.4, 1.0, 0.5)
const ENEMY := Color(1.0, 0.35, 0.3)
const LOCKED := Color(1.0, 0.7, 0.2)
const SIZE := 14.0

var ship: Ship


func _ready() -> void:
	BusEvent.local_ship_changed.connect(func(s: Ship): ship = s)
	ship = Data.local_ship


func _process(_dt: float) -> void:
	queue_redraw()


func _draw() -> void:
	if not is_instance_valid(ship) or not ship.alive:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var font := ThemeDB.fallback_font
	if ship.is_multiplayer_authority():
		draw_string(font, Vector2(size.x * 0.5 - 330.0, 100.0), ship.stations.status_text(), HORIZONTAL_ALIGNMENT_CENTER, 660.0, 15, Color(0.7, 0.9, 1.0))
		if ship.stations.walking:
			draw_rect(Rect2(size.x * 0.5 - 100.0, 112.0, 200.0 * ship.stations.walk_progress(), 5.0), Color(0.7, 0.9, 1.0))
		elif not ship.stations.is_commander_mode():
			draw_line(Vector2(size.x * 0.5 - 8, size.y * 0.5), Vector2(size.x * 0.5 + 8, size.y * 0.5), Color(1, 1, 1, 0.6), 1.0)   # crosshair
			draw_line(Vector2(size.x * 0.5, size.y * 0.5 - 8), Vector2(size.x * 0.5, size.y * 0.5 + 8), Color(1, 1, 1, 0.6), 1.0)
	var det := ship.detection
	var radars := det.working_radars().size()
	var header := "DETECTION  view %.0f m%s   %d contact%s" % [Data.VIEW_RANGE,
		"  +  %d radar%s" % [radars, "" if radars == 1 else "s"] if radars > 0 else "  (no radar)", det.contacts.size(), "" if det.contacts.size() == 1 else "s"]
	draw_string(font, Vector2(16, size.y - 170), header, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.75))
	var line := 1
	for c in det.contacts:
		var other: Ship = c["ship"]
		if not is_instance_valid(other):
			continue
		var col := FRIEND if c["friendly"] else ENEMY
		var is_locked := other == det.locked
		if is_locked:
			col = LOCKED
		if line <= 6:
			draw_string(font, Vector2(16, size.y - 170 + line * 18), "%s %s  %.0f m  [%s %d%%]" % ["*" if is_locked else " ", other.pilot_name, c["dist"], c["how"], int(c["precision"] * 100.0)],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col)
			line += 1
		var pos: Vector3 = c["est_pos"]
		if cam.is_position_behind(pos):
			continue
		var p := cam.unproject_position(pos)
		_bracket(p, col, is_locked)
		draw_string(font, p + Vector2(SIZE + 4, 4), "%s  %.0f m" % [other.pilot_name, c["dist"]], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)
		if is_locked:
			var lead := det.lead_point(ship.turrets.average_muzzle_speed())
			if lead != Vector3.ZERO and not cam.is_position_behind(lead):
				var lp := cam.unproject_position(lead)
				draw_arc(lp, 7.0, 0.0, TAU, 20, LOCKED, 2.0)
				draw_line(lp + Vector2(-12, 0), lp + Vector2(12, 0), LOCKED, 1.0)
				draw_line(lp + Vector2(0, -12), lp + Vector2(0, 12), LOCKED, 1.0)


func _bracket(p: Vector2, col: Color, filled: bool) -> void:
	var s := SIZE
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var corner := p + Vector2(sx * s, sy * s)
			draw_line(corner, corner - Vector2(sx * 6.0, 0), col, 2.0)
			draw_line(corner, corner - Vector2(0, sy * 6.0), col, 2.0)
	if filled:
		draw_rect(Rect2(p - Vector2(3, 3), Vector2(6, 6)), col)
