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

# Quadtree her seviyede doğrusal çözünürlüğü zaten iki katına çıkarır. Derin
# seviyelerde 56/64 kullanmak görünür fayda sağlamadan üretim ve çizim yükünü
# katlıyordu. 32x32, büyük gezegenlerde LOD 11'de yaklaşık 55 m aralık sağlar.
const SUBDIV_LEVELS: Array = [24, 28, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32]

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
static var elevation_scale_km: float = 16.0
static var debug_elevation_override_km: float = 0.0

static func get_elevation_scale_km(body_radius: float) -> float:
	if debug_elevation_override_km > 0.0:
		return debug_elevation_override_km
	# Küçük test gövdesinde 16 km korunur. Ana oyundaki binlerce km
	# yarıçaplı gezegenlerde aynı değer silüette görünmez kaldığından ölçek
	# yarıçapın %0.8'ine kadar çıkar, fakat 32 km'de güvenli biçimde durur.
	return clampf(maxf(elevation_scale_km, body_radius * 0.000010), elevation_scale_km, 32.0)

var _noise: FastNoiseLite = null
var _terrain_material: Material = null
var _border_material: Material = null
var _border_visible: bool = false
var _builds_this_frame := 0
# Chunk meshleri ana thread'de oluşturuluyor. Kare başına 2 mesh,
# ana thread bütçesini 1.0 ms altında tutarken quadtree düğümlerini 2 karede
# tamamlar ve takılma oluşturmaz.
const MAX_BUILDS_PER_FRAME := 2
var _is_active: bool = false
var _body_radius: float = 1.0
var _all_chunks: Dictionary = {}
var _root_keys: Array[String] = []
var _all_borders: Array[MeshInstance3D] = []
var _visibility_alpha: float = 1.0
var _last_focus_direction: Vector3 = Vector3.ZERO


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
		"debug_color_mode": debug_color_mode,
		"focus_direction": _last_focus_direction
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


func set_visibility_alpha(value: float) -> void:
	_visibility_alpha = clampf(value, 0.0, 1.0)
	# Arazi parçaları daima opak olmalıdır; şeffaflık arka plan yıldızlarının
	# gezegen gövdesinin içinden görünmesine (dither sızıntısı) yol açar.
	for cd in _all_chunks.values():
		if is_instance_valid(cd.mesh):
			cd.mesh.transparency = 0.0
	for border in _all_borders:
		if is_instance_valid(border):
			border.transparency = 0.0


func get_visibility_alpha() -> float:
	return _visibility_alpha

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
			real_cam: Vector3, real_center: Vector3, cam_forward: Vector3 = Vector3.ZERO,
			focus_direction_override: Vector3 = Vector3.ZERO) -> void:
	if not _is_active:
		return
	_builds_this_frame = 0

	# 1. Pozisyon ve ölçek
	position = mesh_pos
	scale = Vector3.ONE * visual_radius

	# Yerel koordinat uzayına dönüştür (Gezegenin dönüşü, eksen eğikliği ve koordinat farkını sıfırlar)
	var inv_basis: Basis = global_basis.orthonormalized().inverse() if absf(global_basis.determinant()) > 0.0001 else Basis.IDENTITY
	var local_cam: Vector3 = inv_basis * (real_cam - real_center)
	var local_cam_fwd: Vector3 = (inv_basis * cam_forward).normalized() if cam_forward.length_squared() > 0.001 else Vector3.ZERO

	# 2. Hiyerarşik LOD değerlendirmesi
	var local_lod_observer: Vector3
	if focus_direction_override.length_squared() > 0.001:
		var local_focus_dir := (inv_basis * focus_direction_override).normalized()
		_last_focus_direction = local_focus_dir
		var altitude := maxf(local_cam.length() - _body_radius, 0.0)
		local_lod_observer = local_focus_dir * (_body_radius + altitude)
	else:
		local_lod_observer = _get_view_focused_observer_local(local_cam, local_cam_fwd)

	var prioritized_roots := _sorted_keys_by_distance(_root_keys, local_lod_observer)
	for root_index in range(prioritized_roots.size()):
		var rkey = prioritized_roots[root_index]
		if not _all_chunks.has(rkey):
			continue
		_evaluate_node(rkey, local_lod_observer, local_cam_fwd, root_index == 0)


func _get_view_focused_observer_local(local_cam: Vector3, local_cam_fwd: Vector3) -> Vector3:
	var center_distance := local_cam.length()
	if center_distance < 1.0 or local_cam_fwd.length_squared() < 0.001:
		_last_focus_direction = local_cam.normalized() if center_distance > 0.001 else Vector3.UP
		return local_cam

	var ray_dir := local_cam_fwd.normalized()
	var cam_to_center := -local_cam
	var along_ray := cam_to_center.dot(ray_dir)
	var closest_on_ray := local_cam + ray_dir * maxf(along_ray, 0.0)
	var focus_dir := closest_on_ray.normalized()

	# Işın küreyi kesiyorsa gerçek ön yüz vuruşunu kullan. Kesmiyorsa ışına
	# en yakın yüzey yönü, ufka bakarken kararlı bir odak noktası sağlar.
	var discriminant := along_ray * along_ray - (cam_to_center.length_squared() - _body_radius * _body_radius)
	if along_ray >= 0.0 and discriminant >= 0.0:
		var hit_distance := along_ray - sqrt(discriminant)
		var hit_point := local_cam + ray_dir * maxf(hit_distance, 0.0)
		focus_dir = hit_point.normalized()
	if focus_dir.length_squared() < 0.001:
		focus_dir = local_cam.normalized() if center_distance > 0.001 else Vector3.UP

	_last_focus_direction = focus_dir
	var altitude := maxf(center_distance - _body_radius, 0.0)
	return focus_dir * (_body_radius + altitude)


func _get_view_focused_observer(real_cam: Vector3, real_center: Vector3, cam_forward: Vector3) -> Vector3:
	var center_to_cam := real_cam - real_center
	var center_distance := center_to_cam.length()
	if center_distance < 1.0 or cam_forward.length_squared() < 0.001:
		_last_focus_direction = center_to_cam.normalized()
		return real_cam

	var ray_dir := cam_forward.normalized()
	var cam_to_center := real_center - real_cam
	var along_ray := cam_to_center.dot(ray_dir)
	var closest_on_ray := real_cam + ray_dir * maxf(along_ray, 0.0)
	var focus_dir := (closest_on_ray - real_center).normalized()

	# Işın küreyi kesiyorsa gerçek ön yüz vuruşunu kullan. Kesmiyorsa ışına
	# en yakın yüzey yönü, ufka bakarken kararlı bir odak noktası sağlar.
	var discriminant := along_ray * along_ray - (cam_to_center.length_squared() - _body_radius * _body_radius)
	if along_ray >= 0.0 and discriminant >= 0.0:
		var hit_distance := along_ray - sqrt(discriminant)
		var hit_point := real_cam + ray_dir * maxf(hit_distance, 0.0)
		focus_dir = (hit_point - real_center).normalized()
	if focus_dir.length_squared() < 0.001:
		focus_dir = center_to_cam.normalized()

	_last_focus_direction = focus_dir
	var altitude := maxf(center_distance - _body_radius, 0.0)
	return real_center + focus_dir * (_body_radius + altitude)


# ── Görüş alanı dışı ve ufuk arkası parçaları budama (Frustum & Horizon Culling) ──
func _is_chunk_culled(cd: Dictionary, real_cam: Vector3, real_center: Vector3 = Vector3.ZERO, cam_forward: Vector3 = Vector3.ZERO) -> bool:
	# A centre-point test is not a valid visibility bound for a curved patch:
	# it produced the planet-sized black wedge visible in approach screenshots.
	# RenderingServer already frustum-culls each MeshInstance3D using its AABB.
	# Keep complete spherical coverage until conservative angular bounds exist.
	var _unused = [cd, real_cam, real_center, cam_forward]
	return false


func is_ready() -> bool:
	if not _is_active or _root_keys.is_empty():
		return false
	for rkey in _root_keys:
		var cd = _all_chunks.get(rkey)
		if cd == null or not is_instance_valid(cd.mesh):
			return false
	return true


func _evaluate_node(key: String, local_cam: Vector3, local_cam_fwd: Vector3 = Vector3.ZERO, prioritize: bool = false) -> void:
	var cd = _all_chunks.get(key)
	if cd == null:
		return

	# Görüş alanı dışı veya ufuk arkası parçaları ağaçtan buda
	if _is_chunk_culled(cd, local_cam, Vector3.ZERO, local_cam_fwd):
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

	var dist = _chunk_surface_dist(cd, local_cam)
	var rel = dist / max(_body_radius, 1.0)

	var was_subdivided = cd.get("is_subdivided", false)
	# Histerezis: Zaten bölünmüşse birleşme eşiğini (merge threshold), değilse bölünme eşiğini kullan
	var max_idx = min(LEVEL_MERGE_THRESHOLDS.size() - 1, LEVEL_SUBDIV_THRESHOLDS.size() - 1)
	var idx = clampi(level, 0, max_idx)
	var thresh = LEVEL_MERGE_THRESHOLDS[idx] if was_subdivided else LEVEL_SUBDIV_THRESHOLDS[idx]
	
	# Kamera bakış yönüne öncelik veren quadtree bütçesi (Grup 4)
	# Kameranın hemen yakınındaki/altındaki parçalar (rel < 0.003) oyuncu ufka baksa bile
	# ayak altı/gövde altı detayının düşmemesi için sınırlanmaz.
	var max_allowed_level = MAX_LEVEL
	var is_nearby = rel < 0.003
	if not is_nearby and local_cam_fwd.length_squared() > 0.001:
		var cdir = _chunk_center_dir(cd.level, cd.li, cd.lj)
		var chunk_pos = cdir * _body_radius
		var cam_to_chunk = (chunk_pos - local_cam).normalized()
		var forward_dot = local_cam_fwd.normalized().dot(cam_to_chunk)
		if forward_dot < -0.25:
			# Kamera arkasındaki parçalar için quadtree bütçe sınırlaması (LOD 4 tavanı)
			max_allowed_level = 4
			thresh *= 0.65
		elif forward_dot < 0.15:
			# Çevresel/yan bakış parçaları için bütçe sınırlaması (LOD 7 tavanı)
			max_allowed_level = 7
			thresh *= 0.85

	var should_subdivide = (level < max_allowed_level and rel < thresh)

	if should_subdivide:
		# Çocukların tümünün üretilmiş ve mesh'lerinin hazır olduğundan emin ol
		var ready = _ensure_children(cd)
		if ready:
			# Çocuklar hazır: Atomik takas! Ebeveyn KESİNLİKLE gizlenir, asla aynı anda görünmez
			cd["is_subdivided"] = true
			_set_visible(cd, false)
			# Yalnızca aktif yapraklar görünür olacak şekilde çocukları değerlendir
			var ckeys = _child_keys(cd.level, cd.li, cd.lj)
			if prioritize:
				ckeys = _sorted_keys_by_distance(ckeys, local_cam)
			for child_index in range(ckeys.size()):
				_evaluate_node(ckeys[child_index], local_cam, local_cam_fwd, prioritize and child_index == 0)
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


func _chunk_surface_dist(cd: Dictionary, observer: Vector3, center: Vector3 = Vector3.ZERO) -> float:
	var dir = _chunk_center_dir(cd.level, cd.li, cd.lj)
	# LOD uzaklığını deniz seviyesi küresinden değil, üretilmiş arazinin
	# gerçek yarıçapından ölç. Dağın üzerinde duran kamera aksi halde arazi
	# yüksekliği kadar uzakta sanılıyor ve son seviye açılmıyordu.
	var terrain_radius = _body_radius * (1.0 + _sample_terrain_height(dir, cd.level))
	var pos = center + dir * terrain_radius
	# Merkez uzaklığı küçük parçalarda yeterli olsa da kamera chunk kenarına
	# yaklaştığında gerçek yüzeyi kilometrelerce uzakta sanıyordu. Chunk'ın
	# küresel kapladığı alanı bir sınır yarıçapı olarak çıkar; böylece kameranın
	# altında kalan yaprak LOD 11'e kadar ilerleyebilir.
	var gs = _grid_size(cd.level)
	var half_lat = (PI / float(gs.x)) * 0.5
	var half_lon = (TAU / float(gs.y)) * 0.5
	var center_lat = -PI * 0.5 + (float(cd.li) + 0.5) * (PI / float(gs.x))
	var angular_radius = sqrt(half_lat * half_lat + pow(half_lon * cos(center_lat), 2.0))
	var patch_radius = _body_radius * angular_radius
	return maxf((pos - observer).length() - patch_radius, 0.0)


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


func _sorted_keys_by_distance(keys: Array[String], observer: Vector3, center: Vector3 = Vector3.ZERO) -> Array[String]:
	var sorted := keys.duplicate()
	sorted.sort_custom(func(a: String, b: String) -> bool:
		var a_chunk = _all_chunks.get(a)
		var b_chunk = _all_chunks.get(b)
		if a_chunk == null: return false
		if b_chunk == null: return true
		return _chunk_surface_dist(a_chunk, observer, center) < _chunk_surface_dist(b_chunk, observer, center)
	)
	return sorted


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
	# FastNoiseLite girdiyi kendi frequency değeriyle yeniden çarpar. Küresel
	# koordinatlar birim vektör olduğu için eski değerler bütün gezegende
	# gürültünün çok küçük, neredeyse düz bir bölümünü örnekliyordu.
	var domain = 1.0 / maxf(noise.frequency, 0.0001)

	# 1. Kıtalar ve Okyanus/Ova Havzaları (Continental Layer: -3.5 km ila +2.5 km)
	var continental = noise.get_noise_3dv(dir * (1.6 * domain))

	# Dağ Maskesi: Kıtasal kütleler ve tektonik plaka sınırlarında yükselen heybetli sıradağlar
	var mountain_mask = smoothstep(-0.12, 0.40, continental)

	# Düzlükler ve Havzalar (Plains & Basins)
	var plains = continental * 0.20

	# 2. Sıradağlar, Sarp Sırtlar ve Kanyonlar (Mountain Layer: Ridged Multifractal)
	var ridge_1 = 1.0 - absf(noise.get_noise_3dv(dir * (7.5 * domain)))
	var ridge_2 = 1.0 - absf(noise.get_noise_3dv(dir * (16.0 * domain)))
	var sharp_ridge = (pow(ridge_1, 2.2) * 0.70 + pow(ridge_2, 2.0) * 0.30) * mountain_mask

	# 3. Kanyon ve Okyanus Hendekleri (Rifts & Trenches)
	var rift_raw = absf(noise.get_noise_3dv(dir * (4.5 * domain)))
	var rift = (1.0 - smoothstep(0.0, 0.12, rift_raw)) * (1.0 - mountain_mask) * 0.25

	# 4. Yerel Detaylar (Local-Detail Layer: Onlarca ve yüzlerce metre ölçeğinde tepecikler, kayalar)
	var local_hills_raw = noise.get_noise_3dv(dir * (36.0 * domain))
	var local_hills = local_hills_raw * 0.18
	# Aynı yerel sinyalin mutlak değeri sırt maskesi olarak tekrar kullanılır.
	var local_ridges = (1.0 - absf(local_hills_raw)) * 0.06
	# Kilometre ölçekli geometri: yakın yüzeyde gerçek tepe ve kaya sırtı verir.
	var local_micro_raw = noise.get_noise_3dv(dir * (2400.0 * domain))
	var local_micro = local_micro_raw * 0.075
	var ultra_ridge = (1.0 - absf(local_micro_raw)) * 0.022
	var local_detail = (local_hills + local_ridges + local_micro + ultra_ridge)

	# Aktif topoğrafya ölçeği (Varsayılan 16 km, gezegen yarıçapına orantılı)
	var active_scale_km = get_elevation_scale_km(body_radius)

	var normalized_elevation = (continental * 0.26) + (plains * 0.06) + (sharp_ridge * 0.62) - rift + (local_detail * 0.10)
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

	# Önce yalnızca konumları örnekle. Eski yöntem normal hesabı için her
	# vertex'te iki ek yükseklik örneği alıyor ve noise maliyetini üçe katlıyordu.
	for si in range(subdiv + 1):
		var sf = float(si) / subdiv
		for sj in range(subdiv + 1):
			var tf = float(sj) / subdiv
			var dir = _sphere_point(li, lj, nlat, nlon, sf, tf)
			var h = _sample_terrain_height(dir, level)

			verts.append(dir * (1.0 + h))
			uvs.append(Vector2(1.0 - float(lj + tf) / nlon, 1.0 - float(li + sf) / nlat))

	# Komşu vertex farklarından normal üret. Bu yöntem örneklenmiş gerçek mesh
	# eğimini kullanır ve ilave noise sorgusu gerektirmez.
	for si in range(subdiv + 1):
		for sj in range(subdiv + 1):
			var left_i = si * (subdiv + 1) + maxi(sj - 1, 0)
			var right_i = si * (subdiv + 1) + mini(sj + 1, subdiv)
			var lower_i = maxi(si - 1, 0) * (subdiv + 1) + sj
			var upper_i = mini(si + 1, subdiv) * (subdiv + 1) + sj
			var tangent_lon = verts[right_i] - verts[left_i]
			var tangent_lat = verts[upper_i] - verts[lower_i]
			var normal = tangent_lon.cross(tangent_lat).normalized()
			var vertex_dir = verts[si * (subdiv + 1) + sj].normalized()
			# Enlem-boylam küresinin kutup satırında boylam teğeti sıfırdır.
			# Sıfır normal ışık/sivri birleşme artefaktı üretmesin.
			if normal.length_squared() < 0.25:
				normal = vertex_dir
			if normal.dot(vertex_dir) < 0.0:
				normal = -normal
			normals.append(normal)

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
	# The old percentage-based skirt was several kilometres deep on large planets,
	# so a harmless LOD seam appeared as a black canyon.  Derive the depth from
	# local vertex spacing and cap it in world metres.
	var angular_span = maxf(PI / float(nlat), TAU / float(nlon))
	var vertex_spacing_m = _body_radius * angular_span / float(subdiv)
	var skirt_depth_m = clampf(vertex_spacing_m * 0.32, 1.5, 64.0)
	var skirt_ratio = skirt_depth_m / _body_radius
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
		# Bütün boylamlar kutupta aynı vertexe kapanır. Burada etek aşağı
		# uzatılırsa üst/alt birleşimde siyah iğne ve yıldız biçimli yarık oluşur.
		var at_pole := absf(top_v.normalized().y) > 0.999999
		var skirt_v = top_v if at_pole else top_v * (1.0 - skirt_ratio)
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
	mi.transparency = 0.0
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
	bmi.transparency = 0.0
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
		sm.set_shader_parameter("color_ocean_deep", Color(0.24, 0.08, 0.04))
		sm.set_shader_parameter("color_lowlands", Color(0.62, 0.25, 0.12))
		sm.set_shader_parameter("color_midlands", Color(0.82, 0.44, 0.22))
		sm.set_shader_parameter("color_highlands", Color(0.96, 0.74, 0.58))
		sm.set_shader_parameter("color_cliff", Color(0.38, 0.14, 0.08))
	elif "Buz Dünyası" in body_name:
		sm.set_shader_parameter("color_ocean_deep", Color(0.10, 0.24, 0.48))
		sm.set_shader_parameter("color_lowlands", Color(0.48, 0.68, 0.88))
		sm.set_shader_parameter("color_midlands", Color(0.78, 0.90, 0.98))
		sm.set_shader_parameter("color_highlands", Color(1.00, 1.00, 1.00))
		sm.set_shader_parameter("color_cliff", Color(0.24, 0.36, 0.52))
	elif "Okyanus Dünyası" in body_name or "Egzotik Yaşam" in body_name:
		sm.set_shader_parameter("color_ocean_deep", Color(0.01, 0.07, 0.28))
		sm.set_shader_parameter("color_lowlands", Color(0.14, 0.46, 0.20))
		sm.set_shader_parameter("color_midlands", Color(0.44, 0.58, 0.26))
		sm.set_shader_parameter("color_highlands", Color(0.86, 0.90, 0.94))
		sm.set_shader_parameter("color_cliff", Color(0.26, 0.22, 0.18))
	elif "Sıcak Çöl" in body_name:
		sm.set_shader_parameter("color_ocean_deep", Color(0.32, 0.18, 0.10))
		sm.set_shader_parameter("color_lowlands", Color(0.66, 0.44, 0.26))
		sm.set_shader_parameter("color_midlands", Color(0.88, 0.68, 0.46))
		sm.set_shader_parameter("color_highlands", Color(0.98, 0.88, 0.74))
		sm.set_shader_parameter("color_cliff", Color(0.44, 0.26, 0.15))
	else:
		# Standart karasal dünya (derin lacivert okyanuslar, zümrüt kıyılar, kayalık yaylalar, karlı granit zirveler)
		sm.set_shader_parameter("color_ocean_deep", Color(0.03, 0.11, 0.24))
		sm.set_shader_parameter("color_lowlands", Color(0.18, 0.38, 0.16))
		sm.set_shader_parameter("color_midlands", Color(0.48, 0.42, 0.32))
		sm.set_shader_parameter("color_highlands", Color(0.90, 0.92, 0.96))
		sm.set_shader_parameter("color_cliff", Color(0.28, 0.22, 0.18))

	var p_radius = body.real_radius if body != null else 3477200.0
	var active_scale = get_elevation_scale_km(p_radius)
	var peak_ratio = (active_scale * 1000.0) / maxf(p_radius, 1000.0)
	sm.set_shader_parameter("elevation_peak", peak_ratio)

	return sm
