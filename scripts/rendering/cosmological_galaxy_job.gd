extends RefCounted

# ─────────────────────────────────────────────────────────────────────────────
# KOZMOLOJİK GALAKSİ ARKA PLAN İŞ PARÇACIĞI (COSMOLOGICAL GALAXY FIELD JOB)
# main_star.tscn'deki StarFieldJob mimarisinin galaksilerarası kozmolojik ölçeğe
# (Milyonlarca Işık Yılı / Mpc) uyarlanmış halidir.
# 15.000–25.000 derin uzay galaksisini arka planda iş parçacığı (worker thread)
# üzerinde üretir, kozmik ağ (cosmic web) filament dağılımını hesaplar ve
# GPU MultiMesh tamponuna sıfır kare takılmasıyla aktarır.
# ─────────────────────────────────────────────────────────────────────────────

var _mutex := Mutex.new()
var _cancelled := false

func cancel() -> void:
	_mutex.lock()
	_cancelled = true
	_mutex.unlock()

func cancelled() -> bool:
	_mutex.lock()
	var value := _cancelled
	_mutex.unlock()
	return value

func build(seed_value: int, region: Vector3i, region_size: float, minimum: float,
		maximum: float, capacity: int, chunk_count: int) -> Dictionary:
	var started := Time.get_ticks_usec()
	var anchor := Vector3(region) * region_size
	
	# Deterministik sektör tohumu (Asal çarpan mikseri)
	var h: int = seed_value
	h = (h ^ (region.x * 73856093)) * 19349663
	h = (h ^ (region.y * 83492791)) * 38928379
	h = (h ^ (region.z * 50629129)) * 97261079
	h = (h ^ (h >> 16)) * 0x45d9f3b
	h = (h ^ (h >> 16))
	var s_seed: int = h & 0x7FFFFFFFFFFFFFFF
	
	var rng := RandomNumberGenerator.new()
	rng.seed = s_seed
	
	var positions := PackedVector3Array()
	var seeds := PackedInt32Array()
	var morphologies := PackedByteArray()
	var diameters := PackedFloat32Array()
	
	positions.resize(capacity)
	seeds.resize(capacity)
	morphologies.resize(capacity)
	diameters.resize(capacity)
	
	var buffers: Array[PackedFloat32Array] = []
	var index := 0
	
	for c in range(chunk_count):
		var count := capacity / chunk_count + (1 if c < capacity % chunk_count else 0)
		var buffer := PackedFloat32Array()
		buffer.resize(count * 20)
		
		for i in range(count):
			if i % 64 == 0 and cancelled():
				return {}
				
			# 1. 3D Kozmik Ağ (Cosmic Web) Filament ve Boşluk Örneklemesi:
			# Galaksiler uzayda homojen dağılmaz; Zeldovich krep modeli benzeri
			# filamentler ve yoğun üstkümeler boyunca dizilir, aralarda büyük boşluklar kalır.
			var cand_dir := Vector3.ZERO
			var cand_dist := 0.0
			var gal_pos_abs := Vector3.ZERO
			
			for attempt in range(8):
				var theta := rng.randf_range(0.0, TAU)
				var z := rng.randf_range(-1.0, 1.0)
				var radial := sqrt(maxf(0.0, 1.0 - z * z))
				cand_dir = Vector3(radial * cos(theta), z, radial * sin(theta))
				
				# Mesafeyi hacimsel güç eğrisiyle dağıt (Uzakta daha çok galaksi hacmi)
				var t_dist := pow(rng.randf(), 0.55)
				cand_dist = lerpf(minimum, maximum, t_dist)
				gal_pos_abs = anchor + cand_dir * cand_dist
				
				# Kozmik ağ yoğunluk dalgası
				var k := 0.00000028 # ~3.5 Milyon LY dalga boyu
				var density := (
					sin(gal_pos_abs.x * k * 1.1 + gal_pos_abs.y * k * 0.7) *
					cos(gal_pos_abs.z * k * 0.9 + gal_pos_abs.x * k * 0.4) +
					cos(gal_pos_abs.y * k * 1.3 - gal_pos_abs.z * k * 0.8) *
					sin(gal_pos_abs.x * k * 0.8 + gal_pos_abs.y * k * 1.2)
				) * 0.5
				
				# Filament içi ise kabul et, boşluksa (void) düşük ihtimalle kabul et
				if density > -0.20 or rng.randf() < 0.25:
					break
					
			var gal_seed := int(rng.randi()) & 0x7FFFFFFF
			positions[index] = gal_pos_abs
			seeds[index] = gal_seed
			
			# 2. Galaksi Morfolojisi ve Astrofizik Parametreleri:
			var gal_rng := RandomNumberGenerator.new()
			gal_rng.seed = gal_seed
			
			var morph_roll := gal_rng.randf()
			var morph_type := 0 # 0: Spiral, 1: Elliptical, 2: Irregular, 3: Lenticular
			var num_arms := 2.0
			var arm_param := 1.0
			var diameter_ly := 75000.0
			var base_tint := Color.WHITE
			
			if morph_roll < 0.65:
				# Sarmal Galaksi (Spiral)
				morph_type = 0
				diameter_ly = gal_rng.randf_range(55000.0, 140000.0)
				num_arms = 2.0 if gal_rng.randf() < 0.70 else 4.0
				arm_param = gal_rng.randf_range(0.8, 1.6) # Kol kıvrım/pitch açısı faktörü
				base_tint = Color(0.85, 0.92, 1.0).lerp(Color(1.0, 0.90, 0.75), gal_rng.randf() * 0.4)
			elif morph_roll < 0.85:
				# Eliptik Galaksi (Elliptical)
				morph_type = 1
				diameter_ly = gal_rng.randf_range(40000.0, 220000.0)
				arm_param = gal_rng.randf_range(0.45, 1.0) # Basıklık oranı (E0 - E7)
				num_arms = 0.0
				base_tint = Color(1.0, 0.84, 0.58)
			elif morph_roll < 0.94:
				# Düzensiz Galaksi (Irregular)
				morph_type = 2
				diameter_ly = gal_rng.randf_range(12000.0, 35000.0)
				num_arms = 1.0
				arm_param = gal_rng.randf_range(0.5, 1.2)
				base_tint = Color(0.70, 0.85, 1.0)
			else:
				# Merceksi Galaksi (Lenticular)
				morph_type = 3
				diameter_ly = gal_rng.randf_range(60000.0, 120000.0)
				num_arms = 0.0
				arm_param = 0.8
				base_tint = Color(0.96, 0.90, 0.78)
				
			morphologies[index] = morph_type
			diameters[index] = diameter_ly
			
			# 3. Kozmolojik Kırmızıya Kayma (Cosmological Redshift):
			# Hubble kanunu uyarınca uzak mesafelerdeki galaksilerin ışığı kırmızıya kayar
			var z_dist := clampf(cand_dist / 50000000.0, 0.0, 1.0)
			var redshift_tint := Color(1.0, 0.75, 0.52)
			var final_tint := base_tint.lerp(redshift_tint, z_dist * 0.45)
			
			# Görsel parlaklık ve görünür büyüklük
			var prominence := pow(gal_rng.randf(), 3.5)
			var brightness := 0.75 + prominence * 1.85
			
			var local := gal_pos_abs - anchor
			var offset := i * 20
			
			# MultiMesh Row-Major 3x4 Transform (Birim matris)
			buffer[offset] = 1.0
			buffer[offset + 5] = 1.0
			buffer[offset + 10] = 1.0
			
			# INSTANCE_COLOR (RGBA Renk ve Parlaklık)
			buffer[offset + 12] = final_tint.r * brightness
			buffer[offset + 13] = final_tint.g * brightness
			buffer[offset + 14] = final_tint.b * brightness
			buffer[offset + 15] = 1.0
			
			# INSTANCE_CUSTOM (Galaksi Konumu ve Morfoloji)
			# xyz: Anchor noktasına göre yerel koordinat (LY)
			# w: Galaksi Yarıçapı (LY) / 10000.0 (Kompakt paketleme)
			buffer[offset + 16] = local.x
			buffer[offset + 17] = local.y
			buffer[offset + 18] = local.z
			buffer[offset + 19] = float(morph_type) + (clampf(diameter_ly / 200000.0, 0.05, 1.0) * 0.1)
			
			index += 1
			
		buffers.append(buffer)
		
	return {
		"region": region,
		"anchor": anchor,
		"positions": positions,
		"seeds": seeds,
		"morphologies": morphologies,
		"diameters": diameters,
		"buffers": buffers,
		"generation_usec": Time.get_ticks_usec() - started
	}
