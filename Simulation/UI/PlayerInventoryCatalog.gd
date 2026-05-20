extends RefCounted
class_name PlayerInventoryCatalog

## Static catalog of player-visible inventory items.
##
## Adding a new item requires three edits:
##   1) Register the item id below (label, icon, tab_label).
##   2) Provide a count via Citizen.get_inventory_count(id).
##   3) Optional: shop offers map a Building's stock_item to this id via
##      get_shop_item_id_for_stock(stock_key).
##
## The catalog stays plain Dictionary data so callers can extend it from
## config files later without touching every consumer.

const ITEMS: Dictionary = {
	"food": {
		"label": "Vorraete",
		"icon": "🍞",
		"tab_label": "Essen",
		"tab_order": 0,
	},
	"clothing": {
		"label": "Kleidung",
		"icon": "👕",
		"tab_label": "Kleidung",
		"tab_order": 1,
	},
}

# Maps a Shop's internal stock_item key to the inventory item id used here.
# Keep this list aligned with Shop.define_stock_item() calls.
const STOCK_TO_ITEM: Dictionary = {
	"clothing": "clothing",
	"grocery_bundle": "food",
}


static func item_ids() -> Array:
	var ids: Array = ITEMS.keys()
	ids.sort_custom(func(a, b): return _order(a) < _order(b))
	return ids


static func get_label(id: String) -> String:
	return str(ITEMS.get(id, {}).get("label", id))


static func get_icon(id: String) -> String:
	return str(ITEMS.get(id, {}).get("icon", "📦"))


static func get_tab_label(id: String) -> String:
	return str(ITEMS.get(id, {}).get("tab_label", get_label(id)))


static func get_shop_item_id_for_stock(stock_key: String) -> String:
	return str(STOCK_TO_ITEM.get(stock_key, ""))


static func _order(id: Variant) -> int:
	return int(ITEMS.get(str(id), {}).get("tab_order", 99))
