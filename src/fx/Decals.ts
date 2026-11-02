import * as THREE from 'three';

function makeSplatTexture(): THREE.CanvasTexture {
  const size = 128;
  const c = document.createElement('canvas');
  c.width = c.height = size;
  const g = c.getContext('2d');
  if (!g) throw new Error('2D canvas unavailable');
  g.fillStyle = '#fff';
  // Irregular blob: a core plus satellite droplets.
  const blob = (x: number, y: number, r: number, a: number): void => {
    const grad = g.createRadialGradient(x, y, 0, x, y, r);
    grad.addColorStop(0, `rgba(255,255,255,${a})`);
    grad.addColorStop(0.7, `rgba(255,255,255,${a * 0.8})`);
    grad.addColorStop(1, 'rgba(255,255,255,0)');
    g.fillStyle = grad;
    g.beginPath();
    g.arc(x, y, r, 0, Math.PI * 2);
    g.fill();
  };
  blob(64, 64, 40, 1);
  for (let i = 0; i < 14; i++) {
    const a = (i / 14) * Math.PI * 2 + Math.sin(i * 7.3) * 0.4;
    const d = 30 + ((i * 37) % 22);
    blob(64 + Math.cos(a) * d, 64 + Math.sin(a) * d, 5 + ((i * 13) % 9), 0.9);
  }
  const tex = new THREE.CanvasTexture(c);
  return tex;
}

/**
 * Ground decals (blood, scorch marks, acid) as one instanced mesh with a
 * per-instance alpha attribute. Oldest decals are recycled first.
 */
export class Decals {
  readonly mesh: THREE.InstancedMesh;
  private readonly alpha: THREE.InstancedBufferAttribute;
  private readonly life: Float32Array;
  private readonly maxLife: Float32Array;
  private readonly baseAlpha: Float32Array;
  private next = 0;
  private used = 0;
  private readonly m = new THREE.Matrix4();
  private readonly q = new THREE.Quaternion();
  private readonly e = new THREE.Euler();
  private readonly p = new THREE.Vector3();
  private readonly s = new THREE.Vector3();
  private readonly hidden = new THREE.Matrix4().makeScale(0, 0, 0);
  budget: number;

  constructor(private readonly capacity: number) {
    this.budget = capacity;
    const geo = new THREE.PlaneGeometry(1, 1);
    geo.rotateX(-Math.PI / 2);
    this.alpha = new THREE.InstancedBufferAttribute(new Float32Array(capacity), 1);
    this.alpha.setUsage(THREE.DynamicDrawUsage);
    geo.setAttribute('aAlpha', this.alpha);
    const mat = new THREE.MeshBasicMaterial({
      map: makeSplatTexture(),
      transparent: true,
      depthWrite: false,
      polygonOffset: true,
      polygonOffsetFactor: -2,
      polygonOffsetUnits: -2,
    });
    mat.onBeforeCompile = (shader) => {
      shader.vertexShader = shader.vertexShader
        .replace('#include <common>', '#include <common>\nattribute float aAlpha;\nvarying float vAlpha;')
        .replace('#include <begin_vertex>', '#include <begin_vertex>\nvAlpha = aAlpha;');
      shader.fragmentShader = shader.fragmentShader
        .replace('#include <common>', '#include <common>\nvarying float vAlpha;')
        .replace('#include <color_fragment>', '#include <color_fragment>\ndiffuseColor.a *= vAlpha;');
    };
    mat.customProgramCacheKey = () => 'decal-alpha';
    this.mesh = new THREE.InstancedMesh(geo, mat, capacity);
    this.mesh.instanceMatrix.setUsage(THREE.DynamicDrawUsage);
    this.mesh.setColorAt(0, new THREE.Color());
    this.mesh.frustumCulled = false;
    this.mesh.receiveShadow = false;
    this.mesh.renderOrder = 1;
    this.life = new Float32Array(capacity);
    this.maxLife = new Float32Array(capacity);
    this.baseAlpha = new Float32Array(capacity);
    for (let i = 0; i < capacity; i++) this.mesh.setMatrixAt(i, this.hidden);
    this.mesh.count = 0;
  }

  clear(): void {
    for (let i = 0; i < this.capacity; i++) {
      this.life[i] = 0;
      this.mesh.setMatrixAt(i, this.hidden);
    }
    this.mesh.instanceMatrix.needsUpdate = true;
    this.next = 0;
    this.used = 0;
    this.mesh.count = 0;
  }

  add(x: number, z: number, size: number, color: THREE.Color, alpha: number, life: number): void {
    const limit = Math.min(this.budget, this.capacity);
    const i = this.next;
    this.next = (this.next + 1) % limit;
    this.used = Math.max(this.used, i + 1);
    this.e.set(0, Math.random() * Math.PI * 2, 0);
    this.q.setFromEuler(this.e);
    // Tiny height offset per slot prevents z-fighting between overlapping decals.
    this.p.set(x, 0.02 + (i % 16) * 0.002, z);
    const stretch = 0.75 + Math.random() * 0.5;
    this.s.set(size * stretch, 1, size / stretch);
    this.m.compose(this.p, this.q, this.s);
    this.mesh.setMatrixAt(i, this.m);
    this.mesh.setColorAt(i, color);
    this.life[i] = life;
    this.maxLife[i] = life;
    this.baseAlpha[i] = alpha;
    this.alpha.setX(i, alpha);
    this.mesh.count = this.used;
    this.mesh.instanceMatrix.needsUpdate = true;
    (this.mesh.instanceColor as THREE.InstancedBufferAttribute).needsUpdate = true;
    this.alpha.needsUpdate = true;
  }

  update(dt: number): void {
    let dirty = false;
    for (let i = 0; i < this.used; i++) {
      const l = this.life[i] as number;
      if (l <= 0) continue;
      const nl = l - dt;
      this.life[i] = nl;
      const t = nl / (this.maxLife[i] as number);
      // Hold, then fade out over the last 30% of life.
      const a = (this.baseAlpha[i] as number) * Math.min(1, t / 0.3);
      this.alpha.setX(i, Math.max(0, a));
      if (nl <= 0) this.mesh.setMatrixAt(i, this.hidden);
      dirty = true;
    }
    if (dirty) {
      this.alpha.needsUpdate = true;
      this.mesh.instanceMatrix.needsUpdate = true;
    }
  }
}
