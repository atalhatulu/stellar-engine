class_name CelestialBody
extends RefCounted

var name: String
var type: String
var unique_id: String = ""
var parent_id: String = ""
var galaxy_id: String = ""
var system_id: String = ""
var body_seed: int = 0
var real_radius: float
var real_position: Vector3
var local_position: Vector3
var is_lod: bool = false

var visual_mesh: MeshInstance3D
var atmosphere_mesh: MeshInstance3D # Atmosfer efekti için mesh
var ring_mesh: MeshInstance3D
var orbit_line_mesh: MeshInstance3D # Yörünge çizgisi efekti için mesh
var orbit_sample_points: PackedVector3Array = PackedVector3Array() # 3B uzaydaki yörünge örnek noktaları
var lod_sprite: Sprite3D # Yıldızların uzaktaki 2D görünümü için Sprite3D
var noise_albedo: NoiseTexture2D
var noise_normal: NoiseTexture2D


var parent_body: CelestialBody = null
var orbit_radius: float
var orbit_speed: float
var orbit_angle: float
var orbit_inclination: float = 0.0 # Radyan cinsinden yörünge eğikliği
var orbit_eccentricity: float = 0.0
var argument_of_periapsis: float = 0.0
var longitude_ascending_node: float = 0.0
var rotation_speed: float
var rotation_angle: float
var axial_tilt: float = 0.0   # Radyan cinsinden eksenel eğim (0 = dik, PI/2 = yan yatmış)

var moon_count: int = 0
var max_visibility_distance: float = INF

# Yıldız özellikleri
var light_color: Color = Color.WHITE
var light_energy: float = 1.0
var luminosity: float = 1.0
var mass_solar: float = 1.0
var age_billion_years: float = 4.6
var temperature_kelvin: float = 5778.0
var metallicity: float = 0.0
var stellar_activity: float = 1.0
var spectral_type: String = ""
var system_type: String = "STANDARD"
var planet_type: String = ""
var system_diameter: float = 0.0
var sys_seed: int = 0
var star_index: int = 0

# Spawn/Despawn ve dinamik görsellik verileri
var base_color: Color = Color.WHITE
var roughness: float = 0.5
var metallic: float = 0.0
var has_atmosphere: bool = false
var atmosphere_color: Color = Color(0, 0, 0, 0)

# Gezegen iklimi ve yaşanabilirlik verileri
var climate_zone: String = ""
var habitable_zone_inner: float = 0.0
var habitable_zone_outer: float = 0.0
var mass_earth: float = 0.0
var surface_gravity_g: float = 0.0
var atmosphere_pressure_bar: float = 0.0
var surface_temperature_k: float = 0.0
var water_fraction: float = 0.0
var habitability_score: float = 0.0
var is_habitable: bool = false
var atmosphere_composition: Dictionary = {}
var atmosphere_class: String = "VACUUM"
var atmosphere_description: String = "Vakum"
var rotation_period_hours: float = 0.0
var orbital_period_days: float = 0.0
var is_tidally_locked: bool = false
var magnetic_field_earth: float = 0.0
var radiation_level: float = 0.0
var life_level: String = "NONE"
var life_description: String = "Yaşam izi yok"
var civilization_level: String = "NONE"
var has_city_lights: bool = false
var has_subsurface_ocean: bool = false
var has_rings: bool = false
var ring_inner_ratio: float = 0.0
var ring_outer_ratio: float = 0.0
var ring_density: float = 0.0
var ring_color: Color = Color.WHITE
var asteroid_belts: Array[Dictionary] = []
var asteroid_belt_instances: Array[MultiMeshInstance3D] = []

func get_orbit_position_at_mean_anomaly(mean_anomaly: float) -> Vector3:
	var e := clampf(orbit_eccentricity, 0.0, 0.82)
	var m := fposmod(mean_anomaly, TAU)
	var eccentric_anomaly := m
	for _iteration in range(5):
		eccentric_anomaly -= (eccentric_anomaly - e * sin(eccentric_anomaly) - m) / maxf(1.0 - e * cos(eccentric_anomaly), 0.001)
	var semi_major := maxf(orbit_radius, 1.0)
	var semi_minor := semi_major * sqrt(maxf(1.0 - e * e, 0.001))
	# Odak ebeveyndedir; elips merkezi e*a kadar kayıktır.
	var position := Vector3(
		semi_major * (cos(eccentric_anomaly) - e),
		0.0,
		semi_minor * sin(eccentric_anomaly)
	)
	position = position.rotated(Vector3.UP, argument_of_periapsis)
	position = position.rotated(Vector3.RIGHT, orbit_inclination)
	position = position.rotated(Vector3.UP, longitude_ascending_node)
	return position

func get_orbit_position() -> Vector3:
	return get_orbit_position_at_mean_anomaly(orbit_angle)

# Sistem 64-bit koordinatları (titremeyi önlemek için)
var stellar_x: float = 0.0
var stellar_y: float = 0.0
var stellar_z: float = 0.0

# Sistem yıldızını bulur
func get_system_star() -> CelestialBody:
	var current = self
	while current.parent_body != null:
		current = current.parent_body
	return current

# Sistem yıldızına olan mesafeyi (offset) hesaplar
func get_offset_from_system_star() -> Vector3:
	if parent_body == null:
		return Vector3.ZERO
	else:
		return parent_body.get_offset_from_system_star() + local_position

# Yıldızın sistem koordinatlarına göre mutlak pozisyonunu hesaplar
func get_absolute_position(active_star: CelestialBody) -> Vector3:
	var body_star = get_system_star()
	var body_offset = get_offset_from_system_star()
	
	if active_star == null:
		return body_offset + body_star.local_position
		
	var dx = body_star.stellar_x - active_star.stellar_x
	var dy = body_star.stellar_y - active_star.stellar_y
	var dz = body_star.stellar_z - active_star.stellar_z
	
	return Vector3(dx, dy, dz) + body_offset
