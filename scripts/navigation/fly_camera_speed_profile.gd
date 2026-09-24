class_name FlyCameraSpeedProfile
extends RefCounted

const LIGHT_SPEED_MPS: float = 299792458.0
const LIGHT_YEAR_METERS: float = 9460730472580800.0

static func presets_mps() -> Array[float]:
	return [
		50.0, 343.0, 3000.0, 30000.0, 300000.0,
		0.01 * LIGHT_SPEED_MPS, 0.1 * LIGHT_SPEED_MPS, LIGHT_SPEED_MPS,
		60.0 * LIGHT_SPEED_MPS, 3600.0 * LIGHT_SPEED_MPS,
		86400.0 * LIGHT_SPEED_MPS, 2629800.0 * LIGHT_SPEED_MPS,
		1.0 * LIGHT_YEAR_METERS, 10.0 * LIGHT_YEAR_METERS,
		100.0 * LIGHT_YEAR_METERS, 1000.0 * LIGHT_YEAR_METERS,
		5000.0 * LIGHT_YEAR_METERS, 10000.0 * LIGHT_YEAR_METERS,
		25000.0 * LIGHT_YEAR_METERS, 50000.0 * LIGHT_YEAR_METERS,
		100000.0 * LIGHT_YEAR_METERS, 250000.0 * LIGHT_YEAR_METERS,
		500000.0 * LIGHT_YEAR_METERS, 1000000.0 * LIGHT_YEAR_METERS,
		2500000.0 * LIGHT_YEAR_METERS, 5000000.0 * LIGHT_YEAR_METERS,
		10000000.0 * LIGHT_YEAR_METERS, 25000000.0 * LIGHT_YEAR_METERS,
		50000000.0 * LIGHT_YEAR_METERS, 100000000.0 * LIGHT_YEAR_METERS
	]

static func labels() -> Array[String]:
	return [
		"50 m/s", "Mach 1", "3 km/s", "30 km/s", "300 km/s",
		"%1 Işık Hızı", "%10 Işık Hızı", "Işık Hızı (1c)",
		"1 Işık Dakikası/s", "1 Işık Saati/s", "1 Işık Günü/s",
		"1 Işık Ayı/s", "1 Işık Yılı/s", "10 Işık Yılı/s",
		"1 Işık Asrı/s (100 LY/s)", "1.000 Işık Yılı/s",
		"5.000 Işık Yılı/s", "10.000 Işık Yılı/s",
		"25.000 Işık Yılı/s", "50.000 Işık Yılı/s",
		"100.000 Işık Yılı/s", "250.000 Işık Yılı/s",
		"500.000 Işık Yılı/s", "1 Milyon Işık Yılı/s",
		"2,5 Milyon Işık Yılı/s", "5 Milyon Işık Yılı/s",
		"10 Milyon Işık Yılı/s", "25 Milyon Işık Yılı/s",
		"50 Milyon Işık Yılı/s", "100 Milyon Işık Yılı/s"
	]

static func closest_index(speed_mps: float, presets: Array[float]) -> int:
	var result := 0
	var smallest_difference := INF
	for index in range(presets.size()):
		var difference := absf(presets[index] - speed_mps)
		if difference < smallest_difference:
			smallest_difference = difference
			result = index
	return result
