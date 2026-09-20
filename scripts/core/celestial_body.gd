class_name CelestialBody
extends RefCounted

var name: String
var type: String
var real_radius: float
var real_position: Vector3
var local_position: Vector3
var is_lod: bool = false

var visual_mesh: MeshInstance3D
var atmosphere_mesh: MeshInstance3D # Atmosfer efekti için mesh
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
var rotation_speed: float
var rotation_angle: float
var axial_tilt: float = 0.0   # Radyan cinsinden eksenel eğim (0 = dik, PI/2 = yan yatmış)

var moon_count: int = 0
var max_visibility_distance: float = INF

# Yıldız özellikleri
var light_color: Color = Color.WHITE
var light_energy: float = 1.0
var luminosity: float = 1.0
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
