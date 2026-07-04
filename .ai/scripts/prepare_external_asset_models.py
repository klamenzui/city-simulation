#!/usr/bin/env python3
"""Prepare selected external 3D assets as centered, self-contained GLB files."""

from __future__ import annotations

import argparse
import math
import shutil
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Vector


MEDIEVAL_SOURCE_FILES = (
    "Floor_Brick.gltf",
    "Floor_Brick.bin",
    "Floor_RedBrick.gltf",
    "Floor_RedBrick.bin",
    "Floor_UnevenBrick.gltf",
    "Floor_UnevenBrick.bin",
    "Prop_Vine1.gltf",
    "Prop_Vine1.bin",
    "Prop_Vine2.gltf",
    "Prop_Vine2.bin",
    "Prop_Vine4.gltf",
    "Prop_Vine4.bin",
    "Prop_Vine5.gltf",
    "Prop_Vine5.bin",
    "Prop_Vine6.gltf",
    "Prop_Vine6.bin",
    "Prop_Vine9.gltf",
    "Prop_Vine9.bin",
    "T_Brick_BaseColor.png",
    "T_Brick_Normal.png",
    "T_Brick_Roughness.png",
    "T_RedBrick_BaseColor.png",
    "T_UnevenBrick_BaseColor.png",
    "T_UnevenBrick_Normal.png",
    "T_UnevenBrick_Roughness.png",
    "T_VineLeaf_png.png",
)

INDIVIDUAL_ASSETS = (
    (
        "Ultimate Nature Pack by Quaternius/FBX/Corn_1.fbx",
        "Scenes/FarmAssets/Quaternius/GLB/Corn_1.glb",
        "Corn1",
    ),
    (
        "Ultimate Nature Pack by Quaternius/FBX/Corn_2.fbx",
        "Scenes/FarmAssets/Quaternius/GLB/Corn_2.glb",
        "Corn2",
    ),
    (
        "Ultimate Nature Pack by Quaternius/FBX/Wheat.fbx",
        "Scenes/FarmAssets/Quaternius/GLB/Wheat.glb",
        "Wheat",
    ),
    (
        "cars/ambulance_car_-_low_poly.glb",
        "Scenes/Vehicles/Ambulances/GLB/ambulance_low_poly.glb",
        "AmbulanceLowPoly",
    ),
    (
        "cars/dodge_ambulance_1957_lowpoly_for_3d-printing.glb",
        "Scenes/Vehicles/Ambulances/GLB/dodge_ambulance_1957.glb",
        "DodgeAmbulance1957",
    ),
    (
        "cars/city_van_from_synty.glb",
        "Scenes/Vehicles/Synty/GLB/city_van.glb",
        "SyntyCityVan",
    ),
    (
        "cars/city_police_car_from_synty.glb",
        "Scenes/Vehicles/Synty/GLB/city_police_car.glb",
        "SyntyCityPoliceCar",
    ),
    (
        "cars/city_taxi_car_from_synty.glb",
        "Scenes/Vehicles/Synty/GLB/city_taxi_car.glb",
        "SyntyCityTaxiCar",
    ),
    (
        "cars/tractor_-_game_asset.glb",
        "Scenes/Vehicles/Farm/GLB/tractor_yellow.glb",
        "FarmTractorYellow",
    ),
    (
        "cars/green_farm_tractor_-_game_asset_update.glb",
        "Scenes/Vehicles/Farm/GLB/tractor_green.glb",
        "FarmTractorGreen",
    ),
    (
        "cars/crop_harvestor.glb",
        "Scenes/Vehicles/Farm/GLB/crop_harvester.glb",
        "CropHarvester",
    ),
)

TRUCK_SOURCE = "cars/Trucks/trucks_collection.glb"
TRUCK_ASSETS = (
    (-1378.54, "Scenes/Vehicles/Trucks/GLB/truck_box.glb", "TruckBox"),
    (-679.34, "Scenes/Vehicles/Trucks/GLB/truck_cargo.glb", "TruckCargo"),
    (20.83, "Scenes/Vehicles/Trucks/GLB/truck_flatbed.glb", "TruckFlatbed"),
    (725.42, "Scenes/Vehicles/Trucks/GLB/truck_cab.glb", "TruckCab"),
    (1457.47, "Scenes/Vehicles/Trucks/GLB/truck_tanker.glb", "TruckTanker"),
)

COMBINE_SOURCE = "cars/low_poly_combine_harvestors.glb"
COMBINE_ASSETS = (
    (-585.0, "Scenes/Vehicles/Farm/GLB/combine_harvester_a.glb", "CombineHarvesterA"),
    (29.0, "Scenes/Vehicles/Farm/GLB/combine_harvester_b.glb", "CombineHarvesterB"),
    (562.0, "Scenes/Vehicles/Farm/GLB/combine_harvester_c.glb", "CombineHarvesterC"),
)

ROTATE_Z_BY_SOURCE = {
    "cars/tractor_-_game_asset.glb": 90.0,
}

OPAQUE_MATERIAL_SOURCES = {
    "Ultimate Nature Pack by Quaternius/FBX/Wheat.fbx",
}


def _argv_after_blender_separator() -> list[str]:
    if "--" not in sys.argv:
        return []
    return sys.argv[sys.argv.index("--") + 1 :]


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--asset-root", required=True, help="Root folder containing the external asset packs.")
    parser.add_argument("--project-root", required=True, help="Godot project root receiving the GLB files.")
    parser.add_argument("--overwrite", action="store_true", help="Overwrite existing prepared GLB files.")
    parser.add_argument(
        "--only-target",
        action="append",
        default=[],
        help="Only prepare assets with this project-relative target path. Can be passed more than once.",
    )
    return parser.parse_args(_argv_after_blender_separator())


def _import_asset(source_file: Path) -> None:
    suffix = source_file.suffix.lower()
    if suffix in {".glb", ".gltf"}:
        bpy.ops.import_scene.gltf(filepath=str(source_file))
        return
    if suffix == ".fbx":
        bpy.ops.import_scene.fbx(filepath=str(source_file))
        return
    raise ValueError(f"Unsupported source format: {source_file}")


def _mesh_objects() -> list[bpy.types.Object]:
    return [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]


def _world_corners(obj: bpy.types.Object) -> list[Vector]:
    return [obj.matrix_world @ Vector(corner) for corner in obj.bound_box]


def _world_bounds(objects: list[bpy.types.Object]) -> tuple[Vector, Vector]:
    corners = [corner for obj in objects for corner in _world_corners(obj)]
    if not corners:
        raise RuntimeError("Asset contains no mesh bounds.")
    minimum = Vector((min(point.x for point in corners), min(point.y for point in corners), min(point.z for point in corners)))
    maximum = Vector((max(point.x for point in corners), max(point.y for point in corners), max(point.z for point in corners)))
    return minimum, maximum


def _flatten_under_root(objects: list[bpy.types.Object], root_name: str) -> bpy.types.Object:
    world_matrices = {obj: obj.matrix_world.copy() for obj in objects}
    root = bpy.data.objects.new(root_name, None)
    bpy.context.scene.collection.objects.link(root)
    for obj in objects:
        obj.parent = root
        obj.matrix_world = world_matrices[obj]
    return root


def _remove_unselected_objects(kept_objects: set[bpy.types.Object]) -> None:
    for obj in list(bpy.context.scene.objects):
        if obj not in kept_objects:
            bpy.data.objects.remove(obj, do_unlink=True)


def _force_opaque_materials(objects: list[bpy.types.Object]) -> None:
    for obj in objects:
        for slot in obj.material_slots:
            material = slot.material
            if material is None:
                continue
            material.diffuse_color[3] = 1.0
            if hasattr(material, "blend_method"):
                material.blend_method = "OPAQUE"
            if not material.use_nodes:
                continue
            for node in material.node_tree.nodes:
                if node.bl_idname != "ShaderNodeBsdfPrincipled":
                    continue
                if "Alpha" in node.inputs:
                    node.inputs["Alpha"].default_value = 1.0
                if "Base Color" in node.inputs:
                    color = node.inputs["Base Color"].default_value
                    if len(color) >= 4:
                        color[3] = 1.0


def _center_and_ground(root: bpy.types.Object, objects: list[bpy.types.Object]) -> tuple[Vector, Vector]:
    minimum, maximum = _world_bounds(objects)
    root.location += Vector(
        (
            -(minimum.x + maximum.x) * 0.5,
            -(minimum.y + maximum.y) * 0.5,
            -minimum.z,
        )
    )
    bpy.context.view_layer.update()
    return _world_bounds(objects)


def _export_glb(target_file: Path, root: bpy.types.Object, objects: list[bpy.types.Object]) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    root.select_set(True)
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = root

    target_file.parent.mkdir(parents=True, exist_ok=True)
    kwargs = {
        "filepath": str(target_file),
        "export_format": "GLB",
        "export_yup": True,
        "use_selection": True,
        "check_existing": False,
        "export_materials": "EXPORT",
        "export_image_format": "AUTO",
        "export_cameras": False,
        "export_lights": False,
    }
    supported = {prop.identifier for prop in bpy.ops.export_scene.gltf.get_rna_type().properties}
    bpy.ops.export_scene.gltf(**{key: value for key, value in kwargs.items() if key in supported})


def _prepare_one(
    source_file: Path,
    target_file: Path,
    root_name: str,
    overwrite: bool,
    mesh_filter=None,
    rotation_z_degrees: float = 0.0,
    force_opaque_materials: bool = False,
) -> bool:
    if target_file.exists() and not overwrite:
        print(f"[SKIP] {target_file}")
        return False
    if not source_file.is_file():
        raise FileNotFoundError(f"Missing source asset: {source_file}")

    bpy.ops.wm.read_factory_settings(use_empty=True)
    _import_asset(source_file)
    bpy.context.view_layer.update()

    meshes = _mesh_objects()
    if mesh_filter is not None:
        meshes = [obj for obj in meshes if mesh_filter(obj)]
    if not meshes:
        raise RuntimeError(f"No geometry selected from {source_file}")

    if not math.isclose(rotation_z_degrees, 0.0):
        rotation = Matrix.Rotation(math.radians(rotation_z_degrees), 4, "Z")
        for obj in meshes:
            obj.matrix_world = rotation @ obj.matrix_world
        bpy.context.view_layer.update()

    if force_opaque_materials:
        _force_opaque_materials(meshes)

    root = _flatten_under_root(meshes, root_name)
    _remove_unselected_objects({root, *meshes})
    minimum, maximum = _center_and_ground(root, meshes)
    _export_glb(target_file, root, meshes)
    dimensions = maximum - minimum
    print(
        f"[EXPORT] {source_file.name} -> {target_file} "
        f"meshes={len(meshes)} dimensions=({dimensions.x:.3f}, {dimensions.y:.3f}, {dimensions.z:.3f})"
    )
    return True


def _copy_medieval_sources(asset_root: Path, project_root: Path, overwrite: bool) -> int:
    source_dir = asset_root / "Medieval Village MegaKit[Standard]" / "glTF"
    target_dir = project_root / "ImportedCitySource" / "assets" / "medieval_village"
    target_dir.mkdir(parents=True, exist_ok=True)

    copied_count = 0
    for file_name in MEDIEVAL_SOURCE_FILES:
        source_file = source_dir / file_name
        target_file = target_dir / file_name
        if not source_file.is_file():
            raise FileNotFoundError(f"Missing Medieval Village dependency: {source_file}")
        if target_file.exists() and not overwrite:
            print(f"[SKIP] {target_file}")
            continue
        shutil.copy2(source_file, target_file)
        copied_count += 1
        print(f"[COPY] {source_file.name} -> {target_file}")
    return copied_count


def _mesh_world_center_x(obj: bpy.types.Object) -> float:
    corners = _world_corners(obj)
    return (min(point.x for point in corners) + max(point.x for point in corners)) * 0.5


def _mesh_world_center(obj: bpy.types.Object) -> Vector:
    corners = _world_corners(obj)
    minimum = Vector(
        (
            min(point.x for point in corners),
            min(point.y for point in corners),
            min(point.z for point in corners),
        )
    )
    maximum = Vector(
        (
            max(point.x for point in corners),
            max(point.y for point in corners),
            max(point.z for point in corners),
        )
    )
    return (minimum + maximum) * 0.5


def _green_tractor_mesh_filter(obj: bpy.types.Object) -> bool:
    center = _mesh_world_center(obj)
    corners = _world_corners(obj)
    y_size = max(point.y for point in corners) - min(point.y for point in corners)
    return (
        -7.0 <= center.x <= -4.0
        and 5.0 <= center.y <= 11.0
        and y_size < 7.0
        and not obj.name.startswith("Tree_winding")
    )


def main() -> int:
    args = _parse_args()
    asset_root = Path(args.asset_root).resolve()
    project_root = Path(args.project_root).resolve()
    only_targets = {target.replace("\\", "/") for target in args.only_target}
    medieval_copy_count = 0
    prepared_glb_count = 0

    if not only_targets:
        medieval_copy_count = _copy_medieval_sources(asset_root, project_root, args.overwrite)

    for source_relative, target_relative, root_name in INDIVIDUAL_ASSETS:
        if only_targets and target_relative.replace("\\", "/") not in only_targets:
            continue
        mesh_filter = None
        if source_relative == "cars/green_farm_tractor_-_game_asset_update.glb":
            mesh_filter = _green_tractor_mesh_filter
        if _prepare_one(
            asset_root / source_relative,
            project_root / target_relative,
            root_name,
            args.overwrite,
            mesh_filter=mesh_filter,
            rotation_z_degrees=ROTATE_Z_BY_SOURCE.get(source_relative, 0.0),
            force_opaque_materials=source_relative in OPAQUE_MATERIAL_SOURCES,
        ):
            prepared_glb_count += 1

    truck_source = asset_root / TRUCK_SOURCE
    truck_anchors = [spec[0] for spec in TRUCK_ASSETS]
    for anchor, target_relative, root_name in TRUCK_ASSETS:
        if only_targets and target_relative.replace("\\", "/") not in only_targets:
            continue
        if _prepare_one(
            truck_source,
            project_root / target_relative,
            root_name,
            args.overwrite,
            mesh_filter=lambda obj, selected_anchor=anchor: min(
                truck_anchors,
                key=lambda candidate: abs(_mesh_world_center_x(obj) - candidate),
            )
            == selected_anchor,
        ):
            prepared_glb_count += 1

    combine_source = asset_root / COMBINE_SOURCE
    combine_anchors = [spec[0] for spec in COMBINE_ASSETS]
    for anchor, target_relative, root_name in COMBINE_ASSETS:
        if only_targets and target_relative.replace("\\", "/") not in only_targets:
            continue
        if _prepare_one(
            combine_source,
            project_root / target_relative,
            root_name,
            args.overwrite,
            mesh_filter=lambda obj, selected_anchor=anchor: min(
                combine_anchors,
                key=lambda candidate: abs(_mesh_world_center_x(obj) - candidate),
            )
            == selected_anchor,
        ):
            prepared_glb_count += 1

    print(
        f"[DONE] Copied {medieval_copy_count} Medieval source files and "
        f"prepared {prepared_glb_count} GLB assets."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
