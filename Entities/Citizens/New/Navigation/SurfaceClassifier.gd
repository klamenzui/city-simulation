class_name SurfaceClassifier
extends RefCounted

## Stateless classifier for navigation surfaces.
##
## Input: any `Node` (typically from a physics query collider or surface ray).
## Output: one of "pedestrian" / "road" / "crosswalk" / "unknown".
##
## Keep all name/group heuristics here — so when a new asset type is added the
## whole citizen navigation stack learns it in one place, not scattered across
## perception + local grid + jump.

const KIND_UNKNOWN: String = "unknown"
const KIND_PEDESTRIAN: String = "pedestrian"
const KIND_ROAD: String = "road"
const KIND_CROSSWALK: String = "crosswalk"


## Classifies a surface probe's raw hit dictionary.
static func classify_hit(hit: Dictionary) -> String:
	if hit.is_empty():
		return KIND_UNKNOWN
	var collider: Variant = hit.get("collider", null)
	if collider is Node:
		return classify_node(collider as Node)
	return KIND_UNKNOWN


static func _is_park_walkable_name(name_lower: String, path_lower: String) -> bool:
	return name_lower.begins_with("park_road") or path_lower.contains("/park_road_")


static func _is_park_blocker_name(name_lower: String, path_lower: String) -> bool:
	return name_lower.begins_with("park_wall") or path_lower.contains("/park_wall_")


## Walks the parent chain and returns the first match.
##
## Priority order matters — see inline comments.  In particular "pedestrian"
## must win over "crosswalk" for assets like `Road_straight_crossing` whose
## root name would otherwise false-match the crosswalk keyword.
static func classify_node(node: Node) -> String:
	var current: Node = node
	while current != null:
		var current_path := ""
		if current.is_inside_tree():
			current_path = str(current.get_path()).to_lower()
		var current_name := current.name.to_lower()

		# Priority 1: /only_people_nav/ path — authoritative pedestrian signal.
		# Wins over the `crossing` substring that shows up in road asset names.
		if current_path.contains("/only_people_nav/"):
			return KIND_PEDESTRIAN

		# Priority 2: explicit walkable tags and named park floor pieces.
		if current.is_in_group("walkable_surface"):
			return KIND_PEDESTRIAN
		if _is_park_walkable_name(current_name, current_path):
			return KIND_PEDESTRIAN
		if _is_park_blocker_name(current_name, current_path):
			return KIND_UNKNOWN

		# Priority 3: zebra crossings — matched only after pedestrian check
		# so sidewalks attached to a crossing-road asset are not misread.
		if current_path.contains("/road_straight_crossing/") \
				or current_name.contains("crosswalk") \
				or current_name.contains("crossing"):
			return KIND_CROSSWALK

		# Priority 4: road.
		if current.is_in_group("road_group"):
			return KIND_ROAD
		if current_path.contains("/only_transport/"):
			return KIND_ROAD

		current = current.get_parent()

	return KIND_UNKNOWN


## Walkable test for the local-A* physics probe (sphere intersect).
## Determines whether a hit collider should BLOCK a cell.
##
## Returns true = walkable through it (NOT blocking).
##
## Priority chain mirrors classify_node but answers a narrower question: can
## the ankle sphere pass this collider?  Park walls must block, park sidewalks
## must not — both live under a "parks" group, so the group check alone cannot
## decide; we need the explicit "walkable_surface" tag.
static func is_walkable_probe_collider(collider: Variant) -> bool:
	if not (collider is Node):
		return false
	var node := collider as Node

	# Priority 1: explicit walkable tags and named park floor pieces always win.
	var current: Node = node
	while current != null:
		var current_name := current.name.to_lower()
		var current_path := ""
		if current.is_inside_tree():
			current_path = str(current.get_path()).to_lower()
		if current.is_in_group("walkable_surface"):
			return true
		if _is_park_walkable_name(current_name, current_path):
			return true
		if _is_park_blocker_name(current_name, current_path):
			return false
		current = current.get_parent()

	# Priority 2: buildings-grouped ancestors always block — walls, props, fixtures.
	current = node
	while current != null:
		if current.is_in_group("buildings"):
			return false
		current = current.get_parent()

	# Priority 3: world-terrain floor — collider's IMMEDIATE parent in group "world".
	# Must NOT walk the chain here — buildings live under world too.
	var owner_parent := node.get_parent()
	if owner_parent == null:
		return false
	if owner_parent.is_in_group("world"):
		return true

	# Priority 4: road-tile sidewalks — owner mesh name starts with road_ AND
	# lives on /only_people_nav/.  The path qualifier prevents car-road meshes
	# on /only_transport/ from being mis-allowed; the direct-owner restriction
	# prevents a hydrant inside a Road_* asset from inheriting walkable.
	var owner_name := owner_parent.name.to_lower()
	var owner_path := ""
	if owner_parent.is_inside_tree():
		owner_path = str(owner_parent.get_path()).to_lower()
	if not owner_path.contains("/only_people_nav/"):
		return false
	if owner_name.begins_with("road_"):
		return true
	if owner_name.contains("crosswalk") or owner_name.contains("crossing"):
		return true
	return false


## Pretty-prints a collider chain for the log (up to 6 levels), including
## node groups in braces:  "Mesh{walkable_surface}->Park{parks,buildings}->..."
static func fmt_collider_chain(node: Node, depth_limit: int = 6) -> String:
	var out := ""
	var current := node
	var depth := 0
	while current != null and depth < depth_limit:
		var groups_str := ""
		for g in current.get_groups():
			if groups_str.is_empty():
				groups_str = "{" + str(g)
			else:
				groups_str += "," + str(g)
		if not groups_str.is_empty():
			groups_str += "}"
		var entry := "%s%s" % [current.name, groups_str]
		if out.is_empty():
			out = entry
		else:
			out += "->" + entry
		current = current.get_parent()
		depth += 1
	return out
