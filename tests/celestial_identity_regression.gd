extends SceneTree

func _init() -> void:
	var galaxy_a := Galaxy.generate(424242)
	var galaxy_b := Galaxy.generate(424242)
	_assert(galaxy_a.unique_id == galaxy_b.unique_id, "Aynı galaksi tohumu farklı kimlik üretti")

	var data := StarData.new()
	data.galaxy_id = galaxy_a.unique_id
	data.parent_id = galaxy_a.unique_id
	data.sector_coord = Vector3i(-4, 2, 19)
	data.unique_id = CelestialAddress.star_id(data.galaxy_id, data.sector_coord, 7)
	data.system_seed = 99117
	data.name = "Kimlik Test Yıldızı"
	data.radius = 696340000.0
	data.spectral_type = "Sarı Cüce"
	data.luminosity = 1.0
	data.system_type = "STANDARD"
	data.base_color = Color.WHITE
	data.light_color = Color.WHITE
	data.set_galactic_position(GalacticPosition.from_light_years(Vector3(-201.25, 131.5, 1249.75)))

	var restored := data.get_galactic_position().to_light_years()
	_assert(restored.distance_to(Vector3(-201.25, 131.5, 1249.75)) < 0.001, "Galaktik konum dönüşümü bozuk")

	var first := SystemGenerator.generate_planets_for_star(null, SystemGenerator.instantiate_star_from_data(null, data), false)
	var second := SystemGenerator.generate_planets_for_star(null, SystemGenerator.instantiate_star_from_data(null, data), false)
	_assert(first.size() == second.size(), "Aynı yıldız tohumu farklı gökcismi sayısı üretti")
	var seen := {}
	for i in range(first.size()):
		var a: CelestialBody = first[i]
		var b: CelestialBody = second[i]
		_assert(not a.unique_id.is_empty(), "Boş gökcismi kimliği")
		_assert(a.unique_id == b.unique_id, "Aynı hiyerarşi farklı kimlik üretti")
		_assert(not seen.has(a.unique_id), "Tekrarlanan gökcismi kimliği: " + a.unique_id)
		seen[a.unique_id] = true
		if a.type == "PLANET":
			_assert(a.parent_id == data.unique_id, "Gezegen ebeveyni yıldız değil")
		elif a.type == "MOON":
			_assert(a.parent_id.begins_with(data.unique_id + "_P"), "Uydu ebeveyni gezegen değil")
	print("CELESTIAL_IDENTITY_REGRESSION_OK bodies=%d" % first.size())
	quit(0)

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	quit(1)

