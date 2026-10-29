class_name MapObjects
extends RefCounted
## EVERYTHING THE SHIP KNOWS ABOUT, for the tactical map: detected ships, shots in flight and the landmarks of the world,
## each with its position and the direction it moves in. One list of dictionaries:
##   {kind: "ship"|"projectile"|"landmark", pos, vel, radius, name, friendly, how, locked, ship?}
## Ships come from the detection module (the radar's estimate, so a bad radar gives a blurry map). Shots are seen by eye
## up to Data.PROJECTILE_EYE_RANGE and by any working radar up to Data.PROJECTILE_RADAR_RANGE. Landmarks are always known.

const MAX_SHOTS := 200


static func gather(ship: Ship) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not is_instance_valid(ship):
		return out
	for c in ship.detection.contacts:
		var other: Ship = c["ship"]
		if not is_instance_valid(other):
			continue
		out.append({"kind": "ship", "pos": c["est_pos"], "vel": c["est_vel"], "radius": 6.0, "name": other.pilot_name,
			"friendly": c["friendly"], "how": c["how"], "locked": other == ship.detection.locked, "ship": other, "dist": c["dist"]})
	var radar := not ship.detection.working_radars().is_empty()
	var reach := Data.PROJECTILE_RADAR_RANGE if radar else Data.PROJECTILE_EYE_RANGE
	var tree := ship.get_tree()
	var pool := tree.get_first_node_in_group("projectile_pool") if tree != null else null
	if pool != null:
		var me := ship.global_position
		var n := 0
		for node in pool.get_children():
			var p := node as Projectile
			if p == null or not p.active:
				continue
			if p.global_position.distance_to(me) > reach:
				continue
			out.append({"kind": "projectile", "pos": p.global_position, "vel": p.velocity, "radius": 1.0, "name": "shot",
				"friendly": p.shooter == ship, "how": "radar" if radar else "view", "locked": false})
			n += 1
			if n >= MAX_SHOTS:
				break
	var world := tree.get_first_node_in_group("world") if tree != null else null
	var lm := world.get_node_or_null("Landmarks") if world != null else null
	if lm != null:
		for node in lm.get_children():
			var m := node as Node3D
			if m == null:
				continue
			var r := 5.0
			var mi := m as MeshInstance3D
			if mi != null and mi.mesh != null:
				r = maxf((m.global_transform * mi.get_aabb()).size.length() * 0.3, 2.0)
			var v := (m as RigidBody3D).linear_velocity if m is RigidBody3D else Vector3.ZERO
			out.append({"kind": "landmark", "pos": m.global_position, "vel": v, "radius": r, "name": str(m.name),
				"friendly": false, "how": "known", "locked": false})
	return out
