extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var scene = load("res://main.tscn").instantiate()
	scene.seed_value = 24680
	scene.enable_mid_field = false
	scene.enable_deep_field = false
	root.add_child(scene)
	scene.set_process(false)
	if scene.is_local_system_loaded or not scene.universe.is_empty() or not scene.active_render_bodies.is_empty():
		push_error("The main scene must start without a loaded local star system")
		quit(1)
		return
	scene._update_active_system_bodies()
	if not scene.is_local_system_loaded or scene.universe.is_empty():
		push_error("Entering a star system must create its local bodies")
		quit(1)
		return
	scene._unload_local_system()
	if scene.is_local_system_loaded or not scene.universe.is_empty() or not scene.active_render_bodies.is_empty():
		push_error("Leaving a star system must remove bodies and orbit state")
		quit(1)
		return
	print("LOCAL_SYSTEM_LIFECYCLE_REGRESSION_OK")
	quit(0)
