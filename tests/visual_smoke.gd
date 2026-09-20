extends SceneTree

# Real-renderer smoke test and review images. Headless tests use streaming_regression.gd.
func _initialize() -> void:
	call_deferred("run")

func capture(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/star-system-%s.png" % name)
	print("VISUAL CAPTURE: ", name)

func run() -> void:
	Engine.max_fps = 60
	var scene = load("res://scenes/main_star.tscn").instantiate()
	scene.seed_value = 424243
	root.add_child(scene)
	scene.set_process_input(false)
	scene.camera.set_process_input(false)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	var deadline := Time.get_ticks_msec() + 12000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if scene.mid_field_renderer.star_logical_positions_ly.size() > 0 and scene.deep_field_renderer.star_logical_positions_ly.size() > 0 and scene.deep_field_renderer._fade >= 1.0:
			break
	await capture("visual")
	scene.set_process(false)
	scene.camera.set_process(false)
	scene.is_hud_visible = false
	scene.hud.visible = false
	scene.get_node("Control").visible = false
	var sc: Spacecraft = scene.spacecraft
	var cam: Camera3D = scene.camera.camera_node
	sc.visible = false
	await capture("space")
	sc.visible = true
	cam.global_position = sc.global_position + Vector3(6,3.7,7.5)
	cam.look_at(sc.global_position + Vector3(0,0.5,0),Vector3.UP)
	await capture("exterior")
	sc.current_view_mode = Spacecraft.CameraViewMode.INTERIOR_FPS
	sc.is_seated_in_cockpit = true
	sc.cabin_player_pos = sc.PILOT_SEAT_POS
	cam.near = 0.04
	scene.camera._update_camera_view(true)
	await capture("cockpit")
	scene.flight_speed_mps = 299792458.0 * 100000.0
	for frame in range(90):
		sc.update_spacecraft(1.0 / 60.0, Vector3.FORWARD, true, true)
		scene.camera._update_camera_view(false, 1.0 / 60.0)
		await process_frame
	await capture("travel")
	scene.flight_speed_mps = 0.0
	sc.update_spacecraft(5.0, Vector3.ZERO, false, false)
	sc.toggle_cockpit_seat()
	sc.cabin_player_pos = Vector3(0,sc.CABIN_EYE_HEIGHT,1.9)
	scene.camera._update_camera_view(true)
	await capture("cabin")
	sc.is_airlock_open = true
	sc.airlock_anim_progress = 1.0
	sc.update_spacecraft(0.016,Vector3.ZERO,false,false)
	sc.cabin_player_pos = Vector3(0,0.70,3.75)
	scene.start_eva_mode()
	scene.eva_offset = Vector3(4.0,1.0,8.0)
	scene._step_eva_motion(0.0,Vector3.ZERO,false,false)
	scene.camera.eva_third_person = true
	scene.camera.astronaut_visual.visible = true
	scene.camera.astronaut_visual.animate(0.016,true,false)
	scene.camera._update_camera_view(true)
	await capture("eva")
	scene.queue_free()
	await process_frame
	quit()
