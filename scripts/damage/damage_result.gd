class_name DamageResult
extends RefCounted
## What a DamageType decided: how much HP to remove and whether/how to dent the hull.

var hp_damage: float = 0.0
## Dent: vertices within `dent_radius` (m) of the impact are pushed `dent_depth` (m) along `dent_direction` (world).
var dent_depth: float = 0.0
var dent_radius: float = 0.0
var dent_direction: Vector3 = Vector3.ZERO


func is_empty() -> bool:
	return hp_damage <= 0.0 and dent_depth <= 0.0
