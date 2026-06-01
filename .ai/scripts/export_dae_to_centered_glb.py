#!/usr/bin/env python3
"""Export COLLADA models to centered GLB files through Blender."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import bpy
from mathutils import Vector


GEOMETRY_TYPES = {"MESH", "CURVE", "SURFACE", "FONT", "META"}


def _argv_after_blender_separator() -> list[str]:
    if "--" not in sys.argv:
        return []
    return sys.argv[sys.argv.index("--") + 1 :]


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Export .dae files to centered .glb files.")
    parser.add_argument("--source", required=True, help="Folder containing .dae models.")
    parser.add_argument("--target", required=True, help="Folder that receives .glb files.")
    parser.add_argument("--textures", default="", help="Optional folder containing PNG textures to assign by material name.")
    parser.add_argument(
        "--house-theme",
        default="Houses Colorscheme 2.png",
        help="Texture file used for every HouseDiffuse/HouseWindow material.",
    )
    parser.add_argument("--overwrite", action="store_true", help="Overwrite existing .glb files.")
    parser.add_argument("--apply-textures", action="store_true", help="Assign known texture files before export.")
    parser.add_argument(
        "--validate",
        action="store_true",
        help="Re-import every exported .glb and validate that its bounding box is centered.",
    )
    parser.add_argument(
        "--tolerance",
        type=float,
        default=0.001,
        help="Maximum accepted absolute center offset during validation.",
    )
    return parser.parse_args(_argv_after_blender_separator())


def _texture_catalog(texture_dir: Path) -> dict[str, Path]:
    if not texture_dir.is_dir():
        raise FileNotFoundError(f"Texture folder does not exist: {texture_dir}")
    return {path.name.lower(): path for path in texture_dir.glob("*.png")}


def _texture_name_for_material(
    material_name: str,
    house_theme: str,
    normal: bool = False,
) -> str:
    name = material_name.lower()

    if name == "foliage":
        return "FoliageNormal.png" if normal else "FoliageColor.png"
    if name == "foliage2":
        return "FoliageNormal2.png" if normal else "FoliageColor2.png"
    if name == "foliage3":
        return "FoliageNormal3.png" if normal else "FoliageColor3.png"
    if "tree" in name:
        return "" if normal else "TreesColorscheme.png"
    if "ship" in name:
        return "" if normal else "Ship Colorscheme.png"
    if "ground" in name:
        return "GroundDirtNormal.png" if normal else "GroundDirtColor.png"
    if "rock" in name:
        return "GroundTilesBrokenNormal.png" if normal else "GroundTilesBrokenColor.png"
    if "brick" in name:
        return "GroundTilesNormal.png" if normal else "GroundTilesColor.png"
    if "wood" in name:
        return "" if normal else "GroundDirtColor.png"
    if "house" in name:
        return "" if normal else house_theme
    return ""


def _image_from_catalog(catalog: dict[str, Path], texture_name: str):
    if not texture_name:
        return None
    path = catalog.get(texture_name.lower())
    if path is None:
        return None
    image = bpy.data.images.load(str(path), check_existing=True)
    image.pack()
    return image


def _principled_node(material: bpy.types.Material):
    if not material.use_nodes:
        material.use_nodes = True
    for node in material.node_tree.nodes:
        if node.bl_idname == "ShaderNodeBsdfPrincipled":
            return node
    return material.node_tree.nodes.new("ShaderNodeBsdfPrincipled")


def _set_material_texture(
    material: bpy.types.Material,
    color_image,
    normal_image,
    alpha_cutout: bool,
) -> None:
    bsdf = _principled_node(material)
    nodes = material.node_tree.nodes
    links = material.node_tree.links

    if color_image is not None:
        color_node = nodes.new("ShaderNodeTexImage")
        color_node.name = f"{material.name}_Albedo"
        color_node.image = color_image
        color_node.extension = "REPEAT"
        links.new(color_node.outputs["Color"], bsdf.inputs["Base Color"])
        if alpha_cutout and "Alpha" in color_node.outputs and "Alpha" in bsdf.inputs:
            links.new(color_node.outputs["Alpha"], bsdf.inputs["Alpha"])
            material.blend_method = "CLIP"
            material.alpha_threshold = 0.4
            material.use_screen_refraction = False

    if normal_image is not None:
        normal_image.colorspace_settings.name = "Non-Color"
        normal_texture = nodes.new("ShaderNodeTexImage")
        normal_texture.name = f"{material.name}_Normal"
        normal_texture.image = normal_image
        normal_map = nodes.new("ShaderNodeNormalMap")
        links.new(normal_texture.outputs["Color"], normal_map.inputs["Color"])
        links.new(normal_map.outputs["Normal"], bsdf.inputs["Normal"])


def _apply_textures(source_file: Path, texture_dir: Path, house_theme: str) -> dict[str, str]:
    catalog = _texture_catalog(texture_dir)
    applied: dict[str, str] = {}
    for material in bpy.data.materials:
        color_name = _texture_name_for_material(material.name, house_theme, normal=False)
        normal_name = _texture_name_for_material(material.name, house_theme, normal=True)
        color_image = _image_from_catalog(catalog, color_name)
        normal_image = _image_from_catalog(catalog, normal_name)
        if color_image is None and normal_image is None:
            continue
        _set_material_texture(
            material,
            color_image,
            normal_image,
            material.name.lower().startswith("foliage"),
        )
        applied[material.name] = ", ".join(part for part in (color_name, normal_name) if part)
    return applied


def _reset_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()

    # Keep each source import isolated so old meshes/materials cannot leak into the next export.
    for collection in (
        bpy.data.meshes,
        bpy.data.curves,
        bpy.data.materials,
        bpy.data.images,
        bpy.data.textures,
        bpy.data.cameras,
        bpy.data.lights,
        bpy.data.armatures,
    ):
        for datablock in list(collection):
            if datablock.users == 0:
                collection.remove(datablock)


def _geometry_objects() -> list[bpy.types.Object]:
    return [obj for obj in bpy.context.scene.objects if obj.type in GEOMETRY_TYPES]


def _world_bounds(objects: list[bpy.types.Object]) -> tuple[Vector, Vector]:
    points: list[Vector] = []
    for obj in objects:
        if not obj.bound_box:
            continue
        points.extend(obj.matrix_world @ Vector(corner) for corner in obj.bound_box)

    if not points:
        raise RuntimeError("No geometry bounds found.")

    min_corner = Vector((min(point.x for point in points), min(point.y for point in points), min(point.z for point in points)))
    max_corner = Vector((max(point.x for point in points), max(point.y for point in points), max(point.z for point in points)))
    return min_corner, max_corner


def _center_scene_geometry() -> Vector:
    objects = _geometry_objects()
    if not objects:
        raise RuntimeError("Imported file contains no supported geometry objects.")

    min_corner, max_corner = _world_bounds(objects)
    center = (min_corner + max_corner) * 0.5

    root_objects = [obj for obj in bpy.context.scene.objects if obj.parent is None]
    for obj in root_objects:
        obj.location -= center

    bpy.context.view_layer.update()
    return center


def _validate_centered_glb(path: Path, tolerance: float) -> Vector:
    _reset_scene()
    bpy.ops.import_scene.gltf(filepath=str(path))
    bpy.context.view_layer.update()
    min_corner, max_corner = _world_bounds(_geometry_objects())
    center = (min_corner + max_corner) * 0.5
    max_offset = max(abs(center.x), abs(center.y), abs(center.z))
    if max_offset > tolerance:
        raise RuntimeError(f"{path.name} is not centered: center={tuple(round(v, 6) for v in center)}")
    return center


def _export_one(
    source_file: Path,
    target_file: Path,
    texture_dir: Path | None,
    house_theme: str,
    apply_textures: bool,
    overwrite: bool,
    validate: bool,
    tolerance: float,
) -> None:
    if target_file.exists() and not overwrite:
        print(f"[SKIP] {target_file.name} exists")
        return

    _reset_scene()
    bpy.ops.wm.collada_import(filepath=str(source_file))
    bpy.context.view_layer.update()

    offset = _center_scene_geometry()
    applied_textures: dict[str, str] = {}
    if apply_textures:
        if texture_dir is None:
            raise RuntimeError("--apply-textures requires --textures")
        applied_textures = _apply_textures(source_file, texture_dir, house_theme)
    target_file.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(target_file),
        export_format="GLB",
        export_yup=True,
        use_selection=False,
        check_existing=False,
        export_materials="EXPORT",
        export_image_format="AUTO",
    )

    if validate:
        validated_center = _validate_centered_glb(target_file, tolerance)
        center_text = ", ".join(f"{value:.6f}" for value in validated_center)
        texture_text = f" textures={len(applied_textures)}" if apply_textures else ""
        print(f"[OK] {source_file.name} -> {target_file.name} centered=({center_text}){texture_text}")
    else:
        offset_text = ", ".join(f"{value:.6f}" for value in offset)
        texture_text = f" textures={len(applied_textures)}" if apply_textures else ""
        print(f"[OK] {source_file.name} -> {target_file.name} moved_by=(-{offset_text}){texture_text}")


def main() -> int:
    args = _parse_args()
    source_dir = Path(args.source)
    target_dir = Path(args.target)
    texture_dir = Path(args.textures) if args.textures else None

    if not source_dir.is_dir():
        raise FileNotFoundError(f"Source folder does not exist: {source_dir}")
    if args.apply_textures and texture_dir is None:
        raise RuntimeError("--apply-textures requires --textures")

    dae_files = sorted(source_dir.glob("*.dae"))
    if not dae_files:
        raise RuntimeError(f"No .dae files found in {source_dir}")

    for source_file in dae_files:
        target_file = target_dir / f"{source_file.stem}.glb"
        _export_one(
            source_file,
            target_file,
            texture_dir,
            args.house_theme,
            args.apply_textures,
            args.overwrite,
            args.validate,
            args.tolerance,
        )

    print(f"Exported {len(dae_files)} model(s) to {target_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
