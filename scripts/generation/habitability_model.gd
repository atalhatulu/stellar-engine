class_name HabitabilityModel
extends RefCounted

const ONE_AU := 149597870700.0
const EARTH_RADIUS := 6371000.0


static func get_orbital_zones(luminosity: float) -> Dictionary:
	var scale := sqrt(maxf(luminosity, 0.01))
	return {
		"hot_outer_m": 0.95 * scale * ONE_AU,
		"habitable_inner_m": 0.95 * scale * ONE_AU,
		"habitable_outer_m": 1.67 * scale * ONE_AU,
		"cold_inner_m": 1.67 * scale * ONE_AU,
	}


static func evaluate_planet(planet: CelestialBody, star: CelestialBody, rng: RandomNumberGenerator) -> void:
	var zones := get_orbital_zones(star.luminosity)
	planet.habitable_zone_inner = zones.habitable_inner_m
	planet.habitable_zone_outer = zones.habitable_outer_m
	if planet.orbit_radius < zones.habitable_inner_m:
		planet.climate_zone = "HOT"
	elif planet.orbit_radius <= zones.habitable_outer_m:
		planet.climate_zone = "HABITABLE"
	else:
		planet.climate_zone = "COLD"

	var radius_earth := planet.real_radius / EARTH_RADIUS
	var density_factor := _density_factor(planet.planet_type)
	planet.mass_earth = maxf(0.01, pow(radius_earth, 3.0) * density_factor)
	planet.surface_gravity_g = planet.mass_earth / maxf(radius_earth * radius_earth, 0.01)
	planet.atmosphere_pressure_bar = _atmosphere_pressure(planet, rng)
	planet.water_fraction = _water_fraction(planet, rng)
	var distance_au := planet.orbit_radius / ONE_AU
	var equilibrium_kelvin := 278.0 * pow(maxf(star.luminosity, 0.01), 0.25) / sqrt(maxf(distance_au, 0.02))
	var greenhouse := clampf(planet.atmosphere_pressure_bar * rng.randf_range(7.0, 18.0), 0.0, 90.0)
	planet.surface_temperature_k = equilibrium_kelvin + greenhouse
	var stable_star := star.spectral_type not in ["Mavi Dev", "Kırmızı Dev"]
	var rocky := planet.planet_type not in ["GAS_GIANT", "ICE_WORLD"]
	planet.is_habitable = (
		planet.climate_zone == "HABITABLE"
		and rocky
		and stable_star
		and planet.has_atmosphere
		and planet.atmosphere_pressure_bar >= 0.35
		and planet.atmosphere_pressure_bar <= 3.5
		and planet.surface_gravity_g >= 0.45
		and planet.surface_gravity_g <= 1.8
		and planet.surface_temperature_k >= 250.0
		and planet.surface_temperature_k <= 320.0
		and planet.water_fraction >= 0.05
		and planet.water_fraction <= 0.95
	)
	planet.habitability_score = _score(planet, stable_star, rocky)


static func _density_factor(planet_type: String) -> float:
	match planet_type:
		"TERRESTRIAL_METALLIC": return 1.18
		"HOT_DESERT", "RED_PLANET": return 0.92
		"OCEAN_WORLD": return 0.72
		"EXOTIC_LIFE": return 0.85
		"ICE_WORLD": return 0.45
		"GAS_GIANT": return 0.08
		_: return 0.8


static func _atmosphere_pressure(planet: CelestialBody, rng: RandomNumberGenerator) -> float:
	if not planet.has_atmosphere:
		return 0.0
	var gravity_retention := clampf(planet.surface_gravity_g, 0.1, 3.0)
	match planet.planet_type:
		"GAS_GIANT": return rng.randf_range(20.0, 180.0)
		"OCEAN_WORLD": return rng.randf_range(0.7, 2.8) * gravity_retention
		"EXOTIC_LIFE": return rng.randf_range(0.5, 3.2) * gravity_retention
		"RED_PLANET": return rng.randf_range(0.03, 0.8) * gravity_retention
		_: return rng.randf_range(0.15, 4.5) * gravity_retention


static func _water_fraction(planet: CelestialBody, rng: RandomNumberGenerator) -> float:
	match planet.planet_type:
		"OCEAN_WORLD": return rng.randf_range(0.55, 0.96)
		"EXOTIC_LIFE": return rng.randf_range(0.15, 0.75)
		"RED_PLANET": return rng.randf_range(0.0, 0.18)
		"ICE_WORLD": return rng.randf_range(0.25, 0.8)
		"HOT_DESERT": return rng.randf_range(0.0, 0.06)
		_: return rng.randf_range(0.0, 0.35)


static func _score(planet: CelestialBody, stable_star: bool, rocky: bool) -> float:
	var zone_score := 1.0 if planet.climate_zone == "HABITABLE" else 0.15
	var temp_score := clampf(1.0 - absf(planet.surface_temperature_k - 288.0) / 110.0, 0.0, 1.0)
	var gravity_score := clampf(1.0 - absf(planet.surface_gravity_g - 1.0) / 1.2, 0.0, 1.0)
	var water_score := clampf(planet.water_fraction * 3.0, 0.0, 1.0)
	var atmosphere_score := 1.0 if planet.atmosphere_pressure_bar >= 0.35 and planet.atmosphere_pressure_bar <= 3.5 else 0.2
	return clampf((zone_score + temp_score + gravity_score + water_score + atmosphere_score + float(stable_star) + float(rocky)) / 7.0, 0.0, 1.0)
