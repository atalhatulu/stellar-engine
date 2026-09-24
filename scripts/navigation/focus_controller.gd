class_name FocusController
extends RefCounted

static func step(host: Node3D, delta: float) -> void:
	if host == null or not host.is_focusing_target or host.is_system_map_active or host.is_landed:
		return
	var target_direction := Vector3.ZERO
	if host.focus_target_star != null:
		var observer: Vector3 = host.get_player_galactic_position()
		var star_position := Vector3(
			host.focus_target_star.stellar_x,
			host.focus_target_star.stellar_y,
			host.focus_target_star.stellar_z
		)
		target_direction = (star_position - observer).normalized()
	elif host.focus_target_body != null and is_instance_valid(host.focus_target_body):
		target_direction = host.focus_target_body.real_position.normalized()
	else:
		cancel(host)
		return
	if target_direction.length_squared() <= 0.000001:
		return
	var target_pitch := asin(clampf(target_direction.y, -0.9999, 0.9999))
	var target_yaw := atan2(-target_direction.x, -target_direction.z)
	host.camera.rot_x = lerp_angle(host.camera.rot_x, target_pitch, 8.0 * delta)
	host.camera.rot_y = lerp_angle(host.camera.rot_y, target_yaw, 8.0 * delta)
	host.camera.rot_z = lerp_angle(host.camera.rot_z, 0.0, 8.0 * delta)
	host.camera.transform.basis = Basis.from_euler(Vector3(host.camera.rot_x, host.camera.rot_y, host.camera.rot_z))
	host.focus_time += delta
	var aligned: bool = (
		host.focus_time >= 0.25
		and absf(angle_difference(host.camera.rot_x, target_pitch)) < 0.02
		and absf(angle_difference(host.camera.rot_y, target_yaw)) < 0.02
	)
	if aligned:
		host.camera.rot_x = target_pitch
		host.camera.rot_y = target_yaw
		host.camera.rot_z = 0.0
		host.camera.transform.basis = Basis.from_euler(Vector3(target_pitch, target_yaw, 0.0))
		cancel(host)

static func cancel(host: Node3D) -> void:
	host.is_focusing_target = false
	host.focus_target_body = null
	host.focus_target_star = null
	host.focus_time = 0.0
