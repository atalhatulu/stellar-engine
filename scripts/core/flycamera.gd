extends Node3D

@export var mouse_sensitivity: float = 0.002

const LIGHT_SPEED: float = 299792458.0
const ONE_AU: float = 149597870700.0
const LIGHT_YEAR: float = 9460730472580800.0

var speed_presets: Array = [
	5.0, 50.0, 343.0, 3000.0, 30000.0, 300000.0,
	0.001 * LIGHT_SPEED, 0.01 * LIGHT_SPEED, 0.05 * LIGHT_SPEED,
	0.1 * LIGHT_SPEED, 0.25 * LIGHT_SPEED, 0.5 * LIGHT_SPEED,
	1.0 * LIGHT_SPEED, 2.0 * LIGHT_SPEED, 5.0 * LIGHT_SPEED,
	10.0 * LIGHT_SPEED, 100.0 * LIGHT_SPEED, 1000.0 * LIGHT_SPEED,
	1.0 * ONE_AU, 5.0 * ONE_AU, 10.0 * ONE_AU, 100.0 * ONE_AU, 1000.0 * ONE_AU,
	0.01 * LIGHT_YEAR, 0.05 * LIGHT_YEAR, 0.1 * LIGHT_YEAR, 0.5 * LIGHT_YEAR,
	1.0 * LIGHT_YEAR, 2.0 * LIGHT_YEAR, 5.0 * LIGHT_YEAR, 10.0 * LIGHT_YEAR,
	25.0 * LIGHT_YEAR, 50.0 * LIGHT_YEAR, 100.0 * LIGHT_YEAR, 250.0 * LIGHT_YEAR,
	500.0 * LIGHT_YEAR, 1000.0 * LIGHT_YEAR, 2500.0 * LIGHT_YEAR, 5000.0 * LIGHT_YEAR,
	10000.0 * LIGHT_YEAR, 25000.0 * LIGHT_YEAR, 50000.0 * LIGHT_YEAR, 100000.0 * LIGHT_YEAR
]

var speed_multiplier_index: int = 3
var current_speed: float = 0.0
var target_speed: float = 0.0

# Kararlı Euler açı takibi
var rot_x: float = 0.0 # Pitch
var rot_y: float = 0.0 # Yaw
var rot_z: float = 0.0 # Roll
var mouse_turn_speed: Vector2 = Vector2.ZERO # Dinamik gemi yatması ve kamera yaylanması

const SpacecraftScript = preload("res://scripts/core/spacecraft.gd")

@onready var camera_node: Camera3D = $Camera3D
var third_person_distance: float = 14.0
const MIN_THIRD_PERSON_DIST: float = 7.5
const MAX_THIRD_PERSON_DIST: float = 35.0
var spacecraft = null
var headlamp: SpotLight3D = null # Outer Wilds Kask Feneri (L Tuşu)

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	target_speed = speed_presets[speed_multiplier_index]
	current_speed = target_speed
	
	var euler = transform.basis.get_euler()
	rot_x = euler.x
	rot_y = euler.y
	rot_z = euler.z
	
	# Outer Wilds Kask Feneri (Headlamp)
	headlamp = SpotLight3D.new()
	headlamp.name = "AstronautHeadlamp"
	headlamp.light_color = Color(0.95, 0.98, 1.0)
	headlamp.light_energy = 3.2
	headlamp.spot_range = 95.0
	headlamp.spot_angle = 40.0
	headlamp.spot_attenuation = 1.1
	headlamp.position = Vector3(0.0, -0.1, -0.2)
	headlamp.visible = true
	if camera_node != null:
		camera_node.add_child(headlamp)
	else:
		add_child(headlamp)
	
	# Sahnede ayrı bulunan Spacecraft düğümüne bağlan (Artık çocuğumuz değil!)
	if spacecraft == null and get_parent() != null:
		spacecraft = get_parent().get_node_or_null("Spacecraft")
	if spacecraft != null:
		_update_camera_view(true)

func _process(delta):
	current_speed = lerp(current_speed, target_speed, 1.0 - exp(-8.0 * delta))
	
	# Fare dönüş ivmesini sönümle
	mouse_turn_speed = mouse_turn_speed.lerp(Vector2.ZERO, 6.0 * delta)
	
	# Kabin İçi FPS ve Yürüyüş Kontrolü
	var is_walking_in_cabin = false
	if spacecraft != null:
		if spacecraft.current_view_mode == SpacecraftScript.CameraViewMode.INTERIOR_FPS and not spacecraft.is_seated_in_cockpit:
			is_walking_in_cabin = true
			var walk_input = Vector2.ZERO
			if Input.is_key_pressed(KEY_W): walk_input.y -= 1.0
			if Input.is_key_pressed(KEY_S): walk_input.y += 1.0
			if Input.is_key_pressed(KEY_A): walk_input.x -= 1.0
			if Input.is_key_pressed(KEY_D): walk_input.x += 1.0
			spacecraft.update_cabin_walking(delta, walk_input, Vector2.ZERO)
			
			# Eğer hava kilidi açıksa ve oyuncu rampanın ucuna kadar yürüdüyse: Dışarı çık (EVA)
			if spacecraft.is_airlock_open and spacecraft.airlock_anim_progress > 0.95 and spacecraft.cabin_player_pos.z >= 3.75:
				var p = get_parent()
				if p != null and p.has_method("start_eva_mode"):
					p.start_eva_mode()

	_update_camera_view(false, delta)
	
	# Uçuş Kontrolleri ve İtici Dinamikleri (Koltuktayken veya 3. Şahıstayken sürülür)
	if spacecraft != null:
		var input_dir = Vector3.ZERO
		var is_eva = false
		if get_parent() and get_parent().get("is_eva_active") == true:
			is_eva = true
			
		# SADECE koltukta otururken gemi motorları sürülür!
		if not is_walking_in_cabin and not is_eva and (spacecraft == null or spacecraft.is_seated_in_cockpit):
			if Input.is_key_pressed(KEY_W): input_dir.z -= 1.0
			if Input.is_key_pressed(KEY_S): input_dir.z += 1.0
			if Input.is_key_pressed(KEY_A): input_dir.x -= 1.0
			if Input.is_key_pressed(KEY_D): input_dir.x += 1.0
			if Input.is_key_pressed(KEY_SPACE): input_dir.y += 1.0
			if Input.is_key_pressed(KEY_CTRL): input_dir.y -= 1.0
		
		var is_warp = false
		var is_auto = false
		if get_parent():
			is_warp = (get_parent().get("is_interstellar_autopilot") == true) or (get_parent().get("is_hyper_autopilot") == true)
			is_auto = get_parent().get("is_autopilot_active") == true
			
		spacecraft.update_spacecraft(delta, input_dir, is_warp, is_auto, mouse_turn_speed)
	
	# Roll kontrolü (Q / E tuşları) - Koltuktayken veya 3. şahıstayken
	var roll_input = 0.0
	var is_eva_mode = false
	if get_parent() and get_parent().get("is_eva_active") == true:
		is_eva_mode = true
		
	if not is_walking_in_cabin and not is_eva_mode:
		if Input.is_key_pressed(KEY_Q): roll_input += 1.0
	
	var is_landed = false
	if get_parent() and get_parent().get("is_landed"):
		is_landed = true
	
	if roll_input != 0.0 and not is_landed and not is_walking_in_cabin and not is_eva_mode:
		transform.basis = transform.basis.rotated(transform.basis.z.normalized(), -roll_input * 1.5 * delta)
		transform.basis = transform.basis.orthonormalized()
		var euler = transform.basis.get_euler()
		rot_x = euler.x
		rot_y = euler.y
		rot_z = euler.z

func _input(event):
	var is_camera_disabled = false
	if get_parent():
		if get_parent().get("is_system_map_active"):
			is_camera_disabled = true
		elif get_parent().get("is_autopilot_active") or get_parent().get("is_interstellar_autopilot"):
			if event is InputEventMouseMotion and event.relative.length_squared() > 4.0:
				get_parent().set("is_autopilot_active", false)
				get_parent().set("is_hyper_autopilot", false)
				get_parent().set("is_interstellar_autopilot", false)
				get_parent().set("is_interstellar_hyper_boost", false)
				get_parent().set("is_focusing_target", false)
				get_parent().set("autopilot_target_body", null)
				is_camera_disabled = false
			else:
				is_camera_disabled = true
			
	# İnteraktif Etkileşimler (E tuşu: Koltuk / Hava Kilidi / Gemiye Binme)
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_E:
			var parent_node = get_parent()
			
			# 1. Eğer dışarıda EVA modundaysak ve hava kilidine yakınsak: Gemiye gir
			if parent_node != null and parent_node.get("is_eva_active") == true:
				if parent_node.get("is_near_ship_airlock") == true:
					parent_node.end_eva_mode()
					get_viewport().set_input_as_handled()
					return
					
			# 2. Kabin içindeyken etkileşim (Hava Kilidi veya Pilot Koltuğu)
			if spacecraft != null and spacecraft.current_view_mode == SpacecraftScript.CameraViewMode.INTERIOR_FPS:
				if spacecraft.near_airlock:
					spacecraft.toggle_airlock()
					get_viewport().set_input_as_handled()
					return
				elif spacecraft.near_pilot_seat:
					spacecraft.toggle_cockpit_seat()
					get_viewport().set_input_as_handled()
					return
				
	# Fare Hareketi (Bakış ve Yönlendirme)
	if not is_camera_disabled and event is InputEventMouseMotion:
		if get_parent() and get_parent().get("is_focusing_target") and event.relative.length_squared() > 1.0:
			get_parent().set("is_focusing_target", false)
			get_parent().set("focus_target_body", null)
			get_parent().set("focus_target_star", null)
			get_parent().set("focus_time", 0.0)
			
		# Eğer kabin içi yürüyüş modundaysak ve koltukta değilsek: Oyuncunun kafasını kabin içinde çevir
		if spacecraft != null and spacecraft.current_view_mode == SpacecraftScript.CameraViewMode.INTERIOR_FPS and not spacecraft.is_seated_in_cockpit:
			spacecraft.update_cabin_walking(0.016, Vector2.ZERO, event.relative)
			return

		var is_landed = false
		if get_parent() and get_parent().get("is_landed"):
			is_landed = true
			
		if is_landed:
			rot_y -= event.relative.x * mouse_sensitivity
			rot_x -= event.relative.y * mouse_sensitivity
			rot_x = clamp(rot_x, -PI / 2.2, PI / 2.2)
			var surface_basis = get_parent().get("landed_ship_basis") if get_parent() != null and get_parent().get("landed_ship_basis") is Basis else Basis.IDENTITY
			transform.basis = surface_basis * Basis.from_euler(Vector3(rot_x, rot_y, 0.0))
		else:
			var yaw_delta = -event.relative.x * mouse_sensitivity
			var pitch_delta = -event.relative.y * mouse_sensitivity
			
			transform.basis = transform.basis.rotated(transform.basis.y.normalized(), yaw_delta)
			transform.basis = transform.basis.rotated(transform.basis.x.normalized(), pitch_delta)
			transform.basis = transform.basis.orthonormalized()
			
			mouse_turn_speed = mouse_turn_speed.lerp(Vector2(event.relative.x, event.relative.y), 0.45)
			
			var euler = transform.basis.get_euler()
			rot_x = euler.x
			rot_y = euler.y
			rot_z = euler.z
	
	if event is InputEventMouseButton and event.pressed:
		var in_third_person: bool = false
		if spacecraft != null and spacecraft.current_view_mode == SpacecraftScript.CameraViewMode.THIRD_PERSON:
			in_third_person = true
			
		if in_third_person and not event.shift_pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				third_person_distance = clampf(third_person_distance - 1.5, MIN_THIRD_PERSON_DIST, MAX_THIRD_PERSON_DIST)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				third_person_distance = clampf(third_person_distance + 1.5, MIN_THIRD_PERSON_DIST, MAX_THIRD_PERSON_DIST)
		else:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				speed_multiplier_index = min(speed_multiplier_index + 1, speed_presets.size() - 1)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				speed_multiplier_index = max(speed_multiplier_index - 1, 0)
			target_speed = speed_presets[speed_multiplier_index]
		
	# Kamera Görünüm Modu Değiştirme (F tuşu: 3. Şahıs / Kabin İçi FPS / Serbest)
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F:
			if spacecraft != null and (spacecraft.is_seated_in_cockpit or spacecraft.current_view_mode == SpacecraftScript.CameraViewMode.EVA):
				var mode_str = spacecraft.cycle_camera_mode()
				print("KAMERA MODU: ", mode_str)
		elif event.keycode == KEY_H:
			if headlamp != null:
				headlamp.visible = !headlamp.visible
				print("OUTER WILDS KASK FENERİ: ", "AÇIK" if headlamp.visible else "KAPALI")
		elif event.keycode == KEY_BRACKETLEFT:
			speed_multiplier_index = max(speed_multiplier_index - 1, 0)
			target_speed = speed_presets[speed_multiplier_index]
		elif event.keycode == KEY_BRACKETRIGHT:
			speed_multiplier_index = min(speed_multiplier_index + 1, speed_presets.size() - 1)
			target_speed = speed_presets[speed_multiplier_index]

func _update_camera_view(instant: bool = false, delta: float = 0.016) -> void:
	if camera_node == null:
		return
		
	var target_cam_pos = Vector3.ZERO
	var target_cam_rot = Vector3.ZERO
	var t_int: float = spacecraft.travel_intensity if spacecraft != null else 0.0
	var w_int: float = spacecraft.warp_intensity if spacecraft != null else 0.0
	var t_phase: float = spacecraft.travel_phase if spacecraft != null else 0.0
	
	if spacecraft != null:
		match spacecraft.current_view_mode:
			SpacecraftScript.CameraViewMode.THIRD_PERSON:
				var sway_x = clamp(-mouse_turn_speed.x * 0.006, -0.4, 0.4)
				var sway_y = clamp(mouse_turn_speed.y * 0.005, -0.3, 0.3)
				var cam_dist = third_person_distance + t_int * 7.5 + w_int * 14.0
				var cam_height = 2.5 + (third_person_distance - MIN_THIRD_PERSON_DIST) * 0.18 + (t_int * 2.0) + sway_y
				target_cam_pos = Vector3(sway_x, cam_height, cam_dist)
				var warp_roll_deg: float = sin(t_phase * 1.8) * (t_int * 2.8 + w_int * 3.5)
				var warp_pitch_deg: float = cos(t_phase * 1.4) * (t_int * 1.5 + w_int * 2.0)
				target_cam_rot = Vector3(-3.2 + sway_y * 4.0 + warp_pitch_deg, sway_x * 6.0, -sway_x * 8.0 + warp_roll_deg)
			SpacecraftScript.CameraViewMode.INTERIOR_FPS:
				target_cam_pos = to_local(spacecraft.to_global(spacecraft.cabin_player_pos))
				if not spacecraft.is_seated_in_cockpit:
					target_cam_pos.y += sin(spacecraft.cabin_walk_phase) * 0.012
					target_cam_rot = Vector3(rad_to_deg(spacecraft.cabin_player_pitch), rad_to_deg(spacecraft.cabin_player_yaw), 0.0)
				else:
					var shake_roll = sin(t_phase * 2.2) * (t_int * 0.8)
					var shake_pitch = cos(t_phase * 1.7) * (t_int * 0.5)
					target_cam_rot = Vector3(shake_pitch, 0.0, shake_roll)
			SpacecraftScript.CameraViewMode.FREE_CAM:
				target_cam_pos = Vector3.ZERO
				target_cam_rot = Vector3.ZERO
			SpacecraftScript.CameraViewMode.EVA:
				# EVA modunda kamera astronotun kaskının içindedir
				target_cam_pos = Vector3.ZERO
				target_cam_rot = Vector3.ZERO
				
	var warp_fov := 78.0 + t_int * 15.0 + w_int * 12.0
	camera_node.fov = lerpf(camera_node.fov, warp_fov, 1.0 - exp(-3.0 * delta))
	if instant:
		camera_node.position = target_cam_pos
		camera_node.rotation_degrees = target_cam_rot
	else:
		camera_node.position = camera_node.position.lerp(target_cam_pos, 1.0 - exp(-10.0 * delta))
		camera_node.rotation_degrees = camera_node.rotation_degrees.lerp(target_cam_rot, 1.0 - exp(-10.0 * delta))

func set_speed_to_match_body(body_radius: float) -> void:
	var desired_speed = body_radius * 0.05
	var closest_index = 0
	var min_diff = INF
	for i in range(speed_presets.size()):
		var diff = abs(speed_presets[i] - desired_speed)
		if diff < min_diff:
			min_diff = diff
			closest_index = i
	speed_multiplier_index = closest_index
	target_speed = speed_presets[closest_index]

func reset_camera_orientation(new_basis: Basis) -> void:
	transform.basis = new_basis
	var euler = new_basis.get_euler()
	rot_x = euler.x
	rot_y = euler.y
	rot_z = euler.z
	_update_camera_view(true)
