extends SceneTree

const ASSET_SCENE_PATHS := [
	"res://Scenes/FarmAssets/Quaternius/Barn.tscn",
	"res://Scenes/FarmAssets/Quaternius/BigBarn.tscn",
	"res://Scenes/FarmAssets/Quaternius/ChickenCoop.tscn",
	"res://Scenes/FarmAssets/Quaternius/Fence.tscn",
	"res://Scenes/FarmAssets/Quaternius/Fence2.tscn",
	"res://Scenes/FarmAssets/Quaternius/OpenBarn.tscn",
	"res://Scenes/FarmAssets/Quaternius/Silo.tscn",
	"res://Scenes/FarmAssets/Quaternius/Silo_House.tscn",
	"res://Scenes/FarmAssets/Quaternius/SmallBarn.tscn",
	"res://Scenes/FarmAssets/Quaternius/TowerWindmill.tscn",
	"res://Scenes/FarmAssets/Quaternius/WaterTower.tscn",
	"res://Scenes/FarmAssets/Quaternius/Well.tscn",
	"res://Scenes/FarmAssets/Quaternius/Windmill.tscn",
]

const FARM_MODEL_NODES := {
	"res://Scenes/Farm.tscn": [
		"Buildings/SmallBarnModel",
		"Buildings/BigBarnModel",
		"Buildings/SiloModel",
		"Fence/BackFenceModel",
		"Props/WellModel",
	],
	"res://Scenes/Farm_Windmill.tscn": [
		"Buildings/SmallBarnModel",
		"Buildings/BigBarnModel",
		"Buildings/SiloModel",
		"VariantDecor/WindmillModel",
		"VariantDecor/WaterTowerModel",
		"VariantDecor/SideBarnModel",
		"Fence/SideGateModel",
	],
	"res://Scenes/Farm_AnimalRanch.tscn": [
		"Buildings/SmallBarnModel",
		"Buildings/BigBarnModel",
		"Buildings/SiloModel",
		"AnimalArea/OpenBarnModel",
		"AnimalArea/ChickenCoopModel",
		"AnimalArea/FeedBarnModel",
		"AnimalArea/PastureNorthFenceModel",
	],
}


func _initialize() -> void:
	var errors: Array[String] = []
	var asset_mesh_total := 0

	for scene_path in ASSET_SCENE_PATHS:
		var scene := load(scene_path) as PackedScene
		if scene == null:
			errors.append("Could not load asset scene: %s" % scene_path)
			continue

		var instance := scene.instantiate()
		if instance == null:
			errors.append("Could not instantiate asset scene: %s" % scene_path)
			continue

		var mesh_count := _count_nodes_of_type(instance, MeshInstance3D)
		if mesh_count <= 0:
			errors.append("Asset scene has no MeshInstance3D descendants: %s" % scene_path)
		asset_mesh_total += mesh_count
		instance.free()

	for scene_path in FARM_MODEL_NODES.keys():
		var scene := load(scene_path) as PackedScene
		if scene == null:
			errors.append("Could not load farm scene: %s" % scene_path)
			continue

		var farm := scene.instantiate()
		if farm == null:
			errors.append("Could not instantiate farm scene: %s" % scene_path)
			continue

		for node_path in FARM_MODEL_NODES[scene_path]:
			var node := farm.get_node_or_null(NodePath(node_path))
			if node == null:
				errors.append("%s missing expected model node: %s" % [scene_path, node_path])
				continue
			if _count_nodes_of_type(node, MeshInstance3D) <= 0:
				errors.append("%s model node has no MeshInstance3D descendants: %s" % [scene_path, node_path])
		farm.free()

	if not errors.is_empty():
		for error in errors:
			push_error(error)
		quit(FAILED)
		return

	print("Quaternius farm asset probe passed: assets=%d asset_meshes=%d farm_scenes=%d" % [
		ASSET_SCENE_PATHS.size(),
		asset_mesh_total,
		FARM_MODEL_NODES.size(),
	])
	quit(OK)


func _count_nodes_of_type(root_node: Node, node_type: Variant) -> int:
	var count := 0
	if is_instance_of(root_node, node_type):
		count += 1
	for child in root_node.get_children():
		count += _count_nodes_of_type(child, node_type)
	return count
