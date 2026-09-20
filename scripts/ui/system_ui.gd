class_name SystemUI
extends RefCounted

const LIGHT_SPEED: float = 299792458.0
const LIGHT_YEAR: float = 9460730472580800.0

static func update_ui(main_node: Node3D, closest_name: String, closest_dist: float) -> void:
	if !main_node.is_hud_visible:
		return
		
	var current_speed = main_node.camera.current_speed
	var speed_in_c = current_speed / LIGHT_SPEED
	
	# Hız Göstergesi Yuvarlaması
	var speed_text = ""
	const ONE_AU: float = 149597870700.0
	if current_speed >= 100.0 * LIGHT_YEAR:
		speed_text = "%d Işık Yılı/s" % int(round(current_speed / LIGHT_YEAR))
	elif current_speed >= 1.0 * LIGHT_YEAR:
		speed_text = "%.1f Işık Yılı/s" % (current_speed / LIGHT_YEAR)
	elif current_speed >= 0.001 * LIGHT_YEAR:
		speed_text = "%.4f Işık Yılı/s" % (current_speed / LIGHT_YEAR)
	elif current_speed >= 0.1 * ONE_AU:
		speed_text = "%.2f AU/s" % (current_speed / ONE_AU)
	elif current_speed >= LIGHT_SPEED:
		speed_text = "%.2f C (Işık Hızı)" % speed_in_c
	elif current_speed >= 1000.0:
		speed_text = "%.2f km/s" % (current_speed / 1000.0)
	else:
		speed_text = "%.1f m/s" % current_speed
		
	# Zaman Akışı Göstergesi
	var time_speed_str = "DURDURULDU" if main_node.is_time_paused else "%.2fx" % main_node.time_scale
	var total_seconds = int(main_node.simulation_time)
	var hours = total_seconds / 3600
	var minutes = (total_seconds % 3600) / 60
	var seconds = total_seconds % 60
	var time_str = "%02d:%02d:%02d" % [hours, minutes, seconds]
	
	# Otopilot / İniş Durumu
	var autopilot_status = "BOŞTA"
	if main_node.is_landed and main_node.landed_body != null:
		autopilot_status = "İNDİ (%s)" % main_node.landed_body.name
	elif main_node.get("is_interstellar_autopilot") == true and main_node.get("targeted_star_data") != null:
		if main_node.get("is_interstellar_hyper_boost") == true:
			autopilot_status = "[color=#ff00ff]⚡ HİPER SEYİR (%s)[/color]" % main_node.targeted_star_data.name
		else:
			autopilot_status = "WARP SEYRİ (%s) [G: Hızlandır]" % main_node.targeted_star_data.name
	elif main_node.is_autopilot_active and main_node.autopilot_target_body != null:
		if main_node.is_landing_autopilot:
			autopilot_status = "İNİŞ YAPILIYOR (%s)" % main_node.autopilot_target_body.name
		elif main_node.get("is_hyper_autopilot") == true:
			autopilot_status = "[color=#ff00ff]⚡ HİPER OTOPİLOT (%s)[/color]" % main_node.autopilot_target_body.name
		else:
			autopilot_status = "OTOPİLOT SEYRİ (%s) [G: Hızlandır]" % main_node.autopilot_target_body.name
	elif main_node.get("is_focusing_target") == true:
		if main_node.get("focus_target_star") != null:
			autopilot_status = "KİLİTLİ / ODAKTA (%s)" % main_node.focus_target_star.name
		elif main_node.get("focus_target_body") != null:
			autopilot_status = "KİLİTLİ / ODAKTA (%s)" % main_node.focus_target_body.name
		else:
			autopilot_status = "HEDEFE ODAKLI"
	elif main_node.followed_body != null:
		autopilot_status = "YÖRÜNGE TAKİBİ (%s)" % main_node.followed_body.name
		
	# Aktif Yıldız Sistemini Bul
	var active_system_name = "Bilinmeyen"
	var closest_star_dist: float = 0.0
	if main_node.active_star != null:
		active_system_name = main_node.active_star.name
		closest_star_dist = main_node.active_star.real_position.length()
		
	var total_planets = main_node.total_planets_count
	var loaded_planets = 0
	var total_moons = main_node.total_moons_count
	var loaded_moons = 0
	
	for b in main_node.active_system_bodies:
		if b.type == "PLANET":
			if is_instance_valid(b.visual_mesh) and b.visual_mesh.visible:
				loaded_planets += 1
		elif b.type == "MOON":
			if is_instance_valid(b.visual_mesh) and b.visual_mesh.visible:
				loaded_moons += 1

	# Başlık ve Panel Moduna Göre Seçim
	var telemetry_text = ""
	if main_node.is_system_map_active:
		telemetry_text = "[center][b][color=#ff9f1c]🛰️ SİSTEM HARİTASI[/color][/b][/center]\n"
	elif main_node.get("is_eva_active") == true:
		if main_node.is_landed:
			telemetry_text = "[center][b][color=#00ff66]🌍 GEZEGEN YÜZEYİ (EVA KEŞFİ)[/color][/b][/center]\n"
		else:
			telemetry_text = "[center][b][color=#00e5ff]🧑‍🚀 UZAY YÜRÜYÜŞÜ (SIFIR-G EVA)[/color][/b][/center]\n"
	elif main_node.is_landed:
		telemetry_text = "[center][b][color=#00ff66]🌍 İNİŞ YAPILDI (GEMİ İÇİ)[/color][/b][/center]\n"
	else:
		telemetry_text = "[center][b][color=#00e5ff]🚀 TELEMETRİ PANELİ[/color][/b][/center]\n"
		
	telemetry_text += "[color=#3f4f60]━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━[/color]\n"
	
	if main_node.get("is_eva_active") == true:
		var o2_val = int(main_node.get("astronaut_oxygen") if main_node.get("astronaut_oxygen") != null else 100)
		var fuel_val = int(main_node.get("astronaut_fuel") if main_node.get("astronaut_fuel") != null else 100)
		
		var o2_color = "#00ff66" if o2_val > 50 else ("#ffaa00" if o2_val > 25 else "#ff3333")
		var fuel_color = "#00e5ff" if fuel_val > 30 else "#ff9f1c"
		
		var jet_status = "RÖLANTİ"
		if main_node.get("is_jetpack_boosting"):
			jet_status = "[color=#ff3366]İLERİ BOOST[/color]"
		elif main_node.get("is_jetpack_active"):
			jet_status = "[color=#00e5ff]RCS İTİCİ[/color]"
		else:
			jet_status = "[color=#8d99ae]HAZIR[/color]"
			
		var lamp_status = "AÇIK"
		if main_node.camera != null and main_node.camera.get("headlamp") != null:
			lamp_status = "AÇIK" if main_node.camera.headlamp.visible else "KAPALI"
			
		telemetry_text += "[b][color=#8a9baf]🧑‍🚀 ASTRONOT YAŞAM DESTEĞİ & EVA:[/color][/b]\n"
		telemetry_text += " • Oksijen (O2): [color=%s]%d%%[/color] | Yakıt: [color=%s]%d%%[/color]\n" % [o2_color, o2_val, fuel_color, fuel_val]
		telemetry_text += " • İtici: %s | Fener: [color=#ffff00]%s[/color] ([L])\n" % [jet_status, lamp_status]
		telemetry_text += " • Korvet Mesafesi: [color=#ffcc00]%.1f m[/color]\n" % main_node.get("dist_to_ship_eva")
		if main_node.get("is_near_ship_airlock") == true:
			telemetry_text += " • Eylem: [color=#00ff66][b][E] GEMİYE GİR (HAVA KİLİDİ)[/b][/color]\n"
		else:
			telemetry_text += " • Durum: [color=#00e5ff]Dış Görevde (Hava kilidine yaklaş)[/color]\n"
	elif main_node.is_landed and main_node.landed_body != null:
		var body = main_node.landed_body
		var gravity = (body.real_radius / 6371000.0) * 1.0
		if body.type == "MOON":
			gravity = (body.real_radius / 1737000.0) * 0.16
			
		telemetry_text += "[b][color=#8a9baf]İNDİĞİMİZ CİSİM VERİLERİ:[/color][/b]\n"
		telemetry_text += " • Cisim: [color=#e2eafc]%s[/color] (%s)\n" % [body.name, body.type]
		telemetry_text += " • Yerçekimi: [color=#ff9f1c]%.2f g[/color]\n" % gravity
		
		var sc = main_node.spacecraft if main_node.get("spacecraft") != null else (main_node.camera.spacecraft if main_node.camera != null else null)
		if sc != null and sc.current_view_mode == 1:
			if sc.get("is_seated_in_cockpit"):
				telemetry_text += " • Konum: [color=#00e5ff]Kokpit Pilot Koltuğu[/color]\n"
				telemetry_text += " • Eylemler: [color=#00ff66][E] Kalkış Yap | [C] Odak[/color]\n"
			else:
				if sc.get("near_airlock"):
					var act = "Kapağı Kapat" if sc.is_airlock_open else "Rampayı İndir (Dışarı Çık)"
					telemetry_text += " • Konum: [color=#00ff66]Hava Kilidi Odası[/color]\n"
					telemetry_text += " • Eylemler: [color=#00ff66][E] %s[/color]\n" % act
				elif sc.get("near_pilot_seat"):
					telemetry_text += " • Konum: [color=#00e5ff]Pilot Koltuğu Yanı[/color]\n"
					telemetry_text += " • Eylemler: [color=#00ff66][E] Koltuğa Otur[/color]\n"
				else:
					telemetry_text += " • Konum: [color=#00e5ff]Kabin İçi Koridor[/color]\n"
	else:
		telemetry_text += "[b][color=#8a9baf]UÇUŞ VERİLERİ (FLIGHT DATA):[/color][/b]\n"
		telemetry_text += " • Yıldız: [color=#00ff66]%s[/color] (%s)\n" % [active_system_name, format_space_distance(closest_star_dist)]
		telemetry_text += " • Hız: [color=#ff9f1c]%s[/color]\n" % speed_text
		telemetry_text += " • Durum: [color=#00e5ff]%s[/color]\n" % autopilot_status
		
		var cam_mode_str = "3. ŞAHIS (DIŞ TAKİP)"
		var sc = main_node.spacecraft if main_node.get("spacecraft") != null else (main_node.camera.spacecraft if main_node.camera != null else null)
		if sc != null:
			match sc.current_view_mode:
				0: cam_mode_str = "3. ŞAHIS (DIŞ TAKİP)"
				1:
					if sc.get("is_seated_in_cockpit"):
						cam_mode_str = "KOKPİT UÇUŞ ([E] Koltuktan Kalk)"
					else:
						if sc.get("near_airlock"):
							cam_mode_str = "HAVA KİLİDİ ([E] %s)" % ("Kapağı Kapat" if sc.is_airlock_open else "Hava Kilidini Aç")
						elif sc.get("near_pilot_seat"):
							cam_mode_str = "KABİN İÇİ ([E] Koltuğa Otur)"
						else:
							cam_mode_str = "KABİN İÇİ YÜRÜYÜŞ"
				2: cam_mode_str = "SERBEST BAKIŞ"
		telemetry_text += " • Görünüm: [color=#ffaa00]%s[/color] ([F] Değiştir)\n" % cam_mode_str
		telemetry_text += " • Zaman: [color=#00ff66]%s[/color] (Hız: %s)\n" % [time_str, time_speed_str]
	
	# Evren ve Canlı Yıldız Popülasyonu
	telemetry_text += "[color=#3f4f60]━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━[/color]\n"
	telemetry_text += "[b][color=#8a9baf]🌌 EVREN VE YILDIZ POPÜLASYONU:[/color][/b]\n"
	
	var near_stars = 0
	var near_max = 1000
	if main_node.star_visual_pool != null:
		near_stars = main_node.star_visual_pool.active_count
		near_max = main_node.star_visual_pool.pool_capacity
		
	var ram_stars = 0
	var loaded_sectors_count = 0
	var cur_sec_str = "(0, 0, 0)"
	if main_node.sector_manager != null:
		ram_stars = main_node.sector_manager.total_generated_stars
		loaded_sectors_count = main_node.sector_manager.loaded_sectors.size()
		var cs = main_node.sector_manager.current_sector
		cur_sec_str = "(%d, %d, %d)" % [cs.x, cs.y, cs.z]
		
	var mid_stars = 20000 if main_node.get("enable_mid_field") else 0
	var deep_stars = 50000 if main_node.get("enable_deep_field") else 0
	var total_visible_stars = near_stars + mid_stars + deep_stars
	
	telemetry_text += " • Toplam Görünür Yıldız: [color=#00ff66]%s[/color]\n" % format_number_with_dots(total_visible_stars)
	telemetry_text += "   ├ Yakın Yıldızlar (0-150 LY): [color=#00e5ff]%d[/color] / %d (GPU MultiMesh)\n" % [near_stars, near_max]
	telemetry_text += "   ├ Orta Alan (150-2.5k LY): [color=#ffcc00]%s[/color] (GPU Point)\n" % format_number_with_dots(mid_stars)
	telemetry_text += "   └ Derin Alan (2.5k-25k LY): [color=#ff9f1c]%s[/color] (GPU Point)\n" % format_number_with_dots(deep_stars)
	telemetry_text += " • RAM Sektör Havuzu: [color=#00e5ff]%s[/color] Yıldız (%d Sektör)\n" % [format_number_with_dots(ram_stars), loaded_sectors_count]
	telemetry_text += " • Aktif Sektör: [color=#ffcc00]%s[/color]\n" % cur_sec_str

	# Aktif Sistem Gök Cisimleri
	telemetry_text += "[color=#3f4f60]━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━[/color]\n"
	telemetry_text += "[b][color=#8a9baf]🪐 AKTİF SİSTEM GÖK CİSİMLERİ:[/color][/b]\n"
	telemetry_text += " • Sistem Yıldızı: [color=#00e5ff]%s[/color]\n" % active_system_name
	telemetry_text += " • Gezegenler: [color=#00ff66]%d[/color] / %d Yüklü\n" % [loaded_planets, total_planets]
	telemetry_text += " • Uydular: [color=#00ff66]%d[/color] / %d Yüklü\n" % [loaded_moons, total_moons]
	
	telemetry_text += "[color=#3f4f60]━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━[/color]\n"
	
	telemetry_text += "[b][color=#8a9baf]HEDEF TELEMETRİSİ (TARGET):[/color][/b]\n"
	if main_node.get("targeted_star_data") != null:
		var s_data = main_node.targeted_star_data
		var gal_pos = main_node.get_player_galactic_position()
		var star_pos = Vector3(s_data.stellar_x, s_data.stellar_y, s_data.stellar_z)
		var dist_to_star = gal_pos.distance_to(star_pos)
		
		telemetry_text += " • İsim: [color=#ffcc00]%s[/color] (Galaktik Yıldız)\n" % s_data.name
		telemetry_text += " • Spektral Tip: [color=#00e5ff]%s[/color]\n" % s_data.spectral_type
		telemetry_text += " • Galaktik Mesafe: [color=#ffcc00]%s[/color]\n" % format_space_distance(dist_to_star)
		telemetry_text += " • Işık Seyahati: [color=#00e5ff]%s[/color]\n" % format_light_time(dist_to_star)
		telemetry_text += " • Kat Etme Süresi (ETA): [color=#00ff66]%s[/color]\n" % format_travel_time(dist_to_star, current_speed)
		if main_node.get("is_interstellar_autopilot") == true:
			telemetry_text += " • Eylemler: [color=#ff00ff][G] HİPER HIZLANDIR (ÇİFT G)[/color] | [WASD] İptal | [C] Odaklan\n"
		else:
			telemetry_text += " • Eylemler: [color=#00ff66][G] Otopilot Seyri | [C] Odaklan | [Ctrl+T] Işınlan[/color]\n"
	elif main_node.current_target_index >= 0 and main_node.current_target_index < main_node.universe.size():
		var target = main_node.universe[main_node.current_target_index]
		var dist_to_target = target.real_position.length()
		
		telemetry_text += " • İsim: [color=#ffcc00]%s[/color]\n" % target.name
		telemetry_text += " • Tip: [color=#00e5ff]%s[/color]\n" % target.type
		telemetry_text += " • Mesafe: [color=#ffcc00]%s[/color]\n" % format_space_distance(dist_to_target)
		telemetry_text += " • Işık Seyahati: [color=#00e5ff]%s[/color]\n" % format_light_time(dist_to_target)
		telemetry_text += " • Kat Etme Süresi (ETA): [color=#00ff66]%s[/color]\n" % format_travel_time(dist_to_target, current_speed)
		
		if main_node.is_autopilot_active:
			telemetry_text += " • Eylemler: [color=#ff00ff][G] HİPER HIZLANDIR (ÇİFT G)[/color] | [WASD] İptal | [C] Odaklan\n"
		elif not main_node.is_landed and target.type != "STAR":
			if target.get_system_star() == main_node.active_star:
				if dist_to_target < target.real_radius * 1.5:
					telemetry_text += " • Eylemler: [color=#00ff66][E] Gezegene İniş Yap | [C] Odaklan[/color]\n"
				else:
					telemetry_text += " • Eylemler: [color=#00ff66][G] Otopilot | [C] Odaklan | [E] İniş[/color]\n"
			else:
				telemetry_text += " • Eylemler: [color=#ffaa00][G] Otopilot ile Yaklaş | [C] Odaklan[/color]\n"
		else:
			telemetry_text += " • Eylemler: [color=#00ff66][G] Otopilot Seyri | [C] Odaklan[/color]\n"
	else:
		telemetry_text += " • Hedef: [color=#8d99ae]Kilit Yok (T veya Sol Tık)[/color]\n"
			
	telemetry_text += "[color=#3f4f60]━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━[/color]\n"
	
	if main_node.is_system_map_active:
		telemetry_text += "[color=#8d99ae][M] Haritadan Çık | [Sol Tık] Gezegen Seç\n[TAB] HUD Gizle | [P] Zamanı Durdur[/color]"
	elif main_node.get("is_eva_active") == true:
		if main_node.is_landed:
			telemetry_text += "[color=#00e5ff][WASD] Yürü | [Space] Jetpack Zıpla | [Ctrl] Fren | [Shift] Boost\n[L] Kask Feneri | [E] Gemiye Dön (Rampa) | [TAB] HUD[/color]"
		else:
			telemetry_text += "[color=#00e5ff][WASD] RCS İtici | [Space] Yüksel | [Ctrl] Alçal | [Shift] Boost\n[L] Kask Feneri | [E] Gemiye Gir (Hava Kilidi) | [TAB] HUD[/color]"
	elif main_node.is_landed:
		var sc = main_node.spacecraft if main_node.get("spacecraft") != null else (main_node.camera.spacecraft if main_node.camera != null else null)
		if sc != null and sc.current_view_mode == 1 and not sc.get("is_seated_in_cockpit"):
			var airlock_act = "Hava Kilidini Kapat" if sc.is_airlock_open else "Rampayı İndir (Dışarı Çık)"
			var act_str = airlock_act if sc.get("near_airlock") else "Koltuğa Otur"
			telemetry_text += "[color=#00e5ff][WASD] Kabinde Yürü | [E] %s | [F] Kamera | [TAB] HUD[/color]" % act_str
		else:
			telemetry_text += "[color=#00ff66][E] Kalkış Yap / Koltuktan Kalk | [F] Kamera Modu | [TAB] HUD Paneli[/color]"
	else:
		var sc = main_node.spacecraft if main_node.get("spacecraft") != null else (main_node.camera.spacecraft if main_node.camera != null else null)
		if sc != null and sc.current_view_mode == 1 and not sc.get("is_seated_in_cockpit"):
			var airlock_act = "Hava Kilidini Kapat" if sc.is_airlock_open else "Hava Kilidini Aç (Açık Uzay)"
			var act_str = airlock_act if sc.get("near_airlock") else "Koltuğa Otur"
			telemetry_text += "[color=#00e5ff][WASD] Kabinde Yürü | [E] %s | [F] Kamera | [TAB] HUD[/color]" % act_str
		var auto_prompt = "[G] Hiper Boost" if (main_node.is_autopilot_active or main_node.get("is_interstellar_autopilot") == true) else "[G] Otopilot"
		if sc != null and sc.current_view_mode == 1 and sc.get("is_seated_in_cockpit"):
			telemetry_text += "[color=#00ff66][WASD] Gemi Sürüşü | [E] Koltuktan Kalk | [F] Kamera | %s\n[TAB] HUD | [T] Hedef | [C] Odak | [M] Harita | [Ctrl+T] Işınlan[/color]" % auto_prompt
		else:
			telemetry_text += "[color=#8d99ae][TAB] HUD | [T] Hedef | [C] Odak | %s | [F] Kamera\n[Sol Tık] Seç | [M] Harita | [Ctrl+T] Işınlan | [P] Zaman[/color]" % auto_prompt
		
	main_node.ui_label.text = telemetry_text

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
