#!/usr/bin/env python3
"""Inspect external GLB/GLTF/FBX geometry and optional spatial groups in Blender."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import bpy
from mathutils import Vector


def _argv_after_blender_separator() -> list[str]:
    if "--" not in sys.argv:
        return []
    return sys.argv[sys.argv.index("--") + 1 :]


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", action="append", required=True, help="Model file to inspect.")
    parser.add_argument(
        "--cluster-gap",
        type=float,
        default=0.0,
        help="When positive, group mesh centers along X whenever the gap exceeds this value.",
    )
    parser.add_argument(
        "--details",
        type=int,
        default=0,
        help="Print this many largest mesh objects with dimensions and centers.",
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


def _world_corners(obj: bpy.types.Object) -> list[Vector]:
    return [obj.matrix_world @ Vector(corner) for corner in obj.bound_box]


def _center_x(obj: bpy.types.Object) -> float:
    corners = _world_corners(obj)
    return (min(point.x for point in corners) + max(point.x for point in corners)) * 0.5


def _bounds(objects: list[bpy.types.Object]) -> tuple[Vector, Vector]:
    corners = [point for obj in objects for point in _world_corners(obj)]
    return (
        Vector(
            (
                min(point.x for point in corners),
                min(point.y for point in corners),
                min(point.z for point in corners),
            )
        ),
        Vector(
            (
                max(point.x for point in corners),
                max(point.y for point in corners),
                max(point.z for point in corners),
            )
        ),
    )


def _inspect(source_file: Path, cluster_gap: float, detail_count: int) -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    _import_asset(source_file)
    bpy.context.view_layer.update()

    meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    if not meshes:
        raise RuntimeError(f"{source_file} contains no mesh objects.")

    minimum, maximum = _bounds(meshes)
    dimensions = maximum - minimum
    print(
        f"[ASSET] {source_file} meshes={len(meshes)} "
        f"dimensions=({dimensions.x:.3f}, {dimensions.y:.3f}, {dimensions.z:.3f}) "
        f"center=({(minimum.x + maximum.x) * 0.5:.3f}, "
        f"{(minimum.y + maximum.y) * 0.5:.3f}, {(minimum.z + maximum.z) * 0.5:.3f})"
    )
    print("[NAMES]", ", ".join(obj.name for obj in meshes[:12]))

    if detail_count > 0:
        ranked = sorted(
            meshes,
            key=lambda obj: obj.dimensions.x * obj.dimensions.y * obj.dimensions.z,
            reverse=True,
        )
        for obj in ranked[:detail_count]:
            object_minimum, object_maximum = _bounds([obj])
            object_dimensions = object_maximum - object_minimum
            center = (object_minimum + object_maximum) * 0.5
            print(
                f"[MESH] {obj.name} "
                f"dimensions=({object_dimensions.x:.3f}, "
                f"{object_dimensions.y:.3f}, {object_dimensions.z:.3f}) "
                f"center=({center.x:.3f}, {center.y:.3f}, {center.z:.3f})"
            )

    if cluster_gap <= 0.0:
        return

    ordered = sorted((_center_x(obj), obj.name) for obj in meshes)
    clusters: list[list[tuple[float, str]]] = []
    for center_x, name in ordered:
        if not clusters or center_x - clusters[-1][-1][0] > cluster_gap:
            clusters.append([])
        clusters[-1].append((center_x, name))

    print(f"[CLUSTERS] count={len(clusters)} gap={cluster_gap:.3f}")
    for index, cluster in enumerate(clusters):
        cluster_names = {name for _, name in cluster}
        cluster_meshes = [obj for obj in meshes if obj.name in cluster_names]
        cluster_minimum, cluster_maximum = _bounds(cluster_meshes)
        cluster_dimensions = cluster_maximum - cluster_minimum
        print(
            f"  {index}: meshes={len(cluster)} "
            f"x=({cluster[0][0]:.3f}, {cluster[-1][0]:.3f}) "
            f"dimensions=({cluster_dimensions.x:.3f}, "
            f"{cluster_dimensions.y:.3f}, {cluster_dimensions.z:.3f}) "
            f"sample={','.join(name for _, name in cluster[:4])}"
        )


def main() -> int:
    args = _parse_args()
    for source in args.source:
        source_file = Path(source).resolve()
        if not source_file.is_file():
            raise FileNotFoundError(source_file)
        _inspect(source_file, args.cluster_gap, args.details)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
