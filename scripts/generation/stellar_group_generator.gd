class_name StellarGroupGenerator
extends RefCounted

const LIGHT_YEAR := 9460730472580800.0
const GROUP_FRACTION := 0.36

static func build_layout(universe_seed: int, sector_coord: Vector3i, star_count: int, sector_size: float) -> Array[Dictionary]:
	var layout: Array[Dictionary] = []
	for star_index in range(star_count):
		layout.append(build_entry(universe_seed, sector_coord, star_index, sector_size))
	return layout

static func build_entry(universe_seed: int, sector_coord: Vector3i, star_index: int, sector_size: float) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = SectorManager.get_sector_seed(universe_seed ^ 0x53544752, sector_coord)
	var group_count := rng.randi_range(2, 3)
	var groups: Array[Dictionary] = []
	for group_index in range(group_count):
		var group_type := "OPEN_CLUSTER" if rng.randf() < 0.28 else "STELLAR_ASSOCIATION"
		groups.append({
			"id": "SG_%d_%d_%d_%d" % [sector_coord.x, sector_coord.y, sector_coord.z, group_index + 1],
			"name": _group_name(rng, sector_coord, group_index, group_type),
			"type": group_type,
			"center": Vector3(
				rng.randf_range(0.18, 0.82) * sector_size,
				rng.randf_range(0.18, 0.82) * sector_size,
				rng.randf_range(0.18, 0.82) * sector_size
			),
			"radius": rng.randf_range(3.0, 8.0) * LIGHT_YEAR if group_type == "OPEN_CLUSTER" else rng.randf_range(7.0, 16.0) * LIGHT_YEAR,
			"members": 0,
		})

	var star_rng := RandomNumberGenerator.new()
	star_rng.seed = SectorManager.get_sector_seed(universe_seed ^ ((star_index + 1) * 0x1F123BB5), sector_coord)
	var local_position := Vector3(
		star_rng.randf_range(0.05, 0.95) * sector_size,
		star_rng.randf_range(0.05, 0.95) * sector_size,
		star_rng.randf_range(0.05, 0.95) * sector_size
	)
	var entry := {"position": local_position, "group_id": "", "group_name": "", "group_type": "FIELD", "group_center": Vector3.ZERO, "group_member_index": -1}
	if star_rng.randf() < GROUP_FRACTION:
		var group: Dictionary = groups[star_rng.randi_range(0, groups.size() - 1)]
		var direction := Vector3(star_rng.randfn(), star_rng.randfn(), star_rng.randfn()).normalized()
		var radial_factor := pow(star_rng.randf(), 0.55)
		local_position = group.center + direction * group.radius * radial_factor
		local_position = local_position.clamp(Vector3.ONE * sector_size * 0.05, Vector3.ONE * sector_size * 0.95)
		entry.position = local_position
		entry.group_id = group.id
		entry.group_name = group.name
		entry.group_type = group.type
		entry.group_center = group.center
		entry.group_member_index = star_index
	return entry

static func _group_name(rng: RandomNumberGenerator, coord: Vector3i, index: int, group_type: String) -> String:
	var roots := ["Aquila", "Lyra", "Cygnus", "Orionis", "Vela", "Draco", "Carina", "Persei"]
	var suffix := "Açık Kümesi" if group_type == "OPEN_CLUSTER" else "Yıldız Birliği"
	var coordinate_hash := coord.x * 73856093 ^ coord.y * 19349663 ^ coord.z * 83492791
	return "%s-%02d %s" % [roots[rng.randi_range(0, roots.size() - 1)], abs(coordinate_hash + index * 17) % 97 + 1, suffix]
