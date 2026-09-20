class_name PlanetChunkSphere
extends Node3D

# =============================================================================
# High-Resolution Multi-Branch Planetary Spherical Chunk LOD
# Eliminates low-poly clipping, backface culling, and interior camera entrapment.
# =============================================================================

# Root grid: 6×4 = 24 chunks (60° lon × 45° lat each) - maintains spherical topology
const BASE_NLON: int = 6
const BASE_NLAT: int = 4
const MAX_LEVEL: int = 5

# Each subdivision splits into 4 (2 lon × 2 lat)
const CHILD_NLON: int = 2
const CHILD_NLAT: int = 2

# High-resolution vertex grid per chunk across LOD levels (uzaydan yaklaşırken zengin dağ silüeti)
const SUBDIV_LEVELS: Array = [24, 32, 40, 48, 56, 56]

# Distance thresholds relative to planet radius (dist / radius) - Uzaktan kademeli ve dengeli detaylanma
const LEVEL_SUBDIV_THRESHOLDS: Array = [1.2, 0.55, 0.22, 0.08, 0.025]
const LEVEL_MERGE_THRESHOLDS: Array = [1.5, 0.70, 0.28, 0.11, 0.035]

var _noise: FastNoiseLite = null
var _terrain_material: Material = null
var _border_material: Material = null
var _border_visible: bool = false
var _builds_this_frame := 0
const MAX_BUILDS_PER_FRAME := 2
var _is_active: bool = false
var _body_radius: float = 1.0
var _all_chunks: Dictionary = {}
var _root_keys: Array[String] = []
var _all_borders: Array[MeshInstance3D] = []


func initialize(p_noise: FastNoiseLite, body_radius: float) -> void:
	_noise = p_noise
	_body_radius = maxf(body_radius, 1000.0)
	_is_active = true
	_all_chunks.clear()
	_root_keys.clear()
	_all_borders.clear()

	_border_material = StandardMaterial3D.new()
	_border_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_border_material.albedo_color = Color(0.0, 0.8, 1.0, 0.9)
	_border_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_border_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_border_material.use_point_size = true
	_border_material.point_size = 3

	# 24 root chunks
	for li in range(BASE_NLAT):
		for lj in range(BASE_NLON):
			var key = _ckey(0, li, lj)
			_root_keys.append(key)
			_create_chunk(0, li, lj)


var debug_color_mode: bool = false
var _debug_materials: Array[StandardMaterial3D] = []

func _init_debug_materials() -> void:
	if not _debug_materials.is_empty():
		return
	var colors = [
		Color(0.92, 0.22, 0.22), # Level 0: Kırmızı (Root 24 parça)
		Color(1.00, 0.50, 0.12), # Level 1: Turuncu
		Color(0.96, 0.85, 0.18), # Level 2: Sarı
		Color(0.20, 0.65, 1.00), # Level 3: Mavi
		Color(0.18, 0.90, 0.32), # Level 4: Yeşil (Yüksek küresel detay)
		Color(0.12, 0.90, 0.85)  # Level 5: Turkuaz (En yüksek yüzey detayı)
	]
	for i in range(colors.size()):
		var mat = StandardMaterial3D.new()
		mat.albedo_color = colors[i]
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.roughness = 0.8
		_debug_materials.append(mat)

func toggle_debug_colors() -> bool:
	debug_color_mode = not debug_color_mode
	_init_debug_materials()
	_refresh_all_materials()
	return debug_color_mode

func get_lod_stats() -> Dictionary:
	var counts = { 0: 0, 1: 0, 2: 0, 3: 0, 4: 0, 5: 0 }
	var total = 0
	for cd in _all_chunks.values():
		if is_instance_valid(cd.mesh) and cd.mesh.visible:
			var lvl = clampi(cd.level, 0, 5)
			counts[lvl] = counts.get(lvl, 0) + 1
			total += 1
	return {
		"total_chunks": total,
		"lod_counts": counts,
		"is_active": _is_active,
		"body_radius": _body_radius,
		"debug_color_mode": debug_color_mode
	}

func _refresh_all_materials() -> void:
	for cd in _all_chunks.values():
		if is_instance_valid(cd.mesh):
			cd.mesh.material_override = _get_chunk_material(cd.level)

func _get_chunk_material(level: int) -> Material:
	if debug_color_mode:
		_init_debug_materials()
		var clamped = clampi(level, 0, _debug_materials.size() - 1)
		return _debug_materials[clamped]
	return _terrain_material

func set_material(mat: Material) -> void:
	if mat != null:
		# Çift taraflı render: kameranın arkasında kalma / zemin şeffaflaşma sorununu önler
		if mat is StandardMaterial3D:
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_terrain_material = mat
	_refresh_all_materials()

func is_active() -> bool:
	return _is_active

func set_borders_visible(v: bool) -> void:
	_border_visible = v
	for b in _all_borders:
		if is_instance_valid(b):
			b.visible = v

func clear() -> void:
	for key in _all_chunks:
		var cd = _all_chunks[key]
		if is_instance_valid(cd.mesh):
			cd.mesh.queue_free()
		if is_instance_valid(cd.border):
			cd.border.queue_free()
	_all_chunks.clear()
	_root_keys.clear()
	_all_borders.clear()
	_is_active = false


func update(camera_world: Vector3, planet_center: Vector3, radius: float,
			real_cam: Vector3, real_center: Vector3, cam_forward: Vector3 = Vector3.ZERO) -> void:
	if not _is_active:
		return
	_builds_this_frame = 0

	for rkey in _root_keys:
		_evaluate_node(rkey, real_cam, real_center, cam_forward)


func _chunk_surface_dist(cd: Dictionary, real_cam: Vector3, real_center: Vector3) -> float:
	var local_dir = _chunk_center_dir(cd.level, cd.li, cd.lj)
	var world_dir = (global_basis * local_dir).normalized()
	var pos = real_center + world_dir * _body_radius
	return (pos - real_cam).length()


# Parçanın gezegen arkasında (ufuk engellemesi) veya kameranın görüş açısı dışında olup olmadığını denetler
func _is_chunk_culled(cd: Dictionary, real_cam: Vector3, real_center: Vector3, cam_forward: Vector3) -> bool:
	var local_dir = _chunk_center_dir(cd.level, cd.li, cd.lj)
	var world_dir = (global_basis * local_dir).normalized()
	
	# 1. Gezegen Arka Yüzü Ufuk Engellemesi (Horizon Occlusion)
	var cam_to_center = real_center - real_cam
	var cam_dist = cam_to_center.length()
	var center_to_cam = -cam_to_center / max(cam_dist, 1.0)
	
	# Seviyeye bağlı açısal yarıçap marjini (Kök parçalar geniş, alt parçalar dardır)
	var angular_margins = [0.42, 0.25, 0.15, 0.08, 0.05, 0.03]
	var margin = angular_margins[min(cd.level, 5)]
	if world_dir.dot(center_to_cam) < -margin:
		return true

	# 2. Kamera Frustum Culling (Sadece uzaydan bakarken uygulanır)
	# Yüzeyde veya yakın yörüngedeyken (cam_dist < 2.0 * R) 360° ufuk bütünlüğü korunur, gezegen asla silinmez
	if cam_forward != Vector3.ZERO and cam_dist >= _body_radius * 2.0:
		var chunk_pos = real_center + world_dir * _body_radius
		var to_chunk = chunk_pos - real_cam
		var dist_to_chunk = to_chunk.length()
		
		# Parçanın tahmini yarıçapı
		var approx_radius = (_body_radius * 0.45) / pow(2.0, cd.level)
		
		if dist_to_chunk > approx_radius * 1.5:
			var dir_to_chunk = to_chunk / dist_to_chunk
			var angle_subtended = asin(clamp(approx_radius / dist_to_chunk, 0.0, 0.95))
			var cull_cos = cos(deg_to_rad(55.0) + angle_subtended)
			if cam_forward.dot(dir_to_chunk) < cull_cos:
				return true

	return false


func is_ready() -> bool:
	if not _is_active or _root_keys.is_empty():
		return false
	for rkey in _root_keys:
		var cd = _all_chunks.get(rkey)
		if cd == null or not is_instance_valid(cd.mesh):
			return false
	return true


func _evaluate_node(key: String, real_cam: Vector3, real_center: Vector3, cam_forward: Vector3 = Vector3.ZERO) -> void:
	var cd = _all_chunks.get(key)
	if cd == null:
		return

	# Görüş alanı dışı veya ufuk arkası parçaları ağaçtan buda
	if _is_chunk_culled(cd, real_cam, real_center, cam_forward):
		_set_visible(cd, false)
		_hide_all_descendants(key, cd.level, cd.li, cd.lj)
		cd["is_subdivided"] = false
		return

	var level = cd.level
	if level >= MAX_LEVEL:
		cd["is_subdivided"] = false
		_set_visible(cd, true)
		_hide_all_descendants(key, cd.level, cd.li, cd.lj)
		return

	var dist = _chunk_surface_dist(cd, real_cam, real_center)
	var rel = dist / max(_body_radius, 1.0)

	var was_subdivided = cd.get("is_subdivided", false)
	# Histerezis: Zaten bölünmüşse birleşme eşiğini (merge threshold), değilse bölünme eşiğini kullan
	var max_idx = min(LEVEL_MERGE_THRESHOLDS.size() - 1, LEVEL_SUBDIV_THRESHOLDS.size() - 1)
	var idx = clampi(level, 0, max_idx)
	var thresh = LEVEL_MERGE_THRESHOLDS[idx] if was_subdivided else LEVEL_SUBDIV_THRESHOLDS[idx]
	var should_subdivide = (level < MAX_LEVEL and rel < thresh)

	if should_subdivide:
		# Çocukların tümünün üretilmiş ve mesh'lerinin hazır olduğundan emin ol
		var ready = _ensure_children(cd)
		if ready:
			# Çocuklar hazır: Atomik takas! Ebeveyn KESİNLİKLE gizlenir, asla aynı anda görünmez
			cd["is_subdivided"] = true
			_set_visible(cd, false)
			# Yalnızca aktif yapraklar görünür olacak şekilde çocukları değerlendir
			var ckeys = _child_keys(cd.level, cd.li, cd.lj)
			for ckey in ckeys:
				_evaluate_node(ckey, real_cam, real_center, cam_forward)
			return
		else:
			# Çocuklar henüz GPU'da oluşmadıysa ebeveyni ASLA gizleme (boşluk kalmasını önler)
			cd["is_subdivided"] = false
			_set_visible(cd, true)
			var ckeys = _child_keys(cd.level, cd.li, cd.lj)
			for ckey in ckeys:
				var child = _all_chunks.get(ckey)
				if child != null:
					_set_visible(child, false)
			return
	else:
		# Birleşme / Uzak durma: Ebeveyn aktif yapraktır, tüm alt soyları KESİNLİKLE gizle
		cd["is_subdivided"] = false
		_set_visible(cd, true)
		_hide_all_descendants(key, cd.level, cd.li, cd.lj)


func _ensure_children(cd: Dictionary) -> bool:
	var level = cd.level + 1
	var base_li = cd.li * CHILD_NLAT
	var base_lj = cd.lj * CHILD_NLON
	var all_ready = true
	for ci in range(CHILD_NLAT):
		for cj in range(CHILD_NLON):
			var ckey = _ckey(level, base_li + ci, base_lj + cj)
			if not _all_chunks.has(ckey):
				if _builds_this_frame >= MAX_BUILDS_PER_FRAME:
					all_ready = false
					continue
				_create_chunk(level, base_li + ci, base_lj + cj)
				_set_visible(_all_chunks[ckey], false)
				_builds_this_frame += 1
			elif not is_instance_valid(_all_chunks[ckey].mesh):
				all_ready = false
	return all_ready


func _child_keys(level: int, li: int, lj: int) -> Array[String]:
	var res: Array[String] = []
	var base_li = li * CHILD_NLAT
	var base_lj = lj * CHILD_NLON
	for ci in range(CHILD_NLAT):
		for cj in range(CHILD_NLON):
			res.append(_ckey(level + 1, base_li + ci, base_lj + cj))
	return res


func _set_visible(cd: Dictionary, v: bool) -> void:
	if is_instance_valid(cd.mesh):
		cd.mesh.visible = v
	if is_instance_valid(cd.border):
		cd.border.visible = v and _border_visible


func _hide_all_descendants(key: String, level: int, li: int, lj: int) -> void:
	if level >= MAX_LEVEL:
		return
	for ci in range(CHILD_NLAT):
		for cj in range(CHILD_NLON):
			var ckey = _ckey(level + 1, li * CHILD_NLAT + ci, lj * CHILD_NLON + cj)
			var cd = _all_chunks.get(ckey)
			if cd != null:
				cd["is_subdivided"] = false
				_set_visible(cd, false)
				_hide_all_descendants(ckey, level + 1,
					li * CHILD_NLAT + ci, lj * CHILD_NLON + cj)


func _ckey(level: int, li: int, lj: int) -> String:
	return "%d,%d,%d" % [level, li, lj]

func _chunk_center_dir(level: int, li: int, lj: int) -> Vector3:
	var nlat = BASE_NLAT
	var nlon = BASE_NLON
	for _i in range(level):
		nlat *= CHILD_NLAT
		nlon *= CHILD_NLON
	var lat_deg = -90.0 + (li + 0.5) * 180.0 / nlat
	var lon_deg = (lj + 0.5) * 360.0 / nlon
	var lat = deg_to_rad(lat_deg)
	var lon = deg_to_rad(lon_deg)
	return Vector3(cos(lat) * sin(lon), sin(lat), cos(lat) * cos(lon))

func _grid_size(level: int) -> Vector2i:
	var nlat = BASE_NLAT
	var nlon = BASE_NLON
	for _i in range(level):
		nlat *= CHILD_NLAT
		nlon *= CHILD_NLON
	return Vector2i(nlat, nlon)


# ── Çoklu Oktav Analitik Arazi Yüksekliği (Gerçekçi 0 - 6500m Dağlar ve Vadiler) ──
static func sample_terrain_height_static(noise: FastNoiseLite, dir: Vector3, body_radius: float = 6371000.0) -> float:
	if noise == null:
		return 0.0
	# 1. Kıtalar ve Ana Yüzey Biçimleri (Okyanus çukurları ve geniş kıta platoları)
	var continental = noise.get_noise_3dv(dir * 2.2)
	
	# Dağ Maskesi: Yüksek kıtalarda yükselen heybetli sıradağlar
	var mountain_mask = smoothstep(0.08, 0.52, continental)
	
	# Düzlükler ve Ovalar
	var plains = noise.get_noise_3dv(dir * 6.0) * 0.25
	
	# Keskin ve Heybetli Sıradağlar (Dağ sırtları)
	var ridge_raw = 1.0 - absf(noise.get_noise_3dv(dir * 12.0))
	var mountains = pow(ridge_raw, 2.0) * mountain_mask
	
	# Tepeler, kraterler ve platolar
	var hills = noise.get_noise_3dv(dir * 24.0) * 0.20
	
	# Metre cinsinden yükseklik: Kıta platoları (-500m ila +1200m), Dağlar (+4800m), Tepeler (+350m)
	var height_meters = (continental * 1200.0) + (plains * 300.0) + (mountains * 4800.0) + (hills * 350.0)
	return height_meters / maxf(body_radius, 1000.0)

func _sample_terrain_height(dir: Vector3, _level: int = 0) -> float:
	return sample_terrain_height_static(_noise, dir, _body_radius)


# ── Mesh creation ───────────────────────────────────────────────────────────

func _create_chunk(level: int, li: int, lj: int) -> void:
	var gs = _grid_size(level)
	var nlat = gs.x
	var nlon = gs.y
	var subdiv = SUBDIV_LEVELS[min(level, SUBDIV_LEVELS.size() - 1)]

	var verts: PackedVector3Array = []
	var normals: PackedVector3Array = []
	var uvs := PackedVector2Array()
	var indices: PackedInt32Array = []

	var eps = 0.004

	for si in range(subdiv + 1):
		var sf = float(si) / subdiv
		for sj in range(subdiv + 1):
			var tf = float(sj) / subdiv
			var dir = _sphere_point(li, lj, nlat, nlon, sf, tf)
			var h = _sample_terrain_height(dir, level)

			# Yüzey normali: Yerel küresel teğetler üzerinden gradyan hesabı
			var t_lon = Vector3(-dir.z, 0.0, dir.x).normalized()
			if t_lon.length_squared() < 0.001:
				t_lon = Vector3.RIGHT
			var t_lat = dir.cross(t_lon).normalized()

			var h_lon = _sample_terrain_height((dir + t_lon * eps).normalized(), level)
			var h_lat = _sample_terrain_height((dir + t_lat * eps).normalized(), level)
			var dh_dlon = (h_lon - h) / eps
			var dh_dlat = (h_lat - h) / eps

			var norm = (dir - t_lon * (dh_dlon * 3.5) - t_lat * (dh_dlat * 3.5)).normalized()

			verts.append(dir * (1.0 + h))
			normals.append(norm)
			uvs.append(Vector2(1.0 - float(lj + tf) / nlon, 1.0 - float(li + sf) / nlat))

	for si in range(subdiv):
		for sj in range(subdiv):
			var i0 = si * (subdiv + 1) + sj
			var i1 = i0 + 1
			var i2 = (si + 1) * (subdiv + 1) + sj
			var i3 = i2 + 1
			indices.append(i0); indices.append(i2); indices.append(i1)
			indices.append(i1); indices.append(i2); indices.append(i3)

	var arr = []; arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = indices
	var arr_mesh = ArrayMesh.new()
	arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)

	var mi = MeshInstance3D.new()
	mi.mesh = arr_mesh
	var mat = _get_chunk_material(level)
	if mat != null:
		mi.material_override = mat
	mi.extra_cull_margin = 1000000.0
	mi.visible = (level == 0)
	add_child(mi)

	# Border
	var c00 = _sphere_point(li, lj, nlat, nlon, 0.0, 0.0)
	var c01 = _sphere_point(li, lj, nlat, nlon, 0.0, 1.0)
	var c10 = _sphere_point(li, lj, nlat, nlon, 1.0, 0.0)
	var c11 = _sphere_point(li, lj, nlat, nlon, 1.0, 1.0)
	var br = 1.002
	var bv = PackedVector3Array([c00*br, c01*br, c11*br, c10*br, c00*br])
	var ba = []; ba.resize(Mesh.ARRAY_MAX); ba[Mesh.ARRAY_VERTEX] = bv
	var bm = ArrayMesh.new()
	bm.add_surface_from_arrays(Mesh.PRIMITIVE_LINE_STRIP, ba)
	var bmi = MeshInstance3D.new()
	bmi.mesh = bm
	if _border_material != null:
		bmi.material_override = _border_material
	bmi.extra_cull_margin = 1000000.0
	bmi.visible = (level == 0 and _border_visible)
	add_child(bmi)

	_all_chunks[_ckey(level, li, lj)] = {
		"level": level, "li": li, "lj": lj,
		"mesh": mi, "border": bmi,
		"is_subdivided": false
	}


func _sphere_point(li: int, lj: int, nlat: int, nlon: int,
					li_frac: float, lj_frac: float) -> Vector3:
	var lat_deg = -90.0 + (li + li_frac) * 180.0 / nlat
	var lon_deg = (lj + lj_frac) * 360.0 / nlon
	var lat = deg_to_rad(lat_deg)
	var lon = deg_to_rad(lon_deg)
	return Vector3(cos(lat) * sin(lon), sin(lat), cos(lat) * cos(lon))
