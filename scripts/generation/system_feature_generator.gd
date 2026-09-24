class_name SystemFeatureGenerator
extends RefCounted

const ONE_AU := 149597870700.0


static func generate_asteroid_belts(star: CelestialBody, frost_line: float, rng: RandomNumberGenerator) -> void:
	star.asteroid_belts.clear()
	var count := rng.randi_range(1, 2) if star.system_type == "ASTEROID_RICH" else (1 if rng.randf() < 0.22 else 0)
	for index in range(count):
		star.asteroid_belts.append({
			"name": "Ana Asteroit Kuşağı" if index == 0 else "Dış Enkaz Kuşağı",
			"radius_m": frost_line * rng.randf_range(0.72, 1.15) * (index + 1),
			"density": rng.randf_range(0.25, 1.0),
		})


static func create_companion(star: CelestialBody, rng: RandomNumberGenerator) -> Star:
	if not star.system_type == "BINARY_CANDIDATE":
		return null
	var companion := Star.new()
	companion.unique_id = star.unique_id + ":COMPANION_B"
	companion.system_id = star.unique_id
	companion.parent_id = star.unique_id
	companion.parent_body = star
	companion.name = star.name + " B"
	companion.spectral_type = "Kırmızı Cüce" if rng.randf() < 0.72 else "Turuncu Cüce"
	companion.mass_solar = rng.randf_range(0.15, 0.8)
	companion.luminosity = pow(companion.mass_solar, 3.5)
	companion.temperature_kelvin = rng.randf_range(2800.0, 5000.0)
	companion.real_radius = rng.randf_range(180000000.0, 520000000.0)
	companion.base_color = Color(1.0, 0.38, 0.15)
	companion.light_color = companion.base_color
	companion.orbit_radius = rng.randf_range(8.0, 45.0) * ONE_AU
	companion.orbit_angle = rng.randf_range(0.0, TAU)
	companion.orbit_speed = rng.randf_range(0.0001, 0.001)
	companion.local_position = companion.get_orbit_position()
	companion.real_position = companion.local_position
	companion.max_visibility_distance = INF
	return companion
