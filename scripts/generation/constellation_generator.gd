class_name ConstellationGenerator
extends RefCounted

## Gökyüzü bölgeleri üretir. Fiziksel yıldız kümelerinden bağımsızdır:
## her yıldız tam olarak bir takımyıldız bölgesine atanır.

static func build_entry(universe_seed: int, sector_coord: Vector3i, local_position: Vector3, sector_size: float) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = SectorManager.get_sector_seed(universe_seed ^ 0x434F4E53, sector_coord)
	var region_count := rng.randi_range(3, 5)
	var nearest_index := 0
	var nearest_distance := INF
	var names := ["Aquila", "Lyra", "Cygnus", "Orionis", "Vela", "Draco", "Carina", "Persei", "Andromeda", "Cassiopeia"]
	var chosen_name := ""
	for region_index in range(region_count):
		var center := Vector3(
			rng.randf_range(0.1, 0.9) * sector_size,
			rng.randf_range(0.1, 0.9) * sector_size,
			rng.randf_range(0.1, 0.9) * sector_size
		)
		var name_index := rng.randi_range(0, names.size() - 1)
		var distance := local_position.distance_squared_to(center)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_index = region_index
			chosen_name = names[name_index]
	var coord_hash: int = absi(sector_coord.x * 73856093 ^ sector_coord.y * 19349663 ^ sector_coord.z * 83492791)
	return {
		"id": "CON_%d_%d_%d_%d" % [sector_coord.x, sector_coord.y, sector_coord.z, nearest_index + 1],
		"name": "%s-%02d" % [chosen_name, (coord_hash + nearest_index * 17) % 97 + 1]
	}
