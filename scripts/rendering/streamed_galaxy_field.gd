class_name StreamedGalaxyField
extends Node3D

# ─────────────────────────────────────────────────────────────────────────────
# AKIŞKAN DERİN KOZMOLOJİK GALAKSİ ALANI (STREAMED COSMOLOGICAL GALAXY FIELD)
# main_star.tscn'deki StreamedStarField mimarisinin galaksilerarası uzaya
# uyarlanmış halidir.
# 1. 20.000 gerçek derin uzay galaksisini arka planda iş parçacığında (Thread) üretir.
# 2. Çift tamponlama (double-buffering) ve dilimlenmiş yükleme (sliced chunk upload)
#    ile ana iş parçacığında sıfır takılma (0 ms frame spike) sağlar.
# 3. GPU Shader (deep_field_galaxies.gdshader) ile her karede sıfır CPU dönüşümü.
# 4. Herhangi bir arka plan galaksisine nişan alındığında deterministik tohumuyla
#    gerçek bir Galaxy nesnesine dönüştürülüp hedeflenebilir ve seyahat edilebilir.
# ─────────────────────────────────────────────────────────────────────────────

const Job = preload("res://scripts/rendering/cosmological_galaxy_job.gd")
const INVALID_REGION := Vector3i(2147483647, 2147483647, 2147483647)
const FADE_SECONDS := 0.65

var is_enabled := true
var universe_seed := 0
var galaxy_capacity := 20000
var active_region := INVALID_REGION
var anchor_pos_ly := Vector3.ZERO
var shader_mat: ShaderMaterial

var chunk_nodes: Array[MultiMeshInstance3D] = []
var galaxy_logical_positions_ly := PackedVector3Array()
var galaxy_seeds := PackedInt32Array()
var galaxy_morphologies := PackedByteArray()
var galaxy_diameters := PackedFloat32Array()

var _region_size := 8000000.0 # 8 Milyon Işık Yılı (~2.45 Mpc)
var _min_distance := 180000.0 # 180.000 LY (Aktif galaksi LOD küresi dışı)
var _max_distance := 60000000.0 # 60 Milyon LY derin kozmolojik ağ
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

func _init() -> void:
	_quad.size = Vector2.ONE
	shader_mat = ShaderMaterial.new()
	shader_mat.shader = load("res://shaders/deep_field_galaxies.gdshader")

func setup(p_universe_seed: int, p_capacity: int = 20000) -> void:
	_stop_worker()
	_clear_nodes(chunk_nodes)
	_clear_nodes(_staging_nodes)
	_clear_nodes(_old_nodes)
	_pending.clear()
	_old_material = null
	universe_seed = p_universe_seed
	if p_capacity > 0:
		galaxy_capacity = p_capacity
	active_region = INVALID_REGION
	_requested_region = INVALID_REGION
	galaxy_logical_positions_ly.clear()
	galaxy_seeds.clear()
	galaxy_morphologies.clear()
	galaxy_diameters.clear()
	_fade = 1.0
	_last_tick = 0

func set_enabled(value: bool) -> void:
	is_enabled = value
	visible = value

func _start_worker(region: Vector3i) -> void:
	_building_region = region
	_job = Job.new()
	_thread = Thread.new()
	var error := _thread.start(_job.build.bind(universe_seed, region, _region_size,
		_min_distance, _max_distance, galaxy_capacity, _chunk_count))
	if error != OK:
		_thread = null
		push_error("Cosmological galaxy field worker could not start: %s" % error)

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
	_upload_index = 0
	_staging_material = shader_mat.duplicate()
	_staging_material.set_shader_parameter("u_anchor_pos_ly", result.anchor)
	_staging_material.set_shader_parameter("u_layer_opacity", 0.0)

func _upload_one_chunk() -> void:
	var buffer: PackedFloat32Array = _pending.buffers[_upload_index]
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = _quad
	mm.instance_count = buffer.size() / 20
	mm.custom_aabb = AABB(Vector3.ONE * -400000.0, Vector3.ONE * 800000.0)
	mm.buffer = buffer
	
	var node := MultiMeshInstance3D.new()
	node.name = "CosmicGalaxyChunk_%d" % _upload_index
	node.multimesh = mm
	node.material_override = _staging_material
	node.custom_aabb = mm.custom_aabb
	node.extra_cull_margin = 800000.0
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.ignore_occlusion_culling = true
	add_child(node)
	_staging_nodes.append(node)
	_upload_index += 1
	
	if _upload_index == _chunk_count:
		_old_nodes.assign(chunk_nodes)
		_old_material = shader_mat
		chunk_nodes.assign(_staging_nodes)
		_staging_nodes.clear()
		shader_mat = _staging_material
		active_region = _pending.region
		anchor_pos_ly = _pending.anchor
		galaxy_logical_positions_ly = _pending.positions
		galaxy_seeds = _pending.seeds
		galaxy_morphologies = _pending.morphologies
		galaxy_diameters = _pending.diameters
		_pending.clear()
		_fade = 0.0

func update_renderer(camera: Node3D, observer_absolute_ly: Vector3) -> void:
	if not is_enabled or camera == null:
		return
		
	var started := Time.get_ticks_usec()
	var delta := minf(float(started - _last_tick) / 1000000.0, 0.1) if _last_tick else 0.016
	_last_tick = started
	
	global_position = camera.global_position
	global_rotation = Vector3.ZERO
	
	_requested_region = Vector3i((observer_absolute_ly / _region_size).floor())
	
	# İptal ve iş parçacığı toplama
	if _thread != null:
		if _building_region != _requested_region:
			_job.cancel()
		if not _thread.is_alive():
			_collect_worker()
			
	if not _pending.is_empty() and _pending.region != _requested_region:
		_pending.clear()
		_clear_nodes(_staging_nodes)
		
	# Yumuşak geçiş sönümlemesi
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
	shader_mat.set_shader_parameter("u_observer_pos_ly", observer_absolute_ly)
	shader_mat.set_shader_parameter("u_layer_opacity", opacity)
	if _old_material != null:
		_old_material.set_shader_parameter("u_observer_pos_ly", observer_absolute_ly)
		_old_material.set_shader_parameter("u_layer_opacity", 1.0 - opacity)

func find_closest_galaxy_to_ray(observer_absolute_ly: Vector3, ray_dir: Vector3, max_angle_rad: float = 0.045) -> int:
	if not is_enabled or galaxy_logical_positions_ly.is_empty():
		return -1
	var best := -1
	var best_dot := cos(max_angle_rad)
	for i in range(galaxy_logical_positions_ly.size()):
		var offset := galaxy_logical_positions_ly[i] - observer_absolute_ly
		var distance := offset.length()
		if distance < _min_distance or distance > _max_distance:
			continue
		var alignment := ray_dir.dot(offset / distance)
		if alignment > best_dot:
			best_dot = alignment
			best = i
	return best

func get_galaxy_metadata(index: int) -> Dictionary:
	if index < 0 or index >= galaxy_logical_positions_ly.size():
		return {}
	return {
		"index": index,
		"position_ly": galaxy_logical_positions_ly[index],
		"seed": galaxy_seeds[index],
		"morphology": galaxy_morphologies[index],
		"diameter_ly": galaxy_diameters[index]
	}

func create_galaxy_data(index: int) -> Galaxy:
	var meta := get_galaxy_metadata(index)
	if meta.is_empty():
		return null
	var g := Galaxy.generate(meta.seed, meta.position_ly, false)
	g.morphology = int(meta.morphology)
	g.diameter_ly = float(meta.diameter_ly)
	g.radius_ly = g.diameter_ly * 0.5
	return g

func _exit_tree() -> void:
	_stop_worker()
