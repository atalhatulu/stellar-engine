extends RefCounted

# Worker owns all generated data. No scene nodes or RenderingServer calls here.
const LY: float = 9460730472580800.0
var _mutex := Mutex.new()
var _cancelled := false

func cancel() -> void:
	_mutex.lock()
	_cancelled = true
	_mutex.unlock()

func cancelled() -> bool:
	_mutex.lock()
	var value := _cancelled
	_mutex.unlock()
	return value

func build(seed_value: int, region: Vector3i, region_size: float, minimum: float,
		maximum: float, capacity: int, chunk_count: int) -> Dictionary:
	var started := Time.get_ticks_usec()
	var anchor := Vector3(region) * region_size
	var rng := RandomNumberGenerator.new()
	rng.seed = SectorManager.get_sector_seed(seed_value, region)
	var positions := PackedVector3Array()
	var seeds := PackedInt32Array()
	positions.resize(capacity)
	seeds.resize(capacity)
	var buffers: Array[PackedFloat32Array] = []
	var used: Dictionary = {}
	var index := 0
	for c in range(chunk_count):
		var count := capacity / chunk_count + (1 if c < capacity % chunk_count else 0)
		var buffer := PackedFloat32Array()
		buffer.resize(count * 20)
		for i in range(count):
			if i % 64 == 0 and cancelled():
				return {}
			var coord: Vector3i
			while true:
				var theta := rng.randf_range(0.0, TAU)
				var z := rng.randf_range(-1.0, 1.0)
				var radial := sqrt(maxf(0.0, 1.0 - z * z))
				var direction := Vector3(radial * cos(theta), z, radial * sin(theta))
				# A restrained galactic disk, aligned with the sky's dust band.
				if maximum > 3000.0 and rng.randf() < 0.65:
					direction.y *= 0.22
					direction = direction.normalized().rotated(Vector3.RIGHT, -0.35)
				var distance := lerpf(minimum, maximum, pow(rng.randf(), 0.7))
				coord = SectorManager.get_sector_coord((anchor + direction * distance) * LY)
				if not used.has(coord):
					break
			used[coord] = true
			var star := SectorManager.generate_single_star(seed_value, coord, 0)
			var position := Vector3(star.stellar_x, star.stellar_y, star.stellar_z) / LY
			positions[index] = position
			seeds[index] = star.system_seed
			var local := position - anchor
			# Many faint points, a few bright stars; colour belongs to the star,
			# so it doesn't change when the same star is sampled in another region.
			var appearance := RandomNumberGenerator.new()
			appearance.seed = star.system_seed
			var prominence := pow(appearance.randf(), 5.0)
			# Yıldızın kendi özgün spektral rengi (Mavi, Turuncu, Kırmızı, Sarı, Beyaz)
			var tint := star.base_color.lerp(Color.WHITE, 0.12)
			var brightness := (0.35 + prominence * 2.2) * clampf(sqrt(star.luminosity), 0.6, 1.4)
			var offset := i * 20
			# Row-major 3x4 identity, RGBA colour, RGBA custom data.
			buffer[offset] = 1.0
			buffer[offset + 5] = 1.0
			buffer[offset + 10] = 1.0
			buffer[offset + 12] = tint.r * brightness
			buffer[offset + 13] = tint.g * brightness
			buffer[offset + 14] = tint.b * brightness
			buffer[offset + 15] = 1.0
			buffer[offset + 16] = local.x
			buffer[offset + 17] = local.y
			buffer[offset + 18] = local.z
			buffer[offset + 19] = 0.65 + prominence * 1.2
			index += 1
		buffers.append(buffer)
	return {"region": region, "anchor": anchor, "positions": positions,
		"seeds": seeds, "buffers": buffers, "generation_usec": Time.get_ticks_usec() - started}
