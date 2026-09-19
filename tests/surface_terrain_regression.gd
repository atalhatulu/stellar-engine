extends SceneTree

const PlanetSurfaceProfile = preload("res://scripts/terrain/planet_surface_profile.gd")
const PlanetHeightSampler = preload("res://scripts/terrain/planet_height_sampler.gd")
const SurfaceChunkJob = preload("res://scripts/terrain/surface_chunk_job.gd")
const PlanetSurfaceManager = preload("res://scripts/terrain/planet_surface_manager.gd")
const SurfaceWalker = preload("res://scripts/core/surface_walker.gd")

var failures := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("FAIL: " + message)
		print("FAIL: ", message)
	else:
		print("PASS: ", message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	print("--- GEZEGEN YÜZEYİ VE 3D ARAZİ REGRESYON TESTİ BAŞLATILIYOR ---")
	
	# 1. Aşama: Profil ve Parametre Kontrolleri
	var moon_prof := PlanetSurfaceProfile.new()
	moon_prof.seed_value = 424243
	moon_prof.moon = true
	moon_prof.gravity = 1.62
	check(moon_prof.moon and is_equal_approx(moon_prof.gravity, 1.62), "Uydu yüzey profili ayarları geçerli")
	
	# 2. Aşama: Deterministik Yükseklik ve Eğim Örnekleyicisi
	var sampler1 := PlanetHeightSampler.new(moon_prof, Vector3.UP)
	var sampler2 := PlanetHeightSampler.new(moon_prof, Vector3.UP)
	var h1 := sampler1.height_local(24.5, -42.8)
	var h2 := sampler2.height_local(24.5, -42.8)
	check(is_equal_approx(h1, h2), "Aynı tohum ve koordinat birebir aynı yüksekliği üretir")
	
	var norm := sampler1.normal_local(0.0, 0.0)
	check(is_equal_approx(norm.length(), 1.0) and norm.y > 0.7, "Yüzey normali normalize ve yukarı yönlü")
	
	var site := sampler1.find_landing_site()
	check(site.x != INF and site.y != INF, "Emniyetli iniş alanı bulundu")
	check(sampler1.landing_suitable(site.x, site.y), "Bulunan iniş alanı eğim ve düzlük sınırlarına uygun (<12 derece)")
	
	# 3. Aşama: Yüzey Parçası ve Üçgen Sarım Yönü (CCW)
	var job := SurfaceChunkJob.new()
	var chunk_data := job.build(moon_prof, Vector3.UP, Vector2i(0, 0), 64, Vector4i(2, 2, 2, 2))
	check(not chunk_data.is_empty(), "LOD0 arazi parçası başarıyla üretildi")
	
	var verts: PackedVector3Array = chunk_data["vertices"]
	var indices: PackedInt32Array = chunk_data["indices"]
	var faces: PackedVector3Array = chunk_data["faces"]
	check(verts.size() == 65 * 65, "64 bölmeli LOD0 için tepe noktası sayısı 4225")
	check(indices.size() == 64 * 64 * 6, "64 bölmeli LOD0 için indeks sayısı 24576")
	check(faces.size() == indices.size(), "Fizik çarpışma üçgenleri (faces) üretildi")
	
	# Üçgen yönelimi (Front-face CCW / Normal +Y kontrolü)
	var v0 := verts[indices[0]]
	var v1 := verts[indices[1]]
	var v2 := verts[indices[2]]
	var tri_normal := (v1 - v0).cross(v2 - v0).normalized()
	check(tri_normal.y > 0.0, "Üçgen sarım yönü (CCW) ve normali doğru: +Y yukarı bakıyor (cull_back hatasız)")

	# 4. Aşama: Yüzey Yöneticisi ve Fizik Çarpışma Ağı
	var surface_mgr := PlanetSurfaceManager.new(moon_prof, Vector3.UP)
	root.add_child(surface_mgr)
	surface_mgr.build_surface(1)
	check(surface_mgr.chunks.size() == 9, "3x3 parçalık (grid_radius=1) 9 adet arazi parçası oluşturuldu")
	check(surface_mgr.static_bodies.has("0,0"), "Merkez parçanın fiziksel çarpışma gövdesi (StaticBody3D) eklendi")
	
	# 5. Aşama: Karakter Yürüyüş Fiziği (CharacterBody3D)
	var walker := SurfaceWalker.new()
	walker.configure_for_profile(moon_prof)
	root.add_child(walker)
	walker._setup_nodes()
	
	# Fizik sunucusunun çarpışma şekillerini kaydetmesini bekle
	await physics_frame
	await physics_frame
	
	# Karakteri merkez parçanın ortasına yerleştir (x=64, z=64)
	var center_h := surface_mgr.get_height(64.0, 64.0)
	walker.position = Vector3(64.0, center_h + 0.5, 64.0)
	
	# Yerçekimi altında düşme ve zemine temas simülasyonu
	for frame in range(60):
		walker.step(0.016, Vector2.ZERO, false, false, false)
		await physics_frame
		if frame == 0 or frame == 30 or frame == 59:
			print("Frame ", frame, " pos: ", walker.position, " vel: ", walker.velocity, " floor: ", walker.is_on_floor())
	
	check(walker.is_on_floor(), "Karakter ay uydusu yerçekimiyle zemine başarıyla indi ve zemin temasını algıladı")
	check(walker.position.y >= center_h - 0.2, "Karakter 3D engebeli arazinin içine gömülmedi")
	
	# Zemin üzerinde ileri yürüme simülasyonu
	var prev_pos := walker.position
	for frame in range(30):
		walker.step(0.016, Vector2(0.0, 1.0), false, false, false)
		await physics_frame
	
	check(walker.position.z > prev_pos.z + 1.0, "Karakter engebeli yüzey üzerinde WASD ile ilerledi")
	check(walker.is_on_floor(), "Karakter yürürken zemin temasını korudu")
	
	# Zıplama simülasyonu
	walker.step(0.016, Vector2.ZERO, false, true, false)
	await physics_frame
	check(walker.velocity.y > 0.0, "Karakter zıpladı (yukarı yönlü hız kazandı)")
	
	# Jetpack testi
	walker.velocity.y = 0.0
	walker.position.y += 1.0 # Havada
	var initial_fuel := walker.jetpack_fuel
	walker.step(0.016, Vector2.ZERO, false, false, true)
	check(walker.is_jetpack_active, "Havada Space ile jetpack itişi aktif oldu")
	check(walker.jetpack_fuel < initial_fuel, "Jetpack kullanımı yakıt tüketti")
	
	# Temizlik
	walker.queue_free()
	surface_mgr.queue_free()
	
	print("--- TEST TAMAMLANDI: HATA SAYISI: ", failures, " ---")
	if failures == 0:
		print("SURFACE TERRAIN REGRESSION: PASS")
		quit(0)
	else:
		print("SURFACE TERRAIN REGRESSION: FAIL")
		quit(1)
