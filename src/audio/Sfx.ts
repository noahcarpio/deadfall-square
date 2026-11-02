/**
 * Synthesised sound-effect recipes. Each recipe schedules oscillators/noise
 * into `out` starting at time `t` and returns its duration in seconds.
 */
export interface SynthContext {
  ctx: AudioContext;
  out: AudioNode;
  noise: AudioBuffer;
  t: number;
  pitch: number;
}

type FilterKind = BiquadFilterType;

function env(g: GainNode, t: number, peak: number, attack: number, decay: number): void {
  g.gain.setValueAtTime(0.0001, t);
  g.gain.exponentialRampToValueAtTime(Math.max(0.0002, peak), t + attack);
  g.gain.exponentialRampToValueAtTime(0.0001, t + attack + decay);
}

/** Filtered noise burst. */
function noise(s: SynthContext, opts: { start?: number; dur: number; type: FilterKind; freq: number; freqEnd?: number; q?: number; gain: number; attack?: number }): void {
  const { ctx } = s;
  const t = s.t + (opts.start ?? 0);
  const src = ctx.createBufferSource();
  src.buffer = s.noise;
  src.playbackRate.value = 0.8 + Math.random() * 0.4;
  const f = ctx.createBiquadFilter();
  f.type = opts.type;
  f.frequency.setValueAtTime(opts.freq * s.pitch, t);
  if (opts.freqEnd !== undefined) f.frequency.exponentialRampToValueAtTime(Math.max(20, opts.freqEnd * s.pitch), t + opts.dur);
  f.Q.value = opts.q ?? 0.7;
  const g = ctx.createGain();
  env(g, t, opts.gain, opts.attack ?? 0.003, opts.dur);
  src.connect(f).connect(g).connect(s.out);
  src.start(t, Math.random() * 1.5);
  src.stop(t + (opts.attack ?? 0.003) + opts.dur + 0.05);
}

/** Pitched oscillator with an exponential pitch sweep. */
function tone(s: SynthContext, opts: { start?: number; dur: number; type: OscillatorType; freq: number; freqEnd?: number; gain: number; attack?: number; filter?: number }): void {
  const { ctx } = s;
  const t = s.t + (opts.start ?? 0);
  const o = ctx.createOscillator();
  o.type = opts.type;
  o.frequency.setValueAtTime(opts.freq * s.pitch, t);
  if (opts.freqEnd !== undefined) o.frequency.exponentialRampToValueAtTime(Math.max(10, opts.freqEnd * s.pitch), t + opts.dur);
  const g = ctx.createGain();
  env(g, t, opts.gain, opts.attack ?? 0.004, opts.dur);
  let node: AudioNode = o;
  if (opts.filter) {
    const f = ctx.createBiquadFilter();
    f.type = 'lowpass';
    f.frequency.value = opts.filter;
    node = node.connect(f);
  }
  node.connect(g).connect(s.out);
  o.start(t);
  o.stop(t + (opts.attack ?? 0.004) + opts.dur + 0.05);
}

/** Vocal-ish growl: sawtooth with vibrato through two formant filters. */
function growl(s: SynthContext, opts: { start?: number; dur: number; freq: number; freqEnd: number; gain: number; formants: [number, number]; attack?: number }): void {
  const { ctx } = s;
  const t = s.t + (opts.start ?? 0);
  const o = ctx.createOscillator();
  o.type = 'sawtooth';
  o.frequency.setValueAtTime(opts.freq * s.pitch, t);
  o.frequency.exponentialRampToValueAtTime(opts.freqEnd * s.pitch, t + opts.dur);
  const lfo = ctx.createOscillator();
  lfo.frequency.value = 5 + Math.random() * 4;
  const lfoGain = ctx.createGain();
  lfoGain.gain.value = opts.freq * 0.06;
  lfo.connect(lfoGain).connect(o.frequency);
  const g = ctx.createGain();
  env(g, t, opts.gain, opts.attack ?? 0.08, opts.dur);
  for (const fq of opts.formants) {
    const f = ctx.createBiquadFilter();
    f.type = 'bandpass';
    f.frequency.value = fq;
    f.Q.value = 4;
    o.connect(f).connect(g);
  }
  g.connect(s.out);
  o.start(t);
  lfo.start(t);
  const end = t + (opts.attack ?? 0.08) + opts.dur + 0.05;
  o.stop(end);
  lfo.stop(end);
}

function echo(s: SynthContext, time: number, feedback: number): AudioNode {
  const d = s.ctx.createDelay(1);
  d.delayTime.value = time;
  const fb = s.ctx.createGain();
  fb.gain.value = feedback;
  const lp = s.ctx.createBiquadFilter();
  lp.type = 'lowpass';
  lp.frequency.value = 1400;
  d.connect(lp).connect(fb).connect(d);
  lp.connect(s.out);
  return d;
}

export const SFX_RECIPES = {
  pistol(s: SynthContext) {
    noise(s, { dur: 0.11, type: 'bandpass', freq: 1900, freqEnd: 700, q: 0.8, gain: 0.9 });
    tone(s, { dur: 0.08, type: 'sine', freq: 170, freqEnd: 55, gain: 0.7 });
    noise(s, { dur: 0.02, type: 'highpass', freq: 4000, gain: 0.4 });
    return 0.2;
  },
  shotgun(s: SynthContext) {
    noise(s, { dur: 0.32, type: 'lowpass', freq: 2600, freqEnd: 300, gain: 1.3 });
    tone(s, { dur: 0.22, type: 'sine', freq: 95, freqEnd: 38, gain: 1.0 });
    noise(s, { start: 0.04, dur: 0.4, type: 'bandpass', freq: 500, q: 0.6, gain: 0.35 });
    // Pump action.
    noise(s, { start: 0.38, dur: 0.05, type: 'bandpass', freq: 2200, q: 2, gain: 0.25 });
    noise(s, { start: 0.5, dur: 0.05, type: 'bandpass', freq: 1600, q: 2, gain: 0.25 });
    return 0.6;
  },
  smg(s: SynthContext) {
    noise(s, { dur: 0.06, type: 'bandpass', freq: 2600, freqEnd: 1100, q: 0.9, gain: 0.7 });
    tone(s, { dur: 0.05, type: 'sine', freq: 210, freqEnd: 90, gain: 0.45 });
    return 0.12;
  },
  rifle(s: SynthContext) {
    noise(s, { dur: 0.15, type: 'bandpass', freq: 1500, freqEnd: 450, q: 0.7, gain: 1.0 });
    tone(s, { dur: 0.11, type: 'sine', freq: 140, freqEnd: 48, gain: 0.8 });
    noise(s, { dur: 0.025, type: 'highpass', freq: 4500, gain: 0.5 });
    return 0.22;
  },
  sniper(s: SynthContext) {
    const tail = echo(s, 0.19, 0.32);
    const wet = { ...s, out: tail };
    noise(s, { dur: 0.45, type: 'lowpass', freq: 3200, freqEnd: 200, gain: 1.4 });
    tone(s, { dur: 0.4, type: 'sine', freq: 85, freqEnd: 32, gain: 1.1 });
    noise(s, { dur: 0.03, type: 'highpass', freq: 5000, gain: 0.7 });
    noise(wet, { dur: 0.35, type: 'lowpass', freq: 1500, freqEnd: 200, gain: 0.5 });
    noise(s, { start: 0.55, dur: 0.06, type: 'bandpass', freq: 1800, q: 3, gain: 0.25 });
    noise(s, { start: 0.72, dur: 0.06, type: 'bandpass', freq: 1300, q: 3, gain: 0.25 });
    return 1.4;
  },
  flamer(s: SynthContext) {
    noise(s, { dur: 0.15, type: 'lowpass', freq: 800, gain: 0.3 });
    return 0.2;
  },
  launcher(s: SynthContext) {
    tone(s, { dur: 0.16, type: 'sine', freq: 130, freqEnd: 55, gain: 1.1 });
    noise(s, { dur: 0.1, type: 'lowpass', freq: 700, gain: 0.6 });
    noise(s, { start: 0.02, dur: 0.05, type: 'bandpass', freq: 2500, q: 2, gain: 0.25 });
    return 0.3;
  },
  reload(s: SynthContext) {
    noise(s, { dur: 0.04, type: 'bandpass', freq: 2400, q: 3, gain: 0.35 });
    noise(s, { start: 0.12, dur: 0.05, type: 'bandpass', freq: 1500, q: 3, gain: 0.3 });
    return 0.25;
  },
  reloadDone(s: SynthContext) {
    noise(s, { dur: 0.04, type: 'bandpass', freq: 1900, q: 4, gain: 0.35 });
    noise(s, { start: 0.07, dur: 0.05, type: 'bandpass', freq: 2800, q: 4, gain: 0.35 });
    return 0.2;
  },
  dryFire(s: SynthContext) {
    noise(s, { dur: 0.025, type: 'highpass', freq: 3000, gain: 0.3 });
    return 0.06;
  },
  weaponSwap(s: SynthContext) {
    noise(s, { dur: 0.05, type: 'bandpass', freq: 1200, q: 2, gain: 0.3 });
    noise(s, { start: 0.08, dur: 0.04, type: 'bandpass', freq: 2600, q: 3, gain: 0.3 });
    return 0.16;
  },
  hit(s: SynthContext) {
    const p = 0.85 + Math.random() * 0.3;
    noise({ ...s, pitch: s.pitch * p }, { dur: 0.06, type: 'bandpass', freq: 750, q: 1.4, gain: 0.55 });
    tone({ ...s, pitch: s.pitch * p }, { dur: 0.05, type: 'triangle', freq: 220, freqEnd: 110, gain: 0.2 });
    return 0.1;
  },
  zombieDeath(s: SynthContext) {
    const p = 0.8 + Math.random() * 0.4;
    growl({ ...s, pitch: s.pitch * p }, { dur: 0.45, freq: 160, freqEnd: 55, gain: 0.55, formants: [450, 900], attack: 0.02 });
    noise(s, { dur: 0.15, type: 'lowpass', freq: 700, gain: 0.45 });
    return 0.55;
  },
  zombieAttack(s: SynthContext) {
    const p = 0.8 + Math.random() * 0.4;
    growl({ ...s, pitch: s.pitch * p }, { dur: 0.3, freq: 150, freqEnd: 95, gain: 0.45, formants: [550, 1300], attack: 0.03 });
    return 0.4;
  },
  groan(s: SynthContext) {
    const p = 0.75 + Math.random() * 0.5;
    const dur = 0.9 + Math.random() * 0.9;
    growl({ ...s, pitch: s.pitch * p }, { dur, freq: 95, freqEnd: 70 + Math.random() * 40, gain: 0.35, formants: [420 + Math.random() * 200, 1000 + Math.random() * 300], attack: 0.25 });
    return dur + 0.3;
  },
  explosion(s: SynthContext) {
    noise(s, { dur: 0.9, type: 'lowpass', freq: 2200, freqEnd: 120, gain: 1.6, attack: 0.005 });
    tone(s, { dur: 0.75, type: 'sine', freq: 70, freqEnd: 24, gain: 1.4 });
    noise(s, { start: 0.05, dur: 1.2, type: 'lowpass', freq: 500, freqEnd: 80, gain: 0.5 });
    return 1.3;
  },
  playerHurt(s: SynthContext) {
    tone(s, { dur: 0.16, type: 'square', freq: 260, freqEnd: 140, gain: 0.25, filter: 1200 });
    noise(s, { dur: 0.08, type: 'lowpass', freq: 1000, gain: 0.5 });
    tone(s, { dur: 0.12, type: 'sine', freq: 90, freqEnd: 50, gain: 0.6 });
    return 0.25;
  },
  pickup(s: SynthContext) {
    tone(s, { dur: 0.08, type: 'triangle', freq: 660, gain: 0.35 });
    tone(s, { start: 0.06, dur: 0.08, type: 'triangle', freq: 990, gain: 0.35 });
    return 0.2;
  },
  pickupHealth(s: SynthContext) {
    tone(s, { dur: 0.12, type: 'sine', freq: 523, gain: 0.35 });
    tone(s, { start: 0.08, dur: 0.12, type: 'sine', freq: 659, gain: 0.35 });
    tone(s, { start: 0.16, dur: 0.2, type: 'sine', freq: 784, gain: 0.35 });
    return 0.4;
  },
  pickupWeapon(s: SynthContext) {
    noise(s, { dur: 0.05, type: 'bandpass', freq: 1500, q: 2, gain: 0.4 });
    tone(s, { start: 0.05, dur: 0.1, type: 'square', freq: 440, gain: 0.15, filter: 2500 });
    tone(s, { start: 0.12, dur: 0.18, type: 'square', freq: 660, gain: 0.15, filter: 2500 });
    return 0.35;
  },
  coin(s: SynthContext) {
    tone(s, { dur: 0.06, type: 'sine', freq: 1320, gain: 0.18 });
    tone(s, { start: 0.05, dur: 0.12, type: 'sine', freq: 1760, gain: 0.18 });
    return 0.2;
  },
  roll(s: SynthContext) {
    noise(s, { dur: 0.22, type: 'bandpass', freq: 500, freqEnd: 1400, q: 0.8, gain: 0.35, attack: 0.04 });
    return 0.3;
  },
  spit(s: SynthContext) {
    noise(s, { dur: 0.18, type: 'bandpass', freq: 600, freqEnd: 1800, q: 1.5, gain: 0.5 });
    tone(s, { dur: 0.1, type: 'sine', freq: 300, freqEnd: 600, gain: 0.2 });
    return 0.25;
  },
  acidSplash(s: SynthContext) {
    noise(s, { dur: 0.45, type: 'highpass', freq: 2500, freqEnd: 5000, gain: 0.35, attack: 0.01 });
    noise(s, { dur: 0.1, type: 'lowpass', freq: 600, gain: 0.4 });
    return 0.5;
  },
  fuse(s: SynthContext) {
    noise(s, { dur: 0.6, type: 'highpass', freq: 3500, gain: 0.25, attack: 0.05 });
    for (let i = 0; i < 4; i++) tone(s, { start: i * 0.17 - i * i * 0.012, dur: 0.05, type: 'square', freq: 880, gain: 0.12, filter: 3000 });
    return 0.7;
  },
  bossRoar(s: SynthContext) {
    growl(s, { dur: 1.2, freq: 75, freqEnd: 42, gain: 0.9, formants: [350, 800], attack: 0.1 });
    growl({ ...s, pitch: s.pitch * 1.5 }, { dur: 1.0, freq: 75, freqEnd: 50, gain: 0.4, formants: [600, 1400], attack: 0.15 });
    noise(s, { dur: 1.1, type: 'bandpass', freq: 400, q: 0.8, gain: 0.35, attack: 0.1 });
    return 1.5;
  },
  slam(s: SynthContext) {
    tone(s, { dur: 0.6, type: 'sine', freq: 60, freqEnd: 22, gain: 1.5 });
    noise(s, { dur: 0.6, type: 'lowpass', freq: 900, freqEnd: 100, gain: 1.1 });
    return 0.8;
  },
  waveStart(s: SynthContext) {
    tone(s, { dur: 1.6, type: 'sawtooth', freq: 220, freqEnd: 440, gain: 0.18, filter: 1400, attack: 0.3 });
    tone(s, { dur: 1.6, type: 'sawtooth', freq: 223, freqEnd: 446, gain: 0.14, filter: 1400, attack: 0.3 });
    tone(s, { dur: 0.5, type: 'sine', freq: 80, freqEnd: 40, gain: 0.8 });
    noise(s, { dur: 1.2, type: 'lowpass', freq: 300, gain: 0.25, attack: 0.2 });
    return 2.0;
  },
  waveClear(s: SynthContext) {
    const notes = [392, 494, 587, 784];
    notes.forEach((f, i) => tone(s, { start: i * 0.09, dur: 0.9 - i * 0.1, type: 'triangle', freq: f, gain: 0.22 }));
    return 1.2;
  },
  bossDefeated(s: SynthContext) {
    const notes = [262, 330, 392, 523, 659];
    notes.forEach((f, i) => tone(s, { start: i * 0.12, dur: 1.3, type: 'triangle', freq: f, gain: 0.2 }));
    tone(s, { dur: 1.8, type: 'sine', freq: 65, gain: 0.5 });
    return 2.2;
  },
  uiClick(s: SynthContext) {
    tone(s, { dur: 0.04, type: 'square', freq: 1200, freqEnd: 900, gain: 0.08, filter: 4000 });
    return 0.08;
  },
  uiHover(s: SynthContext) {
    tone(s, { dur: 0.025, type: 'sine', freq: 1800, gain: 0.04 });
    return 0.05;
  },
  uiBuy(s: SynthContext) {
    tone(s, { dur: 0.07, type: 'sine', freq: 1046, gain: 0.2 });
    tone(s, { start: 0.06, dur: 0.12, type: 'sine', freq: 1568, gain: 0.2 });
    noise(s, { dur: 0.03, type: 'highpass', freq: 5000, gain: 0.15 });
    return 0.25;
  },
  uiDeny(s: SynthContext) {
    tone(s, { dur: 0.18, type: 'square', freq: 140, gain: 0.15, filter: 900 });
    return 0.22;
  },
  perk(s: SynthContext) {
    [523, 659, 784, 1046, 1318].forEach((f, i) => tone(s, { start: i * 0.06, dur: 0.5, type: 'triangle', freq: f, gain: 0.16 }));
    return 0.9;
  },
  turret(s: SynthContext) {
    tone(s, { dur: 0.05, type: 'square', freq: 1100, freqEnd: 350, gain: 0.12, filter: 3000 });
    noise(s, { dur: 0.04, type: 'bandpass', freq: 3000, q: 1, gain: 0.25 });
    return 0.1;
  },
  build(s: SynthContext) {
    noise(s, { dur: 0.12, type: 'lowpass', freq: 500, gain: 0.7 });
    tone(s, { dur: 0.15, type: 'sine', freq: 130, freqEnd: 70, gain: 0.6 });
    noise(s, { start: 0.15, dur: 0.1, type: 'lowpass', freq: 600, gain: 0.5 });
    return 0.35;
  },
  structureHit(s: SynthContext) {
    noise(s, { dur: 0.08, type: 'bandpass', freq: 380, q: 2, gain: 0.6 });
    tone(s, { dur: 0.07, type: 'triangle', freq: 180, freqEnd: 120, gain: 0.3 });
    return 0.12;
  },
  structureBreak(s: SynthContext) {
    noise(s, { dur: 0.5, type: 'lowpass', freq: 1400, freqEnd: 200, gain: 0.9 });
    for (let i = 0; i < 5; i++) noise(s, { start: 0.05 + i * 0.07, dur: 0.05, type: 'bandpass', freq: 600 + Math.random() * 900, q: 3, gain: 0.35 });
    return 0.6;
  },
  footstep(s: SynthContext) {
    noise(s, { dur: 0.04, type: 'lowpass', freq: 380, gain: 0.18 });
    return 0.06;
  },
  heartbeat(s: SynthContext) {
    tone(s, { dur: 0.12, type: 'sine', freq: 60, freqEnd: 40, gain: 0.6 });
    tone(s, { start: 0.2, dur: 0.12, type: 'sine', freq: 55, freqEnd: 38, gain: 0.45 });
    return 0.4;
  },
  gameOver(s: SynthContext) {
    [392, 370, 349, 294].forEach((f, i) => tone(s, { start: i * 0.35, dur: 0.6, type: 'sawtooth', freq: f, gain: 0.12, filter: 900 }));
    tone(s, { start: 1.2, dur: 2, type: 'sine', freq: 49, gain: 0.5 });
    return 3.3;
  },
} satisfies Record<string, (s: SynthContext) => number>;

export type SfxName = keyof typeof SFX_RECIPES;
