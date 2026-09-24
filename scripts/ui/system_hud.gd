class_name SystemHUD
extends Control

# ─────────────────────────────────────────────────────────────────────────────
# Modüler serbest uçuş, navigasyon ve gök cismi bilgi arayüzü.
# ─────────────────────────────────────────────────────────────────────────────

const LIGHT_SPEED: float = 299792458.0
const ONE_AU: float = 149597870700.0
const LIGHT_YEAR: float = 9460730472580800.0
const PlanetSphere = preload("res://scripts/rendering/planet_chunk_sphere.gd")

# Üst Bar (Navigasyon & Sistem)
var top_bar: PanelContainer
var lbl_system_name: Label
var lbl_flight_mode: Label
var lbl_clock_time: Label

# Sağ Alt (Serbest Uçuş Telemetrisi)
var flight_card: PanelContainer
var lbl_flight_title: Label
var lbl_flight_speed_val: Label
var lbl_speed_limit_val: Label
var bar_throttle: ProgressBar
var lbl_camera_state: Label
var lbl_control_state: Label

# Özel Yazı Tipleri (Custom Typography)
var font_main: Font
var font_bold: Font
var font_mono: Font
var font_title: Font

# Sağ Taraf (Hedef Kilit Kartı - Geriye dönük uyumluluk)
var target_card: PanelContainer
var lbl_target_name: Label
var lbl_target_type: Label
var lbl_target_dist: Label
var lbl_target_travel: Label
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
var stellar_system_summary_cache: Dictionary = {}
var _detail_layout_signature: String = ""

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
var show_lod_debug_card: bool = false

func toggle_lod_debug_card() -> bool:
	show_lod_debug_card = !show_lod_debug_card
	if is_instance_valid(lod_debug_card):
		lod_debug_card.visible = show_lod_debug_card
	return show_lod_debug_card

# Alt Orta (Eylem Tuşları Rozet Barı)
var action_bar: HBoxContainer

# Ekran Ortası (Nişangah ve Kask Siperliği)
var crosshair_center: Control
var visor_overlay: Control

# İniş ve Kalkış Sinematik Geçiş Katmanı (Atmospheric Entry & Launch Transition)
var transition_overlay: ColorRect
var lbl_trans_title: Label
var lbl_trans_sub: Label
var bar_trans: ProgressBar
var is_transitioning: bool = false
var transition_timer: float = 0.0
var transition_duration: float = 1.4
var transition_midpoint_called: bool = false
var transition_midpoint_callback: Callable
var transition_finish_callback: Callable
var transition_mode: String = ""
var transition_body_name: String = ""

# Contextual approach/landing telemetry. This replaces technical loading feedback
# with information that belongs to the ship's navigation computer.
var approach_card: PanelContainer
var lbl_approach_kicker: Label
var lbl_approach_name: Label
var lbl_approach_altitude: Label
var lbl_approach_speed: Label
var lbl_approach_vertical: Label
var lbl_approach_angle: Label
var lbl_approach_status: Label
var bar_approach_scan: ProgressBar
var _approach_target_alpha := 0.0
var _approach_alpha := 0.0

func _init_fonts() -> void:
	if ResourceLoader.exists("res://assets/fonts/FiraSans-Medium.ttf"):
		font_main = load("res://assets/fonts/FiraSans-Medium.ttf")
	if ResourceLoader.exists("res://assets/fonts/FiraSans-Bold.ttf"):
		font_bold = load("res://assets/fonts/FiraSans-Bold.ttf")
	if ResourceLoader.exists("res://assets/fonts/FiraSansCondensed-Bold.ttf"):
		font_title = load("res://assets/fonts/FiraSansCondensed-Bold.ttf")
	if ResourceLoader.exists("res://assets/fonts/DejaVuSansMono-Bold.ttf"):
		font_mono = load("res://assets/fonts/DejaVuSansMono-Bold.ttf")

	if font_main == null:
		var sf = SystemFont.new()
		sf.font_names = PackedStringArray(["Fira Sans", "Segoe UI", "Ubuntu", "sans-serif"])
		font_main = sf
	if font_bold == null:
		var sf = SystemFont.new()
		sf.font_names = PackedStringArray(["Fira Sans", "Segoe UI", "Ubuntu", "sans-serif"])
		sf.font_weight = 700
		font_bold = sf
	if font_title == null:
		var sf = SystemFont.new()
		sf.font_names = PackedStringArray(["Fira Sans Condensed", "Impact", "Arial Black", "sans-serif"])
		sf.font_weight = 800
		font_title = sf
	if font_mono == null:
		var sf = SystemFont.new()
		sf.font_names = PackedStringArray(["DejaVu Sans Mono", "Consolas", "Courier New", "monospace"])
		sf.font_weight = 600
		font_mono = sf

func _ready():
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_init_fonts()
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
	
	lbl_flight_mode = _create_label("SERBEST UÇUŞ", Color(0.1, 1.0, 0.6), 15, true)
	top_hbox.add_child(lbl_flight_mode)
	
	var sep2 = VSeparator.new()
	sep2.custom_minimum_size = Vector2(30, 0)
	top_hbox.add_child(sep2)
	
	lbl_clock_time = _create_label("ZAMAN: 00:00:00 [1.0x]", Color(1.0, 0.8, 0.2), 15, true)
	top_hbox.add_child(lbl_clock_time)

	# 3. Sağ Alt Panel: Serbest Uçuş Telemetrisi
	flight_card = PanelContainer.new()
	flight_card.custom_minimum_size = Vector2(330, 180)
	flight_card.anchor_left = 0.77
	flight_card.anchor_top = 0.74
	flight_card.anchor_right = 0.98
	flight_card.anchor_bottom = 0.96
	flight_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flight_card.add_theme_stylebox_override("panel", _create_glass_box(Color(0.8, 0.35, 1.0, 0.5), 10, Color(0.04, 0.03, 0.12, 0.85)))
	add_child(flight_card)
	
	var flight_vbox = VBoxContainer.new()
	flight_vbox.add_theme_constant_override("separation", 6)
	flight_card.add_child(flight_vbox)
	
	lbl_flight_title = _create_label("SERBEST UÇUŞ TELEMETRİSİ", Color(0.85, 0.5, 1.0), 14, true)
	flight_vbox.add_child(lbl_flight_title)
	
	var speed_box = HBoxContainer.new()
	var lbl_sp_tag = _create_label("MEVCUT HIZ:", Color(0.85, 0.85, 0.9), 12, false)
	speed_box.add_child(lbl_sp_tag)
	lbl_flight_speed_val = _create_label("0.0 m/s", Color(0.3, 1.0, 0.6), 18, true)
	speed_box.add_child(lbl_flight_speed_val)
	flight_vbox.add_child(speed_box)
	
	var throttle_val_box = HBoxContainer.new()
	var lbl_th_tag = _create_label("HIZ LİMİTİ:", Color(0.7, 0.75, 0.85), 11, false)
	throttle_val_box.add_child(lbl_th_tag)
	lbl_speed_limit_val = _create_label("343.0 m/s", Color(0.3, 0.85, 1.0), 13, false)
	throttle_val_box.add_child(lbl_speed_limit_val)
	flight_vbox.add_child(throttle_val_box)
	
	# Hız Seviyesi Barı
	var throttle_box = HBoxContainer.new()
	var lbl_th = _create_label("HIZ", Color(0.85, 0.7, 1.0), 12, false)
	lbl_th.custom_minimum_size = Vector2(60, 0)
	throttle_box.add_child(lbl_th)
	bar_throttle = _create_progress_bar(Color(0.7, 0.3, 1.0), Color(0.15, 0.05, 0.25))
	bar_throttle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar_throttle.value = 40.0
	throttle_box.add_child(bar_throttle)
	flight_vbox.add_child(throttle_box)
	
	lbl_camera_state = _create_label("KAMERA: FREE-FLY", Color(0.1, 0.95, 0.6), 12, false)
	flight_vbox.add_child(lbl_camera_state)
	
	lbl_control_state = _create_label("DURUM: MANUEL KONTROL", Color(0.0, 0.9, 1.0), 12, false)
	flight_vbox.add_child(lbl_control_state)

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
	
	lbl_target_dist = _create_label("MESAFE: 1.45 AU", Color(1.0, 0.9, 0.3), 16, true, true)
	target_vbox.add_child(lbl_target_dist)

	lbl_target_travel = _create_label("KAT ETME: Durağan", Color(0.2, 1.0, 0.5), 13, true, true)
	target_vbox.add_child(lbl_target_travel)

	lbl_target_details = _create_label("YARIÇAP: 6.371 km | YERÇEKİMİ: 1.00 g", Color(0.7, 0.8, 0.9), 11, false)
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

	# 9. Bağlamsal gezegen yaklaşma ve iniş telemetrisi
	_build_approach_card()

	# 10. Sağ Üst Gezegen LOD & Chunk Telemetri Kartı
	_build_lod_debug_card()

func _build_approach_card() -> void:
	approach_card = PanelContainer.new()
	approach_card.anchor_left = 0.025
	approach_card.anchor_right = 0.275
	approach_card.anchor_top = 0.085
	approach_card.anchor_bottom = 0.325
	approach_card.custom_minimum_size = Vector2(420, 0)
	approach_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	approach_card.add_theme_stylebox_override("panel", _create_glass_box(
		Color(0.16, 0.78, 0.90, 0.72), 7, Color(0.012, 0.032, 0.060, 0.91)))
	approach_card.visible = false
	approach_card.modulate.a = 0.0
	add_child(approach_card)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 4)
	approach_card.add_child(content)

	lbl_approach_kicker = _create_label("YAKLAŞMA TELEMETRİSİ", Color(0.32, 0.82, 0.92), 10, true, false, true)
	lbl_approach_kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	content.add_child(lbl_approach_kicker)

	lbl_approach_name = _create_label("GEZEGEN", Color(0.91, 0.97, 1.0), 20, true, false, true)
	lbl_approach_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	content.add_child(lbl_approach_name)
	content.add_child(_create_h_separator(Color(0.12, 0.65, 0.78, 0.38)))

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 2)
	content.add_child(grid)
	for heading in ["İRTİFA", "YÜZEY HIZI", "DİKEY HIZ", "İNİŞ EĞİMİ"]:
		var tag := _create_label(heading, Color(0.50, 0.63, 0.72), 10, true)
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		tag.custom_minimum_size.x = 112
		grid.add_child(tag)
		var value := _create_label("—", Color(0.88, 0.96, 1.0), 13, true, true)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(value)
		match heading:
			"İRTİFA": lbl_approach_altitude = value
			"YÜZEY HIZI": lbl_approach_speed = value
			"DİKEY HIZ": lbl_approach_vertical = value
			"İNİŞ EĞİMİ": lbl_approach_angle = value

	lbl_approach_status = _create_label("YÜZEY HARİTALANIYOR", Color(1.0, 0.70, 0.24), 11, true)
	lbl_approach_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	content.add_child(lbl_approach_status)
	bar_approach_scan = _create_progress_bar(Color(0.12, 0.82, 0.88), Color(0.025, 0.10, 0.15))
	bar_approach_scan.value = 0.0
	content.add_child(bar_approach_scan)

func _build_lod_debug_card() -> void:
	lod_debug_card = PanelContainer.new()
	lod_debug_card.anchor_left = 0.74
	lod_debug_card.anchor_right = 0.98
	lod_debug_card.anchor_top = 0.08
	lod_debug_card.anchor_bottom = 0.30
	lod_debug_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lod_debug_card.add_theme_stylebox_override("panel", _create_glass_box(Color(0.0, 0.85, 0.5, 0.5), 6, Color(0.01, 0.04, 0.08, 0.82)))
	lod_debug_card.visible = false
	add_child(lod_debug_card)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	lod_debug_card.add_child(vbox)
	
	lbl_lod_title = _create_label("GEZEGEN LOD [V: Renk | B: Sınır | Z: Tel]", Color(0.1, 0.95, 0.6), 12, true)
	vbox.add_child(lbl_lod_title)
	
	lbl_lod_grid_status = _create_label("DURUM: BEKLENİYOR", Color(0.8, 0.9, 1.0), 11, false)
	vbox.add_child(lbl_lod_grid_status)
	
	lbl_lod_breakdown = _create_label("LOD Dağılımı: Hesaplanıyor...", Color(0.9, 0.95, 1.0), 11, false)
	vbox.add_child(lbl_lod_breakdown)
	
	lbl_lod_perf = _create_label("Kuyruk: 0 | Süre: 0.0 ms", Color(0.7, 0.8, 0.9), 10, false)
	vbox.add_child(lbl_lod_perf)
	
	lbl_lod_color_mode = _create_label("Debug: [B] Sınır KAPALI | [V] Renk KAPALI", Color(0.9, 0.7, 0.2), 11, true)
	vbox.add_child(lbl_lod_color_mode)

	# 7. İniş ve Kalkış Sinematik Geçiş Katmanı (Atmospheric Entry & Launch Overlay)
	transition_overlay = ColorRect.new()
	transition_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	transition_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	transition_overlay.color = Color(0.01, 0.02, 0.04, 0.0)
	transition_overlay.visible = false
	add_child(transition_overlay)
	
	var trans_center_vb = VBoxContainer.new()
	trans_center_vb.set_anchors_preset(Control.PRESET_CENTER)
	trans_center_vb.custom_minimum_size = Vector2(700, 120)
	trans_center_vb.alignment = BoxContainer.ALIGNMENT_CENTER
	trans_center_vb.add_theme_constant_override("separation", 12)
	transition_overlay.add_child(trans_center_vb)
	
	lbl_trans_title = Label.new()
	lbl_trans_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_trans_title.add_theme_font_size_override("font_size", 22)
	lbl_trans_title.add_theme_color_override("font_color", Color(0.1, 0.95, 1.0))
	trans_center_vb.add_child(lbl_trans_title)
	
	lbl_trans_sub = Label.new()
	lbl_trans_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_trans_sub.add_theme_font_size_override("font_size", 13)
	lbl_trans_sub.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0))
	trans_center_vb.add_child(lbl_trans_sub)
	
	bar_trans = ProgressBar.new()
	bar_trans.custom_minimum_size = Vector2(380, 4)
	bar_trans.show_percentage = false
	bar_trans.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var bar_trans_bg = StyleBoxFlat.new()
	bar_trans_bg.bg_color = Color(0.1, 0.15, 0.25, 0.5)
	bar_trans_bg.set_corner_radius_all(2)
	bar_trans.add_theme_stylebox_override("background", bar_trans_bg)
	var bar_trans_fg = StyleBoxFlat.new()
	bar_trans_fg.bg_color = Color(0.0, 0.9, 1.0, 0.95)
	bar_trans_fg.set_corner_radius_all(2)
	bar_trans.add_theme_stylebox_override("fill", bar_trans_fg)
	trans_center_vb.add_child(bar_trans)

# ─────────────────────────────────────────────────────────────────────────────
# GÖRSEL VE ÇİZİM DESTEĞİ (KASK VİZÖRÜ & MERKEZ NİŞANGAH)
# ─────────────────────────────────────────────────────────────────────────────
func _draw_visor_and_reticle() -> void:
	var center = visor_overlay.size * 0.5
	var glow = Color(0.0, 0.9, 1.0, 0.25)
	
	# One precise aim marker, readable against both stars and a dark space.
	var ink := Color(0.005, 0.015, 0.025, 0.85)
	var aim := Color(0.78, 0.96, 1.0, 0.95)
	visor_overlay.draw_circle(center, 3.0, ink)
	visor_overlay.draw_circle(center, 1.5, aim)
	for direction in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		visor_overlay.draw_line(center + direction * 7.0, center + direction * 14.0, ink, 3.5, true)
		visor_overlay.draw_line(center + direction * 7.0, center + direction * 14.0, aim, 1.5, true)

	# Fütüristik Uçuş Braketleri (Tactical Flight Brackets [  ])
	var b_dist = 28.0
	var b_len = 8.0
	var b_col = Color(0.0, 0.85, 1.0, 0.45)
	# Sol braket [
	visor_overlay.draw_line(center + Vector2(-b_dist, -b_len), center + Vector2(-b_dist, b_len), b_col, 1.5)
	visor_overlay.draw_line(center + Vector2(-b_dist, -b_len), center + Vector2(-b_dist + 5.0, -b_len), b_col, 1.5)
	visor_overlay.draw_line(center + Vector2(-b_dist, b_len), center + Vector2(-b_dist + 5.0, b_len), b_col, 1.5)
	# Sağ braket ]
	visor_overlay.draw_line(center + Vector2(b_dist, -b_len), center + Vector2(b_dist, b_len), b_col, 1.5)
	visor_overlay.draw_line(center + Vector2(b_dist, -b_len), center + Vector2(b_dist - 5.0, -b_len), b_col, 1.5)
	visor_overlay.draw_line(center + Vector2(b_dist, b_len), center + Vector2(b_dist - 5.0, b_len), b_col, 1.5)
	
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
# SİNEMATİK İNİŞ VE KALKIŞ GEÇİŞ SİSTEMİ (ATMOSPHERIC ENTRY & LAUNCH FADE)
# ─────────────────────────────────────────────────────────────────────────────
func trigger_landing_transition(body_name: String, on_midpoint: Callable, on_finish: Callable = Callable()) -> void:
	is_transitioning = true
	transition_timer = 0.0
	transition_duration = 1.4
	transition_midpoint_called = false
	transition_midpoint_callback = on_midpoint
	transition_finish_callback = on_finish
	transition_mode = "LANDING"
	transition_body_name = body_name
	
	if is_instance_valid(transition_overlay):
		transition_overlay.visible = true
		transition_overlay.color = Color(0.01, 0.02, 0.04, 0.0)
	if is_instance_valid(lbl_trans_title):
		lbl_trans_title.text = "ATMOSFERİK ALÇALMA VE İNİŞ PROTOKOLÜ"
		lbl_trans_title.add_theme_color_override("font_color", Color(0.1, 0.95, 1.0))
		lbl_trans_title.modulate.a = 0.0
	if is_instance_valid(lbl_trans_sub):
		lbl_trans_sub.text = "%s // YÜZEY İNİŞ DÜZENİ AKTİF" % body_name.to_upper()
		lbl_trans_sub.modulate.a = 0.0
	if is_instance_valid(bar_trans):
		bar_trans.value = 0.0
		bar_trans.modulate.a = 0.0

func trigger_launch_transition(body_name: String, on_midpoint: Callable, on_finish: Callable = Callable()) -> void:
	is_transitioning = true
	transition_timer = 0.0
	transition_duration = 1.4
	transition_midpoint_called = false
	transition_midpoint_callback = on_midpoint
	transition_finish_callback = on_finish
	transition_mode = "LAUNCH"
	transition_body_name = body_name
	
	if is_instance_valid(transition_overlay):
		transition_overlay.visible = true
		transition_overlay.color = Color(0.01, 0.02, 0.04, 0.0)
	if is_instance_valid(lbl_trans_title):
		lbl_trans_title.text = "YÖRÜNGEYE ÇIKIŞ PROTOKOLÜ"
		lbl_trans_title.add_theme_color_override("font_color", Color(1.0, 0.65, 0.1))
		lbl_trans_title.modulate.a = 0.0
	if is_instance_valid(lbl_trans_sub):
		lbl_trans_sub.text = "%s YÜZEYİNDEN AYRILINIYOR // UZAY SEYRİ" % body_name.to_upper()
		lbl_trans_sub.modulate.a = 0.0
	if is_instance_valid(bar_trans):
		bar_trans.value = 0.0
		bar_trans.modulate.a = 0.0

func _process(delta: float) -> void:
	_approach_alpha = move_toward(_approach_alpha, _approach_target_alpha, delta * 5.5)
	if is_instance_valid(approach_card):
		approach_card.visible = _approach_alpha > 0.01
		approach_card.modulate.a = _approach_alpha

	if not is_transitioning:
		return
		
	transition_timer += delta
	var half_dur = transition_duration * 0.45
	var fade_in_phase = transition_timer <= half_dur
	
	var overlay_alpha: float = 0.0
	var text_alpha: float = 0.0
	
	if fade_in_phase:
		var t = clampf(transition_timer / maxf(half_dur, 0.01), 0.0, 1.0)
		overlay_alpha = t * t
		text_alpha = clampf((t - 0.2) / 0.8, 0.0, 1.0)
		if is_instance_valid(bar_trans):
			bar_trans.value = t * 50.0
	else:
		if not transition_midpoint_called:
			transition_midpoint_called = true
			if transition_midpoint_callback.is_valid():
				transition_midpoint_callback.call()
				
		var out_dur = maxf(transition_duration - half_dur, 0.01)
		var out_t = clampf((transition_timer - half_dur) / out_dur, 0.0, 1.0)
		overlay_alpha = 1.0 - (out_t * out_t)
		text_alpha = 1.0 - out_t
		if is_instance_valid(bar_trans):
			bar_trans.value = 50.0 + out_t * 50.0
			
	if is_instance_valid(transition_overlay):
		transition_overlay.color = Color(0.01, 0.02, 0.04, overlay_alpha)
	if is_instance_valid(lbl_trans_title):
		lbl_trans_title.modulate.a = text_alpha
	if is_instance_valid(lbl_trans_sub):
		lbl_trans_sub.modulate.a = text_alpha
	if is_instance_valid(bar_trans):
		bar_trans.modulate.a = text_alpha
		
	if transition_timer >= transition_duration:
		is_transitioning = false
		if is_instance_valid(transition_overlay):
			transition_overlay.visible = false
		if transition_finish_callback.is_valid():
			transition_finish_callback.call()

# ─────────────────────────────────────────────────────────────────────────────
# GERÇEK ZAMANLI TELEMETRİ GÜNCELLEME (HER KARE ÇAĞRILIR)
# ─────────────────────────────────────────────────────────────────────────────
func update_hud(main_node: Node3D) -> void:
	if not is_instance_valid(main_node):
		return
		
	visible = main_node.is_hud_visible or is_transitioning
	if not visible:
		return
		
	visor_overlay.queue_redraw()
	
	var cam = main_node.camera
	var current_speed = cam.get("current_speed") if (cam != null and cam.get("current_speed") != null) else 0.0
	
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
	else:
		lbl_flight_mode.text = "SERBEST UÇUŞ"
		lbl_flight_mode.modulate = Color(0.1, 0.95, 0.6)

	flight_card.visible = true

	# 3. Serbest Uçuş Telemetrisi
	var actual_speed: float = float(main_node.flight_speed_mps) if main_node.get("flight_speed_mps") != null else 0.0
	lbl_flight_speed_val.text = _format_speed(actual_speed)
	var fly_speed_label = main_node.get("fly_speed_label")
	lbl_speed_limit_val.text = str(fly_speed_label) if fly_speed_label != null and str(fly_speed_label) != "" else _format_speed(current_speed)
	lbl_flight_speed_val.modulate = Color(0.3, 1.0, 0.6) if actual_speed > 0.5 else Color(0.7, 0.75, 0.8)
	
	var is_warp = (main_node.get("is_interstellar_autopilot") == true) or (main_node.get("is_hyper_autopilot") == true)
	if true:
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
			
		lbl_camera_state.text = "KAMERA: FREE-FLY"
		lbl_control_state.text = "DURUM: %s" % ("OTOPİLOT" if main_node.is_autopilot_active or main_node.is_interstellar_autopilot else "MANUEL KONTROL")

	# 4. Sol Üst Mini Sistem Haritası ve Starfield Kartı Yönetimi
	mini_map_main_ref = main_node
	if main_node.is_system_map_active:
		mini_system_map.visible = true
		mini_system_map.queue_redraw()
		flight_card.visible = false
		starfield_card.anchor_top = 0.29
		starfield_card.anchor_bottom = 0.94
	else:
		mini_system_map.visible = false
		starfield_card.anchor_top = 0.08
		starfield_card.anchor_bottom = 0.72

	# Starfield Bilgi Kartını Güncelle
	_update_starfield_card(main_node)
	_update_approach_card(main_node)

	# 5. Gezegen LOD & Chunk Telemetri Kartı
	_update_lod_debug_card(main_node)

	# 6. Dinamik Eylemler ve Tuş Rozetleri
	_update_action_badges(main_node)

func _get_approach_body(main_node: Node3D):
	if main_node.get("is_landed") == true and main_node.get("landed_body") != null:
		return main_node.landed_body
	if main_node.get("is_landing_autopilot") == true and main_node.get("autopilot_target_body") != null:
		return main_node.autopilot_target_body
	var selected = null
	if main_node.get("focus_target_body") != null:
		selected = main_node.focus_target_body
	elif main_node.get("followed_body") != null:
		selected = main_node.followed_body
	elif main_node.get("current_target_index") != null:
		var index: int = main_node.current_target_index
		if index >= 0 and index < main_node.universe.size():
			selected = main_node.universe[index]
	if selected != null and selected.type in ["PLANET", "MOON"]:
		var selected_dist: float = selected.real_position.length()
		if selected_dist <= selected.real_radius * 8.0:
			return selected
	var nearest = null
	var nearest_ratio := INF
	for body in main_node.active_system_bodies:
		if body.type not in ["PLANET", "MOON"]:
			continue
		var ratio: float = body.real_position.length() / maxf(body.real_radius, 1.0)
		if ratio <= 8.0 and ratio < nearest_ratio:
			nearest = body
			nearest_ratio = ratio
	return nearest

func _update_approach_card(main_node: Node3D) -> void:
	var body = _get_approach_body(main_node)
	var map_active: bool = main_node.get("is_system_map_active") == true
	_approach_target_alpha = 0.0 if body == null or map_active else 1.0
	if body == null or map_active:
		return

	var center_distance: float = body.real_position.length()
	var surface_direction: Vector3 = (-body.real_position).normalized() if center_distance > 1.0 else Vector3.UP
	var terrain_height := 0.0
	if body.noise_albedo != null and body.noise_albedo.noise != null:
		terrain_height = PlanetSphere.sample_terrain_height_static(
			body.noise_albedo.noise, surface_direction, body.real_radius) * body.real_radius
	var altitude: float = maxf(center_distance - (body.real_radius + terrain_height), 0.0)
	var rel_radius: float = center_distance / maxf(body.real_radius, 1.0)
	var flight_speed: float = absf(float(main_node.get("flight_speed_mps")))
	var radial_speed := 0.0
	if main_node.get("is_landed") == true:
		altitude = maxf(float(main_node.get("landed_vertical_offset")), 0.0)
		radial_speed = float(main_node.get("landed_vertical_velocity"))
	elif main_node.get("is_landing_autopilot") == true:
		radial_speed = -flight_speed
	elif main_node.get("player_velocity") is Vector3 and center_distance > 1.0:
		radial_speed = (main_node.player_velocity as Vector3).dot((-body.real_position).normalized()) * -1.0

	var up: Vector3 = (-body.real_position).normalized() if center_distance > 1.0 else Vector3.UP
	var camera_up: Vector3 = main_node.camera.global_basis.y.normalized() if main_node.camera != null else up
	var angle: float = rad_to_deg(acos(clampf(camera_up.dot(up), -1.0, 1.0)))
	var scan_progress := clampf((8.0 - rel_radius) / 6.8, 0.0, 1.0) * 100.0
	var sphere_mgr = main_node.get("sphere_chunk_manager")
	if is_instance_valid(sphere_mgr) and sphere_mgr.has_method("is_active") and sphere_mgr.is_active():
		scan_progress = maxf(scan_progress, 35.0)
		if sphere_mgr.has_method("get_lod_stats"):
			var chunk_count: int = sphere_mgr.get_lod_stats().get("total_chunks", 0)
			scan_progress = maxf(scan_progress, clampf(float(chunk_count) / 96.0, 0.0, 1.0) * 100.0)
	if main_node.get("is_landed") == true:
		scan_progress = 100.0

	var is_landing: bool = main_node.get("is_landing_autopilot") == true
	lbl_approach_kicker.text = "İNİŞ PROTOKOLÜ" if is_landing else ("YÜZEY OPERASYONU" if main_node.is_landed else "YAKLAŞMA TELEMETRİSİ")
	lbl_approach_name.text = str(body.name).to_upper()
	lbl_approach_altitude.text = _format_compact_distance(altitude)
	lbl_approach_speed.text = _format_speed(flight_speed)
	lbl_approach_vertical.text = "%+.1f m/s" % radial_speed
	lbl_approach_angle.text = "%.1f°" % angle
	bar_approach_scan.value = scan_progress

	if main_node.is_landed:
		lbl_approach_status.text = "YÜZEY TEMASI  //  KAMERA SABİT"
		lbl_approach_status.modulate = Color(0.30, 0.94, 0.60)
	elif is_landing and scan_progress >= 92.0:
		lbl_approach_status.text = "İNİŞ KORİDORU HAZIR  //  ALÇALMA AKTİF"
		lbl_approach_status.modulate = Color(0.30, 0.94, 0.60)
	elif scan_progress >= 70.0:
		lbl_approach_status.text = "YÜZEY ÇÖZÜMLENİYOR  //  %02d" % int(scan_progress)
		lbl_approach_status.modulate = Color(0.26, 0.84, 0.94)
	else:
		lbl_approach_status.text = "ARAZİ TARAMASI  //  %02d" % int(scan_progress)
		lbl_approach_status.modulate = Color(1.0, 0.70, 0.24)

	# Detailed survey and approach telemetry compete for the same attention.
	# Keep the compact flight context while a planet fills the view.
	if is_instance_valid(starfield_card):
		starfield_card.visible = false

func _format_compact_distance(meters: float) -> String:
	if meters >= 1000000.0:
		return "%.2f Mm" % (meters / 1000000.0)
	if meters >= 1000.0:
		return "%.2f km" % (meters / 1000.0)
	return "%.1f m" % meters

func _update_lod_debug_card(main_node: Node3D) -> void:
	if not is_instance_valid(lod_debug_card):
		return
	if not show_lod_debug_card:
		lod_debug_card.visible = false
		return
		
	var lod_mgr = main_node.get("landed_lod_manager")
	var sphere_mgr = main_node.get("sphere_chunk_manager")
	var show_borders = main_node.get("show_chunk_borders") == true
	var color_mode = main_node.get("debug_lod_colors_active") == true

	if is_instance_valid(lod_mgr) and lod_mgr.has_method("get_lod_stats") and lod_mgr.is_active() and lod_mgr.visible:
		lod_debug_card.visible = true
		lbl_lod_title.text = "GEZEGEN CHUNK SİSTEMİ (YÜZEY + KÜRE)"
		var stats: Dictionary = lod_mgr.get_lod_stats()
		var total_chunks = stats.get("total_chunks", 0)
		var grid_pos: Vector2i = stats.get("grid_pos", Vector2i.ZERO)
		var counts: Dictionary = stats.get("lod_counts", {})
		var q_size = stats.get("build_queue_size", 0)
		var b_usec = stats.get("last_build_usec", 0)
		
		var sphere_total = 0
		if is_instance_valid(sphere_mgr) and sphere_mgr.has_method("get_lod_stats"):
			sphere_total = sphere_mgr.get_lod_stats().get("total_chunks", 24)
		
		lbl_lod_grid_status.text = "Yüzey: %d Parça | Küre: %d Parça (360°)" % [total_chunks, sphere_total]
		lbl_lod_breakdown.text = "L0(40x40): %d [Yeşil]  L1(24x24): %d [Mavi]\nL2(14x14): %d [Sarı]   L3(6x6): %d [Turuncu]\nL4(2x2): %d [Kırmızı]" % [
			counts.get(0, 0), counts.get(1, 0), counts.get(2, 0), counts.get(3, 0), counts.get(4, 0)
		]
		lbl_lod_perf.text = "Kuyruk: %d | Son Üretim: %.2f ms" % [q_size, b_usec / 1000.0]
		lbl_lod_color_mode.text = "[B] Sınır: %s | [V] Renk: %s | [Z] Tel: %s" % [
			"AÇIK" if show_borders else "KAPALI",
			"AÇIK" if color_mode else "KAPALI",
			"AÇIK" if main_node.get("is_wireframe_mode") else "KAPALI"
		]
		lbl_lod_color_mode.modulate = Color(0.2, 1.0, 0.4) if (color_mode or show_borders) else Color(0.8, 0.8, 0.8)
	elif is_instance_valid(sphere_mgr) and sphere_mgr.is_active():
		lod_debug_card.visible = true
		lbl_lod_title.text = "KÜRESEL GEZEGEN CHUNK LOD (TÜM GEZEGEN AKTİF)"
		if sphere_mgr.has_method("get_lod_stats"):
			var stats: Dictionary = sphere_mgr.get_lod_stats()
			var total = stats.get("total_chunks", 24)
			var counts: Dictionary = stats.get("lod_counts", {})
			lbl_lod_grid_status.text = "Tüm Gezegen Aktif: %d Parça | Küresel 360°" % total
			lbl_lod_breakdown.text = "L0:%d  L1:%d  L2:%d  L3:%d\nL4:%d  L5:%d  L6:%d  L7:%d\nL8:%d  L9:%d  L10:%d  L11:%d" % [
				counts.get(0, 0), counts.get(1, 0), counts.get(2, 0), counts.get(3, 0),
				counts.get(4, 0), counts.get(5, 0), counts.get(6, 0), counts.get(7, 0),
				counts.get(8, 0), counts.get(9, 0), counts.get(10, 0), counts.get(11, 0)
			]
			lbl_lod_perf.text = "Gezegen Yarıçapı: %.1f km" % (stats.get("body_radius", 6000000.0) / 1000.0)
		else:
			lbl_lod_grid_status.text = "Tüm Gezegen Aktif: 24 Kök Parça | 5 Seviye Quadtree"
			lbl_lod_breakdown.text = "L0: Kırmızı | L1: Turuncu | L2: Sarı\nL3: Mavi    | L4: Yeşil   | L5: Turkuaz"
			lbl_lod_perf.text = "Küre Durumu: Aktif Küresel Çap"
		lbl_lod_color_mode.text = "[B] Sınır: %s | [V] Renk: %s | [Z] Tel: %s" % [
			"AÇIK" if show_borders else "KAPALI",
			"AÇIK" if color_mode else "KAPALI",
			"AÇIK" if main_node.get("is_wireframe_mode") else "KAPALI"
		]
		lbl_lod_color_mode.modulate = Color(0.2, 1.0, 0.4) if (color_mode or show_borders) else Color(0.8, 0.8, 0.8)
	else:
		lod_debug_card.visible = false

# ─────────────────────────────────────────────────────────────────────────────
# EYLEM TUŞ ROZETLERİ GÜNCELLEMESİ
# ─────────────────────────────────────────────────────────────────────────────
func _update_action_badges(main_node: Node3D) -> void:
	for child in action_bar.get_children():
		child.queue_free()
		
	if main_node.is_system_map_active:
		_add_badge("[M] HARİTADAN ÇIK", Color(1.0, 0.6, 0.1))
		_add_badge("[SOL TIK] SEÇ", Color(0.0, 0.9, 1.0))
		_add_badge("[P] ZAMANI DURDUR", Color(0.8, 0.8, 0.9))
		_add_badge("[TAB] HUD", Color(0.6, 0.6, 0.7))
		return
		
	# Serbest uçuş
	if main_node.is_interstellar_autopilot or main_node.is_autopilot_active:
		if main_node.get("is_landing_autopilot") == true:
			_add_badge("İNİŞ ALÇALMASI AKTİF", Color(0.1, 1.0, 0.5))
			_add_badge("[WASD] İPTAL ET", Color(1.0, 0.4, 0.3))
		else:
			_add_badge("[G] HİPER HIZLANDIR", Color(1.0, 0.2, 0.9))
			_add_badge("[WASD] İPTAL ET", Color(1.0, 0.4, 0.3))
	elif main_node.get("is_landed") == true:
		_add_badge("[WASD] YÜZEY UÇUŞU", Color(0.0, 0.85, 1.0))
		_add_badge("[SPACE/CTRL] DİKEY HIZ", Color(0.2, 0.9, 0.9))
		_add_badge("[G / L] YÖRÜNGEYE KALKIŞ", Color(0.1, 1.0, 0.5))
	else:
		var near_planet_for_landing: bool = false
		if main_node.get("active_system_bodies") != null:
			for b in main_node.active_system_bodies:
				if b.type != "STAR" and b.real_position.length() <= b.real_radius * 3.5:
					near_planet_for_landing = true
					break
		if near_planet_for_landing:
			_add_badge("[G / L] GEZEGENE İNİŞ YAP", Color(0.1, 1.0, 0.5))
		elif main_node.current_target_index >= 0 or main_node.targeted_star_data != null:
			_add_badge("[G] OTOPİLOT", Color(0.1, 1.0, 0.5))
			_add_badge("[C] HEDEF KAPAT", Color(1.0, 0.45, 0.35))
		_add_badge("[WASD] UÇUŞ  [Q] ROLL", Color(0.0, 0.85, 1.0))
		_add_badge("[M] HARİTA", Color(1.0, 0.65, 0.1))
	if show_lod_debug_card:
		_add_badge("[B/V/Z] LOD DEBUG", Color(0.2, 1.0, 0.4))

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
func _create_glass_box(border_color: Color, corner_rad: int, bg_color: Color = Color(0.015, 0.03, 0.06, 0.88), accent_top: bool = true) -> StyleBoxFlat:
	var box = StyleBoxFlat.new()
	box.bg_color = bg_color
	box.border_color = border_color
	box.border_width_left = 1
	box.border_width_top = 2 if accent_top else 1
	box.border_width_right = 1
	box.border_width_bottom = 1
	box.corner_radius_top_left = corner_rad
	box.corner_radius_top_right = corner_rad
	box.corner_radius_bottom_left = corner_rad
	box.corner_radius_bottom_right = corner_rad
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 10
	box.content_margin_bottom = 10
	box.shadow_color = Color(border_color.r, border_color.g, border_color.b, 0.20)
	box.shadow_size = 5
	box.shadow_offset = Vector2(0, 1)
	return box

func _create_progress_bar(fill_color: Color, bg_color: Color) -> ProgressBar:
	var pb = ProgressBar.new()
	pb.custom_minimum_size = Vector2(0, 7)
	pb.show_percentage = false
	pb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	var bg_box = StyleBoxFlat.new()
	bg_box.bg_color = bg_color
	bg_box.corner_radius_top_left = 2
	bg_box.corner_radius_top_right = 2
	bg_box.corner_radius_bottom_left = 2
	bg_box.corner_radius_bottom_right = 2
	pb.add_theme_stylebox_override("background", bg_box)
	
	var fill_box = StyleBoxFlat.new()
	fill_box.bg_color = fill_color
	fill_box.corner_radius_top_left = 2
	fill_box.corner_radius_top_right = 2
	fill_box.corner_radius_bottom_left = 2
	fill_box.corner_radius_bottom_right = 2
	fill_box.shadow_color = Color(fill_color.r, fill_color.g, fill_color.b, 0.45)
	fill_box.shadow_size = 3
	pb.add_theme_stylebox_override("fill", fill_box)
	return pb

func _create_label(text: String, color: Color, font_size: int, bold: bool = false, is_mono: bool = false, is_title: bool = false) -> Label:
	var lbl = Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_font_size_override("font_size", font_size)
	if is_title and font_title != null:
		lbl.add_theme_font_override("font", font_title)
	elif is_mono and font_mono != null:
		lbl.add_theme_font_override("font", font_mono)
	elif bold and font_bold != null:
		lbl.add_theme_font_override("font", font_bold)
	elif font_main != null:
		lbl.add_theme_font_override("font", font_main)
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

# ─────────────────────────────────────────────────────────────────────────────
# ASTRONOMİK IŞIK MESAFESİ VE SEYAHAT SÜRESİ HESAPLAYICI
# (Saniye, Dakika, Saat, Gün, Hafta, Ay, Yıl, Asır)
# ─────────────────────────────────────────────────────────────────────────────
static func format_time_duration(t: float) -> String:
	if not is_finite(t):
		return "Hesaplanamadı"
	if t <= 0.0:
		return "0 Saniye"
		
	const SEC_IN_BILLION_YEARS: float = 31557600000000000.0 # 1 Milyar Yıl
	const SEC_IN_MILLION_YEARS: float = 31557600000000.0    # 1 Milyon Yıl
	const SEC_IN_CENTURY: float       = 3155760000.0        # 1 Asır = 100 Julian Işık Yılı
	const SEC_IN_YEAR: float          = 31557600.0          # 1 Yıl = 365.25 Gün
	const SEC_IN_MONTH: float         = 2629800.0           # 1 Ay = 30.4375 Gün (365.25 / 12)
	const SEC_IN_WEEK: float          = 604800.0            # 1 Hafta = 7 Gün
	const SEC_IN_DAY: float           = 86400.0             # 1 Gün = 24 Saat
	const SEC_IN_HOUR: float          = 3600.0              # 1 Saat = 60 Dakika
	const SEC_IN_MINUTE: float        = 60.0                # 1 Dakika = 60 Saniye
	
	# 0. Kozmolojik Süreler (Milyar / Milyon Yıl) - Negatif Sayı Taşmalarını Önler
	if t >= SEC_IN_BILLION_YEARS:
		return "> 1 Milyar Yıl"
	elif t >= SEC_IN_MILLION_YEARS:
		return "%.1f Milyon Yıl" % (t / SEC_IN_MILLION_YEARS)
	# 1. Asır (Centuries) - Derin galaktik mesafe (100+ Işık Yılı)
	elif t >= SEC_IN_CENTURY:
		var centuries = int(clampf(t / SEC_IN_CENTURY, 0.0, 999999.0))
		var rem_years = int(clampf(fmod(t, SEC_IN_CENTURY) / SEC_IN_YEAR, 0.0, 99.0))
		if rem_years > 0:
			return "%d Asır %d Yıl" % [centuries, rem_years]
		return "%d Asır" % centuries
		
	# 2. Yıl (Years) - Yıldızlararası mesafe (1 - 100 Işık Yılı)
	elif t >= SEC_IN_YEAR:
		var years = int(t / SEC_IN_YEAR)
		var rem_months = int(fmod(t, SEC_IN_YEAR) / SEC_IN_MONTH)
		if rem_months > 0:
			return "%d Yıl %d Ay" % [years, rem_months]
		return "%d Yıl" % years
		
	# 3. Ay (Months) - Dış Oort bulutu (~5000 - 63000 AU)
	elif t >= SEC_IN_MONTH:
		var months = int(t / SEC_IN_MONTH)
		var rem_weeks = int(fmod(t, SEC_IN_MONTH) / SEC_IN_WEEK)
		if rem_weeks > 0:
			return "%d Ay %d Hafta" % [months, rem_weeks]
		return "%d Ay" % months
		
	# 4. Hafta (Weeks) - İç Oort bulutu (~1200 - 5000 AU)
	elif t >= SEC_IN_WEEK:
		var weeks = int(t / SEC_IN_WEEK)
		var rem_days = int(fmod(t, SEC_IN_WEEK) / SEC_IN_DAY)
		if rem_days > 0:
			return "%d Hafta %d Gün" % [weeks, rem_days]
		return "%d Hafta" % weeks
		
	# 5. Gün (Days) - Kuiper kuşağı ve heliopoz (~170 - 1200 AU)
	elif t >= SEC_IN_DAY:
		var days = int(t / SEC_IN_DAY)
		var rem_hours = int(fmod(t, SEC_IN_DAY) / SEC_IN_HOUR)
		if rem_hours > 0:
			return "%d Gün %d Saat" % [days, rem_hours]
		return "%d Gün" % days
		
	# 6. Saat (Hours) - Dış Güneş Sistemi (~1.2 - 70 AU: Jüpiter, Satürn, Neptün, Plüton)
	elif t >= SEC_IN_HOUR:
		var hours = int(t / SEC_IN_HOUR)
		var rem_minutes = int(fmod(t, SEC_IN_HOUR) / SEC_IN_MINUTE)
		if rem_minutes > 0:
			return "%d Saat %d Dakika" % [hours, rem_minutes]
		return "%d Saat" % hours
		
	# 7. Dakika (Minutes) - İç Güneş Sistemi (~0.1 - 2.5 AU: Güneş, Merkür, Dünya, Mars)
	elif t >= SEC_IN_MINUTE:
		var minutes = int(t / SEC_IN_MINUTE)
		var rem_seconds = int(fmod(t, SEC_IN_MINUTE))
		if rem_seconds > 0:
			return "%d Dakika %d Saniye" % [minutes, rem_seconds]
		return "%d Dakika" % minutes
		
	# 8. Saniye (Seconds) - Gezegen-Uydu mesafesi (~300.000 - 18.000.000 km)
	elif t >= 1.0:
		return "%.1f Saniye" % t
		
	elif t >= 0.001:
		return "%.3f Saniye" % t
		
	else:
		return "< 0.001 Saniye"

static func format_light_time(meters: float) -> String:
	if not is_finite(meters):
		return "Hesaplanamadı"
	if meters <= 0.0:
		return "0 Saniye"
	return format_time_duration(meters / LIGHT_SPEED)

static func format_travel_time(distance_meters: float, speed_mps: float) -> String:
	if not is_finite(distance_meters) or not is_finite(speed_mps):
		return "Hesaplanamadı"
	if speed_mps <= 0.5:
		return "Durağan (Hız Yok)"
	if distance_meters <= 1.0:
		return "Ulaşıldı (0 Sn)"
	var t: float = distance_meters / speed_mps
	return format_time_duration(t)

func _format_light_time(meters: float) -> String:
	return format_light_time(meters)

func _format_travel_time(distance_meters: float, speed_mps: float) -> String:
	return format_travel_time(distance_meters, speed_mps)

func _format_metric_size(meters: float) -> String:
	if meters >= 1000000000.0:
		return "%.2f Milyon km" % (meters / 1000000000.0)
	elif meters >= 1000000.0:
		return "%.1f Bin km" % (meters / 1000000.0)
	elif meters >= 1000.0:
		return "%.1f km" % (meters / 1000.0)
	else:
		return "%.0f m" % meters

static func _format_distance(meters: float) -> String:
	if not is_finite(meters):
		return "Hesaplanamadı"
	if meters <= 0.0:
		return "0 m"
		
	var lt = format_light_time(meters)
	
	if meters >= 100.0 * LIGHT_YEAR:
		return "%s (%.1f ly)" % [lt, meters / LIGHT_YEAR]
	elif meters >= 0.01 * LIGHT_YEAR:
		return "%s (%.2f ly)" % [lt, meters / LIGHT_YEAR]
	elif meters >= 0.1 * ONE_AU:
		return "%s (%.2f AU)" % [lt, meters / ONE_AU]
	elif meters >= 1000000000.0:
		return "%s (%.1f Milyon km)" % [lt, meters / 1000000000.0]
	elif meters >= 1000000.0:
		return "%s (%.0f Bin km)" % [lt, meters / 1000000.0]
	elif meters >= 1000.0:
		return "%.2f km (< 0.01 Sn)" % (meters / 1000.0)
	else:
		return "%.0f m" % meters

# ─────────────────────────────────────────────────────────────────────────────
# STARFIELD TARZI DETAYLI CİSİM KARTI VE MİNYATÜR SİSTEM HARİTASI
# ─────────────────────────────────────────────────────────────────────────────
func _build_starfield_card() -> void:
	starfield_card = PanelContainer.new()
	starfield_card.custom_minimum_size = Vector2(330, 0)
	starfield_card.anchor_left = 0.02
	starfield_card.anchor_top = 0.08
	starfield_card.anchor_right = 0.23
	starfield_card.anchor_bottom = 0.72
	starfield_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	starfield_card.add_theme_stylebox_override("panel", _create_glass_box(Color(0.2, 0.6, 0.9, 0.7), 10, Color(0.02, 0.04, 0.08, 0.93)))
	starfield_card.visible = false
	add_child(starfield_card)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 8)
	starfield_card.add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	margin.add_child(vbox)

	# 1. Sistem Adı
	lbl_sf_system = _create_label("ALPHA CENTAURI SİSTEMİ", Color(0.35, 0.75, 1.0), 11, false)
	lbl_sf_system.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	vbox.add_child(lbl_sf_system)

	# 2. Cisim Adı (Büyük Başlık)
	lbl_sf_name = _create_label("JEMISON", Color(0.95, 0.98, 1.0), 18, true)
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
		["GEZEGENLER", "—"],
		["YAŞANABİLİR", "—"],
		["YARIÇAP", "6.371 km"],
		["MESAFE", "1.00 AU"],
		["KAT ETME SÜRESİ", "Durağan"],
		["IŞIK SÜRESİ", "8 Dakika 19 Saniye"]
	]
	for r in rows:
		var row_box = HBoxContainer.new()
		var lbl_key = _create_label(r[0], Color(0.55, 0.65, 0.75), 11, false)
		lbl_key.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		lbl_key.custom_minimum_size = Vector2(95, 0)
		row_box.add_child(lbl_key)

		var lbl_val = _create_label(r[1], Color(0.9, 0.95, 1.0), 11, true, true)
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
	var h_c = _create_badge_label("[C] KAPAT", Color(1.0, 0.45, 0.35))
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
	var max_orbit_m := 1.0
	for planet in planets:
		max_orbit_m = maxf(max_orbit_m, planet.orbit_radius)
	if main_node.active_star != null:
		var zones := HabitabilityModel.get_orbital_zones(main_node.active_star.luminosity)
		var hot_r := minf(max_r, zones.habitable_inner_m / max_orbit_m * max_r)
		var habitable_r := minf(max_r, zones.habitable_outer_m / max_orbit_m * max_r)
		mini_system_map.draw_arc(center, hot_r, 0, TAU, 64, Color(1.0, 0.28, 0.12, 0.38), 4.0)
		mini_system_map.draw_arc(center, habitable_r, 0, TAU, 64, Color(0.2, 1.0, 0.45, 0.42), 4.0)
		mini_system_map.draw_arc(center, max_r, 0, TAU, 64, Color(0.25, 0.55, 1.0, 0.22), 3.0)
		for belt in main_node.active_star.asteroid_belts:
			var belt_r := minf(max_r, float(belt.radius_m) / max_orbit_m * max_r)
			for segment in range(18):
				var start_angle := TAU * float(segment) / 18.0
				mini_system_map.draw_arc(center, belt_r, start_angle, start_angle + 0.16, 3, Color(0.72, 0.62, 0.45, 0.5), 2.0)

	var selected_body: CelestialBody = null
	if main_node.current_target_index >= 0 and main_node.current_target_index < main_node.universe.size():
		selected_body = main_node.universe[main_node.current_target_index]

	for i in range(count):
		var p = planets[i]
		var orb_r = maxf(8.0, p.orbit_radius / max_orbit_m * max_r)
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
	target_card.visible = false # Çakışmayı önlemek için sağdaki mükerrer hedef kartı tamamen gizlenir

	# Eğer yüzeydeysek ve seçili hedef iniş yaptığımız cismin kendisiyse, kartı gizle
	if main_node.is_landed and main_node.landed_body != null:
		if main_node.current_target_index >= 0 and main_node.current_target_index < main_node.universe.size():
			if main_node.universe[main_node.current_target_index] == main_node.landed_body:
				starfield_card.visible = false
				return

	if main_node.get("selected_extragalactic_galaxy") != null:
		var info = _get_galaxy_survey_info(main_node.selected_extragalactic_galaxy, main_node)
		_apply_survey_info_to_card(info)
		starfield_card.visible = true
	elif main_node.targeted_star_data != null:
		var info = _get_stardata_survey_info(main_node.targeted_star_data, main_node)
		_apply_survey_info_to_card(info)
		starfield_card.visible = true
	elif main_node.current_target_index >= 0 and main_node.current_target_index < main_node.universe.size():
		var b = main_node.universe[main_node.current_target_index]
		var info = _get_body_survey_info(b, main_node)
		_apply_survey_info_to_card(info)
		starfield_card.visible = true
	else:
		starfield_card.visible = false

func _apply_survey_info_to_card(info: Dictionary) -> void:
	lbl_sf_system.text = info["system"]
	lbl_sf_name.text = info["name"]
	lbl_sf_survey_val.text = "%%%d" % info["survey_pct"]
	bar_sf_survey.value = float(info["survey_pct"])
	var detail_rows: Array = info.get("detail_rows", [
		{"label": "TİP", "value": info.get("type", "Bilinmiyor")},
		{"label": "YARIÇAP", "value": info.get("radius", "—")},
		{"label": "MESAFE", "value": info.get("dist", "—")},
		{"label": "IŞIK SÜRESİ", "value": info.get("light_time", "—")},
	])
	var visible_fraction := clampf(float(info.get("survey_pct", 100)) / 100.0, 0.15, 1.0)
	var visible_row_count := maxi(2, int(ceil(detail_rows.size() * visible_fraction)))
	detail_rows = detail_rows.slice(0, visible_row_count)
	_set_starfield_detail_rows(detail_rows)

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
	if sf_row_labels.has("GEZEGENLER"):
		sf_row_labels["GEZEGENLER"].text = info.get("planets", "—")
	if sf_row_labels.has("YAŞANABİLİR"):
		sf_row_labels["YAŞANABİLİR"].text = info.get("habitable", "—")
	if sf_row_labels.has("YARIÇAP"):
		sf_row_labels["YARIÇAP"].text = info["radius"]
	if sf_row_labels.has("MESAFE"):
		sf_row_labels["MESAFE"].text = info["dist"]
	if sf_row_labels.has("KAT ETME SÜRESİ"):
		var tt = info.get("travel_time", "Durağan")
		sf_row_labels["KAT ETME SÜRESİ"].text = tt
		if tt.begins_with("Durağan"):
			sf_row_labels["KAT ETME SÜRESİ"].modulate = Color(0.65, 0.7, 0.8)
		else:
			sf_row_labels["KAT ETME SÜRESİ"].modulate = Color(0.2, 1.0, 0.5)
	if sf_row_labels.has("IŞIK SÜRESİ"):
		sf_row_labels["IŞIK SÜRESİ"].text = info.get("light_time", "0 Saniye")

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
	var survey_pct = int(main_node.survey_controller.get_progress(body)) if main_node.enable_survey_system else 100
	info["survey_pct"] = survey_pct

	var dist_m = body.real_position.length()
	var current_spd = 0.0
	if main_node.camera != null and main_node.camera.get("current_speed") != null:
		current_spd = float(main_node.camera.get("current_speed"))
	if main_node.get("flight_speed_mps") != null and float(main_node.flight_speed_mps) > 0.1:
		current_spd = float(main_node.flight_speed_mps)
	info["dist"] = _format_distance(dist_m)
	info["light_time"] = _format_light_time(dist_m)
	info["travel_time"] = format_travel_time(dist_m, current_spd)
	info["radius"] = _format_metric_size(body.real_radius)

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
		var summary := {"planets": 0, "moons": 0, "companions": 0, "belts": body.asteroid_belts.size(), "in_zone": 0, "habitable": 0}
		for system_body in main_node.universe:
			if system_body.system_id != body.unique_id:
				continue
			if system_body.type == "PLANET":
				summary.planets += 1
				if system_body.climate_zone == "HABITABLE": summary.in_zone += 1
				if system_body.is_habitable: summary.habitable += 1
			elif system_body.type == "MOON":
				summary.moons += 1
			elif system_body.type == "STAR" and system_body != body:
				summary.companions += 1
		info["detail_rows"] = CelestialDetailFormatter.for_star(body, info, summary)
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
	if body.surface_temperature_k > 0.0:
		var zone_name: String = str({"HOT": "Sıcak Kuşak", "HABITABLE": "Yaşanabilir Kuşak", "COLD": "Soğuk Kuşak"}.get(body.climate_zone, body.climate_zone))
		info["type"] = "%s • %s%s" % [info["type"], zone_name, " • YAŞANABİLİR" if body.is_habitable else ""]
		info["gravity"] = "%.2f G" % body.surface_gravity_g
		info["temp"] = "%.0f K (%.0f °C)" % [body.surface_temperature_k, body.surface_temperature_k - 273.15]
		info["atmo"] = "%.2f bar" % body.atmosphere_pressure_bar if body.has_atmosphere else "Yok (Vakum)"
		info["water"] = "%%%d yüzey suyu" % int(body.water_fraction * 100.0)
	info["detail_rows"] = CelestialDetailFormatter.for_body(body, info)
	return info

func _get_stardata_survey_info(star_data, main_node: Node3D) -> Dictionary:
	var info = {}
	info["name"] = star_data.name.to_upper()
	info["system"] = "GALAKTİK SEKTÖR [%d,%d,%d]" % [star_data.sector_coord.x, star_data.sector_coord.y, star_data.sector_coord.z]
	if star_data.get("constellation_id") != null and star_data.constellation_id != "":
		info["system"] = "%s • %s TAKIMYILDIZI" % [info["system"], star_data.constellation_name.to_upper()]
	if star_data.get("group_id") != null and star_data.group_id != "":
		var group_kind := "AÇIK KÜME" if star_data.group_type == "OPEN_CLUSTER" else "YILDIZ BİRLİĞİ"
		info["system"] = "%s • %s (%s)" % [info["system"], star_data.group_name.to_upper(), group_kind]
	info["survey_pct"] = int(main_node.survey_controller.get_progress(star_data)) if main_node.enable_survey_system else 100
	var gal_pos_m: Vector3 = main_node.get_player_galactic_position()
	# Metre koordinatları galaksi ölçeğinde ~1e20 değerine ulaşır. Bunların
	# Vector3.length() karesi tek duyarlıklı bileşenlerde INF üretebilir.
	# Önce ışık yılına küçült, güvenli uzunluğu hesapla, sonra metreye dön.
	var player_pos_ly := gal_pos_m / LIGHT_YEAR
	var star_pos_ly := Vector3(
		star_data.stellar_x / LIGHT_YEAR,
		star_data.stellar_y / LIGHT_YEAR,
		star_data.stellar_z / LIGHT_YEAR
	)
	var dist: float = (star_pos_ly - player_pos_ly).length() * LIGHT_YEAR
	var current_spd = 0.0
	if main_node.camera != null and main_node.camera.get("current_speed") != null:
		current_spd = float(main_node.camera.get("current_speed"))
	if main_node.get("flight_speed_mps") != null and float(main_node.flight_speed_mps) > 0.1:
		current_spd = float(main_node.flight_speed_mps)
	info["dist"] = _format_distance(dist)
	info["light_time"] = _format_light_time(dist)
	info["travel_time"] = format_travel_time(dist, current_spd)
	info["radius"] = _format_metric_size(star_data.radius)
	if star_data.spectral_type.contains("SMBH") or star_data.spectral_type.contains("Kara Delik"):
		info["type"] = "Süper Kütleli Kara Delik (SMBH)"
		info["gravity"] = "Aşırı Tekillik (Olay Ufku)"
		info["temp"] = "Hawking (~0 K) | Disk: >10⁷ K"
		info["atmo"] = "Relativistik Yığılma Diski & Plazma Jeti"
		info["mag"] = "Devasa Relativistik Manyetosfer"
		info["water"] = "Yok (Spagettileşme)"
		info["biome"] = "Schwarzschild Olay Ufku & Ergoküre"
		info["resources"] = [
			{"sym": "DM", "name": "Karanlık Madde", "col": Color(0.7, 0.3, 1.0)},
			{"sym": "γ", "name": "Gama Işını", "col": Color(0.2, 1.0, 0.8)},
			{"sym": "Pl", "name": "Aşırı Sıcak Plazma", "col": Color(1.0, 0.45, 0.2)},
			{"sym": "G-W", "name": "Yerçekim Dalgası", "col": Color(0.9, 0.2, 0.5)}
		]
	else:
		var system_summary := _get_stellar_system_summary(star_data)
		info["type"] = "Galaktik Yıldız (%s)" % star_data.spectral_type
		info["gravity"] = "25.0+ G (Kütle Çekim)"
		info["temp"] = "Spektral Sınıf: %s" % star_data.spectral_type
		info["atmo"] = "Yıldız Koronası"
		info["mag"] = "Devasa Galaktik Manyetosfer"
		info["water"] = "Yok (Nükleer Füzyon)"
		info["biome"] = "Plazma Çekirdeği & Korona"
		info["planets"] = "%d gezegen • %d uydu" % [system_summary.planets, system_summary.moons]
		if system_summary.habitable > 0:
			info["habitable"] = "VAR • %d yaşanabilir (%d kuşakta)" % [system_summary.habitable, system_summary.in_zone]
		else:
			info["habitable"] = "YOK • %d gezegen kuşakta" % system_summary.in_zone
		info["resources"] = [
			{"sym": "H", "name": "Hidrojen", "col": Color(0.35, 0.75, 1.0)},
			{"sym": "He-3", "name": "Helyum-3", "col": Color(1.0, 0.85, 0.2)},
			{"sym": "Pl", "name": "Plazma", "col": Color(1.0, 0.4, 0.8)},
			{"sym": "Fe", "name": "Ağır Element", "col": Color(0.9, 0.5, 0.2)}
		]
		info["detail_rows"] = CelestialDetailFormatter.for_star(star_data, info, system_summary)
	return info


func _set_starfield_detail_rows(rows: Array) -> void:
	var labels: Array[String] = []
	for row in rows:
		labels.append(str(row.label))
	var signature := "|".join(labels)
	if signature == _detail_layout_signature:
		for row in rows:
			if sf_row_labels.has(str(row.label)):
				sf_row_labels[str(row.label)].text = str(row.value)
		return
	_detail_layout_signature = signature
	for child in sf_table_vbox.get_children():
		child.queue_free()
	sf_row_labels.clear()
	for row in rows:
		var row_box := HBoxContainer.new()
		var label := _create_label(str(row.label), Color(0.55, 0.65, 0.75), 10, false)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		label.custom_minimum_size = Vector2(102, 0)
		row_box.add_child(label)
		var value := _create_label(str(row.value), Color(0.9, 0.95, 1.0), 11, true, true)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row_box.add_child(value)
		sf_table_vbox.add_child(row_box)
		sf_row_labels[str(row.label)] = value


func _get_stellar_system_summary(star_data) -> Dictionary:
	if stellar_system_summary_cache.has(star_data.unique_id):
		return stellar_system_summary_cache[star_data.unique_id]
	var star: CelestialBody = SystemGenerator.instantiate_star_from_data(null, star_data)
	var bodies: Array[CelestialBody] = SystemGenerator.generate_planets_for_star(null, star, false)
	var summary := {"planets": 0, "moons": 0, "companions": 0, "belts": 0, "in_zone": 0, "habitable": 0}
	for body in bodies:
		if body.type == "PLANET":
			summary.planets += 1
			if body.climate_zone == "HABITABLE":
				summary.in_zone += 1
			if body.is_habitable:
				summary.habitable += 1
		elif body.type == "MOON":
			summary.moons += 1
		elif body.type == "STAR":
			summary.companions += 1
	summary.belts = star.asteroid_belts.size()
	stellar_system_summary_cache[star_data.unique_id] = summary
	return summary

func _get_galaxy_survey_info(galaxy, main_node: Node3D) -> Dictionary:
	var info = {}
	var name_str = galaxy.custom_name if galaxy.custom_name != "" else galaxy.designation
	info["name"] = name_str.to_upper()
	info["system"] = "KOZMOLOJİK DERİN UZAY"
	info["survey_pct"] = 100
	
	var cam = main_node.camera
	var cam_pos_ly: Vector3 = (cam.global_position + main_node.galaxy_origin_ly) if (cam != null and main_node.get("galaxy_origin_ly") != null) else Vector3.ZERO
	var dist_ly: float = (galaxy.position_ly - cam_pos_ly).length()
	var dist_m: float = dist_ly * LIGHT_YEAR
	
	var current_spd = 0.0
	if cam != null and cam.get("current_speed") != null:
		current_spd = float(cam.get("current_speed"))
	if main_node.get("flight_speed_mps") != null and float(main_node.flight_speed_mps) > 0.1:
		current_spd = float(main_node.flight_speed_mps)
		
	info["dist"] = _format_distance(dist_m)
	info["light_time"] = _format_light_time(dist_m)
	info["travel_time"] = format_travel_time(dist_m, current_spd)
	info["radius"] = "Çap: %.0f Bin LY" % (galaxy.diameter_ly / 1000.0)
	info["type"] = galaxy.hubble_type
	info["gravity"] = "SMBH: %.1f Milyon M☉" % (galaxy.black_hole_mass_solar / 1.0e6)
	info["temp"] = "Yaş: %.1f Milyar Yıl" % galaxy.age_gyr
	info["atmo"] = "SFR: %.1f M☉/Yıl (Gaz)" % galaxy.star_formation_rate
	info["mag"] = "Galaktik Manyetik Alan"
	info["water"] = "Yıldız Sayısı: ~%.0f Milyar" % (galaxy.total_real_stars / 1.0e9)
	info["biome"] = "Kütle: %.2f × 10¹¹ M☉" % (galaxy.total_mass_solar / 1.0e11)
	info["resources"] = [
		{"sym": "DM", "name": "Karanlık Madde Halosu", "col": Color(0.75, 0.35, 1.0)},
		{"sym": "H-I", "name": "Nötr Hidrojen Gazı", "col": Color(0.3, 0.8, 1.0)},
		{"sym": "Pop-I", "name": "Genç Yıldız Kümeleri", "col": Color(0.2, 0.95, 0.6)},
		{"sym": "Pop-II", "name": "Yaşlı Küresel Kümeler", "col": Color(1.0, 0.85, 0.3)}
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
