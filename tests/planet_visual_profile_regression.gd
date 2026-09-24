extends SceneTree


func _initialize() -> void:
	var body := Planet.new()
	body.planet_type = "OCEAN_WORLD"
	body.climate_zone = "HABITABLE"
	body.water_fraction = 0.72
	body.life_level = "COMPLEX"
	body.base_color = Color(0.4, 0.5, 0.4)
	body.has_atmosphere = true
	body.atmosphere_pressure_bar = 1.0
	body.atmosphere_class = "BREATHABLE"
	body.atmosphere_composition = {"N₂": 78.0, "O₂": 21.0, "CO₂": 1.0}
	var initial := body.base_color
	PlanetVisualProfile.apply(body)
	if body.base_color == initial or body.atmosphere_color.a <= 0.0:
		push_error("Physical planet data must affect its visual profile")
		quit(1)
		return
	var host := Node3D.new()
	root.add_child(host)
	SystemGenerator.spawn_body_graphics(host, body)
	if body.visual_mesh == null or body.atmosphere_mesh == null:
		push_error("Atmospheric planets must create a lightweight visual shell")
		quit(1)
		return
	print("PLANET_VISUAL_PROFILE_REGRESSION_OK")
	quit(0)
