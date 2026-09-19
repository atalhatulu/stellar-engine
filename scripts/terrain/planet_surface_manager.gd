class_name PlanetSurfaceManager
extends Node3D

const SurfaceChunkJob = preload("res://scripts/terrain/surface_chunk_job.gd")

var profile: PlanetSurfaceProfile
var landing_dir := Vector3.UP
var landing_site_local := Vector2.ZERO
var sampler: PlanetHeightSampler
var terrain_material: ShaderMaterial

var chunks: Dictionary = {}
var static_bodies: Dictionary = {}

func _init(p_profile: PlanetSurfaceProfile = null, p_direction: Vector3 = Vector3.UP) -> void:
	if p_profile == null:
		p_profile = PlanetSurfaceProfile.new()
	profile = p_profile
	landing_dir = p_direction.normalized()
	sampler = PlanetHeightSampler.new(profile, landing_dir)
	_setup_material()

func _setup_material() -> void:
	terrain_material = ShaderMaterial.new()
	var shader = load("res://shaders/surface_terrain.gdshader")
	terrain_material.shader = shader
	terrain_material.set_shader_parameter("soil", profile.ground_color)
	terrain_material.set_shader_parameter("rock", profile.rock_color)

func build_surface(grid_radius: int = 1) -> void:
	clear()
	for gx in range(-grid_radius, grid_radius + 1):
		for gz in range(-grid_radius, grid_radius + 1):
			_create_chunk(Vector2i(gx, gz))

func _create_chunk(coord: Vector2i) -> void:
	var key := "%d,%d" % [coord.x, coord.y]
	if chunks.has(key):
		return
		
	var job = SurfaceChunkJob.new()
	# Center chunk is LOD0 (divisions = 64, ~2.0m resolution) with physics.
	# Outer chunks can have divisions = 32 (~4.0m resolution).
	var is_center = (coord.x == 0 and coord.y == 0)
	var divisions = 64 if is_center else 32
	var edge_steps = Vector4i(2, 2, 2, 2)
	
	var data: Dictionary = job.build(profile, landing_dir, coord, divisions, edge_steps)
	if data.is_empty():
		return
		
	var vertices: PackedVector3Array = data["vertices"]
	var normals: PackedVector3Array = data["normals"]
	var uvs: PackedVector2Array = data["uvs"]
	var indices: PackedInt32Array = data["indices"]
	var faces: PackedVector3Array = data["faces"]
	
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, terrain_material)
	
	var mi := MeshInstance3D.new()
	mi.name = "ChunkMesh_%s" % key
	mi.mesh = mesh
	mi.position = Vector3(float(coord.x) * SurfaceChunkJob.SIZE, 0.0, float(coord.y) * SurfaceChunkJob.SIZE)
	add_child(mi)
	chunks[key] = mi
	
	# Create physics collision for chunks with faces (divisions == 64)
	if not faces.is_empty():
		var sb := StaticBody3D.new()
		sb.name = "ChunkCol_%s" % key
		sb.position = mi.position
		
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(faces)
		shape.backface_collision = true
		
		var cs := CollisionShape3D.new()
		cs.shape = shape
		sb.add_child(cs)
		add_child(sb)
		static_bodies[key] = sb

func get_height(x: float, z: float) -> float:
	if sampler != null:
		return sampler.height_local(x, z)
	return 0.0

func get_normal(x: float, z: float) -> Vector3:
	if sampler != null:
		return sampler.normal_local(x, z)
	return Vector3.UP

func clear() -> void:
	for mi in chunks.values():
		if is_instance_valid(mi):
			mi.queue_free()
	chunks.clear()
	
	for sb in static_bodies.values():
		if is_instance_valid(sb):
			sb.queue_free()
	static_bodies.clear()
