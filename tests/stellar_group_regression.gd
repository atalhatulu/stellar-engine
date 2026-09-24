extends SceneTree

func _initialize() -> void:
	var manager := SectorManager.new(73421)
	var stars := manager.generate_sector(Vector3i(2, -1, 4))
	var grouped := 0
	var groups := {}
	var constellations := {}
	for star in stars:
		if star.constellation_id == "" or star.constellation_name == "":
			push_error("Every generated star must belong to a constellation region")
			quit(1)
			return
		constellations[star.constellation_id] = true
		if star.group_id == "":
			continue
		grouped += 1
		if not groups.has(star.group_id):
			groups[star.group_id] = []
		groups[star.group_id].append(star)
	if grouped < 5 or groups.is_empty():
		push_error("Sector generation must produce physical stellar groups")
		quit(1)
		return
	var multi_member_group := false
	for members in groups.values():
		if members.size() >= 2:
			multi_member_group = true
			break
	if not multi_member_group:
		push_error("At least one generated stellar group must contain multiple stars")
		quit(1)
		return
	if constellations.size() < 2:
		push_error("A sector must contain multiple constellation regions")
		quit(1)
		return
	var sample_index := mini(7, stars.size() - 1)
	var single := SectorManager.generate_single_star(73421, Vector3i(2, -1, 4), sample_index)
	if single.get_fingerprint() != stars[sample_index].get_fingerprint():
		push_error("Single-star generation must preserve grouped sector determinism")
		quit(1)
		return
	print("STELLAR_GROUP_REGRESSION_OK physical_groups=%d/%d constellations=%d" % [grouped, stars.size(), constellations.size()])
	quit(0)
