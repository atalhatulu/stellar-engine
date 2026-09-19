class_name SystemHUD
extends Control

# ─────────────────────────────────────────────────────────────────────────────
# FÜTÜRİSTİK UZAY SİMÜLASYONU VE ASTRONOT KASKI HUD SİSTEMİ (SYSTEM HUD)
#
# Düz metin kutusu yerine modüler, cam efektli (glassmorphism), neon kenarlıklı,
# grafiksel durum barları içeren; Player (Astronot Yaşam Destek), Spacecraft
# (Korvet Telemetrisi), Navigasyon ve Hedef Kartı barındıran gelişmiş arayüz.
# ─────────────────────────────────────────────────────────────────────────────

const LIGHT_SPEED: float = 299792458.0
const ONE_AU: float = 149597870700.0
const LIGHT_YEAR: float = 9460730472580800.0

# Üst Bar (Navigasyon & Sistem)
var top_bar: PanelContainer
var lbl_system_name: Label
var lbl_flight_mode: Label
var lbl_clock_time: Label

# Sol Alt (Astronot / Player Yaşam Destek)
var player_card: PanelContainer
var lbl_player_title: Label
var bar_oxygen: ProgressBar
var bar_fuel: ProgressBar
var lbl_headlamp_status: Label
var lbl_player_speed: Label

# Sağ Alt (Uzay Gemisi Telemetrisi)
var ship_card: PanelContainer
var lbl_ship_title: Label
var lbl_ship_speed_val: Label
var lbl_ship_throttle_val: Label
var bar_throttle: ProgressBar
var lbl_airlock_state: Label
var lbl_pilot_state: Label

# Sağ Taraf (Hedef Kilit Kartı - Geriye dönük uyumluluk)
var target_card: PanelContainer
var lbl_target_name: Label
var lbl_target_type: Label
var lbl_target_dist: Label
var lbl_target_details: Label

# Starfield Detaylı Cisim ve Gezegen Kartı (Sol Panel)
var starfield_card: PanelContainer
var lbl_sf_system: Label
var lbl_sf_name: Label
var lbl_sf_survey_val: Label
var bar_sf_survey: ProgressBar
var sf_table_vbox: VBoxContainer
var sf_resources_box: HFlowContainer
var lbl_sf_resources_title: Label
var sf_row_labels: Dictionary = {}

# Sol Üst Mini Sistem Haritası (Harita Modunda Görünür)
var mini_system_map: Control
var mini_map_main_ref: Node3D = null

# Sağ Üst Gezegen LOD & Chunk Telemetri Kartı
var lod_debug_card: PanelContainer
var lbl_lod_title: Label
var lbl_lod_grid_status: Label
var lbl_lod_breakdown: Label
var lbl_lod_perf: Label
var lbl_lod_color_mode: Label

# Alt Orta (Eylem Tuşları Rozet Barı)
var action_bar: HBoxContainer

# Ekran Ortası (Nişangah ve Kask Siperliği)
var crosshair_center: Control
var visor_overlay: Control

func _ready():
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_hud_layout()

# ─────────────────────────────────────────────────────────────────────────────
# ARAYÜZ YERLEŞİMİ VE FÜTÜRİSTİK STİL OLUŞTURMA
# ─────────────────────────────────────────────────────────────────────────────
func _build_hud_layout() -> void:
	# 1. Ekran Ortası Kask Siperliği ve Nişangah
	visor_overlay = Control.new()
	visor_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	visor_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(visor_overlay)
	visor_overlay.draw.connect(_draw_visor_and_reticle)
	visor_overlay.resized.connect(visor_overlay.queue_redraw)

	# 2. Üst Navigasyon Barı (Top Bar)
	top_bar = PanelContainer.new()
	top_bar.custom_minimum_size = Vector2(0, 48)
	top_bar.anchor_left = 0.02
	top_bar.anchor_right = 0.98
	top_bar.anchor_top = 0.015
	top_bar.anchor_bottom = 0.065
	top_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_bar.add_theme_stylebox_override("panel", _create_glass_box(Color(0.0, 0.8, 1.0, 0.4), 8, Color(0.02, 0.05, 0.10, 0.78)))
	add_child(top_bar)
	
	var top_hbox = HBoxContainer.new()
	top_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	top_bar.add_child(top_hbox)
	
	lbl_system_name = _create_label("SİSTEM: GÜNEŞ SİSTEMİ", Color(0.0, 0.95, 1.0), 16, true)
	top_hbox.add_child(lbl_system_name)
	
	var sep1 = VSeparator.new()
	sep1.custom_minimum_size = Vector2(30, 0)
	top_hbox.add_child(sep1)
	
	lbl_flight_mode = _create_label("KOKPİT SEYRİ", Color(0.1, 1.0, 0.6), 15, true)
	top_hbox.add_child(lbl_flight_mode)
	
	var sep2 = VSeparator.new()
	sep2.custom_minimum_size = Vector2(30, 0)
	top_hbox.add_child(sep2)
	
	lbl_clock_time = _create_label("ZAMAN: 00:00:00 [1.0x]", Color(1.0, 0.8, 0.2), 15, true)
	top_hbox.add_child(lbl_clock_time)

	# 3. Sol Alt Panel: Oyuncu / Astronot Yaşam Destek
	player_card = PanelContainer.new()
	player_card.custom_minimum_size = Vector2(330, 185)
	player_card.anchor_left = 0.02
	player_card.anchor_top = 0.75
	player_card.anchor_right = 0.22
	player_card.anchor_bottom = 0.96
	player_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	player_card.add_theme_stylebox_override("panel", _create_glass_box(Color(0.0, 0.85, 1.0, 0.5), 10, Color(0.02, 0.06, 0.12, 0.85)))
	add_child(player_card)
	
	var player_vbox = VBoxContainer.new()
	player_vbox.add_theme_constant_override("separation", 6)
	player_card.add_child(player_vbox)
	
	lbl_player_title = _create_label("ASTRONOT YAŞAM DESTEK (EVA)", Color(0.0, 0.95, 1.0), 14, true)
	player_vbox.add_child(lbl_player_title)
	
	# Oksijen Barı
	var o2_box = HBoxContainer.new()
	var lbl_o2 = _create_label("OKSİJEN", Color(0.7, 0.85, 1.0), 12, false)
	lbl_o2.custom_minimum_size = Vector2(65, 0)
	o2_box.add_child(lbl_o2)
	bar_oxygen = _create_progress_bar(Color(0.0, 0.9, 1.0), Color(0.05, 0.15, 0.25))
	bar_oxygen.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar_oxygen.value = 100.0
	o2_box.add_child(bar_oxygen)
	player_vbox.add_child(o2_box)
	
	# Jetpack Yakıt Barı
	var fuel_box = HBoxContainer.new()
	var lbl_f = _create_label("JETPACK", Color(1.0, 0.8, 0.5), 12, false)
	lbl_f.custom_minimum_size = Vector2(65, 0)
	fuel_box.add_child(lbl_f)
	bar_fuel = _create_progress_bar(Color(1.0, 0.6, 0.1), Color(0.25, 0.15, 0.05))
	bar_fuel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar_fuel.value = 100.0
	fuel_box.add_child(bar_fuel)
	player_vbox.add_child(fuel_box)
	
	lbl_headlamp_status = _create_label("FENER [L]: AÇIK", Color(0.1, 0.95, 0.6), 12, false)
	player_vbox.add_child(lbl_headlamp_status)
	
	lbl_player_speed = _create_label("EVA HIZI: 0.0 m/s", Color(0.85, 0.9, 1.0), 12, false)
	player_vbox.add_child(lbl_player_speed)

	# 4. Sağ Alt Panel: Keşif Korveti Uçuş Telemetrisi
	ship_card = PanelContainer.new()
	ship_card.custom_minimum_size = Vector2(340, 185)
	ship_card.anchor_left = 0.78
	ship_card.anchor_top = 0.75
	ship_card.anchor_right = 0.98
	ship_card.anchor_bottom = 0.96
	ship_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ship_card.add_theme_stylebox_override("panel", _create_glass_box(Color(0.8, 0.35, 1.0, 0.5), 10, Color(0.04, 0.03, 0.12, 0.85)))
	add_child(ship_card)
	
	var ship_vbox = VBoxContainer.new()
	ship_vbox.add_theme_constant_override("separation", 6)
	ship_card.add_child(ship_vbox)
	
	lbl_ship_title = _create_label("KEŞİF KORVETİ TELEMETRİSİ", Color(0.85, 0.5, 1.0), 14, true)
	ship_vbox.add_child(lbl_ship_title)
	
	var speed_box = HBoxContainer.new()
	var lbl_sp_tag = _create_label("MEVCUT HIZ:", Color(0.85, 0.85, 0.9), 12, false)
	speed_box.add_child(lbl_sp_tag)
	lbl_ship_speed_val = _create_label("0.0 m/s", Color(0.3, 1.0, 0.6), 18, true)
	speed_box.add_child(lbl_ship_speed_val)
	ship_vbox.add_child(speed_box)
	
	var throttle_val_box = HBoxContainer.new()
	var lbl_th_tag = _create_label("GAZ (MAKS):", Color(0.7, 0.75, 0.85), 11, false)
	throttle_val_box.add_child(lbl_th_tag)
	lbl_ship_throttle_val = _create_label("343.0 m/s", Color(0.3, 0.85, 1.0), 13, false)
	throttle_val_box.add_child(lbl_ship_throttle_val)
	ship_vbox.add_child(throttle_val_box)
	
	# İtici Gücü Barı
	var throttle_box = HBoxContainer.new()
	var lbl_th = _create_label("İTİCİ", Color(0.85, 0.7, 1.0), 12, false)
	lbl_th.custom_minimum_size = Vector2(60, 0)
	throttle_box.add_child(lbl_th)
	bar_throttle = _create_progress_bar(Color(0.7, 0.3, 1.0), Color(0.15, 0.05, 0.25))
	bar_throttle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar_throttle.value = 40.0
	throttle_box.add_child(bar_throttle)
	ship_vbox.add_child(throttle_box)
	
	lbl_airlock_state = _create_label("HAVA KİLİDİ: KİLİTLİ & BASINÇLI", Color(0.1, 0.95, 0.6), 12, false)
	ship_vbox.add_child(lbl_airlock_state)
	
	lbl_pilot_state = _create_label("DURUM: PİLOT KOLTUĞUNDA", Color(0.0, 0.9, 1.0), 12, false)
	ship_vbox.add_child(lbl_pilot_state)

	# 5. Sağ Taraf: Hedef Kilit Bilgi Kartı (Target Card - Geriye dönük uyumluluk)
	target_card = PanelContainer.new()
	target_card.custom_minimum_size = Vector2(320, 160)
	target_card.anchor_left = 0.79
	target_card.anchor_top = 0.20
	target_card.anchor_right = 0.98
	target_card.anchor_bottom = 0.40
	target_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	target_card.add_theme_stylebox_override("panel", _create_glass_box(Color(1.0, 0.75, 0.1, 0.55), 8, Color(0.08, 0.06, 0.02, 0.85)))
	target_card.visible = false
	add_child(target_card)
	
	var target_vbox = VBoxContainer.new()
	target_vbox.add_theme_constant_override("separation", 5)
	target_card.add_child(target_vbox)
	
	lbl_target_name = _create_label("HEDEF: TERRA NOVA", Color(1.0, 0.85, 0.2), 15, true)
	target_vbox.add_child(lbl_target_name)
	
	lbl_target_type = _create_label("TİP: YAŞANABİLİR GEZEGEN", Color(0.0, 0.9, 1.0), 13, false)
	target_vbox.add_child(lbl_target_type)
	
	lbl_target_dist = _create_label("MESAFE: 1.45 AU", Color(1.0, 0.9, 0.3), 18, true)
	target_vbox.add_child(lbl_target_dist)
	
	lbl_target_details = _create_label("YARIÇAP: 6.371 km | YERÇEKİMİ: 1.00 g", Color(0.7, 0.8, 0.9), 12, false)
	target_vbox.add_child(lbl_target_details)

	# 6. Starfield Tarzı Sol Detaylı Cisim ve Gezegen Kartı (Starfield Card)
	_build_starfield_card()

	# 7. Sol Üst Minyatür Sistem Şeması (Mini System Map)
	_build_mini_system_map()

	# 8. Alt Orta Eylem Rozetleri Barı (Action Bar)
	action_bar = HBoxContainer.new()
	action_bar.anchor_left = 0.25
	action_bar.anchor_right = 0.75
	action_bar.anchor_top = 0.93
	action_bar.anchor_bottom = 0.98
	action_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	action_bar.add_theme_constant_override("separation", 12)
	action_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(action_bar)

	# 9. Sağ Üst Gezegen LOD & Chunk Telemetri Kartı
	_build_lod_debug_card()

func _build_lod_debug_card() -> void:
	lod_debug_card = PanelContainer.new()
	lod_debug_card.anchor_left = 0.72
	lod_debug_card.anchor_right = 0.98
	lod_debug_card.anchor_top = 0.08
	lod_debug_card.anchor_bottom = 0.32
	lod_debug_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lod_debug_card.add_theme_stylebox_override("panel", _create_glass_box(Color(0.0, 0.85, 0.5, 0.5), 6, Color(0.01, 0.04, 0.08, 0.82)))
	lod_debug_card.visible = false
	add_child(lod_debug_card)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	lod_debug_card.add_child(vbox)
	
	lbl_lod_title = _create_label("GEZEGEN LOD & ARAZİ [F8: Renk]", Color(0.1, 0.95, 0.6), 13, true)
	vbox.add_child(lbl_lod_title)
	
	lbl_lod_grid_status = _create_label("DURUM: BEKLENİYOR", Color(0.8, 0.9, 1.0), 11, false)
	vbox.add_child(lbl_lod_grid_status)
	
	lbl_lod_breakdown = _create_label("LOD Dağılımı: Hesaplanıyor...", Color(0.9, 0.95, 1.0), 11, false)
	vbox.add_child(lbl_lod_breakdown)
	
	lbl_lod_perf = _create_label("Kuyruk: 0 | Süre: 0.0 ms", Color(0.7, 0.8, 0.9), 10, false)
	vbox.add_child(lbl_lod_perf)
	
	lbl_lod_color_mode = _create_label("Renk Modu [F8]: KAPALI", Color(0.9, 0.7, 0.2), 11, true)
	vbox.add_child(lbl_lod_color_mode)

# ─────────────────────────────────────────────────────────────────────────────
# GÖRSEL VE ÇİZİM DESTEĞİ (KASK VİZÖRÜ & MERKEZ NİŞANGAH)
# ─────────────────────────────────────────────────────────────────────────────
func _draw_visor_and_reticle() -> void:
	var center = visor_overlay.size * 0.5
	var glow = Color(0.0, 0.9, 1.0, 0.25)
	
	# One precise aim marker, readable against both stars and a dark cockpit.
	var ink := Color(0.005, 0.015, 0.025, 0.85)
	var aim := Color(0.78, 0.96, 1.0, 0.95)
	visor_overlay.draw_circle(center, 3.0, ink)
	visor_overlay.draw_circle(center, 1.5, aim)
	for direction in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		visor_overlay.draw_line(center + direction * 7.0, center + direction * 14.0, ink, 3.5, true)
		visor_overlay.draw_line(center + direction * 7.0, center + direction * 14.0, aim, 1.5, true)
	
	# Kask Vizör Köşe Hatları (Outer Wilds / Star Citizen Kask Hissi)
	var w = size.x
	var h = size.y
	var margin = 24.0
	var corner_len = 36.0
	
	# Sol Üst Köşe
	visor_overlay.draw_line(Vector2(margin, margin + corner_len), Vector2(margin, margin), glow, 2.0)
	visor_overlay.draw_line(Vector2(margin, margin), Vector2(margin + corner_len, margin), glow, 2.0)
	
	# Sağ Üst Köşe
	visor_overlay.draw_line(Vector2(w - margin - corner_len, margin), Vector2(w - margin, margin), glow, 2.0)
	visor_overlay.draw_line(Vector2(w - margin, margin), Vector2(w - margin, margin + corner_len), glow, 2.0)
	
	# Sol Alt Köşe
	visor_overlay.draw_line(Vector2(margin, h - margin - corner_len), Vector2(margin, h - margin), glow, 2.0)
	visor_overlay.draw_line(Vector2(margin, h - margin), Vector2(margin + corner_len, h - margin), glow, 2.0)
	
	# Sağ Alt Köşe
	visor_overlay.draw_line(Vector2(w - margin - corner_len, h - margin), Vector2(w - margin, h - margin), glow, 2.0)
	visor_overlay.draw_line(Vector2(w - margin, h - margin), Vector2(w - margin, h - margin - corner_len), glow, 2.0)

# ─────────────────────────────────────────────────────────────────────────────
# GERÇEK ZAMANLI TELEMETRİ GÜNCELLEME (HER KARE ÇAĞRILIR)
# ─────────────────────────────────────────────────────────────────────────────
func update_hud(main_node: Node3D) -> void:
	if not is_instance_valid(main_node):
		return
		
	visible = main_node.is_hud_visible
	if not visible:
		return
		
	visor_overlay.queue_redraw()
	
	var cam = main_node.camera
	var sc = main_node.spacecraft if main_node.get("spacecraft") != null else (cam.spacecraft if cam != null else null)
	var current_speed = cam.current_speed if cam != null else 0.0
	
	# 1. Üst Navigasyon Barı
	var active_star_name = main_node.active_star.name if main_node.active_star != null else "Bilinmeyen"
	lbl_system_name.text = "SİSTEM: %s" % active_star_name.to_upper()
	
	var total_seconds = int(main_node.simulation_time)
	var hours = total_seconds / 3600
	var minutes = (total_seconds % 3600) / 60
	var seconds = total_seconds % 60
	var time_str = "%02d:%02d:%02d" % [hours, minutes, seconds]
	var time_speed_str = "DURDURULDU" if main_node.is_time_paused else "%.2fx" % main_node.time_scale
	lbl_clock_time.text = "ZAMAN: %s [%s]" % [time_str, time_speed_str]
	
	# Uçuş / Seyir Modu
	if main_node.is_system_map_active:
		lbl_flight_mode.text = "🛰️ SİSTEM HARİTASI"
		lbl_flight_mode.modulate = Color(1.0, 0.65, 0.1)
	elif main_node.get("is_eva_active") == true:
		if main_node.is_landed:
			lbl_flight_mode.text = "🌍 GEZEGEN YÜZEYİ (EVA)"
			lbl_flight_mode.modulate = Color(0.1, 0.95, 0.5)
		else:
			lbl_flight_mode.text = "🧑‍🚀 SIFIR-G UZAY YÜRÜYÜŞÜ (EVA)"
			lbl_flight_mode.modulate = Color(0.0, 0.9, 1.0)
	elif main_node.get("is_interstellar_autopilot") == true:
		if main_node.get("is_interstellar_hyper_boost") == true:
			lbl_flight_mode.text = "⚡ HİPER SEYİR (YILDIZLARARASI)"
			lbl_flight_mode.modulate = Color(0.9, 0.2, 1.0)
		else:
			lbl_flight_mode.text = "WARP SEYRİ (IŞIK YILI)"
			lbl_flight_mode.modulate = Color(0.2, 0.7, 1.0)
	elif main_node.is_autopilot_active:
		if main_node.get("is_hyper_autopilot") == true:
			lbl_flight_mode.text = "⚡ HİPER OTOPİLOT"
			lbl_flight_mode.modulate = Color(0.9, 0.2, 1.0)
		else:
			lbl_flight_mode.text = "OTOPİLOT SEYRİ"
			lbl_flight_mode.modulate = Color(0.0, 0.9, 1.0)
	elif main_node.is_landed:
		lbl_flight_mode.text = "🌍 İNİŞ YAPILDI (PARK)"
		lbl_flight_mode.modulate = Color(0.1, 0.95, 0.5)
	elif sc != null and sc.current_view_mode == 1 and not sc.get("is_seated_in_cockpit"):
		lbl_flight_mode.text = "KABİN İÇİ SERBEST DOLAŞIM"
		lbl_flight_mode.modulate = Color(0.0, 0.85, 1.0)
	else:
		lbl_flight_mode.text = "KOKPİT SÜRÜŞÜ"
		lbl_flight_mode.modulate = Color(0.1, 0.95, 0.6)

	# 2. Oyuncu / Astronot Yaşam Destek Paneli
	var o2_val = main_node.get("astronaut_oxygen") if main_node.get("astronaut_oxygen") != null else 100.0
	var fuel_val = main_node.get("astronaut_fuel") if main_node.get("astronaut_fuel") != null else 100.0
	bar_oxygen.value = o2_val
	bar_fuel.value = fuel_val
	
	var lamp_on = cam.headlamp.visible if (cam != null and cam.get("headlamp") != null) else false
	lbl_headlamp_status.text = "FENER [L]: %s" % ("AÇIK" if lamp_on else "KAPALI")
	lbl_headlamp_status.modulate = Color(0.1, 0.95, 0.6) if lamp_on else Color(0.6, 0.65, 0.7)
	
	if main_node.get("is_eva_active") == true:
		player_card.visible = true
		lbl_player_title.text = "ASTRONOT YAŞAM DESTEK (EVA)"
		var eva_vel = main_node.player_velocity.length()
		var boost_str = " (BOOST)" if main_node.get("is_jetpack_boosting") else ""
		lbl_player_speed.text = "EVA HIZI: %.1f m/s%s" % [eva_vel, boost_str]
	elif sc != null and sc.current_view_mode == 1 and not sc.get("is_seated_in_cockpit"):
		player_card.visible = true
		lbl_player_title.text = "ASTRONOT (KABİN İÇİ)"
		lbl_player_speed.text = "KONUM: %s" % ("HAVA KİLİDİ" if sc.near_airlock else ("KOLTUK YANI" if sc.near_pilot_seat else "KORİDOR"))
	else:
		player_card.visible = true
		lbl_player_title.text = "PİLOT YAŞAM DESTEK"
		lbl_player_speed.text = "PİLOT: KOKPİTTE GÜVENDE"

	# 3. Keşif Korveti Telemetrisi
	var actual_speed: float = float(main_node.flight_speed_mps) if main_node.get("flight_speed_mps") != null else 0.0
	if main_node.is_eva_active:
		lbl_ship_speed_val.text = "GEMİ: %.1f m" % main_node.dist_to_ship_eva
		lbl_ship_throttle_val.text = "EVA BAĞLANTISI"
		lbl_ship_speed_val.modulate = Color(0.3, 1.0, 0.6)
	else:
		lbl_ship_speed_val.text = _format_speed(actual_speed)
		lbl_ship_throttle_val.text = _format_speed(current_speed)
		if actual_speed > 0.5:
			lbl_ship_speed_val.modulate = Color(0.3, 1.0, 0.6)
		else:
			lbl_ship_speed_val.modulate = Color(0.7, 0.75, 0.8)
	
	if sc != null:
		var is_warp = (main_node.get("is_interstellar_autopilot") == true) or (main_node.get("is_hyper_autopilot") == true)
		if is_warp:
			bar_throttle.value = 100.0
			bar_throttle.modulate = Color(1.0, 0.3, 1.0)
		elif main_node.is_autopilot_active:
			bar_throttle.value = 85.0
			bar_throttle.modulate = Color(0.0, 0.9, 1.0)
		elif actual_speed > 0.5:
			var throttle_ratio = clampf(actual_speed / maxf(current_speed, 0.001), 0.1, 1.0)
			bar_throttle.value = throttle_ratio * 100.0
			bar_throttle.modulate = Color(0.2, 0.9, 0.5)
		else:
			bar_throttle.value = 0.0
			bar_throttle.modulate = Color(0.4, 0.45, 0.55)
			
		var airlock_open = sc.is_airlock_open
		lbl_airlock_state.text = "HAVA KİLİDİ: %s" % ("RAMPA AÇIK (VAKUM)" if airlock_open else "KİLİTLİ & BASINÇLI")
		lbl_airlock_state.modulate = Color(1.0, 0.35, 0.1) if airlock_open else Color(0.1, 0.95, 0.6)
		
		if sc.is_seated_in_cockpit:
			lbl_pilot_state.text = "KOKPİT: PİLOT KOLTUĞUNDA"
			lbl_pilot_state.modulate = Color(0.1, 0.95, 0.6)
		else:
			lbl_pilot_state.text = "KOKPİT: BOŞ (KABİNDE / DIŞARIDA)"
			lbl_pilot_state.modulate = Color(1.0, 0.75, 0.2)

	# 4. Sol Üst Mini Sistem Haritası ve Starfield Kartı Yönetimi
	mini_map_main_ref = main_node
	if main_node.is_system_map_active:
		mini_system_map.visible = true
		mini_system_map.queue_redraw()
		player_card.visible = false
		ship_card.visible = false
		starfield_card.anchor_top = 0.29
		starfield_card.anchor_bottom = 0.94
	else:
		mini_system_map.visible = false
		starfield_card.anchor_top = 0.12
		starfield_card.anchor_bottom = 0.88

	# Starfield Bilgi Kartını Güncelle
	_update_starfield_card(main_node)

	# 5. Gezegen LOD & Chunk Telemetri Kartı
	_update_lod_debug_card(main_node)

	# 6. Dinamik Eylemler ve Tuş Rozetleri
	_update_action_badges(main_node, sc)

func _update_lod_debug_card(main_node: Node3D) -> void:
	if not is_instance_valid(lod_debug_card):
		return
		
	var lod_mgr = main_node.get("landed_lod_manager")
	if is_instance_valid(lod_mgr) and lod_mgr.has_method("get_lod_stats") and lod_mgr.is_active():
		lod_debug_card.visible = true
		var stats: Dictionary = lod_mgr.get_lod_stats()
		var total_chunks = stats.get("total_chunks", 0)
		var grid_pos: Vector2i = stats.get("grid_pos", Vector2i.ZERO)
		var counts: Dictionary = stats.get("lod_counts", {})
		var c_mode = stats.get("debug_color_mode", false)
		var q_size = stats.get("build_queue_size", 0)
		var b_usec = stats.get("last_build_usec", 0)
		
		lbl_lod_grid_status.text = "Grid: (%d, %d) | Aktif Parça: %d" % [grid_pos.x, grid_pos.y, total_chunks]
		lbl_lod_breakdown.text = "L0(40x40): %d [Yeşil]  L1(24x24): %d [Mavi]\nL2(14x14): %d [Sarı]   L3(6x6): %d [Turuncu]\nL4(2x2): %d [Kırmızı]" % [
			counts.get(0, 0), counts.get(1, 0), counts.get(2, 0), counts.get(3, 0), counts.get(4, 0)
		]
		lbl_lod_perf.text = "Kuyruk: %d | Son Üretim: %.2f ms" % [q_size, b_usec / 1000.0]
		if c_mode:
			lbl_lod_color_mode.text = "Görsel Debug [F8]: AÇIK (LOD Renkleri)"
			lbl_lod_color_mode.modulate = Color(0.2, 1.0, 0.4)
		else:
			lbl_lod_color_mode.text = "Görsel Debug [F8]: KAPALI (Standart Doku)"
			lbl_lod_color_mode.modulate = Color(0.9, 0.7, 0.2)
	else:
		lod_debug_card.visible = false

# ─────────────────────────────────────────────────────────────────────────────
# EYLEM TUŞ ROZETLERİ GÜNCELLEMESİ
# ─────────────────────────────────────────────────────────────────────────────
func _update_action_badges(main_node: Node3D, sc: Spacecraft) -> void:
	for child in action_bar.get_children():
		child.queue_free()
		
	if main_node.is_system_map_active:
		_add_badge("[M] HARİTADAN ÇIK", Color(1.0, 0.6, 0.1))
		_add_badge("[SOL TIK] SEÇ", Color(0.0, 0.9, 1.0))
		_add_badge("[P] ZAMANI DURDUR", Color(0.8, 0.8, 0.9))
		_add_badge("[TAB] HUD", Color(0.6, 0.6, 0.7))
		return
		
	if main_node.get("is_eva_active") == true:
		if main_node.get("is_near_ship_airlock") == true:
			_add_badge("[E] GEMİYE BİN (HAVA KİLİDİ)", Color(0.1, 1.0, 0.5))
		_add_badge("[WASD] İTİCİ", Color(0.0, 0.85, 1.0))
		_add_badge("[X] FREN | [F] KAMERA", Color(0.5, 0.8, 1.0))
		_add_badge("[SHIFT] BOOST", Color(1.0, 0.6, 0.1))
		_add_badge("[SPACE] YÜKSEL", Color(0.0, 0.85, 1.0))
		_add_badge("[CTRL] ALÇAL", Color(0.0, 0.85, 1.0))
		_add_badge("[L] FENER", Color(0.1, 1.0, 0.6))
		_add_badge("[TAB] HUD", Color(0.6, 0.6, 0.7))
		return
		
	if sc != null and sc.current_view_mode == 1 and not sc.get("is_seated_in_cockpit"):
		if sc.get("near_airlock"):
			var act = "HAVA KİLİDİNİ KAPAT" if sc.is_airlock_open else "HAVA KİLİDİNİ AÇ (DIŞARI ÇIK)"
			_add_badge("[E] %s" % act, Color(0.1, 1.0, 0.5))
		elif sc.get("near_pilot_seat"):
			_add_badge("[E] KOLTUĞA OTUR", Color(0.1, 1.0, 0.5))
		_add_badge("[WASD] KABİNDE YÜRÜ", Color(0.0, 0.85, 1.0))
		_add_badge("[F] KAMERA MODU", Color(0.8, 0.5, 1.0))
		_add_badge("[TAB] HUD", Color(0.6, 0.6, 0.7))
		return
		
	# Kokpit Sürüşü veya 3. Şahıs
	if main_node.is_interstellar_autopilot or main_node.is_autopilot_active:
		_add_badge("[G] HİPER HIZLANDIR (ÇİFT G)", Color(1.0, 0.2, 0.9))
		_add_badge("[WASD] İPTAL ET", Color(1.0, 0.4, 0.3))
	else:
		if main_node.current_target_index >= 0 or main_node.targeted_star_data != null:
			_add_badge("[G] OTOPİLOT SEYRİ", Color(0.1, 1.0, 0.5))
			_add_badge("[C] ODAKLAN", Color(0.0, 0.9, 1.0))
			_add_badge("[CTRL+T] IŞINLAN", Color(1.0, 0.7, 0.2))
		if sc != null and sc.current_view_mode == 1 and sc.get("is_seated_in_cockpit"):
			_add_badge("[E] KOLTUKTAN KALK", Color(0.0, 0.9, 1.0))
		if main_node.is_landed:
			_add_badge("[F8] LOD RENKLERİ", Color(0.2, 0.9, 0.5))
		_add_badge("[WASD] GEMİ SÜRÜŞÜ", Color(0.0, 0.85, 1.0))
		_add_badge("[Q] ROLL", Color(0.0, 0.85, 1.0))
		_add_badge("[F] KAMERA MODU", Color(0.8, 0.5, 1.0))
		_add_badge("[M] HARİTA", Color(1.0, 0.65, 0.1))
		_add_badge("[TAB] HUD", Color(0.6, 0.6, 0.7))

func _add_badge(text: String, color: Color) -> void:
	var badge = PanelContainer.new()
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_theme_stylebox_override("panel", _create_glass_box(color, 6, Color(0.04, 0.08, 0.14, 0.75)))
	var lbl = _create_label(text, color, 12, true)
	lbl.custom_minimum_size = Vector2(0, 22)
	badge.add_child(lbl)
	action_bar.add_child(badge)

# ─────────────────────────────────────────────────────────────────────────────
# YARDIMCI STİL VE METİN BİÇİMLENDİRME
# ─────────────────────────────────────────────────────────────────────────────
func _create_glass_box(border_color: Color, corner_rad: int, bg_color: Color) -> StyleBoxFlat:
	var box = StyleBoxFlat.new()
	box.bg_color = bg_color
	box.border_color = border_color
	box.border_width_left = 1
	box.border_width_top = 1
	box.border_width_right = 1
	box.border_width_bottom = 1
	box.corner_radius_top_left = corner_rad
	box.corner_radius_top_right = corner_rad
	box.corner_radius_bottom_left = corner_rad
	box.corner_radius_bottom_right = corner_rad
	box.content_margin_left = 10
	box.content_margin_right = 10
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	return box

func _create_progress_bar(fill_color: Color, bg_color: Color) -> ProgressBar:
	var pb = ProgressBar.new()
	pb.custom_minimum_size = Vector2(0, 14)
	pb.show_percentage = false
	pb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	var bg_box = StyleBoxFlat.new()
	bg_box.bg_color = bg_color
	bg_box.corner_radius_top_left = 4
	bg_box.corner_radius_top_right = 4
	bg_box.corner_radius_bottom_left = 4
	bg_box.corner_radius_bottom_right = 4
	pb.add_theme_stylebox_override("background", bg_box)
	
	var fill_box = StyleBoxFlat.new()
	fill_box.bg_color = fill_color
	fill_box.corner_radius_top_left = 4
	fill_box.corner_radius_top_right = 4
	fill_box.corner_radius_bottom_left = 4
	fill_box.corner_radius_bottom_right = 4
	pb.add_theme_stylebox_override("fill", fill_box)
	return pb

func _create_label(text: String, color: Color, font_size: int, bold: bool) -> Label:
	var lbl = Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return lbl

func _format_speed(current_speed: float) -> String:
	if current_speed >= 100.0 * LIGHT_YEAR:
		return "%d Işık Yılı/s" % int(round(current_speed / LIGHT_YEAR))
	elif current_speed >= 1.0 * LIGHT_YEAR:
		return "%.1f Işık Yılı/s" % (current_speed / LIGHT_YEAR)
	elif current_speed >= 0.001 * LIGHT_YEAR:
		return "%.4f Işık Yılı/s" % (current_speed / LIGHT_YEAR)
	elif current_speed >= 0.1 * ONE_AU:
		return "%.2f AU/s" % (current_speed / ONE_AU)
	elif current_speed >= LIGHT_SPEED:
		return "%.2f C (Işık Hızı)" % (current_speed / LIGHT_SPEED)
	elif current_speed >= 1000.0:
		return "%.2f km/s" % (current_speed / 1000.0)
	else:
		return "%.1f m/s" % current_speed

func _format_distance(meters: float) -> String:
	if meters >= 0.01 * LIGHT_YEAR:
		return "%.2f Işık Yılı" % (meters / LIGHT_YEAR)
	elif meters >= 0.1 * ONE_AU:
		return "%.2f AU" % (meters / ONE_AU)
	elif meters >= 1000000000.0:
		return "%.2f Milyon km" % (meters / 1000000000.0)
	elif meters >= 1000000.0:
		return "%.1f Bin km" % (meters / 1000000.0)
	elif meters >= 1000.0:
		return "%.2f km" % (meters / 1000.0)
	else:
		return "%.0f m" % meters

# ─────────────────────────────────────────────────────────────────────────────
# STARFIELD TARZI DETAYLI CİSİM KARTI VE MİNYATÜR SİSTEM HARİTASI
# ─────────────────────────────────────────────────────────────────────────────
func _build_starfield_card() -> void:
	starfield_card = PanelContainer.new()
	starfield_card.custom_minimum_size = Vector2(360, 480)
	starfield_card.anchor_left = 0.02
	starfield_card.anchor_top = 0.12
	starfield_card.anchor_right = 0.28
	starfield_card.anchor_bottom = 0.90
	starfield_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	starfield_card.add_theme_stylebox_override("panel", _create_glass_box(Color(0.2, 0.6, 0.9, 0.7), 10, Color(0.02, 0.04, 0.08, 0.93)))
	starfield_card.visible = false
	add_child(starfield_card)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 12)
	starfield_card.add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)

	# 1. Sistem Adı
	lbl_sf_system = _create_label("ALPHA CENTAURI SİSTEMİ", Color(0.35, 0.75, 1.0), 12, false)
	lbl_sf_system.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	vbox.add_child(lbl_sf_system)

	# 2. Cisim Adı (Büyük Başlık)
	lbl_sf_name = _create_label("JEMISON", Color(0.95, 0.98, 1.0), 22, true)
	lbl_sf_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	vbox.add_child(lbl_sf_name)

	# 3. Tarama Durumu (Survey Progress)
	var survey_box = HBoxContainer.new()
	survey_box.add_theme_constant_override("separation", 8)
	var lbl_surv_title = _create_label("TARAMA", Color(0.65, 0.75, 0.85), 11, true)
	lbl_surv_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	survey_box.add_child(lbl_surv_title)

	bar_sf_survey = _create_progress_bar(Color(0.1, 0.8, 1.0), Color(0.04, 0.12, 0.2))
	bar_sf_survey.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar_sf_survey.value = 100.0
	survey_box.add_child(bar_sf_survey)

	lbl_sf_survey_val = _create_label("%100", Color(0.3, 1.0, 0.6), 12, true)
	survey_box.add_child(lbl_sf_survey_val)
	vbox.add_child(survey_box)

	# Ayırıcı
	vbox.add_child(_create_h_separator(Color(0.2, 0.5, 0.7, 0.5)))

	# 4. Parametreler Tablosu (2 Sütunlu Temiz Bilgi Tablosu)
	sf_table_vbox = VBoxContainer.new()
	sf_table_vbox.add_theme_constant_override("separation", 3)
	vbox.add_child(sf_table_vbox)

	var rows = [
		["TİP", "Karasal Dünya"],
		["YERÇEKİMİ", "1.00 G"],
		["SICAKLIK", "Ilıman (15 °C)"],
		["ATMOSFER", "Standart O2-N2 (%21)"],
		["MANYETOSFER", "Güçlü Manyetik Alan"],
		["SU", "Biyolojik Güvenli"],
		["BİYOM", "Ormanlar & Okyanuslar"],
		["YARIÇAP", "6.371 km"],
		["MESAFE", "1.00 AU"]
	]
	for r in rows:
		var row_box = HBoxContainer.new()
		var lbl_key = _create_label(r[0], Color(0.55, 0.65, 0.75), 11, false)
		lbl_key.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		lbl_key.custom_minimum_size = Vector2(95, 0)
		row_box.add_child(lbl_key)

		var lbl_val = _create_label(r[1], Color(0.9, 0.95, 1.0), 11, true)
		lbl_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		lbl_val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row_box.add_child(lbl_val)

		sf_table_vbox.add_child(row_box)
		sf_row_labels[r[0]] = lbl_val

	# Ayırıcı
	vbox.add_child(_create_h_separator(Color(0.2, 0.5, 0.7, 0.5)))

	# 5. Kaynaklar (Resources) Başlığı ve Rozet Grid'i
	lbl_sf_resources_title = _create_label("KAYNAKLAR / ELEMENTLER", Color(0.7, 0.85, 1.0), 11, true)
	lbl_sf_resources_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	vbox.add_child(lbl_sf_resources_title)

	sf_resources_box = HFlowContainer.new()
	sf_resources_box.add_theme_constant_override("h_separation", 6)
	sf_resources_box.add_theme_constant_override("v_separation", 6)
	vbox.add_child(sf_resources_box)

	# Ayırıcı
	vbox.add_child(_create_h_separator(Color(0.2, 0.5, 0.7, 0.4)))

	# 6. Alt Eylem Rozetleri
	var hints_box = HBoxContainer.new()
	hints_box.add_theme_constant_override("separation", 8)
	hints_box.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(hints_box)

	var h_g = _create_badge_label("[G] SEYAHAT", Color(0.1, 1.0, 0.6))
	hints_box.add_child(h_g)
	var h_c = _create_badge_label("[C] BOŞA DÜŞÜR", Color(1.0, 0.45, 0.35))
	hints_box.add_child(h_c)
	var h_l = _create_badge_label("[L] İNİŞ", Color(0.0, 0.9, 1.0))
	hints_box.add_child(h_l)

func _build_mini_system_map() -> void:
	mini_system_map = Control.new()
	mini_system_map.custom_minimum_size = Vector2(230, 150)
	mini_system_map.anchor_left = 0.02
	mini_system_map.anchor_top = 0.075
	mini_system_map.anchor_right = 0.20
	mini_system_map.anchor_bottom = 0.27
	mini_system_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mini_system_map.visible = false
	add_child(mini_system_map)
	mini_system_map.draw.connect(_draw_mini_system_map)

func _draw_mini_system_map() -> void:
	if mini_map_main_ref == null or not is_instance_valid(mini_map_main_ref):
		return
	var main_node = mini_map_main_ref
	var map_size = mini_system_map.size
	var center = map_size * 0.5

	# Koyu cam arka plan
	var bg_rect = Rect2(Vector2.ZERO, map_size)
	mini_system_map.draw_rect(bg_rect, Color(0.02, 0.04, 0.08, 0.88), true)
	mini_system_map.draw_rect(bg_rect, Color(0.2, 0.5, 0.8, 0.5), false, 1.0)

	# Merkez Yıldız
	var star_col = Color(1.0, 0.85, 0.2)
	if main_node.active_star != null and main_node.active_star.light_color != null:
		star_col = main_node.active_star.light_color
	mini_system_map.draw_circle(center, 5.0, star_col)
	mini_system_map.draw_circle(center, 9.0, Color(star_col.r, star_col.g, star_col.b, 0.25))

	# Gezegenleri ve yörünge halkalarını çiz
	var max_r = minf(center.x, center.y) - 12.0
	var planets: Array = []
	for b in main_node.universe:
		if b.type == "PLANET":
			planets.append(b)

	if planets.is_empty():
		return

	var count = planets.size()
	var step_r = max_r / float(count + 1)

	var selected_body: CelestialBody = null
	if main_node.current_target_index >= 0 and main_node.current_target_index < main_node.universe.size():
		selected_body = main_node.universe[main_node.current_target_index]

	for i in range(count):
		var p = planets[i]
		var orb_r = step_r * float(i + 1)
		var is_selected = (p == selected_body)

		# İnce yörünge çemberi
		var orbit_col = Color(0.2, 0.4, 0.6, 0.35) if not is_selected else Color(0.0, 0.8, 1.0, 0.65)
		mini_system_map.draw_arc(center, orb_r, 0, TAU, 32, orbit_col, 1.0)

		# Gezegenin açısı
		var ang = p.orbit_angle if p.get("orbit_angle") != null else (float(i) * 1.2)
		var p_pos = center + Vector2(cos(ang), sin(ang)) * orb_r

		# Gezegen noktası
		var p_col = p.base_color if p.get("base_color") != null else Color(0.6, 0.8, 1.0)
		var p_rad = 3.0 if not is_selected else 4.5
		mini_system_map.draw_circle(p_pos, p_rad, p_col)

		# Seçiliyse vurgulayıcı hedef halkası
		if is_selected:
			mini_system_map.draw_arc(p_pos, 7.5, 0, TAU, 16, Color(0.0, 1.0, 0.7, 0.9), 1.5)

func _update_starfield_card(main_node: Node3D) -> void:
	if main_node.targeted_star_data != null:
		var info = _get_stardata_survey_info(main_node.targeted_star_data, main_node)
		_apply_survey_info_to_card(info)
		starfield_card.visible = true
		target_card.visible = true
		lbl_target_name.text = "HEDEF: %s" % info["name"]
		lbl_target_type.text = "TİP: %s" % info["type"]
		lbl_target_dist.text = "MESAFE: %s" % info["dist"]
		lbl_target_details.text = "YARIÇAP: %s | %s" % [info["radius"], info["temp"]]
	elif main_node.current_target_index >= 0 and main_node.current_target_index < main_node.universe.size():
		var b = main_node.universe[main_node.current_target_index]
		var info = _get_body_survey_info(b, main_node)
		_apply_survey_info_to_card(info)
		starfield_card.visible = true
		target_card.visible = true
		lbl_target_name.text = "HEDEF: %s" % info["name"]
		lbl_target_type.text = "TİP: %s" % info["type"]
		lbl_target_dist.text = "MESAFE: %s" % info["dist"]
		lbl_target_details.text = "YARIÇAP: %s | %s" % [info["radius"], info["gravity"]]
	else:
		starfield_card.visible = false
		target_card.visible = false

func _apply_survey_info_to_card(info: Dictionary) -> void:
	lbl_sf_system.text = info["system"]
	lbl_sf_name.text = info["name"]
	lbl_sf_survey_val.text = "%%%d" % info["survey_pct"]
	bar_sf_survey.value = float(info["survey_pct"])

	if sf_row_labels.has("TİP"):
		sf_row_labels["TİP"].text = info["type"]
	if sf_row_labels.has("YERÇEKİMİ"):
		sf_row_labels["YERÇEKİMİ"].text = info["gravity"]
	if sf_row_labels.has("SICAKLIK"):
		sf_row_labels["SICAKLIK"].text = info["temp"]
	if sf_row_labels.has("ATMOSFER"):
		sf_row_labels["ATMOSFER"].text = info["atmo"]
	if sf_row_labels.has("MANYETOSFER"):
		sf_row_labels["MANYETOSFER"].text = info["mag"]
	if sf_row_labels.has("SU"):
		sf_row_labels["SU"].text = info["water"]
	if sf_row_labels.has("BİYOM"):
		sf_row_labels["BİYOM"].text = info["biome"]
	if sf_row_labels.has("YARIÇAP"):
		sf_row_labels["YARIÇAP"].text = info["radius"]
	if sf_row_labels.has("MESAFE"):
		sf_row_labels["MESAFE"].text = info["dist"]

	# Kaynak kutucuklarını doldur
	for child in sf_resources_box.get_children():
		child.queue_free()

	var res_list: Array = info.get("resources", [])
	for r in res_list:
		var badge = _create_resource_badge(r["sym"], r["name"], r["col"])
		sf_resources_box.add_child(badge)

func _get_body_survey_info(body: CelestialBody, main_node: Node3D) -> Dictionary:
	var info = {}
	info["name"] = body.name.to_upper()
	var sys_name = main_node.active_star.name if main_node.active_star != null else "BİLİNMEYEN"
	info["system"] = "%s SİSTEMİ" % sys_name.to_upper()

	var hash_val = absi(body.name.hash())
	var survey_pct = 60 + (hash_val % 41)
	info["survey_pct"] = survey_pct

	info["dist"] = _format_distance(body.real_position.length())
	info["radius"] = _format_distance(body.real_radius)

	if body.type == "STAR":
		info["type"] = "Yıldız (%s)" % (body.spectral_type if body.spectral_type != "" else "G-Tipi")
		info["gravity"] = "28.0 G"
		info["temp"] = "5.778 K (Yüzey)"
		info["atmo"] = "Güneş Koronası (H-He Plazma)"
		info["mag"] = "Çok Güçlü Manyetik Alan"
		info["water"] = "Yok (Plazma)"
		info["biome"] = "Fotosfer & Radyatif Kuşak"
		info["resources"] = [
			{"sym": "H", "name": "Hidrojen", "col": Color(0.3, 0.75, 1.0)},
			{"sym": "He-3", "name": "Helyum-3", "col": Color(1.0, 0.9, 0.2)},
			{"sym": "Fe", "name": "Demir", "col": Color(0.9, 0.5, 0.2)},
			{"sym": "Pl", "name": "Plazma", "col": Color(1.0, 0.4, 0.8)}
		]
		return info

	var r_ratio = body.real_radius / 6371000.0
	var ptype = body.planet_type.to_lower()
	var g_factor = 1.0

	if "gaz" in ptype:
		g_factor = 2.4
		info["type"] = "Gaz Devi"
		info["temp"] = "Soğuk (-145 °C)"
		info["atmo"] = "Yoğun H2 / He / CH4"
		info["mag"] = "Aşırı Güçlü"
		info["water"] = "Eser Buhar Bulutları"
		info["biome"] = "Moleküler Gaz Kuşakları & Girdaplar"
		info["resources"] = [
			{"sym": "H", "name": "Hidrojen", "col": Color(0.35, 0.75, 1.0)},
			{"sym": "He-3", "name": "Helyum-3", "col": Color(1.0, 0.85, 0.2)},
			{"sym": "CH4", "name": "Metan", "col": Color(0.2, 0.9, 0.7)},
			{"sym": "Ne", "name": "Neon", "col": Color(1.0, 0.3, 0.3)}
		]
	elif "buz" in ptype:
		g_factor = 0.8
		info["type"] = "Buz Dünyası / Devi"
		info["temp"] = "Dondurucu (-190 °C)"
		info["atmo"] = "N2 & Metan Sis Kuşağı" if body.has_atmosphere else "Vakum"
		info["mag"] = "Orta Seviye"
		info["water"] = "Geniş Buz Katmanları & Ağır Su"
		info["biome"] = "Buzul Ovaları & Kriyovolkanlar"
		info["resources"] = [
			{"sym": "H2O", "name": "Buz / Su", "col": Color(0.2, 0.75, 1.0)},
			{"sym": "Ar", "name": "Argon", "col": Color(0.1, 0.9, 0.85)},
			{"sym": "N2", "name": "Azot", "col": Color(0.5, 0.65, 0.9)},
			{"sym": "NH3", "name": "Amonyak", "col": Color(0.8, 0.5, 0.9)},
			{"sym": "Cl", "name": "Klor", "col": Color(0.6, 0.9, 0.3)}
		]
	elif "yaşanabilir" in ptype or "dünya" in ptype or "terra" in ptype:
		g_factor = 1.0
		info["type"] = "Karasal / Yaşanabilir"
		info["temp"] = "Ilıman (15 °C)"
		info["atmo"] = "Standart O2-N2 (%21 O2)"
		info["mag"] = "Güçlü Manyetosfer"
		info["water"] = "Biyolojik Güvenli Sıvı Su"
		info["biome"] = "Ilıman Ormanlar, Okyanuslar, Savan"
		info["resources"] = [
			{"sym": "H2O", "name": "Su", "col": Color(0.2, 0.75, 1.0)},
			{"sym": "Fe", "name": "Demir", "col": Color(0.9, 0.5, 0.2)},
			{"sym": "Ni", "name": "Nikel", "col": Color(0.85, 0.8, 0.55)},
			{"sym": "Cu", "name": "Bakır", "col": Color(0.95, 0.55, 0.35)},
			{"sym": "Ar", "name": "Argon", "col": Color(0.1, 0.9, 0.85)},
			{"sym": "Ti", "name": "Titanyum", "col": Color(0.75, 0.4, 0.95)},
			{"sym": "Au", "name": "Altın", "col": Color(1.0, 0.85, 0.1)}
		]
	elif "çöl" in ptype:
		g_factor = 0.85
		info["type"] = "Çöl Dünyası"
		info["temp"] = "Sıcak (45 °C)"
		info["atmo"] = "İnce CO2 / Azot" if body.has_atmosphere else "Vakum"
		info["mag"] = "Zayıf"
		info["water"] = "Yok (Kuru Kum)"
		info["biome"] = "Kum Tepecikleri, Kanyonlar, Çorak Kayalık"
		info["resources"] = [
			{"sym": "Fe", "name": "Demir", "col": Color(0.9, 0.5, 0.2)},
			{"sym": "Si", "name": "Silisyum", "col": Color(0.65, 0.75, 0.85)},
			{"sym": "Ti", "name": "Titanyum", "col": Color(0.75, 0.4, 0.95)},
			{"sym": "Pb", "name": "Kurşun", "col": Color(0.5, 0.55, 0.65)},
			{"sym": "U", "name": "Uranyum", "col": Color(0.25, 1.0, 0.35)}
		]
	elif "volkanik" in ptype or "lav" in ptype:
		g_factor = 1.1
		info["type"] = "Volkanik Cehennem Dünyası"
		info["temp"] = "Kavurucu (480 °C)"
		info["atmo"] = "Zehirli Kükürt Dioksit" if body.has_atmosphere else "Vakum"
		info["mag"] = "Kararsız Manyetik Alan"
		info["water"] = "Yok (Lav Gölleri)"
		info["biome"] = "Aktif Lav Nehirleri, Bazalt Dağları"
		info["resources"] = [
			{"sym": "Fe", "name": "Demir", "col": Color(0.9, 0.5, 0.2)},
			{"sym": "Ti", "name": "Titanyum", "col": Color(0.75, 0.4, 0.95)},
			{"sym": "Pt", "name": "Platin", "col": Color(0.8, 0.9, 1.0)},
			{"sym": "Au", "name": "Altın", "col": Color(1.0, 0.85, 0.1)},
			{"sym": "W", "name": "Tungsten", "col": Color(0.6, 0.7, 0.8)}
		]
	else:
		if body.type == "MOON":
			g_factor = 0.25
			info["type"] = "Çorak Ay / Uydu"
			info["temp"] = "Aşırı Değişken (-160°C / +120°C)"
			info["atmo"] = "Yok (Tam Vakum)"
			info["mag"] = "Yok"
			info["water"] = "Eser Krater Buzları"
			info["biome"] = "Regolit Ovaları, Çarpma Kraterleri"
			info["resources"] = [
				{"sym": "He-3", "name": "Helyum-3", "col": Color(1.0, 0.85, 0.2)},
				{"sym": "Fe", "name": "Demir", "col": Color(0.9, 0.5, 0.2)},
				{"sym": "Ti", "name": "Titanyum", "col": Color(0.75, 0.4, 0.95)},
				{"sym": "Al", "name": "Alüminyum", "col": Color(0.75, 0.8, 0.85)}
			]
		else:
			g_factor = 0.7
			info["type"] = body.planet_type if body.planet_type != "" else "Karasal Gezegen"
			info["temp"] = "Soğuk (-35 °C)"
			info["atmo"] = "İnce Atmosfer" if body.has_atmosphere else "Yok (Vakum)"
			info["mag"] = "Orta"
			info["water"] = "Yeraltı Akiferleri"
			info["biome"] = "Kayalık Vadiler, Platomsu Sırtlar"
			info["resources"] = [
				{"sym": "Fe", "name": "Demir", "col": Color(0.9, 0.5, 0.2)},
				{"sym": "Ni", "name": "Nikel", "col": Color(0.85, 0.8, 0.55)},
				{"sym": "Cu", "name": "Bakır", "col": Color(0.95, 0.55, 0.35)},
				{"sym": "Pb", "name": "Kurşun", "col": Color(0.5, 0.55, 0.65)}
			]

	var calc_g = clampf(r_ratio * g_factor, 0.05, 3.5)
	info["gravity"] = "%.2f G" % calc_g
	return info

func _get_stardata_survey_info(star_data, main_node: Node3D) -> Dictionary:
	var info = {}
	info["name"] = star_data.name.to_upper()
	info["system"] = "GALAKTİK SEKTÖR [%d,%d,%d]" % [star_data.sector_coord.x, star_data.sector_coord.y, star_data.sector_coord.z]
	info["survey_pct"] = 100
	var gal_pos = main_node.get_player_galactic_position()
	var star_pos = Vector3(star_data.stellar_x, star_data.stellar_y, star_data.stellar_z)
	var dist = (star_pos - gal_pos).length()
	info["dist"] = _format_distance(dist)
	info["radius"] = _format_distance(star_data.radius)
	info["type"] = "Galaktik Yıldız (%s)" % star_data.spectral_type
	info["gravity"] = "25.0+ G (Kütle Çekim)"
	info["temp"] = "Spektral Sınıf: %s" % star_data.spectral_type
	info["atmo"] = "Yıldız Koronası"
	info["mag"] = "Devasa Galaktik Manyetosfer"
	info["water"] = "Yok (Nükleer Füzyon)"
	info["biome"] = "Plazma Çekirdeği & Korona"
	info["resources"] = [
		{"sym": "H", "name": "Hidrojen", "col": Color(0.35, 0.75, 1.0)},
		{"sym": "He-3", "name": "Helyum-3", "col": Color(1.0, 0.85, 0.2)},
		{"sym": "Pl", "name": "Plazma", "col": Color(1.0, 0.4, 0.8)},
		{"sym": "Fe", "name": "Ağır Element", "col": Color(0.9, 0.5, 0.2)}
	]
	return info

func _create_resource_badge(symbol: String, name: String, col: Color) -> PanelContainer:
	var p = PanelContainer.new()
	p.custom_minimum_size = Vector2(46, 38)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var style = StyleBoxFlat.new()
	style.bg_color = Color(col.r * 0.15, col.g * 0.15, col.b * 0.15, 0.9)
	style.border_color = col
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 4
	style.content_margin_right = 4
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	p.add_theme_stylebox_override("panel", style)

	var vb = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 0)
	p.add_child(vb)

	var lbl_sym = Label.new()
	lbl_sym.text = symbol
	lbl_sym.add_theme_font_size_override("font_size", 12)
	lbl_sym.add_theme_color_override("font_color", col)
	lbl_sym.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(lbl_sym)

	var lbl_nm = Label.new()
	lbl_nm.text = name
	lbl_nm.add_theme_font_size_override("font_size", 8)
	lbl_nm.add_theme_color_override("font_color", Color(0.75, 0.8, 0.85))
	lbl_nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(lbl_nm)

	return p

func _create_badge_label(text: String, col: Color) -> PanelContainer:
	var badge = PanelContainer.new()
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_theme_stylebox_override("panel", _create_glass_box(col, 5, Color(0.04, 0.08, 0.12, 0.8)))
	var lbl = _create_label(text, col, 10, true)
	lbl.custom_minimum_size = Vector2(0, 18)
	badge.add_child(lbl)
	return badge

func _create_h_separator(col: Color) -> HSeparator:
	var sep = HSeparator.new()
	var box = StyleBoxLine.new()
	box.color = col
	box.thickness = 1
	sep.add_theme_stylebox_override("separator", box)
	return sep
