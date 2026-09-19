extends RefCounted

# Procedural, hollow exploration craft. All coordinates are metres in ship space.
# The centre aisle stays open from the pilot seat to the aft airlock.
static func material(color: Color, metal: float = 0.0, rough: float = 0.6, emission: float = 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metal
	mat.roughness = rough
	if emission > 0.0:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = emission
	return mat

static func mesh(parent: Node3D, shape: Mesh, pos: Vector3, mat: Material, title: String = "") -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = shape
	node.position = pos
	node.material_override = mat
	if title != "": node.name = title
	parent.add_child(node)
	return node

static func box(parent: Node3D, pos: Vector3, size: Vector3, mat: Material, title: String = "") -> MeshInstance3D:
	var shape := BoxMesh.new()
	shape.size = size
	return mesh(parent, shape, pos, mat, title)

static func cylinder(parent: Node3D, pos: Vector3, radius: float, length: float, mat: Material, axis_z: bool = false) -> MeshInstance3D:
	var shape := CylinderMesh.new()
	shape.top_radius = radius
	shape.bottom_radius = radius
	shape.height = length
	shape.radial_segments = 32
	var node := mesh(parent, shape, pos, mat)
	if axis_z: node.rotation.x = PI * 0.5
	return node

static func beam(parent: Node3D, a: Vector3, b: Vector3, radius: float, mat: Material) -> MeshInstance3D:
	var node := cylinder(parent, (a + b) * 0.5, radius, a.distance_to(b), mat)
	node.quaternion = Quaternion(Vector3.UP, (b - a).normalized())
	return node

static func slab(parent: Node3D, outline: PackedVector2Array, y: float, depth: float, mat: Material) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var center := Vector2.ZERO
	for point in outline: center += point
	center /= outline.size()
	for i in range(outline.size()):
		var a := outline[i]
		var b := outline[(i + 1) % outline.size()]
		var lo_a := Vector3(a.x, y - depth * 0.5, a.y)
		var lo_b := Vector3(b.x, y - depth * 0.5, b.y)
		var hi_a := Vector3(a.x, y + depth * 0.5, a.y)
		var hi_b := Vector3(b.x, y + depth * 0.5, b.y)
		for point in [Vector3(center.x, y + depth * 0.5, center.y), hi_b, hi_a,
			Vector3(center.x, y - depth * 0.5, center.y), lo_a, lo_b,
			lo_a, hi_a, hi_b, lo_a, hi_b, lo_b]:
			st.add_vertex(point)
	st.generate_normals()
	var mat_double := mat.duplicate() as StandardMaterial3D
	mat_double.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mesh(parent, st.commit(), Vector3.ZERO, mat_double)

static func label(parent: Node3D, text: String, pos: Vector3, size: int = 28, color: Color = Color(0.65, 0.8, 0.87)) -> Label3D:
	var node := Label3D.new()
	node.text = text
	node.font_size = size
	node.pixel_size = 0.003
	node.outline_size = 0
	node.modulate = color
	node.position = pos
	parent.add_child(node)
	return node

static func build(sc: Node3D) -> void:
	sc.hull_mat = material(Color(0.055, 0.075, 0.095), 0.65, 0.38)
	sc.armor_mat = material(Color(0.65, 0.69, 0.70), 0.45, 0.42)
	sc.engine_mat = material(Color(0.025, 0.032, 0.045), 0.7, 0.35)
	sc.interior_wall_mat = material(Color(0.13, 0.17, 0.20), 0.25, 0.65)
	sc.floor_mat = material(Color(0.055, 0.065, 0.075), 0.3, 0.85)
	sc.seat_mat = material(Color(0.045, 0.052, 0.06), 0.0, 0.95)
	sc.glow_cyan_mat = material(Color(0.1, 0.7, 0.85), 0.0, 0.4, 1.6)
	sc.glow_orange_mat = material(Color(0.9, 0.38, 0.085), 0.0, 0.4, 1.3)
	sc.flame_core_mat = material(Color(0.7, 0.88, 1.0), 0.0, 0.3, 3.0)
	sc.flame_outer_mat = material(Color(0.07, 0.32, 0.75, 0.4), 0.0, 0.3, 2.0)
	sc.flame_outer_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sc.flame_outer_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sc.airlock_status_mat = material(Color(0.1, 0.85, 0.6), 0.0, 0.4, 1.0)
	sc.airlock_hazard_mat = material(Color(0.85, 0.5, 0.12), 0.2)
	sc.steam_vent_mat = material(Color(0.6, 0.75, 0.85, 0.15), 0.0, 1.0)
	sc.glass_mat = material(Color(0.1, 0.25, 0.32, 0.10), 0.05, 0.1)
	sc.glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sc.glass_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	sc.ship_root = Node3D.new()
	sc.ship_root.name = "AsterScout"
	sc.add_child(sc.ship_root)
	sc.cabin_root = Node3D.new()
	sc.cabin_root.name = "HabitableCabin"
	sc.ship_root.add_child(sc.cabin_root)
	var hull: Node3D = sc.ship_root
	var cabin: Node3D = sc.cabin_root
	var amber := material(Color(0.72, 0.31, 0.09), 0.25, 0.55)
	# Faceted deck and nose; no solid box enclosing the walkable volume.
	slab(hull, PackedVector2Array([Vector2(-0.8,-4.8),Vector2(0.8,-4.8),Vector2(1.45,-2.3),Vector2(1.45,2.8),Vector2(-1.45,2.8),Vector2(-1.45,-2.3)]), -0.12, 0.35, sc.hull_mat)
	slab(hull, PackedVector2Array([Vector2(-0.5,-4.9),Vector2(0.5,-4.9),Vector2(1.15,-3.4),Vector2(-1.15,-3.4)]), 0.25, 0.4, sc.armor_mat)
	box(cabin, Vector3(0,0.03,-0.5), Vector3(2.4,0.08,6.3), sc.floor_mat)
	box(hull, Vector3(0,2.1,0.55), Vector3(2.7,0.2,4.2), sc.armor_mat)
	box(hull, Vector3(0,2.24,0.8), Vector3(0.7,0.08,3.3), sc.hull_mat)
	for side in [-1.0,1.0]:
		# Double walls with structural ribs and service panels.
		box(hull, Vector3(side*1.32,1.0,0.2), Vector3(0.18,2.0,5.0), sc.hull_mat)
		for z in [-1.7,-0.65,0.4,1.45,2.35]:
			box(hull, Vector3(side*1.43,0.75,z), Vector3(0.10,1.35,0.88), sc.armor_mat)
			box(cabin, Vector3(side*1.20,1.02,z), Vector3(0.055,1.9,0.09), sc.engine_mat)
			box(cabin, Vector3(side*1.21,1.3,z-0.2), Vector3(0.025,0.55,0.55), sc.interior_wall_mat)
		box(hull, Vector3(side*1.49,0.15,0.0), Vector3(0.03,0.12,4.8), amber)
		box(cabin, Vector3(side*1.05,0.095,-0.45), Vector3(0.022,0.015,5.8), sc.glow_cyan_mat)
		box(cabin, Vector3(side*0.88,1.97,0.4), Vector3(0.035,0.02,3.5), sc.glow_cyan_mat)
		# Swept structural outriggers and radiators.
		var outline := PackedVector2Array([Vector2(side*1.3,-1.8),Vector2(side*3.6,0.3),Vector2(side*3.2,2.7),Vector2(side*1.3,1.9)])
		slab(hull, outline, 0.32, 0.16, sc.armor_mat)
		for z in [0.4,0.7,1.0,1.3,1.6]:
			box(hull, Vector3(side*2.6,0.43,z), Vector3(0.8,0.03,0.12), sc.engine_mat)
		beam(hull, Vector3(side*1.3,1.4,1.7), Vector3(side*2.65,0.6,1.5), 0.1, sc.hull_mat)
		# Angled cockpit pillars, clear view between them.
		beam(hull, Vector3(side*1.24,0.3,-3.6), Vector3(side*1.20,1.95,-2.45), 0.055, sc.armor_mat)
		beam(hull, Vector3(side*1.20,1.95,-2.45), Vector3(side*1.25,2.05,-1.5), 0.06, sc.hull_mat)
		box(cabin, Vector3(side*1.01,0.7,1.0), Vector3(0.32,1.2,1.15), sc.interior_wall_mat)
		box(cabin, Vector3(side*0.82,0.9,1.0), Vector3(0.018,0.035,0.75), sc.glow_cyan_mat)
		# Landing struts are grouped for deployment animation.
	sc.landing_gear_root = Node3D.new()
	hull.add_child(sc.landing_gear_root)
	for x in [-1.05,1.05]:
		for z in [-2.1,1.9]:
			beam(sc.landing_gear_root,Vector3(x,-0.2,z),Vector3(x*1.35,-0.75,z+0.15),0.065,sc.armor_mat)
			box(sc.landing_gear_root,Vector3(x*1.35,-0.79,z+0.15),Vector3(0.45,0.10,0.65),sc.engine_mat)
	# Panoramic windscreen, pitched forward and framed instead of a glass sphere.
	var pane := QuadMesh.new()
	pane.size = Vector2(2.37,1.85)
	var windscreen := mesh(hull,pane,Vector3(0,1.15,-3.02),sc.glass_mat)
	windscreen.rotation.x = deg_to_rad(-34)
	beam(hull,Vector3(-1.24,0.35,-3.58),Vector3(1.24,0.35,-3.58),0.06,sc.hull_mat)
	beam(hull,Vector3(-1.2,1.94,-2.45),Vector3(1.2,1.94,-2.45),0.06,sc.hull_mat)
	# Upholstered pilot seat, open side passage, three readable instrument screens.
	box(cabin,Vector3(0,0.25,-2.12),Vector3(0.58,0.35,0.62),sc.engine_mat)
	box(cabin,Vector3(0,0.48,-2.12),Vector3(0.60,0.14,0.63),sc.seat_mat)
	box(cabin,Vector3(0,0.85,-1.78),Vector3(0.60,0.72,0.13),sc.seat_mat)
	for side in [-1.0,1.0]:
		box(cabin,Vector3(side*0.40,0.7,-2.1),Vector3(0.14,0.09,0.5),sc.hull_mat)
		beam(cabin,Vector3(side*0.40,0.74,-2.28),Vector3(side*0.4,0.9,-2.30),0.035,sc.engine_mat)
	box(cabin,Vector3(0,0.57,-2.95),Vector3(2.05,0.35,0.50),sc.hull_mat)
	for i in range(3):
		var x := float(i-1)*0.64
		box(cabin,Vector3(x,0.88,-2.85),Vector3(0.61,0.36,0.07),sc.engine_mat)
		var screen := QuadMesh.new()
		screen.size = Vector2(0.55,0.29)
		var screen_mat := ShaderMaterial.new()
		screen_mat.shader = load("res://shaders/cockpit_display.gdshader")
		screen_mat.set_shader_parameter("panel_kind",0.0 if i == 1 else 1.0)
		mesh(cabin,screen,Vector3(x,0.88,-2.805),screen_mat)
		sc.instrument_materials.append(screen_mat)
		label(cabin,["NAV / COURSE","FLIGHT CONTROL","POWER / RCS"][i],Vector3(x,1.10,-2.79),16)
	# A wall-mounted reactor leaves the centre aisle clear.
	cylinder(cabin,Vector3(-1.02,0.9,0.0),0.15,1.1,sc.engine_mat)
	sc.reactor_core_mesh = cylinder(cabin,Vector3(-0.96,0.9,0.0),0.085,0.7,sc.glow_orange_mat)
	label(cabin,"ASTER  /  07",Vector3(0,1.85,1.42),25)
	label(cabin,"AIRLOCK",Vector3(0,1.64,2.52),24)
	for z in [-0.9,-0.5,-0.1,0.3,0.7,1.1,1.5,1.9,2.3]:
		box(cabin,Vector3(0,0.081,z),Vector3(1.55,0.008,0.025),sc.engine_mat)
	# Aft frame and hinged ramp. Open door has a physically clear exit.
	for side in [-1.0,1.0]:
		box(cabin,Vector3(side*0.98,1.0,2.65),Vector3(0.35,2.0,0.18),sc.hull_mat)
	box(cabin,Vector3(0,1.98,2.65),Vector3(2.2,0.18,0.2),sc.hull_mat)
	sc.airlock_hatch_pivot = Node3D.new()
	sc.airlock_hatch_pivot.position = Vector3(0,0.08,2.65)
	cabin.add_child(sc.airlock_hatch_pivot)
	sc.airlock_hatch_mesh = box(sc.airlock_hatch_pivot,Vector3(0,0.88,0),Vector3(1.65,1.76,0.10),sc.armor_mat)
	for y in range(9):
		box(sc.airlock_hatch_pivot,Vector3(0,0.1+y*0.18,-0.058),Vector3(1.42,0.035,0.018),sc.engine_mat)
	for side in [-1.0,1.0]:
		box(sc.airlock_hatch_pivot,Vector3(side*0.73,0.88,-0.065),Vector3(0.04,1.68,0.02),sc.airlock_hazard_mat)
	sc.airlock_status_mesh = box(cabin,Vector3(0,1.82,2.51),Vector3(0.4,0.055,0.03),sc.airlock_status_mat)
	# Twin ducted engines, recessed white-hot cores and tapered exhaust.
	sc.engines_root = Node3D.new()
	hull.add_child(sc.engines_root)
	for side in [-1.0,1.0]:
		var mount := Node3D.new()
		mount.position = Vector3(side*2.65,0.50,1.4)
		sc.engines_root.add_child(mount)
		cylinder(mount,Vector3(0,0,-0.15),0.47,2.8,sc.hull_mat,true)
		for z in [-1.35,0.2,0.8,1.18]:
			cylinder(mount,Vector3(0,0,z),0.50,0.12,sc.armor_mat,true)
		cylinder(mount,Vector3(0,0,1.3),0.40,0.10,sc.engine_mat,true)
		cylinder(mount,Vector3(0,0,1.36),0.30,0.02,sc.flame_core_mat,true)
		var exhaust := CylinderMesh.new()
		exhaust.top_radius = 0.025
		exhaust.bottom_radius = 0.30
		exhaust.height = 1.5
		var flame := mesh(mount,exhaust,Vector3(0,0,2.05),sc.flame_outer_mat)
		flame.rotation.x = PI*0.5
		var core := mesh(mount,exhaust,Vector3(0,0,1.9),sc.flame_core_mat)
		core.rotation.x = PI*0.5
		if side < 0:
			sc.left_thruster_flame = flame
			sc.left_inner_flame = core
		else:
			sc.right_thruster_flame = flame
			sc.right_inner_flame = core
	# Low-energy local lights: cabin details remain readable without glowing walls.
	sc.cabin_ambient_light = light(cabin,Vector3(0,1.8,0),Color(0.70,0.85,1.0),0.7,4.0)
	sc.cockpit_console_light = light(cabin,Vector3(0,1.2,-2.6),Color(0.15,0.65,1.0),0.4,2.2)
	sc.reactor_light = light(cabin,Vector3(-0.8,1,0),Color(1.0,0.45,0.15),0.3,1.4)
	sc.airlock_status_light = light(cabin,Vector3(0,1.7,2.4),Color(0.1,0.8,0.6),0.25,1.2)
	sc.thruster_light = light(hull,Vector3(0,0.5,3.0),Color(0.15,0.5,1.0),1.0,5.0)

static func light(parent: Node3D, pos: Vector3, color: Color, energy: float, radius: float) -> OmniLight3D:
	var node := OmniLight3D.new()
	node.position = pos
	node.light_color = color
	node.light_energy = energy
	node.omni_range = radius
	parent.add_child(node)
	return node
