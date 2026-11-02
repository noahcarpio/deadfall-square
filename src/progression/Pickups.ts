import * as THREE from 'three';
import { WEAPONS, WEAPON_ORDER, type WeaponId } from '../config/weapons';
import type { PickupKind } from '../game/events';
import type { World } from '../game/World';
import { buildWeaponGeometry } from '../weapons/WeaponModels';
import { MeshBuilder } from '../world/MeshBuilder';
import type { Zombie } from '../zombies/Zombie';

const LIFETIME = 22;
const COLLECT_RADIUS = 1.0;
const BASE_DROP_CHANCE = 0.085;

/** Earliest wave each weapon can drop. */
const WEAPON_DROP_WAVE: Record<WeaponId, number> = {
  pistol: 999, shotgun: 2, smg: 3, rifle: 4, sniper: 6, flamer: 7, launcher: 8,
};

const KIND_COLORS: Record<PickupKind, string> = {
  ammo: '#e0c050',
  health: '#ff4a5a',
  armor: '#4aa8ff',
  weapon: '#c070ff',
  coins: '#ffd23a',
};

interface Pickup {
  kind: PickupKind;
  weapon: WeaponId | null;
  x: number;
  z: number;
  life: number;
  phase: number;
  /** Follows the player once inside the magnet radius. */
  magnet: boolean;
  mesh: THREE.Mesh;
  ring: THREE.Mesh;
  extra: THREE.Mesh | null;
}

/** Loot dropped by zombies: ammo, health, armor, coins and weapon crates. */
export class Pickups {
  readonly group = new THREE.Group();
  readonly list: Pickup[] = [];
  private readonly geometries = new Map<PickupKind, THREE.BufferGeometry>();
  private readonly weaponGeos = new Map<WeaponId, THREE.BufferGeometry>();
  private readonly material = new THREE.MeshLambertMaterial({ vertexColors: true, flatShading: true });
  private readonly ringGeo = new THREE.RingGeometry(0.45, 0.62, 28);
  private readonly ringMats = new Map<PickupKind, THREE.MeshBasicMaterial>();
  /** When true (wave cleared) every pickup flies to the player. */
  vacuum = false;

  constructor() {
    this.ringGeo.rotateX(-Math.PI / 2);
    for (const kind of Object.keys(KIND_COLORS) as PickupKind[]) {
      this.geometries.set(kind, buildPickupGeometry(kind));
      this.ringMats.set(kind, new THREE.MeshBasicMaterial({
        color: KIND_COLORS[kind], transparent: true, opacity: 0.7, blending: THREE.AdditiveBlending, depthWrite: false, toneMapped: false,
      }));
    }
  }

  clear(): void {
    for (const p of this.list) this.disposePickup(p);
    this.list.length = 0;
    this.vacuum = false;
  }

  private disposePickup(p: Pickup): void {
    this.group.remove(p.mesh, p.ring);
    if (p.extra) this.group.remove(p.extra);
  }

  /** Rolls loot for a killed zombie. */
  rollDrop(z: Zombie, world: World): void {
    const rng = world.rng;
    const chance = BASE_DROP_CHANCE * z.def.dropMult * world.player.stats.dropChance;
    // Pity rule: low ammo makes ammo drops more likely.
    const lowAmmo = world.arsenal.lowOnAmmo(0.2);
    if (!rng.chance(lowAmmo ? chance * 1.6 : chance)) return;
    const p = world.player;
    const missing = 1 - p.health / p.stats.maxHealth;
    const weights: Partial<Record<PickupKind, number>> = {
      ammo: world.arsenal.list().length > 1 ? (lowAmmo ? 60 : 32) : 6,
      health: 10 + missing * 45,
      armor: p.armor < p.stats.maxArmor ? 14 : 2,
      coins: 18,
      weapon: this.weaponCandidates(world).length > 0 ? 7 : 0,
    };
    const kind = rng.weighted(weights);
    this.spawn(kind, z.x, z.z, world);
  }

  private weaponCandidates(world: World): WeaponId[] {
    const wave = world.waves.wave;
    return WEAPON_ORDER.filter((id) => wave >= WEAPON_DROP_WAVE[id] && !world.arsenal.owns(id));
  }

  spawn(kind: PickupKind, x: number, z: number, world: World): void {
    let weapon: WeaponId | null = null;
    if (kind === 'weapon') {
      const candidates = this.weaponCandidates(world);
      if (candidates.length === 0) kind = 'ammo';
      else weapon = world.rng.pick(candidates);
    }
    const mesh = new THREE.Mesh(this.geometries.get(kind), this.material);
    mesh.castShadow = true;
    const ring = new THREE.Mesh(this.ringGeo, this.ringMats.get(kind));
    ring.position.set(x, 0.04, z);
    let extra: THREE.Mesh | null = null;
    if (weapon) {
      let g = this.weaponGeos.get(weapon);
      if (!g) {
        g = buildWeaponGeometry(weapon).geometry;
        this.weaponGeos.set(weapon, g);
      }
      extra = new THREE.Mesh(g, this.material);
      extra.scale.setScalar(1.6);
      this.group.add(extra);
    }
    this.group.add(mesh, ring);
    this.list.push({ kind, weapon, x, z, life: LIFETIME, phase: Math.random() * 6, magnet: false, mesh, ring, extra });
  }

  update(dt: number, world: World): void {
    const player = world.player;
    const magnetR = player.stats.magnetRadius;
    for (let i = this.list.length - 1; i >= 0; i--) {
      const p = this.list[i] as Pickup;
      p.life -= dt;
      p.phase += dt;
      if (p.life <= 0) {
        this.disposePickup(p);
        this.list.splice(i, 1);
        continue;
      }
      const dx = player.x - p.x;
      const dz = player.z - p.z;
      const d = Math.hypot(dx, dz);
      if (player.alive && (this.vacuum || d < magnetR)) p.magnet = true;
      if (p.magnet && player.alive) {
        const speed = this.vacuum ? 22 : 10 + (magnetR - Math.min(d, magnetR)) * 4;
        const step = Math.min(d, speed * dt);
        p.x += (dx / (d || 1)) * step;
        p.z += (dz / (d || 1)) * step;
      }
      if (player.alive && d < COLLECT_RADIUS) {
        if (this.collect(p, world)) {
          this.disposePickup(p);
          this.list.splice(i, 1);
        }
      }
    }
  }

  /** Applies the pickup. Returns false if it should stay (e.g. full health). */
  private collect(p: Pickup, world: World): boolean {
    const player = world.player;
    let label = '';
    switch (p.kind) {
      case 'health': {
        const healed = player.heal(30);
        if (healed <= 0 && !this.vacuum) return false;
        label = `+${Math.round(healed)} HP`;
        world.audio.sfx('pickupHealth');
        world.fx.numbers.spawn(label, player.x, 2.4, player.z, 'heal');
        break;
      }
      case 'armor': {
        const added = player.addArmor(20);
        if (added <= 0 && !this.vacuum) return false;
        label = `+${Math.round(added)} ARMOR`;
        world.audio.sfx('pickup');
        world.fx.numbers.spawn(label, player.x, 2.4, player.z, 'info');
        break;
      }
      case 'ammo': {
        let total = 0;
        for (const w of world.arsenal.list()) total += world.arsenal.addAmmoFraction(w.def.id, 0.3);
        label = total > 0 ? 'AMMO' : 'AMMO (FULL)';
        world.audio.sfx('pickup');
        world.fx.numbers.spawn(label, player.x, 2.4, player.z, 'info');
        break;
      }
      case 'coins': {
        const amount = Math.round(world.rng.int(12, 22) * (1 + world.waves.wave * 0.08) * world.economy.coinMultiplier);
        world.economy.addCoins(amount);
        label = `+${amount} COINS`;
        world.audio.sfx('coin');
        world.fx.numbers.spawn(label, player.x, 2.4, player.z, 'coin');
        break;
      }
      case 'weapon': {
        const id = p.weapon as WeaponId;
        const res = world.arsenal.give(id);
        label = res === 'new' ? WEAPONS[id].name.toUpperCase() : `${WEAPONS[id].name.toUpperCase()} AMMO`;
        world.audio.sfx('pickupWeapon');
        world.fx.numbers.spawn(label, player.x, 2.4, player.z, 'info');
        if (res === 'new') {
          world.events.emit('weaponAcquired', { weapon: id });
          world.events.emit('notify', { text: `New weapon: ${WEAPONS[id].name} [${WEAPONS[id].slot}]`, tone: 'good' });
        }
        break;
      }
    }
    world.fx.sparkle(p.x, 0.8, p.z, new THREE.Color(KIND_COLORS[p.kind]));
    world.stats.pickupsCollected++;
    world.events.emit('pickupCollected', { kind: p.kind, label });
    return true;
  }

  /** Positions/animates meshes (render step). */
  sync(): void {
    for (const p of this.list) {
      const bob = Math.sin(p.phase * 3) * 0.12;
      const blink = p.life < 5 && Math.sin(p.phase * 16) > 0;
      p.mesh.visible = !blink;
      p.mesh.position.set(p.x, 0.45 + bob, p.z);
      p.mesh.rotation.y = p.phase * 1.8;
      p.ring.position.set(p.x, 0.04, p.z);
      p.ring.scale.setScalar(1 + Math.sin(p.phase * 4) * 0.08);
      if (p.extra) {
        p.extra.visible = !blink;
        p.extra.position.set(p.x, 1.05 + bob, p.z);
        p.extra.rotation.y = p.phase * 1.8;
      }
    }
  }
}

function buildPickupGeometry(kind: PickupKind): THREE.BufferGeometry {
  const b = new MeshBuilder();
  switch (kind) {
    case 'ammo':
      b.box(0.62, 0.36, 0.42, '#4a5a2a', 0, 0, 0);
      b.box(0.64, 0.06, 0.44, '#2e3a1a', 0, 0.12, 0);
      for (let i = 0; i < 4; i++) b.cylinder(0.04, 0.04, 0.2, 6, '#d8b040', -0.18 + i * 0.12, 0.28, 0);
      break;
    case 'health':
      b.box(0.6, 0.4, 0.45, '#f2f2f2', 0, 0, 0);
      b.box(0.36, 0.1, 0.46, '#d42a3a', 0, 0.05, 0);
      b.box(0.12, 0.34, 0.46, '#d42a3a', 0, 0.05, 0);
      break;
    case 'armor':
      b.box(0.5, 0.6, 0.12, '#2e5f8f', 0, 0.05, 0);
      b.box(0.4, 0.15, 0.14, '#4a8ad0', 0, 0.2, 0);
      b.box(0.3, 0.3, 0.14, '#24476c', 0, -0.1, 0);
      break;
    case 'coins':
      for (let i = 0; i < 4; i++) b.cylinder(0.2, 0.2, 0.07, 10, i % 2 ? '#f0c030' : '#d8a820', 0.02 * (i % 2), -0.1 + i * 0.08, 0);
      b.cylinder(0.2, 0.2, 0.07, 10, '#f0c030', 0.28, -0.1, 0.1);
      break;
    case 'weapon':
      b.box(0.9, 0.42, 0.55, '#6a4a2a', 0, -0.1, 0);
      b.box(0.92, 0.08, 0.57, '#3e2a18', 0, 0.06, 0);
      b.box(0.1, 0.44, 0.57, '#3e2a18', 0.3, -0.1, 0);
      b.box(0.1, 0.44, 0.57, '#3e2a18', -0.3, -0.1, 0);
      break;
  }
  return b.build();
}
