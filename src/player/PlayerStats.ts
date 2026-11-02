import { UPGRADE_EFFECTS, type PlayerUpgradeId } from '../config/shop';
import type { PerkState } from '../progression/PerkState';

export const BASE_PLAYER = {
  maxHealth: 100,
  maxArmor: 50,
  speed: 5.2,
  sprintMultiplier: 1.55,
  maxStamina: 100,
  staminaDrain: 24,
  staminaRegen: 20,
  staminaRegenDelay: 0.8,
  rollCost: 24,
  rollDuration: 0.42,
  rollInvulnerable: 0.34,
  rollCooldown: 0.25,
  rollSpeedStart: 14,
  rollSpeedEnd: 5,
  radius: 0.45,
};

export interface PlayerStats {
  maxHealth: number;
  maxArmor: number;
  speed: number;
  maxStamina: number;
  staminaRegen: number;
  rollCost: number;
  /** Multiplier applied to incoming damage. */
  damageTaken: number;
  reloadSpeed: number;
  dropChance: number;
  magnetRadius: number;
}

export type PlayerUpgradeTiers = Record<PlayerUpgradeId, number>;

/** Derives effective player stats from shop upgrade tiers and perks. */
export function computePlayerStats(tiers: PlayerUpgradeTiers, perks: PerkState): PlayerStats {
  const stamina = 1 + UPGRADE_EFFECTS.staminaPerTier * tiers.stamina + (perks.has('marathon') ? 0.4 : 0);
  return {
    maxHealth: BASE_PLAYER.maxHealth + UPGRADE_EFFECTS.maxHealthPerTier * tiers.maxHealth,
    maxArmor: BASE_PLAYER.maxArmor + UPGRADE_EFFECTS.armorPerTier * tiers.armor,
    speed: BASE_PLAYER.speed * (1 + UPGRADE_EFFECTS.speedPerTier * tiers.speed),
    maxStamina: BASE_PLAYER.maxStamina * stamina,
    staminaRegen: BASE_PLAYER.staminaRegen * (1 + 0.25 * tiers.stamina + (perks.has('marathon') ? 0.3 : 0)),
    rollCost: BASE_PLAYER.rollCost * (perks.has('marathon') ? 0.7 : 1),
    damageTaken: Math.pow(0.88, perks.level('thickSkin')),
    reloadSpeed: 1 + 0.3 * perks.level('quickHands'),
    dropChance: 1 + 0.5 * perks.level('scavenger'),
    magnetRadius: 2.5 + 1.5 * perks.level('scavenger'),
  };
}

/**
 * Applies damage to armor first (armor absorbs 70% of each hit while it lasts),
 * then health. Returns the new health/armor values. Pure for unit testing.
 */
export function applyArmor(health: number, armor: number, damage: number): { health: number; armor: number } {
  if (damage <= 0) return { health, armor };
  const absorbed = Math.min(armor, damage * 0.7);
  return { health: health - (damage - absorbed), armor: armor - absorbed };
}
