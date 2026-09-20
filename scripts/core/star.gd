class_name Star
extends CelestialBody

# Yıldız sistemleri için ortak veri modeli. Görsel oluşturma SystemGenerator'da,
# sahne akışı ise main_star/main_galaxy denetleyicilerinde kalır.
var catalog_id: String = ""

func _init() -> void:
	type = "STAR"
	max_visibility_distance = INF

func apply_star_data(data: StarData) -> void:
	catalog_id = data.unique_id
	name = data.name + " (" + data.spectral_type + ")"
	real_radius = data.radius
	real_position = Vector3.ZERO
	local_position = Vector3.ZERO
	rotation_speed = 0.08
	rotation_angle = 0.0
	axial_tilt = 0.0
	stellar_x = data.stellar_x
	stellar_y = data.stellar_y
	stellar_z = data.stellar_z
	sys_seed = data.system_seed
	base_color = data.base_color
	light_color = data.light_color
	light_energy = data.light_energy
	luminosity = data.luminosity
	spectral_type = data.spectral_type
	system_type = data.system_type
	system_diameter = data.system_radius_m * 2.0 if data.system_radius_m > 0.0 else 2000000000000.0
