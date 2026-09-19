class_name SurfaceWalker
extends CharacterBody3D

@export var walk_speed: float = 4.0
@export var sprint_speed: float = 7.0
@export var jump_velocity: float = 3.8
@export var gravity: float = 1.62
@export var jetpack_thrust: float = 5.5
@export var jetpack_fuel: float = 100.0
@export var oxygen: float = 100.0

var is_jetpack_active: bool = false
var is_active: bool = false

var head: Node3D
var collision_shape: CollisionShape3D

func _init() -> void:
	floor_max_angle = deg_to_rad(45.0)
	floor_snap_length = 0.25

func _ready() -> void:
	_setup_nodes()

func _setup_nodes() -> void:
	if collision_shape == null:
		collision_shape = CollisionShape3D.new()
		var capsule := CapsuleShape3D.new()
		capsule.radius = 0.35
		capsule.height = 1.75
		collision_shape.shape = capsule
		collision_shape.position = Vector3(0.0, 0.875, 0.0)
		add_child(collision_shape)
		
	if head == null:
		head = Node3D.new()
		head.name = "Head"
		head.position = Vector3(0.0, 1.65, 0.0)
		add_child(head)

func configure_for_profile(profile: PlanetSurfaceProfile) -> void:
	gravity = profile.gravity

func step(delta: float, input_dir: Vector2, sprint: bool, jump: bool, jetpack: bool) -> void:
	# Dikey fizik (yerçekimi ve zemin kontrolü)
	if not is_on_floor():
		velocity.y -= gravity * delta
		if jetpack and jetpack_fuel > 0.0:
			velocity.y += jetpack_thrust * delta
			velocity.y = minf(velocity.y, 8.0)
			jetpack_fuel = maxf(jetpack_fuel - 25.0 * delta, 0.0)
			is_jetpack_active = true
		else:
			is_jetpack_active = false
	else:
		is_jetpack_active = false
		jetpack_fuel = minf(jetpack_fuel + 35.0 * delta, 100.0)
		if jump:
			velocity.y = jump_velocity

	# Yatay hareket
	var speed := sprint_speed if sprint else walk_speed
	var wish_dir := Vector3(input_dir.x, 0.0, input_dir.y).normalized()
	var target_vel := wish_dir * speed
	
	var accel := 10.0 if is_on_floor() else 2.5
	velocity.x = move_toward(velocity.x, target_vel.x, accel * delta * speed)
	velocity.z = move_toward(velocity.z, target_vel.z, accel * delta * speed)
	
	# Yaşam desteği
	oxygen = maxf(oxygen - 0.02 * delta, 5.0)
	
	move_and_slide()

func _physics_process(delta: float) -> void:
	if not is_active:
		return
		
	var input_dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_W): input_dir.y -= 1.0
	if Input.is_key_pressed(KEY_S): input_dir.y += 1.0
	if Input.is_key_pressed(KEY_A): input_dir.x -= 1.0
	if Input.is_key_pressed(KEY_D): input_dir.x += 1.0
	
	var sprint := Input.is_key_pressed(KEY_SHIFT)
	var jump := is_on_floor() and Input.is_key_pressed(KEY_SPACE)
	var jetpack := not is_on_floor() and Input.is_key_pressed(KEY_SPACE)
	
	step(delta, input_dir, sprint, jump, jetpack)
