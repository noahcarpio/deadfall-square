import {
  CONSUMABLES, PLAYER_UPGRADES, REPAIR_COST_PER_HP, STRUCTURES,
  playerUpgradeCost, weaponUpgradeCost, type PlayerUpgradeId, type StructureType,
} from '../config/shop';
import { WEAPONS, WEAPON_UPGRADE_LIMITS, type WeaponId, type WeaponUpgradeKind } from '../config/weapons';
import type { Arsenal } from '../weapons/Arsenal';
import type { Economy } from './Economy';

export type ShopAction =
  | { kind: 'weaponUpgrade'; weapon: WeaponId; upgrade: WeaponUpgradeKind }
  | { kind: 'buyWeapon'; weapon: WeaponId }
  | { kind: 'ammo'; weapon: WeaponId }
  | { kind: 'playerUpgrade'; id: PlayerUpgradeId }
  | { kind: 'heal' }
  | { kind: 'structure'; type: StructureType }
  | { kind: 'repair' };

export interface Offer {
  cost: number;
  available: boolean;
  /** Why the offer is unavailable (other than price), e.g. "MAX". */
  reason: string;
  tier: number;
  maxTier: number;
}

/** What the shop needs to know about (and do to) the current run. */
export interface ShopContext {
  readonly economy: Economy;
  readonly arsenal: Arsenal;
  readonly health: number;
  readonly maxHealth: number;
  readonly upgradeTiers: Readonly<Record<PlayerUpgradeId, number>>;
  structureCount(type: StructureType): number;
  readonly structuresMissingHp: number;
  applyPlayerUpgrade(id: PlayerUpgradeId): void;
  healFull(): void;
  repairStructures(): void;
}

/** Prices and availability for every shop action. Pure (unit tested). */
export function getOffer(ctx: ShopContext, a: ShopAction): Offer {
  switch (a.kind) {
    case 'weaponUpgrade': {
      const w = ctx.arsenal.get(a.weapon);
      const max = WEAPON_UPGRADE_LIMITS[a.upgrade];
      if (!w) return { cost: 0, available: false, reason: 'NOT OWNED', tier: 0, maxTier: max };
      const tier = w.upgrades[a.upgrade];
      if (tier >= max) return { cost: 0, available: false, reason: 'MAX', tier, maxTier: max };
      return { cost: weaponUpgradeCost(a.weapon, a.upgrade, tier), available: true, reason: '', tier, maxTier: max };
    }
    case 'buyWeapon': {
      if (ctx.arsenal.owns(a.weapon)) return { cost: 0, available: false, reason: 'OWNED', tier: 1, maxTier: 1 };
      return { cost: WEAPONS[a.weapon].price, available: true, reason: '', tier: 0, maxTier: 1 };
    }
    case 'ammo': {
      const w = ctx.arsenal.get(a.weapon);
      if (!w || !Number.isFinite(w.def.reserveMax)) return { cost: 0, available: false, reason: '—', tier: 0, maxTier: 0 };
      if (w.reserve >= w.def.reserveMax) return { cost: 0, available: false, reason: 'FULL', tier: 0, maxTier: 0 };
      const missing = 1 - w.reserve / w.def.reserveMax;
      const cost = Math.max(CONSUMABLES.ammoMinPrice, Math.round(WEAPONS[a.weapon].price * CONSUMABLES.ammoPriceFactor * missing));
      return { cost, available: true, reason: '', tier: 0, maxTier: 0 };
    }
    case 'playerUpgrade': {
      const def = PLAYER_UPGRADES[a.id];
      const tier = ctx.upgradeTiers[a.id];
      if (tier >= def.maxTier) return { cost: 0, available: false, reason: 'MAX', tier, maxTier: def.maxTier };
      return { cost: playerUpgradeCost(a.id, tier), available: true, reason: '', tier, maxTier: def.maxTier };
    }
    case 'heal': {
      const missing = ctx.maxHealth - ctx.health;
      if (missing < 1) return { cost: 0, available: false, reason: 'FULL', tier: 0, maxTier: 0 };
      return { cost: Math.round(CONSUMABLES.healBase + missing * CONSUMABLES.healPerHp), available: true, reason: '', tier: 0, maxTier: 0 };
    }
    case 'structure': {
      const def = STRUCTURES[a.type];
      const n = ctx.structureCount(a.type);
      if (n >= def.maxCount) return { cost: def.cost, available: false, reason: 'LIMIT', tier: n, maxTier: def.maxCount };
      return { cost: def.cost, available: true, reason: '', tier: n, maxTier: def.maxCount };
    }
    case 'repair': {
      const missing = ctx.structuresMissingHp;
      if (missing < 1) return { cost: 0, available: false, reason: 'NONE', tier: 0, maxTier: 0 };
      return { cost: Math.max(10, Math.round(missing * REPAIR_COST_PER_HP)), available: true, reason: '', tier: 0, maxTier: 0 };
    }
  }
}

/**
 * Attempts a purchase. Structures are not handled here: they are paid for at
 * placement time (so cancelling placement costs nothing).
 */
export function purchase(ctx: ShopContext, a: ShopAction): boolean {
  if (a.kind === 'structure') return false;
  const offer = getOffer(ctx, a);
  if (!offer.available || !ctx.economy.spend(offer.cost)) return false;
  switch (a.kind) {
    case 'weaponUpgrade': {
      const w = ctx.arsenal.get(a.weapon);
      if (!w) return false;
      const before = ctx.arsenal.magSize(a.weapon);
      w.upgrades[a.upgrade]++;
      // A bigger magazine is delivered full.
      if (a.upgrade === 'magazine') w.mag += ctx.arsenal.magSize(a.weapon) - before;
      return true;
    }
    case 'buyWeapon':
      ctx.arsenal.give(a.weapon);
      return true;
    case 'ammo':
      ctx.arsenal.refill(a.weapon);
      return true;
    case 'playerUpgrade':
      ctx.applyPlayerUpgrade(a.id);
      return true;
    case 'heal':
      ctx.healFull();
      return true;
    case 'repair':
      ctx.repairStructures();
      return true;
  }
}
