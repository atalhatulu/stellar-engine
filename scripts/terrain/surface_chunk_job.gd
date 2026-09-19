class_name SurfaceChunkJob
extends RefCounted
const SIZE := 128.0
var mutex := Mutex.new()
var stopped := false
func cancel() -> void:
	mutex.lock()
	stopped = true
	mutex.unlock()
func cancelled() -> bool:
	mutex.lock()
	var value := stopped
	mutex.unlock()
	return value

func build(profile: PlanetSurfaceProfile, direction: Vector3, coord: Vector2i, divisions: int, edge_steps: Vector4i) -> Dictionary:
	var started := Time.get_ticks_usec()
	var sampler := PlanetHeightSampler.new(profile,direction)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var uvs := PackedVector2Array()
	var step := SIZE / divisions
	for iz in range(divisions+1):
		if cancelled(): return {}
		for ix in range(divisions+1):
			var x := float(coord.x)*SIZE + ix*step
			var z := float(coord.y)*SIZE + iz*step
			var h := sampler.height_local(x,z)
			# Snap a fine boundary to the coarser neighbour's actual line segments.
			if ix == 0 or ix == divisions:
				var spacing := float(edge_steps.x if ix == 0 else edge_steps.y)
				if spacing > step:
					var low: float = floorf(z / spacing) * spacing
					h = lerpf(sampler.height_local(x, low), sampler.height_local(x, low + spacing), (z - low) / spacing)
			if iz == 0 or iz == divisions:
				var spacing := float(edge_steps.z if iz == 0 else edge_steps.w)
				if spacing > step:
					var low: float = floorf(x / spacing) * spacing
					h = lerpf(sampler.height_local(low, z), sampler.height_local(low + spacing, z), (x - low) / spacing)
			vertices.append(Vector3(ix*step,h,iz*step))
			normals.append(sampler.normal_local(x,z))
			uvs.append(Vector2(float(ix) / float(divisions), float(iz) / float(divisions)))
	for iz in range(divisions):
		for ix in range(divisions):
			var a := iz*(divisions+1)+ix
			# In Godot, CCW facing +Y: (i0, i2, i1) and (i1, i2, i3)
			indices.append_array(PackedInt32Array([a, a+divisions+1, a+1, a+1, a+divisions+1, a+divisions+2]))
	var faces := PackedVector3Array()
	if divisions == 64:
		for index in indices: faces.append(vertices[index])
	return {"vertices":vertices,"normals":normals,"uvs":uvs,"indices":indices,"faces":faces,"coord":coord,"divisions":divisions,"edges":edge_steps,"usec":Time.get_ticks_usec()-started}
