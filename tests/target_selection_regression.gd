extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var scene = load("res://main.tscn").instantiate()
	scene.seed_value = 424243
	scene.enable_mid_field = false
	scene.enable_deep_field = false
	root.add_child(scene)
	scene.set_process(false)
	if TargetSelectionController.has_selection(scene):
		push_error("Main scene must start without a selected target")
		quit(1)
		return
	scene.current_target_index = 0
	scene.targeted_star_data = StarData.new()
	scene.is_focusing_target = true
	scene.is_autopilot_active = true
	TargetSelectionController.clear(scene)
	if TargetSelectionController.has_selection(scene) or scene.is_focusing_target or scene.is_autopilot_active:
		push_error("Clearing selection must also stop focus and autopilot")
		quit(1)
		return

	# 1. Normal yıldız için 180 LY altı / üstü mesafe kontrolü
	var star_near = StarData.new()
	star_near.unique_id = "SEC_0_0_0_S2"
	star_near.stellar_x = 50.0 * TargetSelectionController.LIGHT_YEAR
	star_near.stellar_y = 0.0
	star_near.stellar_z = 0.0
	scene.targeted_star_data = star_near
	if TargetSelectionController.check_distance_limit(scene):
		push_error("Target within 50 LY should not be cleared")
		quit(1)
		return

	var star_far = StarData.new()
	star_far.unique_id = "SEC_0_0_0_S2"
	star_far.stellar_x = 220.0 * TargetSelectionController.LIGHT_YEAR
	star_far.stellar_y = 0.0
	star_far.stellar_z = 0.0
	scene.targeted_star_data = star_far
	if not TargetSelectionController.check_distance_limit(scene) or TargetSelectionController.has_selection(scene):
		push_error("Secondary star beyond 180 LY must be cleared")
		quit(1)
		return

	# 2. Otopilot koruması: Uzak yıldız olsa bile otopilot aktifken seçim düşmemeli
	scene.targeted_star_data = star_far
	scene.is_interstellar_autopilot = true
	if TargetSelectionController.check_distance_limit(scene) or not TargetSelectionController.has_selection(scene):
		push_error("Star target must be preserved during active interstellar autopilot")
		quit(1)
		return
	scene.is_interstellar_autopilot = false
	TargetSelectionController.clear(scene)

	# 3. Gezegen için sistem mesafesi kontrolü
	scene._update_active_system_bodies()
	if scene.universe.size() > 1:
		scene.current_target_index = 1
		scene.virtual_player_position = Vector3(10.0 * TargetSelectionController.ONE_AU, 0, 0)
		if TargetSelectionController.check_distance_limit(scene):
			push_error("Planet within system range should not be cleared")
			quit(1)
			return

		scene.virtual_player_position = Vector3(250.0 * TargetSelectionController.ONE_AU, 0, 0)
		if not TargetSelectionController.check_distance_limit(scene) or TargetSelectionController.has_selection(scene):
			push_error("Planet beyond system exit range must be cleared")
			quit(1)
			return

		# Gezegen otopilot koruması
		scene.current_target_index = 1
		scene.is_autopilot_active = true
		if TargetSelectionController.check_distance_limit(scene) or not TargetSelectionController.has_selection(scene):
			push_error("Planet target must be preserved during active autopilot")
			quit(1)
			return
		scene.is_autopilot_active = false
		TargetSelectionController.clear(scene)

	print("TARGET_SELECTION_REGRESSION_OK")
	quit(0)
