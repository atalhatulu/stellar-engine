extends Node3D

# ─────────────────────────────────────────────────────────────────────────────
# STELLAR ENGINE - 1:1 GERÇEKÇİ GALAKSİ, GEMİ PİLOTAJI VE PROSEDÜREL YILDIZ SİSTEMLERİ
# 
# Özellikler:
# 1. 100.000 Aktif StarData Nesnesi: Ana oyunla aynı StarData biçimini ve
#    spektral dağılımı kullanır; test kataloğu ayrı GAL_ kimlik alanında tutulur.
# 2. Kesintisiz fly camera: fare ile bakış, WASD ile uçuş ve tekerlekle hız.
#    - Dinamik motor alevleri, iticiler ve warp efektleri.
# 3. Deterministik Prosedürel Gezegen Sistemleri (SystemGenerator):
#    - Her yıldızın tohumuna (sys_seed) bağlı gezegenler, uydular ve Keplerian yörüngeler.
#    - Yıldız seçildiğinde veya yaklaşıldığında anında inşa edilir; uzaklaşınca temizlenir.
# 4. Gemi / Gözlemci Çift Kontrol Modu ([V] tuşu):
#    - Spacecraft Modu: Korveti sür, kokpitte gez.
#    - Gözlemci Modu: 220.000 LY'ye kadar serbest galaktik panorama.
# ─────────────────────────────────────────────────────────────────────────────

const LIGHT_YEAR_METERS: float = 9460730472580800.0
const PARSEC_LY: float = 3.26156
const SOLAR_RADIUS_METERS: float = 696340000.0 # Güneş Yarıçapı (~696.340 km)
const ONE_AU: float = 149597870700.0 # 1 Astronomik Birim (metre)
const AU_VISUAL_SCALE: float = 0.08 # 1 AU = 0.08 LY görsel temsil ölçeği
const SYSTEM_VISUAL_METERS_PER_UNIT: float = ONE_AU / AU_VISUAL_SCALE
const MIN_MOON_ORBIT_VISUAL_FACTOR: float = 1.8
# Galaksi koordinatları LY cinsinden, gemi ve yerel sistem görselleri ise çok
# daha küçük olduğundan binlerce birimlik konumlar standart float hassasiyetini
# görünür biçimde kaybettirir. Oyuncuyu galaktik seyahatte merkeze yakın tut.
const FLOATING_ORIGIN_THRESHOLD_LY: float = 8.0
const SYSTEM_RENDER_LIMIT_METERS: float = 10000.0
const SYSTEM_RENDER_TO_GALAXY: float = 0.00002

const CosmicSectorManager = preload("res://scripts/generation/cosmic_sector_manager.gd")
const StreamedGalaxyField = preload("res://scripts/rendering/streamed_galaxy_field.gd")

# ─────────────────────────────────────────────────────────────────────────────
# 1. ASTROFİZİKSEL GALAKSİ VERİ SINIFI
# ─────────────────────────────────────────────────────────────────────────────
# ─────────────────────────────────────────────────────────────────────────────
# 2. PARAMETRELER VE DEĞİŞKENLER
# ─────────────────────────────────────────────────────────────────────────────
@export_group("1. Simülasyon Örneklemi")
@export var enable_spacecraft_mode: bool = false
@export_range(20, 500, 10) var total_neighbor_galaxies: int = 160:
	set(val):
		total_neighbor_galaxies = val
		if is_inside_tree(): _generate_extragalactic_cluster()

@export_range(10000, 300000, 5000) var total_stars: int = 100000:
	set(val):
		total_stars = val
		if is_inside_tree(): _generate_galaxy()

var _is_switching_galaxy: bool = false

@export var galaxy_seed: int = 2026:
	set(val):
		galaxy_seed = val
		if not _is_switching_galaxy and is_inside_tree():
			_derive_and_rebuild()

@export_group("2. Görsel Piksel ve Parlaklık Ölçeği (LOD)")
@export_range(0.2, 5.0, 0.05) var star_base_scale: float = 1.35:
	set(val):
		star_base_scale = val
		if multimesh_instance and multimesh_instance.material_override:
			multimesh_instance.material_override.set_shader_parameter("u_base_scale", val)

@export_range(0.0001, 0.0015, 0.00005) var distance_lod_scale: float = 0.00036:
	set(val):
		distance_lod_scale = val
		if multimesh_instance and multimesh_instance.material_override:
			multimesh_instance.material_override.set_shader_parameter("u_distance_lod_scale", val)

@export_range(0.2, 5.0, 0.05) var star_brightness_mult: float = 1.65:
	set(val):
		star_brightness_mult = val
		if is_inside_tree(): _generate_galaxy()

@export_range(0.5, 4.0, 0.05) var star_glow_boost: float = 1.40:
	set(val):
		star_glow_boost = val
		if multimesh_instance and multimesh_instance.material_override:
			multimesh_instance.material_override.set_shader_parameter("u_glow_boost", val)

# Sahne Düğümleri
@onready var spacecraft: Spacecraft = get_node_or_null("Spacecraft")
@onready var player: Player = get_node_or_null("Player")
@onready var hud: SystemHUD = get_node_or_null("HUD")
@onready var ui_control: Control = get_node_or_null("Control")
@onready var ui_label: RichTextLabel = get_node_or_null("Control/RichTextLabel")

var world_env: WorldEnvironment
var multimesh_instance: MultiMeshInstance3D
var extragalactic_multimesh: MultiMeshInstance3D
var black_hole_root: Node3D
var black_hole_mesh: MeshInstance3D
var accretion_disk_mesh: MeshInstance3D
var spectator_camera: Camera3D

# Arayüz & SystemHUD Entegrasyonu
var target_reticle: Panel
var target_tag_label: Label
var hud_panel: PanelContainer
var is_hud_visible: bool = true
var is_wireframe_mode: bool = false
var _ui_update_timer: float = 0.0
const UI_REFRESH_INTERVAL: float = 0.1 # 10 Hz arayüz yenileme sıklığı

# SystemHUD Uyumluluk Değişkenleri
var simulation_time: float = 0.0
var is_time_paused: bool = false
var is_system_map_active: bool = false
var is_eva_active: bool = false
var is_landed: bool = false
var landed_body: CelestialBody = null
var is_interstellar_autopilot: bool = false
var is_interstellar_hyper_boost: bool = false
var is_autopilot_active: bool = false
var is_hyper_autopilot: bool = false
var is_landing_autopilot: bool = false
var autopilot_target_body: CelestialBody = null
var astronaut_oxygen: float = 100.0
var astronaut_fuel: float = 100.0
var is_jetpack_active: bool = false
var is_jetpack_boosting: bool = false
var player_velocity: Vector3 = Vector3.ZERO
var flight_speed_mps: float = 0.0
const STAR_SYSTEM_ARRIVAL_SPEED_MPS: float = 50.0
const PLANET_APPROACH_SPEED_MPS: float = 5.0
var local_spectator_speed_mps: float = STAR_SYSTEM_ARRIVAL_SPEED_MPS
var dist_to_ship_eva: float = 0.0
var walk_speed_index: int = 2
const WALK_SPEED_PRESETS: Array = [3.0, 8.0, 15.0, 30.0, 60.0, 120.0, 250.0, 500.0, 1000.0]

# Gemi ve Kamera Görsel Ölçek Senkronizasyonu (1 Godot Birimi = 1 Işık Yılı)
const SHIP_VISUAL_SCALE: float = 0.02
const SHIP_LOCAL_OFFSET: Vector3 = Vector3(0.0, -0.45, -0.6) * SHIP_VISUAL_SCALE

# Hedefleme & StarData
var targeted_star_data: StarData = null
var current_target_index: int = -1
var black_hole_star_data: StarData = null
var fallback_galaxy_star: CelestialBody = null

var camera: Node3D:
	get:
		return player if control_mode == ControlMode.SPACECRAFT else spectator_camera

var camera_3d: Camera3D:
	get:
		return _get_active_camera()

var active_star: CelestialBody:
	get:
		if active_star_body != null:
			return active_star_body
		return fallback_galaxy_star

func get_player_galactic_position() -> Vector3:
	var cam = _get_active_camera()
	var p = cam.global_position if cam != null else Vector3.ZERO
	return (p + galaxy_origin_ly) * LIGHT_YEAR_METERS

func _star_world_position(star: StarData) -> Vector3:
	if star == null:
		return Vector3.ZERO
	var absolute_ly := Vector3(star.stellar_x, star.stellar_y, star.stellar_z) / LIGHT_YEAR_METERS
	return absolute_ly - galaxy_origin_ly

var active_galaxy_center_ly: Vector3 = Vector3.ZERO
var active_galaxy_radius_ly: float = 65000.0

func _galactic_center_world_position() -> Vector3:
	return active_galaxy_center_ly - galaxy_origin_ly

func _absolute_ly_to_world(absolute_ly: Vector3) -> Vector3:
	return absolute_ly - galaxy_origin_ly

# Galaksi kataloğunun 100.000 StarData örneği. Bu katalog test sahnesine özeldir;
# ana oyunun SectorManager kayıtlarının yerine geçmez.
var stars_data: Array[StarData] = []
var selected_star: StarData = null
var selected_planet: CelestialBody = null
var selected_black_hole: bool = false
var selected_extragalactic_galaxy: Galaxy = null
var current_astro: Galaxy = Galaxy.new()
var extragalactic_cluster: Array[Galaxy] = []
var cosmic_sector_manager: CosmicSectorManager = null
var streamed_galaxy_field: StreamedGalaxyField = null

# SystemGenerator Tarafından Beklenen Özellikler
var total_planets_count: int = 0
var total_moons_count: int = 0
var current_seed: int = 2026
var universe: Array[CelestialBody] = []

# Aktif Prosedürel Yıldız ve Gezegen Sistemi
var active_star_data: StarData = null
var active_star_body: CelestialBody = null
var active_system_bodies: Array[CelestialBody] = []
var active_system_root: Node3D = null
var active_planet_nodes: Array[Node3D] = []
var active_moon_nodes: Array[Node3D] = []
var show_orbit_lines: bool = true
var time_scale: float = 1.0
var galaxy_origin_ly: Vector3 = Vector3.ZERO
var system_stream_grace_seconds: float = 0.0

# Kontrol Modları
enum ControlMode { SPACECRAFT, SPECTATOR }
var control_mode: int = ControlMode.SPECTATOR

# Fly camera fiziksel hız merdiveni. Bütün değerler m/s tutulur; galaksi ve
# yerel sistem hareketi kendi dünya ölçeğine çevrilir.
var fly_speed_presets_mps: Array[float] = [
	50.0, 343.0, 3000.0, 30000.0, 300000.0,
	0.01 * 299792458.0, 0.1 * 299792458.0, 299792458.0,
	60.0 * 299792458.0, 3600.0 * 299792458.0, 86400.0 * 299792458.0,
	2629800.0 * 299792458.0,
	1.0 * LIGHT_YEAR_METERS, 10.0 * LIGHT_YEAR_METERS,
	100.0 * LIGHT_YEAR_METERS, 1000.0 * LIGHT_YEAR_METERS,
	5000.0 * LIGHT_YEAR_METERS, 10000.0 * LIGHT_YEAR_METERS,
	25000.0 * LIGHT_YEAR_METERS, 50000.0 * LIGHT_YEAR_METERS,
	100000.0 * LIGHT_YEAR_METERS, 250000.0 * LIGHT_YEAR_METERS,
	500000.0 * LIGHT_YEAR_METERS, 1000000.0 * LIGHT_YEAR_METERS,
	2500000.0 * LIGHT_YEAR_METERS, 5000000.0 * LIGHT_YEAR_METERS,
	10000000.0 * LIGHT_YEAR_METERS, 25000000.0 * LIGHT_YEAR_METERS,
	50000000.0 * LIGHT_YEAR_METERS, 100000000.0 * LIGHT_YEAR_METERS
]
var fly_speed_labels: Array[String] = [
	"50 m/s", "Mach 1", "3 km/s", "30 km/s", "300 km/s",
	"%1 Işık Hızı", "%10 Işık Hızı", "Işık Hızı (1c)",
	"1 Işık Dakikası/s", "1 Işık Saati/s", "1 Işık Günü/s",
	"1 Işık Ayı/s", "1 Işık Yılı/s", "10 Işık Yılı/s",
	"1 Işık Asrı/s (100 LY/s)", "1.000 Işık Yılı/s",
	"5.000 Işık Yılı/s", "10.000 Işık Yılı/s",
	"25.000 Işık Yılı/s", "50.000 Işık Yılı/s",
	"100.000 Işık Yılı/s", "250.000 Işık Yılı/s",
	"500.000 Işık Yılı/s", "1 Milyon Işık Yılı/s",
	"2,5 Milyon Işık Yılı/s", "5 Milyon Işık Yılı/s",
	"10 Milyon Işık Yılı/s", "25 Milyon Işık Yılı/s",
	"50 Milyon Işık Yılı/s", "100 Milyon Işık Yılı/s"
]
var speed_index: int = 0 # Başlangıç: 50 m/s; yalnızca fare tekerleği değiştirir.
var fly_speed_label: String = "50 m/s"
var cam_rot_x: float = 0.0
var cam_rot_y: float = 0.0
var mouse_captured: bool = false
var mouse_sensitivity: float = 0.0025

# ─────────────────────────────────────────────────────────────────────────────
# 3. BAŞLATMA VE KURULUM
# ─────────────────────────────────────────────────────────────────────────────
func _ready() -> void:
	current_seed = galaxy_seed
	_derive_and_rebuild()
	_setup_spectator_camera()
	_setup_player_and_spacecraft()
	_setup_hud()
	
	# Başlangıçta Orion kolu benzeri bir yıldızı otomatik seç ve sistemini yükle
	_select_initial_star()
	
	if OS.get_cmdline_user_args().has("--screenshot"):
		_capture_debug_screenshot()

func _capture_debug_screenshot() -> void:
	if OS.get_cmdline_user_args().has("--test-jump"):
		await get_tree().create_timer(0.3).timeout
		_fly_to_targeted_object()
		await get_tree().create_timer(2.0).timeout
	else:
		await get_tree().create_timer(1.2).timeout
	var vp = get_viewport()
	if vp != null:
		var img = vp.get_texture().get_image()
		if img != null:
			img.save_png("/home/teha/Desktop/debug.png")
			print(">>> [StellarEngine] Ekran Görüntüsü Kaydedildi: /home/teha/Desktop/debug.png")
	get_tree().quit()

func _derive_and_rebuild() -> void:
	var start_time = Time.get_ticks_msec()
	selected_star = null
	selected_planet = null
	selected_black_hole = false
	selected_extragalactic_galaxy = null
	targeted_star_data = null
	current_target_index = -1
	_despawn_planetary_system()
	_calculate_astrophysics()
	_init_black_hole_data()
	_setup_environment()
	_create_black_hole()
	_generate_galaxy()
	_generate_extragalactic_cluster()
	if streamed_galaxy_field == null:
		streamed_galaxy_field = StreamedGalaxyField.new()
		streamed_galaxy_field.name = "StreamedGalaxyField"
		add_child(streamed_galaxy_field)
	streamed_galaxy_field.setup(galaxy_seed, 20000)
	var elapsed = Time.get_ticks_msec() - start_time
	print(">>> [StellarEngine] %s (%s) %d StarData Yıldızı ve %d Komşu Galaksi Yüklendi! Süre: %d ms" % [
		current_astro.designation, current_astro.hubble_type, total_stars, extragalactic_cluster.size() - 1, elapsed
	])

func _setup_spectator_camera() -> void:
	spectator_camera = Camera3D.new()
	spectator_camera.name = "SpectatorCamera"
	spectator_camera.near = 1.0
	spectator_camera.far = 600000.0
	spectator_camera.fov = 65.0
	spectator_camera.current = true
	add_child(spectator_camera)
	spectator_camera.position = Vector3(18000.0, 650.0, 19000.0)
	spectator_camera.look_at(Vector3.ZERO, Vector3.UP)
	var initial_rotation := spectator_camera.rotation
	cam_rot_x = initial_rotation.x
	cam_rot_y = initial_rotation.y
	mouse_captured = true
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _setup_player_and_spacecraft() -> void:
	if player != null:
		player.camera_scale = SHIP_VISUAL_SCALE
		if player.camera_node != null:
			player.camera_node.near = 0.05
			player.camera_node.far = 250000.0
			player.camera_node.current = enable_spacecraft_mode and control_mode == ControlMode.SPACECRAFT
		
		# Hız kademesini galaksi ölçeğine ayarla (~2000 LY/s)
		player.speed_multiplier_index = 37
		player.target_speed = player.speed_presets[player.speed_multiplier_index]
		player.current_speed = player.target_speed
		
		# Başlangıç konumu: Galaksiye yukarıdan bakan kol bölgesi
		player.position = Vector3(18000.0, 650.0, 19000.0)
		player.look_at(Vector3.ZERO, Vector3.UP)
		var euler = player.transform.basis.get_euler()
		player.rot_x = euler.x
		player.rot_y = euler.y
		player.rot_z = 0.0
		
	if spacecraft != null and player != null:
		player.spacecraft = spacecraft
		spacecraft.scale = Vector3.ONE * SHIP_VISUAL_SCALE
		spacecraft.global_position = player.global_position + player.global_basis * SHIP_LOCAL_OFFSET
		spacecraft.global_basis = player.global_basis
		spacecraft.current_view_mode = Spacecraft.CameraViewMode.THIRD_PERSON
		spacecraft.is_seated_in_cockpit = true

	# Galaksi prototipinde varsayılan kontrol yalnızca fly camera'dır. Düğümleri
	# sahneden silmiyoruz; gemi geliştirmesine dönüldüğünde tek ayarla açılabilir.
	if not enable_spacecraft_mode:
		control_mode = ControlMode.SPECTATOR
		if player != null:
			player.process_mode = Node.PROCESS_MODE_DISABLED
			player.visible = false
			if player.camera_node != null:
				player.camera_node.current = false
		if spacecraft != null:
			spacecraft.process_mode = Node.PROCESS_MODE_DISABLED
			spacecraft.visible = false
		if spectator_camera != null:
			spectator_camera.current = true

func _select_initial_star() -> void:
	if stars_data.size() > 500:
		var candidate = stars_data[rng_pick_sample(stars_data.size())]
		selected_star = candidate
		targeted_star_data = candidate
		current_target_index = -1
		var star_pos = _star_world_position(candidate)
		var approach_pos = star_pos + Vector3(0.12, 0.06, 0.16)
		_teleport_player_or_spectator(approach_pos, star_pos)

func rng_pick_sample(size: int) -> int:
	var rng = RandomNumberGenerator.new()
	rng.seed = galaxy_seed + 77
	return rng.randi_range(size / 3, (size * 2) / 3)

# ─────────────────────────────────────────────────────────────────────────────
# 4. ASTROFİZİKSEL GALAKSİ TÜRETİMİ
# ─────────────────────────────────────────────────────────────────────────────
func _calculate_astrophysics() -> void:
	current_astro = Galaxy.generate(galaxy_seed)

func _setup_environment() -> void:
	if world_env != null:
		world_env.queue_free()
		
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.001, 0.001, 0.002)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.01, 0.01, 0.02)
	
	env.glow_enabled = true
	env.glow_intensity = 0.30
	env.glow_strength = 0.88
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.15
	
	world_env = WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

func _create_black_hole() -> void:
	if is_instance_valid(black_hole_root):
		black_hole_root.queue_free()
		
	black_hole_root = Node3D.new()
	black_hole_root.name = "SupermassiveBlackHole"
	black_hole_root.position = _galactic_center_world_position()
	add_child(black_hole_root)
	
	var bh_radius_ly = 12.0
	var disk_radius_ly = 65.0
	
	var sphere = SphereMesh.new()
	sphere.radius = bh_radius_ly
	sphere.height = bh_radius_ly * 2.0
	sphere.radial_segments = 64
	sphere.rings = 32
	
	var bh_mat = StandardMaterial3D.new()
	bh_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bh_mat.albedo_color = Color.BLACK
	
	black_hole_mesh = MeshInstance3D.new()
	black_hole_mesh.mesh = sphere
	black_hole_mesh.material_override = bh_mat
	black_hole_root.add_child(black_hole_mesh)
	
	var disk_quad = QuadMesh.new()
	disk_quad.size = Vector2(disk_radius_ly * 2.0, disk_radius_ly * 2.0)
	disk_quad.orientation = PlaneMesh.FACE_Y
	
	var accretion_shader = load("res://shaders/black_hole_accretion.gdshader")
	var disk_mat = ShaderMaterial.new()
	disk_mat.shader = accretion_shader
	disk_mat.set_shader_parameter("u_inner_radius", 0.22)
	disk_mat.set_shader_parameter("u_outer_radius", 0.96)
	disk_mat.set_shader_parameter("u_spin_speed", 0.35)
	disk_mat.set_shader_parameter("u_doppler_intensity", 0.45)
	disk_mat.set_shader_parameter("u_brightness", 0.85)
	
	accretion_disk_mesh = MeshInstance3D.new()
	accretion_disk_mesh.mesh = disk_quad
	accretion_disk_mesh.material_override = disk_mat
	black_hole_root.add_child(accretion_disk_mesh)

func _switch_active_galaxy(target_galaxy: Galaxy) -> void:
	if target_galaxy == null:
		return
	if is_instance_valid(multimesh_instance) and (target_galaxy.position_ly - active_galaxy_center_ly).length_squared() < 100.0:
		return
		
	_is_switching_galaxy = true
	active_galaxy_center_ly = target_galaxy.position_ly
	active_galaxy_radius_ly = target_galaxy.radius_ly
	current_astro = target_galaxy
	galaxy_seed = target_galaxy.system_seed if target_galaxy.system_seed != 0 else (target_galaxy.seed if target_galaxy.seed != 0 else 2026)
	_is_switching_galaxy = false
	
	_create_black_hole()
	_generate_galaxy()
	
	var g_name = target_galaxy.custom_name if target_galaxy.custom_name != "" else target_galaxy.designation
	print(">>> AKTİF GALAKSİ DEĞİŞTİRİLDİ: %s [%s] | 100.000 Yıldız ve Çekirdek Oluşturuldu!" % [g_name, target_galaxy.hubble_type])

# ─────────────────────────────────────────────────────────────────────────────
# 5. 100.000 GERÇEK STARDATA NESNESİNİN OLUŞTURULMASI (SECTOR_MANAGER MODELİ)
# ─────────────────────────────────────────────────────────────────────────────
func _generate_galaxy() -> void:
	if is_instance_valid(multimesh_instance):
		multimesh_instance.queue_free()
		
	stars_data.clear()
	stars_data.resize(total_stars)
	
	var rng = RandomNumberGenerator.new()
	rng.seed = galaxy_seed
	
	var mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	
	var quad = QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	mm.mesh = quad
	mm.instance_count = total_stars
	
	var star_shader = load("res://shaders/spiral_star_billboard.gdshader")
	var star_mat = ShaderMaterial.new()
	star_mat.shader = star_shader
	star_mat.set_shader_parameter("u_base_scale", star_base_scale)
	star_mat.set_shader_parameter("u_glow_boost", star_glow_boost)
	star_mat.set_shader_parameter("u_distance_lod_scale", distance_lod_scale)
	
	multimesh_instance = MultiMeshInstance3D.new()
	multimesh_instance.position = active_galaxy_center_ly - galaxy_origin_ly
	multimesh_instance.multimesh = mm
	multimesh_instance.material_override = star_mat
	multimesh_instance.custom_aabb = AABB(Vector3.ONE * -500000.0, Vector3.ONE * 1000000.0)
	multimesh_instance.extra_cull_margin = 2000000.0
	multimesh_instance.ignore_occlusion_culling = true
	add_child(multimesh_instance)
	
	var gal_r = current_astro.radius_ly
	var Rd = current_astro.disk_scale_length_ly
	var zd = current_astro.disk_scale_height_ly
	var R_core = current_astro.core_radius_ly
	var num_arms = current_astro.num_arms
	var pitch_rad = deg_to_rad(current_astro.arm_pitch_angle_deg)
	var b = 1.0 / tan(pitch_rad)
	var has_bar = current_astro.has_bar
	var bar_angle = rng.randf_range(0.0, PI)
	var bar_length = R_core * 1.6
	
	var arm_contrast = 0.88
	var young_factor = current_astro.young_star_boost
	var star_idx = 0
	# Bir sektörde 32'den fazla yıldız bulunabildiği için global indeks modülü
	# kimlik çakışması üretir. Her sektör kendi monoton sayacını kullanır.
	var sector_star_counts: Dictionary = {}
	
	while star_idx < total_stars:
		var u1 = maxf(rng.randf(), 0.00001)
		var u2 = maxf(rng.randf(), 0.00001)
		var r = -Rd * log(u1 * u2)
		if r > (gal_r * 1.15):
			continue
			
		var is_bulge = (r < R_core) and (rng.randf() < 0.65)
		var theta = rng.randf_range(0.0, TAU)
		var pos = Vector3.ZERO
		var in_spiral_arm = false
		
		if is_bulge:
			if has_bar and rng.randf() < 0.70:
				var t_bar = rng.randf_range(-1.0, 1.0)
				var bx = t_bar * (bar_length * 0.5)
				var bz = rng.randfn(0.0, bar_length * 0.14)
				var by = rng.randfn(0.0, zd * 0.35)
				pos = Vector3(
					bx * cos(bar_angle) - bz * sin(bar_angle),
					by,
					bx * sin(bar_angle) + bz * cos(bar_angle)
				)
			else:
				var phi = acos(rng.randf_range(-1.0, 1.0)) - (PI * 0.5)
				pos = Vector3(
					r * cos(phi) * cos(theta),
					r * sin(phi) * 0.45,
					r * cos(phi) * sin(theta)
				)
		else:
			var ref_angle = bar_angle if has_bar else 0.0
			var spiral_phase = ref_angle + b * log(maxf(r / R_core, 1.0))
			var wave = cos(float(num_arms) * (theta - spiral_phase))
			
			var acceptance_prob = (1.0 + arm_contrast * wave) / (1.0 + arm_contrast)
			if rng.randf() > acceptance_prob:
				continue
				
			if wave > 0.45:
				in_spiral_arm = true
				
			var u_z = rng.randf_range(-0.99, 0.99)
			var z_pos = zd * 0.5 * log((1.0 + u_z) / (1.0 - u_z))
			pos = Vector3(r * cos(theta), z_pos, r * sin(theta))
			
		# StarData Mimarisi
		var star = StarData.new()
		var sec_x = int(floor(pos.x / 65.0))
		var sec_y = int(floor(pos.y / 65.0))
		var sec_z = int(floor(pos.z / 65.0))
		var sector_coord := Vector3i(sec_x, sec_y, sec_z)
		var sector_star_index: int = int(sector_star_counts.get(sector_coord, 0)) + 1
		sector_star_counts[sector_coord] = sector_star_index
		star.sector_coord = sector_coord
		star.unique_id = "GAL_%d_SEC_%d_%d_%d_S%d" % [galaxy_seed, sec_x, sec_y, sec_z, sector_star_index]
		star.name = "S_%d_%d_%d_%d" % [sec_x, sec_y, sec_z, sector_star_index]
		star.system_seed = int(rng.randi()) & 0x7FFFFFFF
		star.extra_flags["catalog"] = "spiral_galaxy_test"
		star.extra_flags["catalog_index"] = star_idx
		var abs_star_pos = active_galaxy_center_ly + pos
		star.stellar_x = abs_star_pos.x * LIGHT_YEAR_METERS
		star.stellar_y = abs_star_pos.y * LIGHT_YEAR_METERS
		star.stellar_z = abs_star_pos.z * LIGHT_YEAR_METERS
		
		var spec_roll = rng.randf()
		var is_giant = 0.0
		
		if in_spiral_arm and rng.randf() < (0.28 * young_factor):
			if rng.randf() < 0.25:
				star.spectral_type = "Mavi Süperdev (O-tipi)"
				star.radius = rng.randf_range(2500000000.0, 7000000000.0)
				star.base_color = Color(0.25, 0.58, 1.0)
				star.light_color = Color(0.65, 0.82, 1.0)
				star.light_energy = rng.randf_range(2.6, 3.2)
				star.luminosity = rng.randf_range(6.0, 10.0)
				is_giant = 1.0
			else:
				star.spectral_type = "Mavi Dev (B-tipi)"
				star.radius = rng.randf_range(950000000.0, 1450000000.0)
				star.base_color = Color(0.35, 0.65, 1.0)
				star.light_color = Color(0.65, 0.82, 1.0)
				star.light_energy = rng.randf_range(2.2, 2.8)
				star.luminosity = rng.randf_range(3.5, 6.0)
				is_giant = 1.0 if rng.randf() < 0.3 else 0.0
		elif spec_roll < 0.68:
			star.spectral_type = "Kırmızı Cüce (M-tipi)"
			star.radius = rng.randf_range(160000000.0, 320000000.0)
			star.base_color = Color(1.0, 0.28, 0.12)
			star.light_color = Color(1.0, 0.45, 0.25)
			star.light_energy = rng.randf_range(0.9, 1.15)
			star.luminosity = rng.randf_range(0.15, 0.35)
		elif spec_roll < 0.84:
			star.spectral_type = "Turuncu Cüce (K-tipi)"
			star.radius = rng.randf_range(320000000.0, 460000000.0)
			star.base_color = Color(1.0, 0.55, 0.14)
			star.light_color = Color(1.0, 0.72, 0.38)
			star.light_energy = rng.randf_range(1.15, 1.35)
			star.luminosity = rng.randf_range(0.45, 0.75)
		elif spec_roll < 0.93:
			star.spectral_type = "Sarı Cüce (G-tipi)"
			star.radius = rng.randf_range(460000000.0, 620000000.0)
			star.base_color = Color(1.0, 0.88, 0.28)
			star.light_color = Color(1.0, 0.94, 0.75)
			star.light_energy = rng.randf_range(1.35, 1.6)
			star.luminosity = rng.randf_range(0.9, 1.25)
		elif spec_roll < 0.975:
			star.spectral_type = "Beyaz Yıldız (F/A-tipi)"
			star.radius = rng.randf_range(620000000.0, 880000000.0)
			star.base_color = Color(0.92, 0.96, 1.0)
			star.light_color = Color(0.96, 0.98, 1.0)
			star.light_energy = rng.randf_range(1.65, 2.0)
			star.luminosity = rng.randf_range(1.6, 2.6)
		elif spec_roll < 0.990:
			star.spectral_type = "Mavi Dev (B-tipi)"
			star.radius = rng.randf_range(950000000.0, 1450000000.0)
			star.base_color = Color(0.25, 0.58, 1.0)
			star.light_color = Color(0.65, 0.82, 1.0)
			star.light_energy = rng.randf_range(2.2, 2.8)
			star.luminosity = rng.randf_range(3.5, 6.0)
			is_giant = 1.0 if rng.randf() < 0.3 else 0.0
		else:
			star.spectral_type = "Kırmızı Dev (M/K-tipi Dev)"
			star.radius = rng.randf_range(1300000000.0, 2100000000.0)
			star.base_color = Color(1.0, 0.12, 0.04)
			star.light_color = Color(1.0, 0.32, 0.15)
			star.light_energy = rng.randf_range(1.8, 2.4)
			star.luminosity = rng.randf_range(2.2, 4.2)
			is_giant = 1.0 if rng.randf() < 0.4 else 0.0
			
		var type_roll = rng.randf()
		if type_roll < 0.12:
			star.system_type = "EMPTY (Gezegensiz)"
		elif type_roll < 0.92:
			star.system_type = "STANDARD (Gezegen Sistemli)"
		elif type_roll < 0.96:
			star.system_type = "ASTEROID_RICH (Asteroit Kuşaklı)"
			star.has_asteroid_belt = true
		else:
			star.system_type = "BINARY_CANDIDATE (Çift Yıldız Adayı)"
			star.is_binary_candidate = true

		# Gezegenleri oluşturmadan sistemin deterministik uzak LOD zarfını biliriz.
		# İlk ziyaret sonrası gerçek en dış yörünge ile bu değer güncellenir.
		star.system_radius_m = maxf(15.0, 12.0 * sqrt(maxf(star.luminosity, 0.05))) * ONE_AU
		star.activation_radius_visual = maxf(0.20, (star.system_radius_m / ONE_AU) * AU_VISUAL_SCALE * 1.25)
		star.deactivation_radius_visual = star.activation_radius_visual * 1.35
			
		stars_data[star_idx] = star
		
		# MultiMesh Dönüşüm ve Renk
		var t = Transform3D(Basis(), pos)
		mm.set_instance_transform(star_idx, t)
		mm.set_instance_color(star_idx, star.base_color)
		
		var norm_size = clamp(star.radius / SOLAR_RADIUS_METERS, 0.35, 3.5)
		var star_lum = star.luminosity * star.light_energy * star_brightness_mult
		mm.set_instance_custom_data(star_idx, Color(norm_size, rng.randf() * TAU, star_lum, is_giant))
		
		star_idx += 1

# ─────────────────────────────────────────────────────────────────────────────
# 5B. KOZMİK AĞ VE DERİN UZAY KOMŞU GALAKSİLERİ (EXTRAGALACTIC CLUSTER)
# ─────────────────────────────────────────────────────────────────────────────
func _generate_extragalactic_cluster() -> void:
	if is_instance_valid(extragalactic_multimesh):
		extragalactic_multimesh.queue_free()
		extragalactic_multimesh = null
		
	if cosmic_sector_manager == null:
		cosmic_sector_manager = CosmicSectorManager.new(galaxy_seed)
		
	var cam := _get_active_camera()
	var init_pos := (cam.global_position + galaxy_origin_ly) if cam != null else galaxy_origin_ly
	cosmic_sector_manager.update_sectors(init_pos)
	extragalactic_cluster = cosmic_sector_manager.active_galaxies
	
	var mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	
	var quad = QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	mm.mesh = quad
	mm.instance_count = CosmicSectorManager.MAX_ACTIVE_GALAXIES
	
	var g_shader = load("res://shaders/extragalactic_galaxy.gdshader")
	var g_mat = ShaderMaterial.new()
	g_mat.shader = g_shader
	g_mat.set_shader_parameter("u_brightness_boost", 1.85)
	g_mat.set_shader_parameter("u_min_pixel_size", 4.0)
	
	extragalactic_multimesh = MultiMeshInstance3D.new()
	extragalactic_multimesh.name = "ExtragalacticMultiMesh"
	extragalactic_multimesh.multimesh = mm
	extragalactic_multimesh.material_override = g_mat
	extragalactic_multimesh.position = Vector3.ZERO
	extragalactic_multimesh.custom_aabb = AABB(Vector3.ONE * -300000.0, Vector3.ONE * 600000.0)
	extragalactic_multimesh.extra_cull_margin = 600000.0
	extragalactic_multimesh.ignore_occlusion_culling = true
	add_child(extragalactic_multimesh)
	
	_update_extragalactic_lod()

func _update_extragalactic_lod() -> void:
	if not is_instance_valid(extragalactic_multimesh) or extragalactic_multimesh.multimesh == null:
		return
	var cam := _get_active_camera()
	if cam == null or not cam.is_inside_tree():
		return
	var observer_absolute_ly := cam.global_position + galaxy_origin_ly
	
	if streamed_galaxy_field != null:
		streamed_galaxy_field.update_renderer(cam, observer_absolute_ly)
	
	# Kozmik Grid / Sektör Güncellemesi (Sadece yeni chunk'a girildiğinde tetiklenir)
	if cosmic_sector_manager != null and cosmic_sector_manager.update_sectors(observer_absolute_ly):
		extragalactic_cluster = cosmic_sector_manager.active_galaxies
		
	var mm := extragalactic_multimesh.multimesh
	var active_count := extragalactic_cluster.size()
	const LOD_SPHERE_RADIUS_LY: float = 350000.0
	
	# Otomatik Yakın Galaksi Aktivasyonu:
	# Seyahat sırasında herhangi bir komşu galaksinin yakınına (2.2 * R) girildiğinde
	# o galaksiyi otomatik aktif yapıp 100.000 gerçek yıldızını ve çekirdeğini yükle
	var nearest_candidate: Galaxy = null
	var min_approach_dist := INF
	for g in extragalactic_cluster:
		if (g.position_ly - active_galaxy_center_ly).length_squared() < 100.0:
			continue
		var d := (g.position_ly - observer_absolute_ly).length()
		var switch_dist := maxf(g.radius_ly * 2.2, 45000.0)
		if d < switch_dist and d < min_approach_dist:
			min_approach_dist = d
			nearest_candidate = g
			
	if nearest_candidate != null and not _is_switching_galaxy:
		_switch_active_galaxy(nearest_candidate)
	
	# SpaceEngine Modeli: Aktif odak galaksinin 100.000 tekil yıldızı ile uzak impostor'ı arasında geçiş
	var dist_to_active := (observer_absolute_ly - active_galaxy_center_ly).length()
	var active_threshold := maxf(active_galaxy_radius_ly * 3.5, 300000.0)
	if is_instance_valid(multimesh_instance):
		multimesh_instance.visible = (dist_to_active < active_threshold)
	if is_instance_valid(black_hole_root):
		black_hole_root.visible = (dist_to_active < active_threshold * 0.75)
		
	for i in range(mm.instance_count):
		if i < active_count:
			var galaxy := extragalactic_cluster[i]
			var relative_ly: Vector3 = galaxy.position_ly - observer_absolute_ly
			var real_distance_ly := relative_ly.length()
			
			# Aktif galaksi yakınındayken kendi impostorumuzu gizle (100.000 yıldız ve sarmallar devrede)
			var is_current_focal := (galaxy.position_ly - active_galaxy_center_ly).length_squared() < 100.0
			if is_current_focal and dist_to_active < active_threshold * 0.8:
				var hidden_t := Transform3D.IDENTITY
				hidden_t.origin = Vector3(0.0, -999999.0, 0.0)
				mm.set_instance_transform(i, hidden_t)
				mm.set_instance_custom_data(i, Color(0.0, 0.0, 0.0, 0.0))
				continue
				
			if real_distance_ly <= 0.001:
				continue
				
			var lod_distance_ly := minf(real_distance_ly, LOD_SPHERE_RADIUS_LY)
			var render_position := cam.global_position + (relative_ly / real_distance_ly) * lod_distance_ly
			var visual_radius := galaxy.radius_ly * (lod_distance_ly / real_distance_ly)
			
			var transform := Transform3D.IDENTITY
			transform = transform.rotated(Vector3.RIGHT, galaxy.rotation_euler.x)
			transform = transform.rotated(Vector3.UP, galaxy.rotation_euler.y)
			transform = transform.rotated(Vector3.FORWARD, galaxy.rotation_euler.z)
			transform.origin = render_position
			mm.set_instance_transform(i, transform)
			mm.set_instance_color(i, galaxy.color_tint)
			mm.set_instance_custom_data(i, Color(
				visual_radius,
				float(galaxy.morphology),
				galaxy.arm_pitch_angle_deg / 20.0,
				float(galaxy.num_arms)
			))
		else:
			# Boş havuz örneklerini sahne dışına gizle
			var hidden_t := Transform3D.IDENTITY
			hidden_t.origin = Vector3(0.0, -999999.0, 0.0)
			mm.set_instance_transform(i, hidden_t)
			mm.set_instance_custom_data(i, Color(0.0, 0.0, 0.0, 0.0))

# ─────────────────────────────────────────────────────────────────────────────
# 6. BELLEK DOSTU PROSEDÜREL YILDIZ SİSTEMİ OLUŞTURMA (SYSTEMGENERATOR)
# ─────────────────────────────────────────────────────────────────────────────
func _spawn_planetary_system(star_data: StarData) -> void:
	if star_data == null:
		return
	if active_star_data == star_data and is_instance_valid(active_system_root):
		return
		
	_despawn_planetary_system()
	active_star_data = star_data
	
	active_system_root = Node3D.new()
	active_system_root.name = "ActiveStarSystem_" + star_data.name
	var star_gal_pos = _star_world_position(star_data)
	active_system_root.position = star_gal_pos
	add_child(active_system_root)
	
	# 1. StarData'yı CelestialBody nesnesine dönüştür
	active_star_body = SystemGenerator.instantiate_star_from_data(self, star_data)
	
	# Aktif sistem yıldızı gerçek 3D küre olarak çizildiğinden MultiMesh billboard'u sıfırlanır
	if multimesh_instance != null and multimesh_instance.multimesh != null:
		var cat_idx: int = int(star_data.extra_flags.get("catalog_index", -1))
		if cat_idx >= 0 and cat_idx < multimesh_instance.multimesh.instance_count:
			multimesh_instance.multimesh.set_instance_transform(cat_idx, Transform3D(Basis().scaled(Vector3.ZERO), Vector3(0, -99999999, 0)))
	
	# 2. Görseller ana yıldız sistemiyle aynı SystemGenerator zincirinden gelir.
	SystemGenerator.generate_body_textures(self, active_star_body)
	SystemGenerator.spawn_body_graphics(self, active_star_body)
	_configure_shared_body_visual(active_star_body)
	
	var star_light = OmniLight3D.new()
	star_light.light_color = star_data.light_color
	star_light.light_energy = star_data.light_energy * 2.2
	star_light.omni_range = 10.0
	star_light.omni_attenuation = 1.0
	active_system_root.add_child(star_light)
	
	# 3. Gezegen ve Uyduları Deterministik Olarak Üret
	active_system_bodies = SystemGenerator.generate_planets_for_star(self, active_star_body, false)
	star_data.system_radius_m = maxf(active_star_body.system_diameter * 0.5, active_star_body.real_radius * 10.0)
	star_data.activation_radius_visual = maxf(0.20, (star_data.system_radius_m / ONE_AU) * AU_VISUAL_SCALE * 1.25)
	star_data.deactivation_radius_visual = star_data.activation_radius_visual * 1.35
	star_data.discovered = true
	system_stream_grace_seconds = 1.0
	active_planet_nodes.clear()
	active_moon_nodes.clear()
	
	for body in active_system_bodies:
		SystemGenerator.generate_body_textures(self, body)
		SystemGenerator.spawn_body_graphics(self, body)
		_configure_shared_body_visual(body)
			
	# 4. Evren (Universe) Listesini Güncelle
	universe.clear()
	if active_star_body != null:
		universe.append(active_star_body)
	for body in active_system_bodies:
		universe.append(body)

func _configure_shared_body_visual(body: CelestialBody) -> void:
	if not is_instance_valid(body.visual_mesh):
		return
	body.visual_mesh.reparent(active_system_root, false)
	if is_instance_valid(body.lod_sprite):
		body.lod_sprite.reparent(active_system_root, false)
	if is_instance_valid(body.orbit_line_mesh):
		body.orbit_line_mesh.reparent(active_system_root, false)

	if body.type == "STAR":
		body.visual_mesh.scale = Vector3.ONE * 0.075
		body.visual_mesh.position = Vector3.ZERO
	elif body.type == "PLANET":
		var visual_radius := _get_planet_visual_radius(body)
		body.visual_mesh.scale = Vector3.ONE * visual_radius
		body.visual_mesh.position = body.get_orbit_position() * (AU_VISUAL_SCALE / ONE_AU)
		active_planet_nodes.append(body.visual_mesh)
	elif body.type == "MOON":
		var parent_radius := _get_planet_visual_radius(body.parent_body) if body.parent_body != null else 0.012
		body.visual_mesh.scale = Vector3.ONE * maxf(parent_radius * 0.22, 0.003)
		active_moon_nodes.append(body.visual_mesh)

	if is_instance_valid(body.lod_sprite):
		body.lod_sprite.visible = false

func _build_planet_visual(planet: CelestialBody) -> void:
	var planet_pivot = Node3D.new()
	planet_pivot.name = planet.name
	active_system_root.add_child(planet_pivot)
	active_planet_nodes.append(planet_pivot)
	
	# Gezegen Küresi
	var mesh_inst = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	var visual_r := _get_planet_visual_radius(planet)
	sphere.radius = visual_r
	sphere.height = visual_r * 2.0
	sphere.radial_segments = 32
	sphere.rings = 16
	mesh_inst.mesh = sphere
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = planet.base_color
	mat.roughness = planet.roughness
	mat.metallic = planet.metallic
	mesh_inst.material_override = mat
	planet_pivot.add_child(mesh_inst)
	planet.visual_mesh = mesh_inst
	
	# Atmosfer Halesi
	if planet.has_atmosphere:
		var atmos_mesh = MeshInstance3D.new()
		var a_sphere = SphereMesh.new()
		a_sphere.radius = visual_r * 1.15
		a_sphere.height = visual_r * 2.30
		atmos_mesh.mesh = a_sphere
		var a_mat = StandardMaterial3D.new()
		a_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		a_mat.albedo_color = Color(planet.base_color.r, planet.base_color.g, 1.0, 0.30)
		a_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		a_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		atmos_mesh.material_override = a_mat
		planet_pivot.add_child(atmos_mesh)
		
	# Keplerian Yörünge Çizgisi
	var orbit_instance = MeshInstance3D.new()
	var imm = ImmediateMesh.new()
	imm.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	var steps = 64
	var line_color = Color(0.18, 0.85, 1.0, 0.45)
	for s in range(steps + 1):
		var theta = (float(s) / steps) * TAU
		var pt_m = planet.get_orbit_position_at_mean_anomaly(theta)
		var pt_vis = pt_m * (AU_VISUAL_SCALE / ONE_AU)
		imm.surface_set_color(line_color)
		imm.surface_add_vertex(pt_vis)
	imm.surface_end()
	
	var o_mat = StandardMaterial3D.new()
	o_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	o_mat.vertex_color_use_as_albedo = true
	o_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	o_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	orbit_instance.mesh = imm
	orbit_instance.material_override = o_mat
	active_system_root.add_child(orbit_instance)
	planet.orbit_line_mesh = orbit_instance
	
	# Uyduları Ekle
	var m_idx = 0
	for b in active_system_bodies:
		if b.type == "MOON" and b.parent_body == planet:
			m_idx += 1
			var moon_mesh = MeshInstance3D.new()
			var m_sphere = SphereMesh.new()
			var m_r = maxf(visual_r * 0.22, 0.003)
			m_sphere.radius = m_r
			m_sphere.height = m_r * 2.0
			moon_mesh.mesh = m_sphere
			var m_mat = StandardMaterial3D.new()
			m_mat.albedo_color = Color(0.72, 0.75, 0.82)
			m_mat.roughness = 0.85
			moon_mesh.material_override = m_mat
			planet_pivot.add_child(moon_mesh)
			b.visual_mesh = moon_mesh
			active_moon_nodes.append(moon_mesh)

func _get_planet_visual_radius(planet: CelestialBody) -> float:
	var r_norm := clampf(planet.real_radius / 6371000.0, 0.4, 11.0)
	return lerpf(0.009, 0.032, (r_norm - 0.4) / 10.6)

func _despawn_planetary_system() -> void:
	if active_star_data != null and multimesh_instance != null and multimesh_instance.multimesh != null:
		var cat_idx: int = int(active_star_data.extra_flags.get("catalog_index", -1))
		if cat_idx >= 0 and cat_idx < multimesh_instance.multimesh.instance_count:
			var orig_pos := Vector3(active_star_data.stellar_x, active_star_data.stellar_y, active_star_data.stellar_z) / LIGHT_YEAR_METERS
			multimesh_instance.multimesh.set_instance_transform(cat_idx, Transform3D(Basis(), orig_pos))
	if is_instance_valid(active_system_root):
		active_system_root.queue_free()
		active_system_root = null
	active_star_data = null
	active_star_body = null
	active_system_bodies.clear()
	active_planet_nodes.clear()
	active_moon_nodes.clear()
	universe.clear()
	selected_planet = null
	if current_target_index >= 0:
		current_target_index = -1

func _update_planetary_system_simulation(delta: float) -> void:
	if not is_instance_valid(active_system_root) or active_star_body == null:
		return
		
	var cam = _get_active_camera()
	var cam_pos = cam.global_position if cam != null else Vector3.ZERO
	# Aktif sistem ayrı bir yerel ölçek balonudur: burada bir görsel birim LY
	# değil, AU_VISUAL_SCALE oranıyla büyütülmüş astronomik birim temsil eder.
	# Böylece yıldızın yanındaki 0.1 birimlik kamera uzaklığı binlerce AU olmaz.
	var star_offset_visual: Vector3 = active_system_root.global_position - cam_pos
	active_star_body.real_position = star_offset_visual * SYSTEM_VISUAL_METERS_PER_UNIT
	
	for body in active_system_bodies:
		if body.type == "PLANET":
			body.orbit_angle += body.orbit_speed * delta * time_scale
			body.rotation_angle += body.rotation_speed * delta * time_scale
			var local_orbit_pos = body.get_orbit_position() * (AU_VISUAL_SCALE / ONE_AU)
			if is_instance_valid(body.visual_mesh):
				body.visual_mesh.position = local_orbit_pos
				body.visual_mesh.rotation.y = body.rotation_angle
			if is_instance_valid(body.orbit_line_mesh):
				body.orbit_line_mesh.visible = show_orbit_lines
				
			# real_position her zaman fiziksel metre taşır. AU_VISUAL_SCALE yalnızca
			# render konumunda kullanılır; aksi halde HUD ve uçuş fiziği yüz binlerce
			# kat hatalı mesafe görür.
			body.local_position = body.get_orbit_position()
			body.real_position = active_star_body.real_position + body.local_position
		elif body.type == "MOON" and is_instance_valid(body.visual_mesh):
			body.orbit_angle += (body.orbit_speed + 0.05) * delta * time_scale
			var moon_orbit_m := body.get_orbit_position()
			body.local_position = moon_orbit_m
			if body.parent_body != null:
				var natural_visual := moon_orbit_m * (AU_VISUAL_SCALE / ONE_AU)
				var parent_visual_radius := _get_planet_visual_radius(body.parent_body)
				var min_visual_distance := parent_visual_radius * MIN_MOON_ORBIT_VISUAL_FACTOR
				if natural_visual.length() < min_visual_distance:
					natural_visual = moon_orbit_m.normalized() * min_visual_distance
				var parent_visual_pos := body.parent_body.get_orbit_position() * (AU_VISUAL_SCALE / ONE_AU)
				body.visual_mesh.position = parent_visual_pos + natural_visual
				body.real_position = body.parent_body.real_position + moon_orbit_m

	_apply_shared_system_projection(cam)

func _apply_shared_system_projection(cam: Camera3D) -> void:
	if cam == null or not cam.is_inside_tree() or active_star_body == null:
		return
	var viewport_height := 1080.0
	if get_viewport() != null and get_viewport().size.y > 0:
		viewport_height = float(get_viewport().size.y)
	var render_bodies: Array[CelestialBody] = [active_star_body]
	render_bodies.append_array(active_system_bodies)
	for body in render_bodies:
		var distance_m := body.real_position.length()
		var projection := CelestialRenderScale.project_body(
			body, distance_m, viewport_height, cam.fov,
			SYSTEM_RENDER_LIMIT_METERS, 1.0, false
		)
		var projected_m := CelestialRenderScale.project_position(body.real_position, SYSTEM_RENDER_LIMIT_METERS)
		var world_position := cam.global_position + projected_m * SYSTEM_RENDER_TO_GALAXY
		var world_scale: float = float(projection["render_scale"]) * SYSTEM_RENDER_TO_GALAXY
		body.is_lod = bool(projection["use_lod"])
		if is_instance_valid(body.visual_mesh):
			body.visual_mesh.global_position = world_position
			body.visual_mesh.scale = Vector3.ONE * world_scale
			body.visual_mesh.visible = not body.is_lod
		if is_instance_valid(body.lod_sprite):
			body.lod_sprite.global_position = world_position
			body.lod_sprite.scale = Vector3.ONE * world_scale
			body.lod_sprite.visible = body.is_lod

	# Yörüngeler de main_star ile aynı fiziksel örnek noktaları ve aynı 10 km
	# projeksiyon sınırını kullanır. Uniform son katsayı oranları değiştirmez.
	for body in active_system_bodies:
		if not is_instance_valid(body.orbit_line_mesh):
			continue
		body.orbit_line_mesh.visible = show_orbit_lines
		if not show_orbit_lines:
			continue
		var immediate := body.orbit_line_mesh.mesh as ImmediateMesh
		if immediate == null:
			continue
		immediate.clear_surfaces()
		immediate.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
		var line_color := Color(0.15, 0.75, 1.0, 0.35) if body.type != "MOON" else Color(0.75, 0.85, 1.0, 0.18)
		var parent_relative_m := body.parent_body.real_position if body.parent_body != null else Vector3.ZERO
		for orbit_point_m in body.orbit_sample_points:
			var relative_m: Vector3 = parent_relative_m + orbit_point_m
			var projected_m := CelestialRenderScale.project_position(relative_m, SYSTEM_RENDER_LIMIT_METERS)
			immediate.surface_set_color(line_color)
			immediate.surface_add_vertex(projected_m * SYSTEM_RENDER_TO_GALAXY)
		immediate.surface_end()
		body.orbit_line_mesh.global_position = cam.global_position

# ─────────────────────────────────────────────────────────────────────────────
# 7. OYUNCU, GEMİ VE KAMERA DİNAMİKLERİ
# ─────────────────────────────────────────────────────────────────────────────
func _get_active_camera() -> Camera3D:
	if control_mode == ControlMode.SPACECRAFT and player != null and player.camera_node != null:
		return player.camera_node
	return spectator_camera

func _process(delta: float) -> void:
	# 1. Önce uçuş ve kamera hareketini işlet (1-frame gecikmesini ve titremeyi sıfırla)
	if control_mode == ControlMode.SPACECRAFT:
		_process_spacecraft_flight(delta)
		flight_speed_mps = player.current_speed if player != null else 0.0
	else:
		_process_spectator_flight(delta)
		flight_speed_mps = fly_speed_presets_mps[speed_index]
		local_spectator_speed_mps = flight_speed_mps
		fly_speed_label = fly_speed_labels[speed_index]
		if spectator_camera != null:
			spectator_camera.set("current_speed", flight_speed_mps)
			
	# 2. Güncel kamera konumuna göre kayan orijin ve galaksi LOD'unu senkronize güncelle
	_update_floating_origin()
	_update_extragalactic_lod()
		
	simulation_time += delta * (time_scale if not is_time_paused else 0.0)
	_update_planetary_system_simulation(delta)
	_update_system_streaming(delta)
	
	_ui_update_timer += delta
	if _ui_update_timer >= UI_REFRESH_INTERVAL:
		_ui_update_timer = 0.0
		if hud != null:
			hud.update_hud(self)
		if hud_panel != null and hud_panel.visible:
			_update_debug_ui()
			
	_update_target_reticle(delta)

func _update_system_streaming(delta: float) -> void:
	var cam := _get_active_camera()
	if cam == null or not cam.is_inside_tree():
		return
	var stream_position := cam.global_position
	if control_mode == ControlMode.SPACECRAFT and player != null and player.is_inside_tree():
		stream_position = player.global_position
	if is_instance_valid(active_system_root) and active_star_data != null:
		system_stream_grace_seconds = maxf(system_stream_grace_seconds - delta, 0.0)
		if system_stream_grace_seconds > 0.0:
			return
		var exit_radius := maxf(active_star_data.deactivation_radius_visual, 0.35)
		if stream_position.distance_to(active_system_root.global_position) > exit_radius:
			print(">>> SİSTEM LOD ÇIKIŞI: %s (gezegen ve uydu nesneleri temizlendi)" % active_star_data.name)
			_despawn_planetary_system()
		return
	if selected_star != null:
		var enter_radius := maxf(selected_star.activation_radius_visual, 0.20)
		if stream_position.distance_to(_star_world_position(selected_star)) <= enter_radius:
			_spawn_planetary_system(selected_star)

func _update_floating_origin() -> void:
	var cam := _get_active_camera()
	# Adaptif Eşik: Yerel yıldız/gezegen sistemindeyken 8.0 LY, derin uzaydayken 2500.0 LY
	# Böylece yüksek hızda seyahat ederken her karede gereksiz koordinat zıplaması ve titreme yaşanmaz
	var threshold := 8.0 if is_instance_valid(active_system_root) else 2500.0
	if cam == null or cam.global_position.length() < threshold:
		return
	var shift: Vector3 = cam.global_position
	galaxy_origin_ly += shift
	if is_instance_valid(multimesh_instance):
		multimesh_instance.position -= shift
	if is_instance_valid(black_hole_root):
		black_hole_root.position -= shift
	if is_instance_valid(active_system_root):
		active_system_root.position -= shift
	if player != null:
		player.position -= shift
	if spectator_camera != null:
		spectator_camera.position -= shift
	if spacecraft != null:
		spacecraft.global_position -= shift

func _process_spacecraft_flight(delta: float) -> void:
	if player == null or spacecraft == null:
		return
		
	# Kabin içi yürüme modu aktifse gemi uzayda hareket etmez
	var is_walking = (spacecraft.current_view_mode == Spacecraft.CameraViewMode.INTERIOR_FPS and not spacecraft.is_seated_in_cockpit)
	if is_walking or not spacecraft.is_seated_in_cockpit:
		return

	# 1. Yıldızlararası ve Galaksilerarası Warp Otopilotu (G Tuşu ile Seyir)
	if is_interstellar_autopilot and (selected_star != null or selected_extragalactic_galaxy != null):
		var has_manual_input = (
			Input.is_key_pressed(KEY_W) or
			Input.is_key_pressed(KEY_S) or
			Input.is_key_pressed(KEY_A) or
			Input.is_key_pressed(KEY_D) or
			Input.is_key_pressed(KEY_SPACE) or
			Input.is_key_pressed(KEY_CTRL)
		)
		if has_manual_input:
			is_interstellar_autopilot = false
			print(">>> Manuel Müdahale: Warp Otopilotu Devreden Çıkarıldı")
		elif selected_star != null:
			var target_pos = _star_world_position(selected_star)
			var to_target = target_pos - player.position
			var dist_ly = to_target.length()
			
			if dist_ly <= 0.28:
				# Sisteme varıldı!
				is_interstellar_autopilot = false
				_enter_selected_star_system()
				return
			
			var move_dir = to_target / dist_ly
			# Kamerayı ve gemiyi hedefe yumuşakça yönlendir
			var target_pitch = asin(clampf(move_dir.y, -0.9999, 0.9999))
			var target_yaw = atan2(-move_dir.x, -move_dir.z)
			player.rot_x = lerp_angle(player.rot_x, target_pitch, 7.0 * delta)
			player.rot_y = lerp_angle(player.rot_y, target_yaw, 7.0 * delta)
			player.rot_z = lerp_angle(player.rot_z, 0.0, 7.0 * delta)
			player.transform.basis = Basis.from_euler(Vector3(player.rot_x, player.rot_y, player.rot_z))
			
			# Mesafeye göre dinamik warp hızı (mesafe arttıkça hızlanır, yaklaştıkça frenler)
			var warp_speed_ly = clampf(dist_ly * 3.5, 8.0, 16000.0)
			player.current_speed = warp_speed_ly * LIGHT_YEAR_METERS
			player.target_speed = player.current_speed
			player.position += move_dir * warp_speed_ly * delta
			
			spacecraft.global_position = player.global_position + player.global_basis * SHIP_LOCAL_OFFSET
			spacecraft.global_basis = player.global_basis
			return
		elif selected_extragalactic_galaxy != null:
			var target_pos = selected_extragalactic_galaxy.position_ly - galaxy_origin_ly
			var to_target = target_pos - player.position
			var dist_ly = to_target.length()
			var stop_dist_ly = selected_extragalactic_galaxy.radius_ly * 1.5
			
			if dist_ly <= stop_dist_ly:
				is_interstellar_autopilot = false
				_switch_active_galaxy(selected_extragalactic_galaxy)
				print(">>> Galaksiye Ulaşıldı: %s [%s]" % [selected_extragalactic_galaxy.designation, selected_extragalactic_galaxy.hubble_type])
				return
				
			var move_dir = to_target / dist_ly
			var target_pitch = asin(clampf(move_dir.y, -0.9999, 0.9999))
			var target_yaw = atan2(-move_dir.x, -move_dir.z)
			player.rot_x = lerp_angle(player.rot_x, target_pitch, 7.0 * delta)
			player.rot_y = lerp_angle(player.rot_y, target_yaw, 7.0 * delta)
			player.rot_z = lerp_angle(player.rot_z, 0.0, 7.0 * delta)
			player.transform.basis = Basis.from_euler(Vector3(player.rot_x, player.rot_y, player.rot_z))
			
			var warp_speed_ly = clampf(dist_ly * 0.8, 50.0, 800000.0)
			player.current_speed = warp_speed_ly * LIGHT_YEAR_METERS
			player.target_speed = player.current_speed
			player.position += move_dir * warp_speed_ly * delta
			
			spacecraft.global_position = player.global_position + player.global_basis * SHIP_LOCAL_OFFSET
			spacecraft.global_basis = player.global_basis
			return
			
	# 2. Manuel Serbest Uçuş Kontrolleri
	var input_dir = Vector3.ZERO
	if Input.is_key_pressed(KEY_W): input_dir.z -= 1.0
	if Input.is_key_pressed(KEY_S): input_dir.z += 1.0
	if Input.is_key_pressed(KEY_A): input_dir.x -= 1.0
	if Input.is_key_pressed(KEY_D): input_dir.x += 1.0
	if Input.is_key_pressed(KEY_SPACE): input_dir.y += 1.0
	if Input.is_key_pressed(KEY_CTRL): input_dir.y -= 1.0
	
	var speed_ly: float
	if is_instance_valid(active_system_root):
		speed_ly = player.current_speed / SYSTEM_VISUAL_METERS_PER_UNIT
	else:
		speed_ly = player.current_speed / LIGHT_YEAR_METERS
		if speed_ly < 0.001:
			speed_ly = fly_speed_presets_mps[speed_index] / LIGHT_YEAR_METERS
	if input_dir.length_squared() > 0.001:
		var fwd = -player.global_transform.basis.z
		var rgt = player.global_transform.basis.x
		var up = player.global_transform.basis.y
		var move_dir = (fwd * -input_dir.z + rgt * input_dir.x + up * input_dir.y).normalized()
		player.position += move_dir * speed_ly * delta
		
	spacecraft.global_position = player.global_position + player.global_basis * SHIP_LOCAL_OFFSET
	spacecraft.global_basis = player.global_basis
	
	# Yaklaşınca streaming katmanı aynı sahnede gerçek sistemi etkinleştirir.

func _process_spectator_flight(delta: float) -> void:
	if spectator_camera == null:
		return

	if is_interstellar_autopilot and selected_extragalactic_galaxy != null:
		var has_manual_input := (
			Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_S) or
			Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_D) or
			Input.is_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_CTRL) or
			Input.is_key_pressed(KEY_Q)
		)
		if has_manual_input:
			is_interstellar_autopilot = false
			print(">>> Galaksilerarası seyir manuel hareketle iptal edildi")
		else:
			var target_pos := selected_extragalactic_galaxy.position_ly - galaxy_origin_ly
			var to_target := target_pos - spectator_camera.position
			var distance_ly := to_target.length()
			var arrival_radius_ly := maxf(selected_extragalactic_galaxy.radius_ly * 1.8, 5000.0)
			if distance_ly <= arrival_radius_ly:
				is_interstellar_autopilot = false
				var target_gal := selected_extragalactic_galaxy
				var desig := target_gal.designation if target_gal != null else "Galaksi"
				_switch_active_galaxy(target_gal)
				print(">>> GALAKSİYE VARILDI: %s | Merkeze uzaklık: %.0f LY" % [desig, distance_ly])
				return
			var travel_direction := to_target / distance_ly
			var base_speed_ly := fly_speed_presets_mps[speed_index] / LIGHT_YEAR_METERS
			var warp_speed_ly := maxf(base_speed_ly, distance_ly * 0.95)
			warp_speed_ly = clampf(warp_speed_ly, 100.0, 2000000.0)
			var travel_step := minf(warp_speed_ly * delta, distance_ly - arrival_radius_ly)
			spectator_camera.position += travel_direction * travel_step
			var target_basis := Basis.looking_at(travel_direction, Vector3.UP)
			spectator_camera.basis = spectator_camera.basis.slerp(target_basis, 1.0 - exp(-3.5 * delta)).orthonormalized()
			var rotation_now := spectator_camera.rotation
			cam_rot_x = rotation_now.x
			cam_rot_y = rotation_now.y
			return
		
	var move_vec = Vector3.ZERO
	if Input.is_key_pressed(KEY_W): move_vec.z -= 1.0
	if Input.is_key_pressed(KEY_S): move_vec.z += 1.0
	if Input.is_key_pressed(KEY_A): move_vec.x -= 1.0
	if Input.is_key_pressed(KEY_D): move_vec.x += 1.0
	if Input.is_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_E): move_vec.y += 1.0
	if Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_Q): move_vec.y -= 1.0
		
	var speed_ly: float
	if is_instance_valid(active_system_root):
		speed_ly = fly_speed_presets_mps[speed_index] / SYSTEM_VISUAL_METERS_PER_UNIT
	else:
		speed_ly = fly_speed_presets_mps[speed_index] / LIGHT_YEAR_METERS
	var forward = -spectator_camera.global_transform.basis.z
	var right = spectator_camera.global_transform.basis.x
	var up = Vector3.UP
	
	var dir = (forward * -move_vec.z) + (right * move_vec.x) + (up * move_vec.y)
	if dir.length_squared() > 0.001:
		spectator_camera.position += dir.normalized() * speed_ly * delta

# ─────────────────────────────────────────────────────────────────────────────
# 8. ETKİLEŞİM VE GİRDİ YÖNETİMİ
# ─────────────────────────────────────────────────────────────────────────────
func _handle_interaction_key() -> void:
	if spacecraft != null:
		if spacecraft.current_view_mode == Spacecraft.CameraViewMode.INTERIOR_FPS:
			if spacecraft.near_airlock:
				spacecraft.toggle_airlock()
			elif spacecraft.near_pilot_seat:
				spacecraft.toggle_cockpit_seat()
		elif spacecraft.current_view_mode == Spacecraft.CameraViewMode.THIRD_PERSON:
			spacecraft.current_view_mode = Spacecraft.CameraViewMode.INTERIOR_FPS
			spacecraft.toggle_cockpit_seat()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			mouse_captured = !mouse_captured
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED if mouse_captured else Input.MOUSE_MODE_VISIBLE)
		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_select_object_under_cursor()
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			if is_instance_valid(active_system_root):
				speed_index = mini(speed_index + 1, fly_speed_presets_mps.size() - 1)
				_set_local_travel_speed(fly_speed_presets_mps[speed_index])
			else:
				speed_index = mini(speed_index + 1, fly_speed_presets_mps.size() - 1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if is_instance_valid(active_system_root):
				speed_index = maxi(speed_index - 1, 0)
				_set_local_travel_speed(fly_speed_presets_mps[speed_index])
			else:
				speed_index = maxi(speed_index - 1, 0)
			
	if event is InputEventMouseMotion and mouse_captured and control_mode == ControlMode.SPECTATOR:
		cam_rot_y -= event.relative.x * mouse_sensitivity
		cam_rot_x = clamp(cam_rot_x - event.relative.y * mouse_sensitivity, -1.5, 1.5)
		spectator_camera.rotation = Vector3(cam_rot_x, cam_rot_y, 0.0)
		
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_V and enable_spacecraft_mode:
			_toggle_control_mode()
		elif event.keycode == KEY_G:
			if event.ctrl_pressed:
				_instant_teleport_to_target()
			else:
				_fly_to_targeted_object()
		elif event.keycode == KEY_T:
			if event.ctrl_pressed:
				_instant_teleport_to_target()
			else:
				_select_object_under_cursor()
		elif event.keycode == KEY_Y:
			_cycle_next_extragalactic_galaxy()
		elif event.keycode == KEY_C:
			is_interstellar_autopilot = false
			selected_planet = null
			selected_star = null
			selected_black_hole = false
			selected_extragalactic_galaxy = null
			targeted_star_data = null
			current_target_index = -1
			if target_reticle != null: target_reticle.visible = false
			if target_tag_label != null: target_tag_label.visible = false
			print(">>> Hedef ve Otopilot İptal Edildi (C)")
		elif event.keycode == KEY_TAB:
			is_hud_visible = !is_hud_visible
			if hud != null:
				hud.visible = is_hud_visible
			if target_reticle != null:
				target_reticle.visible = is_hud_visible
			if target_tag_label != null:
				target_tag_label.visible = is_hud_visible
		elif event.keycode == KEY_F3:
			if hud_panel != null:
				hud_panel.visible = !hud_panel.visible
		elif event.keycode == KEY_O:
			show_orbit_lines = !show_orbit_lines
			print("YÖRÜNGE ÇİZGİLERİ (O): ", "AÇIK" if show_orbit_lines else "KAPALI")
		elif event.keycode == KEY_4:
			if cosmic_sector_manager != null and cosmic_sector_manager.host_galaxy != null:
				_switch_active_galaxy(cosmic_sector_manager.host_galaxy)
			_teleport_spectator(_absolute_ly_to_world(Vector3(0.0, 140000.0, 180000.0)), _galactic_center_world_position())
		elif event.keycode == KEY_5:
			_teleport_spectator(Vector3(1200000.0, 2400000.0, 1800000.0) - galaxy_origin_ly, -galaxy_origin_ly)
			print(">>> Kozmolojik Derin Uzay Panoraması (Yerel Grup & Kozmik Ağ - 3.5 Milyon Işık Yılı)")
		elif event.keycode == KEY_6:
			if extragalactic_cluster.size() > 3:
				var andromeda = extragalactic_cluster[3]
				_switch_active_galaxy(andromeda)
				var andromeda_pos = andromeda.position_ly - galaxy_origin_ly
				_teleport_spectator(andromeda_pos + Vector3(80000.0, 120000.0, 90000.0), andromeda_pos)
				print(">>> Andromeda Tipi Dev Komşu Galaksi Görüş Noktası (~2.5 Milyon Işık Yılı)")
		elif event.keycode == KEY_R:
			galaxy_seed = randi()
		elif event.keycode == KEY_ESCAPE:
			mouse_captured = false
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _toggle_control_mode() -> void:
	if control_mode == ControlMode.SPACECRAFT:
		control_mode = ControlMode.SPECTATOR
		if player != null and spectator_camera != null:
			spectator_camera.global_transform = player.camera_node.global_transform
			spectator_camera.current = true
			if player.camera_node != null:
				player.camera_node.current = false
		print("KONTROL MODU DEĞİŞTİRİLDİ: SERBEST GÖZLEMCİ KAMERA")
	else:
		control_mode = ControlMode.SPACECRAFT
		if player != null and spectator_camera != null:
			player.position = spectator_camera.global_position
			player.transform.basis = spectator_camera.transform.basis
			if player.camera_node != null:
				player.camera_node.current = true
			spectator_camera.current = false
			if spacecraft != null:
				spacecraft.scale = Vector3.ONE * SHIP_VISUAL_SCALE
				spacecraft.global_position = player.global_position + player.global_basis * SHIP_LOCAL_OFFSET
				spacecraft.global_basis = player.global_basis
		print("KONTROL MODU DEĞİŞTİRİLDİ: KEŞİF KORVETİ (Spacecraft Pilotluğu)")

func _teleport_spectator(target_pos: Vector3, look_pos: Vector3) -> void:
	if control_mode != ControlMode.SPECTATOR:
		_toggle_control_mode()
	spectator_camera.position = target_pos
	spectator_camera.look_at(look_pos, Vector3.UP)
	var rot = spectator_camera.rotation
	cam_rot_x = rot.x
	cam_rot_y = rot.y

# ─────────────────────────────────────────────────────────────────────────────
# 9. HEDEFLEME VE IŞINLANMA SİSTEMİ (PLANET, BLACK HOLE & STAR RAYCAST)
# ─────────────────────────────────────────────────────────────────────────────
func _select_object_under_cursor() -> void:
	var cam = _get_active_camera()
	if cam == null:
		return
		
	var cam_pos = cam.global_position
	var cam_fwd = -cam.global_transform.basis.z
	var vp = get_viewport()
	var cursor_pos: Vector2
	if mouse_captured or vp == null:
		cursor_pos = vp.get_visible_rect().size * 0.5 if vp != null else Vector2.ZERO
	else:
		cursor_pos = vp.get_mouse_position()
	
	# 1. Aktif gezegen sisteminde gezegenleri kontrol et
	if is_instance_valid(active_system_root):
		var best_planet: CelestialBody = null
		var best_p_dot = cos(0.08) # ~4.5 derece
		for body in active_system_bodies:
			if body.type == "PLANET" and is_instance_valid(body.visual_mesh):
				var p_pos = body.visual_mesh.global_position
				var offset = p_pos - cam_pos
				var dist = offset.length()
				if dist > 0.001:
					var dir = offset / dist
					var dot = cam_fwd.dot(dir)
					if dot > best_p_dot:
						best_p_dot = dot
						best_planet = body
		if best_planet != null:
			selected_planet = best_planet
			selected_star = null
			selected_black_hole = false
			targeted_star_data = null
			current_target_index = universe.find(selected_planet)
			print(">>> Gezegen Seçildi: %s [%s]" % [selected_planet.name, selected_planet.planet_type])
			return
			
	# 2. Merkez Süper Kütleli Kara Delik Kontrolü
	var to_center = _galactic_center_world_position() - cam_pos
	var center_dist = to_center.length()
	if center_dist > 5.0:
		var dir_center = to_center / center_dist
		if cam_fwd.dot(dir_center) > cos(0.06): # ~3.4 derece koni
			selected_planet = null
			selected_star = null
			selected_black_hole = true
			targeted_star_data = black_hole_star_data
			current_target_index = -1
			print(">>> Merkez Süper Kütleli Kara Delik Seçildi!")
			return

	# 3. 100.000 Galaktik Yıldız Arasından Seçim (Ön Plan ve Ekran Hassasiyeti Öncelikli)
	selected_planet = null
	selected_black_hole = false
	var best_star: StarData = null
	var best_dist_in_circle = INF
	var min_px_dist = 36.0 # 36 piksel nişan alanı
	var fallback_star: StarData = null
	var fallback_min_px = 75.0
	
	for star in stars_data:
		var star_pos = _star_world_position(star)
		var offset = star_pos - cam_pos
		var dist = offset.length()
		if dist < 0.01:
			continue
		var dir = offset / dist
		var dot = cam_fwd.dot(dir)
		# Hızlı açısal filtre (~5.7 derece dışındakileri anında ele)
		if dot < 0.995:
			continue
			
		if cam.is_position_behind(star_pos):
			continue
			
		var screen_pos = cam.unproject_position(star_pos)
		var px_dist = screen_pos.distance_to(cursor_pos)
		
		# Nişangah çemberi içindeyse: En yakındaki (ön plandaki) yıldızı seç!
		if px_dist <= min_px_dist:
			if dist < best_dist_in_circle:
				best_dist_in_circle = dist
				best_star = star
		elif best_star == null and px_dist < fallback_min_px:
			fallback_min_px = px_dist
			fallback_star = star
			
	# 4. Derin Uzay / Kozmik Ağ Komşu Galaksi Kontrolü
	var best_galaxy: Galaxy = null
	var best_gal_dist := INF
	for g in extragalactic_cluster:
		if g.is_host_galaxy:
			continue
		var g_world_pos = g.position_ly - galaxy_origin_ly
		var to_g = g_world_pos - cam_pos
		var dist = to_g.length()
		if dist < 50.0:
			continue
		var dir = to_g / dist
		if cam_fwd.dot(dir) < 0.2:
			continue
		var proj_pos = cam_pos + dir * minf(dist, 160000.0)
		if cam.is_position_behind(proj_pos):
			continue
		var screen_pos = cam.unproject_position(proj_pos)
		var screen_dist = (screen_pos - cursor_pos).length()
		if screen_dist < 48.0 and screen_dist < best_gal_dist:
			best_gal_dist = screen_dist
			best_galaxy = g
			
	# 4B. Akışkan Derin Kozmolojik Galaksi Alanı Raycast Kontrolü (20.000 Derin Galaksi)
	if best_galaxy == null and streamed_galaxy_field != null:
		var stream_idx := streamed_galaxy_field.find_closest_galaxy_to_ray(cam_pos + galaxy_origin_ly, cam_fwd, 0.040)
		if stream_idx >= 0:
			best_galaxy = streamed_galaxy_field.create_galaxy_data(stream_idx)
			best_gal_dist = 16.0
			
	# Eğer nişangâha yakın bir galaksi varsa veya yıldız bulunamadıysa galaksiyi seç
	if best_galaxy != null and (best_star == null or best_gal_dist < 24.0):
		selected_extragalactic_galaxy = best_galaxy
		selected_star = null
		selected_planet = null
		selected_black_hole = false
		targeted_star_data = null
		current_target_index = -1
		var g_name = best_galaxy.custom_name if best_galaxy.custom_name != "" else best_galaxy.designation
		var dist_ly = (best_galaxy.position_ly - (cam_pos + galaxy_origin_ly)).length()
		print(">>> Komşu Galaksi Hedeflendi: %s [%s] | Mesafe: %.2f Milyon LY (G: Galaksilerarası Warp Seyri | Ctrl+G: Anında Atlama)" % [
			g_name, best_galaxy.hubble_type, dist_ly / 1.0e6
		])
		if hud != null:
			hud.update_hud(self)
		return

	var final_star = best_star if best_star != null else fallback_star
	if final_star != null:
		selected_star = final_star
		selected_extragalactic_galaxy = null
		targeted_star_data = selected_star
		current_target_index = -1
		var f_pos = _star_world_position(final_star)
		var actual_dist = (f_pos - cam_pos).length()
		print(">>> Yıldız Hedeflendi: %s [%s] | Mesafe: %.1f LY (G: Warp Seyri | Ctrl+G: Anında Atlama)" % [
			final_star.name, final_star.spectral_type, actual_dist
		])
		if hud != null:
			hud.update_hud(self)

var _current_galaxy_cycle_idx: int = 0

func _cycle_next_extragalactic_galaxy() -> void:
	if extragalactic_cluster.size() <= 1:
		return
	_current_galaxy_cycle_idx = (_current_galaxy_cycle_idx % (extragalactic_cluster.size() - 1)) + 1
	var g = extragalactic_cluster[_current_galaxy_cycle_idx]
	selected_extragalactic_galaxy = g
	selected_star = null
	selected_planet = null
	selected_black_hole = false
	targeted_star_data = null
	current_target_index = -1
	
	var cam = _get_active_camera()
	var cam_pos = cam.global_position if cam != null else Vector3.ZERO
	var dist_ly = (g.position_ly - (cam_pos + galaxy_origin_ly)).length()
	var g_name = g.custom_name if g.custom_name != "" else g.designation
	print(">>> Komşu Galaksi Seçildi [%d/%d]: %s [%s] | Mesafe: %.2f Milyon LY (G: Warp | Ctrl+G: Atlama)" % [
		_current_galaxy_cycle_idx, extragalactic_cluster.size() - 1, g_name, g.hubble_type, dist_ly / 1.0e6
	])
	if hud != null:
		hud.update_hud(self)

func _fly_to_targeted_object() -> void:
	var cam = _get_active_camera()
	if cam == null:
		return
		
	# Eğer Kara Delik seçiliyse
	if selected_black_hole:
		var target_pos = _galactic_center_world_position()
		var approach_pos = target_pos + Vector3(0.0, 25.0, 120.0)
		_teleport_player_or_spectator(approach_pos, target_pos)
		print(">>> Kara Deliğe Yaklaşıldı!")
		return
		
	# Eğer seçili bir gezegen varsa gezegene uç
	if selected_planet != null and is_instance_valid(selected_planet.visual_mesh):
		var target_pos = selected_planet.visual_mesh.global_position
		var approach_pos = target_pos + Vector3(0.04, 0.02, 0.05)
		_teleport_player_or_spectator(approach_pos, target_pos)
		_set_local_travel_speed(PLANET_APPROACH_SPEED_MPS)
		print(">>> Gezegene Yaklaşıldı: %s" % selected_planet.name)
		return
		
	# Eğer seçili komşu galaksi varsa galaksilerarası seyahat / warp
	if selected_extragalactic_galaxy != null:
		var target_pos = selected_extragalactic_galaxy.position_ly - galaxy_origin_ly
		var approach_pos = target_pos + Vector3(
			selected_extragalactic_galaxy.radius_ly * 1.35,
			selected_extragalactic_galaxy.radius_ly * 0.75,
			selected_extragalactic_galaxy.radius_ly * 1.45
		)
		if control_mode == ControlMode.SPECTATOR:
			if is_interstellar_autopilot:
				is_interstellar_autopilot = false
				_switch_active_galaxy(selected_extragalactic_galaxy)
				_teleport_spectator(approach_pos, target_pos)
				print(">>> Komşu Galaksiye Anında Atlandı: %s [%s]" % [selected_extragalactic_galaxy.designation, selected_extragalactic_galaxy.hubble_type])
			else:
				is_interstellar_autopilot = true
				var distance_ly: float = (target_pos - cam.global_position).length()
				print(">>> Galaksilerarası Fly Camera Seyri: %s | %.2f Milyon LY | %s [G: Anında Varış]" % [selected_extragalactic_galaxy.designation, distance_ly / 1.0e6, fly_speed_labels[speed_index]])
			return
		if is_interstellar_autopilot:
			is_interstellar_autopilot = false
			_switch_active_galaxy(selected_extragalactic_galaxy)
			_teleport_player_or_spectator(approach_pos, target_pos)
			print(">>> Komşu Galaksiye Anında Atlandı: %s [%s]" % [selected_extragalactic_galaxy.designation, selected_extragalactic_galaxy.hubble_type])
		else:
			is_interstellar_autopilot = true
			var dist_ly = (player.position - target_pos).length()
			print(">>> Galaksilerarası Warp Otopilotu Devrede -> Hedef: %s (%.2f Milyon LY)" % [selected_extragalactic_galaxy.designation, dist_ly / 1.0e6])
		return

	# Eğer seçili yıldız varsa yıldıza seyahat / warp
	if selected_star != null:
		var star_pos = _star_world_position(selected_star)
		var approach_offset = Vector3(0.12, 0.06, 0.16)
		var approach_pos = star_pos + approach_offset
		
		if control_mode == ControlMode.SPECTATOR:
			_enter_selected_star_system()
			return
			
		# SPACECRAFT Modu
		if is_interstellar_autopilot:
			# Zaten otopilottayken G'ye ikinci kez basıldıysa: Anında Atla
			is_interstellar_autopilot = false
			_enter_selected_star_system()
		else:
			var dist_ly = (player.position - star_pos).length()
			if dist_ly < 0.35:
				_enter_selected_star_system()
			else:
				is_interstellar_autopilot = true
				print(">>> Yıldızlararası Warp Otopilotu Devreye Girdi -> Hedef: %s (%.1f LY) [G: Anında Atlama]" % [selected_star.name, dist_ly])

func _instant_teleport_to_target() -> void:
	if selected_black_hole:
		var target_pos = _galactic_center_world_position()
		var approach_pos = target_pos + Vector3(0.0, 25.0, 120.0)
		_teleport_player_or_spectator(approach_pos, target_pos)
		print(">>> Kara Deliğe Anında Atlama Yapıldı!")
	elif selected_planet != null and is_instance_valid(selected_planet.visual_mesh):
		var target_pos = selected_planet.visual_mesh.global_position
		var approach_pos = target_pos + Vector3(0.04, 0.02, 0.05)
		_teleport_player_or_spectator(approach_pos, target_pos)
		_set_local_travel_speed(PLANET_APPROACH_SPEED_MPS)
		print(">>> Gezegene Anında Atlama Yapıldı: %s" % selected_planet.name)
	elif selected_extragalactic_galaxy != null:
		var target_pos = selected_extragalactic_galaxy.position_ly - galaxy_origin_ly
		var approach_pos = target_pos + Vector3(
			selected_extragalactic_galaxy.radius_ly * 1.35,
			selected_extragalactic_galaxy.radius_ly * 0.75,
			selected_extragalactic_galaxy.radius_ly * 1.45
		)
		_switch_active_galaxy(selected_extragalactic_galaxy)
		_teleport_player_or_spectator(approach_pos, target_pos)
		print(">>> Komşu Galaksiye Anında Atlama Yapıldı: %s [%s]" % [selected_extragalactic_galaxy.designation, selected_extragalactic_galaxy.hubble_type])
	elif selected_star != null:
		_enter_selected_star_system()

func _enter_selected_star_system() -> void:
	if selected_star == null:
		return
	var star_pos := _star_world_position(selected_star)
	_spawn_planetary_system(selected_star)
	_teleport_player_or_spectator(star_pos + Vector3(0.12, 0.06, 0.16), star_pos)
	_set_local_travel_speed(STAR_SYSTEM_ARRIVAL_SPEED_MPS)
	print(">>> KESİNTİSİZ YILDIZ SİSTEMİ YÜKLENDİ: %s [%s]" % [selected_star.name, selected_star.unique_id])

func _set_local_travel_speed(speed_mps: float) -> void:
	local_spectator_speed_mps = maxf(speed_mps, 0.0)
	flight_speed_mps = local_spectator_speed_mps
	var closest_speed_index := 0
	var closest_speed_difference := INF
	for index in range(fly_speed_presets_mps.size()):
		var speed_difference: float = absf(fly_speed_presets_mps[index] - local_spectator_speed_mps)
		if speed_difference < closest_speed_difference:
			closest_speed_difference = speed_difference
			closest_speed_index = index
	speed_index = closest_speed_index
	fly_speed_label = fly_speed_labels[speed_index]
	if player == null or player.speed_presets.is_empty():
		return
	var best_index := 0
	var smallest_difference := INF
	for index in range(player.speed_presets.size()):
		var difference: float = absf(float(player.speed_presets[index]) - local_spectator_speed_mps)
		if difference < smallest_difference:
			smallest_difference = difference
			best_index = index
	player.speed_multiplier_index = best_index
	player.target_speed = local_spectator_speed_mps
	player.current_speed = local_spectator_speed_mps

func _teleport_player_or_spectator(approach_pos: Vector3, target_pos: Vector3) -> void:
	if control_mode == ControlMode.SPACECRAFT and player != null:
		player.position = approach_pos
		var diff := target_pos - player.global_position
		if diff.length_squared() > 0.001 and not player.global_position.is_equal_approx(target_pos):
			var up_vec := Vector3.UP if absf(diff.normalized().dot(Vector3.UP)) < 0.99 else Vector3.FORWARD
			player.look_at(target_pos, up_vec)
			var euler = player.transform.basis.get_euler()
			player.rot_x = euler.x
			player.rot_y = euler.y
			player.rot_z = 0.0
			player.transform.basis = Basis.from_euler(Vector3(player.rot_x, player.rot_y, 0.0))
		if spacecraft != null:
			spacecraft.scale = Vector3.ONE * SHIP_VISUAL_SCALE
			spacecraft.global_position = player.global_position + player.global_basis * SHIP_LOCAL_OFFSET
			spacecraft.global_basis = player.global_basis
		player.reset_camera_orientation(player.transform.basis)
		player.mouse_turn_speed = Vector2.ZERO
		player_velocity = Vector3.ZERO
	elif spectator_camera != null:
		spectator_camera.position = approach_pos
		var diff := target_pos - spectator_camera.global_position
		if diff.length_squared() > 0.001 and not spectator_camera.global_position.is_equal_approx(target_pos):
			var up_vec := Vector3.UP if absf(diff.normalized().dot(Vector3.UP)) < 0.99 else Vector3.FORWARD
			spectator_camera.look_at(target_pos, up_vec)
			var rot = spectator_camera.rotation
			cam_rot_x = rot.x
			cam_rot_y = rot.y

# ─────────────────────────────────────────────────────────────────────────────
# 10. KULLANICI ARAYÜZÜ (SYSTEMHUD, 3B HEDEFLEME RETICLE & F3 TELEMETRİ KONSOLU)
# ─────────────────────────────────────────────────────────────────────────────
func _init_black_hole_data() -> void:
	black_hole_star_data = StarData.new()
	black_hole_star_data.unique_id = "SMBH_CENTRAL"
	black_hole_star_data.name = "Süper Kütleli Kara Delik (%s)" % current_astro.designation
	black_hole_star_data.sector_coord = Vector3i(0, 0, 0)
	black_hole_star_data.spectral_type = "Kerr Kara Deliği (SMBH)"
	black_hole_star_data.stellar_x = 0.0
	black_hole_star_data.stellar_y = 0.0
	black_hole_star_data.stellar_z = 0.0
	black_hole_star_data.radius = current_astro.schwarzschild_radius_km * 1000.0
	black_hole_star_data.luminosity = 1.0e8
	black_hole_star_data.base_color = Color(0.05, 0.05, 0.1)
	black_hole_star_data.light_color = Color(0.8, 0.6, 1.0)
	
	fallback_galaxy_star = Star.new()
	fallback_galaxy_star.name = current_astro.designation
	fallback_galaxy_star.spectral_type = current_astro.hubble_type
	fallback_galaxy_star.light_color = Color(0.85, 0.92, 1.0)
	fallback_galaxy_star.real_radius = current_astro.radius_ly * LIGHT_YEAR_METERS
	fallback_galaxy_star.real_position = Vector3.ZERO

func _setup_hud() -> void:
	if ui_control == null:
		ui_control = Control.new()
		ui_control.set_anchors_preset(Control.PRESET_FULL_RECT)
		ui_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(ui_control)
		
	# 1. 3B Holografik Hedefleme Nişangahı (Dönen braket [ ])
	target_reticle = Panel.new()
	target_reticle.name = "TargetReticle"
	var reticle_style = StyleBoxFlat.new()
	reticle_style.bg_color = Color(0, 0, 0, 0)
	reticle_style.border_width_left = 2
	reticle_style.border_width_top = 2
	reticle_style.border_width_right = 2
	reticle_style.border_width_bottom = 2
	reticle_style.border_color = Color(0, 0.85, 1.0, 0.85)
	reticle_style.corner_radius_top_left = 6
	reticle_style.corner_radius_top_right = 6
	reticle_style.corner_radius_bottom_left = 6
	reticle_style.corner_radius_bottom_right = 6
	reticle_style.shadow_color = Color(0.0, 0.85, 1.0, 0.35)
	reticle_style.shadow_size = 4
	target_reticle.add_theme_stylebox_override("panel", reticle_style)
	target_reticle.size = Vector2(36, 36)
	target_reticle.pivot_offset = Vector2(18, 18)
	target_reticle.visible = false
	target_reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_control.add_child(target_reticle)

	# 2. 3B Holografik Hedef Bilgi Etiketi (Holographic Target Tag)
	target_tag_label = Label.new()
	target_tag_label.name = "TargetTagLabel"
	target_tag_label.custom_minimum_size = Vector2(320, 50)
	target_tag_label.add_theme_color_override("font_color", Color(0.2, 0.95, 1.0))
	target_tag_label.add_theme_font_size_override("font_size", 11)
	if ResourceLoader.exists("res://assets/fonts/DejaVuSansMono-Bold.ttf"):
		target_tag_label.add_theme_font_override("font", load("res://assets/fonts/DejaVuSansMono-Bold.ttf"))
	target_tag_label.visible = false
	target_tag_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_control.add_child(target_tag_label)

	# 3. F3 Teknik Telemetri Paneli (İsteğe bağlı döküm konsolu)
	if ui_label != null:
		hud_panel = PanelContainer.new()
		hud_panel.name = "HUDPanel"
		hud_panel.position = Vector2(25, 75)
		hud_panel.custom_minimum_size = Vector2(420, 720)
		var style = StyleBoxFlat.new()
		style.bg_color = Color(0.015, 0.03, 0.06, 0.90)
		style.border_width_left = 1
		style.border_width_top = 1
		style.border_width_right = 1
		style.border_width_bottom = 1
		style.border_color = Color(0.0, 0.8, 1.0, 0.4)
		style.corner_radius_top_left = 6
		style.corner_radius_top_right = 6
		style.corner_radius_bottom_left = 6
		style.corner_radius_bottom_right = 6
		hud_panel.add_theme_stylebox_override("panel", style)
		
		var p = ui_label.get_parent()
		if p != null: p.remove_child(ui_label)
		hud_panel.add_child(ui_label)
		ui_control.add_child(hud_panel)
		hud_panel.visible = false
		ui_label.visible = true
		ui_label.custom_minimum_size = Vector2(400, 700)
		ui_label.autowrap_mode = TextServer.AUTOWRAP_WORD
		ui_label.bbcode_enabled = true

func _update_target_reticle(delta: float) -> void:
	if target_reticle == null or target_tag_label == null:
		return
		
	if not is_hud_visible or (selected_star == null and selected_planet == null and not selected_black_hole and selected_extragalactic_galaxy == null):
		target_reticle.visible = false
		target_tag_label.visible = false
		return
		
	var cam = _get_active_camera()
	if cam == null or not cam.is_inside_tree():
		target_reticle.visible = false
		target_tag_label.visible = false
		return
		
	var target_world_pos = Vector3.ZERO
	var target_name = ""
	var dist_m = 0.0
	
	if selected_black_hole:
		target_world_pos = _galactic_center_world_position()
		target_name = "SÜPER KÜTLELİ KARA DELİK"
		dist_m = (target_world_pos - cam.global_position).length() * LIGHT_YEAR_METERS
	elif selected_planet != null and is_instance_valid(selected_planet.visual_mesh):
		target_world_pos = selected_planet.visual_mesh.global_position
		target_name = selected_planet.name.to_upper()
		dist_m = selected_planet.real_position.length()
	elif selected_extragalactic_galaxy != null:
		target_world_pos = selected_extragalactic_galaxy.position_ly - galaxy_origin_ly
		var gal_title = selected_extragalactic_galaxy.custom_name if selected_extragalactic_galaxy.custom_name != "" else selected_extragalactic_galaxy.designation
		target_name = "GALAKSİ: %s [%s]" % [gal_title.to_upper(), selected_extragalactic_galaxy.hubble_type]
		dist_m = (target_world_pos - cam.global_position).length() * LIGHT_YEAR_METERS
	elif selected_star != null:
		# Sistem yüklüyken galaksi MultiMesh noktasını değil, kamera göreli olarak
		# çizilen gerçek yıldız görselini izle. Aksi halde nişangâh ve yıldız farklı
		# koordinat uzaylarında kalıp özellikle hareket sırasında titrer.
		if active_star_data == selected_star and active_star_body != null and is_instance_valid(active_star_body.visual_mesh):
			target_world_pos = active_star_body.visual_mesh.global_position
			dist_m = active_star_body.real_position.length()
		else:
			var star_pos = _star_world_position(selected_star)
			target_world_pos = star_pos
			dist_m = (star_pos - cam.global_position).length() * LIGHT_YEAR_METERS
		target_name = selected_star.name.to_upper()
	else:
		target_reticle.visible = false
		target_tag_label.visible = false
	var check_world_pos = target_world_pos
	if selected_extragalactic_galaxy != null:
		var to_g = target_world_pos - cam.global_position
		var d = to_g.length()
		check_world_pos = cam.global_position + (to_g / maxf(d, 0.001)) * minf(d, 160000.0)

	var pos_in_cam = cam.to_local(check_world_pos)
	if pos_in_cam.z < 0:
		var screen_pos = cam.unproject_position(check_world_pos)
		target_reticle.visible = true
		target_reticle.position = screen_pos - target_reticle.size * 0.5
		target_reticle.rotation += 1.0 * delta
		
		target_tag_label.visible = true
		target_tag_label.position = screen_pos + Vector2(24, -18)
		var spd = flight_speed_mps
		target_tag_label.text = "%s\n%s\nKAT ETME: %s" % [
			target_name,
			SystemHUD._format_distance(dist_m),
			SystemHUD.format_travel_time(dist_m, spd)
		]
	else:
		target_reticle.visible = false
		target_tag_label.visible = false

func _update_debug_ui() -> void:
	if ui_label == null:
		return
	var cam = _get_active_camera()
	var cam_pos = cam.global_position if cam != null else Vector3.ZERO
	var dist_ly = (cam_pos + galaxy_origin_ly).length()
	var fps = Performance.get_monitor(Performance.TIME_FPS)
	
	var mode_name = "KEŞİF KORVETİ (Spacecraft)" if control_mode == ControlMode.SPACECRAFT else "SERBEST GÖZLEMCİ KAMERA"
	var view_submode = ""
	if control_mode == ControlMode.SPACECRAFT and spacecraft != null:
		match spacecraft.current_view_mode:
			Spacecraft.CameraViewMode.THIRD_PERSON: view_submode = "3. Şahıs Dış Gemi Takibi"
			Spacecraft.CameraViewMode.INTERIOR_FPS:
				view_submode = "Kokpit İçi Pilotaj" if spacecraft.is_seated_in_cockpit else "Kabin İçi Yürüyüş"
			Spacecraft.CameraViewMode.FREE_CAM: view_submode = "Serbest Bakış"
			
	var text = "[color=#00e5ff]=== STELLAR ENGINE: GALAKSİ & FİZİK DÖKÜM KONSOLU [F3] ===[/color]\n"
	text += "FPS: %d | Galaksi: %s (%s) | Tohum: %d\n" % [fps, current_astro.designation, current_astro.hubble_type, galaxy_seed]
	text += "Galaksi Çapı: %.0f LY (%.0f pc) | Yaş: %.1f Gyr | Kol: %d\n" % [
		current_astro.diameter_ly, current_astro.diameter_ly / PARSEC_LY, current_astro.age_gyr, current_astro.num_arms
	]
	text += "Toplam Galaktik Kütle: ~%.2f × 10¹¹ M☉ (%s kg)\n" % [
		current_astro.total_mass_solar / 1.0e11, format_sci(current_astro.total_mass_solar * SOLAR_MASS_KG)
	]
	text += "Karanlık Madde Halosu: %%85 | Yıldız Kütlesi: %%15\n"
	text += "Gerçek Yıldız Sayısı: ~%.1f Milyar | Aktif Örneklem: 100.000 StarData\n" % [
		current_astro.total_real_stars / 1.0e9
	]
	text += "Kozmik Ağ: %d Komşu Galaksi Serpiştirildi (Yerel Grup & Filamentler)\n" % (extragalactic_cluster.size() - 1)
	text += "Kontrol Modu: %s %s\n" % [mode_name, ("- " + view_submode) if view_submode != "" else ""]
	text += "─".repeat(50) + "\n"
	
	if selected_extragalactic_galaxy != null:
		var g_dist_ly = (selected_extragalactic_galaxy.position_ly - (cam_pos + galaxy_origin_ly)).length()
		text += "[color=#33ffaa]Kilitlenilen Galaksi: %s [%s]\nMesafe: %.2f Milyon LY | Kütle: ~%.1f × 10¹¹ M☉ | Çap: %.0f LY[/color]\n" % [
			selected_extragalactic_galaxy.designation, selected_extragalactic_galaxy.hubble_type, g_dist_ly / 1.0e6,
			selected_extragalactic_galaxy.total_mass_solar / 1.0e11, selected_extragalactic_galaxy.diameter_ly
		]
	elif active_star_data != null:
		var sys_planets = 0
		for b in active_system_bodies:
			if b.type == "PLANET": sys_planets += 1
		text += "Aktif Sistem: %s [%s] (%d Gezegen, %d Uydu)\n" % [
			active_star_data.name, active_star_data.spectral_type, sys_planets, active_system_bodies.size() - sys_planets
		]
	else:
		text += "Aktif Yıldız Sistemi: Yok\n"
		
	text += "Merkez SMBH: %.2f × 10⁶ M☉ | Kara Deliğe Mesafe: %.1f LY\n\n" % [
		current_astro.black_hole_mass_solar / 1.0e6, dist_ly
	]
	text += "[color=#ffe066]Kısayollar:[/color]\n"
	text += " [Sol Tık / T]: Hedef Kilitle | [G]: Warp İle Git\n"
	text += " [1-4]: Galaktik Panorama | [5-6]: Derin Uzay & Komşu Galaksiler\n"
	text += " [WASD / SPACE / CTRL]: Fly Camera | [Mouse Tekerleği]: Hız\n"
	text += " [TAB]: SystemHUD Aç/Kapat | [F3]: Bu Konsolu Gizle\n"
	text += " [O]: Yörünge Çizgileri | [C]: Hedef İptal"
	ui_label.text = text

# ─────────────────────────────────────────────────────────────────────────────
# 11. ASTROFİZİKSEL HESAPLAMA MOTORU (FİZİKSEL SABİTLER & FORMÜLLER)
# ─────────────────────────────────────────────────────────────────────────────
const G_CONST: float = 6.67430e-11 # m^3 kg^-1 s^-2
const SOLAR_MASS_KG: float = 1.98847e30
const EARTH_MASS_KG: float = 5.9722e24
const EARTH_RADIUS_METERS: float = 6371000.0
const SOLAR_TEMP_K: float = 5778.0

static func format_sci(val: float) -> String:
	if absf(val) < 1e-35:
		return "0.0"
	var exp_val = int(floor(log(absf(val)) / 2.302585092994046))
	var mantissa = val / pow(10.0, exp_val)
	return "%.2f × 10^%d" % [mantissa, exp_val]

func _get_star_physics(star: StarData) -> Dictionary:
	var lum = maxf(star.luminosity, 0.0001)
	var r_m = star.radius
	var r_solar = r_m / SOLAR_RADIUS_METERS
	
	var mass_solar: float = 1.0
	if "Süperdev" in star.spectral_type or "O-tipi" in star.spectral_type:
		mass_solar = clampf(pow(lum, 0.22) * 1.8, 20.0, 65.0)
	elif "Mavi Dev" in star.spectral_type:
		mass_solar = clampf(pow(lum, 0.26) * 1.4, 4.0, 18.0)
	elif "Kırmızı Dev" in star.spectral_type:
		mass_solar = 2.4
	elif "Kırmızı Cüce" in star.spectral_type:
		mass_solar = clampf(pow(lum, 0.42), 0.08, 0.55)
	else:
		mass_solar = clampf(pow(lum, 1.0 / 3.5), 0.6, 2.5)
		
	var mass_kg = mass_solar * SOLAR_MASS_KG
	var vol_m3 = (4.0 / 3.0) * PI * pow(r_m, 3.0)
	var density_g_cm3 = (mass_kg / vol_m3) * 0.001
	var gravity_mps2 = (G_CONST * mass_kg) / pow(r_m, 2.0)
	var gravity_earth = gravity_mps2 / 9.80665
	
	# Stefan-Boltzmann & Spektral Sınıf Etkin Sıcaklığı (T_eff)
	var temp_k = SOLAR_TEMP_K
	if "Süperdev" in star.spectral_type or "O-tipi" in star.spectral_type:
		temp_k = clampf(lerpf(32000.0, 46000.0, (lum - 6.0) / 4.0), 30000.0, 50000.0)
	elif "Mavi Dev" in star.spectral_type:
		temp_k = clampf(lerpf(12000.0, 26000.0, (lum - 3.5) / 2.5), 11000.0, 28000.0)
	elif "Beyaz" in star.spectral_type:
		temp_k = clampf(lerpf(7200.0, 9600.0, (lum - 1.6) / 1.0), 7000.0, 10000.0)
	elif "Sarı Cüce" in star.spectral_type:
		temp_k = clampf(lerpf(5200.0, 6000.0, (lum - 0.9) / 0.35), 5000.0, 6200.0)
	elif "Turuncu Cüce" in star.spectral_type:
		temp_k = clampf(lerpf(3900.0, 5200.0, (lum - 0.45) / 0.30), 3700.0, 5300.0)
	elif "Kırmızı Cüce" in star.spectral_type:
		temp_k = clampf(lerpf(2500.0, 3700.0, (lum - 0.15) / 0.20), 2400.0, 3800.0)
	elif "Kırmızı Dev" in star.spectral_type:
		temp_k = clampf(lerpf(3100.0, 3800.0, (lum - 2.2) / 2.0), 3000.0, 4000.0)
	
	var hz_inner_au = 0.95 * sqrt(lum)
	var hz_outer_au = 1.37 * sqrt(lum)
	
	return {
		"mass_solar": mass_solar,
		"mass_kg": mass_kg,
		"radius_km": r_m / 1000.0,
		"radius_solar": r_solar,
		"density_g_cm3": density_g_cm3,
		"gravity_mps2": gravity_mps2,
		"gravity_earth": gravity_earth,
		"temp_k": temp_k,
		"temp_c": temp_k - 273.15,
		"hz_inner_au": hz_inner_au,
		"hz_outer_au": hz_outer_au
	}

func _get_planet_physics(planet: CelestialBody, star: StarData) -> Dictionary:
	var r_m = planet.real_radius
	var r_km = r_m / 1000.0
	var r_earth = r_m / EARTH_RADIUS_METERS
	
	var density_g_cm3 = 5.5
	var atmo_comp = "N2, O2, Ar, CO2"
	var atmo_bar = 1.0
	var albedo = 0.30
	
	match planet.planet_type:
		"HOT_DESERT":
			density_g_cm3 = 4.9
			atmo_comp = "CO2 (%93), N2 (%5), SO2 (%2)"
			atmo_bar = 2.4
			albedo = 0.38
		"TERRESTRIAL_METALLIC":
			density_g_cm3 = 7.4
			atmo_comp = "Egzosfer (Eser Na, He, O2)"
			atmo_bar = 0.00001
			albedo = 0.12
		"OCEAN_WORLD":
			density_g_cm3 = 3.2
			atmo_comp = "H2O Buharı (%62), N2 (%30), CO2 (%7)"
			atmo_bar = 4.2
			albedo = 0.28
		"ICE_PLANET":
			density_g_cm3 = 2.2
			atmo_comp = "CH4 (%48), N2 (%38), CO (%12)"
			atmo_bar = 0.6
			albedo = 0.65
		"GAS_GIANT":
			density_g_cm3 = 1.15
			atmo_comp = "H2 (%77), He (%20), CH4 (%2), NH3 (%1)"
			atmo_bar = 280.0
			albedo = 0.52
		"BARREN_ROCK":
			density_g_cm3 = 3.9
			atmo_comp = "Vakum (Atmosfersiz)"
			atmo_bar = 0.0
			albedo = 0.08
		_:
			density_g_cm3 = 4.6
			atmo_comp = "N2 (%75), O2 (%22), Ar (%2)"
			atmo_bar = 1.0
			
	var vol_m3 = (4.0 / 3.0) * PI * pow(r_m, 3.0)
	var mass_kg = density_g_cm3 * 1000.0 * vol_m3
	var mass_earth = mass_kg / EARTH_MASS_KG
	var gravity_mps2 = (G_CONST * mass_kg) / pow(r_m, 2.0)
	var gravity_earth = gravity_mps2 / 9.80665
	
	var s_phys = _get_star_physics(star) if star != null else {"mass_kg": SOLAR_MASS_KG, "temp_k": SOLAR_TEMP_K}
	var a_m = maxf(planet.orbit_radius, 1.0)
	var a_au = a_m / ONE_AU
	var period_sec = TAU * sqrt(pow(a_m, 3.0) / (G_CONST * s_phys["mass_kg"]))
	var period_days = period_sec / 86400.0
	var period_years = period_days / 365.25
	var orb_speed_km_s = sqrt((G_CONST * s_phys["mass_kg"]) / a_m) / 1000.0
	
	var r_star_m = star.radius if star != null else SOLAR_RADIUS_METERS
	var t_eq = s_phys["temp_k"] * sqrt(r_star_m / (2.0 * a_m)) * pow(1.0 - albedo, 0.25)
	
	return {
		"mass_kg": mass_kg,
		"mass_earth": mass_earth,
		"radius_km": r_km,
		"radius_earth": r_earth,
		"density_g_cm3": density_g_cm3,
		"gravity_mps2": gravity_mps2,
		"gravity_earth": gravity_earth,
		"orbit_au": a_au,
		"orbit_km": a_m / 1000.0,
		"period_days": period_days,
		"period_years": period_years,
		"speed_km_s": orb_speed_km_s,
		"temp_k": t_eq,
		"temp_c": t_eq - 273.15,
		"atmo_comp": atmo_comp,
		"atmo_bar": atmo_bar
	}
