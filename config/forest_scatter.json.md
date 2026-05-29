# forest_scatter.json

Data-driven recipe for vegetation biomes. Consumed by
`tools/codex_generate_forest_yamms.gd`, which writes one editable Yamms
`MultiScatter` scene per biome into `output.biome_scene_dir`. Validated by
`tools/codex_forest_multimesh_scene_probe.gd` (run_tests key `forest`).

Workflow: edit this file → run the generator (headless is fine, it only writes
the biome scenes) → in the editor, instance `Scenes/Plants/Biomes/<Biome>.tscn`
under `World` in Main.tscn → select the MultiScatter → click **Generate** (needs
the real renderer + the ground collider that lives in Main). The live scatters
are the runtime; there is no bake step.

```
Godot_v4.6.3-stable_win64_console.exe --headless --path . \
  --script res://tools/codex_generate_forest_yamms.gd
```

## Top level

- `version` — schema version (2).
- `output.biome_scene_dir` — folder the per-biome scenes are written to.
- `output.root_suffix` — appended to the biome name for the scene's root node
  (e.g. biome `Forest` → root node `ForestScatter`, file `Forest.tscn`).

## global

- `seed` — RNG seed for Yamms (same seed = reproducible layout on Generate).
- `density_multiplier` — scales every item `count` (1.5 = +50% everywhere).
- `ground_collision_mask` — physics layer the raycast snaps onto (World = 1).
- `ray_height` — Y the polygon sits at; the ground raycast starts here, so it
  must be above the terrain.
- `visibility_range_end` — per-item distance cull (engine LOD); 0 disables.

## placement_defaults

Applied to every item unless overridden per category or per item.

- `normal_influence` — 0 keeps instances upright, 1 aligns to ground normal.
- `rotation.randomize` / `rotation.min_deg` / `rotation.max_deg` — random Euler
  degrees; `[0,360,0]` = full random yaw.

## categories

Map of category name → defaults (currently just `shadow`). Drives the
`cast_shadow` of each item in that category.

## biomes[]

Each biome becomes one MultiScatter scene with its own area and plant palette.

- `name` — biome id; used for the scene file and root node name.
- `area.source` — `"authoring"`: when the biome scene already exists, its
  polygon + exclusions are preserved on rebuild (so editor reshaping survives);
  `"config"`: always rebuild the polygon from below.
- `area.polygon.shape` — `"ellipse"` (`radius:[rx,rz]`, `inset`, `segments`) or
  `"points"` (`points:[[x,z], ...]`, local XZ).
- `area.exclusions[]` — empty areas. `shape:"rect"` (`position`,`size`) or
  `shape:"points"` (`points`).
- `items[]` — one entry per plant variant (one MultiScatterItem):
  - `name`, `category`, `mesh` (`.gltf`/`.glb`/`.obj`; first mesh is used).
  - `count` — instances before `density_multiplier`.
  - Scale, choose one:
    - `scale_min` / `scale_max` — raw proportional factor range, or
    - `height_min` / `height_max` — target height in meters (converted using the
      mesh's base height).
  - Optional per-item overrides: `shadow`, `rotation`, `normal_influence`,
    `visibility_range_end`.

Inheritance: `item` overrides `category` overrides `placement_defaults`/`global`.
