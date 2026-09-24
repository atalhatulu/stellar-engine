class_name CelestialAddress
extends RefCounted

# Prosedürel evrendeki her nesne için tek ve yeniden üretilebilir adres biçimi.
# Görsel LOD nesneleri yüklenip silinse de bu kimlik değişmez.

static func galaxy_id(galaxy_seed: int) -> String:
	return "GAL_%d" % galaxy_seed

static func star_id(p_galaxy_id: String, sector: Vector3i, index: int) -> String:
	return "%s_SEC_%d_%d_%d_S%d" % [p_galaxy_id, sector.x, sector.y, sector.z, index]

static func planet_id(p_star_id: String, index: int) -> String:
	return "%s_P%d" % [p_star_id, index + 1]

static func moon_id(p_planet_id: String, index: int) -> String:
	return "%s_M%d" % [p_planet_id, index + 1]

static func black_hole_id(p_galaxy_id: String) -> String:
	return "%s_SMBH" % p_galaxy_id

# String.hash() motor sürümüne bağlı davranmasın diye kimlikten tohum üretimini
# açık bir FNV-1a zinciriyle yapıyoruz. Sonuç RandomNumberGenerator için pozitiftir.
static func seed_from_id(identifier: String) -> int:
	var value: int = 2166136261
	for byte in identifier.to_utf8_buffer():
		value = value ^ int(byte)
		value = int((value * 16777619) & 0x7FFFFFFF)
	return max(value, 1)
