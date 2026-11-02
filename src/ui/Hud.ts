import { PERKS } from '../config/perks';
import { WEAPONS, WEAPON_ORDER } from '../config/weapons';
import { WAVE } from '../config/waves';
import type { NotifyTone } from '../game/events';
import type { World } from '../game/World';
import { h, setText, setWidth, toggle } from './dom';
import { Minimap } from './Minimap';

interface Bar {
  root: HTMLElement;
  fill: HTMLElement;
  label: HTMLElement;
}

function bar(cls: string, name: string): Bar {
  const fill = h('div', { class: 'bar-fill' });
  const label = h('div', { class: 'bar-label' });
  const root = h('div', { class: `bar ${cls}` }, [h('div', { class: 'bar-name', text: name }), h('div', { class: 'bar-track' }, [fill, label])]);
  return { root, fill, label };
}

/**
 * In-game heads-up display: vitals, wave info, score/coins/combo, weapon and
 * ammo, perks, boss bar, minimap, crosshair, notifications and hurt vignette.
 */
export class Hud {
  readonly root: HTMLElement;
  readonly minimap: Minimap;
  private readonly health = bar('health', 'HP');
  private readonly armor = bar('armor', 'ARMOR');
  private readonly stamina = bar('stamina', 'STAMINA');
  private readonly waveLabel = h('div', { class: 'wave-label' });
  private readonly waveSub = h('div', { class: 'wave-sub' });
  private readonly bossWrap = h('div', { class: 'boss-bar hidden' });
  private readonly bossFill = h('div', { class: 'boss-fill' });
  private readonly bossName = h('div', { class: 'boss-name', text: 'THE ABOMINATION' });
  private readonly score = h('div', { class: 'score-value' });
  private readonly coins = h('div', { class: 'coins-value' });
  private readonly combo = h('div', { class: 'combo' });
  private readonly comboMult = h('div', { class: 'combo-mult' });
  private readonly comboCount = h('div', { class: 'combo-count' });
  private readonly comboFill = h('div', { class: 'combo-fill' });
  private readonly weaponName = h('div', { class: 'weapon-name' });
  private readonly ammo = h('div', { class: 'ammo' });
  private readonly ammoMag = h('span', { class: 'ammo-mag' });
  private readonly ammoReserve = h('span', { class: 'ammo-reserve' });
  private readonly reloadBar = h('div', { class: 'reload-bar hidden' });
  private readonly reloadFill = h('div', { class: 'reload-fill' });
  private readonly slots: HTMLElement[] = [];
  private readonly perkTray = h('div', { class: 'perk-tray' });
  private readonly fps = h('div', { class: 'fps hidden' });
  private readonly toasts = h('div', { class: 'toasts' });
  private readonly banner = h('div', { class: 'banner' });
  private readonly bannerTitle = h('div', { class: 'banner-title' });
  private readonly bannerSub = h('div', { class: 'banner-sub' });
  private readonly vignette = h('div', { class: 'vignette' });
  private readonly crosshair = h('div', { class: 'crosshair hidden' });
  private readonly crossRing = h('div', { class: 'crosshair-ring' });
  private readonly lowAmmo = h('div', { class: 'low-ammo hidden', text: 'RELOAD' });
  private bannerTimer = 0;
  private perkSignature = '';

  constructor(parent: HTMLElement, private readonly world: World) {
    this.minimap = new Minimap(world);
    this.bossWrap.append(this.bossName, h('div', { class: 'boss-track' }, [this.bossFill]));
    this.combo.append(this.comboMult, this.comboCount, h('div', { class: 'combo-track' }, [this.comboFill]));
    this.ammo.append(this.ammoMag, h('span', { class: 'ammo-sep', text: '/' }), this.ammoReserve);
    this.reloadBar.append(this.reloadFill);
    const slotRow = h('div', { class: 'slots' });
    for (const id of WEAPON_ORDER) {
      const s = h('div', { class: 'slot', text: String(WEAPONS[id].slot), attrs: { title: WEAPONS[id].name } });
      this.slots.push(s);
      slotRow.append(s);
    }
    this.banner.append(this.bannerTitle, this.bannerSub);
    this.crosshair.append(this.crossRing, h('div', { class: 'crosshair-dot' }));

    this.root = h('div', { class: 'hud hidden' }, [
      this.vignette,
      h('div', { class: 'hud-vitals panel' }, [this.health.root, this.armor.root, this.stamina.root, this.perkTray]),
      h('div', { class: 'hud-wave' }, [this.waveLabel, this.waveSub, this.bossWrap]),
      h('div', { class: 'hud-score panel' }, [
        h('div', { class: 'score-row' }, [h('span', { class: 'score-label', text: 'SCORE' }), this.score]),
        h('div', { class: 'score-row' }, [h('span', { class: 'coin-icon' }), this.coins]),
        this.combo,
      ]),
      h('div', { class: 'hud-weapon panel' }, [this.weaponName, this.ammo, this.reloadBar, slotRow]),
      h('div', { class: 'hud-minimap' }, [this.minimap.canvas]),
      this.toasts,
      this.banner,
      this.lowAmmo,
      this.fps,
      this.crosshair,
    ]);
    parent.appendChild(this.root);
  }

  setVisible(v: boolean): void {
    toggle(this.root, 'hidden', !v);
  }

  setFpsVisible(v: boolean): void {
    toggle(this.fps, 'hidden', !v);
  }

  setCrosshairVisible(v: boolean): void {
    toggle(this.crosshair, 'hidden', !v);
  }

  moveCrosshair(x: number, y: number, spreadPx: number): void {
    this.crosshair.style.transform = `translate(${x.toFixed(1)}px, ${y.toFixed(1)}px)`;
    const size = Math.max(14, Math.min(140, spreadPx * 2));
    const v = `${size.toFixed(0)}px`;
    if (this.crossRing.style.width !== v) {
      this.crossRing.style.width = v;
      this.crossRing.style.height = v;
    }
  }

  showBanner(title: string, sub: string, duration: number, tone: NotifyTone = 'info'): void {
    setText(this.bannerTitle, title);
    setText(this.bannerSub, sub);
    this.banner.className = `banner show tone-${tone}`;
    this.bannerTimer = duration;
  }

  toast(text: string, tone: NotifyTone): void {
    const el = h('div', { class: `toast tone-${tone}`, text });
    this.toasts.prepend(el);
    while (this.toasts.childElementCount > 4) this.toasts.lastElementChild?.remove();
    window.setTimeout(() => el.classList.add('fade'), 2200);
    window.setTimeout(() => el.remove(), 2800);
  }

  clearTransient(): void {
    this.toasts.replaceChildren();
    this.banner.className = 'banner';
    this.bannerTimer = 0;
  }

  update(dt: number, fps: number, playing: boolean): void {
    const w = this.world;
    const p = w.player;
    const st = p.stats;

    setWidth(this.health.fill, p.health / st.maxHealth);
    setText(this.health.label, `${Math.ceil(p.health)} / ${st.maxHealth}`);
    toggle(this.health.root, 'critical', p.alive && p.health < st.maxHealth * 0.3);
    setWidth(this.armor.fill, st.maxArmor > 0 ? p.armor / st.maxArmor : 0);
    setText(this.armor.label, `${Math.ceil(p.armor)} / ${st.maxArmor}`);
    setWidth(this.stamina.fill, p.stamina / st.maxStamina);
    setText(this.stamina.label, `${Math.round(p.stamina)}`);
    toggle(this.stamina.root, 'exhausted', p.exhausted);

    // Wave status.
    const wd = w.waves;
    if (wd.phase === 'countdown') {
      setText(this.waveLabel, `WAVE ${wd.nextWave}`);
      setText(this.waveSub, `Starting in ${Math.ceil(wd.timer)}`);
    } else if (wd.phase === 'active') {
      setText(this.waveLabel, `WAVE ${wd.wave}`);
      const rem = wd.remaining(w);
      setText(this.waveSub, `${rem} zombie${rem === 1 ? '' : 's'} remaining`);
    } else if (wd.phase === 'cleared') {
      setText(this.waveLabel, `WAVE ${wd.wave}`);
      setText(this.waveSub, 'Cleared!');
    } else {
      setText(this.waveLabel, '');
      setText(this.waveSub, '');
    }
    const boss = wd.boss;
    toggle(this.bossWrap, 'hidden', !boss || !boss.alive);
    if (boss && boss.alive) {
      setWidth(this.bossFill, boss.hp / boss.maxHp);
      toggle(this.bossWrap, 'enraged', boss.enraged);
    }

    // Score / coins / combo.
    const eco = w.economy;
    setText(this.score, eco.score.toLocaleString());
    setText(this.coins, eco.coins.toLocaleString());
    toggle(this.combo, 'active', eco.comboCount >= 2);
    setText(this.comboMult, `x${eco.multiplier.toFixed(1)}`);
    setText(this.comboCount, `${eco.comboCount} combo`);
    setWidth(this.comboFill, eco.comboRemaining);

    // Weapon.
    const a = w.arsenal;
    const cur = a.current;
    setText(this.weaponName, cur.def.name);
    setText(this.ammoMag, String(cur.mag));
    setText(this.ammoReserve, Number.isFinite(cur.reserve) ? String(cur.reserve) : '∞');
    const magSize = a.magSize(cur.def.id);
    toggle(this.ammoMag, 'low', cur.mag <= Math.ceil(magSize * 0.25));
    toggle(this.reloadBar, 'hidden', !a.reloading);
    if (a.reloading) setWidth(this.reloadFill, a.reloadProgress);
    toggle(this.lowAmmo, 'hidden', !(playing && cur.mag === 0 && !a.reloading && p.alive));
    setText(this.lowAmmo, cur.reserve > 0 ? 'RELOAD [R]' : 'NO AMMO');
    WEAPON_ORDER.forEach((id, i) => {
      const s = this.slots[i] as HTMLElement;
      toggle(s, 'owned', a.owns(id));
      toggle(s, 'current', a.currentId === id);
    });

    // Perks (rebuild only when they change).
    const perks = w.perks.list();
    const sig = perks.map((x) => `${x.id}${x.level}`).join(',');
    if (sig !== this.perkSignature) {
      this.perkSignature = sig;
      this.perkTray.replaceChildren(...perks.map((x) => {
        const def = PERKS[x.id];
        const el = h('div', { class: 'perk-badge', text: def.glyph, attrs: { title: `${def.name}${x.level > 1 ? ` x${x.level}` : ''}: ${def.description}` } });
        el.style.borderColor = def.color;
        el.style.color = def.color;
        if (x.level > 1) el.append(h('span', { class: 'perk-level', text: String(x.level) }));
        return el;
      }));
    }

    // Hurt vignette: flash on hit + pulse at low health.
    const low = p.alive && p.health < st.maxHealth * 0.3 ? 0.35 + Math.sin(w.time * 6) * 0.15 : 0;
    const v = Math.max(p.hurtFlash * 0.75, low, p.alive ? 0 : 0.6);
    this.vignette.style.opacity = v.toFixed(2);

    if (this.bannerTimer > 0) {
      this.bannerTimer -= dt;
      if (this.bannerTimer <= 0) this.banner.classList.remove('show');
    }
    setText(this.fps, `${Math.round(fps)} FPS`);
    this.minimap.update(dt);
  }

  /** Called on wave events to show the big centre banner. */
  announceWave(wave: number, boss: boolean): void {
    if (boss) this.showBanner(`WAVE ${wave}`, 'BOSS INCOMING — watch for red warnings!', 3, 'boss');
    else this.showBanner(`WAVE ${wave}`, wave === 1 ? 'Survive the horde' : 'They keep coming…', 2.2, 'bad');
  }

  announceCleared(wave: number, bonus: number): void {
    this.showBanner(`WAVE ${wave} CLEARED`, `+${bonus} coins bonus`, WAVE.clearDelay, 'good');
  }
}
