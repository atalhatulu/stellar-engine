class_name SurveyController
extends RefCounted

var catalog := DiscoveryCatalog.new()
var progress: Dictionary = {}


func load_catalog() -> void:
	catalog.load_catalog()
	for identifier in catalog.get_ids():
		progress[identifier] = 100.0


func update_target(target, delta: float) -> void:
	if target == null or str(target.unique_id).is_empty():
		return
	var identifier := str(target.unique_id)
	var value := minf(100.0, float(progress.get(identifier, 0.0)) + delta * 12.0)
	progress[identifier] = value
	if value >= 100.0 and not catalog.is_discovered(identifier):
		var kind := "STAR" if target is StarData else str(target.type)
		catalog.discover(identifier, kind, str(target.parent_id), str(target.name))
		catalog.save()


func get_progress(target) -> float:
	if target == null:
		return 0.0
	return float(progress.get(str(target.unique_id), 0.0))
