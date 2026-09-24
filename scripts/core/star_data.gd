class_name StarData
extends RefCounted

# Yalnızca saf prosedürel yıldız verisi taşır; Node3D veya render nesnesi barındırmaz.
var unique_id: String
var galaxy_id: String = ""
var parent_id: String = ""
var system_seed: int
var sector_coord: Vector3i
var galactic_position: GalacticPosition = null
var stellar_x: float
var stellar_y: float
var stellar_z: float
var name: String
var radius: float
var spectral_type: String
var base_color: Color
var light_color: Color
var light_energy: float
var luminosity: float = 1.0
var mass_solar: float = 1.0
var age_billion_years: float = 4.6
var temperature_kelvin: float = 5778.0
var metallicity: float = 0.0
var stellar_activity: float = 1.0
var system_radius_m: float = 0.0
var activation_radius_visual: float = 0.0
var deactivation_radius_visual: float = 0.0
var discovered: bool = false
var system_type: String = "STANDARD"
var is_binary_candidate: bool = false
var has_asteroid_belt: bool = false
var extra_flags: Dictionary = {}
var group_id: String = ""
var group_name: String = ""
var group_type: String = "FIELD"
var group_center: Vector3 = Vector3.ZERO
var group_member_index: int = -1
var constellation_id: String = ""
var constellation_name: String = ""

func set_galactic_position(position: GalacticPosition) -> void:
	galactic_position = position.duplicate_pos() if position != null else null
	if galactic_position != null:
		var meters := galactic_position.to_meters_approx()
		stellar_x = meters.x
		stellar_y = meters.y
		stellar_z = meters.z
		sector_coord = galactic_position.sector

func get_galactic_position() -> GalacticPosition:
	if galactic_position == null:
		galactic_position = GalacticPosition.from_meters(Vector3(stellar_x, stellar_y, stellar_z))
	return galactic_position

func get_fingerprint() -> String:
	return "%s|%d|(%.1f,%.1f,%.1f)|%s|%.1f|%.2f|%s|%s|%s" % [
		unique_id,
		system_seed,
		stellar_x,
		stellar_y,
		stellar_z,
		spectral_type,
		radius,
		luminosity,
		system_type,
		group_id,
		constellation_id
	]
