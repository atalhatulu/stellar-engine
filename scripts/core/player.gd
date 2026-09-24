class_name Player
extends Node3D

@export var mouse_sensitivity: float = 0.002

const LIGHT_SPEED: float = 299792458.0
const ONE_AU: float = 149597870700.0
const LIGHT_YEAR: float = 9460730472580800.0

var speed_presets: Array[float] = [
	5.0, 50.0, 343.0, 3000.0, 30000.0, 300000.0,
	0.001 * LIGHT_SPEED, 0.01 * LIGHT_SPEED, 0.05 * LIGHT_SPEED,
	0.1 * LIGHT_SPEED, 0.25 * LIGHT_SPEED, 0.5 * LIGHT_SPEED,
	LIGHT_SPEED, 2.0 * LIGHT_SPEED, 5.0 * LIGHT_SPEED,
	10.0 * LIGHT_SPEED, 100.0 * LIGHT_SPEED, 1000.0 * LIGHT_SPEED,
	ONE_AU, 5.0 * ONE_AU, 10.0 * ONE_AU, 100.0 * ONE_AU, 1000.0 * ONE_AU,
	0.01 * LIGHT_YEAR, 0.05 * LIGHT_YEAR, 0.1 * LIGHT_YEAR, 0.5 * LIGHT_YEAR,
	LIGHT_YEAR, 2.0 * LIGHT_YEAR, 5.0 * LIGHT_YEAR, 10.0 * LIGHT_YEAR,
	25.0 * LIGHT_YEAR, 50.0 * LIGHT_YEAR, 100.0 * LIGHT_YEAR, 250.0 * LIGHT_YEAR,
	500.0 * LIGHT_YEAR, 1000.0 * LIGHT_YEAR, 2500.0 * LIGHT_YEAR, 5000.0 * LIGHT_YEAR,
	10000.0 * LIGHT_YEAR, 25000.0 * LIGHT_YEAR, 50000.0 * LIGHT_YEAR, 100000.0 * LIGHT_YEAR,
]

var speed_multiplier_index: int = 3
var current_speed: float = 0.0
var target_speed: float = 0.0
var rot_x: float = 0.0
var rot_y: float = 0.0
var rot_z: float = 0.0
var mouse_turn_speed: Vector2 = Vector2.ZERO

@onready var camera_node: Camera3D = $Camera3D

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	target_speed = speed_presets[speed_multiplier_index]
	current_speed = target_speed
	var angles := transform.basis.get_euler()
	rot_x = angles.x
	rot_y = angles.y
	rot_z = angles.z

func _process(delta: float) -> void:
	current_speed = lerpf(current_speed, target_speed, 1.0 - exp(-8.0 * delta))
	mouse_turn_speed = mouse_turn_speed.lerp(Vector2.ZERO, 6.0 * delta)

func _input(event: InputEvent) -> void:
	var parent_node := get_parent()
	var camera_disabled: bool = parent_node != null and parent_node.get("is_system_map_active") == true
	if parent_node != null and (parent_node.get("is_autopilot_active") == true or parent_node.get("is_interstellar_autopilot") == true):
		if event is InputEventMouseMotion and event.relative.length_squared() > 4.0:
			parent_node.set("is_autopilot_active", false)
			parent_node.set("is_hyper_autopilot", false)
			parent_node.set("is_interstellar_autopilot", false)
			parent_node.set("is_interstellar_hyper_boost", false)
			parent_node.set("is_focusing_target", false)
			parent_node.set("autopilot_target_body", null)
			camera_disabled = false
		else:
			camera_disabled = true

	if not camera_disabled and event is InputEventMouseMotion:
		if parent_node != null and parent_node.get("is_focusing_target") == true and event.relative.length_squared() > 1.0:
			parent_node.set("is_focusing_target", false)
			parent_node.set("focus_target_body", null)
			parent_node.set("focus_target_star", null)
			parent_node.set("focus_time", 0.0)
		var landed: bool = parent_node != null and parent_node.get("is_landed") == true
		if landed:
			rot_y -= event.relative.x * mouse_sensitivity
			rot_x = clampf(rot_x - event.relative.y * mouse_sensitivity, -PI / 2.2, PI / 2.2)
			var surface_basis = parent_node.get("landed_surface_basis")
			transform.basis = (surface_basis if surface_basis is Basis else Basis.IDENTITY) * Basis.from_euler(Vector3(rot_x, rot_y, 0.0))
		else:
			transform.basis = transform.basis.rotated(transform.basis.y.normalized(), -event.relative.x * mouse_sensitivity)
			transform.basis = transform.basis.rotated(transform.basis.x.normalized(), -event.relative.y * mouse_sensitivity).orthonormalized()
			mouse_turn_speed = mouse_turn_speed.lerp(Vector2(event.relative.x, event.relative.y), 0.45)
			var angles := transform.basis.get_euler()
			rot_x = angles.x
			rot_y = angles.y
			rot_z = angles.z

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			speed_multiplier_index = mini(speed_multiplier_index + 1, speed_presets.size() - 1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			speed_multiplier_index = maxi(speed_multiplier_index - 1, 0)
		target_speed = speed_presets[speed_multiplier_index]

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_BRACKETLEFT:
			speed_multiplier_index = maxi(speed_multiplier_index - 1, 0)
			target_speed = speed_presets[speed_multiplier_index]
		elif event.keycode == KEY_BRACKETRIGHT:
			speed_multiplier_index = mini(speed_multiplier_index + 1, speed_presets.size() - 1)
			target_speed = speed_presets[speed_multiplier_index]

func _update_camera_view(_instant: bool = false, _delta: float = 0.016) -> void:
	if camera_node != null:
		camera_node.position = Vector3.ZERO
		camera_node.rotation = Vector3.ZERO

func set_speed_to_match_body(body_radius: float) -> void:
	var desired_speed := body_radius * 0.05
	var closest_index := 0
	var min_difference := INF
	for index in range(speed_presets.size()):
		var difference := absf(speed_presets[index] - desired_speed)
		if difference < min_difference:
			min_difference = difference
			closest_index = index
	speed_multiplier_index = closest_index
	target_speed = speed_presets[closest_index]

func reset_camera_orientation(new_basis: Basis) -> void:
	transform.basis = new_basis
	var angles := new_basis.get_euler()
	rot_x = angles.x
	rot_y = angles.y
	rot_z = angles.z
	_update_camera_view(true)
