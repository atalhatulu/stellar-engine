class_name GalacticPosition
extends RefCounted

# =============================================================================
# Yüksek Hassasiyetli Galaktik Koordinat Veri Sınıfı (GalacticPosition)
# 64-bit hassasiyet kaybını (precision loss) ve derin uzay titremesini (jitter)
# engellemek için koordinatları tamsayı sektör (Vector3i) ve yerel metre (Vector3)
# olarak iki kademede saklar.
# =============================================================================

const SelfScript = preload("res://scripts/core/galactic_position.gd")

const LIGHT_YEAR: float = 9460730472580800.0
const ASTRONOMICAL_UNIT: float = 149597870700.0
const SECTOR_SIZE_LY: float = 65.0
const SECTOR_SIZE_METERS: float = 65.0 * LIGHT_YEAR

var sector: Vector3i = Vector3i.ZERO
var local_pos: Vector3 = Vector3.ZERO # Sektör tabanından yerel metre [0, SECTOR_SIZE_METERS)

func _init(p_sector: Vector3i = Vector3i.ZERO, p_local: Vector3 = Vector3.ZERO) -> void:
	sector = p_sector
	local_pos = p_local
	normalize()

# Ham metre koordinatından Galaktik Konum oluşturur
static func from_meters(meters: Vector3):
	var sx := int(floor(meters.x / SECTOR_SIZE_METERS))
	var sy := int(floor(meters.y / SECTOR_SIZE_METERS))
	var sz := int(floor(meters.z / SECTOR_SIZE_METERS))
	var sec := Vector3i(sx, sy, sz)
	var loc := Vector3(
		meters.x - float(sx) * SECTOR_SIZE_METERS,
		meters.y - float(sy) * SECTOR_SIZE_METERS,
		meters.z - float(sz) * SECTOR_SIZE_METERS
	)
	return SelfScript.new(sec, loc)

# Sektör koordinatı ve yerel metreden oluşturur
static func from_sector_and_local(p_sector: Vector3i, p_local: Vector3):
	return SelfScript.new(p_sector, p_local)

# Işık yılı cinsinden oluşturur
static func from_light_years(ly: Vector3):
	var sx := int(floor(ly.x / SECTOR_SIZE_LY))
	var sy := int(floor(ly.y / SECTOR_SIZE_LY))
	var sz := int(floor(ly.z / SECTOR_SIZE_LY))
	var sec := Vector3i(sx, sy, sz)
	var loc_ly := Vector3(
		ly.x - float(sx) * SECTOR_SIZE_LY,
		ly.y - float(sy) * SECTOR_SIZE_LY,
		ly.z - float(sz) * SECTOR_SIZE_LY
	)
	return SelfScript.new(sec, loc_ly * LIGHT_YEAR)

# Yerel pozisyon sektör sınırlarını aştığında sektör koordinatını otomatik günceller
func normalize() -> void:
	var shift_x := int(floor(local_pos.x / SECTOR_SIZE_METERS))
	var shift_y := int(floor(local_pos.y / SECTOR_SIZE_METERS))
	var shift_z := int(floor(local_pos.z / SECTOR_SIZE_METERS))
	
	if shift_x != 0 or shift_y != 0 or shift_z != 0:
		sector.x += shift_x
		sector.y += shift_y
		sector.z += shift_z
		local_pos.x -= float(shift_x) * SECTOR_SIZE_METERS
		local_pos.y -= float(shift_y) * SECTOR_SIZE_METERS
		local_pos.z -= float(shift_z) * SECTOR_SIZE_METERS

# Metre cinsinden delta ekler ve sektör taşmasını normalize eder
func add_meters(delta: Vector3) -> void:
	local_pos += delta
	normalize()

# Diğer bir galaktik konuma göre yüksek hassasiyetli fark vektörünü (metre) döner.
# Sektör farkı tamsayı uzayında hesaplandığı için devasa sayılarda hassasiyet kaybı oluşmaz.
func get_relative_meters(other: GalacticPosition) -> Vector3:
	var d_sec := sector - other.sector
	var sec_offset := Vector3(
		float(d_sec.x) * SECTOR_SIZE_METERS,
		float(d_sec.y) * SECTOR_SIZE_METERS,
		float(d_sec.z) * SECTOR_SIZE_METERS
	)
	return sec_offset + (local_pos - other.local_pos)

# Diğer konuma olan mutlak mesafeyi (metre) döner
func distance_to_meters(other: GalacticPosition) -> float:
	return get_relative_meters(other).length()

# Diğer konuma olan mesafeyi ışık yılı cinsinden döner
func distance_to_ly(other: GalacticPosition) -> float:
	return distance_to_meters(other) / LIGHT_YEAR

# Küresel yaklaşık metre pozisyonunu döner (yalnızca tekil Vector3 isteyen legacy fonksiyonlar için)
func to_meters_approx() -> Vector3:
	return Vector3(
		float(sector.x) * SECTOR_SIZE_METERS + local_pos.x,
		float(sector.y) * SECTOR_SIZE_METERS + local_pos.y,
		float(sector.z) * SECTOR_SIZE_METERS + local_pos.z
	)

# Işık yılı cinsinden galaktik pozisyon
func to_light_years() -> Vector3:
	return Vector3(
		float(sector.x) * SECTOR_SIZE_LY + (local_pos.x / LIGHT_YEAR),
		float(sector.y) * SECTOR_SIZE_LY + (local_pos.y / LIGHT_YEAR),
		float(sector.z) * SECTOR_SIZE_LY + (local_pos.z / LIGHT_YEAR)
	)

func duplicate_pos():
	return SelfScript.new(sector, local_pos)

func _to_string() -> String:
	return "GalacticPos(Sec: %s, Loc_LY: (%.2f, %.2f, %.2f))" % [
		sector,
		local_pos.x / LIGHT_YEAR,
		local_pos.y / LIGHT_YEAR,
		local_pos.z / LIGHT_YEAR
	]
