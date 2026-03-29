extends CommercialBuilding
class_name Factory

@export var clothes_output_per_day: int = 55
@export var entertainment_output_per_day: int = 90
@export var production_cost_per_unit: int = 2

var output_clothes_today: int = 0
var output_entertainment_today: int = 0

func _ready() -> void:
	super._ready()
	building_type = BuildingType.FACTORY
	var settings := apply_balance_settings("factory")
	clothes_output_per_day = int(settings.get("clothes_output_per_day", clothes_output_per_day))
	entertainment_output_per_day = int(settings.get("entertainment_output_per_day", entertainment_output_per_day))
	production_cost_per_unit = int(settings.get("production_cost_per_unit", production_cost_per_unit))
	restock_enabled = false

func get_service_type() -> String:
	return "production_goods"

func run_daily_production(world: World) -> void:
	if world == null:
		return
	if is_financially_closed():
		output_clothes_today = 0
		output_entertainment_today = 0
		return
	if requires_staff_to_operate() and not has_required_staff():
		output_clothes_today = 0
		output_entertainment_today = 0
		return

	var labor_ratio: float = clamp(float(workers.size()) / float(maxi(job_capacity, 1)), 0.2, 1.3)
	labor_ratio *= get_operating_efficiency_multiplier()
	var clothes_qty: int = maxi(int(round(float(clothes_output_per_day) * labor_ratio)), 0)
	var entertainment_qty: int = maxi(int(round(float(entertainment_output_per_day) * labor_ratio)), 0)
	output_clothes_today = clothes_qty
	output_entertainment_today = entertainment_qty

	var total_output := clothes_qty + entertainment_qty
	var production_cost: int = total_output * maxi(production_cost_per_unit, 0)
	if production_cost > 0:
		if not world.economy.pay_production_cost(account, production_cost):
			close_due_to_finance(world, "unpaid production costs")
			output_clothes_today = 0
			output_entertainment_today = 0
			return
		record_production_expense(production_cost)

	var shipped_total := 0
	if clothes_qty > 0:
		var clothes_result: Dictionary = world.economy.sell_wholesale_to_market(account, "clothes", clothes_qty)
		var clothes_revenue: int = int(clothes_result.get("total_revenue", 0))
		if clothes_revenue > 0:
			record_income(clothes_revenue)
		shipped_total += int(clothes_result.get("qty", 0))

	if entertainment_qty > 0:
		var ent_result: Dictionary = world.economy.sell_wholesale_to_market(account, "entertainment", entertainment_qty)
		var ent_revenue: int = int(ent_result.get("total_revenue", 0))
		if ent_revenue > 0:
			record_income(ent_revenue)
		shipped_total += int(ent_result.get("qty", 0))

func _get_extra_info(_world = null) -> Dictionary:
	var info := get_commercial_info()
	info["Output clothes"] = str(output_clothes_today)
	info["Output entertainment"] = str(output_entertainment_today)
	return info
