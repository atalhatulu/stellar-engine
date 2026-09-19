class_name Spacecraft
extends Node3D

# ─────────────────────────────────────────────────────────────────────────────
# PROSEDÜREL KEŞİF VE SAVAŞ KORVETİ (PROCEDURAL RECON CORVETTE)
#
# Tamamen saf Godot 4 geometrisiyle inşa edilmiş, hem dıştan izlenebilen (3. Şahıs)
# hem de içinde ayakla gezilebilen (Kabin İçi FPS) ve pilot koltuğuna oturup
# uzayda sürülebilen çift modlu gelişmiş uzay gemisi.
# ─────────────────────────────────────────────────────────────────────────────

enum CameraViewMode {
	THIRD_PERSON, # 3. Şahıs - Gemiyi arkadan izleyen sinematik dış kamera
	INTERIOR_FPS, # Kabin İçi FPS - Gemi içinde yürüme ve pilot kokpiti
	FREE_CAM,     # Serbest Kamera - Saf uzay fotoğraf modu
	EVA           # Uzay Yürüyüşü / Yüzey Keşfi - Gemi dışı astronot modu
}

var current_view_mode: int = CameraViewMode.THIRD_PERSON

# Görsel Düğümler
var ship_root: Node3D
var cabin_root: Node3D
var engines_root: Node3D
var reactor_core_mesh: MeshInstance3D
var landing_gear_root: Node3D

var left_thruster_flame: MeshInstance3D
var right_thruster_flame: MeshInstance3D
var left_inner_flame: MeshInstance3D
var right_inner_flame: MeshInstance3D

var thruster_light: OmniLight3D
var cabin_ambient_light: OmniLight3D
var reactor_light: OmniLight3D
var cockpit_console_light: OmniLight3D

# Hava Kilidi ve İniş Rampası Düğümleri
var airlock_hatch_pivot: Node3D
var airlock_hatch_mesh: MeshInstance3D
var airlock_status_light: OmniLight3D
var airlock_status_mesh: MeshInstance3D
var airlock_vent_steam: MeshInstance3D
var left_hydraulic_strut: MeshInstance3D
var right_hydraulic_strut: MeshInstance3D

# Materyaller
var hull_mat: StandardMaterial3D
var armor_mat: StandardMaterial3D
var glass_mat: StandardMaterial3D
var engine_mat: StandardMaterial3D
var interior_wall_mat: StandardMaterial3D
var floor_mat: StandardMaterial3D
var seat_mat: StandardMaterial3D
var glow_cyan_mat: StandardMaterial3D
var glow_orange_mat: StandardMaterial3D
var flame_core_mat: StandardMaterial3D
var flame_outer_mat: StandardMaterial3D
var airlock_status_mat: StandardMaterial3D
var airlock_hazard_mat: StandardMaterial3D
var steam_vent_mat: StandardMaterial3D

# Kabin İçi FPS ve Pilot Koltuğu Durumu
const PILOT_SEAT_POS: Vector3 = Vector3(0.0, 1.25, -2.15)
const CABIN_EYE_HEIGHT: float = 1.55
const SEAT_EYE_HEIGHT: float = 1.25

const CABIN_MIN_X: float = -0.85
const CABIN_MAX_X: float = 0.85
const CABIN_MIN_Z: float = -2.35
const CABIN_MAX_Z: float = 2.45
const AIRLOCK_DOOR_Z: float = 2.65
const AIRLOCK_TRIGGER_Z: float = 1.45

var is_seated_in_cockpit: bool = true # Varsayılan olarak pilot koltuğunda oturuyor
var near_pilot_seat: bool = true
var near_airlock: bool = false
var is_airlock_open: bool = false
var airlock_anim_progress: float = 0.0 # 0.0 (kapalı) -> 1.0 (tamamen açık)
var vent_timer: float = 0.0

var cabin_player_pos: Vector3 = PILOT_SEAT_POS
var cabin_player_yaw: float = 0.0
var cabin_player_pitch: float = 0.0

# Dinamik Uçuş ve Animasyon Değişkenleri
var target_tilt_roll: float = 0.0
var current_tilt_roll: float = 0.0
var target_tilt_pitch: float = 0.0
var current_tilt_pitch: float = 0.0
var target_tilt_yaw: float = 0.0
var current_tilt_yaw: float = 0.0

var flame_intensity: float = 0.4
var engine_vector_yaw: float = 0.0
var engine_vector_pitch: float = 0.0
var reactor_pulse: float = 0.0

func _ready() -> void:
	_build_spacecraft_mesh()

const Design = preload("res://scripts/rendering/spacecraft_design.gd")
var instrument_materials: Array[ShaderMaterial] = []
var cabin_walk_phase := 0.0
var travel_material: ShaderMaterial
@export_range(0.0, 1.5, 0.05) var travel_effect_strength: float = 1.0
var travel_intensity := 0.0
var warp_intensity := 0.0
var travel_phase := 0.0
var travel_overlay: ColorRect
var landing_deployment := 0.0

func _build_spacecraft_mesh() -> void:
	Design.build(self)
	var layer := CanvasLayer.new()
	layer.layer = -1
	add_child(layer)
	var overlay := ColorRect.new()
	travel_overlay = overlay
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	travel_material = ShaderMaterial.new()
	travel_material.shader = load("res://shaders/travel_streaks.gdshader")
	overlay.material = travel_material
	layer.add_child(overlay)

# Logarithmic bands cover local flight through interstellar speeds without
# treating a high throttle setting or the autopilot switch as actual movement.
static func travel_profile(speed_mps: float) -> Vector2:
	var speed := maxf(speed_mps, 0.0)
	var cruise := clampf(log(maxf(speed / 1000.0, 1.0)) / log(10.0) / 5.5, 0.0, 1.0)
	var warp := clampf(log(maxf(speed / 299792458.0, 1.0)) / log(10.0) / 7.0, 0.0, 1.0)
	return Vector2(cruise * 0.45 + warp * 0.55, warp)

func update_travel_effect(delta: float, speed_mps: float, allowed: bool) -> void:
	var profile := travel_profile(speed_mps) if allowed else Vector2.ZERO
	var response := 2.5 if profile.x > travel_intensity else 4.6
	var weight := 1.0 - exp(-response * maxf(delta, 0.0))
	travel_intensity = lerpf(travel_intensity, profile.x * travel_effect_strength, weight)
	warp_intensity = lerpf(warp_intensity, profile.y * travel_effect_strength, weight)
	# Integrate animation phase: changing speed never jumps the streak positions.
	travel_phase = fposmod(travel_phase + maxf(delta, 0.0) * (0.15 + 2.8 * travel_intensity), 1024.0)
	travel_overlay.visible = allowed and travel_intensity > 0.002
	travel_material.set_shader_parameter("intensity", travel_intensity)
	travel_material.set_shader_parameter("warp", warp_intensity)
	travel_material.set_shader_parameter("phase", travel_phase)
	travel_material.set_shader_parameter("cockpit_view", 1.0 if current_view_mode == CameraViewMode.INTERIOR_FPS else 0.0)
	travel_material.set_shader_parameter("aspect", get_viewport().get_visible_rect().size.aspect())

func toggle_cockpit_seat() -> bool:
	if is_seated_in_cockpit:
		# Koltuktan kalk -> Kabin içine adım at
		is_seated_in_cockpit = false
		if get_parent().has_method("_on_player_left_seat"):
			get_parent()._on_player_left_seat()
		cabin_player_pos = Vector3(0.0, CABIN_EYE_HEIGHT, -1.35)
		near_pilot_seat = true
		print("PİLOT KOLTUĞUNDAN KALKILDI: Kabin İçi FPS Modu Aktif")
	else:
		# Eğer koltuğa yakınsak otur
		if near_pilot_seat:
			is_airlock_open = false
			is_seated_in_cockpit = true
			cabin_player_pos = PILOT_SEAT_POS
			cabin_player_pitch = 0.0
			cabin_player_yaw = 0.0
			print("PİLOT KOLTUĞUNA OTURULDU: Uçuş Kontrolleri Aktif")
	return is_seated_in_cockpit

func toggle_airlock() -> bool:
	is_airlock_open = !is_airlock_open
	if is_airlock_open:
		vent_timer = 1.4 # Basınç tahliye buhar parıltısı
		print("HAVA KİLİDİ AÇILIYOR: Dış Kapak İndiriliyor (Vakum Uyarısı)")
	else:
		print("HAVA KİLİDİ KAPATILIYOR: Basınç Koruması Devrede")
	return is_airlock_open

func update_cabin_walking(delta: float, walk_input: Vector2, mouse_rel: Vector2) -> void:
	if is_seated_in_cockpit:
		# Koltuktayken pozisyon sabitlenir
		cabin_player_pos = PILOT_SEAT_POS
		near_pilot_seat = true
		near_airlock = false
		return
		
	# 1. Fare ile Kabin İçi Bakış (FPS Look)
	cabin_player_yaw -= mouse_rel.x * 0.003
	cabin_player_pitch = clamp(cabin_player_pitch - mouse_rel.y * 0.003, -1.35, 1.35)
	
	# 2. WASD ile Kabin İçi Yürüyüş (Yürüme Hızı: ~2.8 m/s)
	if walk_input.length_squared() > 0.01:
		var fwd = Vector3(-sin(cabin_player_yaw), 0.0, -cos(cabin_player_yaw)).normalized()
		var rgt = Vector3(cos(cabin_player_yaw), 0.0, -sin(cabin_player_yaw)).normalized()
		var move_dir = (fwd * -walk_input.y + rgt * walk_input.x).normalized()
		cabin_player_pos += move_dir * 2.0 * delta
		cabin_walk_phase += delta * 9.0
		
	# 3. Pilot Koltuğuna ve Hava Kilidine Yakınlık Kontrolü
	var dist_to_seat = cabin_player_pos.distance_to(PILOT_SEAT_POS)
	near_pilot_seat = (dist_to_seat < 1.35)
	near_airlock = (cabin_player_pos.z >= AIRLOCK_TRIGGER_Z)
	
	# 4. Kabin İçi ve Rampa Sınırları
	# Kapı açıksa oyuncu rampadan aşağıya doğru yürüyebilir (Z: 3.65)
	var door_clear := is_airlock_open and airlock_anim_progress > 0.95
	var max_z = 4.0 if door_clear else 2.45
	cabin_player_pos.x = clamp(cabin_player_pos.x, CABIN_MIN_X, CABIN_MAX_X)
	cabin_player_pos.z = clamp(cabin_player_pos.z, CABIN_MIN_Z, max_z)
	
	if door_clear and cabin_player_pos.z > 2.65:
		# Rampanın eğimini takip et (aşağı iniş açısı)
		var ramp_run = cabin_player_pos.z - 2.65
		cabin_player_pos.y = CABIN_EYE_HEIGHT - ramp_run * 0.7813
	else:
		cabin_player_pos.y = CABIN_EYE_HEIGHT

# ─────────────────────────────────────────────────────────────────────────────
# DİNAMİK UÇUŞ VE HAVA KİLİDİ ANİMASYONU
# ─────────────────────────────────────────────────────────────────────────────
func update_spacecraft(delta: float, input_dir: Vector3, is_warp: bool, is_autopilot: bool, mouse_turn_speed: Vector2 = Vector2.ZERO) -> void:
	if not is_instance_valid(ship_root):
		return
	# Enforce ownership here too: EVA/cabin inputs can never steer parked engines.
	var owner_node := get_parent()
	var propulsion_enabled: bool = is_seated_in_cockpit and current_view_mode != CameraViewMode.EVA and owner_node.get("is_eva_active") != true and owner_node.get("is_landed") != true and owner_node.get("is_system_map_active") != true
	if not propulsion_enabled:
		input_dir = Vector3.ZERO
		mouse_turn_speed = Vector2.ZERO
		is_warp = false
		is_autopilot = false
		
	# 1. Reaktör Nabız Parıltısı ve Çekirdek Dönüşü
	reactor_pulse += delta * 3.5
	if is_instance_valid(reactor_light):
		reactor_light.light_energy = 0.30 + sin(reactor_pulse) * 0.035
	if is_instance_valid(reactor_core_mesh):
		reactor_core_mesh.rotation.y += delta * 1.5

	# 2. Hava Kilidi ve İniş Rampası Hidrolik Hareketi
	var target_anim = 1.0 if is_airlock_open else 0.0
	airlock_anim_progress = lerp(airlock_anim_progress, target_anim, 1.0 - exp(-3.5 * delta))
	
	if is_instance_valid(airlock_hatch_pivot):
		# 0 derece: Dikey kapalı kapı, 128 derece: Aşağı inen rampa
		airlock_hatch_pivot.rotation_degrees.x = airlock_anim_progress * 128.0
		
	# Hidrolik kolların rampa açısına göre esnemesi
	if is_instance_valid(left_hydraulic_strut) and is_instance_valid(right_hydraulic_strut):
		var strut_angle = -25.0 + airlock_anim_progress * 28.0
		left_hydraulic_strut.rotation_degrees.x = strut_angle
		right_hydraulic_strut.rotation_degrees.x = strut_angle

	# Basınç Durum Işığı (Yeşil/Turkuaz: Kilitli & Basınçlı, Kırmızı/Amber Flaş: Açık & Vakum)
	if is_instance_valid(airlock_status_light) and is_instance_valid(airlock_status_mat):
		if airlock_anim_progress > 0.08:
			var flash = (sin(reactor_pulse * 3.0) + 1.0) * 0.5
			var alert_col = Color(1.0, 0.25, 0.05).lerp(Color(1.0, 0.65, 0.1), flash)
			airlock_status_light.light_color = alert_col
			airlock_status_light.light_energy = 0.35 + flash * 0.15
			airlock_status_mat.albedo_color = alert_col
			airlock_status_mat.emission = alert_col
		else:
			var normal_col = Color(0.1, 0.95, 0.8)
			airlock_status_light.light_color = normal_col
			airlock_status_light.light_energy = 0.25
			airlock_status_mat.albedo_color = normal_col
			airlock_status_mat.emission = normal_col

	# Basınç Tahliye Buhar Efekti (Vent Puff)
	if vent_timer > 0.0:
		vent_timer -= delta
		if is_instance_valid(airlock_vent_steam):
			airlock_vent_steam.visible = true
			var t = 1.0 - (vent_timer / 1.4)
			airlock_vent_steam.scale = Vector3(1.0 + t * 2.2, 1.0 + t * 2.2, 1.0 + t * 3.5)
			airlock_vent_steam.position.z = 2.7 + t * 1.2
	elif is_instance_valid(airlock_vent_steam):
		airlock_vent_steam.visible = false

	# 3. Kamera Görünüm Moduna Göre Model Görünürlüğü
	match current_view_mode:
		CameraViewMode.THIRD_PERSON:
			ship_root.visible = true
			if cabin_root != null: cabin_root.visible = true
		CameraViewMode.INTERIOR_FPS:
			ship_root.visible = true
			if cabin_root != null: cabin_root.visible = true
		CameraViewMode.FREE_CAM:
			ship_root.visible = false
		CameraViewMode.EVA:
			# Dış uzay yürüyüşünde tüm gemi dışı ve açık hava kilidi görünür olmalı
			ship_root.visible = true
			if cabin_root != null: cabin_root.visible = true

	# 4. İtici Gücü ve Alev Parlaklığı
	var target_intensity = 0.18 if propulsion_enabled else 0.0 # Parked engines are off.
	
	if is_warp:
		target_intensity = 3.4
		if flame_outer_mat != null:
			flame_outer_mat.emission = Color(0.65, 0.35, 1.0)
		if flame_core_mat != null:
			flame_core_mat.emission = Color(0.95, 0.85, 1.0)
		if thruster_light != null:
			thruster_light.light_color = Color(0.7, 0.4, 1.0)
	else:
		if flame_outer_mat != null:
			flame_outer_mat.emission = Color(0.1, 0.65, 1.0)
		if flame_core_mat != null:
			flame_core_mat.emission = Color(0.88, 0.96, 1.0)
		if thruster_light != null:
			thruster_light.light_color = Color(0.2, 0.8, 1.0)
			
		if is_autopilot:
			target_intensity = 1.6
		elif input_dir.z < -0.1:
			target_intensity = 2.2
		elif input_dir.length_squared() > 0.1:
			target_intensity = 1.0
			
	for flame in [left_thruster_flame, right_thruster_flame, left_inner_flame, right_inner_flame]:
		if is_instance_valid(flame):
			flame.visible = propulsion_enabled
	flame_intensity = lerp(flame_intensity, target_intensity, 1.0 - exp(-12.0 * delta))
	
	var flame_scale_z = clamp(flame_intensity, 0.35, 3.4)
	var flame_scale_xy = clamp(0.75 + flame_intensity * 0.25, 0.75, 1.6)
	
	for flame in [left_thruster_flame, right_thruster_flame]:
		if is_instance_valid(flame):
			flame.scale = Vector3(flame_scale_xy, flame_scale_z, flame_scale_xy)
			flame.position.z = 1.1 + flame_scale_z * 1.1
			
	for core in [left_inner_flame, right_inner_flame]:
		if is_instance_valid(core):
			core.scale = Vector3(flame_scale_xy * 0.8, flame_scale_z * 0.9, flame_scale_xy * 0.8)
			core.position.z = 1.0 + flame_scale_z * 0.8
			
	if is_instance_valid(thruster_light):
		thruster_light.light_energy = flame_intensity * 0.8 if propulsion_enabled else 0.0
		
	var navigation = get_parent()
	var has_thrust: bool = is_warp or is_autopilot or (input_dir.length_squared() > 0.05)
	var travel_allowed: bool = is_seated_in_cockpit and has_thrust and navigation.get("is_eva_active") != true and navigation.get("is_landed") != true and navigation.get("is_system_map_active") != true
	var speed: float = float(navigation.get("flight_speed_mps")) if navigation.get("flight_speed_mps") != null else 0.0
	update_travel_effect(delta, speed, travel_allowed)
	for instrument in instrument_materials:
		instrument.set_shader_parameter("power", flame_intensity / 3.4)
	var landed: bool = get_parent().get("is_landed") == true
	landing_deployment = lerpf(landing_deployment, 1.0 if landed else 0.0, 1.0 - exp(-3.0 * delta))
	landing_gear_root.scale.y = maxf(0.05, landing_deployment)
	landing_gear_root.visible = landing_deployment > 0.02
	# Slight exhaust modulation communicates thrust without flickering the stars.
	var exhaust_pulse := 1.0 + sin(reactor_pulse * 8.0) * 0.035
	for flame in [left_thruster_flame, right_thruster_flame]:
		flame.scale.y *= exhaust_pulse

	# 5. İtici Vektörlemesi (Thrust Vectoring)
	var target_vec_yaw = clamp(mouse_turn_speed.x * 0.22 + input_dir.x * 0.15, -0.28, 0.28)
	var target_vec_pitch = clamp(mouse_turn_speed.y * 0.22 - input_dir.y * 0.15, -0.22, 0.22)
	engine_vector_yaw = lerp(engine_vector_yaw, target_vec_yaw, 1.0 - exp(-10.0 * delta)) if propulsion_enabled else 0.0
	engine_vector_pitch = lerp(engine_vector_pitch, target_vec_pitch, 1.0 - exp(-10.0 * delta)) if propulsion_enabled else 0.0
	
	if is_instance_valid(engines_root):
		engines_root.rotation = Vector3(engine_vector_pitch, engine_vector_yaw, 0.0)

	# 6. Aerodinamik Gövde Yatması (Banking / Roll Lean & Pitch Inertia)
	if propulsion_enabled and current_view_mode == CameraViewMode.THIRD_PERSON:
		var roll_from_keys = -input_dir.x * 0.40
		var roll_from_mouse = -clamp(mouse_turn_speed.x * 0.07, -0.32, 0.32)
		target_tilt_roll = roll_from_keys + roll_from_mouse
		current_tilt_roll = lerp_angle(current_tilt_roll, target_tilt_roll, 1.0 - exp(-7.0 * delta))
		
		var pitch_from_thrust = -0.04 if input_dir.z < -0.1 else 0.0
		var pitch_from_vert = -input_dir.y * 0.18
		var pitch_from_mouse = clamp(mouse_turn_speed.y * 0.05, -0.18, 0.18)
		target_tilt_pitch = pitch_from_vert + pitch_from_thrust + pitch_from_mouse
		current_tilt_pitch = lerp_angle(current_tilt_pitch, target_tilt_pitch, 1.0 - exp(-7.0 * delta))
		
		target_tilt_yaw = clamp(mouse_turn_speed.x * 0.035, -0.12, 0.12)
		current_tilt_yaw = lerp_angle(current_tilt_yaw, target_tilt_yaw, 1.0 - exp(-6.0 * delta))
		
		ship_root.rotation = Vector3(current_tilt_pitch, current_tilt_yaw, current_tilt_roll)
	else:
		ship_root.rotation = ship_root.rotation.lerp(Vector3.ZERO, 1.0 - exp(-6.0 * delta))

# Kamera Perspektifini Değiştir (F tuşu)
func cycle_camera_mode() -> String:
	match current_view_mode:
		CameraViewMode.THIRD_PERSON:
			current_view_mode = CameraViewMode.INTERIOR_FPS
			return "KABİN İÇİ FPS (YÜRÜYÜŞ & KOKPİT)"
		CameraViewMode.INTERIOR_FPS:
			current_view_mode = CameraViewMode.FREE_CAM
			return "SERBEST BAKIŞ (GİZLİ GEMİ)"
		CameraViewMode.FREE_CAM:
			current_view_mode = CameraViewMode.THIRD_PERSON
			return "3. ŞAHIS (DIŞ GEMİ TAKİBİ)"
		CameraViewMode.EVA:
			# EVA modunda serbest kamera veya astronot bakışı
			return "ASTRONOT UZAY YÜRÜYÜŞÜ (EVA)"
		_:
			current_view_mode = CameraViewMode.THIRD_PERSON
			return "3. ŞAHIS (DIŞ GEMİ TAKİBİ)"
