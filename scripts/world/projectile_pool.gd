class_name ProjectilePool
extends Node3D
## Pool of reusable bullets. The bullets are created once in _ready() and then only switched
## on/off, so no node is created or freed while shooting. (They are made in code on purpose:
## nobody needs to see or edit 48 identical nodes in the editor.)
##
## Change how many bullets can fly at once in Data.PROJECTILE_POOL_SIZE.
## `bolt_mesh` (set in game_world.tscn) is the look of a bullet.

@export var bolt_mesh: Mesh

var _next: int = 0


func _ready() -> void:
	add_to_group("projectile_pool")
	for i in Data.PROJECTILE_POOL_SIZE:
		var shot := Projectile.new()
		shot.name = "Shot%02d" % i
		var visual := MeshInstance3D.new()
		visual.name = "Bolt"
		visual.mesh = bolt_mesh
		shot.add_child(visual)
		add_child(shot)


## Wakes up the next free bullet (round robin). Recycles the oldest if all are in flight.
func spawn_shot(pos: Vector3, vel: Vector3, from_ship: Ship, dmg: float) -> void:
	var count := get_child_count()
	if count == 0:
		return
	for i in count:
		var p := get_child((_next + i) % count) as Projectile
		if p != null and not p.active:
			_next = (_next + i + 1) % count
			p.activate(pos, vel, from_ship, dmg)
			return
	var oldest := get_child(_next % count) as Projectile
	_next = (_next + 1) % count
	oldest.activate(pos, vel, from_ship, dmg)
