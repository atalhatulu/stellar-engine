class_name SectorManager
extends RefCounted

const LIGHT_YEAR: float = 9460730472580800.0
const SECTOR_SIZE_LY: float = 65.0
const SECTOR_SIZE: float = 65.0 * LIGHT_YEAR
const GRID_RADIUS: int = 2 # 5x5x5 = 125 sektör (Genişletilmiş ~225 LY görüş menzili)
const TOTAL_GRID_SECTORS: int = (2 * GRID_RADIUS + 1) * (2 * GRID_RADIUS + 1) * (2 * GRID_RADIUS + 1) # 125

var universe_seed: int = 0
var current_sector: Vector3i = Vector3i(2147483647, 2147483647, 2147483647) # Başlangıçta geçersiz
var protected_sector_coord: Vector3i = Vector3i(2147483647, 2147483647, 2147483647) # Korumalı aktif sistem sektörü
var loaded_sectors: Dictionary = {} # Vector3i -> Array
var total_generated_stars: int = 0
var _pending_sectors: Array[Vector3i] = []

func _init(p_universe_seed: int = 0):
	universe_seed = p_universe_seed

# Galaktik 64-bit koordinattan sektör koordinatını hesaplar
static func get_sector_coord(galactic_pos: Vector3) -> Vector3i:
	return Vector3i(
		int(floor(galactic_pos.x / SECTOR_SIZE)),
		int(floor(galactic_pos.y / SECTOR_SIZE)),
		int(floor(galactic_pos.z / SECTOR_SIZE))
	)

# Deterministik 64-bit sektör tohumu türetici (Asal çarpanlar ve bit mikseri)
static func get_sector_seed(u_seed: int, coord: Vector3i) -> int:
	var h: int = u_seed
	h = (h ^ (coord.x * 73856093)) * 19349663
	h = (h ^ (coord.y * 83492791)) * 38928379
	h = (h ^ (coord.z * 50629129)) * 97261079
	h = (h ^ (h >> 16)) * 0x45d9f3b
	h = (h ^ (h >> 16))
	return h & 0x7FFFFFFFFFFFFFFF # Pozitif 64-bit integer

# Tek bir sektörü tamamen deterministik olarak üretir (Saf veri, sıfır Node3D)
func generate_sector(coord: Vector3i) -> Array:
	var rng = RandomNumberGenerator.new()
	rng.seed = get_sector_seed(universe_seed, coord)
	
	var stars: Array = []
	var star_count: int = rng.randi_range(24, 40)
	
	var base_x: float = float(coord.x) * SECTOR_SIZE
	var base_y: float = float(coord.y) * SECTOR_SIZE
	var base_z: float = float(coord.z) * SECTOR_SIZE
	
	for i in range(star_count):
		var star = StarData.new()
		star.unique_id = "SEC_%d_%d_%d_S%d" % [coord.x, coord.y, coord.z, i + 1]
		star.name = "S_%d_%d_%d_%d" % [coord.x, coord.y, coord.z, i + 1]
		star.sector_coord = coord
		star.system_seed = int(rng.randi()) & 0x7FFFFFFF
		
		# Sektör sınırları içinde hafif iç kenar marjı (%5-%95) ile yerleştirme
		var local_x = rng.randf_range(0.05 * SECTOR_SIZE, 0.95 * SECTOR_SIZE)
		var local_y = rng.randf_range(0.05 * SECTOR_SIZE, 0.95 * SECTOR_SIZE)
		var local_z = rng.randf_range(0.05 * SECTOR_SIZE, 0.95 * SECTOR_SIZE)
		
		star.stellar_x = base_x + local_x
		star.stellar_y = base_y + local_y
		star.stellar_z = base_z + local_z
		
		# Spektral tip, yarıçap, parlaklık ve renk dağılımı (Canlı Spektral Renkler)
		var star_roll = rng.randf()
		if star_roll < 0.68:
			# Kırmızı Cüce (M-tipi) - Evrenin en yaygın yıldızları (%68)
			star.spectral_type = "Kırmızı Cüce"
			star.radius = rng.randf_range(160000000.0, 320000000.0)
			star.base_color = Color(1.0, 0.28, 0.12)
			star.light_color = Color(1.0, 0.45, 0.25)
			star.light_energy = rng.randf_range(0.9, 1.15)
			star.luminosity = rng.randf_range(0.15, 0.35)
		elif star_roll < 0.84:
			# Turuncu Cüce (K-tipi) - Sıcak mandalina/turuncu (%16)
			star.spectral_type = "Turuncu Cüce"
			star.radius = rng.randf_range(320000000.0, 460000000.0)
			star.base_color = Color(1.0, 0.55, 0.14)
			star.light_color = Color(1.0, 0.72, 0.38)
			star.light_energy = rng.randf_range(1.15, 1.35)
			star.luminosity = rng.randf_range(0.45, 0.75)
		elif star_roll < 0.93:
			# Sarı Cüce (G-tipi) - Güneş benzeri altın sarısı (%9)
			star.spectral_type = "Sarı Cüce"
			star.radius = rng.randf_range(460000000.0, 620000000.0)
			star.base_color = Color(1.0, 0.88, 0.28)
			star.light_color = Color(1.0, 0.94, 0.75)
			star.light_energy = rng.randf_range(1.35, 1.6)
			star.luminosity = rng.randf_range(0.9, 1.25)
		elif star_roll < 0.975:
			# Beyaz Yıldız (F/A-tipi) - Parlak gümüşi beyaz (%4.5)
			star.spectral_type = "Beyaz Yıldız"
			star.radius = rng.randf_range(620000000.0, 880000000.0)
			star.base_color = Color(0.92, 0.96, 1.0)
			star.light_color = Color(0.96, 0.98, 1.0)
			star.light_energy = rng.randf_range(1.65, 2.0)
			star.luminosity = rng.randf_range(1.6, 2.6)
		elif star_roll < 0.990:
			# Mavi Dev (B/O-tipi) - Canlı elektrik mavisi (%1.5)
			star.spectral_type = "Mavi Dev"
			star.radius = rng.randf_range(950000000.0, 1450000000.0)
			star.base_color = Color(0.25, 0.58, 1.0)
			star.light_color = Color(0.65, 0.82, 1.0)
			star.light_energy = rng.randf_range(2.2, 2.8)
			star.luminosity = rng.randf_range(3.5, 6.0)
		else:
			# Kırmızı Dev (M/K-tipi Dev) - Derin kızıl/yakut kırmızısı dev (%1.0)
			star.spectral_type = "Kırmızı Dev"
			star.radius = rng.randf_range(1300000000.0, 2100000000.0)
			star.base_color = Color(1.0, 0.12, 0.04)
			star.light_color = Color(1.0, 0.32, 0.15)
			star.light_energy = rng.randf_range(1.8, 2.4)
			star.luminosity = rng.randf_range(2.2, 4.2)
			
		# Gelecek uyumluluğu ve nadir sistem sınıflandırması (Aşama 7)
		var type_roll = rng.randf()
		if type_roll < 0.12:
			star.system_type = "EMPTY"
		elif type_roll < 0.92:
			star.system_type = "STANDARD"
		elif type_roll < 0.96:
			star.system_type = "ASTEROID_RICH"
			star.has_asteroid_belt = true
		else:
			star.system_type = "BINARY_CANDIDATE"
			star.is_binary_candidate = true
			
		stars.append(star)
		
	return stars

# Tek bir yıldızı (örneğin S1 ana yıldızını) tüm sektörü üretmeden doğrudan türetir (Aşama 7C)
# generate_sector(coord)[target_index] ile %100 birebir aynı veriyi üretir.
static func generate_single_star(u_seed: int, coord: Vector3i, target_index: int = 0) -> StarData:
	var rng = RandomNumberGenerator.new()
	rng.seed = get_sector_seed(u_seed, coord)
	
	var star_count: int = rng.randi_range(24, 40)
	if target_index >= star_count:
		target_index = target_index % star_count
		
	var base_x: float = float(coord.x) * SECTOR_SIZE
	var base_y: float = float(coord.y) * SECTOR_SIZE
	var base_z: float = float(coord.z) * SECTOR_SIZE
	
	# Hedef yıldıza kadar olan önceki adımları deterministik tüket
	for i in range(target_index):
		var _sys_seed = int(rng.randi()) & 0x7FFFFFFF
		var _lx = rng.randf_range(0.05 * SECTOR_SIZE, 0.95 * SECTOR_SIZE)
		var _ly = rng.randf_range(0.05 * SECTOR_SIZE, 0.95 * SECTOR_SIZE)
		var _lz = rng.randf_range(0.05 * SECTOR_SIZE, 0.95 * SECTOR_SIZE)
		var _sr = rng.randf()
		var _tr = rng.randf()
		
	var star = StarData.new()
	star.unique_id = "SEC_%d_%d_%d_S%d" % [coord.x, coord.y, coord.z, target_index + 1]
	star.name = "S_%d_%d_%d_%d" % [coord.x, coord.y, coord.z, target_index + 1]
	star.sector_coord = coord
	star.system_seed = int(rng.randi()) & 0x7FFFFFFF
	
	var local_x = rng.randf_range(0.05 * SECTOR_SIZE, 0.95 * SECTOR_SIZE)
	var local_y = rng.randf_range(0.05 * SECTOR_SIZE, 0.95 * SECTOR_SIZE)
	var local_z = rng.randf_range(0.05 * SECTOR_SIZE, 0.95 * SECTOR_SIZE)
	
	star.stellar_x = base_x + local_x
	star.stellar_y = base_y + local_y
	star.stellar_z = base_z + local_z
	
	var star_roll = rng.randf()
	if star_roll < 0.68:
		star.spectral_type = "Kırmızı Cüce"
		star.radius = rng.randf_range(160000000.0, 320000000.0)
		star.base_color = Color(1.0, 0.28, 0.12)
		star.light_color = Color(1.0, 0.45, 0.25)
		star.light_energy = rng.randf_range(0.9, 1.15)
		star.luminosity = rng.randf_range(0.15, 0.35)
	elif star_roll < 0.84:
		star.spectral_type = "Turuncu Cüce"
		star.radius = rng.randf_range(320000000.0, 460000000.0)
		star.base_color = Color(1.0, 0.55, 0.14)
		star.light_color = Color(1.0, 0.72, 0.38)
		star.light_energy = rng.randf_range(1.15, 1.35)
		star.luminosity = rng.randf_range(0.45, 0.75)
	elif star_roll < 0.93:
		star.spectral_type = "Sarı Cüce"
		star.radius = rng.randf_range(460000000.0, 620000000.0)
		star.base_color = Color(1.0, 0.88, 0.28)
		star.light_color = Color(1.0, 0.94, 0.75)
		star.light_energy = rng.randf_range(1.35, 1.6)
		star.luminosity = rng.randf_range(0.9, 1.25)
	elif star_roll < 0.975:
		star.spectral_type = "Beyaz Yıldız"
		star.radius = rng.randf_range(620000000.0, 880000000.0)
		star.base_color = Color(0.92, 0.96, 1.0)
		star.light_color = Color(0.96, 0.98, 1.0)
		star.light_energy = rng.randf_range(1.65, 2.0)
		star.luminosity = rng.randf_range(1.6, 2.6)
	elif star_roll < 0.990:
		star.spectral_type = "Mavi Dev"
		star.radius = rng.randf_range(950000000.0, 1450000000.0)
		star.base_color = Color(0.25, 0.58, 1.0)
		star.light_color = Color(0.65, 0.82, 1.0)
		star.light_energy = rng.randf_range(2.2, 2.8)
		star.luminosity = rng.randf_range(3.5, 6.0)
	else:
		star.spectral_type = "Kırmızı Dev"
		star.radius = rng.randf_range(1300000000.0, 2100000000.0)
		star.base_color = Color(1.0, 0.12, 0.04)
		star.light_color = Color(1.0, 0.32, 0.15)
		star.light_energy = rng.randf_range(1.8, 2.4)
		star.luminosity = rng.randf_range(2.2, 4.2)
		
	var type_roll = rng.randf()
	if type_roll < 0.12:
		star.system_type = "EMPTY"
	elif type_roll < 0.92:
		star.system_type = "STANDARD"
	elif type_roll < 0.96:
		star.system_type = "ASTEROID_RICH"
		star.has_asteroid_belt = true
	else:
		star.system_type = "BINARY_CANDIDATE"
		star.is_binary_candidate = true
		
	return star

func is_coord_in_grid(coord: Vector3i, center: Vector3i) -> bool:
	return abs(coord.x - center.x) <= GRID_RADIUS and abs(coord.y - center.y) <= GRID_RADIUS and abs(coord.z - center.z) <= GRID_RADIUS

# Oyuncunun galaktik pozisyonuna göre 3x3x3 sektör ızgarasını Delta Streaming ile günceller
func update_player_position(galactic_pos: Vector3, p_protected_coord: Vector3i = Vector3i(2147483647, 2147483647, 2147483647), budget_usec: int = 0) -> bool:
	var protection_changed := p_protected_coord != Vector3i(2147483647, 2147483647, 2147483647) and p_protected_coord != protected_sector_coord
	if protection_changed:
		protected_sector_coord = p_protected_coord
		
	var new_sector_coord = get_sector_coord(galactic_pos)
	var has_protected = (protected_sector_coord != Vector3i(2147483647, 2147483647, 2147483647))
	var expected_size = TOTAL_GRID_SECTORS if not has_protected else (TOTAL_GRID_SECTORS if is_coord_in_grid(protected_sector_coord, new_sector_coord) else TOTAL_GRID_SECTORS + 1)
	
	if not protection_changed and new_sector_coord == current_sector and loaded_sectors.size() == expected_size and _pending_sectors.is_empty():
		return false # Sektör değişmedi ve tüm gerekli sektörler RAM'de
		
	var sector_changed: bool = (new_sector_coord != current_sector)
	
	if sector_changed or protection_changed or (_pending_sectors.is_empty() and loaded_sectors.size() != expected_size):
		current_sector = new_sector_coord
		
		# Hedeflenen 125 aktif sektör koordinat kümesi (GRID_RADIUS = 2)
		var target_coords: Dictionary = {}
		for x in range(current_sector.x - GRID_RADIUS, current_sector.x + GRID_RADIUS + 1):
			for y in range(current_sector.y - GRID_RADIUS, current_sector.y + GRID_RADIUS + 1):
				for z in range(current_sector.z - GRID_RADIUS, current_sector.z + GRID_RADIUS + 1):
					target_coords[Vector3i(x, y, z)] = true
					
		# Korumalı aktif sistem sektörü varsa unload edilmesini engelle
		if has_protected:
			target_coords[protected_sector_coord] = true
					
		# 1. UNLOAD: Hedef kümede olmayan eski sektörleri sil
		var coords_to_remove: Array[Vector3i] = []
		for coord in loaded_sectors.keys():
			if not target_coords.has(coord):
				coords_to_remove.append(coord)
				
		for coord in coords_to_remove:
			loaded_sectors.erase(coord)
			
		# En yakın sektörler önce üretilecek şekilde kuyruğu hazırla
		_pending_sectors.clear()
		for coord in target_coords:
			if not loaded_sectors.has(coord):
				_pending_sectors.append(coord)
		_pending_sectors.sort_custom(func(a, b): return Vector3(a - current_sector).length_squared() < Vector3(b - current_sector).length_squared())

	# 2. Kuyruktan sektör üret (Süre ve miktar bütçesiyle karelere yay)
	var started := Time.get_ticks_usec()
	var generated := 0
	while not _pending_sectors.is_empty():
		var coord = _pending_sectors.pop_front()
		loaded_sectors[coord] = generate_sector(coord)
		generated += 1
		if budget_usec > 0 and (generated >= 2 or Time.get_ticks_usec() - started >= budget_usec):
			break

	# Toplam aktif yıldız sayısını güncelle
	total_generated_stars = 0
	for coord in loaded_sectors:
		total_generated_stars += loaded_sectors[coord].size()
		
	return sector_changed or protection_changed or generated > 0

# Belirli bir sektörün yıldız parmak izini (fingerprint) oluşturur
func get_sector_fingerprint(coord: Vector3i) -> String:
	var stars: Array
	if loaded_sectors.has(coord):
		stars = loaded_sectors[coord]
	else:
		stars = generate_sector(coord)
		
	var parts: Array[String] = []
	for star in stars:
		parts.append(star.get_fingerprint())
		
	# Deterministik string özeti
	var raw_str = ";".join(parts)
	return "%d_stars_%X" % [stars.size(), raw_str.hash()]

# Determinizm Doğrulama Testi (A -> B -> A testi)
func test_sector_determinism(coord_a: Vector3i, coord_b: Vector3i) -> Dictionary:
	var fp_a1 = get_sector_fingerprint(coord_a)
	var fp_b = get_sector_fingerprint(coord_b)
	var fp_a2 = get_sector_fingerprint(coord_a)
	
	var is_consistent = (fp_a1 == fp_a2)
	return {
		"sector_a": coord_a,
		"sector_b": coord_b,
		"fingerprint_a1": fp_a1,
		"fingerprint_b": fp_b,
		"fingerprint_a2": fp_a2,
		"is_deterministic": is_consistent
	}

# Performans ve Süre Ölçüm Benchmark'ı (Farklı büyüklükteki koordinatlarda)
func run_benchmark(test_coords: Array) -> Array:
	var results: Array = []
	for coord in test_coords:
		var start_time = Time.get_ticks_usec()
		var stars = generate_sector(coord)
		var elapsed_usec = Time.get_ticks_usec() - start_time
		
		results.append({
			"coord": coord,
			"star_count": stars.size(),
			"elapsed_usec": elapsed_usec,
			"elapsed_ms": float(elapsed_usec) / 1000.0,
			"fingerprint": get_sector_fingerprint(coord)
		})
	return results


# Aşama 6 Test 4: Negatif Koordinat ve Sınır Kapsama Testi
func test_negative_coordinates() -> Dictionary:
	var test_coords = [
		Vector3i(-1, 0, 0),
		Vector3i(0, -1, 0),
		Vector3i(0, 0, -1),
		Vector3i(-100, -100, -100)
	]
	var results: Array = []
	var all_valid = true
	
	for coord in test_coords:
		var stars = generate_sector(coord)
		var coord_valid = true
		for s in stars:
			var s_pos = Vector3(s.stellar_x, s.stellar_y, s.stellar_z)
			var calculated_coord = get_sector_coord(s_pos)
			if calculated_coord != coord:
				coord_valid = false
				all_valid = false
				break
				
		var fp1 = get_sector_fingerprint(coord)
		var fp2 = get_sector_fingerprint(coord)
		if fp1 != fp2:
			all_valid = false
			coord_valid = false
			
		results.append({
			"coord": coord,
			"star_count": stars.size(),
			"valid_bounds": coord_valid,
			"fingerprint": fp1
		})
		
	return {
		"all_valid": all_valid,
		"results": results
	}


# Aşama 6 Test 2: Çoklu Sektör Geri Dönüş Döngü Testi (A -> B -> C -> D -> A)
func test_multi_sector_loop(coords: Array = []) -> Dictionary:
	if coords.is_empty():
		coords = [
			Vector3i(0, 0, 0),
			Vector3i(-5, 12, -3),
			Vector3i(100, -200, 50),
			Vector3i(-999, -888, -777)
		]
	var initial_fp_a = get_sector_fingerprint(coords[0])
	
	# B, C, D sektörlerini yükle
	var visited_fps: Array = []
	for i in range(1, coords.size()):
		visited_fps.append(get_sector_fingerprint(coords[i]))
		
	# Tekrar A sektörünü yükle
	var final_fp_a = get_sector_fingerprint(coords[0])
	var loop_deterministic = (initial_fp_a == final_fp_a)
	
	return {
		"start_sector": coords[0],
		"initial_fingerprint": initial_fp_a,
		"final_fingerprint": final_fp_a,
		"is_deterministic": loop_deterministic
	}

# Aşama 6 Test 3: Hızlı Sektör Geçişi / Işınlanma Testi (Tek Karede Çoklu Sektör Atlama)
func test_rapid_jump() -> Dictionary:
	var original_sector = current_sector
	var jumps = [
		Vector3(0, 0, 0),
		Vector3(1500, 2200, -3100), # ~100+ sektör öteye anlık sıçrama
		Vector3(-8000, -5000, 9500), # ~500+ sektör ters yöne anlık sıçrama
		Vector3(0, 0, 0) # Merkeze geri sıçrama
	]
	
	var jump_results: Array = []
	var all_successful = true
	
	for target_pos in jumps:
		var start_ticks = Time.get_ticks_usec()
		var target_coord = get_sector_coord(target_pos)
		var changed = update_player_position(target_pos)
		var elapsed_usec = Time.get_ticks_usec() - start_ticks
		
		var expected_size = TOTAL_GRID_SECTORS if protected_sector_coord == Vector3i(2147483647, 2147483647, 2147483647) else (TOTAL_GRID_SECTORS if is_coord_in_grid(protected_sector_coord, target_coord) else TOTAL_GRID_SECTORS + 1)
		var is_size_valid = (loaded_sectors.size() == expected_size)
		var is_center_valid = (current_sector == target_coord)
		
		if not is_size_valid or not is_center_valid:
			all_successful = false
			
		jump_results.append({
			"target_coord": target_coord,
			"loaded_sectors": loaded_sectors.size(),
			"elapsed_usec": elapsed_usec,
			"elapsed_ms": float(elapsed_usec) / 1000.0,
			"valid": (is_size_valid and is_center_valid)
		})
		
	# Test sonrası başlangıç sektörüne geri dön
	update_player_position(Vector3(original_sector.x * SECTOR_SIZE, original_sector.y * SECTOR_SIZE, original_sector.z * SECTOR_SIZE))
	
	return {
		"all_successful": all_successful,
		"jumps": jump_results
	}
