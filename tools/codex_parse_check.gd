extends SceneTree

const RESOURCES := [
	"res://main.gd",
	"res://Main.tscn",
	"res://Scenes/Environment/ExteriorGrassDecorator.gd",
	"res://Scenes/Environment/Grass/GrassShader.tres",
	"res://Scenes/Environment/Grass/Stylized3DGrass.tres",
	"res://Scenes/Environment/Grass/grass.glb",
	"res://Scenes/Plants/ForestMultiMesh.tscn",
	"res://Entities/Buildings/Building.gd",
	"res://Entities/Buildings/Hospital.gd",
	"res://Entities/Citizens/New/Citizen.gd",
	"res://Entities/Citizens/CitizenNew.tscn",
	"res://Actions/GoToBuildingAction.gd",
	"res://Actions/TreatAtHospitalAction.gd",
	"res://Simulation/GOAP/CitizenHealthGoap.gd",
	"res://Simulation/World.gd",
	"res://Simulation/Config/BalanceConfig.gd",
	"res://Simulation/Localization/LocaleService.gd",
	"res://Simulation/UI/MainMenuController.gd",
	"res://Scenes/Minigames/RetailWorkSort/RetailWorkSortMinigame.gd",
	"res://Scenes/Minigames/RetailWorkSort/RetailWorkSortMinigame.tscn",
	"res://Scenes/Minigames/TeacherLesson/TeacherLessonMinigame.gd",
	"res://Scenes/Minigames/TeacherLesson/TeacherLessonMinigame.tscn",
	"res://Scenes/Minigames/WarehouseStack/WarehouseStackMinigame.gd",
	"res://Scenes/Minigames/WarehouseStack/WarehouseStackMinigame.tscn",
	"res://Scenes/Minigames/ServiceFlow/ServiceFlowMinigame.gd",
	"res://Scenes/Minigames/ServiceFlow/ServiceFlowMinigame.tscn",
	"res://Scenes/WorkScenes/Farm/FarmWorkScene.gd",
	"res://Scenes/WorkScenes/Farm/FarmWorkScene.tscn",
	"res://Simulation/Bootstrap/NavigationSetup.gd",
	"res://Simulation/Bootstrap/SceneRuntimeController.gd",
	"res://Simulation/Camera/CityBuilderCamera.gd",
	"res://Simulation/AI/LocalDialogueRuntimeService.gd",
	"res://Simulation/Citizens/CitizenLocomotion.gd",
	"res://Simulation/Citizens/CitizenSimulationLodController.gd",
	"res://Simulation/Conversation/CitizenConversationManager.gd",
	"res://Simulation/Multiplayer/MultiplayerSession.gd",
	"res://Simulation/Multiplayer/shared/NetworkRole.gd",
	"res://Simulation/Multiplayer/shared/MultiplayerLaunchOptions.gd",
	"res://Simulation/Multiplayer/shared/NetworkEntityRegistry.gd",
	"res://Simulation/Multiplayer/shared/WorldSnapshotSerializer.gd",
	"res://Simulation/Multiplayer/server/MultiplayerHostAuthority.gd",
	"res://Simulation/Multiplayer/client/MultiplayerClientReplica.gd",
	"res://Simulation/Spatial/CityDistrictIndex.gd",
	"res://Simulation/Navigation/PedestrianGraph.gd",
	"res://environment/sky/Cycle.tscn",
	"res://environment/sky/simulation_sky_bridge.gd",
	"res://Scenes/CityBuildings/services/Hospital.tscn",
	"res://ImportedCitySource/scenes/trafficlight_c_active.gd",
	"res://tools/codex_economy_test.gd",
	"res://tools/codex_retail_work_sort_minigame_test.gd",
	"res://tools/codex_teacher_lesson_minigame_test.gd",
	"res://tools/codex_warehouse_stack_minigame_test.gd",
	"res://tools/codex_service_flow_minigame_test.gd",
	"res://tools/codex_farm_work_scene_test.gd",
	"res://tools/codex_building_occupancy_test.gd",
	"res://tools/codex_citizen_fall_respawn_test.gd",
	"res://tools/codex_multiplayer_host_connect_test.gd",
	"res://tools/codex_multiplayer_process_probe.gd",
	"res://tools/codex_multiplayer_two_process_test.gd",
	"res://tools/codex_runtime_lod_conversation_test.gd",
	"res://tools/codex_dialogue_probe.gd",
	"res://tools/codex_exterior_grass_scene_probe.gd",
	"res://tools/codex_forest_multimesh_scene_probe.gd",
	"res://tools/codex_generate_forest_scene.gd",
	"res://tools/codex_locale_test.gd",
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
