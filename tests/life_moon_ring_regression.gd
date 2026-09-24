extends SceneTree


func _initialize() -> void:
	var star := Star.new()
	star.luminosity = 1.0
	star.mass_solar = 1.0
	star.age_billion_years = 6.0
	star.stellar_activity = 1.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	var planet := Planet.new()
	planet.planet_type = "OCEAN_WORLD"
	planet.is_habitable = true
	planet.habitability_score = 0.9
	planet.water_fraction = 0.7
	planet.base_color = Color.BLUE
	LifeModel.evaluate_planet(planet, star, rng)
	if planet.life_level == "NONE":
		push_error("A confirmed habitable mature planet must receive a life level")
		quit(1)
		return
	if planet.has_city_lights and planet.civilization_level != "TECHNOLOGICAL":
		push_error("City lights must only represent technological civilizations")
		quit(1)
		return
	var host := Planet.new()
	host.planet_type = "GAS_GIANT"
	host.orbit_radius = HabitabilityModel.ONE_AU
	host.real_radius = 60000000.0
	host.radiation_level = 0.4
	var moon := Moon.new()
	moon.real_radius = 3000000.0
	moon.orbit_radius = 600000000.0
	PlanetaryDynamicsModel.evaluate_moon(moon, host, star, rng)
	LifeModel.evaluate_moon(moon, host, star, rng)
	if moon.habitability_score <= 0.0 or moon.surface_temperature_k <= 0.0:
		push_error("Moon habitability evaluation must produce physical values")
		quit(1)
		return
	var ringed := false
	for i in range(20):
		RingSystemModel.apply(host, rng)
		if host.has_rings:
			ringed = true
			break
	if not ringed or host.ring_outer_ratio <= host.ring_inner_ratio:
		push_error("Gas giants must be able to generate valid ring systems")
		quit(1)
		return
	print("LIFE_MOON_RING_REGRESSION_OK life=%s" % planet.life_level)
	quit(0)
