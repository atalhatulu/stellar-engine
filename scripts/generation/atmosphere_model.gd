class_name AtmosphereModel
extends RefCounted


static func apply(planet: CelestialBody, rng: RandomNumberGenerator) -> void:
	planet.atmosphere_composition.clear()
	if not planet.has_atmosphere or planet.atmosphere_pressure_bar <= 0.001:
		planet.atmosphere_class = "VACUUM"
		planet.atmosphere_description = "Vakum"
		planet.is_habitable = false
		return

	match planet.planet_type:
		"OCEAN_WORLD":
			var oxygen := rng.randf_range(16.0, 27.0)
			var carbon := rng.randf_range(0.02, 1.2)
			planet.atmosphere_composition = {"N₂": 100.0 - oxygen - carbon, "O₂": oxygen, "CO₂": carbon}
		"EXOTIC_LIFE":
			var oxygen := rng.randf_range(8.0, 24.0)
			var methane := rng.randf_range(0.2, 8.0)
			planet.atmosphere_composition = {"N₂": 100.0 - oxygen - methane, "O₂": oxygen, "CH₄": methane}
		"RED_PLANET":
			planet.atmosphere_composition = {"CO₂": rng.randf_range(82.0, 97.0), "N₂": rng.randf_range(2.0, 12.0), "Ar": rng.randf_range(1.0, 4.0)}
		"HOT_DESERT":
			planet.atmosphere_composition = {"CO₂": rng.randf_range(55.0, 92.0), "N₂": rng.randf_range(5.0, 30.0), "SO₂": rng.randf_range(1.0, 12.0)}
		"ICE_WORLD":
			planet.atmosphere_composition = {"N₂": rng.randf_range(55.0, 88.0), "CH₄": rng.randf_range(5.0, 25.0), "NH₃": rng.randf_range(1.0, 8.0)}
		"GAS_GIANT":
			planet.atmosphere_composition = {"H₂": rng.randf_range(72.0, 90.0), "He": rng.randf_range(8.0, 24.0), "CH₄": rng.randf_range(0.2, 5.0)}
		_:
			planet.atmosphere_composition = {"CO₂": rng.randf_range(25.0, 80.0), "N₂": rng.randf_range(15.0, 65.0)}

	_normalize(planet.atmosphere_composition)
	var oxygen: float = float(planet.atmosphere_composition.get("O₂", 0.0))
	var carbon: float = float(planet.atmosphere_composition.get("CO₂", 0.0))
	var sulfur: float = float(planet.atmosphere_composition.get("SO₂", 0.0))
	var ammonia: float = float(planet.atmosphere_composition.get("NH₃", 0.0))
	if sulfur >= 3.0 or ammonia >= 3.0:
		planet.atmosphere_class = "CORROSIVE"
		planet.atmosphere_description = "Aşındırıcı"
	elif oxygen >= 15.0 and oxygen <= 30.0 and carbon < 2.0 and planet.atmosphere_pressure_bar <= 2.5:
		planet.atmosphere_class = "BREATHABLE"
		planet.atmosphere_description = "Solunabilir"
	else:
		planet.atmosphere_class = "TOXIC"
		planet.atmosphere_description = "Zehirli / solunamaz"
	planet.is_habitable = planet.is_habitable and planet.atmosphere_class == "BREATHABLE"
	if planet.atmosphere_class != "BREATHABLE":
		planet.habitability_score *= 0.72


static func summary(composition: Dictionary, max_components: int = 3) -> String:
	var parts: Array[String] = []
	var gases := composition.keys()
	gases.sort_custom(func(a, b): return float(composition[a]) > float(composition[b]))
	for gas in gases.slice(0, max_components):
		parts.append("%s %.0f%%" % [gas, composition[gas]])
	return " • ".join(parts)


static func _normalize(composition: Dictionary) -> void:
	var total := 0.0
	for value in composition.values():
		total += float(value)
	if total <= 0.0:
		return
	for gas in composition:
		composition[gas] = float(composition[gas]) * 100.0 / total
