extends Node
## Frame time of the exploded 3D plan of the Dreadnought (needs a display: xvfb-run).
func _ready() -> void:
	var cam := Camera3D.new(); add_child(cam)
	var pool := ProjectilePool.new(); pool.name = "ProjectilePool"; add_child(pool)
	var me: Ship = load("res://scenes/ship.tscn").instantiate()
	me.design_blob = ShipDesign.read_blob("res://ships/Dreadnought.ship"); me.name = "1"
	add_child(me)
	Data.local_ship = me
	cam.position = Vector3(0, 300, 900); cam.look_at(Vector3.ZERO); cam.make_current()
	var hud: Node = load("res://scenes/hud.tscn").instantiate()
	add_child(hud)
	for i in 20: await get_tree().physics_frame
	var tb := Time.get_ticks_usec()
	for i in 30:
		await get_tree().process_frame
	print("plan closed: %.1f ms per frame" % ((Time.get_ticks_usec() - tb) / 30000.0))
	var pv: PlanView = hud.get_node("HudRoot/PlanView")
	pv.open_ship(me)
	pv.canvas.set_view(PlanCanvas.View.ISO)
	pv.canvas.set_explode(1.0)
	for i in 10: await get_tree().process_frame
	var t := Time.get_ticks_usec()
	for i in 60:
		pv.canvas.queue_redraw()
		await get_tree().process_frame
	print("exploded plan: %.1f ms per frame" % ((Time.get_ticks_usec() - t) / 60000.0))
	var t0 := Time.get_ticks_usec()
	pv.canvas._iso_hover = 5
	for i in 60:
		await get_tree().process_frame
	print("hovering (animating): %.1f ms per frame" % ((Time.get_ticks_usec() - t0) / 60000.0))
	pv.canvas._iso_hover = -1
	for i in 20: await get_tree().process_frame
	if OS.get_environment("TILT") != "":
		pv.canvas._iso_pitch = deg_to_rad(65.0)
		pv.canvas._iso_yaw = 1.0
		pv.canvas._iso_zoom_at(3.0, Vector2(800, 450))
		for i in 10: await get_tree().process_frame
	if OS.get_environment("OUT") != "":
		get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT"))
	get_tree().quit()
