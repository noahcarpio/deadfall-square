import { ZOMBIES, type ZombieDef, type ZombieType } from '../config/zombies';

export type ZombieState =
  | 'spawning'
  | 'chase'
  | 'windup'
  | 'recover'
  | 'ranged'
  | 'fuse'
  | 'chargeTelegraph'
  | 'charging'
  | 'slamTelegraph'
  | 'summon'
  | 'stunned'
  | 'dying';

export interface WaveScaling {
  hp: number;
  damage: number;
  speed: number;
}

/** A pooled zombie instance. Plain mutable data; behaviour lives in ZombieAI. */
export class Zombie {
  /** Stable pool slot (0..capacity), used for instanced rendering order. */
  readonly slot: number;
  active = false;
  def: ZombieDef = ZOMBIES.walker;
  type: ZombieType = 'walker';

  x = 0;
  z = 0;
  vx = 0;
  vz = 0;
  kx = 0;
  kz = 0;
  /** Smoothed steering direction. */
  dirX = 0;
  dirZ = 1;
  facing = 0;

  hp = 1;
  maxHp = 1;
  speed = 1;
  damage = 1;
  radius = 0.4;

  state: ZombieState = 'spawning';
  stateTime = 0;
  attackCooldown = 0;
  rangedCooldown = 0;
  /** Countdown until the next line-of-sight check (staggered across zombies). */
  losTimer = 0;
  hasLos = false;

  flash = 0;
  dissolve = 1;
  animPhase = 0;
  /** Per-zombie colour variation multiplier. */
  tint = 1;
  /** Movement speed variation multiplier. */
  speedVariance = 1;

  burnTime = 0;
  burnDps = 0;
  burnAccum = 0;
  flameCooldown = 0;

  deathT = 0;
  deathDirX = 0;
  deathDirZ = 1;
  /** Index into the alive list (maintained by ZombieManager). */
  listIndex = -1;

  /** Structure currently blocking this zombie's path (attacked if in the way). */
  blockedBy: unknown = null;
  /** Target of the current melee wind-up: 'player' or a structure. */
  attackTarget: unknown = null;

  // Boss-only state.
  chargeDirX = 0;
  chargeDirZ = 0;
  hitDuringCharge = false;
  bossCooldown = 0;
  summonCooldown = 0;
  enraged = false;
  /** Opaque handle for an active ground telegraph owned by this zombie. */
  telegraph: unknown = null;

  /** Progress watchdog: position at the last check and accumulated stuck time. */
  checkX = 0;
  checkZ = 0;
  checkTimer = 2;
  stuckTime = 0;

  /** Weapon / source that last damaged this zombie (for kill attribution). */
  lastHitBy = '';

  constructor(slot: number) {
    this.slot = slot;
  }

  init(type: ZombieType, x: number, z: number, scaling: WaveScaling, rand: () => number): void {
    const def = ZOMBIES[type];
    this.active = true;
    this.def = def;
    this.type = type;
    this.x = x;
    this.z = z;
    this.vx = this.vz = this.kx = this.kz = 0;
    this.dirX = 0;
    this.dirZ = 1;
    this.facing = 0;
    this.maxHp = def.hp * scaling.hp;
    this.hp = this.maxHp;
    this.speedVariance = 0.88 + rand() * 0.24;
    this.speed = def.speed * scaling.speed * this.speedVariance;
    this.damage = def.damage * scaling.damage;
    this.radius = def.radius;
    this.state = 'spawning';
    this.stateTime = 0;
    this.attackCooldown = 0.5;
    this.rangedCooldown = 1 + rand() * 1.5;
    this.losTimer = rand() * 0.3;
    this.hasLos = false;
    this.flash = 0;
    this.dissolve = 1;
    this.animPhase = rand() * Math.PI * 2;
    this.tint = 0.85 + rand() * 0.3;
    this.burnTime = 0;
    this.burnDps = 0;
    this.burnAccum = 0;
    this.flameCooldown = 0;
    this.deathT = 0;
    this.blockedBy = null;
    this.attackTarget = null;
    this.chargeDirX = this.chargeDirZ = 0;
    this.hitDuringCharge = false;
    this.bossCooldown = 3;
    this.summonCooldown = 8;
    this.enraged = false;
    this.telegraph = null;
    this.lastHitBy = '';
    this.checkX = x;
    this.checkZ = z;
    this.checkTimer = 2;
    this.stuckTime = 0;
  }

  get alive(): boolean {
    return this.active && this.state !== 'dying';
  }

  setState(state: ZombieState): void {
    this.state = state;
    this.stateTime = 0;
  }
}
