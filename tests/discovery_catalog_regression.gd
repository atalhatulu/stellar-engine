extends SceneTree

const TEST_PATH := "/tmp/stellar_engine_discovery_catalog_test.json"

func _init() -> void:
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(TEST_PATH)

	var catalog := DiscoveryCatalog.new(TEST_PATH)
	_assert(catalog.load_catalog(), "Olmayan katalog boş olarak açılamadı")
	_assert(catalog.discover("GAL_42", "GALAXY", "", "Test Galaksisi"), "Yeni galaksi keşfi eklenmedi")
	_assert(catalog.discover("GAL_42_SEC_1_2_3_S4", "STAR", "GAL_42", "Test Yıldızı"), "Yeni yıldız keşfi eklenmedi")
	_assert(not catalog.discover("GAL_42", "GALAXY", "", "Yeni Ad"), "Aynı kimlik ikinci keşif sayıldı")
	_assert(catalog.save(), catalog.last_error)

	var loaded := DiscoveryCatalog.new(TEST_PATH)
	_assert(loaded.load_catalog(), loaded.last_error)
	_assert(loaded.is_discovered("GAL_42"), "Galaksi kimliği yüklenemedi")
	_assert(loaded.get_ids("STAR") == ["GAL_42_SEC_1_2_3_S4"], "Tür filtresi bozuk")
	_assert(loaded.get_record("GAL_42_SEC_1_2_3_S4").get("parent_id") == "GAL_42", "Ebeveyn kimliği korunmadı")

	var corrupt := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	corrupt.store_string("{bozuk-json")
	corrupt.close()
	var broken := DiscoveryCatalog.new(TEST_PATH)
	_assert(not broken.load_catalog(), "Bozuk katalog geçerli kabul edildi")
	_assert(broken.records.is_empty(), "Bozuk katalog kısmi veri bıraktı")

	DirAccess.remove_absolute(TEST_PATH)
	print("DISCOVERY_CATALOG_REGRESSION_OK")
	quit(0)

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	quit(1)
