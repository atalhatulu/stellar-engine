class_name SpaceScaleManager
extends RefCounted

const CelestialRenderScale = preload("res://scripts/rendering/celestial_render_scale.gd")

# =============================================================================
# Uzay Ölçek ve Render Projeksiyon Yöneticisi (SpaceScaleManager)
#
# Simülasyon Uzayı (milyonlarca metre/ışık yılı) ile Render Uzayı (10-20 km
# görünürlük kabuğu) arasındaki matematiksel ölçekleme ve projekte etme
# işlemlerini merkezi olarak yönetir.
# =============================================================================

const LIGHT_YEAR: float = 9460730472580800.0
const DEFAULT_VISUAL_DISTANCE_LIMIT: float = 10000.0 # 10 km render kabuğu

var visual_distance_limit: float = DEFAULT_VISUAL_DISTANCE_LIMIT
var visual_scale_multiplier: float = 1.0

func _init(p_visual_distance_limit: float = DEFAULT_VISUAL_DISTANCE_LIMIT, p_scale_multiplier: float = 1.0) -> void:
	visual_distance_limit = p_visual_distance_limit
	visual_scale_multiplier = p_scale_multiplier

# Bir gök cismini kameranın frustum ve derinlik sınırına projekte eder
func project_celestial_body(
	body: CelestialBody,
	distance_meters: float,
	viewport_height: float,
	fov_degrees: float,
	near_surface: bool = false
) -> Dictionary:
	return CelestialRenderScale.project_body(
		body,
		distance_meters,
		viewport_height,
		fov_degrees,
		visual_distance_limit,
		visual_scale_multiplier,
		near_surface
	)

# Göreceli metre pozisyonunu maksimum render kabuğu sınırına projekte eder
func project_world_position(relative_meters: Vector3, near_surface: bool = false) -> Vector3:
	return CelestialRenderScale.project_position(
		relative_meters,
		visual_distance_limit,
		near_surface
	)
