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
## Set when this ship was torn off a bigger one (see _perform_split): the module health of that moment, so that
## the child does not start repaired. Empty = a fresh ship.
var initial_hp: PackedFloat32Array = PackedFloat32Array()
var initial_max_hp: PackedFloat32Array = PackedFloat32Array()
var initial_volume: PackedFloat64Array = PackedFloat64Array()

@onready var hull: HullRenderer = $Hull
@onready var flames: MultiMeshInstance3D = $Flames
@onready var electricity: ShipElectricity = $Systems/Electricity
@onready var gyro: ShipGyroscope = $Systems/Gyroscope
@onready var rcs: ShipRCS = $Systems/RCS
@onready var autopilot: ShipAutopilot = $Autopilot
@onready var weapons: ShipWeapons = $Weapons
@onready var turrets: ShipTurrets = $Turrets
@onready var detection: ShipDetection = $Systems/Detection
@onready var comms: ShipComms = $Systems/Communications
@onready var report_spheres: Node3D = $ReportSpheres
@onready var stations: ShipStations = $Stations
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
		_last_sync_ms = Time.get_ticks_msec()
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
## Health (0..1) of every corridor piece of the ship plan (order = ShipPlan.edges). Replicated; see PlanState.
var corridor_hp: PackedFloat32Array = PackedFloat32Array():
	set(v):
		corridor_hp = v
		_function_dirty = true
var reports: ShipReports = ShipReports.new()   ## what the commander has been told so far (own ship, see ShipReports)
var _held_dents: Array[Dictionary] = []     # visible dents waiting for their report: {due, changed}
var _report_clock: float = 0.0
var plan_state: PlanState = null          ## live plan (null until the hull is ready)
var throttles: PackedFloat32Array = PackedFloat32Array()
## What this ship gives off, as seen by other ships' radars (replicated, rounded so that it rarely changes):
var sig_elec: float = 0.0     # watts of electricity in use  -> electronic radar
var sig_heat: float = 0.0     # watts of heat (thrusters, weapons ...) -> thermal radar
var turret_angles: PackedFloat32Array = PackedFloat32Array()   # [yaw, pitch] per turret, see ShipTurrets
var alive: bool = true:
	set(v):
		var was := alive
		alive = v
		if was and not v and is_node_ready():
			_play_death()

var _got_first_sync: bool = false
var _last_sync_ms: int = 0
var net_far: Dictionary = {}               # peer id -> true while that peer's ship is beyond Data.NET_RANGE (no data is sent to it)
var _thr_elec: PackedFloat32Array = PackedFloat32Array()   # per thruster: watts of electricity per newton
var _thr_heat: PackedFloat32Array = PackedFloat32Array()   # per thruster: watts of heat per newton
var _net_timer: float = 0.0
var _thrust_full_w: float = 0.0
var _sig_elec_f: float = 0.0
var _sig_heat_f: float = 0.0
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
# ---- structure (see _check_structure)
var _graph: ModuleGraph = null            # which module touches which (built once, in the worker thread for big ships)
var _initial_volume: PackedFloat64Array = PackedFloat64Array()   # per module, for the crush rule
var _com: Vector3 = Vector3.ZERO          # centre of mass in body-origin coordinates (moves when modules are lost)
var _structure_dirty: bool = false
var _function_dirty: bool = false         # corridors changed: re-evaluate which modules work
var _types: PackedStringArray = PackedStringArray()
var _cmd_hist: Array = []                 # [[time, throttles]] of the thruster commands (order delay without communications)
var _cmd_clock: float = 0.0
var _flames_ready: bool = false
var _burn: Array[Vector2i] = []             # [thruster module, module standing in its exhaust]


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
	_initial_volume.resize(count)
	for i in count:
		module_max_hp[i] = props["modules"][i]["hp"]
		_initial_volume[i] = props["modules"][i]["volume"]
		_add_module_shape(i)
	if initial_max_hp.size() == count:
		module_max_hp = initial_max_hp.duplicate()
	if initial_volume.size() == count:
		_initial_volume = initial_volume.duplicate()
	if is_multiplayer_authority() or module_hp.size() != count:
		module_hp = initial_hp.duplicate() if initial_hp.size() == count else module_max_hp.duplicate()
	_on_hp_changed_shapes_only()
	if initial_hp.size() == count:
		_refresh_props()   # a torn-off part starts with modules missing

	weapons.configure(self)
	_rebuild_systems()
	$TransformSync.add_visibility_filter(_net_filter)     # no data for peers whose ship is beyond Data.NET_RANGE
	$StateSync.add_visibility_filter(_net_filter)
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


func _configure_electricity() -> void:
	var weapons_w := 0.0
	for r in turrets.rigs:
		if turrets.is_usable(r):
			weapons_w += r.elec_w
	electricity.configure(_thrust_full_w, rcs.force_max, gyro.torque_max, weapons_w, _passive_watts(), design.reactor_scale)


## Life support / computers of the commanders and the radars (per m3 of the module, only while it lives).
func _passive_watts() -> float:
	var w := 0.0
	for mi in design.modules.size():
		var t: String = design.modules[mi]["type"]
		if (t == ModuleCatalog.COMMANDER or t == ModuleCatalog.RADAR or t == ModuleCatalog.ANTENNA or t == ModuleCatalog.ENGINE_ROOM) and is_working(mi):
			w += design.stat(mi, "elec_w_per_m3") * design.module_volume(mi)
	return w


## Re-derive everything that depends on which modules are still alive.
func _rebuild_systems() -> void:
	var powers := PackedFloat32Array()
	var dirs: Array[Vector3] = []
	var poss: Array[Vector3] = []
	_thr_module.clear()
	_thr_elec.clear()
	_thr_heat.clear()
	var thrust_full_w := 0.0
	for t in props["thrusters"]:
		var mi: int = t["module"]
		powers.append(t["power"])
		_thr_elec.append(t["elec_per_n"])
		_thr_heat.append(t["heat_per_n"])
		thrust_full_w += float(t["power"]) * float(t["elec_per_n"])
		dirs.append(t["dir"])
		poss.append((t["pos"] as Vector3) - _com)   # relative to the centre of mass: torque arms
		_thr_module.append(mi)
	alloc.setup(powers, dirs, poss)
	rcs.configure(alloc.f_best)
	gyro.configure(alloc.worst_torque, inertia, design.gyro_scale)
	_thrust_full_w = thrust_full_w
	_configure_electricity()
	detection.configure(self)
	stations.configure(self)
	autopilot.configure(self)
	_cmd_hist.clear()
	_cmd_throttle.resize(alloc.n)
	if throttles.size() != alloc.n:
		throttles.resize(alloc.n)
	if _flames_ready and flames.multimesh.instance_count != alloc.n:
		flames.multimesh.instance_count = alloc.n


## Ships that stopped sending data (beyond Data.NET_RANGE) are ghosts of where they were: not drawn, not detected.
func is_stale() -> bool:
	return not Net.players.is_empty() and not is_multiplayer_authority() and Time.get_ticks_msec() - _last_sync_ms > 1500


## Show / hide the whole ship (ships beyond Data.VIEW_RANGE are not drawn at all).
func set_rendered(on: bool) -> void:
	if visible != on:
		visible = on


func is_wreck() -> bool:
	return pilot_name == "Wreck"


## Visibility filter of both synchronizers: no data for peers whose ship is out of range.
func _net_filter(peer: int) -> bool:
	return not net_far.get(peer, false)


## Authority: decide which peers still get this ship's data (distance between ships).
func _update_net_visibility() -> void:
	if not multiplayer.has_multiplayer_peer():
		return
	for peer in multiplayer.get_peers():
		var theirs: Ship = null
		for n in get_tree().get_nodes_in_group("ships"):
			if (n as Ship).get_multiplayer_authority() == peer and not (n as Ship).is_wreck():
				theirs = n
				break
		if theirs == null:
			continue
		var far := global_position.distance_to(theirs.global_position) > Data.NET_RANGE
		if net_far.get(peer, false) != far:
			net_far[peer] = far
			$TransformSync.update_visibility(peer)
			$StateSync.update_visibility(peer)


func _setup_flames() -> void:
	flames.multimesh = flames.multimesh.duplicate()
	flames.multimesh.instance_count = alloc.n
	_flames_ready = true


# ----------------------------------------------------------------- queries
func alive_turret_count() -> int:
	return turrets.usable_count()


## First commander that still works (-1 = none).
func commander_index() -> int:
	for i in design.modules.size():
		if design.modules[i]["type"] == ModuleCatalog.COMMANDER and is_working(i):
			return i
	return -1


## Health of the commanders together (0..1): the HUD shows this as "core".
func commander_ratio() -> float:
	var hp := 0.0
	var mx := 0.0
	for i in design.modules.size():
		if design.modules[i]["type"] == ModuleCatalog.COMMANDER and module_hp.size() > i:
			hp += maxf(module_hp[i], 0.0)
			mx += module_max_hp[i]
	return clampf(hp / maxf(mx, 0.001), 0.0, 1.0)


## COMMANDER LINKS (see ShipDesign.linked_turrets): the commander module the player flying THIS ship sits at
## (-1 = not known, e.g. no lobby roster: then the player controls everything).
func my_commander() -> int:
	var peer := int(str(name)) if str(name).is_valid_int() else 0
	return Net.seat_of(peer) if peer != 0 and Net.players.has(peer) else -1


## Turret bases (with barrels) that the commander module `seat` controls.
func bases_of_seat(seat: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for mi in design.modules.size():
		if design.modules[mi]["type"] == ModuleCatalog.TURRET and not design.barrels_of(mi).is_empty() and design.controls(seat, mi):
			out.append(mi)
	return out


## Does the player flying this ship sit at a commander that holds the flight controls?
func i_fly() -> bool:
	return design.controls_flight(my_commander())


## Commander modules that still work.
func alive_commanders() -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in design.modules.size():
		if design.modules[i]["type"] == ModuleCatalog.COMMANDER and is_working(i):
			out.append(i)
	return out


## MODULE STATES: hp > 0 working, hp == 0 DEAD (a wreck: present, solid, heavy, but unusable), hp < 0 GONE (cut off).
## 1 for every module that is still PART OF THE SHIP (working or dead): they have mass, collide and hold the ship together.
func alive_mask() -> PackedByteArray:
	var m := PackedByteArray()
	m.resize(design.modules.size())
	for i in m.size():
		m[i] = 1 if (i < module_hp.size() and module_hp[i] >= 0.0 and design.modules[i]["type"] != ModuleCatalog.LOOSE) else 0
	return m


## 1 for every module that FUNCTIONS (see PlanState): hp > 0 and (communications OK or reachable from a commander).
func working_mask() -> PackedByteArray:
	if plan_state != null and plan_state.work.size() == design.modules.size():
		return plan_state.work
	var m := PackedByteArray()
	m.resize(design.modules.size())
	for i in m.size():
		m[i] = 1 if (i < module_hp.size() and module_hp[i] > 0.0 and design.modules[i]["type"] != ModuleCatalog.LOOSE) else 0
	return m


func is_working(mi: int) -> bool:
	if plan_state != null and mi < plan_state.work.size():
		return plan_state.work[mi] != 0
	return mi >= 0 and mi < module_hp.size() and module_hp[mi] > 0.0


## Seconds an order of the commander needs to reach module `mi` (0 with communications, INF when cut off).
func order_delay(mi: int) -> float:
	return plan_state.order_delay(mi) if plan_state != null else 0.0


func hull_ratio() -> float:
	var hp := 0.0
	var mx := 0.0
	for i in module_hp.size():
		hp += maxf(module_hp[i], 0.0)    # gone modules (-1) count as 0
		mx += module_max_hp[i]
	return hp / maxf(mx, 1.0)


## True if the local player is the pilot of this ship. A torn-off part nobody flies ("derelict") just drifts.
## (Offline / in tests there is no roster: then every ship counts as flown.)
func is_flown_by_me() -> bool:
	return Net.players.is_empty() or str(name) == str(Net.ship_owner_of(Net.my_id()))


func speed() -> float:
	return linear_velocity.length()


# ----------------------------------------------------------------- damage
## ONE entry point for every kind of damage. Runs on the owning peer only.
## The DamageType registered for hit.type_id decides what happens (see scripts/damage/).
func apply_hit(hit: DamageHit) -> void:
	if not is_multiplayer_authority() or not alive:
		return
	if hit.module < 0 or hit.module >= module_hp.size() or module_hp[hit.module] < 0.0:
		return     # (a DEAD wreck, hp == 0, can still be hit and dented; a GONE module cannot)
	var dtype := DamageRegistry.get_type(hit.type_id)
	if dtype == null:
		push_warning("Unknown damage type: %s" % hit.type_id)
		return
	var result := dtype.resolve(hit, MaterialCatalog.info(design.material_of(hit.module)))
	if result.is_empty():
		return
	if result.hp_damage > 0.0 and module_hp[hit.module] > 0.0:
		_remove_module_hp(hit.module, result.hp_damage)
	if result.dent_depth > 0.005 and alive and design.modules[hit.module]["type"] != ModuleCatalog.BARREL:
		_dent(hit.module, hit.point, result.dent_direction, result.dent_depth, result.dent_radius)
	_damage_corridors(hit, result)
	BusEvent.ship_hit.emit(self, hit, result)


## Old shortcut kept for tests/tools: plain bullet damage.
func apply_damage(module: int, amount: float) -> void:
	apply_hit(DamageHit.kinetic(module, amount))


func _remove_module_hp(module: int, amount: float) -> void:
	var hp := module_hp
	if hp[module] <= 0.0:
		return      # dead or gone modules lose no more health
	hp[module] = maxf(hp[module] - amount, 0.0)
	module_hp = hp # reassign -> setter -> StateSync replicates it
	if hp[module] <= 0.0:
		_structure_dirty = true   # something may be cut off now: checked once per physics frame


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
	var hold := _dent_report_delay(p)
	if hold > 0.05:
		_held_dents.append({"due": _report_clock + hold, "changed": res["changed"]})   # the commander has not heard of this dent yet
	else:
		hull.rebuild(res["changed"])
	_refresh_props()
	if is_multiplayer_authority():
		_crush_check(module, res)
	BusEvent.ship_deformed.emit(self, module)


## Mass, centre of mass, inertia and thruster positions change when the hull is dented.
## The sums are cached per module, so this is O(modules), not O(vertices).
func _refresh_props() -> void:
	_update_function()
	props = design.compute_props(alive_mask(), working_mask())
	_com = props["com"]
	mass = props["mass"]
	inertia = props["inertia"]
	center_of_mass = _com        # lost modules / dents move it; thrust torques are computed around it
	_rebuild_systems()


# ----------------------------------------------------------------- plan (corridors, working modules, communications)
## Build the ship plan from the design and the module graph (once the hull is ready).
func _build_plan() -> void:
	_types.clear()
	for m in design.modules:
		_types.append(m["type"])
	var plan := ShipPlan.generate(design, _graph.adj if _graph != null else [])
	plan_state = PlanState.new(plan)
	if corridor_hp.size() == plan.edges.size():
		plan_state.edge_hp = corridor_hp.duplicate()
	elif is_multiplayer_authority():
		corridor_hp = plan_state.edge_hp.duplicate()
	comms.configure(self)
	_function_dirty = true
	_refresh_props()
	_mesh_dirty = true


## Re-evaluate which modules work (hp, communications, corridors that can still be walked).
func _update_function() -> void:
	if plan_state == null:
		return
	comms.refresh()
	if corridor_hp.size() == plan_state.edge_hp.size():
		plan_state.edge_hp = corridor_hp.duplicate()
	plan_state.update(_types, module_hp, comms.online)


## A hit also wrecks corridors: a LINE from the impact, along the way it travelled, `reach` metres into the ship.
## Every corridor piece near that line loses health (PlanState.damage_line).
func _damage_corridors(hit: DamageHit, result: DamageResult) -> void:
	if plan_state == null:
		return
	var dir_w := hit.direction
	if dir_w.length_squared() < 0.0001:
		dir_w = result.dent_direction if result.dent_direction.length_squared() > 0.0001 else -hit.normal
	dir_w = dir_w.normalized()
	var reach := hit.reach
	if reach <= 0.0:
		reach = Data.CORRIDOR_REACH_BASE + result.hp_damage * Data.CORRIDOR_REACH_PER_DAMAGE + result.dent_depth * 2.0
	var amount := result.hp_damage / Data.CORRIDOR_HP
	if amount <= 0.0:
		return
	var a := global_transform.affine_inverse() * hit.point
	var b := a + (global_transform.basis.inverse() * dir_w).normalized() * minf(reach, Data.CORRIDOR_REACH_MAX)
	var radius := Data.CORRIDOR_HIT_RADIUS + result.dent_radius * 0.5
	if plan_state.damage_line(a, b, radius, amount):
		corridor_hp = plan_state.edge_hp.duplicate()     # replicated; every peer re-evaluates in its next physics frame


# ----------------------------------------------------------------- structure
## CRUSH RULE (authority). A module cannot be squeezed through the geometry it is attached to; it turns into a DEAD wreck instead (hp = 0):
##   a) FLATTENED: its volume fell under Data.CRUSH_VOLUME_FRACTION of what it had (or turned inside out), or
##   b) PUSHED THROUGH: vertices of the dented module were driven deeper than Data.CRUSH_PENETRATION into a module it is
##      attached to (e.g. an armor plate dented into the hull behind it). Only vertices that MOVED in this dent and
##      were not already inside count, so overlapping designs are not punished.
## Linked vertices (shared between modules) already move together, so stuck geometry is dragged along, not torn.
func _crush_check(dented: int, res: Dictionary) -> void:
	var hp := module_hp
	var any := false
	var contacts_changed := false
	for mi in (res["changed"] as Dictionary).keys():
		if mi >= hp.size() or hp[mi] < 0.0 or design.modules[mi]["type"] == ModuleCatalog.BARREL:
			continue
		if hp[mi] > 0.0:
			var vol: float = props["modules"][mi]["volume"]
			if vol < Data.CRUSH_VOLUME_FRACTION * _initial_volume[mi]:
				hp[mi] = 0.0     # flattened: a DEAD wreck
				any = true
			elif _below_min_size(mi):
				hp[mi] = 0.0     # too thin to walk in: dead
				any = true
		if _graph != null and not (res["changed"][mi] as PackedInt32Array).is_empty():
			var before := (_graph.adj[mi] as PackedInt32Array).size()
			_graph.refresh(design, _hull_ids, mi)
			if (_graph.adj[mi] as PackedInt32Array).size() < before:
				contacts_changed = true       # lost a link: maybe cut off now
	if _graph != null and hp[dented] > 0.0 and design.modules[dented]["type"] != ModuleCatalog.BARREL:
		var moved: PackedInt32Array = res["moved"]
		var from: PackedVector3Array = res["moved_from"]
		var step := maxi(1, int(ceil(moved.size() / 48.0)))       # at most ~48 test points per dent
		for nb in _graph.adj[dented]:
			if hp[nb] < 0.0 or design.modules[nb]["type"] == ModuleCatalog.BARREL or _hull_ids[nb].is_empty():
				continue
			var pts := HullShapes.points(design, _hull_ids[nb])
			var crushed := false
			for k in range(0, moved.size(), step):
				var now := PackedVector3Array([design.vertices[moved[k]]])
				if ConvexOverlap.intersects(now, pts, -Data.CRUSH_PENETRATION) \
						and not ConvexOverlap.intersects(PackedVector3Array([from[k]]), pts, -Data.CRUSH_PENETRATION):
					crushed = true
					break
			if crushed:
				hp[dented] = 0.0
				any = true
				break
	if any:
		module_hp = hp
	if any or contacts_changed:
		_structure_dirty = true


## Is module `mi` squeezed below the size a person can walk in (ModuleCatalog.MIN_EXTENT)?
func _below_min_size(mi: int) -> bool:
	var need: float = ModuleCatalog.MIN_EXTENT.get(design.modules[mi]["type"], 0.0)
	if need <= 0.0:
		return false
	if (_hull_ids[mi] as PackedInt32Array).is_empty():
		return false
	# the collision-hull points are the module's extreme vertices: cheap, even for a module of millions of faces
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for v in HullShapes.points(design, _hull_ids[mi]):
		lo = lo.min(v)
		hi = hi.max(v)
	var ext := hi - lo
	return minf(ext.x, minf(ext.y, ext.z)) < need * Data.WALK_SIZE_TOLERANCE


## STRUCTURE CHECK (authority). Runs at most once per physics frame, and only after a module was lost.
##   1. Every group of connected modules WITHOUT a working commander is cut off: its modules are destroyed.
##   2. No group with a commander left -> the ship is lost.
##   3. Several groups with commanders -> the ship SPLITS: the group with the pilot's seat stays, the others become
##      ships of their own (_perform_split).
func _check_structure() -> void:
	if _graph == null:
		return   # the hull is still being built (big ship): try again later
	_structure_dirty = false
	var comps := _graph.components(alive_mask())
	var hp := module_hp
	var commanders_before := _commander_count_alive_before
	var with_cmd: Array[PackedInt32Array] = []
	var cut := false
	for g in comps:
		var has_cmd := false
		for m in g:
			if design.modules[m]["type"] == ModuleCatalog.COMMANDER and hp[m] > 0.0:
				has_cmd = true
				break
		if has_cmd:
			with_cmd.append(g)
		else:
			for m in g:
				hp[m] = -1.0   # GONE: no link to any working commander
				cut = true
	if with_cmd.is_empty():
		if cut:
			module_hp = hp
		_die()
		return
	if cut:
		module_hp = hp
	var alive_cmds := alive_commanders()
	if with_cmd.size() > 1:
		_perform_split(with_cmd)
	elif alive_cmds.size() != commanders_before:
		_report_structure(alive_cmds, [], [])
	_commander_count_alive_before = alive_cmds.size()


var _commander_count_alive_before: int = -1   ## set when the hull is ready


func _die() -> void:
	if not alive:
		return
	alive = false
	var world := get_tree().get_first_node_in_group("world")
	if world != null:
		world.report_death.rpc_id(1, str(name))


## Splitting (authority): every group except the one holding the pilot's seat becomes a new ship.
## Only small numbers travel: which modules, their health, where the part was and how fast it moves.
## Every peer cuts the same modules out of its OWN copy of this ship (deterministic, see ShipDesign.extract).
func _perform_split(groups: Array[PackedInt32Array]) -> void:
	var owner_peer := int(str(name)) if str(name).is_valid_int() else 0
	var seat := Net.seat_of(owner_peer) if owner_peer != 0 else -1
	var stay := 0
	var best := -1
	for gi in groups.size():
		var g: PackedInt32Array = groups[gi]
		var score := g.size()
		if seat >= 0 and g.has(seat):
			score += 1000000
		if score > best:
			best = score
			stay = gi
	var leaving: Array = []
	var payloads: Array = []
	var b := global_transform.basis
	var total_mass := mass
	var hp := module_hp
	for gi in groups.size():
		if gi == stay:
			continue
		var ids := groups[gi].duplicate()
		ids.sort()
		var sub := design.extract(ids)
		var sub_props := sub.compute_props()
		var child_mass: float = sub_props["mass"]
		var r: Vector3 = b * ((sub_props["com"] as Vector3) - _com)
		var push := r.normalized() if r.length() > 0.01 else b.x
		var share := clampf(child_mass / maxf(total_mass + child_mass, 1.0), 0.0, 0.9)
		var child_hp := PackedFloat32Array()
		var child_max := PackedFloat32Array()
		var child_vol := PackedFloat64Array()
		for m in ids:
			child_hp.append(hp[m])
			child_max.append(module_max_hp[m])
			child_vol.append(_initial_volume[m])
			hp[m] = -1.0
		leaving.append(ids)
		payloads.append({
			"xf": global_transform, "com_child": sub_props["com"],
			"vel": linear_velocity + angular_velocity.cross(r) + push * Data.SPLIT_PUSH * (1.0 - share),
			"ang": angular_velocity, "hp": child_hp, "max_hp": child_max, "vol0": child_vol,
		})
		linear_velocity -= push * Data.SPLIT_PUSH * share   # recoil
	module_hp = hp
	var world := get_tree().get_first_node_in_group("world")
	if world != null:
		world.structure_changed.rpc_id(1, str(name), alive_commanders(), leaving, payloads)
	_commander_count_alive_before = alive_commanders().size()


## Commanders were lost without a split: the host re-seats the people aboard.
func _report_structure(alive_cmds: PackedInt32Array, leaving: Array, payloads: Array) -> void:
	var world := get_tree().get_first_node_in_group("world")
	if world != null:
		world.structure_changed.rpc_id(1, str(name), alive_cmds, leaving, payloads)


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
	_refresh_props()    # lost modules: less mass, a new centre of mass, fewer thrusters
	_mesh_dirty = true


func _on_hp_changed_shapes_only() -> void:
	for i in _shapes.size():
		var gone := i < module_hp.size() and module_hp[i] < 0.0     # a DEAD wreck (0) keeps its collision shape
		if gone:
			_shapes[i].disabled = true
		if i < module_hp.size() and module_hp[i] <= 0.0:
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
		ratios.append(-1.0 if module_hp[i] < 0.0 else module_hp[i] / maxf(module_max_hp[i], 0.001))
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
	var graph := ModuleGraph.build(design, ids)   # which modules touch (shared vertices or contact)
	var burn := ExhaustZone.conflicts(design, ids)     # modules standing in a thruster's exhaust (hand-edited files only)
	if OS.is_debug_build() and design.vertices.size() > THREAD_VERTICES:
		print("[Ship %s] face index + collision points + module graph: %d ms" % [name, Time.get_ticks_msec() - t0])
	return {"idx": idx, "ids": ids, "graph": graph, "burn": burn}


func _finish_hull(data: Dictionary, chunks: Array = []) -> void:
	_hull_idx = data["idx"]
	_burn = data["burn"]
	turrets.setup(self)
	for r in turrets.rigs:
		r.node = hull.add_pivot(r.barrel, r.pivot)     # the barrel meshes live in a pivot node that can swivel
	_configure_electricity()
	_graph = data["graph"]
	_build_plan()
	_commander_count_alive_before = alive_commanders().size()
	if chunks.is_empty():
		chunks = HullRenderer.prepare(design)
	if design.vertices.size() > THREAD_VERTICES:
		for mi in _shapes.size():
			_hull_ids[mi] = data["ids"][mi]
			(_shapes[mi].shape as ConvexPolygonShape3D).points = HullShapes.points(design, _hull_ids[mi])
			_shapes[mi].disabled = mi < module_hp.size() and module_hp[mi] < 0.0
	hull.attach(design, chunks)
	_update_mesh()
	if design.vertices.size() <= THREAD_VERTICES:
		hull.flush()
	_hull_ready = true
	for d in _pending_dents:
		apply_dent(d[0], d[1], d[2], d[3], d[4])
	_pending_dents.clear()


## Own ship only: how long until the commander learns of a dent at `p` (see ShipReports). 0 = visible at once.
func _dent_report_delay(p: Vector3) -> float:
	if plan_state == null or not is_flown_by_me() or plan_state.comms_ok:
		return 0.0
	return minf(plan_state.delay_at(p), Data.ORDER_DELAY_MAX)


## The theorised damage spheres (ShipReports.pending) are also drawn on the ship itself, seen from outside.
func _update_report_spheres() -> void:
	var template := report_spheres.get_node("SphereTemplate") as MeshInstance3D
	var shown: Array[Dictionary] = []
	for r in reports.pending:
		if r.get("sphere", false):
			shown.append(r)
	while report_spheres.get_child_count() - 1 < shown.size():
		var m := template.duplicate() as MeshInstance3D
		m.visible = true
		report_spheres.add_child(m)
	var pulse := 0.55 + 0.25 * sin(Time.get_ticks_msec() * 0.006)
	for i in report_spheres.get_child_count() - 1:
		var m := report_spheres.get_child(i + 1) as MeshInstance3D
		m.visible = i < shown.size()
		if m.visible:
			m.position = shown[i]["center"]
			m.scale = Vector3.ONE * float(shown[i]["radius"])
			m.transparency = pulse


func _process(dt: float) -> void:
	if plan_state != null and is_flown_by_me():
		_report_clock += dt
		reports.tick(self, dt)
		_update_report_spheres()
		var k := 0
		while k < _held_dents.size():
			if _report_clock >= float(_held_dents[k]["due"]) or plan_state.comms_ok:
				hull.rebuild(_held_dents[k]["changed"])
				_held_dents.remove_at(k)
			else:
				k += 1
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
	if _function_dirty:
		_function_dirty = false
		var before := working_mask().duplicate()
		_update_function()
		if before != working_mask():
			_refresh_props()
			_mesh_dirty = true
	if _structure_dirty and is_multiplayer_authority():
		_check_structure()
		if not alive:
			return
	if is_multiplayer_authority():
		_authority_step(dt)
		_burn_step(dt)
		turrets.track(dt)
		var angles := turrets.angles()
		if angles != turret_angles:      # only touch the replicated variable when something moved
			turret_angles = angles
	else:
		_remote_step()
		_crew_step(dt)
		turrets.apply_angles(turret_angles, 0.5)
	while not _pending_hits.is_empty():
		apply_hit(_pending_hits.pop_back())
	while not _pending_remote_hits.is_empty():
		var r: Dictionary = _pending_remote_hits.pop_back()
		var victim := r["other"] as Ship
		if is_instance_valid(victim) and multiplayer.has_multiplayer_peer():
			victim.receive_ram.rpc_id(victim.get_multiplayer_authority(), r["module"], r["point"], r["normal"],
				r["closing"], r["mass"], r["hardness"])
	_update_flames()


## Smooth what the ship gives off (so it fades instead of flickering) and round it so the network rarely resends it.
func _update_signatures(dt: float, elec_w: float, heat_w: float) -> void:
	var a := clampf(dt * 2.0, 0.0, 1.0)
	_sig_elec_f = lerpf(_sig_elec_f, elec_w, a)
	_sig_heat_f = lerpf(_sig_heat_f, heat_w, a)
	var e := snappedf(_sig_elec_f, 2000.0)
	var h := snappedf(_sig_heat_f, 5000.0)
	if e != sig_elec:
		sig_elec = e
	if h != sig_heat:
		sig_heat = h
	_net_timer -= dt
	if _net_timer <= 0.0:
		_net_timer = 0.5
		_update_net_visibility()


func _authority_step(dt: float) -> void:
	var b := global_transform.basis
	var thr := PackedFloat32Array()
	thr.resize(alloc.n)
	var f_rcs := Vector3.ZERO
	var tau := Vector3.ZERO

	var gui_typing := get_viewport().gui_get_focus_owner() is LineEdit or not is_flown_by_me()
	if not gui_typing:
		if Input.is_action_just_pressed("toggle_control_mode"):
			stations.toggle_mode()
		elif Input.is_action_just_pressed("next_station") and stations.mode == "crew":
			stations.next_station()
	var typing := gui_typing or not stations.can_fly()     # only the pilot seat flies the ship (see ShipStations)
	var manual := _read_manual(typing)
	if not i_fly():
		# the owner sits at a gunner-only bridge: the ship is flown by a CREW member at a pilot bridge (if any)
		if autopilot.is_active():
			autopilot.cancel()
		manual = _crew_manual()
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

	thr = _delayed_throttles(thr, dt)
	f_rcs = rcs.clamp_force(f_rcs)
	tau = gyro.clamp_torque(tau)

	var thrust_w := 0.0       # watts the thrusters ask for (each has its own electricity per newton)
	var heat_w := Data.HEAT_BASE_W + weapons.firing_heat()
	for i in alloc.n:
		var newtons: float = alloc.power[i] * thr[i]
		thrust_w += newtons * _thr_elec[i]
		heat_w += newtons * _thr_heat[i]
	var k := electricity.consume(thrust_w, f_rcs.length(), absf(tau.x) + absf(tau.y) + absf(tau.z),
		weapons.firing_power())
	_update_signatures(dt, electricity.demand_w, heat_w * k)

	# main thrusters: force applied AT each thruster's position (makes torque)
	for i in alloc.n:
		if thr[i] > 0.0001:
			var f_body: Vector3 = alloc.col_f[i] * (thr[i] * k)
			apply_force(b * f_body, b * (alloc.pos[i] + _com))   # apply_force takes the offset from the body ORIGIN
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

	_gunnery(k, gui_typing)

	sync_pos = global_position
	sync_quat = global_transform.basis.get_rotation_quaternion()
	sync_vel = linear_velocity


## ORDER DELAY. Without communications the pilot's thruster orders must be WALKED to each engine room: thruster i obeys
## the command the pilot gave order_delay(i) seconds ago (PlanState.order_delay). With communications: no delay.
func _delayed_throttles(thr: PackedFloat32Array, dt: float) -> PackedFloat32Array:
	if plan_state != null and plan_state.engines_cut():
		_cmd_hist.clear()
		var none := thr.duplicate()
		none.fill(0.0)
		return none               # the engine rooms are gone: no thruster gets its orders
	if plan_state == null or plan_state.comms_ok or _thr_module.size() != thr.size():
		_cmd_hist.clear()
		return thr
	_cmd_clock += dt
	if _cmd_hist.is_empty() or _cmd_clock - float(_cmd_hist.back()[0]) >= 0.05:
		_cmd_hist.append([_cmd_clock, thr.duplicate()])
	while _cmd_hist.size() > 2 and _cmd_clock - float(_cmd_hist[1][0]) > Data.ORDER_DELAY_MAX:
		_cmd_hist.pop_front()
	var out := thr.duplicate()
	for i in out.size():
		var delay := plan_state.order_delay(_thr_module[i])
		if delay <= 0.05:
			continue
		var want := _cmd_clock - minf(delay, Data.ORDER_DELAY_MAX)
		var v := 0.0
		for k in range(_cmd_hist.size() - 1, -1, -1):
			if float(_cmd_hist[k][0]) <= want:
				v = (_cmd_hist[k][1] as PackedFloat32Array)[i]
				break
		out[i] = v
	return out


## Aiming and firing for the player who flies this ship (authority). What happens depends on the control mode:
##   commander mode: automatic gunnery on the nearest enemy (+ the autopilot flies to a firing position)
##   crew mode:      the mouse (screen centre in first person) aims the guns of the CURRENT station only;
##                   a locked target (R) is aimed at with lead instead of the mouse.
func _gunnery(k: float, gui_typing: bool) -> void:
	# crew members aboard (lobby seats) work all the turrets as before; alone, only the current station's guns fire
	stations.apply_filter(turrets, Net.crew_count(get_multiplayer_authority()) > 0)
	if gui_typing or not is_flown_by_me():
		return
	if Input.is_action_just_pressed("lock_target"):
		detection.cycle_lock()
	if stations.is_commander_mode():
		_auto_gunnery(k)
		return
	if turrets.filter_base == -1:
		turrets.has_aim = false
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null or get_viewport().gui_get_hovered_control() != null and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	var m := get_viewport().get_mouse_position()
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		m = get_viewport().get_visible_rect().size * 0.5
	var aim := cam.project_ray_origin(m) + cam.project_ray_normal(m) * 400.0
	if detection.locked != null:     # a locked target: aim at where it WILL be (lead), not at the mouse
		var lead := detection.lead_point(turrets.average_muzzle_speed())
		if lead != Vector3.ZERO:
			aim = lead
	_take_aim(aim)
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		weapons.try_fire(aim, k, PackedInt32Array(), true)       # crew mode: the trigger fires the turret you control, aimed or not


## Commander mode: true = the guns fire at the locked target on their own (default false: they wait for the player).
var weapons_free: bool = false
## Commander mode: the AI used to fly towards the enemy by itself. Off now: the ship only goes where it is ordered.
var auto_close_in: bool = false
var fire_ready: bool = false          ## a target is locked and in range: the guns would fire on command (for the HUD)
var _engage_timer: float = 0.0
var _engage_target: Vector3 = Vector3(1e9, 1e9, 1e9)

## Commander mode: pick the nearest enemy, lead it, fire when it is close enough, and fly to a firing position.
func _auto_gunnery(k: float) -> void:
	if detection.locked == null:
		var list := detection.enemies()
		if not list.is_empty():
			detection.locked = list[0]["ship"]
	if detection.locked == null:
		turrets.has_aim = false
		return
	var c := detection.find_contact(detection.locked)
	var lead := detection.lead_point(turrets.average_muzzle_speed())
	if c.is_empty() or lead == Vector3.ZERO:
		return
	_take_aim(lead)
	var dist: float = c["dist"]
	# HALF AUTOMATIC: radar locks and the turrets keep aiming, but the guns only fire when the player says so
	# (hold the left mouse button over the 3D view, or switch WEAPONS FREE on with H).
	var trigger := weapons_free or (Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and get_viewport().gui_get_hovered_control() == null)
	fire_ready = dist <= Data.AUTO_FIRE_RANGE
	if fire_ready and trigger:
		weapons.try_fire(lead, k)
	_engage_timer -= get_physics_process_delta_time()
	# a destination the player typed in the autopilot panel always wins over our own "close in on the enemy" order
	var player_order := autopilot.is_active() and autopilot.player_order
	if auto_close_in and _engage_timer <= 0.0 and not player_order and dist > Data.AUTO_FIRE_RANGE * 0.8:
		_engage_timer = 2.0
		var to_target: Vector3 = (c["est_pos"] as Vector3) - global_position
		_engage_target = global_position + to_target.normalized() * maxf(dist - Data.AUTO_FIRE_RANGE * 0.6, 0.0)
		if i_fly():
			autopilot.go_to(_engage_target, false)


## Modules that stand in the exhaust of a firing thruster burn (they should not exist in a validated design,
## but a hand-edited file or a dent can put one there).
func _burn_step(dt: float) -> void:
	if _burn.is_empty():
		return
	for pair in _burn:
		var t_mod := pair.x
		if module_hp[pair.y] <= 0.0 or module_hp[t_mod] <= 0.0:
			continue
		var idx := _thr_module.find(t_mod)
		if idx >= 0 and idx < throttles.size() and throttles[idx] > 0.2:
			_remove_module_hp(pair.y, Data.EXHAUST_BURN_DPS * throttles[idx] * dt)


## The owner aims: their commander's turrets follow `aim` (they take the aim back from crew at the same bridge).
func _take_aim(aim: Vector3) -> void:
	turrets.aim_point = aim
	turrets.has_aim = true
	turrets.clear_aim_for(bases_of_seat(my_commander()))


## Flight orders sent by a CREW member at a pilot bridge (only used while the owner cannot fly).
var _crew_was_flying: bool = false
var _crew_flight: Dictionary = {}
var _crew_flight_ms: int = 0

func _crew_manual() -> Dictionary:
	if Time.get_ticks_msec() - _crew_flight_ms > 400 or _crew_flight.is_empty():
		return {"move": Vector3.ZERO, "rot": Vector3.ZERO, "active": false}
	return _crew_flight


## Crew peer -> ship owner: "my thrust / rotation keys". Accepted only from a crew member whose commander holds the flight controls.
@rpc("any_peer", "call_remote", "unreliable")
func request_flight(move: Vector3, rot: Vector3) -> void:
	if not is_multiplayer_authority() or not alive or not move.is_finite() or not rot.is_finite():
		return
	var sender := multiplayer.get_remote_sender_id()
	if int(Net.players.get(sender, {}).get("crew_of", 0)) != multiplayer.get_unique_id():
		return
	if not design.controls_flight(Net.seat_of(sender)):
		return
	_crew_flight = {"move": move.limit_length(1.0), "rot": rot.limit_length(1.0), "active": move != Vector3.ZERO or rot != Vector3.ZERO}
	_crew_flight_ms = Time.get_ticks_msec()


## A crew member controls what THEIR commander is linked to: aim with the mouse, left click fires; a pilot bridge flies.
func _crew_step(dt: float) -> void:
	_crew_cooldown = maxf(_crew_cooldown - dt, 0.0)
	if _crew_cooldown > 0.0 or not Net.is_crew_on(self):
		return
	if get_viewport().gui_get_focus_owner() is LineEdit or get_viewport().gui_get_hovered_control() != null:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var m := get_viewport().get_mouse_position()
	var aim := cam.project_ray_origin(m) + cam.project_ray_normal(m) * 400.0
	_crew_cooldown = 0.08          # 12 messages per second at most
	var my_seat := Net.seat_of(multiplayer.get_unique_id())
	if design.controls_flight(my_seat):
		var fl := _read_manual(false)
		if fl["active"] or _crew_was_flying:
			request_flight.rpc_id(get_multiplayer_authority(), fl["move"], fl["rot"])
		_crew_was_flying = fl["active"]
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		weapons.request_fire.rpc_id(get_multiplayer_authority(), aim)
	else:
		weapons.request_aim.rpc_id(get_multiplayer_authority(), aim)


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
	if not is_multiplayer_authority() or not alive or not is_flown_by_me():
		return
	if event.is_action_pressed("brake"):
		autopilot.brake()
	elif event.is_action_pressed("hold_attitude"):
		flight_assist = not flight_assist
	elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_H \
			and not (get_viewport().gui_get_focus_owner() is LineEdit):
		weapons_free = not weapons_free
		BusEvent.notify.emit("WEAPONS FREE: the guns fire on their own" if weapons_free else "WEAPONS HOLD: hold the left mouse button to fire")


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
		mm.set_instance_transform(i, Transform3D(flame_basis, alloc.pos[i] + _com + e * (0.2 * s + flame_len * 0.5)))
