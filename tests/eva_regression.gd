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
	sc.current_view_mode = Spacecraft.CameraViewMode.INTERIOR_FPS
	scene.is_autopilot_active = true
	scene.is_hyper_autopilot = true
	sc.toggle_cockpit_seat()
	check(not scene.is_autopilot_active and not scene.is_hyper_autopilot, "Standing must stop ship navigation")
	scene.start_eva_mode()
	check(not scene.is_eva_active, "Closed airlock must prevent EVA")
	sc.is_airlock_open = true
	sc.airlock_anim_progress = 0.5
	sc.cabin_player_pos = Vector3(0, sc.CABIN_EYE_HEIGHT, 2.3)
	sc.update_cabin_walking(1.0, Vector2(0,1), Vector2.ZERO)
	check(sc.cabin_player_pos.z <= 2.451, "Opening ramp must block walking outside")
	scene.start_eva_mode()
	check(not scene.is_eva_active, "Partially open airlock must prevent EVA")
	sc.airlock_anim_progress = 1.0
	sc.update_cabin_walking(1.0, Vector2(0,1), Vector2.ZERO)
	check(sc.cabin_player_pos.z >= 3.75, "Open ramp must allow exit")
	scene.virtual_player_position = Vector3(1e13, -2e13, 3e13)
	scene.camera._process(0.0)
	check(scene.is_eva_active, "Walking off ramp must start EVA through actual player controller")
	var anchor: Vector3 = scene.ship_eva_world_pos
	var offset: Vector3 = scene.eva_offset
	scene._step_eva_motion(0.1, Vector3.RIGHT, false, false)
	check(scene.eva_offset.distance_to(offset) > 0.01, "Centimetre motion must survive astronomical coordinates")
	check(scene.ship_eva_world_pos == anchor, "EVA must not move parked ship's universe anchor")
	check(sc.global_position.is_equal_approx(-scene.eva_offset), "Parked ship must track local EVA displacement")
	var fuel: float = scene.astronaut_fuel
	var speed: float = scene.eva_velocity.length()
	scene._step_eva_motion(0.5, Vector3.ZERO, false, false)
	check(is_equal_approx(scene.astronaut_fuel, fuel), "Coasting must not consume fuel")
	check(scene.eva_velocity.length() > speed * 0.8, "EVA must coast when thrust stops")
	scene._step_eva_motion(0.5, Vector3.ZERO, false, true)
	check(scene.eva_velocity.length() < speed * 0.15, "X brake must reduce drift")
	var key := InputEventKey.new()
	key.keycode = KEY_F
	key.pressed = true
	var previous: bool = scene.camera.eva_third_person
	scene.camera._input(key)
	check(scene.camera.eva_third_person != previous, "F must toggle EVA camera")
	scene.eva_offset = Vector3(100,0,0)
	scene._step_eva_motion(0.0, Vector3.ZERO, false, false)
	scene.end_eva_mode()
	check(scene.is_eva_active, "Boarding from far away must be refused")
	scene.eva_offset = scene.ship_eva_basis * Vector3(0,0.7,3.75)
	scene._step_eva_motion(0.0, Vector3.ZERO, false, false)
	scene.end_eva_mode()
	check(not scene.is_eva_active and not sc.is_seated_in_cockpit, "Nearby boarding must return to cabin")
	check(not sc.is_airlock_open and scene.astronaut_fuel == 100.0, "Boarding must close door and recharge")
	check(scene.camera.camera_node.global_position.distance_to(sc.to_global(sc.cabin_player_pos)) < 0.05, "Cabin camera must follow the ship interior")
	var old_mesh = scene.active_star.visual_mesh
	scene.is_eva_active = true
	scene.is_landed = true
	scene.is_hyper_autopilot = true
	scene._generate_universe(424244)
	check(not scene.is_eva_active and not scene.is_landed and not scene.is_hyper_autopilot, "Universe reset must clear travel modes")
	check(sc.is_seated_in_cockpit and not sc.is_airlock_open, "Universe reset must return player to sealed ship")
	check(not is_instance_valid(old_mesh) or old_mesh.is_queued_for_deletion(), "Universe reset must remove old star mesh")
	scene.queue_free()
	await process_frame
	print("EVA REGRESSION: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)
