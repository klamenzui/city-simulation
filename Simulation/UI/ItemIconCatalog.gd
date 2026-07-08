extends RefCounted
class_name ItemIconCatalog

const ICON_PATHS := {
	"food": "res://Scenes/UI/Icons/Items/food.png",
	"grocery_bundle": "res://Scenes/UI/Icons/Items/food.png",
	"bread": "res://Scenes/UI/Icons/Items/bread.png",
	"drink": "res://Scenes/UI/Icons/Items/drink.png",
	"snack": "res://Scenes/UI/Icons/Items/snack.png",
	"meal": "res://Scenes/UI/Icons/Items/meal.png",
	"flour_sack": "res://Scenes/UI/Icons/Items/flour.png",
	"cornmeal_sack": "res://Scenes/UI/Icons/FarmInventory/corn_grain.png",
	"sunflower_oil_crate": "res://Scenes/UI/Icons/FarmInventory/sunflower.png",
	"wheat_seed": "res://Scenes/UI/Icons/FarmInventory/wheat_seed.png",
	"corn_seed": "res://Scenes/UI/Icons/FarmInventory/corn_seed.png",
	"sunflower_seed": "res://Scenes/UI/Icons/FarmInventory/sunflower_seed.png",
	"wheat_grain": "res://Scenes/UI/Icons/FarmInventory/wheat_grain.png",
	"corn_grain": "res://Scenes/UI/Icons/FarmInventory/corn_grain.png",
	"sunflower_grain": "res://Scenes/UI/Icons/FarmInventory/sunflower.png",
}

const LINEAR_FILTER_ITEMS := {
	"food": true,
	"grocery_bundle": true,
	"bread": true,
	"drink": true,
	"snack": true,
	"meal": true,
	"flour_sack": true,
	"cornmeal_sack": true,
	"sunflower_oil_crate": true,
	"wheat_seed": true,
	"corn_seed": true,
	"sunflower_seed": true,
	"corn_grain": true,
}

static var _texture_cache: Dictionary = {}


static func get_icon_path(item_id: String) -> String:
	return str(ICON_PATHS.get(item_id.strip_edges(), ""))


static func get_texture(item_id: String) -> Texture2D:
	var clean := item_id.strip_edges()
	if clean.is_empty():
		return null
	if _texture_cache.has(clean):
		return _texture_cache[clean] as Texture2D
	var path := get_icon_path(clean)
	if path.is_empty():
		return null
	var texture := load(path) as Texture2D
	if texture != null:
		_texture_cache[clean] = texture
	return texture


static func uses_linear_filter(item_id: String) -> bool:
	return LINEAR_FILTER_ITEMS.has(item_id.strip_edges())
