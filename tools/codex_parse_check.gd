extends SceneTree

const RESOURCES := [
	"res://main.gd",
	"res://Main.tscn",
	"res://Entities/Buildings/Building.gd",
	"res://Entities/Citizens/Citizen.gd",
	"res://Actions/GoToBuildingAction.gd",
	"res://Simulation/World.gd",
	"res://Simulation/Config/BalanceConfig.gd",
	"res://Simulation/Bootstrap/NavigationSetup.gd",
	"res://Simulation/Camera/CityBuilderCamera.gd",
	"res://Simulation/Citizens/CitizenLocomotion.gd",
	"res://Simulation/Navigation/PedestrianGraph.gd",
	"res://environment/sky/Cycle.tscn",
	"res://environment/sky/simulation_sky_bridge.gd",
	"res://ImportedCitySource/scenes/trafficlight_c_active.gd",
	"res://tools/codex_economy_test.gd",
	"res://tools/codex_building_occupancy_test.gd",
]

func _initialize() -> void:
	var failed: Array[String] = []
	for path in RESOURCES:
		var resource := load(path)
		if resource == null:
			push_error("Failed to load %s" % path)
			failed.append(path)
	var config_text := FileAccess.get_file_as_string("res://config/balance.json")
	if config_text.is_empty():
		push_error("Failed to read res://config/balance.json")
		failed.append("res://config/balance.json")
	else:
		var parsed: Variant = JSON.parse_string(config_text)
		if parsed is not Dictionary:
			push_error("Invalid JSON in res://config/balance.json")
			failed.append("res://config/balance.json")
	if failed.is_empty():
		print("Parse check OK (%d resources)." % RESOURCES.size())
		quit(0)
		return
	print("Parse check failed: %s" % ", ".join(failed))
	quit(1)
