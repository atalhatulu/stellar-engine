extends SceneTree
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var scene = load("res://scenes/main_star.tscn").instantiate()
	scene.seed_value = 424243
	scene.enable_mid_field = false
	scene.enable_deep_field = false
	root.add_child(scene)
	scene.set_process(false)
	var player: Player = scene.camera
	player.set_process(false)
	var sc: Spacecraft = scene.spacecraft
	sc.current_view_mode = Spacecraft.CameraViewMode.INTERIOR_FPS
	sc.is_seated_in_cockpit = false
	sc.global_basis = Basis.from_euler(Vector3(0.2, 0.8, -0.4))
	sc.cabin_player_yaw = deg_to_rad(175.0)
	player._update_camera_view(true)
	# Cross +/-180 repeatedly, including a pitched/rolled ship frame.
	for degree in range(176, 550):
		var before := player.camera_node.global_basis.get_rotation_quaternion()
		sc.cabin_player_yaw = deg_to_rad(float(degree))
		player._update_camera_view(false, 1.0 / 60.0)
		var after := player.camera_node.global_basis.get_rotation_quaternion()
		check(before.angle_to(after) < deg_to_rad(3.0), "Cabin yaw wrap must never spin the camera")
	# Test real world follow lag, rather than smoothing a child of an instant parent.
	for mode in [Spacecraft.CameraViewMode.THIRD_PERSON, Spacecraft.CameraViewMode.EVA]:
		sc.current_view_mode = mode
		player.eva_third_person = true
		player.global_basis = Basis.IDENTITY
		player.mouse_turn_speed = Vector2.ZERO
		player._update_camera_view(true)
		var before := player.camera_node.global_basis.get_rotation_quaternion()
		player.global_basis = Basis(Vector3.UP, 0.6)
		player._update_camera_view(false, 1.0 / 60.0)
		var angle := before.angle_to(player.camera_node.global_basis.get_rotation_quaternion())
		check(angle > 0.01 and angle < 0.3, "Ship and EVA cameras must lag behind parent turns")
		player._update_camera_view(false, 2.0)
		var settled := player.camera_node.global_basis.get_rotation_quaternion()
		player._update_camera_view(true)
		check(settled.angle_to(player.camera_node.global_basis.get_rotation_quaternion()) < 0.005, "Follow camera must converge")
	# Walking should have a small positional follow delay, then converge.
	sc.current_view_mode = Spacecraft.CameraViewMode.INTERIOR_FPS
	sc.cabin_player_pos = Vector3(0,1.55,0)
	player._update_camera_view(true)
	sc.cabin_player_pos.z = 0.5
	player._update_camera_view(false, 1.0 / 60.0)
	var remaining := player.camera_node.global_position.distance_to(sc.to_global(sc.cabin_player_pos))
	check(remaining > 0.1 and remaining < 0.5, "Cabin camera must gently follow walking")
	# Simulate both keyboard and mouse input through the actual EVA controller.
	scene.is_eva_active = true
	sc.current_view_mode = Spacecraft.CameraViewMode.EVA
	for keycode in [KEY_W, KEY_A, KEY_S, KEY_D]:
		var key := InputEventKey.new()
		key.keycode = keycode
		key.pressed = true
		Input.parse_input_event(key)
		var mouse := InputEventMouseMotion.new()
		mouse.relative = Vector2(24, -16)
		player._input(mouse)
		player._process(1.0 / 60.0)
		check(sc.engines_root.rotation.is_zero_approx(), "EVA WASD and look must not swivel ship engines")
		check(not sc.left_thruster_flame.visible and sc.thruster_light.light_energy == 0.0, "Parked ship exhaust must be off")
		var release := key.duplicate() as InputEventKey
		release.pressed = false
		Input.parse_input_event(release)
	# A stale caller cannot reactivate the engines with direct steering input.
	sc.update_spacecraft(0.1, Vector3.ONE, true, true, Vector2(50,50))
	check(sc.engines_root.rotation.is_zero_approx() and not sc.left_thruster_flame.visible, "Ship must reject unowned propulsion input")
	scene.is_eva_active = false
	sc.is_seated_in_cockpit = true
	sc.current_view_mode = Spacecraft.CameraViewMode.THIRD_PERSON
	sc.update_spacecraft(0.1, Vector3.FORWARD, false, false, Vector2(5,5))
	check(not sc.engines_root.rotation.is_zero_approx() and sc.left_thruster_flame.visible, "Piloting must restore engine steering")
	check(not scene.has_node("Control/Crosshair"), "Legacy duplicate crosshair must be removed")
	check(scene.hud.visor_overlay.mouse_filter == Control.MOUSE_FILTER_IGNORE, "HUD crosshair must not intercept input")
	
	# C Odaklanma ve Odak Kilidini Otomatik/Manuel Bozma Testleri
	scene.is_focusing_target = false
	scene.current_target_index = 0 if scene.universe.size() > 0 else -1
	scene._handle_focus_key()
	check(scene.is_focusing_target, "C tuşu hedefe odaklanmayı başlatmalı")
	
	# Hedefe yönelme simülasyonu (yeterli kare sonra odaklanma tamamlanıp kilit otomatik çözülmeli)
	for i in range(40):
		scene._process(0.016)
	check(not scene.is_focusing_target, "Hedefe yönelme tamamlandıktan sonra odak kilidi otomatik olarak kaldırılmalı")
	
	# Manuel fare hareketi ile odağın anında bozulması testi
	scene._handle_focus_key()
	check(scene.is_focusing_target, "Odaklanma tekrar başlatıldı")
	var move_event := InputEventMouseMotion.new()
	move_event.relative = Vector2(5.0, 3.0)
	player._input(move_event)
	check(not scene.is_focusing_target, "Fare hareketi odaklanmayı anında bozmalı")
	
	# Tekrar C'ye basarak odağın bozulması (toggle) testi
	scene._handle_focus_key()
	check(scene.is_focusing_target, "Odaklanma 3. kez başlatıldı")
	scene._handle_focus_key()
	check(not scene.is_focusing_target, "İkinci C basımı odaklanmayı anında bozmalı")
	
	# 3. Şahıs Kamera Zoom ve Crosshair Konum Testleri
	sc.current_view_mode = Spacecraft.CameraViewMode.THIRD_PERSON
	player.third_person_distance = 14.0
	player._update_camera_view(true)
	var initial_dist = player.third_person_distance
	
	# Fare tekerleği yukarı (zoom in - yaklaşma)
	var wheel_up := InputEventMouseButton.new()
	wheel_up.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel_up.pressed = true
	player._input(wheel_up)
	check(player.third_person_distance < initial_dist, "Fare tekerleği yukarı kaydırıldığında 3. şahıs kamera yaklaşmalı")
	
	# Fare tekerleği aşağı (zoom out - uzaklaşma)
	var wheel_down := InputEventMouseButton.new()
	wheel_down.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel_down.pressed = true
	player._input(wheel_down)
	player._input(wheel_down)
	check(player.third_person_distance > initial_dist, "Fare tekerleği aşağı kaydırıldığında 3. şahıs kamera uzaklaşmalı")
	
	# Shift + Fare tekerleği ile hız kademesi değişmeli
	var initial_speed_idx = player.speed_multiplier_index
	var shift_wheel := InputEventMouseButton.new()
	shift_wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	shift_wheel.pressed = true
	shift_wheel.shift_pressed = true
	player._input(shift_wheel)
	check(player.speed_multiplier_index == initial_speed_idx + 1, "Shift + Fare tekerleği hız kademesini artırmalı")
	
	# [ ve ] tuşları ile hız kademesi değişmeli
	var bracket_left := InputEventKey.new()
	bracket_left.keycode = KEY_BRACKETLEFT
	bracket_left.pressed = true
	player._input(bracket_left)
	check(player.speed_multiplier_index == initial_speed_idx, "[ tuşu hız kademesini düşürmeli")
	
	# Kamera yüksekliği ve nişangâh hattının gemi gövdesinin üstünde kalması testi
	player.third_person_distance = 14.0
	player._update_camera_view(true)
	var cam_pos = player.camera_node.position
	# Gemi tavanı Y ~ 1.8m iken kamera en az 3.0m yüksekte olmalı
	check(cam_pos.y > 3.0, "3. şahıs kamerası geminin üstünden gökyüzünü görecek yükseklikte olmalı")
	# Gemi burnu Z ~ -6.0m civarında iken kamera bakış ışını gemi burnunun üstünden geçmeli
	var cam_forward = -player.camera_node.basis.z
	var ray_y_at_nose = cam_pos.y + (cam_forward.y / -cam_forward.z) * (cam_pos.z - (-6.0))
	check(ray_y_at_nose > 2.0, "Nişangâh (crosshair) geminin burnunun en az 20 cm üstünden ufka bakmalı")
	
	# followed_body aktifken fare dönüşünün kilitlenmediği testi
	scene.followed_body = scene.active_star
	var rot_before = player.rot_y
	var mouse_turn := InputEventMouseMotion.new()
	mouse_turn.relative = Vector2(30.0, 10.0)
	player._input(mouse_turn)
	check(player.rot_y != rot_before, "followed_body aktifken fare hareketi rotasyonu değiştirebilmeli (kilitlenmemeli)")
	var rot_after_input = player.rot_y
	scene._process(0.016)
	check(absf(player.rot_y - rot_after_input) < 0.05, "followed_body kare güncellemesi kamerayı zorla kitlememeli")
	scene.followed_body = null
	
	# Otopilot sırasında farenin bariz hareketi ile otopilotun iptal edilmesi testi
	scene.is_autopilot_active = true
	var break_autopilot := InputEventMouseMotion.new()
	break_autopilot.relative = Vector2(10.0, 5.0)
	player._input(break_autopilot)
	check(not scene.is_autopilot_active, "Otopilot sırasında fare hareketi otopilotu iptal etmeli")
	
	# 2500+ LY aşırı yüksek hızlarda 32-bit float taşma (INF / NaN) güvenliği testi
	for high_speed_ly in [2500.0, 10000.0, 50000.0, 100000.0]:
		var test_speed_mps = high_speed_ly * 9460730472580800.0
		var test_vel = Vector3(0.0, 0.0, -test_speed_mps)
		var safe_len = scene.safe_vector_length(test_vel)
		check(is_finite(safe_len), "Yüksek hız (%f LY) safe_vector_length taşma yapmamalı" % high_speed_ly)
		var safe_norm = scene.safe_vector_normalized(test_vel)
		check(is_finite(safe_norm.z) and absf(safe_norm.z + 1.0) < 0.001, "Yüksek hız normalize vektörü geçerli olmalı")
	
	# Gezegene İniş, Yerçekimi Doğrultusu ve Sağ-El Matris Testleri
	var test_planet: CelestialBody = null
	for body in scene.universe:
		if body.type == "PLANET":
			test_planet = body
			break
	if test_planet != null:
		scene._execute_landing(test_planet)
		var landed_basis = scene.landed_ship_basis
		check(landed_basis.determinant() > 0.99, "İniş basis determinantı pozitif (+1.0 sağ el) olmalı, asla aynalanmamalı")
		var expected_up = (scene.virtual_player_position - test_planet.get_absolute_position(scene.active_star)).normalized()
		check(landed_basis.y.dot(expected_up) > 0.95, "Geminin ve kameranın tavanı gezegenin yerel yerçekimi tersine (yukarı) bakmalı")
		check(sc.global_basis.y.dot(expected_up) > 0.95, "Uzay gemisi gezegen yüzeyinde ters dönmemeli, dik basmalı")
		
		# Kalkış testi
		scene._launch_from_planet()
		check(not scene.is_landed, "Gezegenden kalkış başarılı olmalı")
		
		# C vs G Flyover LOD Tutarlılık Testi (Uzaktayken görsel mesh ve atmosfer kapanmamalı)
		scene.is_focusing_target = true
		scene.focus_target_body = test_planet
		test_planet.real_position = Vector3(0.0, 0.0, test_planet.real_radius * 20.0) # Uzak mesafe
		scene._flv_update_flyover_lod()
		check(scene.sphere_chunk_manager == null, "Uzaktayken C odağında chunk LOD açılmamalı, visual mesh ve atmosfer kalmalı")
		
		scene.is_focusing_target = false
		scene.is_autopilot_active = true
		scene.autopilot_target_body = test_planet
		scene._flv_update_flyover_lod()
		check(scene.sphere_chunk_manager == null, "Uzaktayken G otopilotunda da chunk LOD erken açılmamalı, asıl mesh korunmalı")
		check(test_planet.visual_mesh.visible, "Uzaktaki gezegen visual_mesh'i G otopilotunda gizlenmemeli")
		
		# Yaklaşınca pürüzsüz çoklu chunk LOD devreye girmeli ve atmosfer açık kalmalı
		test_planet.real_position = Vector3(0.0, 0.0, test_planet.real_radius * 2.2) # Yakın yörünge
		scene._flv_update_flyover_lod()
		check(scene.sphere_chunk_manager != null, "Gezegene yaklaşıldığında pürüzsüz küresel chunk LOD devreye girmeli")
		if test_planet.atmosphere_mesh != null:
			check(test_planet.atmosphere_mesh.visible, "Yaklaşıldığında yeşil atmosfer halesi daima açık kalmalı")
		scene.is_autopilot_active = false
		scene.autopilot_target_body = null
		scene._flv_clear_chunks()
		
		# İniş yüzey atmosferi ve gökyüzü testi
		scene._execute_landing(test_planet)
		var cam_3d = scene.camera.get_node_or_null("Camera3D")
		if test_planet.has_atmosphere and cam_3d and cam_3d.environment:
			check(cam_3d.environment.fog_enabled, "Atmosferli gezegene inildiğinde yerel atmosfer sisi aktif olmalı")
		scene._launch_from_planet()
	
	scene.queue_free()
	await process_frame
	print("CAMERA / CONTROLS REGRESSION: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)
