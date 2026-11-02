/** Coins, score and the kill-combo multiplier. Pure logic (unit tested). */
export class Economy {
  coins = 0;
  score = 0;
  totalCoinsEarned = 0;
  comboCount = 0;
  comboTimer = 0;
  bestCombo = 0;
  /** Multiplier applied to coin rewards (Greed perk). */
  coinMultiplier = 1;
  /** Seconds after a kill before the combo resets. */
  readonly comboWindow = 3;

  reset(startCoins = 0): void {
    this.coins = startCoins;
    this.score = 0;
    this.totalCoinsEarned = 0;
    this.comboCount = 0;
    this.comboTimer = 0;
    this.bestCombo = 0;
    this.coinMultiplier = 1;
  }

  /** Score multiplier from the current combo: +0.5x every 5 chained kills, up to 5x. */
  get multiplier(): number {
    return Math.min(5, 1 + Math.floor(this.comboCount / 5) * 0.5);
  }

  /** Fraction (0..1) of the combo window remaining, for the HUD timer bar. */
  get comboRemaining(): number {
    return this.comboCount > 0 ? this.comboTimer / this.comboWindow : 0;
  }

  registerKill(baseScore: number, baseCoins: number): { score: number; coins: number } {
    this.comboCount++;
    this.comboTimer = this.comboWindow;
    this.bestCombo = Math.max(this.bestCombo, this.comboCount);
    const score = Math.round(baseScore * this.multiplier);
    const coins = Math.max(1, Math.round(baseCoins * this.coinMultiplier));
    this.score += score;
    this.addCoins(coins);
    return { score, coins };
  }

  addScore(amount: number): void {
    this.score += Math.round(amount);
  }

  addCoins(amount: number): void {
    const a = Math.max(0, Math.round(amount));
    this.coins += a;
    this.totalCoinsEarned += a;
  }

  canAfford(cost: number): boolean {
    return this.coins >= cost;
  }

  spend(cost: number): boolean {
    if (cost < 0 || this.coins < cost) return false;
    this.coins -= cost;
    return true;
  }

  update(dt: number): void {
    if (this.comboCount === 0) return;
    this.comboTimer -= dt;
    if (this.comboTimer <= 0) {
      this.comboTimer = 0;
      this.comboCount = 0;
    }
  }
}
