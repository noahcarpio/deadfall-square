#!/usr/bin/env python3
"""
Renders a contact sheet of every model in roblox/assets/DeadfallMeshes.obj
(flat-shaded, three-quarter view) to roblox/assets/preview.png.

Needs NumPy and Pillow (only for previews; the generator itself has no dependencies).
  python3 roblox/tools/preview_meshes.py
"""
from __future__ import annotations

import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(ROOT, "assets")
TILE = 220
COLS = 6
PLAIN = (150, 160, 140)  # untextured (tinted in game) parts


def load():
    palette = Image.open(os.path.join(ASSETS, "DeadfallPalette.png")).convert("RGB")
    w, h = palette.size
    verts, uvs, objects = [], [], []
    current = None
    with open(os.path.join(ASSETS, "DeadfallMeshes.obj")) as f:
        for line in f:
            parts = line.split()
            if not parts:
                continue
            if parts[0] == "v":
                verts.append(tuple(map(float, parts[1:4])))
            elif parts[0] == "vt":
                u, v = map(float, parts[1:3])
                uvs.append(palette.getpixel((min(w - 1, int(u * w)), min(h - 1, int((1 - v) * h)))))
            elif parts[0] == "o":
                current = {"name": parts[1], "faces": []}
                objects.append(current)
            elif parts[0] == "f":
                idx = [p.split("/") for p in parts[1:4]]
                tri = [verts[int(i[0]) - 1] for i in idx]
                color = uvs[int(idx[0][1]) - 1] if idx[0][1] else PLAIN
                current["faces"].append((tri, color))
    return objects


def render(obj) -> Image.Image:
    img = Image.new("RGB", (TILE, TILE), (30, 34, 40))
    draw = ImageDraw.Draw(img)
    tris = np.array([f[0] for f in obj["faces"]], dtype=float)  # (n, 3, 3)
    # Three-quarter view: yaw 35 deg, pitch 25 deg. Front of guns is -Z, of the rest +Z;
    # yaw so both read well.
    yaw, pitch = math.radians(215 if obj["name"].startswith("Gun_") else 35), math.radians(25)
    ry = np.array([[math.cos(yaw), 0, math.sin(yaw)], [0, 1, 0], [-math.sin(yaw), 0, math.cos(yaw)]])
    rx = np.array([[1, 0, 0], [0, math.cos(pitch), -math.sin(pitch)], [0, math.sin(pitch), math.cos(pitch)]])
    pts = tris @ (rx @ ry).T
    flat = pts.reshape(-1, 3)
    lo, hi = flat.min(0), flat.max(0)
    scale = (TILE - 50) / max(hi[0] - lo[0], hi[1] - lo[1], 1e-6)
    cx, cy = (lo[0] + hi[0]) / 2, (lo[1] + hi[1]) / 2
    light = np.array([0.4, 0.8, 0.45])
    light /= np.linalg.norm(light)
    order = np.argsort(pts[:, :, 2].mean(1))  # painter's algorithm: far (low z) first
    for i in order:
        a, b, c = pts[i]
        n = np.cross(b - a, c - a)
        if n[2] <= 0:  # back-facing (camera looks down -Z in view space)
            continue
        n /= np.linalg.norm(n)
        shade = 0.35 + 0.65 * max(0.0, float(n @ light))
        col = tuple(int(min(255, ch * shade)) for ch in obj["faces"][i][1])
        poly = [(TILE / 2 + (p[0] - cx) * scale, TILE / 2 + 10 - (p[1] - cy) * scale) for p in (a, b, c)]
        draw.polygon(poly, fill=col)
    draw.text((8, 6), obj["name"], fill=(236, 231, 220), font=ImageFont.load_default())
    return img


def main() -> None:
    objects = load()
    rows = math.ceil(len(objects) / COLS)
    sheet = Image.new("RGB", (COLS * TILE, rows * TILE), (20, 22, 26))
    for i, obj in enumerate(objects):
        sheet.paste(render(obj), ((i % COLS) * TILE, (i // COLS) * TILE))
    out = os.path.join(ASSETS, "preview.png")
    sheet.save(out)
    print(f"wrote {out}")


if __name__ == "__main__":
    main()
