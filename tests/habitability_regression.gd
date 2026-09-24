extends SceneTree


func _initialize() -> void:
	var star := Star.new()
	star.luminosity = 1.0
	star.spectral_type = "Sarı Cüce"
	var zones := HabitabilityModel.get_orbital_zones(star.luminosity)
	if not is_equal_approx(zones.habitable_inner_m / HabitabilityModel.ONE_AU, 0.95):
		push_error("Solar habitable-zone inner edge must be near 0.95 AU")
		quit(1)
		return
	var planet := Planet.new()
	planet.planet_type = "OCEAN_WORLD"
	planet.real_radius = HabitabilityModel.EARTH_RADIUS
	planet.orbit_radius = 1.0 * HabitabilityModel.ONE_AU
	planet.has_atmosphere = true
	var rng := RandomNumberGenerator.new()
	rng.seed = 8128
	HabitabilityModel.evaluate_planet(planet, star, rng)
	if planet.climate_zone != "HABITABLE" or planet.habitability_score <= 0.5:
		push_error("Earth-like ocean planet must be evaluated inside the habitable zone")
		quit(1)
		return
	planet.orbit_radius = 0.2 * HabitabilityModel.ONE_AU
	rng.seed = 8128
	HabitabilityModel.evaluate_planet(planet, star, rng)
	if planet.climate_zone != "HOT" or planet.is_habitable:
		push_error("Close orbit must be hot and non-habitable")
		quit(1)
		return
	print("HABITABILITY_REGRESSION_OK score=%.2f" % planet.habitability_score)
	quit(0)
