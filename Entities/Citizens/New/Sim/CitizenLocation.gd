class_name CitizenLocation
extends RefCounted

## Indoor/outdoor presence state + building-nav-point resolution.
## Extracted from old `Citizen.gd` lines 1482-1654.
##
## Responsibilities:
##   - Track whether the citizen is currently inside an enclosed building
##     (rest of the time `_inside_building` is null even when standing in an
##     outdoor venue like a park).
##   - Resolve a building's navigation points (entrance/access/spawn/visit)
##     using the citizen's deterministic lane offset for crowd separation.
##
## Does NOT:
##   - Move the citizen (that's the Facade's `enter_building` orchestration).
##   - Toggle visibility/collision (that's the Facade's `_set_interior_presence`).
##   - Touch GOAP/actions/SimLogger.

const _LANE_OFFSETS: Array[float] = [-0.12, -0.04, 0.04, 0.12]

var _inside_building: Building = null


# ----------------------------- state -----------------------------

func is_inside() -> bool:
	return _inside_building != null


func get_inside_building() -> Building:
	return _inside_building


func set_inside_building(b: Building) -> void:
	_inside_building = b


func clear_inside_building() -> void:
	_inside_building = null


# ----------------------------- nav points -----------------------------

## Deterministic per-citizen lateral offset (~ ±12 cm). Two citizens with
## different names take slightly different lanes when approaching the same
## building, reducing pile-up at entrances.
static func get_lane_offset(citizen_name: String) -> float:
	var slot := int(absi(citizen_name.hash())) % _LANE_OFFSETS.size()
	return _LANE_OFFSETS[slot]


## Resolves a building's navigation points for the given citizen.
## `building.get_navigation_points()` is the source of truth — this wrapper
## just supplies the lane offset and the reference position.
##
## `reserved_bench` (optional) lets the caller inject a Park-bench reservation
## without coupling Location to the (not-yet-extracted) bench-reservation
## subsystem.
static func resolve_navigation_points(
		building: Building,
		world: Node,
		citizen_name: String,
		reference_pos: Vector3,
		reserved_bench: Dictionary = {}) -> Dictionary:
	if building == null:
		return {}

	var lane_offset := get_lane_offset(citizen_name)
	var nav_points: Dictionary = {}
	if building.has_method("get_navigation_points"):
		nav_points = building.get_navigation_points(world, lane_offset, reference_pos)
	else:
		var entrance_pos: Vector3 = building.get_entrance_pos()
		nav_points = {
			"entrance": entrance_pos,
			"access": entrance_pos,
			"spawn": entrance_pos,
		}

	# Bench reservation overrides the visit/center points so the citizen
	# walks straight to the bench rather than the building centroid.
	if not reserved_bench.is_empty():
		var bench_pos: Vector3 = reserved_bench.get(
				"position",
				nav_points.get("visit", nav_points.get("center", reference_pos))) as Vector3
		nav_points["visit"] = bench_pos
		nav_points["center"] = bench_pos
		nav_points["bench"] = bench_pos
		nav_points["bench_yaw"] = float(reserved_bench.get("yaw", 0.0))

	return nav_points
