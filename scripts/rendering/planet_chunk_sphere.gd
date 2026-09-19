class_name PlanetChunkSphere
extends Node3D

# =============================================================================
# High-Resolution Multi-Branch Planetary Spherical Chunk LOD
# Eliminates low-poly clipping, backface culling, and interior camera entrapment.
# =============================================================================

# Root grid: 6×4 = 24 chunks (60° lon × 45° lat each) - maintains spherical topology
const BASE_NLON: int = 6
const BASE_NLAT: int = 4
const MAX_LEVEL: int = 4

# Each subdivision splits into 4 (2 lon × 2 lat)
const CHILD_NLON: int = 2
const CHILD_NLAT: int = 2

# High-resolution vertex grid per chunk across LOD levels
const SUBDIV_LEVELS: Array = [16, 24, 32, 40, 48]

# Distance thresholds relative to planet radius (dist / radius)
const LEVEL_SUBDIV_THRESHOLDS: Array = [1.4, 0.65, 0.25, 0.08]
const LEVEL_MERGE_THRESHOLDS: Array = [1.65, 0.80, 0.32, 0.12]

var _noise: FastNoiseLite = null
var _terrain_material: Material = null
var _border_material: Material = null
var _border_visible: bool = false
var _builds_this_frame := 0
const MAX_BUILDS_PER_FRAME := 4
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


func set_material(mat: Material) -> void:
	if mat != null:
		# Çift taraflı render: kameranın arkasında kalma / zemin şeffaflaşma sorununu önler
		if mat is StandardMaterial3D:
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_terrain_material = mat
	for cd in _all_chunks.values():
		if is_instance_valid(cd.mesh):
			cd.mesh.material_override = mat

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
			real_cam: Vector3, real_center: Vector3) -> void:
	if not _is_active:
		return
	_builds_this_frame = 0

	# Kameranın yakınındaki tüm kök parçaları değerlendir
	for rkey in _root_keys:
		if not _all_chunks.has(rkey):
			continue
		var cd = _all_chunks[rkey]
		var dist = _chunk_surface_dist(cd, real_cam, real_center)
		var rel = dist / max(_body_radius, 1.0)
		if rel < LEVEL_SUBDIV_THRESHOLDS[0]:
			_evaluate_node(rkey, real_cam, real_center)
		elif rel > LEVEL_MERGE_THRESHOLDS[0]:
			_set_visible(cd, true)
			_hide_all_descendants(rkey, cd.level, cd.li, cd.lj)


func _chunk_surface_dist(cd: Dictionary, real_cam: Vector3, real_center: Vector3) -> float:
	var dir = _chunk_center_dir(cd.level, cd.li, cd.lj)
	var pos = real_center + dir * _body_radius
	# Doğrudan yüzey noktasına olan gerçek mesafe (hatalı çıkarma işlemi kaldırıldı)
	return (pos - real_cam).length()


func _evaluate_node(key: String, real_cam: Vector3, real_center: Vector3) -> void:
	var cd = _all_chunks.get(key)
	if cd == null:
		return

	var dist = _chunk_surface_dist(cd, real_cam, real_center)
	var rel = dist / max(_body_radius, 1.0)
	var level = cd.level

	if level < MAX_LEVEL and rel < LEVEL_SUBDIV_THRESHOLDS[level]:
		# Bu parçayı alt bölümlere ayır (tüm çocukları oluştur ve göster)
		if not _ensure_children(cd):
			return
		_set_visible(cd, false)
		_show_all_children(cd)

		# Çoklu yol değerlendirmesi: Kameraya yakın olan tüm çocukları derinlemesine işle
		var ckeys = _child_keys(cd.level, cd.li, cd.lj)
		for ckey in ckeys:
			_evaluate_node(ckey, real_cam, real_center)
	elif rel > LEVEL_MERGE_THRESHOLDS[min(level, LEVEL_MERGE_THRESHOLDS.size() - 1)]:
		# Mesafeden dolayı bu seviyede birleştir
		_set_visible(cd, true)
		_hide_all_descendants(key, cd.level, cd.li, cd.lj)


func _ensure_children(cd: Dictionary) -> bool:
	var level = cd.level + 1
	var base_li = cd.li * CHILD_NLAT
	var base_lj = cd.lj * CHILD_NLON
	for ci in range(CHILD_NLAT):
		for cj in range(CHILD_NLON):
			var ckey = _ckey(level, base_li + ci, base_lj + cj)
			if not _all_chunks.has(ckey):
				if _builds_this_frame >= MAX_BUILDS_PER_FRAME:
					return false
				_create_chunk(level, base_li + ci, base_lj + cj)
				_set_visible(_all_chunks[ckey], false)
				_builds_this_frame += 1
	return true


func _show_all_children(cd: Dictionary) -> void:
	var level = cd.level + 1
	var base_li = cd.li * CHILD_NLAT
	var base_lj = cd.lj * CHILD_NLON
	for ci in range(CHILD_NLAT):
		for cj in range(CHILD_NLON):
			var ckey = _ckey(level, base_li + ci, base_lj + cj)
			var child = _all_chunks.get(ckey)
			if child != null:
				_set_visible(child, true)


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


# ── Çoklu Oktav Analitik Arazi Yüksekliği ───────────────────────────────────
func _sample_terrain_height(dir: Vector3, level: int) -> float:
	if _noise == null:
		return 0.0
	var mountain = _noise.get_noise_3dv(dir * 3.5) * 0.022
	var ridge = (1.0 - absf(_noise.get_noise_3dv(dir * 7.0))) * 0.012
	var hills = _noise.get_noise_3dv(dir * 18.0) * 0.005
	var h = mountain + ridge + hills
	if level > 0:
		var micro = _noise.get_noise_3dv(dir * 45.0) * (0.003 / float(level + 1))
		h += micro
	return h


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

	var eps = 0.005

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

			var norm = (dir - t_lon * (dh_dlon * 2.0) - t_lat * (dh_dlat * 2.0)).normalized()

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
	if _terrain_material != null:
		mi.material_override = _terrain_material
	mi.extra_cull_margin = 1000000.0
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
	bmi.visible = _border_visible
	add_child(bmi)

	_all_chunks[_ckey(level, li, lj)] = {
		"level": level, "li": li, "lj": lj,
		"mesh": mi, "border": bmi
	}


func _sphere_point(li: int, lj: int, nlat: int, nlon: int,
					li_frac: float, lj_frac: float) -> Vector3:
	var lat_deg = -90.0 + (li + li_frac) * 180.0 / nlat
	var lon_deg = (lj + lj_frac) * 360.0 / nlon
	var lat = deg_to_rad(lat_deg)
	var lon = deg_to_rad(lon_deg)
	return Vector3(cos(lat) * sin(lon), sin(lat), cos(lat) * cos(lon))
