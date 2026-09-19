class_name PlanetLODManager
extends Node3D

# =============================================================================
# Mesh-Based Chunked LOD terrain system for planet surfaces
# Supports both surface mode (walking) and flyover mode (orbit/approach)
# =============================================================================

const CHUNK_SIZE_BASE: float = 2000.0
var _chunk_size: float = 2000.0
# GRID_RADIUS: how many chunks on each side of the player. Total = (2*R+1)^2
const GRID_RADIUS: int = 4

# LOD levels: subdivision count → 2D distance threshold (excl. altitude)
# Rebalanced for high performance with crisp terrain visuals
static var LOD_LEVELS: Array = [
	{ "subdiv": 40, "dist": 450.0 },   # LOD0: ultra detay (~1681 tepe noktası)
	{ "subdiv": 24, "dist": 1200.0 },  # LOD1: yüksek detay
	{ "subdiv": 14, "dist": 3000.0 },  # LOD2: orta detay
	{ "subdiv": 6,  "dist": 7000.0 },  # LOD3: ufuk çizgisi
	{ "subdiv": 2,  "dist": INF },     # LOD4: en uzak ufuk
]

# Çok Katmanlı Analitik Fraktal Arazi Yükseklik Fonksiyonu
static func sample_surface_height(wx: float, wz: float, noise: FastNoiseLite, base_scale: float = 0.002, max_h: float = 350.0) -> float:
	if noise == null:
		return 0.0
	# 1. Makro dağ sıraları ve vadiler (doğal jeolojik ölçek)
	var macro = noise.get_noise_2d(wx * base_scale, wz * base_scale) * max_h
	# 2. Orta sırt ve tepe sırtları
	var ridge = (1.0 - absf(noise.get_noise_2d(wx * base_scale * 3.2, wz * base_scale * 3.2))) * (max_h * 0.35)
	# 3. Mikro kayalık ve zemin engebeleri
	var micro = noise.get_noise_2d(wx * base_scale * 10.0, wz * base_scale * 10.0) * (max_h * 0.08)
	return macro + ridge + micro

# Chunk data dictionary keys: "lod", "mesh" (MeshInstance3D), "gx", "gz"
var _chunks: Dictionary = {}
# Mesh creation has a soft time budget and a hard chunk limit per update.
const BUILD_BUDGET_USEC := 1500
const MAX_BUILDS_PER_FRAME := 2
var _build_queue: Array[String] = []
var last_build_usec := 0
var last_build_count := 0

var _noise: FastNoiseLite = null
var _target_body: CelestialBody = null
var _noise_scale: float = 0.002
var _noise_height: float = 350.0

# Tangent plane basis (world-space vectors that define the terrain plane)
var _local_up: Vector3 = Vector3.UP
var _local_x: Vector3 = Vector3.RIGHT
var _local_z: Vector3 = Vector3.FORWARD

var _last_grid_x: int = -999999
var _last_grid_z: int = -999999
var _last_eye_int: int = -999999
var _is_active: bool = false
var _eye_height: float = 1.8

# Cached material (reused across all chunks)
var _terrain_material: Material = null
var debug_color_mode: bool = false
var _debug_materials: Array[StandardMaterial3D] = []

# Flyover mode: when true, the LOD system is viewed from above (orbit/approach)
var _is_flyover: bool = false


func _init_debug_materials() -> void:
	if not _debug_materials.is_empty():
		return
	var colors = [
		Color(0.18, 0.90, 0.32), # LOD 0: Ultra Yeşil (40x40)
		Color(0.20, 0.65, 1.00), # LOD 1: Canlı Mavi (24x24)
		Color(0.96, 0.85, 0.18), # LOD 2: Parlak Sarı (14x14)
		Color(1.00, 0.50, 0.12), # LOD 3: Turuncu (6x6)
		Color(0.92, 0.22, 0.22)  # LOD 4: Kırmızı (2x2)
	]
	for i in range(colors.size()):
		var mat = StandardMaterial3D.new()
		mat.albedo_color = colors[i]
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.roughness = 0.8
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		_debug_materials.append(mat)

func toggle_debug_colors() -> bool:
	debug_color_mode = not debug_color_mode
	_init_debug_materials()
	_refresh_all_materials()
	return debug_color_mode

func _refresh_all_materials() -> void:
	for key in _chunks:
		var cd = _chunks[key]
		if is_instance_valid(cd.mesh):
			cd.mesh.material_override = _get_chunk_material(cd.lod)

func _get_chunk_material(lod: int) -> Material:
	if debug_color_mode:
		_init_debug_materials()
		var clamped_lod = clampi(lod, 0, _debug_materials.size() - 1)
		return _debug_materials[clamped_lod]
	if _terrain_material != null:
		if _terrain_material is StandardMaterial3D:
			_terrain_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		return _terrain_material
	return null

func get_lod_stats() -> Dictionary:
	var counts = { 0: 0, 1: 0, 2: 0, 3: 0, 4: 0 }
	var total = 0
	for key in _chunks:
		var cd = _chunks[key]
		var lod = clampi(cd.get("lod", 0), 0, 4)
		counts[lod] = counts.get(lod, 0) + 1
		total += 1
	return {
		"total_chunks": total,
		"lod_counts": counts,
		"build_queue_size": _build_queue.size(),
		"last_build_usec": last_build_usec,
		"last_build_count": last_build_count,
		"debug_color_mode": debug_color_mode,
		"eye_height": _eye_height,
		"is_flyover": _is_flyover,
		"grid_pos": Vector2i(_last_grid_x, _last_grid_z)
	}


# ── Public API ──────────────────────────────────────────────────────────────

func initialize(body: CelestialBody, noise: FastNoiseLite,
				up: Vector3, lx: Vector3, lz: Vector3,
				eye_height: float = 1.8) -> void:
	_target_body = body
	_noise = noise
	_local_up = up
	_local_x = lx
	_local_z = lz
	_eye_height = eye_height
	_is_active = true
	_is_flyover = false
	_last_grid_x = -999999
	_last_grid_z = -999999
	_last_eye_int = -999999

func start_flyover(body: CelestialBody, p_noise: FastNoiseLite, eye_height: float) -> void:
	_target_body = body
	_noise = p_noise
	_eye_height = max(eye_height, 1.8)
	_is_active = true
	_is_flyover = true
	_last_grid_x = -999999
	_last_grid_z = -999999
	_last_eye_int = -999999

func set_noise_params(scale: float, height: float) -> void:
	_noise_scale = scale
	_noise_height = height

func set_material(mat: Material) -> void:
	_terrain_material = mat

func set_tangent_basis(up: Vector3, lx: Vector3, lz: Vector3) -> void:
	_local_up = up
	_local_x = lx
	_local_z = lz

func set_eye_height(h: float) -> void:
	_eye_height = max(h, 1.0)

func set_chunk_size(size: float) -> void:
	# Sadece %20'den fazla değişimde rebuild tetikle
	var old = _chunk_size
	_chunk_size = max(size, CHUNK_SIZE_BASE)
	if abs(_chunk_size - old) / max(old, 1.0) > 0.2:
		_last_grid_x = -999999
		_last_grid_z = -999999

func is_active() -> bool:
	return _is_active

func get_target_body() -> CelestialBody:
	return _target_body

func update(walk_offset_x: float, walk_offset_z: float) -> void:
	if not _is_active:
		return
	var gx := floori(walk_offset_x / _chunk_size)
	var gz := floori(walk_offset_z / _chunk_size)
	var eh_int := int(_eye_height / 5.0)
	if gx != _last_grid_x or gz != _last_grid_z or (_is_flyover and eh_int != _last_eye_int):
		_last_grid_x = gx
		_last_grid_z = gz
		_last_eye_int = eh_int
		_sync_chunks(gx, gz, walk_offset_x, walk_offset_z)
	_process_build_queue(walk_offset_x, walk_offset_z)
	# Geometry is cached; camera-relative placement must still follow every step.
	_update_all_chunk_transforms(walk_offset_x, walk_offset_z)

func _process_build_queue(wox: float, woz: float) -> void:
	var started := Time.get_ticks_usec()
	last_build_count = 0
	while not _build_queue.is_empty():
		var key: String = _build_queue.pop_front()
		if not _chunks.has(key):
			continue
		var cd: Dictionary = _chunks[key]
		_build_chunk(cd.gx, cd.gz, wox, woz, cd)
		cd.built_lod = cd.lod
		last_build_count += 1
		if last_build_count >= MAX_BUILDS_PER_FRAME or Time.get_ticks_usec() - started >= BUILD_BUDGET_USEC:
			break
	last_build_usec = Time.get_ticks_usec() - started


func clear() -> void:
	for key in _chunks.keys():
		_remove_chunk(key)
	_chunks.clear()
	_build_queue.clear()
	_is_active = false
	_is_flyover = false


# ── Internal chunk management ───────────────────────────────────────────────

func _sync_chunks(px: int, pz: int, wox: float, woz: float) -> void:
	# Step 1: Determine the set of needed positions for the NEW player grid position
	var min_gx = px - GRID_RADIUS
	var max_gx = px + GRID_RADIUS
	var min_gz = pz - GRID_RADIUS
	var max_gz = pz + GRID_RADIUS

	# Step 2: Remove chunks outside new range (sliding window edge)
	var to_remove: Array[String] = []
	for key in _chunks:
		var cd = _chunks[key]
		if cd.gx < min_gx or cd.gx > max_gx or cd.gz < min_gz or cd.gz > max_gz:
			to_remove.append(key)

	for key in to_remove:
		_remove_chunk(key)

	# Keep the old mesh until its replacement is ready. Prioritize near terrain.
	_build_queue.clear()
	for dx in range(-GRID_RADIUS, GRID_RADIUS + 1):
		for dz in range(-GRID_RADIUS, GRID_RADIUS + 1):
			var wx := px + dx
			var wz := pz + dz
			var key := "%d,%d" % [wx, wz]
			var lod := _calc_lod(float(maxi(absi(dx), absi(dz))) * _chunk_size)
			if not _chunks.has(key):
				_chunks[key] = {"lod": lod, "built_lod": -1, "mesh": null, "gx": wx, "gz": wz}
			var cd: Dictionary = _chunks[key]
			cd.lod = lod
			if cd.built_lod != lod:
				_build_queue.append(key)
	_build_queue.sort_custom(func(a, b):
		var ca: Dictionary = _chunks[a]
		var cb: Dictionary = _chunks[b]
		return Vector2(ca.gx - px, ca.gz - pz).length_squared() < Vector2(cb.gx - px, cb.gz - pz).length_squared())


func _calc_lod(dist: float) -> int:
	# For flyover mode, include eye height in distance calculation
	var effective_dist = dist
	if _is_flyover:
		effective_dist = sqrt(dist * dist + _eye_height * _eye_height * 0.25)

	for i in range(LOD_LEVELS.size()):
		if effective_dist <= LOD_LEVELS[i]["dist"]:
			return i
	return LOD_LEVELS.size() - 1


func _remove_chunk(key: String) -> void:
	if not _chunks.has(key):
		return
	var cd = _chunks[key]
	if is_instance_valid(cd.mesh):
		cd.mesh.queue_free()
	_chunks.erase(key)


func _build_chunk(gx: int, gz: int, wox: float, woz: float, cd: Dictionary) -> void:
	# Delete old mesh
	if is_instance_valid(cd.mesh):
		cd.mesh.queue_free()
		cd.mesh = null

	var lod = clampi(cd.lod, 0, LOD_LEVELS.size() - 1)
	var subdiv = LOD_LEVELS[lod]["subdiv"]

	var chunk_center_x = gx * _chunk_size + _chunk_size * 0.5
	var chunk_center_z = gz * _chunk_size + _chunk_size * 0.5
	var step = _chunk_size / float(subdiv)
	var half_size = _chunk_size * 0.5

	# Doğrudan SurfaceTool ile hızlı yüzey üretimi ve küresel eğrilik (planet curvature) hesabı
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var planet_r = _target_body.real_radius if _target_body != null else 6371000.0

	for iz in range(subdiv + 1):
		var lz = -half_size + iz * step
		var wz = chunk_center_z + lz
		var v = float(iz) / float(subdiv)
		var rel_z = wz
		for ix in range(subdiv + 1):
			var lx = -half_size + ix * step
			var wx = chunk_center_x + lx
			var u = float(ix) / float(subdiv)
			var h = sample_surface_height(wx, wz, _noise, _noise_scale, _noise_height)
				
			# Gerçek küresel eğrilik (ufuk çizgisi alçalması): d^2 / (2 * R)
			var rel_x = wx
			var dist_sq = rel_x * rel_x + rel_z * rel_z
			var curvature_drop = dist_sq / (2.0 * planet_r)
			
			st.set_uv(Vector2(u, v))
			st.add_vertex(Vector3(lx, h - curvature_drop, lz))

	for iz in range(subdiv):
		for ix in range(subdiv):
			var i0 = iz * (subdiv + 1) + ix
			var i1 = i0 + 1
			var i2 = (iz + 1) * (subdiv + 1) + ix
			var i3 = i2 + 1
			st.add_index(i0)
			st.add_index(i2)
			st.add_index(i1)
			st.add_index(i1)
			st.add_index(i2)
			st.add_index(i3)

	st.generate_normals()
	st.generate_tangents()
	var final_mesh = st.commit()

	# ── Create MeshInstance ──
	var mi = MeshInstance3D.new()
	mi.mesh = final_mesh

	# ── Material (Çift taraflı render ve dinamik LOD debug renklendirmesi) ──
	var mat = _get_chunk_material(lod)
	if mat != null:
		mi.material_override = mat

	# ── Position chunk ──
	_position_chunk(mi, chunk_center_x, chunk_center_z, wox, woz)

	add_child(mi)
	cd.mesh = mi


func _position_chunk(mi: MeshInstance3D, chunk_center_x: float, chunk_center_z: float,
					 wox: float, woz: float) -> void:
	var player_height = sample_surface_height(wox, woz, _noise, _noise_scale, _noise_height)
	var planet_r := _target_body.real_radius if _target_body != null else 6371000.0
	player_height -= (wox * wox + woz * woz) / (2.0 * planet_r)

	var rel_x = chunk_center_x - wox
	var rel_z = chunk_center_z - woz
	var pos = _local_x * rel_x + _local_z * rel_z - (player_height + _eye_height) * _local_up

	mi.transform = Transform3D(Basis(_local_x, _local_up, _local_z), pos)


func _update_all_chunk_transforms(wox: float, woz: float) -> void:
	var player_height = sample_surface_height(wox, woz, _noise, _noise_scale, _noise_height)
	var planet_r := _target_body.real_radius if _target_body != null else 6371000.0
	player_height -= (wox * wox + woz * woz) / (2.0 * planet_r)

	for key in _chunks:
		var cd = _chunks[key]
		if not is_instance_valid(cd.mesh):
			continue

		var chunk_center_x = cd.gx * _chunk_size + _chunk_size * 0.5
		var chunk_center_z = cd.gz * _chunk_size + _chunk_size * 0.5
		var rel_x = chunk_center_x - wox
		var rel_z = chunk_center_z - woz
		var pos = _local_x * rel_x + _local_z * rel_z - (player_height + _eye_height) * _local_up

		cd.mesh.transform = Transform3D(Basis(_local_x, _local_up, _local_z), pos)
