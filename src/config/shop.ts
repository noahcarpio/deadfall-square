import type { WeaponId, WeaponUpgradeKind } from './weapons';
import { WEAPONS } from './weapons';

export type PlayerUpgradeId = 'maxHealth' | 'speed' | 'armor' | 'stamina';

export interface PlayerUpgradeDef {
  id: PlayerUpgradeId;
  name: string;
  description: string;
  maxTier: number;
  baseCost: number;
  costGrowth: number;
}

export const PLAYER_UPGRADES: Record<PlayerUpgradeId, PlayerUpgradeDef> = {
  maxHealth: { id: 'maxHealth', name: 'Vitality', description: '+20 max health', maxTier: 5, baseCost: 110, costGrowth: 0.55 },
  armor: { id: 'armor', name: 'Kevlar Plating', description: '+25 max armor and refills armor', maxTier: 4, baseCost: 130, costGrowth: 0.5 },
  speed: { id: 'speed', name: 'Running Shoes', description: '+6% movement speed', maxTier: 4, baseCost: 140, costGrowth: 0.6 },
  stamina: { id: 'stamina', name: 'Endurance', description: '+25% stamina and regen', maxTier: 3, baseCost: 90, costGrowth: 0.6 },
};

export const UPGRADE_EFFECTS = {
  maxHealthPerTier: 20,
  armorPerTier: 25,
  speedPerTier: 0.06,
  staminaPerTier: 0.25,
} as const;

export function playerUpgradeCost(id: PlayerUpgradeId, tier: number): number {
  const def = PLAYER_UPGRADES[id];
  return Math.round(def.baseCost * (1 + def.costGrowth * tier));
}

/** Cost of a weapon upgrade tier; pricier weapons cost more to upgrade. */
export function weaponUpgradeCost(weapon: WeaponId, kind: WeaponUpgradeKind, tier: number): number {
  const base = kind === 'damage' ? 90 : kind === 'fireRate' ? 80 : 60;
  const weaponFactor = 1 + WEAPONS[weapon].price / 1200;
  return Math.round(base * weaponFactor * (1 + 0.6 * tier));
}

export const CONSUMABLES = {
  /** Heal to full: base + per missing HP. */
  healBase: 20,
  healPerHp: 0.9,
  /** Refill a weapon's reserve ammo: fraction of weapon price. */
  ammoPriceFactor: 0.22,
  ammoMinPrice: 35,
};

export type StructureType = 'barricade' | 'turret';

export interface StructureDef {
  type: StructureType;
  name: string;
  description: string;
  cost: number;
  maxCount: number;
  hp: number;
  /** Footprint in nav cells (width, depth) before rotation. */
  footprint: readonly [number, number];
}

export const STRUCTURES: Record<StructureType, StructureDef> = {
  barricade: {
    type: 'barricade', name: 'Barricade', description: 'Spiked wooden wall. Blocks and distracts zombies.',
    cost: 70, maxCount: 8, hp: 320, footprint: [3, 1],
  },
  turret: {
    type: 'turret', name: 'Auto-Turret', description: 'Shoots nearby zombies automatically.',
    cost: 320, maxCount: 3, hp: 260, footprint: [2, 2],
  },
};

export const TURRET = {
  range: 15,
  fireRate: 6,
  damage: 11,
  turnSpeed: 8,
};

/** Cost to fully repair all structures, per missing HP. */
export const REPAIR_COST_PER_HP = 0.12;
