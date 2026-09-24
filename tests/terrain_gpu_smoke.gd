extends SceneTree

# GPU Render & Terrain Visual Test Script
# 1. 45 km Debug Displacement (Displacement doğrulaması, uzaydan heybetli dağ silüetleri)
# 2. 12 km Normal Kayalık Gezegen (Gündüz tarafı yaklaşma, pürüzsüz iniş, vadi ve tepecikler, EVA)

const PlanetChunkSphere = preload("res://scripts/rendering/planet_chunk_sphere.gd")

func _initialize() -> void:
	call_deferred("run")

func capture(path: String) -> void:
	for i in range(12):
		await process_frame
	if DisplayServer.get_name() == "headless":
		print("CAPTURED [%s]: headless skipped" % path)
		return
	await RenderingServer.frame_post_draw
	var img = root.get_texture().get_image()
	if img != null:
		var err = img.save_png(path)
		print("CAPTURED [%s]: status=%d" % [path, err])

func run() -> void:
	print("--- TERRAIN GPU TEST & GÖRSEL DOĞRULAMA BAŞLATILIYOR ---")
	Engine.max_fps = 60
	var scene = load("res://main.tscn").instantiate()
	scene.seed_value = 424243
	root.add_child(scene)
	
	scene.set_process_input(false)
	if scene.camera != null:
		scene.camera.set_process_input(false)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	
	scene._update_active_system_bodies()
	for f in range(60):
		await process_frame
		
	var target_planet: CelestialBody = null
	for b in scene.universe:
		if b.type == "PLANET":
			target_planet = b
			break
			
	if target_planet == null:
		print("HATA: Gezegen bulunamadı!")
		quit(1)
		return

	var planet_abs = target_planet.get_absolute_position(scene.active_star)
	
	# Gezegenin güneşe bakan aydınlık tarafının normali
	var sun_face_dir = (-planet_abs).normalized()
	var sunlit_dir = (sun_face_dir + Vector3(0.18, 0.38, 0.22)).normalized()
	
	# ═════════════════════════════════════════════════════════════════════════
	# BÖLÜM 1: 45 KM DEBUG DISPLACEMENT DOĞRULAMASI (Genişletilmiş Dağ Silüeti)
	# ═════════════════════════════════════════════════════════════════════════
	print("\n>>> BÖLÜM 1: 45 km Debug Displacement Test Ediliyor...")
	PlanetChunkSphere.debug_elevation_override_km = 45.0
	
	var orbit_pos = planet_abs + sunlit_dir * (target_planet.real_radius * 1.08)
	scene.virtual_player_position = orbit_pos
	scene.camera.transform.origin = Vector3.ZERO
	var look_dir_debug = (planet_abs - orbit_pos).normalized()
	scene.camera.look_at(look_dir_debug, Vector3.UP)
	
	if is_instance_valid(scene.sphere_chunk_manager):
		scene.sphere_chunk_manager.queue_free()
		scene.sphere_chunk_manager = null
	scene._flv_update_flyover_lod()
	for f in range(50):
		await process_frame
		
	await capture("/home/teha/Desktop/terrain_debug_45km_approach.png")
	
	# ═════════════════════════════════════════════════════════════════════════
	# BÖLÜM 2: 12 KM NORMAL KAYALIK GEZEGEN VE ALTITUDE/SLOPE SHADER
	# ═════════════════════════════════════════════════════════════════════════
	print("\n>>> BÖLÜM 2: 12 km Normal Kayalık Gezegen Test Ediliyor...")
	PlanetChunkSphere.debug_elevation_override_km = 0.0 # Varsayılan 12 km
	PlanetChunkSphere.elevation_scale_km = 12.0
	
	# 1. Uzaydan Yaklaşma ve Heybetli Dağ Silüeti
	print("1. Normal yaklaşma görünümü hazırlanıyor...")
	var approach_pos = planet_abs + sunlit_dir * (target_planet.real_radius * 1.12)
	scene.virtual_player_position = approach_pos
	scene.camera.transform.origin = Vector3.ZERO
	var look_dir = (planet_abs - approach_pos).normalized()
	scene.camera.look_at(look_dir, Vector3.UP)
	
	if is_instance_valid(scene.sphere_chunk_manager):
		scene.sphere_chunk_manager.queue_free()
		scene.sphere_chunk_manager = null
	scene._flv_update_flyover_lod()
	for f in range(50):
		await process_frame
		
	await capture("/home/teha/Desktop/terrain_approach.png")
	
	# 2. Pürüzsüz İniş ve 360° Kesintisiz Küresel Yüzey
	print("2. Pürüzsüz iniş yürütülüyor...")
	# Oyuncuyu güneşe bakan gündüz tarafına konumlandırıp inişi yürüt
	scene.virtual_player_position = planet_abs + sunlit_dir * (target_planet.real_radius * 1.05)
	scene._execute_landing(target_planet)
	
	# Kamerayı zemin ve ufku tam karşıdan görecek açıya ayarla
	if scene.camera != null:
		scene.camera.rot_x = deg_to_rad(-8.0)
		scene.camera.rot_y = deg_to_rad(25.0)
		scene.camera._update_camera_view(true)
	
	for f in range(60):
		await process_frame
		
	await capture("/home/teha/Desktop/terrain_landed.png")
	
	# 3. Serbest kamera ile onlarca metre ölçekli arazi detayı
	print("3. Serbest kamera yüzey görünümüne geçiliyor...")
	if scene.camera != null:
		scene.camera.rot_x = deg_to_rad(-8.0)
		scene.camera.rot_y = deg_to_rad(45.0)
	
	# Oyuncuyu arazi boyunca biraz yürüt
	scene.landed_walk_offset = Vector2(85.0, 55.0)
	for f in range(50):
		await process_frame
		
	await capture("/home/teha/Desktop/terrain_free_camera.png")
	
	print("--- TERRAIN GPU TESTİ BAŞARIYLA TAMAMLANDI ---")
	quit(0)
