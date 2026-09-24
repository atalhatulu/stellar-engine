extends SceneTree

const PlanetChunkSphere = preload("res://scripts/rendering/planet_chunk_sphere.gd")

var failures := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("FAIL: " + message)
	else:
		print("PASS: " + message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	print("--- G/L YAKLAŞMA VE İNİŞ AKIŞI REGRESYON TESTİ BAŞLATILIYOR ---")
	var scene = load("res://main.tscn").instantiate()
	scene.seed_value = 554433
	scene.enable_mid_field = false
	scene.enable_deep_field = false
	root.add_child(scene)
	scene.set_process(false)
	scene._update_active_system_bodies()

	var test_planet: CelestialBody = null
	for b in scene.universe:
		if b.type == "PLANET":
			test_planet = b
			break

	check(test_planet != null, "Aktif sistemde test edilecek gezegen bulunmalı")
	if test_planet == null:
		quit(1)
		return

	# Hedef olarak gezegeni seç
	scene.current_target_index = scene.universe.find(test_planet)

	# 1. G tuşu ile yörünge yaklaşma otopilotunu başlat
	scene._start_autopilot()
	check(scene.is_autopilot_active, "G tuşu hedef gezegene otopilot yaklaşmasını başlatmalı")
	check(scene.autopilot_target_body == test_planet, "Otopilot hedefi seçili gezegen olmalı")

	# Otopilot yaklaşmasını simüle et ve tamamla
	scene.autopilot_timer = scene.autopilot_duration + 0.1
	# 1 kare process adımını manuel işlet
	scene._process(0.016)

	var planet_abs = test_planet.get_absolute_position(scene.active_star)
	var rel_to_planet = scene.virtual_player_position - planet_abs
	var radius_ratio = rel_to_planet.length() / test_planet.real_radius
	check(radius_ratio >= 2.5 and radius_ratio <= 3.5, "G otopilotu oyuncuyu yörünge irtifasına (~3.0R) getirmeli (alınan: %.2fR)" % radius_ratio)

	# 2. Far plane ve 1:1 ölçek kontrolü
	var cam_3d: Camera3D = scene.camera.get_node_or_null("Camera3D")
	check(cam_3d != null and cam_3d.far >= test_planet.real_radius * 4.0, "Kamera far plane mesafesi gezegenin tamamını kapsayacak derinlikte olmalı (far: %.0f, R: %.0f)" % [cam_3d.far if cam_3d else 0.0, test_planet.real_radius])

	# 3. L tuşu ile yüzeye kontrollü inişi başlat
	scene._handle_landing_key()
	check(scene.is_landing_autopilot, "L tuşu yörüngeden yüzeye iniş otopilotunu başlatmalı")

	# İniş alçalmasını tamamla
	scene.autopilot_timer = scene.autopilot_duration + 0.1
	scene._process(0.016)

	check(scene.is_landed, "Alçalma tamamlandığında is_landed durumu aktif olmalı")
	check(scene.landed_body == test_planet, "İniş yapılan gövde hedef gezegen olmalı")
	check(is_instance_valid(scene.sphere_chunk_manager), "İnişte PlanetChunkSphere yöneticisi aktif olmalı")
	check(scene.sphere_chunk_manager.visible, "Yüzeyde küresel arazi LOD'u görünür olmalı")

	# Zemin irtifa kontrolü
	var landed_abs = scene.virtual_player_position - planet_abs
	check(landed_abs.length() >= test_planet.real_radius * 0.99, "Oyuncu yüzeyin üzerinde olmalı, merkeze çökmüş olmamalı")

	# 4. L tuşuna tekrar basarak yüzeyden kalkış yap
	scene._handle_landing_key()
	check(not scene.is_landed, "L tuşuna tekrar basıldığında gezegenden kalkış yapılmalı")
	check(scene.landed_body == null, "Kalkışta landed_body sıfırlanmalı")
	check(scene.player_velocity.length() > 0.0, "Kalkışta dikey itme hızı kazanılmalı")

	scene.queue_free()
	print("--- TEST TAMAMLANDI: HATA SAYISI: %d ---" % failures)
	print("G/L LANDING FLOW REGRESSION: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)
