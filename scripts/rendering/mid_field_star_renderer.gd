extends "res://scripts/rendering/streamed_star_field.gd"

const TOTAL_STARS := 20000
const CHUNK_COUNT := 4
const STARS_PER_CHUNK := 5000
const REGION_SIZE_LY := 1000.0
const MIN_DIST_LY := 150.0
const MAX_DIST_LY := 2500.0

func _init() -> void:
	render_dist_min_ratio = 0.90
	render_dist_max_ratio = 0.94
	configure("res://shaders/mid_field_stars.gdshader", REGION_SIZE_LY,
		MIN_DIST_LY, MAX_DIST_LY, CHUNK_COUNT, TOTAL_STARS)
