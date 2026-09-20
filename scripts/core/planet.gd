class_name Planet
extends CelestialBody

# Gezegenin prosedürel kimliği aynı sistem tohumu ve sıra numarasından gelir.
var terrain_seed: int = 0

func _init() -> void:
	type = "PLANET"

func is_gas_giant() -> bool:
	return planet_type == "GAS_GIANT"

func get_surface_gravity_ratio() -> float:
	return clampf(real_radius / 6371000.0, 0.05, 3.5)

