class_name CosmicSectorManager
extends RefCounted

# ─────────────────────────────────────────────────────────────────────────────
# KOZMİK AĞ VE GALAKSİ SEKTÖR YÖNETİCİSİ (COSMIC CHUNK / GRID MANAGER)
# main_star.tscn'deki SectorManager mimarisinin galaktik ölçeğe (Mpc / Milyon LY)
# uyarlanmış halidir. Sonsuz evrende galaksileri deterministik chunk'lar halinde
# üretir, LOD seviyelerini yönetir ve sıfır tahsisle (allocation-free) havuza aktarır.
# ─────────────────────────────────────────────────────────────────────────────

const SECTOR_SIZE_LY: float = 7000000.0 # Her kozmik sektör 7.000.000 Işık Yılı genişliğindedir (~2.15 Mpc)
const GRID_RADIUS: int = 2 # 5x5x5 = 125 kozmik sektör (~35.000.000 LY görüş hacmi)
const MAX_ACTIVE_GALAXIES: int = 3000 # MultiMesh havuz kapasitesi

var universe_seed: int = 0
var current_sector: Vector3i = Vector3i(2147483647, 2147483647, 2147483647)
var loaded_sectors: Dictionary = {} # Vector3i -> Array[Galaxy]
var active_galaxies: Array[Galaxy] = []
var host_galaxy: Galaxy = null

func _init(p_universe_seed: int = 0) -> void:
	universe_seed = p_universe_seed
	_init_host_galaxy()

func _init_host_galaxy() -> void:
	host_galaxy = Galaxy.generate(universe_seed, Vector3.ZERO, true)
	host_galaxy.custom_name = "Ana Galaksi (Samanyolu Tipi)"
	host_galaxy.designation = "IC-1424"

# Koordinattan kozmik sektör koordinatını verir
static func get_sector_coord(pos_ly: Vector3) -> Vector3i:
	return Vector3i(
		int(floor(pos_ly.x / SECTOR_SIZE_LY)),
		int(floor(pos_ly.y / SECTOR_SIZE_LY)),
		int(floor(pos_ly.z / SECTOR_SIZE_LY))
	)

# 64-bit deterministik sektör tohum mikseri (Asal çarpanlar)
static func get_sector_seed(u_seed: int, coord: Vector3i) -> int:
	var h: int = u_seed
	h = (h ^ (coord.x * 73856093)) * 19349663
	h = (h ^ (coord.y * 83492791)) * 38928379
	h = (h ^ (coord.z * 50629129)) * 97261079
	h = (h ^ (h >> 16)) * 0x45d9f3b
	h = (h ^ (h >> 16))
	return h & 0x7FFFFFFFFFFFFFFF

# Kozmik Ağ (Cosmic Web) Filament ve Boşluk (Void) Yoğunluk Fonksiyonu
static func get_cosmic_density(coord: Vector3i) -> float:
	var fx := float(coord.x) * 0.45
	var fy := float(coord.y) * 0.45
	var fz := float(coord.z) * 0.45
	var wave1 := sin(fx * 1.2 + fy * 0.7) * cos(fz * 1.1 + fx * 0.5)
	var wave2 := cos(fy * 1.4 - fz * 0.9) * sin(fx * 0.8 + fy * 1.3)
	var wave3 := sin((fx + fy + fz) * 0.9)
	return (wave1 + wave2 + wave3) / 3.0 # -1.0 (Büyük Boşluk / Void) ile +1.0 (Üstküme / Filament) arası

# Tek bir sektörü deterministik olarak üretir
func generate_sector(coord: Vector3i) -> Array[Galaxy]:
	var list: Array[Galaxy] = []
	
	# Sektör (0, 0, 0) özel Yerel Grup sektörüdür
	if coord == Vector3i.ZERO:
		list.append(host_galaxy)
		_append_local_group_templates(list)
		return list
		
	var s_seed := get_sector_seed(universe_seed, coord)
	var rng := RandomNumberGenerator.new()
	rng.seed = s_seed
	
	var density := get_cosmic_density(coord)
	var count := 0
	
	if density < -0.35:
		# Kozmik Boşluk (Void - Örn: Boötes Boşluğu): Az sayıda izole cüce galaksi
		count = rng.randi_range(2, 6)
	elif density < 0.25:
		# Standart Kozmik İplikçik / Filament Alanı
		count = rng.randi_range(12, 28)
	else:
		# Yoğun Galaksi Kümesi / Düğüm (Örn: Başak Kümesi / Koma Kümesi Analog)
		count = rng.randi_range(35, 60)
		
	var base_pos := Vector3(
		float(coord.x) * SECTOR_SIZE_LY,
		float(coord.y) * SECTOR_SIZE_LY,
		float(coord.z) * SECTOR_SIZE_LY
	)
	
	for i in range(count):
		var g_seed := int(rng.randi()) & 0x7FFFFFFF
		var local_offset := Vector3(
			rng.randf_range(0.10 * SECTOR_SIZE_LY, 0.90 * SECTOR_SIZE_LY),
			rng.randf_range(0.10 * SECTOR_SIZE_LY, 0.90 * SECTOR_SIZE_LY),
			rng.randf_range(0.10 * SECTOR_SIZE_LY, 0.90 * SECTOR_SIZE_LY)
		)
		var galaxy_pos := base_pos + local_offset
		var g := Galaxy.generate(g_seed, galaxy_pos, false)
		g.custom_name = "Galaksi [%d,%d,%d #%d]" % [coord.x, coord.y, coord.z, i + 1]
		list.append(g)
		
	return list

func _append_local_group_templates(list: Array[Galaxy]) -> void:
	var templates = [
		{
			"seed_off": 101, "pos": Vector3(-95000.0, -120000.0, 55000.0), "morph": Galaxy.Morphology.IRREGULAR,
			"name": "Büyük Macellan Tipi Uydu", "desig": "LMC-Analog", "diam": 16000.0, "type": "Irr (Uydu Cüce Bulut)"
		},
		{
			"seed_off": 102, "pos": Vector3(85000.0, -170000.0, -75000.0), "morph": Galaxy.Morphology.IRREGULAR,
			"name": "Küçük Macellan Tipi Uydu", "desig": "SMC-Analog", "diam": 9000.0, "type": "Irr (Uydu Cüce Bulut)"
		},
		{
			"seed_off": 103, "pos": Vector3(-250000.0, 680000.0, 420000.0), "morph": Galaxy.Morphology.ELLIPTICAL,
			"name": "Leo I Cüce Küresel Galaksi", "desig": "Leo-I Analog", "diam": 7200.0, "type": "dE (Cüce Eliptik)"
		},
		{
			"seed_off": 201, "pos": Vector3(1450000.0, 850000.0, -1850000.0), "morph": Galaxy.Morphology.SPIRAL,
			"name": "Andromeda Tipi Dev Komşu", "desig": "M-31 Analog", "diam": 152000.0, "type": "Sb (Dev Sarmal Galaksi)"
		},
		{
			"seed_off": 202, "pos": Vector3(1850000.0, 450000.0, -2200000.0), "morph": Galaxy.Morphology.SPIRAL,
			"name": "Üçgen Galaksisi (M-33)", "desig": "M-33 Analog", "diam": 62000.0, "type": "Sc (Açık Sarmal Galaksi)"
		},
		{
			"seed_off": 203, "pos": Vector3(-850000.0, -1100000.0, 720000.0), "morph": Galaxy.Morphology.IRREGULAR,
			"name": "Barnard Düzensiz Galaksisi", "desig": "NGC-6822", "diam": 14000.0, "type": "Irr (Yerel Düzensiz)"
		},
		{
			"seed_off": 204, "pos": Vector3(-1900000.0, -1400000.0, -1800000.0), "morph": Galaxy.Morphology.IRREGULAR,
			"name": "Wolf-Lundmark-Melotte Cücesi", "desig": "WLM-Analog", "diam": 11000.0, "type": "Irr (İzole Cüce)"
		},
		{
			"seed_off": 301, "pos": Vector3(-2800000.0, 2200000.0, 3100000.0), "morph": Galaxy.Morphology.LENTICULAR,
			"name": "Centaurus A Radyo Galaksisi", "desig": "NGC-5128", "diam": 130000.0, "type": "S0 (Toz Kuşaklı Merceksi)"
		}
	]
	for tmpl in templates:
		var g := Galaxy.generate(universe_seed + int(tmpl["seed_off"]), tmpl["pos"], false)
		g.morphology = tmpl["morph"]
		g.custom_name = tmpl["name"]
		g.designation = tmpl["desig"]
		g.diameter_ly = tmpl["diam"]
		g.radius_ly = g.diameter_ly * 0.5
		g.hubble_type = tmpl["type"]
		list.append(g)

# Gözlemcinin konumuna göre sektörleri günceller (Sadece chunk değiştiğinde tetiklenir)
func update_sectors(observer_pos_ly: Vector3) -> bool:
	var target_sector := get_sector_coord(observer_pos_ly)
	if target_sector == current_sector:
		return false
		
	current_sector = target_sector
	
	# İstenen 5x5x5 sektör koordinatları kümesi
	var needed_coords: Dictionary = {}
	for x in range(current_sector.x - GRID_RADIUS, current_sector.x + GRID_RADIUS + 1):
		for y in range(current_sector.y - GRID_RADIUS, current_sector.y + GRID_RADIUS + 1):
			for z in range(current_sector.z - GRID_RADIUS, current_sector.z + GRID_RADIUS + 1):
				needed_coords[Vector3i(x, y, z)] = true
				
	# Menzilden çıkan sektörleri temizle
	var to_remove: Array[Vector3i] = []
	for coord in loaded_sectors.keys():
		if not needed_coords.has(coord):
			to_remove.append(coord)
	for coord in to_remove:
		loaded_sectors.erase(coord)
		
	# Yeni giren sektörleri oluştur
	for coord in needed_coords.keys():
		if not loaded_sectors.has(coord):
			loaded_sectors[coord] = generate_sector(coord)
			
	# Aktif galaksi listesini güncelle
	active_galaxies.clear()
	for coord in loaded_sectors.keys():
		var sector_list: Array[Galaxy] = loaded_sectors[coord]
		for g in sector_list:
			if active_galaxies.size() < MAX_ACTIVE_GALAXIES:
				active_galaxies.append(g)
				
	return true
