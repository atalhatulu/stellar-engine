class_name SystemGenerator
extends RefCounted

const LIGHT_YEAR: float = 9460730472580800.0
const ATMOSPHERE_SHADER = preload("res://shaders/atmosphere.gdshader")

static var detail_noise_tex: NoiseTexture2D = null
static var detail_normal_tex: NoiseTexture2D = null
static var star_glow_texture: GradientTexture2D = null

static func get_star_glow_texture() -> GradientTexture2D:
	if star_glow_texture != null:
		return star_glow_texture

	var grad = Gradient.new()
	grad.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CUBIC
	grad.offsets = [0.0, 0.15, 0.38, 0.70, 1.0]
	grad.colors = [
		Color(1.0, 1.0, 1.0, 1.0),       # Odak çekirdek noktası (tam doymuş)
		Color(1.0, 1.0, 1.0, 0.95),      # Çekirdek gövdesi (%95 yoğunluk)
		Color(1.0, 1.0, 1.0, 0.60),      # Parlak hale
		Color(1.0, 1.0, 1.0, 0.18),      # Dış ışık tülü
		Color(1.0, 1.0, 1.0, 0.0)        # Yumuşak sınır
	]
	
	star_glow_texture = GradientTexture2D.new()
	star_glow_texture.gradient = grad
	star_glow_texture.fill = GradientTexture2D.FILL_RADIAL
	star_glow_texture.fill_from = Vector2(0.5, 0.5)
	star_glow_texture.fill_to = Vector2(1.0, 0.5)
	star_glow_texture.width = 128
	star_glow_texture.height = 128
	return star_glow_texture

# Aşama 7: Prosedürel Gezegen Sınıf Veri Modeli
const PLANET_CATALOG = {
	"HOT_DESERT": {
		"type_name": "Sıcak Çöl",
		"min_radius": 3000000.0,
		"max_radius": 7500000.0,
		"roughness": 0.9,
		"metallic": 0.1,
		"has_atmosphere": true,
		"atmos_alpha": 0.45
	},
	"TERRESTRIAL_METALLIC": {
		"type_name": "Karasal Metalik",
		"min_radius": 2500000.0,
		"max_radius": 6000000.0,
		"roughness": 0.8,
		"metallic": 0.35,
		"has_atmosphere": false,
		"atmos_alpha": 0.0
	},
	"OCEAN_WORLD": {
		"type_name": "Okyanus Dünyası",
		"min_radius": 5500000.0,
		"max_radius": 11000000.0,
		"roughness": 0.5,
		"metallic": 0.02,
		"has_atmosphere": true,
		"atmos_alpha": 0.65
	},
	"RED_PLANET": {
		"type_name": "Kızıl Gezegen",
		"min_radius": 3500000.0,
		"max_radius": 7500000.0,
		"roughness": 0.85,
		"metallic": 0.05,
		"has_atmosphere": true,
		"atmos_alpha": 0.4
	},
	"EXOTIC_LIFE": {
		"type_name": "Egzotik Yaşam",
		"min_radius": 6000000.0,
		"max_radius": 12000000.0,
		"roughness": 0.65,
		"metallic": 0.02,
		"has_atmosphere": true,
		"atmos_alpha": 0.7
	},
	"GAS_GIANT": {
		"type_name": "Gaz Devi",
		"min_radius": 35000000.0,
		"max_radius": 75000000.0,
		"roughness": 0.3,
		"metallic": 0.0,
		"has_atmosphere": true,
		"atmos_alpha": 0.8
	},
	"ICE_WORLD": {
		"type_name": "Buz Dünyası",
		"min_radius": 4000000.0,
		"max_radius": 14000000.0,
		"roughness": 0.6,
		"metallic": 0.05,
		"has_atmosphere": true,
		"atmos_alpha": 0.5
	}
}

static func pick_planet_type(rng: RandomNumberGenerator, orbit_dist: float, frost_line: float, habitable_inner: float = 0.0, habitable_outer: float = 0.0) -> String:
	if habitable_inner > 0.0 and orbit_dist >= habitable_inner and orbit_dist <= habitable_outer:
		var roll = rng.randf()
		if roll < 0.38:
			return "OCEAN_WORLD"
		elif roll < 0.74:
			return "RED_PLANET"
		else:
			return "EXOTIC_LIFE"
	elif orbit_dist < 0.75 * frost_line:
		# Kavurucu İç Kuşak
		return "HOT_DESERT" if rng.randf() < 0.52 else "TERRESTRIAL_METALLIC"
	elif orbit_dist < 1.85 * frost_line:
		# Ilıman / Yaşanabilir Kuşak
		var roll = rng.randf()
		if roll < 0.38:
			return "OCEAN_WORLD"
		elif roll < 0.74:
			return "RED_PLANET"
		else:
			return "EXOTIC_LIFE"
	else:
		# Donma Çizgisi Ötesi / Soğuk Dış Kuşak
		return "GAS_GIANT" if rng.randf() < 0.62 else "ICE_WORLD"

static func generate_planet_color(rng: RandomNumberGenerator, p_key: String) -> Color:
	match p_key:
		"HOT_DESERT":
			return Color(rng.randf_range(0.65, 0.88), rng.randf_range(0.35, 0.5), rng.randf_range(0.15, 0.25))
		"TERRESTRIAL_METALLIC":
			var g = rng.randf_range(0.25, 0.45)
			return Color(g * 1.1, g, g * 0.95)
		"OCEAN_WORLD":
			return Color(rng.randf_range(0.1, 0.2), rng.randf_range(0.4, 0.65), rng.randf_range(0.75, 0.95))
		"RED_PLANET":
			return Color(rng.randf_range(0.7, 0.9), rng.randf_range(0.28, 0.42), rng.randf_range(0.12, 0.22))
		"EXOTIC_LIFE":
			return Color(rng.randf_range(0.15, 0.3), rng.randf_range(0.6, 0.85), rng.randf_range(0.25, 0.45))
		"GAS_GIANT":
			var gas_roll = rng.randf()
			if gas_roll < 0.38:
				return Color(rng.randf_range(0.75, 0.9), rng.randf_range(0.5, 0.65), rng.randf_range(0.3, 0.4))
			elif gas_roll < 0.70:
				return Color(rng.randf_range(0.4, 0.6), rng.randf_range(0.3, 0.45), rng.randf_range(0.65, 0.85))
			else:
				return Color(rng.randf_range(0.15, 0.3), rng.randf_range(0.55, 0.8), rng.randf_range(0.8, 1.0))
		"ICE_WORLD":
			return Color(rng.randf_range(0.78, 0.92), rng.randf_range(0.86, 0.96), rng.randf_range(0.94, 1.0))
		_:
			return Color.GRAY

static func pick_moon_count(rng: RandomNumberGenerator, p_key: String, is_scorched: bool) -> int:
	if is_scorched:
		return 1 if rng.randf() < 0.15 else 0
	elif p_key == "GAS_GIANT":
		var roll = rng.randf()
		if roll < 0.10:
			return 1
		elif roll < 0.55:
			return 2
		elif roll < 0.85:
			return 3
		else:
			return 4
	else:
		var roll = rng.randf()
		if roll < 0.65:
			return 0
		elif roll < 0.90:
			return 1
		else:
			return 2


static func generate_systems(main_node: Node3D, p_seed: int, star_count: int) -> void:
	main_node.current_seed = p_seed
	seed(p_seed)
	
	# Eski gök cismi mesh'lerini ve starfield multimesh'i temizle
	var old_mm = main_node.get_node_or_null("StarfieldMultiMesh")
	if is_instance_valid(old_mm):
		old_mm.queue_free()
		
	for body in main_node.universe:
		if is_instance_valid(body.visual_mesh):
			body.visual_mesh.queue_free()
		if is_instance_valid(body.atmosphere_mesh):
			body.atmosphere_mesh.queue_free()
		if is_instance_valid(body.ring_mesh):
			body.ring_mesh.queue_free()
		if is_instance_valid(body.orbit_line_mesh):
			body.orbit_line_mesh.queue_free()
		if is_instance_valid(body.lod_sprite):
			body.lod_sprite.queue_free()
	main_node.universe.clear()
	main_node.total_planets_count = 0
	main_node.total_moons_count = 0
	
	# Durum değişkenlerini sıfırla
	main_node.current_target_index = -1
	main_node.is_autopilot_active = false
	main_node.autopilot_target_body = null
	main_node.followed_body = null
	
	# Kamera hızını ve açısını sıfırla/varsayılana çek
	if main_node.camera:
		main_node.camera.speed_multiplier_index = 3
		main_node.camera.target_speed = main_node.camera.speed_presets[3]
		main_node.camera.current_speed = main_node.camera.speed_presets[3]
		main_node.camera.rot_x = 0.0
		main_node.camera.rot_y = 0.0
		main_node.camera.rot_z = 0.0
		main_node.camera.transform.basis = Basis.IDENTITY
	
	# Oyuncu başlangıç konumu: tüm sistemleri uzaktan görebilecek mesafe
	main_node.virtual_player_position = Vector3(0, 2.0 * 9460730472580800.0, 6.0 * 9460730472580800.0)
	
	# star_count kadar isim üret
	var star_names: Array[String] = []
	for i in range(star_count):
		star_names.append("P_%d" % i)
	
	# Yıldız konumları listesi (İlk yıldız olan Güneş daima merkezde)
	var star_positions: Array[Vector3] = []
	star_positions.append(Vector3.ZERO)
	
	# Kalan yıldızlar için seed tabanlı 3D küresel konum üretimi
	var attempts = 0
	var min_star_dist = 2.5 * LIGHT_YEAR
	var min_star_dist_sq = min_star_dist * min_star_dist
	var max_cluster_radius = max(25.0, pow(float(star_count), 1.0 / 3.0) * 4.0) * LIGHT_YEAR
	var max_attempts = star_count * 50
	while star_positions.size() < star_count and attempts < max_attempts:
		attempts += 1
		var dir = Vector3(
			randf_range(-1.0, 1.0),
			randf_range(-1.0, 1.0),
			randf_range(-1.0, 1.0)
		).normalized()
		
		var dist = randf_range(3.5 * LIGHT_YEAR, max_cluster_radius)
		var candidate_pos = dir * dist
		
		var is_valid = true
		for existing_pos in star_positions:
			if candidate_pos.distance_squared_to(existing_pos) < min_star_dist_sq:
				is_valid = false
				break
				
		if is_valid:
			star_positions.append(candidate_pos)
			
	# Yıldızları sırayla üret (Gezegenler peşin üretilmez, sadece yıldız var edilir!)
	var sun: CelestialBody = null
	for i in range(star_positions.size()):
		var s_pos = star_positions[i]
		var s_seed = p_seed + i * 999
		var star = generate_star(main_node, i, s_pos, s_seed)
		if i == 0:
			sun = star
			
	if sun != null:
		main_node.active_star = sun
		main_node._check_active_star_transition()
			
	# Evreni oyuncuya göre başlangıçta konumlandır
	for body in main_node.universe:
		body.real_position = body.get_absolute_position(main_node.active_star) - main_node.virtual_player_position
		
	if sun != null:
		main_node._look_at_body(sun)

static func generate_star(main_node: Node3D, star_index: int, star_local_pos: Vector3, sys_seed: int) -> CelestialBody:
	seed(sys_seed)
	var base_name = "P_%d" % star_index
	var star = create_celestial_body(main_node, base_name, "STAR", randf_range(300000000.0, 500000000.0), star_local_pos)
	star.sys_seed = sys_seed
	star.star_index = star_index
	star.max_visibility_distance = INF
	star.system_diameter = 2000000000000.0 # ~13.3 AU tahmini sistem çapı
	return star

# Aşama 4 & 7: StarData kaydını aktif sistemin CelestialBody yıldızına dönüştürür
static func instantiate_star_from_data(_main_node: Node3D, star_data) -> CelestialBody:
	var star := Star.new()
	star.apply_star_data(star_data)
	return star

# Aşama 7: Prosedürel Gezegen Çeşitliliği ve Bağımsız Deterministik Sistem Üretimi
static func generate_planets_for_star(main_node: Node3D, star: CelestialBody, spawn_graphics: bool = true) -> Array[CelestialBody]:
	# Hiyerarşik Tohum Zinciri: Yıldız parametrelerinden bağımsız deterministik sistem tohumu
	var system_seed = (star.sys_seed * 1664525 + 1013904223) & 0x7FFFFFFF
	var rng = RandomNumberGenerator.new()
	rng.seed = system_seed
	
	var system_bodies: Array[CelestialBody] = []
	
	# 1. Gezegen Sayısı Dağılımı (Deterministik ve Yıldız Tipi Duyarlı)
	var num_planets: int = 0
	if star.system_type == "EMPTY":
		num_planets = 0
	elif star.spectral_type == "Mavi Dev" and rng.randf() < 0.45:
		num_planets = 0 # Mavi devlerde şiddetli radyasyon rüzgarları nedeniyle yüksek boş oran
	else:
		var count_roll = rng.randf()
		if count_roll < 0.12:
			num_planets = 0 # Gezegensiz yıldız (%12)
		elif count_roll < 0.47:
			num_planets = rng.randi_range(1, 3) # Küçük sistem (%35)
		elif count_roll < 0.87:
			num_planets = rng.randi_range(4, 7) # Normal sistem (%40)
		else:
			num_planets = rng.randi_range(8, 12) # Nadir büyük sistem (%13)
			
	if star.spectral_type == "Kırmızı Dev":
		num_planets = mini(num_planets, 4) # Kırmızı dev genişlerken iç gezegenleri yutmuştur

	const ONE_AU: float = 149597870700.0
	var lum = max(star.luminosity, 0.05)
	var frost_line_factor = sqrt(lum)
	var frost_line = 2.4 * ONE_AU * frost_line_factor
	var habitable_zones := HabitabilityModel.get_orbital_zones(lum)
	SystemFeatureGenerator.generate_asteroid_belts(star, frost_line, rng)
	if main_node != null and spawn_graphics and not star.asteroid_belts.is_empty():
		AsteroidBeltRenderer.create_for_star(main_node, star)
	var companion := SystemFeatureGenerator.create_companion(star, rng)
	if companion != null:
		system_bodies.append(companion)
		if main_node != null and spawn_graphics:
			spawn_body_graphics(main_node, companion)

	# Gezegensiz sistemlerde erken çıkış
	if num_planets == 0:
		star.system_diameter = maxf(star.real_radius * 20.0, companion.orbit_radius * 2.0 if companion != null else 0.0)
		return system_bodies
	
	# Başlangıç yörünge mesafesi (Yıldız tipine ve ışımasına göre)
	var current_orbit_distance: float
	if star.spectral_type == "Kırmızı Cüce":
		current_orbit_distance = rng.randf_range(0.12, 0.35) * ONE_AU * frost_line_factor
	elif star.spectral_type == "Mavi Dev" or star.spectral_type == "Kırmızı Dev":
		current_orbit_distance = rng.randf_range(2.0, 3.8) * ONE_AU * frost_line_factor
	else:
		current_orbit_distance = rng.randf_range(0.35, 0.75) * ONE_AU * frost_line_factor
		
	# Güvenlik marjı: Yörünge yıldız yarıçapından en az 3.2 kat uzakta olmalıdır
	current_orbit_distance = max(current_orbit_distance, star.real_radius * 3.2)
	var max_orbit_radius: float = current_orbit_distance
	
	var total_system_moons = 0
	const MAX_SYSTEM_MOONS = 18 # Aktif sistem performans koruma tavanı
	
	for i in range(num_planets):
		if i > 0:
			var spacing = rng.randf_range(0.2, 0.55) * ONE_AU * (1.0 + float(i) * 0.22) * frost_line_factor
			spacing = max(spacing, ONE_AU * 0.15)
			current_orbit_distance += spacing
		max_orbit_radius = max(max_orbit_radius, current_orbit_distance)
		
		# Gezegen Tipini Kuşağa Göre Seç
		var p_key = pick_planet_type(rng, current_orbit_distance, frost_line, habitable_zones.habitable_inner_m, habitable_zones.habitable_outer_m)
		var p_config = PLANET_CATALOG[p_key]
		var planet_radius = rng.randf_range(p_config["min_radius"], p_config["max_radius"])
		
		var angle = rng.randf_range(0.0, TAU)
		var p_inclination = rng.randf_range(deg_to_rad(-3.5), deg_to_rad(3.5))
		var planet_local_pos = Vector3(cos(angle), 0, sin(angle)) * current_orbit_distance
		if p_inclination != 0.0:
			planet_local_pos = planet_local_pos.rotated(Vector3.FORWARD, p_inclination)
			
		var planet := Planet.new()
		planet.galaxy_id = star.galaxy_id
		planet.system_id = star.unique_id
		planet.parent_id = star.unique_id
		planet.unique_id = CelestialAddress.planet_id(star.unique_id, i)
		planet.body_seed = CelestialAddress.seed_from_id(planet.unique_id)
		planet.name = "%s (%s)" % [CelestialNameGenerator.planet_name(star.name, i), p_config["type_name"]]
		planet.terrain_seed = system_seed + (i + 1) * 104729
		planet.planet_type = p_key
		planet.real_radius = planet_radius
		planet.real_position = planet_local_pos
		planet.local_position = planet_local_pos
		planet.parent_body = star
		planet.orbit_radius = current_orbit_distance
		planet.orbit_angle = angle
		planet.orbit_inclination = p_inclination
		planet.orbit_eccentricity = clampf(absf(rng.randfn(0.07, 0.06)), 0.005, 0.32)
		planet.argument_of_periapsis = rng.randf_range(0.0, TAU)
		planet.longitude_ascending_node = rng.randf_range(0.0, TAU)
		planet.local_position = planet.get_orbit_position()
		planet.real_position = planet.local_position
		planet.rotation_speed = rng.randf_range(0.05, 0.2)
		planet.rotation_angle = rng.randf_range(0.0, TAU)
		
		# Eksenel eğim
		var tilt_roll = rng.randf()
		if tilt_roll < 0.6:
			planet.axial_tilt = rng.randf_range(deg_to_rad(5.0), deg_to_rad(45.0))
		elif tilt_roll < 0.85:
			planet.axial_tilt = rng.randf_range(deg_to_rad(45.0), deg_to_rad(70.0))
		else:
			planet.axial_tilt = rng.randf_range(deg_to_rad(70.0), deg_to_rad(98.0))
			
		# Yörünge hızı (Kepler)
		planet.orbit_speed = 0.025 * pow(ONE_AU / max(current_orbit_distance, 1.0), 1.5)
		planet.orbit_speed = clamp(planet.orbit_speed, 0.002, 0.12)
		
		# Görsel parametreler
		planet.base_color = generate_planet_color(rng, p_key)
		planet.roughness = p_config["roughness"]
		planet.metallic = p_config["metallic"]
		planet.has_atmosphere = p_config["has_atmosphere"]
		if planet.has_atmosphere:
			var atmos_col = planet.base_color
			atmos_col.a = p_config["atmos_alpha"]
			planet.atmosphere_color = atmos_col
		else:
			planet.atmosphere_color = Color(0, 0, 0, 0)

		HabitabilityModel.evaluate_planet(planet, star, rng)
		AtmosphereModel.apply(planet, rng)
		PlanetaryDynamicsModel.evaluate_planet(planet, star, rng)
		LifeModel.evaluate_planet(planet, star, rng)
		RingSystemModel.apply(planet, rng)
		PlanetVisualProfile.apply(planet)
			
		# Uydu Sayısı (Moons)
		var num_moons = 0
		if total_system_moons < MAX_SYSTEM_MOONS:
			num_moons = pick_moon_count(rng, p_key, current_orbit_distance < 0.75 * frost_line)
			num_moons = mini(num_moons, MAX_SYSTEM_MOONS - total_system_moons)
		total_system_moons += num_moons
		planet.moon_count = num_moons
		
		planet.max_visibility_distance = max_orbit_radius * 2.0 * (planet.real_radius / 10000000.0) * (1.0 + num_moons * 0.5) * 1.5
		if main_node != null:
			main_node.total_planets_count += 1
			if spawn_graphics:
				spawn_body_graphics(main_node, planet)
		system_bodies.append(planet)
		
		# Uyduları Üret
		var current_moon_distance = planet_radius * 4.5
		for j in range(num_moons):
			var moon_spacing = rng.randf_range(planet_radius * 3.5, planet_radius * 7.0)
			current_moon_distance += moon_spacing
			var moon_radius = rng.randf_range(500000.0, planet_radius * (0.22 if p_key != "GAS_GIANT" else 0.08))
			moon_radius = max(moon_radius, 400000.0)
			
			var m_angle = rng.randf_range(0.0, TAU)
			var m_inclination = rng.randf_range(deg_to_rad(-6.0), deg_to_rad(6.0))
			var moon_local_pos = Vector3(cos(m_angle), 0, sin(m_angle)) * current_moon_distance
			if m_inclination != 0.0:
				moon_local_pos = moon_local_pos.rotated(Vector3.FORWARD, m_inclination)
				
			var moon := Moon.new()
			moon.galaxy_id = star.galaxy_id
			moon.system_id = star.unique_id
			moon.parent_id = planet.unique_id
			moon.unique_id = CelestialAddress.moon_id(planet.unique_id, j)
			moon.body_seed = CelestialAddress.seed_from_id(moon.unique_id)
			moon.name = CelestialNameGenerator.moon_name(planet.name.get_slice(" (", 0), j)
			moon.terrain_seed = system_seed + (i + 1) * 104729 + (j + 1) * 13007
			moon.real_radius = moon_radius
			moon.real_position = moon_local_pos
			moon.local_position = moon_local_pos
			moon.parent_body = planet
			moon.orbit_radius = current_moon_distance
			moon.orbit_angle = m_angle
			moon.orbit_inclination = m_inclination
			moon.orbit_eccentricity = clampf(absf(rng.randfn(0.035, 0.035)), 0.0, 0.18)
			moon.argument_of_periapsis = rng.randf_range(0.0, TAU)
			moon.longitude_ascending_node = rng.randf_range(0.0, TAU)
			moon.local_position = moon.get_orbit_position()
			moon.real_position = moon.local_position
			moon.rotation_speed = rng.randf_range(0.05, 0.2)
			moon.rotation_angle = rng.randf_range(0.0, TAU)
			moon.axial_tilt = rng.randf_range(0.0, deg_to_rad(30.0))
			
			var ref_moon_dist = planet_radius * 4.5
			moon.orbit_speed = 0.15 * pow(ref_moon_dist / max(current_moon_distance, 1.0), 1.5)
			moon.orbit_speed = clamp(moon.orbit_speed, 0.02, 0.35)
			moon.max_visibility_distance = max_orbit_radius * 2.0 * (moon.real_radius / 10000000.0) * 0.8
			
			var moon_gray = rng.randf_range(0.35, 0.65)
			moon.base_color = Color(moon_gray, moon_gray, moon_gray)
			moon.roughness = rng.randf_range(0.8, 0.95)
			moon.metallic = 0.0
			moon.has_atmosphere = false
			PlanetaryDynamicsModel.evaluate_moon(moon, planet, star, rng)
			LifeModel.evaluate_moon(moon, planet, star, rng)
			PlanetVisualProfile.apply(moon)
			
			if main_node != null:
				main_node.total_moons_count += 1
				if spawn_graphics:
					spawn_body_graphics(main_node, moon)
			system_bodies.append(moon)
			
	star.system_diameter = max_orbit_radius * 2.0
	return system_bodies

# Aşama 7: 100 Farklı Sistemde Çeşitlilik ve Dağılım Ölçümü Benchmark'ı
static func run_diversity_benchmark(count: int = 100, base_seed: int = 424242) -> Dictionary:
	var rng = RandomNumberGenerator.new()
	rng.seed = base_seed
	
	var system_sizes = {"EMPTY": 0, "SMALL (1-3)": 0, "NORMAL (4-7)": 0, "LARGE (8-12)": 0}
	var spectral_dist = {}
	var planet_types_dist = {}
	var total_planets = 0
	var total_moons = 0
	var zero_moon_planets = 0
	var gas_giant_moons = 0
	var gas_giant_count = 0
	
	for s_idx in range(count):
		var star_data = StarData.new()
		star_data.unique_id = "BENCH_STAR_%d" % s_idx
		star_data.name = "B_Star_%d" % s_idx
		star_data.system_seed = int(rng.randi()) & 0x7FFFFFFF
		
		# Spektral tip ağırlıklı seçimi
		var star_roll = rng.randf()
		if star_roll < 0.68:
			star_data.spectral_type = "Kırmızı Cüce"
			star_data.radius = rng.randf_range(160000000.0, 320000000.0)
			star_data.luminosity = rng.randf_range(0.15, 0.35)
		elif star_roll < 0.84:
			star_data.spectral_type = "Turuncu Cüce"
			star_data.radius = rng.randf_range(320000000.0, 460000000.0)
			star_data.luminosity = rng.randf_range(0.45, 0.75)
		elif star_roll < 0.93:
			star_data.spectral_type = "Sarı Cüce"
			star_data.radius = rng.randf_range(460000000.0, 620000000.0)
			star_data.luminosity = rng.randf_range(0.9, 1.25)
		elif star_roll < 0.975:
			star_data.spectral_type = "Beyaz Yıldız"
			star_data.radius = rng.randf_range(620000000.0, 880000000.0)
			star_data.luminosity = rng.randf_range(1.6, 2.6)
		elif star_roll < 0.990:
			star_data.spectral_type = "Mavi Dev"
			star_data.radius = rng.randf_range(950000000.0, 1450000000.0)
			star_data.luminosity = rng.randf_range(3.5, 6.0)
		else:
			star_data.spectral_type = "Kırmızı Dev"
			star_data.radius = rng.randf_range(1300000000.0, 2100000000.0)
			star_data.luminosity = rng.randf_range(2.2, 4.2)
			
		var type_roll = rng.randf()
		star_data.system_type = "EMPTY" if type_roll < 0.12 else ("ASTEROID_RICH" if type_roll < 0.16 else ("BINARY_CANDIDATE" if type_roll < 0.19 else "STANDARD"))
		
		spectral_dist[star_data.spectral_type] = spectral_dist.get(star_data.spectral_type, 0) + 1
		
		var star = instantiate_star_from_data(null, star_data)
		var bodies = generate_planets_for_star(null, star, false)
		
		var planets_in_system = 0
		for b in bodies:
			if b.type == "PLANET":
				planets_in_system += 1
				total_planets += 1
				planet_types_dist[b.planet_type] = planet_types_dist.get(b.planet_type, 0) + 1
				if b.moon_count == 0:
					zero_moon_planets += 1
				if b.planet_type == "GAS_GIANT":
					gas_giant_count += 1
					gas_giant_moons += b.moon_count
			elif b.type == "MOON":
				total_moons += 1
				
		if planets_in_system == 0:
			system_sizes["EMPTY"] += 1
		elif planets_in_system <= 3:
			system_sizes["SMALL (1-3)"] += 1
		elif planets_in_system <= 7:
			system_sizes["NORMAL (4-7)"] += 1
		else:
			system_sizes["LARGE (8-12)"] += 1
			
	return {
		"total_systems": count,
		"system_sizes": system_sizes,
		"spectral_dist": spectral_dist,
		"planet_types_dist": planet_types_dist,
		"total_planets": total_planets,
		"total_moons": total_moons,
		"zero_moon_planets": zero_moon_planets,
		"zero_moon_ratio": float(zero_moon_planets) / max(total_planets, 1),
		"avg_planets": float(total_planets) / max(count, 1),
		"avg_moons": float(total_moons) / max(count, 1),
		"avg_gas_giant_moons": float(gas_giant_moons) / max(gas_giant_count, 1)
	}


static func create_celestial_body(main_node: Node3D, b_name: String, b_type: String, radius: float, initial_pos: Vector3) -> CelestialBody:
	var body: CelestialBody
	match b_type:
		"STAR": body = Star.new()
		"PLANET": body = Planet.new()
		"MOON": body = Moon.new()
		_: body = CelestialBody.new()
	body.name = b_name
	body.type = b_type
	body.real_radius = radius
	body.real_position = initial_pos
	body.local_position = initial_pos
	body.rotation_speed = randf_range(0.05, 0.2)
	body.rotation_angle = randf_range(0.0, TAU)
	
	# Eksenel eğim: yıldızlar dik, gezegenler rastgele eğimli, uydular biraz eğik
	match b_type:
		"STAR":
			body.axial_tilt = 0.0
		"PLANET":
			# Gerçekçi dağılım: ağırlıklı olarak 0-45° ama bazıları çok eğik (Uranüs gibi)
			var tilt_roll = randf()
			if tilt_roll < 0.6:
				# Çoğu gezegen: 0–45° arası (Dünya, Mars, Satürn benzeri)
				body.axial_tilt = randf_range(deg_to_rad(5.0), deg_to_rad(45.0))
			elif tilt_roll < 0.85:
				# Orta eğim: 45–70° (nadir ama mümkün)
				body.axial_tilt = randf_range(deg_to_rad(45.0), deg_to_rad(70.0))
			else:
				# Aşırı eğik: 70–98° (Uranüs benzeri - neredeyse yan yatmış)
				body.axial_tilt = randf_range(deg_to_rad(70.0), deg_to_rad(98.0))
		"MOON":
			# Uydular genellikle daha az eğimli olur (ana gezegenden etkilenir)
			body.axial_tilt = randf_range(0.0, deg_to_rad(40.0))
		_:
			body.axial_tilt = randf_range(0.0, deg_to_rad(30.0))
	
	if b_type == "STAR":
		body.stellar_x = initial_pos.x
		body.stellar_y = initial_pos.y
		body.stellar_z = initial_pos.z
		
		# Yıldız Tipleri ve Canlı Spektral Renkler
		var star_roll = randf()
		var star_color: Color
		var light_color: Color
		var light_energy: float
		var class_suffix: String
		var spectral_type: String
		
		if star_roll < 0.02:
			# Mavi Dev (B/O-tipi) - Canlı elektrik mavisi
			star_color = Color(0.25, 0.58, 1.0)
			light_color = Color(0.65, 0.82, 1.0)
			light_energy = 2.4
			class_suffix = " (Mavi Dev)"
			spectral_type = "Mavi Dev"
		elif star_roll < 0.08:
			# Beyaz Yıldız (F/A-tipi) - Saf gümüşi beyaz
			star_color = Color(0.92, 0.96, 1.0)
			light_color = Color(0.96, 0.98, 1.0)
			light_energy = 1.8
			class_suffix = " (Beyaz Yıldız)"
			spectral_type = "Beyaz Yıldız"
		elif star_roll < 0.22:
			# Sarı Cüce (G-tipi) - Güneş benzeri sıcak altın sarısı
			star_color = Color(1.0, 0.88, 0.28)
			light_color = Color(1.0, 0.94, 0.75)
			light_energy = 1.5
			class_suffix = " (Sarı Cüce)"
			spectral_type = "Sarı Cüce"
		elif star_roll < 0.44:
			# Turuncu Cüce (K-tipi) - Canlı mandalina turuncusu
			star_color = Color(1.0, 0.55, 0.14)
			light_color = Color(1.0, 0.72, 0.38)
			light_energy = 1.25
			class_suffix = " (Turuncu Cüce)"
			spectral_type = "Turuncu Cüce"
		elif star_roll < 0.98:
			# Kırmızı Cüce (M-tipi) - Parlak yakut kızılı
			star_color = Color(1.0, 0.28, 0.12)
			light_color = Color(1.0, 0.45, 0.25)
			light_energy = 1.05
			class_suffix = " (Kırmızı Cüce)"
			spectral_type = "Kırmızı Cüce"
		else:
			# Kırmızı Dev - Devasa derin nar kırmızısı
			star_color = Color(1.0, 0.12, 0.04)
			light_color = Color(1.0, 0.32, 0.15)
			light_energy = 2.0
			class_suffix = " (Kırmızı Dev)"
			spectral_type = "Kırmızı Dev"
			
		body.base_color = star_color
		body.name += class_suffix
		body.spectral_type = spectral_type
		body.light_color = light_color
		body.light_energy = light_energy
		
		if main_node.directional_light:
			main_node.directional_light.light_color = light_color
			main_node.directional_light.light_energy = light_energy
			
	elif b_type == "PLANET":
		main_node.total_planets_count += 1
		var orbit_dist = initial_pos.length()
		var ONE_AU: float = 149597870700.0
		var planet_color: Color
		var planet_roughness: float = 0.5
		var planet_metallic: float = 0.0
		
		if orbit_dist < 1.0 * ONE_AU:
			var roll = randf()
			if roll < 0.5:
				planet_color = Color(randf_range(0.5, 0.8), randf_range(0.2, 0.35), randf_range(0.1, 0.2))
				body.name += " (Sıcak Çöl)"
			else:
				var gray = randf_range(0.25, 0.4)
				planet_color = Color(gray, gray, gray)
				body.name += " (Karasal Metalik)"
			planet_roughness = 0.9
			planet_metallic = 0.1
		elif orbit_dist < 3.0 * ONE_AU:
			var roll = randf()
			if roll < 0.4:
				planet_color = Color(randf_range(0.1, 0.2), randf_range(0.4, 0.6), randf_range(0.7, 0.9))
				body.name += " (Okyanus Dünyası)"
				planet_roughness = 0.55
			elif roll < 0.7:
				planet_color = Color(randf_range(0.65, 0.85), randf_range(0.3, 0.45), randf_range(0.15, 0.25))
				body.name += " (Kızıl Gezegen)"
				planet_roughness = 0.85
			else:
				planet_color = Color(randf_range(0.1, 0.25), randf_range(0.5, 0.75), randf_range(0.15, 0.3))
				body.name += " (Egzotik Yaşam)"
				planet_roughness = 0.7
			planet_metallic = 0.02
		else:
			var roll = randf()
			if roll < 0.55:
				var gas_roll = randf()
				if gas_roll < 0.33:
					planet_color = Color(randf_range(0.7, 0.85), randf_range(0.45, 0.6), randf_range(0.25, 0.35))
				elif gas_roll < 0.66:
					planet_color = Color(randf_range(0.35, 0.55), randf_range(0.2, 0.3), randf_range(0.6, 0.8))
				else:
					planet_color = Color(randf_range(0.15, 0.3), randf_range(0.5, 0.75), randf_range(0.55, 0.7))
				body.name += " (Gaz Devi)"
				planet_roughness = 0.3
				planet_metallic = 0.0
			else:
				planet_color = Color(randf_range(0.75, 0.9), randf_range(0.85, 0.95), randf_range(0.95, 1.0))
				body.name += " (Buz Dünyası)"
				planet_roughness = 0.6
				planet_metallic = 0.05
				
		body.base_color = planet_color
		body.roughness = planet_roughness
		body.metallic = planet_metallic
		body.has_atmosphere = true
		
		var atmos_color = planet_color
		atmos_color.a = 0.6
		body.atmosphere_color = atmos_color
		
	elif b_type == "MOON":
		main_node.total_moons_count += 1
		var moon_gray = randf_range(0.35, 0.6)
		body.base_color = Color(
			moon_gray * randf_range(0.92, 1.08),
			moon_gray * randf_range(0.92, 1.08),
			moon_gray * randf_range(0.92, 1.08)
		).clamp()
		body.roughness = randf_range(0.8, 0.95)
		body.metallic = 0.0
		
	if b_type == "STAR":
		spawn_body_graphics(main_node, body)
		main_node.universe.append(body)
		
	return body

static func spawn_body_graphics(main_node: Node3D, body: CelestialBody) -> void:
	if is_instance_valid(body.visual_mesh):
		return
		
	var mesh_instance = MeshInstance3D.new()
	var sphere_mesh = SphereMesh.new()
	sphere_mesh.radius = 1.0
	sphere_mesh.height = 2.0
	mesh_instance.mesh = sphere_mesh
	mesh_instance.extra_cull_margin = 2000000.0
	
	var mat = StandardMaterial3D.new()
	mat.roughness = body.roughness
	mat.metallic = body.metallic
	
	if body.noise_albedo != null:
		mat.albedo_color = Color.WHITE
		mat.albedo_texture = body.noise_albedo
		if body.noise_normal != null:
			mat.normal_texture = body.noise_normal
			mat.normal_enabled = true
	else:
		mat.albedo_color = body.base_color
	if body.has_city_lights:
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.58, 0.16)
		mat.emission_energy_multiplier = 0.22
		
	if "Gaz Devi" in body.name:
		mat.uv1_scale = Vector3(3.0, 0.2, 1.0)
		
	if body.type != "STAR":
		_init_detail_textures()
		mat.detail_enabled = true
		mat.detail_blend_mode = 3 # DETAIL_BLEND_MIX
		mat.detail_albedo = detail_noise_tex
		mat.detail_normal = detail_normal_tex
		mat.detail_uv_layer = 1 # DETAIL_UV_2
		mat.uv2_scale = Vector3(20000, 10000, 1)
	
	if body.type == "STAR":
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	else:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		
	sphere_mesh.material = mat
	main_node.add_child(mesh_instance)
	body.visual_mesh = mesh_instance
	
	# Tüm gök cisimleri için (STAR, PLANET, MOON) uzaktaki 2D billboard Sprite3D'yi oluştur
	var sprite_instance = Sprite3D.new()
	var tex = get_star_glow_texture()
	sprite_instance.texture = tex
	sprite_instance.pixel_size = 2.0 / 128.0
	sprite_instance.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite_instance.shaded = false
	sprite_instance.transparent = true
	sprite_instance.modulate = body.base_color
	sprite_instance.extra_cull_margin = 2000000.0
	sprite_instance.visible = false
	main_node.add_child(sprite_instance)
	body.lod_sprite = sprite_instance
	
	body.atmosphere_mesh = null
	if body.type != "STAR" and body.has_atmosphere:
		spawn_atmosphere_graphics(main_node, body)
	if body.type == "PLANET" and body.has_rings:
		spawn_planet_rings(main_node, body)
		
	# Yörünge çizgisi ekle
	if body.type != "STAR":
		spawn_orbit_line(main_node, body)

static func spawn_orbit_line(main_node: Node3D, body: CelestialBody) -> void:
	if body.parent_body == null or is_instance_valid(body.orbit_line_mesh):
		return
		
	var steps = 128 if body.type != "MOON" else 72
	var pts = PackedVector3Array()
	pts.resize(steps + 1)
	for i in range(steps + 1):
		var theta = (float(i) / steps) * TAU
		var pos = body.get_orbit_position_at_mean_anomaly(theta)
		pts[i] = pos
	body.orbit_sample_points = pts
	
	var orbit_instance = MeshInstance3D.new()
	orbit_instance.mesh = ImmediateMesh.new()
	orbit_instance.extra_cull_margin = 10000000.0
	orbit_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.use_point_size = true
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color.WHITE
	mat.emission_enabled = true
	mat.emission = Color(0.08, 0.55, 1.0)
	mat.emission_energy_multiplier = 1.35
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	orbit_instance.material_override = mat
	
	main_node.add_child(orbit_instance)
	body.orbit_line_mesh = orbit_instance


static func spawn_planet_rings(main_node: Node3D, body: CelestialBody) -> void:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = body.ring_inner_ratio
	torus.outer_radius = body.ring_outer_ratio
	torus.rings = 64
	torus.ring_segments = 8
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(body.ring_color, 0.32 + body.ring_density * 0.35)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.roughness = 0.85
	torus.material = material
	ring.mesh = torus
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.extra_cull_margin = 2000000.0
	main_node.add_child(ring)
	body.ring_mesh = ring


static func spawn_atmosphere_graphics(main_node: Node3D, body: CelestialBody) -> void:
	var atmosphere := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.035
	sphere.height = 2.07
	sphere.radial_segments = 32
	sphere.rings = 16
	var material := StandardMaterial3D.new()
	material.albedo_color = body.atmosphere_color
	material.emission_enabled = true
	material.emission = Color(body.atmosphere_color, 1.0)
	material.emission_energy_multiplier = 0.18
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_FRONT
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	sphere.material = material
	atmosphere.mesh = sphere
	atmosphere.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	atmosphere.extra_cull_margin = 2000000.0
	main_node.add_child(atmosphere)
	body.atmosphere_mesh = atmosphere

static func despawn_orbit_line(body: CelestialBody) -> void:
	if is_instance_valid(body.orbit_line_mesh):
		body.orbit_line_mesh.queue_free()
		body.orbit_line_mesh = null
	body.orbit_sample_points.clear()

static func despawn_body_graphics(body: CelestialBody) -> void:
	AsteroidBeltRenderer.clear(body)
	if body.type == "STAR":
		return # Yıldızlar evrende kalıcı arka plan cisimleridir
	if is_instance_valid(body.visual_mesh):
		body.visual_mesh.queue_free()
		body.visual_mesh = null
	if is_instance_valid(body.atmosphere_mesh):
		body.atmosphere_mesh.queue_free()
		body.atmosphere_mesh = null
	if is_instance_valid(body.ring_mesh):
		body.ring_mesh.queue_free()
		body.ring_mesh = null
	if is_instance_valid(body.lod_sprite):
		body.lod_sprite.queue_free()
		body.lod_sprite = null
	despawn_orbit_line(body)


static func _init_detail_textures() -> void:
	if detail_noise_tex != null:
		return
		
	var noise = FastNoiseLite.new()
	noise.seed = 12345
	noise.frequency = 0.1
	noise.fractal_octaves = 2
	
	detail_noise_tex = NoiseTexture2D.new()
	detail_noise_tex.noise = noise
	detail_noise_tex.seamless = true
	detail_noise_tex.width = 256
	detail_noise_tex.height = 256
	
	detail_normal_tex = NoiseTexture2D.new()
	detail_normal_tex.noise = noise
	detail_normal_tex.as_normal_map = true
	detail_normal_tex.bump_strength = 2.0
	detail_normal_tex.seamless = true
	detail_normal_tex.width = 256
	detail_normal_tex.height = 256

static func generate_body_textures(main_node: Node3D, body: CelestialBody) -> void:
	_init_detail_textures()
	
	var body_seed = (body.name + str(main_node.current_seed)).hash()
	var noise = FastNoiseLite.new()
	noise.seed = body_seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	
	var grad = Gradient.new()
	grad.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_LINEAR
	
	if body.type == "STAR":
		noise.frequency = 0.03
		noise.fractal_octaves = 3
		
		# Yıldız türüne göre gradyan belirle
		if "Mavi Dev" in body.name:
			grad.offsets = [0.0, 0.5, 1.0]
			grad.colors = [Color(0.1, 0.2, 0.6), Color(0.4, 0.6, 1.0), Color(1.0, 1.0, 1.0)]
		elif "Beyaz Yıldız" in body.name:
			grad.offsets = [0.0, 0.6, 1.0]
			grad.colors = [Color(0.3, 0.35, 0.4), Color(0.8, 0.85, 0.9), Color(1.0, 1.0, 1.0)]
		elif "Kırmızı Cüce" in body.name:
			grad.offsets = [0.0, 0.6, 1.0]
			grad.colors = [Color(0.3, 0.05, 0.0), Color(0.8, 0.2, 0.05), Color(1.0, 0.5, 0.1)]
		else: # Sarı Cüce ve diğerleri
			grad.offsets = [0.0, 0.5, 1.0]
			grad.colors = [Color(0.5, 0.1, 0.0), Color(0.9, 0.5, 0.1), Color(1.0, 0.9, 0.6)]
			
	elif body.type == "PLANET" or body.type == "MOON":
		noise.frequency = 0.015
		noise.fractal_octaves = 5
		
		if "Sıcak Çöl" in body.name:
			grad.offsets = [0.0, 0.4, 0.8, 1.0]
			grad.colors = [Color(0.25, 0.12, 0.08), Color(0.55, 0.32, 0.2), Color(0.85, 0.65, 0.45), Color(0.95, 0.85, 0.7)]
		elif "Karasal Metalik" in body.name:
			grad.offsets = [0.0, 0.4, 0.7, 1.0]
			grad.colors = [Color(0.12, 0.12, 0.12), Color(0.3, 0.25, 0.22), Color(0.45, 0.45, 0.45), Color(0.7, 0.7, 0.75)]
		elif "Okyanus Dünyası" in body.name:
			grad.offsets = [0.0, 0.45, 0.52, 0.62, 1.0]
			grad.colors = [Color(0.02, 0.08, 0.25), Color(0.05, 0.22, 0.45), Color(0.85, 0.8, 0.65), Color(0.12, 0.45, 0.18), Color(0.18, 0.32, 0.12)]
		elif "Kızıl Gezegen" in body.name:
			grad.offsets = [0.0, 0.5, 0.8, 1.0]
			grad.colors = [Color(0.22, 0.05, 0.02), Color(0.55, 0.18, 0.08), Color(0.8, 0.35, 0.15), Color(0.9, 0.55, 0.3)]
		elif "Egzotik Yaşam" in body.name:
			grad.offsets = [0.0, 0.48, 0.54, 0.75, 1.0]
			grad.colors = [Color(0.15, 0.02, 0.2), Color(0.35, 0.08, 0.45), Color(0.1, 0.75, 0.45), Color(0.65, 0.12, 0.55), Color(0.85, 0.8, 0.95)]
		elif "Gaz Devi" in body.name:
			noise.frequency = 0.015
			grad.offsets = [0.0, 0.25, 0.5, 0.75, 1.0]
			grad.colors = [Color(0.2, 0.1, 0.05), Color(0.55, 0.35, 0.2), Color(0.75, 0.6, 0.45), Color(0.4, 0.2, 0.1), Color(0.85, 0.75, 0.65)]
		elif "Buz Dünyası" in body.name:
			grad.offsets = [0.0, 0.5, 0.8, 1.0]
			grad.colors = [Color(0.2, 0.35, 0.55), Color(0.55, 0.75, 0.9), Color(0.85, 0.92, 0.98), Color(1.0, 1.0, 1.0)]
		else:
			grad.offsets = [0.0, 1.0]
			grad.colors = [body.base_color.darkened(0.4), body.base_color.lightened(0.4)]
			
	elif body.type == "MOON":
		noise.frequency = 0.025
		noise.fractal_octaves = 4
		grad.offsets = [0.0, 0.5, 1.0]
		grad.colors = [Color(0.15, 0.15, 0.15), Color(0.35, 0.35, 0.35), Color(0.65, 0.65, 0.65)]
		
	# Dokuları kademeli ve optimize çözünürlükle oluştur (Spike önleme)
	var tex_size = 256
	if body.type == "MOON":
		tex_size = 128
		
	var albedo_tex = NoiseTexture2D.new()
	albedo_tex.noise = noise
	albedo_tex.color_ramp = grad
	albedo_tex.seamless = true
	albedo_tex.width = tex_size
	albedo_tex.height = tex_size
	
	body.noise_albedo = albedo_tex
	
	# Normal haritası sadece gezegenler için gereklidir (Yıldızlar unshaded'dır, uydular ise küçüktür)
	if body.type == "PLANET":
		var normal_tex = NoiseTexture2D.new()
		normal_tex.noise = noise
		normal_tex.as_normal_map = true
		normal_tex.bump_strength = 4.0
		normal_tex.seamless = true
		normal_tex.width = tex_size
		normal_tex.height = tex_size
		body.noise_normal = normal_tex
	else:
		body.noise_normal = null
