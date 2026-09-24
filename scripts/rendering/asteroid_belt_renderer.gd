class_name AsteroidBeltRenderer
extends RefCounted

const ASTEROIDS_PER_BELT := 320


static func create_for_star(host: Node3D, star: CelestialBody) -> void:
	clear(star)
	for belt_index in range(star.asteroid_belts.size()):
		var belt: Dictionary = star.asteroid_belts[belt_index]
		var instance := MultiMeshInstance3D.new()
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.instance_count = ASTEROIDS_PER_BELT
		var rock := BoxMesh.new()
		rock.size = Vector3(0.006, 0.004, 0.005)
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.34, 0.29, 0.23)
		material.roughness = 0.96
		rock.material = material
		multimesh.mesh = rock
		var rng := RandomNumberGenerator.new()
		rng.seed = star.sys_seed ^ ((belt_index + 1) * 0x41535452)
		for index in range(ASTEROIDS_PER_BELT):
			var angle := rng.randf_range(0.0, TAU)
			var radius := rng.randf_range(0.88, 1.12)
			var height := rng.randfn(0.0, 0.018)
			var position := Vector3(cos(angle) * radius, height, sin(angle) * radius)
			var basis := Basis.from_euler(Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU))
			basis = basis.scaled(Vector3.ONE * rng.randf_range(0.5, 1.8))
			multimesh.set_instance_transform(index, Transform3D(basis, position))
		instance.multimesh = multimesh
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		instance.extra_cull_margin = 100000.0
		host.add_child(instance)
		star.asteroid_belt_instances.append(instance)


static func update(star: CelestialBody, center: Vector3, visual_limit: float, visible: bool) -> void:
	for index in range(star.asteroid_belt_instances.size()):
		var instance: MultiMeshInstance3D = star.asteroid_belt_instances[index]
		if not is_instance_valid(instance):
			continue
		var belt: Dictionary = star.asteroid_belts[index]
		var visual_radius := minf(float(belt.radius_m), visual_limit * 0.72)
		instance.global_position = center
		instance.scale = Vector3.ONE * visual_radius
		instance.visible = visible


static func clear(star: CelestialBody) -> void:
	for instance in star.asteroid_belt_instances:
		if is_instance_valid(instance):
			instance.queue_free()
	star.asteroid_belt_instances.clear()
