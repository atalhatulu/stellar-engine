class_name FreeFlightController
extends RefCounted

static func step(host: Node3D, delta: float) -> void:
	if host == null or host.camera == null or host.is_system_map_active or host.is_landed:
		return
	var input_direction := Vector3.ZERO
	if Input.is_key_pressed(KEY_W): input_direction.z -= 1.0
	if Input.is_key_pressed(KEY_S): input_direction.z += 1.0
	if Input.is_key_pressed(KEY_A): input_direction.x -= 1.0
	if Input.is_key_pressed(KEY_D): input_direction.x += 1.0
	if Input.is_key_pressed(KEY_SPACE): input_direction.y += 1.0
	if Input.is_key_pressed(KEY_CTRL): input_direction.y -= 1.0

	if host.is_focusing_target and (input_direction.length_squared() > 0.0 or Input.is_key_pressed(KEY_Q)):
		host.is_focusing_target = false
		host.focus_target_body = null
		host.focus_target_star = null
		host.focus_time = 0.0

	var moving := input_direction.length_squared() > 0.0
	var basis: Basis = host.camera.global_transform.basis
	var direction := Vector3.ZERO
	if moving:
		direction = (-basis.z * -input_direction.z + basis.x * input_direction.x + basis.y * input_direction.y).normalized()
	var desired_velocity: Vector3 = direction * host.camera.current_speed if moving else Vector3.ZERO
	var response := 3.5 if moving else 1.6
	host.player_velocity = host.player_velocity.lerp(desired_velocity, response * delta)
	host.flight_speed_mps = host.safe_vector_length(host.player_velocity)
	if not moving and host.flight_speed_mps < 0.2:
		host.player_velocity = Vector3.ZERO
		host.flight_speed_mps = 0.0
	host.virtual_player_position += host.player_velocity * delta
