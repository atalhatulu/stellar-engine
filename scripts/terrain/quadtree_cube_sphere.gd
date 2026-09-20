class_name QuadtreeCubeSphere
extends Node3D

# =============================================================================
# Quadtree Normalized Cube-Sphere Planetary Terrain
# 6 küp yüzeyi üzerinde kameraya göre dinamik bölünen ve gerçek 3D devasa
# dağlar, kraterler ve vadiler üreten kesintisiz küresel gezegen sistemi.
# =============================================================================

@export var planet_radius: float = 120000.0  # 120 km test yarıçapı (devasa ölçek)
@export var max_mountain_height: float = 6500.0  # 6.5 km devasa dağ sıraları
@export var min_valley_depth: float = -3500.0    # 3.5 km kanyon ve vadi derinliği
@export var max_lod: int = 7                     # LOD 0'dan 7'ye (yakında ~1-2 metre detay)
@export var lod_split_factor: float = 1.45       # Bölünme mesafe eşiği
@export var chunk_subdivisions: int = 20         # Her parçada 20x20 bölme (441 vertex)
@export var wireframe_debug: bool = false

var lod_multiplier: float = 1.0                  # Tekerlek ile anlık detay ölçeği (0.4 - 3.0)
var show_chunk_borders: bool = false             # Sınır çizgileri
var debug_lod_colors: bool = false               # Renkli LOD seviyesi modu

var camera_ref: Node3D = null

# Gürültü katmanları (Deterministik 3D frekanslar)
var noise_macro := FastNoiseLite.new()
var noise_ridge := FastNoiseLite.new()
var noise_hills := FastNoiseLite.new()
var noise_crater := FastNoiseLite.new()
var noise_canyon := FastNoiseLite.new()
var noise_rocks := FastNoiseLite.new()
var noise_detail := FastNoiseLite.new()

# Malzeme
var terrain_material: ShaderMaterial = null

# 6 Küp Yüzü Tanımları
const FACE_NAMES = ["+Z Front", "-Z Back", "+X Right", "-X Left", "+Y Top", "-Y Bottom"]
var face_bases: Array = [
	{ "normal": Vector3(0, 0, 1), "right": Vector3(1, 0, 0), "up": Vector3(0, 1, 0) },   # +Z Front
	{ "normal": Vector3(0, 0, -1), "right": Vector3(-1, 0, 0), "up": Vector3(0, 1, 0) }, # -Z Back
	{ "normal": Vector3(1, 0, 0), "right": Vector3(0, 0, -1), "up": Vector3(0, 1, 0) },  # +X Right
	{ "normal": Vector3(-1, 0, 0), "right": Vector3(0, 0, 1), "up": Vector3(0, 1, 0) },  # -X Left
	{ "normal": Vector3(0, 1, 0), "right": Vector3(1, 0, 0), "up": Vector3(0, 0, -1) },  # +Y Top
	{ "normal": Vector3(0, -1, 0), "right": Vector3(1, 0, 0), "up": Vector3(0, 0, 1) },  # -Y Bottom
]

# Kök parçalar
var root_nodes: Array[QuadNode] = []

# Kare başına parça üretim bütçesi (mikro takılmaları önler)
var build_queue: Array[QuadNode] = []
const MAX_BUILDS_PER_FRAME := 4

# İstatistikler
var total_leaf_chunks: int = 0
var deepest_lod_rendered: int = 0

# -----------------------------------------------------------------------------
# İç Düğüm Sınıfı (QuadNode)
# -----------------------------------------------------------------------------
class QuadNode:
	var sphere: QuadtreeCubeSphere
	var face_idx: int = 0
	var lod: int = 0
	var u_center: float = 0.0
	var v_center: float = 0.0
	var size: float = 2.0 # Kök için 2.0 (u, v aralığı [-1, 1])
	
	var parent: QuadNode = null
	var children: Array[QuadNode] = []
	var is_leaf: bool = true
	var is_mesh_ready: bool = false
	
	var center_dir: Vector3 = Vector3.UP
	var center_world: Vector3 = Vector3.ZERO
	var approx_radius_meters: float = 0.0
	
	var mesh_instance: MeshInstance3D = null

	func _init(p_sphere: QuadtreeCubeSphere, p_face: int, p_lod: int, p_u: float, p_v: float, p_size: float, p_parent: QuadNode = null):
		sphere = p_sphere
		face_idx = p_face
		lod = p_lod
		u_center = p_u
		v_center = p_v
		size = p_size
		parent = p_parent
		
		# Küresel merkez yönü ve yaklaşık dünya konumu
		var base = sphere.face_bases[face_idx]
		var cube_point: Vector3 = base["normal"] + base["right"] * u_center + base["up"] * v_center
		center_dir = cube_point.normalized()
		var h = sphere.sample_height(center_dir, lod)
		center_world = sphere.global_position + center_dir * (sphere.planet_radius + h)
		
		# Parçanın yaklaşık metre yarıçapı
		approx_radius_meters = sphere.planet_radius * (size * 0.5) * 1.15

	func update(cam_pos: Vector3) -> void:
		var dist = (cam_pos - center_world).length()
		var split_dist = approx_radius_meters * sphere.lod_split_factor * sphere.lod_multiplier
		
		if is_leaf:
			# Derine bölünme kontrolü
			if lod < sphere.max_lod and dist < split_dist:
				_subdivide()
				for child in children:
					child.update(cam_pos)
		else:
			# Birleşme kontrolü (histerezis: split_dist * 1.45)
			if dist > split_dist * 1.45:
				_merge()
			else:
				for child in children:
					child.update(cam_pos)

	func _subdivide() -> void:
		if not children.is_empty():
			return
			
		var half_size = size * 0.5
		var quarter = size * 0.25
		
		# 4 yeni çocuk oluştur
		var offsets = [
			Vector2(-quarter, -quarter),
			Vector2(quarter, -quarter),
			Vector2(-quarter, quarter),
			Vector2(quarter, quarter)
		]
		
		for off in offsets:
			var child = QuadNode.new(sphere, face_idx, lod + 1, u_center + off.x, v_center + off.y, half_size, self)
			children.append(child)
			# Yeni çocuğu hemen üretim kuyruğuna al
			sphere.build_queue.append(child)
			
		is_leaf = false
		# Ebeveyn mesh'i çocuklar hazır olana kadar tutulabilir veya gizlenebilir
		if mesh_instance != null:
			mesh_instance.visible = false

	func _merge() -> void:
		if is_leaf or children.is_empty():
			return
			
		for child in children:
			child.destroy()
		children.clear()
		is_leaf = true
		
		# Ebeveyn mesh'ini tekrar aktif et
		if mesh_instance != null:
			mesh_instance.visible = true
		else:
			sphere.build_queue.append(self)

	func destroy() -> void:
		for child in children:
			child.destroy()
		children.clear()
		if is_instance_valid(mesh_instance):
			mesh_instance.queue_free()
			mesh_instance = null
		is_leaf = true
		is_mesh_ready = false

# -----------------------------------------------------------------------------
# Başlatma ve Gürültü Ayarları
# -----------------------------------------------------------------------------
func _ready() -> void:
	_init_noise()
	_init_material()
	_create_root_nodes()

func _init_noise() -> void:
	# 1. Kıtalar ve ana yükseklik dağılımı (Geniş ovalar)
	noise_macro.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise_macro.seed = 424243
	noise_macro.frequency = 1.0

	# 2. Bölgesel keskin dağ sıraları (Sadece maskeli alanlarda)
	noise_ridge.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise_ridge.seed = 98765
	noise_ridge.frequency = 1.0
	noise_ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED

	# 3. Kraterler (Düz tabanlı doğal çanaklar)
	noise_crater.noise_type = FastNoiseLite.TYPE_CELLULAR
	noise_crater.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
	noise_crater.seed = 55555
	noise_crater.frequency = 1.0

	# 4. Yumuşak dalgalı tepeler ve yaylalar (Gezilebilir eğimler)
	noise_hills.noise_type = FastNoiseLite.TYPE_PERLIN
	noise_hills.seed = 12345
	noise_hills.frequency = 1.0

	# 5. İnce zemin mikro dalgası (0.5 - 2m yürünebilir zemin)
	noise_detail.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise_detail.seed = 77777
	noise_detail.frequency = 1.0

func _init_material() -> void:
	terrain_material = ShaderMaterial.new()
	var code = """
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform bool use_lod_colors = false;
uniform bool show_borders = false;
uniform float border_thickness = 0.018;

varying vec3 v_world_pos;
varying vec3 v_world_normal;
varying vec4 v_vertex_color;
varying float v_altitude;
varying float v_slope;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_vertex_color = COLOR;
	v_altitude = length(v_world_pos);
	vec3 sphere_norm = normalize(v_world_pos);
	// Yüzeyin gezegen merkezine göre dikliği (eğim)
	v_slope = 1.0 - clamp(dot(v_world_normal, sphere_norm), 0.0, 1.0);
}

// Prosedürel mikro zemin gürültüsü
float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise3d(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash(i + vec3(0,0,0)), hash(i + vec3(1,0,0)), f.x),
		    mix(hash(i + vec3(0,1,0)), hash(i + vec3(1,1,0)), f.x), f.y),
		mix(mix(hash(i + vec3(0,0,1)), hash(i + vec3(1,0,1)), f.x),
		    mix(hash(i + vec3(0,1,1)), hash(i + vec3(1,1,1)), f.x), f.y), f.z);
}

void fragment() {
	// 3D Triplanar mikro engebe dokusu
	vec3 p_micro = v_world_pos * 0.08;
	float micro_grain = noise3d(p_micro) * 0.6 + noise3d(p_micro * 3.5) * 0.4;
	
	// Renk Paleti (Gerçekçi kayalık gezegen tonları)
	vec3 snow_peak = vec3(0.95, 0.97, 1.0);       // Karlı / mineral zirveler
	vec3 cliff_rock = vec3(0.18, 0.16, 0.15);     // Sarp dik bazalt kayalıklar
	vec3 highland = vec3(0.42, 0.34, 0.26);       // Yüksek sırtlar ve platolar
	vec3 valley_soil = vec3(0.32, 0.28, 0.24);    // Alçak zemin ve çöküntüler
	vec3 crater_dust = vec3(0.20, 0.21, 0.24);    // Krater içi toz tabakası

	// Yükseklik normalizasyonu (120 km gezegen yarıçapı çevresi)
	float alt_norm = clamp((v_altitude - 118000.0) / 9000.0, 0.0, 1.0);
	
	// Eğim faktörü (Eğim > 25° ise sarp kaya açığa çıkar)
	float cliff_factor = smoothstep(0.12, 0.42, v_slope);

	vec3 base = mix(valley_soil, highland, smoothstep(0.25, 0.65, alt_norm));
	base = mix(base, snow_peak, smoothstep(0.75, 0.92, alt_norm));
	
	// Dik kayalıkları kaya rengiyle ve mikro tanecikle zenginleştir
	vec3 surface_color = mix(base, cliff_rock, cliff_factor);
	surface_color *= (0.92 + 0.16 * micro_grain);

	// Debug 1: LOD Seviye Renklendirmesi
	if (use_lod_colors) {
		surface_color = mix(surface_color, v_vertex_color.rgb, 0.78);
	}

	// Debug 2: Parça Sınır Çizgileri (Chunk Borders)
	if (show_borders) {
		bool is_border = (UV.x < border_thickness || UV.x > (1.0 - border_thickness) ||
		                  UV.y < border_thickness || UV.y > (1.0 - border_thickness));
		if (is_border) {
			surface_color = vec3(0.0, 1.0, 0.85); // Parlak neon turkuaz sınır
			ROUGHNESS = 0.1;
		}
	}

	ALBEDO = surface_color;
	ROUGHNESS = mix(0.78, 0.96, cliff_factor);
	METALLIC = 0.02;
	SPECULAR = 0.2;
}
"""
	var shader = Shader.new()
	shader.code = code
	terrain_material.shader = shader
	_update_shader_uniforms()

func _update_shader_uniforms() -> void:
	if terrain_material != null:
		terrain_material.set_shader_parameter("use_lod_colors", debug_lod_colors)
		terrain_material.set_shader_parameter("show_borders", show_chunk_borders)

func toggle_borders() -> bool:
	show_chunk_borders = !show_chunk_borders
	_update_shader_uniforms()
	return show_chunk_borders

func toggle_debug_colors() -> bool:
	debug_lod_colors = !debug_lod_colors
	_update_shader_uniforms()
	return debug_lod_colors

func adjust_lod_factor(delta_factor: float) -> float:
	lod_multiplier = clampf(lod_multiplier + delta_factor, 0.35, 3.5)
	return lod_multiplier

# -----------------------------------------------------------------------------
# 3D Küresel Yükseklik Fonksiyonu (Dikişsiz ve Deterministik)
# -----------------------------------------------------------------------------
func sample_height(dir: Vector3, lod: int = 7) -> float:
	var d = dir.normalized()
	
	# 1. Kıtalar ve Ana Yükseltiler (Geniş ovalar ve platolar)
	var continental = noise_macro.get_noise_3dv(d * 2.2) # [-1.0, 1.0]
	
	# Dağ Maskesi: Yalnızca kıtaların belirli %25-30'luk kısımlarında dağlar yükselir.
	# Geriye kalan alanlar pürüzsüz, gezilebilir geniş ovalar ve platolardır.
	var mountain_mask = smoothstep(0.18, 0.65, continental)
	
	# Düzlükler ve Vadiler: Hafif dalgalı, yürünebilir zemin (±110m)
	var plains = noise_hills.get_noise_3dv(d * 8.0) * 110.0
	
	# Temel arazi yüksekliği
	var base_terrain = (continental * 750.0) + plains
	
	# Sıradağlar: Sadece dağ maskesinin olduğu bölgelerde yükselir
	if lod >= 1 and mountain_mask > 0.01:
		var ridge_raw = 1.0 - absf(noise_ridge.get_noise_3dv(d * 14.0))
		var mountains = pow(ridge_raw, 2.2) * (max_mountain_height * 0.85) * mountain_mask
		base_terrain += mountains

	# Kraterler: Düz tabanlı doğal çanaklar (Gezilebilir taban)
	if lod >= 2:
		var crat_raw = clampf(noise_crater.get_noise_3dv(d * 65.0) + 1.0, 0.0, 1.6)
		# Düz tabanlı çanak
		var bowl = -280.0 * (1.0 - smoothstep(0.12, 0.40, crat_raw))
		var rim = exp(-pow((crat_raw - 0.44) / 0.07, 2.0)) * 140.0
		# Dağlık alanda kraterleri sönümle, düzlüklerde net kraterler olsun
		base_terrain += (bowl + rim) * (1.0 - mountain_mask * 0.65)

	# LOD 4+: Orta ölçekli yürünebilir sırtlar (Düzlükte yumuşak, dağda belirgin)
	if lod >= 4:
		var rolling = noise_hills.get_noise_3dv(d * 80.0) * (20.0 + 60.0 * mountain_mask)
		base_terrain += rolling

	# LOD 6+: Yürüme seviyesinde organik zemin pürüzü (0.8m - 3.2m doğal taşlık dalga)
	if lod >= 6:
		var micro = noise_detail.get_noise_3dv(d * 450.0) * (0.8 + 2.4 * mountain_mask)
		base_terrain += micro

	return clampf(base_terrain, min_valley_depth, max_mountain_height * 1.5)

func sample_normal(dir: Vector3, lod: int = 7, eps: float = 0.002) -> Vector3:
	var d = dir.normalized()
	var t1 = Vector3(-d.z, 0, d.x).normalized()
	if t1.length_squared() < 0.001:
		t1 = Vector3.RIGHT
	var t2 = d.cross(t1).normalized()
	
	var h0 = sample_height(d, lod)
	var h1 = sample_height((d + t1 * eps).normalized(), lod)
	var h2 = sample_height((d + t2 * eps).normalized(), lod)
	
	var dh1 = (h1 - h0) / eps
	var dh2 = (h2 - h0) / eps
	
	return (d - t1 * (dh1 / planet_radius) - t2 * (dh2 / planet_radius)).normalized()

# -----------------------------------------------------------------------------
# Kök Parçaları Oluşturma
# -----------------------------------------------------------------------------
func _create_root_nodes() -> void:
	for face_idx in range(6):
		var root = QuadNode.new(self, face_idx, 0, 0.0, 0.0, 2.0, null)
		root_nodes.append(root)
		build_queue.append(root)

# -----------------------------------------------------------------------------
# Her Karede Güncelleme (LOD Yönetimi ve Parça Üretimi)
# -----------------------------------------------------------------------------
func _process(_delta: float) -> void:
	if camera_ref == null:
		var vp = get_viewport()
		if vp != null and vp.get_camera_3d() != null:
			camera_ref = vp.get_camera_3d()
	if camera_ref == null:
		return
		
	var cam_pos = camera_ref.global_position
	
	# 1. Quadtree mesafelerini kontrol et ve bölünme/birleşmeleri yönet
	total_leaf_chunks = 0
	deepest_lod_rendered = 0
	for root in root_nodes:
		root.update(cam_pos)
		_gather_stats(root)
		
	# 2. Kuyruktan sınırlı sayıda parça üret (stutter engelleme)
	_process_build_queue()

func _gather_stats(node: QuadNode) -> void:
	if node.is_leaf:
		total_leaf_chunks += 1
		deepest_lod_rendered = maxi(deepest_lod_rendered, node.lod)
	else:
		for c in node.children:
			_gather_stats(c)

func _process_build_queue() -> void:
	var builds := 0
	while not build_queue.is_empty() and builds < MAX_BUILDS_PER_FRAME:
		var node = build_queue.pop_front()
		if node != null and is_instance_valid(node.sphere) and node.is_leaf and not node.is_mesh_ready:
			_build_node_mesh(node)
			node.is_mesh_ready = true
			builds += 1

# -----------------------------------------------------------------------------
# Parça Ağı (Mesh) Üretimi ve Dikiş Eteği (Skirt)
# -----------------------------------------------------------------------------
func _build_node_mesh(node: QuadNode) -> void:
	if is_instance_valid(node.mesh_instance):
		node.mesh_instance.queue_free()
		node.mesh_instance = null
		
	var base = face_bases[node.face_idx]
	var subdiv = chunk_subdivisions
	var step = node.size / float(subdiv)
	var half_size = node.size * 0.5
	var u_start = node.u_center - half_size
	var v_start = node.v_center - half_size
	
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	
	var row_stride = subdiv + 1
	verts.resize((subdiv + 1) * (subdiv + 1))
	normals.resize(verts.size())
	uvs.resize(verts.size())
	
	# 1. Ana ızgara tepeleri
	for iv in range(subdiv + 1):
		var v_val = v_start + float(iv) * step
		for iu in range(subdiv + 1):
			var u_val = u_start + float(iu) * step
			var cube_point: Vector3 = base["normal"] + base["right"] * u_val + base["up"] * v_val
			var sphere_dir = cube_point.normalized()
			
			var h = sample_height(sphere_dir, node.lod)
			var pos = sphere_dir * (planet_radius + h)
			var norm = sample_normal(sphere_dir, node.lod)
			
			var idx = iv * row_stride + iu
			verts[idx] = pos
			normals[idx] = norm
			uvs[idx] = Vector2(float(iu) / float(subdiv), float(iv) / float(subdiv))
			
	# 2. Ana ızgara üçgenleri (CCW)
	for iv in range(subdiv):
		for iu in range(subdiv):
			var i0 = iv * row_stride + iu
			var i1 = i0 + 1
			var i2 = (iv + 1) * row_stride + iu
			var i3 = i2 + 1
			
			indices.append(i0); indices.append(i2); indices.append(i1)
			indices.append(i1); indices.append(i2); indices.append(i3)
			
	# 3. Kenar Eteği (Mesh Skirts - LOD Yarıklarını Kapatma)
	var skirt_depth = node.approx_radius_meters * 0.12 # Parça boyutuyla orantılı etek
	var skirt_indices := []
	
	# Kenar indekslerini topla (Alt, Sağ, Üst, Sol)
	var edge_indices: Array[int] = []
	for iu in range(subdiv + 1): edge_indices.append(iu) # Alt kenar (iv=0)
	for iv in range(1, subdiv + 1): edge_indices.append(iv * row_stride + subdiv) # Sağ kenar (iu=subdiv)
	for iu in range(subdiv - 1, -1, -1): edge_indices.append(subdiv * row_stride + iu) # Üst kenar (iv=subdiv)
	for iv in range(subdiv - 1, 0, -1): edge_indices.append(iv * row_stride) # Sol kenar (iu=0)
	
	var base_vert_count = verts.size()
	for i in range(edge_indices.size()):
		var orig_idx = edge_indices[i]
		var orig_v = verts[orig_idx]
		var orig_dir = orig_v.normalized()
		var skirt_v = orig_v - orig_dir * skirt_depth
		
		verts.append(skirt_v)
		normals.append(normals[orig_idx])
		uvs.append(uvs[orig_idx])
		
		# Etek etrafında dörtgen üçgenleri kur
		var next_i = (i + 1) % edge_indices.size()
		var orig_next = edge_indices[next_i]
		var skirt_curr = base_vert_count + i
		var skirt_next = base_vert_count + next_i
		
		indices.append(orig_idx); indices.append(skirt_curr); indices.append(orig_next)
		indices.append(orig_next); indices.append(skirt_curr); indices.append(skirt_next)

	# 4. LOD Renkleri (Debug Renklendirme)
	const LOD_COLORS = [
		Color(0.90, 0.15, 0.15), # LOD 0: Kırmızı
		Color(0.95, 0.45, 0.10), # LOD 1: Turuncu
		Color(0.95, 0.85, 0.15), # LOD 2: Sarı
		Color(0.40, 0.88, 0.20), # LOD 3: Açık Yeşil
		Color(0.15, 0.85, 0.45), # LOD 4: Zümrüt Yeşili
		Color(0.15, 0.75, 0.95), # LOD 5: Camgöbeği
		Color(0.20, 0.40, 0.95), # LOD 6: Mavi
		Color(0.65, 0.25, 0.95), # LOD 7: Mor
	]
	var lod_color = LOD_COLORS[clampi(node.lod, 0, LOD_COLORS.size() - 1)]
	var skirt_color = lod_color.darkened(0.45)
	var colors := PackedColorArray()
	colors.resize(verts.size())
	for i in range(base_vert_count):
		colors[i] = lod_color
	for i in range(base_vert_count, verts.size()):
		colors[i] = skirt_color

	# 5. ArrayMesh Oluştur
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	
	var mi := MeshInstance3D.new()
	mi.name = "Chunk_F%d_L%d" % [node.face_idx, node.lod]
	mi.mesh = mesh
	mi.material_override = terrain_material
	mi.extra_cull_margin = 100000.0
	
	add_child(mi)
	node.mesh_instance = mi
	mi.visible = node.is_leaf
