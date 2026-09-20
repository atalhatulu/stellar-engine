extends SceneTree

const GalacticPosition = preload("res://scripts/core/galactic_position.gd")
const OriginManager = preload("res://scripts/core/origin_manager.gd")
const SpaceScaleManager = preload("res://scripts/rendering/space_scale_manager.gd")
const StreamingManager = preload("res://scripts/generation/streaming_manager.gd")
const SectorManager = preload("res://scripts/generation/sector_manager.gd")

var failures := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("FAIL: " + message)
		print("FAIL: ", message)
	else:
		print("PASS: ", message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	print("--- HİYERARŞİK KOORDİNAT VE STREAMING REGRESYON TESTİ BAŞLATILIYOR ---")

	# 1. Aşama: GalacticPosition Hassasiyet ve Normalizasyon Testleri
	var gpos1 = GalacticPosition.new(Vector3i(0, 0, 0), Vector3(1000.0, 2000.0, 3000.0))
	check(gpos1.sector == Vector3i(0, 0, 0), "Başlangıç sektörü doğru")
	check(gpos1.local_pos == Vector3(1000.0, 2000.0, 3000.0), "Yerel metre pozisyonu doğru")

	# Sektör sınırını aşma testi (Pozitif ve Negatif Normalizasyon)
	var sector_size = GalacticPosition.SECTOR_SIZE_METERS
	gpos1.add_meters(Vector3(sector_size * 2.5, -sector_size * 1.2, 0.0))
	check(gpos1.sector.x == 2, "X sektör taşması doğru pozitif normalizasyon yaptı (Sektör 2)")
	check(gpos1.sector.y == -2, "Y sektör taşması doğru negatif normalizasyon yaptı (Sektör -2)")
	check(gpos1.local_pos.x >= 0.0 and gpos1.local_pos.x < sector_size, "X yerel pozisyonu [0, SECTOR_SIZE) aralığında")
	check(gpos1.local_pos.y >= 0.0 and gpos1.local_pos.y < sector_size, "Y yerel pozisyonu [0, SECTOR_SIZE) aralığında")

	# İki galaktik konum arası hassas bağıl fark (Precision Test)
	var pos_a = GalacticPosition.new(Vector3i(100, 50, -25), Vector3(500.0, 0.0, 0.0))
	var pos_b = GalacticPosition.new(Vector3i(100, 50, -25), Vector3(800.0, 0.0, 0.0))
	var rel_diff = pos_b.get_relative_meters(pos_a)
	check(is_equal_approx(rel_diff.x, 300.0) and is_equal_approx(rel_diff.y, 0.0), "Aynı sektördeki iki nesne arası bağıl mesafe tam 300m")

	var pos_c = GalacticPosition.new(Vector3i(101, 50, -25), Vector3(500.0, 0.0, 0.0))
	var rel_inter_sector = pos_c.get_relative_meters(pos_a)
	check(is_equal_approx(rel_inter_sector.x, sector_size), "Komşu sektörler arası bağıl fark tam 1 sektör boyutu")

	# Işık yılı dönüşümü testi
	var ly_test = GalacticPosition.from_light_years(Vector3(65.0, 130.0, 0.0))
	check(ly_test.sector.x == 1 and ly_test.sector.y == 2, "Işık yılından sektör koordinatına dönüşüm doğru")

	# 2. Aşama: OriginManager (4 Katmanlı Koordinat Hiyerarşisi)
	var origin_mgr = OriginManager.new(pos_a)
	check(origin_mgr.player_galactic_pos.sector == Vector3i(100, 50, -25), "OriginManager galaktik oyuncu konumunu devraldı")

	# System Space -> Planet Space dönüşümü
	origin_mgr.set_active_planet(Vector3(5000000.0, 0.0, 0.0)) # 5000 km mesafede uydu/gezegen
	var ship_system_pos = Vector3(5005000.0, 0.0, 0.0)
	var planet_rel_pos = origin_mgr.system_to_planet_pos(ship_system_pos)
	check(is_equal_approx(planet_rel_pos.x, 5000.0), "System -> Planet space dönüşümü tam 5000m ofset verdi")

	# Floating origin eşiği testi
	var origin_shift = origin_mgr.check_and_shift_origin(Vector3(15000.0, 0.0, 0.0))
	check(origin_shift.x > 0.0, "10 km eşiğini aşan hareket floating origin kaydırmasını tetikledi")
	check(origin_mgr.render_origin_offset.x == 15000.0, "Birikimli render origin ofseti kaydedildi")

	# 3. Aşama: SpaceScaleManager (Simülasyon -> Render Kabuğu Projeksiyonu)
	var scale_mgr = SpaceScaleManager.new(10000.0, 1.0)
	var projected = scale_mgr.project_world_position(Vector3(1000000.0, 0.0, 0.0), false)
	check(is_equal_approx(projected.length(), 10000.0), "Uzak simülasyon konumu (1000 km) maksimum 10 km render kabuğuna projekte edildi")

	var near_projected = scale_mgr.project_world_position(Vector3(250.0, 0.0, 0.0), true)
	check(is_equal_approx(near_projected.length(), 250.0), "Yüzey yakınındaki 1:1 metre konumu projekte edilmeden korundu")

	# 4. Aşama: StreamingManager (Frame Budgeting & Delta Streaming)
	var sec_mgr = SectorManager.new(123456)
	var stream_mgr = StreamingManager.new(sec_mgr, 1500)
	check(stream_mgr.frame_budget_usec == 1500, "Streaming yöneticisi 1.5 ms kare bütçesiyle yapılandırıldı")

	var update_res = stream_mgr.update(Vector3(0.5, 0.5, 0.5) * SectorManager.SECTOR_SIZE)
	check(update_res == true, "Streaming yöneticisi ilk güncellemede sektörleri başarıyla devreye aldı")
	check(stream_mgr.last_frame_stream_time_usec >= 0, "Kare içi harcanan streaming süresi mikrosaniye cinsinden ölçüldü")

	if failures == 0:
		print("--- HİYERARŞİK KOORDİNAT VE STREAMING TESTİ BAŞARILI: HATA SAYISI: 0 ---")
		print("HIERARCHICAL COORDINATES REGRESSION: PASS")
		quit(0)
	else:
		push_error("HATA SAYISI: %d" % failures)
		quit(1)
