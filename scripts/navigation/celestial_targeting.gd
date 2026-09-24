class_name CelestialTargeting
extends RefCounted

const NONE := "none"
const BODY := "body"
const BLACK_HOLE := "black_hole"
const STAR := "star"
const GALAXY := "galaxy"

static func pick(host: Node3D, cam: Camera3D, cursor_pos: Vector2) -> Dictionary:
	if cam == null:
		return {"kind": NONE}
	var camera_position := cam.global_position
	var camera_forward := -cam.global_transform.basis.z

	var body := _pick_system_body(host, cam, cursor_pos, camera_position)
	if body != null:
		return {"kind": BODY, "value": body}
	# Aktif bir sistemde arka plan kataloğu ancak nişangâha çok kesin biçimde
	# alınır. Böylece gezegenlerin yakınındaki uzak yıldızlar seçimi çalmaz.
	var inside_system := is_instance_valid(host.active_system_root)

	var center_position: Vector3 = host._galactic_center_world_position()
	var center_offset := center_position - camera_position
	if center_offset.length() > 5.0 and camera_forward.dot(center_offset.normalized()) > cos(0.06):
		return {"kind": BLACK_HOLE}

	var star_result := _pick_star(host, cam, cursor_pos, camera_position, camera_forward, 9.0 if inside_system else 28.0)
	var galaxy_result := _pick_galaxy(host, cam, cursor_pos, camera_position, camera_forward, star_result)
	if not galaxy_result.is_empty():
		return galaxy_result
	if not star_result.is_empty():
		return {"kind": STAR, "value": star_result["value"]}
	return {"kind": NONE}

static func _pick_system_body(host: Node3D, cam: Camera3D, cursor_pos: Vector2, camera_position: Vector3) -> CelestialBody:
	if not is_instance_valid(host.active_system_root):
		return null
	var best: CelestialBody = null
	var best_pixels := INF
	var best_distance := INF
	for candidate in host.active_system_bodies:
		if candidate.type not in ["PLANET", "MOON"] or not is_instance_valid(candidate.visual_mesh):
			continue
		var world_position: Vector3 = candidate.visual_mesh.global_position
		if cam.to_local(world_position).z >= -0.0001:
			continue
		var distance := world_position.distance_to(camera_position)
		if distance <= 0.001:
			continue
		var pixels := cam.unproject_position(world_position).distance_to(cursor_pos)
		var apparent_radius := 0.0
		if candidate.real_radius > 0.0:
			apparent_radius = clampf(candidate.real_radius / distance * 900.0, 0.0, 70.0)
		var radius := maxf(58.0 if candidate.type == "PLANET" else 40.0, apparent_radius + 20.0)
		if pixels <= radius and (pixels < best_pixels or (is_equal_approx(pixels, best_pixels) and distance < best_distance)):
			best = candidate
			best_pixels = pixels
			best_distance = distance
	return best

static func _pick_star(host: Node3D, cam: Camera3D, cursor_pos: Vector2, camera_position: Vector3, camera_forward: Vector3, exact_radius: float = 28.0) -> Dictionary:
	var best: StarData = null
	var best_pixels := INF
	var best_distance := INF
	var fallback: StarData = null
	var fallback_pixels := 55.0
	for candidate in host.stars_data:
		if candidate == null:
			continue
		var world_position: Vector3 = host._star_world_position(candidate)
		var offset := world_position - camera_position
		var distance := offset.length()
		if distance < 0.01 or camera_forward.dot(offset / distance) < 0.995 or cam.is_position_behind(world_position):
			continue
		var pixels := cam.unproject_position(world_position).distance_to(cursor_pos)
		if pixels <= exact_radius:
			if pixels < best_pixels or (is_equal_approx(pixels, best_pixels) and distance < best_distance):
				best = candidate
				best_pixels = pixels
				best_distance = distance
		elif exact_radius >= 20.0 and pixels < fallback_pixels:
			fallback = candidate
			fallback_pixels = pixels
	if best != null:
		return {"value": best, "pixels": best_pixels}
	if fallback != null:
		return {"value": fallback, "pixels": fallback_pixels, "fallback": true}
	return {}

static func _pick_galaxy(host: Node3D, cam: Camera3D, cursor_pos: Vector2, camera_position: Vector3, camera_forward: Vector3, star_result: Dictionary) -> Dictionary:
	var best: Galaxy = null
	var best_pixels := INF
	for candidate in host.extragalactic_cluster:
		if candidate.is_host_galaxy:
			continue
		# Render konumu kayan orijin/sector sistemiyle hesaplanmalıdır. Eski
		# galaxy_origin_ly çıkarımı uzun seyahatlerden sonra görsel ile ışını ayırıyordu.
		var candidate_world: Vector3 = host._galaxy_world_position(candidate)
		var offset: Vector3 = candidate_world - camera_position
		var distance := offset.length()
		if distance < 50.0 or camera_forward.dot(offset / distance) < 0.2:
			continue
		var projected := camera_position + offset / distance * minf(distance, 180000.0)
		if cam.is_position_behind(projected):
			continue
		var pixels := cam.unproject_position(projected).distance_to(cursor_pos)
		if pixels < 64.0 and pixels < best_pixels:
			best = candidate
			best_pixels = pixels

	# Uzak galaksi alanı, nişangâhın yanında bir yıldız bulunmasından bağımsız
	# sorgulanır. Aksi halde yoğun yıldız alanında galaksi seçmek imkânsızlaşır.
	if best == null and host.streamed_galaxy_field != null:
		var observer_position: GalacticPosition = host.get_player_galactic_position_precise()
		var stream_index: int = host.streamed_galaxy_field.find_closest_galaxy_to_ray(
			observer_position.to_light_years(), camera_forward, 0.075
		)
		if stream_index >= 0:
			var streamed_candidate: Galaxy = host.streamed_galaxy_field.create_galaxy_data(stream_index)
			if streamed_candidate != null:
				var stream_offset: Vector3 = host._galaxy_world_position(streamed_candidate) - camera_position
				var stream_distance := stream_offset.length()
				if stream_distance > 0.001:
					var stream_projected := camera_position + stream_offset / stream_distance * minf(stream_distance, 180000.0)
					var stream_pixels := cam.unproject_position(stream_projected).distance_to(cursor_pos)
					if stream_pixels <= 72.0:
						best = streamed_candidate
						best_pixels = stream_pixels
	var star_pixels: float = float(star_result.get("pixels", INF))
	# Galaksi ekranda nişangâha yeterince yakınsa tek bir arka plan yıldızının
	# seçimi çalmasına izin verme. Tam merkezdeki yıldız yine önceliklidir.
	if best != null and (star_result.is_empty() or best_pixels <= 18.0 or best_pixels + 4.0 < star_pixels):
		return {"kind": GALAXY, "value": best, "pixels": best_pixels}
	return {}
