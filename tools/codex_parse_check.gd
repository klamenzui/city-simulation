extends SceneTree

const RESOURCES := [
	"res://main.gd",
	"res://Main.tscn",
	"res://Entities/Buildings/Building.gd",
	"res://Entities/Citizens/Citizen.gd",
	"res://Actions/GoToBuildingAction.gd",
	"res://Simulation/Citizens/CitizenLocomotion.gd",
	"res://Simulation/Navigation/PedestrianGraph.gd",
]

func _initialize() -> void:
	var failed: Array[String] = []
	for path in RESOURCES:
		var resource := load(path)
		if resource == null:
			push_error("Failed to load %s" % path)
			failed.append(path)
	if failed.is_empty():
		print("Parse check OK (%d resources)." % RESOURCES.size())
		quit(0)
		return
	print("Parse check failed: %s" % ", ".join(failed))
	quit(1)
