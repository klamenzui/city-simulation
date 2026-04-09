extends RefCounted
class_name CitizenQueryResolver

func resolve_query_world(citizen: Citizen) -> World:
	if citizen == null:
		return null
	if citizen._world_ref != null and is_instance_valid(citizen._world_ref):
		return citizen._world_ref
	citizen._world_ref = null
	return resolve_world_ref_from_tree(citizen)

func resolve_world_ref_from_tree(citizen: Citizen) -> World:
	if citizen == null or not citizen.is_inside_tree():
		return null

	var current := citizen.get_parent()
	while current != null:
		if current is World:
			var parent_world := current as World
			citizen.set_world_ref(parent_world)
			return parent_world
		current = current.get_parent()

	var tree := citizen.get_tree()
	if tree == null:
		return null
	for node in tree.get_nodes_in_group("world"):
		if node is World:
			var grouped_world := node as World
			citizen.set_world_ref(grouped_world)
			return grouped_world
	return null

func find_first_residential_building(citizen: Citizen, from_pos: Vector3 = Vector3.ZERO) -> ResidentialBuilding:
	var query_world := resolve_query_world(citizen)
	if query_world != null:
		if query_world.has_method("find_available_residential_building"):
			return query_world.find_available_residential_building(from_pos)
		return query_world.find_first_residential_building()
	return find_best_tree_residential_building(citizen, from_pos)

func find_nearest_restaurant(citizen: Citizen, from_pos: Vector3, require_open: bool = true) -> Restaurant:
	var query_world := resolve_query_world(citizen)
	if query_world != null:
		if query_world.has_method("find_preferred_restaurant"):
			return query_world.find_preferred_restaurant(from_pos, citizen, require_open, citizen)
		return query_world.find_nearest_restaurant(from_pos, require_open, citizen)
	return find_nearest_tree_building(
		citizen,
		from_pos,
		"buildings",
		func(building: Building) -> bool:
			if building is not Restaurant:
				return false
			return not require_open or building.is_open(-1)
	) as Restaurant

func find_nearest_supermarket(citizen: Citizen, from_pos: Vector3, require_open: bool = true) -> Supermarket:
	var query_world := resolve_query_world(citizen)
	if query_world != null:
		return query_world.find_nearest_supermarket(from_pos, require_open, citizen)
	return find_nearest_tree_building(
		citizen,
		from_pos,
		"buildings",
		func(building: Building) -> bool:
			if building is not Supermarket:
				return false
			return not require_open or building.is_open(-1)
	) as Supermarket

func find_nearest_shop(citizen: Citizen, from_pos: Vector3, require_open: bool = true) -> Shop:
	var query_world := resolve_query_world(citizen)
	if query_world != null:
		return query_world.find_nearest_shop(from_pos, require_open, citizen)
	return find_nearest_tree_building(
		citizen,
		from_pos,
		"buildings",
		func(building: Building) -> bool:
			if building is not Shop or building is Supermarket:
				return false
			return not require_open or building.is_open(-1)
	) as Shop

func find_nearest_cinema(citizen: Citizen, from_pos: Vector3, require_open: bool = true) -> Cinema:
	var query_world := resolve_query_world(citizen)
	if query_world != null:
		return query_world.find_nearest_cinema(from_pos, require_open, citizen)
	return find_nearest_tree_building(
		citizen,
		from_pos,
		"buildings",
		func(building: Building) -> bool:
			if building is not Cinema:
				return false
			return not require_open or building.is_open(-1)
	) as Cinema

func find_nearest_university(citizen: Citizen, from_pos: Vector3, require_open: bool = true) -> University:
	var query_world := resolve_query_world(citizen)
	if query_world != null:
		return query_world.find_nearest_university(from_pos, require_open, citizen)
	return find_nearest_tree_building(
		citizen,
		from_pos,
		"buildings",
		func(building: Building) -> bool:
			if building is not University:
				return false
			return not require_open or building.is_open(-1)
	) as University

func find_nearest_park(citizen: Citizen, from_pos: Vector3) -> Building:
	var query_world := resolve_query_world(citizen)
	if query_world != null:
		return query_world.find_nearest_park(from_pos, citizen)
	return find_nearest_tree_building(
		citizen,
		from_pos,
		"parks",
		func(building: Building) -> bool:
			return building != null
	)

func find_best_tree_residential_building(citizen: Citizen, from_pos: Vector3) -> ResidentialBuilding:
	if citizen == null or not citizen.is_inside_tree():
		return null

	var best: ResidentialBuilding = null
	var best_load := INF
	var best_dist := INF
	for node in citizen.get_tree().get_nodes_in_group("buildings"):
		if node is not ResidentialBuilding:
			continue
		var residential := node as ResidentialBuilding
		if not residential.has_free_slot():
			continue

		var load := float(residential.tenants.size()) / float(maxi(residential.capacity, 1))
		var dist := from_pos.distance_to(residential.global_position)
		if load < best_load or (is_equal_approx(load, best_load) and dist < best_dist):
			best_load = load
			best_dist = dist
			best = residential
	return best

func find_nearest_tree_building(citizen: Citizen, from_pos: Vector3, group_name: String, accept: Callable) -> Building:
	if citizen == null or not citizen.is_inside_tree():
		return null

	var best: Building = null
	var best_dist := INF
	for node in citizen.get_tree().get_nodes_in_group(group_name):
		if node is not Building:
			continue
		var building := node as Building
		if accept.is_valid() and not bool(accept.call(building)):
			continue
		var dist := from_pos.distance_to(building.global_position)
		if dist < best_dist:
			best_dist = dist
			best = building
	return best
