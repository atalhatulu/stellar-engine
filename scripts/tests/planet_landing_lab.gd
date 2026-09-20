class_name PlanetLandingLab
extends Node3D

const PlanetSphere = preload("res://scripts/rendering/planet_chunk_sphere.gd")

@export var planet_radius := 200000.0
@export var landing_clearance := 12.0
@export var landing_duration := 9.0

@onready var camera_rig: Node3D = $FreeLookCamera
@onready var camera: Camera3D = $FreeLookCamera/Camera3D
@onready var status_label: Label = $UILayer/StatusPanel/Margin/VBox/Status
@onready var telemetry_label: Label = $UILayer/StatusPanel/Margin/VBox/Telemetry
@onready var progress_bar: ProgressBar = $UILayer/StatusPanel/Margin/VBox/Progress

var planet: PlanetChunkSphere
var smooth_globe: MeshInstance3D
var noise := FastNoiseLite.new()
var landing_active := false
var landing_elapsed := 0.0
var landing_start := Vector3.ZERO
var landing_direction := Vector3.FORWARD
var landing_target := Vector3.ZERO

func _ready() -> void:
	process_priority = 10 # FreeLookCamera hareketinden sonra zemin çarpışmasını uygula.
	noise.seed = 424243
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.015
	noise.fractal_octaves = 5
	planet = PlanetSphere.new()
	planet.name = "ProceduralPlanet"
	add_child(planet)
	planet.initialize(noise, planet_radius)
	var material := _build_terrain_material()
	planet.set_material(material)
	_build_smooth_globe(Color(0.26, 0.34, 0.22))
	_reset_approach(3.0)
	_update_status("YÖRÜNGE YAKLAŞMASI")

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_L:
			_start_landing()
		KEY_R:
			_reset_approach(3.0)
		KEY_1:
			_reset_approach(6.0)
		KEY_2:
			_reset_approach(3.0)
		KEY_3:
			_reset_approach(1.02)
		KEY_4:
			_reset_surface_probe()
		KEY_V:
			planet.toggle_debug_colors()
		KEY_B:
			planet.set_borders_visible(not planet._border_visible)

func _process(delta: float) -> void:
	if landing_active:
		landing_elapsed += delta
		var t := clampf(landing_elapsed / landing_duration, 0.0, 1.0)
		var eased := t * t * (3.0 - 2.0 * t)
		camera_rig.global_position = landing_start.lerp(landing_target, eased)
		_face_planet_horizon()
		progress_bar.value = t * 100.0
		_update_status("SON YAKLAŞMA" if t > 0.72 else "KONTROLLÜ ALÇALMA")
		if t >= 1.0:
			landing_active = false
			_update_status("YÜZEY TEMASI — TEST TAMAMLANDI")

	_clamp_camera_above_terrain()

	var camera_position := camera_rig.global_position
	planet.update(Vector3.ZERO, Vector3.ZERO, planet_radius,
		camera_position, Vector3.ZERO, -camera.global_basis.z)
	var radius_ratio := camera_position.length() / planet_radius
	var terrain_blend := smoothstep(0.0, 1.0, clampf((5.5 - radius_ratio) / 2.75, 0.0, 1.0))
	planet.set_visibility_alpha(terrain_blend)
	smooth_globe.transparency = terrain_blend
	smooth_globe.visible = terrain_blend < 0.999
	var altitude := maxf(camera_position.length() - _surface_radius(camera_position.normalized()), 0.0)
	var stats := planet.get_lod_stats()
	telemetry_label.text = "İRTİFA  %s\nLOD  %d  ·  GÖRÜNÜR PARÇA  %d\nARAZİ GEÇİŞİ  %d%%  ·  FPS  %d" % [
		_format_distance(altitude), _deepest_visible_lod(stats.get("lod_counts", {})),
		stats.get("total_chunks", 0), roundi(terrain_blend * 100.0), Engine.get_frames_per_second()]

func _build_smooth_globe(color: Color) -> void:
	smooth_globe = MeshInstance3D.new()
	smooth_globe.name = "SmoothMacroGlobe"
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 96
	sphere.rings = 48
	smooth_globe.mesh = sphere
	smooth_globe.scale = Vector3.ONE * planet_radius
	var material := StandardMaterial3D.new()
	material.albedo_color = color.darkened(0.06)
	material.roughness = 0.94
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	smooth_globe.material_override = material
	add_child(smooth_globe)
	move_child(smooth_globe, planet.get_index())

func _build_terrain_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
varying float terrain_height;
varying float terrain_slope;
void vertex() {
	terrain_height = length(VERTEX) - 1.0;
	terrain_slope = 1.0 - clamp(dot(normalize(VERTEX), normalize(NORMAL)), 0.0, 1.0);
}
void fragment() {
	float highland = smoothstep(0.004, 0.026, terrain_height);
	float peak = smoothstep(0.026, 0.052, terrain_height);
	float cliff = smoothstep(0.035, 0.22, terrain_slope);
	vec3 low_color = vec3(0.12, 0.20, 0.11);
	vec3 rock_color = vec3(0.34, 0.30, 0.24);
	vec3 peak_color = vec3(0.55, 0.55, 0.51);
	ALBEDO = mix(mix(low_color, rock_color, max(highland, cliff)), peak_color, peak);
	ROUGHNESS = 0.92;
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	return material

func _start_landing() -> void:
	if landing_active:
		return
	landing_direction = camera_rig.global_position.normalized()
	landing_start = camera_rig.global_position
	landing_target = landing_direction * (_surface_radius(landing_direction) + landing_clearance)
	landing_elapsed = 0.0
	landing_active = true
	progress_bar.value = 0.0

func _reset_approach(radius_multiplier: float) -> void:
	landing_active = false
	landing_elapsed = 0.0
	progress_bar.value = 0.0
	camera_rig.global_position = Vector3(0.32, 0.20, 1.0).normalized() * planet_radius * radius_multiplier
	_face_planet_horizon()
	_update_status("YAKLAŞMA PRESETİ  %.2fR" % radius_multiplier)

func _reset_surface_probe() -> void:
	landing_active = false
	landing_elapsed = 0.0
	progress_bar.value = 100.0
	var direction := Vector3(0.32, 0.20, 1.0).normalized()
	camera_rig.global_position = direction * (_surface_radius(direction) + landing_clearance)
	_face_planet_horizon()
	_update_status("YÜZEY LOD KONTROLÜ — LOD 11 HEDEFİ")

func _surface_radius(direction: Vector3) -> float:
	return planet_radius * (1.0 + PlanetSphere.sample_terrain_height_static(noise, direction, planet_radius))

func _clamp_camera_above_terrain() -> void:
	if camera_rig.global_position.length_squared() < 1.0:
		camera_rig.global_position = Vector3.UP * (planet_radius + landing_clearance)
	var direction := camera_rig.global_position.normalized()
	var minimum_radius := _surface_radius(direction) + 2.0
	if camera_rig.global_position.length() < minimum_radius:
		camera_rig.global_position = direction * minimum_radius

func _face_planet_horizon() -> void:
	var radial_up := camera_rig.global_position.normalized()
	var radius_ratio := camera_rig.global_position.length() / planet_radius
	if radius_ratio < 1.25:
		var tangent := radial_up.cross(Vector3.UP).normalized()
		if tangent.length_squared() < 0.01:
			tangent = radial_up.cross(Vector3.RIGHT).normalized()
		var surface_forward := (tangent - radial_up * 0.08).normalized()
		camera_rig.look_at(camera_rig.global_position + surface_forward, radial_up)
		return
	var view_up := Vector3.UP
	if absf(radial_up.dot(view_up)) > 0.94:
		view_up = Vector3.RIGHT
	camera_rig.look_at(Vector3.ZERO, view_up)

func _deepest_visible_lod(counts: Dictionary) -> int:
	var deepest := 0
	for level in counts:
		if int(counts[level]) > 0:
			deepest = maxi(deepest, int(level))
	return deepest

func _update_status(value: String) -> void:
	status_label.text = value

func _format_distance(meters: float) -> String:
	if meters >= 1000.0:
		return "%.2f km" % (meters / 1000.0)
	return "%.1f m" % meters
