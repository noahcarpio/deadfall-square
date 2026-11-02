import * as THREE from 'three';

export interface ParticleSpec {
  x: number;
  y: number;
  z: number;
  vx: number;
  vy: number;
  vz: number;
  life: number;
  size: number;
  color: THREE.Color;
  /** Gravity multiplier (1 = normal, negative rises like smoke/fire). */
  gravity?: number;
  /** Linear drag per second. */
  drag?: number;
  /** Grow factor over lifetime (smoke expands). */
  grow?: number;
}

const GRAVITY = 18;

/**
 * Pooled, instanced particle system (tumbling low-poly cubes). Data lives in
 * typed arrays; dead particles are swap-removed so the live set is contiguous.
 * `glow` systems render additively and fade by colour.
 */
export class ParticleSystem {
  readonly mesh: THREE.InstancedMesh;
  private count = 0;
  private capacity: number;
  private readonly pos: Float32Array;
  private readonly vel: Float32Array;
  private readonly rot: Float32Array;
  private readonly spin: Float32Array;
  private readonly col: Float32Array;
  private readonly life: Float32Array;
  private readonly maxLife: Float32Array;
  private readonly size: Float32Array;
  private readonly gravity: Float32Array;
  private readonly drag: Float32Array;
  private readonly grow: Float32Array;
  private readonly m = new THREE.Matrix4();
  private readonly q = new THREE.Quaternion();
  private readonly e = new THREE.Euler();
  private readonly p = new THREE.Vector3();
  private readonly s = new THREE.Vector3();
  private readonly c = new THREE.Color();
  /** Soft limit (quality setting); spawns beyond it are dropped. */
  budget: number;

  constructor(maxCapacity: number, private readonly glow: boolean) {
    this.capacity = maxCapacity;
    this.budget = maxCapacity;
    const n = maxCapacity;
    this.pos = new Float32Array(n * 3);
    this.vel = new Float32Array(n * 3);
    this.rot = new Float32Array(n * 3);
    this.spin = new Float32Array(n * 3);
    this.col = new Float32Array(n * 3);
    this.life = new Float32Array(n);
    this.maxLife = new Float32Array(n);
    this.size = new Float32Array(n);
    this.gravity = new Float32Array(n);
    this.drag = new Float32Array(n);
    this.grow = new Float32Array(n);

    const geometry = new THREE.BoxGeometry(1, 1, 1);
    const material = glow
      ? new THREE.MeshBasicMaterial({ blending: THREE.AdditiveBlending, depthWrite: false, transparent: true, toneMapped: false })
      : new THREE.MeshLambertMaterial({ flatShading: true });
    this.mesh = new THREE.InstancedMesh(geometry, material, n);
    this.mesh.instanceMatrix.setUsage(THREE.DynamicDrawUsage);
    this.mesh.setColorAt(0, new THREE.Color());
    (this.mesh.instanceColor as THREE.InstancedBufferAttribute).setUsage(THREE.DynamicDrawUsage);
    this.mesh.frustumCulled = false;
    this.mesh.count = 0;
    this.mesh.renderOrder = glow ? 3 : 0;
  }

  get liveCount(): number {
    return this.count;
  }

  clear(): void {
    this.count = 0;
    this.mesh.count = 0;
  }

  spawn(sp: ParticleSpec): void {
    if (this.count >= Math.min(this.budget, this.capacity)) return;
    const i = this.count++;
    const i3 = i * 3;
    this.pos[i3] = sp.x;
    this.pos[i3 + 1] = sp.y;
    this.pos[i3 + 2] = sp.z;
    this.vel[i3] = sp.vx;
    this.vel[i3 + 1] = sp.vy;
    this.vel[i3 + 2] = sp.vz;
    this.rot[i3] = Math.random() * 6;
    this.rot[i3 + 1] = Math.random() * 6;
    this.rot[i3 + 2] = Math.random() * 6;
    this.spin[i3] = (Math.random() - 0.5) * 14;
    this.spin[i3 + 1] = (Math.random() - 0.5) * 14;
    this.spin[i3 + 2] = (Math.random() - 0.5) * 14;
    this.col[i3] = sp.color.r;
    this.col[i3 + 1] = sp.color.g;
    this.col[i3 + 2] = sp.color.b;
    this.life[i] = sp.life;
    this.maxLife[i] = sp.life;
    this.size[i] = sp.size;
    this.gravity[i] = sp.gravity ?? 1;
    this.drag[i] = sp.drag ?? 0.5;
    this.grow[i] = sp.grow ?? 0;
  }

  private kill(i: number): void {
    const last = --this.count;
    if (i === last) return;
    const i3 = i * 3;
    const l3 = last * 3;
    for (let k = 0; k < 3; k++) {
      this.pos[i3 + k] = this.pos[l3 + k] as number;
      this.vel[i3 + k] = this.vel[l3 + k] as number;
      this.rot[i3 + k] = this.rot[l3 + k] as number;
      this.spin[i3 + k] = this.spin[l3 + k] as number;
      this.col[i3 + k] = this.col[l3 + k] as number;
    }
    this.life[i] = this.life[last] as number;
    this.maxLife[i] = this.maxLife[last] as number;
    this.size[i] = this.size[last] as number;
    this.gravity[i] = this.gravity[last] as number;
    this.drag[i] = this.drag[last] as number;
    this.grow[i] = this.grow[last] as number;
  }

  update(dt: number): void {
    for (let i = this.count - 1; i >= 0; i--) {
      const life = (this.life[i] as number) - dt;
      if (life <= 0) {
        this.kill(i);
        continue;
      }
      this.life[i] = life;
      const i3 = i * 3;
      const drag = Math.exp(-(this.drag[i] as number) * dt);
      let vx = (this.vel[i3] as number) * drag;
      let vy = (this.vel[i3 + 1] as number) * drag - GRAVITY * (this.gravity[i] as number) * dt;
      let vz = (this.vel[i3 + 2] as number) * drag;
      const x = (this.pos[i3] as number) + vx * dt;
      let y = (this.pos[i3 + 1] as number) + vy * dt;
      const z = (this.pos[i3 + 2] as number) + vz * dt;
      const half = (this.size[i] as number) * 0.5;
      if (y < half && (this.gravity[i] as number) > 0) {
        y = half;
        if (vy < -1.5) {
          vy = -vy * 0.3;
          vx *= 0.6;
          vz *= 0.6;
        } else {
          vy = 0;
          vx *= 0.8;
          vz *= 0.8;
          this.spin[i3] = (this.spin[i3] as number) * 0.8;
          this.spin[i3 + 1] = (this.spin[i3 + 1] as number) * 0.8;
          this.spin[i3 + 2] = (this.spin[i3 + 2] as number) * 0.8;
        }
      }
      this.pos[i3] = x;
      this.pos[i3 + 1] = y;
      this.pos[i3 + 2] = z;
      this.vel[i3] = vx;
      this.vel[i3 + 1] = vy;
      this.vel[i3 + 2] = vz;
      this.rot[i3] = (this.rot[i3] as number) + (this.spin[i3] as number) * dt;
      this.rot[i3 + 1] = (this.rot[i3 + 1] as number) + (this.spin[i3 + 1] as number) * dt;
      this.rot[i3 + 2] = (this.rot[i3 + 2] as number) + (this.spin[i3 + 2] as number) * dt;
    }
  }

  /** Writes live particles into the instanced mesh. */
  sync(): void {
    const n = this.count;
    for (let i = 0; i < n; i++) {
      const i3 = i * 3;
      const t = (this.life[i] as number) / (this.maxLife[i] as number); // 1 -> 0
      const age = 1 - t;
      let size = this.size[i] as number;
      size *= 1 + (this.grow[i] as number) * age;
      // Glow fades/shrinks over its whole life; solids pop out over the last 25%.
      if (this.glow) size *= 0.35 + 0.65 * t;
      else size *= (this.grow[i] as number) > 0 ? Math.min(1, t * 1.5) : Math.min(1, t * 4);
      this.e.set(this.rot[i3] as number, this.rot[i3 + 1] as number, this.rot[i3 + 2] as number);
      this.q.setFromEuler(this.e);
      this.p.set(this.pos[i3] as number, this.pos[i3 + 1] as number, this.pos[i3 + 2] as number);
      this.s.set(size, size, size);
      this.m.compose(this.p, this.q, this.s);
      this.mesh.setMatrixAt(i, this.m);
      const fade = this.glow ? Math.pow(t, 0.8) : 1;
      this.c.setRGB((this.col[i3] as number) * fade, (this.col[i3 + 1] as number) * fade, (this.col[i3 + 2] as number) * fade);
      this.mesh.setColorAt(i, this.c);
    }
    this.mesh.count = n;
    if (n > 0) {
      this.mesh.instanceMatrix.needsUpdate = true;
      (this.mesh.instanceColor as THREE.InstancedBufferAttribute).needsUpdate = true;
    }
  }
}
