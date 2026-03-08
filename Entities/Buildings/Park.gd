extends Building
class_name Park

func _ready() -> void:
	# BUG FIX: super._ready() was missing. Without it, Building._ready() never ran,
	# so Park was never added to the "buildings" group and its Account was never initialized.
	super._ready()
	add_to_group("parks")
