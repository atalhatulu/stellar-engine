class_name HabitabilityLidar
extends Node3D

const MAX_CANDIDATES := 24
const HIGHLIGHT_SECONDS := 5.0
var _markers: Array[MeshInstance3D] = []
var _remaining := 0.0

func scan(host: Node3D) -> int:
	clear()
	if host.star_visual_pool == null or host.star_visual_pool.multimesh == null:
		return 0
	var found := 0
	var checked := 0
	for index in range(host.star_visual_pool.slots.size()):
		var slot = host.star_visual_pool.slots[index]
		if not slot.active or slot.star_data == null:
			continue
		checked += 1
		var star := SystemGenerator.instantiate_star_from_data(null, slot.star_data)
		var bodies := SystemGenerator.generate_planets_for_star(null, star, false)
		var habitable := false
		for body in bodies:
			if body.type == "PLANET" and body.is_habitable:
				habitable = true
				break
		if habitable:
			_add_marker(host, host.star_visual_pool.multimesh.get_instance_transform(index).origin)
			found += 1
		if checked >= MAX_CANDIDATES:
			break
	_remaining = HIGHLIGHT_SECONDS
	set_process(true)
	return found

func _add_marker(host: Node3D, position: Vector3) -> void:
	var marker := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.24
	sphere.height = 0.48
	sphere.radial_segments = 12
	sphere.rings = 6
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.1, 1.0, 0.55, 0.28)
	material.emission_enabled = true
	material.emission = Color(0.1, 1.0, 0.55)
	material.emission_energy_multiplier = 3.0
	material.no_depth_test = true
	sphere.material = material
	marker.mesh = sphere
	marker.position = position
	host.add_child(marker)
	_markers.append(marker)

func _process(delta: float) -> void:
	_remaining -= delta
	var pulse := 1.0 + sin(Time.get_ticks_msec() * 0.008) * 0.22
	for marker in _markers:
		if is_instance_valid(marker):
			marker.scale = Vector3.ONE * pulse
	if _remaining <= 0.0:
		clear()

func clear() -> void:
	for marker in _markers:
		if is_instance_valid(marker):
			marker.queue_free()
	_markers.clear()
	set_process(false)
