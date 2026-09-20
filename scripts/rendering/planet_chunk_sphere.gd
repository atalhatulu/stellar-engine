class_name PlanetChunkSphere
extends Node3D

# =============================================================================
# High-Resolution Multi-Branch Planetary Spherical Chunk LOD (Levels 0 - 11)
# Eliminates low-poly clipping, backface culling, edge cracking, and interior entrapment.
# Achieves 20–50m vertex spacing near the surface with seamless LOD transitions.
# =============================================================================

# Root grid: 6×4 = 24 chunks (60° lon × 45° lat each) - maintains spherical topology
const BASE_NLON: int = 6
const BASE_NLAT: int = 4
const MAX_LEVEL: int = 11

# Each subdivision splits into 4 (2 lon × 2 lat)
const CHILD_NLON: int = 2
const CHILD_NLAT: int = 2

# High-resolution vertex grid per chunk across LOD levels (Level 10-11: 64x64 -> ~27-55m spacing)
const SUBDIV_LEVELS: Array = [24, 32, 40, 48, 56, 56, 56, 56, 56, 56, 64, 64]

# Distance thresholds relative to planet radius (dist / radius)
# Sadece oyuncunun hemen altındaki yerel parçalar derinleşir; gezegenin geri kalanı düşük LOD'da kalır.
const LEVEL_SUBDIV_THRESHOLDS: Array = [
	1.35,     # L0 -> L1 (dist < 4700 km @ R=3477km)
	0.55,     # L1 -> L2 (dist < 1900 km)
	0.22,     # L2 -> L3 (dist < 765 km)
	0.085,    # L3 -> L4 (dist < 295 km)
	0.032,    # L4 -> L5 (dist < 111 km)
	0.012,    # L5 -> L6 (dist < 42 km)
	0.0045,   # L6 -> L7 (dist < 15.6 km)
	0.0018,   # L7 -> L8 (dist < 6.2 km)
	0.00075,  # L8 -> L9 (dist < 2.6 km)
	0.00030,  # L9 -> L10 (dist < 1.0 km)
	0.00010   # L10 -> L11 (dist < 350 m)
]

const LEVEL_MERGE_THRESHOLDS: Array = [
	1.65,     # L0
	0.70,     # L1
	0.28,     # L2
	0.11,     # L3
	0.042,    # L4
	0.016,    # L5
	0.0060,   # L6
	0.0024,   # L7
	0.00100,  # L8
	0.00040,  # L9
	0.00014   # L10
]

# ── Topoğrafya Ölçeği Parametreleri ──────────────────────────────────────────
# Normal kayalık gezegenlerde toplam yükseklik genliği 5–15 km bandındadır (varsayılan: 12 km).
# Debug ve doğrulama için 30–50 km bandına çekilebilir.
static var elevation_scale_km: float = 12.0
static var debug_elevation_override_km: float = 0.0

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
		Color(0.92, 0.20, 0.20), # L0: Kırmızı (Root 24)
		Color(1.00, 0.45, 0.10), # L1: Koyu Turuncu
		Color(1.00, 0.68, 0.15), # L2: Açık Turuncu
		Color(0.95, 0.88, 0.18), # L3: Sarı
		Color(0.65, 0.92, 0.20), # L4: Açık Yeşil
		Color(0.18, 0.88, 0.35), # L5: Zümrüt Yeşili
		Color(0.15, 0.85, 0.70), # L6: Turkuaz
		Color(0.20, 0.65, 1.00), # L7: Açık Mavi
		Color(0.25, 0.40, 0.95), # L8: Koyu Mavi
		Color(0.65, 0.25, 0.95), # L9: Mor (~127m)
		Color(0.95, 0.25, 0.80), # L10: Pembe (~55m)
		Color(1.00, 1.00, 1.00)  # L11: Beyaz (~28m)
	]
	for i in range(colors.size()):
		var mat = StandardMaterial3D.new()
		mat.albedo_color = colors[i]
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.roughness = 0.85
		_debug_materials.append(mat)

func toggle_debug_colors() -> bool:
	debug_color_mode = not debug_color_mode
	_init_debug_materials()
	_refresh_all_materials()
	return debug_color_mode

func get_lod_stats() -> Dictionary:
	var counts = {}
	for lvl in range(MAX_LEVEL + 1):
		counts[lvl] = 0
	var total = 0
	for cd in _all_chunks.values():
		if is_instance_valid(cd.mesh) and cd.mesh.visible:
			var lvl = clampi(cd.level, 0, MAX_LEVEL)
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


# ── Update per frame ────────────────────────────────────────────────────────
func update(origin_offset: Vector3, mesh_pos: Vector3, visual_radius: float,
			real_cam: Vector3, real_center: Vector3, cam_forward: Vector3 = Vector3.ZERO) -> void:
	if not _is_active:
		return
	_builds_this_frame = 0

	# 1. Pozisyon ve ölçek
	position = mesh_pos
	scale = Vector3.ONE * visual_radius

	# 2. Hiyerarşik LOD değerlendirmesi
	for rkey in _root_keys:
		if not _all_chunks.has(rkey):
			continue
		_evaluate_node(rkey, real_cam, real_center, cam_forward)


# ── Görüş alanı dışı ve ufuk arkası parçaları budama (Frustum & Horizon Culling) ──
func _is_chunk_culled(cd: Dictionary, real_cam: Vector3, real_center: Vector3, cam_forward: Vector3) -> bool:
	var dir = _chunk_center_dir(cd.level, cd.li, cd.lj)
	var chunk_pos = real_center + dir * _body_radius

	# Ufuk Arkası (Horizon Occlusion): Gezegenin tam arkasında kalan parçaları çizme
	var to_cam = (real_cam - chunk_pos).normalized()
	if dir.dot(to_cam) < -0.32:
		return true

	# Kamera Arkası (Frustum Culling): Kameranın görüş açısının gerisinde kalan parçalar
	if cam_forward != Vector3.ZERO:
		var to_chunk_from_cam = (chunk_pos - real_cam).normalized()
		# FOV toleransı (110 derece açının gerisi elenir)
		if cam_forward.dot(to_chunk_from_cam) < -0.35:
			var cam_dist = (chunk_pos - real_cam).length()
			# Sadece kameraya çok yakın olmayan parçaları eler
			if cam_dist > _body_radius * 0.15:
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


func _chunk_surface_dist(cd: Dictionary, real_cam: Vector3, real_center: Vector3) -> float:
	var dir = _chunk_center_dir(cd.level, cd.li, cd.lj)
	var pos = real_center + dir * _body_radius
	return (pos - real_cam).length()


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
	var keys: Array[String] = []
	var clvl = level + 1
	var base_li = li * CHILD_NLAT
	var base_lj = lj * CHILD_NLON
	for ci in range(CHILD_NLAT):
		for cj in range(CHILD_NLON):
			keys.append(_ckey(clvl, base_li + ci, base_lj + cj))
	return keys


func _set_visible(cd: Dictionary, v: bool) -> void:
	if cd != null:
		if is_instance_valid(cd.mesh):
			cd.mesh.visible = v
		if is_instance_valid(cd.border):
			cd.border.visible = (v and _border_visible)


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
	return "%d_%d_%d" % [level, li, lj]


func _chunk_center_dir(level: int, li: int, lj: int) -> Vector3:
	var gs = _grid_size(level)
	return _sphere_point(li, lj, gs.x, gs.y, 0.5, 0.5)


func _sphere_point_static(li: int, lj: int, nlat: int, nlon: int,
							li_frac: float, lj_frac: float) -> Vector3:
	var lat_deg = -90.0 + (li + li_frac) * 180.0 / nlat
	var lon_deg = (lj + lj_frac) * 360.0 / nlon
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


# ── Çok Katmanlı Analitik Arazi Yüksekliği (Continental, Mountain, Local-Detail) ──
static func sample_terrain_height_static(noise: FastNoiseLite, dir: Vector3, body_radius: float = 6371000.0) -> float:
	if noise == null:
		return 0.0

	# 1. Kıtalar ve Okyanus/Ova Havzaları (Continental Layer: -3.5 km ila +2.5 km)
	var continental = noise.get_noise_3dv(dir * 1.6)

	# Dağ Maskesi: Sadece kıtasal kabuk üzerinde yükselen heybetli sıradağlar
	var mountain_mask = smoothstep(0.02, 0.45, continental)

	# Düzlükler ve Havzalar (Plains & Basins)
	var plains = noise.get_noise_3dv(dir * 4.5) * 0.20

	# 2. Sıradağlar, Sarp Sırtlar ve Kanyonlar (Mountain Layer: +3.0 km ila +9.0 km)
	var ridge_1 = 1.0 - absf(noise.get_noise_3dv(dir * 7.5))
	var ridge_2 = 1.0 - absf(noise.get_noise_3dv(dir * 16.0))
	var sharp_ridge = (pow(ridge_1, 2.2) * 0.75 + pow(ridge_2, 2.0) * 0.25) * mountain_mask

	# 3. Yerel Detaylar (Local-Detail Layer: Onlarca ve yüzlerce metre ölçeğinde tepecikler, kayalar)
	var local_hills = noise.get_noise_3dv(dir * 36.0) * 0.18
	var local_ridges = (1.0 - absf(noise.get_noise_3dv(dir * 90.0))) * 0.08
	var local_micro = noise.get_noise_3dv(dir * 250.0) * 0.035
	var local_detail = (local_hills + local_ridges + local_micro)

	# Aktif topoğrafya ölçeği (Varsayılan 12 km, debug sırasında 30-50 km)
	var active_scale_km = debug_elevation_override_km if debug_elevation_override_km > 0.0 else elevation_scale_km

	var normalized_elevation = (continental * 0.22) + (plains * 0.08) + (sharp_ridge * 0.60) + (local_detail * 0.10)
	var height_meters = normalized_elevation * (active_scale_km * 1000.0)

	return height_meters / maxf(body_radius, 1000.0)


func _sample_terrain_height(dir: Vector3, _level: int = 0) -> float:
	return sample_terrain_height_static(_noise, dir, _body_radius)


# ── Mesh creation (With Mesh Skirts for Crack-Free LOD Stitching) ───────────
func _create_chunk(level: int, li: int, lj: int) -> void:
	var gs = _grid_size(level)
	var nlat = gs.x
	var nlon = gs.y
	var subdiv = SUBDIV_LEVELS[min(level, SUBDIV_LEVELS.size() - 1)]

	var verts: PackedVector3Array = []
	var normals: PackedVector3Array = []
	var uvs := PackedVector2Array()
	var indices: PackedInt32Array = []

	var eps = 0.003

	for si in range(subdiv + 1):
		var sf = float(si) / subdiv
		for sj in range(subdiv + 1):
			var tf = float(sj) / subdiv
			var dir = _sphere_point(li, lj, nlat, nlon, sf, tf)
			var h = _sample_terrain_height(dir, level)

			# Yüzey normali: Küresel teğet gradyanı üzerinden analitik hesap
			var t_lon = Vector3(-dir.z, 0.0, dir.x).normalized()
			if t_lon.length_squared() < 0.001:
				t_lon = Vector3.RIGHT
			var t_lat = dir.cross(t_lon).normalized()

			var h_lon = _sample_terrain_height((dir + t_lon * eps).normalized(), level)
			var h_lat = _sample_terrain_height((dir + t_lat * eps).normalized(), level)
			var dh_dlon = (h_lon - h) / eps
			var dh_dlat = (h_lat - h) / eps

			var norm = (dir - t_lon * (dh_dlon * 4.0) - t_lat * (dh_dlat * 4.0)).normalized()

			verts.append(dir * (1.0 + h))
			normals.append(norm)
			uvs.append(Vector2(1.0 - float(lj + tf) / nlon, 1.0 - float(li + sf) / nlat))

	# 1. Ana Yüzey Üçgenleri
	for si in range(subdiv):
		for sj in range(subdiv):
			var i0 = si * (subdiv + 1) + sj
			var i1 = i0 + 1
			var i2 = (si + 1) * (subdiv + 1) + sj
			var i3 = i2 + 1
			indices.append(i0); indices.append(i2); indices.append(i1)
			indices.append(i1); indices.append(i2); indices.append(i3)

	# 2. Kenar Eteği (Mesh Skirts): Komşu LOD seviyeleri arasındaki çatlak ve boşlukları sıfırlar
	var skirt_ratio = (1.0 / pow(1.85, level)) * 0.018
	var edge_indices: Array[int] = []
	for sj in range(subdiv):
		edge_indices.append(0 * (subdiv + 1) + sj) # Üst kenar
	for si in range(subdiv):
		edge_indices.append(si * (subdiv + 1) + subdiv) # Sağ kenar
	for sj in range(subdiv, 0, -1):
		edge_indices.append(subdiv * (subdiv + 1) + sj) # Alt kenar
	for si in range(subdiv, 0, -1):
		edge_indices.append(si * (subdiv + 1) + 0) # Sol kenar

	var base_vert_count = verts.size()
	var num_edges = edge_indices.size()
	for k in range(num_edges):
		var top_idx = edge_indices[k]
		var top_v = verts[top_idx]
		var skirt_v = top_v * (1.0 - skirt_ratio)
		verts.append(skirt_v)
		normals.append(normals[top_idx])
		uvs.append(uvs[top_idx])

	for k in range(num_edges):
		var top_curr = edge_indices[k]
		var top_next = edge_indices[(k + 1) % num_edges]
		var skirt_curr = base_vert_count + k
		var skirt_next = base_vert_count + ((k + 1) % num_edges)
		indices.append(top_curr); indices.append(skirt_curr); indices.append(top_next)
		indices.append(top_next); indices.append(skirt_curr); indices.append(skirt_next)

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

	# Sınır Çizgisi (Debug Borders)
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


# ── Altitude / Slope Tabanlı Prosedürel Arazi Materyali Oluşturucu ───────────
static func create_planet_terrain_material(body: CelestialBody = null) -> ShaderMaterial:
	var shader = load("res://shaders/planet_terrain.gdshader") as Shader
	var sm = ShaderMaterial.new()
	sm.shader = shader

	var base_col = body.base_color if body != null else Color(0.55, 0.35, 0.22)
	var body_name = body.name if body != null else ""

	if "Kızıl Gezegen" in body_name:
		sm.set_shader_parameter("color_ocean_deep", Color(0.18, 0.05, 0.02))
		sm.set_shader_parameter("color_lowlands", Color(0.52, 0.18, 0.08))
		sm.set_shader_parameter("color_midlands", Color(0.75, 0.35, 0.16))
		sm.set_shader_parameter("color_highlands", Color(0.92, 0.65, 0.45))
		sm.set_shader_parameter("color_cliff", Color(0.28, 0.10, 0.05))
	elif "Buz Dünyası" in body_name:
		sm.set_shader_parameter("color_ocean_deep", Color(0.12, 0.25, 0.45))
		sm.set_shader_parameter("color_lowlands", Color(0.45, 0.65, 0.85))
		sm.set_shader_parameter("color_midlands", Color(0.75, 0.88, 0.96))
		sm.set_shader_parameter("color_highlands", Color(0.98, 0.99, 1.00))
		sm.set_shader_parameter("color_cliff", Color(0.20, 0.32, 0.50))
	elif "Okyanus Dünyası" in body_name or "Egzotik Yaşam" in body_name:
		sm.set_shader_parameter("color_ocean_deep", Color(0.02, 0.08, 0.28))
		sm.set_shader_parameter("color_lowlands", Color(0.18, 0.45, 0.22))
		sm.set_shader_parameter("color_midlands", Color(0.45, 0.55, 0.28))
		sm.set_shader_parameter("color_highlands", Color(0.85, 0.88, 0.92))
		sm.set_shader_parameter("color_cliff", Color(0.22, 0.20, 0.18))
		# Standart karasal / çöl gezegeni
		sm.set_shader_parameter("color_ocean_deep", base_col.darkened(0.6))
		sm.set_shader_parameter("color_lowlands", base_col.darkened(0.2))
		sm.set_shader_parameter("color_midlands", base_col)
		sm.set_shader_parameter("color_highlands", base_col.lightened(0.55))
		sm.set_shader_parameter("color_cliff", base_col.darkened(0.5))

	var active_scale = debug_elevation_override_km if debug_elevation_override_km > 0.0 else elevation_scale_km
	var p_radius = body.real_radius if body != null else 3477200.0
	var peak_ratio = (active_scale * 1000.0) / maxf(p_radius, 1000.0)
	sm.set_shader_parameter("elevation_peak", peak_ratio)

	return sm
