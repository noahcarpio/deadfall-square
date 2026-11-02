import { BOSS, SPITTER } from '../config/zombies';
import { damp } from '../core/math';
import type { World } from '../game/World';
import type { Telegraph } from '../fx/Hazards';
import type { Zombie } from './Zombie';

export interface SteeringOutput {
  x: number;
  z: number;
  /** Explicit facing angle, or null to face the movement direction. */
  face: number | null;
}

const out: SteeringOutput = { x: 0, z: 0, face: null };
const flowDir = { x: 0, z: 0 };

/** Updates zombie.dirX/dirZ toward the current target; returns the straight-line distance. */
function steer(z: Zombie, world: World, dt: number): number {
  const tx = world.targetX;
  const tz = world.targetZ;
  const dx = tx - z.x;
  const dz = tz - z.z;
  const dist = Math.hypot(dx, dz) || 1e-4;

  z.losTimer -= dt;
  if (z.losTimer <= 0) {
    z.losTimer = 0.2 + (z.slot % 7) * 0.02;
    z.hasLos = dist < 16 && world.nav.lineOfSight(z.x, z.z, tx, tz, false);
  }

  let wx: number;
  let wz: number;
  if (z.hasLos || dist < 1.6) {
    wx = dx / dist;
    wz = dz / dist;
  } else if (world.flow.sample(z.x, z.z, flowDir)) {
    wx = flowDir.x;
    wz = flowDir.z;
  } else {
    wx = dx / dist;
    wz = dz / dist;
  }
  z.dirX = damp(z.dirX, wx, 10, dt);
  z.dirZ = damp(z.dirZ, wz, 10, dt);
  const len = Math.hypot(z.dirX, z.dirZ) || 1;
  z.dirX /= len;
  z.dirZ /= len;
  return dist;
}

function faceTarget(world: World, z: Zombie): number {
  return Math.atan2(world.targetX - z.x, world.targetZ - z.z);
}

function move(z: Zombie, factor: number): void {
  out.x = z.dirX * z.speed * factor;
  out.z = z.dirZ * z.speed * factor;
}

/** Starts a melee wind-up against the player or a blocking structure if possible. */
function tryMelee(z: Zombie, world: World, edge: number): boolean {
  if (z.attackCooldown > 0) return false;
  if (z.blockedBy) {
    z.attackTarget = z.blockedBy;
    z.setState('windup');
    return true;
  }
  if (world.targetIsPlayer && world.player.alive && edge < z.def.reach) {
    z.attackTarget = 'player';
    z.setState('windup');
    world.audio.sfx('zombieAttack', { x: z.x, z: z.z, volume: 0.6 });
    return true;
  }
  return false;
}

/** Handles the shared melee wind-up / recover states. Returns true if it consumed this step. */
function meleeStates(z: Zombie, world: World, edge: number): boolean {
  if (z.state === 'windup') {
    move(z, 0.12);
    if (z.attackTarget === 'player') out.face = faceTarget(world, z);
    if (z.stateTime >= z.def.windup) {
      if (z.attackTarget === 'player') {
        const angle = faceTarget(world, z);
        const facingDiff = Math.abs(Math.atan2(Math.sin(angle - z.facing), Math.cos(angle - z.facing)));
        if (edge < z.def.reach + 0.5 && facingDiff < 1.3) world.combat.zombieMeleePlayer(z);
      } else if (z.attackTarget) {
        world.combat.zombieMeleeStructure(z, z.attackTarget);
      }
      z.attackTarget = null;
      z.attackCooldown = z.def.attackCooldown;
      z.setState('recover');
    }
    return true;
  }
  if (z.state === 'recover') {
    move(z, 0.35);
    if (z.stateTime > 0.35) z.setState('chase');
    return true;
  }
  return false;
}

function updateWalker(z: Zombie, world: World, edge: number): void {
  if (meleeStates(z, world, edge)) return;
  if (z.state === 'chase' && tryMelee(z, world, edge)) return;
  move(z, 1);
}

function updateSpitter(z: Zombie, world: World, dist: number, edge: number): void {
  if (meleeStates(z, world, edge)) return;
  const p = world.player;
  if (z.state === 'ranged') {
    out.face = faceTarget(world, z);
    if (z.stateTime >= z.def.windup) {
      // Lead the target a little so standing still is never safe.
      const flight = dist / SPITTER.projectileSpeed;
      const tx = p.x + p.vx * flight * 0.6;
      const tz = p.z + p.vz * flight * 0.6;
      world.hazards.spitAcid(z.x, z.z, tx, tz, z.damage);
      world.audio.sfx('spit', { x: z.x, z: z.z });
      z.rangedCooldown = z.def.attackCooldown * (0.8 + world.rng.next() * 0.4);
      z.setState('recover');
    }
    return;
  }
  if (z.state !== 'chase') {
    move(z, 1);
    return;
  }
  if (tryMelee(z, world, edge)) return;
  const canSpit = world.targetIsPlayer && p.alive && z.hasLos;
  if (canSpit && dist <= SPITTER.preferredMax && z.rangedCooldown <= 0) {
    z.setState('ranged');
    return;
  }
  if (canSpit && dist < SPITTER.preferredMin) {
    move(z, -0.75); // back away
    out.face = faceTarget(world, z);
  } else if (canSpit && dist <= SPITTER.preferredMax) {
    // Strafe sideways while waiting to spit again.
    const side = z.slot % 2 === 0 ? 1 : -1;
    out.x = -z.dirZ * side * z.speed * 0.55;
    out.z = z.dirX * side * z.speed * 0.55;
    out.face = faceTarget(world, z);
  } else {
    move(z, 1);
  }
}

function updateExploder(z: Zombie, world: World, edge: number): void {
  if (z.state === 'fuse') {
    move(z, 0.55);
    if (z.stateTime >= z.def.windup) world.combat.detonate(z);
    return;
  }
  if (z.state !== 'chase') {
    move(z, 1);
    return;
  }
  const nearPlayer = world.targetIsPlayer && world.player.alive && edge < 1.5;
  if (nearPlayer || z.blockedBy) {
    z.setState('fuse');
    world.audio.sfx('fuse', { x: z.x, z: z.z });
    return;
  }
  move(z, 1);
}

function telegraphOf(z: Zombie): Telegraph | null {
  return (z.telegraph as Telegraph | null) ?? null;
}

function updateBoss(z: Zombie, world: World, dt: number, dist: number, edge: number): void {
  const p = world.player;
  z.bossCooldown -= dt;
  z.summonCooldown -= dt;
  if (!z.enraged && z.hp < z.maxHp * BOSS.enrageThreshold) {
    z.enraged = true;
    z.speed *= 1.2;
    world.combat.bossEnrage(z);
  }
  const rate = z.enraged ? 1.35 : 1;

  switch (z.state) {
    case 'chargeTelegraph': {
      out.face = Math.atan2(z.chargeDirX, z.chargeDirZ);
      // Track the player for most of the telegraph, then lock the direction.
      if (z.stateTime < BOSS.chargeTelegraph * 0.7 / rate) {
        const dx = p.x - z.x;
        const dz = p.z - z.z;
        const len = Math.hypot(dx, dz) || 1;
        z.chargeDirX = dx / len;
        z.chargeDirZ = dz / len;
      }
      const t = telegraphOf(z);
      if (t) {
        t.x = z.x;
        t.z = z.z;
        t.dirX = z.chargeDirX;
        t.dirZ = z.chargeDirZ;
        t.progress = Math.min(1, z.stateTime / (BOSS.chargeTelegraph / rate));
      }
      if (z.stateTime >= BOSS.chargeTelegraph / rate) {
        world.hazards.releaseTelegraph(t);
        z.telegraph = null;
        z.hitDuringCharge = false;
        z.setState('charging');
        world.audio.sfx('bossRoar', { x: z.x, z: z.z, volume: 0.8 });
      }
      return;
    }
    case 'charging': {
      out.x = z.chargeDirX * BOSS.chargeSpeed * rate;
      out.z = z.chargeDirZ * BOSS.chargeSpeed * rate;
      out.face = Math.atan2(z.chargeDirX, z.chargeDirZ);
      if (!z.hitDuringCharge && p.alive && edge < 0.6) {
        z.hitDuringCharge = true;
        world.combat.bossChargeHit(z);
      }
      if (z.stateTime >= BOSS.chargeDuration) {
        z.bossCooldown = 2.6 / rate;
        z.setState('recover');
      }
      return;
    }
    case 'stunned':
      if (z.stateTime >= 1.3) {
        z.bossCooldown = 1.2;
        z.setState('chase');
      }
      return;
    case 'slamTelegraph': {
      out.face = faceTarget(world, z);
      const t = telegraphOf(z);
      if (t) {
        t.x = z.x;
        t.z = z.z;
        t.progress = Math.min(1, z.stateTime / (BOSS.slamTelegraph / rate));
      }
      if (z.stateTime >= BOSS.slamTelegraph / rate) {
        world.hazards.releaseTelegraph(t);
        z.telegraph = null;
        world.combat.bossSlam(z);
        z.bossCooldown = 2.8 / rate;
        z.setState('recover');
      }
      return;
    }
    case 'summon':
      out.face = faceTarget(world, z);
      if (z.stateTime >= 1.0) {
        world.combat.bossSummon(z);
        z.summonCooldown = 14;
        z.bossCooldown = 2.2 / rate;
        z.setState('recover');
      }
      return;
    default:
      break;
  }

  if (meleeStates(z, world, edge)) return;
  if (z.state !== 'chase') {
    move(z, 1);
    return;
  }
  if (tryMelee(z, world, edge)) return;
  move(z, 1);

  if (z.bossCooldown > 0 || !world.targetIsPlayer || !p.alive) return;
  const roll = world.rng.next();
  if (z.summonCooldown <= 0 && roll < 0.3) {
    z.setState('summon');
    world.audio.sfx('bossRoar', { x: z.x, z: z.z });
  } else if (dist < 8.5) {
    z.setState('slamTelegraph');
    z.telegraph = world.hazards.telegraphCircle(z.x, z.z, 3.2);
  } else if (z.hasLos) {
    const dx = p.x - z.x;
    const dz = p.z - z.z;
    const len = Math.hypot(dx, dz) || 1;
    z.chargeDirX = dx / len;
    z.chargeDirZ = dz / len;
    z.setState('chargeTelegraph');
    z.telegraph = world.hazards.telegraphLine(z.x, z.z, z.chargeDirX, z.chargeDirZ, 20, z.radius * 2);
  } else {
    z.bossCooldown = 0.5;
  }
}

/** Runs one zombie's decision-making for this step and returns its desired velocity. */
export function updateZombieAI(z: Zombie, dt: number, world: World): SteeringOutput {
  out.x = 0;
  out.z = 0;
  out.face = null;
  const dist = steer(z, world, dt);

  if (z.state === 'spawning') {
    move(z, 0.6);
    return out;
  }
  if (z.state === 'stunned' && z.type !== 'boss') {
    if (z.stateTime > 0.6) z.setState('chase');
    return out;
  }

  const edge = dist - z.radius - world.player.radius;
  switch (z.type) {
    case 'spitter':
      updateSpitter(z, world, dist, edge);
      break;
    case 'exploder':
      updateExploder(z, world, edge);
      break;
    case 'boss':
      updateBoss(z, world, dt, dist, edge);
      break;
    default:
      updateWalker(z, world, edge);
      break;
  }
  return out;
}
