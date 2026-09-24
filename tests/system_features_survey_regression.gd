extends SceneTree


func _initialize() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1447
	var star := Star.new()
	star.unique_id = "TEST_BINARY"
	star.name = "Test"
	star.system_type = "BINARY_CANDIDATE"
	star.real_radius = 600000000.0
	star.luminosity = 1.0
	SystemFeatureGenerator.generate_asteroid_belts(star, 2.4 * SystemFeatureGenerator.ONE_AU, rng)
	var companion := SystemFeatureGenerator.create_companion(star, rng)
	if companion == null or companion.parent_body != star:
		push_error("Binary systems must create an orbiting companion")
		quit(1)
		return
	var survey := SurveyController.new()
	survey.catalog = DiscoveryCatalog.new("/tmp/stellar_engine_survey_regression.json")
	var planet := Planet.new()
	planet.unique_id = "TEST_SURVEY_PLANET"
	planet.name = "Survey"
	planet.parent_id = star.unique_id
	survey.update_target(planet, 10.0)
	if survey.get_progress(planet) < 100.0 or not survey.catalog.is_discovered(planet.unique_id):
		push_error("Completed scans must persist in the discovery catalog")
		quit(1)
		return
	print("SYSTEM_FEATURES_SURVEY_REGRESSION_OK companion=%s" % companion.name)
	quit(0)
