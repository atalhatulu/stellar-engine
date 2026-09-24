extends SceneTree

var failures := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	print("--- STARFIELD HARİTA VE CİSİM SEÇİMİ REGRESYON TESTİ BAŞLATILIYOR ---")
	var scene = load("res://main.tscn").instantiate()
	scene.seed_value = 12345
	scene.enable_mid_field = false
	scene.enable_deep_field = false
	scene.enable_survey_system = false
	root.add_child(scene)
	scene.set_process(false)

	var hud = scene.hud
	check(hud != null, "HUD sahnede mevcut olmalı")
	check(hud.starfield_card != null, "Starfield bilgi kartı HUD'da tanımlı olmalı")
	check(hud.mini_system_map != null, "Sol üst mini sistem haritası HUD'da tanımlı olmalı")

	# Test 1: Başlangıçta hedef yokken Starfield kartı kapalı olmalı
	hud.update_hud(scene)
	check(not hud.starfield_card.visible, "Başlangıçta hiçbir cisim seçili değilken Starfield kartı gizli olmalı")

	# Test 2: Bir gezegen seçildiğinde Starfield kartı açılmalı ve bilgileri doldurulmalı
	scene._update_active_system_bodies()
	var test_planet: CelestialBody = null
	var planet_idx := -1
	for i in range(scene.universe.size()):
		var b = scene.universe[i]
		if b.type == "PLANET":
			test_planet = b
			planet_idx = i
			break

	check(test_planet != null, "Sistemde en az bir gezegen bulunmalı")
	scene.current_target_index = planet_idx
	hud.update_hud(scene)

	check(hud.starfield_card.visible, "Gezegen seçildiğinde Starfield bilgi kartı görünür olmalı")
	check(hud.lbl_sf_name.text == test_planet.name.to_upper(), "Starfield kartı seçilen gezegenin adını göstermeli")
	check(hud.sf_row_labels.has("TİP") and hud.sf_row_labels["TİP"].text.length() > 0, "Gezegen tipi bilgisi dolu olmalı")
	check(hud.sf_row_labels.has("YERÇEKİMİ") and hud.sf_row_labels["YERÇEKİMİ"].text.ends_with("G"), "Yerçekimi 'G' birimiyle listelenmeli")
	check(hud.sf_row_labels.has("SICAKLIK") and hud.sf_row_labels["SICAKLIK"].text.length() > 0, "Sıcaklık bilgisi dolu olmalı")
	check(hud.sf_row_labels.has("ATMOSFER") and hud.sf_row_labels["ATMOSFER"].text.length() > 0, "Atmosfer bilgisi dolu olmalı")
	check(hud.sf_row_labels.has("MANYETİK ALAN") and hud.sf_row_labels["MANYETİK ALAN"].text.length() > 0, "Manyetik alan bilgisi dolu olmalı")
	check(hud.sf_row_labels.has("SU") and hud.sf_row_labels["SU"].text.length() > 0, "Su durumu bilgisi dolu olmalı")
	check(hud.sf_row_labels.has("YAŞAM") and hud.sf_row_labels["YAŞAM"].text.length() > 0, "Yaşam bilgisi dolu olmalı")
	check(hud.sf_resources_box.get_child_count() > 0, "Gezegene ait renkli element rozetleri oluşturulmuş olmalı")

	# Test 3: C tuşuna basıldığında hedefin ve odağın boşa düşmesi (kullanıcının isteği)
	scene._handle_focus_key() # 1. basış: hedefe odaklanır
	check(scene.is_focusing_target, "Hedef seçiliyken C tuşuna 1. basış hedefe odaklanmayı başlatmalı")
	scene._handle_focus_key() # 2. basış: seçimi ve odağı boşa düşürmeli
	check(not scene.is_focusing_target, "Tekrar C tuşuna basıldığında odaklanma iptal olmalı")
	check(scene.current_target_index == -1, "Tekrar C tuşuna basıldığında hedef boşa düşmeli (-1)")
	check(scene.targeted_star_data == null, "Hedeflenen galaktik yıldız sıfırlanmalı")

	hud.update_hud(scene)
	check(not hud.starfield_card.visible, "Hedef boşa düştükten sonra Starfield bilgi kartı kapanmalı")

	# Test 4: Ekrandaki cisme tıklayarak seçim yapılması (_select_body_at_screen_pos)
	var cam_3d = scene.camera.get_node_or_null("Camera3D")
	var vp = scene.get_viewport()
	var vp_center = vp.get_visible_rect().size * 0.5 if vp != null else Vector2(576, 324)
	var cam_fwd = -cam_3d.global_basis.z.normalized()
	test_planet.real_position = cam_fwd * 10000000.0
	var sel_ok = scene._select_body_at_screen_pos(vp_center)
	check(sel_ok, "Kameranın önündeki gezegen ekran projeksiyonuyla seçilebilmeli")
	check(scene.current_target_index == planet_idx, "Ekran seçimi doğru gezegen indeksini atamalı")

	# Test 5: Sistem Haritası (M Tuşu) - Starfield İzometrik Perspektifi ve Mini Harita
	scene._toggle_system_map()
	check(scene.is_system_map_active, "M tuşu sistem haritasını açmalı")
	check(absf(scene.camera.rot_x - deg_to_rad(-52.0)) < 0.01, "Harita kamera açısı Starfield izometrik (~52 derece) olmalı")

	hud.update_hud(scene)
	check(hud.mini_system_map.visible, "Sistem haritasında sol üst mini şema görünür olmalı")
	check(not hud.flight_card.visible, "Sistem haritasında uçuş telemetrisi gizlenmeli")

	# Harita Zoom Testi
	var dist_before = (scene.virtual_player_position - scene.active_star.get_absolute_position(scene.active_star)).length()
	scene._zoom_system_map(true) # Zoom in
	var dist_after_in = (scene.virtual_player_position - scene.active_star.get_absolute_position(scene.active_star)).length()
	check(dist_after_in < dist_before, "Fare tekerleği yukarı haritada yakınlaşmalı (zoom in)")

	scene._zoom_system_map(false) # Zoom out
	scene._zoom_system_map(false)
	var dist_after_out = (scene.virtual_player_position - scene.active_star.get_absolute_position(scene.active_star)).length()
	check(dist_after_out > dist_after_in, "Fare tekerleği aşağı haritada uzaklaşmalı (zoom out)")

	# Haritayı kapat
	scene._toggle_system_map()
	check(not scene.is_system_map_active, "M tuşu haritayı kapatmalı")
	hud.update_hud(scene)
	check(not hud.mini_system_map.visible, "Harita kapandığında mini şema gizlenmeli")

	scene.queue_free()
	await process_frame
	print("--- TEST TAMAMLANDI: HATA SAYISI: %d ---" % failures)
	print("STARFIELD MAP & SELECTION REGRESSION: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)
