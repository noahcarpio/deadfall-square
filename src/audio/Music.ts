export type MusicMood = 'menu' | 'calm' | 'combat' | 'boss' | 'gameover';

/** D minor-ish progressions (semitone offsets from D). */
const PROGRESSIONS: number[][][] = [
  // i - VI - III - VII
  [[0, 3, 7], [-4, 0, 3], [3, 7, 10], [-2, 2, 5]],
  // i - iv - VI - V
  [[0, 3, 7], [5, 8, 12], [-4, 0, 3], [-5, -1, 2]],
  // i - VII - VI - VII
  [[0, 3, 7], [-2, 2, 5], [-4, 0, 3], [-2, 2, 5]],
];
const SCALE = [0, 2, 3, 5, 7, 8, 10];
const ROOT_HZ = 146.83; // D3

function hz(semitones: number): number {
  return ROOT_HZ * Math.pow(2, semitones / 12);
}

interface MoodSettings {
  bpm: number;
  pad: number;
  bass: number;
  drums: number;
  bells: number;
  tension: number;
}

const MOODS: Record<MusicMood, MoodSettings> = {
  menu: { bpm: 72, pad: 0.9, bass: 0.0, drums: 0, bells: 0.5, tension: 0 },
  calm: { bpm: 80, pad: 0.8, bass: 0.35, drums: 0.15, bells: 0.4, tension: 0 },
  combat: { bpm: 104, pad: 0.6, bass: 0.8, drums: 0.8, bells: 0.15, tension: 0.4 },
  boss: { bpm: 124, pad: 0.65, bass: 1, drums: 1, bells: 0.1, tension: 1 },
  gameover: { bpm: 60, pad: 0.7, bass: 0, drums: 0, bells: 0.3, tension: 0 },
};

/**
 * Procedural soundtrack: a look-ahead scheduler (Web Audio clock) plays pads,
 * bass, drums and bell motifs whose density follows the game's mood and
 * intensity. Chord progressions are picked at random every few bars.
 */
export class Music {
  private mood: MoodSettings = MOODS.menu;
  private moodName: MusicMood = 'menu';
  private intensity = 0;
  private timer = 0;
  private nextStep = 0;
  private step = 0;
  private progression = PROGRESSIONS[0] as number[][];
  private readonly reverb: ConvolverNode;
  private readonly dry: GainNode;
  private readonly wet: GainNode;

  constructor(private readonly ctx: AudioContext, out: AudioNode, private readonly noise: AudioBuffer) {
    this.dry = ctx.createGain();
    this.dry.gain.value = 0.8;
    this.wet = ctx.createGain();
    this.wet.gain.value = 0.45;
    this.reverb = ctx.createConvolver();
    this.reverb.buffer = this.makeImpulse(2.8);
    this.dry.connect(out);
    this.wet.connect(this.reverb).connect(out);
  }

  setMood(mood: MusicMood): void {
    if (mood === this.moodName) return;
    this.moodName = mood;
    this.mood = MOODS[mood];
  }

  /** 0..1 extra intensity within a mood (e.g. many zombies alive). */
  setIntensity(level: number): void {
    this.intensity = Math.max(0, Math.min(1, level));
  }

  start(): void {
    this.nextStep = this.ctx.currentTime + 0.1;
    this.timer = window.setInterval(() => this.schedule(), 50);
  }

  stop(): void {
    window.clearInterval(this.timer);
  }

  private makeImpulse(seconds: number): AudioBuffer {
    const len = Math.floor(this.ctx.sampleRate * seconds);
    const buf = this.ctx.createBuffer(2, len, this.ctx.sampleRate);
    for (let c = 0; c < 2; c++) {
      const d = buf.getChannelData(c);
      for (let i = 0; i < len; i++) d[i] = (Math.random() * 2 - 1) * Math.pow(1 - i / len, 2.6);
    }
    return buf;
  }

  private schedule(): void {
    const ahead = this.ctx.currentTime + 0.2;
    while (this.nextStep < ahead) {
      this.playStep(this.step, this.nextStep);
      const sixteenth = 60 / this.mood.bpm / 4;
      this.nextStep += sixteenth;
      this.step++;
    }
  }

  private playStep(step: number, t: number): void {
    const m = this.mood;
    const stepInBar = step % 16;
    const bar = Math.floor(step / 16);
    if (stepInBar === 0 && bar % 8 === 0) {
      this.progression = PROGRESSIONS[Math.floor(Math.random() * PROGRESSIONS.length)] as number[][];
    }
    const chord = this.progression[bar % this.progression.length] as number[];
    const barLen = (60 / m.bpm) * 4;
    const drive = m.drums * (0.6 + 0.4 * this.intensity);

    if (stepInBar === 0 && m.pad > 0) this.pad(chord, t, barLen, m.pad);

    // Bass: eighth notes on the chord root with octave pops.
    if (m.bass > 0 && stepInBar % 2 === 0) {
      const root = (chord[0] as number) - 12;
      const pattern = m.tension > 0.5 ? [1, 1, 1, 1, 1, 1, 1, 1] : [1, 0, 1, 1, 0, 1, 1, 0];
      if (pattern[stepInBar / 2]) {
        const octave = stepInBar === 6 || stepInBar === 14 ? 12 : 0;
        this.bass(hz(root + octave), t, 0.22, m.bass * (0.7 + 0.3 * this.intensity));
      }
    }

    if (drive > 0) {
      const kick = m.tension > 0.5 ? stepInBar % 4 === 0 : stepInBar === 0 || stepInBar === 8 || stepInBar === 10;
      if (kick) this.kick(t, drive);
      if (stepInBar === 4 || stepInBar === 12) this.snare(t, drive * 0.8);
      if (stepInBar % 2 === 0 || (this.intensity > 0.6 && m.tension > 0)) this.hat(t, drive * (stepInBar % 4 === 2 ? 0.5 : 0.3));
    }

    // Sparse bell motifs from the scale.
    if (m.bells > 0 && stepInBar % 4 === 0 && Math.random() < m.bells * 0.35) {
      const deg = SCALE[Math.floor(Math.random() * SCALE.length)] as number;
      this.bell(hz(deg + 12 + (Math.random() < 0.3 ? 12 : 0)), t, 0.12 * m.bells);
    }
    // Tension drone pulses for the boss.
    if (m.tension > 0.5 && stepInBar === 0) this.drone(hz(-12 + 1), t, barLen, 0.05 * m.tension);
  }

  private pad(chord: number[], t: number, dur: number, level: number): void {
    const ctx = this.ctx;
    const g = ctx.createGain();
    g.gain.setValueAtTime(0.0001, t);
    g.gain.linearRampToValueAtTime(0.05 * level, t + dur * 0.3);
    g.gain.linearRampToValueAtTime(0.0001, t + dur * 1.05);
    const f = ctx.createBiquadFilter();
    f.type = 'lowpass';
    f.frequency.setValueAtTime(500 + this.intensity * 600, t);
    f.frequency.linearRampToValueAtTime(900 + this.intensity * 900, t + dur * 0.5);
    f.connect(g);
    g.connect(this.dry);
    g.connect(this.wet);
    for (const note of chord) {
      for (const detune of [-8, 7]) {
        const o = ctx.createOscillator();
        o.type = 'sawtooth';
        o.frequency.value = hz(note);
        o.detune.value = detune;
        o.connect(f);
        o.start(t);
        o.stop(t + dur * 1.1);
      }
    }
  }

  private bass(freq: number, t: number, dur: number, level: number): void {
    const ctx = this.ctx;
    const o = ctx.createOscillator();
    o.type = 'sawtooth';
    o.frequency.value = freq;
    const f = ctx.createBiquadFilter();
    f.type = 'lowpass';
    f.frequency.setValueAtTime(900, t);
    f.frequency.exponentialRampToValueAtTime(140, t + dur);
    f.Q.value = 6;
    const g = ctx.createGain();
    g.gain.setValueAtTime(0.0001, t);
    g.gain.exponentialRampToValueAtTime(0.16 * level, t + 0.01);
    g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
    o.connect(f).connect(g).connect(this.dry);
    o.start(t);
    o.stop(t + dur + 0.05);
  }

  private kick(t: number, level: number): void {
    const ctx = this.ctx;
    const o = ctx.createOscillator();
    o.frequency.setValueAtTime(130, t);
    o.frequency.exponentialRampToValueAtTime(38, t + 0.18);
    const g = ctx.createGain();
    g.gain.setValueAtTime(0.0001, t);
    g.gain.exponentialRampToValueAtTime(0.5 * level, t + 0.005);
    g.gain.exponentialRampToValueAtTime(0.0001, t + 0.3);
    o.connect(g).connect(this.dry);
    o.start(t);
    o.stop(t + 0.35);
  }

  private noiseHit(t: number, dur: number, type: BiquadFilterType, freq: number, level: number, wet: boolean): void {
    const ctx = this.ctx;
    const src = ctx.createBufferSource();
    src.buffer = this.noise;
    const f = ctx.createBiquadFilter();
    f.type = type;
    f.frequency.value = freq;
    const g = ctx.createGain();
    g.gain.setValueAtTime(0.0001, t);
    g.gain.exponentialRampToValueAtTime(level, t + 0.003);
    g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
    src.connect(f).connect(g).connect(this.dry);
    if (wet) g.connect(this.wet);
    src.start(t, Math.random());
    src.stop(t + dur + 0.05);
  }

  private snare(t: number, level: number): void {
    this.noiseHit(t, 0.18, 'bandpass', 1800, 0.22 * level, true);
  }

  private hat(t: number, level: number): void {
    this.noiseHit(t, 0.04, 'highpass', 7000, 0.12 * level, false);
  }

  private bell(freq: number, t: number, level: number): void {
    const ctx = this.ctx;
    for (const [mult, amp] of [[1, 1], [2.76, 0.3], [5.4, 0.12]] as const) {
      const o = ctx.createOscillator();
      o.type = 'sine';
      o.frequency.value = freq * mult;
      const g = ctx.createGain();
      g.gain.setValueAtTime(0.0001, t);
      g.gain.exponentialRampToValueAtTime(level * amp, t + 0.005);
      g.gain.exponentialRampToValueAtTime(0.0001, t + 1.6 / mult);
      o.connect(g);
      g.connect(this.wet);
      g.connect(this.dry);
      o.start(t);
      o.stop(t + 1.7);
    }
  }

  private drone(freq: number, t: number, dur: number, level: number): void {
    const ctx = this.ctx;
    const o = ctx.createOscillator();
    o.type = 'square';
    o.frequency.value = freq;
    const f = ctx.createBiquadFilter();
    f.type = 'lowpass';
    f.frequency.value = 300;
    const g = ctx.createGain();
    g.gain.setValueAtTime(0.0001, t);
    g.gain.linearRampToValueAtTime(level, t + dur * 0.5);
    g.gain.linearRampToValueAtTime(0.0001, t + dur);
    o.connect(f).connect(g).connect(this.dry);
    o.start(t);
    o.stop(t + dur + 0.05);
  }
}
