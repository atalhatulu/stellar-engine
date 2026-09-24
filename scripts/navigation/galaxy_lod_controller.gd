class_name GalaxyLodController
extends RefCounted

enum State {
	FAR_IMPOSTOR,
	LOADING_STARS,
	NEAR_STAR_FIELD
}

const LOAD_ENTER_RADIUS := 5.0
const LOAD_EXIT_RADIUS := 5.5
const STAR_ENTER_RADIUS := 3.0
const STAR_EXIT_RADIUS := 4.0

var active_galaxy_id: String = ""
var state: State = State.FAR_IMPOSTOR
var impostor_opacity: float = 1.0
var star_field_visible: bool = false
var wants_star_data: bool = false

func set_active(galaxy: Galaxy) -> void:
	active_galaxy_id = galaxy.unique_id if galaxy != null else ""
	state = State.FAR_IMPOSTOR
	impostor_opacity = 1.0
	star_field_visible = false
	wants_star_data = false

func update(distance_ly: float, radius_ly: float, stars_ready: bool) -> void:
	var radius := maxf(radius_ly, 1.0)
	var ratio := distance_ly / radius

	match state:
		State.FAR_IMPOSTOR:
			if ratio <= LOAD_ENTER_RADIUS:
				state = State.LOADING_STARS
		State.LOADING_STARS:
			if ratio >= LOAD_EXIT_RADIUS:
				state = State.FAR_IMPOSTOR
			elif stars_ready and ratio <= STAR_ENTER_RADIUS:
				state = State.NEAR_STAR_FIELD
		State.NEAR_STAR_FIELD:
			if ratio >= STAR_EXIT_RADIUS:
				state = State.FAR_IMPOSTOR

	wants_star_data = state != State.FAR_IMPOSTOR
	star_field_visible = state == State.NEAR_STAR_FIELD and stars_ready
	if star_field_visible:
		# main_star davranışı: detaylı sistem aktifken aynı nesnenin uzak havuz
		# temsili tamamen çıkarılır. Yakında 2D kalıntı bırakılmaz.
		impostor_opacity = 0.0
	else:
		impostor_opacity = 1.0

func is_far() -> bool:
	return state == State.FAR_IMPOSTOR
