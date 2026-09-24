class_name DiscoveryCatalog
extends RefCounted

const FORMAT_VERSION: int = 1
const DEFAULT_PATH: String = "user://discovery_catalog.json"

var save_path: String
var records: Dictionary = {}
var last_error: String = ""

func _init(p_save_path: String = DEFAULT_PATH) -> void:
	save_path = p_save_path

func discover(identifier: String, kind: String, parent_id: String = "", display_name: String = "") -> bool:
	if identifier.is_empty():
		last_error = "Boş gökcismi kimliği kaydedilemez"
		return false
	var is_new := not records.has(identifier)
	var record: Dictionary = records.get(identifier, {})
	record["id"] = identifier
	record["kind"] = kind
	record["parent_id"] = parent_id
	record["name"] = display_name
	if not record.has("discovered_unix"):
		record["discovered_unix"] = int(Time.get_unix_time_from_system())
	records[identifier] = record
	return is_new

func is_discovered(identifier: String) -> bool:
	return records.has(identifier)

func get_record(identifier: String) -> Dictionary:
	return records.get(identifier, {}).duplicate(true)

func get_ids(kind: String = "") -> Array[String]:
	var result: Array[String] = []
	for identifier in records:
		var record: Dictionary = records[identifier]
		if kind.is_empty() or str(record.get("kind", "")) == kind:
			result.append(str(identifier))
	result.sort()
	return result

func save() -> bool:
	last_error = ""
	var ordered_records: Array[Dictionary] = []
	for identifier in get_ids():
		ordered_records.append(get_record(identifier))
	var payload := {
		"version": FORMAT_VERSION,
		"discoveries": ordered_records
	}
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		last_error = "Katalog yazılamadı: %s" % FileAccess.get_open_error()
		return false
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	return true

func load_catalog() -> bool:
	last_error = ""
	records.clear()
	if not FileAccess.file_exists(save_path):
		return true
	var file := FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		last_error = "Katalog okunamadı: %s" % FileAccess.get_open_error()
		return false
	var json := JSON.new()
	var parse_error := json.parse(file.get_as_text())
	file.close()
	if parse_error != OK:
		last_error = "Katalog JSON hatası (satır %d): %s" % [json.get_error_line(), json.get_error_message()]
		return false
	var parsed = json.data
	if not parsed is Dictionary:
		last_error = "Katalog geçerli JSON nesnesi değil"
		return false
	if int(parsed.get("version", 0)) > FORMAT_VERSION:
		last_error = "Katalog sürümü bu oyun sürümünden yeni"
		return false
	var discoveries = parsed.get("discoveries", [])
	if not discoveries is Array:
		last_error = "Katalog keşif listesi bozuk"
		return false
	for value in discoveries:
		if not value is Dictionary:
			continue
		var identifier := str(value.get("id", ""))
		if identifier.is_empty():
			continue
		records[identifier] = value.duplicate(true)
	return true
