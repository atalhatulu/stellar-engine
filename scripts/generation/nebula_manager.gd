extends Node3D

# ─────────────────────────────────────────────────────────────────────────────
# 3D PROCEDURAL VOLUMETRIC NEBULA GRID SYSTEM (No Man's Sky Renk Cümbüşü)
#
# Evrenin her tarafına dağıtılmış 5x5x5 (125 makro hücre, toplam 600x600x600 LY)
# dinamik kozmik bulutsu sistemi. Simsiyah derin uzay zemininde her yönde
# canlı, çift tonlu, ışıldayan gaz bulutları ve yıldız tozları oluşturur.
# ─────────────────────────────────────────────────────────────────────────────

const LIGHT_YEAR: float = 9460730472580800.0

const CELL_SIZE_LY: float = 120.0 # 120 Işık Yılı makro hücre boyutu
const CELL_SIZE_METERS: float = CELL_SIZE_LY * LIGHT_YEAR
const GRID_RADIUS: int = 2 # 5x5x5 = 125 makro hücre (Toplam 600x600x600 LY hacim)
const SPAWN_CHANCE: float = 0.65 # %65 yüksek oluşum oranı (Gök kubbede yoğun renk cümbüşü)
const FADE_START_LY: float = 240.0 # 240 LY mesafeden sonra sönümlenme başlar
const FADE_END_LY: float = 380.0 # 380 LY mesafede ufukta pürüzsüz kaybolur (0 popping)
const PUFF_COUNT: int = 28 # Zengin 3D hacimsel duman katmanı (Çekirdek + Gövde + Kollar)

class NebulaCluster extends RefCounted:
	var name: String
	var gal_pos: Vector3
	var radius: float
	var tint_core: Vector3
	var tint_edge: Vector3
	var node: MultiMeshInstance3D
	var mat: ShaderMaterial
	var cell_coord: Vector3i

var loaded_cells: Dictionary = {} # Vector3i -> NebulaCluster veya null
var universe_seed: int = 0
var visual_distance_limit: float = 1000000.0
var current_cell: Vector3i = Vector3i(2147483647, 2147483647, 2147483647)
var quad_mesh: QuadMesh = null
var nebula_shader: Shader = null

# No Man's Sky Tarzı Zengin Çift-Ton Kozmik Renk Paletleri
const THEMES = [
	{
		"name": "Siber Kozmos (Mor & Elektrik Mavi)",
		"core": Vector3(1.0, 0.25, 0.95),  # Parlak Eflatun/Mor
		"edge": Vector3(0.1, 0.55, 1.0)    # Elektrik Kobalt Mavisi
	},
	{
		"name": "Oksijen Lagünü (Turkuaz & Zümrüt)",
		"core": Vector3(0.15, 0.95, 0.85), # Neon Turkuaz
		"edge": Vector3(0.05, 0.75, 0.35)  # Canlı Zümrüt Yeşili
	},
	{
		"name": "Süpernova Kalıntısı (Alev Kızılı & Altın)",
		"core": Vector3(1.0, 0.85, 0.2),   # Işıldayan Altın Sarı
		"edge": Vector3(0.95, 0.18, 0.1)   # Kızıl Alev
	},
	{
		"name": "Yıldız Beşiği (Gül Pembesi & Eflatun)",
		"core": Vector3(1.0, 0.45, 0.75),  # Gül Pembesi
		"edge": Vector3(0.65, 0.15, 0.9)   # Koyu Menekşe
	},
	{
		"name": "Kozmik Okyanus (Derin Çivit & Akuamarin)",
		"core": Vector3(0.2, 0.8, 0.95),   # Parlak Akuamarin
		"edge": Vector3(0.15, 0.2, 0.85)   # Gece Mavisi
	},
	{
		"name": "Güneş Fırtınası (Plazma Turuncusu & Kehribar)",
		"core": Vector3(1.0, 0.55, 0.1),   # Ateş Turuncusu
		"edge": Vector3(0.85, 0.3, 0.05)   # Yanık Kehribar
	},
	{
		"name": "Neon Sayber (Fuşya & Turkuaz İkilemi)",
		"core": Vector3(0.95, 0.1, 0.6),   # Neon Fuşya
		"edge": Vector3(0.0, 0.85, 0.8)    # Canlı Cyan
	},
	{
		"name": "Buzul Yıldız Tozu (Buzul Mavi & Beyaz)",
		"core": Vector3(0.85, 0.95, 1.0),  # Buzul Beyazı
		"edge": Vector3(0.3, 0.65, 0.95)   # Gök Mavisi
	},
	{
		"name": "Karanlık Madde Alevi (Yakut Kızılı & Mor)",
		"core": Vector3(0.95, 0.12, 0.25), # Yakut Kırmızı
		"edge": Vector3(0.45, 0.08, 0.6)   # Koyu Mor
	},
	{
		"name": "Kozmik Şafak (Altın & Lavanta)",
		"core": Vector3(1.0, 0.9, 0.5),    # Sıcak Altın
		"edge": Vector3(0.7, 0.35, 0.85)   # Lavanta Tülü
	}
]

func _init(p_visual_limit: float = 1000000.0) -> void:
	visual_distance_limit = p_visual_limit
	quad_mesh = QuadMesh.new()
	quad_mesh.size = Vector2(1.0, 1.0)
	nebula_shader = load("res://shaders/nebula_3d.gdshader")

func setup_grid(p_universe_seed: int) -> void:
	clear_all()
	universe_seed = p_universe_seed

func clear_all() -> void:
	for coord in loaded_cells:
		var cluster = loaded_cells[coord]
		if cluster != null and is_instance_valid(cluster.node):
			cluster.node.queue_free()
	loaded_cells.clear()
	current_cell = Vector3i(2147483647, 2147483647, 2147483647)

func _exit_tree() -> void:
	clear_all()

# Deterministik 64-bit koordinat hash'i
func _hash_coords(x: int, y: int, z: int, seed_val: int) -> int:
	var h: int = seed_val
	h = (h ^ (x * 73856093)) * 19349663
	h = (h ^ (y * 83492791)) * 5381
	h = (h ^ (z * 294967261)) * 38241
	h = (h ^ (h >> 16)) * 1103515245
	return int(abs(h) % 2147483647)

# Her karede çağrılır: Hücre geçişini algılar ve görünür bulutsuların render pozisyonunu günceller
func update_nebulae(player_gal_pos: Vector3, camera_3d: Camera3D) -> void:
	if camera_3d == null:
		return
		
	# Oyuncunun bulunduğu 120 Işık Yılı makro ızgara hücresi
	var cell_x = floori(player_gal_pos.x / CELL_SIZE_METERS)
	var cell_y = floori(player_gal_pos.y / CELL_SIZE_METERS)
	var cell_z = floori(player_gal_pos.z / CELL_SIZE_METERS)
	var player_cell = Vector3i(cell_x, cell_y, cell_z)
	
	if player_cell != current_cell:
		_update_grid_streaming(player_cell)
		
	# Yüklenmiş aktif bulutsuların pozisyon, ölçek ve kenar sönümlemesini güncelle
	for coord in loaded_cells:
		var cluster = loaded_cells[coord]
		if cluster == null or not is_instance_valid(cluster.node):
			continue
			
		var rel_pos = cluster.gal_pos - player_gal_pos
		var dist = rel_pos.length()
		var dir = rel_pos / max(dist, 0.0001)
		var dist_ly = dist / LIGHT_YEAR
		
		# 240 - 380 Işık Yılı arasında yumuşak mesafe sönümlemesi (Anti-popping)
		var alpha_factor = clamp((FADE_END_LY - dist_ly) / (FADE_END_LY - FADE_START_LY), 0.0, 1.0)
		alpha_factor = alpha_factor * alpha_factor * (3.0 - 2.0 * alpha_factor) # Smoothstep
		
		if cluster.mat != null:
			cluster.mat.set_shader_parameter("alpha_fade", alpha_factor)
			
		# Render konumu ve ölçekleme (Hacimsel derinlik)
		var render_dist: float
		var scale_factor: float
		
		if dist > visual_distance_limit:
			render_dist = visual_distance_limit * 0.88
			scale_factor = render_dist * (cluster.radius / max(dist, 1.0))
			cluster.node.global_position = camera_3d.global_position + dir * render_dist
		else:
			render_dist = dist
			scale_factor = cluster.radius
			cluster.node.global_position = camera_3d.global_position + rel_pos
			
		scale_factor = clamp(scale_factor, visual_distance_limit * 0.05, visual_distance_limit * 0.65)
		cluster.node.scale = Vector3(scale_factor, scale_factor, scale_factor)

# Izgara hücrelerinin yükleme ve boşaltma yönetimi
func _update_grid_streaming(new_cell: Vector3i) -> void:
	var needed_coords: Dictionary = {}
	
	for dx in range(-GRID_RADIUS, GRID_RADIUS + 1):
		for dy in range(-GRID_RADIUS, GRID_RADIUS + 1):
			for dz in range(-GRID_RADIUS, GRID_RADIUS + 1):
				var c = new_cell + Vector3i(dx, dy, dz)
				needed_coords[c] = true
				
	# Menzilden çıkan hücreleri bellekten ve sahneden temizle
	var to_remove: Array = []
	for coord in loaded_cells:
		if not needed_coords.has(coord):
			to_remove.append(coord)
			
	for coord in to_remove:
		_unload_cell(coord)
		
	# Yeni menzile giren hücreleri üret
	for coord in needed_coords:
		if not loaded_cells.has(coord):
			_load_cell(coord)
			
	current_cell = new_cell

# Belirli bir ızgara koordinatındaki bulutsuyu deterministik olarak oluştur
func _load_cell(coord: Vector3i) -> void:
	var cell_seed = _hash_coords(coord.x, coord.y, coord.z, universe_seed)
	var rng = RandomNumberGenerator.new()
	rng.seed = cell_seed
	
	# Olasılık kontrolü (%65 doluluk - Her yönde zengin gökyüzü)
	if rng.randf() > SPAWN_CHANCE:
		loaded_cells[coord] = null
		return
		
	var theme = THEMES[rng.randi() % THEMES.size()]
	var cluster = NebulaCluster.new()
	cluster.name = "%s (%d, %d, %d)" % [theme["name"], coord.x, coord.y, coord.z]
	cluster.tint_core = theme["core"]
	cluster.tint_edge = theme["edge"]
	cluster.cell_coord = coord
	
	# Hücre içinde rastgele merkezleme
	var ox = (float(coord.x) + rng.randf_range(0.15, 0.85)) * CELL_SIZE_METERS
	var oy = (float(coord.y) + rng.randf_range(0.15, 0.85)) * CELL_SIZE_METERS
	var oz = (float(coord.z) + rng.randf_range(0.15, 0.85)) * CELL_SIZE_METERS
	cluster.gal_pos = Vector3(ox, oy, oz)
	cluster.radius = rng.randf_range(35.0, 85.0) * LIGHT_YEAR
	
	# MultiMeshInstance3D kurulumu
	var mm_inst = MultiMeshInstance3D.new()
	mm_inst.name = "Nebula_%d_%d_%d" % [coord.x, coord.y, coord.z]
	mm_inst.extra_cull_margin = 2500000.0
	mm_inst.custom_aabb = AABB(Vector3(-1500000.0, -1500000.0, -1500000.0), Vector3(3000000.0, 3000000.0, 3000000.0))
	
	var mat = ShaderMaterial.new()
	mat.shader = nebula_shader
	mat.set_shader_parameter("nebula_tint_core", cluster.tint_core)
	mat.set_shader_parameter("nebula_tint_edge", cluster.tint_edge)
	mat.set_shader_parameter("density", rng.randf_range(1.0, 1.6))
	mat.set_shader_parameter("noise_scale", rng.randf_range(1.3, 2.0))
	mat.set_shader_parameter("alpha_fade", 0.0)
	cluster.mat = mat
	mm_inst.material_override = mat
	
	var mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.instance_count = PUFF_COUNT
	mm.mesh = quad_mesh
	
	for p in range(PUFF_COUNT):
		# 3 Kademeli Hacimsel Dağılım:
		# 0..7  : Yoğun Çekirdek (Merkezde küçük, parlak ve yoğun)
		# 8..19 : Gaz Gövdesi (Orta mesafe, ana hacim)
		# 20..27: Dağınık Gaz Kolları (Geniş alana yayılan yumuşak tül kollar)
		var theta = rng.randf_range(0.0, TAU)
		var phi = rng.randf_range(-PI * 0.48, PI * 0.48)
		var p_dist: float
		var p_scale: float
		var puff_alpha: float
		var puff_brightness: float
		
		if p < 8:
			# Çekirdek katmanı
			p_dist = rng.randf_range(0.02, 0.28)
			p_scale = rng.randf_range(0.5, 0.9)
			puff_alpha = rng.randf_range(0.65, 0.95)
			puff_brightness = rng.randf_range(1.1, 1.4)
		elif p < 20:
			# Gövde katmanı
			p_dist = rng.randf_range(0.25, 0.65)
			p_scale = rng.randf_range(0.7, 1.25)
			puff_alpha = rng.randf_range(0.4, 0.7)
			puff_brightness = rng.randf_range(0.85, 1.15)
		else:
			# Dağınık dış kollar
			p_dist = rng.randf_range(0.6, 1.15)
			p_scale = rng.randf_range(1.0, 1.6)
			puff_alpha = rng.randf_range(0.2, 0.45)
			puff_brightness = rng.randf_range(0.65, 0.95)
			
		var p_pos = Vector3(cos(phi) * cos(theta), sin(phi), cos(phi) * sin(theta)) * p_dist
		var p_rot = rng.randf_range(0.0, TAU)
		
		var xform = Transform3D()
		xform = xform.rotated(Vector3.FORWARD, p_rot)
		xform = xform.scaled(Vector3(p_scale, p_scale, p_scale))
		xform.origin = p_pos
		
		mm.set_instance_transform(p, xform)
		var puff_col = Color(puff_brightness, puff_brightness, puff_brightness, puff_alpha)
		mm.set_instance_color(p, puff_col)
		
	mm_inst.multimesh = mm
	add_child(mm_inst)
	cluster.node = mm_inst
	
	loaded_cells[coord] = cluster

# Hücreyi sahneden ve bellekten kaldır
func _unload_cell(coord: Vector3i) -> void:
	if loaded_cells.has(coord):
		var cluster = loaded_cells[coord]
		if cluster != null and is_instance_valid(cluster.node):
			cluster.node.queue_free()
		loaded_cells.erase(coord)
