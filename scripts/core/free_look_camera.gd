class_name FreeLookCamera
extends Node3D

@export var mouse_sensitivity: float = 0.002
@export var base_speed: float = 50.0
@export var min_speed: float = 2.0
@export var max_speed: float = 200000.0

var current_speed: float = 200.0
var target_speed: float = 200.0

var rot_x: float = 0.0 # Pitch
var rot_y: float = 0.0 # Yaw

var camera: Camera3D = null

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	camera = get_node_or_null("Camera3D")
	if camera == null:
		camera = Camera3D.new()
		camera.name = "Camera3D"
		camera.near = 0.1
		camera.far = 2000000.0 # 2.000 km render mesafesi
		add_child(camera)
	else:
		camera.near = 0.1
		camera.far = 2000000.0

	var euler = transform.basis.get_euler()
	rot_x = euler.x
	rot_y = euler.y

signal lod_wheel_adjusted(delta_factor: float)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
				Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			else:
				Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	
	if event is InputEventMouseButton and event.pressed:
		if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			if event.shift_pressed:
				target_speed = clampf(target_speed * 1.4, min_speed, max_speed)
			else:
				lod_wheel_adjusted.emit(0.12)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if event.shift_pressed:
				target_speed = clampf(target_speed / 1.4, min_speed, max_speed)
			else:
				lod_wheel_adjusted.emit(-0.12)

	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		rot_y -= event.relative.x * mouse_sensitivity
		rot_x -= event.relative.y * mouse_sensitivity
		rot_x = clampf(rot_x, -1.55, 1.55)
		transform.basis = Basis.from_euler(Vector3(rot_x, rot_y, 0.0))

func _process(delta: float) -> void:
	current_speed = lerpf(current_speed, target_speed, 1.0 - exp(-10.0 * delta))
	
	var move_vec := Vector3.ZERO
	if Input.is_key_pressed(KEY_W): move_vec.z -= 1.0
	if Input.is_key_pressed(KEY_S): move_vec.z += 1.0
	if Input.is_key_pressed(KEY_A): move_vec.x -= 1.0
	if Input.is_key_pressed(KEY_D): move_vec.x += 1.0
	if Input.is_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_E): move_vec.y += 1.0
	if Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_Q): move_vec.y -= 1.0
	
	var mult = 3.0 if Input.is_key_pressed(KEY_SHIFT) else 1.0
	if move_vec.length_squared() > 0.001:
		move_vec = move_vec.normalized()
		var forward = -transform.basis.z
		var right = transform.basis.x
		var up = transform.basis.y
		var world_move = (right * move_vec.x + up * move_vec.y + forward * (-move_vec.z))
		global_position += world_move * (current_speed * mult * delta)
