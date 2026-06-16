#!/usr/bin/env python3
"""Export every .blend file in a folder to GLB through Blender."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import bpy


GEOMETRY_TYPES = {"MESH", "CURVE", "SURFACE", "FONT", "META"}


def _argv_after_blender_separator() -> list[str]:
    if "--" not in sys.argv:
        return []
    return sys.argv[sys.argv.index("--") + 1 :]


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Export .blend files to .glb files.")
    parser.add_argument("--source", required=True, help="Folder containing .blend files.")
    parser.add_argument("--target", required=True, help="Folder that receives .glb files.")
    parser.add_argument("--overwrite", action="store_true", help="Overwrite existing .glb files.")
    parser.add_argument(
        "--validate",
        action="store_true",
        help="Re-import every exported GLB and verify that geometry exists.",
    )
    return parser.parse_args(_argv_after_blender_separator())


def _geometry_objects() -> list[bpy.types.Object]:
    return [obj for obj in bpy.context.scene.objects if obj.type in GEOMETRY_TYPES]


def _select_objects(objects: list[bpy.types.Object]) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    if objects:
        bpy.context.view_layer.objects.active = objects[0]


def _gltf_export_kwargs(target_file: Path) -> dict:
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
    return {key: value for key, value in kwargs.items() if key in supported}


def _export_one(source_file: Path, target_file: Path, overwrite: bool) -> tuple[int, int, int]:
    if target_file.exists() and not overwrite:
        print(f"[SKIP] {target_file.name} exists")
        return 0, 0, target_file.stat().st_size

    bpy.ops.wm.open_mainfile(filepath=str(source_file))
    bpy.context.view_layer.update()

    objects = _geometry_objects()
    if not objects:
        raise RuntimeError(f"{source_file.name} contains no supported geometry objects.")

    _select_objects(objects)
    target_file.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(**_gltf_export_kwargs(target_file))

    mesh_count = sum(1 for obj in objects if obj.type == "MESH")
    material_count = len([material for material in bpy.data.materials if material.users > 0])
    return mesh_count, material_count, target_file.stat().st_size


def _validate_glb(target_file: Path) -> int:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(target_file))
    bpy.context.view_layer.update()

    object_count = len(_geometry_objects())
    if object_count == 0:
        raise RuntimeError(f"{target_file.name} imports without geometry.")
    return object_count


def main() -> int:
    args = _parse_args()
    source_dir = Path(args.source)
    target_dir = Path(args.target)

    if not source_dir.is_dir():
        raise FileNotFoundError(f"Source folder does not exist: {source_dir}")

    blend_files = sorted(source_dir.glob("*.blend"))
    if not blend_files:
        raise RuntimeError(f"No .blend files found in {source_dir}")

    exported: list[Path] = []
    for source_file in blend_files:
        target_file = target_dir / f"{source_file.stem}.glb"
        mesh_count, material_count, file_size = _export_one(source_file, target_file, args.overwrite)
        if mesh_count > 0:
            print(
                f"[EXPORT] {source_file.name} -> {target_file.name} "
                f"meshes={mesh_count} materials={material_count} bytes={file_size}"
            )
        exported.append(target_file)

    if args.validate:
        for target_file in exported:
            object_count = _validate_glb(target_file)
            print(f"[VALID] {target_file.name} objects={object_count}")

    print(f"[DONE] Exported {len(exported)} GLB file(s) to {target_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
