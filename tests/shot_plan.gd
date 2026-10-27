extends Node
## Screenshot: live ship plan of a damaged Brick (antenna dead, corridors hit).  tools/shots.sh res://tests/shot_plan.tscn out.png
func _ready() -> void:
	var cam := Camera3D.new(); add_child(cam)
	var pool := ProjectilePool.new(); pool.name = "ProjectilePool"; add_child(pool)
	var me: Ship = load("res://scenes/ship.tscn").instantiate()
	me.design_blob = ShipDesign.read_blob("res://ships/Brick.json"); me.name = "1"
	add_child(me)
	Data.local_ship = me
	cam.position = Vector3(14, 8, 16); cam.look_at(Vector3.ZERO); cam.make_current()
	var light := DirectionalLight3D.new(); light.rotation = Vector3(-0.8, 0.6, 0); add_child(light)
	var hud: Node = load("res://scenes/hud.tscn").instantiate()
	add_child(hud)
	for i in 10: await get_tree().physics_frame
	for mi in me.design.modules.size():
		if me.design.modules[mi]["type"] == "antenna":
			me.apply_damage(mi, 1e9)
	for i in 10: await get_tree().physics_frame
	me.apply_damage(5, 1e9)       # a thruster dies: the report is on its way
	for i in 4:
		me.apply_hit(DamageHit.kinetic(0, 500.0, me.global_transform * Vector3(0.5, 0, -3.0 + i * 1.5), null, me.global_transform.basis * Vector3(0, 0, 1), 5.0))
	for i in 10: await get_tree().physics_frame
	if OS.get_environment("SHOT_3D") == "":
		(hud.get_node("HudRoot/PlanView") as PlanView).open_ship(me)
	if OS.get_environment("SHOT_SIDE") != "" and OS.get_environment("SHOT_3D") == "":
		hud.get_node("HudRoot/PlanView").canvas.set_view(PlanCanvas.View.SIDE)
	var dk := OS.get_environment("SHOT_DECK")
	if dk != "" and OS.get_environment("SHOT_3D") == "":
		hud.get_node("HudRoot/PlanView").canvas.set_deck(int(dk))
