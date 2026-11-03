#!/usr/bin/env python3
"""
Generates Deadfall Square's low-poly 3D models for Roblox, without Blender.

Outputs (in roblox/assets/ unless --out is given):
  DeadfallMeshes.obj   one OBJ with a named object per model (import with Studio's "Import 3D")
  DeadfallMeshes.mtl   materials: "Palette" (flat colours from the texture) and "Plain" (tinted in code)
  DeadfallPalette.png  colour palette texture; each face samples the centre of one colour cell
And roblox/src/shared/Config/MeshSizes.luau: every model's exact bounding box in studs,
which the game uses to size the imported MeshParts regardless of importer unit settings.

Every model is built from convex primitives (boxes, tapered boxes, cylinders,
low-poly spheres). Faces are flat-shaded and wound outward; this is checked.

Usage:
  python3 roblox/tools/make_meshes.py          # write files
  python3 roblox/tools/make_meshes.py --check  # verify committed files are up to date (CI)

Standard library only (zlib/struct for the PNG), so CI needs nothing installed.
"""
from __future__ import annotations

import argparse
import math
import os
import struct
import sys
import tempfile
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
S = 3.0  # studs per metre, matching Config/Constants.STUDS

CELL = 16  # palette cell size in pixels
GRID = 16  # palette is GRID x GRID cells

Vec = tuple[float, float, float]


# --------------------------------------------------------------------------- maths


def rot_yxz(rx: float, ry: float, rz: float):
    """Rotation matrix R = Ry * Rx * Rz (Roblox CFrame.fromEulerAnglesYXZ)."""
    cx, sx = math.cos(rx), math.sin(rx)
    cy, sy = math.cos(ry), math.sin(ry)
    cz, sz = math.cos(rz), math.sin(rz)
    ry_m = ((cy, 0, sy), (0, 1, 0), (-sy, 0, cy))
    rx_m = ((1, 0, 0), (0, cx, -sx), (0, sx, cx))
    rz_m = ((cz, -sz, 0), (sz, cz, 0), (0, 0, 1))
    return matmul(matmul(ry_m, rx_m), rz_m)


def matmul(a, b):
    return tuple(tuple(sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)) for i in range(3))


def apply(m, p: Vec) -> Vec:
    return (
        m[0][0] * p[0] + m[0][1] * p[1] + m[0][2] * p[2],
        m[1][0] * p[0] + m[1][1] * p[1] + m[1][2] * p[2],
        m[2][0] * p[0] + m[2][1] * p[1] + m[2][2] * p[2],
    )


def sub(a: Vec, b: Vec) -> Vec:
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def cross(a: Vec, b: Vec) -> Vec:
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def dot(a: Vec, b: Vec) -> float:
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def normalize(v: Vec) -> Vec:
    n = math.sqrt(dot(v, v))
    return (v[0] / n, v[1] / n, v[2] / n) if n > 1e-12 else (0.0, 1.0, 0.0)


# ---------------------------------------------------------------------- primitives
# Each primitive returns (vertices, triangles) of a convex solid centred on the origin.


def hexahedron(bottom: list[Vec], top: list[Vec]):
    """Eight corners: bottom quad then top quad, both in the same winding order."""
    v = list(bottom) + list(top)
    quads = [(0, 1, 2, 3), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
    tris = []
    for a, b, c, d in quads:
        tris += [(a, b, c), (a, c, d)]
    return v, tris


def frustum(w0: float, d0: float, w1: float, d1: float, h: float, top_dz: float = 0.0):
    """Tapered box: bottom w0 x d0, top w1 x d1 (optionally shifted forward by top_dz)."""
    y0, y1 = -h / 2, h / 2
    bottom = [(-w0 / 2, y0, -d0 / 2), (w0 / 2, y0, -d0 / 2), (w0 / 2, y0, d0 / 2), (-w0 / 2, y0, d0 / 2)]
    top = [
        (-w1 / 2, y1, -d1 / 2 + top_dz),
        (w1 / 2, y1, -d1 / 2 + top_dz),
        (w1 / 2, y1, d1 / 2 + top_dz),
        (-w1 / 2, y1, d1 / 2 + top_dz),
    ]
    return hexahedron(bottom, top)


def box(w: float, h: float, d: float):
    return frustum(w, d, w, d, h)


def cylinder(r_bottom: float, r_top: float, h: float, segments: int = 8):
    """Vertical (Y) cylinder or cone, capped."""
    v: list[Vec] = []
    tris = []
    for i in range(segments):
        a = 2 * math.pi * i / segments
        v.append((math.cos(a) * r_bottom, -h / 2, math.sin(a) * r_bottom))
    for i in range(segments):
        a = 2 * math.pi * i / segments
        v.append((math.cos(a) * r_top, h / 2, math.sin(a) * r_top))
    cb = len(v)
    v.append((0, -h / 2, 0))
    ct = len(v)
    v.append((0, h / 2, 0))
    for i in range(segments):
        j = (i + 1) % segments
        tris.append((cb, j, i))
        tris.append((ct, segments + i, segments + j))
        if r_top > 1e-9:
            tris += [(i, j, segments + j), (i, segments + j, segments + i)]
        else:
            tris.append((i, j, ct))
    return v, tris


def sphere(r: float, rings: int = 4, segments: int = 7):
    """Low-poly UV sphere."""
    v: list[Vec] = [(0, r, 0)]
    for ring in range(1, rings):
        phi = math.pi * ring / rings
        for s in range(segments):
            th = 2 * math.pi * s / segments
            v.append((math.sin(phi) * math.cos(th) * r, math.cos(phi) * r, math.sin(phi) * math.sin(th) * r))
    v.append((0, -r, 0))
    tris = []
    bottom = len(v) - 1
    for s in range(segments):
        t = (s + 1) % segments
        tris.append((0, 1 + s, 1 + t))
    for ring in range(rings - 2):
        a0 = 1 + ring * segments
        b0 = a0 + segments
        for s in range(segments):
            t = (s + 1) % segments
            tris += [(a0 + s, b0 + s, b0 + t), (a0 + s, b0 + t, a0 + t)]
    last = 1 + (rings - 2) * segments
    for s in range(segments):
        t = (s + 1) % segments
        tris.append((bottom, last + t, last + s))
    return v, tris


# --------------------------------------------------------------------------- model


class Palette:
    def __init__(self) -> None:
        self.colors: list[str] = []

    def index(self, hex_color: str) -> int:
        c = hex_color.lower()
        if c not in self.colors:
            if len(self.colors) >= GRID * GRID:
                raise ValueError("palette full")
            self.colors.append(c)
        return self.colors.index(c)

    def uv(self, i: int) -> tuple[float, float]:
        cx, cy = i % GRID, i // GRID
        # OBJ v=0 is the bottom of the image.
        return ((cx + 0.5) / GRID, 1 - (cy + 0.5) / GRID)


class Model:
    """A named mesh built from convex primitives. Units are studs; +Y up."""

    def __init__(self, name: str, palette: Palette, textured: bool = True) -> None:
        self.name = name
        self.palette = palette
        self.textured = textured
        self.verts: list[Vec] = []
        self.tris: list[tuple[int, int, int, int]] = []  # (a, b, c, colour index)

    def add(self, prim, color: str, pos: Vec = (0, 0, 0), rot: Vec = (0, 0, 0), scale: Vec = (1, 1, 1)) -> None:
        pv, pt = prim
        m = rot_yxz(*rot)
        base = len(self.verts)
        world = [apply(m, (p[0] * scale[0], p[1] * scale[1], p[2] * scale[2])) for p in pv]
        world = [(p[0] + pos[0], p[1] + pos[1], p[2] + pos[2]) for p in world]
        centre = tuple(sum(p[k] for p in world) / len(world) for k in range(3))
        ci = self.palette.index(color) if self.textured else 0
        for a, b, c in pt:
            n = cross(sub(world[b], world[a]), sub(world[c], world[a]))
            fc = tuple((world[a][k] + world[b][k] + world[c][k]) / 3 for k in range(3))
            # Convex primitive: every face must point away from its centre.
            if dot(n, sub(fc, centre)) < 0:
                b, c = c, b
            self.tris.append((base + a, base + b, base + c, ci))
        self.verts += world

    def bounds(self) -> tuple[Vec, Vec]:
        lo = tuple(min(p[k] for p in self.verts) for k in range(3))
        hi = tuple(max(p[k] for p in self.verts) for k in range(3))
        return lo, hi

    def centre(self) -> None:
        """Moves the bounding-box centre to the origin (MeshPart pivots are bbox centres)."""
        lo, hi = self.bounds()
        c = tuple((lo[k] + hi[k]) / 2 for k in range(3))
        self.verts = [(p[0] - c[0], p[1] - c[1], p[2] - c[2]) for p in self.verts]

    def fit(self, size: Vec) -> None:
        """Centres and scales the mesh so its bounding box is exactly `size`."""
        self.centre()
        lo, hi = self.bounds()
        k = [size[i] / max(hi[i] - lo[i], 1e-9) for i in range(3)]
        self.verts = [(p[0] * k[0], p[1] * k[1], p[2] * k[2]) for p in self.verts]

    def size(self) -> Vec:
        lo, hi = self.bounds()
        return tuple(round(hi[k] - lo[k], 3) for k in range(3))


# Helpers that take metres (game units) and convert to studs. `mirror` flips Z so a
# model authored with its front at +Z (the browser version) faces -Z (Roblox forward).


def mbox(m: Model, w, h, d, color, x, y, z, rx=0.0, ry=0.0, rz=0.0, mirror=False, taper=None):
    if mirror:
        z, rx, ry = -z, -rx, -ry
    prim = box(w * S, h * S, d * S) if taper is None else frustum(w * S, d * S, taper[0] * S, taper[1] * S, h * S)
    m.add(prim, color, (x * S, y * S, z * S), (rx, ry, rz))


def mcyl(m: Model, r0, r1, h, seg, color, x, y, z, rx=0.0, ry=0.0, rz=0.0, mirror=False):
    if mirror:
        z, rx, ry = -z, -rx, -ry
    m.add(cylinder(r0 * S, r1 * S, h * S, seg), color, (x * S, y * S, z * S), (rx, ry, rz))


def mball(m: Model, r, color, x, y, z, sx=1.0, sy=1.0, sz=1.0, rings=4, seg=7):
    m.add(sphere(r * S, rings, seg), color, (x * S, y * S, z * S), (0, 0, 0), (sx, sy, sz))


# ------------------------------------------------------------------------- models

METAL = "#2c2f33"
DARK = "#1c1d1f"
WOOD = "#6b4528"
GOLD = "#d8b040"
HP = math.pi / 2


def zombie_parts(p: Palette) -> list[Model]:
    """Untextured body parts (tinted per zombie type in code). Front faces +Z."""
    out = []

    torso = Model("ZombieTorso", p, textured=False)
    torso.add(frustum(0.52, 0.32, 0.6, 0.36, 0.62, 0.03), "#fff", (0, -0.05, 0))
    torso.add(box(0.36, 0.2, 0.08), "#fff", (0, 0.06, 0.17))  # chest / ribcage
    torso.add(frustum(0.6, 0.36, 0.42, 0.26, 0.14, 0.02), "#fff", (0, 0.31, 0.015))  # shoulders
    torso.add(box(0.5, 0.08, 0.34), "#fff", (0, -0.36, 0), (0, 0, 0.06))  # torn hem
    torso.fit((0.6, 0.76, 0.36))
    out.append(torso)

    head = Model("ZombieHead", p, textured=False)
    head.add(frustum(0.3, 0.32, 0.36, 0.36, 0.26), "#fff", (0, 0.04, -0.01))  # cranium
    head.add(box(0.38, 0.06, 0.08), "#fff", (0, 0.1, 0.17))  # brow ridge
    head.add(frustum(0.26, 0.2, 0.3, 0.24, 0.12, 0.02), "#fff", (0, -0.13, 0.04), (0.25, 0, 0))  # sagging jaw
    head.add(box(0.06, 0.1, 0.06), "#fff", (0, 0.0, 0.2))  # nose
    head.add(box(0.05, 0.1, 0.07), "#fff", (-0.19, 0.02, 0))  # ears
    head.add(box(0.05, 0.1, 0.07), "#fff", (0.19, 0.02, 0))
    head.fit((0.38, 0.38, 0.38))
    out.append(head)

    arm = Model("ZombieArm", p, textured=False)
    arm.add(frustum(0.13, 0.15, 0.17, 0.19, 0.34), "#fff", (0, 0.2, 0))  # upper arm
    arm.add(frustum(0.11, 0.12, 0.14, 0.16, 0.3), "#fff", (0, -0.12, 0.005))  # forearm
    arm.add(box(0.15, 0.1, 0.13), "#fff", (0, -0.31, 0.01))  # hand
    for x in (-0.045, 0, 0.045):
        arm.add(cylinder(0.022, 0.006, 0.09, 4), "#fff", (x, -0.39, 0.03))  # claws
    arm.fit((0.17, 0.74, 0.19))
    out.append(arm)

    leg = Model("ZombieLeg", p, textured=False)
    leg.add(frustum(0.17, 0.19, 0.22, 0.23, 0.38), "#fff", (0, 0.2, 0))  # thigh
    leg.add(frustum(0.14, 0.16, 0.17, 0.19, 0.32), "#fff", (0, -0.14, 0))  # shin
    leg.add(box(0.18, 0.1, 0.26), "#fff", (0, -0.36, 0.04))  # foot
    leg.fit((0.22, 0.82, 0.24))
    out.append(leg)
    return out


def guns(p: Palette) -> list[Model]:
    """Player weapons. Grip near the origin, barrel toward -Z (Roblox forward)."""
    out = []

    def gun(name):
        m = Model(f"Gun_{name}", p)
        out.append(m)
        return m

    g = gun("pistol")
    mbox(g, 0.1, 0.11, 0.34, METAL, 0, 0.05, 0.1, mirror=True)
    mbox(g, 0.104, 0.03, 0.3, "#45494f", 0, 0.115, 0.1, mirror=True)  # slide top
    mbox(g, 0.08, 0.17, 0.09, DARK, 0, -0.07, -0.02, rx=-0.25, mirror=True)
    mbox(g, 0.02, 0.03, 0.02, DARK, 0, 0.14, 0.24, mirror=True)  # sight

    g = gun("shotgun")
    mbox(g, 0.11, 0.12, 0.62, METAL, 0, 0.06, 0.28, mirror=True)
    mcyl(g, 0.035, 0.035, 0.5, 6, DARK, 0, -0.02, 0.32, rx=HP, mirror=True)
    mbox(g, 0.13, 0.1, 0.22, WOOD, 0, -0.02, 0.36, mirror=True)  # pump
    mbox(g, 0.1, 0.15, 0.36, WOOD, 0, 0.0, -0.18, rx=0.2, mirror=True)  # stock

    g = gun("smg")
    mbox(g, 0.1, 0.14, 0.42, "#3a3d42", 0, 0.05, 0.14, mirror=True)
    mbox(g, 0.06, 0.06, 0.14, DARK, 0, 0.07, 0.42, mirror=True)
    mbox(g, 0.07, 0.24, 0.08, DARK, 0, -0.13, 0.14, rx=0.15, mirror=True)  # magazine
    mbox(g, 0.07, 0.14, 0.08, DARK, 0, -0.08, -0.02, rx=-0.3, mirror=True)
    mbox(g, 0.05, 0.05, 0.16, DARK, 0, 0.06, -0.14, mirror=True)  # folding stock

    g = gun("rifle")
    mbox(g, 0.1, 0.14, 0.62, "#3b3f36", 0, 0.06, 0.2, mirror=True)
    mcyl(g, 0.025, 0.025, 0.3, 6, DARK, 0, 0.07, 0.62, rx=HP, mirror=True)
    mbox(g, 0.07, 0.2, 0.09, DARK, 0, -0.11, 0.22, rx=0.2, mirror=True)
    mbox(g, 0.09, 0.15, 0.3, "#3b3f36", 0, 0.02, -0.2, mirror=True)
    mbox(g, 0.05, 0.06, 0.16, DARK, 0, 0.17, 0.18, mirror=True)  # carry handle / optic
    mbox(g, 0.11, 0.09, 0.2, "#2f322b", 0, 0.03, 0.4, mirror=True)  # handguard

    g = gun("sniper")
    mbox(g, 0.1, 0.13, 0.7, "#4a4632", 0, 0.05, 0.22, mirror=True)
    mcyl(g, 0.022, 0.022, 0.5, 6, DARK, 0, 0.07, 0.8, rx=HP, mirror=True)
    mcyl(g, 0.045, 0.045, 0.32, 8, DARK, 0, 0.18, 0.2, rx=HP, mirror=True)  # scope
    mcyl(g, 0.055, 0.045, 0.05, 8, "#6a8ea8", 0, 0.18, 0.37, rx=HP, mirror=True)  # lens
    mbox(g, 0.09, 0.16, 0.34, "#4a4632", 0, 0.0, -0.24, rx=0.15, mirror=True)
    mbox(g, 0.02, 0.12, 0.02, DARK, -0.03, -0.04, 0.62, rz=0.3, mirror=True)  # bipod
    mbox(g, 0.02, 0.12, 0.02, DARK, 0.03, -0.04, 0.62, rz=-0.3, mirror=True)

    g = gun("flamer")
    mbox(g, 0.12, 0.14, 0.6, "#7a2a22", 0, 0.05, 0.22, mirror=True)
    mcyl(g, 0.11, 0.11, 0.42, 8, "#c4a23a", 0, -0.1, 0.1, rx=HP, mirror=True)  # fuel tank
    mcyl(g, 0.05, 0.07, 0.18, 8, DARK, 0, 0.06, 0.6, rx=HP, mirror=True)
    mbox(g, 0.03, 0.03, 0.03, "#ff8a2a", 0, 0.02, 0.7, mirror=True)  # pilot light

    g = gun("launcher")
    mcyl(g, 0.1, 0.1, 0.55, 8, "#4d5a3a", 0, 0.07, 0.24, rx=HP, mirror=True)
    mcyl(g, 0.12, 0.12, 0.2, 8, DARK, 0, 0.07, 0.05, rx=HP, mirror=True)  # drum
    mbox(g, 0.07, 0.18, 0.08, DARK, 0, -0.1, 0.1, rx=0.2, mirror=True)
    mbox(g, 0.09, 0.13, 0.3, "#4d5a3a", 0, 0.0, -0.22, mirror=True)

    for m in out:
        m.centre()
    return out


def pickups(p: Palette) -> list[Model]:
    out = []

    m = Model("Pickup_ammo", p)
    mbox(m, 0.62, 0.36, 0.42, "#4a5a2a", 0, 0, 0)
    mbox(m, 0.64, 0.06, 0.44, "#2e3a1a", 0, 0.12, 0)
    for i in range(4):
        mcyl(m, 0.04, 0.04, 0.2, 6, GOLD, -0.18 + i * 0.12, 0.28, 0)
        mcyl(m, 0.04, 0.0, 0.06, 6, "#b07a20", -0.18 + i * 0.12, 0.41, 0)
    out.append(m)

    m = Model("Pickup_health", p)
    mbox(m, 0.6, 0.4, 0.45, "#f2f2f2", 0, 0, 0)
    mbox(m, 0.36, 0.1, 0.46, "#d42a3a", 0, 0.05, 0)
    mbox(m, 0.12, 0.34, 0.46, "#d42a3a", 0, 0.05, 0)
    mbox(m, 0.2, 0.06, 0.12, "#bbbbbb", 0, 0.23, 0)  # handle
    out.append(m)

    m = Model("Pickup_armor", p)
    mbox(m, 0.5, 0.6, 0.12, "#2e5f8f", 0, 0.05, 0, taper=(0.42, 0.12))
    mbox(m, 0.4, 0.15, 0.14, "#4a8ad0", 0, 0.2, 0)
    mbox(m, 0.3, 0.3, 0.14, "#24476c", 0, -0.1, 0)
    out.append(m)

    m = Model("Pickup_coins", p)
    for i in range(4):
        mcyl(m, 0.2, 0.2, 0.07, 10, "#f0c030" if i % 2 else "#d8a820", 0.02 * (i % 2), -0.1 + i * 0.08, 0)
    mcyl(m, 0.2, 0.2, 0.07, 10, "#f0c030", 0.28, -0.1, 0.1)
    out.append(m)

    m = Model("Pickup_weapon", p)
    mbox(m, 0.9, 0.42, 0.55, "#6a4a2a", 0, -0.1, 0)
    mbox(m, 0.92, 0.08, 0.57, "#3e2a18", 0, 0.06, 0)
    mbox(m, 0.1, 0.44, 0.59, "#3e2a18", 0.3, -0.1, 0)
    mbox(m, 0.1, 0.44, 0.59, "#3e2a18", -0.3, -0.1, 0)
    mbox(m, 0.5, 0.06, 0.2, "#c070ff", 0, 0.12, 0)  # glowing stripe
    out.append(m)

    for m in out:
        m.centre()
    return out


def structures(p: Palette) -> list[Model]:
    out = []

    m = Model("Barricade", p)
    for x in (-1.3, 0, 1.3):
        mbox(m, 0.18, 1.2, 0.18, "#4f3a26", x, 0.6, 0)
    for i in range(3):
        mbox(m, 2.95, 0.28, 0.12, "#8a6238" if i % 2 else "#7a5634", 0, 0.3 + i * 0.36, 0.08, rz=(i - 1) * 0.03)
    for i in range(5):
        x = -1.2 + i * 0.6
        mcyl(m, 0.07, 0.0, 0.6, 5, "#b8a888", x, 0.75, -0.3, rx=-1.1)
    mbox(m, 2.9, 0.08, 0.1, "#3a3a3a", 0, 0.95, 0.15)  # wire
    out.append(m)

    m = Model("TurretBase", p)
    mbox(m, 1.5, 0.12, 1.5, "#3a3d42", 0, 0.06, 0)
    for x, z in ((-0.44, -0.44), (0.44, -0.44), (-0.44, 0.44), (0.44, 0.44)):
        mbox(m, 0.12, 0.6, 0.12, "#2a2c30", x, 0.35, z, rz=0.2 if x * z > 0 else -0.2)
    mcyl(m, 0.32, 0.4, 0.6, 8, "#4a4f56", 0, 0.45, 0)
    mbox(m, 0.5, 0.08, 0.5, "#d8a020", 0, 0.78, 0)
    out.append(m)

    # Head: barrels toward -Z, an ammo box at the back keeps the bbox centred on the pivot.
    m = Model("TurretHead", p)
    mbox(m, 0.62, 0.38, 0.7, "#56606a", 0, 0, 0)
    mbox(m, 0.5, 0.06, 0.6, "#d8a020", 0, 0.21, 0)
    mcyl(m, 0.06, 0.06, 0.75, 6, "#1f2124", -0.12, 0.03, -0.6, rx=HP)
    mcyl(m, 0.06, 0.06, 0.75, 6, "#1f2124", 0.12, 0.03, -0.6, rx=HP)
    mbox(m, 0.16, 0.12, 0.05, "#ff3a2a", 0, 0.1, -0.36)  # sensor
    mbox(m, 0.5, 0.3, 0.6, "#3d4651", 0, -0.02, 0.6)  # ammo box
    out.append(m)

    for m in out:
        m.centre()
    return out


CAR_COLORS = ["#7a2f2a", "#2f4f6e", "#5d6a3a", "#8a8378", "#3d3a46", "#9a6b2e", "#25544f"]


def car(p: Palette, name: str, body: str, burnt: bool) -> Model:
    m = Model(name, p)
    glass = "#1a1817" if burnt else "#24323d"
    trim = "#1f1f1f"
    mbox(m, 1.9, 0.5, 4.3, body, 0, 0.6, 0)  # lower body
    mbox(m, 1.88, 0.18, 1.2, body, 0, 0.92, 1.45, taper=(1.84, 1.05))  # hood
    mbox(m, 1.88, 0.18, 0.9, body, 0, 0.92, -1.65, taper=(1.84, 0.8))  # trunk
    mbox(m, 1.8, 0.62, 2.2, body, 0, 1.15, -0.2, taper=(1.5, 1.5))  # cabin
    mbox(m, 1.82, 0.42, 2.0, glass, 0, 1.18, -0.2, taper=(1.54, 1.32))  # windows
    mbox(m, 1.92, 0.12, 0.2, trim, 0, 0.42, 2.18)  # bumpers
    mbox(m, 1.92, 0.12, 0.2, trim, 0, 0.42, -2.18)
    lights = "#2a2725" if burnt else "#f4e7b0"
    for x in (-0.6, 0.6):
        mbox(m, 0.35, 0.14, 0.05, lights, x, 0.75, 2.16)
        mbox(m, 0.35, 0.14, 0.05, "#6b1d1d", x, 0.75, -2.16)
    for side in (-1, 1):
        mbox(m, 0.08, 0.1, 0.16, body, side * 0.98, 1.05, 0.75)  # mirrors
    for x, z in ((-0.86, 1.4), (0.86, 1.4), (-0.86, -1.4), (0.86, -1.4)):
        mcyl(m, 0.38, 0.38, 0.26, 10, "#161616", x, 0.38, z, rz=HP)
        mcyl(m, 0.2, 0.2, 0.28, 8, "#5a5a5a" if not burnt else "#2a2a2a", x, 0.38, z, rz=HP)  # hubs
    m.centre()
    return m


def props(p: Palette) -> list[Model]:
    out = []

    m = Model("Crate", p)
    mbox(m, 1.15, 1.15, 1.15, "#8a6238", 0, 0, 0)
    for y in (-0.35, 0.35):
        mbox(m, 1.17, 0.14, 1.17, "#4f3a26", 0, y, 0)
    for x in (-0.5, 0.5):
        mbox(m, 0.12, 1.16, 1.19, "#4f3a26", x, 0, 0)
    out.append(m)

    for name, color in (("red", "#a33a2a"), ("yellow", "#c49a2a"), ("blue", "#2a6aa3"), ("green", "#4a7a3a")):
        m = Model(f"Barrel_{name}", p)
        mcyl(m, 0.42, 0.42, 1.1, 10, color, 0, 0, 0)
        mcyl(m, 0.44, 0.44, 0.08, 10, "#2b2b2b", 0, -0.25, 0)
        mcyl(m, 0.44, 0.44, 0.08, 10, "#2b2b2b", 0, 0.25, 0)
        mcyl(m, 0.06, 0.06, 0.04, 6, "#2b2b2b", 0.2, 0.57, 0)  # bung
        out.append(m)

    for i, color in enumerate(CAR_COLORS, start=1):
        out.append(car(p, f"Car_{i}", color, False))
    out.append(car(p, "Car_burnt", "#2e2a27", True))

    m = Model("Bus", p)
    mbox(m, 2.6, 2.4, 10, "#c48a2a", 0, 1.55, 0)
    mbox(m, 2.62, 0.5, 10.02, "#3a3632", 0, 0.55, 0)
    mbox(m, 2.64, 0.9, 8.6, "#22303a", 0, 2.0, -0.3)
    mbox(m, 2.4, 0.1, 9.6, "#a87420", 0, 2.79, 0)
    mbox(m, 2.3, 1.2, 0.06, "#22303a", 0, 2.0, 5.02)  # windscreen
    for z in (3.4, -3.4):
        for x in (-1.2, 1.2):
            mcyl(m, 0.5, 0.5, 0.35, 10, "#161616", x, 0.5, z, rz=HP)
    m.centre()
    out.append(m)

    m = Model("Dumpster", p)
    mbox(m, 2.4, 1.3, 1.3, "#2f5a3a", 0, 0.75, 0, taper=(2.5, 1.4))
    mbox(m, 2.45, 0.1, 1.35, "#24452d", 0, 1.44, 0.05, rx=0.12)
    for z in (-0.6, 0.6):
        mbox(m, 2.5, 0.12, 0.12, "#1d1d1d", 0, 0.12, z)
    for x in (-1.0, 1.0):
        mcyl(m, 0.1, 0.1, 0.1, 6, "#1d1d1d", x, 0.05, 0.5)
    out.append(m)

    m = Model("Bench", p)
    mbox(m, 2.0, 0.1, 0.55, WOOD, 0, 0.5, 0)
    mbox(m, 2.0, 0.45, 0.08, WOOD, 0, 0.85, -0.25, rx=-0.15)
    for x in (-0.85, 0.85):
        mbox(m, 0.1, 0.5, 0.5, "#2b2e31", x, 0.25, 0)
    out.append(m)

    m = Model("Barrier", p)
    mbox(m, 3.0, 0.35, 0.8, "#8d8a84", 0, 0.18, 0)
    mbox(m, 2.98, 0.65, 0.78, "#8d8a84", 0, 0.67, 0, taper=(2.98, 0.3))
    mbox(m, 3.02, 0.1, 0.32, "#c9a227", 0, 0.95, 0)
    out.append(m)

    for m in out:
        m.centre()
    return out


def build_all() -> tuple[Palette, list[Model]]:
    palette = Palette()
    models = zombie_parts(palette) + guns(palette) + pickups(palette) + structures(palette) + props(palette)
    names = [m.name for m in models]
    assert len(names) == len(set(names)), "duplicate model names"
    return palette, models


# --------------------------------------------------------------------------- output


def write_png(path: str, palette: Palette) -> None:
    size = GRID * CELL
    rows = []
    for y in range(size):
        row = bytearray([0])  # filter type 0
        for x in range(size):
            i = (y // CELL) * GRID + (x // CELL)
            c = palette.colors[i] if i < len(palette.colors) else "#ff00ff"
            row += bytes.fromhex(c[1:])
        rows.append(bytes(row))
    raw = b"".join(rows)

    def chunk(kind: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)


def fmt(v: float) -> str:
    s = f"{v:.4f}".rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s


def write_obj(path: str, mtl_name: str, palette: Palette, models: list[Model]) -> None:
    lines = [
        "# Deadfall Square models - generated by roblox/tools/make_meshes.py (do not edit)",
        f"mtllib {mtl_name}",
    ]
    for i in range(len(palette.colors)):
        u, v = palette.uv(i)
        lines.append(f"vt {fmt(u)} {fmt(v)}")
    v_offset = 1
    n_offset = 1
    for m in models:
        lines.append(f"o {m.name}")
        for p in m.verts:
            lines.append(f"v {fmt(p[0])} {fmt(p[1])} {fmt(p[2])}")
        normals = []
        for a, b, c, _ in m.tris:
            n = normalize(cross(sub(m.verts[b], m.verts[a]), sub(m.verts[c], m.verts[a])))
            normals.append(n)
            lines.append(f"vn {fmt(n[0])} {fmt(n[1])} {fmt(n[2])}")
        lines.append(f"usemtl {'Palette' if m.textured else 'Plain'}")
        lines.append("s off")
        for k, (a, b, c, ci) in enumerate(m.tris):
            vn = n_offset + k
            if m.textured:
                vt = ci + 1
                lines.append(f"f {a + v_offset}/{vt}/{vn} {b + v_offset}/{vt}/{vn} {c + v_offset}/{vt}/{vn}")
            else:
                lines.append(f"f {a + v_offset}//{vn} {b + v_offset}//{vn} {c + v_offset}//{vn}")
        v_offset += len(m.verts)
        n_offset += len(m.tris)
    with open(path, "w", newline="\n") as f:
        f.write("\n".join(lines) + "\n")


def write_mtl(path: str, png_name: str) -> None:
    text = "\n".join(
        [
            "# Deadfall Square materials - generated by roblox/tools/make_meshes.py",
            "newmtl Palette",
            "Kd 1 1 1",
            "Ka 0 0 0",
            "Ks 0 0 0",
            f"map_Kd {png_name}",
            "",
            "newmtl Plain",
            "Kd 1 1 1",
            "Ka 0 0 0",
            "Ks 0 0 0",
        ]
    )
    with open(path, "w", newline="\n") as f:
        f.write(text + "\n")


def write_sizes(path: str, models: list[Model]) -> None:
    lines = [
        "--!strict",
        "-- Generated by roblox/tools/make_meshes.py from the models in roblox/assets. Do not edit by hand.",
        "-- Exact bounding-box size of every model, in studs: { x, y, z }.",
        "return {",
    ]
    for m in sorted(models, key=lambda m: m.name):
        x, y, z = (fmt(v) for v in m.size())
        lines.append(f"\t{m.name} = {{ {x}, {y}, {z} }},")
    lines.append("}")
    with open(path, "w", newline="\n") as f:
        f.write("\n".join(lines) + "\n")


def generate(asset_dir: str, sizes_path: str) -> list[Model]:
    palette, models = build_all()
    os.makedirs(asset_dir, exist_ok=True)
    write_png(os.path.join(asset_dir, "DeadfallPalette.png"), palette)
    write_mtl(os.path.join(asset_dir, "DeadfallMeshes.mtl"), "DeadfallPalette.png")
    write_obj(os.path.join(asset_dir, "DeadfallMeshes.obj"), "DeadfallMeshes.mtl", palette, models)
    write_sizes(sizes_path, models)
    return models


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--check", action="store_true", help="fail if committed outputs are out of date")
    args = parser.parse_args()

    asset_dir = os.path.join(ROOT, "assets")
    sizes_path = os.path.join(ROOT, "src", "shared", "Config", "MeshSizes.luau")
    if not args.check:
        models = generate(asset_dir, sizes_path)
        tris = sum(len(m.tris) for m in models)
        print(f"wrote {len(models)} models ({tris} triangles) to {asset_dir}")
        return 0

    with tempfile.TemporaryDirectory() as tmp:
        generate(os.path.join(tmp, "assets"), os.path.join(tmp, "MeshSizes.luau"))
        pairs = [(os.path.join(tmp, "assets", n), os.path.join(asset_dir, n)) for n in os.listdir(os.path.join(tmp, "assets"))]
        pairs.append((os.path.join(tmp, "MeshSizes.luau"), sizes_path))
        stale = []
        for fresh, committed in pairs:
            if not os.path.exists(committed) or open(fresh, "rb").read() != open(committed, "rb").read():
                stale.append(os.path.relpath(committed, ROOT))
        if stale:
            print("Out of date (run python3 roblox/tools/make_meshes.py):\n  " + "\n  ".join(stale))
            return 1
    print("meshes up to date")
    return 0


if __name__ == "__main__":
    sys.exit(main())
