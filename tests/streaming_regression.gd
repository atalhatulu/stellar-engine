extends SceneTree

const Mid = preload("res://scripts/rendering/mid_field_star_renderer.gd")
const Deep = preload("res://scripts/rendering/deep_field_star_renderer.gd")
const Terrain = preload("res://scripts/rendering/planet_lod_manager.gd")
const Sphere = preload("res://scripts/rendering/planet_chunk_sphere.gd")
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func settle(field, camera, position: Vector3) -> void:
	var deadline := Time.get_ticks_msec() + 15000
	var target := Vector3i((position / field.LIGHT_YEAR / field._region_size).floor())
	while Time.get_ticks_msec() < deadline:
		field.update_renderer(camera, position)
		if field.active_region == target and field._fade >= 1.0:
			return
		await create_timer(0.005).timeout
	check(false, "Timed out settling star field")

func run() -> void:
	var camera := Camera3D.new()
	root.add_child(camera)
	var sync := SectorManager.new(424242)
	var streamed := SectorManager.new(424242)
	var protected := Vector3i.ZERO
	var sync_max := 0
	var streamed_max := 0
	for center in [Vector3i.ZERO, Vector3i(1, 0, 0), Vector3i(-3, 2, -4), Vector3i(9, 8, 7)]:
		var position := (Vector3(center) + Vector3.ONE * 0.5) * SectorManager.SECTOR_SIZE
		var started := Time.get_ticks_usec()
		sync.update_player_position(position, protected)
		sync_max = maxi(sync_max, Time.get_ticks_usec() - started)
		for frame in range(130):
			started = Time.get_ticks_usec()
			streamed.update_player_position(position, protected, 1000)
			streamed_max = maxi(streamed_max, Time.get_ticks_usec() - started)
			check(streamed.loaded_sectors.size() <= 126, "Sector cache must stay bounded")
			if streamed._pending_sectors.is_empty():
				break
		check(streamed.loaded_sectors.size() == sync.loaded_sectors.size(), "Incomplete sector stream")
		for coord in sync.loaded_sectors:
			check(streamed.get_sector_fingerprint(coord) == sync.get_sector_fingerprint(coord), "Streaming changed generated stars")
	# Protection can change without a player sector change.
	var position := (Vector3(9, 8, 7) + Vector3.ONE * 0.5) * SectorManager.SECTOR_SIZE
	streamed.update_player_position(position, Vector3i(-20, -20, -20))
	check(streamed.loaded_sectors.has(Vector3i(-20, -20, -20)), "New protected sector missing")
	check(not streamed.loaded_sectors.has(Vector3i.ZERO), "Old protected sector retained")
	print("SECTOR sync_max_ms=", sync_max / 1000.0, " streamed_max_ms=", streamed_max / 1000.0)

	for Script in [Mid, Deep]:
		var field = Script.new()
		root.add_child(field)
		field.setup(424242)
		await settle(field, camera, Vector3.ZERO)
		var original: PackedVector3Array = field.star_logical_positions_ly.duplicate()
		check(original.size() == field.star_capacity, "Star count mismatch")
		var unique := {}
		for i in range(original.size()):
			var meta: Dictionary = field.get_star_metadata(i)
			unique[meta.unique_id] = true
		check(unique.size() == original.size(), "Duplicate stars in one layer")
		for i in [0, original.size() / 2, original.size() - 1]:
			var star: StarData = field.create_star_data(i, 424242)
			check(star.system_seed == field.star_system_seeds[i], "Star seed mismatch")
			check(Vector3(star.stellar_x, star.stellar_y, star.stellar_z) / field.LIGHT_YEAR == original[i], "Star position mismatch")
		var jump: Vector3 = Vector3(2.25, -1.5, 0.5) * field._region_size * field.LIGHT_YEAR
		field.update_renderer(camera, jump)
		check(field.star_logical_positions_ly == original, "Old field discarded while generating")
		# A rapid reversal must discard a stale worker result.
		field.update_renderer(camera, -jump)
		await settle(field, camera, -jump)
		await settle(field, camera, Vector3.ZERO)
		check(field.star_logical_positions_ly == original, "Returning to region changed stars")
		await process_frame
		check(field.get_child_count() == field._chunk_count, "Faded star chunks leaked")
		print("FIELD ", field.star_capacity, " generation_ms=", field.last_generation_usec / 1000.0,
			" max_main_thread_update_ms=", field.max_update_usec / 1000.0)
		field.update_renderer(camera, jump)
		field.setup(99) # Reset while worker is still running.
		check(field.star_logical_positions_ly.is_empty(), "Reset retained old stars")
		field.queue_free()
		await process_frame

	var body := CelestialBody.new()
	body.real_radius = 6371000.0
	var terrain := Terrain.new()
	root.add_child(terrain)
	terrain.initialize(body, null, Vector3.UP, Vector3.RIGHT, Vector3.BACK)
	for i in range(90):
		terrain.update(0.0, 0.0)
		check(terrain.last_build_count <= 2, "Terrain rebuilt too many chunks in one frame")
	check(terrain._chunks.size() == 81 and terrain._build_queue.is_empty(), "Terrain did not finish loading")
	var chunk: MeshInstance3D = terrain._chunks["0,0"].mesh
	var old_pos := chunk.position
	terrain.update(100.0, 0.0)
	check(is_equal_approx(chunk.position.x - old_pos.x, -100.0), "Walking does not move camera-relative terrain")
	terrain.set_eye_height(21.8)
	old_pos = chunk.position
	terrain.update(100.0, 0.0)
	check(is_equal_approx(chunk.position.y - old_pos.y, -20.0), "Jetpack altitude does not move terrain")
	var terrain_max := 0
	for frame in range(100):
		var started := Time.get_ticks_usec()
		terrain.update(2100.0, -100.0)
		terrain_max = maxi(terrain_max, Time.get_ticks_usec() - started)
		check(terrain.last_build_count <= 2, "Terrain boundary exceeds build limit")
	check(terrain._chunks.size() == 81 and terrain._build_queue.is_empty(), "Terrain boundary stream incomplete")
	print("TERRAIN crossing_max_ms=", terrain_max / 1000.0)
	var sphere := Sphere.new()
	root.add_child(sphere)
	sphere.initialize(null, body.real_radius)
	var material := StandardMaterial3D.new()
	sphere.set_material(material)
	for cd in sphere._all_chunks.values():
		check(cd.mesh.material_override == material, "Root chunks did not receive planet material")
		check(cd.mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV].size() > 0, "Missing sphere UVs")
	for i in range(25):
		sphere.update(Vector3.ZERO, Vector3.ZERO, 1.0, Vector3.BACK * 7000000.0, Vector3.ZERO)
		check(sphere._builds_this_frame <= 2, "Sphere rebuilt too many chunks")
	terrain.queue_free()
	sphere.queue_free()
	camera.queue_free()
	await process_frame
	print("STREAMING REGRESSION: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)
