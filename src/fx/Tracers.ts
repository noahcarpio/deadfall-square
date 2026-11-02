import * as THREE from 'three';

/** Short-lived additive bullet tracers drawn as stretched instanced boxes. */
export class Tracers {
  readonly mesh: THREE.InstancedMesh;
  private count = 0;
  private readonly data: Float32Array; // x0,y,z0,x1,z1,life,maxLife,width
  private readonly colors: Float32Array;
  private readonly m = new THREE.Matrix4();
  private readonly q = new THREE.Quaternion();
  private readonly e = new THREE.Euler();
  private readonly p = new THREE.Vector3();
  private readonly s = new THREE.Vector3();
  private readonly c = new THREE.Color();

  constructor(private readonly capacity: number) {
    const geo = new THREE.BoxGeometry(1, 1, 1);
    geo.translate(0, 0, 0.5);
    const mat = new THREE.MeshBasicMaterial({ blending: THREE.AdditiveBlending, transparent: true, depthWrite: false, toneMapped: false });
    this.mesh = new THREE.InstancedMesh(geo, mat, capacity);
    this.mesh.instanceMatrix.setUsage(THREE.DynamicDrawUsage);
    this.mesh.setColorAt(0, new THREE.Color());
    this.mesh.frustumCulled = false;
    this.mesh.count = 0;
    this.mesh.renderOrder = 4;
    this.data = new Float32Array(capacity * 8);
    this.colors = new Float32Array(capacity * 3);
  }

  clear(): void {
    this.count = 0;
    this.mesh.count = 0;
  }

  add(x0: number, y: number, z0: number, x1: number, z1: number, color: THREE.Color, width = 0.06, life = 0.07): void {
    if (this.count >= this.capacity) return;
    const i = this.count++;
    const d = this.data;
    const o = i * 8;
    d[o] = x0; d[o + 1] = y; d[o + 2] = z0; d[o + 3] = x1; d[o + 4] = z1;
    d[o + 5] = life; d[o + 6] = life; d[o + 7] = width;
    this.colors[i * 3] = color.r;
    this.colors[i * 3 + 1] = color.g;
    this.colors[i * 3 + 2] = color.b;
  }

  update(dt: number): void {
    const d = this.data;
    for (let i = this.count - 1; i >= 0; i--) {
      const o = i * 8;
      d[o + 5] = (d[o + 5] as number) - dt;
      if ((d[o + 5] as number) > 0) continue;
      const last = --this.count;
      if (i !== last) {
        d.copyWithin(o, last * 8, last * 8 + 8);
        this.colors.copyWithin(i * 3, last * 3, last * 3 + 3);
      }
    }
  }

  sync(): void {
    const d = this.data;
    for (let i = 0; i < this.count; i++) {
      const o = i * 8;
      const x0 = d[o] as number;
      const z0 = d[o + 2] as number;
      const dx = (d[o + 3] as number) - x0;
      const dz = (d[o + 4] as number) - z0;
      const len = Math.hypot(dx, dz);
      const t = (d[o + 5] as number) / (d[o + 6] as number);
      // The tracer's tail catches up with the head as it fades.
      const start = (1 - t) * 0.6;
      this.e.set(0, Math.atan2(dx, dz), 0);
      this.q.setFromEuler(this.e);
      this.p.set(x0 + dx * start, d[o + 1] as number, z0 + dz * start);
      const w = (d[o + 7] as number) * (0.5 + 0.5 * t);
      this.s.set(w, w, Math.max(0.01, len * (1 - start)));
      this.m.compose(this.p, this.q, this.s);
      this.mesh.setMatrixAt(i, this.m);
      const k = 1.5 * t;
      this.c.setRGB((this.colors[i * 3] as number) * k, (this.colors[i * 3 + 1] as number) * k, (this.colors[i * 3 + 2] as number) * k);
      this.mesh.setColorAt(i, this.c);
    }
    this.mesh.count = this.count;
    if (this.count > 0) {
      this.mesh.instanceMatrix.needsUpdate = true;
      (this.mesh.instanceColor as THREE.InstancedBufferAttribute).needsUpdate = true;
    }
  }
}
