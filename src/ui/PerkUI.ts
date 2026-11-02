import { PERKS, type PerkId } from '../config/perks';
import { h } from './dom';

/** "Choose 1 of 3" perk selection overlay. Keys 1–3 also select. */
export class PerkUI {
  readonly root: HTMLElement;
  private readonly cards = h('div', { class: 'perk-cards' });
  private choices: PerkId[] = [];

  constructor(private readonly onChoose: (id: PerkId) => void, private readonly hover: () => void) {
    this.root = h('div', { class: 'screen perks modal hidden' }, [
      h('div', { class: 'perk-box' }, [
        h('h2', { text: 'CHOOSE A PERK' }),
        h('div', { class: 'perk-sub', text: 'Pick one. Perks last for the whole run.' }),
        this.cards,
      ]),
    ]);
    window.addEventListener('keydown', (e) => {
      if (!this.visible) return;
      const n = Number(e.key);
      if (n >= 1 && n <= this.choices.length) this.choose(this.choices[n - 1] as PerkId);
    });
  }

  get visible(): boolean {
    return !this.root.classList.contains('hidden');
  }

  open(choices: PerkId[], levels: (id: PerkId) => number): void {
    this.choices = choices;
    this.cards.replaceChildren(...choices.map((id, i) => {
      const def = PERKS[id];
      const lvl = levels(id);
      const card = h('button', { class: 'perk-card' }, [
        h('div', { class: 'perk-key', text: String(i + 1) }),
        h('div', { class: 'perk-glyph', text: def.glyph }),
        h('div', { class: 'perk-name', text: def.name }),
        h('div', { class: 'perk-desc', text: def.description }),
        h('div', { class: 'perk-stack', text: def.maxStacks > 1 ? `Level ${lvl + 1} / ${def.maxStacks}` : 'Unique' }),
      ]);
      card.style.setProperty('--perk-color', def.color);
      card.addEventListener('click', () => this.choose(id));
      card.addEventListener('mouseenter', this.hover);
      return card;
    }));
    this.root.classList.remove('hidden');
  }

  private choose(id: PerkId): void {
    if (!this.visible) return;
    this.root.classList.add('hidden');
    this.onChoose(id);
  }

  hide(): void {
    this.root.classList.add('hidden');
  }
}
