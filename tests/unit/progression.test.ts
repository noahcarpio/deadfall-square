import { describe, expect, it } from 'vitest';
import { WEAPONS } from '../../src/config/weapons';
import { Rng } from '../../src/core/Rng';
import { applyArmor, computePlayerStats } from '../../src/player/PlayerStats';
import { Economy } from '../../src/progression/Economy';
import { insertScore, qualifies, sanitizeName, type HighScoreEntry } from '../../src/progression/HighScores';
import { PerkState } from '../../src/progression/PerkState';
import { getOffer, purchase, type ShopContext } from '../../src/progression/Shop';
import { sanitizeSettings } from '../../src/core/Settings';
import { Arsenal } from '../../src/weapons/Arsenal';
import type { PlayerUpgradeId } from '../../src/config/shop';

describe('Economy', () => {
  it('builds a combo multiplier and resets it after the window', () => {
    const e = new Economy();
    for (let i = 0; i < 10; i++) e.registerKill(10, 1);
    expect(e.multiplier).toBe(2);
    expect(e.bestCombo).toBe(10);
    e.update(e.comboWindow + 0.01);
    expect(e.comboCount).toBe(0);
    expect(e.multiplier).toBe(1);
  });

  it('caps the multiplier at 5x', () => {
    const e = new Economy();
    for (let i = 0; i < 200; i++) e.registerKill(1, 1);
    expect(e.multiplier).toBe(5);
  });

  it('never spends more than it has', () => {
    const e = new Economy();
    e.addCoins(50);
    expect(e.spend(60)).toBe(false);
    expect(e.spend(50)).toBe(true);
    expect(e.coins).toBe(0);
  });
});

describe('Arsenal', () => {
  it('fires at the weapon fire rate and auto-reloads', () => {
    const a = new Arsenal();
    a.reset();
    let shots = 0;
    const dt = 1 / 60;
    for (let i = 0; i < 60; i++) shots += a.update(dt, true, true).shots;
    // 4.5 shots/s for the pistol, minus nothing (12-round mag not exhausted in 1s).
    expect(shots).toBeGreaterThanOrEqual(4);
    expect(shots).toBeLessThanOrEqual(5);
    for (let i = 0; i < 300; i++) a.update(dt, true, true);
    expect(a.current.mag).toBeGreaterThan(0); // infinite pistol reserve keeps reloading
  });

  it('reload moves ammo from reserve', () => {
    const a = new Arsenal();
    a.reset();
    a.give('shotgun');
    a.switchTo('shotgun');
    const w = a.current;
    w.mag = 1;
    const reserve = w.reserve;
    expect(a.startReload()).toBe(true);
    for (let i = 0; i < 200; i++) a.update(1 / 60, false, true);
    expect(w.mag).toBe(WEAPONS.shotgun.magSize);
    expect(w.reserve).toBe(reserve - (WEAPONS.shotgun.magSize - 1));
  });

  it('giving an owned weapon grants ammo instead', () => {
    const a = new Arsenal();
    a.reset();
    expect(a.give('smg')).toBe('new');
    const w = a.get('smg');
    if (!w) throw new Error('missing');
    w.reserve = 0;
    expect(a.give('smg')).toBe('ammo');
    expect(w.reserve).toBeGreaterThan(0);
  });

  it('cycles through owned weapons in slot order', () => {
    const a = new Arsenal();
    a.reset();
    a.give('sniper');
    a.give('shotgun');
    a.cycle(1);
    expect(a.currentId).toBe('shotgun');
    a.cycle(1);
    expect(a.currentId).toBe('sniper');
    a.cycle(1);
    expect(a.currentId).toBe('pistol');
  });
});

describe('PerkState', () => {
  it('offers distinct perks and respects max stacks', () => {
    const p = new PerkState();
    const choices = p.rollChoices(new Rng(5), 3);
    expect(new Set(choices).size).toBe(3);
    p.add('adrenaline');
    expect(p.canTake('adrenaline')).toBe(false);
    expect(() => p.add('adrenaline')).toThrow();
    for (let i = 0; i < 50; i++) expect(p.rollChoices(new Rng(i), 3)).not.toContain('adrenaline');
  });
});

describe('Player stats', () => {
  it('armor absorbs 70% of damage until depleted', () => {
    expect(applyArmor(100, 50, 10)).toEqual({ health: 97, armor: 43 });
    const r = applyArmor(100, 5, 20);
    expect(r.armor).toBe(0);
    expect(r.health).toBe(85);
  });

  it('upgrades and perks change derived stats', () => {
    const perks = new PerkState();
    const base = computePlayerStats({ maxHealth: 0, speed: 0, armor: 0, stamina: 0 }, perks);
    perks.add('thickSkin');
    perks.add('quickHands');
    const up = computePlayerStats({ maxHealth: 2, speed: 1, armor: 1, stamina: 0 }, perks);
    expect(up.maxHealth).toBe(base.maxHealth + 40);
    expect(up.speed).toBeGreaterThan(base.speed);
    expect(up.maxArmor).toBe(base.maxArmor + 25);
    expect(up.damageTaken).toBeLessThan(1);
    expect(up.reloadSpeed).toBeGreaterThan(1);
  });
});

function fakeShop(coins: number): ShopContext & { tiers: Record<PlayerUpgradeId, number>; healed: boolean } {
  const economy = new Economy();
  economy.addCoins(coins);
  const arsenal = new Arsenal();
  arsenal.reset();
  const tiers: Record<PlayerUpgradeId, number> = { maxHealth: 0, speed: 0, armor: 0, stamina: 0 };
  const ctx = {
    economy,
    arsenal,
    health: 40,
    maxHealth: 100,
    upgradeTiers: tiers,
    tiers,
    healed: false,
    structureCount: () => 0,
    structuresMissingHp: 0,
    applyPlayerUpgrade: (id: PlayerUpgradeId) => {
      tiers[id]++;
    },
    healFull: () => {
      ctx.healed = true;
    },
    repairStructures: () => undefined,
  };
  return ctx;
}

describe('Shop', () => {
  it('buys weapons and refuses when broke', () => {
    const ctx = fakeShop(300);
    expect(purchase(ctx, { kind: 'buyWeapon', weapon: 'smg' })).toBe(false); // 340
    expect(purchase(ctx, { kind: 'buyWeapon', weapon: 'shotgun' })).toBe(true); // 260
    expect(ctx.arsenal.owns('shotgun')).toBe(true);
    expect(ctx.economy.coins).toBe(40);
    expect(getOffer(ctx, { kind: 'buyWeapon', weapon: 'shotgun' }).reason).toBe('OWNED');
  });

  it('weapon upgrades escalate in price and cap out', () => {
    const ctx = fakeShop(100000);
    const action = { kind: 'weaponUpgrade', weapon: 'pistol', upgrade: 'magazine' } as const;
    const first = getOffer(ctx, action).cost;
    expect(purchase(ctx, action)).toBe(true);
    expect(getOffer(ctx, action).cost).toBeGreaterThan(first);
    expect(ctx.arsenal.current.mag).toBe(15); // bigger magazine delivered full
    purchase(ctx, action);
    purchase(ctx, action);
    expect(getOffer(ctx, action)).toMatchObject({ available: false, reason: 'MAX' });
    expect(purchase(ctx, action)).toBe(false);
  });

  it('heals and applies player upgrades', () => {
    const ctx = fakeShop(1000);
    expect(purchase(ctx, { kind: 'heal' })).toBe(true);
    expect(ctx.healed).toBe(true);
    expect(purchase(ctx, { kind: 'playerUpgrade', id: 'speed' })).toBe(true);
    expect(ctx.tiers.speed).toBe(1);
  });

  it('structures are paid at placement, not in purchase()', () => {
    const ctx = fakeShop(1000);
    expect(purchase(ctx, { kind: 'structure', type: 'barricade' })).toBe(false);
    expect(ctx.economy.coins).toBe(1000);
  });
});

describe('HighScores', () => {
  const entry = (score: number, date = '2026-01-01'): HighScoreEntry => ({ name: 'x', score, wave: 1, kills: 1, date });

  it('keeps the top 10 sorted', () => {
    let list: HighScoreEntry[] = [];
    for (let i = 1; i <= 12; i++) list = insertScore(list, entry(i * 100)).list;
    expect(list).toHaveLength(10);
    expect(list[0]?.score).toBe(1200);
    expect(list[9]?.score).toBe(300);
  });

  it('reports rank, or -1 when not placed', () => {
    let list: HighScoreEntry[] = [];
    for (let i = 1; i <= 10; i++) list = insertScore(list, entry(i * 100)).list;
    expect(insertScore(list, entry(550)).rank).toBe(5);
    expect(insertScore(list, entry(50)).rank).toBe(-1);
    expect(qualifies(list, 50)).toBe(false);
    expect(qualifies(list, 150)).toBe(true);
  });

  it('sanitizes names', () => {
    expect(sanitizeName('  <script>alert(1)</script>  ')).toBe('scriptalert1sc');
    expect(sanitizeName('')).toBe('Survivor');
  });
});

describe('Settings', () => {
  it('sanitizes stored values', () => {
    const s = sanitizeSettings({ masterVolume: 7, quality: 'ultra' as never, showFps: 'yes' as never, sensitivity: Number.NaN });
    expect(s.masterVolume).toBe(1);
    expect(['low', 'medium', 'high']).toContain(s.quality);
    expect(typeof s.showFps).toBe('boolean');
    expect(s.sensitivity).toBe(1);
  });
});
