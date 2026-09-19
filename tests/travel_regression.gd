extends SceneTree
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	scene.seed_value = 424243
	scene.enable_mid_field = false
	scene.enable_deep_field = false
	root.add_child(scene)
	scene.set_process(false)
	scene.camera.set_process(false)
	var sc: Spacecraft = scene.spacecraft
	var last := -1.0
	for speed in [0.0, 10.0, 1000.0, 1e4, 1e6, 1e8, 1e10, 1e13, 1e17]:
		var profile := Spacecraft.travel_profile(speed)
		check(profile.x >= last and profile.x <= 1.0, "Speed response must be monotonic and bounded")
		last = profile.x
	check(Spacecraft.travel_profile(500.0) == Vector2.ZERO, "Local manoeuvres must have no warp effect")
	scene.camera.current_speed = 1e17
	scene.flight_speed_mps = 0.0
	sc.update_spacecraft(1.0, Vector3.ZERO, true, true)
	check(sc.travel_intensity == 0.0, "Warp flag and selected throttle must not imply movement")
	scene.flight_speed_mps = 1e12
	sc.update_spacecraft(0.1, Vector3.FORWARD, false, false)
	check(sc.travel_intensity > 0.0, "Manual high speed must produce trails without warp flag")
	# Gaz (W) kesildiğinde warp efekti oluşmamalı / sönümlenmeli
	sc.update_spacecraft(0.5, Vector3.ZERO, false, false)
	check(sc.travel_intensity < 0.05, "Releasing W must cut warp travel effect")
	var low: float = sc.travel_intensity
	sc.update_travel_effect(0.1, 1e17, true)
	check(sc.travel_intensity > low and sc.travel_intensity < 1.0, "Acceleration must ease in")
	var moving: float = sc.travel_intensity
	sc.update_travel_effect(0.1, 0.0, true)
	check(sc.travel_intensity > 0.0 and sc.travel_intensity < moving, "Stopping must fade, not snap")
	sc.update_travel_effect(3.0, 0.0, true)
	check(not sc.travel_overlay.visible, "Stopped ship must disable effect draw")
	for state in ["is_eva_active", "is_landed", "is_system_map_active"]:
		scene.set(state, true)
		sc.update_spacecraft(0.016, Vector3.ZERO, true, true)
		check(not sc.travel_overlay.visible, "Travel effect must be hidden in " + state)
		scene.set(state, false)
	sc.is_seated_in_cockpit = false
	sc.update_spacecraft(0.016, Vector3.ZERO, true, true)
	check(not sc.travel_overlay.visible, "Cabin walking must suppress trails")
	sc.is_seated_in_cockpit = true
	# Exponential response must be the same after equal real time.
	var results: Array[float] = []
	for fps in [30, 144]:
		sc.travel_intensity = 0.0
		sc.warp_intensity = 0.0
		for frame in range(fps): sc.update_travel_effect(1.0 / fps, 1e17, true)
		results.append(sc.travel_intensity)
	check(absf(results[0] - results[1]) < 0.001, "Effect response must not depend on FPS")
	# Integration: interstellar navigation reports actual speed rather than a stale velocity.
	var stars: Array = scene.sector_manager.loaded_sectors[Vector3i.ZERO]
	scene.targeted_star_data = stars[1]
	scene.is_interstellar_autopilot = true
	scene._process(0.016)
	check(scene.flight_speed_mps > 0.0, "Interstellar autopilot must publish travel speed")
	scene.is_interstellar_autopilot = false
	scene.is_autopilot_active = true
	scene.autopilot_target_body = scene.active_star
	scene.autopilot_duration = 2.0
	scene.autopilot_timer = 0.0
	scene.autopilot_relative_start_pos = Vector3(0,0,1e12)
	scene._process(0.1)
	var start_speed: float = scene.flight_speed_mps
	scene.autopilot_timer = 0.9
	scene._process(0.1)
	check(scene.flight_speed_mps > start_speed, "System autopilot must follow smoothstep acceleration")
	scene.autopilot_timer = 1.9
	scene._process(0.1)
	check(scene.flight_speed_mps < 1.0, "Arrival must have zero travel speed")
	scene.queue_free()
	await process_frame
	print("TRAVEL REGRESSION: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)
