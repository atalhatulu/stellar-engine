class_name StarData
extends RefCounted

# Yalnızca saf prosedürel yıldız verisi taşır; Node3D veya render nesnesi barındırmaz.
var unique_id: String
var system_seed: int
var sector_coord: Vector3i
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
var system_type: String = "STANDARD"
var is_binary_candidate: bool = false
var has_asteroid_belt: bool = false
var extra_flags: Dictionary = {}

func get_fingerprint() -> String:
	return "%s|%d|(%.1f,%.1f,%.1f)|%s|%.1f|%.2f|%s" % [
		unique_id,
		system_seed,
		stellar_x,
		stellar_y,
		stellar_z,
		spectral_type,
		radius,
		luminosity,
		system_type
	]
