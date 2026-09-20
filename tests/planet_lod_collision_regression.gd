extends SceneTree

const PlanetChunkSphere = preload("res://scripts/rendering/planet_chunk_sphere.gd")

var failures := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	print("--- GEZEGEN LOD VE YÜZEY ÇARPIŞMA REGRESYON TESTİ BAŞLATILIYOR ---")
	var scene = load("res://scenes/main_star.tscn").instantiate()
	scene.seed_value = 98765
	scene.enable_mid_field = false
	scene.enable_deep_field = false
	root.add_child(scene)
	scene.set_process(false)

	var test_planet: CelestialBody = null
	for b in scene.universe:
		if b.type == "PLANET":
			test_planet = b
			break

	check(test_planet != null, "Sistemde test edilecek gezegen bulunmalı")

	# Test 1: Gezegene doğru son sürat uçulduğunda içine girmeyi engelleyen irtifa koruması
	var planet_abs_pos = test_planet.get_absolute_position(scene.active_star)
	# Oyuncuyu tam gezegenin merkezine (yarıçapın içine) zorla koymayı deneyelim
	scene.virtual_player_position = planet_abs_pos + Vector3(0, test_planet.real_radius * 0.5, 0) # Yarıçapın yarısı (içeride)
	scene.player_velocity = Vector3(0, -1000.0, 0) # İçe doğru hız

	scene._clamp_player_above_planet_surfaces()

	var actual_dist = (scene.virtual_player_position - planet_abs_pos).length()
	var body_noise = test_planet.noise_albedo.noise if (test_planet.noise_albedo and test_planet.noise_albedo.noise) else null
	var expected_surface = test_planet.real_radius * (1.0 + PlanetChunkSphere.sample_terrain_height_static(body_noise, Vector3.UP, test_planet.real_radius))
	check(actual_dist >= expected_surface + 14.9, "İrtifa koruması oyuncunun gezegenin içine girmesini engellemeli ve yüzey üstünde tutmalı")
	check(scene.player_velocity.y >= 0.0, "Yüzeye doğru olan içe dalış hızı sıfırlanmalı/sönümlenmeli")

	# Test 2: PlanetChunkSphere Çoklu Çözünürlük ve Çift Taraflı Render Testi
	var sphere_lod = PlanetChunkSphere.new()
	scene.add_child(sphere_lod)
	sphere_lod.initialize(null, test_planet.real_radius)
	
	var mat = StandardMaterial3D.new()
	sphere_lod.set_material(mat)
	check(mat.cull_mode == BaseMaterial3D.CULL_DISABLED, "Görsel bugları ve şeffaflaşmayı önlemek için materyal çift taraflı (cull disabled) olmalı")

	# Küresel LOD mesafe formülü testi
	var cam_at_orbit = planet_abs_pos + Vector3(0, test_planet.real_radius * 1.5, 0)
	sphere_lod.update(Vector3.ZERO, Vector3.ZERO, test_planet.real_radius, cam_at_orbit, planet_abs_pos)
	check(sphere_lod._all_chunks.size() >= 24, "En az 24 kök parça oluşturulmuş olmalı")

	# Yakınlaşınca altbölümlere ayrılma testi
	var cam_near_surface = planet_abs_pos + Vector3(0, test_planet.real_radius * 1.05, 0)
	for i in range(10):
		sphere_lod.update(Vector3.ZERO, Vector3.ZERO, test_planet.real_radius, cam_near_surface, planet_abs_pos)
	check(sphere_lod._all_chunks.size() > 24, "Yüzeye yaklaşıldığında parçalar çoklu çözünürlükle detaylanmalı (subdivide olmalı)")

	sphere_lod.queue_free()

	# Test 3: PlanetChunkSphere Tekleştirilmiş Ortak Yüzey Yüksekliği ve İniş Senkronizasyonu
	var test_noise = FastNoiseLite.new()
	test_noise.seed = 1234
	var h0 = PlanetChunkSphere.sample_terrain_height_static(test_noise, Vector3.UP, test_planet.real_radius)
	var h1 = PlanetChunkSphere.sample_terrain_height_static(test_noise, Vector3.RIGHT, test_planet.real_radius)
	check(h0 != h1, "Fraktal arazi yüksekliği farklı küresel koordinatlarda doğal engebeler üretmeli")
	check(absf(h0) < 0.1 and absf(h1) < 0.1, "Yükseklik oranı tanımlanan gerçekçi gezegen topoğrafya sınırında kalmalı")

	# İniş testi
	scene._execute_landing(test_planet)
	check(scene.is_landed, "Gezegene iniş başarılı olmalı")
	check(scene.sphere_chunk_manager != null, "İnişte tekil 360 küresel chunk yöneticisi (sphere_chunk_manager) aktif olmalı")
	check(scene.sphere_chunk_manager.is_ready(), "İniş anında küresel LOD sistemi hazır durumda olmalı")

	# Orta enlem kontrolü: İniş pozisyonunun Y normali kutupta (>0.8) değil, ortada (<=0.35) olmalı
	var rel_landing = (scene.virtual_player_position - planet_abs_pos).normalized()
	check(absf(rel_landing.y) <= 0.35, "İniş gezegenin en tepesine/kutusuna değil, ortasına/ekvatoruna yapılmalı (|Y| <= 0.35 olmalı, alınan: %.2f)" % rel_landing.y)

	# LOD Debug renk modu ve istatistik testi
	var lod_mgr: PlanetChunkSphere = scene.sphere_chunk_manager
	var stats_before = lod_mgr.get_lod_stats()
	check(stats_before.has("total_chunks") and stats_before.has("lod_counts"), "LOD yöneticisi detaylı telemetri istatistikleri sunmalı")
	var color_mode_active = lod_mgr.toggle_debug_colors()
	check(color_mode_active == true, "toggle_debug_colors debug renk modunu etkinleştirmeli")
	check(lod_mgr.debug_color_mode == true, "debug_color_mode bayrağı true olmalı")
	var color_mode_off = lod_mgr.toggle_debug_colors()
	check(color_mode_off == false, "toggle_debug_colors ikinci çağrıda renk modunu kapatmalı")

	var cam_3d = scene.camera.get_node_or_null("Camera3D")
	if cam_3d != null:
		check(cam_3d.near <= 0.3, "Yüzeyde yakın kırpma (near plane) ayak altındaki zemin kesilmesin diye optimize olmalı")

	scene._launch_from_planet()
	check(not scene.is_landed, "Kalkış başarılı olmalı")

	scene.queue_free()
	await process_frame
	print("--- TEST TAMAMLANDI: HATA SAYISI: %d ---" % failures)
	print("PLANET LOD & COLLISION REGRESSION: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)
