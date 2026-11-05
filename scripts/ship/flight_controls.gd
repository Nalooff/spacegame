class_name FlightControls
extends RefCounted
## Turns the player's input into a manual flight command {move, rot, active} for ShipManual (body frame, each axis -1..1).
## One instance per ship (the throttle lever remembers its position). `compute` is pure: it only looks at `raw`, so tests can
## feed it synthetic input.
##
## Schemes (the player picks one in the settings; all of them also accept the keyboard and a gamepad):
##   CLASSIC        keyboard: WASD thrust, Space / C up / down, arrows pitch + yaw, Q / E roll.
##   MOUSE_FLIGHT   Star Wars Outlaws style: the mouse (distance of the cursor from the screen centre) steers pitch + yaw,
##                  W / S thrust, A / D strafe, Q / E roll. Right mouse button = free look (the ship stops turning).
##   MOUSE_LEVER    the same mouse steering, but W / S move a THROTTLE LEVER that stays where you leave it (X = zero).
##   POINT_CIRCLE   Nebulous Fleet Command style: press G, a circle follows the cursor on the horizontal plane (x, z); hold Alt to
##                  move it up / down (y) instead; click to fly there. (OrderControls does that; the keys still fly the ship.)
##   EVE_ORDERS     EVE Online style: double click space = fly that way, Z approach the locked ship, O orbit it, K keep it at range,
##                  [ and ] change the range. (OrderControls.)

enum Scheme { CLASSIC, MOUSE_FLIGHT, MOUSE_LEVER, POINT_CIRCLE, EVE_ORDERS }

const NAMES: Array[String] = ["Classic keyboard", "Mouse flight (Star Wars Outlaws)", "Mouse flight + throttle lever",
	"Point and click circle (Nebulous)", "Click orders (EVE Online)"]
const HELP: Array[String] = [
	"WASD thrust / strafe, Space and C up / down, arrow keys pitch and yaw, Q and E roll. The simplest and most precise.",
	"Move the mouse away from the centre of the screen to turn the ship, like a flight stick. W / S thrust, A / D strafe, Q / E roll. Hold the right mouse button to look around without turning.",
	"The same mouse steering, with a throttle lever: W / S push the lever, it stays where you leave it, X sets it to zero. Good for long burns.",
	"Press G: a circle follows your cursor on the flat plane at your ship's height (x, z). Hold ALT and move the mouse up / down to raise or lower the circle (y). Click to fly there, Esc / right click to cancel. Keys still work.",
	"Double click in space to fly that way. Lock an enemy (R), then Z approach it, O orbit it, K keep it at range. [ and ] change the orbit / range distance. Keys still work.",
]

var lever: float = 0.0          ## MOUSE_LEVER: -0.3 .. 1


static func uses_mouse_stick(scheme: int) -> bool:
	return scheme == Scheme.MOUSE_FLIGHT or scheme == Scheme.MOUSE_LEVER


## Everything the devices say right now. `allow_stick`: the cursor may steer (commander mode, not over a button, not in a move circle).
static func read_raw(viewport: Viewport, allow_stick: bool, scheme: int) -> Dictionary:
	var raw := {
		"strafe": Input.get_axis("thrust_left", "thrust_right"),
		"vertical": Input.get_axis("thrust_down", "thrust_up"),
		"fwd": Input.get_axis("thrust_back", "thrust_fwd"),
		"pitch": Input.get_axis("pitch_down", "pitch_up"),
		"yaw": Input.get_axis("yaw_right", "yaw_left"),
		"roll": -Input.get_axis("roll_left", "roll_right"),
		"cut": Input.is_action_pressed("brake"),
		"stick": Vector2.ZERO,
	}
	if allow_stick and uses_mouse_stick(scheme) and not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) \
			and not Data.cursor_busy and viewport.gui_get_hovered_control() == null \
			and DisplayServer.window_is_focused():
		var rect := viewport.get_visible_rect().size
		raw["stick"] = (viewport.get_mouse_position() - rect * 0.5) / maxf(rect.y * 0.5, 1.0)
	# gamepad 0: left stick strafe / forward, right stick yaw / pitch, triggers up / down, bumpers roll
	var dz := Prefs.deadzone if Prefs != null else 0.1
	var lx := _dead(Input.get_joy_axis(0, JOY_AXIS_LEFT_X), dz)
	var ly := _dead(Input.get_joy_axis(0, JOY_AXIS_LEFT_Y), dz)
	var rx := _dead(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), dz)
	var ry := _dead(Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y), dz)
	var trig_r := Input.get_joy_axis(0, JOY_AXIS_TRIGGER_RIGHT)
	var trig_l := Input.get_joy_axis(0, JOY_AXIS_TRIGGER_LEFT)
	raw["strafe"] = clampf(raw["strafe"] + lx, -1.0, 1.0)
	raw["fwd"] = clampf(raw["fwd"] - ly, -1.0, 1.0)
	raw["yaw"] = clampf(raw["yaw"] - rx, -1.0, 1.0)
	raw["pitch"] = clampf(raw["pitch"] - ry, -1.0, 1.0)
	raw["vertical"] = clampf(raw["vertical"] + _dead(trig_r, 0.1) - _dead(trig_l, 0.1), -1.0, 1.0)
	raw["roll"] = clampf(raw["roll"] + float(Input.is_joy_button_pressed(0, JOY_BUTTON_RIGHT_SHOULDER)) - float(Input.is_joy_button_pressed(0, JOY_BUTTON_LEFT_SHOULDER)), -1.0, 1.0)
	return raw


static func _dead(v: float, dz: float) -> float:
	var a := absf(v)
	return 0.0 if a < dz else signf(v) * (a - dz) / (1.0 - dz)


## Cursor offset (screen centre = 0, screen half height = 1) -> turn command, with dead zone, sensitivity and a gentle curve.
static func stick_to_turn(stick: Vector2, deadzone: float, sens: float, invert_y: bool) -> Vector2:
	var mag := stick.length()
	if mag <= deadzone:
		return Vector2.ZERO
	var t := (mag - deadzone) / maxf(1.0 - deadzone, 0.01)
	var out := stick / mag * clampf(pow(t, 1.4) * sens * 1.5, 0.0, 1.0)
	return Vector2(-out.x, -out.y * (-1.0 if invert_y else 1.0))     # x: cursor right = yaw right (negative yaw_left); y: cursor up = nose up


## raw + prefs -> {move: Vector3, rot: Vector3, active: bool}. `ap_active`: an autopilot order is running (the lever lets go of it).
func compute(scheme: int, raw: Dictionary, dt: float, prefs: Dictionary, ap_active: bool = false) -> Dictionary:
	var fwd: float = raw["fwd"]
	var thrust_z := fwd
	if scheme == Scheme.MOUSE_LEVER:
		if ap_active and absf(fwd) < 0.01:
			lever = 0.0
		if raw.get("cut", false):
			lever = 0.0
		lever = clampf(lever + fwd * float(prefs.get("lever_rate", 0.5)) * dt, -0.3, 1.0)
		thrust_z = lever
	else:
		lever = 0.0
	var move := Vector3(raw["strafe"], raw["vertical"], -thrust_z)
	var rot := Vector3(raw["pitch"], raw["yaw"], raw["roll"])
	if uses_mouse_stick(scheme):
		var turn := stick_to_turn(raw.get("stick", Vector2.ZERO), float(prefs.get("deadzone", 0.08)), float(prefs.get("mouse_sens", 1.0)), bool(prefs.get("invert_y", false)))
		rot.y = clampf(rot.y + turn.x, -1.0, 1.0)
		rot.x = clampf(rot.x + turn.y, -1.0, 1.0)
	var direct := move != Vector3.ZERO or rot != Vector3.ZERO
	if scheme == Scheme.MOUSE_LEVER and lever != 0.0 and not direct:
		direct = not ap_active          # the lever keeps the ship under manual control
	return {"move": move, "rot": rot, "active": direct}
