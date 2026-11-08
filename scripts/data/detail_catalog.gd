class_name DetailCatalog
extends RefCounted
## The DETAIL layer of a ship: small things stuck anywhere on its surface (windows, lights, hatches, stripes, numbers,
## scorch marks, antennas...). A detail belongs to NO module: it has its own place, direction, size and colours, so it can
## go anywhere, even across two modules or floating a little above the hull. (It does remember the module it was put
## on, only so that it disappears when that module is shot away.)
##
## One detail = Dictionary:
##   k  kind (the constants below)        p  position (ship space)         n  surface normal (unit)
##   a  rotation around the normal, rad   w, h  size in metres             d  height above the hull (solid kinds)
##   c  main colour                       c2 second colour (glass, stripe...)
##   g  option: WINDOW = how lit it is 0..1, LIGHT = 1 blinks, STREAK/SCORCH = strength
##   t  text (TEXT kind only)             m  module it was put on (-1 = none)
##   auto  true when AutoPaint made it (so "Auto paint" can replace its own work and leave the player's alone)

const WINDOW := 0
const PORTHOLE := 1
const HATCH := 2
const LIGHT := 3
const PANEL := 4
const VENT := 5
const GRILLE := 6
const STRIPE := 7
const CHEVRON := 8
const STAR := 9
const ROUNDEL := 10
const WARNING := 11
const SCORCH := 12
const STREAK := 13
const SCRATCH := 14
const DOCK_MARK := 15
const BOX := 16
const CYLINDER := 17
const ANTENNA := 18
const TEXT := 19
const KIND_COUNT := 20

const MAX_DETAILS := 60000
const MAX_TEXTS := 24
const MAX_TEXT_LEN := 32

## kind -> [display name, category, w, h, d, colour 1, colour 2, option]
const INFO := {
	WINDOW: ["Window", "Openings", 1.2, 0.7, 0.0, Color(0.05, 0.08, 0.12), Color(1.0, 0.85, 0.5), 0.5],
	PORTHOLE: ["Porthole", "Openings", 0.8, 0.8, 0.0, Color(0.05, 0.08, 0.12), Color(0.9, 0.9, 0.7), 0.4],
	HATCH: ["Hatch / port", "Openings", 1.6, 1.6, 0.0, Color(0.3, 0.32, 0.36), Color(0.1, 0.1, 0.12), 0.0],
	LIGHT: ["Light", "Lights", 0.4, 0.4, 0.0, Color(1.0, 0.2, 0.15), Color(1, 1, 1), 0.0],
	PANEL: ["Plate", "Surface", 3.0, 2.0, 0.0, Color(0.4, 0.42, 0.46), Color(0.15, 0.16, 0.18), 0.0],
	VENT: ["Vent", "Surface", 1.6, 1.0, 0.0, Color(0.08, 0.08, 0.1), Color(0.3, 0.3, 0.33), 0.0],
	GRILLE: ["Grille", "Surface", 1.6, 1.6, 0.0, Color(0.1, 0.1, 0.12), Color(0.4, 0.4, 0.45), 0.0],
	STRIPE: ["Stripe", "Livery", 12.0, 0.8, 0.0, Color(0.8, 0.15, 0.1), Color(1, 1, 1), 0.0],
	CHEVRON: ["Chevron", "Livery", 3.0, 3.0, 0.0, Color(0.95, 0.75, 0.1), Color(0, 0, 0), 0.0],
	STAR: ["Star", "Livery", 3.0, 3.0, 0.0, Color(0.95, 0.95, 0.95), Color(0, 0, 0), 0.0],
	ROUNDEL: ["Roundel", "Livery", 4.0, 4.0, 0.0, Color(0.8, 0.15, 0.1), Color(0.95, 0.95, 0.95), 0.0],
	WARNING: ["Warning sign", "Livery", 1.5, 1.5, 0.0, Color(0.95, 0.75, 0.1), Color(0.05, 0.05, 0.05), 0.0],
	SCORCH: ["Scorch mark", "Wear", 4.0, 4.0, 0.0, Color(0.03, 0.025, 0.02), Color(0.2, 0.1, 0.05), 0.7],
	STREAK: ["Dirt / rust streak", "Wear", 1.5, 6.0, 0.0, Color(0.35, 0.18, 0.08), Color(0.05, 0.05, 0.05), 0.6],
	SCRATCH: ["Scratches", "Wear", 3.0, 3.0, 0.0, Color(0.85, 0.85, 0.9), Color(0, 0, 0), 0.6],
	DOCK_MARK: ["Docking mark", "Livery", 3.0, 3.0, 0.0, Color(0.95, 0.95, 0.95), Color(0.95, 0.75, 0.1), 0.0],
	BOX: ["Box / block", "Greebles", 2.0, 1.5, 0.6, Color(0.45, 0.47, 0.5), Color(0.2, 0.2, 0.22), 0.0],
	CYLINDER: ["Tank / pipe", "Greebles", 1.2, 1.2, 1.0, Color(0.5, 0.5, 0.52), Color(0.2, 0.2, 0.22), 0.0],
	ANTENNA: ["Antenna / mast", "Greebles", 0.12, 0.12, 5.0, Color(0.6, 0.6, 0.62), Color(1, 0.2, 0.2), 0.0],
	TEXT: ["Text", "Livery", 8.0, 1.6, 0.0, Color(0.95, 0.95, 0.95), Color(0, 0, 0), 0.0],
}
const CATEGORIES := ["Openings", "Lights", "Surface", "Livery", "Wear", "Greebles"]


static func name_of(kind: int) -> String:
	return INFO[kind][0] if INFO.has(kind) else "?"


static func kinds_in(category: String) -> Array:
	var out: Array = []
	for k in KIND_COUNT:
		if INFO[k][1] == category:
			out.append(k)
	return out


static func is_solid(kind: int) -> bool:
	return kind == BOX or kind == CYLINDER or kind == ANTENNA


## A new detail of `kind` with the default look, scaled by `scale` (1 = the sizes in INFO).
static func make(kind: int, p: Vector3, n: Vector3, scale: float = 1.0, angle: float = 0.0) -> Dictionary:
	var info: Array = INFO[kind]
	return {"k": kind, "p": p, "n": n.normalized(), "a": angle, "w": info[2] * scale, "h": info[3] * scale,
		"d": info[4] * scale, "c": info[5], "c2": info[6], "g": info[7], "t": "", "m": -1, "auto": false}


## Fixes whatever came from a file or from the network (never trust it): ranges, finite numbers, known kind.
static func clean(src: Dictionary) -> Dictionary:
	var k := clampi(int(src.get("k", 0)), 0, KIND_COUNT - 1)
	var n: Vector3 = src.get("n", Vector3.UP)
	if not n.is_finite() or n.length() < 0.001:
		n = Vector3.UP
	var p: Vector3 = src.get("p", Vector3.ZERO)
	if not p.is_finite():
		p = Vector3.ZERO
	var t := str(src.get("t", "")).left(MAX_TEXT_LEN) if k == TEXT else ""
	return {"k": k, "p": p, "n": n.normalized(), "a": clampf(float(src.get("a", 0.0)), -TAU, TAU),
		"w": clampf(float(src.get("w", 1.0)), 0.01, 400.0), "h": clampf(float(src.get("h", 1.0)), 0.01, 400.0),
		"d": clampf(float(src.get("d", 0.0)), 0.0, 400.0), "c": src.get("c", Color.WHITE), "c2": src.get("c2", Color.BLACK),
		"g": clampf(float(src.get("g", 0.0)), 0.0, 1.0), "t": t, "m": maxi(int(src.get("m", -1)), -1), "auto": bool(src.get("auto", false))}


## Rotation frame of a detail: x = its right, y = its top, z = the normal. "Top" follows the ship's up axis (Y) unless
## the surface faces up or down, then it follows the ship's forward axis (-Z), turned by the detail's own angle.
static func frame(n: Vector3, angle: float) -> Basis:
	var up := Vector3.UP if absf(n.y) < 0.95 else Vector3.FORWARD
	var right := up.cross(n).normalized()
	var top := n.cross(right).normalized()
	var c := cos(angle)
	var s := sin(angle)
	return Basis(right * c + top * s, top * c - right * s, n)


# ---- compact (file / network) form: one flat array per detail
static func pack(dt: Dictionary) -> Array:
	var p: Vector3 = dt["p"]
	var n: Vector3 = dt["n"]
	var out := [int(dt["k"]), snappedf(p.x, 0.001), snappedf(p.y, 0.001), snappedf(p.z, 0.001),
		snappedf(n.x, 0.001), snappedf(n.y, 0.001), snappedf(n.z, 0.001), snappedf(float(dt["a"]), 0.001),
		snappedf(float(dt["w"]), 0.001), snappedf(float(dt["h"]), 0.001), snappedf(float(dt["d"]), 0.001),
		int((dt["c"] as Color).to_rgba32()), int((dt["c2"] as Color).to_rgba32()), snappedf(float(dt["g"]), 0.01),
		int(dt["m"]), 1 if dt["auto"] else 0]
	if int(dt["k"]) == TEXT:
		out.append(str(dt["t"]))
	return out


static func unpack(a: Array) -> Dictionary:
	if a.size() < 16:
		return {}
	var src := {"k": int(a[0]), "p": Vector3(float(a[1]), float(a[2]), float(a[3])),
		"n": Vector3(float(a[4]), float(a[5]), float(a[6])), "a": float(a[7]), "w": float(a[8]), "h": float(a[9]),
		"d": float(a[10]), "c": Color.hex(int(a[11]) & 0xFFFFFFFF), "c2": Color.hex(int(a[12]) & 0xFFFFFFFF),
		"g": float(a[13]), "m": int(a[14]), "auto": int(a[15]) == 1}
	if a.size() > 16:
		src["t"] = str(a[16])
	return clean(src)
