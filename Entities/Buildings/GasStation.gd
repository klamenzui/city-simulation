extends CommercialBuilding
class_name GasStation

@export var fuel_price: int = 7
@export var base_vehicle_sales_per_day: int = 18
@export_range(0.0, 2.0, 0.05) var citizen_vehicle_demand_factor: float = 0.35
@export var fuel_units_per_vehicle: int = 2

var vehicles_served_today: int = 0
var fuel_units_sold_today: int = 0

func _ready() -> void:
	super._ready()
	building_type = BuildingType.GAS_STATION
	var settings := apply_balance_settings("gas_station")
	fuel_price = int(settings.get("fuel_price", fuel_price))
	base_vehicle_sales_per_day = int(settings.get("base_vehicle_sales_per_day", base_vehicle_sales_per_day))
	citizen_vehicle_demand_factor = float(settings.get("citizen_vehicle_demand_factor", citizen_vehicle_demand_factor))
	fuel_units_per_vehicle = int(settings.get("fuel_units_per_vehicle", fuel_units_per_vehicle))
	define_stock_item(
		"fuel",
		int(settings.get("fuel_start_stock", 90)),
		fuel_price,
		int(settings.get("fuel_restock_target", 140)),
		int(settings.get("fuel_restock_batch", 50)),
		"fuel"
	)

func get_service_type() -> String:
	return "fuel"

func begin_new_day() -> void:
	super.begin_new_day()
	vehicles_served_today = 0
	fuel_units_sold_today = 0

func run_daily_supply(world: World) -> void:
	super.run_daily_supply(world)
	_simulate_drive_in_sales(world)

func _simulate_drive_in_sales(world: World) -> void:
	if world == null:
		return
	if is_financially_closed():
		return
	if requires_staff_to_operate() and not has_required_staff():
		return

	var stock := get_stock("fuel")
	if stock <= 0:
		return

	var labor_ratio := clampf(float(maxi(workers.size(), 1)) / float(maxi(job_capacity, 1)), 0.35, 1.25)
	labor_ratio *= get_operating_efficiency_multiplier()

	var estimated_demand := float(base_vehicle_sales_per_day) + float(world.citizens.size()) * citizen_vehicle_demand_factor
	var target_vehicles := maxi(int(round(estimated_demand * labor_ratio * get_attractiveness_multiplier())), 0)
	if target_vehicles <= 0:
		return

	var units_per_vehicle := maxi(fuel_units_per_vehicle, 1)
	var max_vehicles_by_stock := int(floor(float(stock) / float(units_per_vehicle)))
	vehicles_served_today = mini(target_vehicles, max_vehicles_by_stock)
	fuel_units_sold_today = vehicles_served_today * units_per_vehicle
	if fuel_units_sold_today <= 0:
		return

	var revenue := get_item_price("fuel", fuel_units_sold_today)
	_finalize_sale("fuel", fuel_units_sold_today, revenue)

func _get_extra_info(_world = null) -> Dictionary:
	var info := get_commercial_info()
	info["Fuel price"] = "%d EUR" % get_item_price("fuel", 1)
	info["Fuel stock"] = str(get_stock("fuel"))
	info["Vehicles served"] = str(vehicles_served_today)
	info["Fuel sold"] = str(fuel_units_sold_today)
	return info
