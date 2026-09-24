class_name RingSystemModel
extends RefCounted


static func apply(planet: CelestialBody, rng: RandomNumberGenerator) -> void:
	var chance := 0.62 if planet.planet_type == "GAS_GIANT" else (0.22 if planet.planet_type == "ICE_WORLD" else 0.035)
	planet.has_rings = rng.randf() < chance
	if not planet.has_rings:
		return
	planet.ring_inner_ratio = rng.randf_range(1.25, 1.65)
	planet.ring_outer_ratio = rng.randf_range(maxf(planet.ring_inner_ratio + 0.25, 1.8), 2.8)
	planet.ring_density = rng.randf_range(0.25, 0.9)
	planet.ring_color = planet.base_color.lightened(rng.randf_range(0.15, 0.45))

