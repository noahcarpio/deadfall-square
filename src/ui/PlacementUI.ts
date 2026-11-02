import { STRUCTURES, type StructureType } from '../config/shop';
import { h } from './dom';

export interface PlacementActions {
  rotate(): void;
  confirm(): void;
  cancel(): void;
}

/** Bottom bar shown while placing a barricade or turret. */
export class PlacementUI {
  readonly root: HTMLElement;
  private readonly label = h('div', { class: 'place-label' });
  private readonly hint = h('div', { class: 'place-hint' });
  private readonly confirmBtn: HTMLButtonElement;

  constructor(actions: PlacementActions) {
    const btn = (text: string, fn: () => void, cls = ''): HTMLButtonElement => {
      const b = h('button', { class: `btn small ${cls}`, text });
      b.addEventListener('click', (e) => {
        e.stopPropagation();
        fn();
      });
      b.addEventListener('pointerdown', (e) => e.stopPropagation());
      return b;
    };
    this.confirmBtn = btn('PLACE', actions.confirm, 'primary');
    this.root = h('div', { class: 'placement hidden' }, [
      h('div', {}, [this.label, this.hint]),
      h('div', { class: 'row' }, [btn('ROTATE', actions.rotate), this.confirmBtn, btn('CANCEL', actions.cancel, 'danger')]),
    ]);
  }

  show(type: StructureType, cost: number, touch: boolean): void {
    this.label.textContent = `Placing ${STRUCTURES[type].name} — ${cost} coins`;
    this.hint.textContent = touch
      ? 'Drag to pan · tap the ground to position · PLACE to build'
      : 'Click to place · R / right-click to rotate · WASD to pan · Esc to cancel';
    this.confirmBtn.style.display = touch ? '' : 'none';
    this.root.classList.remove('hidden');
  }

  setValid(valid: boolean): void {
    this.confirmBtn.disabled = !valid;
    this.root.classList.toggle('invalid', !valid);
  }

  hide(): void {
    this.root.classList.add('hidden');
  }
}
