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
	unique_id = data.unique_id
	parent_id = data.parent_id
	galaxy_id = data.galaxy_id
	system_id = data.unique_id
	body_seed = data.system_seed
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
	mass_solar = data.mass_solar
	age_billion_years = data.age_billion_years
	temperature_kelvin = data.temperature_kelvin
	metallicity = data.metallicity
	stellar_activity = data.stellar_activity
	spectral_type = data.spectral_type
	system_type = data.system_type
	system_diameter = data.system_radius_m * 2.0 if data.system_radius_m > 0.0 else 2000000000000.0
