import { ZOMBIES, ZOMBIE_TYPES } from '../config/zombies';
import { formatTime } from '../core/math';
import type { Settings, SettingsData } from '../core/Settings';
import type { HighScoreEntry } from '../progression/HighScores';
import { MAX_NAME_LENGTH } from '../progression/HighScores';
import type { RunStats } from '../game/RunStats';
import { h, clear } from './dom';

export interface MenuActions {
  play(): void;
  resume(): void;
  restart(): void;
  quitToMenu(): void;
  saveScore(name: string): number;
  uiSound(kind: 'click' | 'hover'): void;
}

function button(label: string, onClick: () => void, actions: MenuActions, cls = ''): HTMLButtonElement {
  return h('button', {
    class: `btn ${cls}`.trim(),
    text: label,
    on: {
      click: () => {
        actions.uiSound('click');
        onClick();
      },
      mouseenter: () => actions.uiSound('hover'),
    },
  });
}

/** Base for full-screen overlay panels. */
abstract class Screen {
  readonly root: HTMLElement;
  constructor(cls: string) {
    this.root = h('div', { class: `screen ${cls} hidden` });
  }
  show(): void {
    this.root.classList.remove('hidden');
  }
  hide(): void {
    this.root.classList.add('hidden');
  }
  get visible(): boolean {
    return !this.root.classList.contains('hidden');
  }
}

export class MainMenu extends Screen {
  constructor(actions: MenuActions, open: (panel: 'howto' | 'settings' | 'scores') => void) {
    super('main-menu');
    this.root.append(
      h('div', { class: 'title-block' }, [
        h('div', { class: 'title-kicker', text: 'a low-poly survival horror' }),
        h('h1', { class: 'title' }, ['DEADFALL', h('span', { text: 'SQUARE' })]),
        h('div', { class: 'title-tag', text: 'Hold the town square. Survive the night.' }),
      ]),
      h('div', { class: 'menu-buttons' }, [
        button('PLAY', () => actions.play(), actions, 'primary'),
        button('HOW TO PLAY', () => open('howto'), actions),
        button('HIGH SCORES', () => open('scores'), actions),
        button('SETTINGS', () => open('settings'), actions),
      ]),
      h('div', { class: 'menu-footer', text: 'WASD move · Mouse aim · Click shoot · Shift sprint · Space roll · R reload' }),
    );
  }
}

export class PauseMenu extends Screen {
  constructor(actions: MenuActions, open: (panel: 'howto' | 'settings') => void) {
    super('pause-menu modal');
    const confirmRow = h('div', { class: 'confirm hidden' }, [
      h('div', { class: 'confirm-text', text: 'Quit this run? Progress will be lost.' }),
      h('div', { class: 'row' }, [
        button('QUIT', () => actions.quitToMenu(), actions, 'danger'),
        button('CANCEL', () => confirmRow.classList.add('hidden'), actions),
      ]),
    ]);
    this.root.append(
      h('div', { class: 'panel-box narrow' }, [
        h('h2', { text: 'PAUSED' }),
        h('div', { class: 'menu-buttons' }, [
          button('RESUME', () => actions.resume(), actions, 'primary'),
          button('SETTINGS', () => open('settings'), actions),
          button('HOW TO PLAY', () => open('howto'), actions),
          button('QUIT TO MENU', () => confirmRow.classList.remove('hidden'), actions, 'danger'),
        ]),
        confirmRow,
      ]),
    );
  }

  override show(): void {
    this.root.querySelector('.confirm')?.classList.add('hidden');
    super.show();
  }
}

export class HowToPlay extends Screen {
  constructor(actions: MenuActions, back: () => void) {
    super('howto modal');
    const controls: Array<[string, string]> = [
      ['WASD / Arrows', 'Move'],
      ['Mouse', 'Aim'],
      ['Left click (hold)', 'Shoot'],
      ['R', 'Reload'],
      ['Shift', 'Sprint (uses stamina)'],
      ['Space', 'Dodge roll (brief invulnerability)'],
      ['1–7 / Wheel / Q', 'Switch weapon'],
      ['Esc / P', 'Pause'],
    ];
    const touch: Array<[string, string]> = [
      ['Left stick', 'Move (push to the rim to sprint)'],
      ['Right stick', 'Aim & auto-fire'],
      ['ROLL / RELOAD / SWAP', 'Actions'],
    ];
    const tips = [
      'Kill zombies quickly in succession to build a combo multiplier for score.',
      'Coins buy upgrades, weapons, barricades and turrets between waves.',
      'Every 3rd wave you choose a perk. Every 5th wave a boss appears.',
      'Red ground markings warn of boss attacks — roll through shockwaves!',
      'Exploders blow up near you (and when killed). Shoot them at range.',
      'Barricades block zombies and soak damage; turrets fire automatically.',
      'Night falls as the waves go on. Your flashlight follows your aim.',
    ];
    const zombieRows = ZOMBIE_TYPES.map((t) => {
      const d = ZOMBIES[t];
      const desc: Record<string, string> = {
        walker: 'Slow and steady. Dangerous in numbers.',
        runner: 'Fast and fragile. Arrives first.',
        brute: 'Huge health. Its slam knocks you flying.',
        spitter: 'Keeps its distance and lobs acid that pools on the ground.',
        exploder: 'Glowing belly. Detonates when close.',
        boss: 'Every 5 waves. Charges, slams shockwaves, summons runners.',
      };
      const sw = h('span', { class: 'swatch' });
      sw.style.background = d.colors.skin;
      sw.style.boxShadow = `0 0 0 2px ${d.colors.eyes} inset`;
      return h('div', { class: 'zrow' }, [sw, h('b', { text: d.name }), h('span', { text: desc[t] ?? '' })]);
    });
    this.root.append(
      h('div', { class: 'panel-box wide scroll' }, [
        h('h2', { text: 'HOW TO PLAY' }),
        h('div', { class: 'cols' }, [
          h('div', {}, [
            h('h3', { text: 'Keyboard & Mouse' }),
            h('div', { class: 'keys' }, controls.flatMap(([k, v]) => [h('kbd', { text: k }), h('span', { text: v })])),
            h('h3', { text: 'Touch' }),
            h('div', { class: 'keys' }, touch.flatMap(([k, v]) => [h('kbd', { text: k }), h('span', { text: v })])),
          ]),
          h('div', {}, [h('h3', { text: 'The Undead' }), ...zombieRows]),
        ]),
        h('h3', { text: 'Survival tips' }),
        h('ul', { class: 'tips' }, tips.map((t) => h('li', { text: t }))),
        h('div', { class: 'row end' }, [button('BACK', back, actions)]),
      ]),
    );
  }
}

export class SettingsPanel extends Screen {
  private readonly inputs = new Map<keyof SettingsData, HTMLInputElement>();
  private readonly qualityButtons = new Map<string, HTMLButtonElement>();
  private readonly formatters = new Map<keyof SettingsData, { fmt: (v: number) => string; label: HTMLElement }>();

  constructor(private readonly settings: Settings, actions: MenuActions, back: () => void) {
    super('settings modal');
    const slider = (key: 'masterVolume' | 'musicVolume' | 'sfxVolume' | 'sensitivity', label: string, min: number, max: number, step: number, fmt: (v: number) => string): HTMLElement => {
      const value = h('span', { class: 'value' });
      const input = h('input', { attrs: { type: 'range', min: String(min), max: String(max), step: String(step), 'aria-label': label } });
      input.addEventListener('input', () => {
        const v = Number(input.value);
        value.textContent = fmt(v);
        settings.update({ [key]: v });
      });
      this.inputs.set(key, input);
      this.formatters.set(key, { fmt, label: value });
      return h('label', { class: 'setting' }, [h('span', { class: 'name', text: label }), input, value]);
    };
    const check = (key: 'showFps' | 'screenShake' | 'damageNumbers', label: string): HTMLElement => {
      const input = h('input', { attrs: { type: 'checkbox', 'aria-label': label } });
      input.addEventListener('change', () => {
        actions.uiSound('click');
        settings.update({ [key]: input.checked });
      });
      this.inputs.set(key, input);
      return h('label', { class: 'setting check' }, [h('span', { class: 'name', text: label }), input, h('span', { class: 'toggle' })]);
    };
    const pct = (v: number): string => `${Math.round(v * 100)}%`;
    const quality = h('div', { class: 'segmented' });
    for (const q of ['low', 'medium', 'high'] as const) {
      const b = h('button', { class: 'seg', text: q.toUpperCase() });
      b.addEventListener('click', () => {
        actions.uiSound('click');
        settings.update({ quality: q });
        this.refresh();
      });
      this.qualityButtons.set(q, b);
      quality.append(b);
    }
    this.root.append(
      h('div', { class: 'panel-box narrow' }, [
        h('h2', { text: 'SETTINGS' }),
        h('h3', { text: 'Audio' }),
        slider('masterVolume', 'Master volume', 0, 1, 0.05, pct),
        slider('musicVolume', 'Music volume', 0, 1, 0.05, pct),
        slider('sfxVolume', 'Effects volume', 0, 1, 0.05, pct),
        h('h3', { text: 'Controls' }),
        slider('sensitivity', 'Mouse sensitivity', 0.2, 3, 0.05, (v) => `${v.toFixed(2)}x`),
        h('h3', { text: 'Graphics' }),
        h('div', { class: 'setting' }, [h('span', { class: 'name', text: 'Quality' }), quality]),
        check('showFps', 'Show FPS'),
        check('screenShake', 'Screen shake'),
        check('damageNumbers', 'Damage numbers'),
        h('div', { class: 'row end' }, [button('BACK', back, actions)]),
      ]),
    );
  }

  refresh(): void {
    const d = this.settings.data;
    for (const [key, input] of this.inputs) {
      const v = d[key];
      if (typeof v === 'boolean') input.checked = v;
      else if (typeof v === 'number') {
        input.value = String(v);
        const f = this.formatters.get(key);
        if (f) f.label.textContent = f.fmt(v);
      }
    }
    for (const [q, b] of this.qualityButtons) b.classList.toggle('active', d.quality === q);
  }

  override show(): void {
    this.refresh();
    super.show();
  }
}

export function scoreTable(entries: readonly HighScoreEntry[], highlight = -1): HTMLElement {
  if (entries.length === 0) return h('div', { class: 'empty', text: 'No scores yet. Be the first survivor on the board!' });
  const rows = entries.map((e, i) =>
    h('tr', { class: i === highlight ? 'me' : '' }, [
      h('td', { text: `${i + 1}` }),
      h('td', { text: e.name }),
      h('td', { class: 'num', text: e.score.toLocaleString() }),
      h('td', { class: 'num', text: String(e.wave) }),
      h('td', { class: 'num', text: String(e.kills) }),
    ]),
  );
  return h('table', { class: 'scores' }, [
    h('thead', {}, [h('tr', {}, ['#', 'Name', 'Score', 'Wave', 'Kills'].map((t) => h('th', { text: t })))]),
    h('tbody', {}, rows),
  ]);
}

export class HighScoresPanel extends Screen {
  private readonly body = h('div', { class: 'scores-body' });
  constructor(private readonly getEntries: () => readonly HighScoreEntry[], actions: MenuActions, back: () => void) {
    super('highscores modal');
    this.root.append(
      h('div', { class: 'panel-box narrow' }, [
        h('h2', { text: 'HIGH SCORES' }),
        this.body,
        h('div', { class: 'row end' }, [button('BACK', back, actions)]),
      ]),
    );
  }
  override show(): void {
    clear(this.body);
    this.body.append(scoreTable(this.getEntries()));
    super.show();
  }
}

export interface GameOverData {
  stats: RunStats;
  score: number;
  bestCombo: number;
  coinsEarned: number;
  qualifies: boolean;
  lastName: string;
  /** Reads the current leaderboard (it changes after saving). */
  getEntries: () => readonly HighScoreEntry[];
}

export class GameOverScreen extends Screen {
  private readonly content = h('div', { class: 'gameover-content' });
  private readonly board = h('div', { class: 'gameover-board' });

  constructor(private readonly actions: MenuActions) {
    super('gameover modal');
    this.root.append(
      h('div', { class: 'panel-box wide' }, [
        h('h1', { class: 'died', text: 'YOU DIED' }),
        this.content,
        this.board,
        h('div', { class: 'row center' }, [
          button('PLAY AGAIN', () => actions.restart(), actions, 'primary'),
          button('MAIN MENU', () => actions.quitToMenu(), actions),
        ]),
      ]),
    );
  }

  open(data: GameOverData): void {
    const s = data.stats;
    const stat = (label: string, value: string, big = false): HTMLElement =>
      h('div', { class: `stat ${big ? 'big' : ''}` }, [h('div', { class: 'stat-value', text: value }), h('div', { class: 'stat-label', text: label })]);
    const kills = ZOMBIE_TYPES.filter((t) => s.kills[t] > 0).map((t) =>
      h('div', { class: 'kill-row' }, [h('span', { text: ZOMBIES[t].name }), h('b', { text: String(s.kills[t]) })]),
    );
    clear(this.content);
    this.content.append(
      h('div', { class: 'stats-grid' }, [
        stat('Score', data.score.toLocaleString(), true),
        stat('Waves survived', String(s.wavesCleared), true),
        stat('Time played', formatTime(s.timePlayed)),
        stat('Total kills', String(s.totalKills)),
        stat('Accuracy', `${Math.round(s.accuracy * 100)}%`),
        stat('Best combo', String(data.bestCombo)),
        stat('Coins earned', data.coinsEarned.toLocaleString()),
        stat('Damage dealt', Math.round(s.damageDealt).toLocaleString()),
      ]),
      h('div', { class: 'kills-box' }, [h('h3', { text: 'Kills by type' }), ...(kills.length ? kills : [h('div', { class: 'empty', text: 'None — the horde won this time.' })])]),
    );
    clear(this.board);
    if (data.qualifies) {
      const input = h('input', { class: 'name-input', attrs: { type: 'text', maxlength: String(MAX_NAME_LENGTH), placeholder: 'Your name', 'aria-label': 'Your name' } });
      input.value = data.lastName;
      const save = (): void => {
        const rank = this.actions.saveScore(input.value);
        clear(this.board);
        this.board.append(h('h3', { text: rank >= 0 ? `Saved! Rank #${rank + 1}` : 'High scores' }), scoreTable(data.getEntries(), rank));
      };
      input.addEventListener('keydown', (e) => {
        e.stopPropagation();
        if (e.key === 'Enter') save();
      });
      this.board.append(
        h('h3', { class: 'new-hs', text: 'NEW HIGH SCORE!' }),
        h('div', { class: 'row name-row' }, [input, button('SAVE', save, this.actions, 'primary')]),
        scoreTable(data.getEntries()),
      );
      window.setTimeout(() => input.focus(), 50);
    } else {
      this.board.append(h('h3', { text: 'High scores' }), scoreTable(data.getEntries()));
    }
    this.show();
  }
}
