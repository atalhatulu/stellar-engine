class_name CelestialNameGenerator
extends RefCounted

const PREFIXES := ["Ae", "Al", "Ar", "Bel", "Ca", "Cer", "Da", "El", "Eri", "Ha", "Ily", "Ka", "Ke", "Lyr", "Ma", "Nar", "Ori", "Per", "Rhe", "Sol", "Ta", "Vel", "Xan", "Zer"]
const CORES := ["dan", "dor", "lia", "mer", "nara", "phos", "ran", "ria", "tar", "thea", "vex", "yon"]
const SUFFIXES := ["", "a", "is", "on", "os", "um", " Prime"]


static func star_name(seed_value: int) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value ^ 0x4E414D45
	return "%s%s%s" % [
		PREFIXES[rng.randi_range(0, PREFIXES.size() - 1)],
		CORES[rng.randi_range(0, CORES.size() - 1)],
		SUFFIXES[rng.randi_range(0, SUFFIXES.size() - 1)]
	]


static func planet_name(star_display_name: String, index: int) -> String:
	return "%s %s" % [_root_name(star_display_name), String.chr(98 + index)]


static func moon_name(planet_display_name: String, index: int) -> String:
	return "%s-%s" % [planet_display_name, _roman(index + 1)]


static func _root_name(display_name: String) -> String:
	var marker := display_name.find(" (")
	return display_name.left(marker) if marker >= 0 else display_name


static func _roman(value: int) -> String:
	var numerals := ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI", "XII", "XIII", "XIV", "XVIII"]
	return numerals[clampi(value - 1, 0, numerals.size() - 1)]
