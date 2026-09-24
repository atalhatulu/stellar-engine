class_name StarVisualPool
extends Node3D

# ─────────────────────────────────────────────────────────────────────────────
# STAR VISUAL POOL (Aşama 3 & Aşama 7C+: GPU MultiMesh Mimarisi)
# 
# SectorManager tarafından üretilen StarData kayıtlarını sahne ağacında 1.000 ayrı
# Sprite3D Node'u yerine TEK BİR GPU MultiMeshInstance3D (1 Draw Call, 0 Node yükü)
# üzerinde çizer. Sahnedeki düğüm sayısını 1000'den 1'e indirir.
# ─────────────────────────────────────────────────────────────────────────────

const LIGHT_YEAR: float = 9460730472580800.0
const DEFAULT_CAPACITY: int = 1000
const REBIND_INTERVAL: float = 0.25 # 4 Hz akıllı rebinding aralığı
const REBIND_MOVE_THRESHOLD: float = 0.05 * LIGHT_YEAR # Yeniden bağlama için hareket eşiği

class StarVisualSlot extends RefCounted:
	var star_data = null
	var active: bool = false
	var distance: float = 0.0

var pool_capacity: int = DEFAULT_CAPACITY
var slots: Array[StarVisualSlot] = []
var active_count: int = 0
var is_pool_visible: bool = true
var visual_distance_limit: float = 1000000.0

# GPU MultiMesh Bileşenleri (Sıfır Sprite3D)
var multimesh_instance: MultiMeshInstance3D = null
var multimesh: MultiMesh = null
var quad_mesh: QuadMesh = null
var material: StandardMaterial3D = null

# Telemetri ve Profiler Verileri
var last_rebind_usec: int = 0
var last_transform_usec: int = 0
var max_rebind_usec: int = 0
var rebind_count: int = 0
var rebind_timer: float = 0.0
var last_rebind_pos: Vector3 = Vector3(INF, INF, INF)
var active_star_id: String = ""
var pinned_star_data = null
var _stream_dirty := false
var _bound_active_id := ""
var _bound_pinned_id := ""
var _render_player_pos := Vector3.ZERO


func _init(p_capacity: int = DEFAULT_CAPACITY, p_visual_limit: float = 1000000.0):
	pool_capacity = p_capacity
	visual_distance_limit = p_visual_limit


# Havuzu başlangıçta bir kez tahsis eder (Tek seferlik 1 MultiMeshInstance3D)
func init_pool() -> void:
	slots.clear()
	active_count = 0
	
	if is_instance_valid(multimesh_instance):
		multimesh_instance.queue_free()
		
	var shared_texture = SystemGenerator.get_star_glow_texture()
	
	# 1. Billboard QuadMesh ve Malzemesi
	quad_mesh = QuadMesh.new()
	quad_mesh.size = Vector2(1.0, 1.0)
	
	material = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.billboard_keep_scale = true
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_texture = shared_texture
	material.render_priority = -1 # Gezegenlerin arkasında çizilir
	
	# 2. MultiMesh Havuzu (Sabit 1000 yıldız kapasitesi, 1 Draw Call)
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.instance_count = pool_capacity
	multimesh.mesh = quad_mesh
	
	multimesh_instance = MultiMeshInstance3D.new()
	multimesh_instance.name = "NearStarMultiMesh"
	multimesh_instance.material_override = material
	multimesh_instance.multimesh = multimesh
	multimesh_instance.extra_cull_margin = 2000000.0
	multimesh_instance.custom_aabb = AABB(Vector3(-2000000.0, -2000000.0, -2000000.0), Vector3(4000000.0, 4000000.0, 4000000.0))
	add_child(multimesh_instance)
	
	# Başlangıçta tüm instance'ları sıfırla
	for i in range(pool_capacity):
		multimesh.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), Vector3(0, -99999999, 0)))
		multimesh.set_instance_color(i, Color(0, 0, 0, 0))
		
		var slot = StarVisualSlot.new()
		slot.star_data = null
		slot.active = false
		slots.append(slot)


# SectorManager'daki aktif sektörlerin yıldızlarını havuz slotlarına bağlar
func rebind(sector_manager, player_gal_pos: Vector3, cam_forward: Vector3 = Vector3.FORWARD, p_active_star_id: String = "", p_pinned_star_data = null) -> void:
	if sector_manager == null or slots.is_empty():
		return
		
	if p_active_star_id != "":
		active_star_id = p_active_star_id
	if p_pinned_star_data != null:
		pinned_star_data = p_pinned_star_data
	elif active_star_id != "" and pinned_star_data != null and pinned_star_data.unique_id == active_star_id:
		pinned_star_data = null # Aktif yıldıza dönüştüyse sabitlemeyi kaldır
		
	var start_usec = Time.get_ticks_usec()
	rebind_count += 1
	last_rebind_pos = player_gal_pos
	_bound_active_id = active_star_id
	_bound_pinned_id = pinned_star_data.unique_id if pinned_star_data != null else ""
	
	# 1. Oyuncunun merkez sektörünü bul
	var player_sector = SectorManager.get_sector_coord(player_gal_pos)
	
	# Sabitlenmiş yıldız varsa daima ilk aday olarak ekle
	var candidates: Array = []
	if pinned_star_data != null and pinned_star_data.unique_id != active_star_id:
		candidates.append(pinned_star_data)
		
	# 2. 260 Işık Yılı menzilindeki tüm sektörleri topla
	# 0-160 LY arasında tüm yıldızlar, 160-260 LY arasında sektörlerin ana yıldızları (_S1) korunur.
	# Böylece geri giderken ana yıldızlar asla silinmez; derin uzayda parlamaya devam eder!
	var player_pos_ly = player_gal_pos / LIGHT_YEAR
	for coord in sector_manager.loaded_sectors:
		var sec_center_ly = (Vector3(coord) + Vector3(0.5, 0.5, 0.5)) * SectorManager.SECTOR_SIZE_LY
		var sec_dist_sq = (sec_center_ly - player_pos_ly).length_squared()
		if sec_dist_sq > 260.0 * 260.0:
			continue
			
		var sec_stars = sector_manager.loaded_sectors[coord]
		for star in sec_stars:
			if active_star_id != "" and star.unique_id == active_star_id:
				continue # Aktif sistem yıldızı 3D mesh olarak çizildiğinden havuzda tekrarlanmaz
			if pinned_star_data != null and star.unique_id == pinned_star_data.unique_id:
				continue
				
			var is_primary = star.unique_id.ends_with("_S1")
			# 160 LY ötesinde sadece S1 ana yıldızlarını al (Havuz kapasitesini 1000'de dengeler)
			if sec_dist_sq > 160.0 * 160.0 and not is_primary:
				continue
				
			candidates.append(star)
			
	var total_candidates = candidates.size()
	
	# 3. Eğer nadiren aday yıldız sayısı havuz kapasitesini aşarsa hafif skorlama uygula
	if total_candidates > pool_capacity:
		# Pack score and index into integer keys; native sorting avoids tens of
		# thousands of GDScript comparator calls and temporary dictionaries.
		var ordering := PackedInt64Array()
		var distances := PackedFloat64Array()
		ordering.resize(total_candidates)
		distances.resize(total_candidates)
		for candidate_index in range(total_candidates):
			var star = candidates[candidate_index]
			var offset_ly := (Vector3(star.stellar_x, star.stellar_y, star.stellar_z) - player_gal_pos) / LIGHT_YEAR
			var dist_ly := offset_ly.length()
			var distance := dist_ly * LIGHT_YEAR
			var alignment := cam_forward.dot(offset_ly / maxf(dist_ly, 0.00001))
			var score := distance * (1.35 - clampf(alignment, -1.0, 1.0) * 0.75)
			if distance < 15.0 * LIGHT_YEAR:
				score = distance * 0.2
			var rank := int(score / LIGHT_YEAR * 1000000.0)
			if pinned_star_data != null and star.unique_id == pinned_star_data.unique_id:
				rank = -1
			ordering[candidate_index] = rank * total_candidates + candidate_index
			distances[candidate_index] = distance
		ordering.sort()
		for i in range(pool_capacity):
			var candidate_index := posmod(ordering[i], total_candidates)
			var slot = slots[i]
			slot.star_data = candidates[candidate_index]
			slot.active = true
			slot.distance = distances[candidate_index]

		active_count = pool_capacity
	else:
		# Tüm 27 sektör adayları doğrudan havuza sığar (Sıfır Sort Gecikmesi)
		for i in range(total_candidates):
			var slot = slots[i]
			var star = candidates[i]
			slot.star_data = star
			slot.active = true
			var star_pos_ly = Vector3(star.stellar_x, star.stellar_y, star.stellar_z) / LIGHT_YEAR
			slot.distance = (star_pos_ly - player_pos_ly).length() * LIGHT_YEAR
			
		# Kalan boş slotları pasife çek
		for i in range(total_candidates, pool_capacity):
			var slot = slots[i]
			slot.star_data = null
			slot.active = false
			
		active_count = total_candidates
		
	last_rebind_usec = Time.get_ticks_usec() - start_usec
	if last_rebind_usec > max_rebind_usec:
		max_rebind_usec = last_rebind_usec


# Slotlardaki yıldızların 3D MultiMesh transformlarını ve renklerini günceller
func update_transforms(player_gal_pos: Vector3, fov: float, viewport_height: float, cam_forward: Vector3 = Vector3.ZERO, surface_up: Vector3 = Vector3.ZERO) -> void:
	_render_player_pos = player_gal_pos
	if not is_pool_visible or multimesh == null:
		return
		
	var start_usec = Time.get_ticks_usec()
	var tan_half_fov = tan(deg_to_rad(fov * 0.5))
	var safe_vp_h = max(viewport_height, 600.0)
	var cull_cos = cos(deg_to_rad(fov * 0.5 + 32.0)) if cam_forward != Vector3.ZERO else -1.0
	
	for i in range(pool_capacity):
		var slot = slots[i]
		if not slot.active or slot.star_data == null:
			multimesh.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), Vector3(0, -99999999, 0)))
			multimesh.set_instance_color(i, Color(0, 0, 0, 0))
			continue
			
		var star = slot.star_data
		var star_pos_ly = Vector3(star.stellar_x, star.stellar_y, star.stellar_z) / LIGHT_YEAR
		var player_pos_ly = player_gal_pos / LIGHT_YEAR
		var rel_pos_ly = star_pos_ly - player_pos_ly
		var dist_ly = rel_pos_ly.length()
		var dir = rel_pos_ly / max(dist_ly, 0.00001)
		
		# Gezegen yüzeyindeyken ufkun ve yerin altında kalan yıldızları tamamen gizle
		if surface_up != Vector3.ZERO and dir.dot(surface_up) < 0.05:
			multimesh.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), Vector3(0, -99999999, 0)))
			multimesh.set_instance_color(i, Color(0, 0, 0, 0))
			continue

		# Kamera arkasındaki ve FOV dışındaki yıldızları GPU'da çizilmeyecek şekilde gizle
		if cull_cos > -1.0 and cam_forward.dot(dir) < cull_cos:
			multimesh.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), Vector3(0, -99999999, 0)))
			multimesh.set_instance_color(i, Color(0, 0, 0, 0))
			continue
			
		var dist = dist_ly * LIGHT_YEAR
		slot.distance = dist
		
		var render_dist = min(dist, visual_distance_limit)
		var local_pos = dir * render_dist
		
		# Astronomik derinlik ve kademeli algısal boyut hesabı (0 - 180 LY)
		var dist_ratio = clamp((dist_ly - 0.2) / 180.0, 0.0, 1.0)
		var perceptual_depth = pow(dist_ratio, 0.42) # Yakın mesafelere logaritmik duyarlılık
		
		# Kademeli algısal piksel yarıçapı (Yakın yıldızlar iri ve belirgin fenerler):
		# < 6 LY:   22.0 - 14.0 px (Burnumuzun dibinde devasa göz alıcı fenerler)
		# 6-25 LY:  14.0 - 8.0 px  (Çok yakın belirgin iri yıldızlar)
		# 25-70 LY: 8.0 - 4.5 px   (Orta yakın net yıldızlar)
		# > 70 LY:  4.5 - 2.2 px   (Sektör sınırı noktaları)
		var pixel_radius: float
		if dist_ly < 6.0:
			pixel_radius = lerp(22.0, 14.0, dist_ly / 6.0)
		elif dist_ly < 25.0:
			pixel_radius = lerp(14.0, 8.0, (dist_ly - 6.0) / 19.0)
		elif dist_ly < 70.0:
			pixel_radius = lerp(8.0, 4.5, (dist_ly - 25.0) / 45.0)
		else:
			pixel_radius = lerp(4.5, 2.2, clamp((dist_ly - 70.0) / 110.0, 0.0, 1.0))
			
		# Spektral fiziksel boyut varyasyonu:
		# Yakın mesafelerde ters-kare ışık akısı çok güçlü olduğundan tüm yıldızlar iri parlar
		var raw_radius_factor = clamp(star.radius / 480000000.0, 0.7, 1.8)
		var radius_factor = lerp(1.0, raw_radius_factor, clamp(dist_ly / 50.0, 0.1, 1.0))
		pixel_radius *= radius_factor
		
		var min_scale = pixel_radius * 2.0 * render_dist * tan_half_fov / safe_vp_h
		var natural_scale = star.radius * (render_dist / max(dist, 1.0))
		var final_scale = max(natural_scale, min_scale)
		
		# Spektral tip ve parlaklık: Yakındakiler göz kamaştırıcı ve çok parlak
		var energy_factor = clamp(star.light_energy / 1.4, 0.8, 1.6)
		var star_brightness = lerp(3.6, 1.05, perceptual_depth) * energy_factor
		
		# Yıldızın kendi ÖZGÜN VE CANLI spektral rengi (Mavi, Turuncu, Kırmızı, Sarı, Beyaz)
		var base_col = star.base_color.lerp(Color.WHITE, 0.08)
		
		# Pinned hedef yıldız ve S1 ana yıldız kontrolü
		var is_pinned: bool = (pinned_star_data != null and star.unique_id == pinned_star_data.unique_id)
		var is_primary: bool = star.unique_id.ends_with("_S1")
		
		# Sektör sınırında yumuşak çapraz sönümleme:
		# Hedeflenen yıldız (pinned_star_data) oyuncu ne kadar uzaklaşırsa uzaklaşsın ASLA SÖNMEZ!
		var edge_fade: float = 1.0
		if is_pinned:
			edge_fade = 1.0
		elif is_primary:
			# Ana yıldızlar (S1) derin uzayda 300 LY'ye kadar parlar; asla birdenbire yok olmaz
			edge_fade = clamp((300.0 - dist_ly) / (300.0 - 180.0), 0.0, 1.0)
			edge_fade = edge_fade * edge_fade * (3.0 - 2.0 * edge_fade)
		else:
			# Küçük yan cüce yıldızlar 120-180 LY arasında doğal olarak sönümlenir
			edge_fade = clamp((180.0 - dist_ly) / (180.0 - 120.0), 0.0, 1.0)
			edge_fade = edge_fade * edge_fade * (3.0 - 2.0 * edge_fade) # Smoothstep
		
		var star_alpha = (lerp(1.0, 0.65, perceptual_depth) if not is_pinned else 0.9) * edge_fade
		
		var star_col = Color(
			base_col.r * star_brightness,
			base_col.g * star_brightness,
			base_col.b * star_brightness,
			star_alpha
		)
		
		var xform = Transform3D(Basis().scaled(Vector3(final_scale, final_scale, final_scale)), local_pos)
		multimesh.set_instance_transform(i, xform)
		multimesh.set_instance_color(i, star_col)
		
	last_transform_usec = Time.get_ticks_usec() - start_usec


# Ana oyun döngüsünden çağrılan birleşik yöneticisi
func update_pool(delta: float, sector_manager, player_gal_pos: Vector3, cam_forward: Vector3, fov: float, viewport_height: float, sector_changed: bool, p_active_star_id: String = "", p_pinned_star_data = null, surface_up: Vector3 = Vector3.ZERO) -> void:
	if p_active_star_id != "":
		active_star_id = p_active_star_id
	pinned_star_data = p_pinned_star_data
	if active_star_id != "" and pinned_star_data != null and pinned_star_data.unique_id == active_star_id:
		pinned_star_data = null
		
	rebind_timer += delta
	
	# Yeniden bağlama koşulları: Sektör değişimi VEYA zaman/mesafe eşiği
	var dist_moved = player_gal_pos.distance_to(last_rebind_pos)
	_stream_dirty = _stream_dirty or sector_changed
	var pinned_id: String = pinned_star_data.unique_id if pinned_star_data != null else ""
	var target_changed := _bound_active_id != active_star_id or _bound_pinned_id != pinned_id
	var needs_rebind = target_changed or (rebind_timer >= REBIND_INTERVAL and (_stream_dirty or dist_moved >= REBIND_MOVE_THRESHOLD))
	
	if needs_rebind:
		_stream_dirty = false
		rebind_timer = 0.0
		rebind(sector_manager, player_gal_pos, cam_forward, active_star_id, pinned_star_data)
		
	# Her kare aktif slotların MultiMesh transformlarını güncelle
	update_transforms(player_gal_pos, fov, viewport_height, cam_forward, surface_up)


# Ekran merkezine (crosshair) en yakın görsel havuz yıldızını bulur
func find_star_under_screen_pos(camera_3d: Camera3D, screen_center: Vector2, max_radius_px: float = 40.0) -> Dictionary:
	if camera_3d == null or active_count == 0 or not is_pool_visible:
		return {}
		
	var best_star = null
	var min_screen_dist = max_radius_px
	
	for i in range(active_count):
		var slot = slots[i]
		if not slot.active or slot.star_data == null:
			continue
			
		var render_pos = get_star_render_position(slot.star_data, _render_player_pos)
		var star_world_pos = global_position + render_pos
		if camera_3d.is_position_behind(star_world_pos):
			continue
			
		var screen_pos = camera_3d.unproject_position(star_world_pos)
		var dist = screen_center.distance_to(screen_pos)
		if dist < min_screen_dist:
			min_screen_dist = dist
			best_star = slot.star_data
			
	if best_star != null:
		return {
			"star": best_star,
			"screen_dist": min_screen_dist
		}
	return {}


# Hedeflenen bir StarData kaydının kameraya göre 3D render konumunu döner (Hassasiyet kayıpsız, titreşimsiz)
func get_star_render_position(star_data, player_gal_pos: Vector3) -> Vector3:
	if star_data == null:
		return Vector3.ZERO
	# 32-bit float hassasiyet kaybını önlemek için hesabı Işık Yılı ölçeğinde yap
	var star_pos_ly = Vector3(star_data.stellar_x, star_data.stellar_y, star_data.stellar_z) / LIGHT_YEAR
	var player_gal_pos_ly = player_gal_pos / LIGHT_YEAR
	var rel_pos_ly = star_pos_ly - player_gal_pos_ly
	var dist_ly = rel_pos_ly.length()
	var dir = rel_pos_ly / max(dist_ly, 0.00001)
	var render_dist = min(dist_ly * LIGHT_YEAR, visual_distance_limit)
	return dir * render_dist


# Havuzun görünürlüğünü açıp kapatır
func set_pool_visibility(p_visible: bool) -> void:
	is_pool_visible = p_visible
	if is_instance_valid(multimesh_instance):
		multimesh_instance.visible = is_pool_visible


func toggle_pool_visibility() -> bool:
	set_pool_visibility(!is_pool_visible)
	return is_pool_visible


# Performans ve Doğrulama Benchmark Aracı
func run_pool_benchmark(test_counts: Array = [100, 500, 1000]) -> Array:
	var results: Array = []
	var node_count_initial = get_child_count()
	
	var rng = RandomNumberGenerator.new()
	rng.seed = 12345
	
	for count in test_counts:
		var target_count = mini(int(count), pool_capacity)
		
		var test_stars: Array = []
		for i in range(target_count):
			var s = StarData.new()
			s.unique_id = "BENCH_STAR_%d" % i
			s.name = "BStar_%d" % i
			s.stellar_x = rng.randf_range(-15.0 * LIGHT_YEAR, 15.0 * LIGHT_YEAR)
			s.stellar_y = rng.randf_range(-15.0 * LIGHT_YEAR, 15.0 * LIGHT_YEAR)
			s.stellar_z = rng.randf_range(-15.0 * LIGHT_YEAR, 15.0 * LIGHT_YEAR)
			s.radius = rng.randf_range(300000000.0, 600000000.0)
			s.base_color = Color(rng.randf(), rng.randf(), rng.randf())
			s.light_energy = 1.4
			test_stars.append(s)
			
		# 1. Rebind süresini ölç
		var rebind_start = Time.get_ticks_usec()
		for i in range(target_count):
			var slot = slots[i]
			slot.star_data = test_stars[i]
			slot.active = true
		for i in range(target_count, pool_capacity):
			var slot = slots[i]
			slot.star_data = null
			slot.active = false
		var rebind_usec = Time.get_ticks_usec() - rebind_start
		
		active_count = target_count
		
		# 2. Transform güncelleme süresini ölç (10 kare ortalaması)
		var total_transform_usec = 0
		var iterations = 10
		for it in range(iterations):
			var tr_start = Time.get_ticks_usec()
			var dummy_player_pos = Vector3(it * 1000.0, 0, 0)
			update_transforms(dummy_player_pos, 75.0, 1080.0)
			total_transform_usec += (Time.get_ticks_usec() - tr_start)
		var avg_transform_usec = total_transform_usec / iterations
		
		var node_count_current = get_child_count()
		var nodes_constant = (node_count_current == node_count_initial)
		
		var transform_ms = float(avg_transform_usec) / 1000.0
		var rebind_ms = float(rebind_usec) / 1000.0
		var est_fps = 1000.0 / max(transform_ms, 0.001)
		
		results.append({
			"sprite_count": target_count,
			"rebind_usec": rebind_usec,
			"rebind_ms": rebind_ms,
			"transform_usec": avg_transform_usec,
			"transform_ms": transform_ms,
			"estimated_fps": est_fps,
			"nodes_constant": nodes_constant,
			"node_count": node_count_current,
			"spike_detected": (rebind_ms > 1.0)
		})
		
	return results
