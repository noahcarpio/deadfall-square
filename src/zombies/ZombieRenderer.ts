import * as THREE from 'three';
import type { ZombieDef } from '../config/zombies';
import { easeOutCubic } from '../core/math';
import { MeshBuilder } from '../world/MeshBuilder';
import type { Zombie } from './Zombie';

/** GLSL value noise shared by the dissolve patch. */
const NOISE_GLSL = /* glsl */ `
varying vec2 vFx;
varying vec3 vObjPos;
float dzHash(vec3 p) {
  p = fract(p * 0.3183099 + 0.1);
  p *= 17.0;
  return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}
float dzNoise(vec3 x) {
  vec3 i = floor(x);
  vec3 f = fract(x);
  f = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(mix(dzHash(i), dzHash(i + vec3(1, 0, 0)), f.x), mix(dzHash(i + vec3(0, 1, 0)), dzHash(i + vec3(1, 1, 0)), f.x), f.y),
    mix(mix(dzHash(i + vec3(0, 0, 1)), dzHash(i + vec3(1, 0, 1)), f.x), mix(dzHash(i + vec3(0, 1, 1)), dzHash(i + vec3(1, 1, 1)), f.x), f.y),
    f.z);
}
`;

/**
 * Patches a built-in material with per-instance hit-flash (aFx.y) and noise
 * dissolve with a glowing edge (aFx.x). Works for lit, unlit and depth materials.
 */
export function patchFxMaterial<T extends THREE.Material>(material: T, mode: 'lit' | 'basic' | 'depth'): T {
  material.onBeforeCompile = (shader) => {
    shader.vertexShader = shader.vertexShader
      .replace('#include <common>', '#include <common>\nattribute vec2 aFx;\nvarying vec2 vFx;\nvarying vec3 vObjPos;')
      .replace('#include <begin_vertex>', '#include <begin_vertex>\nvFx = aFx;\nvObjPos = position;');
    shader.fragmentShader = shader.fragmentShader
      .replace('#include <common>', `#include <common>\n${NOISE_GLSL}`)
      .replace(
        '#include <clipping_planes_fragment>',
        '#include <clipping_planes_fragment>\nfloat dzN = dzNoise(vObjPos * 9.0);\nif (vFx.x > 0.0 && dzN < vFx.x * 1.05) discard;',
      );
    if (mode !== 'depth') {
      shader.fragmentShader = shader.fragmentShader.replace(
        '#include <color_fragment>',
        '#include <color_fragment>\ndiffuseColor.rgb = mix(diffuseColor.rgb, vec3(1.0), vFx.y);',
      );
    }
    if (mode === 'lit') {
      shader.fragmentShader = shader.fragmentShader.replace(
        '#include <emissivemap_fragment>',
        `#include <emissivemap_fragment>
float dzEdge = vFx.x > 0.0 ? smoothstep(vFx.x * 1.05 + 0.14, vFx.x * 1.05, dzN) : 0.0;
totalEmissiveRadiance += vec3(0.45, 1.0, 0.3) * dzEdge * 2.0 + vec3(vFx.y * 0.7);`,
      );
    }
  };
  material.customProgramCacheKey = () => `fx-${mode}`;
  return material;
}

type PartName = 'legs' | 'torso' | 'head' | 'arms' | 'eyes' | 'belly' | 'sac' | 'spikes';

interface Part {
  mesh: THREE.InstancedMesh;
  fx: THREE.InstancedBufferAttribute;
  count: number;
}

/**
 * Renders every zombie with a fixed set of InstancedMeshes (one per body part),
 * so 400 zombies cost ~8 draw calls. Body proportions per type come from config
 * via non-uniform part scales; animation is computed into instance matrices.
 */
export class ZombieRenderer {
  readonly group = new THREE.Group();
  private readonly parts: Record<PartName, Part>;
  private readonly litMaterial: THREE.MeshLambertMaterial;
  private readonly depthMaterial: THREE.MeshDepthMaterial;
  private readonly glowMaterial: THREE.MeshBasicMaterial;

  // Scratch objects (no per-frame allocations).
  private readonly root = new THREE.Matrix4();
  private readonly frame = new THREE.Matrix4();
  private readonly headFrame = new THREE.Matrix4();
  private readonly m = new THREE.Matrix4();
  private readonly tmp = new THREE.Matrix4();
  private readonly q = new THREE.Quaternion();
  private readonly e = new THREE.Euler();
  private readonly v = new THREE.Vector3();
  private readonly s = new THREE.Vector3();
  private readonly axis = new THREE.Vector3();
  private readonly color = new THREE.Color();
  private readonly skinC = new THREE.Color();
  private readonly shirtC = new THREE.Color();
  private readonly pantsC = new THREE.Color();
  private readonly colorCache = new Map<string, THREE.Color>();
  private time = 0;

  constructor(capacity: number) {
    this.litMaterial = patchFxMaterial(new THREE.MeshLambertMaterial({ flatShading: true }), 'lit');
    this.depthMaterial = patchFxMaterial(new THREE.MeshDepthMaterial({ depthPacking: THREE.RGBADepthPacking }), 'depth');
    this.glowMaterial = patchFxMaterial(new THREE.MeshBasicMaterial({ toneMapped: false }), 'basic');

    const box = (w: number, h: number, d: number, y: number): THREE.BufferGeometry => {
      const g = new THREE.BoxGeometry(w, h, d);
      g.translate(0, y, 0);
      return g;
    };
    const eyes = new MeshBuilder();
    eyes.box(0.08, 0.06, 0.04, '#ffffff', -0.09, 0.22, 0.19);
    eyes.box(0.08, 0.06, 0.04, '#ffffff', 0.09, 0.22, 0.19);
    const spikes = new MeshBuilder();
    for (const [x, y, r] of [[0, 0.35, 0], [-0.22, 0.2, -0.5], [0.22, 0.2, 0.5], [-0.12, 0.55, -0.3], [0.12, 0.55, 0.3]] as const) {
      spikes.cone(0.08, 0.38, 5, '#ffffff', x, y, -0.05, -1.1, 0, r);
    }
    const legs = box(0.22, 0.82, 0.24, -0.41);
    const arms = box(0.17, 0.74, 0.19, -0.37);

    this.parts = {
      legs: this.makePart(legs, this.litMaterial, capacity * 2, true),
      torso: this.makePart(box(0.6, 0.76, 0.36, 0.38), this.litMaterial, capacity, true),
      head: this.makePart(box(0.38, 0.38, 0.38, 0.19), this.litMaterial, capacity, true),
      arms: this.makePart(arms, this.litMaterial, capacity * 2, true),
      eyes: this.makePart(stripColor(eyes.build()), this.glowMaterial, capacity, false),
      belly: this.makePart(new THREE.IcosahedronGeometry(0.42, 1), this.glowMaterial, Math.ceil(capacity / 3), false),
      sac: this.makePart(new THREE.IcosahedronGeometry(0.3, 1), this.glowMaterial, Math.ceil(capacity / 3), false),
      spikes: this.makePart(stripColor(spikes.build()), this.litMaterial, 8, true),
    };
  }

  private makePart(geometry: THREE.BufferGeometry, material: THREE.Material, count: number, castShadow: boolean): Part {
    const fx = new THREE.InstancedBufferAttribute(new Float32Array(count * 2), 2);
    fx.setUsage(THREE.DynamicDrawUsage);
    geometry.setAttribute('aFx', fx);
    const mesh = new THREE.InstancedMesh(geometry, material, count);
    mesh.instanceMatrix.setUsage(THREE.DynamicDrawUsage);
    mesh.setColorAt(0, new THREE.Color('#ffffff'));
    (mesh.instanceColor as THREE.InstancedBufferAttribute).setUsage(THREE.DynamicDrawUsage);
    mesh.count = 0;
    mesh.frustumCulled = false;
    mesh.castShadow = castShadow;
    mesh.receiveShadow = material !== this.glowMaterial;
    if (castShadow) mesh.customDepthMaterial = this.depthMaterial;
    this.group.add(mesh);
    return { mesh, fx, count: 0 };
  }

  setShadows(enabled: boolean): void {
    for (const name of ['legs', 'torso', 'head', 'arms', 'spikes'] as const) this.parts[name].mesh.castShadow = enabled;
  }

  private cachedColor(hex: string): THREE.Color {
    let c = this.colorCache.get(hex);
    if (!c) {
      c = new THREE.Color(hex);
      this.colorCache.set(hex, c);
    }
    return c;
  }

  private push(name: PartName, matrix: THREE.Matrix4, color: THREE.Color, dissolve: number, flash: number): void {
    const part = this.parts[name];
    const i = part.count;
    if (i >= part.mesh.instanceMatrix.count) return;
    part.mesh.setMatrixAt(i, matrix);
    part.mesh.setColorAt(i, color);
    part.fx.setXY(i, dissolve, flash);
    part.count++;
  }

  /** Rebuilds all instance data from the zombie list. */
  update(zombies: readonly Zombie[], dt: number): void {
    this.time += dt;
    for (const name of Object.keys(this.parts) as PartName[]) this.parts[name].count = 0;
    for (const z of zombies) this.writeZombie(z);
    for (const name of Object.keys(this.parts) as PartName[]) {
      const p = this.parts[name];
      p.mesh.count = p.count;
      if (p.count === 0) continue;
      p.mesh.instanceMatrix.needsUpdate = true;
      (p.mesh.instanceColor as THREE.InstancedBufferAttribute).needsUpdate = true;
      p.fx.needsUpdate = true;
    }
  }

  private compose(out: THREE.Matrix4, x: number, y: number, z: number, rx: number, ry: number, rz: number, sx: number, sy: number, sz: number): THREE.Matrix4 {
    this.e.set(rx, ry, rz, 'YXZ');
    this.q.setFromEuler(this.e);
    return out.compose(this.v.set(x, y, z), this.q, this.s.set(sx, sy, sz));
  }

  private writeZombie(z: Zombie): void {
    const def: ZombieDef = z.def;
    const b = def.body;
    const scale = def.scale;
    const dissolve = z.dissolve;
    const flash = z.flash;
    const t = this.time;

    // Root transform with optional death topple about the feet.
    let sink = 0;
    if (z.state === 'dying') sink = z.dissolve * 0.35 * scale;
    this.compose(this.root, z.x, -sink, z.z, 0, z.facing, 0, scale, scale, scale);
    if (z.state === 'dying') {
      const a = easeOutCubic(Math.min(1, z.deathT / 0.45)) * (Math.PI / 2) * 0.96;
      this.axis.set(z.deathDirZ, 0, -z.deathDirX).normalize();
      this.q.setFromAxisAngle(this.axis, a);
      this.tmp.makeRotationFromQuaternion(this.q);
      // root = T(pos) * R(topple) * Ry(facing) * S
      const px = this.root.elements[12];
      const py = this.root.elements[13];
      const pz = this.root.elements[14];
      this.root.setPosition(0, 0, 0);
      this.root.premultiply(this.tmp);
      this.root.setPosition(px as number, (py as number) + Math.sin(a) * 0.15 * scale, pz as number);
    }

    const moving = z.state !== 'dying' ? Math.min(1.4, Math.hypot(z.vx, z.vz) / Math.max(0.8, def.speed)) : 0;
    const swingAmp = (z.type === 'runner' ? 0.9 : 0.55) * moving;
    const swing = Math.sin(z.animPhase) * swingAmp;
    const hipY = 0.82 * b.legs[1];
    const bob = Math.abs(Math.cos(z.animPhase)) * 0.05 * moving;

    // Pose by state.
    let lean = b.hunch + (z.type === 'runner' ? 0.25 * moving : 0);
    let armPitch = -1.3 + Math.sin(z.animPhase * 0.5 + z.slot) * 0.15;
    let armSpread = 0.08;
    let headPitch = 0.15;
    let legL = swing;
    let legR = -swing;
    const p = z.stateTime;
    switch (z.state) {
      case 'windup': {
        const k = Math.min(1, p / Math.max(0.05, def.windup));
        armPitch = -1.3 - k * 1.5;
        lean = b.hunch - 0.25 * k;
        break;
      }
      case 'recover':
        armPitch = -0.5 - Math.min(1, p / 0.35) * 0.8;
        lean = b.hunch + 0.35 * (1 - Math.min(1, p / 0.35));
        break;
      case 'ranged': {
        const k = Math.min(1, p / Math.max(0.05, def.windup));
        headPitch = 0.15 - k * 0.6;
        lean = b.hunch - 0.3 * k;
        break;
      }
      case 'chargeTelegraph':
        lean = 0.6;
        armPitch = -0.4;
        armSpread = 0.5;
        legL = 0.4;
        legR = -0.3;
        break;
      case 'charging':
        lean = 0.75;
        armPitch = -0.9;
        armSpread = 0.35;
        break;
      case 'slamTelegraph':
      case 'summon': {
        const k = Math.min(1, p / 0.6);
        armPitch = -1.3 - k * 1.6;
        armSpread = 0.3 + k * 0.3;
        lean = b.hunch - 0.35 * k;
        headPitch = z.state === 'summon' ? -0.6 * k : headPitch;
        break;
      }
      case 'stunned':
        lean = 0.9;
        armPitch = -0.2;
        headPitch = 0.6 + Math.sin(t * 8) * 0.2;
        break;
      case 'dying': {
        const k = Math.min(1, z.deathT / 0.45);
        armPitch = -1.3 + k * 2.6;
        armSpread = 0.2 + k * 0.6;
        legL = k * 0.3;
        legR = -k * 0.2;
        headPitch = 0.6 * k;
        break;
      }
      default:
        break;
    }

    // Colours.
    const char = z.burnTime > 0 ? 0.55 : 1;
    const enr = z.enraged ? 1 : 0;
    const skinColor = this.skinC.copy(this.cachedColor(def.colors.skin)).multiplyScalar(z.tint * char);
    if (enr) skinColor.lerp(this.cachedColor('#a83a2a'), 0.5);
    const shirt = this.shirtC.copy(this.cachedColor(def.colors.shirt)).multiplyScalar(z.tint * char);
    const pants = this.pantsC.copy(this.cachedColor(def.colors.pants)).multiplyScalar(z.tint * char);

    // Legs.
    const legX = 0.14 * b.torso[0];
    this.compose(this.m, -legX, hipY, 0, legL, 0, 0, b.legs[0], b.legs[1], b.legs[2]);
    this.push('legs', this.tmp.multiplyMatrices(this.root, this.m), pants, dissolve, flash);
    this.compose(this.m, legX, hipY, 0, legR, 0, 0, b.legs[0], b.legs[1], b.legs[2]);
    this.push('legs', this.tmp.multiplyMatrices(this.root, this.m), pants, dissolve, flash);

    // Torso frame (unscaled) and mesh.
    const sway = Math.sin(z.animPhase) * 0.06 * moving;
    this.compose(this.m, 0, hipY + bob, 0, lean, 0, sway, 1, 1, 1);
    this.frame.multiplyMatrices(this.root, this.m);
    this.compose(this.m, 0, 0, 0, 0, 0, 0, b.torso[0], b.torso[1], b.torso[2]);
    this.push('torso', this.tmp.multiplyMatrices(this.frame, this.m), shirt, dissolve, flash);

    // Head.
    const tilt = Math.sin(t * 1.3 + z.slot * 1.7) * 0.12;
    this.compose(this.m, 0, 0.76 * b.torso[1], 0.04, headPitch, tilt * 0.5, tilt, 1, 1, 1);
    this.headFrame.multiplyMatrices(this.frame, this.m);
    this.compose(this.m, 0, 0, 0, 0, 0, 0, b.head[0], b.head[1], b.head[2]);
    this.tmp.multiplyMatrices(this.headFrame, this.m);
    this.push('head', this.tmp, skinColor, dissolve, flash);
    // Eyes share the scaled head transform; they glow in the dark.
    const eyeColor = this.color.copy(this.cachedColor(def.colors.eyes));
    if (z.state === 'dying') eyeColor.multiplyScalar(Math.max(0, 1 - z.deathT * 2));
    this.push('eyes', this.tmp, eyeColor, dissolve, 0);

    // Arms.
    const shoulderX = 0.3 * b.torso[0] + 0.08 * b.arms[0];
    const shoulderY = 0.68 * b.torso[1];
    const armSwing = Math.sin(z.animPhase + 0.5) * 0.18 * moving;
    this.compose(this.m, -shoulderX, shoulderY, 0, armPitch + armSwing, 0, -armSpread, b.arms[0], b.arms[1], b.arms[2]);
    this.push('arms', this.tmp.multiplyMatrices(this.frame, this.m), skinColor, dissolve, flash);
    this.compose(this.m, shoulderX, shoulderY, 0, armPitch - armSwing, 0, armSpread, b.arms[0], b.arms[1], b.arms[2]);
    this.push('arms', this.tmp.multiplyMatrices(this.frame, this.m), skinColor, dissolve, flash);

    // Type-specific extras.
    if (z.type === 'exploder') {
      const fusing = z.state === 'fuse';
      const k = fusing ? Math.min(1, p / def.windup) : 0;
      const pulse = 1 + Math.sin(t * (fusing ? 30 : 4) + z.slot) * (fusing ? 0.12 : 0.05) + k * 0.35;
      this.compose(this.m, 0, 0.36 * b.torso[1], 0.17 * b.torso[2], 0, 0, 0, pulse * b.torso[0], pulse, pulse * b.torso[2] * 0.8);
      const blink = fusing && Math.sin(t * 40) > 0 ? 2.2 : 1;
      const belly = this.color.copy(this.cachedColor('#ff7a1a')).multiplyScalar(blink);
      this.push('belly', this.tmp.multiplyMatrices(this.frame, this.m), belly, dissolve, 0);
    } else if (z.type === 'spitter') {
      const k = z.state === 'ranged' ? Math.min(1, p / def.windup) : 0;
      const swell = 1 + k * 0.6 + Math.sin(t * 3 + z.slot) * 0.06;
      this.compose(this.m, 0, 0.62 * b.torso[1], -0.24, 0, 0, 0, swell, swell * 0.9, swell);
      const sac = this.color.copy(this.cachedColor('#8cff3a')).multiplyScalar(0.8 + k * 0.8);
      this.push('sac', this.tmp.multiplyMatrices(this.frame, this.m), sac, dissolve, 0);
    } else if (z.type === 'boss') {
      this.compose(this.m, 0, 0.45 * b.torso[1], -0.18 * b.torso[2], 0, 0, 0, b.torso[0], b.torso[1], b.torso[2]);
      const bone = this.color.copy(this.cachedColor(z.enraged ? '#ff9a7a' : '#d8cfb4'));
      this.push('spikes', this.tmp.multiplyMatrices(this.frame, this.m), bone, dissolve, flash);
    }
  }
}

function stripColor(g: THREE.BufferGeometry): THREE.BufferGeometry {
  if (g.getAttribute('color')) g.deleteAttribute('color');
  return g;
}
