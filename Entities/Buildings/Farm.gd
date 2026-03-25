extends CommercialBuilding
class_name Farm

@export var base_food_output_per_day: int = 140
@export var production_cost_per_unit: int = 1

var output_today: int = 0

func _ready() -> void:
	super._ready()
	building_type = BuildingType.FARM
	var settings := apply_balance_settings("farm")
	base_food_output_per_day = int(settings.get("base_food_output_per_day", base_food_output_per_day))
	production_cost_per_unit = int(settings.get("production_cost_per_unit", production_cost_per_unit))
	restock_enabled = false

func get_service_type() -> String:
	return "production_food"

func run_daily_production(world: World) -> void:
	if world == null:
		return

	var labor_ratio: float = clamp(float(workers.size()) / float(maxi(job_capacity, 1)), 0.15, 1.25)
	var produced: int = maxi(int(round(float(base_food_output_per_day) * labor_ratio)), 0)
	output_today = produced
	if produced <= 0:
		return

	var result: Dictionary = world.economy.sell_wholesale_to_market(account, "food", produced)
	var shipped: int = int(result.get("qty", 0))
	var total_revenue: int = int(result.get("total_revenue", 0))
	if total_revenue > 0:
		record_income(total_revenue)
	if shipped > 0:
		var production_cost: int = shipped * maxi(production_cost_per_unit, 0)
		if production_cost > 0 and account.balance >= production_cost:
			account.balance -= production_cost
			record_expense(production_cost)

func _get_extra_info(_world = null) -> Dictionary:
	var info := get_commercial_info()
	info["Output today"] = "%d food" % output_today
	return info
