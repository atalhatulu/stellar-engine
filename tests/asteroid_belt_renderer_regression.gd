extends SceneTree


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var host := Node3D.new()
	root.add_child(host)
	var star := Star.new()
	star.sys_seed = 555
	star.asteroid_belts = [{"radius_m": 4.0e11, "density": 0.7, "name": "Test"}]
	AsteroidBeltRenderer.create_for_star(host, star)
	if star.asteroid_belt_instances.size() != 1:
		push_error("Every asteroid belt must use one MultiMesh renderer")
		quit(1)
		return
	var instance := star.asteroid_belt_instances[0]
	if instance.multimesh.instance_count != AsteroidBeltRenderer.ASTEROIDS_PER_BELT:
		push_error("Asteroid belt renderer must batch all rocks")
		quit(1)
		return
	AsteroidBeltRenderer.update(star, Vector3(2, 3, 4), 10000.0, true)
	if instance.global_position != Vector3(2, 3, 4) or not instance.visible:
		push_error("Asteroid belt renderer must follow its star")
		quit(1)
		return
	print("ASTEROID_BELT_RENDERER_REGRESSION_OK instances=%d" % instance.multimesh.instance_count)
	quit(0)
