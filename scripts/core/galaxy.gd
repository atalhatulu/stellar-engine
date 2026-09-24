class_name Galaxy
extends RefCounted

# ─────────────────────────────────────────────────────────────────────────────
# ASTROFİZİKSEL GALAKSİ MODELİ VE KOZMİK AĞ (COSMIC WEB) ÜRETİCİSİ
# ─────────────────────────────────────────────────────────────────────────────

enum Morphology {
	SPIRAL = 0,
	ELLIPTICAL = 1,
	IRREGULAR = 2,
	LENTICULAR = 3
}

var seed: int = 0
var system_seed: int = 0
var unique_id: String = ""
var designation: String = ""
var custom_name: String = ""
var hubble_type: String = ""
var morphology: int = Morphology.SPIRAL
var has_bar: bool = false
var num_arms: int = 2
var age_gyr: float = 9.2
var total_real_stars: float = 2.5e11
var total_mass_solar: float = 8.0e11
var diameter_ly: float = 100000.0
var radius_ly: float = 50000.0
var core_radius_ly: float = 6500.0
var disk_scale_length_ly: float = 11500.0
var disk_scale_height_ly: float = 1000.0
var star_formation_rate: float = 2.2
var black_hole_mass_solar: float = 4.3e6
var schwarzschild_radius_km: float = 12.7e6
var schwarzschild_radius_au: float = 0.085
var arm_pitch_angle_deg: float = 12.5
var young_star_boost: float = 1.0

# Kozmolojik Uzay Konumu ve Yönelimi (Işık Yılı)
var position_ly: Vector3 = Vector3.ZERO
var galactic_position: GalacticPosition = null
var rotation_euler: Vector3 = Vector3.ZERO
var color_tint: Color = Color(0.9, 0.95, 1.0)
var is_host_galaxy: bool = false
var extra_flags: Dictionary = {}

static func generate(p_seed: int, p_pos_ly: Vector3 = Vector3.ZERO, p_is_host: bool = false) -> Galaxy:
	var galaxy := Galaxy.new()
	galaxy.seed = p_seed
	galaxy.system_seed = p_seed
	galaxy.unique_id = CelestialAddress.galaxy_id(p_seed)
	galaxy.position_ly = p_pos_ly
	galaxy.galactic_position = GalacticPosition.from_light_years(p_pos_ly)
	galaxy.is_host_galaxy = p_is_host
	
	var rng := RandomNumberGenerator.new()
	rng.seed = p_seed
	
	var catalog_prefixes := ["NGC-", "M-", "UGC-", "ESO-", "IC-"]
	galaxy.designation = "%s%d" % [catalog_prefixes[rng.randi() % catalog_prefixes.size()], rng.randi_range(1100, 8900)]
	galaxy.age_gyr = rng.randf_range(3.0, 13.2)
	
	# Yönelim açıları
	galaxy.rotation_euler = Vector3(
		rng.randf_range(-PI, PI),
		rng.randf_range(-PI, PI),
		rng.randf_range(-PI, PI)
	)
	
	# Morfoloji Dağılımı (Hubble Sequence)
	var morph_roll := rng.randf()
	if p_is_host:
		# Ana galaksi Samanyolu benzeri orta/sıkı sarmal olarak üretilir
		morph_roll = 0.40
	
	if morph_roll < 0.65:
		# SARMAL (Spiral)
		galaxy.morphology = Morphology.SPIRAL
		galaxy.diameter_ly = rng.randf_range(70000.0, 140000.0)
		galaxy.has_bar = rng.randf() < 0.65
		var sub_roll := rng.randf()
		if sub_roll < 0.35:
			galaxy.hubble_type = ("SBa" if galaxy.has_bar else "Sa") + " (Sıkı Sarmal)"
			galaxy.num_arms = 2
			galaxy.arm_pitch_angle_deg = rng.randf_range(8.0, 11.5)
			galaxy.color_tint = Color(0.95, 0.90, 0.75)
		elif sub_roll < 0.75:
			galaxy.hubble_type = ("SBb" if galaxy.has_bar else "Sb") + " (Orta Sarmal)"
			galaxy.num_arms = 2 if rng.randf() < 0.60 else 4
			galaxy.arm_pitch_angle_deg = rng.randf_range(12.0, 15.5)
			galaxy.color_tint = Color(0.85, 0.92, 1.0)
		else:
			galaxy.hubble_type = ("SBc" if galaxy.has_bar else "Sc") + " (Açık Sarmal)"
			galaxy.num_arms = rng.randi_range(3, 4)
			galaxy.arm_pitch_angle_deg = rng.randf_range(16.0, 21.0)
			galaxy.color_tint = Color(0.75, 0.88, 1.0)
	elif morph_roll < 0.85:
		# ELİPTİK (Elliptical: E0 - E7)
		galaxy.morphology = Morphology.ELLIPTICAL
		var e_num = rng.randi_range(0, 7)
		galaxy.hubble_type = "E%d (Eliptik Galaksi)" % e_num
		galaxy.diameter_ly = rng.randf_range(40000.0, 220000.0)
		galaxy.arm_pitch_angle_deg = 1.0 - (float(e_num) * 0.08) # Basıklık oranı
		galaxy.num_arms = 0
		galaxy.has_bar = false
		galaxy.color_tint = Color(1.0, 0.85, 0.62)
	elif morph_roll < 0.93:
		# MERCEKSİ (Lenticular: S0)
		galaxy.morphology = Morphology.LENTICULAR
		galaxy.hubble_type = "S0 (Merceksi Galaksi)"
		galaxy.diameter_ly = rng.randf_range(50000.0, 110000.0)
		galaxy.num_arms = 0
		galaxy.has_bar = rng.randf() < 0.35
		galaxy.color_tint = Color(0.96, 0.92, 0.80)
	else:
		# DÜZENSİZ / CÜCE (Irregular: Irr)
		galaxy.morphology = Morphology.IRREGULAR
		galaxy.hubble_type = "Irr (Düzensiz Cüce Galaksi)"
		galaxy.diameter_ly = rng.randf_range(12000.0, 35000.0)
		galaxy.num_arms = 1
		galaxy.has_bar = false
		galaxy.color_tint = Color(0.70, 0.85, 1.0)

	galaxy.radius_ly = galaxy.diameter_ly * 0.5
	galaxy.disk_scale_length_ly = galaxy.radius_ly * 0.23
	galaxy.core_radius_ly = galaxy.radius_ly * 0.13
	galaxy.disk_scale_height_ly = rng.randf_range(800.0, 1400.0)
	galaxy.total_mass_solar = (galaxy.diameter_ly / 100000.0) * rng.randf_range(4.0e11, 1.6e12)
	galaxy.total_real_stars = galaxy.total_mass_solar * rng.randf_range(0.22, 0.38)

	var bulge_mass := galaxy.total_mass_solar * 0.18
	galaxy.black_hole_mass_solar = bulge_mass * rng.randf_range(0.0012, 0.0018)
	galaxy.schwarzschild_radius_km = galaxy.black_hole_mass_solar * 2.9532
	galaxy.schwarzschild_radius_au = galaxy.schwarzschild_radius_km / 149597870.7
	
	var youth := clampf((13.5 - galaxy.age_gyr) / 10.0, 0.05, 1.0)
	galaxy.star_formation_rate = pow(youth, 1.3) * rng.randf_range(2.0, 8.0)
	galaxy.young_star_boost = youth
	
	return galaxy

# Kozmik Ağ ve Yerel Grup Galaksilerini Üretir (Poisson Ayrımı ve Astrofiziksel Çeşitlilik)
static func generate_cosmic_cluster(p_universe_seed: int, count: int = 80, max_dist_ly: float = 35000000.0) -> Array[Galaxy]:
	var list: Array[Galaxy] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = p_universe_seed
	
	# 1. Ana (Ev Sahibi) Galaksi - Merkezde (0, 0, 0)
	var host = Galaxy.generate(p_universe_seed, Vector3.ZERO, true)
	host.custom_name = "Ana Galaksi (Samanyolu Tipi)"
	list.append(host)
	
	# 2. Yerel Grup ve Yakın Çevre Temsilci Galaksileri (Önceden Tanımlı Astrofiziksel Şablonlar)
	var templates = [
		{
			"seed_off": 101, "pos": Vector3(-95000.0, -120000.0, 55000.0), "morph": Morphology.IRREGULAR,
			"name": "Büyük Macellan Tipi Uydu", "desig": "LMC-Analog", "diam": 16000.0, "type": "Irr (Uydu Cüce Bulut)"
		},
		{
			"seed_off": 102, "pos": Vector3(85000.0, -170000.0, -75000.0), "morph": Morphology.IRREGULAR,
			"name": "Küçük Macellan Tipi Uydu", "desig": "SMC-Analog", "diam": 9000.0, "type": "Irr (Uydu Cüce Bulut)"
		},
		{
			"seed_off": 103, "pos": Vector3(-250000.0, 680000.0, 420000.0), "morph": Morphology.ELLIPTICAL,
			"name": "Leo I Cüce Küresel Galaksi", "desig": "Leo-I Analog", "diam": 7200.0, "type": "dE (Cüce Eliptik)"
		},
		{
			"seed_off": 201, "pos": Vector3(1450000.0, 850000.0, -1850000.0), "morph": Morphology.SPIRAL,
			"name": "Andromeda Tipi Dev Komşu", "desig": "M-31 Analog", "diam": 152000.0, "type": "Sb (Dev Sarmal Galaksi)"
		},
		{
			"seed_off": 202, "pos": Vector3(1850000.0, 450000.0, -2200000.0), "morph": Morphology.SPIRAL,
			"name": "Üçgen Galaksisi (M-33)", "desig": "M-33 Analog", "diam": 62000.0, "type": "Sc (Açık Sarmal Galaksi)"
		},
		{
			"seed_off": 203, "pos": Vector3(-850000.0, -1100000.0, 720000.0), "morph": Morphology.IRREGULAR,
			"name": "Barnard Düzensiz Galaksisi", "desig": "NGC-6822", "diam": 14000.0, "type": "Irr (Yerel Düzensiz)"
		},
		{
			"seed_off": 204, "pos": Vector3(-1900000.0, -1400000.0, -1800000.0), "morph": Morphology.IRREGULAR,
			"name": "Wolf-Lundmark-Melotte Cücesi", "desig": "WLM-Analog", "diam": 11000.0, "type": "Irr (İzole Cüce)"
		},
		{
			"seed_off": 301, "pos": Vector3(-5800000.0, 4200000.0, 9400000.0), "morph": Morphology.LENTICULAR,
			"name": "Centaurus A Radyo Galaksisi", "desig": "NGC-5128", "diam": 130000.0, "type": "S0 (Toz Kuşaklı Merceksi)"
		},
		{
			"seed_off": 302, "pos": Vector3(6200000.0, 7800000.0, -6500000.0), "morph": Morphology.SPIRAL,
			"name": "Bode Sarmal Galaksisi", "desig": "M-81 Analog", "diam": 96000.0, "type": "Sa (Büyük Tasarım Sarmal)"
		},
		{
			"seed_off": 303, "pos": Vector3(6400000.0, 7500000.0, -6100000.0), "morph": Morphology.IRREGULAR,
			"name": "Puro Galaksisi (Starburst)", "desig": "M-82 Analog", "diam": 37000.0, "type": "Irr (Yıldız Yağmuru Galaksisi)"
		},
		{
			"seed_off": 304, "pos": Vector3(3200000.0, -8400000.0, 5500000.0), "morph": Morphology.SPIRAL,
			"name": "Heykeltıraş Sarmal Galaksisi", "desig": "NGC-253", "diam": 90000.0, "type": "Sc (Tozlu Sarmal)"
		},
		{
			"seed_off": 401, "pos": Vector3(11200000.0, 16500000.0, -11800000.0), "morph": Morphology.SPIRAL,
			"name": "Girdap Galaksisi", "desig": "M-51 Analog", "diam": 110000.0, "type": "Sc (Etkileşen Çift Sarmal)"
		},
		{
			"seed_off": 402, "pos": Vector3(-14500000.0, 12200000.0, 22100000.0), "morph": Morphology.LENTICULAR,
			"name": "Sombrero Dev Galaksisi", "desig": "M-104 Analog", "diam": 105000.0, "type": "Sa/S0 (Geniş Halolu)"
		},
		{
			"seed_off": 403, "pos": Vector3(9500000.0, 15200000.0, -8900000.0), "morph": Morphology.SPIRAL,
			"name": "Fırıldak Galaksisi", "desig": "M-101 Analog", "diam": 170000.0, "type": "Sc (Görkemli Sarmal)"
		},
		{
			"seed_off": 404, "pos": Vector3(-18200000.0, -22500000.0, 21000000.0), "morph": Morphology.LENTICULAR,
			"name": "Araba Tekerleği Galaksisi", "desig": "ESO 350-40", "diam": 145000.0, "type": "Halka (Çarpışma Halkası)"
		},
		{
			"seed_off": 501, "pos": Vector3(24000000.0, 38000000.0, -28000000.0), "morph": Morphology.ELLIPTICAL,
			"name": "Başak A (M-87) Süper Dev", "desig": "M-87 Virgo-A", "diam": 240000.0, "type": "cD (Devasa Eliptik)"
		}
	]
	
	for tmpl in templates:
		if list.size() >= count:
			break
		var g = Galaxy.generate(p_universe_seed + int(tmpl["seed_off"]), tmpl["pos"], false)
		g.morphology = tmpl["morph"]
		g.custom_name = tmpl["name"]
		g.designation = tmpl["desig"]
		g.diameter_ly = tmpl["diam"]
		g.radius_ly = g.diameter_ly * 0.5
		g.hubble_type = tmpl["type"]
		list.append(g)
		
	# 3. Kozmik Ağ Filamentleri Boyunca Poisson-Disk Ayrımıyla Serpiştirme
	# Galaksiler birbirinin çekim alanını ezmeyecek şekilde minimum mesafelerini korur.
	const MIN_SEPARATION_LY: float = 750000.0 # İki galaksi arası en az 750.000 Işık Yılı mesafe
	var num_filaments = 8
	var filament_dirs: Array[Vector3] = []
	for f in range(num_filaments):
		var dir = Vector3(
			rng.randf_range(-1.0, 1.0),
			rng.randf_range(-0.45, 0.45), # Kozmik düzlem basıklığı
			rng.randf_range(-1.0, 1.0)
		).normalized()
		filament_dirs.append(dir)
		
	var attempts = 0
	var max_attempts = (count - list.size()) * 40
	var gen_idx = 0
	
	while list.size() < count and attempts < max_attempts:
		attempts += 1
		var f_idx = rng.randi() % num_filaments
		var f_dir = filament_dirs[f_idx]
		
		# Mesafeyi merkeze yakın yoğun, dışa doğru seyreltik ölçekle (800.000 LY - max_dist_ly)
		var t = pow(rng.randf(), 0.65)
		var dist_ly = lerpf(850000.0, max_dist_ly, t)
		
		var perp1 = f_dir.cross(Vector3.UP).normalized()
		if perp1.length_squared() < 0.01:
			perp1 = f_dir.cross(Vector3.RIGHT).normalized()
		var perp2 = f_dir.cross(perp1).normalized()
		
		var scatter_radius = (dist_ly * 0.16) * rng.randfn(0.0, 1.0)
		var angle = rng.randf_range(0.0, TAU)
		var offset = (perp1 * cos(angle) + perp2 * sin(angle)) * scatter_radius
		var cand_pos = (f_dir * dist_ly) + offset
		
		# Poisson-disk asgari mesafe kontrolü: Başka hiçbir galaksiye MIN_SEPARATION_LY'den yakın olamaz
		var too_close = false
		for existing in list:
			if (cand_pos - existing.position_ly).length_squared() < (MIN_SEPARATION_LY * MIN_SEPARATION_LY):
				too_close = true
				break
		if too_close:
			continue
			
		gen_idx += 1
		var g_seed = p_universe_seed + 1000 + gen_idx * 43
		var g = Galaxy.generate(g_seed, cand_pos, false)
		list.append(g)
		
	return list
