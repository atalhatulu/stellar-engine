class_name GalaxyLodRegistry
extends RefCounted

# Sektör ve uzak-alan üreticileri geçici listeler oluşturur. Oyuncunun seçtiği,
# ziyaret ettiği veya etkinleştirdiği galaksiler bu kayıt katmanında kalıcıdır.
const MAX_PINNED_GALAXIES := 128

var _pinned: Dictionary = {}
var _pin_order: Array[String] = []
var active_id: String = ""

func pin(galaxy: Galaxy) -> void:
	if galaxy == null or galaxy.unique_id.is_empty():
		return
	if not _pinned.has(galaxy.unique_id):
		_pin_order.append(galaxy.unique_id)
	_pinned[galaxy.unique_id] = galaxy
	_trim()

func set_active(galaxy: Galaxy) -> void:
	pin(galaxy)
	active_id = galaxy.unique_id if galaxy != null else ""

func compose(sector_galaxies: Array[Galaxy], capacity: int) -> Array[Galaxy]:
	var result: Array[Galaxy] = []
	var seen: Dictionary = {}
	# Sabitlenmiş galaksiler önce yazılır; MultiMesh kapasitesi dolsa bile hedef
	# veya daha önce ziyaret edilen galaksi listeden düşmez.
	for identifier in _pin_order:
		var galaxy: Galaxy = _pinned.get(identifier)
		if galaxy == null or seen.has(identifier):
			continue
		result.append(galaxy)
		seen[identifier] = true
		if result.size() >= capacity:
			return result
	for galaxy in sector_galaxies:
		if galaxy == null or seen.has(galaxy.unique_id):
			continue
		result.append(galaxy)
		seen[galaxy.unique_id] = true
		if result.size() >= capacity:
			break
	return result

func compose_pinned(capacity: int) -> Array[Galaxy]:
	var empty: Array[Galaxy] = []
	return compose(empty, capacity)

func contains(identifier: String) -> bool:
	return _pinned.has(identifier)

func _trim() -> void:
	while _pin_order.size() > MAX_PINNED_GALAXIES:
		var oldest: String = _pin_order.pop_front()
		if oldest == active_id:
			_pin_order.append(oldest)
			continue
		_pinned.erase(oldest)
