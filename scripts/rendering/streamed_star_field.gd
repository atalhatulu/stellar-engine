extends Node3D

const Job = preload("res://scripts/rendering/star_field_job.gd")
const LIGHT_YEAR: float = 9460730472580800.0
const INVALID_REGION := Vector3i(2147483647, 2147483647, 2147483647)
const FADE_SECONDS := 0.65
var is_enabled := true
var universe_seed := 0
var star_capacity := 20000
var active_region := INVALID_REGION
var anchor_pos_ly := Vector3.ZERO
var shader_mat: ShaderMaterial
var chunk_nodes: Array[MultiMeshInstance3D] = []
var star_logical_positions_ly := PackedVector3Array()
var star_system_seeds := PackedInt32Array()
var last_generation_usec := 0
var last_upload_usec := 0
var max_update_usec := 0
var _region_size := 1000.0
var _min_distance := 150.0
var _max_distance := 2500.0
var _chunk_count := 4
var _quad := QuadMesh.new()
var _thread: Thread
var _job: RefCounted
var _requested_region := INVALID_REGION
var _building_region := INVALID_REGION
var _pending: Dictionary = {}
var _upload_index := 0
var _staging_nodes: Array[MultiMeshInstance3D] = []
var _staging_material: ShaderMaterial
var _old_nodes: Array[MultiMeshInstance3D] = []
var _old_material: ShaderMaterial
var _fade := 1.0
var _last_tick := 0

func configure(shader_path: String, region_size: float, minimum: float, maximum: float,
		chunks: int, capacity: int) -> void:
	_region_size = region_size
	_min_distance = minimum
	_max_distance = maximum
	_chunk_count = chunks
	star_capacity = capacity
	_quad.size = Vector2.ONE
	shader_mat = ShaderMaterial.new()
	shader_mat.shader = load(shader_path)

func setup(p_universe_seed: int, p_capacity: int = -1) -> void:
	_stop_worker()
	_clear_nodes(chunk_nodes)
	_clear_nodes(_staging_nodes)
	_clear_nodes(_old_nodes)
	_pending.clear()
	_old_material = null
	universe_seed = p_universe_seed
	if p_capacity > 0:
		star_capacity = p_capacity
	active_region = INVALID_REGION
	_requested_region = INVALID_REGION
	star_logical_positions_ly.clear()
	star_system_seeds.clear()
	_fade = 1.0
	_last_tick = 0

func set_enabled(value: bool) -> void:
	is_enabled = value
	visible = value

func toggle_enabled() -> bool:
	set_enabled(not is_enabled)
	return is_enabled

func _start_worker(region: Vector3i) -> void:
	_building_region = region
	_job = Job.new()
	_thread = Thread.new()
	var error := _thread.start(_job.build.bind(universe_seed, region, _region_size,
		_min_distance, _max_distance, star_capacity, _chunk_count))
	if error != OK:
		_thread = null
		push_error("Star field worker could not start: %s" % error)

func _stop_worker() -> void:
	if _thread != null:
		_job.cancel()
		_thread.wait_to_finish()
		_thread = null
	_job = null

func _clear_nodes(nodes: Array[MultiMeshInstance3D]) -> void:
	for node in nodes:
		node.visible = false
		node.queue_free()
	nodes.clear()

func _collect_worker() -> void:
	var result: Dictionary = _thread.wait_to_finish()
	_thread = null
	_job = null
	if result.is_empty() or result.region != _requested_region:
		return
	_pending = result
	last_generation_usec = result.generation_usec
	_upload_index = 0
	_staging_material = shader_mat.duplicate()
	_staging_material.set_shader_parameter("u_anchor_pos_ly", result.anchor)
	_staging_material.set_shader_parameter("u_layer_opacity", 0.0)

func _upload_one_chunk() -> void:
	var started := Time.get_ticks_usec()
	var buffer: PackedFloat32Array = _pending.buffers[_upload_index]
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = _quad
	mm.instance_count = buffer.size() / 20
	mm.custom_aabb = AABB(Vector3.ONE * -1800000.0, Vector3.ONE * 3600000.0)
	mm.buffer = buffer
	var node := MultiMeshInstance3D.new()
	node.multimesh = mm
	node.material_override = _staging_material
	node.custom_aabb = mm.custom_aabb
	node.extra_cull_margin = 2500000.0
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	_staging_nodes.append(node)
	_upload_index += 1
	last_upload_usec = Time.get_ticks_usec() - started
	if _upload_index == _chunk_count:
		_old_nodes.assign(chunk_nodes)
		_old_material = shader_mat
		chunk_nodes.assign(_staging_nodes)
		_staging_nodes.clear()
		shader_mat = _staging_material
		active_region = _pending.region
		anchor_pos_ly = _pending.anchor
		star_logical_positions_ly = _pending.positions
		star_system_seeds = _pending.seeds
		_pending.clear()
		_fade = 0.0

func update_renderer(camera: Node3D, player_gal_pos_meters: Vector3) -> void:
	if not is_enabled or camera == null:
		return
	var started := Time.get_ticks_usec()
	var delta := minf(float(started - _last_tick) / 1000000.0, 0.1) if _last_tick else 0.016
	_last_tick = started
	global_position = camera.global_position
	global_rotation = Vector3.ZERO
	var player := player_gal_pos_meters / LIGHT_YEAR
	_requested_region = Vector3i((player / _region_size).floor())
	# Cancel obsolete work without waiting on the game thread.
	if _thread != null:
		if _building_region != _requested_region:
			_job.cancel()
		if not _thread.is_alive():
			_collect_worker()
	if not _pending.is_empty() and _pending.region != _requested_region:
		_pending.clear()
		_clear_nodes(_staging_nodes)
	if _fade < 1.0:
		_fade = minf(_fade + delta / FADE_SECONDS, 1.0)
		if _fade >= 1.0:
			_clear_nodes(_old_nodes)
			_old_material = null
	if _fade >= 1.0:
		if not _pending.is_empty():
			_upload_one_chunk()
		elif _thread == null and _requested_region != active_region:
			_start_worker(_requested_region)
	var opacity := smoothstep(0.0, 1.0, _fade)
	shader_mat.set_shader_parameter("u_player_gal_ly", player)
	shader_mat.set_shader_parameter("u_layer_opacity", opacity)
	if _old_material != null:
		_old_material.set_shader_parameter("u_player_gal_ly", player)
		_old_material.set_shader_parameter("u_layer_opacity", 1.0 - opacity)
	max_update_usec = maxi(max_update_usec, Time.get_ticks_usec() - started)

# Explicit blocking path for offline diagnostics only; gameplay never calls it.
func finish_streaming() -> void:
	if _thread != null:
		_collect_worker()
	_clear_nodes(_old_nodes)
	_old_material = null
	while not _pending.is_empty():
		_upload_one_chunk()
	_clear_nodes(_old_nodes)
	_old_material = null
	_fade = 1.0
	shader_mat.set_shader_parameter("u_layer_opacity", 1.0)

func get_star_metadata(index: int) -> Dictionary:
	if index < 0 or index >= star_logical_positions_ly.size():
		return {}
	var position := star_logical_positions_ly[index]
	var coord := SectorManager.get_sector_coord(position * LIGHT_YEAR)
	return {"star_index": index, "unique_id": "SEC_%d_%d_%d_S1" % [coord.x, coord.y, coord.z],
		"name": "S_%d_%d_%d_1" % [coord.x, coord.y, coord.z], "galactic_pos_ly": position,
		"galactic_pos_meters": position * LIGHT_YEAR, "sector_coord": coord,
		"system_seed": star_system_seeds[index]}

func create_star_data(index: int, seed_value: int) -> StarData:
	var meta := get_star_metadata(index)
	if meta.is_empty():
		return null
	return SectorManager.generate_single_star(seed_value, meta.sector_coord, 0)

func find_closest_star_to_ray(origin: Vector3, direction: Vector3, max_angle_rad: float = 0.035) -> int:
	if not is_enabled:
		return -1
	var best := -1
	var best_dot := cos(max_angle_rad)
	for i in range(star_logical_positions_ly.size()):
		var offset := star_logical_positions_ly[i] - origin
		var distance := offset.length()
		if distance < _min_distance or distance > _max_distance:
			continue
		var alignment := direction.dot(offset / distance)
		if alignment > best_dot:
			best_dot = alignment
			best = i
	return best

func _exit_tree() -> void:
	_stop_worker()
