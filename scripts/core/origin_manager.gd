class_name OriginManager
extends RefCounted

const GalacticPosition = preload("res://scripts/core/galactic_position.gd")

# =============================================================================
# Dört Katmanlı Koordinat ve Floating Origin Yöneticisi (OriginManager)
#
# Katmanlar:
# 1. Galaxy Space : Sektör (Vector3i) + Sektör İçi Yerel Metre (GalacticPosition)
# 2. System Space : Aktif Yıldız Merkezli Metre / AU Uzayı
# 3. Planet Space : Gezegen Merkezli Metre ve Yörünge Fazı
# 4. Local Render Space: Godot Sahne Çizim Dünyası (Kamera Merkezli Floating Origin)
# =============================================================================

signal origin_shifted(shift_delta: Vector3)

# Floating origin kaydırma eşiği (Yerel metre cinsinden)
# Oyuncu bu mesafeyi aştığında render kökeni oyuncunun konumuna sıfırlanır.
var floating_origin_threshold: float = 10000.0

# Aktif galaktik oyuncu konumu (Hassas 2 kademeli)
var player_galactic_pos: GalacticPosition = GalacticPosition.new()

# Aktif sistemdeki yıldızın galaktik konumu
var active_star_galactic_pos: GalacticPosition = null

# Aktif gezegenin sistem içi göreceli konumu (metre)
var active_planet_system_pos: Vector3 = Vector3.ZERO

# Render uzayındaki floating origin birikimli ofseti
var render_origin_offset: Vector3 = Vector3.ZERO

func _init(initial_galactic_pos = null) -> void:
	if initial_galactic_pos != null and initial_galactic_pos.has_method("duplicate_pos"):
		player_galactic_pos = initial_galactic_pos.duplicate_pos()
	else:
		player_galactic_pos = GalacticPosition.new()

# Oyuncunun galaktik konumunu doğrudan veya delta metreyle günceller
func update_player_motion(delta_meters: Vector3) -> void:
	player_galactic_pos.add_meters(delta_meters)

# Aktif yıldız sistemini ayarlar
func set_active_star(star_pos: GalacticPosition) -> void:
	active_star_galactic_pos = star_pos.duplicate_pos() if star_pos != null else null

# Aktif gezegenin sistem içi ofsetini ayarlar
func set_active_planet(planet_system_offset: Vector3) -> void:
	active_planet_system_pos = planet_system_offset

# ── 1. Galaxy Space -> System Space ──────────────────────────────────────────
# Galaktik konumdan aktif yıldıza göre sistem içi bağıl pozisyonu (metre) hesaplar
func galactic_to_system_pos(target_galactic: GalacticPosition) -> Vector3:
	if active_star_galactic_pos == null:
		return target_galactic.to_meters_approx()
	return target_galactic.get_relative_meters(active_star_galactic_pos)

# ── 2. System Space -> Planet Space ──────────────────────────────────────────
# Sistem içi metre pozisyonundan gezegen merkezli bağıl pozisyona geçer
func system_to_planet_pos(system_pos: Vector3) -> Vector3:
	return system_pos - active_planet_system_pos

# ── 3. Planet Space -> Local Space (Metre / Yüzey) ───────────────────────────
# Gezegen merkezli pozisyon ile yüzey irtifasını ayıklar
func planet_pos_to_altitude(planet_pos: Vector3, planet_radius: float) -> float:
	return maxf(planet_pos.length() - planet_radius, 0.0)

# ── 4. Floating Origin Kontrolü (Local Render Space) ─────────────────────────
# Render sahnesindeki görsel kameranın konumunu denetler; eşiği aşarsa sahneyi yeniden merkezler
func check_and_shift_origin(camera_local_pos: Vector3) -> Vector3:
	if camera_local_pos.length() > floating_origin_threshold:
		var shift = camera_local_pos
		render_origin_offset += shift
		origin_shifted.emit(shift)
		return shift
	return Vector3.ZERO

# İki galaktik konum arasındaki astronomik mesafeyi döner (HUD ve seyrüsefer için)
func get_astronomical_distance_meters(a: GalacticPosition, b: GalacticPosition) -> float:
	return a.distance_to_meters(b)

func get_astronomical_distance_ly(a: GalacticPosition, b: GalacticPosition) -> float:
	return a.distance_to_ly(b)
