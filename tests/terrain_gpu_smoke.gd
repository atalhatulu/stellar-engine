extends SceneTree

# GPU Render & Terrain Visual Test Script
# Generates high-fidelity GPU test screenshots directly to Desktop

func _initialize() -> void:
	call_deferred("run")

func capture(path: String) -> void:
	for i in range(5):
		await process_frame
	await RenderingServer.frame_post_draw
	var img = root.get_texture().get_image()
	if img != null:
		var err = img.save_png(path)
		print("CAPTURED [%s]: status=%d" % [path, err])

func run() -> void:
	print("--- TERRAIN GPU TEST & GÖRSEL DOĞRULAMA BAŞLATILIYOR ---")
	Engine.max_fps = 60
	var scene = load("res://scenes/main.tscn").instantiate()
	scene.seed_value = 424243
	root.add_child(scene)
	
	# Girişleri devre dışı bırak, test kontrolünde ilerle
	scene.set_process_input(false)
	if scene.camera != null:
		scene.camera.set_process_input(false)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	
	# Sistemin ve yıldız alanının oturması için bekle
	for f in range(60):
		await process_frame
		
	# İlk gezegeni bul
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
	
	# ── 1. GÖRÜNTÜ: Gezegene Yaklaşma ve Küresel LOD Dağ Silüeti ──
	print("1. Yaklaşma görünümü hazırlanıyor...")
	# Kamerayı gezegenin 1.25 yarıçapı mesafesine yerleştir
	var approach_pos = planet_abs + Vector3(0, target_planet.real_radius * 0.45, target_planet.real_radius * 1.15)
	scene.virtual_player_position = approach_pos
	scene.camera.transform.origin = Vector3.ZERO
	var look_dir = (planet_abs - approach_pos).normalized()
	scene.camera.look_at(look_dir, Vector3.UP)
	
	# LOD chunk sisteminin hesaplanıp render edilmesi için birkaç kare ilerlet
	for f in range(40):
		await process_frame
		
	await capture("/home/teha/Desktop/terrain_approach.png")
	
	# ── 2. GÖRÜNTÜ: Pürüzsüz İniş ve Kesintisiz Küresel Yüzey ──
	print("2. Pürüzsüz iniş yürütülüyor...")
	scene._execute_landing(target_planet)
	
	for f in range(60):
		await process_frame
		
	await capture("/home/teha/Desktop/terrain_landed.png")
	
	# ── 3. GÖRÜNTÜ: EVA Yüzey Yürüyüşü ve Arazi Detayı ──
	print("3. EVA moduna geçiliyor...")
	var sc: Spacecraft = scene.spacecraft
	if sc != null:
		sc.is_airlock_open = true
		sc.airlock_anim_progress = 1.0
	scene.start_eva_mode()
	if scene.camera != null:
		scene.camera.eva_third_person = true
	
	# Oyuncuyu biraz ileri doğru yürüt
	scene.landed_walk_offset = Vector2(35.0, 20.0)
	for f in range(40):
		await process_frame
		
	await capture("/home/teha/Desktop/terrain_eva.png")
	
	print("--- TERRAIN GPU TESTİ BAŞARIYLA TAMAMLANDI ---")
	quit(0)
