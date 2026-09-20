class_name CelestialRenderScale
extends RefCounted

const LIGHT_YEAR: float = 9460730472580800.0

# main_star ve main_galaxy tarafından paylaşılan tek gök cismi projeksiyonu.
# Girdi ve çıktı metre uzayındadır; kullanan sahne sonucu kendi dünya
# birimine tek bir uniform katsayıyla dönüştürebilir.
static func project_body(
	body: CelestialBody,
	distance_m: float,
	viewport_height: float,
	fov_degrees: float,
	visual_distance_limit_m: float,
	visual_scale_multiplier: float = 1.0,
	near_surface: bool = false
) -> Dictionary:
	var safe_distance := maxf(distance_m, 1.0)
	var render_distance := safe_distance if near_surface else minf(safe_distance, visual_distance_limit_m)
	var scale_multiplier := visual_scale_multiplier
	if body.type == "STAR":
		scale_multiplier = maxf(1.0, visual_scale_multiplier * 0.1)
	var natural_scale := body.real_radius * scale_multiplier * (render_distance / safe_distance)
	var minimum_pixels := 4.0
	var star_distance_factor := 0.0
	if body.type == "STAR":
		var distance_ly := safe_distance / LIGHT_YEAR
		star_distance_factor = clampf((distance_ly - 0.5) / 17.5, 0.0, 1.0)
		minimum_pixels = lerpf(6.5, 1.8, star_distance_factor)
	elif body.type == "MOON":
		minimum_pixels = 1.5
	var tan_half_fov := tan(deg_to_rad(fov_degrees * 0.5))
	var minimum_scale := minimum_pixels * 2.0 * render_distance * tan_half_fov / maxf(viewport_height, 1.0)
	var use_lod := (safe_distance >= 0.07 * LIGHT_YEAR) if body.type == "STAR" else (minimum_scale > natural_scale)
	return {
		"render_distance": render_distance,
		"render_scale": maxf(natural_scale, minimum_scale),
		"use_lod": use_lod,
		"star_distance_factor": star_distance_factor
	}

static func project_position(relative_m: Vector3, visual_distance_limit_m: float, near_surface: bool = false) -> Vector3:
	var distance := relative_m.length()
	if distance <= 0.001 or near_surface or distance <= visual_distance_limit_m:
		return relative_m
	return relative_m / distance * visual_distance_limit_m
