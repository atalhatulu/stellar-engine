class_name StellarEvolutionModel
extends RefCounted


static func apply(star, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value ^ 0x5354454C
	match star.spectral_type:
		"Kırmızı Cüce":
			star.mass_solar = rng.randf_range(0.10, 0.55)
			star.temperature_kelvin = rng.randf_range(2400.0, 3900.0)
			star.age_billion_years = rng.randf_range(0.3, 12.5)
		"Turuncu Cüce":
			star.mass_solar = rng.randf_range(0.55, 0.85)
			star.temperature_kelvin = rng.randf_range(3900.0, 5200.0)
			star.age_billion_years = rng.randf_range(0.2, 11.0)
		"Sarı Cüce":
			star.mass_solar = rng.randf_range(0.85, 1.15)
			star.temperature_kelvin = rng.randf_range(5200.0, 6100.0)
			star.age_billion_years = rng.randf_range(0.1, 9.5)
		"Beyaz Yıldız":
			star.mass_solar = rng.randf_range(1.15, 2.2)
			star.temperature_kelvin = rng.randf_range(6100.0, 10000.0)
			star.age_billion_years = rng.randf_range(0.03, 3.5)
		"Mavi Dev":
			star.mass_solar = rng.randf_range(8.0, 35.0)
			star.temperature_kelvin = rng.randf_range(10000.0, 35000.0)
			star.age_billion_years = rng.randf_range(0.001, 0.05)
		"Kırmızı Dev":
			star.mass_solar = rng.randf_range(0.9, 8.0)
			star.temperature_kelvin = rng.randf_range(3000.0, 5000.0)
			star.age_billion_years = rng.randf_range(0.4, 11.5)
		_:
			star.mass_solar = 1.0
			star.temperature_kelvin = 5778.0
			star.age_billion_years = 4.6
	star.metallicity = clampf(rng.randfn(-0.05, 0.28), -1.5, 0.6)
	var age_damping := clampf(1.4 - star.age_billion_years / 10.0, 0.25, 1.4)
	var spectral_activity := 1.8 if star.spectral_type == "Kırmızı Cüce" else (2.5 if star.spectral_type == "Mavi Dev" else 1.0)
	star.stellar_activity = spectral_activity * age_damping * rng.randf_range(0.7, 1.35)
