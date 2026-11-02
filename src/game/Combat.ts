import * as THREE from 'three';
import { BOSS, BRUTE, EXPLODER, ZOMBIES } from '../config/zombies';
import { applyArmor } from '../player/PlayerStats';
import type { Collider } from '../world/Collision';
import type { Structure } from '../progression/Structures';
import type { Zombie } from '../zombies/Zombie';
import type { World } from './World';

export interface DamageOptions {
  dirX: number;
  dirZ: number;
  knock: number;
  source: string;
  crit: boolean;
  hitX: number;
  hitZ: number;
  allowIncendiary: boolean;
}

interface PendingExplosion {
  x: number;
  z: number;
  radius: number;
  zombieDamage: number;
  playerDamage: number;
  structureDamage: number;
  source: string;
}

const MAX_EXPLOSIONS_PER_STEP = 24;

/**
 * Central damage rules: zombie damage/death (with perks, drops and rewards),
 * player damage (armor, i-frames, second wind), explosions (queued so chain
 * reactions resolve iteratively) and boss special attacks.
 */
export class Combat {
  /** Test hook: when true the player cannot die. */
  godMode = false;
  private readonly pending: PendingExplosion[] = [];
  private readonly near: Zombie[] = [];
  private readonly skinC = new THREE.Color();
  private readonly clothC = new THREE.Color();
  private secondWindUsedWave = -1;
  private lowHealthBeat = 0;

  constructor(private readonly world: World) {}

  reset(): void {
    this.pending.length = 0;
    this.secondWindUsedWave = -1;
  }

  damageZombie(z: Zombie, amount: number, o: DamageOptions): boolean {
    if (!z.alive || amount <= 0) return false;
    const w = this.world;
    if (z.type === 'brute' || z.type === 'boss') amount *= 1 + 0.35 * w.perks.level('bigGame');
    const dealt = Math.min(amount, z.hp);
    z.hp -= amount;
    z.flash = 1;
    z.lastHitBy = o.source;
    const mass = z.def.mass;
    z.kx += (o.dirX * o.knock) / mass;
    z.kz += (o.dirZ * o.knock) / mass;
    w.stats.damageDealt += dealt;

    if (w.perks.has('vampire') && w.player.alive) {
      const healed = w.player.heal(dealt * 0.03 * w.perks.level('vampire'));
      if (healed > 0) w.player.hurtFlash = Math.max(0, w.player.hurtFlash - 0.1);
    }
    if (o.allowIncendiary && w.perks.has('incendiary') && w.rng.chance(0.25 * w.perks.level('incendiary'))) {
      this.ignite(z, 9, 2.5);
    }

    const y = 1.1 * z.def.scale;
    if (o.source !== 'burn') {
      w.fx.blood(o.hitX, y, o.hitZ, o.dirX, o.dirZ, o.crit ? 6 : 3);
      w.audio.sfx('hit', { x: z.x, z: z.z, volume: 0.6 });
    }
    w.fx.numbers.spawn(String(Math.max(1, Math.round(amount))), z.x, y + 0.6 * z.def.scale, z.z, o.crit ? 'crit' : 'damage');

    if (z.hp <= 0) {
      this.killZombie(z, o.source, o.dirX, o.dirZ);
      return true;
    }
    return false;
  }

  ignite(z: Zombie, dps: number, duration: number): void {
    if (!z.alive) return;
    z.burnDps = Math.max(z.burnDps * (z.burnTime > 0 ? 1 : 0), dps);
    z.burnTime = Math.max(z.burnTime, duration);
  }

  /** Called each step for burning zombies by ZombieManager. */
  applyBurn(z: Zombie, dt: number): void {
    const w = this.world;
    z.burnAccum += z.burnDps * dt;
    if (Math.random() < 0.5) w.fx.fire(z.x, 0.6 * z.def.scale, z.z, 0.3 * z.def.scale);
    if (z.burnAccum >= 4 || (z.burnTime <= 0 && z.burnAccum > 0)) {
      const amount = z.burnAccum;
      z.burnAccum = 0;
      this.damageZombie(z, amount, { dirX: 0, dirZ: 0, knock: 0, source: 'burn', crit: false, hitX: z.x, hitZ: z.z, allowIncendiary: false });
    }
  }

  killZombie(z: Zombie, source: string, dirX: number, dirZ: number): void {
    if (!z.alive) return;
    const w = this.world;
    w.zombies.markDying(z, dirX || z.x - w.player.x, dirZ || z.z - w.player.z);
    w.hazards.releaseTelegraph(z.telegraph as never);
    z.telegraph = null;
    // Knock the corpse along the killing blow.
    z.kx += dirX * 3;
    z.kz += dirZ * 3;

    const reward = w.economy.registerKill(z.def.score * (1 + w.waves.wave * 0.05), z.def.coins);
    w.stats.kills[z.type]++;
    w.waves.onZombieKilled(z);
    w.events.emit('zombieKilled', { zombie: z, type: z.type, x: z.x, z: z.z, source, score: reward.score, coins: reward.coins });
    w.fx.numbers.spawn(`+${reward.coins}`, z.x + 0.4, 1.8 * z.def.scale, z.z, 'coin');

    this.skinC.set(z.def.colors.skin);
    this.clothC.set(z.def.colors.shirt);
    w.fx.gibs(z.x, z.z, this.skinC, this.clothC, z.def.scale, dirX, dirZ);
    w.audio.sfx('zombieDeath', { x: z.x, z: z.z });
    w.audio.sfx('coin', { volume: 0.4 });

    if (z.type !== 'boss') w.pickups.rollDrop(z, w);

    if (z.type === 'exploder') {
      this.queueExplosion(z.x, z.z, EXPLODER.blastRadius, EXPLODER.zombieDamage, z.damage, EXPLODER.structureDamage, 'exploder');
    } else if (w.perks.has('explosiveKills') && source !== 'perkBlast' && w.rng.chance(0.2 * w.perks.level('explosiveKills'))) {
      this.queueExplosion(z.x, z.z, 2.6, 45 * (1 + w.waves.wave * 0.05), 0, 0, 'perkBlast');
    }

    if (w.perks.has('adrenaline') && w.player.alive) {
      w.player.stamina = Math.min(w.player.stats.maxStamina, w.player.stamina + 8);
      w.player.speedBoost = 0.6;
    }

    if (z.type === 'boss') {
      w.stats.bossesKilled++;
      w.fx.shake(1);
      w.fx.explosion(z.x, z.z, 5);
      w.lighting.flashBlast(z.x, z.z, 120);
      w.audio.sfx('explosion');
      w.audio.sfx('bossDefeated');
      for (let i = 0; i < 5; i++) {
        const a = (i / 5) * Math.PI * 2;
        const kind = i === 0 ? 'weapon' : i % 2 ? 'health' : 'ammo';
        w.pickups.spawn(kind, z.x + Math.cos(a) * 2, z.z + Math.sin(a) * 2, w);
      }
      w.events.emit('bossDefeated', { wave: w.waves.wave });
      w.events.emit('notify', { text: 'BOSS DEFEATED', tone: 'good' });
    }
  }

  /** Exploder fuse ran out: it blows itself up. */
  detonate(z: Zombie): void {
    this.killZombie(z, 'self', 0, 0);
  }

  // ------------------------------------------------------------------ player

  damagePlayer(amount: number, srcX: number, srcZ: number, knock: number, source: string): void {
    const w = this.world;
    const p = w.player;
    if (!p.alive || amount <= 0 || w.targetIsPlayer === false) return;
    if (p.invulnerable > 0) return;
    amount *= p.stats.damageTaken;
    const continuous = amount < 1.5 && source === 'acid';
    const { health, armor } = applyArmor(p.health, p.armor, amount);
    w.stats.damageTaken += amount;
    p.armor = armor;
    p.health = health;

    const dx = p.x - srcX;
    const dz = p.z - srcZ;
    const len = Math.hypot(dx, dz) || 1;
    if (knock > 0) p.knock(dx / len, dz / len, knock);

    if (continuous) {
      p.hurtFlash = Math.max(p.hurtFlash, 0.35);
    } else {
      p.hurtFlash = 1;
      p.invulnerable = Math.max(p.invulnerable, 0.12);
      w.fx.shake(Math.min(0.6, 0.15 + amount / 60));
      w.fx.blood(p.x, 1.2, p.z, dx / len, dz / len, 5);
      w.audio.sfx('playerHurt');
      w.fx.numbers.spawn(`-${Math.round(amount)}`, p.x, 2.2, p.z, 'player');
    }
    w.events.emit('playerDamaged', { amount, source });

    if (p.health <= 0) {
      if (this.godMode) {
        p.health = 1;
        return;
      }
      if (w.perks.has('secondWind') && this.secondWindUsedWave !== w.waves.wave) {
        this.secondWindUsedWave = w.waves.wave;
        p.health = 1;
        p.invulnerable = 2;
        w.events.emit('notify', { text: 'SECOND WIND!', tone: 'good' });
        w.audio.sfx('perk');
        return;
      }
      p.health = 0;
      p.alive = false;
      w.fx.shake(0.8);
      w.events.emit('playerDied', { source });
    }
  }

  /** Low-health heartbeat cue. */
  update(dt: number): void {
    const p = this.world.player;
    if (!p.alive || p.health > p.stats.maxHealth * 0.3) return;
    this.lowHealthBeat -= dt;
    if (this.lowHealthBeat <= 0) {
      this.lowHealthBeat = 0.9;
      this.world.audio.sfx('heartbeat', { volume: 0.7 });
    }
  }

  zombieMeleePlayer(z: Zombie): void {
    const knock = z.type === 'brute' ? BRUTE.knockback : z.type === 'boss' ? 12 : 2.5;
    this.damagePlayer(z.damage, z.x, z.z, knock, z.type);
    if (z.type === 'brute') {
      this.world.fx.shake(0.45);
      this.world.fx.dust(z.x + Math.sin(z.facing) * 1.2, z.z + Math.cos(z.facing) * 1.2, 8, 0.5);
      this.world.audio.sfx('slam', { x: z.x, z: z.z, volume: 0.5 });
    }
  }

  zombieMeleeStructure(z: Zombie, target: unknown): void {
    this.world.structures.damage(target as Structure, z.damage * (z.type === 'brute' ? 3 : 1.6), this.world);
  }

  // -------------------------------------------------------------- explosions

  queueExplosion(x: number, z: number, radius: number, zombieDamage: number, playerDamage: number, structureDamage: number, source: string): void {
    this.pending.push({ x, z, radius, zombieDamage, playerDamage, structureDamage, source });
  }

  /** Resolves queued explosions, including chain reactions, with a safety cap. */
  processExplosions(): void {
    let processed = 0;
    while (this.pending.length > 0 && processed < MAX_EXPLOSIONS_PER_STEP) {
      const e = this.pending.shift() as PendingExplosion;
      this.explosion(e.x, e.z, e.radius, e.zombieDamage, e.playerDamage, e.structureDamage, e.source);
      processed++;
    }
  }

  /** Immediate explosion. Returns how many zombies were damaged. */
  explosion(x: number, z: number, radius: number, zombieDamage: number, playerDamage: number, structureDamage: number, source: string): number {
    const w = this.world;
    const n = w.zombies.queryRadius(x, z, radius, this.near);
    const victims = this.near.slice(0, n);
    let hits = 0;
    for (const v of victims) {
      if (!v.alive) continue;
      const dx = v.x - x;
      const dz = v.z - z;
      const d = Math.hypot(dx, dz);
      const k = 1 - Math.min(1, d / (radius + v.radius)) * 0.6;
      const len = d || 1;
      this.damageZombie(v, zombieDamage * k, { dirX: dx / len, dirZ: dz / len, knock: 10 * k, source, crit: false, hitX: v.x, hitZ: v.z, allowIncendiary: false });
      hits++;
    }
    const p = w.player;
    const pd = Math.hypot(p.x - x, p.z - z);
    if (playerDamage > 0 && pd < radius + p.radius) {
      const k = 1 - Math.min(1, pd / (radius + p.radius)) * 0.5;
      this.damagePlayer(playerDamage * k, x, z, 10 * k, source);
    }
    if (structureDamage > 0) w.structures.damageInRadius(x, z, radius, structureDamage, w);

    w.fx.explosion(x, z, radius);
    w.lighting.flashBlast(x, z, 60 + radius * 10);
    w.audio.sfx('explosion', { x, z });
    w.fx.shake(Math.max(0.1, 0.7 - pd / 30));
    return hits;
  }

  // -------------------------------------------------------------------- boss

  bossChargeHit(z: Zombie): void {
    this.damagePlayer(z.damage * 1.3, z.x, z.z, 20, 'boss');
    this.world.fx.shake(0.7);
  }

  bossChargeImpact(z: Zombie, collider: Collider): void {
    const w = this.world;
    if (z.stateTime < 0.12) return;
    if (w.structures.isStructureCollider(collider)) {
      w.structures.damage(collider.owner as Structure, 400, w);
      return;
    }
    z.setState('stunned');
    z.vx = z.vz = 0;
    w.fx.shake(0.6);
    w.fx.dust(z.x + z.chargeDirX * 1.5, z.z + z.chargeDirZ * 1.5, 16, 1);
    w.audio.sfx('slam', { x: z.x, z: z.z });
    w.events.emit('notify', { text: 'Boss stunned!', tone: 'info' });
  }

  bossSlam(z: Zombie): void {
    const w = this.world;
    const scale = z.damage / ZOMBIES.boss.damage;
    w.hazards.shockwave(z.x, z.z, BOSS.slamDamage * scale);
    if (z.enraged) w.hazards.shockwave(z.x, z.z, BOSS.slamDamage * scale, 0.45);
    const p = w.player;
    const d = Math.hypot(p.x - z.x, p.z - z.z);
    if (d < 3.4) this.damagePlayer(z.damage, z.x, z.z, 14, 'boss');
    w.structures.damageInRadius(z.x, z.z, 4, 200, w);
    w.fx.dust(z.x, z.z, 24, 1.5);
    w.fx.ring(z.x, z.z, 2, new THREE.Color('#ff8a3a'));
    w.fx.shake(0.75);
    w.audio.sfx('slam', { x: z.x, z: z.z });
  }

  bossSummon(z: Zombie): void {
    const w = this.world;
    const count = BOSS.summonCount + (z.enraged ? 2 : 0);
    for (let i = 0; i < count; i++) {
      const a = (i / count) * Math.PI * 2;
      const x = z.x + Math.cos(a) * 2.6;
      const zz = z.z + Math.sin(a) * 2.6;
      if (w.collision.overlapsCircle(x, zz, 0.4)) continue;
      w.waves.spawnExtra('runner', x, zz, w);
      w.fx.dust(x, zz, 6, 0.3);
    }
    w.fx.shake(0.3);
  }

  bossEnrage(z: Zombie): void {
    const w = this.world;
    w.audio.sfx('bossRoar', { x: z.x, z: z.z });
    w.fx.shake(0.6);
    w.fx.ring(z.x, z.z, 2.5, new THREE.Color('#ff3a2a'), 32);
    w.events.emit('notify', { text: 'THE ABOMINATION IS ENRAGED', tone: 'boss' });
  }
}
