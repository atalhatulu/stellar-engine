class_name TargetSelectionController
extends RefCounted

const LIGHT_YEAR: float = 9460730472580800.0
const ONE_AU: float = 149597870700.0
const MAX_STAR_DISTANCE_PRIMARY_LY: float = 300.0
const MAX_STAR_DISTANCE_SECONDARY_LY: float = 180.0

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
			if host.has_method("get_player_galactic_position") and host.get("camera") != null and host.get("sector_manager") != null:
				var cam = host.get("camera")
				var cam_fwd = -cam.transform.basis.z if cam != null else Vector3.FORWARD
				var active_id = str(host.get("active_star_unique_id")) if host.get("active_star_unique_id") != null else ""
				pool.rebind(host.get("sector_manager"), host.get_player_galactic_position(), cam_fwd, active_id)
	if available.has("hud"):
		var hud = host.get("hud")
		if hud != null:
			if hud.has_method("update_hud"):
				hud.update_hud(host)
			if "starfield_card" in hud:
				var card = hud.get("starfield_card")
				if card is CanvasItem:
					card.visible = false
			if "target_card" in hud:
				var card = hud.get("target_card")
				if card is CanvasItem:
					card.visible = false
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

static func check_distance_limit(host: Node) -> bool:
	if host == null:
		return false
		
	# 1. Galaktik Yıldız Seçimi Kontrolü (StarData)
	if host.get("targeted_star_data") != null:
		if bool(host.get("is_interstellar_autopilot")):
			return false
		var star_data = host.get("targeted_star_data")
		var gal_pos: Vector3 = host.get_player_galactic_position() if host.has_method("get_player_galactic_position") else Vector3.ZERO
		var star_pos = Vector3(star_data.stellar_x, star_data.stellar_y, star_data.stellar_z)
		var dist_ly = (star_pos - gal_pos).length() / LIGHT_YEAR
		var is_primary = str(star_data.unique_id).ends_with("_S1")
		var max_reach_ly = MAX_STAR_DISTANCE_PRIMARY_LY if is_primary else MAX_STAR_DISTANCE_SECONDARY_LY
		if dist_ly > max_reach_ly:
			clear(host)
			return true

	# 2. Aktif Sistem İçi Cisim Seçimi Kontrolü (Gezegen, Ay, Yıldız)
	var target_idx = int(host.get("current_target_index")) if host.get("current_target_index") != null else -1
	var universe = host.get("universe") as Array
	if universe != null and target_idx >= 0 and target_idx < universe.size():
		if bool(host.get("is_autopilot_active")) or bool(host.get("is_landing_autopilot")):
			return false
		var target_body = universe[target_idx]
		if target_body != null:
			var active_star = host.get("active_star")
			var v_player_pos: Vector3 = host.get("virtual_player_position") if host.get("virtual_player_position") != null else Vector3.ZERO
			var body_pos = target_body.get_absolute_position(active_star) if target_body.has_method("get_absolute_position") else target_body.position
			var dist_to_player = (body_pos - v_player_pos).length()
			var sys_diam: float = active_star.system_diameter if (active_star != null and "system_diameter" in active_star) else 0.0
			var max_body_dist = maxf(sys_diam * 1.5, 100.0 * ONE_AU)
			if dist_to_player > max_body_dist:
				clear(host)
				return true
				
	return false
