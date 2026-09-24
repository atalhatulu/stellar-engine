class_name TargetSelectionController
extends RefCounted

const RESET_VALUES := {
	"current_target_index": -1,
	"targeted_star_data": null,
	"selected_star": null,
	"selected_planet": null,
	"selected_black_hole": false,
	"selected_extragalactic_galaxy": null,
	"is_focusing_target": false,
	"focus_target_body": null,
	"focus_target_star": null,
	"focus_time": 0.0,
	"is_autopilot_active": false,
	"is_interstellar_autopilot": false,
	"is_hyper_autopilot": false,
	"is_interstellar_hyper_boost": false,
	"autopilot_target_body": null,
	"is_landing_autopilot": false,
	"followed_body": null,
}

static func clear(host: Node) -> void:
	if host == null:
		return
	var available := {}
	for property in host.get_property_list():
		available[property.name] = true
	for property_name in RESET_VALUES:
		if available.has(property_name):
			host.set(property_name, RESET_VALUES[property_name])
	if available.has("star_visual_pool"):
		var pool = host.get("star_visual_pool")
		if pool != null:
			pool.pinned_star_data = null
	for control_name in ["target_reticle", "target_tag_label"]:
		if available.has(control_name):
			var control = host.get(control_name)
			if control is CanvasItem:
				control.visible = false

static func has_selection(host: Node) -> bool:
	if host == null:
		return false
	var available := {}
	for property in host.get_property_list():
		available[property.name] = true
	if available.has("current_target_index") and int(host.get("current_target_index")) >= 0:
		return true
	for property_name in ["targeted_star_data", "selected_star", "selected_planet", "selected_extragalactic_galaxy"]:
		if available.has(property_name) and host.get(property_name) != null:
			return true
	return available.has("selected_black_hole") and host.get("selected_black_hole") == true
