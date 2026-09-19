class_name PlanetSurfaceProfile
extends RefCounted

var seed_value: int = 424243
var radius: float = 1737400.0
var gravity: float = 1.62
var moon: bool = true
var landable: bool = true
var label: String = "SELENE / KAYALIK UYDU"
var ground_color := Color(0.29, 0.31, 0.35)
var rock_color := Color(0.13, 0.15, 0.19)
var relief: float = 1.0

static func from_body(body: CelestialBody) -> PlanetSurfaceProfile:
	var result := PlanetSurfaceProfile.new()
	result.seed_value = hash("%d/%s/%s" % [body.sys_seed, body.name, body.type])
	result.radius = maxf(body.real_radius, 1000.0)
	result.moon = body.type == "MOON"
	result.label = body.name
	result.landable = body.type in ["PLANET", "MOON"] and body.planet_type not in ["GAS_GIANT", "OCEAN_WORLD"]
	result.gravity = 1.62 if result.moon else clampf(9.81 * result.radius / 6371000.0, 3.0, 16.0)
	if not result.moon:
		result.ground_color = Color(0.39, 0.30, 0.20)
		result.rock_color = Color(0.17, 0.14, 0.12)
		result.relief = 1.35
	if body.planet_type == "ICE_WORLD":
		result.ground_color = Color(0.60, 0.72, 0.79)
		result.rock_color = Color(0.23, 0.34, 0.43)
	return result
