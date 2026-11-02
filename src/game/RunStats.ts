import { ZOMBIE_TYPES, type ZombieType } from '../config/zombies';

/** Statistics for the game-over screen. */
export class RunStats {
  kills: Record<ZombieType, number> = emptyKills();
  shotsFired = 0;
  shotsHit = 0;
  damageDealt = 0;
  damageTaken = 0;
  timePlayed = 0;
  wavesCleared = 0;
  waveReached = 0;
  bossesKilled = 0;
  structuresBuilt = 0;
  pickupsCollected = 0;

  reset(): void {
    this.kills = emptyKills();
    this.shotsFired = 0;
    this.shotsHit = 0;
    this.damageDealt = 0;
    this.damageTaken = 0;
    this.timePlayed = 0;
    this.wavesCleared = 0;
    this.waveReached = 0;
    this.bossesKilled = 0;
    this.structuresBuilt = 0;
    this.pickupsCollected = 0;
  }

  get totalKills(): number {
    return ZOMBIE_TYPES.reduce((sum, t) => sum + this.kills[t], 0);
  }

  /** Fraction of bullets/pellets/grenades that damaged at least one zombie. */
  get accuracy(): number {
    return this.shotsFired > 0 ? Math.min(1, this.shotsHit / this.shotsFired) : 0;
  }
}

function emptyKills(): Record<ZombieType, number> {
  return { walker: 0, runner: 0, brute: 0, spitter: 0, exploder: 0, boss: 0 };
}
