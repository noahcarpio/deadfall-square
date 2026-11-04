#!/usr/bin/env python3
"""
Keyframed player animations for Deadfall Square (R15), written as Roblox
KeyframeSequences.

Outputs (both committed; CI runs --check):
  roblox/assets/DeadfallAnimations.rbxmx    - a Folder of KeyframeSequences, mapped by
                                              Rojo to ReplicatedStorage.DeadfallAnimations
  roblox/src/shared/Config/AnimationClips.luau - each clip's length, looping and blend mode

Two blend modes:
  * additive  - played on top of the code-driven aim pose (CharacterAnimator keeps
                the arms raised and the gun pointed); the keyframes are offsets
                from that pose. Reloads, the throw and the kneel's arms.
  * absolute  - CharacterAnimator stops posing those joints while the clip plays.
                Melee swings, the roll and the downed loop.

Angles are radians, positions studs. A pose is (rx, ry, rz) or
(rx, ry, rz, px, py, pz), turned into CFrame.Angles(0, ry, 0) * CFrame.Angles(rx, 0, 0)
* CFrame.Angles(0, 0, rz) like the procedural poses. In a joint's frame +rx swings a
hanging limb forward (raises an arm, lifts a thigh), -rx bends a knee back, and -rx
on the waist or neck leans or looks forward.

  python3 roblox/tools/make_animations.py          # regenerate
  python3 roblox/tools/make_animations.py --check  # verify committed files are up to date (CI)
"""

from __future__ import annotations

import argparse
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
RBXMX = os.path.join(ROOT, "assets", "DeadfallAnimations.rbxmx")
CLIPS = os.path.join(ROOT, "src", "shared", "Config", "AnimationClips.luau")

# Joint key -> the R15 part whose pose drives it.
PART = {
    "root": "LowerTorso",
    "waist": "UpperTorso",
    "neck": "Head",
    "rShoulder": "RightUpperArm",
    "rElbow": "RightLowerArm",
    "rWrist": "RightHand",
    "lShoulder": "LeftUpperArm",
    "lElbow": "LeftLowerArm",
    "lWrist": "LeftHand",
    "rHip": "RightUpperLeg",
    "rKnee": "RightLowerLeg",
    "rAnkle": "RightFoot",
    "lHip": "LeftUpperLeg",
    "lKnee": "LeftLowerLeg",
    "lAnkle": "LeftFoot",
}
PARENT = {
    "LowerTorso": "HumanoidRootPart",
    "UpperTorso": "LowerTorso",
    "Head": "UpperTorso",
    "RightUpperArm": "UpperTorso",
    "RightLowerArm": "RightUpperArm",
    "RightHand": "RightLowerArm",
    "LeftUpperArm": "UpperTorso",
    "LeftLowerArm": "LeftUpperArm",
    "LeftHand": "LeftLowerArm",
    "RightUpperLeg": "LowerTorso",
    "RightLowerLeg": "RightUpperLeg",
    "RightFoot": "RightLowerLeg",
    "LeftUpperLeg": "LowerTorso",
    "LeftLowerLeg": "LeftUpperLeg",
    "LeftFoot": "LeftLowerLeg",
}

# Enum values (Enum.AnimationPriority, Enum.PoseEasingStyle, Enum.PoseEasingDirection).
ACTION = 2
EASE = {"linear": (0, 0), "cubic": (3, 2), "out": (3, 1), "in": (3, 0), "constant": (1, 0)}

PI = math.pi


class Clip:
    def __init__(self, name: str, length: float, blend: str, loop: bool = False):
        self.name = name
        self.length = length
        self.blend = blend
        self.loop = loop
        self.frames: list[tuple[float, dict, str]] = []

    def key(self, t: float, poses: dict, ease: str = "cubic") -> "Clip":
        self.frames.append((t, poses, ease))
        return self

    def joints(self) -> list[str]:
        seen: list[str] = []
        for _, poses, _ in self.frames:
            for j in poses:
                if j not in seen:
                    seen.append(j)
        return seen


# --------------------------------------------------------------------------- the clips


def reloads() -> list[Clip]:
    # Offsets from the aim pose; each clip is 1 s and is played at 1 / reloadTime speed.
    rifle = Clip("Reload_Rifle", 1.0, "additive")
    rest = {"rShoulder": (0, 0, 0), "rElbow": (0, 0, 0), "lShoulder": (0, 0, 0), "lElbow": (0, 0, 0), "neck": (0, 0, 0)}
    rifle.key(0.0, rest)
    rifle.key(0.15, {**rest, "rShoulder": (-0.35, 0.5, 0), "neck": (-0.25, 0, 0)}, "out")  # tilt the gun to see the mag
    rifle.key(0.32, {**rest, "rShoulder": (-0.35, 0.5, 0), "lShoulder": (-0.9, 0, 0.1), "lElbow": (0.6, 0, 0), "neck": (-0.3, 0, 0)})
    rifle.key(0.5, {**rest, "rShoulder": (-0.3, 0.45, 0), "lShoulder": (-1.3, 0, 0.25), "lElbow": (0.9, 0, 0), "neck": (-0.3, 0.1, 0)})
    rifle.key(0.7, {**rest, "rShoulder": (-0.35, 0.5, 0), "lShoulder": (-0.3, 0, 0.05), "lElbow": (0.25, 0, 0), "neck": (-0.25, 0, 0)})
    rifle.key(0.8, {**rest, "rShoulder": (-0.3, 0.5, 0), "lShoulder": (-0.05, 0.1, 0), "lElbow": (0.1, 0, 0), "neck": (-0.2, 0, 0)}, "out")  # seat it
    rifle.key(0.9, {**rest, "rShoulder": (-0.1, 0.15, 0), "lShoulder": (0.05, 0, -0.2), "lElbow": (0.2, 0, 0)})  # charging handle
    rifle.key(1.0, rest)

    pistol = Clip("Reload_Pistol", 1.0, "additive")
    rest = {"rShoulder": (0, 0, 0), "rElbow": (0, 0, 0), "lShoulder": (0, 0, 0), "lElbow": (0, 0, 0), "neck": (0, 0, 0)}
    pistol.key(0.0, rest)
    pistol.key(0.12, {**rest, "rShoulder": (-0.45, 0.35, 0), "rElbow": (0.35, 0, 0), "neck": (-0.2, 0, 0)}, "out")  # flick the mag out
    pistol.key(0.4, {**rest, "rShoulder": (-0.4, 0.3, 0), "rElbow": (0.35, 0, 0), "lShoulder": (-1.1, 0, 0.2), "lElbow": (0.8, 0, 0), "neck": (-0.25, 0, 0)})
    pistol.key(0.65, {**rest, "rShoulder": (-0.4, 0.3, 0), "rElbow": (0.35, 0, 0), "lShoulder": (-0.25, 0, 0), "lElbow": (0.3, 0, 0), "neck": (-0.2, 0, 0)}, "out")
    pistol.key(0.85, {**rest, "rShoulder": (-0.15, 0.1, 0), "lShoulder": (0.05, 0.25, 0), "lElbow": (0.15, 0, 0)})  # rack the slide
    pistol.key(1.0, rest)

    shotgun = Clip("Reload_Shotgun", 1.0, "additive")
    rest = {"rShoulder": (0, 0, 0), "lShoulder": (0, 0, 0), "lElbow": (0, 0, 0), "waist": (0, 0, 0), "neck": (0, 0, 0)}
    port = {"rShoulder": (-0.25, -0.4, 0), "waist": (0, 0.15, 0), "neck": (-0.2, 0.1, 0)}  # roll the loading port up
    shotgun.key(0.0, rest)
    shotgun.key(0.1, {**rest, **port}, "out")
    t = 0.1
    for _ in range(3):  # three shells: pocket, then the port
        shotgun.key(t + 0.12, {**rest, **port, "lShoulder": (-1.2, 0, 0.3), "lElbow": (0.9, 0, 0)})
        shotgun.key(t + 0.24, {**rest, **port, "lShoulder": (-0.15, 0.15, 0), "lElbow": (0.35, 0, 0)}, "out")
        t += 0.24
    shotgun.key(0.86, {**rest, "lShoulder": (-0.25, 0, 0), "lElbow": (-0.1, 0, 0)}, "out")  # rack the pump
    shotgun.key(0.93, {**rest, "lShoulder": (0.05, 0, 0)}, "out")
    shotgun.key(1.0, rest)
    return [rifle, pistol, shotgun]


def throw() -> Clip:
    # Left-hand overhand toss (the right hand keeps the gun); offsets from the aim pose.
    c = Clip("Throw", 0.6, "additive")
    rest = {"lShoulder": (0, 0, 0), "lElbow": (0, 0, 0), "waist": (0, 0, 0)}
    c.key(0.0, rest)
    c.key(0.2, {"lShoulder": (1.2, 0.3, -0.3), "lElbow": (1.0, 0, 0), "waist": (0.05, -0.35, 0)}, "out")  # wind up
    c.key(0.32, {"lShoulder": (-0.5, 0.1, 0), "lElbow": (0.1, 0, 0), "waist": (-0.15, 0.3, 0)}, "in")  # release
    c.key(0.45, {"lShoulder": (-0.75, 0, 0.1), "lElbow": (0.2, 0, 0), "waist": (-0.1, 0.2, 0)}, "out")
    c.key(0.6, rest)
    return c


def swings() -> list[Clip]:
    # Absolute arm poses over MeleeMath.SWING_TIME (0.32 s), with a step and hip turn.
    def swing(name: str, frames: list[tuple[float, float, float, float, float]], legs: bool) -> Clip:
        c = Clip(name, 0.32, "absolute")
        for i, (t, yaw, pitch, elbow, waist) in enumerate(frames):
            poses = {
                "rShoulder": (pitch, yaw, 0),
                "rElbow": (elbow, 0, 0),
                "lShoulder": (0.45, -0.3, 0),
                "lElbow": (0.6, 0, 0),
                "waist": (0, waist, 0),
                "root": (0, waist * 0.35, 0),
            }
            if legs:
                lunge = min(1.0, t / 0.16)
                poses["lHip"] = (0.35 * lunge, 0, 0)
                poses["lKnee"] = (-0.3 * lunge, 0, 0)
                poses["rHip"] = (-0.2 * lunge, 0, 0)
            c.key(t, poses, "out" if i == 1 else "cubic")
        return c

    forehand = swing(
        "Swing_1",
        [(0.0, 1.55, 1.35, 0.6, 0.75), (0.08, 0.45, 1.35, 0.2, 0.15), (0.18, -0.85, 1.3, 0.1, -0.4), (0.32, -1.15, 1.2, 0.15, -0.5)],
        True,
    )
    backhand = swing(
        "Swing_2",
        [(0.0, -1.3, 1.25, 0.7, -0.6), (0.08, -0.3, 1.25, 0.25, -0.1), (0.18, 0.9, 1.25, 0.1, 0.45), (0.32, 1.25, 1.2, 0.15, 0.55)],
        True,
    )
    overhead = Clip("Swing_3", 0.32, "absolute")
    for t, pitch, waist, crouch, ease in [
        (0.0, 3.05, 0.15, 0.0, "cubic"),  # raised high, leaning back
        (0.07, 2.6, 0.1, 0.1, "in"),
        (0.16, 0.9, -0.4, 0.9, "out"),  # slam
        (0.32, 0.7, -0.35, 0.7, "cubic"),
    ]:
        overhead.key(
            t,
            {
                "rShoulder": (pitch, 0.1, 0),
                "rElbow": (0.15, 0, 0),
                "lShoulder": (pitch * 0.85, -0.25, 0),
                "lElbow": (0.3, 0, 0),
                "waist": (waist, 0, 0),
                "root": (0, 0, 0, 0, -0.45 * crouch, 0),
                "rHip": (0.45 * crouch, 0, 0),
                "lHip": (0.6 * crouch, 0, 0),
                "rKnee": (-0.6 * crouch, 0, 0),
                "lKnee": (-0.8 * crouch, 0, 0),
            },
            ease,
        )
    return [forehand, backhand, overhead]


def roll() -> Clip:
    # PlayerStats.BASE.rollDuration (0.42 s): a forward tumble with tucked legs.
    c = Clip("Roll", 0.42, "absolute")
    steps = 6
    for i in range(steps + 1):
        f = i / steps
        tuck = math.sin(PI * f)
        c.key(
            0.42 * f,
            {
                "root": (-2 * PI * f, 0, 0, 0, -1.1 * tuck, 0),
                "waist": (-0.4 * tuck, 0, 0),
                "neck": (-0.5 * tuck, 0, 0),
                "rHip": (1.4 * tuck, 0, 0),
                "lHip": (1.4 * tuck, 0, 0),
                "rKnee": (-2.1 * tuck, 0, 0),
                "lKnee": (-2.1 * tuck, 0, 0),
            },
            "linear",
        )
    return c


def downed() -> Clip:
    # Lying face down, reaching forward and dragging (loops).
    c = Clip("Downed", 2.4, "absolute", loop=True)
    lie = (-1.45, 0, 0, 0, -2.0, -0.6)
    for t, reach, breathe in [(0.0, 0.0, 0.0), (0.8, 1.0, 0.5), (1.6, 0.4, 1.0), (2.4, 0.0, 0.0)]:
        c.key(
            t,
            {
                "root": lie,
                "waist": (0.04 * breathe, 0.05 * reach, 0),
                "neck": (0.35, 0.15 * reach, 0),
                "rShoulder": (2.7 + 0.3 * reach, 0, 0.15),
                "rElbow": (0.5 - 0.4 * reach, 0, 0),
                "lShoulder": (0.5 + 0.4 * (1 - reach), 0, -0.2),
                "lElbow": (0.6, 0, 0),
                "rHip": (0.05, 0, 0.08),
                "lHip": (0.2 * reach, 0, -0.08),
                "rKnee": (-0.15, 0, 0),
                "lKnee": (-0.5 * reach, 0, 0),
            },
        )
    return c


def kneel() -> Clip:
    # Down on one knee to search or revive (loops). Legs absolute, arms offset from the aim pose.
    c = Clip("Kneel", 1.6, "additive", loop=True)
    for t, work in [(0.0, 0.0), (0.4, 1.0), (0.8, 0.0), (1.2, -1.0), (1.6, 0.0)]:
        c.key(
            t,
            {
                "root": (0, 0, 0, 0, -1.1, 0),
                "waist": (-0.35, 0, 0),
                "neck": (-0.35, 0, 0),
                "lHip": (1.5, 0, 0),
                "lKnee": (-1.5, 0, 0),
                "rHip": (0.05, 0, 0),
                "rKnee": (-1.55, 0, 0),
                "rAnkle": (0.6, 0, 0),
                "rShoulder": (-0.85, 0.12 * work, 0),
                "lShoulder": (-0.8, -0.12 * work, 0),
                "lElbow": (0.2 + 0.15 * work, 0, 0),
            },
        )
    return c


def all_clips() -> list[Clip]:
    return [*reloads(), throw(), *swings(), roll(), downed(), kneel()]


# --------------------------------------------------------------------------- output


def rot_yxz(rx: float, ry: float, rz: float):
    cx, sx = math.cos(rx), math.sin(rx)
    cy, sy = math.cos(ry), math.sin(ry)
    cz, sz = math.cos(rz), math.sin(rz)
    a = ((cy, 0, sy), (0, 1, 0), (-sy, 0, cy))
    b = ((1, 0, 0), (0, cx, -sx), (0, sx, cx))
    c = ((cz, -sz, 0), (sz, cz, 0), (0, 0, 1))

    def mul(p, q):
        return tuple(tuple(sum(p[i][k] * q[k][j] for k in range(3)) for j in range(3)) for i in range(3))

    return mul(mul(a, b), c)


def num(v: float) -> str:
    s = f"{v:.5f}".rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s


class Writer:
    def __init__(self):
        self.lines: list[str] = []
        self.ref = 0

    def open(self, cls: str, props: list[str], depth: int):
        self.ref += 1
        pad = "  " * depth
        self.lines.append(f'{pad}<Item class="{cls}" referent="RBX{self.ref}">')
        self.lines.append(f"{pad}  <Properties>")
        for p in props:
            self.lines.append(f"{pad}    {p}")
        self.lines.append(f"{pad}  </Properties>")

    def close(self, depth: int):
        self.lines.append("  " * depth + "</Item>")


def cframe(pose) -> str:
    rx, ry, rz = pose[0], pose[1], pose[2]
    px, py, pz = (pose[3], pose[4], pose[5]) if len(pose) == 6 else (0.0, 0.0, 0.0)
    m = rot_yxz(rx, ry, rz)
    parts = [f"<X>{num(px)}</X>", f"<Y>{num(py)}</Y>", f"<Z>{num(pz)}</Z>"]
    for i in range(3):
        for j in range(3):
            parts.append(f"<R{i}{j}>{num(m[i][j])}</R{i}{j}>")
    return '<CoordinateFrame name="CFrame">' + "".join(parts) + "</CoordinateFrame>"


def write_pose(w: Writer, part: str, poses_by_part: dict, needed: set, ease: str, depth: int):
    style, direction = EASE[ease]
    keyed = part in poses_by_part
    pose = poses_by_part.get(part, (0, 0, 0))
    w.open(
        "Pose",
        [
            f'<string name="Name">{part}</string>',
            cframe(pose),
            f'<float name="Weight">{1 if keyed else 0}</float>',
            f'<token name="EasingStyle">{style}</token>',
            f'<token name="EasingDirection">{direction}</token>',
        ],
        depth,
    )
    for child, parent in PARENT.items():
        if parent == part and child in needed:
            write_pose(w, child, poses_by_part, needed, ease, depth + 1)
    w.close(depth)


def build_rbxmx(clips: list[Clip]) -> str:
    w = Writer()
    w.lines.append('<roblox version="4">')
    w.open("Folder", ['<string name="Name">DeadfallAnimations</string>'], 1)
    for clip in clips:
        w.open(
            "KeyframeSequence",
            [
                f'<string name="Name">{clip.name}</string>',
                f'<bool name="Loop">{"true" if clip.loop else "false"}</bool>',
                f'<token name="Priority">{ACTION}</token>',
            ],
            2,
        )
        parts = {PART[j] for j in clip.joints()}
        needed = set()
        for p in parts:
            while p:
                needed.add(p)
                p = PARENT.get(p)
        for t, poses, ease in clip.frames:
            w.open("Keyframe", ['<string name="Name">Keyframe</string>', f'<float name="Time">{num(t)}</float>'], 3)
            by_part = {PART[j]: v for j, v in poses.items()}
            write_pose(w, "HumanoidRootPart", by_part, needed, ease, 4)
            w.close(3)
        w.close(2)
    w.close(1)
    w.lines.append("</roblox>")
    return "\n".join(w.lines) + "\n"


def build_clips_luau(clips: list[Clip]) -> str:
    out = [
        "--!strict",
        "-- Generated by roblox/tools/make_animations.py. Do not edit by hand.",
        "-- Keyframed clips in ReplicatedStorage.DeadfallAnimations: length (s), looping, and whether",
        "-- the clip plays on top of the code-driven aim pose (additive) or replaces it (absolute).",
        "return {",
    ]
    for c in clips:
        out.append(f'\t{c.name} = {{ length = {num(c.length)}, loop = {"true" if c.loop else "false"}, additive = {"true" if c.blend == "additive" else "false"} }},')
    out.append("}")
    return "\n".join(out) + "\n"


def validate(clips: list[Clip]):
    names = set()
    for c in clips:
        assert c.name not in names, f"duplicate clip {c.name}"
        names.add(c.name)
        times = [t for t, _, _ in c.frames]
        assert times == sorted(times), f"{c.name}: keyframes out of order"
        assert times[0] == 0 and abs(times[-1] - c.length) < 1e-9, f"{c.name}: keyframes must span 0..length"
        for _, poses, _ in c.frames:
            for j, v in poses.items():
                assert j in PART, f"{c.name}: unknown joint {j}"
                assert len(v) in (3, 6), f"{c.name}: bad pose for {j}"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--check", action="store_true", help="fail if committed outputs are out of date")
    args = parser.parse_args()
    clips = all_clips()
    validate(clips)
    outputs = {RBXMX: build_rbxmx(clips), CLIPS: build_clips_luau(clips)}
    stale = []
    for path, text in outputs.items():
        current = open(path, encoding="utf-8").read() if os.path.exists(path) else None
        if current != text:
            stale.append(path)
            if not args.check:
                with open(path, "w", encoding="utf-8", newline="\n") as f:
                    f.write(text)
    if args.check and stale:
        print("Out of date (run python3 roblox/tools/make_animations.py):", *stale, sep="\n  ")
        return 1
    print(f"{len(clips)} clips" + (" (up to date)" if not stale else f", wrote {len(stale)} file(s)"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
