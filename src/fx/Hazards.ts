import * as THREE from 'three';
import { BOSS, SPITTER } from '../config/zombies';
import type { World } from '../game/World';

export interface Telegraph {
  kind: 'line' | 'circle';
  x: number;
  z: number;
  dirX: number;
  dirZ: number;
  length: number;
  width: number;
  radius: number;
  /** 0..1 fill progress; the inner fill grows until the attack lands. */
  progress: number;
  active: boolean;
  outer: THREE.Mesh;
  inner: THREE.Mesh;
}

interface AcidBlob {
  x0: number;
  z0: number;
  x1: number;
  z1: number;
  t: number;
  duration: number;
  damage: number;
}

interface Puddle {
  x: number;
  z: number;
  r: number;
  time: number;
  dps: number;
}

interface Shockwave {
  x: number;
  z: number;
  radius: number;
  delay: number;
  damage: number;
  hit: boolean;
  mesh: THREE.Mesh;
}

const MAX_BLOBS = 48;
const MAX_TELEGRAPHS = 8;
const MAX_WAVES = 6;

/**
 * Enemy-side hazards: spitter acid (projectiles + puddles), boss shockwave
 * rings and ground telegraphs that warn the player before big attacks.
 */
export class Hazards {
  readonly group = new THREE.Group();
  private readonly blobs: AcidBlob[] = [];
  private readonly puddles: Puddle[] = [];
  private readonly waves: Shockwave[] = [];
  private readonly telegraphs: Telegraph[] = [];
  private readonly freeWaveMeshes: THREE.Mesh[] = [];
  private readonly blobMesh: THREE.InstancedMesh;
  private readonly m = new THREE.Matrix4();
  private readonly v = new THREE.Vector3();
  private readonly s = new THREE.Vector3();
  private readonly q = new THREE.Quaternion();
  private readonly planeGeo = new THREE.PlaneGeometry(1, 1);
  /** Unit-diameter disc for circular telegraphs. */
  private readonly discGeo = new THREE.CircleGeometry(0.5, 40);
  private bubbleTimer = 0;
  private time = 0;

  constructor() {
    const blobMat = new THREE.MeshBasicMaterial({ color: '#9dff4a', toneMapped: false });
    this.blobMesh = new THREE.InstancedMesh(new THREE.IcosahedronGeometry(0.22, 1), blobMat, MAX_BLOBS);
    this.blobMesh.instanceMatrix.setUsage(THREE.DynamicDrawUsage);
    this.blobMesh.frustumCulled = false;
    this.blobMesh.count = 0;
    this.group.add(this.blobMesh);

    for (let i = 0; i < MAX_TELEGRAPHS; i++) {
      const outerMat = new THREE.MeshBasicMaterial({ color: '#ff2a1a', transparent: true, opacity: 0.25, depthWrite: false, blending: THREE.AdditiveBlending, toneMapped: false });
      const innerMat = new THREE.MeshBasicMaterial({ color: '#ff5a2a', transparent: true, opacity: 0.45, depthWrite: false, blending: THREE.AdditiveBlending, toneMapped: false });
      const outer = new THREE.Mesh(this.planeGeo, outerMat);
      const inner = new THREE.Mesh(this.planeGeo, innerMat);
      outer.visible = inner.visible = false;
      outer.renderOrder = inner.renderOrder = 2;
      this.group.add(outer, inner);
      this.telegraphs.push({ kind: 'line', x: 0, z: 0, dirX: 0, dirZ: 1, length: 1, width: 1, radius: 1, progress: 0, active: false, outer, inner });
    }
    const ringGeo = new THREE.CylinderGeometry(1, 1, 0.9, 48, 1, true);
    ringGeo.translate(0, 0.45, 0);
    for (let i = 0; i < MAX_WAVES; i++) {
      const mat = new THREE.MeshBasicMaterial({ color: '#ff8a3a', transparent: true, opacity: 0.8, side: THREE.DoubleSide, depthWrite: false, blending: THREE.AdditiveBlending, toneMapped: false });
      const mesh = new THREE.Mesh(ringGeo, mat);
      mesh.visible = false;
      this.group.add(mesh);
      this.freeWaveMeshes.push(mesh);
    }
  }

  clear(): void {
    this.blobs.length = 0;
    this.puddles.length = 0;
    for (const w of this.waves) {
      w.mesh.visible = false;
      this.freeWaveMeshes.push(w.mesh);
    }
    this.waves.length = 0;
    for (const t of this.telegraphs) this.releaseTelegraph(t);
    this.blobMesh.count = 0;
  }

  /** Lobs an acid glob from (x0, z0) toward (x1, z1). */
  spitAcid(x0: number, z0: number, x1: number, z1: number, damage: number): void {
    if (this.blobs.length >= MAX_BLOBS) return;
    const dist = Math.hypot(x1 - x0, z1 - z0);
    this.blobs.push({ x0, z0, x1, z1, t: 0, duration: Math.max(0.35, dist / SPITTER.projectileSpeed), damage });
  }

  private acquireTelegraph(): Telegraph | null {
    const t = this.telegraphs.find((x) => !x.active);
    if (!t) return null;
    t.active = true;
    t.progress = 0;
    t.outer.visible = t.inner.visible = true;
    return t;
  }

  telegraphLine(x: number, z: number, dirX: number, dirZ: number, length: number, width: number): Telegraph | null {
    const t = this.acquireTelegraph();
    if (!t) return null;
    Object.assign(t, { kind: 'line', x, z, dirX, dirZ, length, width });
    t.outer.geometry = t.inner.geometry = this.planeGeo;
    return t;
  }

  telegraphCircle(x: number, z: number, radius: number): Telegraph | null {
    const t = this.acquireTelegraph();
    if (!t) return null;
    Object.assign(t, { kind: 'circle', x, z, radius });
    t.outer.geometry = t.inner.geometry = this.discGeo;
    return t;
  }

  releaseTelegraph(t: Telegraph | null | undefined): void {
    if (!t) return;
    t.active = false;
    t.outer.visible = t.inner.visible = false;
  }

  /** Spawns an expanding shockwave ring (boss ground slam). */
  shockwave(x: number, z: number, damage: number, delay = 0): void {
    const mesh = this.freeWaveMeshes.pop();
    if (!mesh) return;
    this.waves.push({ x, z, radius: 0.5, delay, damage, hit: false, mesh });
  }

  update(dt: number, world: World): void {
    this.time += dt;
    const player = world.player;

    // Acid globs.
    for (let i = this.blobs.length - 1; i >= 0; i--) {
      const b = this.blobs[i] as AcidBlob;
      b.t += dt;
      if (b.t < b.duration) continue;
      this.blobs.splice(i, 1);
      world.fx.acid(b.x1, 0.2, b.z1, 12);
      world.audio.sfx('acidSplash', { x: b.x1, z: b.z1 });
      const d = Math.hypot(player.x - b.x1, player.z - b.z1);
      if (d < SPITTER.splashRadius + player.radius) world.combat.damagePlayer(b.damage, b.x1, b.z1, 0, 'acid');
      this.puddles.push({ x: b.x1, z: b.z1, r: SPITTER.puddleRadius, time: SPITTER.puddleDuration, dps: SPITTER.puddleDps * (b.damage / 9) });
      world.fx.acidPuddle(b.x1, b.z1, SPITTER.puddleRadius, SPITTER.puddleDuration);
    }

    // Puddles damage over time.
    this.bubbleTimer -= dt;
    const bubble = this.bubbleTimer <= 0;
    if (bubble) this.bubbleTimer = 0.08;
    for (let i = this.puddles.length - 1; i >= 0; i--) {
      const p = this.puddles[i] as Puddle;
      p.time -= dt;
      if (p.time <= 0) {
        this.puddles.splice(i, 1);
        continue;
      }
      if (bubble && Math.random() < 0.6) {
        const a = Math.random() * Math.PI * 2;
        const r = Math.random() * p.r * 0.8;
        world.fx.bubble(p.x + Math.cos(a) * r, p.z + Math.sin(a) * r);
      }
      const d = Math.hypot(player.x - p.x, player.z - p.z);
      if (d < p.r && !player.rolling) world.combat.damagePlayer(p.dps * dt, p.x, p.z, 0, 'acid');
    }

    // Shockwaves.
    for (let i = this.waves.length - 1; i >= 0; i--) {
      const w = this.waves[i] as Shockwave;
      if (w.delay > 0) {
        w.delay -= dt;
        continue;
      }
      w.radius += BOSS.slamRingSpeed * dt;
      if (w.radius >= BOSS.slamRingMaxRadius) {
        w.mesh.visible = false;
        this.freeWaveMeshes.push(w.mesh);
        this.waves.splice(i, 1);
        continue;
      }
      if (!w.hit && player.alive) {
        const d = Math.hypot(player.x - w.x, player.z - w.z);
        if (Math.abs(d - w.radius) < BOSS.slamRingWidth * 0.5 + player.radius) {
          w.hit = true;
          // Rolling through the ring (i-frames) avoids it entirely.
          if (!player.rolling) world.combat.damagePlayer(w.damage, w.x, w.z, 9, 'shockwave');
        }
      }
      if (Math.random() < 0.5) {
        const a = Math.random() * Math.PI * 2;
        world.fx.dust(w.x + Math.cos(a) * w.radius, w.z + Math.sin(a) * w.radius, 1, 0);
      }
    }
  }

  /** Updates meshes for rendering. */
  sync(): void {
    let n = 0;
    for (const b of this.blobs) {
      const t = b.t / b.duration;
      const x = b.x0 + (b.x1 - b.x0) * t;
      const z = b.z0 + (b.z1 - b.z0) * t;
      const y = 1.6 * (1 - t) + 0.2 + Math.sin(t * Math.PI) * Math.min(4, b.duration * 4);
      this.m.compose(this.v.set(x, y, z), this.q.identity(), this.s.setScalar(1 + Math.sin(this.time * 20) * 0.15));
      this.blobMesh.setMatrixAt(n++, this.m);
    }
    this.blobMesh.count = n;
    if (n > 0) this.blobMesh.instanceMatrix.needsUpdate = true;

    for (const w of this.waves) {
      w.mesh.visible = w.delay <= 0;
      w.mesh.position.set(w.x, 0, w.z);
      w.mesh.scale.set(w.radius, 1 - (w.radius / BOSS.slamRingMaxRadius) * 0.6, w.radius);
      (w.mesh.material as THREE.MeshBasicMaterial).opacity = 0.85 * (1 - w.radius / BOSS.slamRingMaxRadius);
    }

    const pulse = 0.75 + Math.sin(this.time * 18) * 0.25;
    for (const t of this.telegraphs) {
      if (!t.active) continue;
      const outerMat = t.outer.material as THREE.MeshBasicMaterial;
      const innerMat = t.inner.material as THREE.MeshBasicMaterial;
      outerMat.opacity = 0.22 * pulse;
      innerMat.opacity = 0.35 + 0.3 * t.progress;
      if (t.kind === 'line') {
        const yaw = Math.atan2(t.dirX, t.dirZ);
        for (const [mesh, len] of [[t.outer, t.length], [t.inner, t.length * t.progress]] as const) {
          mesh.rotation.set(-Math.PI / 2, 0, 0);
          mesh.rotation.order = 'YXZ';
          mesh.rotation.y = yaw;
          mesh.scale.set(t.width, Math.max(0.01, len), 1);
          mesh.position.set(t.x + t.dirX * len * 0.5, 0.05, t.z + t.dirZ * len * 0.5);
        }
      } else {
        for (const [mesh, r] of [[t.outer, t.radius], [t.inner, t.radius * t.progress]] as const) {
          mesh.rotation.set(-Math.PI / 2, 0, 0);
          mesh.scale.set(Math.max(0.01, r * 2), Math.max(0.01, r * 2), 1);
          mesh.position.set(t.x, 0.05, t.z);
        }
      }
    }
  }
}
