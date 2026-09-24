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
	print("TARGET_SELECTION_REGRESSION_OK")
	quit(0)
