export type WeaponId = 'pistol' | 'shotgun' | 'smg' | 'rifle' | 'sniper' | 'flamer' | 'launcher';

export type WeaponKind = 'hitscan' | 'flame' | 'grenade';

export type GunSound = 'pistol' | 'shotgun' | 'smg' | 'rifle' | 'sniper' | 'flamer' | 'launcher';

export interface WeaponDef {
  id: WeaponId;
  name: string;
  slot: number;
  kind: WeaponKind;
  /** Damage per bullet / pellet / flame tick / grenade blast centre. */
  damage: number;
  pellets: number;
  /** Shots per second. */
  fireRate: number;
  /** Base cone half-angle in radians. */
  spread: number;
  /** Extra spread while moving (radians at full speed). */
  moveSpread: number;
  magSize: number;
  /** Max reserve ammo; Infinity for the pistol. */
  reserveMax: number;
  /** Reserve ammo granted when the weapon is first obtained. */
  startReserve: number;
  reloadTime: number;
  range: number;
  /** Additional zombies a bullet passes through. */
  pierce: number;
  /** Knockback impulse applied to zombies (m/s). */
  knockback: number;
  /** Screen-shake trauma added per shot. */
  shake: number;
  /** Price in the shop (0 = not sold). */
  price: number;
  /** Tracer / flash colour. */
  color: string;
  /** Blast radius for grenades. */
  blastRadius?: number;
  /** Projectile speed for flame / grenade weapons. */
  projectileSpeed?: number;
  sound: GunSound;
  description: string;
}

export const WEAPONS: Record<WeaponId, WeaponDef> = {
  pistol: {
    id: 'pistol', name: 'M9 Pistol', slot: 1, kind: 'hitscan',
    damage: 16, pellets: 1, fireRate: 4.5, spread: 0.025, moveSpread: 0.05,
    magSize: 12, reserveMax: Infinity, startReserve: Infinity, reloadTime: 1.05,
    range: 40, pierce: 0, knockback: 2.5, shake: 0.06, price: 0, color: '#ffd27a',
    sound: 'pistol', description: 'Reliable sidearm with infinite ammo.',
  },
  shotgun: {
    id: 'shotgun', name: 'Pump Shotgun', slot: 2, kind: 'hitscan',
    damage: 11, pellets: 8, fireRate: 1.15, spread: 0.2, moveSpread: 0.04,
    magSize: 6, reserveMax: 48, startReserve: 24, reloadTime: 2.1,
    range: 16, pierce: 0, knockback: 5, shake: 0.28, price: 260, color: '#ffbe6b',
    sound: 'shotgun', description: 'Devastating up close. Wide spread.',
  },
  smg: {
    id: 'smg', name: 'Vector SMG', slot: 3, kind: 'hitscan',
    damage: 9, pellets: 1, fireRate: 13, spread: 0.075, moveSpread: 0.06,
    magSize: 36, reserveMax: 288, startReserve: 144, reloadTime: 1.55,
    range: 30, pierce: 0, knockback: 1.2, shake: 0.045, price: 340, color: '#fff08a',
    sound: 'smg', description: 'Hoses down crowds. Chews through ammo.',
  },
  rifle: {
    id: 'rifle', name: 'AR-15 Rifle', slot: 4, kind: 'hitscan',
    damage: 19, pellets: 1, fireRate: 8.5, spread: 0.035, moveSpread: 0.05,
    magSize: 30, reserveMax: 240, startReserve: 120, reloadTime: 1.85,
    range: 45, pierce: 0, knockback: 2.2, shake: 0.07, price: 520, color: '#ffe08a',
    sound: 'rifle', description: 'Accurate, powerful, full-auto all-rounder.',
  },
  sniper: {
    id: 'sniper', name: 'Bolt Sniper', slot: 5, kind: 'hitscan',
    damage: 150, pellets: 1, fireRate: 0.95, spread: 0.002, moveSpread: 0.03,
    magSize: 5, reserveMax: 40, startReserve: 20, reloadTime: 2.5,
    range: 80, pierce: 5, knockback: 8, shake: 0.35, price: 640, color: '#bfe8ff',
    sound: 'sniper', description: 'One shot, many kills. Pierces through lines.',
  },
  flamer: {
    id: 'flamer', name: 'Flamethrower', slot: 6, kind: 'flame',
    damage: 6, pellets: 2, fireRate: 22, spread: 0.16, moveSpread: 0,
    magSize: 120, reserveMax: 480, startReserve: 240, reloadTime: 2.6,
    range: 8, pierce: 99, knockback: 0.4, shake: 0.03, price: 720, color: '#ff8a2a',
    projectileSpeed: 13, sound: 'flamer', description: 'Sets crowds ablaze. Burning damage over time.',
  },
  launcher: {
    id: 'launcher', name: 'Grenade Launcher', slot: 7, kind: 'grenade',
    damage: 110, pellets: 1, fireRate: 1.25, spread: 0.02, moveSpread: 0.02,
    magSize: 6, reserveMax: 36, startReserve: 18, reloadTime: 2.8,
    range: 26, pierce: 0, knockback: 12, shake: 0.2, price: 900, color: '#9ad36b',
    blastRadius: 4.2, projectileSpeed: 24, sound: 'launcher', description: 'Lobbed explosives. Huge area damage.',
  },
};

export const WEAPON_ORDER: readonly WeaponId[] = ['pistol', 'shotgun', 'smg', 'rifle', 'sniper', 'flamer', 'launcher'];

/** Upgrade tiers available per weapon in the shop. */
export const WEAPON_UPGRADE_LIMITS = { damage: 5, fireRate: 4, magazine: 3 } as const;
export type WeaponUpgradeKind = keyof typeof WEAPON_UPGRADE_LIMITS;

export interface WeaponUpgrades {
  damage: number;
  fireRate: number;
  magazine: number;
}

export function upgradedDamage(def: WeaponDef, u: WeaponUpgrades): number {
  return def.damage * (1 + 0.15 * u.damage);
}

export function upgradedFireRate(def: WeaponDef, u: WeaponUpgrades): number {
  return def.fireRate * (1 + 0.1 * u.fireRate);
}

export function upgradedMagSize(def: WeaponDef, u: WeaponUpgrades): number {
  return Math.round(def.magSize * (1 + 0.25 * u.magazine));
}
