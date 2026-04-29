class_name CitizenBenchReservation
extends RefCounted

## Releases the citizen's bench reservation against a building and/or the
## city-wide bench pool. Extracted from old `Citizen.gd` lines 1316-1322.
##
## Today this component holds no state — the source of truth lives on
## `Park.release_bench_for(citizen)` and `World.release_city_bench_for(citizen)`.
## The component shape mirrors the other Sim components so the Facade
## delegates uniformly. Future extension: cache the last reserved bench so
## `release()` becomes O(1) instead of an iteration over the building's
## reservation map.

var owner_node: Node = null


func _init(p_owner: Node) -> void:
	owner_node = p_owner


## Releases the citizen's reservation from `building` (or `fallback_building`
## if `building` is null — typically the citizen's `current_location`) plus
## from the city-wide bench pool via `world`.
##
## Both target calls are guarded by `has_method` so callers can pass
## buildings without bench support without checking up front.
func release(world: Node, building: Building = null, fallback_building: Building = null) -> void:
	var resolved_building: Building = building if building != null else fallback_building
	if resolved_building != null and resolved_building.has_method("release_bench_for"):
		resolved_building.release_bench_for(owner_node)
	if world != null and world.has_method("release_city_bench_for"):
		world.release_city_bench_for(owner_node)
