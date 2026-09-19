extends "res://scripts/rendering/streamed_star_field.gd"

const SECTOR_SIZE_LY := SectorManager.SECTOR_SIZE_LY
const REGION_SIZE_LY := 5000.0
const MIN_DIST_LY := 2500.0
const MAX_DIST_LY := 25000.0
const CHUNK_COUNT := 5

func _init() -> void:
	configure("res://shaders/deep_field_stars.gdshader", REGION_SIZE_LY,
		MIN_DIST_LY, MAX_DIST_LY, CHUNK_COUNT, 50000)
