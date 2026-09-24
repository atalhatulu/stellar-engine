class_name StreamedGalaxyField
extends Node3D

# ─────────────────────────────────────────────────────────────────────────────
# AKIŞKAN DERİN KOZMOLOJİK GALAKSİ ALANI (STREAMED COSMOLOGICAL GALAXY FIELD)
# main.tscn'deki StreamedStarField mimarisinin galaksilerarası uzaya
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
# Yüksek warp hızında bölge sınırı birkaç karede geçilebilir. Eski ve yeni
# kozmik alanları daha uzun çapraz söndürerek galaksilerin aniden doğmasını önle.
const FADE_SECONDS := 1.5

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
var _old_positions_ly := PackedVector3Array()
var _old_seeds := PackedInt32Array()
var _old_morphologies := PackedByteArray()
var _old_diameters := PackedFloat32Array()

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
var _suppressed_seeds: Dictionary = {}
var _active_exclusion_position_ly := Vector3.ZERO
var _active_exclusion_radius_ly := 0.0

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
	_old_positions_ly.clear()
	_old_seeds.clear()
	_old_morphologies.clear()
	_old_diameters.clear()
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
		_old_positions_ly = galaxy_logical_positions_ly.duplicate()
		_old_seeds = galaxy_seeds.duplicate()
		_old_morphologies = galaxy_morphologies.duplicate()
		_old_diameters = galaxy_diameters.duplicate()
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
		_apply_suppressed_galaxies()

func set_galaxy_impostor_visible(seed_value: int, is_visible: bool) -> void:
	if is_visible:
		_suppressed_seeds.erase(seed_value)
	else:
		_suppressed_seeds[seed_value] = true
	_set_seed_alpha(seed_value, 1.0 if is_visible else 0.0)

func set_active_galaxy_exclusion(position_ly: Vector3, radius_ly: float) -> void:
	_active_exclusion_position_ly = position_ly
	_active_exclusion_radius_ly = maxf(radius_ly, 0.0)
	_apply_active_exclusion(shader_mat)
	_apply_active_exclusion(_staging_material)
	_apply_active_exclusion(_old_material)

func _apply_active_exclusion(material: ShaderMaterial) -> void:
	if material == null:
		return
	material.set_shader_parameter("u_active_galaxy_pos_ly", _active_exclusion_position_ly)
	material.set_shader_parameter("u_active_exclusion_radius_ly", _active_exclusion_radius_ly)

func suppress_galaxy_seed(seed_value: int) -> void:
	set_galaxy_impostor_visible(seed_value, false)

func _set_seed_alpha(seed_value: int, alpha: float) -> void:
	for i in range(galaxy_seeds.size()):
		if int(galaxy_seeds[i]) == seed_value:
			_set_global_instance_alpha(chunk_nodes, i, alpha)
	for i in range(_old_seeds.size()):
		if int(_old_seeds[i]) == seed_value:
			_set_global_instance_alpha(_old_nodes, i, alpha)
	_apply_suppressed_galaxies()

func _apply_suppressed_galaxies() -> void:
	for i in range(galaxy_seeds.size()):
		if _suppressed_seeds.has(int(galaxy_seeds[i])):
			_set_global_instance_alpha(chunk_nodes, i, 0.0)
	for i in range(_old_seeds.size()):
		if _suppressed_seeds.has(int(_old_seeds[i])):
			_set_global_instance_alpha(_old_nodes, i, 0.0)

func _set_global_instance_alpha(nodes: Array[MultiMeshInstance3D], global_index: int, alpha: float) -> void:
	var remaining := global_index
	for node in nodes:
		if not is_instance_valid(node) or node.multimesh == null:
			continue
		var count := node.multimesh.instance_count
		if remaining < count:
			var color := node.multimesh.get_instance_color(remaining)
			color.a = alpha
			node.multimesh.set_instance_color(remaining, color)
			return
		remaining -= count

func update_renderer(camera: Node3D, observer_absolute_ly: Vector3) -> void:
	if not is_enabled or camera == null:
		return
		
	var started := Time.get_ticks_usec()
	var delta := minf(float(started - _last_tick) / 1000000.0, 0.1) if _last_tick else 0.016
	_last_tick = started
	
	global_position = camera.global_position
	global_rotation = Vector3.ZERO
	_apply_active_exclusion(shader_mat)
	_apply_active_exclusion(_staging_material)
	_apply_active_exclusion(_old_material)
	
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
			_old_positions_ly.clear()
			_old_seeds.clear()
			_old_morphologies.clear()
			_old_diameters.clear()
			
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
	# Çapraz sönüm sırasında eski alan hâlâ ekrandadır; negatif kodlanan indeks
	# sayesinde bu galaksiler de seçilebilir kalır. -1 "yok", -(i+2) eski alan.
	for i in range(_old_positions_ly.size()):
		var offset := _old_positions_ly[i] - observer_absolute_ly
		var distance := offset.length()
		if distance < _min_distance or distance > _max_distance:
			continue
		var alignment := ray_dir.dot(offset / distance)
		if alignment > best_dot:
			best_dot = alignment
			best = -(i + 2)
	return best

# Oyuncu bir galaksiyi seçmeden manuel uçuşla yaklaştığında da yakın LOD'a
# geçebilmek için görünür streaming kataloğundaki aktivasyon adayını bulur.
func find_activation_candidate(observer_absolute_ly: Vector3) -> int:
	var best_index := -1
	var best_ratio := INF
	for i in range(galaxy_logical_positions_ly.size()):
		var radius_ly := float(galaxy_diameters[i]) * 0.5
		var activation_distance := maxf(radius_ly * 4.0, 90000.0)
		var distance := galaxy_logical_positions_ly[i].distance_to(observer_absolute_ly)
		if distance <= activation_distance:
			var ratio := distance / activation_distance
			if ratio < best_ratio:
				best_ratio = ratio
				best_index = i
	for i in range(_old_positions_ly.size()):
		var radius_ly := float(_old_diameters[i]) * 0.5
		var activation_distance := maxf(radius_ly * 4.0, 90000.0)
		var distance := _old_positions_ly[i].distance_to(observer_absolute_ly)
		if distance <= activation_distance:
			var ratio := distance / activation_distance
			if ratio < best_ratio:
				best_ratio = ratio
				best_index = -(i + 2)
	return best_index

func get_galaxy_metadata(index: int) -> Dictionary:
	if index <= -2:
		var old_index := -index - 2
		if old_index < 0 or old_index >= _old_positions_ly.size():
			return {}
		return {
			"index": index,
			"position_ly": _old_positions_ly[old_index],
			"seed": _old_seeds[old_index],
			"morphology": _old_morphologies[old_index],
			"diameter_ly": _old_diameters[old_index]
		}
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
	g.extra_flags["streamed_field_index"] = int(meta.index)
	return g

func _exit_tree() -> void:
	_stop_worker()
