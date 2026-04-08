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
	"res://Simulation/Bootstrap/SceneRuntimeController.gd",
	"res://Simulation/Camera/CityBuilderCamera.gd",
	"res://Simulation/AI/LocalDialogueRuntimeService.gd",
	"res://Simulation/Citizens/CitizenLocomotion.gd",
	"res://Simulation/Citizens/CitizenSimulationLodController.gd",
	"res://Simulation/Conversation/CitizenConversationManager.gd",
	"res://Simulation/Spatial/CityDistrictIndex.gd",
	"res://Simulation/Navigation/PedestrianGraph.gd",
	"res://environment/sky/Cycle.tscn",
	"res://environment/sky/simulation_sky_bridge.gd",
	"res://ImportedCitySource/scenes/trafficlight_c_active.gd",
	"res://tools/codex_economy_test.gd",
	"res://tools/codex_building_occupancy_test.gd",
	"res://tools/codex_runtime_lod_conversation_test.gd",
	"res://tools/codex_dialogue_probe.gd",
]

const JSON_CONFIGS := [
	"res://config/balance.json",
	"res://config/city_districts.json",
	"res://config/citizen_decision_rules.json",
	"res://config/citizen_simulation_lod.json",
	"res://config/conversation_rules.json",
	"res://config/dialogue_runtime.json",
	"res://tools/dialogue_probe_default.json",
]

func _initialize() -> void:
	var failed: Array[String] = []
	for path in RESOURCES:
		var resource := load(path)
		if resource == null:
			push_error("Failed to load %s" % path)
			failed.append(path)
	for config_path in JSON_CONFIGS:
		var config_text := FileAccess.get_file_as_string(config_path)
		if config_text.is_empty():
			push_error("Failed to read %s" % config_path)
			failed.append(config_path)
			continue
		var parsed: Variant = JSON.parse_string(config_text)
		if parsed is not Dictionary:
			push_error("Invalid JSON in %s" % config_path)
			failed.append(config_path)
	if failed.is_empty():
		print("Parse check OK (%d resources, %d json configs)." % [RESOURCES.size(), JSON_CONFIGS.size()])
		quit(0)
		return
	print("Parse check failed: %s" % ", ".join(failed))
	quit(1)
