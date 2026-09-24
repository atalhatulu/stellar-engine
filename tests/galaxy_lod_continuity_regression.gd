extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed := load("res://scenes/test_galaxy.tscn") as PackedScene
	var main = packed.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	# Seçim yapmadan, yalnız kamerayla bir streaming galaksisinin yakınına gir.
	var observer_ly: Vector3 = main.get_player_galactic_position_precise().to_light_years()
	var destination_pos := observer_ly + Vector3(100000.0, 0.0, 0.0)
	main.streamed_galaxy_field.galaxy_logical_positions_ly = PackedVector3Array([destination_pos])
	main.streamed_galaxy_field.galaxy_seeds = PackedInt32Array([778899])
	main.streamed_galaxy_field.galaxy_morphologies = PackedByteArray([Galaxy.Morphology.SPIRAL])
	main.streamed_galaxy_field.galaxy_diameters = PackedFloat32Array([100000.0])
	main.galaxy_proximity_scan_timer = 0.0
	main._update_streamed_galaxy_proximity(0.3)
	var destination: Galaxy = main.current_astro
	destination.designation = "LOD-TEST"
	var build_frames := 0
	var max_frame_usec := 0
	var saw_progressive_stars := false
	while not main.galaxy_star_field_ready and build_frames < 2000:
		var frame_started := Time.get_ticks_usec()
		await process_frame
		max_frame_usec = maxi(max_frame_usec, Time.get_ticks_usec() - frame_started)
		if is_instance_valid(main.multimesh_instance) and main.multimesh_instance.multimesh != null \
				and main.multimesh_instance.multimesh.visible_instance_count > 0 and main.multimesh_instance.visible:
			saw_progressive_stars = true
		build_frames += 1
	# Hazırlık bayrağından sonraki karede LOD denetleyicisi LOADING -> NEAR
	# geçişini uygular.
	await process_frame
	await process_frame
	print("LOD_TEST_STATE state=%s progress=%.3f active=%s generation=%d distance=%.1f radius=%.1f" % [
		main.galaxy_lod_controller.state,
		main.galaxy_star_build_progress,
		main.galaxy_star_build_active,
		main.galaxy_star_build_generation,
		main._observer_distance_to_galaxy_ly(main.current_astro),
		main.active_galaxy_radius_ly
	])

	_assert(main.current_astro.unique_id == CelestialAddress.galaxy_id(778899), "Yakındaki streaming galaksisi otomatik etkinleşmedi")
	_assert(is_instance_valid(main.multimesh_instance), "Etkin galaksinin yıldız MultiMesh'i yok")
	_assert(main.multimesh_instance.visible, "Etkin galaksinin yıldızları gizli")
	_assert(main.multimesh_instance.multimesh.instance_count == main.total_stars, "Etkin galaksi yıldız kataloğu eksik")
	_assert(main.multimesh_instance.multimesh.visible_instance_count == main.total_stars, "Yıldız üretimi tamamlanmadı")
	_assert(main.galaxy_star_field_ready, "Kare bütçeli yıldız alanı hazır olmadı")
	_assert(saw_progressive_stars, "Yıldızlar üretim tamamlanana kadar gereksiz yere gizli kaldı")
	_assert(main.extragalactic_cluster.has(destination), "Aktif galaksi kalıcı LOD kaydından düştü")
	_assert(not main.extragalactic_render_ids.has(destination.unique_id), "Aktif 2D galaksi render havuzundan çıkarılmadı")
	_assert(main.extragalactic_multimesh.multimesh.visible_instance_count == main.extragalactic_render_ids.size(), "Uzak galaksi render sayacı tutarsız")

	# Galaksiden tekrar uzaklaş: yıldız alanı kapanmalı ve sabit uzak galaksi
	# impostor'u geri gelmeli.
	main.spectator_camera.position += Vector3(-400000.0, 0.0, 0.0)
	await process_frame
	await process_frame
	_assert(main.galaxy_lod_controller.is_far(), "Uzaklaşınca FAR_IMPOSTOR durumuna dönülmedi")
	_assert(not main.multimesh_instance.visible, "Uzaklaşınca detaylı yıldız alanı kapanmadı")
	_assert(main.extragalactic_cluster.has(destination), "Uzak galaksi sabit LOD listesinden düştü")
	_assert(main.extragalactic_render_ids.has(destination.unique_id), "Uzaklaşınca galaksi impostor'u geri açılmadı")

	# Uzak alan bölgesi tamamen değişse bile etkin/ziyaret edilmiş galaksi kalıcı
	# LOD kayıt katmanında tutulmalıdır.
	var recomposed: Array[Galaxy] = main.galaxy_lod_registry.compose_pinned(CosmicSectorManager.MAX_ACTIVE_GALAXIES)
	var found := false
	for galaxy in recomposed:
		if galaxy.unique_id == destination.unique_id:
			found = true
			break
	_assert(found, "Etkin galaksi sektör değişiminde LOD listesinden düştü")

	print("GALAXY_LOD_CONTINUITY_OK stars=%d galaxies=%d build_frames=%d max_frame_ms=%.2f" % [
		main.multimesh_instance.multimesh.instance_count,
		recomposed.size(),
		build_frames,
		float(max_frame_usec) / 1000.0
	])
	main.queue_free()
	quit(0)

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	quit(1)
