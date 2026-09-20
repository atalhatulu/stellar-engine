class_name Moon
extends CelestialBody

var terrain_seed: int = 0

func _init() -> void:
	type = "MOON"

func get_host_planet() -> Planet:
	return parent_body as Planet

