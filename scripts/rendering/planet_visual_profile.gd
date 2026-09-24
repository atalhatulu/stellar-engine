class_name PlanetVisualProfile
extends RefCounted


static func apply(body: CelestialBody) -> void:
	if body.type == "PLANET":
		var mineral := body.base_color
		match body.climate_zone:
			"HOT": mineral = mineral.lerp(Color(0.48, 0.16, 0.06), 0.34)
			"COLD": mineral = mineral.lerp(Color(0.72, 0.86, 1.0), 0.46)
			"HABITABLE": mineral = mineral.lerp(Color(0.18, 0.42, 0.24), body.water_fraction * 0.18)
		if body.water_fraction > 0.35:
			mineral = mineral.lerp(Color(0.04, 0.22, 0.58), clampf(body.water_fraction * 0.58, 0.0, 0.55))
		match body.life_level:
			"PLANT": mineral = mineral.lerp(Color(0.12, 0.5, 0.16), 0.28)
			"COMPLEX": mineral = mineral.lerp(Color(0.1, 0.58, 0.25), 0.34)
		body.base_color = mineral
		body.roughness = clampf(0.92 - body.water_fraction * 0.55, 0.24, 0.94)
	elif body.type == "MOON" and body.has_subsurface_ocean:
		body.base_color = body.base_color.lerp(Color(0.62, 0.82, 1.0), 0.42)

	if body.has_atmosphere:
		body.atmosphere_color = atmosphere_color(body)


static func atmosphere_color(body: CelestialBody) -> Color:
	var composition := body.atmosphere_composition
	var color := Color(0.34, 0.62, 1.0)
	if float(composition.get("CH₄", 0.0)) > 5.0:
		color = Color(0.22, 0.62, 0.82)
	if float(composition.get("CO₂", 0.0)) > 40.0:
		color = Color(0.82, 0.48, 0.18)
	if body.atmosphere_class == "CORROSIVE":
		color = Color(0.64, 0.82, 0.16)
	color.a = clampf(0.10 + log(1.0 + body.atmosphere_pressure_bar) * 0.11, 0.10, 0.48)
	return color
