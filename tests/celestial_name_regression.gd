extends SceneTree


func _initialize() -> void:
	var first := CelestialNameGenerator.star_name(123456)
	var repeat := CelestialNameGenerator.star_name(123456)
	var other := CelestialNameGenerator.star_name(654321)
	if first != repeat or first == other:
		push_error("Celestial names must be deterministic and seed-sensitive")
		quit(1)
		return
	if CelestialNameGenerator.planet_name(first, 0) != first + " b":
		push_error("Planet designations must follow astronomical lettering")
		quit(1)
		return
	if not CelestialNameGenerator.moon_name(first + " b", 1).ends_with("-II"):
		push_error("Moon designations must use stable Roman numerals")
		quit(1)
		return
	print("CELESTIAL_NAME_REGRESSION_OK %s" % first)
	quit(0)
