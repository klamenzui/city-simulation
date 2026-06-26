# Low Poly Water Pack

## Runtime setup

1. Instance `Scenes/UniversalWater.tscn`.
2. Set `plane_size` and `water_y`.
3. Assign a prepared shore-mask texture to the material when shoreline coloring or foam is needed.
4. Select `LOW`, `MEDIUM`, or `HIGH` quality on `LowPolyWaterPlane`.

The water node is visual only. It does not create collision, navigation, or gameplay state.

## Shore masks

Runtime shore-mask generation is disabled by default because it scans mesh data and rasterizes the result on the CPU. Use a prepared texture for production scenes.

`generate_and_apply_shore_mask()` remains available for deliberate tooling or prototyping. Automatic runtime generation requires both:

- `auto_generate_shore_mask = true`
- `allow_runtime_shore_mask_generation = true`

Generation is always skipped on headless and dedicated-server runtimes.

Mask channels:

- Red: shallow-water gradient
- Green: shoreline foam
- Blue: land cutout
- Alpha: reserved

Use lossless, non-color texture import settings for shore masks.

The included baker can generate the demo mask without enabling runtime generation:

```powershell
Godot_v4.7-stable_win64_console.exe --headless --path C:\dev\projects\Godot\LowPolyWater --script res://Scenes/LowPolyWater/WaterPack/Tools/bake_shore_mask.gd
```

Optional arguments after `--`:

- `--scene=res://path/to/scene.tscn`
- `--water-node=Path/To/Water`
- `--output=res://path/to/shore_mask.png`

## Integration notes

- Keep the water plane horizontal. The shader supports translation and global scale, but shoreline UVs are axis-aligned.
- Disable water shadows; `LowPolyWaterPlane` does this automatically.
- Prefer `MEDIUM` quality for strategy and simulation cameras. Use `HIGH` only when the additional surface detail is visible.
- Do not copy the large pirate demo scene into production projects. The reusable runtime pack is the `WaterPack` folder.

## Licensing

Confirm and document the license and origin of all textures and audio before shipping them in a product.
