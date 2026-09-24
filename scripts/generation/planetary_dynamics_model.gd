class_name PlanetaryDynamicsModel
extends RefCounted

const ONE_AU := 149597870700.0


static func evaluate_planet(planet: CelestialBody, star: CelestialBody, rng: RandomNumberGenerator) -> void:
	var distance_au := maxf(planet.orbit_radius / ONE_AU, 0.01)
	planet.orbital_period_days = 365.25 * sqrt(pow(distance_au, 3.0) / maxf(star.mass_solar, 0.05))
	planet.rotation_period_hours = rng.randf_range(8.0, 80.0)
	var lock_limit_au := 0.12 * sqrt(maxf(star.luminosity, 0.02))
	planet.is_tidally_locked = distance_au <= lock_limit_au or (distance_au <= lock_limit_au * 1.7 and rng.randf() < 0.35)
	if planet.is_tidally_locked:
		planet.rotation_period_hours = planet.orbital_period_days * 24.0
	var rotation_factor := clampf(24.0 / maxf(planet.rotation_period_hours, 4.0), 0.08, 2.0)
	var core_factor := 0.15 if planet.planet_type in ["ICE_WORLD", "GAS_GIANT"] else 1.0
	planet.magnetic_field_earth = clampf(sqrt(maxf(planet.mass_earth, 0.01)) * rotation_factor * core_factor * rng.randf_range(0.5, 1.5), 0.0, 8.0)
	var raw_radiation := star.stellar_activity * star.luminosity / maxf(distance_au * distance_au, 0.01)
	planet.radiation_level = raw_radiation / (1.0 + planet.magnetic_field_earth * 2.5)
	if planet.radiation_level > 2.5:
		planet.is_habitable = false
		planet.habitability_score *= 0.55
	elif planet.radiation_level > 1.0:
		planet.habitability_score *= 0.82


static func evaluate_moon(moon: CelestialBody, host: CelestialBody, star: CelestialBody, rng: RandomNumberGenerator) -> void:
	moon.is_tidally_locked = true
	moon.orbital_period_days = clampf(4.0 + (moon.orbit_radius / maxf(host.real_radius, 1.0)) * 0.8, 1.0, 120.0)
	moon.rotation_period_hours = moon.orbital_period_days * 24.0
	moon.magnetic_field_earth = rng.randf_range(0.0, 0.18)
	moon.radiation_level = host.radiation_level * rng.randf_range(0.7, 1.3)

