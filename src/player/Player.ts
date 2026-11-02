import { angleDamp, damp } from '../core/math';
import type { CollisionWorld, Collider } from '../world/Collision';
import { BASE_PLAYER, type PlayerStats } from './PlayerStats';

/** What the player wants to do this simulation step (from keyboard/mouse or touch). */
export interface PlayerIntent {
  moveX: number;
  moveZ: number;
  sprint: boolean;
  /** Normalised aim direction on the ground plane. */
  aimX: number;
  aimZ: number;
  /** Distance to the aim point (used to target grenades). */
  aimDistance: number;
  fire: boolean;
  reload: boolean;
  roll: boolean;
  /** Weapon slot (1-7) requested this step, or 0. */
  slot: number;
  /** -1 / +1 to cycle weapons, or 0. */
  cycle: number;
}

export function emptyIntent(): PlayerIntent {
  return { moveX: 0, moveZ: 0, sprint: false, aimX: 0, aimZ: -1, aimDistance: 10, fire: false, reload: false, roll: false, slot: 0, cycle: 0 };
}

/** Player movement, stamina, dodge roll and vitals. */
export class Player {
  x = 0;
  z = 8;
  vx = 0;
  vz = 0;
  /** Knockback velocity, decays quickly. */
  kx = 0;
  kz = 0;
  facing = Math.PI;
  aimX = 0;
  aimZ = -1;
  /** Distance from the player to the aim point (grenade targeting). */
  aimDistance = 10;
  readonly radius = BASE_PLAYER.radius;

  health = BASE_PLAYER.maxHealth;
  armor = 0;
  stamina = BASE_PLAYER.maxStamina;
  alive = true;
  deathTime = 0;

  sprinting = false;
  /** Set when stamina hits zero; sprinting is disabled until it recovers. */
  exhausted = false;
  rolling = false;
  rollTime = 0;
  private rollDirX = 0;
  private rollDirZ = 0;
  private rollCooldown = 0;
  private staminaDelay = 0;
  /** Remaining invulnerability seconds (roll i-frames, second wind). */
  invulnerable = 0;
  /** 0..1 red flash after taking damage. */
  hurtFlash = 0;
  /** Seconds of adrenaline speed boost remaining. */
  speedBoost = 0;
  /** Movement speed 0..1 relative to sprint speed, for animation. */
  speed01 = 0;
  /** Dot product between move direction and facing (negative when backpedalling). */
  moveDot = 0;

  stats: PlayerStats;

  constructor(stats: PlayerStats) {
    this.stats = stats;
    this.reset(stats);
  }

  reset(stats: PlayerStats): void {
    this.stats = stats;
    this.x = 0;
    this.z = 8;
    this.vx = this.vz = this.kx = this.kz = 0;
    this.facing = Math.PI;
    this.aimX = 0;
    this.aimZ = -1;
    this.health = stats.maxHealth;
    this.armor = stats.maxArmor;
    this.stamina = stats.maxStamina;
    this.alive = true;
    this.deathTime = 0;
    this.sprinting = false;
    this.exhausted = false;
    this.rolling = false;
    this.rollTime = 0;
    this.rollCooldown = 0;
    this.staminaDelay = 0;
    this.invulnerable = 0;
    this.hurtFlash = 0;
    this.speedBoost = 0;
  }

  /** Re-applies stats after an upgrade, keeping current values proportionally sane. */
  applyStats(stats: PlayerStats): void {
    const healthGain = Math.max(0, stats.maxHealth - this.stats.maxHealth);
    this.stats = stats;
    this.health = Math.min(stats.maxHealth, this.health + healthGain);
    this.armor = Math.min(stats.maxArmor, this.armor);
    this.stamina = Math.min(stats.maxStamina, this.stamina);
  }

  /** 0..1 progress through the current roll. */
  get rollProgress(): number {
    return this.rolling ? this.rollTime / BASE_PLAYER.rollDuration : 0;
  }

  get canAct(): boolean {
    return this.alive && !this.rolling;
  }

  /** Returns true if a roll started this step. */
  update(dt: number, intent: PlayerIntent, collision: CollisionWorld): { rolled: boolean; blockedBy: Collider | null } {
    let rolled = false;
    this.invulnerable = Math.max(0, this.invulnerable - dt);
    this.hurtFlash = Math.max(0, this.hurtFlash - dt * 4);
    this.rollCooldown = Math.max(0, this.rollCooldown - dt);
    this.speedBoost = Math.max(0, this.speedBoost - dt);

    if (!this.alive) {
      this.deathTime += dt;
      this.kx = damp(this.kx, 0, 6, dt);
      this.kz = damp(this.kz, 0, 6, dt);
      this.x += this.kx * dt;
      this.z += this.kz * dt;
      collision.resolveCircle(this, this.radius);
      return { rolled, blockedBy: null };
    }

    let mx = intent.moveX;
    let mz = intent.moveZ;
    const mlen = Math.hypot(mx, mz);
    if (mlen > 1) {
      mx /= mlen;
      mz /= mlen;
    }
    const moving = mlen > 0.1;

    if (Math.hypot(intent.aimX, intent.aimZ) > 0.01) {
      this.aimX = intent.aimX;
      this.aimZ = intent.aimZ;
    }
    this.aimDistance = intent.aimDistance;

    // Dodge roll.
    if (intent.roll && !this.rolling && this.rollCooldown <= 0 && this.stamina >= this.stats.rollCost) {
      this.rolling = true;
      this.rollTime = 0;
      const dirLen = moving ? Math.hypot(mx, mz) : 0;
      this.rollDirX = moving ? mx / dirLen : this.aimX;
      this.rollDirZ = moving ? mz / dirLen : this.aimZ;
      this.stamina -= this.stats.rollCost;
      this.staminaDelay = BASE_PLAYER.staminaRegenDelay;
      this.invulnerable = Math.max(this.invulnerable, BASE_PLAYER.rollInvulnerable);
      rolled = true;
    }

    let targetVx: number;
    let targetVz: number;
    if (this.rolling) {
      this.rollTime += dt;
      const t = Math.min(1, this.rollTime / BASE_PLAYER.rollDuration);
      const speed = BASE_PLAYER.rollSpeedStart + (BASE_PLAYER.rollSpeedEnd - BASE_PLAYER.rollSpeedStart) * t;
      this.vx = this.rollDirX * speed;
      this.vz = this.rollDirZ * speed;
      targetVx = this.vx;
      targetVz = this.vz;
      this.sprinting = false;
      if (this.rollTime >= BASE_PLAYER.rollDuration) {
        this.rolling = false;
        this.rollCooldown = BASE_PLAYER.rollCooldown;
      }
    } else {
      // Stamina & sprint.
      const wantSprint = intent.sprint && moving && !this.exhausted;
      this.sprinting = wantSprint && this.stamina > 0;
      if (this.sprinting) {
        this.stamina = Math.max(0, this.stamina - BASE_PLAYER.staminaDrain * dt);
        this.staminaDelay = BASE_PLAYER.staminaRegenDelay;
        if (this.stamina <= 0) this.exhausted = true;
      }
      const boost = this.speedBoost > 0 ? 1.2 : 1;
      const speed = this.stats.speed * boost * (this.sprinting ? BASE_PLAYER.sprintMultiplier : 1);
      targetVx = mx * speed;
      targetVz = mz * speed;
      this.vx = damp(this.vx, targetVx, 14, dt);
      this.vz = damp(this.vz, targetVz, 14, dt);
    }

    if (!this.sprinting && !this.rolling) {
      this.staminaDelay = Math.max(0, this.staminaDelay - dt);
      if (this.staminaDelay <= 0) {
        this.stamina = Math.min(this.stats.maxStamina, this.stamina + this.stats.staminaRegen * dt);
      }
    }
    if (this.exhausted && this.stamina >= this.stats.maxStamina * 0.3) this.exhausted = false;

    this.kx = damp(this.kx, 0, 6, dt);
    this.kz = damp(this.kz, 0, 6, dt);
    this.x += (this.vx + this.kx) * dt;
    this.z += (this.vz + this.kz) * dt;
    const blockedBy = collision.resolveCircle(this, this.radius);

    const aimAngle = Math.atan2(this.aimX, this.aimZ);
    const faceTarget = this.rolling ? Math.atan2(this.rollDirX, this.rollDirZ) : aimAngle;
    this.facing = angleDamp(this.facing, faceTarget, this.rolling ? 30 : 28, dt);

    const sp = Math.hypot(this.vx, this.vz);
    this.speed01 = Math.min(1, sp / (this.stats.speed * BASE_PLAYER.sprintMultiplier));
    this.moveDot = sp > 0.1 ? (this.vx * Math.sin(this.facing) + this.vz * Math.cos(this.facing)) / sp : 0;
    return { rolled, blockedBy };
  }

  /** Adds a knockback impulse (m/s). */
  knock(dirX: number, dirZ: number, strength: number): void {
    this.kx += dirX * strength;
    this.kz += dirZ * strength;
  }

  heal(amount: number): number {
    const before = this.health;
    this.health = Math.min(this.stats.maxHealth, this.health + amount);
    return this.health - before;
  }

  addArmor(amount: number): number {
    const before = this.armor;
    this.armor = Math.min(this.stats.maxArmor, this.armor + amount);
    return this.armor - before;
  }
}
