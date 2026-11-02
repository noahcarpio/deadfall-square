import {
  WAVE, bossHpMultiplier, damageMultiplier, hpMultiplier, isBossWave, maxAlive,
  spawnGroupSize, spawnInterval, speedMultiplier, typeWeights, waveBudget, waveClearBonus,
} from '../config/waves';
import { ZOMBIES, type ZombieType } from '../config/zombies';
import type { Rng } from '../core/Rng';
import type { World } from '../game/World';
import type { WaveScaling, Zombie } from '../zombies/Zombie';

export type WavePhase = 'idle' | 'countdown' | 'active' | 'cleared';

/** Builds the (shuffled) list of zombie types for a wave from its spawn budget. */
export function buildComposition(wave: number, rng: Rng): ZombieType[] {
  let budget = waveBudget(wave);
  if (isBossWave(wave)) budget *= 0.6; // the boss takes the place of part of the horde
  const weights = typeWeights(wave);
  const out: ZombieType[] = [];
  // Guarantee at least one of each newly unlocked type so players meet them.
  for (const type of Object.keys(weights) as ZombieType[]) {
    if ((weights[type] ?? 0) > 0 && type !== 'walker' && budget >= ZOMBIES[type].cost) {
      out.push(type);
      budget -= ZOMBIES[type].cost;
    }
  }
  let guard = 0;
  while (budget > 0.5 && guard++ < 2000) {
    const type = rng.weighted(weights);
    const cost = ZOMBIES[type].cost;
    if (cost > budget + 0.5) {
      if (budget >= 1) {
        out.push('walker');
        budget -= 1;
        continue;
      }
      break;
    }
    out.push(type);
    budget -= cost;
  }
  return rng.shuffle(out);
}

export function scalingFor(wave: number): WaveScaling {
  return { hp: hpMultiplier(wave), damage: damageMultiplier(wave), speed: speedMultiplier(wave) };
}

/**
 * Runs the wave loop: countdown → spawning/fighting → cleared. Spawns zombies
 * in groups from alley entrances away from the player, respecting a
 * concurrent-alive cap, and spawns a boss every fifth wave.
 */
export class WaveDirector {
  wave = 0;
  phase: WavePhase = 'idle';
  timer = 0;
  queue: ZombieType[] = [];
  totalThisWave = 0;
  killedThisWave = 0;
  boss: Zombie | null = null;
  private bossPending = false;
  private spawnTimer = 0;
  /** Concurrent zombie cap from the quality preset. */
  aliveCap = 140;

  reset(): void {
    this.wave = 0;
    this.phase = 'idle';
    this.timer = 0;
    this.queue = [];
    this.totalThisWave = 0;
    this.killedThisWave = 0;
    this.boss = null;
    this.bossPending = false;
    this.spawnTimer = 0;
  }

  /** Zombies still to kill this wave (queued + alive). */
  remaining(world: World): number {
    return this.queue.length + world.zombies.aliveCount + (this.bossPending ? 1 : 0);
  }

  get nextWave(): number {
    return this.wave + 1;
  }

  beginCountdown(): void {
    this.phase = 'countdown';
    this.timer = WAVE.countdown;
  }

  private startWave(world: World): void {
    this.wave++;
    this.phase = 'active';
    this.queue = buildComposition(this.wave, world.rng);
    this.bossPending = isBossWave(this.wave);
    this.totalThisWave = this.queue.length + (this.bossPending ? 1 : 0);
    this.killedThisWave = 0;
    this.spawnTimer = 0.5;
    this.timer = 0;
    world.stats.waveReached = this.wave;
    world.events.emit('waveStarted', { wave: this.wave, boss: this.bossPending, total: this.totalThisWave });
  }

  onZombieKilled(z: Zombie): void {
    if (this.phase === 'active') this.killedThisWave++;
    if (z === this.boss) this.boss = null;
  }

  /** Spawns an additional zombie immediately (boss summons); counts toward the wave. */
  spawnExtra(type: ZombieType, x: number, z: number, world: World): Zombie | null {
    const zombie = world.zombies.spawn(type, x, z, scalingFor(Math.max(1, this.wave)), () => world.rng.next());
    if (zombie && this.phase === 'active') this.totalThisWave++;
    return zombie;
  }

  update(dt: number, world: World): void {
    switch (this.phase) {
      case 'countdown':
        this.timer -= dt;
        if (this.timer <= 0) this.startWave(world);
        break;
      case 'active':
        this.timer += dt;
        this.updateSpawning(dt, world);
        if (this.queue.length === 0 && !this.bossPending && world.zombies.aliveCount === 0) {
          this.phase = 'cleared';
          this.timer = WAVE.clearDelay;
          const bonus = waveClearBonus(this.wave);
          world.economy.addCoins(bonus);
          world.stats.wavesCleared = this.wave;
          world.events.emit('waveCleared', { wave: this.wave, bonus });
        }
        break;
      case 'cleared':
        this.timer -= dt;
        break;
      default:
        break;
    }
  }

  /** True once the post-wave banner has finished (Game then opens perk/shop screens). */
  get readyForIntermission(): boolean {
    return this.phase === 'cleared' && this.timer <= 0;
  }

  private updateSpawning(dt: number, world: World): void {
    if (this.bossPending && this.timer > 1.5) {
      this.bossPending = false;
      const sp = this.pickSpawn(world, 25);
      const boss = world.zombies.spawn('boss', sp.x, sp.z, scalingFor(this.wave), () => world.rng.next());
      if (boss) {
        boss.maxHp *= bossHpMultiplier(this.wave);
        boss.hp = boss.maxHp;
        this.boss = boss;
        world.events.emit('bossSpawned', { zombie: boss });
      }
    }
    if (this.queue.length === 0) return;
    this.spawnTimer -= dt;
    if (this.spawnTimer > 0) return;
    this.spawnTimer = spawnInterval(this.wave) * (0.7 + world.rng.next() * 0.6);
    const cap = maxAlive(this.wave, this.aliveCap);
    const group = Math.min(spawnGroupSize(this.wave), this.queue.length);
    const sp = this.pickSpawn(world, 18);
    const scaling = scalingFor(this.wave);
    for (let i = 0; i < group; i++) {
      if (world.zombies.aliveCount >= cap || world.zombies.capacityLeft === 0) break;
      const type = this.queue.pop() as ZombieType;
      // Spread the group across the alley width and depth.
      const side = (world.rng.next() - 0.5) * 2.4;
      const back = world.rng.next() * 2.5;
      const x = sp.x + -sp.dirZ * side - sp.dirX * back;
      const z = sp.z + sp.dirX * side - sp.dirZ * back;
      world.zombies.spawn(type, x, z, scaling, () => world.rng.next());
    }
  }

  /** Picks a spawn point, preferring ones at least `minDist` from the player. */
  private pickSpawn(world: World, minDist: number): { x: number; z: number; dirX: number; dirZ: number } {
    const points = world.arena.spawnPoints;
    const p = world.player;
    const far = points.filter((s) => Math.hypot(s.x - p.x, s.z - p.z) >= minDist);
    return world.rng.pick(far.length > 0 ? far : points);
  }
}
