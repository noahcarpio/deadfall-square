import * as THREE from 'three';
import { mergeGeometries } from 'three/examples/jsm/utils/BufferGeometryUtils.js';

export type ColorInput = THREE.ColorRepresentation;

/**
 * Accumulates low-poly primitives with baked vertex colours and merges them
 * into a single BufferGeometry, so an entire prop set renders in one draw call.
 */
export class MeshBuilder {
  private readonly parts: THREE.BufferGeometry[] = [];
  private readonly stack: THREE.Matrix4[] = [new THREE.Matrix4()];
  private readonly tmpM = new THREE.Matrix4();
  private readonly tmpQ = new THREE.Quaternion();
  private readonly tmpE = new THREE.Euler(0, 0, 0, 'YXZ');
  private readonly tmpP = new THREE.Vector3();
  private readonly tmpS = new THREE.Vector3();
  private readonly tmpC = new THREE.Color();

  /** Random colour jitter amount (0 = none), applied per primitive. */
  constructor(private readonly jitter = 0, private readonly random: () => number = Math.random) {}

  get isEmpty(): boolean {
    return this.parts.length === 0;
  }

  /** Runs `fn` with a parent transform applied to every primitive it adds. */
  group(x: number, y: number, z: number, ry: number, fn: () => void, scale = 1): void {
    const parent = this.stack[this.stack.length - 1] as THREE.Matrix4;
    this.tmpE.set(0, ry, 0);
    this.tmpQ.setFromEuler(this.tmpE);
    const local = new THREE.Matrix4().compose(this.tmpP.set(x, y, z), this.tmpQ, this.tmpS.setScalar(scale));
    this.stack.push(parent.clone().multiply(local));
    try {
      fn();
    } finally {
      this.stack.pop();
    }
  }

  add(
    geometry: THREE.BufferGeometry,
    color: ColorInput,
    x = 0, y = 0, z = 0,
    rx = 0, ry = 0, rz = 0,
    sx = 1, sy = 1, sz = 1,
  ): void {
    let g = geometry.index ? geometry.toNonIndexed() : geometry;
    if (g === geometry) g = geometry.clone();
    geometry.dispose();
    if (g.getAttribute('uv')) g.deleteAttribute('uv');
    if (g.getAttribute('uv1')) g.deleteAttribute('uv1');
    this.tmpE.set(rx, ry, rz);
    this.tmpQ.setFromEuler(this.tmpE);
    this.tmpM.compose(this.tmpP.set(x, y, z), this.tmpQ, this.tmpS.set(sx, sy, sz));
    this.tmpM.premultiply(this.stack[this.stack.length - 1] as THREE.Matrix4);
    g.applyMatrix4(this.tmpM);

    const c = this.tmpC.set(color);
    if (this.jitter > 0) {
      const j = (this.random() - 0.5) * this.jitter;
      c.offsetHSL(0, 0, j);
    }
    const count = (g.getAttribute('position') as THREE.BufferAttribute).count;
    const colors = new Float32Array(count * 3);
    for (let i = 0; i < count; i++) {
      colors[i * 3] = c.r;
      colors[i * 3 + 1] = c.g;
      colors[i * 3 + 2] = c.b;
    }
    g.setAttribute('color', new THREE.BufferAttribute(colors, 3));
    this.parts.push(g);
  }

  box(w: number, h: number, d: number, color: ColorInput, x: number, y: number, z: number, ry = 0, rx = 0, rz = 0): void {
    this.add(new THREE.BoxGeometry(w, h, d), color, x, y, z, rx, ry, rz);
  }

  cylinder(rTop: number, rBottom: number, h: number, segments: number, color: ColorInput, x: number, y: number, z: number, rx = 0, ry = 0, rz = 0): void {
    this.add(new THREE.CylinderGeometry(rTop, rBottom, h, segments), color, x, y, z, rx, ry, rz);
  }

  cone(r: number, h: number, segments: number, color: ColorInput, x: number, y: number, z: number, rx = 0, ry = 0, rz = 0): void {
    this.add(new THREE.ConeGeometry(r, h, segments), color, x, y, z, rx, ry, rz);
  }

  ico(r: number, detail: number, color: ColorInput, x: number, y: number, z: number, sx = 1, sy = 1, sz = 1): void {
    this.add(new THREE.IcosahedronGeometry(r, detail), color, x, y, z, 0, 0, 0, sx, sy, sz);
  }

  /** Merges all primitives; returns an empty geometry if nothing was added. */
  build(): THREE.BufferGeometry {
    if (this.parts.length === 0) return new THREE.BufferGeometry();
    const merged = mergeGeometries(this.parts, false);
    for (const p of this.parts) p.dispose();
    this.parts.length = 0;
    if (!merged) throw new Error('MeshBuilder: failed to merge geometries');
    merged.computeBoundingSphere();
    merged.computeBoundingBox();
    return merged;
  }
}
