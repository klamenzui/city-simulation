extends Resource
class_name DataMap
@export var wood := 500
@export var stone := 50
@export var gold := 10000
@export var iron := 0
@export var food := 1000
@export var dynamic_data: Array[Transform3D]
#@export var guards: Array[Transform3D]
#@export var structures:Array[DataStructure]
@export var structures: Dictionary = {}
