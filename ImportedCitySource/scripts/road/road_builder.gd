class_name RoadBuilder

var road_map: Dictionary = {}
var world: Node3D = null
var pos: Vector2 = Vector2.ZERO
var grid_size: int = 2
var sides_positions: Dictionary = {
	"front": Vector2(0, 2),
	"right": Vector2(2, 0),
	"back": Vector2(0, -2),
	"left": Vector2(-2, 0)
}

# Returns the opposite direction
func get_opposite_direction(direction: String) -> String:
	return RoadPart.get_opposite_direction(direction)

# Returns the rotation angle for a direction
func get_rotation_for_direction(direction: String) -> float:
	return RoadPart.get_rotation_for_direction(direction)

# Constructor
func _init(_world: Node3D) -> void:
	world = _world

# Builds or retrieves a road part at the specified position
func build(_pos: Vector2) -> RoadPart:
	pos = _pos
	var current: RoadPart = road_map.get(_pos, null)
	
	# Return existing road part if available
	if current:
		return current
	
	# Create new road part if none exists
	current = RoadPart.new(world, _pos)
	road_map[_pos] = current
	
	# Connect with neighboring roads
	reconnect_neighbors(current)
	return current

# Gets a road at the specified position
func get_road(_pos: Vector2) -> RoadPart:
	return road_map.get(_pos, null)
	
# Reconnects a road with all its neighbors
func reconnect_neighbors(current: RoadPart) -> void:
	# Check and connect all neighbors
	for s in sides_positions:
		var neighbor_pos: Vector2 = pos + sides_positions[s]
		var neighbor: RoadPart = road_map.get(neighbor_pos, null)
		if neighbor:
			current.connect_road(neighbor)
			
	# Update model after all connections
	current.update_model()
	
# Decorates a crossing road
func decorate_cross(road: RoadPart) -> void:
	for s in road.connections:
		var neighbor_pos = road.connections[s]
		if not neighbor_pos:
			continue
			
		var neighbor: RoadPart = road_map.get(neighbor_pos, null)
		if neighbor:
			neighbor.crossing = s
			neighbor.update_model()
			neighbor.decorate()

# Decorates all roads in the map
func decorate_all() -> void:
	for _pos in road_map:
		var road: RoadPart = road_map[_pos]
		if not road:
			continue
			
		if road.form_type in [RoadPart.FormType.TSPLIT, RoadPart.FormType.JUNCTION]:
			decorate_cross(road)
		else:
			road.decorate()
