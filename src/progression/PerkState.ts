import { PERKS, PERK_IDS, type PerkId } from '../config/perks';
import type { Rng } from '../core/Rng';

/** Which perks the player holds (with stack counts). */
export class PerkState {
  private readonly stacks = new Map<PerkId, number>();

  reset(): void {
    this.stacks.clear();
  }

  level(id: PerkId): number {
    return this.stacks.get(id) ?? 0;
  }

  has(id: PerkId): boolean {
    return this.level(id) > 0;
  }

  canTake(id: PerkId): boolean {
    return this.level(id) < PERKS[id].maxStacks;
  }

  add(id: PerkId): void {
    if (!this.canTake(id)) throw new Error(`Perk ${id} already at max stacks`);
    this.stacks.set(id, this.level(id) + 1);
  }

  /** All held perks in acquisition order with their stack counts. */
  list(): Array<{ id: PerkId; level: number }> {
    return [...this.stacks.entries()].map(([id, level]) => ({ id, level }));
  }

  /** Draws up to `count` distinct perks that can still be taken. */
  rollChoices(rng: Rng, count = 3): PerkId[] {
    const pool = PERK_IDS.filter((id) => this.canTake(id));
    rng.shuffle(pool);
    return pool.slice(0, count);
  }
}
