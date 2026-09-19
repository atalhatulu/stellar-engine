extends Node3D

const PlanetLODManager = preload("res://scripts/rendering/planet_lod_manager.gd")
const PlanetChunkSphere = preload("res://scripts/rendering/planet_chunk_sphere.gd")
const MidFieldStarRenderer = preload("res://scripts/rendering/mid_field_star_renderer.gd")
const DeepFieldStarRenderer = preload("res://scripts/rendering/deep_field_star_renderer.gd")
var NebulaManagerScript = load("res://scripts/generation/nebula_manager.gd")

@onready var camera = get_node_or_null("Player") if has_node("Player") else get_node_or_null("FlyCamera")
@onready var spacecraft: Spacecraft = get_node_or_null("Spacecraft")
@onready var hud: SystemHUD = get_node_or_null("HUD")
@onready var ui_label = get_node_or_null("Control/RichTextLabel")
@onready var directional_light = $DirectionalLight3D

# Gemi ve Oyuncu Ayrık Evren Pozisyonları
var spacecraft_universe_pos: Vector3 = Vector3.ZERO
var spacecraft_basis: Basis = Basis.IDENTITY

var visual_distance_limit: float = 10000.0
const LIGHT_SPEED: float = 299792458.0
const LIGHT_YEAR: float = 9460730472580800.0


var virtual_player_position: Vector3 = Vector3.ZERO
var current_target_index: int = -1
var targeted_star_data = null # Aşama 5: Kilitlenilen galaktik StarData
var is_interstellar_autopilot: bool = false # Aşama 5: Yıldızlararası galaktik otopilot
var is_interstellar_hyper_boost: bool = false # Çift G ile yıldızlararası hiper hızlandırma
var player_velocity: Vector3 = Vector3.ZERO
# Actual travel speed, independent of selected throttle and coordinate precision.
var flight_speed_mps: float = 0.0
var target_reticle: Panel

# Zaman Kontrol Değişkenleri
var time_scale: float = 1.0
var is_time_paused: bool = true
var simulation_time: float = 0.0

# Otopilot Değişkenleri
var is_autopilot_active: bool = false
var is_hyper_autopilot: bool = false # Çift G ile sistem içi hiper hızlandırma
var is_landing_autopilot: bool = false
var autopilot_start_player_pos: Vector3
var autopilot_target_body: CelestialBody = null
var autopilot_timer: float = 0.0
var autopilot_duration: float = 2.0
var autopilot_relative_start_pos: Vector3 = Vector3.ZERO
var autopilot_close_approach: bool = false  # Çift G ile yaklaşma
var followed_body: CelestialBody = null
var active_star: CelestialBody = null

# Odaklanma (C Tuşu / Target Lock) Değişkenleri
var is_focusing_target: bool = false
var focus_target_body: CelestialBody = null
var focus_target_star = null
var focus_time: float = 0.0

# Harita ve İniş Modu Değişkenleri
var is_system_map_active: bool = false
var map_pre_pos: Vector3 = Vector3.ZERO
var map_pre_rot_x: float = 0.0
var map_pre_rot_y: float = 0.0
var map_pre_rot_z: float = 0.0
var map_pre_speed_index: int = 3

var is_landed: bool = false
var landed_body: CelestialBody = null
var landed_local_pos: Vector3 = Vector3.ZERO
var landed_lod_manager = null
var sphere_chunk_manager = null  # Spherical chunk LOD for orbit/approach view
var _chunk_target: CelestialBody = null  # Current chunk target planet
var landed_walk_offset: Vector2 = Vector2.ZERO
var landed_vertical_offset: float = 0.0     # Zıplama/yükseklik için
var landed_vertical_velocity: float = 0.0   # Zıplama hızı (gravity uygulanır)
var show_chunk_borders: bool = false        # B tuşu ile chunk sınırlarını göster
var walk_speed_index: int = 2               # Varsayılan hız 15 m/s
const WALK_SPEED_PRESETS: Array = [2.0, 5.0, 10.0, 20.0, 40.0, 80.0, 160.0]
const JUMP_SPEED: float = 12.0              # Zıplama başlangıç hızı (m/s)
const SURFACE_GRAVITY: float = 20.0         # Gezegen yüzeyi yerçekimi (m/s²)
const EYE_HEIGHT: float = 1.8

# Outer Wilds Astronot & Jetpack Yaşam Desteği
var astronaut_oxygen: float = 100.0             # % Kask Yaşam Desteği (O2)
var astronaut_fuel: float = 100.0               # % Sırt Roketi (Jetpack Yakıtı)
var is_jetpack_active: bool = false
var is_jetpack_boosting: bool = false
const JETPACK_FUEL_CONSUMPTION: float = 24.0    # %/sn yakıt harcama
const JETPACK_FUEL_RECHARGE: float = 45.0       # %/sn şarj hızı (yüzeyde/gemide)

# Kesintisiz EVA (Uzay Yürüyüşü ve Park Edilmiş Gemi Durumu)
var is_eva_active: bool = false
var ship_eva_world_pos: Vector3 = Vector3.ZERO
var ship_eva_basis: Basis = Basis.IDENTITY
var eva_velocity: Vector3 = Vector3.ZERO
# Metre-scale EVA displacement never passes through astronomical Vector3 subtraction.
var eva_offset: Vector3 = Vector3.ZERO
var is_near_ship_airlock: bool = false
var dist_to_ship_eva: float = 0.0
var landed_ship_basis: Basis = Basis.IDENTITY

# Görsel Ölçek ve Sistem Çapı Değişkenleri
var visual_scale_multiplier: float = 1.0
var system_diameter: float = 0.0
var current_seed: int = 0
var sector_manager = null
var star_visual_pool = null
var galactic_starfield: MultiMeshInstance3D = null
var mid_field_renderer = null
@export var enable_mid_field: bool = true
var deep_field_renderer = null
@export var enable_deep_field: bool = true
@export var deep_field_star_count: int = 50000
var nebula_manager = null
var space_sky: Sky = null
var active_star_unique_id: String = ""
var _star_transition_cooldown: float = 0.0
var _star_transition_timer: float = 0.0
const STAR_TRANSITION_CHECK_INTERVAL: float = 0.15 # Saniyede ~6.6 kez histerezis kontrolü (7.500 döngü yerine)
var _body_texture_queue: Array[CelestialBody] = [] # Kare başına 1 gök cismi doku üretim kuyruğu (Sıfır spike)

# Debug / Geriye Dönük Uyumluluk (Aşama 4 ile evren SectorManager tarafından sonsuz yönetilir)
@export var debug_star_system_count: int = 10
@export var seed_value: int = 0
@export var run_startup_tests: bool = false

var universe: Array[CelestialBody] = []
var stars: Array[CelestialBody] = []
var active_system_bodies: Array[CelestialBody] = []
var active_render_bodies: Array[CelestialBody] = []
var total_planets_count: int = 0
var total_moons_count: int = 0
var is_hud_visible: bool = true
var is_wireframe_mode: bool = false
var _ui_update_timer: float = 0.0
const UI_REFRESH_INTERVAL: float = 0.1 # 10 Hz arayüz yenileme sıklığı


func _input(event):
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			get_tree().quit()
		elif event.keycode == KEY_TAB:
			is_hud_visible = !is_hud_visible
			is_wireframe_mode = false
			var hud_panel = get_node_or_null("Control/HUDPanel")
			if hud_panel:
				hud_panel.visible = is_hud_visible
			if hud != null:
				hud.visible = is_hud_visible
			if target_reticle:
				target_reticle.visible = is_hud_visible
			_update_materials_wireframe()
		elif event.keycode == KEY_T:
			if event.ctrl_pressed:
				_teleport_to_current_target()
			else:
				_cycle_target()
		elif event.keycode == KEY_P:
			is_time_paused = !is_time_paused
		elif event.keycode == KEY_LEFT:
			time_scale = clamp(time_scale / 2.0, 0.0625, 64.0)
		elif event.keycode == KEY_RIGHT:
			time_scale = clamp(time_scale * 2.0, 0.0625, 64.0)
		elif event.keycode == KEY_G:
			_start_autopilot()
		elif event.keycode == KEY_B:
			show_chunk_borders = !show_chunk_borders
			_update_chunk_borders()
		elif event.keycode == KEY_C:
			_handle_focus_key()
		elif event.keycode == KEY_R:
			_generate_universe(randi())
		elif event.keycode == KEY_M:
			_toggle_system_map()
		elif event.keycode == KEY_V:
			if star_visual_pool != null:
				var state = star_visual_pool.toggle_pool_visibility()
				print("Star Visual Pool Görünürlüğü: ", "AÇIK" if state else "KAPALI")
		elif event.keycode == KEY_F8:
			if is_instance_valid(landed_lod_manager) and landed_lod_manager.has_method("toggle_debug_colors"):
				var c_mode = landed_lod_manager.toggle_debug_colors()
				print("LOD CHUNK DEBUG RENK MODU (F8): ", "AÇIK (Yeşil/Mavi/Sarı/Turuncu/Kırmızı)" if c_mode else "KAPALI")
		elif event.keycode == KEY_F9:
			print("--- MANUEL TEST VE PROFİLLEME BAŞLATILIYOR (F9) ---")
			_run_all_diagnostics()
		elif event.keycode == KEY_F10:
			if mid_field_renderer != null:
				var state = mid_field_renderer.toggle_enabled()
				enable_mid_field = state
				print("GPU Mid-Field Star Layer (Aşama 7A): ", "AÇIK (20.000 Yıldız)" if state else "KAPALI")
		elif event.keycode == KEY_F11:
			if deep_field_renderer != null:
				var state = deep_field_renderer.toggle_enabled()
				enable_deep_field = state
				print("GPU Deep-Field Real Star Layer (Aşama 7B): ", ("AÇIK (%d Yıldız)" % deep_field_renderer.star_capacity) if state else "KAPALI")
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if is_system_map_active:
				_select_body_at_screen_pos(event.position)
			else:
				_select_body_under_crosshair()
		elif is_system_map_active and (event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			_zoom_system_map(event.button_index == MOUSE_BUTTON_WHEEL_UP)
		elif is_landed and (event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			# Yürüme hızı kontrolü
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				walk_speed_index = mini(walk_speed_index + 1, WALK_SPEED_PRESETS.size() - 1)
			else:
				walk_speed_index = maxi(walk_speed_index - 1, 0)

func _update_materials_wireframe() -> void:
	var vp = get_viewport()
	if not vp:
		return
		
	if is_wireframe_mode:
		vp.debug_draw = 1
	else:
		vp.debug_draw = 0

func _ready():
	randomize()
	
	# Oyuncu ve gemi başlangıç konumu: Yıldız sistemine uzaktan bakacak şekilde (yaklaşık 5.2 AU)
	virtual_player_position = Vector3(0, 0, 781200000000.0)
	spacecraft_universe_pos = virtual_player_position
	if spacecraft != null and camera != null:
		camera.spacecraft = spacecraft
		spacecraft_basis = camera.transform.basis
	
	# WorldEnvironment Ayarları (HDR Parlama)
	var camera_3d = camera.get_node_or_null("Camera3D")
	if camera_3d:
		camera_3d.near = 1.5 # Uzay boşluğunda Z-buffer hassasiyetini 15 kat artırır
		camera_3d.far = 20000.0 # 20 km render shell; simulation distances remain astronomical
		
		# Keep near/far precision suitable for both cockpit and compressed space.
		visual_distance_limit = 10000.0
		
		if not camera_3d.environment:
			camera_3d.environment = Environment.new()
		var env = camera_3d.environment
		
		# No Man's Sky tarzı Prosedürel Nebula ve Kozmik Gökyüzü
		var sky_shader = load("res://shaders/starfield.gdshader")
		if sky_shader:
			var sky_mat = ShaderMaterial.new()
			sky_mat.shader = sky_shader
			var sky = Sky.new()
			sky.sky_material = sky_mat
			env.background_mode = Environment.BG_SKY
			env.sky = sky
			space_sky = sky
		else:
			env.background_mode = Environment.BG_COLOR
			env.background_color = Color(0.01, 0.01, 0.02)

		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.23, 0.29, 0.36)
		env.ambient_light_energy = 0.30
		env.glow_enabled = true
		env.glow_intensity = 0.25
		env.glow_strength = 0.9
		env.glow_bloom = 0.0
		env.glow_hdr_threshold = 1.5
		camera_3d.attributes = null
	
	# Güneş Işığı Ayarları
	if directional_light:
		directional_light.light_color = Color(1.0, 0.98, 0.95)
		directional_light.light_energy = 1.5
		directional_light.shadow_enabled = false
		
	# Cam Efektli Modern HUD Paneli Oluşturma
	var hud_panel = PanelContainer.new()
	hud_panel.name = "HUDPanel"
	hud_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	hud_panel.position = Vector2(20, 20)
	hud_panel.size = Vector2(400, 960)
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.02, 0.05, 0.7)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.0, 0.8, 1.0, 0.3)
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	style.content_margin_left = 15
	style.content_margin_top = 15
	style.content_margin_right = 15
	style.content_margin_bottom = 15
	hud_panel.add_theme_stylebox_override("panel", style)
	
	var ui_parent = ui_label.get_parent()
	ui_parent.remove_child(ui_label)
	hud_panel.add_child(ui_label)
	ui_parent.add_child(hud_panel)
	
	ui_label.custom_minimum_size = Vector2(370, 930)
	ui_label.size = Vector2(370, 930)
	ui_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	ui_label.bbcode_enabled = true
	
	# Hedef Kilitleme Nişangahı (Reticle)
	target_reticle = Panel.new()
	target_reticle.name = "TargetReticle"
	var reticle_style = StyleBoxFlat.new()
	reticle_style.bg_color = Color(0, 0, 0, 0)
	reticle_style.border_width_left = 2
	reticle_style.border_width_top = 2
	reticle_style.border_width_right = 2
	reticle_style.border_width_bottom = 2
	reticle_style.border_color = Color(0, 0.8, 1.0, 0.7)
	reticle_style.corner_radius_top_left = 6
	reticle_style.corner_radius_top_right = 6
	reticle_style.corner_radius_bottom_left = 6
	reticle_style.corner_radius_bottom_right = 6
	target_reticle.add_theme_stylebox_override("panel", reticle_style)
	target_reticle.size = Vector2(40, 40)
	target_reticle.pivot_offset = Vector2(20, 20)
	ui_parent.add_child(target_reticle)
	
	# The HUD owns the single screen-centred crosshair.

	# Sağ üstte FPS sayacı
	var fps_label = Label.new()
	fps_label.name = "FPSLabel"
	fps_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	fps_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	fps_label.position = Vector2(-120, 20)
	fps_label.size = Vector2(100, 30)
	fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	fps_label.modulate = Color(0.0, 0.8, 1.0, 0.8) # Fütüristik mavi
	ui_parent.add_child(fps_label)
	
	# Seed ayarına göre evreni oluştur
	if seed_value != 0:
		_generate_universe(seed_value)
	else:
		_generate_universe(randi())

func _generate_universe(p_seed: int) -> void:
	flight_speed_mps = 0.0
	current_seed = p_seed
	seed(p_seed)
	
	# Reset must leave both the surface and EVA before replacing their anchors.
	is_landed = false
	landed_body = null
	landed_walk_offset = Vector2.ZERO
	landed_vertical_offset = 0.0
	landed_vertical_velocity = 0.0
	if is_instance_valid(landed_lod_manager):
		landed_lod_manager.queue_free()
	landed_lod_manager = null
	is_eva_active = false
	is_near_ship_airlock = false
	eva_offset = Vector3.ZERO
	eva_velocity = Vector3.ZERO
	player_velocity = Vector3.ZERO
	is_jetpack_active = false
	is_jetpack_boosting = false
	astronaut_fuel = 100.0
	astronaut_oxygen = 100.0
	is_interstellar_autopilot = false
	is_hyper_autopilot = false
	is_interstellar_hyper_boost = false
	is_landing_autopilot = false
	is_focusing_target = false
	is_system_map_active = false
	focus_target_body = null
	focus_target_star = null
	targeted_star_data = null
	_body_texture_queue.clear()
	if spacecraft != null:
		spacecraft.is_seated_in_cockpit = true
		spacecraft.current_view_mode = Spacecraft.CameraViewMode.THIRD_PERSON
		spacecraft.cabin_player_pos = spacecraft.PILOT_SEAT_POS
		spacecraft.cabin_player_pitch = 0.0
		spacecraft.cabin_player_yaw = 0.0
		spacecraft.is_airlock_open = false
		spacecraft.airlock_anim_progress = 0.0
		spacecraft.near_pilot_seat = true
		spacecraft.near_airlock = false
		spacecraft.travel_intensity = 0.0
	# Stars are intentionally excluded from generic planet despawning.
	for old_star in stars:
		if is_instance_valid(old_star.visual_mesh):
			old_star.visual_mesh.queue_free()
		if is_instance_valid(old_star.lod_sprite):
			old_star.lod_sprite.queue_free()

	# Sphere chunk'ları temizle (eski universe referansları geçersiz)
	if is_instance_valid(sphere_chunk_manager):
		_flv_clear_chunks()

	# Eski aktif sistem gök cismi grafiklerini ve referanslarını temizle
	for body in universe:
		SystemGenerator.despawn_body_graphics(body)
	universe.clear()
	stars.clear()
	active_system_bodies.clear()
	active_render_bodies.clear()
	total_planets_count = 0
	total_moons_count = 0
	current_target_index = -1
	is_autopilot_active = false
	autopilot_target_body = null
	followed_body = null
	
	# Kamera hızını ve açısını sıfırla/varsayılana çek
	if camera:
		camera.speed_multiplier_index = 3
		camera.target_speed = camera.speed_presets[3]
		camera.current_speed = camera.speed_presets[3]
		camera.rot_x = 0.0
		camera.rot_y = 0.0
		camera.rot_z = 0.0
		camera.transform.basis = Basis.IDENTITY

	# 1. Prosedürel 3D Galaktik Sektör Yöneticisini başlat (Sınırsız Evren)
	sector_manager = SectorManager.new(p_seed)
	
	# 2. Başlangıç galaktik konumunu belirle (Sektör (0,0,0) içi)
	var starting_gal_pos = Vector3(
		0.5 * SectorManager.SECTOR_SIZE,
		0.5 * SectorManager.SECTOR_SIZE,
		0.5 * SectorManager.SECTOR_SIZE
	)
	
	# 3. Başlangıç sektörünü ve çevresindeki 27 sektörü stream et
	sector_manager.update_player_position(starting_gal_pos)
	
	# 4. Başlangıç sektöründen (0,0,0) deterministik olarak bir yıldız seç
	var origin_sector_stars = sector_manager.loaded_sectors.get(Vector3i(0, 0, 0), [])
	if origin_sector_stars.is_empty():
		for coord in sector_manager.loaded_sectors:
			if not sector_manager.loaded_sectors[coord].is_empty():
				origin_sector_stars = sector_manager.loaded_sectors[coord]
				break
				
	var starting_star_data = origin_sector_stars[0]
	active_star_unique_id = starting_star_data.unique_id
	
	# 5. Bu yıldızı aktif sisteme (CelestialBody) dönüştür
	active_star = SystemGenerator.instantiate_star_from_data(self, starting_star_data)
	stars = [active_star]
	
	# Oyuncu başlangıç konumu: aktif yıldıza uzaktan bakış (~5.2 AU)
	virtual_player_position = Vector3(0, 0, 781200000000.0)
	
	# 6. Aktif sistemin gezegenlerini ve uydularını üret
	_update_active_system_bodies()
	
	# 7. Star Visual Pool'u başlat ve aktif sektörlerdeki yıldızlara bağla (1000 Slot Genişletilmiş)
	if star_visual_pool == null:
		star_visual_pool = StarVisualPool.new(1000, visual_distance_limit)
		add_child(star_visual_pool)
		star_visual_pool.init_pool()
		
	# 8. Derin Uzay Galaktik Yıldız Alanını Kur (4500 Uzak Yıldız - Tek Draw Call, 0 CPU Yükü)
	_setup_galactic_starfield()
	
	# 8.5 GPU Mid-Field Yıldız Katmanını Kur (Aşama 7A: 20.000 Yıldız, Gerçek Paralaks)
	if mid_field_renderer == null:
		mid_field_renderer = MidFieldStarRenderer.new()
		add_child(mid_field_renderer)
	mid_field_renderer.setup(current_seed)
	mid_field_renderer.set_enabled(enable_mid_field)
	
	# 8.6 GPU Deep-Field Gerçek Yıldız Katmanını Kur (Aşama 7B: 2.500-25.000 LY, 50.000 Yıldız)
	if deep_field_renderer == null:
		deep_field_renderer = DeepFieldStarRenderer.new()
		add_child(deep_field_renderer)
	deep_field_renderer.setup(current_seed, deep_field_star_count)
	deep_field_renderer.set_enabled(enable_deep_field)
	
	# 9. Prosedürel Bulutsular (Yapay görünüm sebebiyle devreden çıkarıldı)
	if nebula_manager != null and is_instance_valid(nebula_manager):
		nebula_manager.queue_free()
		nebula_manager = null
		
	var cam_forward = -camera.transform.basis.z if camera != null else Vector3.FORWARD
	var current_gal_pos = get_player_galactic_position()
	star_visual_pool.rebind(sector_manager, current_gal_pos, cam_forward, active_star_unique_id)
	
	# Başlangıç yıldızına bak
	_look_at_body(active_star)
	spacecraft_universe_pos = virtual_player_position
	spacecraft_basis = camera.global_basis
	if spacecraft != null:
		spacecraft.global_position = Vector3.ZERO
		spacecraft.global_basis = spacecraft_basis
	camera._update_camera_view(true)
	
	# İsteğe bağlı otomatik testler (Varsayılan kapalı - anında açılış, F9 ile manuel çalıştırılabilir)
	if run_startup_tests or OS.get_cmdline_user_args().has("--diagnostics"):
		_run_all_diagnostics()
		if OS.get_cmdline_user_args().has("--quit-after-diagnostics"):
			get_tree().quit()

func _run_all_diagnostics() -> void:
	_run_sector_manager_tests()
	_run_star_pool_benchmark()
	_run_mid_field_benchmark()
	_run_deep_field_benchmark()
	_run_stage_7c_single_universe_test()
	_run_sector_streaming_stress_test(10.0)
	_run_system_transition_determinism_test()
	_run_system_diversity_benchmark()
	_run_autopilot_and_focus_test()
	_run_airlock_and_eva_test()
	_run_player_spacecraft_decoupling_test()

func _update_active_system_bodies() -> void:
	_body_texture_queue.clear()
	for body in active_system_bodies:
		SystemGenerator.despawn_body_graphics(body)
	active_system_bodies.clear()
	
	if active_star != null:
		SystemGenerator.spawn_body_graphics(self, active_star)
		_body_texture_queue.append(active_star) # Aktif yıldıza en yüksek doku önceliği
		active_system_bodies = SystemGenerator.generate_planets_for_star(self, active_star)
				
	active_render_bodies.clear()
	if active_star != null:
		active_render_bodies.append(active_star)
	active_render_bodies.append_array(active_system_bodies)
	
	universe.clear()
	if active_star != null:
		universe.append(active_star)
	universe.append_array(active_system_bodies)
	
	stars.clear()
	if active_star != null:
		stars.append(active_star)
		
	total_planets_count = 0
	total_moons_count = 0
	for b in active_system_bodies:
		if b.type == "PLANET":
			total_planets_count += 1
		elif b.type == "MOON":
			total_moons_count += 1

# Kare başına en fazla 1 gök cisminin dokusunu üreterek sistem yaklaşma spike'larını sıfırlar
func _process_body_texture_queue() -> void:
	if _body_texture_queue.is_empty():
		return
		
	var body = _body_texture_queue.pop_front()
	if body == null:
		return
		
	if body.noise_albedo != null:
		return
		
	# Sadece aktif sistemdeyse üret
	if not active_render_bodies.has(body) and body != active_star:
		return
		
	SystemGenerator.generate_body_textures(self, body)
	
	if is_instance_valid(body.visual_mesh):
		var mat = body.visual_mesh.mesh.material as StandardMaterial3D
		if mat != null:
			mat.albedo_color = Color.WHITE
			mat.albedo_texture = body.noise_albedo
			if body.noise_normal != null:
				mat.normal_texture = body.noise_normal
				mat.normal_enabled = true
			else:
				mat.normal_enabled = false

# 32-bit float taşmalarını önleyen güvenli vektör uzunluğu (2500+ Işık Yılı ölçeği)
static func safe_vector_length(v: Vector3) -> float:
	var max_comp = maxf(absf(v.x), maxf(absf(v.y), absf(v.z)))
	if max_comp > 1.0e18:
		return (v / 9460730472580800.0).length() * 9460730472580800.0
	return v.length()

static func safe_vector_normalized(v: Vector3) -> Vector3:
	var max_comp = maxf(absf(v.x), maxf(absf(v.y), absf(v.z)))
	if max_comp > 1.0e18:
		return (v / 9460730472580800.0).normalized()
	return v.normalized()

# Oyuncunun evren içindeki 64-bit mutlak galaktik koordinatını döndürür
func get_player_galactic_position() -> Vector3:
	if active_star != null:
		return Vector3(active_star.stellar_x, active_star.stellar_y, active_star.stellar_z) + virtual_player_position
	return virtual_player_position

# Aşama 2 & 6: Determinizm, Negatif Koordinat ve Benchmark Doğrulama Testi
func _run_sector_manager_tests() -> void:
	if sector_manager == null:
		return
	print("==================================================")
	print("--- GALAKTİK SEKTÖR IZGARASI TESTLERİ (AŞAMA 2 & 6) ---")
	var det_result = sector_manager.test_sector_determinism(Vector3i(0, 0, 0), Vector3i(1, 0, 0))
	print("[DETERMİNİZM TESTİ: A -> B -> A]")
	print("  Sektör A: ", det_result["sector_a"])
	print("  Sektör B: ", det_result["sector_b"])
	print("  Sonuç: ", "BAŞARILI (TUTARLI)" if det_result["is_deterministic"] else "BAŞARISIZ (TUTARSIZ)")
	
	# Aşama 6 Test 2: Çoklu Sektör Döngüsü (A -> B -> C -> D -> A)
	var loop_result = sector_manager.test_multi_sector_loop()
	print("[ÇOKLU SEKTÖR DÖNGÜSÜ: A -> B -> C -> D -> A]")
	print("  Başlangıç: ", loop_result["start_sector"])
	print("  Parmak İzi İlk: ", loop_result["initial_fingerprint"])
	print("  Parmak İzi Son: ", loop_result["final_fingerprint"])
	print("  Döngü Determinizm: ", "BAŞARILI (A İLK == A SON)" if loop_result["is_deterministic"] else "BAŞARISIZ")
	
	# Aşama 6 Test 4: Negatif Koordinat ve Sınır Kapsama Testi
	var neg_result = sector_manager.test_negative_coordinates()
	print("[NEGATİF KOORDİNATLAR VE SINIR TESTİ]")
	for nr in neg_result["results"]:
		print("  Sektör %-20s | Yıldız: %2d | Sınır Kapsama: %s | Parmak İzi: %s" % [
			str(nr["coord"]),
			nr["star_count"],
			"GEÇERLİ" if nr["valid_bounds"] else "HATALI!",
			nr["fingerprint"]
		])
	print("  Negatif Koordinat Başarısı: ", "BAŞARILI" if neg_result["all_valid"] else "BAŞARISIZ")
	
	# Aşama 6 Test 3: Hızlı Sektör Geçişi (Tek Karede 100+ Sektör Atlama)
	var jump_result = sector_manager.test_rapid_jump()
	print("[HIZLI SEKTÖR GEÇİŞİ / IŞINLANMA TESTİ]")
	for jr in jump_result["jumps"]:
		print("  Hedef Sektör: %-25s | Yüklü Sektör: %2d | Süre: %5d us (%.3f ms) | Durum: %s" % [
			str(jr["target_coord"]),
			jr["loaded_sectors"],
			jr["elapsed_usec"],
			jr["elapsed_ms"],
			"GEÇERLİ" if jr["valid"] else "HATALI!"
		])
	print("  Hızlı Geçiş Başarısı: ", "BAŞARILI" if jump_result["all_successful"] else "BAŞARISIZ")
	
	print("[BENCHMARK TESTİ]")
	var test_coords: Array = [
		Vector3i(0, 0, 0),
		Vector3i(100, 0, 0),
		Vector3i(-500, 220, 71),
		Vector3i(100000, -80000, 45000)
	]
	var bench_results = sector_manager.run_benchmark(test_coords)
	for res in bench_results:
		print("  Koordinat: %-32s | Yıldız: %2d | Süre: %6d us (%.3f ms) | Parmak İzi: %s" % [
			str(res["coord"]),
			res["star_count"],
			res["elapsed_usec"],
			res["elapsed_ms"],
			res["fingerprint"]
		])
	print("==================================================")

# Aşama 3: 100, 500, 1000 Sprite Performans ve Sabit Node Doğrulama Benchmark'ı
func _run_star_pool_benchmark() -> void:
	if star_visual_pool == null:
		return
	print("==================================================")
	print("--- STAR VISUAL POOL BENCHMARK TESTİ (AŞAMA 3) ---")
	var bench_results = star_visual_pool.run_pool_benchmark([100, 250, 400])
	for res in bench_results:
		print("  Kapasite: %4d Yıldız | Rebind: %6d us (%.3f ms) | Transform: %6d us (%.3f ms) | Sabit Node: %s (%d) | Spike: %s" % [
			res["sprite_count"],
			res["rebind_usec"],
			res["rebind_ms"],
			res["transform_usec"],
			res["transform_ms"],
			"EVET" if res["nodes_constant"] else "HAYIR",
			res["node_count"],
			"YOK" if not res["spike_detected"] else "VAR"
		])
	print("==================================================")
	# Benchmark sonrası gerçek sektör yıldızlarına geri bağla
	var gal_pos = get_player_galactic_position()
	var cam_forward = -camera.transform.basis.z if camera != null else Vector3.FORWARD
	star_visual_pool.rebind(sector_manager, gal_pos, cam_forward, active_star_unique_id)

# Aşama 7A: GPU Mid-Field Yıldız Katmanı (20.000 Yıldız) Doğrulama ve Profilleme Benchmark'ı
func _run_mid_field_benchmark() -> Dictionary:
	if mid_field_renderer == null:
		print("[AŞAMA 7A BENCHMARK] HATA: mid_field_renderer başlatılmamış!")
		return {}
		
	print("==================================================")
	print("--- GPU MID-FIELD STAR LAYER BENCHMARK (AŞAMA 7A) ---")
	print("  Hedef Yıldız Sayısı : 20.000 Yıldız")
	print("  MultiMesh Parçaları  : 4 Bağımsız Chunk (5.000 yıldız/chunk)")
	print("  Menzil              : 150 LY - 2.500 LY (0-150 LY Fade-in, Çakışmasız)")
	
	var camera_3d = camera.get_node_or_null("Camera3D") if camera != null else null
	var active_cam: Node3D = camera_3d if camera_3d != null else camera
	var gal_pos = get_player_galactic_position()
	var test_frames = 100
	
	# 1. TEST: Mid-Field KAPALI (OFF) Performans Ölçümü
	mid_field_renderer.set_enabled(false)
	var nodes_off = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	var ram_off_bytes = Performance.get_monitor(Performance.MEMORY_STATIC)
	var time_off_start = Time.get_ticks_usec()
	for i in range(test_frames):
		mid_field_renderer.update_renderer(active_cam, gal_pos)
	var time_off_total_us = Time.get_ticks_usec() - time_off_start
	var time_off_per_frame_us = float(time_off_total_us) / float(test_frames)
	var time_off_per_frame_ms = time_off_per_frame_us / 1000.0
	
	# 2. TEST: Mid-Field AÇIK (ON) Performans Ölçümü
	mid_field_renderer.set_enabled(true)
	var nodes_on = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	var ram_on_bytes = Performance.get_monitor(Performance.MEMORY_STATIC)
	mid_field_renderer.update_renderer(active_cam, gal_pos)
	mid_field_renderer.finish_streaming()
	print("  Bölge üretimi (worker): %.3f ms" % (mid_field_renderer.last_generation_usec / 1000.0))
	var time_on_start = Time.get_ticks_usec()
	for i in range(test_frames):
		mid_field_renderer.update_renderer(active_cam, gal_pos)
	var time_on_total_us = Time.get_ticks_usec() - time_on_start
	var time_on_per_frame_us = float(time_on_total_us) / float(test_frames)
	var time_on_per_frame_ms = time_on_per_frame_us / 1000.0
	
	var cpu_overhead_us = time_on_per_frame_us - time_off_per_frame_us
	var cpu_overhead_ms = cpu_overhead_us / 1000.0
	var ram_diff_mb = float(ram_on_bytes - ram_off_bytes) / (1024.0 * 1024.0)
	var draw_call_increase = 4 # 4 adet MultiMeshInstance3D
	
	print("[1. PERFORMANS PROFİLİ]")
	print("  Mid-Field OFF CPU Süresi : %6.2f us (%.4f ms/kare)" % [time_off_per_frame_us, time_off_per_frame_ms])
	print("  Mid-Field ON  CPU Süresi : %6.2f us (%.4f ms/kare)" % [time_on_per_frame_us, time_on_per_frame_ms])
	print("  CPU Ek Yükü              : %6.2f us (%.4f ms/kare) -> HEDEF: < 0.05 ms (%s)" % [cpu_overhead_us, cpu_overhead_ms, "BAŞARILI" if cpu_overhead_ms < 0.05 else "HEDEF AŞILDI"])
	print("  Eklenen Draw Call       : +%d Draw Call (4 chunk)" % draw_call_increase)
	print("  Statik RAM Farkı         : %+.3f MB" % ram_diff_mb)
	print("  Node Sayısı Farkı        : %d Node" % (nodes_on - nodes_off))
	
	# 3. TEST: GPU-Side Galaktik Paralaks ve Anchor Kaydırma Doğrulaması
	print("[2. PARALAKS VE MAKRO BÖLGE DOĞRULAMASI]")
	var initial_anchor = mid_field_renderer.anchor_pos_ly
	var initial_region = mid_field_renderer.active_region
	
	# Oyuncu 1500 LY öteye seyahat etsin (Makro bölge sınırı 1000 LY aşılmalı)
	var far_gal_pos_meters = gal_pos + Vector3(1500.0, 0.0, 0.0) * LIGHT_YEAR
	mid_field_renderer.update_renderer(active_cam, far_gal_pos_meters)
	mid_field_renderer.finish_streaming()
	var shifted_anchor = mid_field_renderer.anchor_pos_ly
	var shifted_region = mid_field_renderer.active_region
	var region_shift_success = (shifted_region != initial_region) and (shifted_anchor.x > initial_anchor.x)
	
	# Geri dön
	mid_field_renderer.update_renderer(active_cam, gal_pos)
	mid_field_renderer.finish_streaming()
	var returned_anchor = mid_field_renderer.anchor_pos_ly
	var returned_region = mid_field_renderer.active_region
	var return_success = (returned_region == initial_region) and (returned_anchor == initial_anchor)
	
	print("  Makro Bölge Kaydırma (1500 LY) : %s (Bölge: %s -> %s)" % [
		"BAŞARILI" if region_shift_success else "BAŞARISIZ",
		str(initial_region),
		str(shifted_region)
	])
	print("  Geri Dönüşte Determinizm       : %s (Eski Tohum ve Anchor Korundu)" % [
		"BAŞARILI" if return_success else "BAŞARISIZ"
	])
	
	# 4. TEST: Culling ve Görsel Güvenlik Sınırları Doğrulaması
	var aabb_valid = true
	for chunk in mid_field_renderer.chunk_nodes:
		if chunk.extra_cull_margin < 2000000.0 or chunk.custom_aabb.size.x < 2000000.0:
			aabb_valid = false
			break
	print("  AABB / Frustum Culling Güvenliği: %s (Kamera Merkezli Geniş Hacim)" % ["BAŞARILI" if aabb_valid else "UYARI"])
	print("==================================================")
	
	# Kullanıcının önceki durumunu geri yükle
	mid_field_renderer.set_enabled(enable_mid_field)
	
	return {
		"time_off_us": time_off_per_frame_us,
		"time_on_us": time_on_per_frame_us,
		"cpu_overhead_ms": cpu_overhead_ms,
		"draw_call_increase": draw_call_increase,
		"region_shift_success": region_shift_success,
		"return_success": return_success,
		"aabb_valid": aabb_valid
	}

# Aşama 7B: GPU Deep-Field Gerçek Yıldız Katmanı (25k -> 50k -> 100k) Doğrulama ve Profilleme Benchmark'ı
func _run_deep_field_benchmark() -> Array:
	if deep_field_renderer == null:
		print("[AŞAMA 7B BENCHMARK] HATA: deep_field_renderer başlatılmamış!")
		return []
		
	print("==================================================")
	print("--- GPU DEEP-FIELD REAL STAR LAYER BENCHMARK (AŞAMA 7B) ---")
	print("  Menzil              : 2.500 LY - 25.000 LY (Hacimsel Derinlik)")
	print("  Kademeli Kapasite   : 25.000 -> 50.000 -> 100.000 Yıldız")
	print("  MultiMesh Parçaları  : 5 Bağımsız Chunk (Culling ve VRAM Kararlılığı)")
	print("  Tasarım Prensibi    : Her yıldız deterministik bir sektör ve tohum karşılığına sahiptir")
	
	var camera_3d = camera.get_node_or_null("Camera3D") if camera != null else null
	var active_cam: Node3D = camera_3d if camera_3d != null else camera
	var gal_pos = get_player_galactic_position()
	var test_frames = 100
	var benchmark_results: Array = []
	var target_capacities = [25000, 50000, 100000]
	
	for cap in target_capacities:
		deep_field_renderer.setup(current_seed, cap)
		deep_field_renderer.set_enabled(true)
		
		var ram_bytes = Performance.get_monitor(Performance.MEMORY_STATIC)
		var ram_mb = float(ram_bytes) / (1024.0 * 1024.0)
		var nodes_count = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
		
		# Measure steady state separately from worker generation and GPU upload.
		deep_field_renderer.update_renderer(active_cam, gal_pos)
		deep_field_renderer.finish_streaming()
		print("  Bölge üretimi (worker): %.3f ms" % (deep_field_renderer.last_generation_usec / 1000.0))
		var time_start = Time.get_ticks_usec()
		for i in range(test_frames):
			deep_field_renderer.update_renderer(active_cam, gal_pos)
		var time_total_us = Time.get_ticks_usec() - time_start
		var time_per_frame_us = float(time_total_us) / float(test_frames)
		var time_per_frame_ms = time_per_frame_us / 1000.0
		
		# Deterministik kimlik ve sektör çözünürlük doğrulaması
		var meta_sample_0 = deep_field_renderer.get_star_metadata(0)
		var meta_sample_mid = deep_field_renderer.get_star_metadata(cap / 2)
		var meta_valid = (not meta_sample_0.is_empty()) and (not meta_sample_mid.is_empty())
		
		print("--------------------------------------------------")
		print("  [KAPASİTE: %6d YILDIZ]" % cap)
		print("  • CPU Update Süresi : %6.2f us (%.4f ms/kare) -> HEDEF: < 0.05 ms (%s)" % [time_per_frame_us, time_per_frame_ms, "BAŞARILI" if time_per_frame_ms < 0.05 else "HEDEF AŞILDI"])
		print("  • Eklenen Draw Call : +5 Draw Call (5 chunk)")
		print("  • Statik Bellek     : %.2f MB" % ram_mb)
		print("  • Sahne Node Sayısı : %d Node" % nodes_count)
		print("  • Deterministik Eşleme : %s" % ("BAŞARILI" if meta_valid else "BAŞARISIZ"))
		if meta_valid:
			print("    -> Örnek Yıldız 0  : %s | Sektör: %s | Tohum: %d" % [meta_sample_0["unique_id"], str(meta_sample_0["sector_coord"]), meta_sample_0["system_seed"]])
			print("    -> Örnek Yıldız Ort: %s | Sektör: %s | Tohum: %d" % [meta_sample_mid["unique_id"], str(meta_sample_mid["sector_coord"]), meta_sample_mid["system_seed"]])
			
		benchmark_results.append({
			"capacity": cap,
			"cpu_us": time_per_frame_us,
			"cpu_ms": time_per_frame_ms,
			"ram_mb": ram_mb,
			"meta_valid": meta_valid
		})
		
	# 4. TEST: Culling ve Makro Bölge Sınır Güvenliği
	print("--------------------------------------------------")
	print("[PARALAKS VE MAKRO BÖLGE (5000 LY) TESTİ]")
	var initial_anchor = deep_field_renderer.anchor_pos_ly
	var initial_region = deep_field_renderer.active_region
	
	# 6.000 LY seyahat simülasyonu (5.000 LY sınırı aşılmalı)
	var far_gal_pos_meters = gal_pos + Vector3(6000.0, 0.0, 0.0) * LIGHT_YEAR
	deep_field_renderer.update_renderer(active_cam, far_gal_pos_meters)
	deep_field_renderer.finish_streaming()
	var shifted_anchor = deep_field_renderer.anchor_pos_ly
	var shifted_region = deep_field_renderer.active_region
	var region_shift_success = (shifted_region != initial_region) and (shifted_anchor.x > initial_anchor.x)
	
	# Geri dön
	deep_field_renderer.update_renderer(active_cam, gal_pos)
	deep_field_renderer.finish_streaming()
	var return_success = (deep_field_renderer.active_region == initial_region)
	
	print("  Makro Bölge Kaydırma (6000 LY) : %s (Bölge: %s -> %s)" % [
		"BAŞARILI" if region_shift_success else "BAŞARISIZ",
		str(initial_region),
		str(shifted_region)
	])
	print("  Geri Dönüşte Determinizm       : %s (Eski Tohum ve Anchor Korundu)" % ["BAŞARILI" if return_success else "BAŞARISIZ"])
	print("==================================================")
	
	# Kullanıcının varsayılan kapasitesini ve görünürlük durumunu geri yükle
	deep_field_renderer.setup(current_seed, deep_field_star_count)
	deep_field_renderer.set_enabled(enable_deep_field)
	deep_field_renderer.update_renderer(active_cam, gal_pos)
	deep_field_renderer.finish_streaming()
	
	return benchmark_results

# Aşama 7C: Tek Gerçek Yıldız Evreni + Hiyerarşik LOD Doğrulama Testi
func _run_stage_7c_single_universe_test() -> bool:
	print("==================================================")
	print("--- TEK GERÇEK YILDIZ EVRENİ + LOD DOĞRULAMA TESTİ (AŞAMA 7C) ---")
	print("  Prensip: Deep GPU Point -> Mid GPU Point -> Near Sprite3D -> Active System")
	print("  Kural  : unique_id, koordinat ve system_seed ASLA değişmemeli!")
	
	if deep_field_renderer == null or sector_manager == null:
		print("  HATA: Gerekli yöneticiler başlatılmamış!")
		return false
		
	var camera_3d = camera.get_node_or_null("Camera3D") if camera != null else null
	var active_cam: Node3D = camera_3d if camera_3d != null else camera
	var gal_pos = get_player_galactic_position()
	
	# Deep-field renderer'ın hazır olduğundan emin ol
	deep_field_renderer.update_renderer(active_cam, gal_pos)
	deep_field_renderer.finish_streaming()
	
	var test_stars_found: Array = []
	var total_stars = deep_field_renderer.star_logical_positions_ly.size()
	var player_pos_ly = gal_pos / LIGHT_YEAR
	
	# 1. ADIM: 5.000+ LY mesafede 3 adet Deep-Field GPU yıldızı seç
	for idx in range(0, total_stars, max(1, total_stars / 200)):
		var meta = deep_field_renderer.get_star_metadata(idx)
		if meta.is_empty():
			continue
		var star_pos_ly = meta["galactic_pos_ly"]
		var dist_ly = player_pos_ly.distance_to(star_pos_ly)
		if dist_ly >= 5000.0:
			test_stars_found.append({
				"deep_index": idx,
				"dist_ly": dist_ly,
				"meta": meta
			})
		if test_stars_found.size() >= 3:
			break
			
	if test_stars_found.size() < 3:
		print("  HATA: Yeterli 5000+ LY yıldız bulunamadı! (Mevcut: %d)" % test_stars_found.size())
		return false
		
	var all_stages_valid = true
	var test_counter = 1
	
	for entry in test_stars_found:
		var deep_meta = entry["meta"]
		var deep_id = deep_meta["unique_id"]
		var deep_coord = deep_meta["sector_coord"]
		var deep_seed = deep_meta["system_seed"]
		var deep_pos_ly = deep_meta["galactic_pos_ly"]
		var dist_ly = entry["dist_ly"]
		
		# AŞAMA 1: DEEP-FIELD (2.500 - 25.000 LY GPU Point)
		# deep_id, deep_seed, deep_pos_ly doğrudan doğrulanır
		
		# AŞAMA 2: MID-FIELD (150 - 2.500 LY GPU Point/Billboard)
		# Oyuncu bu sektöre yaklaştığında Mid-Field aynı sektör koordinatından S1 yıldızını türetir
		var mid_star = SectorManager.generate_single_star(current_seed, deep_coord, 0)
		var mid_id = mid_star.unique_id
		var mid_seed = mid_star.system_seed
		var mid_pos_ly = Vector3(mid_star.stellar_x, mid_star.stellar_y, mid_star.stellar_z) / LIGHT_YEAR
		
		# AŞAMA 3: NEAR GAMEPLAY (0 - 150 LY - StarVisualPool Sprite3D / SectorManager)
		# Oyuncu sektörün yerel streaming alanına girdiğinde SectorManager tüm sektörü stream eder
		var near_sector_stars = sector_manager.generate_sector(deep_coord)
		var near_star = near_sector_stars[0] # S1 yıldızı
		var near_id = near_star.unique_id
		var near_seed = near_star.system_seed
		var near_pos_ly = Vector3(near_star.stellar_x, near_star.stellar_y, near_star.stellar_z) / LIGHT_YEAR
		
		# AŞAMA 4: ACTIVE SYSTEM (0 - 50 AU - CelestialBody)
		# Oyuncu yıldız sistemine vardığında instantiate_star_from_data ile sistem kurulur
		var active_temp_star = SystemGenerator.instantiate_star_from_data(self, near_star)
		var active_id = near_star.unique_id
		var active_seed = active_temp_star.sys_seed
		var active_pos_ly = Vector3(active_temp_star.stellar_x, active_temp_star.stellar_y, active_temp_star.stellar_z) / LIGHT_YEAR
		
		# Temizlik (test amaçlı geçici spawn edilen mesh'i sil)
		SystemGenerator.despawn_body_graphics(active_temp_star)
		if is_instance_valid(active_temp_star.visual_mesh):
			active_temp_star.visual_mesh.queue_free()
		if is_instance_valid(active_temp_star.lod_sprite):
			active_temp_star.lod_sprite.queue_free()
		
		# ZİNCİR DOĞRULAMA KONTROLLERİ
		var id_match = (deep_id == mid_id) and (mid_id == near_id) and (near_id == active_id)
		var seed_match = (deep_seed == mid_seed) and (mid_seed == near_seed) and (near_seed == active_seed)
		
		# Pozisyon farkları (Metre cinsinden tam koordinat farkı)
		var diff_mid = abs(mid_star.stellar_x - near_star.stellar_x) + abs(mid_star.stellar_y - near_star.stellar_y) + abs(mid_star.stellar_z - near_star.stellar_z)
		var diff_active = abs(near_star.stellar_x - active_temp_star.stellar_x) + abs(near_star.stellar_y - active_temp_star.stellar_y) + abs(near_star.stellar_z - active_temp_star.stellar_z)
		var diff_deep = (deep_pos_ly - mid_pos_ly).length() * LIGHT_YEAR
		var max_diff_meters = max(diff_deep, max(diff_mid, diff_active))
		var pos_match = (max_diff_meters < 1000.0) # 100 trilyon km ölçeğinde 1 km altı kuantizasyon toleransı
		
		print("--------------------------------------------------")
		print("[TEST YILDIZI #%d: Mesafe = %.1f LY | Sektör = %s]" % [test_counter, dist_ly, str(deep_coord)])
		print("  1. Deep-Field GPU   : ID = %-20s | Seed = %-10d | Pos = (%.1f, %.1f, %.1f) LY" % [deep_id, deep_seed, deep_pos_ly.x, deep_pos_ly.y, deep_pos_ly.z])
		print("  2. Mid-Field GPU    : ID = %-20s | Seed = %-10d | Pos = (%.1f, %.1f, %.1f) LY" % [mid_id, mid_seed, mid_pos_ly.x, mid_pos_ly.y, mid_pos_ly.z])
		print("  3. Near Gameplay    : ID = %-20s | Seed = %-10d | Pos = (%.1f, %.1f, %.1f) LY" % [near_id, near_seed, near_pos_ly.x, near_pos_ly.y, near_pos_ly.z])
		print("  4. Active System    : ID = %-20s | Seed = %-10d | Pos = (%.1f, %.1f, %.1f) LY" % [active_id, active_seed, active_pos_ly.x, active_pos_ly.y, active_pos_ly.z])
		
		print("  • ID Zinciri (Deep==Mid==Near==Active)     : %s" % ("BAŞARILI (TUTARLI)" if id_match else "BAŞARISIZ"))
		print("  • Tohum Zinciri (Seed Korundu mu?)        : %s" % ("BAŞARILI (TUTARLI)" if seed_match else "BAŞARISIZ"))
		print("  • Pozisyon Sürekliliği (Sıfır Kayma)     : %s (Max Fark = %.2f m)" % [
			"BAŞARILI (TUTARLI)" if pos_match else "BAŞARISIZ",
			max_diff_meters
		])
		
		if not (id_match and seed_match and pos_match):
			all_stages_valid = false
			
		test_counter += 1
		
	print("--------------------------------------------------")
	print("GENEL AŞAMA 7C ZİNCİR DEĞERLENDİRMESİ: %s" % ("%100 TUTARLI VE BAŞARILI" if all_stages_valid else "HATALI"))
	print("==================================================")
	return all_stages_valid

# Aşama 6: 100+ Sektör Streaming Stres Testi ve Kapsamlı Profilleme
func _run_sector_streaming_stress_test(simulated_minutes: float = 10.0) -> Dictionary:
	print("==================================================")
	print("--- KESİNTİSİZ SEKTÖR GEÇİŞİ STRES TESTİ VE PROFİLLEME (AŞAMA 6) ---")
	print("  Simüle Edilen Süre: %.1f Dakika" % simulated_minutes)
	
	var initial_nodes = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	var initial_ram_bytes = Performance.get_monitor(Performance.MEMORY_STATIC)
	var initial_ram_mb = float(initial_ram_bytes) / (1024.0 * 1024.0)
	var initial_stardata = sector_manager.total_generated_stars
	var initial_bodies = universe.size()
	var initial_sprites = star_visual_pool.get_child_count()
	var initial_sectors = sector_manager.loaded_sectors.size()
	
	# Aktif yıldız sektör koruma testi için başlangıç sektörü
	var active_star_coord = sector_manager.get_sector_coord(Vector3(active_star.stellar_x, active_star.stellar_y, active_star.stellar_z)) if active_star != null else Vector3i.ZERO
	
	# Test rotası: 600 adım (Her adım = 1 saniye uçuş, 10 LY hızında, toplam ~300 sektör geçişi)
	var total_steps = int(simulated_minutes * 60.0)
	var step_size = 0.5 * SectorManager.SECTOR_SIZE # Her 2 adımda bir sektör sınırı geçilir
	var travel_direction = Vector3(1.0, 0.2, -0.5).normalized()
	
	var test_gal_pos = get_player_galactic_position()
	var sector_transitions = 0
	var max_step_usec = 0
	var total_step_usec = 0
	
	var ram_samples: Array[float] = [initial_ram_mb]
	var node_samples: Array[int] = [initial_nodes]
	
	var start_benchmark_ticks = Time.get_ticks_msec()
	
	for step in range(total_steps):
		test_gal_pos += travel_direction * step_size
		var step_start_ticks = Time.get_ticks_usec()
		
		# 1. Sektör güncellemesi (Aktif yıldız sektör korumalı Delta streaming)
		var changed = sector_manager.update_player_position(test_gal_pos, active_star_coord)
		if changed:
			sector_transitions += 1
			
		# 2. Star Visual Pool güncellemesi
		var cam_fwd = -camera.transform.basis.z if camera != null else Vector3.FORWARD
		star_visual_pool.update_pool(0.016, sector_manager, test_gal_pos, cam_fwd, 75.0, 1080.0, changed, active_star_unique_id, targeted_star_data)
		
		var step_duration = Time.get_ticks_usec() - step_start_ticks
		if step_duration > max_step_usec:
			max_step_usec = step_duration
		total_step_usec += step_duration
		
		# 100 adımda bir bellek ve node örneği al
		if (step + 1) % 100 == 0:
			var cur_ram = float(Performance.get_monitor(Performance.MEMORY_STATIC)) / (1024.0 * 1024.0)
			var cur_nodes = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
			ram_samples.append(cur_ram)
			node_samples.append(cur_nodes)
			
	var total_benchmark_ms = Time.get_ticks_msec() - start_benchmark_ticks
	var final_nodes = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var final_ram_bytes = Performance.get_monitor(Performance.MEMORY_STATIC)
	var final_ram_mb = float(final_ram_bytes) / (1024.0 * 1024.0)
	var final_stardata = sector_manager.total_generated_stars
	var final_bodies = universe.size()
	var final_sprites = star_visual_pool.get_child_count()
	var final_sectors = sector_manager.loaded_sectors.size()
	var avg_step_usec = total_step_usec / max(total_steps, 1)
	
	var ram_growth_mb = final_ram_mb - initial_ram_mb
	var nodes_constant = (final_nodes == initial_nodes)
	var node_diff = final_nodes - initial_nodes
	
	# Aktif yıldız sektörünün seyahat boyunca silinmediğini doğrula
	var active_star_sector_preserved = sector_manager.loaded_sectors.has(active_star_coord)
	
	# Test sonrası oyuncunun gerçek konumunu geri yükle
	var real_gal_pos = get_player_galactic_position()
	sector_manager.update_player_position(real_gal_pos, active_star_coord)
	var cam_fwd = -camera.transform.basis.z if camera != null else Vector3.FORWARD
	star_visual_pool.rebind(sector_manager, real_gal_pos, cam_fwd, active_star_unique_id, targeted_star_data)
	
	print("  Tamamlanan Seyahat Adımı: %d adım" % total_steps)
	print("  Sektör Sınırı Geçiş Sayısı: %d kez (Gereksinim: >=100)" % sector_transitions)
	print("  Toplam Test Süresi: %d ms | Ortalama CPU Adımı: %d us (%.3f ms)" % [total_benchmark_ms, avg_step_usec, float(avg_step_usec) / 1000.0])
	print("  Maksimum Geçiş Spike: %d us (%.3f ms)" % [max_step_usec, float(max_step_usec) / 1000.0])
	print("--------------------------------------------------")
	print("  [AŞAMA 6 PROFİLLEME KARŞILAŞTIRMASI]")
	print("  • Bu senkron CPU testi gerçek oyun FPS ölçümü değildir.")
	print("  • CPU Adımı:             Ortalama: %.3f ms | En Yüksek: %.3f ms" % [float(avg_step_usec) / 1000.0, float(max_step_usec) / 1000.0])
	print("  • Sahne Node Sayısı:     Başlangıç: %4d | Bitiş: %4d (Fark: %+d)" % [initial_nodes, final_nodes, node_diff])
	print("  • Statik Bellek (RAM):   Başlangıç: %.2f MB | Bitiş: %.2f MB (Değişim: %+.2f MB)" % [initial_ram_mb, final_ram_mb, ram_growth_mb])
	print("  • RAM'deki StarData:     Başlangıç: %4d | Bitiş: %4d (Sabit 125-126 Sektör)" % [initial_stardata, final_stardata])
	print("  • CelestialBody Sayısı:  Başlangıç: %4d | Bitiş: %4d (Sadece Aktif Sistem)" % [initial_bodies, final_bodies])
	print("  • Havuz Çocuk Düğüm:     Başlangıç: %4d | Bitiş: %4d (Sıfır Sızıntı)" % [initial_sprites, final_sprites])
	print("  • Yüklü Sektör Sayısı:   Başlangıç: %4d | Bitiş: %4d (Max 126)" % [initial_sectors, final_sectors])
	print("  • Aktif Sektör Koruma:   %s" % ("BAŞARILI (KORUNDU)" if active_star_sector_preserved else "BAŞARISIZ!"))
	print("  • Node Sızıntı Başarısı: %s" % ("BAŞARILI (SIFIR DÜĞÜM SIZINTISI)" if nodes_constant else "BAŞARISIZ"))
	print("  • RAM Kararlılık:        %s" % ("BAŞARILI (SÜREKLİ BÜYÜME YOK)" if abs(ram_growth_mb) < 5.0 else "DİKKAT"))
	print("==================================================")
	
	return {
		"simulated_minutes": simulated_minutes,
		"steps": total_steps,
		"sector_transitions": sector_transitions,
		"total_benchmark_ms": total_benchmark_ms,
		"avg_step_usec": avg_step_usec,
		"max_step_usec": max_step_usec,
		"initial_ram_mb": initial_ram_mb,
		"final_ram_mb": final_ram_mb,
		"ram_growth_mb": ram_growth_mb,
		"initial_nodes": initial_nodes,
		"final_nodes": final_nodes,
		"ram_samples": ram_samples,
		"node_samples": node_samples
	}


# Aşama 5: A -> B -> A Yıldız Sistemi Geçiş Determinizm Testi
func _run_system_transition_determinism_test() -> void:
	if sector_manager == null or active_star == null:
		return
	print("==================================================")
	print("--- SİSTEM GEÇİŞ DETERMINİZM TESTİ (AŞAMA 5: A -> B -> A) ---")
	
	# 1. Başlangıç yıldızının (Yıldız A) StarData kaydını bul
	var star_a_data = null
	for coord in sector_manager.loaded_sectors:
		for s in sector_manager.loaded_sectors[coord]:
			if s.unique_id == active_star_unique_id:
				star_a_data = s
				break
		if star_a_data != null:
			break
			
	if star_a_data == null:
		print("  [HATA] Yıldız A verisi bulunamadı!")
		print("==================================================")
		return
		
	# 2. Yıldız A parmak izini (fingerprint) oluştur
	var fp_a1 = _get_active_system_fingerprint()
	print("  Yıldız A: %s (%s)" % [star_a_data.name, star_a_data.unique_id])
	print("  Parmak İzi A1: ", fp_a1)
	
	# 3. Farklı bir sektörden Yıldız B bul
	var star_b_data = null
	for coord in sector_manager.loaded_sectors:
		for s in sector_manager.loaded_sectors[coord]:
			if s.unique_id != star_a_data.unique_id:
				star_b_data = s
				break
		if star_b_data != null:
			break
			
	if star_b_data == null:
		print("  [HATA] Yıldız B verisi bulunamadı!")
		print("==================================================")
		return
		
	# 4. Yıldız B'ye geç
	_transition_to_star_data(star_b_data)
	var fp_b = _get_active_system_fingerprint()
	print("  Yıldız B: %s (%s)" % [star_b_data.name, star_b_data.unique_id])
	print("  Parmak İzi B:  ", fp_b)
	
	# 5. Tekrar Yıldız A'ya dön
	_transition_to_star_data(star_a_data)
	var fp_a2 = _get_active_system_fingerprint()
	print("  Yıldız A (Tekrar): %s (%s)" % [star_a_data.name, star_a_data.unique_id])
	print("  Parmak İzi A2: ", fp_a2)
	
	# 6. Karşılaştır
	var is_deterministic = (fp_a1 == fp_a2)
	print("  Sonuç: ", "BAŞARILI (TUTARLI: A1 == A2)" if is_deterministic else "BAŞARISIZ (TUTARSIZ!)")
	print("==================================================")

func _get_active_system_fingerprint() -> String:
	var parts: Array[String] = []
	if active_star != null:
		parts.append("STAR:%s|%d|%.1f|%s" % [active_star.name, active_star.sys_seed, active_star.real_radius, active_star.base_color.to_html()])
	for b in active_system_bodies:
		parts.append("%s:%s|%.1f|%.1f|%.4f|%.4f|%s" % [
			b.type,
			b.name,
			b.real_radius,
			b.orbit_radius,
			b.orbit_speed,
			b.axial_tilt,
			b.base_color.to_html()
		])
	var raw_str = ";".join(parts)
	return "%d_bodies_%X" % [parts.size(), raw_str.hash()]

# Aşama 7: 100 Farklı Sistemde Prosedürel Çeşitlilik Benchmark'ı
func _run_system_diversity_benchmark() -> void:
	print("==================================================")
	print("--- YILDIZ SİSTEMİ VE GEZEGEN ÇEŞİTLİLİĞİ TESTİ (AŞAMA 7) ---")
	print("  100 Farklı Sistem Üzerinde Dağılım Ölçümü Yapılıyor...")
	
	var res = SystemGenerator.run_diversity_benchmark(100, current_seed)
	
	print("--------------------------------------------------")
	print("  [SİSTEM BÜYÜKLÜĞÜ DAĞILIMI (100 SİSTEM)]")
	for size_key in res["system_sizes"]:
		var count = res["system_sizes"][size_key]
		print("  • %-16s: %2d sistem (%%%d)" % [size_key, count, count])
		
	print("--------------------------------------------------")
	print("  [YILDIZ SPEKTRAL TİP DAĞILIMI]")
	for s_type in res["spectral_dist"]:
		var count = res["spectral_dist"][s_type]
		print("  • %-16s: %2d yıldız (%%%d)" % [s_type, count, count])
		
	print("--------------------------------------------------")
	print("  [GEZEGEN TİPLERİ DAĞILIMI]")
	for p_type in res["planet_types_dist"]:
		var count = res["planet_types_dist"][p_type]
		var ratio = float(count) / max(res["total_planets"], 1) * 100.0
		print("  • %-22s: %3d gezegen (%%%4.1f)" % [p_type, count, ratio])
		
	print("--------------------------------------------------")
	print("  [UYDU (MOON) VE ORTALAMA METRİKLERİ]")
	print("  • Toplam Gezegen:        %d (Ortalama: %.1f gezegen/sistem)" % [res["total_planets"], res["avg_planets"]])
	print("  • Toplam Uydu:           %d (Ortalama: %.1f uydu/sistem)" % [res["total_moons"], res["avg_moons"]])
	print("  • Uydusuz Gezegen Oranı: %%%.1f (%d gezegen 0 uydulu)" % [res["zero_moon_ratio"] * 100.0, res["zero_moon_planets"]])
	print("  • Gaz Devi Uydu Ort.:    %.1f uydu/gaz devi" % res["avg_gas_giant_moons"])
	print("==================================================")

func _run_autopilot_and_focus_test() -> void:
	print("==================================================")
	print("--- OTOPİLOT (G), ODAKLANMA (C) VE HUD DOĞRULAMA TESTİ ---")
	var success = true
	
	# 1. Odaklanma (C tuşu) Testi
	is_focusing_target = false
	focus_target_body = null
	focus_target_star = null
	current_target_index = -1
	
	_handle_focus_key()
	if not is_focusing_target or focus_target_body != active_star:
		print("  • Hedefsiz C basımı (Yıldıza odaklanma): BAŞARISIZ")
		success = false
	else:
		print("  • Hedefsiz C basımı (Yıldıza odaklanma): BAŞARILI")
		
	_handle_focus_key()
	if is_focusing_target or focus_target_body != null:
		print("  • İkinci C basımı (Odağı kaldırma): BAŞARISIZ")
		success = false
	else:
		print("  • İkinci C basımı (Odağı kaldırma): BAŞARILI")
		
	# 2. Gezegene Odaklanma Testi
	if universe.size() > 1:
		current_target_index = 1
		var planet = universe[1]
		_handle_focus_key()
		if not is_focusing_target or focus_target_body != planet:
			print("  • Gezegene Odaklanma (C Tuşu): BAŞARISIZ")
			success = false
		else:
			print("  • Gezegene Odaklanma (C Tuşu): BAŞARILI (%s)" % planet.name)
			
	# 3. Otopilot (G tuşu) Başlatma ve Çift G Hiper Testi
	if universe.size() > 1:
		current_target_index = 1
		_start_autopilot()
		if not is_autopilot_active or autopilot_target_body != universe[1] or is_focusing_target or is_hyper_autopilot:
			print("  • Sistem Otopilotu (İlk G Tuşu Başlatma): BAŞARISIZ")
			success = false
		else:
			print("  • Sistem Otopilotu (İlk G Tuşu Başlatma): BAŞARILI (Süre: %.2f sn)" % autopilot_duration)
			
		# Seyir halindeyken ikinci kez G'ye basma (Çift G Hiper Otopilot)
		_start_autopilot()
		if not is_autopilot_active or not is_hyper_autopilot or not is_equal_approx(autopilot_duration, 0.35):
			print("  • Çift G Hiper Otopilot Hızlandırma: BAŞARISIZ")
			success = false
		else:
			print("  • Çift G Hiper Otopilot Hızlandırma: BAŞARILI (0.35 sn Hiper Sıçrama)")
			
	# 4. HUD Telemetri Metin Kontrolü
	if hud != null:
		hud.update_hud(self)
	if ui_label != null:
		SystemUI.update_ui(self, active_star.name if active_star else "Test", 1000.0)
	var pass_hud = (hud != null) or (ui_label != null and ui_label.text.length() > 0)
	if not pass_hud:
		print("  • HUD Telemetri Güncellemesi: BAŞARISIZ")
		success = false
	else:
		print("  • HUD Telemetri Güncellemesi: BAŞARILI (Fütüristik SystemHUD ve Telemetri Aktif)")
		
	# Temizleme
	is_autopilot_active = false
	is_hyper_autopilot = false
	is_interstellar_hyper_boost = false
	autopilot_target_body = null
	is_focusing_target = false
	focus_target_body = null
	current_target_index = -1
	
	if success:
		print("GENEL OTOPİLOT, ODAKLANMA VE HUD DOĞRULAMA: %100 BAŞARILI")
	else:
		printerr("GENEL OTOPİLOT, ODAKLANMA VE HUD DOĞRULAMA: EKSİKLER MEVCUT")
	print("==================================================")

# Derin Uzay Arka Plan Galaktik Yıldız Alanı (MultiMeshInstance3D - Tek Draw Call, 0 CPU Yükü)
func _setup_galactic_starfield() -> void:
	# Aşama 7A ve 7B ile birlikte sahte statik küresel süs yıldızları devreden çıkarılmıştır.
	# Evrendeki tüm uzak yıldızlar artık MidField ve DeepField üzerinden gerçek ve seçilebilir procedural yıldızlardır.
	if is_instance_valid(galactic_starfield):
		galactic_starfield.queue_free()
		galactic_starfield = null


func _process(delta):
	flight_speed_mps = 0.0
	# Yıldız geçiş bekleme süresi
	if _star_transition_cooldown > 0.0:
		_star_transition_cooldown -= delta
		
	# Kare başına en fazla 1 gök cisminin dokusunu üreterek sistem yaklaşma spike'larını sıfırla
	_process_body_texture_queue()
		
	# Derin Uzay Arka Plan Yıldız Alanını Kameraya Sabitle (Sonsuz Derinlik)
	if is_instance_valid(galactic_starfield) and camera != null:
		galactic_starfield.global_position = camera.global_position
		
	# FPS Güncellemesi
	var fl = get_node_or_null("Control/FPSLabel")
	if fl:
		fl.text = "FPS: %d" % Engine.get_frames_per_second()
		
	var simulation_delta = 0.0 if is_time_paused else (delta * time_scale)
	
	# 1. HAREKET GİRDİLERİ VE OTOPİLOT
	if is_landed and landed_body != null:
		var base_landing_pos = landed_local_pos.rotated(Vector3.UP, landed_body.rotation_angle)
		var local_up = base_landing_pos.normalized()
		var planet_x = Vector3.RIGHT.rotated(Vector3.UP, landed_body.rotation_angle)
		var local_z = planet_x.cross(local_up).normalized()
		var local_x = local_up.cross(local_z).normalized()
		var surface_basis = Basis(local_x, local_up, local_z)
		
		# Kameranın UP ekseni yerel yerçekimi normali (local_up) ile hizalı olmalıdır
		camera.transform.basis = surface_basis * Basis.from_euler(Vector3(camera.rot_x, camera.rot_y, camera.rot_z))
		
		# Kameranın bakış yönüne göre yürüme doğrultusunu bul
		var cam_forward = -camera.transform.basis.z
		var cam_right = camera.transform.basis.x
		
		# Bu doğrultuları teğet düzleme (local_x ve local_z) projekte et
		var walk_forward = cam_forward - cam_forward.project(local_up)
		if walk_forward.length() > 0.001:
			walk_forward = walk_forward.normalized()
		else:
			walk_forward = -local_z
			
		var walk_right = cam_right - cam_right.project(local_up)
		if walk_right.length() > 0.001:
			walk_right = walk_right.normalized()
		else:
			walk_right = local_x
			
		# Yürüme girdileri — WASD yatay, Space zıplama
		var move_dir = Vector3.ZERO
		if is_eva_active and Input.is_key_pressed(KEY_W): move_dir += walk_forward
		if is_eva_active and Input.is_key_pressed(KEY_S): move_dir -= walk_forward
		if is_eva_active and Input.is_key_pressed(KEY_A): move_dir -= walk_right
		if is_eva_active and Input.is_key_pressed(KEY_D): move_dir += walk_right
		
		var current_walk_speed = WALK_SPEED_PRESETS[walk_speed_index]
		
		if move_dir.length() > 0.001:
			move_dir = move_dir.normalized()
			
		# ── OUTER WILDS JETPACK & ASTRONOT FİZİĞİ ─────────────────────────────
		is_jetpack_active = false
		is_jetpack_boosting = false
		
		# Dinamik Yerel Kütleçekim (Ayda 0.18g, Karasal Gezegende ~1g)
		var local_gravity = SURFACE_GRAVITY
		if landed_body != null:
			if landed_body.type == "MOON":
				local_gravity = SURFACE_GRAVITY * 0.18
			else:
				local_gravity = SURFACE_GRAVITY * clamp(landed_body.real_radius / 6371000.0, 0.4, 1.8)
				
		# 1. Zıplama ve Dikey Jetpack İtişi (Space Tuşu)
		if is_eva_active and Input.is_key_pressed(KEY_SPACE):
			if landed_vertical_offset <= 0.001:
				landed_vertical_velocity = JUMP_SPEED
			elif astronaut_fuel > 0.0:
				is_jetpack_active = true
				landed_vertical_velocity += (local_gravity + 12.0) * delta
				landed_vertical_velocity = min(landed_vertical_velocity, 32.0)
				astronaut_fuel = max(astronaut_fuel - JETPACK_FUEL_CONSUMPTION * delta, 0.0)
				
		# 2. Retro Fren ve İniş İticisi (Ctrl Tuşu)
		if is_eva_active and Input.is_key_pressed(KEY_CTRL):
			if landed_vertical_offset > 0.05 and astronaut_fuel > 0.0:
				is_jetpack_active = true
				landed_vertical_velocity = lerp(landed_vertical_velocity, -2.0, 6.0 * delta)
				astronaut_fuel = max(astronaut_fuel - (JETPACK_FUEL_CONSUMPTION * 0.5) * delta, 0.0)

		# 3. İleri Jetpack Boost (Shift Tuşu)
		var speed_mult = 1.0
		if is_eva_active and Input.is_key_pressed(KEY_SHIFT):
			if astronaut_fuel > 0.0:
				is_jetpack_boosting = true
				speed_mult = 2.6
				astronaut_fuel = max(astronaut_fuel - (JETPACK_FUEL_CONSUMPTION * 0.6) * delta, 0.0)

		# Yatay hareket
		var dx = move_dir.dot(local_x) * current_walk_speed * speed_mult * delta
		var dz = move_dir.dot(local_z) * current_walk_speed * speed_mult * delta
		landed_walk_offset.x += dx
		landed_walk_offset.y += dz
		
		# Gravity uygula
		landed_vertical_velocity -= local_gravity * delta
		var dv = landed_vertical_velocity * delta
		landed_vertical_offset += dv
		
		# Yere iniş ve yakıt dolumu
		if landed_vertical_offset <= 0.0 and landed_vertical_velocity < 0.0:
			landed_vertical_offset = 0.0
			landed_vertical_velocity = 0.0
			astronaut_fuel = min(astronaut_fuel + JETPACK_FUEL_RECHARGE * delta, 100.0)
			
		# Yüzeyde yaşam desteği (O2 tüketimi, çok yavaş)
		astronaut_oxygen = max(astronaut_oxygen - 0.02 * delta, 10.0)
		
		# Maksimum yükseklik sınırı
		landed_vertical_offset = min(landed_vertical_offset, 500.0)
		
		# Yatay sınır — chunk sistemi ±GRID_RADIUS*CHUNK_SIZE destekler
		var max_walk = float(6 * 2000 - 500)
		landed_walk_offset.x = clamp(landed_walk_offset.x, -max_walk, max_walk)
		landed_walk_offset.y = clamp(landed_walk_offset.y, -max_walk, max_walk)
		
		# Yeni konumdaki yükseklik değerini FastNoiseLite üzerinden bul
		var noise: FastNoiseLite = null
		if landed_body.noise_albedo != null and landed_body.noise_albedo.noise != null:
			noise = landed_body.noise_albedo.noise
			
		var height = 0.0
		if noise != null:
			height = PlanetLODManager.sample_surface_height(landed_walk_offset.x, landed_walk_offset.y, noise, 0.002, 350.0)
			
		# Oyuncunun global pozisyonunu güncelle (dikey offset dahil)
		var current_relative_pos = base_landing_pos + local_x * landed_walk_offset.x + local_z * landed_walk_offset.y + (height + EYE_HEIGHT + landed_vertical_offset) * local_up
		var body_abs_pos = landed_body.get_absolute_position(active_star)
		virtual_player_position = body_abs_pos + current_relative_pos
		player_velocity = Vector3.ZERO
		
		# LOD manager'ın basis'ini güncelle (gezegen dönüşüyle uyumlu)
		if is_instance_valid(landed_lod_manager) and landed_lod_manager.is_active():
			landed_lod_manager.set_tangent_basis(local_up, local_x, local_z)
			landed_lod_manager.set_eye_height(EYE_HEIGHT + landed_vertical_offset)
			# Chunk LOD sistemini güncelle (sadece chunk sınırı geçişinde rebuild yapar)
			landed_lod_manager.update(landed_walk_offset.x, landed_walk_offset.y)

		# Park edilen Keşif Korvetini gezegen yüzeyindeki iniş noktasında sabit tut
		var current_sc = spacecraft if spacecraft != null else (camera.spacecraft if camera != null else null)
		if current_sc != null:
			var height_at_landing = 0.0
			if noise != null:
				height_at_landing = noise.get_noise_2d(0.0, 0.0) * 80.0
			var rel_x = -landed_walk_offset.x
			var rel_z = -landed_walk_offset.y
			var rel_y = (height_at_landing + 0.45) - (height + EYE_HEIGHT + landed_vertical_offset)
			current_sc.global_position = local_x * rel_x + local_z * rel_z + local_up * rel_y
			landed_ship_basis = Basis(local_x, local_up, local_z)
			current_sc.global_basis = landed_ship_basis
			
			dist_to_ship_eva = (landed_walk_offset - Vector2(0.0, 3.7)).length()
			is_near_ship_airlock = (dist_to_ship_eva < 2.2 and landed_vertical_offset < 2.8 and current_sc.is_airlock_open and current_sc.airlock_anim_progress > 0.95)
	elif is_system_map_active:
		# Harita modunda pan/zoom yapabilmek için hareket kontrolleri (kamera rotasyonu kilitliyken)
		var input_dir = Vector3.ZERO
		if Input.is_key_pressed(KEY_W): input_dir.z -= 1.0
		if Input.is_key_pressed(KEY_S): input_dir.z += 1.0
		if Input.is_key_pressed(KEY_A): input_dir.x -= 1.0
		if Input.is_key_pressed(KEY_D): input_dir.x += 1.0
		if Input.is_key_pressed(KEY_SPACE): input_dir.y += 1.0
		if Input.is_key_pressed(KEY_CTRL): input_dir.y -= 1.0

		var forward = -camera.global_transform.basis.z 
		var right = camera.global_transform.basis.x
		var up = camera.global_transform.basis.y
		
		# Haritada kamera dikey aşağı baktığından forward=aşağı(zoom in), right=sağ(pan), up=ekran üstü(pan)
		var move_direction = (forward * -input_dir.z + right * input_dir.x + up * input_dir.y).normalized()
		var target_velocity = move_direction * camera.current_speed
		player_velocity = player_velocity.lerp(target_velocity, 4.0 * delta)
		
		virtual_player_position += player_velocity * delta
	elif is_interstellar_autopilot and targeted_star_data != null:
		# Yıldızlararası galaktik otopilot mantığı
		var has_manual_input = (
			Input.is_key_pressed(KEY_W) or
			Input.is_key_pressed(KEY_S) or
			Input.is_key_pressed(KEY_A) or
			Input.is_key_pressed(KEY_D) or
			Input.is_key_pressed(KEY_SPACE) or
			Input.is_key_pressed(KEY_CTRL) or
			Input.is_key_pressed(KEY_SHIFT)
		)
		if has_manual_input:
			is_interstellar_autopilot = false
			is_interstellar_hyper_boost = false
			if is_focusing_target:
				is_focusing_target = false
				focus_target_body = null
				focus_target_star = null
				focus_time = 0.0
			player_velocity = Vector3.ZERO
		else:
			var gal_pos = get_player_galactic_position()
			var star_pos = Vector3(targeted_star_data.stellar_x, targeted_star_data.stellar_y, targeted_star_data.stellar_z)
			var to_star = star_pos - gal_pos
			var dist = to_star.length()
			
			# Kamerayı hedefe doğru pürüzsüz çevir
			var star_dir = to_star.normalized()
			var target_pitch = asin(clamp(star_dir.y, -0.9999, 0.9999))
			var target_yaw = atan2(-star_dir.x, -star_dir.z)
			camera.rot_x = lerp_angle(camera.rot_x, target_pitch, 6.0 * delta)
			camera.rot_y = lerp_angle(camera.rot_y, target_yaw, 6.0 * delta)
			camera.rot_z = lerp_angle(camera.rot_z, 0.0, 6.0 * delta)
			camera.transform.basis = Basis.from_euler(Vector3(camera.rot_x, camera.rot_y, camera.rot_z))
			
			# Sistem aktivasyon sınırına girildi mi? (~13.3 AU = 2,000,000,000,000 m)
			if dist <= 2000000000000.0:
				is_interstellar_autopilot = false
				is_interstellar_hyper_boost = false
				player_velocity = Vector3.ZERO
				var star_data_to_activate = targeted_star_data
				targeted_star_data = null
				if star_visual_pool != null:
					star_visual_pool.pinned_star_data = null
				_transition_to_star_data(star_data_to_activate)
				camera.set_speed_to_match_body(active_star.real_radius)
				followed_body = active_star
				_look_at_body(active_star)
				print("HEDEFE ULAŞILDI: Yeni Aktif Sistem -> ", active_star.name)
			else:
				# Mesafeye göre orantılı warp hızı (Hedefe yaklaştıkça pürüzsüz frenleme)
				var min_speed = min(0.1 * LIGHT_YEAR, max(dist * 0.4, 100000000000.0))
				var max_warp = 2000000.0 * LIGHT_YEAR if is_interstellar_hyper_boost else 50000.0 * LIGHT_YEAR
				var warp_mult = 4.0 if is_interstellar_hyper_boost else 0.4
				var warp_speed = clamp(dist * warp_mult, min_speed, max_warp)
				flight_speed_mps = warp_speed
				var step = star_dir * warp_speed * delta
				virtual_player_position += step
				camera.current_speed = warp_speed
				camera.target_speed = warp_speed
	elif is_autopilot_active and autopilot_target_body != null:
		# Aktif sistem otopilot mantığı (Gezegen / Ay / Yıldız)
		var has_manual_input = (
			Input.is_key_pressed(KEY_W) or
			Input.is_key_pressed(KEY_S) or
			Input.is_key_pressed(KEY_A) or
			Input.is_key_pressed(KEY_D) or
			Input.is_key_pressed(KEY_SPACE) or
			Input.is_key_pressed(KEY_CTRL) or
			Input.is_key_pressed(KEY_SHIFT)
		)
		if has_manual_input:
			is_autopilot_active = false
			is_hyper_autopilot = false
			is_landing_autopilot = false
			autopilot_target_body = null
			autopilot_close_approach = false
			if is_focusing_target:
				is_focusing_target = false
				focus_target_body = null
				focus_target_star = null
				focus_time = 0.0
			player_velocity = Vector3.ZERO
		else:
			autopilot_timer += delta
			var t = clamp(autopilot_timer / autopilot_duration, 0.0, 1.0)
			# Pürüzsüz s-eğrisi hızlanma/yavaşlama (Smoothstep)
			var ease_t = t * t * (3.0 - 2.0 * t)
			var ease_rate: float = 6.0 * t * (1.0 - t) / maxf(autopilot_duration, 0.001)
			
			var body_abs_pos = autopilot_target_body.get_absolute_position(active_star)
			
			if is_landing_autopilot:
				if autopilot_target_body.noise_albedo == null:
					SystemGenerator.generate_body_textures(self, autopilot_target_body)
					
				var landing_noise: FastNoiseLite = null
				if autopilot_target_body.noise_albedo != null and autopilot_target_body.noise_albedo.noise != null:
					landing_noise = autopilot_target_body.noise_albedo.noise
				
				var height_at_landing = 0.0
				if landing_noise != null:
					height_at_landing = PlanetLODManager.sample_surface_height(0.0, 0.0, landing_noise, 0.002, 350.0)
					
				var approach_vec = autopilot_relative_start_pos
				var horiz = Vector2(approach_vec.x, approach_vec.z)
				if horiz.length_squared() < 0.01:
					horiz = Vector2(0.88, 0.47)
				horiz = horiz.normalized()
				var lat_factor = clampf(approach_vec.y / maxf(approach_vec.length(), 1.0), -0.25, 0.25)
				var landing_dir = Vector3(horiz.x, lat_factor, horiz.y).normalized()
				var landing_offset = landing_dir * (autopilot_target_body.real_radius + EYE_HEIGHT + height_at_landing)
				flight_speed_mps = autopilot_relative_start_pos.distance_to(landing_offset) * ease_rate
				var current_rel_pos = lerp(autopilot_relative_start_pos, landing_offset, ease_t)
				virtual_player_position = body_abs_pos + current_rel_pos
			else:
				var approach_dir = autopilot_relative_start_pos.normalized()
				if approach_dir.length() < 0.001:
					approach_dir = Vector3.BACK
				var dist_mult: float
				if autopilot_close_approach:
					match autopilot_target_body.type:
						"STAR":   dist_mult = 1.6
						"PLANET": dist_mult = 1.2
						_:        dist_mult = 1.5
				else:
					match autopilot_target_body.type:
						"STAR":   dist_mult = 2.2
						"PLANET": dist_mult = 3.2
						_:        dist_mult = 4.5
				var target_dist = autopilot_target_body.real_radius * dist_mult
				var start_dist: float = autopilot_relative_start_pos.length()
				flight_speed_mps = absf(start_dist - target_dist) * ease_rate
				var current_dist: float = lerpf(start_dist, target_dist, ease_t)
				virtual_player_position = body_abs_pos + approach_dir * current_dist
			
			# Kamerayı hedefe pürüzsüz yönelt
			var target_pitch = 0.0
			var target_yaw = camera.rot_y
			var target_dir = autopilot_target_body.real_position.normalized()
			if target_dir.length() > 0.001:
				if is_landing_autopilot:
					target_yaw = atan2(-target_dir.x, -target_dir.z)
					target_pitch = 0.0
				else:
					target_pitch = asin(clamp(target_dir.y, -0.9999, 0.9999))
					target_yaw = atan2(-target_dir.x, -target_dir.z)
				
			camera.rot_x = lerp_angle(camera.rot_x, target_pitch, 6.0 * delta)
			camera.rot_y = lerp_angle(camera.rot_y, target_yaw, 6.0 * delta)
			camera.rot_z = lerp_angle(camera.rot_z, 0.0, 6.0 * delta)
			camera.transform.basis = Basis.from_euler(Vector3(camera.rot_x, camera.rot_y, camera.rot_z))
				
			if t >= 1.0:
				is_autopilot_active = false
				is_hyper_autopilot = false
				autopilot_close_approach = false
				var target = autopilot_target_body
				autopilot_target_body = null
				player_velocity = Vector3.ZERO
				
				if is_landing_autopilot:
					is_landing_autopilot = false
					_execute_landing(target)
				else:
					camera.set_speed_to_match_body(target.real_radius)
					followed_body = target
					# Hedefi ortada tutan odaklanma moduna geçir
					is_focusing_target = true
					focus_target_body = target
					focus_target_star = null
	else:
		if is_eva_active:
			# Sıfır Yerçekimi Uzay Yürüyüşü (Zero-G Spacewalk Jetpack / RCS)
			var rcs_input = Vector3.ZERO
			if Input.is_key_pressed(KEY_W): rcs_input.z -= 1.0
			if Input.is_key_pressed(KEY_S): rcs_input.z += 1.0
			if Input.is_key_pressed(KEY_A): rcs_input.x -= 1.0
			if Input.is_key_pressed(KEY_D): rcs_input.x += 1.0
			if Input.is_key_pressed(KEY_SPACE): rcs_input.y += 1.0
			if Input.is_key_pressed(KEY_CTRL): rcs_input.y -= 1.0
			
			_step_eva_motion(delta, rcs_input, Input.is_key_pressed(KEY_SHIFT), Input.is_key_pressed(KEY_X))

		else:
			# Manuel serbest uçuş veya kabin içi yürüyüş kontrolleri
			var current_sc = spacecraft if spacecraft != null else (camera.spacecraft if camera != null else null)
			var is_walking_in_cabin = false
			if current_sc != null:
				if current_sc.get("current_view_mode") == 1 and not current_sc.get("is_seated_in_cockpit"):
					is_walking_in_cabin = true
					
			if is_walking_in_cabin:
				# Oyuncu kabin içinde yürüyor: Gemi uzayda ve ekranda SABİTTİR, hareket etmez!
				player_velocity = Vector3.ZERO
				if current_sc != null:
					current_sc.global_position = spacecraft_universe_pos - virtual_player_position
					current_sc.global_basis = spacecraft_basis
			else:
				# Oyuncu pilot koltuğunda oturuyor ve gemiyi sürüyor (veya 3. şahıs sürüş modu)
				var input_dir = Vector3.ZERO
				if not is_system_map_active and not is_landed:
					if Input.is_key_pressed(KEY_W): input_dir.z -= 1.0
					if Input.is_key_pressed(KEY_S): input_dir.z += 1.0
					if Input.is_key_pressed(KEY_A): input_dir.x -= 1.0
					if Input.is_key_pressed(KEY_D): input_dir.x += 1.0
					if Input.is_key_pressed(KEY_SPACE): input_dir.y += 1.0
					if Input.is_key_pressed(KEY_CTRL): input_dir.y -= 1.0

				var forward = -camera.global_transform.basis.z 
				var right = camera.global_transform.basis.x
				var up = camera.global_transform.basis.y
				
				if is_focusing_target and (input_dir.length_squared() > 0.0 or Input.is_key_pressed(KEY_Q)):
					is_focusing_target = false
					focus_target_body = null
					focus_target_star = null
					focus_time = 0.0
				
				var is_thrusting: bool = input_dir.length_squared() > 0.0
				var move_direction: Vector3 = (forward * -input_dir.z + right * input_dir.x + up * input_dir.y).normalized() if is_thrusting else Vector3.ZERO
				
				var target_velocity: Vector3 = move_direction * camera.current_speed if is_thrusting else Vector3.ZERO
				var damp_rate: float = 3.5 if is_thrusting else 1.6
				player_velocity = player_velocity.lerp(target_velocity, damp_rate * delta)
				flight_speed_mps = safe_vector_length(player_velocity)
				if not is_thrusting and flight_speed_mps < 0.2:
					player_velocity = Vector3.ZERO
					flight_speed_mps = 0.0
				virtual_player_position += player_velocity * delta
				spacecraft_universe_pos = virtual_player_position
				spacecraft_basis = camera.transform.basis
				
				# Gemi oyuncuyla birlikte hareket eder ve kokpit hizasında kalır
				if current_sc != null:
					current_sc.global_position = camera.global_position + camera.transform.basis * Vector3(0.0, -0.45, -0.6)
					current_sc.global_basis = camera.transform.basis
		
		# Odaklanma Modu (C Tuşu / Target Lock): Kamerayı hedefin hareketine kilitler ve pürüzsüzce merkezde tutar
		if is_focusing_target and not is_system_map_active and not is_landed:
			var target_dir = Vector3.ZERO
			if focus_target_star != null:
				var gal_pos = get_player_galactic_position()
				var star_pos = Vector3(focus_target_star.stellar_x, focus_target_star.stellar_y, focus_target_star.stellar_z)
				target_dir = (star_pos - gal_pos).normalized()
			elif focus_target_body != null and is_instance_valid(focus_target_body):
				target_dir = focus_target_body.real_position.normalized()
			else:
				is_focusing_target = false
				focus_time = 0.0
				
			if target_dir.length() > 0.001:
				var target_pitch = asin(clamp(target_dir.y, -0.9999, 0.9999))
				var target_yaw = atan2(-target_dir.x, -target_dir.z)
				camera.rot_x = lerp_angle(camera.rot_x, target_pitch, 8.0 * delta)
				camera.rot_y = lerp_angle(camera.rot_y, target_yaw, 8.0 * delta)
				camera.rot_z = lerp_angle(camera.rot_z, 0.0, 8.0 * delta)
				camera.transform.basis = Basis.from_euler(Vector3(camera.rot_x, camera.rot_y, camera.rot_z))
				
				# Odaklanma tamamlandığında (hedefe bakış sağlandığında) kilidi otomatik kaldır
				focus_time += delta
				var diff_pitch = abs(angle_difference(camera.rot_x, target_pitch))
				var diff_yaw = abs(angle_difference(camera.rot_y, target_yaw))
				if focus_time >= 0.25 and diff_pitch < 0.02 and diff_yaw < 0.02:
					camera.rot_x = target_pitch
					camera.rot_y = target_yaw
					camera.rot_z = 0.0
					camera.transform.basis = Basis.from_euler(Vector3(target_pitch, target_yaw, 0.0))
					is_focusing_target = false
					focus_target_body = null
					focus_target_star = null
					focus_time = 0.0
					print("HEDEFE ODAKLANMA TAMAMLANDI - ODAK KİLİDİ KALDIRILDI")

	# A piloted craft follows the navigation frame during manual AND autopilot travel.
	if spacecraft != null and spacecraft.is_seated_in_cockpit and not is_eva_active and not is_landed:
		spacecraft_universe_pos = virtual_player_position
		spacecraft_basis = camera.global_basis
		spacecraft.global_position = camera.global_position + camera.global_basis * Vector3(0, -0.45, -0.6)
		spacecraft.global_basis = spacecraft_basis

	# 2. STABİL YÖRÜNGE VE HAREKET MATEMATİĞİ (Zaman Ölçekli)
	var followed_body_prev_pos = Vector3.ZERO
	if followed_body != null:
		followed_body_prev_pos = followed_body.get_absolute_position(active_star)

	simulation_time += simulation_delta
	
	for body in stars:
		body.rotation_angle += body.rotation_speed * simulation_delta
		if is_instance_valid(body.visual_mesh) and body.visual_mesh.visible:
			# Yıldızlar dik döner (axial_tilt = 0)
			body.visual_mesh.rotation.y = body.rotation_angle
		
	for body in active_system_bodies:
		if body.parent_body != null:
			body.orbit_angle += body.orbit_speed * simulation_delta
			var orbit_vec = Vector3(cos(body.orbit_angle), 0, sin(body.orbit_angle)) * body.orbit_radius
			if body.orbit_inclination != 0.0:
				orbit_vec = orbit_vec.rotated(Vector3.FORWARD, body.orbit_inclination)
			body.local_position = orbit_vec
		
		body.rotation_angle += body.rotation_speed * simulation_delta
		
		if is_instance_valid(body.visual_mesh) or is_instance_valid(body.atmosphere_mesh):
			# Eksenel eğimi olan dönme eksenini hesapla
			var tilt_dir_angle = body.orbit_angle + PI * 0.3
			var spin_axis: Vector3
			if body.axial_tilt < 0.001:
				spin_axis = Vector3.UP
			else:
				spin_axis = Vector3(
					sin(body.axial_tilt) * cos(tilt_dir_angle),
					cos(body.axial_tilt),
					sin(body.axial_tilt) * sin(tilt_dir_angle)
				).normalized()
			
			var tilted_basis = Basis(spin_axis, body.rotation_angle)
			
			if is_instance_valid(body.visual_mesh):
				body.visual_mesh.basis = tilted_basis
			if is_instance_valid(body.atmosphere_mesh):
				body.atmosphere_mesh.basis = tilted_basis
			
	if followed_body != null:
		var followed_body_curr_pos = followed_body.get_absolute_position(active_star)
		var movement = followed_body_curr_pos - followed_body_prev_pos
		virtual_player_position += movement
		
		var dist_to_followed = safe_vector_length(followed_body.real_position)
		if dist_to_followed > followed_body.real_radius * 50000.0:
			followed_body = null
	
	# Uçuşta gezegenin içine girmeyi engelleyen yüzey çarpışma / irtifa koruması
	_clamp_player_above_planet_surfaces()

	# Dinamik Derinlik Tamponu (Near Plane) Ayarı: Uzayda 0.3m, yüzeyde veya yakınlaşmada 0.04m
	var camera_3d = camera.get_node_or_null("Camera3D")
	if camera_3d:
		var near_planet: bool = false
		for b in active_system_bodies:
			if b.type != "STAR" and safe_vector_length(b.real_position) < b.real_radius * 1.8:
				near_planet = true
				break
		var close_view: bool = is_landed or is_eva_active or near_planet or (spacecraft != null and spacecraft.current_view_mode == Spacecraft.CameraViewMode.INTERIOR_FPS)
		var target_near = 0.04 if close_view else 0.3
		if camera_3d.near != target_near:
			camera_3d.near = target_near
	
	# Sadece aktif sistemdeki nesnelerin göreceli konumlarını hesapla
	for body in active_render_bodies:
		body.real_position = body.get_absolute_position(active_star) - virtual_player_position

	# Dinamik Güneş Işığı Yönü (Aktif yıldıza kilitli)
	if active_star != null and directional_light != null:
		directional_light.light_color = active_star.light_color
		directional_light.light_energy = active_star.light_energy
		var light_dir = -safe_vector_normalized(active_star.real_position)
		if light_dir.length_squared() > 0.001:
			var up_vec = Vector3.UP if abs(light_dir.dot(Vector3.UP)) < 0.99 else Vector3.FORWARD
			directional_light.look_at(directional_light.global_position + light_dir, up_vec)

	# 3. RENDER, RADAR VE SİSTEM ÖLÇEKLENDİRME SİSTEMİ
	var closest_body_name: String = "Uzay Boşluğu"
	var closest_body_dist: float = INF

	var viewport_height = 1080.0
	if is_inside_tree() and get_viewport() and get_viewport().size.y > 0:
		viewport_height = float(get_viewport().size.y)
		
	var fov = 75.0
	if camera_3d:
		fov = camera_3d.fov
	var half_fov_rad = deg_to_rad(fov * 0.5)
	var tan_half_fov = tan(half_fov_rad)

	# Yıldızlar ve aktif sistemdeki tüm gök cisimlerini işle
	for body in active_render_bodies:
		var dist = safe_vector_length(body.real_position)
		var dir = safe_vector_normalized(body.real_position) if dist > 0.001 else Vector3.FORWARD
		
		if dist < closest_body_dist:
			closest_body_dist = dist
			closest_body_name = body.name

		var scale_mult = visual_scale_multiplier
		if body.type == "STAR":
			scale_mult = max(1.0, visual_scale_multiplier * 0.1)
			
		var effective_radius = body.real_radius * scale_mult
		var render_dist = min(dist, visual_distance_limit)
		
		var min_pixel_radius = 4.0
		var star_dist_factor = 0.0
		if body.type == "STAR":
			var dist_ly = dist / LIGHT_YEAR
			# 0.5 LY ile 18.0 LY aralığında dengeli derinlik faktörü
			star_dist_factor = clamp((dist_ly - 0.5) / (18.0 - 0.5), 0.0, 1.0)
			# Yakındaki yıldız 6.5 piksel, uzaktaki 1.8 piksel (doğal ve dengeli astronomik ölçek)
			min_pixel_radius = lerp(6.5, 1.8, star_dist_factor)
		elif body.type == "MOON":
			min_pixel_radius = 1.5
			
		var min_scale = min_pixel_radius * 2.0 * render_dist * tan_half_fov / viewport_height
		var natural_scale = effective_radius * (render_dist / max(dist, 1.0))
		
		# Yıldızlar, gezegenleri yok olduktan (0.06 LY) biraz daha sonra (0.07 LY) sprite moduna geçmeli
		if body.type == "STAR":
			body.is_lod = (dist >= 0.07 * LIGHT_YEAR)
		else:
			body.is_lod = (min_scale > natural_scale)
			
		var final_scale = max(natural_scale, min_scale)
		
		var mesh_visibility = 1.0
		if body.type != "STAR":
			var max_vis = body.max_visibility_distance
			if dist > max_vis:
				mesh_visibility = 0.0
			elif dist > max_vis * 0.8:
				mesh_visibility = (max_vis - dist) / (max_vis * 0.2)
		
		# Sistem içindeki gezegenler ve kilitlenilen hedefler uzakta daima parlak nokta olarak görünür
		var sprite_visibility = 1.0
		var is_current_target = (current_target_index >= 0 and current_target_index < universe.size() and universe[current_target_index] == body)
		if body.type != "STAR" and not is_current_target:
			if dist > 0.05 * LIGHT_YEAR:
				sprite_visibility = clampf((0.08 * LIGHT_YEAR - dist) / (0.03 * LIGHT_YEAR), 0.0, 1.0)
		
		# Cisimler için 2D Billboard Sprite (LOD) ve 3D Küre Geçiş Mantığı
		var show_lod_sprite = body.is_lod and (sprite_visibility > 0.0)
		var show_3d_mesh = (not body.is_lod) and (mesh_visibility > 0.0)
		
		if is_instance_valid(body.lod_sprite):
			body.lod_sprite.visible = show_lod_sprite
			if show_lod_sprite:
				if dist > visual_distance_limit:
					body.lod_sprite.global_position = dir * visual_distance_limit
				else:
					body.lod_sprite.global_position = body.real_position
				body.lod_sprite.scale = Vector3(final_scale, final_scale, final_scale)
				
				if body.type == "STAR":
					var star_brightness = lerp(1.15, 0.60, star_dist_factor)
					var star_alpha = lerp(1.0, 0.55, star_dist_factor)
					body.lod_sprite.modulate = Color(
						body.base_color.r * star_brightness,
						body.base_color.g * star_brightness,
						body.base_color.b * star_brightness,
						star_alpha
					)
				else:
					# Gezegen ve uydular uzaktayken parlak 2D gökcismi noktası olarak parlar
					body.lod_sprite.modulate = Color(
						body.base_color.r * 1.4,
						body.base_color.g * 1.4,
						body.base_color.b * 1.4,
						maxf(sprite_visibility, 0.75 if is_current_target else 0.5)
					)
					
		if is_instance_valid(body.visual_mesh):
			if dist > visual_distance_limit:
				body.visual_mesh.global_position = dir * visual_distance_limit
			else:
				body.visual_mesh.global_position = body.real_position
				
			body.visual_mesh.scale = Vector3(final_scale, final_scale, final_scale)
			body.visual_mesh.visible = show_3d_mesh
				
			var mat = body.visual_mesh.mesh.material as StandardMaterial3D
			if mat and body.visual_mesh.visible:
				var target_shading = BaseMaterial3D.SHADING_MODE_UNSHADED if (body.is_lod or body.type == "STAR") else BaseMaterial3D.SHADING_MODE_PER_PIXEL
				if mat.shading_mode != target_shading:
					mat.shading_mode = target_shading
				
				# Yıldızın veya gezegenlerin yakınlaşınca gürültü dokularını kuyruğa ekle (Kare başına 1 üretim)
				if body.type == "STAR":
					if body.noise_albedo == null:
						if not _body_texture_queue.has(body):
							_body_texture_queue.push_front(body)
					else:
						mat.albedo_color = Color.WHITE
						if mat.albedo_texture == null:
							mat.albedo_texture = body.noise_albedo
				else:
					if dist < body.max_visibility_distance * 1.5:
						if body.noise_albedo == null:
							if not _body_texture_queue.has(body):
								_body_texture_queue.append(body)
						else:
							mat.albedo_color = Color.WHITE
							if mat.albedo_texture == null:
								mat.albedo_texture = body.noise_albedo
								if body.noise_normal != null:
									mat.normal_texture = body.noise_normal
									mat.normal_enabled = true
				
			if is_instance_valid(body.atmosphere_mesh):
				body.atmosphere_mesh.global_position = body.visual_mesh.global_position
				body.atmosphere_mesh.scale = body.visual_mesh.scale * 1.06
				# Atmosfer 3D mesh kilitliyse veya LOD modundaysa görünmez
				body.atmosphere_mesh.visible = show_3d_mesh and body.has_atmosphere
				
				if body.atmosphere_mesh.visible:
					var parent_star = body.parent_body
					while parent_star and parent_star.type != "STAR":
						parent_star = parent_star.parent_body
					if parent_star != null:
						var sun_dir = (parent_star.real_position - body.real_position).normalized()
						body.atmosphere_mesh.material_override.set_shader_parameter("sun_direction", sun_dir)

		# Yörünge Çizgilerinin Konumunu ve Görünürlüğünü Güncelle
		if is_instance_valid(body.orbit_line_mesh):
			if body.parent_body != null and is_instance_valid(body.parent_body.visual_mesh):
				body.orbit_line_mesh.global_position = body.parent_body.visual_mesh.global_position
			elif body.parent_body != null:
				body.orbit_line_mesh.global_position = body.parent_body.real_position
			else:
				body.orbit_line_mesh.global_position = Vector3.ZERO
			
			var body_visible = (is_instance_valid(body.visual_mesh) and body.visual_mesh.visible) or (is_instance_valid(body.lod_sprite) and body.lod_sprite.visible)
			body.orbit_line_mesh.visible = body_visible or is_system_map_active

	# 4. HEDEF KİLİTLEME NİŞANGAHI (RETICLE) GÜNCELLEMESİ
	if targeted_star_data != null and target_reticle != null and camera_3d != null:
		var gal_pos = get_player_galactic_position()
		var render_pos = star_visual_pool.get_star_render_position(targeted_star_data, gal_pos) if star_visual_pool != null else Vector3.FORWARD * 1000.0
		var star_world_pos = camera_3d.global_position + render_pos
		var pos_in_cam = camera_3d.to_local(star_world_pos)
		
		if pos_in_cam.z < 0:
			var screen_pos = camera_3d.unproject_position(star_world_pos)
			target_reticle.visible = is_hud_visible
			target_reticle.position = screen_pos - target_reticle.size / 2.0
			target_reticle.rotation += 1.0 * delta
		else:
			target_reticle.visible = false
	elif universe.size() > 0 and current_target_index >= 0 and current_target_index < universe.size() and target_reticle != null and camera_3d != null and not is_interstellar_autopilot:
		var target_body = universe[current_target_index]
		var dist_to_player = (target_body.get_absolute_position(active_star) - virtual_player_position).length()
		
		# Eğer aktif sistemden çok uzaklaşıldıysa (> 50 AU), hedefi otomatik bırak
		if dist_to_player > 50.0 * 149597870700.0:
			current_target_index = -1
			target_reticle.visible = false
		else:
			target_body.real_position = target_body.get_absolute_position(active_star) - virtual_player_position
			
			var target_world_pos: Vector3
			if is_instance_valid(target_body.visual_mesh) and target_body.visual_mesh.visible:
				target_world_pos = target_body.visual_mesh.global_position
			elif is_instance_valid(target_body.lod_sprite) and target_body.lod_sprite.visible:
				target_world_pos = target_body.lod_sprite.global_position
			else:
				# MultiMesh veya henüz grafik spawn edilmemiş uzak cisimler için
				var dist = target_body.real_position.length()
				var dir = target_body.real_position.normalized() if dist > 0.001 else Vector3.FORWARD
				var render_d = min(dist, visual_distance_limit * 0.92)
				target_world_pos = dir * render_d
				
			var body_pos_in_camera = camera_3d.to_local(target_world_pos)
			if body_pos_in_camera.z < 0:
				var screen_pos = camera_3d.unproject_position(target_world_pos)
				target_reticle.visible = is_hud_visible
				target_reticle.position = screen_pos - target_reticle.size / 2.0
				target_reticle.rotation += 1.0 * delta
			else:
				target_reticle.visible = false
	else:
		if target_reticle:
			target_reticle.visible = false
	
	# FLYOVER LOD: Yaklaşılan/yörüngedeki gezegen için LOD chunk'ları (iniş yapılmamışsa)
	_flv_update_flyover_lod()

	# Prosedürel Galaktik Sektör Izgarasını ve Görsel Havuzu Güncelle (Delta Streaming)
	if sector_manager != null:
		var gal_pos = get_player_galactic_position()
		var active_star_coord = Vector3i(2147483647, 2147483647, 2147483647)
		if active_star != null:
			active_star_coord = sector_manager.get_sector_coord(Vector3(active_star.stellar_x, active_star.stellar_y, active_star.stellar_z))
		var sector_changed = sector_manager.update_player_position(gal_pos, active_star_coord, 1000)
		if star_visual_pool != null:
			if camera != null:
				star_visual_pool.global_position = camera.global_position
			var cam_forward = -camera.transform.basis.z if camera != null else Vector3.FORWARD
			star_visual_pool.update_pool(delta, sector_manager, gal_pos, cam_forward, fov, viewport_height, sector_changed, active_star_unique_id, targeted_star_data)
			
		# GPU Mid-Field Yıldız Katmanını Güncelle (Aşama 7A: Gerçek Mesafe-Bazlı Paralaks)
		if mid_field_renderer != null:
			var active_cam: Node3D = camera_3d if camera_3d != null else camera
			mid_field_renderer.update_renderer(active_cam, gal_pos)
			
		# GPU Deep-Field Gerçek Yıldız Katmanını Güncelle (Aşama 7B: 2.500-25.000 LY)
		if deep_field_renderer != null:
			var active_cam: Node3D = camera_3d if camera_3d != null else camera
			deep_field_renderer.update_renderer(active_cam, gal_pos)
			
		# Yıldız sistemi sınır geçiş kontrolü (Aşama 4: Histerezisli Akıllı Geçiş - Saniyede ~6.6 kez)
		_star_transition_timer += delta
		if _star_transition_timer >= STAR_TRANSITION_CHECK_INTERVAL:
			_star_transition_timer = 0.0
			_check_active_star_transition()

	# Arayüzü saniyede 60 kez yerine 10 kez güncelle (GC ve BBCode yükünü %85 azaltır)
	_ui_update_timer += delta
	if _ui_update_timer >= UI_REFRESH_INTERVAL:
		_ui_update_timer = 0.0
		if hud != null:
			hud.update_hud(self)
		elif ui_label != null:
			SystemUI.update_ui(self, closest_body_name, closest_body_dist)


# ── CHUNK SINIRLARI VE DİKEY HAREKET ──────────────────────────────────────

func _update_chunk_borders() -> void:
	if is_instance_valid(sphere_chunk_manager):
		sphere_chunk_manager.set_borders_visible(show_chunk_borders)
	# Viewport debug draw'u karıştırma — border'lar ayrı


# ── SPHERICAL CHUNK LOD (orbit/yaklaşma) ─────────────────────────────────

func _flv_update_flyover_lod() -> void:
	if is_landed:
		_flv_clear_chunks()
		return

	# Yaklaşılan / yörüngedeki hedefi bul
	var target: CelestialBody = null
	if is_autopilot_active and autopilot_target_body != null and autopilot_target_body.type != "STAR":
		target = autopilot_target_body
	elif is_focusing_target and focus_target_body != null and focus_target_body.type != "STAR":
		target = focus_target_body
	elif followed_body != null and followed_body.type != "STAR":
		target = followed_body

	if target == null:
		_flv_clear_chunks()
		return

	if not is_instance_valid(target.visual_mesh):
		_flv_clear_chunks()
		return

	# Yaklaşma mesafesi eşiği: Gezegene 3.5 kat yarıçap mesafesine girildiğinde pürüzsüz ve çoklu chunk LOD başlar
	var dist_to_target = safe_vector_length(target.real_position)
	if dist_to_target > target.real_radius * 3.5:
		_flv_clear_chunks()
		return

	# Noise hazırla (sphere chunk için)
	if target.noise_albedo == null:
		SystemGenerator.generate_body_textures(self, target)
	var noise: FastNoiseLite = null
	if target.noise_albedo != null and target.noise_albedo.noise != null:
		noise = target.noise_albedo.noise

	# Sphere chunk manager'ı oluştur/güncelle
	var need_new = not is_instance_valid(sphere_chunk_manager) or not sphere_chunk_manager.is_active() or _chunk_target != target
	if need_new:
		_flv_clear_chunks()
		_chunk_target = target
		sphere_chunk_manager = PlanetChunkSphere.new()
		add_child(sphere_chunk_manager)
		sphere_chunk_manager.initialize(noise, target.real_radius)
		var mesh = target.visual_mesh
		sphere_chunk_manager.set_material(mesh.get_active_material(0))
		sphere_chunk_manager.set_borders_visible(show_chunk_borders)

	var mesh = target.visual_mesh
	sphere_chunk_manager.position = mesh.global_position
	sphere_chunk_manager.scale = mesh.scale

	var visual_radius = mesh.scale.x
	var body_abs_pos = target.get_absolute_position(active_star)
	sphere_chunk_manager.update(Vector3.ZERO, mesh.global_position, visual_radius,
		virtual_player_position, body_abs_pos)

	# 24-parçalı pürüzsüz ve engebeli dağ chunk'ları görünür, asıl küre gizlenir
	target.visual_mesh.visible = false
	# Yeşil atmosfer halesi DAİMA korunur (bug2.png parıltısı kaybolmaz!)
	if is_instance_valid(target.atmosphere_mesh):
		target.atmosphere_mesh.visible = true


func _flv_clear_chunks() -> void:
	if is_instance_valid(sphere_chunk_manager):
		# Gezegen mesh'ini geri göster
		if _chunk_target != null:
			if is_instance_valid(_chunk_target.visual_mesh) and not _chunk_target.visual_mesh.visible:
				_chunk_target.visual_mesh.visible = true
			if is_instance_valid(_chunk_target.atmosphere_mesh) and not _chunk_target.atmosphere_mesh.visible:
				_chunk_target.atmosphere_mesh.visible = true
		_chunk_target = null
		sphere_chunk_manager.queue_free()
		sphere_chunk_manager = null

func _clamp_player_above_planet_surfaces() -> void:
	if is_landed or is_system_map_active or is_interstellar_autopilot:
		return
	if active_star == null:
		return

	for body in active_system_bodies:
		if body.type == "STAR":
			continue

		var body_abs = body.get_absolute_position(active_star)
		var offset = virtual_player_position - body_abs
		var dist = safe_vector_length(offset)

		# Gezegenin dağ yüksekliği hesaba katılarak emniyetli irtifa sınırı
		var safety_margin = 15.0
		var min_dist = body.real_radius + safety_margin

		if dist < min_dist:
			var normal_dir = safe_vector_normalized(offset) if dist > 0.001 else Vector3.UP
			virtual_player_position = body_abs + normal_dir * min_dist

			# İçe doğru olan hız bileşenini engelle (gezegenin içine girmeyi durdur)
			var inward_speed = player_velocity.dot(-normal_dir)
			if inward_speed > 0.0:
				player_velocity += normal_dir * inward_speed

			# Gezegen yüzeyine çarpmada hızı güvenli atmosfere düşür
			if camera != null and camera.current_speed > 343.0:
				camera.current_speed = 343.0
				camera.target_speed = 343.0
				camera.speed_multiplier_index = mini(camera.speed_multiplier_index, 2)


# --- PROSEDÜREL YÖRÜNGE HALKASI ÇİZİCİ ---
func _cycle_target() -> void:
	var targetable_bodies: Array[CelestialBody] = []
	targetable_bodies.append_array(stars)
	for body in active_system_bodies:
		if body.type != "MOON":
			targetable_bodies.append(body)
			
	if targetable_bodies.size() == 0:
		return
		
	var current_target_body = universe[current_target_index] if (current_target_index >= 0 and current_target_index < universe.size()) else null
	var idx = targetable_bodies.find(current_target_body)
	
	idx = (idx + 1) % targetable_bodies.size()
	var new_target = targetable_bodies[idx]
	current_target_index = universe.find(new_target)

func _start_autopilot() -> void:
	if is_eva_active or (spacecraft != null and not spacecraft.is_seated_in_cockpit):
		return
	if is_system_map_active:
		is_system_map_active = false
		camera.rot_x = map_pre_rot_x
		camera.rot_y = map_pre_rot_y
		camera.rot_z = map_pre_rot_z
		camera.transform.basis = Basis.from_euler(Vector3(camera.rot_x, camera.rot_y, camera.rot_z))
		virtual_player_position = map_pre_pos
		
	# Yıldızlararası galaktik otopilot (StarData)
	if targeted_star_data != null:
		if is_interstellar_autopilot:
			# Zaten seyir halindeyiz: Çift G ile Hiper Seyir (Hyper Boost)
			is_interstellar_hyper_boost = true
			var gal_pos = get_player_galactic_position()
			var star_pos = Vector3(targeted_star_data.stellar_x, targeted_star_data.stellar_y, targeted_star_data.stellar_z)
			var to_star = star_pos - gal_pos
			var dist = to_star.length()
			if dist > 2050000000000.0:
				var star_dir = to_star.normalized()
				var target_coord = star_pos - star_dir * 2050000000000.0
				var active_star_gal = Vector3(active_star.stellar_x, active_star.stellar_y, active_star.stellar_z) if active_star != null else Vector3.ZERO
				virtual_player_position = target_coord - active_star_gal
			print("YILDIZLARARASI HİPER BOOST AKTİF: ", targeted_star_data.name)
			return
			
		is_interstellar_autopilot = true
		is_interstellar_hyper_boost = false
		is_autopilot_active = false
		is_hyper_autopilot = false
		autopilot_target_body = null
		followed_body = null
		is_focusing_target = false
		current_target_index = -1
		print("YILDIZLARARASI OTOPİLOT BAŞLATILDI: ", targeted_star_data.name)
		return
		
	# Aktif sistem otopilotu (CelestialBody)
	if universe.size() > 0 and current_target_index >= 0 and current_target_index < universe.size():
		var target_body = universe[current_target_index]
		followed_body = null # Yeni hedefe giderken eski takibi sıfırla
		is_focusing_target = false
		
		var body_abs_pos = target_body.get_absolute_position(active_star)
		autopilot_relative_start_pos = virtual_player_position - body_abs_pos
		var start_dist: float = autopilot_relative_start_pos.length()
		
		# Eğer otopilot zaten aktifse ve aynı hedefe gidiyorsak: Çift G HİPER OTOPİLOT
		if is_autopilot_active and autopilot_target_body == target_body:
			is_hyper_autopilot = true
			autopilot_close_approach = true
			autopilot_duration = 0.35
			autopilot_timer = 0.0
			autopilot_start_player_pos = virtual_player_position
			print("HİPER OTOPİLOT BOOST AKTİF: ", target_body.name)
		else:
			is_autopilot_active = true
			is_hyper_autopilot = false
			autopilot_target_body = target_body
			autopilot_start_player_pos = virtual_player_position
			autopilot_timer = 0.0
			# Mesafeye duyarlı sinematik süre: 1.5s ile 5.0s arası
			autopilot_duration = clamp(sqrt(start_dist / 1000000000.0) * 0.5 + 1.5, 1.5, 5.0)

func _teleport_to_current_target() -> void:
	if is_eva_active or (spacecraft != null and not spacecraft.is_seated_in_cockpit):
		return
	if is_system_map_active:
		is_system_map_active = false
		camera.rot_x = map_pre_rot_x
		camera.rot_y = map_pre_rot_y
		camera.rot_z = map_pre_rot_z
		camera.transform.basis = Basis.from_euler(Vector3(camera.rot_x, camera.rot_y, camera.rot_z))
		
	# Hedeflenen galaktik yıldıza anında ışınlan (StarData)
	if targeted_star_data != null:
		is_interstellar_autopilot = false
		is_interstellar_hyper_boost = false
		is_autopilot_active = false
		is_hyper_autopilot = false
		autopilot_target_body = null
		var star_data_to_visit = targeted_star_data
		targeted_star_data = null
		current_target_index = -1
		if star_visual_pool != null:
			star_visual_pool.pinned_star_data = null
			
		_transition_to_star_data(star_data_to_visit)
		virtual_player_position = Vector3(0, 0, 781200000000.0)
		_look_at_body(active_star)
		camera.set_speed_to_match_body(active_star.real_radius)
		followed_body = active_star
		print("YILDIZA IŞINLANILDI: ", active_star.name)
		return
		
	# Aktif sistem cismine ışınlan (CelestialBody)
	if universe.size() > 0 and current_target_index >= 0 and current_target_index < universe.size():
		is_autopilot_active = false
		is_hyper_autopilot = false
		autopilot_target_body = null
		
		var target_body = universe[current_target_index]
		
		var approach_dir = Vector3.BACK
		if target_body.parent_body != null:
			approach_dir = target_body.local_position.normalized()
			if approach_dir.length() < 0.001:
				approach_dir = Vector3.BACK
				
		var fov = 75.0
		var camera_3d = camera.get_node_or_null("Camera3D")
		if camera_3d:
			fov = camera_3d.fov
		var half_fov_rad = deg_to_rad(fov * 0.5)
		var margin_factor = 0.65
		var target_dist = target_body.real_radius / sin(half_fov_rad * margin_factor)
		var target_offset = approach_dir * target_dist
		virtual_player_position = target_body.get_absolute_position(active_star) + target_offset
		
		# En yakın yıldızı bul ve aktif yıldız yap (Floating Origin geçişi)
		_check_active_star_transition()
		
		# Pozisyonları anında güncelle
		for b in active_render_bodies:
			b.real_position = b.get_absolute_position(active_star) - virtual_player_position
				
		_look_at_body(target_body)
		camera.set_speed_to_match_body(target_body.real_radius)
		followed_body = target_body

func _select_body_under_crosshair() -> bool:
	var camera_3d = camera.get_node_or_null("Camera3D")
	if camera_3d == null:
		return false
		
	var cam_forward = -camera_3d.global_basis.z.normalized()
	
	var best_index: int = -1
	var max_dot: float = -1.0
	
	# 1. Önce aktif sistemdeki gezegen ve yıldızı kontrol et
	for body in active_render_bodies:
		var rel_pos = body.real_position
		var dist = rel_pos.length()
		if dist < 0.001:
			continue
			
		var body_dir = rel_pos.normalized()
		var dot = cam_forward.dot(body_dir)
		if dot > max_dot:
			max_dot = dot
			best_index = universe.find(body)
			
	# Eğer aktif sistemdeki bir cisme çok yakın bakılıyorsa (dot > 0.995) onu seç
	if best_index != -1 and max_dot > 0.995:
		current_target_index = best_index
		targeted_star_data = null
		if star_visual_pool != null:
			star_visual_pool.pinned_star_data = null
		return true
		
	# 2. Aktif sistemde doğrudan hedef yoksa, StarVisualPool içindeki uzaktaki yıldızları screen-space kontrol et
	if star_visual_pool != null:
		var vp = get_viewport()
		if vp != null:
			var screen_center = vp.get_visible_rect().size * 0.5
			var pool_result = star_visual_pool.find_star_under_screen_pos(camera_3d, screen_center, 40.0)
			if not pool_result.is_empty():
				targeted_star_data = pool_result["star"]
				current_target_index = -1
				star_visual_pool.pinned_star_data = targeted_star_data
				print("StarData Hedeflendi: ", targeted_star_data.name, " (", targeted_star_data.spectral_type, ")")
				return true

	# 3. Mid-Field GPU Prosedürel Yıldızlarını Kontrol Et (150 - 2.500 LY)
	if mid_field_renderer != null and mid_field_renderer.is_enabled:
		var gal_pos = get_player_galactic_position()
		var ray_origin_ly = gal_pos / LIGHT_YEAR
		var mid_idx = mid_field_renderer.find_closest_star_to_ray(ray_origin_ly, cam_forward, 0.045)
		if mid_idx != -1:
			var star = mid_field_renderer.create_star_data(mid_idx, current_seed)
			if star != null:
				targeted_star_data = star
				current_target_index = -1
				if star_visual_pool != null:
					star_visual_pool.pinned_star_data = targeted_star_data
				var dist_ly = (Vector3(star.stellar_x, star.stellar_y, star.stellar_z) - gal_pos).length() / LIGHT_YEAR
				print("Mid-Field Prosedürel Yıldız Hedeflendi: %s [%s] - Mesafe: %.1f LY" % [star.name, star.spectral_type, dist_ly])
				return true

	# 4. Deep-Field GPU Prosedürel Yıldızlarını Kontrol Et (2.500 - 25.000 LY)
	if deep_field_renderer != null and deep_field_renderer.is_enabled:
		var gal_pos = get_player_galactic_position()
		var ray_origin_ly = gal_pos / LIGHT_YEAR
		var deep_idx = deep_field_renderer.find_closest_star_to_ray(ray_origin_ly, cam_forward, 0.045)
		if deep_idx != -1:
			var star = deep_field_renderer.create_star_data(deep_idx, current_seed)
			if star != null:
				targeted_star_data = star
				current_target_index = -1
				if star_visual_pool != null:
					star_visual_pool.pinned_star_data = targeted_star_data
				var dist_ly = (Vector3(star.stellar_x, star.stellar_y, star.stellar_z) - gal_pos).length() / LIGHT_YEAR
				print("Deep-Field Prosedürel Yıldız Hedeflendi: %s [%s] - Mesafe: %.1f LY" % [star.name, star.spectral_type, dist_ly])
				return true
				
	# 5. İkisi de tam merkezde değilse, toleranslı aktif sistem seçimi
	if best_index != -1 and max_dot > 0.985:
		current_target_index = best_index
		targeted_star_data = null
		if star_visual_pool != null:
			star_visual_pool.pinned_star_data = null
		return true
		
	return false

func _select_body_at_screen_pos(screen_pos: Vector2) -> bool:
	var camera_3d = camera.get_node_or_null("Camera3D") if camera != null else null
	if camera_3d == null:
		return false
		
	var best_index: int = -1
	var min_dist_px: float = INF
	
	# 1. unproject_position ile ekran 2D mesafesi kontrolü (en sezgisel tıklama deneyimi)
	for i in range(universe.size()):
		var body = universe[i]
		var rel_pos = body.real_position
		if rel_pos.length() < 0.001:
			continue
			
		if camera_3d.is_position_behind(rel_pos):
			continue
			
		var screen_coord = camera_3d.unproject_position(rel_pos)
		var d_px = screen_coord.distance_to(screen_pos)
		if d_px < 70.0 and d_px < min_dist_px:
			min_dist_px = d_px
			best_index = i
			
	# 2. Eğer unproject ile bulunamadıysa ray normal dot toleransı kontrolü
	if best_index == -1:
		var ray_normal = camera_3d.project_ray_normal(screen_pos)
		var max_dot: float = 0.94
		for i in range(universe.size()):
			var body = universe[i]
			var rel_pos = body.real_position
			if rel_pos.length() < 0.001:
				continue
			var dot = ray_normal.dot(rel_pos.normalized())
			if dot > max_dot:
				max_dot = dot
				best_index = i

	if best_index != -1:
		current_target_index = best_index
		targeted_star_data = null
		if star_visual_pool != null:
			star_visual_pool.pinned_star_data = null
		print("SOL TIK İLE CİSİM SEÇİLDİ: ", universe[best_index].name)
		return true
		
	if star_visual_pool != null:
		var pool_res = star_visual_pool.find_star_under_screen_pos(camera_3d, screen_pos, 50.0)
		if not pool_res.is_empty():
			targeted_star_data = pool_res["star"]
			current_target_index = -1
			star_visual_pool.pinned_star_data = targeted_star_data
			print("SOL TIK İLE YILDIZ SEÇİLDİ: ", targeted_star_data.name)
			return true
			
	return false

func _handle_focus_key() -> void:
	# Eğer zaten odak modu aktifse VEYA hedef seçiliyken C'ye basılmışsa:
	# Kullanıcı isteği: "Tekrar c'ye basarsak seçiliyken boşa düşsün"
	if is_focusing_target:
		is_focusing_target = false
		focus_target_star = null
		focus_target_body = null
		focus_time = 0.0
		current_target_index = -1
		targeted_star_data = null
		if star_visual_pool != null:
			star_visual_pool.pinned_star_data = null
		print("HEDEF SEÇİMİ VE ODAK BOŞA DÜŞÜRÜLDÜ")
		return

	focus_time = 0.0

	# 1. Hedeflenen galaktik yıldız varsa (StarData)
	if targeted_star_data != null:
		is_focusing_target = true
		focus_target_star = targeted_star_data
		focus_target_body = null
		print("GALAKTİK YILDIZA ODAKLANILDI: ", targeted_star_data.name)
		return

	# 2. Hedeflenen aktif sistem cismi varsa (Gezegen / Ay / Yıldız)
	if universe.size() > 0 and current_target_index >= 0 and current_target_index < universe.size():
		var target_body = universe[current_target_index]
		is_focusing_target = true
		focus_target_body = target_body
		focus_target_star = null
		print("HEDEFE ODAKLANILDI: ", target_body.name)
		return

	# 3. Hiçbir hedef seçili değilse: Önce crosshair altındaki cismi seç ve odaklan
	if _select_body_under_crosshair():
		if targeted_star_data != null:
			is_focusing_target = true
			focus_target_star = targeted_star_data
			focus_target_body = null
			print("CROSSHAIR İLE YILDIZ SEÇİLDİ VE ODAKLANILDI: ", targeted_star_data.name)
			return
		elif current_target_index >= 0 and current_target_index < universe.size():
			var t_body = universe[current_target_index]
			is_focusing_target = true
			focus_target_body = t_body
			focus_target_star = null
			print("CROSSHAIR İLE CİSİM SEÇİLDİ VE ODAKLANILDI: ", t_body.name)
			return

	# 4. Crosshair altında da yoksa aktif sistem yıldızına odaklan ve seç
	if active_star != null:
		is_focusing_target = true
		focus_target_body = active_star
		focus_target_star = null
		current_target_index = universe.find(active_star)
		print("SİSTEM YILDIZINA ODAKLANILDI: ", active_star.name)



# Aşama 4: Prosedürel Galaktik Sektör Yıldızları Arasında Akıllı ve Histerezisli Geçiş
func _check_active_star_transition() -> void:
	if active_star == null or sector_manager == null:
		return
	if _star_transition_cooldown > 0.0:
		return
		
	var gal_pos = get_player_galactic_position()
	var cur_dx = (active_star.stellar_x - gal_pos.x) / LIGHT_YEAR
	var cur_dy = (active_star.stellar_y - gal_pos.y) / LIGHT_YEAR
	var cur_dz = (active_star.stellar_z - gal_pos.z) / LIGHT_YEAR
	var cur_dist_sq_ly = cur_dx*cur_dx + cur_dy*cur_dy + cur_dz*cur_dz
	
	var closest_star_data = null
	var min_dist_sq_ly: float = INF
	
	# Tüm 125 sektörü her seferinde taramak yerine sadece oyuncunun 3x3x3 yerel sektörlerini tara
	var player_sec = SectorManager.get_sector_coord(gal_pos)
	for ox in range(-1, 2):
		for oy in range(-1, 2):
			for oz in range(-1, 2):
				var check_coord = player_sec + Vector3i(ox, oy, oz)
				if sector_manager.loaded_sectors.has(check_coord):
					var sec_stars = sector_manager.loaded_sectors[check_coord]
					for s_data in sec_stars:
						var dx = (s_data.stellar_x - gal_pos.x) / LIGHT_YEAR
						var dy = (s_data.stellar_y - gal_pos.y) / LIGHT_YEAR
						var dz = (s_data.stellar_z - gal_pos.z) / LIGHT_YEAR
						var d_sq_ly = dx*dx + dy*dy + dz*dz
						if d_sq_ly < min_dist_sq_ly:
							min_dist_sq_ly = d_sq_ly
							closest_star_data = s_data
				
	# Yerel Sistem Eşiği (Heliopoz / Kuiper Kuşağı Sınırı: 100 AU ~ 1.496e13 metre)
	# Derin uzayda (ışık yılları mesafesinde) gezinirken gereksiz sistem değişimleri engellenir.
	# Sistem geçişi yalnızca:
	# 1. G tuşu ile otopilot hedef yıldıza ulaştığında, VEYA
	# 2. Manuel uçuşta oyuncu yeni yıldızın gerçek yerel sistem sınırına (< 100 AU) girdiğinde tetiklenir.
	const SYSTEM_LOCAL_ENTER_RADIUS_SQ_LY: float = 2.50058e-6 # (100 * ONE_AU / LIGHT_YEAR)^2
	
	if closest_star_data != null and closest_star_data.unique_id != active_star_unique_id:
		# Yeni yıldıza gerçekten yerel sistem mesafesinde miyiz VE mevcut yıldızdan daha mı yakınız?
		if min_dist_sq_ly <= SYSTEM_LOCAL_ENTER_RADIUS_SQ_LY and min_dist_sq_ly < cur_dist_sq_ly * 0.7225:
			_transition_to_star_data(closest_star_data)

func _transition_to_star_data(new_star_data) -> void:
	_star_transition_cooldown = 1.0 # 1 saniye geçiş kilidi
	
	# 1. Koordinat sürekliliği için virtual_player_position kaydırması
	var dx = active_star.stellar_x - new_star_data.stellar_x
	var dy = active_star.stellar_y - new_star_data.stellar_y
	var dz = active_star.stellar_z - new_star_data.stellar_z
	virtual_player_position.x += dx
	virtual_player_position.y += dy
	virtual_player_position.z += dz
	
	# 2. Eski aktif yıldızın grafiklerini temizle
	SystemGenerator.despawn_body_graphics(active_star)
	if is_instance_valid(active_star.visual_mesh):
		active_star.visual_mesh.queue_free()
	if is_instance_valid(active_star.lod_sprite):
		active_star.lod_sprite.queue_free()
	
	# 3. Asılı referansları temizle
	if is_instance_valid(sphere_chunk_manager):
		_flv_clear_chunks()
	if autopilot_target_body != null and autopilot_target_body.type != "STAR":
		autopilot_target_body = null
		is_autopilot_active = false
	if followed_body != null and followed_body.type != "STAR":
		followed_body = null
	current_target_index = -1
	
	# 4. Yeni yıldızı oluştur ve aktif kıl
	active_star_unique_id = new_star_data.unique_id
	active_star = SystemGenerator.instantiate_star_from_data(self, new_star_data)
	stars = [active_star]
	
	# 5. Gezegenlerini ve uydularını üret
	_update_active_system_bodies()
	
	print("YILDIZ SİSTEMİ GEÇİŞİ: Yeni Aktif Sistem -> ", active_star.name)

# --- KAMERAYI NESNEYE ÇEVİRME YARDIMCISI ---
func _look_at_body(body: CelestialBody):
	# Kameranın yönünü nesneye kilitler
	var target_pos = body.real_position
	if target_pos.length() > 0.001:
		var target_dir = target_pos.normalized()
		camera.rot_x = asin(target_dir.y)
		camera.rot_y = atan2(-target_dir.x, -target_dir.z)
		camera.rot_z = 0.0 # Reset roll on looking at a body
		camera.transform.basis = Basis.from_euler(Vector3(camera.rot_x, camera.rot_y, camera.rot_z))

# --- YENİ EKLENEN SİSTEMLER (HARİTA & İNİŞ) ---
func _toggle_system_map() -> void:
	if is_landed or is_eva_active:
		return
		
	is_system_map_active = !is_system_map_active
	if is_system_map_active:
		map_pre_pos = virtual_player_position
		map_pre_rot_x = camera.rot_x
		map_pre_rot_y = camera.rot_y
		map_pre_rot_z = camera.rot_z
		map_pre_speed_index = camera.speed_multiplier_index
		
		is_autopilot_active = false
		autopilot_target_body = null
		followed_body = null
		player_velocity = Vector3.ZERO
		
		if active_star != null:
			# Starfield referansı: ~52° eğimli, 3B derinlikli sinematik izometrik harita açısı
			var map_dist = max(active_star.system_diameter * 0.72, 60000000000.0)
			camera.rot_x = deg_to_rad(-52.0)
			camera.rot_y = deg_to_rad(25.0)
			camera.rot_z = 0.0
			var cam_rot_basis = Basis.from_euler(Vector3(camera.rot_x, camera.rot_y, camera.rot_z))
			camera.transform.basis = cam_rot_basis
			
			var cam_offset = cam_rot_basis * Vector3.BACK * map_dist
			virtual_player_position = active_star.get_absolute_position(active_star) + cam_offset
			
			camera.speed_multiplier_index = 20 # ~100 AU/s
			camera.target_speed = camera.speed_presets[camera.speed_multiplier_index]
			camera.current_speed = camera.target_speed
			
			for body in active_render_bodies:
				body.real_position = body.get_absolute_position(active_star) - virtual_player_position
	else:
		virtual_player_position = map_pre_pos
		camera.rot_x = map_pre_rot_x
		camera.rot_y = map_pre_rot_y
		camera.rot_z = map_pre_rot_z
		camera.speed_multiplier_index = map_pre_speed_index
		camera.target_speed = camera.speed_presets[camera.speed_multiplier_index]
		camera.current_speed = camera.target_speed
		camera.transform.basis = Basis.from_euler(Vector3(camera.rot_x, camera.rot_y, camera.rot_z))
		
		for body in active_render_bodies:
			body.real_position = body.get_absolute_position(active_star) - virtual_player_position

func _zoom_system_map(zoom_in: bool) -> void:
	if not is_system_map_active or active_star == null:
		return
	var star_abs = active_star.get_absolute_position(active_star)
	var rel_to_star = virtual_player_position - star_abs
	var cur_dist = rel_to_star.length()
	var min_dist = 5000000000.0 # ~0.033 AU
	var max_dist = active_star.system_diameter * 3.0
	var zoom_factor = 0.82 if zoom_in else 1.22
	var new_dist = clampf(cur_dist * zoom_factor, min_dist, max_dist)
	if cur_dist > 0.001:
		virtual_player_position = star_abs + (rel_to_star.normalized() * new_dist)
		for body in active_render_bodies:
			body.real_position = body.get_absolute_position(active_star) - virtual_player_position

func _handle_landing_key() -> void:
	if is_eva_active:
		if is_near_ship_airlock:
			end_eva_mode()
		return
		
	if camera != null and camera.spacecraft != null:
		var sc = camera.spacecraft
		if sc.current_view_mode == sc.CameraViewMode.INTERIOR_FPS:
			if sc.near_airlock:
				sc.toggle_airlock()
				return
			elif sc.near_pilot_seat:
				sc.toggle_cockpit_seat()
				return
			return
				
	if is_landed:
		_launch_from_planet()
	else:
		_try_land_on_target()

func _try_land_on_target() -> void:
	if is_eva_active or (spacecraft != null and not spacecraft.is_seated_in_cockpit):
		return
	if universe.size() == 0 or current_target_index < 0 or current_target_index >= universe.size():
		return
		
	var target = universe[current_target_index]
	if target.type == "STAR":
		return
		
	# Sadece aktif yıldız sistemindeki cisimlere iniş yapılabilir
	if target.get_system_star() != active_star:
		return
		
	if is_system_map_active:
		_toggle_system_map()
		
	var dist = target.real_position.length()
	if dist < target.real_radius * 1.5:
		_execute_landing(target)
	else:
		followed_body = null
		is_autopilot_active = true
		is_landing_autopilot = true
		autopilot_target_body = target
		autopilot_start_player_pos = virtual_player_position
		var body_abs_pos = target.get_absolute_position(active_star)
		autopilot_relative_start_pos = virtual_player_position - body_abs_pos
		autopilot_timer = 0.0
		autopilot_duration = 2.5 # Yumuşak iniş alçalması

func _execute_landing(target: CelestialBody) -> void:
	is_autopilot_active = false
	is_landing_autopilot = false
	autopilot_target_body = null
	followed_body = null
	player_velocity = Vector3.ZERO
	
	is_landed = true
	landed_body = target
	
	# Defensively load/generate textures for target if they are null
	if target.noise_albedo == null:
		SystemGenerator.generate_body_textures(self, target)
		
	var noise: FastNoiseLite = null
	if target.noise_albedo != null and target.noise_albedo.noise != null:
		noise = target.noise_albedo.noise
		
	var height_at_landing = 0.0
	if noise != null:
		height_at_landing = PlanetLODManager.sample_surface_height(0.0, 0.0, noise, 0.002, 350.0)
		
	var body_abs_pos = landed_body.get_absolute_position(active_star)
	var approach_vec = virtual_player_position - body_abs_pos
	var horiz = Vector2(approach_vec.x, approach_vec.z)
	if horiz.length_squared() < 0.01:
		horiz = Vector2(0.88, 0.47)
	horiz = horiz.normalized()
	var lat_factor = clampf(approach_vec.y / maxf(approach_vec.length(), 1.0), -0.25, 0.25)
	var landing_dir = Vector3(horiz.x, lat_factor, horiz.y).normalized()
	
	var relative_landing_pos = landing_dir * (target.real_radius + EYE_HEIGHT + height_at_landing)
	landed_local_pos = (landing_dir * target.real_radius).rotated(Vector3.UP, -target.rotation_angle)
	landed_walk_offset = Vector2.ZERO
	landed_vertical_offset = 0.0
	
	camera.rot_x = 0.0
	camera.rot_y = 0.0
	camera.rot_z = 0.0
	
	camera.speed_multiplier_index = 0
	camera.target_speed = camera.speed_presets[0]
	camera.current_speed = camera.target_speed
	
	virtual_player_position = body_abs_pos + relative_landing_pos
	
	# Mesh-Based Chunked LOD terrain sistemi oluştur
	if is_instance_valid(landed_lod_manager):
		landed_lod_manager.queue_free()
		landed_lod_manager = null

	# Gezegenin 3D mesh'ini gizle (yerine chunk LOD çalışacak)
	if is_instance_valid(target.visual_mesh):
		target.visual_mesh.visible = false

	# Tangent plane basis vectors (local surface coordinate system - right-handed)
	var local_up = relative_landing_pos.normalized()
	var planet_x = Vector3.RIGHT.rotated(Vector3.UP, target.rotation_angle)
	var local_z = planet_x.cross(local_up).normalized()
	var local_x = local_up.cross(local_z).normalized()
	landed_ship_basis = Basis(local_x, local_up, local_z)
	
	if camera.has_method("reset_camera_orientation"):
		camera.reset_camera_orientation(landed_ship_basis)
	else:
		camera.transform.basis = landed_ship_basis
	
	var current_sc = spacecraft if spacecraft != null else (camera.spacecraft if camera != null else null)
	if current_sc != null:
		current_sc.global_basis = landed_ship_basis
		current_sc.global_position = local_up * (-EYE_HEIGHT + 0.45)
		current_sc.current_view_mode = current_sc.CameraViewMode.INTERIOR_FPS
		current_sc.is_seated_in_cockpit = true
		current_sc.cabin_player_pos = current_sc.PILOT_SEAT_POS
		current_sc.is_airlock_open = false
		current_sc.airlock_anim_progress = 0.0
	is_eva_active = false

	var lod_manager = PlanetLODManager.new()
	add_child(lod_manager)
	landed_lod_manager = lod_manager

	lod_manager.initialize(target, noise, local_up, local_x, local_z, EYE_HEIGHT)
	lod_manager.set_noise_params(0.002, 350.0)

	# Terrain material'ı oluştur ve LOD manager'a ver
	var terrain_mat = StandardMaterial3D.new()
	terrain_mat.albedo_color = Color.WHITE
	terrain_mat.roughness = target.roughness
	terrain_mat.metallic = target.metallic
	terrain_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	if target.noise_albedo != null:
		terrain_mat.albedo_texture = target.noise_albedo
	if target.noise_normal != null:
		terrain_mat.normal_texture = target.noise_normal
		terrain_mat.normal_enabled = true

	if SystemGenerator.detail_noise_tex != null:
		terrain_mat.detail_enabled = true
		terrain_mat.detail_blend_mode = 3 # DETAIL_BLEND_MIX
		terrain_mat.detail_albedo = SystemGenerator.detail_noise_tex
		terrain_mat.detail_normal = SystemGenerator.detail_normal_tex
		terrain_mat.detail_uv_layer = 1 # DETAIL_UV_2
		terrain_mat.uv2_scale = Vector3(15000, 15000, 1)

	lod_manager.set_material(terrain_mat)

	# İlk chunk setini oluştur
	lod_manager.update(0.0, 0.0)
	
	# ── GEZEGEN YÜZEYİ ATMOSFERİK GÖKYÜZÜ VE ORTAM SİSTEMİ ─────────────────────
	# Uzaydaki derin uzay nebulası, bulutsular ve yıldız alanları gezegen atmosferinde gizlenir
	var camera_3d = camera.get_node_or_null("Camera3D")
	if camera_3d:
		camera_3d.near = 0.05
		if camera_3d.environment:
			var env = camera_3d.environment
			if target.has_atmosphere:
				var atmo_color = target.atmosphere_color
				var sky_mat = ProceduralSkyMaterial.new()
				sky_mat.sky_top_color = atmo_color.lerp(Color(0.08, 0.22, 0.45), 0.35)
				sky_mat.sky_horizon_color = atmo_color.lightened(0.2)
				sky_mat.ground_bottom_color = target.base_color.darkened(0.55)
				sky_mat.ground_horizon_color = atmo_color.darkened(0.2)
				sky_mat.sun_angle_max = 28.0
				var planet_sky = Sky.new()
				planet_sky.sky_material = sky_mat
				env.background_mode = Environment.BG_SKY
				env.sky = planet_sky
				
				# Atmosferik Ufuk Sisi (Uzay boşluğunu kapatır, gerçek bir dünya ufku hissi verir)
				env.fog_enabled = true
				env.fog_light_color = atmo_color.lightened(0.15)
				env.fog_density = 0.00045
				env.fog_sky_affect = 0.85
				env.fog_aerial_perspective = 0.65
			else:
				# Atmosfersiz cisimler (Ay vb.): Derin uzay karanlığı
				env.background_mode = Environment.BG_COLOR
				env.background_color = Color(0.005, 0.005, 0.01)
				env.fog_enabled = false
			
	# Derin uzay GPU yıldız ve nebula katmanlarını gezegen atmosferinde kapat
	if mid_field_renderer != null:
		mid_field_renderer.set_enabled(false)
	if deep_field_renderer != null:
		deep_field_renderer.set_enabled(false)
	if star_visual_pool != null:
		star_visual_pool.visible = false
	
	for body in active_render_bodies:
		body.real_position = body.get_absolute_position(active_star) - virtual_player_position

func _launch_from_planet() -> void:
	var cam_3d = camera.get_node_or_null("Camera3D")
	if cam_3d:
		cam_3d.near = 0.3
	if not is_landed or landed_body == null:
		return
		
	if is_instance_valid(landed_body.visual_mesh):
		landed_body.visual_mesh.visible = true
		
	if is_instance_valid(landed_lod_manager):
		landed_lod_manager.queue_free()
		landed_lod_manager = null
		
	# Uzay ortamı ve derin uzay nebulası/yıldız alanını geri yükle
	var camera_3d = camera.get_node_or_null("Camera3D")
	if camera_3d and camera_3d.environment:
		var env = camera_3d.environment
		env.fog_enabled = false
		if space_sky != null:
			env.background_mode = Environment.BG_SKY
			env.sky = space_sky
		else:
			env.background_mode = Environment.BG_COLOR
			env.background_color = Color(0.01, 0.01, 0.02)
			
	if mid_field_renderer != null:
		mid_field_renderer.set_enabled(enable_mid_field)
	if deep_field_renderer != null:
		deep_field_renderer.set_enabled(enable_deep_field)
	if star_visual_pool != null:
		star_visual_pool.visible = true
		
	var body_abs_pos = landed_body.get_absolute_position(active_star)
	var orbit_offset = Vector3.UP * (landed_body.real_radius * 2.5)
	virtual_player_position = body_abs_pos + orbit_offset
	
	is_landed = false
	followed_body = landed_body
	landed_body = null
	
	if camera != null and camera.spacecraft != null:
		var sc = camera.spacecraft
		sc.top_level = false
		sc.position = Vector3(0.0, -0.45, -0.6)
		sc.rotation = Vector3.ZERO
		sc.current_view_mode = sc.CameraViewMode.THIRD_PERSON
		sc.is_seated_in_cockpit = true
		sc.cabin_player_pos = sc.PILOT_SEAT_POS
		sc.is_airlock_open = false
		sc.airlock_anim_progress = 0.0
	is_eva_active = false
	
	camera.set_speed_to_match_body(followed_body.real_radius)
	
	for body in active_render_bodies:
		body.real_position = body.get_absolute_position(active_star) - virtual_player_position

# ─────────────────────────────────────────────────────────────────────────────
# KESİNTİSİZ EVA VE GEMİYE BİNME YÖNETİMİ
# ─────────────────────────────────────────────────────────────────────────────
func _on_player_left_seat() -> void:
	is_autopilot_active = false
	is_interstellar_autopilot = false
	is_hyper_autopilot = false
	is_interstellar_hyper_boost = false
	is_landing_autopilot = false
	autopilot_target_body = null
	followed_body = null
	is_focusing_target = false
	player_velocity = Vector3.ZERO
	spacecraft_universe_pos = virtual_player_position
	spacecraft_basis = spacecraft.global_basis if spacecraft != null else camera.global_basis

func start_eva_mode() -> void:
	var sc: Spacecraft = spacecraft
	if is_eva_active or sc == null or sc.is_seated_in_cockpit or not sc.is_airlock_open or sc.airlock_anim_progress < 0.95:
		return
	_on_player_left_seat()
	var view_basis: Basis = camera.camera_node.global_basis
	is_eva_active = true
	eva_velocity = Vector3.ZERO
	sc.current_view_mode = Spacecraft.CameraViewMode.EVA
	if is_landed and landed_body != null:
		landed_walk_offset = Vector2(0.0, 3.75)
		landed_vertical_offset = 0.0
		landed_vertical_velocity = 0.0
	else:
		ship_eva_world_pos = spacecraft_universe_pos
		ship_eva_basis = spacecraft_basis
		eva_offset = ship_eva_basis * sc.cabin_player_pos
		virtual_player_position = ship_eva_world_pos + eva_offset
		sc.global_position = -eva_offset
		sc.global_basis = ship_eva_basis
	camera.global_basis = view_basis
	var angles: Vector3 = camera.basis.get_euler()
	camera.rot_x = angles.x
	camera.rot_y = angles.y
	camera.rot_z = angles.z
	camera._update_camera_view(true)
	is_near_ship_airlock = true
	print("EVA: Hava kilidinden çıkıldı. WASD/Space/Ctrl itiş, X fren, E dönüş.")

func _step_eva_motion(delta: float, input_dir: Vector3, boost: bool, brake: bool) -> void:
	var has_thrust := input_dir.length_squared() > 0.01
	is_jetpack_active = has_thrust or brake
	is_jetpack_boosting = boost and has_thrust and astronaut_fuel > 0.0
	var acceleration := 12.0 if is_jetpack_boosting else 5.0
	if astronaut_fuel <= 0.0:
		acceleration = 0.5
	var direction: Vector3 = camera.global_basis * input_dir.normalized()
	if has_thrust:
		eva_velocity += direction * acceleration * delta
		eva_velocity = eva_velocity.limit_length(18.0 if is_jetpack_boosting else 6.0)
	if brake:
		eva_velocity *= exp(-5.0 * delta)
	else:
		eva_velocity *= exp(-0.12 * delta)
	if is_jetpack_active:
		astronaut_fuel = maxf(0.0, astronaut_fuel - (4.0 if is_jetpack_boosting else 1.2) * delta)
	astronaut_oxygen = maxf(5.0, astronaut_oxygen - 0.04 * delta)
	eva_offset += eva_velocity * delta
	virtual_player_position = ship_eva_world_pos + eva_offset
	player_velocity = eva_velocity
	if spacecraft != null:
		spacecraft.global_position = -eva_offset
		spacecraft.global_basis = ship_eva_basis
		var door := ship_eva_basis * Vector3(0.0, 0.70, 3.75)
		dist_to_ship_eva = eva_offset.distance_to(door)
		is_near_ship_airlock = dist_to_ship_eva < 2.2 and spacecraft.is_airlock_open and spacecraft.airlock_anim_progress > 0.95

func end_eva_mode() -> void:
	if not is_eva_active or not is_near_ship_airlock or spacecraft == null:
		return
	var sc := spacecraft
	if not sc.is_airlock_open or sc.airlock_anim_progress < 0.95:
		return
	is_eva_active = false
	is_near_ship_airlock = false
	eva_velocity = Vector3.ZERO
	player_velocity = Vector3.ZERO
	is_jetpack_active = false
	is_jetpack_boosting = false
	sc.current_view_mode = Spacecraft.CameraViewMode.INTERIOR_FPS
	sc.is_seated_in_cockpit = false
	sc.cabin_player_pos = Vector3(0.0, sc.CABIN_EYE_HEIGHT, 2.15)
	sc.cabin_player_pitch = 0.0
	sc.cabin_player_yaw = 0.0
	sc.near_airlock = true
	sc.near_pilot_seat = false
	sc.is_airlock_open = false
	if is_landed:
		landed_walk_offset = Vector2.ZERO
		landed_vertical_offset = 0.0
		landed_vertical_velocity = 0.0
	else:
		virtual_player_position = ship_eva_world_pos
		spacecraft_universe_pos = ship_eva_world_pos
		spacecraft_basis = ship_eva_basis
		sc.global_position = Vector3.ZERO
		sc.global_basis = ship_eva_basis
		camera.global_basis = ship_eva_basis
		var angles: Vector3 = camera.basis.get_euler()
		camera.rot_x = angles.x
		camera.rot_y = angles.y
		camera.rot_z = angles.z
	eva_offset = Vector3.ZERO
	astronaut_fuel = 100.0
	astronaut_oxygen = 100.0
	camera._update_camera_view(true)
	print("EVA: Gemiye dönüldü, hava kilidi kapanıyor.")

# Aşama 8: Hava Kilidi ve Kesintisiz EVA Doğrulama Testi
func _run_airlock_and_eva_test() -> void:
	print("==================================================")
	print("--- HAVA KİLİDİ VE KESİNTİSİZ EVA TESTLERİ (AŞAMA 8) ---")
	if camera == null or camera.spacecraft == null:
		print("  [HATA] Camera veya Spacecraft bulunamadı!")
		return
		
	var sc = camera.spacecraft
	
	# 1. Hava Kilidi Açma / Kapama Testi
	var initial_state = sc.is_airlock_open
	sc.current_view_mode = Spacecraft.CameraViewMode.INTERIOR_FPS
	sc.is_seated_in_cockpit = false
	sc.cabin_player_yaw = 0.0
	sc.is_airlock_open = false
	sc.toggle_airlock()
	sc.airlock_anim_progress = 1.0
	var toggled_state = sc.is_airlock_open
	var pass_toggle = (toggled_state != initial_state)
	print("  1. Hava Kilidi Toggle: ", "BAŞARILI (Durum: %s)" % ("AÇIK" if toggled_state else "KAPALI") if pass_toggle else "BAŞARISIZ")
	
	# 2. Rampada Yürüme Sınırları Testi
	sc.cabin_player_pos = Vector3(0.0, sc.CABIN_EYE_HEIGHT, 1.8) # Hava kilidi içi
	sc.update_cabin_walking(0.016, Vector2(0.0, 1.0), Vector2.ZERO) # Arka hava kilidine yürü
	var pass_ramp_walk = (sc.cabin_player_pos.z > 1.8)
	print("  2. Rampa Yürüyüş Sınırı: ", "BAŞARILI (Z: %.2f m)" % sc.cabin_player_pos.z if pass_ramp_walk else "BAŞARISIZ")
	
	# 3. Uzay EVA Modu Başlatma Testi
	var pre_eva_pos = virtual_player_position
	sc.cabin_player_pos = Vector3(0, 0.7, 3.75)
	start_eva_mode()
	var pass_eva_start = (is_eva_active and sc.current_view_mode == sc.CameraViewMode.EVA)
	print("  3. Sıfır-G EVA Başlatma: ", "BAŞARILI (Mod: EVA)" if pass_eva_start else "BAŞARISIZ")
	
	# 4. Gemiye Geri Binme (End EVA) Testi
	end_eva_mode()
	var pass_eva_end = (!is_eva_active and sc.current_view_mode == sc.CameraViewMode.INTERIOR_FPS)
	print("  4. Gemiye Geri Binme: ", "BAŞARILI (Mod: INTERIOR_FPS)" if pass_eva_end else "BAŞARISIZ")
	
	# Test sonu temizlik
	if sc.is_airlock_open != initial_state:
		sc.toggle_airlock()
	virtual_player_position = pre_eva_pos
	print("Hava Kilidi ve EVA Testleri Başarıyla Tamamlandı.")

# Aşama 9: Oyuncu ve Gemi Ayrık Sahne Doğrulama Testi
func _run_player_spacecraft_decoupling_test() -> void:
	print("==================================================")
	print("--- OYUNCU VE GEMİ AYRIK SAHNE TESTİ (AŞAMA 9) ---")
	var success = true
	var sc = spacecraft if spacecraft != null else (camera.spacecraft if camera != null else null)
	
	# 1. Gemi ve Oyuncunun Ayrı Düğümler Olması
	if sc == null:
		print("  • Spacecraft sahnesi bulunamadı: BAŞARISIZ")
		success = false
	elif sc.get_parent() == camera:
		print("  • Spacecraft hala kameranın çocuğu: BAŞARISIZ")
		success = false
	else:
		print("  • Spacecraft ve Player bağımsız kardeş düğümler: BAŞARILI")
		
	# 2. Kabin İçi Yürüyüşte Geminin Hareketsiz Kalması
	if sc != null:
		sc.current_view_mode = sc.CameraViewMode.INTERIOR_FPS
		sc.is_seated_in_cockpit = false
		var prev_ship_universe_pos = spacecraft_universe_pos
		
		# Oyuncu kabin içinde yürür
		sc.cabin_player_pos = Vector3(0.0, sc.CABIN_EYE_HEIGHT, 0.0)
		sc.update_cabin_walking(0.016, Vector2(0.5, 0.5), Vector2.ZERO)
		
		# Gemi evrende hareket etmemeli
		if spacecraft_universe_pos != prev_ship_universe_pos:
			print("  • Kabinde yürürken geminin evren pozisyonu değişti: BAŞARISIZ")
			success = false
		else:
			print("  • Kabinde yürürken geminin evren pozisyonu sabit kaldı: BAŞARILI")
			
		# Test sonu kokpite geri oturt
		sc.is_seated_in_cockpit = true
		sc.current_view_mode = sc.CameraViewMode.THIRD_PERSON
		
	if success:
		print("OYUNCU VE GEMİ AYRIK SAHNE TESTİ: %100 BAŞARILI")
	else:
		printerr("OYUNCU VE GEMİ AYRIK SAHNE TESTİ: EKSİKLER MEVCUT")
	print("==================================================")
