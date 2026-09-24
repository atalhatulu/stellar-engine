class_name LifeModel
extends RefCounted


static func evaluate_planet(planet: CelestialBody, star: CelestialBody, rng: RandomNumberGenerator) -> void:
	planet.life_level = "NONE"
	planet.life_description = "Yaşam izi yok"
	if not planet.is_habitable:
		return
	var maturity := clampf(star.age_billion_years / 4.5, 0.0, 1.4)
	var roll := rng.randf() * maturity * planet.habitability_score
	if roll > 0.72:
		planet.life_level = "COMPLEX"
		planet.life_description = "Karmaşık biyosfer"
		var civilization_roll := rng.randf() * maturity
		if civilization_roll > 0.92:
			planet.civilization_level = "TECHNOLOGICAL"
			planet.has_city_lights = true
			planet.life_description = "Teknolojik biyosfer"
	elif roll > 0.38:
		planet.life_level = "PLANT"
		planet.life_description = "Fotosentetik yaşam"
	else:
		planet.life_level = "MICROBIAL"
		planet.life_description = "Mikrobik yaşam"


static func evaluate_moon(moon: CelestialBody, host: CelestialBody, star: CelestialBody, rng: RandomNumberGenerator) -> void:
	var star_distance := host.orbit_radius
	var zones := HabitabilityModel.get_orbital_zones(star.luminosity)
	moon.climate_zone = "HABITABLE" if star_distance >= zones.habitable_inner_m and star_distance <= zones.habitable_outer_m else ("HOT" if star_distance < zones.habitable_inner_m else "COLD")
	var radius_earth := moon.real_radius / HabitabilityModel.EARTH_RADIUS
	moon.mass_earth = maxf(0.001, pow(radius_earth, 3.0) * 0.75)
	moon.surface_gravity_g = moon.mass_earth / maxf(radius_earth * radius_earth, 0.001)
	moon.surface_temperature_k = 278.0 * pow(maxf(star.luminosity, 0.01), 0.25) / sqrt(maxf(star_distance / HabitabilityModel.ONE_AU, 0.02))
	moon.water_fraction = rng.randf_range(0.15, 0.85) if host.planet_type in ["GAS_GIANT", "ICE_WORLD"] else rng.randf_range(0.0, 0.25)
	moon.has_subsurface_ocean = moon.climate_zone == "COLD" and moon.water_fraction > 0.35 and rng.randf() < 0.45
	var surface_candidate := moon.climate_zone == "HABITABLE" and radius_earth >= 0.22 and rng.randf() < 0.22
	if surface_candidate:
		moon.has_atmosphere = true
		moon.planet_type = "OCEAN_WORLD"
		moon.atmosphere_pressure_bar = rng.randf_range(0.35, 1.8)
		AtmosphereModel.apply(moon, rng)
	moon.is_habitable = surface_candidate and moon.atmosphere_class == "BREATHABLE" and moon.radiation_level <= 2.5
	moon.habitability_score = 0.65 if moon.is_habitable else (0.38 if moon.has_subsurface_ocean else 0.05)
	moon.life_level = "MICROBIAL" if moon.is_habitable or moon.has_subsurface_ocean and rng.randf() < 0.35 else "NONE"
	moon.life_description = "Mikrobik yaşam" if moon.life_level == "MICROBIAL" else "Yaşam izi yok"
