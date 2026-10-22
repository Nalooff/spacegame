class_name Ship
extends RigidBody3D
## A player ship. The fixed structure lives in scenes/ship.tscn:
##   Hull (chunked renderer), Flames, Systems/{Electricity,Gyroscope,RCS}, Autopilot, Weapons,
##   TransformSync, StateSync, Explosion, Nameplate.
## Only what depends on the saved design is created here: one CollisionShape3D per
## external module (named "Module<i>_<type>").
##
## Authority model: the owning peer simulates its ship and replicates pose + state;
## everyone else shows a frozen, smoothed copy.

## The ship design. Set `design_blob` (binary or JSON bytes, see ShipDesign.to_blob) before adding the node.
## `design_json` is a convenience for tests/tools and just stores the text as a blob.
@export var design_blob: PackedByteArray = PackedByteArray()
@export var design_json: String = "":
	set(v):
		design_json = v
		design_blob = v.to_utf8_buffer()
## Ships with more vertices than this build their mesh in a worker thread (the ship is playable meanwhile).
const THREAD_VERTICES := 30000
const HULL_POINTS := 200
@export var pilot_name: String = "Pilot"

@onready var hull: HullRenderer = $Hull
@onready var flames: MultiMeshInstance3D = $Flames
@onready var electricity: ShipElectricity = $Systems/Electricity
@onready var gyro: ShipGyroscope = $Systems/Gyroscope
@onready var rcs: ShipRCS = $Systems/RCS
@onready var autopilot: ShipAutopilot = $Autopilot
@onready var weapons: ShipWeapons = $Weapons
@onready var explosion: CPUParticles3D = $Explosion
@onready var nameplate: Label3D = $Nameplate

var design: ShipDesign
var props: Dictionary = {}
var alloc: ThrustAllocator = ThrustAllocator.new()
var module_max_hp: PackedFloat32Array = PackedFloat32Array()
var flight_assist: bool = true

# ---- replicated (see TransformSync / StateSync in ship.tscn) ----
var sync_pos: Vector3 = Vector3.ZERO:
	set(v):
		sync_pos = v
		if not _got_first_sync and v != Vector3.ZERO:
			_got_first_sync = true
			position = v
var sync_quat: Quaternion = Quaternion.IDENTITY
var sync_vel: Vector3 = Vector3.ZERO
var module_hp: PackedFloat32Array = PackedFloat32Array():
	set(v):
		module_hp = v
		if is_node_ready():
			_on_hp_changed()
var throttles: PackedFloat32Array = PackedFloat32Array()
var alive: bool = true:
	set(v):
		var was := alive
		alive = v
		if was and not v and is_node_ready():
			_play_death()

var _got_first_sync: bool = false
var _dead_modules: Dictionary = {} # module index -> true once it was destroyed (for BusEvent)
var _shapes: Array[CollisionShape3D] = []
var _thr_module: Array[int] = []   # thruster index -> module index
var _mesh_dirty: bool = true
var _hull_idx: Array = []                 # one HullIndex per module (finds the faces near an impact)
var _hull_ids: Array = []                 # per module: vertex ids used for its collision hull
var _hull_thread: Thread = null
var _chunk_thread: Thread = null
var _pending_dents: Array = []            # dents received before the hull was ready
var _hull_ready: bool = false
var _cmd_throttle: PackedFloat32Array = PackedFloat32Array()
# ---- collision bookkeeping (see _integrate_forces)
var _hist_frame: Array[int] = [-1, -1, -1, -1]       # physics frame of each history slot
var _hist_vel: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
var _hist_ang: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
var _ram_times: Dictionary = {}                      # other ship instance id -> last time it hurt us
var _pending_remote_hits: Array[Dictionary] = []     # collisions with ships of other players, sent to them
var _pending_hits: Array[DamageHit] = []             # hits found in _integrate_forces, applied next frame
var _crew_cooldown: float = 0.0


func _ready() -> void:
	design = ShipDesign.from_blob(design_blob)
	props = design.compute_props()
	# recentre so the body origin is the centre of mass (cached sums are shifted, not recomputed)
	design.translate_all(-(props["com"] as Vector3))
	props = design.compute_props()

	mass = props["mass"]
	inertia = props["inertia"]
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3.ZERO
	gravity_scale = 0.0
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp = 0.0
	can_sleep = false
	continuous_cd = true
	contact_monitor = true      # needed to read collisions in _integrate_forces
	max_contacts_reported = 8

	var count := design.modules.size()
	module_max_hp.resize(count)
	for i in count:
		module_max_hp[i] = props["modules"][i]["hp"]
		_add_module_shape(i)
	if is_multiplayer_authority():
		module_hp = module_max_hp.duplicate()
	elif module_hp.size() != count:
		module_hp = module_max_hp.duplicate()
	_on_hp_changed_shapes_only()

	weapons.configure(self)
	_rebuild_systems()
	_setup_flames()

	if is_multiplayer_authority():
		nameplate.visible = false
	else:
		freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		freeze = true
		nameplate.text = pilot_name
	_start_hull()
	autopilot.arrived.connect(_on_autopilot_arrived)
	BusEvent.ship_spawned.emit(self)


func _add_module_shape(i: int) -> void:
	var cs := CollisionShape3D.new()
	var sh := ConvexPolygonShape3D.new()
	if design.vertices.size() > THREAD_VERTICES:
		# big ship: picking the hull points scans every vertex, so the worker thread does it (_finish_hull).
		_hull_ids.append(PackedInt32Array())
		sh.points = PackedVector3Array([Vector3.ZERO, Vector3.RIGHT * 0.1, Vector3.UP * 0.1, Vector3.BACK * 0.1])
		cs.disabled = true   # no collision until the real shape is ready
	else:
		_hull_ids.append(HullShapes.hull_ids(design, i, HULL_POINTS))
		sh.points = HullShapes.points(design, _hull_ids[i])
	cs.shape = sh
	cs.name = "Module%d_%s" % [i, design.modules[i]["type"]]
	cs.set_meta("module", i)
	add_child(cs)
	_shapes.append(cs)


## Re-derive everything that depends on which modules are still alive.
func _rebuild_systems() -> void:
	var powers := PackedFloat32Array()
	var dirs: Array[Vector3] = []
	var poss: Array[Vector3] = []
	_thr_module.clear()
	for t in props["thrusters"]:
		var mi: int = t["module"]
		var ok := module_hp.size() > mi and module_hp[mi] > 0.0
		powers.append(t["power"] if ok else 0.0)
		dirs.append(t["dir"])
		poss.append(t["pos"])
		_thr_module.append(mi)
	alloc.setup(powers, dirs, poss)
	rcs.configure(alloc.f_best)
	gyro.configure(alloc.worst_torque, inertia, design.gyro_scale)
	var total := 0.0
	for p in powers:
		total += p
	electricity.configure(total, rcs.force_max, gyro.torque_max, props["turrets"].size(), design.reactor_scale)
	autopilot.configure(self)
	_cmd_throttle.resize(alloc.n)
	if throttles.size() != alloc.n:
		throttles.resize(alloc.n)


func _setup_flames() -> void:
	flames.multimesh = flames.multimesh.duplicate()
	flames.multimesh.instance_count = alloc.n


# ----------------------------------------------------------------- queries
func alive_turret_count() -> int:
	var n := 0
	for t in props["turrets"]:
		if module_hp[t["module"]] > 0.0:
			n += 1
	return n


func commander_index() -> int:
	for i in design.modules.size():
		if design.modules[i]["type"] == ModuleCatalog.COMMANDER:
			return i
	return -1


func commander_ratio() -> float:
	var c := commander_index()
	if c < 0 or module_hp.size() <= c:
		return 0.0
	return clampf(module_hp[c] / module_max_hp[c], 0.0, 1.0)


func hull_ratio() -> float:
	var hp := 0.0
	var mx := 0.0
	for i in module_hp.size():
		hp += module_hp[i]
		mx += module_max_hp[i]
	return hp / maxf(mx, 1.0)


func speed() -> float:
	return linear_velocity.length()


# ----------------------------------------------------------------- damage
## ONE entry point for every kind of damage. Runs on the owning peer only.
## The DamageType registered for hit.type_id decides what happens (see scripts/damage/).
func apply_hit(hit: DamageHit) -> void:
	if not is_multiplayer_authority() or not alive:
		return
	if hit.module < 0 or hit.module >= module_hp.size() or module_hp[hit.module] <= 0.0:
		return
	var dtype := DamageRegistry.get_type(hit.type_id)
	if dtype == null:
		push_warning("Unknown damage type: %s" % hit.type_id)
		return
	var result := dtype.resolve(hit, MaterialCatalog.info(design.material_of(hit.module)))
	if result.is_empty():
		return
	if result.hp_damage > 0.0:
		_remove_module_hp(hit.module, result.hp_damage)
	if result.dent_depth > 0.005 and alive:
		_dent(hit.module, hit.point, result.dent_direction, result.dent_depth, result.dent_radius)
	BusEvent.ship_hit.emit(self, hit, result)


## Old shortcut kept for tests/tools: plain bullet damage.
func apply_damage(module: int, amount: float) -> void:
	apply_hit(DamageHit.kinetic(module, amount))


func _remove_module_hp(module: int, amount: float) -> void:
	var hp := module_hp
	hp[module] = maxf(hp[module] - amount, 0.0)
	module_hp = hp # reassign -> setter -> StateSync replicates it
	if hp[module] <= 0.0 and design.modules[module]["type"] == ModuleCatalog.COMMANDER:
		alive = false
		var world := get_tree().get_first_node_in_group("world")
		if world != null:
			world.report_death.rpc_id(1, int(str(name)))


## Start a dent (authority only): turn the impact into ship-local numbers and send them to everybody.
## Only these numbers travel; every peer re-runs the same deterministic HullDeformer.dent on its own copy.
func _dent(module: int, point_w: Vector3, dir_w: Vector3, depth: float, radius: float) -> void:
	var p := global_transform.affine_inverse() * point_w
	var dir := (global_transform.basis.inverse() * dir_w).normalized()
	# (re-)snap to the hull surface so a hit slightly outside/inside still dents the nearest face
	apply_dent.rpc(module, p, dir, depth, radius)


## Runs on EVERY peer, in the same order (reliable): add vertices at the impact, push them, refresh everything.
@rpc("authority", "call_local", "reliable")
func apply_dent(module: int, p: Vector3, dir: Vector3, depth: float, radius: float) -> void:
	if design == null:
		return
	if not _hull_ready:
		_pending_dents.append([module, p, dir, depth, radius])   # replayed when the hull is ready
		return
	var res := HullDeformer.dent(design, _hull_idx, module, p, dir, depth, radius)
	# collision: the convex hull of the touched modules' extreme vertices
	# (the hull points are the SAME vertex ids as before: they moved with the dent. Picking new ones would
	#  cost O(all vertices); a dent only pushes inward, so the old extreme points stay extreme.)
	for mi in res["changed"]:
		if (res["changed"][mi] as PackedInt32Array).is_empty():
			continue
		(_shapes[mi].shape as ConvexPolygonShape3D).points = HullShapes.points(design, _hull_ids[mi])
	hull.rebuild(res["changed"])
	_refresh_props()
	BusEvent.ship_deformed.emit(self, module)


## Mass, centre of mass, inertia and thruster positions change when the hull is dented.
## The sums are cached per module, so this is O(modules), not O(vertices).
func _refresh_props() -> void:
	props = design.compute_props()
	mass = props["mass"]
	inertia = props["inertia"]
	_rebuild_systems()


## Another player's ship rammed OURS (we only see their ship as a copy, so we could not feel it ourselves).
## Runs on the owner of the rammed ship: same damage rules as a local collision, plus the push it would have received.
@rpc("any_peer", "call_remote", "reliable")
func receive_ram(module: int, point: Vector3, normal_out: Vector3, closing: float, reduced_mass: float, attacker_hardness: float) -> void:
	if not is_multiplayer_authority() or not alive or not is_finite(closing) or closing <= 0.0 or closing > 100000.0:
		return
	apply_hit(DamageHit.ramming(module, closing, point, normal_out, Vector3.ZERO, reduced_mass, attacker_hardness))
	apply_impulse(-normal_out * reduced_mass * closing, point - global_position)


## Closing speed etc. of ship-ship contacts. Godot calls this every physics step.
## We compare against the velocities of the PREVIOUS frame, because the engine has already
## bounced the ships by the time the contact is reported.
func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	var frame := Engine.get_physics_frames()
	var slot := frame % 4
	_hist_frame[slot] = frame
	_hist_vel[slot] = state.linear_velocity
	_hist_ang[slot] = state.angular_velocity
	if not is_multiplayer_authority() or not alive:
		return
	var now := Time.get_ticks_msec() * 0.001
	for i in state.get_contact_count():
		var other := state.get_contact_collider_object(i) as Ship
		if other == null or not other.alive:
			continue
		var key := other.get_instance_id()
		if now - float(_ram_times.get(key, -10.0)) < Data.RAM_COOLDOWN:
			continue
		var point := state.get_contact_local_position(i)
		var mine := shape_find_owner(state.get_contact_local_shape(i))
		var theirs := other.shape_find_owner(state.get_contact_collider_shape(i))
		var my_shape := shape_owner_get_owner(mine) as CollisionShape3D
		var their_shape := other.shape_owner_get_owner(theirs) as CollisionShape3D
		if my_shape == null or their_shape == null or not my_shape.has_meta("module") or not their_shape.has_meta("module"):
			continue
		var n_out := state.get_contact_local_normal(i)
		if n_out.dot(point - global_position) < 0.0:
			n_out = -n_out
		var v_me := velocity_at(frame - 1, point)
		var v_other := other.velocity_at(frame - 1, point)
		var v_rel := v_other - v_me
		var closing := v_rel.dot(-n_out)
		if closing <= 0.0:
			continue
		_ram_times[key] = now
		var other_mod := int(their_shape.get_meta("module"))
		var hardness := float(MaterialCatalog.info(other.design.material_of(other_mod))["hardness"])
		var reduced := mass * other.mass / (mass + other.mass)
		_pending_hits.append(DamageHit.ramming(int(my_shape.get_meta("module")), closing, point, n_out, v_rel, reduced, hardness, other))
		# The other ship is simulated by ANOTHER player. On their PC our ship is only a copy that has already been
		# stopped by their copy of us, so THEY never feel a hard hit. We therefore tell them (see receive_ram).
		if not other.is_multiplayer_authority() and closing > 1.0:
			var my_hardness := float(MaterialCatalog.info(design.material_of(int(my_shape.get_meta("module"))))["hardness"])
			_pending_remote_hits.append({"other": other, "module": other_mod, "point": point, "normal": -n_out,
				"closing": closing, "mass": reduced, "hardness": my_hardness})


## Velocity of the body's material point at world position `p`, as it was in physics frame `frame`.
func velocity_at(frame: int, p: Vector3) -> Vector3:
	if not is_multiplayer_authority():
		return sync_vel # remote copies only know their replicated linear velocity
	var slot := frame % 4
	if _hist_frame[slot] != frame:
		return linear_velocity
	return _hist_vel[slot] + _hist_ang[slot].cross(p - global_position)


func _on_hp_changed() -> void:
	_on_hp_changed_shapes_only()
	_rebuild_systems()
	_mesh_dirty = true


func _on_hp_changed_shapes_only() -> void:
	for i in _shapes.size():
		var dead := i < module_hp.size() and module_hp[i] <= 0.0
		if dead:
			_shapes[i].disabled = true
			if not _dead_modules.has(i):
				_dead_modules[i] = true
				BusEvent.module_destroyed.emit(self, i)


func _on_autopilot_arrived() -> void:
	BusEvent.autopilot_arrived.emit(self)


func _play_death() -> void:
	BusEvent.ship_died.emit(self)
	hull.visible = false
	flames.visible = false
	nameplate.visible = false
	explosion.restart()
	explosion.emitting = true
	if is_multiplayer_authority():
		set_deferred("freeze", true)
		# stop replicating shortly before the host removes this ship, otherwise the last in-flight packets
		# arrive for a node that no longer exists ("Node not found ... TransformSync" errors)
		get_tree().create_timer(1.0).timeout.connect(_stop_replication)
	for cs in _shapes:
		cs.set_deferred("disabled", true)


func _stop_replication() -> void:
	if is_inside_tree():
		$TransformSync.public_visibility = false
		$StateSync.public_visibility = false


func _update_mesh() -> void:
	var ratios := PackedFloat32Array()
	for i in module_hp.size():
		ratios.append(module_hp[i] / maxf(module_max_hp[i], 0.001))
	hull.set_health(ratios)
	_mesh_dirty = false


## Build the per-module face indexes and the render chunks. Big ships do it in a worker thread.
func _start_hull() -> void:
	if design.vertices.size() > THREAD_VERTICES:
		# two threads: A builds the face indexes + collision points, B builds the render chunks
		_hull_thread = Thread.new()
		_hull_thread.start(_build_hull_data)
		_chunk_thread = Thread.new()
		_chunk_thread.start(HullRenderer.prepare.bind(design))
		set_process(true)
	else:
		_finish_hull(_build_hull_data())


## Heavy and thread safe: touches only `design` (not changed by anyone meanwhile) and creates no nodes.
func _build_hull_data() -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var idx: Array = []
	var ids: Array = []
	for mi in design.modules.size():
		idx.append(HullIndex.build(design, mi))
		ids.append(HullShapes.hull_ids(design, mi, HULL_POINTS))
	if OS.is_debug_build() and design.vertices.size() > THREAD_VERTICES:
		print("[Ship %s] face index + collision points: %d ms" % [name, Time.get_ticks_msec() - t0])
	return {"idx": idx, "ids": ids}


func _finish_hull(data: Dictionary, chunks: Array = []) -> void:
	_hull_idx = data["idx"]
	if chunks.is_empty():
		chunks = HullRenderer.prepare(design)
	if design.vertices.size() > THREAD_VERTICES:
		for mi in _shapes.size():
			_hull_ids[mi] = data["ids"][mi]
			(_shapes[mi].shape as ConvexPolygonShape3D).points = HullShapes.points(design, _hull_ids[mi])
			_shapes[mi].disabled = mi < module_hp.size() and module_hp[mi] <= 0.0
	hull.attach(design, chunks)
	_update_mesh()
	if design.vertices.size() <= THREAD_VERTICES:
		hull.flush()
	_hull_ready = true
	for d in _pending_dents:
		apply_dent(d[0], d[1], d[2], d[3], d[4])
	_pending_dents.clear()


func _process(_dt: float) -> void:
	if _hull_thread != null and not _hull_thread.is_alive() and not _chunk_thread.is_alive():
		var data: Dictionary = _hull_thread.wait_to_finish()
		var chunks: Array = _chunk_thread.wait_to_finish()
		_hull_thread = null
		_chunk_thread = null
		_finish_hull(data, chunks)
	if _mesh_dirty and _hull_ready:
		_update_mesh()


func _exit_tree() -> void:
	if _hull_thread != null:
		_hull_thread.wait_to_finish()
		_chunk_thread.wait_to_finish()
		_hull_thread = null
		_chunk_thread = null


# ----------------------------------------------------------------- physics
func _physics_process(dt: float) -> void:
	if not alive:
		return
	if _mesh_dirty:
		_update_mesh()
	if is_multiplayer_authority():
		_authority_step(dt)
	else:
		_remote_step()
		_crew_step(dt)
	while not _pending_hits.is_empty():
		apply_hit(_pending_hits.pop_back())
	while not _pending_remote_hits.is_empty():
		var r: Dictionary = _pending_remote_hits.pop_back()
		var victim := r["other"] as Ship
		if is_instance_valid(victim) and multiplayer.has_multiplayer_peer():
			victim.receive_ram.rpc_id(victim.get_multiplayer_authority(), r["module"], r["point"], r["normal"],
				r["closing"], r["mass"], r["hardness"])
	_update_flames()


func _authority_step(dt: float) -> void:
	var b := global_transform.basis
	var thr := PackedFloat32Array()
	thr.resize(alloc.n)
	var f_rcs := Vector3.ZERO
	var tau := Vector3.ZERO

	var typing := get_viewport().gui_get_focus_owner() is LineEdit
	var manual := _read_manual(typing)
	if autopilot.is_active():
		if manual["active"]:
			autopilot.cancel() # any manual input hands control back to the pilot
		else:
			autopilot.update(dt)
			thr = autopilot.out_throttle
			f_rcs = autopilot.out_f_rcs
			tau = autopilot.out_tau
	if not autopilot.is_active():
		var r := _manual_command(manual)
		thr = r[0]
		f_rcs = r[1]
		tau = r[2]

	f_rcs = rcs.clamp_force(f_rcs)
	tau = gyro.clamp_torque(tau)

	var thrust_sum := 0.0
	for i in alloc.n:
		thrust_sum += alloc.power[i] * thr[i]
	var k := electricity.consume(thrust_sum, f_rcs.length(), absf(tau.x) + absf(tau.y) + absf(tau.z),
		weapons.firing_power())

	# main thrusters: force applied AT each thruster's position (makes torque)
	for i in alloc.n:
		if thr[i] > 0.0001:
			var f_body: Vector3 = alloc.col_f[i] * (thr[i] * k)
			apply_force(b * f_body, b * alloc.pos[i])
	# RCS: force only, at the centre of mass
	if f_rcs.length_squared() > 0.0:
		apply_central_force(b * (f_rcs * k))
	# gyroscope
	if tau.length_squared() > 0.0:
		apply_torque(b * (tau * k))

	var shown := thr.duplicate()
	for i in shown.size():
		shown[i] *= k
	throttles = shown

	if not typing and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) \
			and get_viewport().gui_get_hovered_control() == null:
		var cam := get_viewport().get_camera_3d()
		if cam != null:
			var m := get_viewport().get_mouse_position()
			var aim := cam.project_ray_origin(m) + cam.project_ray_normal(m) * 400.0
			weapons.try_fire(aim, k)

	sync_pos = global_position
	sync_quat = global_transform.basis.get_rotation_quaternion()
	sync_vel = linear_velocity


## A crew member (not the pilot) controls the turrets: aim with the mouse, left click fires.
func _crew_step(dt: float) -> void:
	_crew_cooldown = maxf(_crew_cooldown - dt, 0.0)
	if _crew_cooldown > 0.0 or not Net.is_crew_on(self):
		return
	if get_viewport().gui_get_focus_owner() is LineEdit or get_viewport().gui_get_hovered_control() != null:
		return
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var m := get_viewport().get_mouse_position()
	var aim := cam.project_ray_origin(m) + cam.project_ray_normal(m) * 400.0
	_crew_cooldown = 0.08
	weapons.request_fire.rpc_id(get_multiplayer_authority(), aim)


func _remote_step() -> void:
	if not _got_first_sync:
		return
	var cur := global_transform
	var q := cur.basis.get_rotation_quaternion().slerp(sync_quat, 0.4)
	var p := cur.origin.lerp(sync_pos, 0.4)
	global_transform = Transform3D(Basis(q), p)
	linear_velocity = sync_vel


func _read_manual(typing: bool) -> Dictionary:
	var move := Vector3.ZERO
	var rot := Vector3.ZERO
	if not typing:
		move = Vector3(Input.get_axis("thrust_left", "thrust_right"),
			Input.get_axis("thrust_down", "thrust_up"),
			-Input.get_axis("thrust_back", "thrust_fwd")) # body -Z is forward
		rot = Vector3(Input.get_axis("pitch_down", "pitch_up"),
			Input.get_axis("yaw_right", "yaw_left"),
			-Input.get_axis("roll_left", "roll_right"))
	return {"move": move, "rot": rot, "active": move != Vector3.ZERO or rot != Vector3.ZERO}


## Manual flight: wanted force/rotation in the body frame -> throttles, RCS, gyro.
func _manual_command(m: Dictionary) -> Array:
	var b := global_transform.basis
	var move: Vector3 = (m["move"] as Vector3).limit_length(1.0)
	var thr := PackedFloat32Array()
	thr.resize(alloc.n)
	var f_rcs := Vector3.ZERO
	if move != Vector3.ZERO and alloc.f_best > 0.0:
		var f_des := move * alloc.f_best
		thr = alloc.allocate(f_des, _cmd_throttle)
		_cmd_throttle = thr
		f_rcs = f_des - alloc.force_of(thr) # RCS adds a little on top; clamped to 5 %
	else:
		_cmd_throttle.fill(0.0)
	var tau_thr := alloc.torque_of(thr)
	var rot: Vector3 = m["rot"]
	var tau: Vector3
	if flight_assist:
		var w_des := rot * 1.2 * electricity.ratio
		var omega_body := b.transposed() * angular_velocity
		tau = inertia * (6.0 * (w_des - omega_body)) - tau_thr
	else:
		tau = rot * gyro.torque_max * 0.5 # raw torque, no damping, no compensation
	return [thr, f_rcs, tau]


func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority() or not alive:
		return
	if event.is_action_pressed("brake"):
		autopilot.brake()
	elif event.is_action_pressed("hold_attitude"):
		flight_assist = not flight_assist


# ----------------------------------------------------------------- visuals
func _update_flames() -> void:
	var mm := flames.multimesh
	if mm.instance_count != alloc.n:
		return
	for i in alloc.n:
		var t: float = throttles[i] if i < throttles.size() else 0.0
		var p: float = alloc.power[i]
		if t < 0.01 or p <= 0.0:
			mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO))
			continue
		var s := pow(p / 2000.0, 1.0 / 3.0)
		var flame_len := (0.3 + 1.4 * t) * s
		var wid := 0.2 * s * (0.6 + 0.4 * t)
		var e: Vector3 = -alloc.dirs[i] # exhaust goes opposite to the push
		var x := e.cross(Vector3.UP)
		if x.length() < 0.01:
			x = e.cross(Vector3.RIGHT)
		x = x.normalized()
		var z := x.cross(e)
		var flame_basis := Basis(x * wid, e * flame_len, z * wid)
		mm.set_instance_transform(i, Transform3D(flame_basis, alloc.pos[i] + e * (0.2 * s + flame_len * 0.5)))
