extends Node3D

const FlyCameraSpeedProfile = preload("res://scripts/navigation/fly_camera_speed_profile.gd")
const CelestialTargeting = preload("res://scripts/navigation/celestial_targeting.gd")
const GalaxyLodControllerScript = preload("res://scripts/navigation/galaxy_lod_controller.gd")
const TargetSelection = preload("res://scripts/navigation/target_selection_controller.gd")

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
# 4. Serbest gözlemci kamerası: 220.000 LY'ye kadar galaktik panorama.
# ─────────────────────────────────────────────────────────────────────────────

const LIGHT_YEAR_METERS: float = 9460730472580800.0
const PARSEC_LY: float = 3.26156
const SOLAR_RADIUS_METERS: float = 696340000.0 # Güneş Yarıçapı (~696.340 km)
const ONE_AU: float = 149597870700.0 # 1 Astronomik Birim (metre)
const AU_VISUAL_SCALE: float = 0.08 # 1 AU = 0.08 LY görsel temsil ölçeği
const SYSTEM_VISUAL_METERS_PER_UNIT: float = ONE_AU / AU_VISUAL_SCALE
const MIN_MOON_ORBIT_VISUAL_FACTOR: float = 1.8
# Galaksi koordinatları LY cinsinden, yerel sistem görselleri ise çok
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

@export_range(0.0001, 0.004, 0.00005) var distance_lod_scale: float = 0.0022:
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
var is_landed: bool = false
var landed_body: CelestialBody = null
var is_interstellar_autopilot: bool = false
var is_interstellar_hyper_boost: bool = false
var is_autopilot_active: bool = false
var is_hyper_autopilot: bool = false
var is_landing_autopilot: bool = false
var autopilot_target_body: CelestialBody = null
var player_velocity: Vector3 = Vector3.ZERO
var flight_speed_mps: float = 0.0
const STAR_SYSTEM_ARRIVAL_SPEED_MPS: float = 50.0
const PLANET_APPROACH_SPEED_MPS: float = 5.0
var local_spectator_speed_mps: float = STAR_SYSTEM_ARRIVAL_SPEED_MPS
var walk_speed_index: int = 2
const WALK_SPEED_PRESETS: Array = [3.0, 8.0, 15.0, 30.0, 60.0, 120.0, 250.0, 500.0, 1000.0]

# Hedefleme & StarData
var targeted_star_data: StarData = null
var current_target_index: int = -1
var black_hole_star_data: StarData = null
var fallback_galaxy_star: CelestialBody = null

var camera: Node3D:
	get:
		return spectator_camera

var camera_3d: Camera3D:
	get:
		return _get_active_camera()

var active_star: CelestialBody:
	get:
		if active_star_body != null:
			return active_star_body
		return fallback_galaxy_star

func get_player_galactic_position() -> Vector3:
	_update_observer_galactic_position()
	return observer_galactic_position.to_meters_approx()

func get_player_galactic_position_precise() -> GalacticPosition:
	_update_observer_galactic_position()
	return observer_galactic_position.duplicate_pos()

func _star_world_position(star: StarData) -> Vector3:
	if star == null:
		return Vector3.ZERO
	return star.get_galactic_position().get_relative_meters(render_origin_position) / LIGHT_YEAR_METERS

var active_galaxy_center_ly: Vector3 = Vector3.ZERO
var active_galaxy_radius_ly: float = 65000.0

func _galactic_center_world_position() -> Vector3:
	return _absolute_ly_to_world(active_galaxy_center_ly)

func _absolute_ly_to_world(absolute_ly: Vector3) -> Vector3:
	var absolute_position: GalacticPosition = GalacticPosition.from_light_years(absolute_ly)
	return _galactic_position_to_world(absolute_position)

func _galactic_position_to_world(absolute_position: GalacticPosition) -> Vector3:
	if absolute_position == null:
		return Vector3.ZERO
	return absolute_position.get_relative_meters(render_origin_position) / LIGHT_YEAR_METERS

func _galaxy_world_position(galaxy: Galaxy) -> Vector3:
	if galaxy == null:
		return Vector3.ZERO
	if galaxy.galactic_position == null:
		galaxy.galactic_position = GalacticPosition.from_light_years(galaxy.position_ly)
	return galaxy.galactic_position.get_relative_meters(render_origin_position) / LIGHT_YEAR_METERS

func _observer_distance_to_galaxy_ly(galaxy: Galaxy) -> float:
	if galaxy == null:
		return INF
	_update_observer_galactic_position()
	if galaxy.galactic_position == null:
		galaxy.galactic_position = GalacticPosition.from_light_years(galaxy.position_ly)
	return observer_galactic_position.distance_to_ly(galaxy.galactic_position)

func _update_observer_galactic_position() -> void:
	var cam := _get_active_camera()
	if cam == null or not cam.is_inside_tree():
		return
	if is_instance_valid(active_system_root) and active_star_data != null:
		# Sistem içindeki dünya birimi LY değildir. Yıldızın kesin adresine,
		# kamera-yıldız yerel farkını sistem ölçeğinde metre olarak ekle.
		observer_galactic_position = active_star_data.get_galactic_position().duplicate_pos()
		var local_system_offset := cam.global_position - active_system_root.global_position
		observer_galactic_position.add_meters(local_system_offset * SYSTEM_VISUAL_METERS_PER_UNIT)
	else:
		observer_galactic_position = render_origin_position.duplicate_pos()
		observer_galactic_position.add_meters(cam.global_position * LIGHT_YEAR_METERS)

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
var galaxy_lod_registry: GalaxyLodRegistry = GalaxyLodRegistry.new()
var galaxy_lod_controller = GalaxyLodControllerScript.new()
var extragalactic_render_ids: Array[String] = []
var discovery_catalog: DiscoveryCatalog = DiscoveryCatalog.new()

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
# Render uzayı kayan orijin çevresinde küçük Vector3 değerleri kullanır. Bu iki
# adres ise fiziksel konumu sektör + yerel metre olarak hassas biçimde korur.
var render_origin_position: GalacticPosition = GalacticPosition.new()
var observer_galactic_position: GalacticPosition = GalacticPosition.new()
var system_stream_grace_seconds: float = 0.0
var galaxy_proximity_scan_timer: float = 0.0
var galaxy_star_build_generation: int = 0
var galaxy_star_build_progress: float = 0.0
var galaxy_star_field_ready: bool = false
var galaxy_star_field_blend: float = 0.0
var galaxy_star_build_active: bool = false
const GALAXY_STAR_BUILD_BUDGET_USEC: int = 2000

# Fly camera fiziksel hız merdiveni. Bütün değerler m/s tutulur; galaksi ve
# yerel sistem hareketi kendi dünya ölçeğine çevrilir.
var fly_speed_presets_mps: Array[float] = FlyCameraSpeedProfile.presets_mps()
var fly_speed_labels: Array[String] = FlyCameraSpeedProfile.labels()
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
	if not discovery_catalog.load_catalog():
		push_warning("Keşif kataloğu yüklenemedi: " + discovery_catalog.last_error)
	_derive_and_rebuild()
	_setup_spectator_camera()
	_update_observer_galactic_position()
	_setup_hud()
	
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
	print(">>> [StellarEngine] %s (%s) %d yıldız + %d sabit / 20000 akış galaksisi hazır! Süre: %d ms" % [
		current_astro.designation, current_astro.hubble_type, total_stars, maxi(extragalactic_cluster.size() - 1, 0), elapsed
	])

func _setup_spectator_camera() -> void:
	spectator_camera = Camera3D.new()
	spectator_camera.name = "SpectatorCamera"
	# Aşırı near/far oranı Vulkan frustum matrisini tek duyarlıklı tarafta
	# tekil hale getirip rendering_light_culler içinde create_frustum_points
	# hatasına yol açabiliyor. Sistem nesneleri zaten kamera çevresine ölçeklenerek
	# çizildiği için 5 cm yakın düzlem yeterli ve çok daha kararlı.
	spectator_camera.near = 0.05
	spectator_camera.far = 250000.0
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

func _calculate_astrophysics() -> void:
	current_astro = Galaxy.generate(galaxy_seed)
	galaxy_lod_registry.set_active(current_astro)
	galaxy_lod_controller.set_active(current_astro)

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
	galaxy_lod_registry.set_active(target_galaxy)
	galaxy_lod_controller.set_active(target_galaxy)
	if streamed_galaxy_field != null:
		# Seçim sırasında gizlenmiş eski durumları temizle. Uzak temsil ancak gerçek
		# yıldız alanı hazır olduğunda merkez tabanlı LOD ile kapanır.
		streamed_galaxy_field.set_galaxy_impostor_visible(target_galaxy.seed, true)
	galaxy_seed = target_galaxy.system_seed if target_galaxy.system_seed != 0 else (target_galaxy.seed if target_galaxy.seed != 0 else 2026)
	_is_switching_galaxy = false
	
	_create_black_hole()
	_generate_galaxy()
	# Galaksi geçişinden sonra yeni katalog aynı karede görünür olmalı. Önceki
	# galaksinin visibility durumu yeni MultiMesh'e taşınamaz.
	if is_instance_valid(multimesh_instance):
		multimesh_instance.position = _galaxy_world_position(target_galaxy)
		multimesh_instance.visible = false
	extragalactic_cluster = galaxy_lod_registry.compose_pinned(CosmicSectorManager.MAX_ACTIVE_GALAXIES)
	
	var g_name = target_galaxy.custom_name if target_galaxy.custom_name != "" else target_galaxy.designation
	print(">>> AKTİF GALAKSİ DEĞİŞTİRİLDİ: %s [%s] | 100.000 Yıldız ve Çekirdek Oluşturuldu!" % [g_name, target_galaxy.hubble_type])

func _complete_galaxy_arrival(target_galaxy: Galaxy) -> void:
	if target_galaxy == null:
		return
	_switch_active_galaxy(target_galaxy)
	# Aynı galaksi daha önce otomatik etkinleşmiş olsa bile varış anında yıldız
	# katmanının gerçekten mevcut ve görünür olduğunu garanti et.
	if not is_instance_valid(multimesh_instance) or multimesh_instance.multimesh == null \
			or multimesh_instance.multimesh.instance_count != total_stars:
		_generate_galaxy()
	if is_instance_valid(multimesh_instance):
		multimesh_instance.position = _galaxy_world_position(target_galaxy)
		multimesh_instance.visible = galaxy_lod_controller.star_field_visible
	selected_extragalactic_galaxy = null
	selected_star = null
	selected_planet = null
	selected_black_hole = false
	targeted_star_data = null
	current_target_index = -1
	is_interstellar_autopilot = false
	if target_reticle != null:
		target_reticle.visible = false
	if target_tag_label != null:
		target_tag_label.visible = false

# ─────────────────────────────────────────────────────────────────────────────
# 5. 100.000 GERÇEK STARDATA NESNESİNİN OLUŞTURULMASI (SECTOR_MANAGER MODELİ)
# ─────────────────────────────────────────────────────────────────────────────
func _generate_galaxy() -> void:
	galaxy_star_build_generation += 1
	var build_generation := galaxy_star_build_generation
	galaxy_star_build_progress = 0.0
	galaxy_star_field_ready = false
	galaxy_star_field_blend = 0.0
	galaxy_star_build_active = true
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
	# Henüz üretilmemiş örneklerin varsayılan Transform3D ile galaksi merkezinde
	# üst üste çizilmesini engelle. Her dilim sonunda yalnız hazır bölüm açılır.
	mm.visible_instance_count = 0
	
	var star_shader = load("res://shaders/spiral_star_billboard.gdshader")
	var star_mat = ShaderMaterial.new()
	star_mat.shader = star_shader
	star_mat.set_shader_parameter("u_base_scale", star_base_scale)
	star_mat.set_shader_parameter("u_glow_boost", star_glow_boost)
	star_mat.set_shader_parameter("u_distance_lod_scale", distance_lod_scale)
	
	multimesh_instance = MultiMeshInstance3D.new()
	multimesh_instance.position = _absolute_ly_to_world(active_galaxy_center_ly)
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
	var slice_started_usec := Time.get_ticks_usec()
	
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
		star.galaxy_id = current_astro.unique_id
		star.parent_id = current_astro.unique_id
		star.unique_id = CelestialAddress.star_id(star.galaxy_id, sector_coord, sector_star_index)
		star.name = "S_%d_%d_%d_%d" % [sec_x, sec_y, sec_z, sector_star_index]
		star.system_seed = int(rng.randi()) & 0x7FFFFFFF
		star.extra_flags["catalog"] = "spiral_galaxy_test"
		star.extra_flags["catalog_index"] = star_idx
		var abs_star_pos = active_galaxy_center_ly + pos
		star.set_galactic_position(GalacticPosition.from_light_years(abs_star_pos))
		
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
		if Time.get_ticks_usec() - slice_started_usec >= GALAXY_STAR_BUILD_BUDGET_USEC:
			mm.visible_instance_count = star_idx
			galaxy_star_build_progress = float(star_idx) / float(total_stars)
			await get_tree().process_frame
			if build_generation != galaxy_star_build_generation:
				return
			slice_started_usec = Time.get_ticks_usec()

	if build_generation == galaxy_star_build_generation:
		mm.visible_instance_count = total_stars
		galaxy_star_build_progress = 1.0
		galaxy_star_field_ready = true
		galaxy_star_build_active = false
		print(">>> GALAKSİ YILDIZ ALANI HAZIR: %s | %d yıldız" % [current_astro.designation, total_stars])

# ─────────────────────────────────────────────────────────────────────────────
# 5B. KOZMİK AĞ VE DERİN UZAY KOMŞU GALAKSİLERİ (EXTRAGALACTIC CLUSTER)
# ─────────────────────────────────────────────────────────────────────────────
func _generate_extragalactic_cluster() -> void:
	if is_instance_valid(extragalactic_multimesh):
		extragalactic_multimesh.queue_free()
		extragalactic_multimesh = null
		
	# main_star ile aynı yaşam döngüsü: çevredeki uzak nesnelerin tek kaynağı
	# StreamedGalaxyField'dır. Bu MultiMesh yalnız seçilen/ziyaret edilen/etkin
	# galaksileri sabit tutar. Önceki CosmicSectorManager listesi aynı uzayda
	# ikinci ve bağımsız galaksi evreni üreterek seçim ve LOD'u bozuyordu.
	extragalactic_cluster = galaxy_lod_registry.compose_pinned(CosmicSectorManager.MAX_ACTIVE_GALAXIES)
	
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
	_update_observer_galactic_position()
	var observer_absolute_ly := observer_galactic_position.to_light_years()
	# Önce mantıksal LOD durumunu güncelle; aynı karede hem uzak grid hem de
	# sabit impostor havuzu yeni durumu kullansın.
	var active_position: GalacticPosition = current_astro.galactic_position
	if active_position == null:
		active_position = GalacticPosition.from_light_years(active_galaxy_center_ly)
	var dist_to_active := observer_galactic_position.distance_to_ly(active_position)
	var active_threshold := maxf(active_galaxy_radius_ly * 5.5, 400000.0)
	galaxy_lod_controller.update(dist_to_active, active_galaxy_radius_ly, galaxy_star_field_ready)
	
	if streamed_galaxy_field != null:
		var exclusion_radius := active_galaxy_radius_ly * 0.25 if galaxy_lod_controller.star_field_visible else 0.0
		streamed_galaxy_field.set_active_galaxy_exclusion(active_galaxy_center_ly, exclusion_radius)
		streamed_galaxy_field.update_renderer(cam, observer_absolute_ly)
	
	# Uzak galaksiler StreamedGalaxyField tarafından main_star'daki yıldız alanı
	# gibi yönetilir. Burada yalnız sabitlenen gerçek galaksiler çizilir.
		
	var mm := extragalactic_multimesh.multimesh
	var render_cluster: Array[Galaxy] = []
	extragalactic_render_ids.clear()
	for galaxy in extragalactic_cluster:
		if galaxy == null:
			continue
		if galaxy.unique_id == current_astro.unique_id and galaxy_lod_controller.star_field_visible:
			continue
		render_cluster.append(galaxy)
		extragalactic_render_ids.append(galaxy.unique_id)
	var active_count := mini(render_cluster.size(), mm.instance_count)
	mm.visible_instance_count = active_count
	# SpectatorCamera far=250.000. Galaksileri bunun dışında bir kabuğa koymak
	# mesafeye bağlı ani/yarım kaybolmaya neden olur.
	const LOD_SPHERE_RADIUS_LY: float = 180000.0
	
	# SpaceEngine Modeli: Aktif odak galaksinin 100.000 tekil yıldızı ile uzak impostor'ı arasında geçiş
	if galaxy_lod_controller.is_far() and galaxy_star_build_active:
		# Detay alanından çıkıldı; yarım kalan üretimi iptal et. Tekrar yaklaşılırsa
		# temiz katalog aynı kare bütçesiyle yeniden başlar.
		galaxy_star_build_generation += 1
		galaxy_star_build_active = false
	elif galaxy_lod_controller.wants_star_data and not galaxy_star_field_ready and not galaxy_star_build_active:
		_generate_galaxy()
	if is_instance_valid(multimesh_instance):
		# 100.000 yıldızın tamamını bekletme. Yükleme sırasında hazır dilimler uzak
		# galaksiyle birlikte görünür; hazır olduğunda denetleyici impostor'u kapatır.
		var has_built_stars := multimesh_instance.multimesh != null and multimesh_instance.multimesh.visible_instance_count > 0
		multimesh_instance.visible = galaxy_lod_controller.star_field_visible or (galaxy_lod_controller.wants_star_data and has_built_stars)
	if is_instance_valid(black_hole_root):
		black_hole_root.visible = (dist_to_active < active_threshold * 0.75)
		
	for i in range(mm.instance_count):
		if i < active_count:
			var galaxy := render_cluster[i]
			if galaxy.galactic_position == null:
				galaxy.galactic_position = GalacticPosition.from_light_years(galaxy.position_ly)
			var relative_ly := galaxy.galactic_position.get_relative_meters(observer_galactic_position) / LIGHT_YEAR_METERS
			var real_distance_ly := relative_ly.length()
			# 4R'de gerçek yıldız kataloğu etkinleşir; bundan sonra galaksi resmi
			# yavaşça söner ve 1.4R içinde yalnız fiziksel yıldızlar kalır.
			# Galaksi resmi yıldız kataloğu açıldıktan sonra iç hacimde söner.
			# Dış kenarda erken sönmesi yaklaşım sırasında boşluk oluşturuyordu.
			# 4R'de yıldız üretimi başlar. 4R–2.2R arasında 2D impostor gerçek
			# yıldızlarla karışır; standart varış mesafesinde tamamen kapanır.
			var near_fade_start := galaxy.radius_ly * 2.2
			var near_fade_end := galaxy.radius_ly * 4.0
			var near_opacity := smoothstep(near_fade_start, near_fade_end, real_distance_ly)
			# Grid uzaklığı galaksiyi gizlemez. Yalnız aynı galaksinin gerçek yıldız
			# alanına geçerken yakın LOD sönümlemesi uygulanır.
			var impostor_opacity := near_opacity
			var is_current_focal := galaxy.unique_id == current_astro.unique_id
			if is_current_focal:
				impostor_opacity = galaxy_lod_controller.impostor_opacity
			
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
			var galaxy_tint := galaxy.color_tint
			galaxy_tint.a = impostor_opacity
			mm.set_instance_color(i, galaxy_tint)
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
	_record_discovery(star_data.unique_id, "STAR", star_data.parent_id, star_data.name)
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
		immediate.surface_begin(Mesh.PRIMITIVE_LINES)
		var line_color := Color(0.15, 0.75, 1.0, 0.35) if body.type != "MOON" else Color(0.75, 0.85, 1.0, 0.18)
		var parent_relative_m := body.parent_body.real_position if body.parent_body != null else Vector3.ZERO
		for index in range(body.orbit_sample_points.size() - 1):
			if index % 3 == 2:
				continue
			for orbit_point_m in [body.orbit_sample_points[index], body.orbit_sample_points[index + 1]]:
				var relative_m: Vector3 = parent_relative_m + orbit_point_m
				var projected_m := CelestialRenderScale.project_position(relative_m, SYSTEM_RENDER_LIMIT_METERS)
				immediate.surface_set_color(line_color)
				immediate.surface_add_vertex(projected_m * SYSTEM_RENDER_TO_GALAXY)
		immediate.surface_end()
		body.orbit_line_mesh.global_position = cam.global_position

# ─────────────────────────────────────────────────────────────────────────────
# 7. SERBEST KAMERA DİNAMİKLERİ
# ─────────────────────────────────────────────────────────────────────────────
func _get_active_camera() -> Camera3D:
	return spectator_camera

func _process(delta: float) -> void:
	# 1. Önce uçuş ve kamera hareketini işlet (1-frame gecikmesini ve titremeyi sıfırla)
	_process_spectator_flight(delta)
	flight_speed_mps = fly_speed_presets_mps[speed_index]
	local_spectator_speed_mps = flight_speed_mps
	fly_speed_label = fly_speed_labels[speed_index]
	if spectator_camera != null:
		spectator_camera.set("current_speed", flight_speed_mps)
	_update_observer_galactic_position()
			
	# 2. Güncel kamera konumuna göre kayan orijin ve galaksi LOD'unu senkronize güncelle
	_update_floating_origin()
	_update_extragalactic_lod()
	_update_streamed_galaxy_proximity(delta)
		
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

func _update_streamed_galaxy_proximity(delta: float) -> void:
	if streamed_galaxy_field == null:
		return
	galaxy_proximity_scan_timer -= delta
	if galaxy_proximity_scan_timer > 0.0:
		return
	galaxy_proximity_scan_timer = 0.25
	_update_observer_galactic_position()
	var candidate_index := streamed_galaxy_field.find_activation_candidate(observer_galactic_position.to_light_years())
	if candidate_index == -1:
		return
	var candidate := streamed_galaxy_field.create_galaxy_data(candidate_index)
	if candidate == null or candidate.unique_id == current_astro.unique_id:
		return
	galaxy_lod_registry.pin(candidate)
	extragalactic_cluster = galaxy_lod_registry.compose_pinned(CosmicSectorManager.MAX_ACTIVE_GALAXIES)
	_switch_active_galaxy(candidate)
	print(">>> YAKIN GALAKSİ OTOMATİK ETKİN: %s | %d yıldız" % [candidate.designation, total_stars])

func _update_floating_origin() -> void:
	var cam := _get_active_camera()
	# Adaptif Eşik: Yerel yıldız/gezegen sistemindeyken 8.0 LY, derin uzaydayken 2500.0 LY
	# Böylece yüksek hızda seyahat ederken her karede gereksiz koordinat zıplaması ve titreme yaşanmaz
	var threshold := 8.0 if is_instance_valid(active_system_root) else 2500.0
	if cam == null or cam.global_position.length() < threshold:
		return
	var shift: Vector3 = cam.global_position
	render_origin_position.add_meters(shift * LIGHT_YEAR_METERS)
	galaxy_origin_ly += shift
	if is_instance_valid(multimesh_instance):
		multimesh_instance.position -= shift
	if is_instance_valid(black_hole_root):
		black_hole_root.position -= shift
	if is_instance_valid(active_system_root):
		active_system_root.position -= shift
	if spectator_camera != null:
		spectator_camera.position -= shift
	_update_observer_galactic_position()

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
			var target_pos := _galaxy_world_position(selected_extragalactic_galaxy)
			var to_target := target_pos - spectator_camera.position
			var distance_ly := to_target.length()
			var arrival_radius_ly := maxf(selected_extragalactic_galaxy.radius_ly * 1.8, 5000.0)
			if distance_ly <= arrival_radius_ly:
				is_interstellar_autopilot = false
				var target_gal := selected_extragalactic_galaxy
				var desig := target_gal.designation if target_gal != null else "Galaksi"
				_complete_galaxy_arrival(target_gal)
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
			
	if event is InputEventMouseMotion and mouse_captured:
		cam_rot_y -= event.relative.x * mouse_sensitivity
		cam_rot_x = clamp(cam_rot_x - event.relative.y * mouse_sensitivity, -1.5, 1.5)
		spectator_camera.rotation = Vector3(cam_rot_x, cam_rot_y, 0.0)
		
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_G:
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
			TargetSelection.clear(self)
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
			_teleport_spectator(_absolute_ly_to_world(Vector3(1200000.0, 2400000.0, 1800000.0)), _absolute_ly_to_world(Vector3.ZERO))
			print(">>> Kozmolojik Derin Uzay Panoraması (Yerel Grup & Kozmik Ağ - 3.5 Milyon Işık Yılı)")
		elif event.keycode == KEY_6:
			if extragalactic_cluster.size() > 3:
				var andromeda = extragalactic_cluster[3]
				_switch_active_galaxy(andromeda)
				var andromeda_pos = _galaxy_world_position(andromeda)
				_teleport_spectator(andromeda_pos + Vector3(80000.0, 120000.0, 90000.0), andromeda_pos)
				print(">>> Andromeda Tipi Dev Komşu Galaksi Görüş Noktası (~2.5 Milyon Işık Yılı)")
		elif event.keycode == KEY_R:
			galaxy_seed = randi()
		elif event.keycode == KEY_ESCAPE:
			mouse_captured = false
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _teleport_spectator(target_pos: Vector3, look_pos: Vector3) -> void:
	spectator_camera.position = target_pos
	spectator_camera.look_at(look_pos, Vector3.UP)
	var rot = spectator_camera.rotation
	cam_rot_x = rot.x
	cam_rot_y = rot.y

# ─────────────────────────────────────────────────────────────────────────────
# 9. HEDEFLEME VE IŞINLANMA SİSTEMİ (PLANET, BLACK HOLE & STAR RAYCAST)
# ─────────────────────────────────────────────────────────────────────────────
func _select_object_under_cursor() -> void:
	var cam := _get_active_camera()
	if cam == null:
		return
	var viewport := get_viewport()
	var cursor_position := Vector2.ZERO
	if viewport != null:
		cursor_position = viewport.get_visible_rect().size * 0.5 if mouse_captured else viewport.get_mouse_position()
	var result: Dictionary = CelestialTargeting.pick(self, cam, cursor_position)
	match result.get("kind", CelestialTargeting.NONE):
		CelestialTargeting.BODY:
			selected_planet = result["value"] as CelestialBody
			selected_star = null
			selected_extragalactic_galaxy = null
			selected_black_hole = false
			targeted_star_data = null
			current_target_index = universe.find(selected_planet)
			var body_kind := "Uydu" if selected_planet.type == "MOON" else "Gezegen"
			_record_discovery(selected_planet.unique_id, selected_planet.type, selected_planet.parent_id, selected_planet.name)
			print(">>> %s Seçildi: %s [%s]" % [body_kind, selected_planet.name, selected_planet.planet_type])
		CelestialTargeting.BLACK_HOLE:
			selected_planet = null
			selected_star = null
			selected_extragalactic_galaxy = null
			selected_black_hole = true
			targeted_star_data = black_hole_star_data
			current_target_index = -1
			_record_discovery(black_hole_star_data.unique_id, "BLACK_HOLE", black_hole_star_data.parent_id, black_hole_star_data.name)
			print(">>> Merkez Süper Kütleli Kara Delik Seçildi!")
		CelestialTargeting.STAR:
			selected_star = result["value"] as StarData
			selected_planet = null
			selected_extragalactic_galaxy = null
			selected_black_hole = false
			targeted_star_data = selected_star
			current_target_index = -1
			selected_star.discovered = true
			_record_discovery(selected_star.unique_id, "STAR", selected_star.parent_id, selected_star.name)
			var distance_ly := (_star_world_position(selected_star) - cam.global_position).length()
			print(">>> Yıldız Hedeflendi: %s [%s] | Mesafe: %.1f LY (G: Warp Seyri | Ctrl+G: Anında Atlama)" % [selected_star.name, selected_star.spectral_type, distance_ly])
		CelestialTargeting.GALAXY:
			selected_extragalactic_galaxy = result["value"] as Galaxy
			galaxy_lod_registry.pin(selected_extragalactic_galaxy)
			extragalactic_cluster = galaxy_lod_registry.compose_pinned(CosmicSectorManager.MAX_ACTIVE_GALAXIES)
			selected_star = null
			selected_planet = null
			selected_black_hole = false
			targeted_star_data = null
			current_target_index = -1
			_record_discovery(selected_extragalactic_galaxy.unique_id, "GALAXY", "", selected_extragalactic_galaxy.designation)
			var galaxy_name := selected_extragalactic_galaxy.custom_name if selected_extragalactic_galaxy.custom_name != "" else selected_extragalactic_galaxy.designation
			var distance_ly := _observer_distance_to_galaxy_ly(selected_extragalactic_galaxy)
			print(">>> Komşu Galaksi Hedeflendi: %s [%s] | Çap: %.0f LY | Mesafe: %.2f Milyon LY (G: Warp | Ctrl+G: Atlama)" % [galaxy_name, selected_extragalactic_galaxy.hubble_type, selected_extragalactic_galaxy.diameter_ly, distance_ly / 1.0e6])
		_:
			return
	if hud != null:
		hud.update_hud(self)

func _record_discovery(identifier: String, kind: String, parent_id: String, display_name: String) -> void:
	if discovery_catalog == null or identifier.is_empty():
		return
	if discovery_catalog.discover(identifier, kind, parent_id, display_name):
		if not discovery_catalog.save():
			push_warning("Keşif kataloğu kaydedilemedi: " + discovery_catalog.last_error)

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
	var dist_ly = _observer_distance_to_galaxy_ly(g)
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
		var body_kind := "Uyduya" if selected_planet.type == "MOON" else "Gezegene"
		print(">>> %s Yaklaşıldı: %s" % [body_kind, selected_planet.name])
		return
		
	# Eğer seçili komşu galaksi varsa galaksilerarası seyahat / warp
	if selected_extragalactic_galaxy != null:
		var target_pos = _galaxy_world_position(selected_extragalactic_galaxy)
		var approach_pos = target_pos + Vector3(
			selected_extragalactic_galaxy.radius_ly * 1.35,
			selected_extragalactic_galaxy.radius_ly * 0.75,
			selected_extragalactic_galaxy.radius_ly * 1.45
		)
		if is_interstellar_autopilot:
			is_interstellar_autopilot = false
			var arrived_galaxy := selected_extragalactic_galaxy
			_teleport_spectator(approach_pos, target_pos)
			_complete_galaxy_arrival(arrived_galaxy)
			print(">>> Komşu Galaksiye Anında Atlandı: %s [%s]" % [arrived_galaxy.designation, arrived_galaxy.hubble_type])
		else:
			is_interstellar_autopilot = true
			var distance_ly: float = (target_pos - cam.global_position).length()
			print(">>> Galaksilerarası Fly Camera Seyri: %s | %.2f Milyon LY" % [selected_extragalactic_galaxy.designation, distance_ly / 1.0e6])
		return

	# Eğer seçili yıldız varsa yıldıza seyahat / warp
	if selected_star != null:
		_enter_selected_star_system()
		return

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
		var body_kind := "Uyduya" if selected_planet.type == "MOON" else "Gezegene"
		print(">>> %s Anında Atlama Yapıldı: %s" % [body_kind, selected_planet.name])
	elif selected_extragalactic_galaxy != null:
		var arrived_galaxy := selected_extragalactic_galaxy
		var target_pos = _galaxy_world_position(selected_extragalactic_galaxy)
		var approach_pos = target_pos + Vector3(
			selected_extragalactic_galaxy.radius_ly * 1.35,
			selected_extragalactic_galaxy.radius_ly * 0.75,
			selected_extragalactic_galaxy.radius_ly * 1.45
		)
		_teleport_player_or_spectator(approach_pos, target_pos)
		_complete_galaxy_arrival(arrived_galaxy)
		print(">>> Komşu Galaksiye Anında Atlama Yapıldı: %s [%s]" % [arrived_galaxy.designation, arrived_galaxy.hubble_type])
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
	speed_index = FlyCameraSpeedProfile.closest_index(local_spectator_speed_mps, fly_speed_presets_mps)
	fly_speed_label = fly_speed_labels[speed_index]

func _teleport_player_or_spectator(approach_pos: Vector3, target_pos: Vector3) -> void:
	_teleport_spectator(approach_pos, target_pos)

# ─────────────────────────────────────────────────────────────────────────────
# 10. KULLANICI ARAYÜZÜ (SYSTEMHUD, 3B HEDEFLEME RETICLE & F3 TELEMETRİ KONSOLU)
# ─────────────────────────────────────────────────────────────────────────────
func _init_black_hole_data() -> void:
	black_hole_star_data = StarData.new()
	black_hole_star_data.galaxy_id = current_astro.unique_id
	black_hole_star_data.parent_id = current_astro.unique_id
	black_hole_star_data.unique_id = CelestialAddress.black_hole_id(current_astro.unique_id)
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
		target_world_pos = _galaxy_world_position(selected_extragalactic_galaxy)
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
	_update_observer_galactic_position()
	var dist_ly = observer_galactic_position.distance_to_ly(GalacticPosition.new())
	var fps = Performance.get_monitor(Performance.TIME_FPS)
	
	var mode_name = "SERBEST GÖZLEMCİ KAMERA"
	var view_submode = ""
			
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
		var g_dist_ly = _observer_distance_to_galaxy_ly(selected_extragalactic_galaxy)
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
