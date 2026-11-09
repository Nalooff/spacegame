class_name WorldBuilder
extends Node3D
## Builds the battlefield of a map (MapCatalog) inside the game world: environment + sky shader, one directional light per
## sun, asteroid fields (one MultiMesh per rock shape, every rock tumbling), and dust drifting around the camera so that
## flying through space is felt. Nothing here is networked: every peer builds the same map from the same map id.
##   WorldBuilder.build(world, MapCatalog.get_map(id))

const SKY := preload("res://shaders/space_sky.gdshader")
const ROCK := preload("res://shaders/rock.gdshader")
const ROCK_SHAPES := 4

var _dust: GPUParticles3D = null
var _suns: Array = []
var map: Dictionary = {}


## Replaces the world's environment and landmarks with the map's. Returns the builder node (child of `world`).
static func build(world: Node3D, m: Dictionary) -> WorldBuilder:
	var b := WorldBuilder.new()
	b.name = "MapDecor"
	b.map = m
	world.add_child(b)
	b._build(world)
	return b


func _build(world: Node3D) -> void:
	if map["id"] == MapCatalog.CLASSIC:
		return                                   # the classic arena is exactly what game_world.tscn contains
	var old_sun := world.get_node_or_null("Sun")
	if old_sun != null:
		old_sun.queue_free()
	var lm := world.get_node_or_null("Landmarks")
	if lm != null:
		lm.queue_free()
	_build_environment(world)
	_build_lights()
	_build_rocks(world)
	if OS.get_environment("NODUST") == "":
		_build_dust()


func _build_environment(world: Node3D) -> void:
	var sky_cfg: Dictionary = map["sky"]
	var mat := ShaderMaterial.new()
	mat.shader = SKY
	for k in ["bg_low", "bg_high", "neb_a", "neb_b", "neb_c", "galaxy_n"]:
		mat.set_shader_parameter("galaxy_normal" if k == "galaxy_n" else k, sky_cfg[k])
	mat.set_shader_parameter("neb_amount", sky_cfg["neb"])
	for k in ["neb_scale", "neb_drift"]:
		mat.set_shader_parameter(k, sky_cfg[k])
	mat.set_shader_parameter("star_amount", sky_cfg["stars"])
	mat.set_shader_parameter("star_bright", sky_cfg["star_bright"])
	mat.set_shader_parameter("galaxy", sky_cfg["galaxy"])
	var suns: Array = map["suns"]
	var sd := PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP])
	var sc := PackedVector3Array([Vector3.ZERO, Vector3.ZERO, Vector3.ZERO])
	var ss := PackedFloat32Array([0.01, 0.01, 0.01])
	for i in mini(suns.size(), 3):
		sd[i] = (suns[i]["dir"] as Vector3).normalized()
		var c: Color = suns[i]["color"]
		sc[i] = Vector3(c.r, c.g, c.b)
		ss[i] = suns[i]["size"]
	mat.set_shader_parameter("sun_count", mini(suns.size(), 3))
	mat.set_shader_parameter("sun_dir", sd)
	mat.set_shader_parameter("sun_col", sc)
	mat.set_shader_parameter("sun_size", ss)
	var planets: Array = map["planets"]
	var pd := PackedVector3Array([Vector3.UP, Vector3.UP])
	var psz := PackedFloat32Array([0.1, 0.1])
	var pa := PackedVector3Array([Vector3.ZERO, Vector3.ZERO])
	var pb := PackedVector3Array([Vector3.ZERO, Vector3.ZERO])
	var pcc := PackedVector3Array([Vector3.ZERO, Vector3.ZERO])
	var patm := PackedVector3Array([Vector3.ZERO, Vector3.ZERO])
	var pm := PackedVector4Array([Vector4(), Vector4()])
	var prn := PackedVector3Array([Vector3.UP, Vector3.UP])
	var prc := PackedVector3Array([Vector3.ONE, Vector3.ONE])
	for i in mini(planets.size(), 2):
		var p: Dictionary = planets[i]
		pd[i] = (p["dir"] as Vector3).normalized()
		psz[i] = p["size"]
		pa[i] = _v3(p["a"])
		pb[i] = _v3(p["b"])
		pcc[i] = _v3(p["c"])
		patm[i] = _v3(p["atm"])
		pm[i] = Vector4(float(p["kind"]), 1.0 if p["ring"] else 0.0, p["spin"], p["seed"])
		prn[i] = (p["ring_n"] as Vector3).normalized()
		prc[i] = _v3(p["ring_col"])
	mat.set_shader_parameter("planet_count", mini(planets.size(), 2))
	mat.set_shader_parameter("planet_dir", pd)
	mat.set_shader_parameter("planet_size", psz)
	mat.set_shader_parameter("planet_a", pa)
	mat.set_shader_parameter("planet_b", pb)
	mat.set_shader_parameter("planet_c", pcc)
	mat.set_shader_parameter("planet_atm", patm)
	mat.set_shader_parameter("planet_misc", pm)
	mat.set_shader_parameter("planet_ring_n", prn)
	mat.set_shader_parameter("planet_ring_col", prc)
	var sky := Sky.new()
	sky.sky_material = mat
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = float(map.get("ambient", 0.6))
	env.ambient_light_sky_contribution = 0.75
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.glow_enabled = true               # the HDR suns and lit windows bloom
	env.glow_intensity = 0.9
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.glow_intensity = 0.45
	var we := world.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we != null:
		we.environment = env


func _v3(c: Color) -> Vector3:
	return Vector3(c.r, c.g, c.b)


## One DirectionalLight3D per sun, shining from the sun's direction in the sky: the light and the glowing disc agree.
func _build_lights() -> void:
	for s in map["suns"]:
		var l := DirectionalLight3D.new()
		var dir: Vector3 = (s["dir"] as Vector3).normalized()
		var up := Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT
		l.basis = Basis.looking_at(-dir, up)
		l.light_color = s["light"]
		l.light_energy = s["energy"]
		l.light_specular = 1.0
		l.light_angular_distance = rad_to_deg(float(s["size"])) * 0.5
		add_child(l)
		_suns.append(l)


# ---- asteroids -------------------------------------------------------------------------------------------------------
func _build_rocks(world: Node3D) -> void:
	var cfg: Dictionary = map["rocks"]
	var count: int = cfg["count"]
	var hero: int = cfg["hero"]
	if count + hero <= 0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(map["id"]))
	var mat := ShaderMaterial.new()
	mat.shader = ROCK
	mat.set_shader_parameter("tint_a", cfg["tint_a"])
	mat.set_shader_parameter("tint_b", cfg["tint_b"])
	mat.set_shader_parameter("glow_amount", cfg["glow"])
	var spawn_pts: Array[Vector3] = []
	var sp := world.get_node_or_null("SpawnPoints")
	if sp != null:
		for c in sp.get_children():
			spawn_pts.append((c as Node3D).position)
	var spawn_r: float = map["spawn_radius"]
	var per: Array = []
	for i in ROCK_SHAPES:
		per.append([])
	var total := count + hero
	for i in total:
		var is_hero := i >= count
		var size := rng.randf_range(cfg["min"], cfg["max"]) * (rng.randf_range(0.4, 1.0) if not is_hero else 1.0)
		if is_hero:
			size = rng.randf_range(float(cfg["max"]) * 1.5, float(cfg["max"]) * 4.0)
		var pos := _rock_position(cfg, rng)
		var tries := 0
		while tries < 12 and _near_spawn(pos, size, spawn_pts, spawn_r):
			pos = _rock_position(cfg, rng)
			tries += 1
		if tries >= 12:
			continue
		var rb := Basis.from_euler(Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU))
		rb = rb.scaled(Vector3(size * rng.randf_range(0.7, 1.3), size * rng.randf_range(0.6, 1.2), size * rng.randf_range(0.7, 1.3)))
		var axis := Vector3(rng.randf() - 0.5, rng.randf() - 0.5, rng.randf() - 0.5).normalized()
		var speed := rng.randf_range(-0.06, 0.06) * (20.0 / maxf(size, 8.0)) ** 0.5
		(per[i % ROCK_SHAPES] as Array).append([Transform3D(rb, pos), Color(axis.x, axis.y, axis.z, speed)])
	for s in ROCK_SHAPES:
		var list: Array = per[s]
		if list.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = _rock_mesh(s)
		mm.instance_count = list.size()
		for j in list.size():
			mm.set_instance_transform(j, list[j][0])
			mm.set_instance_custom_data(j, list[j][1])
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = mat
		mi.name = "Rocks%d" % s
		mi.custom_aabb = AABB(Vector3.ONE * -float(cfg["spread"]) * 1.6, Vector3.ONE * float(cfg["spread"]) * 3.2)
		add_child(mi)


func _rock_position(cfg: Dictionary, rng: RandomNumberGenerator) -> Vector3:
	var spread: float = cfg["spread"]
	var flat: float = cfg["flat"]
	var dir := Vector3(rng.randfn(0.0, 1.0), rng.randfn(0.0, 1.0), rng.randfn(0.0, 1.0)).normalized()
	match String(cfg["mode"]):
		"belt":        # a thick ring around the middle: far away, thin in height
			var a := rng.randf() * TAU
			var r := spread * rng.randf_range(0.35, 1.0)
			return Vector3(cos(a) * r, rng.randfn(0.0, 1.0) * spread * flat * 0.25, sin(a) * r)
		"shell":       # a loose sphere of rocks far out
			return dir * spread * rng.randf_range(0.6, 1.0)
		_:
			return dir * spread * pow(rng.randf(), 0.6) * Vector3(1.0, flat, 1.0)


func _near_spawn(pos: Vector3, size: float, pts: Array[Vector3], spawn_r: float) -> bool:
	if pos.length() < 120.0 + size:
		return true
	for p in pts:
		if p.distance_to(pos) < size * 1.6 + 260.0:
			return true
	# also keep the ring itself reasonably clear
	return false and spawn_r > 0.0


static var _mesh_cache := {}


## A lumpy rock: an icosphere pushed in and out by noise, flat shaded. Four shapes, made once.
static func _rock_mesh(shape: int) -> ArrayMesh:
	if _mesh_cache.has(shape):
		return _mesh_cache[shape]
	var t := (1.0 + sqrt(5.0)) * 0.5
	var verts: Array[Vector3] = []
	for v in [Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0), Vector3(0, -1, t), Vector3(0, 1, t),
			Vector3(0, -1, -t), Vector3(0, 1, -t), Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]:
		verts.append((v as Vector3).normalized())
	var faces: Array = [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
		[3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9], [4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]]
	for level in 2:                                     # subdivide twice: 320 triangles
		var next: Array = []
		var cache := {}
		for f in faces:
			var m: Array = []
			for k in 3:
				var a: int = f[k]
				var b: int = f[(k + 1) % 3]
				var key := Vector2i(mini(a, b), maxi(a, b))
				if not cache.has(key):
					verts.append(((verts[a] + verts[b]) * 0.5).normalized())
					cache[key] = verts.size() - 1
				m.append(cache[key])
			next.append([f[0], m[0], m[2]])
			next.append([f[1], m[1], m[0]])
			next.append([f[2], m[2], m[1]])
			next.append([m[0], m[1], m[2]])
		faces = next
	var noise := FastNoiseLite.new()
	noise.seed = 100 + shape * 37
	noise.frequency = 1.3
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var shaped: Array[Vector3] = []
	for v in verts:
		var r := 1.0 + noise.get_noise_3dv(v * 2.0) * 0.45 + noise.get_noise_3dv(v * 7.0) * 0.12
		shaped.append(v * r)
	for f in faces:
		for k in 3:
			st.add_vertex(shaped[f[k]])
	st.generate_normals()
	var mesh := st.commit()
	_mesh_cache[shape] = mesh
	return mesh


# ---- dust ------------------------------------------------------------------------------------------------------------
func _build_dust() -> void:
	var cfg: Dictionary = map["dust"]
	if int(cfg["amount"]) <= 0:
		return
	var p := GPUParticles3D.new()
	p.name = "Dust"
	p.amount = int(cfg["amount"])
	p.lifetime = 24.0
	p.preprocess = 24.0
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3.ONE * -400.0, Vector3.ONE * 800.0)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3.ONE * 300.0
	pm.gravity = Vector3.ZERO
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 1.5
	pm.direction = Vector3(0, 0, 0)
	pm.spread = 180.0
	pm.scale_min = 0.5
	pm.scale_max = 1.6
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.4
	pm.turbulence_noise_scale = 4.0
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.0))
	curve.add_point(Vector2(0.15, 1.0))
	curve.add_point(Vector2(0.85, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.35, 0.35)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(cfg["color"].r, cfg["color"].g, cfg["color"].b, 0.55)
	mat.vertex_color_use_as_albedo = false
	q.material = mat
	p.draw_pass_1 = q
	add_child(p)
	_dust = p


func _process(_dt: float) -> void:
	if _dust != null and is_instance_valid(_dust):
		var cam := get_viewport().get_camera_3d()
		if cam != null:
			_dust.global_position = cam.global_position
