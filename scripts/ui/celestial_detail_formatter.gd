class_name CelestialDetailFormatter
extends RefCounted

const ONE_AU := 149597870700.0


static func for_star(star_data, info: Dictionary, summary: Dictionary) -> Array[Dictionary]:
	var habitable_text := "Yok"
	if summary.habitable > 0:
		habitable_text = "%d doğrulandı • %d kuşakta" % [summary.habitable, summary.in_zone]
	elif summary.in_zone > 0:
		habitable_text = "0 doğrulandı • %d kuşakta" % summary.in_zone
	return [
		_row("SINIF", star_data.spectral_type),
		_row("KÜTLE", "%.2f M☉" % star_data.mass_solar),
		_row("YAŞ", "%.2f milyar yıl" % star_data.age_billion_years),
		_row("SICAKLIK", "%.0f K" % star_data.temperature_kelvin),
		_row("PARLAKLIK", "%.2f L☉" % star_data.luminosity),
		_row("METALİKLİK", "%+.2f [Fe/H]" % star_data.metallicity),
		_row("GEZEGENLER", "%d gezegen" % summary.planets),
		_row("UYDULAR", "%d uydu" % summary.moons),
		_row("EŞ YILDIZ", "%d" % summary.get("companions", 0)),
		_row("ASTEROİT KUŞAĞI", "%d" % summary.get("belts", 0)),
		_row("YAŞANABİLİR", habitable_text),
		_row("YARIÇAP", info.radius),
		_row("MESAFE", info.dist),
		_row("IŞIK SÜRESİ", info.light_time),
		_row("UÇUŞ SÜRESİ", info.travel_time),
	]


static func for_body(body: CelestialBody, info: Dictionary) -> Array[Dictionary]:
	if body.type == "PLANET":
		var zone: String = str({"HOT": "Sıcak", "HABITABLE": "Yaşanabilir", "COLD": "Soğuk"}.get(body.climate_zone, "Bilinmiyor"))
		return [
			_row("TİP", info.type),
			_row("YÖRÜNGE", "%.2f AU • %s kuşak" % [body.orbit_radius / ONE_AU, zone]),
			_row("YAŞANABİLİRLİK", "Uygun • %%%d" % int(body.habitability_score * 100.0) if body.is_habitable else "Uygun değil • %%%d" % int(body.habitability_score * 100.0)),
			_row("SICAKLIK", info.temp),
			_row("YERÇEKİMİ", info.gravity),
			_row("ATMOSFER", info.atmo),
			_row("ATM. SINIFI", body.atmosphere_description),
			_row("BİLEŞİM", AtmosphereModel.summary(body.atmosphere_composition)),
			_row("SU", info.water),
			_row("UYDULAR", "%d" % body.moon_count),
			_row("GÜN / YIL", "%.1f sa • %.1f gün" % [body.rotation_period_hours, body.orbital_period_days]),
			_row("GELGİT KİLİDİ", "Var" if body.is_tidally_locked else "Yok"),
			_row("MANYETİK ALAN", "%.2f Dünya" % body.magnetic_field_earth),
			_row("RADYASYON", "%.2f R☉" % body.radiation_level),
			_row("YAŞAM", body.life_description),
			_row("UYGARLIK", "Teknolojik iz" if body.civilization_level == "TECHNOLOGICAL" else "Tespit edilmedi"),
			_row("HALKALAR", "Var • %.1f–%.1f R" % [body.ring_inner_ratio, body.ring_outer_ratio] if body.has_rings else "Yok"),
			_row("YARIÇAP", info.radius),
			_row("MESAFE", info.dist),
		]
	if body.type == "MOON":
		var parent_name := body.parent_body.name if body.parent_body != null else "Bilinmiyor"
		return [
			_row("TİP", "Doğal uydu"),
			_row("ANA GEZEGEN", parent_name),
			_row("YÖRÜNGE", _format_km(body.orbit_radius)),
			_row("YÖRÜNGE SÜRESİ", "%.1f gün" % body.orbital_period_days),
			_row("GELGİT KİLİDİ", "Var" if body.is_tidally_locked else "Yok"),
			_row("RADYASYON", "%.2f R☉" % body.radiation_level),
			_row("OKYANUS", "Yeraltı okyanusu" if body.has_subsurface_ocean else "Tespit edilmedi"),
			_row("YAŞAM", body.life_description),
			_row("ATMOSFER", info.atmo),
			_row("YERÇEKİMİ", info.gravity),
			_row("SU", info.water),
			_row("YARIÇAP", info.radius),
			_row("MESAFE", info.dist),
		]
	return []


static func _row(label: String, value) -> Dictionary:
	return {"label": label, "value": str(value)}


static func _format_km(meters: float) -> String:
	return "%.0f km" % (meters / 1000.0)
