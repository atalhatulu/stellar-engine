class_name StellarGroupOverlay
extends Node3D

## Seçili yıldızın grubunu galaksi içinde Skyrim-benzeri parlayan bir
## takım-yıldızı ağı olarak çizer. Yalnızca sunumdan sorumludur; grup üretimi
## ve seçim mantığı kendi modüllerinde kalır.

@export var line_color := Color(0.34, 0.72, 1.0, 0.52)
@export var node_color := Color(0.47, 0.82, 1.0, 0.9)
@export var selected_color := Color(0.92, 0.97, 1.0, 1.0)
@export var node_pixel_size := 0.14

var visible_member_count: int = 0
var edge_count: int = 0

var _host: Node
var _line_instance: MeshInstance3D
var _line_mesh: ImmediateMesh
var _markers: Array[Sprite3D] = []
var _marker_texture: Texture2D
var _cached_group_id := ""
var _members: Array = []
var _fixed_edges: Array[Vector2i] = []


func _ready() -> void:
	_host = get_parent()
	_line_mesh = ImmediateMesh.new()
	_line_instance = MeshInstance3D.new()
	_line_instance.mesh = _line_mesh
	_line_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_line_instance)

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.no_depth_test = true
	material.vertex_color_use_as_albedo = true
	_line_instance.material_override = material
	_marker_texture = _make_glow_texture()
	_hide_overlay()


func _process(_delta: float) -> void:
	if not _can_draw():
		_hide_overlay()
		return

	var selected = _host.targeted_star_data
	if selected.constellation_id != _cached_group_id:
		_cached_group_id = selected.constellation_id
		_members = _collect_constellation_members(_cached_group_id)
		_fixed_edges = _build_fixed_topology()
		_rebuild_markers()

	if _members.size() < 2:
		_hide_overlay()
		return

	visible = true
	visible_member_count = _members.size()
	global_position = _host.star_visual_pool.global_position
	var observer: Vector3 = _host.get_player_galactic_position()
	var points: Array[Vector3] = []
	for member in _members:
		points.append(_host.star_visual_pool.get_star_render_position(member, observer))

	edge_count = _fixed_edges.size()
	_draw_lines(points, _fixed_edges)
	_update_markers(points, selected)


func _can_draw() -> bool:
	if _host == null or not is_instance_valid(_host):
		return false
	if _host.targeted_star_data == null or _host.star_visual_pool == null or _host.sector_manager == null:
		return false
	return _host.targeted_star_data.constellation_id != ""


func _collect_constellation_members(constellation_id: String) -> Array:
	var all_members: Array = []
	for sector_stars in _host.sector_manager.loaded_sectors.values():
		for star in sector_stars:
			if star.constellation_id == constellation_id:
				all_members.append(star)
	# Gerçekte bir bölgedeki her yıldız takımyıldıza aittir fakat desen yalnızca
	# önceden belirlenmiş en parlak yıldızlarla çizilir. Seçim topolojiyi asla
	# değiştirmez; böylece aynı takımyıldızın şekli sabit kalır.
	all_members.sort_custom(func(a, b): return a.luminosity > b.luminosity)
	var visible_count := mini(all_members.size(), maxi(3, int(ceil(all_members.size() * 0.35))))
	var result := all_members.slice(0, visible_count)
	result.sort_custom(func(a, b): return a.unique_id < b.unique_id)
	return result


func _build_fixed_topology() -> Array[Vector2i]:
	# Görsel render konumları gözlemci hareket ettikçe sıkıştırıldığı için bağlantı
	# kararında kullanılmaz. Işık-yılı ölçeğindeki mutlak koordinatlar sabit bir
	# takımyıldız deseni üretir.
	var physical_points: Array[Vector3] = []
	for member in _members:
		physical_points.append(Vector3(member.stellar_x, member.stellar_y, member.stellar_z) / 9460730472580800.0)
	return _minimum_spanning_tree(physical_points)


func _minimum_spanning_tree(points: Array[Vector3], start_index: int = 0) -> Array[Vector2i]:
	var edges: Array[Vector2i] = []
	if points.size() < 2:
		return edges
	var connected: Array[int] = [clampi(start_index, 0, points.size() - 1)]
	var remaining: Array[int] = []
	for i in range(points.size()):
		if i != connected[0]:
			remaining.append(i)
	while not remaining.is_empty():
		var best_from := connected[0]
		var best_to := remaining[0]
		var best_distance := INF
		for from_index in connected:
			for to_index in remaining:
				var distance := points[from_index].distance_squared_to(points[to_index])
				if distance < best_distance:
					best_distance = distance
					best_from = from_index
					best_to = to_index
		edges.append(Vector2i(best_from, best_to))
		connected.append(best_to)
		remaining.erase(best_to)
	return edges


func _draw_lines(points: Array[Vector3], edges: Array[Vector2i]) -> void:
	_line_mesh.clear_surfaces()
	_line_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for edge in edges:
		_line_mesh.surface_set_color(line_color)
		_line_mesh.surface_add_vertex(points[edge.x])
		_line_mesh.surface_set_color(line_color)
		_line_mesh.surface_add_vertex(points[edge.y])
	_line_mesh.surface_end()


func _rebuild_markers() -> void:
	for marker in _markers:
		marker.queue_free()
	_markers.clear()
	for _member in _members:
		var marker := Sprite3D.new()
		marker.texture = _marker_texture
		marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		marker.no_depth_test = true
		marker.pixel_size = node_pixel_size
		marker.render_priority = 1
		add_child(marker)
		_markers.append(marker)


func _update_markers(points: Array[Vector3], selected) -> void:
	var pulse := 1.0 + sin(Time.get_ticks_msec() * 0.004) * 0.12
	for i in range(_markers.size()):
		var is_selected: bool = _members[i].unique_id == selected.unique_id
		_markers[i].position = points[i]
		_markers[i].modulate = selected_color if is_selected else node_color
		_markers[i].scale = Vector3.ONE * (1.65 * pulse if is_selected else 1.0)


func _hide_overlay() -> void:
	visible = false
	visible_member_count = 0
	edge_count = 0
	_cached_group_id = ""
	_members.clear()
	_fixed_edges.clear()
	if _line_mesh != null:
		_line_mesh.clear_surfaces()


func _make_glow_texture() -> Texture2D:
	const SIZE := 64
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var center := Vector2(SIZE - 1, SIZE - 1) * 0.5
	for y in range(SIZE):
		for x in range(SIZE):
			var radius := Vector2(x, y).distance_to(center) / (SIZE * 0.5)
			var core := pow(maxf(0.0, 1.0 - radius), 7.0)
			var halo := pow(maxf(0.0, 1.0 - radius), 2.2) * 0.55
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, core + halo))
	return ImageTexture.create_from_image(image)
