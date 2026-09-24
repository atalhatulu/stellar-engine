extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed := load("res://scenes/test_galaxy.tscn") as PackedScene
	var main := packed.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	var camera: Camera3D = main.spectator_camera
	camera.position = Vector3(1250000.25, -2400000.5, 7100000.75)
	main._update_observer_galactic_position()
	var before: GalacticPosition = main.get_player_galactic_position_precise()
	main._update_floating_origin()
	var after: GalacticPosition = main.get_player_galactic_position_precise()

	_assert(before.distance_to_meters(after) < 1.0, "Kayan orijin fiziksel gözlemci konumunu değiştirdi")
	_assert(camera.position.length() < 0.001, "Kamera kayan orijinden sonra merkeze dönmedi")
	_assert(main.render_origin_position.sector != Vector3i.ZERO, "Büyük seyahat sektör koordinatına aktarılmadı")

	var target_position: GalacticPosition = after.duplicate_pos()
	target_position.add_meters(Vector3(100.0, 200.0, -300.0) * GalacticPosition.LIGHT_YEAR)
	var target_world: Vector3 = main._galactic_position_to_world(target_position)
	var expected_delta := Vector3(100.0, 200.0, -300.0)
	_assert(target_world.distance_to(expected_delta) < 0.01, "Mutlak hedeften render uzayına dönüşüm hatalı: %s" % target_world)

	print("GALACTIC_OBSERVER_REGRESSION_OK sector=%s" % before.sector)
	main.queue_free()
	quit(0)

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	quit(1)
