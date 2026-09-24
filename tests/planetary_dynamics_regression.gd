extends SceneTree


func _initialize() -> void:
	var star := Star.new()
	star.mass_solar = 1.0
	star.luminosity = 1.0
	star.stellar_activity = 1.0
	var planet := Planet.new()
	planet.orbit_radius = PlanetaryDynamicsModel.ONE_AU
	planet.mass_earth = 1.0
	planet.planet_type = "OCEAN_WORLD"
	planet.is_habitable = true
	planet.habitability_score = 1.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 44
	PlanetaryDynamicsModel.evaluate_planet(planet, star, rng)
	if absf(planet.orbital_period_days - 365.25) > 0.1:
		push_error("Earth orbit around a solar-mass star must be one year")
		quit(1)
		return
	if planet.magnetic_field_earth <= 0.0 or planet.radiation_level < 0.0:
		push_error("Planet dynamics must calculate magnetism and radiation")
		quit(1)
		return
	var moon := Moon.new()
	moon.orbit_radius = 384400000.0
	var host := Planet.new()
	host.real_radius = 6371000.0
	host.radiation_level = planet.radiation_level
	PlanetaryDynamicsModel.evaluate_moon(moon, host, star, rng)
	if not moon.is_tidally_locked or moon.rotation_period_hours <= 0.0:
		push_error("Generated moons must be tidally locked to their host")
		quit(1)
		return
	print("PLANETARY_DYNAMICS_REGRESSION_OK year=%.2f" % planet.orbital_period_days)
	quit(0)
