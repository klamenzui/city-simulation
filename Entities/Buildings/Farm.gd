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
	if is_financially_closed():
		output_today = 0
		return
	if requires_staff_to_operate() and not has_required_staff():
		output_today = 0
		return

	var labor_ratio: float = clamp(float(workers.size()) / float(maxi(job_capacity, 1)), 0.15, 1.25)
	labor_ratio *= get_operating_efficiency_multiplier()
	var produced: int = maxi(int(round(float(base_food_output_per_day) * labor_ratio)), 0)
	output_today = produced
	if produced <= 0:
		return

	var production_cost: int = produced * maxi(production_cost_per_unit, 0)
	if production_cost > 0:
		if not world.economy.pay_production_cost(account, production_cost):
			close_due_to_finance(world, "unpaid production costs")
			output_today = 0
			return
		record_production_expense(production_cost)

	var result: Dictionary = world.economy.sell_wholesale_to_market(account, "food", produced)
	var total_revenue: int = int(result.get("total_revenue", 0))
	if total_revenue > 0:
		record_income(total_revenue)

func _get_extra_info(_world = null) -> Dictionary:
	var info := get_commercial_info()
	info["Output today"] = "%d food" % output_today
	return info
