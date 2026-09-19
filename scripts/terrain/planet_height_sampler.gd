class_name PlanetHeightSampler
extends RefCounted

var profile: PlanetSurfaceProfile
var up := Vector3.UP
var east := Vector3.RIGHT
var north := Vector3.BACK
var base_height := 0.0
var macro := FastNoiseLite.new()
var hills := FastNoiseLite.new()
var detail := FastNoiseLite.new()
var craters := FastNoiseLite.new()

func _init(p_profile: PlanetSurfaceProfile, direction: Vector3 = Vector3.UP) -> void:
	profile = p_profile
	up = direction.normalized()
	var axis := Vector3.RIGHT if absf(up.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	north = axis.cross(up).normalized()
	east = up.cross(north).normalized()
	var noises := [macro, hills, detail, craters]
	var frequencies := [0.00008, 0.0025, 0.05, 0.0018]
	for i in range(noises.size()):
		noises[i].seed = profile.seed_value + i * 7919
		noises[i].frequency = frequencies[i]
		noises[i].fractal_octaves = 3 if i < 2 else 2
	craters.noise_type = FastNoiseLite.TYPE_CELLULAR
	craters.fractal_type = FastNoiseLite.FRACTAL_NONE
	craters.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
	base_height = height_direction(up)

func height_direction(direction: Vector3) -> float:
	var d := direction.normalized()
	return _height_xyz(float(d.x) * profile.radius, float(d.y) * profile.radius, float(d.z) * profile.radius)

func _height_xyz(x: float, y: float, z: float) -> float:
	var continental := macro.get_noise_3d(x,y,z) * 320.0
	var ridges := hills.get_noise_3d(x,y,z) * 32.0
	var small := detail.get_noise_3d(x,y,z) * 0.65
	var crater_height := 0.0
	if profile.moon:
		var distance := clampf(craters.get_noise_3d(x,y,z) + 1.0, 0.0, 1.5)
		var bowl := -24.0 * (1.0 - smoothstep(0.05, 0.43, distance))
		var rim := exp(-pow((distance - 0.46) / 0.08, 2.0)) * 9.0
		crater_height = bowl + rim
	return (continental + ridges + crater_height) * profile.relief + small

func height_local(x: float, z: float) -> float:
	# Scalar coordinates retain sub-metre differences at planetary radii.
	var r := profile.radius
	var px: float = float(up.x)*r + float(east.x)*x + float(north.x)*z
	var py: float = float(up.y)*r + float(east.y)*x + float(north.y)*z
	var pz: float = float(up.z)*r + float(east.z)*x + float(north.z)*z
	var length_p := sqrt(px*px + py*py + pz*pz)
	var factor := r / length_p
	var h := _height_xyz(px*factor, py*factor, pz*factor)
	return (r + h) * factor - r - base_height

func normal_local(x: float, z: float, step: float = 1.0) -> Vector3:
	return Vector3(height_local(x-step,z)-height_local(x+step,z), 2.0*step,
		height_local(x,z-step)-height_local(x,z+step)).normalized()

func landing_suitable(x: float, z: float) -> bool:
	var low := INF
	var high := -INF
	for offset in [Vector2(-1.42,-1.95),Vector2(1.42,-1.95),Vector2(-1.42,2.05),Vector2(1.42,2.05),Vector2(0,4.6)]:
		var px: float = x + offset.x
		var pz: float = z + offset.y
		if normal_local(px,pz).dot(Vector3.UP) < cos(deg_to_rad(12.0)):
			return false
		var h := height_local(px,pz)
		low = minf(low,h)
		high = maxf(high,h)
	return high-low < 0.45

func find_landing_site() -> Vector2:
	for ring in range(20):
		for i in range(maxi(1,ring*8)):
			var angle := TAU * float(i) / maxi(1,ring*8)
			var point := Vector2(cos(angle),sin(angle)) * float(ring)*12.0
			if landing_suitable(point.x,point.y):
				return point
	return Vector2(INF,INF)
