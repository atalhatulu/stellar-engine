class_name StreamingManager
extends RefCounted

const SectorManager = preload("res://scripts/generation/sector_manager.gd")

# =============================================================================
# Merkezi Streaming ve Kare Bütçesi Yöneticisi (StreamingManager)
#
# Galaktik sektör streaming, yıldız alanı güncellemeleri ve arazi üretimini
# ortak bir kare zaman bütçesi (~1.5 ms) altında toplar. Ani kare takılmalarını
# (spike) ve ana thread darboğazlarını önler.
# =============================================================================

# Kare başına maksimum üretim süresi (varsayılan: 1500 mikrosaniye = 1.5 ms)
var frame_budget_usec: int = 1500

var sector_manager: SectorManager = null
var last_frame_stream_time_usec: int = 0
var is_streaming_in_progress: bool = false

func _init(p_sector_manager = null, p_budget_usec: int = 1500) -> void:
	sector_manager = p_sector_manager
	frame_budget_usec = p_budget_usec

# Her kare çağrılır; sektörleri ve bekleyen işleri bütçe dahilinde parça parça işler
func update(player_galactic_pos: Vector3, protected_coord: Vector3i = Vector3i(2147483647, 2147483647, 2147483647)) -> bool:
	if sector_manager == null:
		return false
		
	var start_time := Time.get_ticks_usec()
	var updated = sector_manager.update_player_position(player_galactic_pos, protected_coord, frame_budget_usec)
	last_frame_stream_time_usec = Time.get_ticks_usec() - start_time
	
	is_streaming_in_progress = not sector_manager._pending_sectors.is_empty()
	return updated

# Sektör kuyruğunda bekleyen parça olup olmadığını döner
func has_pending_work() -> bool:
	if sector_manager != null:
		return not sector_manager._pending_sectors.is_empty()
	return false

# Kalan kare bütçesini hesaplar (Mikrosaniye)
func get_remaining_budget_usec(elapsed_since_frame_start: int) -> int:
	return maxi(0, frame_budget_usec - elapsed_since_frame_start)
