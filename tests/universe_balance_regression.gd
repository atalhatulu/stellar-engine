extends SceneTree


const SAMPLE_STARS := 400


func _initialize() -> void:
	var started := Time.get_ticks_msec()
	var manager := SectorManager.new(808080)
	var star_count := 0
	var planet_count := 0
	var habitable_count := 0
	var life_count := 0
	var ring_count := 0
	var binary_count := 0
	var belt_count := 0
	var breathable_count := 0
	var coord_index := 0
	while star_count < SAMPLE_STARS:
		var stars := manager.generate_sector(Vector3i(coord_index, 0, 0))
		coord_index += 1
		for data in stars:
			if star_count >= SAMPLE_STARS:
				break
			star_count += 1
			var star := SystemGenerator.instantiate_star_from_data(null, data)
			var bodies := SystemGenerator.generate_planets_for_star(null, star, false)
			binary_count += 1 if bodies.any(func(body): return body.type == "STAR") else 0
			belt_count += star.asteroid_belts.size()
			for body in bodies:
				if body.type != "PLANET":
					continue
				planet_count += 1
				habitable_count += int(body.is_habitable)
				life_count += int(body.life_level != "NONE")
				ring_count += int(body.has_rings)
				breathable_count += int(body.atmosphere_class == "BREATHABLE")
	var habitable_ratio := float(habitable_count) / maxf(planet_count, 1)
	var ring_ratio := float(ring_count) / maxf(planet_count, 1)
	var binary_ratio := float(binary_count) / star_count
	if planet_count < 600 or habitable_ratio < 0.002 or habitable_ratio > 0.12 or life_count == 0 or ring_ratio < 0.03 or ring_ratio > 0.28:
		push_error("Universe feature distribution is outside playable bounds")
		quit(1)
		return
	if binary_ratio < 0.015 or binary_ratio > 0.09:
		push_error("Binary-star frequency is outside intended rare bounds")
		quit(1)
		return
	var elapsed := Time.get_ticks_msec() - started
	print("UNIVERSE_BALANCE_REGRESSION_OK stars=%d planets=%d habitable=%.2f%% life=%d rings=%.2f%% binary=%.2f%% belts=%d breathable=%d ms=%d" % [star_count, planet_count, habitable_ratio * 100.0, life_count, ring_ratio * 100.0, binary_ratio * 100.0, belt_count, breathable_count, elapsed])
	quit(0)
