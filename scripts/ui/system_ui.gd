class_name SystemUI
extends RefCounted

const LIGHT_SPEED: float = 299792458.0
const LIGHT_YEAR: float = 9460730472580800.0

static func update_ui(main_node: Node3D, closest_name: String, closest_dist: float) -> void:
	if not main_node.is_hud_visible:
		return
	var mode := "SİSTEM HARİTASI" if main_node.is_system_map_active else ("YÜZEY SERBEST KAMERA" if main_node.is_landed else "SERBEST UÇUŞ")
	var target_text := "Kilit Yok (T veya Sol Tık)"
	if main_node.get("targeted_star_data") != null:
		target_text = main_node.targeted_star_data.name
	elif main_node.current_target_index >= 0 and main_node.current_target_index < main_node.universe.size():
		target_text = main_node.universe[main_node.current_target_index].name
	var system_name: String = str(main_node.active_star.name) if main_node.active_star != null else closest_name
	main_node.ui_label.text = "[center][b][color=#00e5ff]%s[/color][/b][/center]\n[color=#3f4f60]━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━[/color]\n • Sistem: [color=#00ff66]%s[/color]\n • En yakın: [color=#ffcc00]%s[/color]\n • Hedef: [color=#ffaa00]%s[/color]\n • Kontrol: [color=#00e5ff]FREE-FLY KAMERA[/color]\n\n[color=#8d99ae][WASD] Hareket | [Space/Ctrl] Yüksel/Alçal | [Shift] Hızlan\n[T] Hedef | [C] Seçimi Bırak | [G] Otopilot | [M] Harita | [K] Katalog[/color]" % [mode, system_name, format_space_distance(closest_dist), target_text]
static func format_light_time(meters: float) -> String:
	return SystemHUD.format_light_time(meters)

static func format_travel_time(meters: float, speed: float) -> String:
	return SystemHUD.format_travel_time(meters, speed)

static func format_space_distance(meters: float) -> String:
	const ONE_AU: float = 149597870700.0
	const TRANSITION_AU: float = 0.1 * ONE_AU
	const ONE_MILLION_KM: float = 1000000000.0
	const ONE_THOUSAND_KM: float = 1000000.0
	const ONE_KM: float = 1000.0
	
	if meters <= 0.0:
		return "0 m"
		
	var lt = format_light_time(meters)
	
	if meters >= 100.0 * LIGHT_YEAR:
		return "%s (%.1f ly)" % [lt, meters / LIGHT_YEAR]
	elif meters >= 0.01 * LIGHT_YEAR:
		return "%s (%.2f ly)" % [lt, meters / LIGHT_YEAR]
	elif meters >= TRANSITION_AU:
		return "%s (%.2f AU)" % [lt, meters / ONE_AU]
	elif meters >= ONE_MILLION_KM:
		return "%s (%.1f Milyon km)" % [lt, meters / ONE_MILLION_KM]
	elif meters >= ONE_THOUSAND_KM:
		return "%s (%.0f Bin km)" % [lt, meters / ONE_THOUSAND_KM]
	elif meters >= ONE_KM:
		return "%.2f km (< 0.01 Sn)" % (meters / ONE_KM)
	else:
		return "%.0f m" % meters

static func format_number_with_dots(num: int) -> String:
	var s = str(abs(num))
	var res = ""
	var count = 0
	for i in range(s.length() - 1, -1, -1):
		res = s[i] + res
		count += 1
		if count % 3 == 0 and i > 0:
			res = "." + res
	if num < 0:
		res = "-" + res
	return res
