extends Node3D
const Design = preload("res://scripts/rendering/spacecraft_design.gd")
var body_root: Node3D
var arms: Array[Node3D] = []
var jets: Array[MeshInstance3D] = []
var _phase := 0.0

func _ready() -> void:
	body_root = Node3D.new()
	add_child(body_root)
	var fabric := Design.material(Color(0.65,0.69,0.70),0.1,0.85)
	var joints := Design.material(Color(0.04,0.06,0.08),0.1,0.8)
	var visor := Design.material(Color(0.035,0.09,0.13),0.8,0.14)
	var badge := Design.material(Color(0.95,0.42,0.12),0.1,0.5)
	var glow := Design.material(Color(0.18,0.7,1.0),0,0.5,1.6)
	var torso := CapsuleMesh.new()
	torso.radius = 0.26
	torso.height = 0.7
	Design.mesh(body_root,torso,Vector3.ZERO,fabric)
	Design.box(body_root,Vector3(0,0.02,0.24),Vector3(0.43,0.56,0.22),joints)
	Design.box(body_root,Vector3(0,0.10,-0.255),Vector3(0.3,0.23,0.06),joints)
	Design.box(body_root,Vector3(0,0.10,-0.29),Vector3(0.20,0.035,0.02),glow)
	var helmet := SphereMesh.new()
	helmet.radius = 0.255
	helmet.height = 0.51
	Design.mesh(body_root,helmet,Vector3(0,0.54,0),fabric)
	var face := Design.mesh(body_root,helmet,Vector3(0,0.55,-0.13),visor)
	face.scale = Vector3(0.86,0.64,0.68)
	for side in [-1.0,1.0]:
		var arm := Node3D.new()
		arm.position = Vector3(side*0.28,0.2,0)
		body_root.add_child(arm)
		arms.append(arm)
		Design.beam(arm,Vector3.ZERO,Vector3(side*0.08,-0.35,-0.08),0.09,fabric)
		Design.beam(arm,Vector3(side*0.08,-0.35,-0.08),Vector3(side*0.12,-0.5,-0.3),0.075,joints)
		Design.box(arm,Vector3(side*0.12,-0.51,-0.34),Vector3(0.13,0.13,0.2),fabric)
		Design.beam(body_root,Vector3(side*0.13,-0.26,0),Vector3(side*0.18,-0.78,0.04),0.115,fabric)
		Design.box(body_root,Vector3(side*0.18,-0.88,-0.07),Vector3(0.21,0.19,0.36),joints)
		Design.box(body_root,Vector3(side*0.21,0.2,-0.12),Vector3(0.06,0.08,0.12),badge)
		var jet := Design.cylinder(body_root,Vector3(side*0.17,-0.37,0.27),0.035,0.22,glow)
		jets.append(jet)

func animate(delta: float, thrust: bool, boosting: bool) -> void:
	_phase += delta
	for i in range(arms.size()):
		arms[i].rotation.z = (0.12 if i == 0 else -0.12) + sin(_phase*0.8+i)*0.035
		arms[i].rotation.x = lerpf(arms[i].rotation.x, -0.25 if thrust else 0.0, 1.0-exp(-4.0*delta))
	for jet in jets:
		jet.visible = thrust
		jet.scale.y = (2.2 if boosting else 1.0) * (1.0+sin(_phase*28.0)*0.1)
