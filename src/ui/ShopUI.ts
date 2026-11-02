import { PLAYER_UPGRADES, STRUCTURES, type PlayerUpgradeId, type StructureType } from '../config/shop';
import { WEAPONS, WEAPON_ORDER, upgradedDamage, upgradedFireRate, upgradedMagSize, type WeaponId, type WeaponUpgradeKind } from '../config/weapons';
import { getOffer, type Offer, type ShopAction, type ShopContext } from '../progression/Shop';
import { clear, h } from './dom';

export interface ShopActions {
  buy(action: ShopAction): boolean;
  place(type: StructureType): void;
  startWave(): void;
  uiSound(kind: 'click' | 'hover' | 'deny'): void;
}

type Tab = 'weapons' | 'survivor' | 'defenses';

const UPGRADE_LABELS: Record<WeaponUpgradeKind, string> = { damage: 'Damage', fireRate: 'Fire rate', magazine: 'Magazine' };

/** Between-wave shop: weapon upgrades & purchases, survivor upgrades, defenses. */
export class ShopUI {
  readonly root: HTMLElement;
  private readonly coins = h('span', { class: 'shop-coins' });
  private readonly title = h('h2', { text: 'SUPPLY DEPOT' });
  private readonly body = h('div', { class: 'shop-body' });
  private readonly tabs = new Map<Tab, HTMLButtonElement>();
  private readonly startBtn: HTMLButtonElement;
  private tab: Tab = 'weapons';

  constructor(private readonly ctx: () => ShopContext, private readonly actions: ShopActions) {
    const tabRow = h('div', { class: 'tabs' });
    for (const [t, label] of [['weapons', 'WEAPONS'], ['survivor', 'SURVIVOR'], ['defenses', 'DEFENSES']] as const) {
      const b = h('button', { class: 'tab', text: label });
      b.addEventListener('click', () => {
        actions.uiSound('click');
        this.tab = t;
        this.render();
      });
      this.tabs.set(t, b);
      tabRow.append(b);
    }
    this.startBtn = h('button', { class: 'btn primary start-wave', text: 'START NEXT WAVE' });
    this.startBtn.addEventListener('click', () => {
      actions.uiSound('click');
      actions.startWave();
    });
    this.root = h('div', { class: 'screen shop modal hidden' }, [
      h('div', { class: 'panel-box shop-box' }, [
        h('div', { class: 'shop-header' }, [this.title, h('div', { class: 'coin-pill' }, [h('span', { class: 'coin-icon' }), this.coins])]),
        tabRow,
        this.body,
        h('div', { class: 'shop-footer' }, [h('div', { class: 'hint', text: 'Tip: barricades and turrets persist between waves.' }), this.startBtn]),
      ]),
    ]);
  }

  open(clearedWave: number): void {
    this.title.textContent = `WAVE ${clearedWave} CLEARED — SUPPLY DEPOT`;
    this.startBtn.textContent = `START WAVE ${clearedWave + 1}`;
    this.render();
    this.root.classList.remove('hidden');
  }

  hide(): void {
    this.root.classList.add('hidden');
  }

  get visible(): boolean {
    return !this.root.classList.contains('hidden');
  }

  render(): void {
    const c = this.ctx();
    this.coins.textContent = c.economy.coins.toLocaleString();
    for (const [t, b] of this.tabs) b.classList.toggle('active', t === this.tab);
    clear(this.body);
    if (this.tab === 'weapons') this.renderWeapons(c);
    else if (this.tab === 'survivor') this.renderSurvivor(c);
    else this.renderDefenses(c);
  }

  private buyButton(c: ShopContext, offer: Offer, label: string, action: ShopAction | (() => void)): HTMLButtonElement {
    const affordable = c.economy.coins >= offer.cost;
    const text = offer.available ? `${label} · ${offer.cost}` : offer.reason;
    const b = h('button', { class: `buy ${offer.available && affordable ? '' : 'disabled'}`, text });
    if (!offer.available) b.disabled = true;
    b.addEventListener('click', () => {
      if (!offer.available) return;
      if (!affordable) {
        this.actions.uiSound('deny');
        b.classList.add('shake');
        window.setTimeout(() => b.classList.remove('shake'), 350);
        return;
      }
      if (typeof action === 'function') action();
      else if (!this.actions.buy(action)) this.actions.uiSound('deny');
      this.render();
    });
    b.addEventListener('mouseenter', () => this.actions.uiSound('hover'));
    return b;
  }

  private pips(tier: number, max: number): HTMLElement {
    const el = h('span', { class: 'pips' });
    for (let i = 0; i < max; i++) el.append(h('i', { class: i < tier ? 'on' : '' }));
    return el;
  }

  private renderWeapons(c: ShopContext): void {
    const grid = h('div', { class: 'card-grid' });
    for (const id of WEAPON_ORDER) grid.append(this.weaponCard(c, id));
    this.body.append(grid);
  }

  private weaponCard(c: ShopContext, id: WeaponId): HTMLElement {
    const def = WEAPONS[id];
    const w = c.arsenal.get(id);
    const card = h('div', { class: `card weapon-card ${w ? 'owned' : ''}` });
    card.append(h('div', { class: 'card-title' }, [h('span', { class: 'slot-num', text: String(def.slot) }), def.name]));
    if (!w) {
      card.append(h('div', { class: 'card-desc', text: def.description }));
      card.append(h('div', { class: 'card-stats', text: `${def.damage}${def.pellets > 1 ? `×${def.pellets}` : ''} dmg · ${def.fireRate}/s · ${def.magSize} mag` }));
      card.append(this.buyButton(c, getOffer(c, { kind: 'buyWeapon', weapon: id }), 'BUY', { kind: 'buyWeapon', weapon: id }));
      return card;
    }
    const dmg = upgradedDamage(def, w.upgrades);
    const rate = upgradedFireRate(def, w.upgrades);
    const mag = upgradedMagSize(def, w.upgrades);
    card.append(h('div', { class: 'card-stats', text: `${dmg.toFixed(0)}${def.pellets > 1 ? `×${def.pellets}` : ''} dmg · ${rate.toFixed(1)}/s · ${mag} mag` }));
    for (const kind of ['damage', 'fireRate', 'magazine'] as const) {
      const action: ShopAction = { kind: 'weaponUpgrade', weapon: id, upgrade: kind };
      const offer = getOffer(c, action);
      card.append(h('div', { class: 'upgrade-row' }, [h('span', { class: 'up-name', text: UPGRADE_LABELS[kind] }), this.pips(offer.tier, offer.maxTier), this.buyButton(c, offer, 'UP', action)]));
    }
    if (Number.isFinite(def.reserveMax)) {
      const action: ShopAction = { kind: 'ammo', weapon: id };
      card.append(h('div', { class: 'upgrade-row' }, [h('span', { class: 'up-name', text: `Ammo ${w.reserve}/${def.reserveMax}` }), this.buyButton(c, getOffer(c, action), 'REFILL', action)]));
    }
    return card;
  }

  private renderSurvivor(c: ShopContext): void {
    const grid = h('div', { class: 'card-grid' });
    const heal: ShopAction = { kind: 'heal' };
    grid.append(h('div', { class: 'card' }, [
      h('div', { class: 'card-title', text: 'Field Medkit' }),
      h('div', { class: 'card-desc', text: `Restore health to full (${Math.ceil(c.health)} / ${c.maxHealth}).` }),
      this.buyButton(c, getOffer(c, heal), 'HEAL', heal),
    ]));
    for (const id of Object.keys(PLAYER_UPGRADES) as PlayerUpgradeId[]) {
      const def = PLAYER_UPGRADES[id];
      const action: ShopAction = { kind: 'playerUpgrade', id };
      const offer = getOffer(c, action);
      grid.append(h('div', { class: 'card' }, [
        h('div', { class: 'card-title', text: def.name }),
        h('div', { class: 'card-desc', text: def.description }),
        h('div', { class: 'upgrade-row' }, [this.pips(offer.tier, offer.maxTier), this.buyButton(c, offer, 'BUY', action)]),
      ]));
    }
    this.body.append(grid);
  }

  private renderDefenses(c: ShopContext): void {
    const grid = h('div', { class: 'card-grid' });
    for (const type of ['barricade', 'turret'] as const) {
      const def = STRUCTURES[type];
      const action: ShopAction = { kind: 'structure', type };
      const offer = getOffer(c, action);
      grid.append(h('div', { class: 'card' }, [
        h('div', { class: 'card-title', text: def.name }),
        h('div', { class: 'card-desc', text: `${def.description} ${def.hp} HP.` }),
        h('div', { class: 'card-stats', text: `Built: ${offer.tier} / ${offer.maxTier}` }),
        this.buyButton(c, offer, 'PLACE', () => this.actions.place(type)),
      ]));
    }
    const repair: ShopAction = { kind: 'repair' };
    grid.append(h('div', { class: 'card' }, [
      h('div', { class: 'card-title', text: 'Repair Kit' }),
      h('div', { class: 'card-desc', text: 'Restore all barricades and turrets to full health.' }),
      this.buyButton(c, getOffer(c, repair), 'REPAIR', repair),
    ]));
    this.body.append(grid);
  }
}
