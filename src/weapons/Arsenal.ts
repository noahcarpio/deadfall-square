import {
  WEAPONS, WEAPON_ORDER, upgradedFireRate, upgradedMagSize,
  type WeaponDef, type WeaponId, type WeaponUpgrades,
} from '../config/weapons';

export interface WeaponState {
  readonly def: WeaponDef;
  mag: number;
  reserve: number;
  upgrades: WeaponUpgrades;
}

/**
 * The player's weapons: ownership, ammo, reloading and fire-rate gating.
 * Pure logic with no rendering, so it is unit-tested directly.
 */
export class Arsenal {
  private readonly owned = new Map<WeaponId, WeaponState>();
  currentId: WeaponId = 'pistol';
  reloadTimer = 0;
  reloadDuration = 0;
  private cooldown = 0;
  /** Seconds since the last shot (drives recoil animation / spread recovery). */
  sinceShot = 10;

  reset(): void {
    this.owned.clear();
    this.give('pistol');
    this.currentId = 'pistol';
    this.reloadTimer = 0;
    this.reloadDuration = 0;
    this.cooldown = 0;
  }

  get current(): WeaponState {
    const w = this.owned.get(this.currentId);
    if (!w) throw new Error(`Current weapon ${this.currentId} not owned`);
    return w;
  }

  get reloading(): boolean {
    return this.reloadTimer > 0;
  }

  /** 0..1 reload progress. */
  get reloadProgress(): number {
    return this.reloadDuration > 0 ? 1 - this.reloadTimer / this.reloadDuration : 0;
  }

  owns(id: WeaponId): boolean {
    return this.owned.has(id);
  }

  get(id: WeaponId): WeaponState | undefined {
    return this.owned.get(id);
  }

  /** Owned weapons in slot order. */
  list(): WeaponState[] {
    return WEAPON_ORDER.filter((id) => this.owned.has(id)).map((id) => this.owned.get(id) as WeaponState);
  }

  magSize(id: WeaponId): number {
    const w = this.owned.get(id);
    return w ? upgradedMagSize(w.def, w.upgrades) : WEAPONS[id].magSize;
  }

  /** Gives a weapon. Returns 'new' if newly acquired, otherwise grants ammo and returns 'ammo'. */
  give(id: WeaponId): 'new' | 'ammo' {
    const existing = this.owned.get(id);
    if (existing) {
      this.addAmmoFraction(id, 0.5);
      return 'ammo';
    }
    const def = WEAPONS[id];
    this.owned.set(id, { def, mag: def.magSize, reserve: def.startReserve, upgrades: { damage: 0, fireRate: 0, magazine: 0 } });
    return 'new';
  }

  /** Adds a fraction of the weapon's max reserve. Returns the rounds actually added. */
  addAmmoFraction(id: WeaponId, fraction: number): number {
    const w = this.owned.get(id);
    if (!w || !Number.isFinite(w.def.reserveMax)) return 0;
    const before = w.reserve;
    w.reserve = Math.min(w.def.reserveMax, w.reserve + Math.ceil(w.def.reserveMax * fraction));
    return w.reserve - before;
  }

  /** True if any owned limited-ammo weapon is below `fraction` of its reserve. */
  lowOnAmmo(fraction = 0.25): boolean {
    for (const w of this.owned.values()) {
      if (Number.isFinite(w.def.reserveMax) && w.reserve + w.mag < w.def.reserveMax * fraction) return true;
    }
    return false;
  }

  refill(id: WeaponId): void {
    const w = this.owned.get(id);
    if (!w) return;
    w.reserve = w.def.reserveMax;
    w.mag = this.magSize(id);
  }

  /** Reloads every owned weapon from its reserve (free top-up between waves). */
  reloadAll(): void {
    for (const w of this.owned.values()) {
      const need = this.magSize(w.def.id) - w.mag;
      const take = Math.min(need, w.reserve);
      w.mag += take;
      if (Number.isFinite(w.reserve)) w.reserve -= take;
    }
    this.reloadTimer = 0;
    this.reloadDuration = 0;
  }

  switchTo(id: WeaponId): boolean {
    if (!this.owned.has(id) || id === this.currentId) return false;
    this.currentId = id;
    this.reloadTimer = 0;
    this.reloadDuration = 0;
    this.cooldown = Math.max(this.cooldown, 0.18);
    return true;
  }

  cycle(direction: number): boolean {
    const ids = this.list().map((w) => w.def.id);
    if (ids.length < 2) return false;
    const i = ids.indexOf(this.currentId);
    const next = ids[(i + (direction > 0 ? 1 : -1) + ids.length) % ids.length] as WeaponId;
    return this.switchTo(next);
  }

  canReload(): boolean {
    const w = this.current;
    return !this.reloading && w.mag < this.magSize(w.def.id) && w.reserve > 0;
  }

  startReload(speedMultiplier = 1): boolean {
    if (!this.canReload()) return false;
    this.reloadDuration = this.current.def.reloadTime / speedMultiplier;
    this.reloadTimer = this.reloadDuration;
    return true;
  }

  /**
   * Advances timers and returns how many shots fire this step while the
   * trigger is held. Auto-reloads on an empty magazine.
   */
  update(dt: number, triggerHeld: boolean, canShoot: boolean, reloadSpeed = 1): { shots: number; reloaded: boolean; dryFire: boolean } {
    let reloaded = false;
    let dryFire = false;
    this.sinceShot += dt;
    if (this.reloadTimer > 0) {
      this.reloadTimer -= dt;
      if (this.reloadTimer <= 0) {
        this.finishReload();
        reloaded = true;
      }
    }
    this.cooldown = Math.max(-1 / 60, this.cooldown - dt);
    let shots = 0;
    if (triggerHeld && canShoot && !this.reloading) {
      const w = this.current;
      const interval = 1 / upgradedFireRate(w.def, w.upgrades);
      while (this.cooldown <= 0 && w.mag > 0) {
        w.mag--;
        shots++;
        this.cooldown += interval;
        this.sinceShot = 0;
      }
      if (w.mag === 0 && this.cooldown <= 0) {
        if (!this.startReload(reloadSpeed)) dryFire = true;
        this.cooldown = interval;
      }
    }
    if (!triggerHeld && this.cooldown < 0) this.cooldown = 0;
    return { shots, reloaded, dryFire };
  }

  private finishReload(): void {
    const w = this.current;
    const need = this.magSize(w.def.id) - w.mag;
    const take = Math.min(need, w.reserve);
    w.mag += take;
    if (Number.isFinite(w.reserve)) w.reserve -= take;
    this.reloadTimer = 0;
    this.reloadDuration = 0;
  }
}
