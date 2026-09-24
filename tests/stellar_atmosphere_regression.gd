extends SceneTree


func _initialize() -> void:
	var manager := SectorManager.new(99173)
	var stars := manager.generate_sector(Vector3i.ZERO)
	for star_data in stars:
		if star_data.mass_solar <= 0.0 or star_data.temperature_kelvin <= 0.0 or star_data.age_billion_years <= 0.0:
			push_error("Every star must have physical evolution properties")
			quit(1)
			return
	var star := SystemGenerator.instantiate_star_from_data(null, stars[0])
	var bodies := SystemGenerator.generate_planets_for_star(null, star, false)
	for body in bodies:
		if body.type != "PLANET":
			continue
		if body.has_atmosphere and body.atmosphere_composition.is_empty():
			push_error("Atmospheric planets must have a gas composition")
			quit(1)
			return
		if body.atmosphere_class not in ["VACUUM", "BREATHABLE", "TOXIC", "CORROSIVE"]:
			push_error("Atmosphere safety class is invalid")
			quit(1)
			return
	print("STELLAR_ATMOSPHERE_REGRESSION_OK stars=%d bodies=%d" % [stars.size(), bodies.size()])
	quit(0)
