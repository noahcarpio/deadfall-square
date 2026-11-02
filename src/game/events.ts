import type { WeaponId } from '../config/weapons';
import type { ZombieType } from '../config/zombies';
import type { Zombie } from '../zombies/Zombie';

export type PickupKind = 'ammo' | 'health' | 'armor' | 'weapon' | 'coins';

export type NotifyTone = 'good' | 'bad' | 'info' | 'boss';

/** All cross-system events. UI, audio and stats subscribe; gameplay emits. */
export interface GameEvents {
  zombieKilled: { zombie: Zombie; type: ZombieType; x: number; z: number; source: string; score: number; coins: number };
  playerDamaged: { amount: number; source: string };
  playerDied: { source: string };
  waveStarted: { wave: number; boss: boolean; total: number };
  waveCleared: { wave: number; bonus: number };
  bossSpawned: { zombie: Zombie };
  bossDefeated: { wave: number };
  pickupCollected: { kind: PickupKind; label: string };
  weaponAcquired: { weapon: WeaponId };
  notify: { text: string; tone: NotifyTone };
}
