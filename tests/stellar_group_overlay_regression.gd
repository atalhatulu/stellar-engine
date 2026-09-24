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
	var overlay: StellarGroupOverlay = scene.get_node("StellarGroupOverlay")
	var grouped_star = null
	for stars in scene.sector_manager.loaded_sectors.values():
		for star in stars:
			if star.group_id != "":
				grouped_star = star
				break
		if grouped_star != null:
			break
	if grouped_star == null:
		push_error("Test universe must contain a grouped star")
		quit(1)
		return
	scene.targeted_star_data = grouped_star
	overlay._process(0.0)
	if not overlay.visible or overlay.visible_member_count < 2:
		push_error("Selecting a grouped star must reveal its constellation")
		quit(1)
		return
	if overlay.edge_count != overlay.visible_member_count - 1:
		push_error("Constellation must use a clean spanning tree")
		quit(1)
		return
	var first_edges := overlay._fixed_edges.duplicate()
	var same_constellation = null
	for stars in scene.sector_manager.loaded_sectors.values():
		for star in stars:
			if star.constellation_id == grouped_star.constellation_id and star.unique_id != grouped_star.unique_id:
				same_constellation = star
				break
		if same_constellation != null:
			break
	if same_constellation != null:
		scene.targeted_star_data = same_constellation
		overlay._process(0.0)
		if overlay._fixed_edges != first_edges:
			push_error("Selecting another star must not alter constellation topology")
			quit(1)
			return
	TargetSelectionController.clear(scene)
	overlay._process(0.0)
	if overlay.visible:
		push_error("Clearing selection must hide the constellation")
		quit(1)
		return
	print("STELLAR_GROUP_OVERLAY_REGRESSION_OK members=%d" % overlay.visible_member_count)
	quit(0)
