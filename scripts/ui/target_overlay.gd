class_name TargetOverlay
extends Control

var reticle: Panel
var target_label: Label
var fps_label: Label

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_reticle()
	_build_target_label()
	_build_fps_label()

func _process(_delta: float) -> void:
	fps_label.text = "FPS: %d" % Engine.get_frames_per_second()

func set_target_visible(value: bool) -> void:
	reticle.visible = value
	target_label.visible = value

func _build_reticle() -> void:
	reticle = Panel.new()
	reticle.name = "TargetReticle"
	reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	reticle.size = Vector2(36, 36)
	reticle.pivot_offset = Vector2(18, 18)
	reticle.visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color.TRANSPARENT
	style.set_border_width_all(2)
	style.border_color = Color(0.0, 0.85, 1.0, 0.85)
	style.set_corner_radius_all(6)
	style.shadow_color = Color(0.0, 0.85, 1.0, 0.35)
	style.shadow_size = 4
	reticle.add_theme_stylebox_override("panel", style)
	add_child(reticle)

func _build_target_label() -> void:
	target_label = Label.new()
	target_label.name = "TargetTagLabel"
	target_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	target_label.custom_minimum_size = Vector2(320, 50)
	target_label.add_theme_color_override("font_color", Color(0.2, 0.95, 1.0))
	target_label.add_theme_font_size_override("font_size", 11)
	if ResourceLoader.exists("res://assets/fonts/DejaVuSansMono-Bold.ttf"):
		target_label.add_theme_font_override("font", load("res://assets/fonts/DejaVuSansMono-Bold.ttf"))
	target_label.visible = false
	add_child(target_label)

func _build_fps_label() -> void:
	fps_label = Label.new()
	fps_label.name = "FPSLabel"
	fps_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	fps_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	fps_label.position = Vector2(-120, 20)
	fps_label.size = Vector2(100, 30)
	fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	fps_label.modulate = Color(0.0, 0.8, 1.0, 0.8)
	add_child(fps_label)
